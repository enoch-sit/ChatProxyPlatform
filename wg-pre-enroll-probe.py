#!/usr/bin/env python3
"""
WireGuard Pre-Enrollment Probe
Run on the target workstation BEFORE wg-workstation-setup.ps1

Usage:
    python wg-pre-enroll-probe.py
    python wg-pre-enroll-probe.py --expected-vpn-ip 10.10.0.3
    python wg-pre-enroll-probe.py --json
"""

import argparse
import ctypes
import json
import os
import platform
import shutil
import socket
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

# ── Colour helpers (work on Windows 10 1607+) ────────────────────────

RESET  = "\033[0m"
GREEN  = "\033[92m"
YELLOW = "\033[93m"
RED    = "\033[91m"
CYAN   = "\033[96m"
WHITE  = "\033[97m"
GRAY   = "\033[90m"

def _enable_ansi():
    """Enable ANSI escape codes on Windows console."""
    if sys.platform == "win32":
        try:
            import ctypes
            kernel32 = ctypes.windll.kernel32
            kernel32.SetConsoleMode(kernel32.GetStdHandle(-11), 7)
        except Exception:
            pass

# ── Result tracking ───────────────────────────────────────────────────

results = []

def check(category, name, status, detail="", json_mode=False):
    results.append({"category": category, "check": name, "status": status, "detail": detail})
    if json_mode:
        return
    color = {"PASS": GREEN, "WARN": YELLOW, "FAIL": RED, "INFO": CYAN}.get(status, WHITE)
    label = f"[{status:<4}]"
    line  = f"  {color}{label}{RESET}  {category:<20} {name}"
    if detail:
        line += f"  -- {detail}"
    print(line)

def section(title, json_mode):
    if not json_mode:
        print(f"\n{WHITE}── {title} {'─' * max(0, 46 - len(title))}{RESET}")

