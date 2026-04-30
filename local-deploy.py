#!/usr/bin/env python3
"""
local-deploy.py — Local development deploy for ChatProxy Platform
Brings up all five services on this machine via docker compose.

Usage:
    python local-deploy.py             # Full deploy (create network, write envs, docker compose up -d --build)
    python local-deploy.py --stop      # Stop all services (docker compose down, reverse order)
    python local-deploy.py --status    # Show container states
    python local-deploy.py --no-build  # Skip --build flag on compose up
    python local-deploy.py --reset     # Wipe .env.local + per-service .env files, then re-deploy

Deploy order: auth-service → accounting-service → flowise → flowise-proxy-service-py → bridge
"""

import argparse
import json
import os
import secrets
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

# ── Colour helpers ────────────────────────────────────────────────────────────

RESET  = "\033[0m"
BOLD   = "\033[1m"
GREEN  = "\033[92m"
YELLOW = "\033[93m"
RED    = "\033[91m"
CYAN   = "\033[96m"

def _enable_ansi():
    try:
        import ctypes
        ctypes.windll.kernel32.SetConsoleMode(
            ctypes.windll.kernel32.GetStdHandle(-11), 7)
    except Exception:
        pass

def ok(msg):    print(f"  {GREEN}[OK]  {RESET} {msg}")
def warn(msg):  print(f"  {YELLOW}[WARN]{RESET} {msg}")
def fail(msg):  print(f"  {RED}[FAIL]{RESET} {msg}")
def info(msg):  print(f"  {CYAN}[INFO]{RESET} {msg}")
def step(title): print(f"\n{BOLD}{CYAN}── {title} ──{RESET}")

def die(msg):
    fail(msg)
    sys.exit(1)

# ── Shell helper ──────────────────────────────────────────────────────────────

def run(cmd, check=True, capture=True, cwd=None, env=None):
    """Run a command; return (stdout, returncode)."""
    r = subprocess.run(
        cmd,
        capture_output=capture,
        text=True,
        shell=isinstance(cmd, str),
        cwd=cwd,
        env=env,
    )
    if check and r.returncode != 0:
        stderr = r.stderr.strip() if r.stderr else ""
        stdout = r.stdout.strip() if r.stdout else ""
        combined = stderr or stdout
        die(f"Command failed (rc={r.returncode}): {combined}")
    stdout = r.stdout.strip() if r.stdout is not None else ""
    return stdout, r.returncode

# ── Constants ─────────────────────────────────────────────────────────────────

ROOT = Path(__file__).parent.resolve()

# Maps manifest key → actual directory name (where key ≠ dirname)
SERVICE_DIR_MAP = {
    "flowise-proxy": "flowise-proxy-service-py",
}

# Flowise uses /api/v1/ping for its health endpoint (more reliable than /)
SERVICE_HEALTH_OVERRIDE = {
    "flowise": "/api/v1/ping",
}

# ── Manifest loading ──────────────────────────────────────────────────────────

def load_manifest():
    manifest_path = ROOT / "workstation-manifest.json"
    if not manifest_path.exists():
        die(f"workstation-manifest.json not found at {manifest_path}")
    with open(manifest_path) as f:
        return json.load(f)

# ── Env file helpers ──────────────────────────────────────────────────────────

def write_env(path: Path, values: dict, *, overwrite=False):
    """Write key=value pairs to path. Skip if exists unless overwrite=True."""
    if path.exists() and not overwrite:
        warn(f"  Skipped (already exists): {path.relative_to(ROOT)}")
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    lines = [f"{k}={v}\n" for k, v in values.items()]
    path.write_text("".join(lines), encoding="utf-8")
    ok(f"  Wrote {path.relative_to(ROOT)}")

def load_env_local(path: Path) -> dict:
    """Load key=value pairs from .env.local, returning a dict."""
    result = {}
    if not path.exists():
        return result
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if "=" in line:
            k, _, v = line.partition("=")
            result[k.strip()] = v.strip()
    return result

