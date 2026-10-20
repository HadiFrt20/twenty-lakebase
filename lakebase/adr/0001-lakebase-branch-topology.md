# ADR-0001: Lakebase branches are the environments

**Date**: 2026-10-20 · **Status**: accepted

## Context

We need dev, acceptance and prod databases, plus a throwaway database per PR, and we want acceptance to test upgrades on real prod data. Lakebase branches are copy-on-write forks that are ready in about 5 s (4.4 s measured).

## Decision

One project, `twenty-lakebase-0`, with branches:

| Branch | Parent | Lifetime | Purpose |
|---|---|---|---|
| `production` | root | permanent, **protected** | prod |
| `acceptance` | `production` | re-forked on every release | upgrade rehearsal on today's prod data |
| `dev` | `production` (once) | permanent | integration target; parent of PR branches |
| `pr-<n>` | `dev` | TTL 72 h; deleted on success, compute stopped on failure | per-PR rehearsal + integration suite |
| `pre-<sha>` | `production` | TTL 7 d, compute stopped | restore point taken before each prod migration |

## Alternatives Considered

### One project per environment
- **Pros**: hard isolation, separate compute caps
- **Cons**: no copy-on-write between projects, so acceptance can't be a fresh prod copy
- **Why not**: that copy is the main reason to use Lakebase here

### Long-lived acceptance that only replays migrations
- **Pros**: stable host and password
- **Cons**: drifts from prod; rehearses on stale data
- **Why not**: the point is to test on what prod looks like today

## Consequences

### Positive
- Every release is rehearsed on a full prod copy in seconds, at storage cost only for changed pages.
- Rollback is a branch, not a dump restore.

### Negative
- acceptance's endpoint host changes on every re-fork, so workflows resolve hosts at run time (`lb.sh host`).
- acceptance holds prod data and prod's role passwords (see ADR-0003).

### Risks
- About 20 active endpoints per project (observed 2026-10-19). Stalled branches fail silently, so teardown must delete or disable.