def run(cmd, timeout=10):
    """Run a shell command, return (stdout, stderr, returncode)."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout,
                           shell=isinstance(cmd, str))
        return r.stdout.strip(), r.stderr.strip(), r.returncode
    except subprocess.TimeoutExpired:
        return "", "timeout", 1
    except Exception as e:
        return "", str(e), 1

# ═══════════════════════════════════════════════════════════════════
# 1. SYSTEM
# ═══════════════════════════════════════════════════════════════════

def check_system(json_mode, expected_vpn_ip):
    section("SYSTEM", json_mode)

    # Admin
    try:
        is_admin = ctypes.windll.shell32.IsUserAnAdmin() != 0
    except Exception:
        is_admin = False
    if is_admin:
        check("System", "Admin privileges", "PASS", "Running as administrator", json_mode)
    else:
        check("System", "Admin privileges", "FAIL",
              "Must run as Administrator for WireGuard install. Right-click PowerShell -> Run as Administrator", json_mode)

    # OS
    ver  = platform.version()          # e.g. "10.0.19041"
    name = platform.win32_ver()[0]     # e.g. "10"
    arch = platform.machine()
    try:
        build = int(ver.split(".")[-1])
    except Exception:
        build = 0
    caption = f"Windows {name} Build {build} ({arch})"
    if build >= 17763:
        check("System", "OS version", "PASS", caption, json_mode)
    elif build >= 14393:
        check("System", "OS version", "WARN", caption + " -- WireGuard kernel driver requires Build 17763+", json_mode)
    else:
        check("System", "OS version", "FAIL", caption + " -- too old for WireGuard", json_mode)

    # Disk space
    try:
        import shutil as _sh
        total, used, free = _sh.disk_usage("C:\\")
        free_gb = round(free / 1e9, 1)
        if free_gb >= 2:
            check("System", "Disk space (C:\\)", "PASS", f"{free_gb} GB free", json_mode)
        elif free_gb >= 0.5:
            check("System", "Disk space (C:\\)", "WARN", f"{free_gb} GB free (low)", json_mode)
        else:
            check("System", "Disk space (C:\\)", "FAIL", f"{free_gb} GB free -- insufficient", json_mode)
    except Exception as e:
        check("System", "Disk space (C:\\)", "WARN", str(e), json_mode)

    # Python version
    py = sys.version.split()[0]
    if sys.version_info >= (3, 8):
        check("System", "Python version", "PASS", f"v{py}", json_mode)
    else:
        check("System", "Python version", "WARN", f"v{py} -- 3.8+ recommended", json_mode)

# ═══════════════════════════════════════════════════════════════════
# 2. WIREGUARD STATE
# ═══════════════════════════════════════════════════════════════════

def check_wireguard(json_mode):
    section("WIREGUARD", json_mode)

    wg_exe   = Path(r"C:\Program Files\WireGuard\wireguard.exe")
    wg_tool  = Path(r"C:\Program Files\WireGuard\wg.exe")
    conf_dir = Path(r"C:\Program Files\WireGuard\Data\Configurations")
    conf_file = conf_dir / "wg-fleet.conf"
    key_dir  = Path(os.environ.get("USERPROFILE", "C:\\Users\\admin")) / ".wireguard"
    priv_key = key_dir / "private.key"
    pub_key  = key_dir / "public.key"

    # Binary
    if wg_exe.exists():
        out, _, rc = run([str(wg_exe), "/version"])
        check("WireGuard", "Binary installed", "PASS", out or "found", json_mode)
    else:
        check("WireGuard", "Binary installed", "WARN",
              "Not found -- will be installed by wg-workstation-setup.ps1", json_mode)

    # wg.exe tool
    if wg_tool.exists():
        check("WireGuard", "wg.exe tool", "PASS", "Found", json_mode)
    else:
        check("WireGuard", "wg.exe tool", "WARN", "Not found -- part of WireGuard install package", json_mode)

    # Tunnel config
    if conf_file.exists():
        content = conf_file.read_text(errors="replace")
        if "[Peer]" in content and "PrivateKey" in content and "Address" in content:
            check("WireGuard", "Tunnel config", "WARN",
                  "wg-fleet.conf already exists and will be overwritten", json_mode)
            import re
            m = re.search(r"Address\s*=\s*(\S+)", content)
            if m:
                check("WireGuard", "Existing tunnel IP", "INFO", m.group(1), json_mode)
        else:
            check("WireGuard", "Tunnel config", "WARN", "wg-fleet.conf exists but is incomplete", json_mode)
    else:
        check("WireGuard", "Tunnel config", "PASS", "Not present -- clean slate", json_mode)

    # Tunnel service
    out, _, rc = run(["sc", "query", "WireGuardTunnel$wg-fleet"])
    if rc == 0:
        if "RUNNING" in out:
            check("WireGuard", "Tunnel service", "WARN",
                  "wg-fleet tunnel ALREADY RUNNING -- VPN may already be active", json_mode)
        else:
            check("WireGuard", "Tunnel service", "INFO", "Service exists but not running", json_mode)
    else:
        check("WireGuard", "Tunnel service", "PASS", "Not installed -- ready for enrollment", json_mode)

    # Key pair
    if priv_key.exists():
        check("WireGuard", "Existing key pair", "WARN",
              f"Keys found at {key_dir} -- will be reused (not regenerated)", json_mode)
        if pub_key.exists():
            existing_pub = pub_key.read_text().strip()
            check("WireGuard", "Existing public key", "INFO", existing_pub, json_mode)
    else:
        check("WireGuard", "Existing key pair", "PASS", "No prior keys -- fresh pair will be generated", json_mode)

# ═══════════════════════════════════════════════════════════════════
# 3. NETWORK INTERFACES
# ═══════════════════════════════════════════════════════════════════

def check_interfaces(json_mode, expected_vpn_ip):
    section("NETWORK (INTERFACES)", json_mode)

    # Use ipconfig to get adapters
    out, _, rc = run(["ipconfig"])
    if rc == 0:
        # Parse adapter blocks
        adapters_found = 0
        current = None
        for line in out.splitlines():
            if "adapter" in line.lower() and ":" in line:
                current = line.split(":")[0].strip()
            if current and "IPv4 Address" in line:
                ip = line.split(":")[-1].strip().rstrip("(Preferred)")
                adapters_found += 1
                if not ip.startswith("127.") and not ip.startswith("169.254."):
                    check("Network", f"Interface", "INFO", f"{current}: {ip}", json_mode)
        if adapters_found == 0:
            check("Network", "Active interfaces", "FAIL", "No IPv4 interfaces found", json_mode)
    else:
        check("Network", "Active interfaces", "WARN", "ipconfig failed", json_mode)

    # Check for conflicting 10.10.0.x routes via route print
    out, _, _ = run(["route", "print", "10.10.0.*"])
    if "10.10.0." in out:
        # Look for existing routes not attributed to WireGuard
        conflict_lines = [l for l in out.splitlines() if "10.10.0." in l]
        for cl in conflict_lines[:3]:
            check("Network", "Existing 10.10.0.x route", "WARN",
                  cl.strip() + " (check if from a prior VPN)", json_mode)
    else:
        check("Network", "VPN route conflicts", "PASS", "No existing 10.10.0.x routes", json_mode)

    # Expected IP conflict
    if expected_vpn_ip:
        out, _, _ = run(["ipconfig"])
        if expected_vpn_ip in out:
            check("Network", f"IP conflict {expected_vpn_ip}", "WARN",
                  f"{expected_vpn_ip} already assigned on this machine", json_mode)
        else:
            check("Network", f"IP conflict {expected_vpn_ip}", "PASS", "Not in use", json_mode)

# ═══════════════════════════════════════════════════════════════════
# 4. CONNECTIVITY
# ═══════════════════════════════════════════════════════════════════

def check_connectivity(json_mode, hub_ip, hub_port):
    section("NETWORK (CONNECTIVITY)", json_mode)

    # DNS
    try:
        addr = socket.gethostbyname("google.com")
        check("Connectivity", "DNS resolution", "PASS", f"google.com -> {addr}", json_mode)
    except Exception as e:
        check("Connectivity", "DNS resolution", "FAIL", str(e), json_mode)

    # HTTPS internet
    for label, url in [("HTTPS internet", "https://www.google.com"), ("HTTPS GitHub", "https://github.com")]:
        try:
            req = urllib.request.urlopen(url, timeout=8)
            check("Connectivity", label, "PASS", f"HTTP {req.status}", json_mode)
        except urllib.error.HTTPError as e:
            check("Connectivity", label, "PASS", f"HTTP {e.code} (reachable)", json_mode)
        except Exception as e:
            lvl = "FAIL" if "internet" in label else "WARN"
            check("Connectivity", label, lvl, str(e)[:80], json_mode)

    # ICMP to hub
    out, _, rc = run(["ping", "-n", "1", "-w", "2000", hub_ip])
    if rc == 0:
        check("Connectivity", f"Hub ICMP {hub_ip}", "PASS", "Hub IP is pingable", json_mode)
    else:
        check("Connectivity", f"Hub ICMP {hub_ip}", "WARN",
              "ICMP blocked -- UDP/51820 reachability unconfirmed until tunnel up", json_mode)

    # TCP to hub port 443 (routing sanity)
    try:
        s = socket.create_connection((hub_ip, 443), timeout=5)
        s.close()
        check("Connectivity", f"Hub TCP {hub_ip}:443", "INFO", "TCP reachable (routing OK)", json_mode)
    except Exception:
        check("Connectivity", f"Hub TCP {hub_ip}:443", "INFO",
              "TCP :443 closed/filtered (expected on EC2) -- routing may still be fine", json_mode)

# ═══════════════════════════════════════════════════════════════════
# 5. FIREWALL
# ═══════════════════════════════════════════════════════════════════

def check_firewall(json_mode):
    section("FIREWALL", json_mode)

    # Check each profile state via netsh
    out, _, rc = run(["netsh", "advfirewall", "show", "allprofiles", "state"])
    if rc == 0:
        for line in out.splitlines():
            line = line.strip()
            if "State" in line:
                check("Firewall", "Profile state", "INFO", line, json_mode)
    else:
        check("Firewall", "Profile state", "WARN", "Could not query firewall profiles", json_mode)

    # WireGuard rule
    out, _, _ = run(["netsh", "advfirewall", "firewall", "show", "rule", "name=all"])
    wg_rule  = any("wireguard" in l.lower() for l in out.splitlines())
    ssh_rule = any("openssh" in l.lower() or ("ssh" in l.lower() and "rule" not in l.lower()) for l in out.splitlines())

    if wg_rule:
        check("Firewall", "WireGuard rule", "PASS", "WireGuard firewall rule found", json_mode)
    else:
        check("Firewall", "WireGuard rule", "WARN",
              "No WireGuard rule -- may need: netsh advfirewall firewall add rule name=WireGuard "
              "protocol=UDP dir=in localport=51820 action=allow", json_mode)

    if ssh_rule:
        check("Firewall", "OpenSSH rule", "PASS", "SSH/OpenSSH firewall rule found", json_mode)
    else:
        check("Firewall", "OpenSSH rule", "WARN",
              "No SSH rule -- fleet SSH may be blocked after VPN enrollment", json_mode)

# ═══════════════════════════════════════════════════════════════════
# 6. OPENSSH
# ═══════════════════════════════════════════════════════════════════

def check_openssh(json_mode):
    section("OPENSSH", json_mode)

    out, _, rc = run(["sc", "query", "sshd"])
    if rc != 0:
        check("OpenSSH", "sshd service", "WARN",
              "Not installed -- wg-workstation-setup.ps1 will install it", json_mode)
        return

    running = "RUNNING" in out
    if running:
        check("OpenSSH", "sshd service", "PASS", "Running", json_mode)
    else:
        check("OpenSSH", "sshd service", "WARN", "Installed but not running -- fleet SSH will fail", json_mode)

    # Start type
    out2, _, _ = run(["sc", "qc", "sshd"])
    if "AUTO_START" in out2:
        check("OpenSSH", "sshd auto-start", "PASS", "Automatic", json_mode)
    else:
        check("OpenSSH", "sshd auto-start", "WARN",
              "Not set to AUTO_START -- run: sc config sshd start=auto", json_mode)

    # authorized_keys
    userprofile = os.environ.get("USERPROFILE", "")
    paths = [
        Path(userprofile) / ".ssh" / "authorized_keys",
        Path(r"C:\ProgramData\ssh\administrators_authorized_keys"),
    ]
    found_ak = False
    for p in paths:
        if p.exists():
            lines = len(p.read_text(errors="replace").splitlines())
            check("OpenSSH", "authorized_keys", "INFO", f"{p} ({lines} keys)", json_mode)
            found_ak = True
    if not found_ak:
        check("OpenSSH", "authorized_keys", "WARN",
              "No authorized_keys found -- fleet SSH key must be added before enrollment", json_mode)

# ═══════════════════════════════════════════════════════════════════
# 7. REQUIRED TOOLS
# ═══════════════════════════════════════════════════════════════════

def check_tools(json_mode):
    section("REQUIRED TOOLS", json_mode)

    tools = [
        ("git",    True,  "pull repo updates"),
        ("winget", False, "install WireGuard if missing"),
        ("aws",    False, "SSM hub commands (not needed on workstation itself)"),
        ("docker", False, "running platform services"),
    ]
    for name, required, purpose in tools:
        path = shutil.which(name)
        if path:
            out, _, _ = run([name, "--version"])
            ver = out.split("\n")[0][:60] if out else "found"
            check("Tools", name, "PASS", ver, json_mode)
        else:
            lvl = "FAIL" if required else "WARN"
            check("Tools", name, lvl, f"Not found -- needed to {purpose}", json_mode)

# ═══════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════

def main():
    _enable_ansi()

    parser = argparse.ArgumentParser(description="WireGuard pre-enrollment probe")
    parser.add_argument("--hub-endpoint",    default="3.220.226.162:51820")
    parser.add_argument("--expected-vpn-ip", default="")
    parser.add_argument("--json",            action="store_true", help="Machine-readable JSON output")
    args = parser.parse_args()

    json_mode = args.json
    hub_parts = args.hub_endpoint.split(":")
    hub_ip    = hub_parts[0]
    hub_port  = int(hub_parts[1]) if len(hub_parts) > 1 else 51820

    if not json_mode:
        import datetime
        print()
        print(f"{CYAN}=============================================={RESET}")
        print(f"{CYAN}  WireGuard Pre-Enrollment Probe (Python){RESET}")
        print(f"{CYAN}  Host: {socket.gethostname()}   {datetime.datetime.now():%Y-%m-%d %H:%M:%S}{RESET}")
        print(f"{CYAN}=============================================={RESET}")

    check_system(json_mode, args.expected_vpn_ip)
    check_wireguard(json_mode)
    check_interfaces(json_mode, args.expected_vpn_ip)
    check_connectivity(json_mode, hub_ip, hub_port)
    check_firewall(json_mode)
    check_openssh(json_mode)
    check_tools(json_mode)

    # Summary
    passes = sum(1 for r in results if r["status"] == "PASS")
    warns  = sum(1 for r in results if r["status"] == "WARN")
    fails  = sum(1 for r in results if r["status"] == "FAIL")
    infos  = sum(1 for r in results if r["status"] == "INFO")
    overall = "FAIL" if fails > 0 else ("WARN" if warns > 0 else "PASS")

    if json_mode:
        print(json.dumps({
            "host":      socket.gethostname(),
            "overall":   overall,
            "summary":   {"pass": passes, "warn": warns, "fail": fails, "info": infos},
            "checks":    results,
        }, indent=2))
        return

    print()
    print(f"{WHITE}{'═' * 47}{RESET}")
    print(f"{WHITE} SUMMARY{RESET}")
    color = {"PASS": GREEN, "WARN": YELLOW, "FAIL": RED}[overall]
    print(f"  {color}Overall: {overall}   PASS:{passes}  WARN:{warns}  FAIL:{fails}  INFO:{infos}{RESET}")

    if fails:
        print(f"\n  {RED}BLOCKERS (must fix before enrollment):{RESET}")
        for r in results:
            if r["status"] == "FAIL":
                print(f"  {RED}  [{r['category']}] {r['check']}: {r['detail']}{RESET}")

    if warns:
        print(f"\n  {YELLOW}WARNINGS (review before enrolling):{RESET}")
        for r in results:
            if r["status"] == "WARN":
                print(f"  {YELLOW}  [{r['category']}] {r['check']}: {r['detail']}{RESET}")

    print()
    verdict = {
        "PASS": f"{GREEN}  Machine is READY for WireGuard enrollment.{RESET}",
        "WARN": f"{YELLOW}  Machine can proceed but review warnings above.{RESET}",
        "FAIL": f"{RED}  Enrollment BLOCKED -- resolve FAIL items first.{RESET}",
    }
    print(verdict[overall])
    print(f"{WHITE}{'═' * 47}{RESET}")
    print()

    sys.exit(1 if fails > 0 else 0)

if __name__ == "__main__":
    main()
