# ADR-0002: Search stays in Postgres; Lakebase Search is additive

**Date**: 2026-10-20 · **Status**: accepted

## Context

The goal was to fold any external search (Elasticsearch, OpenSearch, …) into Lakebase. Twenty uses none: search is a generated `tsvector('simple', unaccent_immutable(...))` column with a GIN index, `ts_rank_cd` ranking, and `:*` prefix matching on every term for typeahead (`search.service.ts`, `format-search-terms.ts`). It runs on Lakebase unchanged (spike 1: 0.14 ms server-side).

## Decision

Keep the tsvector + GIN search as is; it already runs on Lakebase, so search is already unified. Add Lakebase Search on top only where it helps: `lakebase_bm25` for long-text bodies, `lakebase_vector` for agent semantic search. Verify search on every environment with `smoke.py`.

## Alternatives Considered

### Replace tsvector with `lakebase_bm25` everywhere
- **Pros**: better relevance on long text; index is storage-backed and survives scale-to-zero
- **Cons**: prefix queries (`term:*`) are not documented for BM25; Twenty's search UX is type-as-you-go
- **Why not**: until prefix works it would be a regression (re-test in Phase 3)

## Consequences

### Positive
- Zero search code change to get onto Lakebase.

### Negative
- GIN indexes are memory-resident; after scale-to-zero the first searches are cold. Keep `suspend_timeout` long on prod.
