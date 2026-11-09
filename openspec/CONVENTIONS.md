# Spectra Project Conventions

Project-specific authoring conventions for Spectra change proposals in
`issue-driven-development`. Distinct from `openspec/LANGUAGE.md`, which holds the
project's canonical **vocabulary** (terms + `definition`/`avoid`/`why` notes,
loaded by `/spectra-discuss` Step 0). This file holds **workflow conventions** —
how proposals are authored and linked.

## GitHub-side tracker marker

Every Spectra change proposal (`openspec/changes/<name>/proposal.md`) that has a
corresponding GitHub issue **MUST** declare it with the explicit marker:

```
**GitHub-side tracker**: #NN
```

Place the marker near the top of `proposal.md`, after the title / summary block.

### Why

Tooling that maps a Spectra change ↔ its GitHub issue — e.g. `/spectra-archive`
Step 7, which posts Implementation Complete (#56) — proposes the issue from this marker
first. Write it exactly as above, the number right after the label: a sentence in that
place, or a tracker in another repository, is offered for a person to choose instead
(#405). Without the marker, the commits' `(#N)` groups and the change's text are read,
and anything they do not settle is offered too. The person reviewing Step 7 confirms the
issue either way.

As of this convention's adoption, only 1 of 6 archived proposals carried the
marker — the other 5 forced the fallback chain on every tooling run.

### Scope

- **Going-forward**: the marker is mandatory for every new proposal.
- **Retroactive backfill** of the unmarked archived proposals
  (`openspec/changes/archive/*/proposal.md`) is **optional** — Step 7 offers
  candidates when the marker is absent. Backfill is a separate mechanical pass if a
  maintainer wants archive consistency.

---

Surfaced during `/idd-plan #56` Step 2.5 tangential sweep — tracked as #90.
