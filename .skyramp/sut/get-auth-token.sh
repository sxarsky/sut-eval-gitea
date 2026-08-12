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
    --must-change-password=false >/dev/null 2>&1 || echo "Admin user already exists or creation skipped" >&2

# Seed: create 3 test repos under the admin user (best-effort)
for i in 1 2 3; do
    curl -sf -X POST "$API_BASE/user/repos" \
        -H "Content-Type: application/json" \
        -u "$ADMIN_USER:$ADMIN_PASS" \
        -d "{\"name\": \"testbot-repo-${i}\", \"description\": \"Testbot seed repo ${i}\", \"auto_init\": true, \"default_branch\": \"main\"}" \
        > /dev/null 2>&1 || echo "Seed repo ${i} already exists or creation skipped" >&2
done

# Seed: populate testbot-repo-1 with a realistic backlog of open issues so the
# issue summary has data to report. DB-level insert (SQLite CLI is in the image),
# bypassing the API so it reflects real repository activity at scale.
DBFILE=$(docker compose -f "$COMPOSE_FILE" --project-directory . exec -T gitea \
    sh -c 'find /data -name "gitea.db" 2>/dev/null | head -1' | tr -d '\r' || true)
if [ -n "${DBFILE:-}" ]; then
    docker compose -f "$COMPOSE_FILE" --project-directory . exec -T gitea \
        sqlite3 "$DBFILE" "
        PRAGMA busy_timeout=10000;
        INSERT INTO issue (repo_id, \"index\", poster_id, name, content, content_version, is_closed, is_pull, created_unix, updated_unix)
        WITH RECURSIVE seq(n) AS (SELECT 1 UNION ALL SELECT n+1 FROM seq WHERE n < 40)
        SELECT r.id, n, u.id, 'Seed issue ' || n, '', 0, 0, 0, strftime('%s','now'), strftime('%s','now')
        FROM seq,
             (SELECT id FROM repository WHERE lower_name='testbot-repo-1' LIMIT 1) r,
             (SELECT id FROM \"user\" WHERE lower_name='testbot-admin' LIMIT 1) u;
        " >/dev/null 2>&1 || echo "Issue backlog seed skipped" >&2
else
    echo "Issue backlog seed skipped (db file not found)" >&2
fi

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

# jq -j (not -r): emit the raw token with NO trailing newline, else it lands in
# the bearer Authorization header and gitea/Go rejects the malformed value.
echo "$TOKEN_RESPONSE" | jq -j '.sha1'
