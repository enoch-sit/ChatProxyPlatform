#!/bin/bash
set -e

# All output goes to a log file for debugging
exec > /var/log/mongodb-setup.log 2>&1

echo "=== MongoDB setup started at $(date) ==="

# Passwords injected by Terraform templatefile
# Using single-quoted bash strings — passwords are alphanumeric, no special chars
MONGO_ADMIN_PASS='${mongo_admin_password}'
AUTH_DB_PASS='${auth_db_password}'
PROXY_DB_PASS='${proxy_db_password}'

# ── Install MongoDB 7.0 (Amazon Linux 2023 / aarch64 / t4g) ──────────

cat > /etc/yum.repos.d/mongodb-org-7.0.repo << 'REPOEOF'
[mongodb-org-7.0]
name=MongoDB Repository
baseurl=https://repo.mongodb.org/yum/amazon/2023/mongodb-org/7.0/aarch64/
gpgcheck=1
enabled=1
gpgkey=https://pgp.mongodb.com/server-7.0.asc
REPOEOF

dnf install -y mongodb-org

systemctl start mongod
systemctl enable mongod

echo "Waiting for mongod to accept connections..."
for attempt in 1 2 3 4 5 6 7 8 9 10; do
  mongosh --quiet --eval "db.runCommand({ ping: 1 })" > /dev/null 2>&1 && break
  echo "Attempt $attempt: not ready yet, sleeping 3s..."
  sleep 3
done

# ── Bootstrap admin user (no-auth mode) ──────────────────────────────

mongosh admin --eval "
  db.createUser({
    user: 'admin',
    pwd: '$MONGO_ADMIN_PASS',
    roles: [ { role: 'root', db: 'admin' } ]
  });
"

echo "Admin user created."

# ── Harden mongod.conf: bind all interfaces + enable auth ────────────

python3 << 'PYEOF'
import re

with open('/etc/mongod.conf', 'r') as f:
    content = f.read()

# Bind to all interfaces (security is enforced by the AWS security group)
content = re.sub(r'bindIp:\s*127\.0\.0\.1', 'bindIp: 0.0.0.0', content)

# Append security block if not already present
if 'authorization:' not in content:
    content += '\nsecurity:\n  authorization: enabled\n'

with open('/etc/mongod.conf', 'w') as f:
    f.write(content)

print("mongod.conf updated.")
PYEOF

systemctl restart mongod
echo "Waiting for mongod to restart with auth enabled..."
sleep 8

# ── Create application users ──────────────────────────────────────────

mongosh admin \
  --username admin \
  --password "$MONGO_ADMIN_PASS" \
  --authenticationDatabase admin \
  --eval "
    db.getSiblingDB('auth_db').createUser({
      user: 'auth_user',
      pwd: '$AUTH_DB_PASS',
      roles: [ { role: 'readWrite', db: 'auth_db' } ]
    });
  "

echo "auth_user created."

mongosh admin \
  --username admin \
  --password "$MONGO_ADMIN_PASS" \
  --authenticationDatabase admin \
  --eval "
    db.getSiblingDB('proxy_db').createUser({
      user: 'proxy_user',
      pwd: '$PROXY_DB_PASS',
      roles: [ { role: 'readWrite', db: 'proxy_db' } ]
    });
  "

echo "proxy_user created."
echo "=== MongoDB setup complete at $(date) ==="
