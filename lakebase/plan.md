# Implementation Plan: Twenty on Lakebase

_ECC `planner` format. Source PRD: [prd.md](prd.md). Complexity: Large._

## Overview

Run Twenty's Postgres on Lakebase and use Lakebase branches as the environments: every PR gets a copy-on-write branch of `dev`, every release is rehearsed on a fresh fork of `production` (acceptance) before prod, and prod gets a restore point first. Search already lives in Postgres, so "unify search" means keeping it in Lakebase and moving it to Lakebase Search where that helps, not replacing an external engine.

## Requirements

- All existing TypeORM migrations and upgrade commands run unmodified on Lakebase, on every PR and every upstream sync.
- The server integration suite runs against Lakebase, not a local `postgres` container.
- Promotion order is fixed: dev → acceptance → prod, the same commit at every stage, prod behind a human approval.
- No data loss across an upgrade, checked mechanically.
- Search behaviour (prefix typeahead, multi-word, accent-insensitive, email/domain) is verified on every stage.
- Upstream stays mergeable: the fork's diff to Twenty code stays minimal and upstreamable.

## Patterns to Mirror

| Category | Source | Pattern |
|---|---|---|
| CI jobs | `.github/workflows/ci-server.yaml` | `yarn-install` action, `nx build twenty-shared`, `reset:env`, sharded `test:integration`, ClickHouse + Redis services, pinned action SHAs |
| DB bootstrap | `packages/twenty-server/src/database/scripts/setup-db.ts` | `CREATE EXTENSION IF NOT EXISTS` for `uuid-ossp`, `unaccent`, `citext` |
| Upgrade | `packages/twenty-docker/twenty/entrypoint.sh` | `database:init:prod` if `core` is missing, then `command:prod upgrade` between two `cache:flush` |
| Upgrade rehearsal | `.github/workflows/ci-cross-version-upgrade.yaml` | seed old version, upgrade from source on the same database |
| Platform schemas | `truncate-db.ts` | explicit skip list (`metric_helpers`, `user_management`), now plus `__db_system` |

## Architecture Changes

- `lakebase/scripts/lb.sh`: branch lifecycle (create from parent with TTL, host, OAuth token, disable endpoint, delete), the same locally and in CI.
- `lakebase/scripts/migrate.sh`, `smoke.sh`, `smoke.py`, `invariants.py`: migrate from an image, boot + login + search, row-count invariants.
- `.github/workflows/lakebase-pr.yaml`: per-PR branch, upgrade rehearsal, 8-shard integration suite, teardown.
- `.github/workflows/lakebase-cd.yaml` + `lakebase-deploy.yaml`: build once, deploy dev, re-fork acceptance from production, gated prod with restore point.
- `.github/workflows/lakebase-upstream-sync.yaml`: daily `main` fast-forward + sync PR.
- `packages/twenty-server/src/database/scripts/truncate-db.ts`: skip `__db_system` (upstream candidate).

## Implementation Steps

### Phase 0: Foundation (done 2026-10-20)

1. **Fork** `twentyhq/twenty` → `HadiFrt20/twenty-lakebase`; `main` mirrors upstream, `lakebase` is the default and integration branch ([ADR-0004](adr/0004-git-flow.md)).
2. **Lakebase topology** in project `twenty-lakebase-0` (fe-vm `classic-stable-2y42x4`, AWS us-east-1, PG 18): `production` (protected), `acceptance`, `dev` ([ADR-0001](adr/0001-lakebase-branch-topology.md)).
3. **CI identity**: service principal `twenty-lakebase-ci` with CAN_MANAGE on the project, OAuth M2M secret; a CREATEDB-only Postgres role on `dev`, inherited by PR branches. No role on production ([ADR-0003](adr/0003-ci-identity-and-credentials.md)).
4. **Per-env app credential**: native role `twenty`, distinct password on `dev`.
5. **Scripts and workflows** (above). Verified locally: branch create 4.4 s, SP create/token/DB/extensions/delete, invariants on `dev` (2 workspaces, 11,099 rows).
6. **First Lakebase-specific fix**: `__db_system` skip in `truncate-db.ts`.

