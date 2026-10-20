#!/usr/bin/env bash
# Boot the image against PG_DATABASE_URL (no migrations) and run the login + search smoke test.
#   smoke.sh <image>
set -euo pipefail
IMAGE=$1
: "${PG_DATABASE_URL:?}"
docker rm -f twenty-smoke >/dev/null 2>&1 || true
docker run -d --name twenty-smoke --network host \
  -e PG_DATABASE_URL -e REDIS_URL="${REDIS_URL:-redis://localhost:6379}" \
  -e APP_SECRET="${APP_SECRET:-$(openssl rand -hex 32)}" -e SERVER_URL=http://localhost:3000 \
  -e DISABLE_DB_MIGRATIONS=true -e DISABLE_CRON_JOBS_REGISTRATION=true "$IMAGE" >/dev/null
trap 'docker logs --tail 200 twenty-smoke > smoke-server.log 2>&1 || true; docker rm -f twenty-smoke >/dev/null' EXIT
for _ in $(seq 1 90); do curl -fs http://localhost:3000/healthz >/dev/null && break; sleep 2; done
curl -fs http://localhost:3000/healthz >/dev/null || { docker logs --tail 100 twenty-smoke; exit 1; }
python3 "$(dirname "$0")/smoke.py"
