# Twenty on Lakebase

_ECC `/plan-prd` format. Implementation plan: [plan.md](plan.md). Decisions: [adr/](adr/README.md)._

## Problem

Twenty (open-source CRM, NestJS + TypeORM) runs on self-managed Postgres 16/18. Its upgrade path is heavy: 49+ upgrade versions, 244+ per-workspace commands, one schema per workspace. Teams self-hosting Twenty rehearse those upgrades by hand, if at all, and have no cheap way to try an upgrade on a full copy of production first.

## Evidence

- Spike 1 (2026-10-16): stock `twentycrm/twenty:latest` ran on Lakebase project `twenty-lakebase-0` with zero code change. Migrations, seed, login, prefix and accent-insensitive search all passed. Search ran in 0.14 ms server-side (GIN bitmap scan).
- Twenty does **not** use Elasticsearch, OpenSearch or any external search engine (re-checked on `d1f7f58e`, 2026-10-20). Search is a generated `tsvector` column + GIN + `ts_rank_cd`, with prefix (`:*`) matching for typeahead. There is no second search system to merge into Lakebase.
- 2026-10-20: `database:reset` (used by the integration suite) fails on Lakebase: `truncate-db.ts` tries to drop the platform schema `__db_system` (`must be owner of schema __db_system`). Fixed in this fork.

## Users

- **Primary**: an engineer who runs Twenty in production and has to ship every upstream release without breaking data.
- **Not for**: Twenty Cloud's own multi-thousand-workspace fleet (see the scale risk below), or analytics users (ClickHouse).

## Hypothesis

If every PR and every upstream release is rehearsed on a copy-on-write Lakebase branch of real data before promotion through dev, acceptance and prod, then upgrades reach prod with zero data loss and a one-step rollback, and no separate search system is needed.

## Success Metrics

| Metric | Target | How measured |
|---|---|---|
| Upstream release rehearsed on Lakebase | 100% of syncs | `Lakebase PR` run on every sync PR |
| Server integration suite on Lakebase | Same pass/fail set as vanilla `postgres:18` (`CI Server`) | Compare both workflow results on the same PR |
| Data loss across an upgrade | 0 rows lost in core objects | `invariants.py` before/after on every stage |
| Time to a fresh prod copy | < 30 s | `lb.sh create` timing (measured 4.4 s) |
| Rollback | One branch switch, restore point < 7 days old | `pre-<sha>` branch per prod deploy |
| Search on Lakebase | Prefix, multi-word, accent and domain cases pass on each env | `smoke.py` |

## Scope

**MVP (Must):** fork + Lakebase env branches; PR lane (ephemeral branch, upgrade rehearsal, integration suite); CD lane (dev, then acceptance re-forked from prod, then prod behind a reviewer, with a restore point); daily upstream sync; search parity on every stage.

**Should:** Lakebase Search (`lakebase_bm25`) for long-text bodies (notes, tasks, emails) while keeping tsvector prefix search for typeahead; workspace-scale load test.

**Could:** semantic and hybrid search (`lakebase_vector` + RRF) for Twenty's AI agents, which today have no vector store.

**Won't (now):** moving ClickHouse analytics or Redis/BullMQ into Lakebase. Neither is search, and Redis is a queue. Hosting the app runtime (open question).

## Delivery Milestones

| # | Milestone | Outcome | Status | Plan |
|---|---|---|---|---|
| 0 | Foundation | Fork, env branches, CI identity, scripts, workflows | done 2026-10-20 | [plan.md#phase-0](plan.md) |
| 1 | Green PR lane | Upgrade + integration suite pass on a per-PR Lakebase branch | in-progress | [plan.md#phase-1](plan.md) |
| 2 | Green promotion | dev → acceptance → prod with gate, invariants, rollback drill | pending | [plan.md#phase-2](plan.md) |
| 3 | Search on Lakebase Search | BM25 long-text + typeahead parity, behind a flag | pending | [plan.md#phase-3](plan.md) |
| 4 | Scale proof | 1k and 5k workspace schemas on one branch | pending | [plan.md#phase-4](plan.md) |
| 5 | Agent search | Embeddings + hybrid search for AI agents | pending | [plan.md#phase-5](plan.md) |

## Open Questions

- Where does the app run per environment (Databricks Apps can't host Redis; a VM or k8s is likely)? Until decided, each stage boots the image on the runner against that stage's database.
- Can container images be published (GHCR on a public fork makes them public), or do they stay in the Actions cache?
- Should `dev` hold synthetic seed data instead of a prod copy? It does not matter with demo data; it does with real customer data.
- Does `lakebase_bm25` support prefix (`term:*`) queries yet? Last known: on the roadmap for end-2026. This decides Phase 3.

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| ~20 active endpoints per project; extra branches stall silently | High | PR runs hang | Delete on success, disable endpoint on failure, 72 h TTL |
| Thousands of workspace schemas on one branch | Medium | Slow catalog, slow upgrades | Phase 4 load test before any real tenant |
| WAN latency between runners and Lakebase | Medium | Slow, flaky integration shards | Same-region runners (us-east-1), shard count tuning |
| CI principal's OAuth token lasts 1 h | Medium | Long shards fail auth | Job timeout 60 min; split shards further if needed |
| Upgrade errors swallowed by the image entrypoint | High | Silent half-migrated prod | `migrate.sh` runs `upgrade` directly and fails the job |
| Enabling Lakebase Search restarts all project computes and can't be undone | Certain | Brief outage of every env | Do it once, in a window, before Phase 3 |
