# North-star tracker SOP

> The convention for an **ordered, progressively-emerging multi-stage roadmap** — a "north-star" epic whose later stages are filed as issues *over time*, not all upfront. (`PsychQuant/issue-driven-development#179`)

## When to use this (vs the other multi-issue structures)

IDD has three ways to relate many issues. They are **complementary, not interchangeable** — pick by two axes: are the children all known *upfront*, and is there an *order*?

|  | all-upfront (children exist now) | **progressive-emergence (stages filed over time)** |
|---|---|---|
| **flat / unordered** | milestone-first SOP (`#83`) | ad-hoc — just file issues as they arise |
| **ordered** | `idd-issue --bundle-mode ordered` → `/idd-all-chain` (`#81`) | **north-star tracker (this doc, `#179`)** |

Use a **north-star tracker** when you have a roadmap (Stage 1 → N) but **Stage N+1 is not designed until Stage N ships** — so you cannot, and should not, file every stage-issue in advance. If all children are already known, use `--bundle-mode` instead (see [`bundle-flags.md`](bundle-flags.md)). If you just need flat grouping of issues that all exist, use a GitHub Milestone (`#83`).

## The roadmap-checklist format

A north-star tracker is a **persistent issue** carrying the `north-star` label. Its body has a `## Roadmap` section — an ordered checklist of stages where the **presence or absence of an issue reference is the emerged-vs-not signal**:

- **Unfiled stage** → unchecked bullet, **no** issue reference: `- [ ] Stage 2: transfers`
- **Filed stage** → checked bullet ending in `→ #N`: `- [x] Stage 1: core → #7`

```markdown
## Roadmap

- [x] Stage 1: routing-engine core → #7
- [ ] Stage 2: multi-modal transfers
- [ ] Stage 3: realtime delay integration
```

In that example, **1 stage is filed** (Stage 1 → #7) and 2 are roadmap-only; total is 3, so progress is `1/3 stages`. The `#N` on an item is canonical: an item with a number has graduated into a real issue; an item without one is still just a roadmap entry.

This is the whole mechanism — no upfront child issues, no new flag. The roadmap is a living document that grows as stages emerge. Contrast `--bundle-mode`, which files **all** children at epic-creation time (so it cannot express "Stage 3 is not designed yet").

## Progressive file-on-start

A stage is filed as **its own issue, running the full IDD lifecycle** (`idd-issue` → `idd-diagnose` → … → `idd-close`), **only when work on it begins** — never in advance. The roadmap stays sparse until then.

When a stage is filed:

1. `idd-issue` the stage (it gets its own `#N`, body, lifecycle).
2. Update the tracker's roadmap item to checked + linked — `- [ ] Stage 2: transfers` becomes `- [x] Stage 2: transfers → #N`. Use `/idd-edit comment:<tracker-body> --replace --section "## Roadmap" …`, or edit the tracker body directly. (The tracker body itself, not a comment, holds the roadmap.)

No stage beyond the one being started needs to exist. This is the defining difference from `--bundle-mode`'s upfront-all-children model.

## How `idd-list` shows a tracker

`idd-list` recognizes a tracker by its label (`north-star`, or `epic`) and shows it as `[tracking]` — **not** `(no phase)` with a misleading "run `/idd-update`" hint. When the body has a parseable `## Roadmap`, it appends roadmap progress:

```
#7  [tracking] 1/3 stages   north-star: routing engine
```

Progress is `<filed>/<total>`, where `<filed>` counts checked items carrying an `#<number>` and `<total>` is the number of roadmap items. This same rule covers the milestone-tracked epic trackers of the milestone-first SOP (`#83`) — the tracker-phase display is **shared**, so a tracker (north-star or milestone epic) is never nagged to run a lifecycle step it has no business running.

> **Why a tracker has no lifecycle phase**: phases (`created`/`diagnosed`/…/`closed`) describe a *single deliverable*. A tracker is meta — its stage-issues each run their own lifecycle, while the tracker persists across all of them. `tracking` is the honest status; `(no phase)` was a false signal.

## Deferred

- `idd-issue --stage-of <tracker>` (auto-append/update the tracker roadmap on file) is **deferred** until the rule-of-three fires (≥3 independent real cases). Today there is one (`PsychQuant/che-transport-mcp#7`); a flag for a single case is premature. The SOP above works today with a manual tracker edit.
