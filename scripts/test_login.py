"""Test login and show exact API response."""
import urllib.request
import json

url = "https://aidcec-ai-agent.com/api/v1/chat/authenticate"
credentials = [
    ("admin", "Admin@eduhkaidcec"),
    ("admin", "Admin@2025!"),
    ("admin", "admin@admin"),
    ("admin@aidcec.com", "Admin@2025!"),
    ("admin@aidcec.com", "Admin@eduhkaidcec"),
    ("admin@admin.com", "admin@admin"),
]

for username, password in credentials:
    payload = json.dumps({"username": username, "password": password}).encode()
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    try:
        resp = urllib.request.urlopen(req)
        print(f"  PASS [{username} / {password}]: {resp.read().decode()[:120]}")
    except urllib.error.HTTPError as e:
        print(f"  FAIL [{username} / {password}]: {e.code} {e.read().decode()}")
    except Exception as e2:
        print(f"  ERROR [{username} / {password}]: {e2}")
