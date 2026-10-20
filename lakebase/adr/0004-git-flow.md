# ADR-0004: `main` mirrors upstream, `lakebase` integrates

**Date**: 2026-10-20 · **Status**: accepted

## Decision

- `main` is an untouched mirror of `twentyhq/twenty`, fast-forwarded daily (`lakebase-upstream-sync.yaml`).
- `lakebase` is the default branch. Everything lands by PR, with `Lakebase PR` required to pass.
- Upstream reaches `lakebase` only through a sync PR, so every upstream release re-runs every migration on Lakebase before merge.
- Push to `lakebase` runs `Lakebase CD` (dev → acceptance → gated prod).
- Fork-specific changes stay small: new files under `lakebase/` and `.github/workflows/lakebase-*`, plus minimal upstreamable fixes.
- Upstream workflows that need upstream secrets (deploy, i18n, preview, Claude) are disabled on the fork; `CI Server` stays on as the vanilla-Postgres baseline.

## Consequences

- Merge conflicts with upstream are limited to the few lines we patch in Twenty code.
- Sync PRs need a PAT (`SYNC_TOKEN`): PRs opened by `GITHUB_TOKEN` don't trigger workflows, and it can't push workflow-file changes.
