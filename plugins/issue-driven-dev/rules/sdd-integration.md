---
name: sdd-integration
description: When to escalate from standard IDD to Spec-Driven Development (SDD)
---

# SDD Integration Rule

SDD (Spec-Driven Development) is a special case of IDD, not a separate workflow.

## Decision Point

`idd-diagnose` is the single decision point. After diagnosis, assess complexity:

### SDD-warranted (any one = yes)

- Changes span 3+ files with interdependent logic
- Requires a new shared abstraction (function, module, protocol)
- Involves architectural decisions or design trade-offs
- Affects multiple existing capabilities or specs
- Strategy has 5+ steps with ordering dependencies

### Simple (all of the above = no)

- Bug fix with clear root cause
- Single-file change
- Following an existing pattern

## Flow

```
Simple:                    diagnose → implement → verify → close
SDD-warranted (default):   diagnose → spectra-discuss → spectra-propose(#NNN) → spectra-apply → verify → close + archive
SDD-warranted (opt-out):   diagnose → spectra-propose(#NNN) → spectra-apply → verify → close + archive
```

## Why spectra-discuss is the default for SDD

AI agents consistently over-estimate how complete their diagnosis is. A diagnosis may describe the strategy in detail but still leave critical decisions unresolved: naming, scope boundaries, which option to pick among equally valid ones, where to place new artifacts. Going directly to `spectra-propose` at that point produces proposals built on implicit assumptions that the user never confirmed.

`spectra-discuss` is the alignment safety net — it forces assumptions to be stated and corrected before any formal proposal is written. Skipping it should be the exception, not the default.

## When to opt-out (skip spectra-discuss)

Only skip `spectra-discuss` when ALL of the following are true:

- The user has already chosen a specific direction in the issue body or diagnosis discussion
- There are no open questions about naming, scope, or trade-offs
- The change follows an existing pattern without new abstractions
- The diagnosis Strategy section has zero unresolved decisions

If even one of these fails, keep `spectra-discuss` in the flow.

## Rules

1. **Issue is always the entry and exit** — even SDD work starts from and closes with an issue
2. **One source of progress** — SDD uses tasks.md, issue gets a link (`→ see spectra change: <name>`)
3. **Verify through IDD** — `idd-verify #NNN` regardless of which path was taken
4. **Close triggers archive** — `idd-close` should also `spectra-archive` for SDD changes
5. **Discuss-first for SDD** — `idd-diagnose` must route SDD-warranted issues to `spectra-discuss` by default; only bypass when the user explicitly opts out during the Step 4 routing prompt
