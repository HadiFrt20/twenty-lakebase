#!/usr/bin/env bash
# Run Twenty's setup + upgrade from a built image against PG_DATABASE_URL.
# Unlike the image entrypoint, a failed upgrade fails the job instead of logging a warning.
#   migrate.sh <image>      (needs PG_DATABASE_URL; REDIS_URL defaults to localhost)
set -euo pipefail
IMAGE=$1
: "${PG_DATABASE_URL:?}"
docker run --rm --network host \
  -e PG_DATABASE_URL -e REDIS_URL="${REDIS_URL:-redis://localhost:6379}" \
  -e APP_SECRET="${APP_SECRET:-$(openssl rand -hex 32)}" -e SERVER_URL=http://localhost:3000 \
  --entrypoint sh "$IMAGE" -ec '
    has_core=$(psql -tAc "SELECT EXISTS (SELECT 1 FROM information_schema.schemata WHERE schema_name = '"'core'"')" "$PG_DATABASE_URL")
    if [ "$has_core" = "f" ]; then yarn database:init:prod; fi
    yarn command:prod cache:flush
    time yarn command:prod upgrade
    yarn command:prod cache:flush'
