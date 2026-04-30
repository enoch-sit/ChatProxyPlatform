#!/usr/bin/env python3
"""
probe-docker.py  —  Quick Docker state probe (pure stdlib, no installs needed)

Run directly on any fleet workstation:
    python probe-docker.py

Checks:
  - Docker daemon is running
  - Each container: name, status, uptime, ports
  - Any containers that have exited/restarted unexpectedly
  - Image list
"""

import subprocess
import sys
import ctypes
import socket
import datetime

# ── Colour helpers ────────────────────────────────────────────────────
RESET  = "\033[0m"
GREEN  = "\033[92m"
YELLOW = "\033[93m"
RED    = "\033[91m"
CYAN   = "\033[96m"

def _enable_ansi():
    try:
        ctypes.windll.kernel32.SetConsoleMode(
            ctypes.windll.kernel32.GetStdHandle(-11), 7)
    except Exception:
        pass

def run(cmd, check=False):
    r = subprocess.run(cmd, capture_output=True, text=True, shell=isinstance(cmd, str))
    return r.stdout.strip(), r.stderr.strip(), r.returncode

def ok(msg):   print(f"  {GREEN}[OK]  {RESET} {msg}")
def warn(msg): print(f"  {YELLOW}[WARN]{RESET} {msg}")
def fail(msg): print(f"  {RED}[FAIL]{RESET} {msg}")
def info(msg): print(f"  {CYAN}[INFO]{RESET} {msg}")
def section(title):
    print(f"\n{CYAN}── {title} {'─' * max(0, 44 - len(title))}{RESET}")

# ═══════════════════════════════════════════════════════════════════

def main():
    _enable_ansi()
    host = socket.gethostname()
    now  = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    print()
    print(f"{CYAN}{'=' * 50}{RESET}")
    print(f"{CYAN}  Docker Probe   {host}   {now}{RESET}")
    print(f"{CYAN}{'=' * 50}{RESET}")

    # ── 1. Docker daemon ─────────────────────────────────────────────
    section("Docker daemon")
    out, err, rc = run(["docker", "version", "--format", "{{.Server.Version}}"])
    if rc != 0:
        fail(f"Docker daemon not reachable: {err or 'docker not found'}")
        sys.exit(1)
    ok(f"Docker daemon v{out}")

    # ── 2. All containers ────────────────────────────────────────────
    section("Containers (all)")
    fmt = "{{.Names}}\t{{.Status}}\t{{.Image}}\t{{.Ports}}"
    out, err, rc = run(["docker", "ps", "-a", f"--format={fmt}"])
    if rc != 0:
        fail(f"docker ps failed: {err}")
        sys.exit(1)

    if not out:
        warn("No containers found (none created yet)")
    else:
        rows = [line.split("\t") for line in out.splitlines()]
        # Pad columns for alignment
        col_w = [max(len(r[i]) if i < len(r) else 0 for r in rows) for i in range(4)]
        header = (
            f"  {'NAME':<{col_w[0]}}  {'STATUS':<{col_w[1]}}  "
            f"{'IMAGE':<{col_w[2]}}  PORTS"
        )
        print(f"{CYAN}{header}{RESET}")
        print(f"  {'─' * (sum(col_w) + 10)}")

        unhealthy = []
        for r in rows:
            name   = r[0] if len(r) > 0 else "?"
            status = r[1] if len(r) > 1 else "?"
            image  = r[2] if len(r) > 2 else "?"
            ports  = r[3] if len(r) > 3 else ""

            is_up      = status.lower().startswith("up")
            is_exited  = "exited" in status.lower()
            is_restart = "restarting" in status.lower()
            color = GREEN if is_up else (RED if is_exited or is_restart else YELLOW)

            print(f"  {name:<{col_w[0]}}  {color}{status:<{col_w[1]}}{RESET}  "
                  f"{image:<{col_w[2]}}  {ports}")

            if not is_up:
                unhealthy.append((name, status))

    # ── 3. Running container count ───────────────────────────────────
    section("Summary")
    out_run, _, _ = run(["docker", "ps", "-q"])
    out_all, _, _ = run(["docker", "ps", "-a", "-q"])
    running = len([x for x in out_run.splitlines() if x]) if out_run else 0
    total   = len([x for x in out_all.splitlines() if x]) if out_all else 0
    stopped = total - running

    if running == total and total > 0:
        ok(f"{running}/{total} containers running")
    elif total == 0:
        warn("0 containers — services not deployed yet")
    else:
        warn(f"{running}/{total} running, {stopped} stopped/exited")
        for name, status in unhealthy:
            fail(f"  {name}: {status}")

    # ── 4. Docker disk usage ─────────────────────────────────────────
    section("Disk usage")
    out, _, rc = run(["docker", "system", "df"])
    if rc == 0:
        for line in out.splitlines():
            print(f"  {line}")
    else:
        warn("docker system df unavailable")

    # ── 5. SSH / sshd check (bonus) ──────────────────────────────────
    section("OpenSSH daemon (fleet SSH prerequisite)")
    out, _, rc = run(["sc", "query", "sshd"])
    if rc != 0:
        fail("sshd service not found — run wg-workstation-setup.py first")
    elif "RUNNING" in out:
        ok("sshd is RUNNING")
    else:
        # Extract state line
        state = next((l.strip() for l in out.splitlines() if "STATE" in l), out)
        warn(f"sshd not running: {state}")
        info("To start: net start sshd   (as Administrator)")

    print()

if __name__ == "__main__":
    main()