# ── Shared secrets ────────────────────────────────────────────────────────────

def get_or_create_shared_secrets(env_local: Path, overwrite=False) -> dict:
    """
    Load shared JWT and Mongo secrets from .env.local.
    Generate fresh ones if missing or overwrite=True.
    Returns dict with JWT secrets and the shared Mongo password.
    """
    existing = load_env_local(env_local)

    if (
        not overwrite
        and "JWT_ACCESS_SECRET" in existing
        and "JWT_REFRESH_SECRET" in existing
        and "MONGO_PASSWORD" in existing
    ):
        info("Loaded existing shared secrets from .env.local")
        return {
            "JWT_ACCESS_SECRET": existing["JWT_ACCESS_SECRET"],
            "JWT_REFRESH_SECRET": existing["JWT_REFRESH_SECRET"],
            "MONGO_PASSWORD": existing["MONGO_PASSWORD"],
        }

    jwt_access  = secrets.token_hex(32)
    jwt_refresh = secrets.token_hex(32)
    mongo_password = secrets.token_urlsafe(24)

    write_env(env_local, {
        "# ChatProxy shared secrets — do not commit this file": "",
        "JWT_ACCESS_SECRET":  jwt_access,
        "JWT_REFRESH_SECRET": jwt_refresh,
        "MONGO_PASSWORD": mongo_password,
    }, overwrite=True)
    ok("Generated fresh shared JWT and Mongo secrets → .env.local")
    return {
        "JWT_ACCESS_SECRET":  jwt_access,
        "JWT_REFRESH_SECRET": jwt_refresh,
        "MONGO_PASSWORD": mongo_password,
    }

# ── Per-service .env writers ──────────────────────────────────────────────────

def write_auth_env(svc_dir: Path, shared: dict, overwrite=False):
    write_env(svc_dir / ".env", {
        "PORT": "3000",
        "NODE_ENV": "development",
        # JWT — must match accounting-service and flowise-proxy
        "JWT_ACCESS_SECRET":  shared["JWT_ACCESS_SECRET"],
        "JWT_REFRESH_SECRET": shared["JWT_REFRESH_SECRET"],
        "JWT_ACCESS_EXPIRES_IN":  "1h",
        "JWT_REFRESH_EXPIRES_IN": "7d",
        # MongoDB — service name within auth-service compose network
        # NOTE: auth-service runtime reads MONGO_URI (see auth-service/src/config/db.config.ts).
        # Migration scripts read MONGODB_URI; both are written for compatibility.
        "MONGO_URI":   "mongodb://mongodb-auth:27017/auth_db",
        "MONGODB_URI": "mongodb://mongodb-auth:27017/auth_db",
        # Email — MailHog (dev only)
        "SMTP_HOST":   "mailhog",
        "SMTP_PORT":   "1025",
        "SMTP_SECURE": "false",
        "SMTP_USER":   "",
        "SMTP_PASS":   "",
        "EMAIL_FROM":  "noreply@chatproxy.local",
        # CORS — localhost origins for all services
        "CORS_ORIGIN":       "http://localhost:3082,http://localhost:3002,http://localhost:8000",
        "CORS_CREDENTIALS":  "true",
        # Service URLs (container DNS within chatproxy-network)
        "ACCOUNTING_SERVICE_URL": "http://accounting-service:3001",
        "FRONTEND_URL":           "http://localhost:3082",
    }, overwrite=overwrite)


def write_accounting_env(svc_dir: Path, shared: dict, overwrite=False):
    write_env(svc_dir / ".env", {
        "PORT":     "3001",
        "NODE_ENV": "development",
        # JWT — must match auth-service and flowise-proxy
        "JWT_ACCESS_SECRET":  shared["JWT_ACCESS_SECRET"],
        "JWT_REFRESH_SECRET": shared["JWT_REFRESH_SECRET"],
        # PostgreSQL
        "DB_HOST":     "postgres-accounting",
        "DB_PORT":     "5432",
        "DB_NAME":     "accounting_db",
        "DB_USER":     "postgres",
        "DB_PASSWORD": "postgres",
        # Service URLs
        "AUTH_SERVICE_URL": "http://auth-service:3000",
        "CORS_ORIGIN":      "*",
        "LOG_LEVEL":        "debug",
    }, overwrite=overwrite)


