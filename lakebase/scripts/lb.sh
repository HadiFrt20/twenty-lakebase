#!/usr/bin/env bash
# Thin wrapper over `databricks postgres` for the Lakebase branch lifecycle.
# Same commands run locally (profile auth) and in CI (DATABRICKS_HOST/CLIENT_ID/CLIENT_SECRET).
#
#   lb.sh create <branch> <source-branch> <ttl|never>   create (or recreate) a branch, print host
#   lb.sh host <branch>                                 print the primary endpoint host
#   lb.sh token <branch>                                OAuth DB credential for the caller (1h)
#   lb.sh disable <branch>                              stop the endpoint (frees the per-project compute cap)
#   lb.sh delete <branch>                               delete the branch (no-op if missing)
#   lb.sh url <branch> <user> <password> [db]           print a PG_DATABASE_URL
set -euo pipefail

PROJECT="${LAKEBASE_PROJECT:-twenty-lakebase-0}"
P="projects/${PROJECT}"
PROFILE_ARGS=()
[[ -n "${DATABRICKS_CONFIG_PROFILE:-}" ]] && PROFILE_ARGS=(-p "$DATABRICKS_CONFIG_PROFILE")

dbx() { databricks "$@" ${PROFILE_ARGS[@]+"${PROFILE_ARGS[@]}"} -o json; }
ep() { echo "${P}/branches/$1/endpoints/primary"; }
exists() { dbx postgres get-branch "${P}/branches/$1" >/dev/null 2>&1; }

host() {
  # A fresh branch's endpoint can take a few seconds to publish its host.
  for _ in $(seq 1 60); do
    h=$(dbx postgres get-endpoint "$(ep "$1")" 2>/dev/null | jq -r '.status.hosts.host // empty')
    [[ -n "$h" ]] && { echo "$h"; return; }
    sleep 5
  done
  echo "no endpoint host for branch $1" >&2; return 1
}

case "${1:-}" in
  create)
    branch=$2 source=$3 ttl=$4
    exists "$branch" && dbx postgres delete-branch "${P}/branches/${branch}" >/dev/null
    if [[ "$ttl" == never ]]; then exp=(--no-expiry); else exp=(--ttl "$ttl"); fi
    dbx postgres create-branch "$P" "$branch" "${exp[@]}" \
      --json "{\"spec\":{\"source_branch\":\"${P}/branches/${source}\"}}" >/dev/null
    host "$branch" ;;
  host) host "$2" ;;
  token) dbx postgres generate-database-credential "$(ep "$2")" | jq -r .token ;;
  disable)
    exists "$2" || exit 0
    dbx postgres update-endpoint "$(ep "$2")" spec.disabled --json '{"spec":{"disabled":true}}' >/dev/null ;;
  delete)
    exists "$2" || exit 0
    dbx postgres delete-branch "${P}/branches/$2" >/dev/null ;;
  url)
    pw=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$4")
    user=$(python3 -c 'import sys,urllib.parse;print(urllib.parse.quote(sys.argv[1],safe=""))' "$3")
    echo "postgres://${user}:${pw}@$(host "$2"):5432/${5:-twenty}?sslmode=require" ;;
  *) sed -n '2,11p' "$0"; exit 2 ;;
esac
