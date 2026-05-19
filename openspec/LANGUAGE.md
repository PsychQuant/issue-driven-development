# Spectra Project Language & Conventions

Project-specific conventions for authoring Spectra change proposals in
`issue-driven-development`. The OpenSpec base documentation covers the general
spec-authoring language; this file records the deltas and additions specific to
this repo.

## GitHub-side tracker marker

Every Spectra change proposal (`openspec/changes/<name>/proposal.md`) that has a
corresponding GitHub issue **MUST** declare it with the explicit marker:

```
**GitHub-side tracker**: #NN
```

Place the marker near the top of `proposal.md`, after the title / summary block.

### Why

Tooling that maps a Spectra change ↔ its GitHub issue — e.g. `idd-close`'s
auto-post-Implementation-Complete detection (#56) — otherwise has to walk a
3-fallback chain: explicit marker → `Refs`/`Closes`/`Fixes` scan → commit grep.
A single canonical marker collapses the mapping to a one-line lookup and removes
the ambiguity of the fallback chain.

As of this convention's adoption, only 1 of 6 archived proposals carried the
marker — the other 5 forced the fallback chain on every tooling run.

### Scope

- **Going-forward**: the marker is mandatory for every new proposal.
- **Retroactive backfill** of the unmarked archived proposals
  (`openspec/changes/archive/*/proposal.md`) is **optional** — `idd-close`'s
  fallback chain already handles their absence. Backfill is a separate
  mechanical pass if a maintainer wants archive consistency.

---

Surfaced during `/idd-plan #56` Step 2.5 tangential sweep — tracked as #90.
