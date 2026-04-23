#!/usr/bin/env python3
"""
WireGuard Workstation Setup (Python)
Equivalent of wg-workstation-setup.ps1 — no execution policy required.

Usage (run as Administrator in cmd or PowerShell):
    python wg-workstation-setup.py --hub-endpoint 3.220.226.162:51820 ^
        --hub-public-key cUDvoyHcJs7T3mpfQYA0xJ130/ff4udsNBchH+/l7T0= ^
        --my-ip 10.10.0.3/24

Steps performed:
    1. Check WireGuard is installed (offer winget install if missing)
    2. Generate key pair with wg.exe (or reuse existing)
    3. Write tunnel config to C:\\Program Files\\WireGuard\\Data\\Configurations\\wg-fleet.conf
    4. Install + start OpenSSH server
    5. Add firewall rules (WireGuard UDP 51820, OpenSSH TCP 22)
    6. Activate the WireGuard tunnel service
    7. Print public key + next steps
"""

import argparse
import ctypes
import os
import stat
import subprocess
import sys
import time
from pathlib import Path

# ── Colour helpers ────────────────────────────────────────────────────

RESET  = "\033[0m"
GREEN  = "\033[92m"
YELLOW = "\033[93m"
RED    = "\033[91m"
CYAN   = "\033[96m"
WHITE  = "\033[97m"

def _enable_ansi():
    try:
        ctypes.windll.kernel32.SetConsoleMode(ctypes.windll.kernel32.GetStdHandle(-11), 7)
    except Exception:
        pass

def ok(msg):   print(f"  {GREEN}[OK]  {RESET} {msg}")
def fail(msg): print(f"  {RED}[FAIL]{RESET} {msg}"); sys.exit(1)
def warn(msg): print(f"  {YELLOW}[WARN]{RESET} {msg}")
def info(msg): print(f"  {CYAN}[INFO]{RESET} {msg}")
def step(title): print(f"\n{CYAN}── {title} ──{RESET}")

def run(cmd, input_text=None, check=True, capture=True):
    """Run a command. Returns (stdout, returncode)."""
    r = subprocess.run(
        cmd, input=input_text,
        capture_output=capture,
        text=True,
        shell=isinstance(cmd, str),
    )
    if check and r.returncode != 0:
        stderr = r.stderr.strip() if r.stderr else ""
        fail(f"Command failed ({r.returncode}): {' '.join(cmd) if isinstance(cmd, list) else cmd}\n{stderr}")
    return (r.stdout.strip() if r.stdout is not None else ""), r.returncode

# ── Constants ─────────────────────────────────────────────────────────

WG_EXE    = Path(r"C:\Program Files\WireGuard\wireguard.exe")
WG_TOOL   = Path(r"C:\Program Files\WireGuard\wg.exe")
CONF_DIR  = Path(r"C:\Program Files\WireGuard\Data\Configurations")

# ═══════════════════════════════════════════════════════════════════
# STEP 0: Admin check
# ═══════════════════════════════════════════════════════════════════

def check_admin():
    try:
        is_admin = ctypes.windll.shell32.IsUserAnAdmin() != 0
    except Exception:
        is_admin = False
    if not is_admin:
        fail("Must run as Administrator. Right-click cmd/PowerShell -> 'Run as Administrator'")
    ok("Running as Administrator")

# ═══════════════════════════════════════════════════════════════════
# STEP 1: Check / install WireGuard
# ═══════════════════════════════════════════════════════════════════

def ensure_wireguard():
    step("Step 1: Check WireGuard installation")
    if WG_EXE.exists() and WG_TOOL.exists():
        ok(f"WireGuard already installed at {WG_EXE.parent}")
        return

    warn("WireGuard not found.")
    print(f"  {YELLOW}Installing via winget...{RESET}")
    _, rc = run(
        ["winget", "install", "WireGuard.WireGuard",
         "--accept-package-agreements", "--accept-source-agreements"],
        check=False, capture=False
    )
    if rc != 0:
        fail(
            "winget install failed. Install manually from https://www.wireguard.com/install/ "
            "then re-run this script."
        )
    # winget does not update the current session PATH; check by path directly
    if WG_EXE.exists():
        ok("WireGuard installed")
    else:
        fail(
            "WireGuard install appeared to succeed but exe not found at expected path. "
            "Please install manually then re-run."
        )

# ═══════════════════════════════════════════════════════════════════
# STEP 2: Generate key pair
# ═══════════════════════════════════════════════════════════════════

