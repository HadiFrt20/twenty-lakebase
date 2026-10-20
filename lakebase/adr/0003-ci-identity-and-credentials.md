# ADR-0003: CI identity and per-environment credentials

**Date**: 2026-10-20 · **Status**: accepted

## Context

CI needs to manage branches (control plane) and run migrations and tests (data plane). Twenty needs a static `PG_DATABASE_URL`, and the objects it creates must stay owned by one role across environments. Branches inherit roles and passwords from their parent.

## Decision

- **Control plane**: service principal `twenty-lakebase-ci`, OAuth M2M (`DATABRICKS_CLIENT_ID/SECRET` repo secrets), CAN_MANAGE on the project only.
- **App and migrations**: native login role `twenty`, one `TWENTY_PG_PASSWORD` secret per GitHub environment. `dev` has its own password; PR branches inherit it.
- **Integration tests**: run as the service principal with a 1 h OAuth token in `test_<shard>` databases it owns. Its Postgres role exists on `dev` only and has CREATEDB, no superuser.
- **acceptance shares prod's password.** It is a copy-on-write fork of production, so it carries prod's roles and prod's data. Treat it as prod-sensitive: deploys only from `lakebase`.

## Alternatives Considered

### DATABRICKS_SUPERUSER for the CI role on every branch
- **Why not**: broader than needed and reaches production. Trusted extensions (`uuid-ossp`, `unaccent`, `citext`) only need database ownership.

### Rotate acceptance's password after every re-fork
- **Why not**: changing it requires logging in with prod's password or a CREATEROLE principal on production, which is worse.

## Consequences

### Negative
- The integration suite's 60 min job timeout is bounded by the 1 h token.
- Hardening: replace the client secret with GitHub OIDC workload identity federation (needs an account-level federation policy).