### Phase 1: Green PR lane

1. **Open the first PR into `lakebase`** (this one) and read the run. Dependencies: Phase 0. Risk: Medium.
2. **Fix what Lakebase breaks** in the integration suite, one PR per root cause, each with the smallest upstreamable change. Watch for: superuser assumptions, `DROP DATABASE`, advisory locks through a pooler, statement timeouts over WAN. Risk: Medium.
3. **Parity check**: keep upstream `CI Server` enabled on the fork so the same PR runs the suite on `postgres:18` and on Lakebase; any test that fails only on Lakebase is a migration bug. Risk: Low.
4. **Tune shards** (8 now, upstream uses 16) against the endpoint autoscaling limit (1–4 CU). Raise the PR branch's max CU if shards contend. Risk: Low.

### Phase 2: Green promotion

1. **Configure environments**: `dev` (no gate), `acceptance` (deploys from `lakebase` only), `prod` (required reviewer, `lakebase` only). Done.
2. **First CD run** on merge: dev → acceptance (re-forked from production) → approval → prod with `pre-<sha>` restore point. Risk: Medium.
3. **Rollback drill**: break a migration on purpose in a throwaway PR, promote to acceptance, confirm the invariants check stops it; then practise restoring prod from `pre-<sha>` and write the runbook into `lakebase/README.md`. Risk: Medium.
4. **Upstream sync**: add `SYNC_TOKEN`, let the first sync PR run end to end. Risk: Low.

### Phase 3: Search on Lakebase Search

1. **Enable Lakebase Search** on the project in a planned window (irreversible, restarts every compute). Risk: High, approval needed.
2. **Prefix test**: `to_tsquery('simple', 'chri:*')` against a `lakebase_bm25` index. If prefix works, BM25 can serve typeahead; if not, keep GIN tsvector for typeahead and use BM25 only for long text. Risk: Low.
3. **BM25 for long text** (note/task bodies, email bodies) behind a feature flag in `search.service.ts`, with the same `smoke.py` cases plus relevance cases. New upgrade command under the current version directory for the index. Risk: Medium.

### Phase 4: Scale proof

1. **Script N-workspace creation** on a throwaway branch: 1k then 5k workspaces (45 tables, 209 indexes each). Measure upgrade time, catalog queries, connection startup. Risk: High (the one real unknown).

### Phase 5: Agent search (optional)

1. **Embeddings + `lakebase_vector`** on notes and emails, hybrid with existing tsvector via SQL RRF, exposed as a tool to Twenty's AI agents (`src/engine/metadata-modules/ai/`). Risk: Medium.

## Testing Strategy

| Stage | Database | What runs | Destructive? |
|---|---|---|---|
| PR | `pr-<n>` forked from `dev`, plus `test_<shard>` databases on it | Upgrade rehearsal, invariants, pending-migration check, smoke, full integration suite (8 shards) | Yes, throwaway |
| dev | `dev` | Upgrade from the built image, invariants, smoke | Upgrade only |
| acceptance | `acceptance`, re-forked from `production` each run | Same as dev, on today's prod data | Upgrade only |
| prod | `production` after a `pre-<sha>` restore point | Same as dev | Upgrade only |

The integration suite resets its database, so it only ever runs on throwaway PR branches, never on a long-lived environment.

## Risks & Mitigations

See [prd.md#risks](prd.md). The two that most need watching: the per-project endpoint cap (teardown discipline) and workspace-count scale (Phase 4).

## Success Criteria

- [ ] `Lakebase PR` green on a PR into `lakebase`
- [ ] Integration suite pass/fail identical to `CI Server` on the same PR
- [ ] `Lakebase CD` green through prod with a recorded approval
- [ ] Rollback drill done and written down
- [ ] First upstream sync PR green with no manual step
- [ ] Phase 3 prefix question answered with a query result