def generate_keys():
    step("Step 2: Generate WireGuard keys")

    key_dir      = Path(os.environ["USERPROFILE"]) / ".wireguard"
    priv_key_file = key_dir / "private.key"
    pub_key_file  = key_dir / "public.key"

    key_dir.mkdir(parents=True, exist_ok=True)

    if priv_key_file.exists() and pub_key_file.exists():
        info("Existing keys found — reusing")
        priv_key = priv_key_file.read_text().strip()
        pub_key  = pub_key_file.read_text().strip()
        ok(f"Public key: {pub_key}")
        return priv_key, pub_key

    # Generate private key
    priv_key, _ = run([str(WG_TOOL), "genkey"])
    # Derive public key
    pub_key, _  = run([str(WG_TOOL), "pubkey"], input_text=priv_key + "\n")

    priv_key_file.write_text(priv_key)
    pub_key_file.write_text(pub_key)

    # Lock down private key: owner read-only
    try:
        import win32security, win32api, ntsecuritycon as con  # type: ignore
        sd  = win32security.GetFileSecurity(str(priv_key_file), win32security.DACL_SECURITY_INFORMATION)
        dacl = win32security.ACL()
        user, _, _ = win32security.LookupAccountName(None, win32api.GetUserName())
        dacl.AddAccessAllowedAce(win32security.ACL_REVISION, con.FILE_GENERIC_READ | con.FILE_GENERIC_WRITE, user)
        sd.SetSecurityDescriptorDacl(True, dacl, False)
        win32security.SetFileSecurity(str(priv_key_file), win32security.DACL_SECURITY_INFORMATION, sd)
    except ImportError:
        # pywin32 not available — use icacls fallback
        run(["icacls", str(priv_key_file), "/inheritance:r",
             "/grant:r", f"{os.environ.get('USERNAME', 'User')}:(R,W)"], check=False)

    ok(f"Keys generated and saved to {key_dir}")
    ok(f"Public key: {pub_key}")
    return priv_key, pub_key

# ═══════════════════════════════════════════════════════════════════
# STEP 2b: IP conflict check
# ═══════════════════════════════════════════════════════════════════

def check_ip_conflict(my_ip_cidr: str):
    """
    Three-layer conflict check for the VPN IP before writing any config:
      1. Subnet route conflict — does this machine already route 10.10.0.0/24
         via a non-WireGuard adapter? (another VPN, corporate network, etc.)
      2. Local interface collision — does this machine already own the exact
         IP we're about to assign on any adapter?
      3. Live host ping — is anything on the network already responding at
         that IP? (another misconfigured peer, leftover static assignment)
    Aborts on FAIL; prints a warning and continues on soft conflicts.
    """
    step("Step 2b: IP conflict check")

    # Strip CIDR notation to get bare IP
    bare_ip = my_ip_cidr.split("/")[0].strip()
    # Derive the /24 subnet prefix for route-print queries (e.g. "10.10.0")
    octets = bare_ip.rsplit(".", 1)
    subnet_prefix = octets[0]  # e.g. "10.10.0"

    # ── Check 1: existing routes for the subnet ──────────────────────
    out, _ = run(["route", "print", f"{subnet_prefix}.*"], check=False)
    if subnet_prefix in out:
        conflict_lines = [l.strip() for l in out.splitlines()
                          if subnet_prefix in l and l.strip()]
        # Ignore the loopback 127.x lines route print always emits
        conflict_lines = [l for l in conflict_lines if not l.startswith("127.")]
        if conflict_lines:
            warn(f"Existing route(s) for {subnet_prefix}.x found on this machine:")
            for cl in conflict_lines:
                print(f"      {YELLOW}{cl}{RESET}")
            warn("This could mean another VPN or network already uses this subnet.")
            warn("WireGuard will add its own route — overlapping routes may cause")
            warn("routing ambiguity. Proceed only if you understand the conflict.")
            answer = input("  Continue anyway? [y/N] ").strip().lower()
            if answer != "y":
                fail("Aborted by user due to subnet route conflict.")
        else:
            ok(f"No existing {subnet_prefix}.0/24 routes")
    else:
        ok(f"No existing {subnet_prefix}.0/24 routes")

    # ── Check 2: local interface already owns this IP ─────────────────
    ipconfig_out, _ = run(["ipconfig", "/all"], check=False)
    if bare_ip in ipconfig_out:
        fail(
            f"This machine already has {bare_ip} assigned to a local interface.\n"
            f"  Cannot assign the same IP to WireGuard — it would be a duplicate."
        )
    ok(f"No local interface owns {bare_ip}")

    # ── Check 3: ping the target IP (pre-tunnel) ──────────────────────
    # -n 2 pings, -w 800ms each — fast enough not to slow the script much
    _, rc = run(["ping", "-n", "2", "-w", "800", bare_ip], check=False)
    if rc == 0:
        fail(
            f"Something at {bare_ip} is already responding to ping!\n"
            f"  Another host may already be using this VPN IP.\n"
            f"  Check fleet-inventory.json and choose a different IP."
        )
    ok(f"{bare_ip} is not responding to ping -- IP appears available")