def write_flowise_env(svc_dir: Path, overwrite=False):
    write_env(svc_dir / ".env", {
        # Flowise app
        "PORT": "3002",
        # PostgreSQL (flowise-postgres, host port 5433)
        "DATABASE_TYPE":     "postgres",
        "DATABASE_HOST":     "flowise-postgres",
        "DATABASE_PORT":     "5432",
        "DATABASE_NAME":     "flowise",
        "DATABASE_USER":     "flowiseuser",
        "DATABASE_PASSWORD": "flowisepass",
        "POSTGRES_DB":       "flowise",
        "POSTGRES_USER":     "flowiseuser",
        "POSTGRES_PASSWORD": "flowisepass",
        "POSTGRES_PORT":     "5433",
        # Storage
        "STORAGE_TYPE":      "local",
        # CORS
        "CORS_ORIGINS":      "*",
        "IFRAME_ORIGINS":    "*",
        # Telemetry
        "DISABLE_FLOWISE_TELEMETRY": "true",
        "SHOW_COMMUNITY_NODES":      "true",
        # Leave auth empty for open local access
        "FLOWISE_USERNAME": "",
        "FLOWISE_PASSWORD": "",
    }, overwrite=overwrite)


def write_flowise_proxy_env(svc_dir: Path, shared: dict, overwrite=False):
    mongo_pass = shared["MONGO_PASSWORD"]
    write_env(svc_dir / ".env", {
        # JWT — must match auth-service and accounting-service
        "JWT_SECRET_KEY":    shared["JWT_ACCESS_SECRET"],
        "JWT_ACCESS_SECRET": shared["JWT_ACCESS_SECRET"],
        "JWT_REFRESH_SECRET": shared["JWT_REFRESH_SECRET"],
        "JWT_ALGORITHM": "HS256",
        "JWT_EXPIRATION_HOURS":              "24",
        "JWT_ACCESS_TOKEN_EXPIRE_MINUTES":   "15",
        "JWT_REFRESH_TOKEN_EXPIRE_DAYS":     "7",
        # Flowise backend (container DNS within chatproxy-network)
        "FLOWISE_API_URL": "http://flowise:3002",
        "FLOWISE_API_KEY": "",
        # Auth / Accounting service URLs (container DNS)
        "EXTERNAL_AUTH_URL":      "http://auth-service:3000",
        "ACCOUNTING_SERVICE_URL": "http://accounting-service:3001",
        # MongoDB — container_name mongodb-proxy, host port 27020
        "MONGO_PASSWORD":        mongo_pass,
        "MONGODB_URL":           f"mongodb://admin:{mongo_pass}@mongodb-proxy:27017/flowise_proxy?authSource=admin",
        "MONGODB_DATABASE_NAME": "flowise_proxy",
        # Server
        "DEBUG":     "true",
        "LOG_LEVEL": "DEBUG",
        "HOST":      "0.0.0.0",
        "PORT":      "8000",
        # Collection setup
        "FORCE_COLLECTION_SETUP":       "false",
        "FAIL_ON_COLLECTION_SETUP_ERROR": "false",
        # CORS — explicit origins required because flowise-proxy uses
        # allow_credentials=True; Starlette will not echo Origin if value is "*".
        "CORS_ALLOW_ORIGINS": "http://localhost:3082,http://localhost:3000,http://localhost:3001,http://localhost:3002,http://localhost:8000",
        # Chatflow sync
        "ENABLE_CHATFLOW_SYNC":         "true",
        "CHATFLOW_SYNC_INTERVAL_MINUTES": "60",
    }, overwrite=overwrite)


