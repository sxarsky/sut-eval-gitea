#!/bin/bash
set -euo pipefail

COMPOSE_FILE=".skyramp/sut/docker-compose.testbot.yml"
ADMIN_USER="testbot-admin"
ADMIN_PASS="testbot1234"
ADMIN_EMAIL="admin@testbot.com"
API_BASE="http://localhost:3000/api/v1"

# Wait for Gitea API to respond (belt-and-suspenders beyond targetReadyCheckCommand)
echo "Verifying Gitea API is reachable..." >&2
for i in $(seq 1 30); do
    if curl -sf "$API_BASE/version" > /dev/null 2>&1; then
        break
    fi
    if [ "$i" -eq 30 ]; then
        echo "ERROR: Gitea API not reachable after 150s" >&2
        exit 1
    fi
    sleep 5
done

# Create admin user via gitea CLI inside the running container (idempotent)
docker compose -f "$COMPOSE_FILE" --project-directory . exec -T -u git gitea \
    /usr/local/bin/gitea admin user create \
    --username "$ADMIN_USER" \
    --password "$ADMIN_PASS" \
    --email "$ADMIN_EMAIL" \
    --admin \
    --must-change-password=false >/dev/null 2>--must-change-password=false 2>&1 >&21 || echo "Admin user already exists or creation skipped" >&2

# Seed: create 3 test repos under the admin user (best-effort)
for i in 1 2 3; do
    curl -sf -X POST "$API_BASE/user/repos" \
        -H "Content-Type: application/json" \
        -u "$ADMIN_USER:$ADMIN_PASS" \
        -d "{\"name\": \"testbot-repo-${i}\", \"description\": \"Testbot seed repo ${i}\", \"auto_init\": true, \"default_branch\": \"main\"}" \
        > /dev/null 2>&1 || echo "Seed repo ${i} already exists or creation skipped" >&2
done

# Seed: create a test user (best-effort)
curl -sf -X POST "$API_BASE/admin/users" \
    -H "Content-Type: application/json" \
    -u "$ADMIN_USER:$ADMIN_PASS" \
    -d "{\"username\": \"testbot-user\", \"email\": \"user@testbot.com\", \"password\": \"testbot1234\", \"login_name\": \"testbot-user\", \"source_id\": 0, \"send_notify\": false, \"must_change_password\": false}" \
    > /dev/null 2>&1 || echo "Seed user already exists or creation skipped" >&2

# Create API token for testbot-admin
TOKEN_RESPONSE=$(curl -sf -X POST \
    "$API_BASE/users/$ADMIN_USER/tokens" \
    -H "Content-Type: application/json" \
    -u "$ADMIN_USER:$ADMIN_PASS" \
    -d '{"name": "testbot-token", "scopes": ["write:repository", "write:issue", "read:user", "write:user", "read:organization"]}')

echo "$TOKEN_RESPONSE" | jq -j '.sha1'
