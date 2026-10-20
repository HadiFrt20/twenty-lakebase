# ADR-0005: Build once into the Actions cache, no registry

**Date**: 2026-10-20 · **Status**: proposed

## Context

Best practice is to build one artifact and promote it unchanged. Pushing to GHCR from a public fork can create a public package, which we have not agreed to publish.

## Decision

The `image` job builds the `twenty` Dockerfile target into the GitHub Actions cache, scoped to the commit SHA. Each stage reloads it from that cache (`load: true`), so all stages run the same layers without a registry.

## Alternatives Considered

### Push to GHCR (private package) and promote by digest
- **Pros**: true digest pinning; the image is reusable by a real runtime
- **Why not yet**: package visibility needs an explicit decision. Switch to it once the app runtime is chosen.

## Consequences

- If the cache is evicted between stages, the stage rebuilds from source at the same commit. Same inputs, but not bit-for-bit guaranteed.
