# Twenty on Lakebase

This fork runs Twenty's Postgres on [Lakebase](https://docs.databricks.com/aws/en/oltp/) and uses Lakebase branches as its environments.

- [prd.md](prd.md): problem, scope, milestones
- [plan.md](plan.md): phased implementation plan
- [adr/](adr/README.md): decisions

## Flow

```
upstream twentyhq/twenty ──daily──▶ main ──sync PR──▶ lakebase ──push──▶ Lakebase CD
                                                 ▲                       │
                         feature PR ─────────────┘                       ├─ dev        (branch dev)
                         │                                               ├─ acceptance (re-forked from production)
                         └─ Lakebase PR: pr-<n> forked from dev          └─ prod       (approval, pre-<sha> restore point)
                            upgrade rehearsal + invariants + smoke
                            + integration suite (8 shards)
```

## Configuration

| Name | Kind | Scope |
|---|---|---|
| `DATABRICKS_HOST`, `LAKEBASE_PROJECT` | variable | repo |
| `DATABRICKS_CLIENT_ID`, `DATABRICKS_CLIENT_SECRET` | secret | repo (SP `twenty-lakebase-ci`) |
| `TWENTY_PG_PASSWORD` | secret | per environment (`dev`, `acceptance`, `prod`) |
| `SYNC_TOKEN` | secret | repo, optional (enables upstream sync) |

## Local use

```bash
export DATABRICKS_CONFIG_PROFILE=<profile>  LAKEBASE_PROJECT=twenty-lakebase-0
lakebase/scripts/lb.sh create my-test dev 4h          # prints the endpoint host
export PG_DATABASE_URL=$(lakebase/scripts/lb.sh url my-test twenty "$TWENTY_PG_PASSWORD")
python3 lakebase/scripts/invariants.py snapshot before.json
lakebase/scripts/migrate.sh twentycrm/twenty:latest
lakebase/scripts/lb.sh delete my-test
```

## Rollback (prod)

Every prod deploy first forks `pre-<sha7>` from `production` (7-day TTL, compute stopped). To roll back: re-enable its endpoint, point the app at it, and redeploy the previous commit. Runbook to be completed in the Phase 2 drill.
