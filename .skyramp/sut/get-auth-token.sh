#!/bin/bash
set -euo pipefail

COMPOSE_FILE=".skyramp/sut/docker-compose.testbot.yml"
GITEA_URL="http://localhost:3000"
USERNAME="testbot"
PASSWORD="testbot123"
EMAIL="testbot@testbot.com"

# Wait for Gitea to be ready (up to 5 minutes)
echo "Waiting for Gitea to be ready..." >&2
for i in $(seq 1 60); do
  if curl -sf "${GITEA_URL}/api/healthz" >/dev/null 2>&1; then
    echo "Gitea is ready." >&2
    break
  fi
  if [ "$i" -eq 60 ]; then
    echo "ERROR: Gitea did not become ready within 5 minutes" >&2
    exit 1
  fi
  sleep 5
done

# Create admin user (idempotent — ignore failures if user already exists)
echo "Creating admin user '${USERNAME}'..." >&2
docker compose -f "${COMPOSE_FILE}" --project-directory . exec -T --user git gitea \
  gitea admin user create \
  --admin \
  --username "${USERNAME}" \
  --email "${EMAIL}" \
  --password "${PASSWORD}" \
  >/dev/null 2>&1 || true

# Mint an API token via REST (token name includes timestamp to avoid collisions on retries)
TOKEN_NAME="testbot-ci-$(date +%s)"
echo "Creating API token '${TOKEN_NAME}'..." >&2
RESPONSE=$(curl -sf -X POST "${GITEA_URL}/api/v1/users/${USERNAME}/tokens" \
  -u "${USERNAME}:${PASSWORD}" \
  -H "Content-Type: application/json" \
  -d "{\"name\":\"${TOKEN_NAME}\",\"scopes\":[\"all\"]}")

TOKEN=$(echo "${RESPONSE}" | jq -r '.sha1')
if [ -z "${TOKEN}" ] || [ "${TOKEN}" = "null" ]; then
  echo "ERROR: Failed to create API token. Response: ${RESPONSE}" >&2
  exit 1
fi

echo "${TOKEN}"
