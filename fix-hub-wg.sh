set -e
sudo cp /etc/wireguard/wg0.conf /etc/wireguard/wg0.conf.bak.$(date +%s)
echo "=== BEFORE ==="
sudo grep -nE "PublicKey|AllowedIPs|^\[" /etc/wireguard/wg0.conf
sudo python3 - <<'PY'
import re
p = "/etc/wireguard/wg0.conf"
text = open(p).read()
NEW_KEY = "WUy9mL/EJ3dtaG61S4l+YK8yzX9TV0I3PzCGiO2yPGI="
STALE_KEY = "uxk1J7dG3HHL7E/T8CWCE0PZUwObsC7XCGKQK5OsCAg="
TARGET_IP = "10.10.0.3/32"
parts = re.split(r'(?m)^(?=\[)', text)
out = []
for p_ in parts:
    if not p_.strip(): 
        out.append(p_); continue
    if p_.lstrip().startswith("[Peer]"):
        if STALE_KEY in p_:
            print("DROP stale peer block"); continue
        if NEW_KEY in p_:
            if "AllowedIPs" in p_:
                p_ = re.sub(r'(?m)^AllowedIPs\s*=.*$', f'AllowedIPs = {TARGET_IP}', p_)
            else:
                p_ = p_.rstrip() + f'\nAllowedIPs = {TARGET_IP}\n'
            print("FIXED current management peer")
        out.append(p_)
    else:
        out.append(p_)
new = "".join(out)
# Also handle: if NEW_KEY peer doesn't exist yet, append it
if NEW_KEY not in new:
    new += f"\n[Peer]\nPublicKey = {NEW_KEY}\nAllowedIPs = {TARGET_IP}\n"
    print("APPENDED new management peer block")
open(p,"w").write(new)
PY
echo "=== AFTER ==="
sudo grep -nE "PublicKey|AllowedIPs|^\[" /etc/wireguard/wg0.conf
echo "=== RELOAD ==="
sudo wg syncconf wg0 <(sudo wg-quick strip wg0)
echo "=== STATUS ==="
sudo wg show wg0