def write_bridge_env(svc_dir: Path, overwrite=False):
    # Bridge uses FLOWISE_PROXY_URL as a build arg (VITE_ prefix applied in Dockerfile)
    write_env(svc_dir / ".env", {
        "FLOWISE_PROXY_URL": "http://localhost:8000",
    }, overwrite=overwrite)

# ── Docker helpers ────────────────────────────────────────────────────────────

def check_docker():
    step("Step 0 — Docker daemon")
    out, rc = run("docker info", check=False, capture=True)
    if rc != 0:
        die("Docker daemon is not running. Start Docker Desktop and retry.")
    ok("Docker daemon is running")


def ensure_network():
    step("Step 1 — chatproxy-network")
    out, rc = run(
        ["docker", "network", "inspect", "chatproxy-network"],
        check=False, capture=True)
    if rc == 0:
        ok("chatproxy-network already exists")
    else:
        run(["docker", "network", "create", "chatproxy-network"])
        ok("Created chatproxy-network")


def compose_up(svc_dir: Path, compose_file: str, build=True):
    cmd = ["docker", "compose", "-f", compose_file, "up", "-d"]
    if build:
        cmd.append("--build")
    run(cmd, capture=False, cwd=str(svc_dir))


def compose_down(svc_dir: Path, compose_file: str):
    run(
        ["docker", "compose", "-f", compose_file, "down"],
        capture=False, cwd=str(svc_dir), check=False)

# ── Health check ──────────────────────────────────────────────────────────────

def health_check(name: str, port: int, path: str, timeout=120, interval=5):
    url = f"http://localhost:{port}{path}"
    info(f"  Health-checking {name} at {url} (up to {timeout}s) …")
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=3) as resp:
                if resp.status < 500:
                    ok(f"  {name} is healthy (HTTP {resp.status})")
                    return True
        except Exception:
            pass
        time.sleep(interval)
    warn(f"  {name} did not become healthy within {timeout}s — check logs with: docker logs <container>")
    return False

# ── Status ────────────────────────────────────────────────────────────────────

def show_status():
    step("Container Status")
    out, _ = run(
        ["docker", "ps", "-a",
         "--format", "table {{.Names}}\t{{.Status}}\t{{.Ports}}"],
        check=False)
    print(out)

# ── Stop all ──────────────────────────────────────────────────────────────────

def stop_all(manifest):
    step("Stopping all services (reverse order)")
    deploy_order = list(reversed(manifest["deployOrder"]))
    services = manifest["services"]
    for key in deploy_order:
        svc = services[key]
        dirname = SERVICE_DIR_MAP.get(key, key)
        svc_dir = ROOT / dirname
        if not svc_dir.exists():
            warn(f"Directory not found, skipping: {svc_dir.name}")
            continue
        info(f"  Stopping {key} …")
        compose_down(svc_dir, svc["composeFile"])
        ok(f"  {key} stopped")

# ── Main deploy ───────────────────────────────────────────────────────────────