# ═══════════════════════════════════════════════════════════════════
# STEP 3: Write tunnel config
# ═══════════════════════════════════════════════════════════════════

def write_tunnel_config(priv_key, hub_public_key, hub_endpoint, my_ip, tunnel_name):
    step("Step 3: Create tunnel configuration")

    CONF_DIR.mkdir(parents=True, exist_ok=True)
    conf_path = CONF_DIR / f"{tunnel_name}.conf"

    config = (
        f"[Interface]\n"
        f"PrivateKey = {priv_key.strip()}\n"
        f"Address = {my_ip}\n"
        f"DNS = 1.1.1.1\n"
        f"\n"
        f"[Peer]\n"
        f"PublicKey = {hub_public_key.strip()}\n"
        f"Endpoint = {hub_endpoint}\n"
        f"AllowedIPs = 10.10.0.0/24\n"
        f"PersistentKeepalive = 25\n"
    )

    conf_path.write_text(config)
    ok(f"Config written to {conf_path}")
    return conf_path

# ═══════════════════════════════════════════════════════════════════
# STEP 4: Install + start OpenSSH
# ═══════════════════════════════════════════════════════════════════

def ensure_openssh():
    step("Step 4: Ensure OpenSSH server is running")

    # Check if installed
    out, rc = run(["sc", "query", "sshd"], check=False)
    if rc != 0:
        info("Installing OpenSSH Server via Windows capability...")
        _, rc2 = run(
            ["powershell", "-ExecutionPolicy", "Bypass", "-NoProfile", "-Command",
             "Add-WindowsCapability -Online -Name OpenSSH.Server~~~~0.0.1.0"],
            check=False, capture=False
        )
        if rc2 != 0:
            warn("Add-WindowsCapability failed — trying dism instead")
            run(["dism", "/Online", "/Add-Capability", "/CapabilityName:OpenSSH.Server~~~~0.0.1.0"],
                check=False, capture=False)

    # Set auto-start
    run(["sc", "config", "sshd", "start=", "auto"], check=False)

    # Start service
    out, rc = run(["sc", "query", "sshd"], check=False)
    if "RUNNING" not in out:
        run(["net", "start", "sshd"], check=False, capture=False)
        time.sleep(2)

    out, _ = run(["sc", "query", "sshd"], check=False)
    if "RUNNING" in out:
        ok("OpenSSH server running")
    else:
        warn("sshd not running after start attempt — check Event Viewer")

# ═══════════════════════════════════════════════════════════════════
# STEP 5: Firewall rules
# ═══════════════════════════════════════════════════════════════════

def ensure_firewall_rules():
    step("Step 5: Firewall rules")

    # WireGuard UDP 51820
    out, _ = run(["netsh", "advfirewall", "firewall", "show", "rule", "name=WireGuard-Fleet-UDP"],
                 check=False)
    if "No rules match" in out or out == "":
        run([
            "netsh", "advfirewall", "firewall", "add", "rule",
            "name=WireGuard-Fleet-UDP", "protocol=UDP", "dir=in",
            "localport=51820", "action=allow"
        ], check=False)
        ok("Added firewall rule: WireGuard UDP 51820 inbound")
    else:
        ok("Firewall rule already exists: WireGuard UDP 51820")

    # OpenSSH TCP 22
    out, _ = run(["netsh", "advfirewall", "firewall", "show", "rule", "name=OpenSSH-Fleet-TCP"],
                 check=False)
    if "No rules match" in out or out == "":
        run([
            "netsh", "advfirewall", "firewall", "add", "rule",
            "name=OpenSSH-Fleet-TCP", "protocol=TCP", "dir=in",
            "localport=22", "action=allow"
        ], check=False)
        ok("Added firewall rule: OpenSSH TCP 22 inbound")
    else:
        ok("Firewall rule already exists: OpenSSH TCP 22")

