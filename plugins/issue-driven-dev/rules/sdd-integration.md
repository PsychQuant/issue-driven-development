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
Simple:        diagnose → implement → verify → close
SDD-warranted: diagnose → spectra-propose(#NNN) → spectra-apply → verify → close + archive
```

## Rules

1. **Issue is always the entry and exit** — even SDD work starts from and closes with an issue
2. **One source of progress** — SDD uses tasks.md, issue gets a link (`→ see spectra change: <name>`)
3. **Verify through IDD** — `idd-verify #NNN` regardless of which path was taken
4. **Close triggers archive** — `idd-close` should also `spectra-archive` for SDD changes