def deploy(manifest, build=True, overwrite_envs=False):
    deploy_order = manifest["deployOrder"]
    services = manifest["services"]
    env_local = ROOT / ".env.local"

    # Step 2 — Shared secrets
    step("Step 2 — Shared JWT secrets")
    shared = get_or_create_shared_secrets(env_local, overwrite=overwrite_envs)

    # Step 3 — Per-service .env files
    step("Step 3 — Per-service .env files")
    writers = {
        "auth-service":       lambda d: write_auth_env(d, shared, overwrite=overwrite_envs),
        "accounting-service": lambda d: write_accounting_env(d, shared, overwrite=overwrite_envs),
        "flowise":            lambda d: write_flowise_env(d, overwrite=overwrite_envs),
        "flowise-proxy":      lambda d: write_flowise_proxy_env(d, shared, overwrite=overwrite_envs),
        "bridge":             lambda d: write_bridge_env(d, overwrite=overwrite_envs),
    }
    for key in deploy_order:
        dirname = SERVICE_DIR_MAP.get(key, key)
        svc_dir = ROOT / dirname
        if key in writers:
            writers[key](svc_dir)

    # Step 4 — docker compose up
    step("Step 4 — docker compose up")
    results = []
    for key in deploy_order:
        svc = services[key]
        dirname = SERVICE_DIR_MAP.get(key, key)
        svc_dir = ROOT / dirname
        if not svc_dir.exists():
            warn(f"Directory not found, skipping: {dirname}")
            results.append((key, "SKIPPED"))
            continue
        info(f"  Deploying {key} …")
        try:
            compose_up(svc_dir, svc["composeFile"], build=build)
            ok(f"  {key} compose up done")
            results.append((key, "UP"))
        except SystemExit:
            warn(f"  {key} compose up failed — continuing with remaining services")
            results.append((key, "FAILED"))

    # Step 5 — Health checks
    step("Step 5 — Health checks")
    health_results = []
    for key in deploy_order:
        svc = services[key]
        dirname = SERVICE_DIR_MAP.get(key, key)
        svc_dir = ROOT / dirname
        if not svc_dir.exists():
            health_results.append((key, "SKIPPED"))
            continue
        health_path = SERVICE_HEALTH_OVERRIDE.get(key, svc["healthPath"])
        healthy = health_check(key, svc["port"], health_path)
        health_results.append((key, "OK" if healthy else "TIMEOUT"))

    # Step 6 — Summary
    step("Step 6 — Summary")
    print(f"\n  {'Service':<30} {'Deploy':<10} {'Health'}")
    print(f"  {'-'*30} {'-'*10} {'-'*10}")
    for (k, deploy_status), (_, health_status) in zip(results, health_results):
        d_color = GREEN if deploy_status == "UP" else (YELLOW if deploy_status == "SKIPPED" else RED)
        h_color = GREEN if health_status == "OK" else (YELLOW if health_status == "SKIPPED" else YELLOW)
        svc = services.get(k, {})
        port = svc.get("port", "?")
        print(f"  {k:<30} {d_color}{deploy_status:<10}{RESET} {h_color}{health_status}{RESET}  (port {port})")

    print(f"\n  {CYAN}Bridge UI:{RESET}         http://localhost:3082")
    print(f"  {CYAN}Flowise:{RESET}            http://localhost:3002")
    print(f"  {CYAN}Flowise Proxy API:{RESET}  http://localhost:8000")
    print(f"  {CYAN}Auth Service:{RESET}       http://localhost:3000")
    print(f"  {CYAN}Accounting Service:{RESET} http://localhost:3001")
    print(f"  {CYAN}MailHog UI:{RESET}         http://localhost:8025")
    print()

# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    _enable_ansi()

    parser = argparse.ArgumentParser(
        description="ChatProxy Platform — local development deploy")
    parser.add_argument("--stop",     action="store_true",
                        help="Stop all services (docker compose down)")
    parser.add_argument("--status",   action="store_true",
                        help="Show container states")
    parser.add_argument("--no-build", action="store_true",
                        help="Skip --build on docker compose up")
    parser.add_argument("--reset",    action="store_true",
                        help="Remove .env.local + per-service .envs, then re-deploy")
    args = parser.parse_args()

    manifest = load_manifest()

    if args.status:
        show_status()
        return

    check_docker()

    if args.stop:
        stop_all(manifest)
        show_status()
        return

    ensure_network()

    if args.reset:
        step("Reset — removing .env.local and per-service .env files")
        env_local = ROOT / ".env.local"
        if env_local.exists():
            env_local.unlink()
            ok("Removed .env.local")
        for key in manifest["deployOrder"]:
            dirname = SERVICE_DIR_MAP.get(key, key)
            env_path = ROOT / dirname / ".env"
            if env_path.exists():
                env_path.unlink()
                ok(f"Removed {dirname}/.env")

    deploy(manifest, build=not args.no_build, overwrite_envs=args.reset)


if __name__ == "__main__":
    main()