# ═══════════════════════════════════════════════════════════════════
# STEP 6: Activate WireGuard tunnel
# ═══════════════════════════════════════════════════════════════════

def activate_tunnel(conf_path, tunnel_name):
    step("Step 6: Activate WireGuard tunnel")

    # Check if service already running
    out, rc = run(["sc", "query", f"WireGuardTunnel${tunnel_name}"], check=False)
    if rc == 0 and "RUNNING" in out:
        ok(f"Tunnel service '{tunnel_name}' already running")
        return

    run([str(WG_EXE), "/installtunnelservice", str(conf_path)], check=False, capture=False)
    time.sleep(3)

    out, rc = run(["sc", "query", f"WireGuardTunnel${tunnel_name}"], check=False)
    if "RUNNING" in out:
        ok(f"Tunnel service '{tunnel_name}' started")
    else:
        warn(f"Tunnel service may not be running yet. Check with: sc query WireGuardTunnel${tunnel_name}")
        warn(f"Or open WireGuard GUI and activate '{tunnel_name}' manually")

# ═══════════════════════════════════════════════════════════════════
# STEP 7: Verify VPN connectivity
# ═══════════════════════════════════════════════════════════════════

def verify_vpn():
    step("Step 7: Verify VPN connectivity")
    info("Waiting 5 seconds for tunnel to establish...")
    time.sleep(5)

    _, rc = run(["ping", "-n", "3", "-w", "2000", "10.10.0.1"], check=False)
    if rc == 0:
        ok("VPN hub (10.10.0.1) is reachable -- tunnel is UP")
        return True
    else:
        warn("Cannot ping hub 10.10.0.1 yet.")
        warn("This is normal if the public key has not been registered on the hub yet.")
        warn("Complete the key registration step below, then test with: ping 10.10.0.1")
        return False

# ═══════════════════════════════════════════════════════════════════
# MAIN
# ═══════════════════════════════════════════════════════════════════

def main():
    _enable_ansi()

    parser = argparse.ArgumentParser(description="WireGuard workstation setup")
    parser.add_argument("--hub-endpoint",   required=True,
                        help="Hub IP:port  e.g. 3.220.226.162:51820")
    parser.add_argument("--hub-public-key", required=True,
                        help="Hub WireGuard public key")
    parser.add_argument("--my-ip",          required=True,
                        help="This workstation VPN IP  e.g. 10.10.0.3/24")
    parser.add_argument("--tunnel-name",    default="wg-fleet",
                        help="Tunnel name (default: wg-fleet)")
    parser.add_argument("--skip-activate",  action="store_true",
                        help="Write config but do not activate the tunnel service yet")
    args = parser.parse_args()

    print()
    print(f"{CYAN}======================================={RESET}")
    print(f"{CYAN} WireGuard Workstation Setup (Python){RESET}")
    print(f"{CYAN}======================================={RESET}")

    check_admin()
    ensure_wireguard()
    check_ip_conflict(args.my_ip)
    priv_key, pub_key = generate_keys()
    conf_path = write_tunnel_config(
        priv_key, args.hub_public_key, args.hub_endpoint,
        args.my_ip, args.tunnel_name
    )
    ensure_openssh()
    ensure_firewall_rules()

    if not args.skip_activate:
        activate_tunnel(conf_path, args.tunnel_name)
        verify_vpn()
    else:
        info("--skip-activate set: tunnel not started. Run later:")
        print(f'    "{WG_EXE}" /installtunnelservice "{conf_path}"')

    # ── Summary ──────────────────────────────────────────────────────
    print()
    print(f"{CYAN}{'─' * 47}{RESET}")
    print(f"{CYAN} Setup Complete{RESET}")
    print()
    print(f"  {YELLOW}Your WireGuard public key:{RESET}")
    print(f"  {WHITE}{pub_key}{RESET}")
    print()
    print(f"  {CYAN}Next steps:{RESET}")
    print(f"  1. Send this public key to the fleet manager")
    print(f"     (they will register it on the hub via AWS SSM)")
    print(f"  2. Once registered, test VPN: ping 10.10.0.1")
    print(f"  3. Fleet SSH will then work via: ssh admin@10.10.0.3")
    print()

if __name__ == "__main__":
    main()
