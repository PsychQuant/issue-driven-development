# Attribute Assessment Rule

> **Scope**: This rule applies to any Claude session in the `issue-driven-development` repo where Claude must assess a property of an issue, requirement, or design artifact (e.g., vagueness, confidence, priority, risk, complexity).

## Core principle

**Attribute scoring SHALL use a Likert scale, not keyword matching.**

Keyword matching is brittle:

- Hedge words like 「感覺」 / 「之類」 / `kinda` / `somewhat` can appear in **confident assertions** as well as vague ones — pattern alone is insufficient signal.
- Cross-language coverage forces ever-growing regex lists, all of which drift over time.
- Deterministic match on a wrong feature is *worse* than honest AI judgment because it hides its mistake behind a rule.

Likert scoring forces Claude to **make and disclose a judgment** with reasoning. The reasoning becomes audit trail; users can spot drift directly by inspecting the score + rationale, then recalibrate the anchors if needed.

## Likert scale shape (REQUIRED for any new attribute scoring)

- **6-point scale**, integer 1–6
- **No neutral midpoint** — the cut runs between 3 and 4, forcing a "lean" decision while preserving nuance over a 4-point scale
- **Score 1** = strongest negative pole (e.g., "completely clear" for vagueness)
- **Score 6** = strongest positive pole (e.g., "completely opaque" for vagueness)
- **Anchors required at every score** — each score MUST have at least one concrete example so AI calibration does not drift

## Output requirements (per scoring instance)

Whenever Claude scores an attribute, the output SHALL include:

1. **Integer score** (1–6) per axis, separately per axis when multi-axis
2. **One-sentence reasoning** per axis citing concrete evidence (line numbers, quoted phrases, structural observations) — never just "feels like X"
3. **Audit trail entry** in the artifact where the scoring decision lives (issue body / Diagnosis comment / design.md / similar). Format: `<axis>: <score> — <reasoning>`

## Adversary checks (per audit discipline)

When applying attribute scoring in any new mechanism, evaluate through 3 lenses:

| Lens | Question | Mitigation |
|------|----------|------------|
| **Scoundrel** | Can a user game the score by writing issue bodies in a particular style to force or avoid a verdict? | Anchors describe content, not style. Scoring is on the **substance** of the issue (what is asked), not on hedge words or markdown formatting. |
| **Lazy Developer** | Will Claude default to the lowest-trigger score (e.g., V=1 V=1) to skip downstream work? | The audit trail forces Claude to **show its reasoning**. Lazy scoring is observable. |
| **Confused Developer** | Will the developer/maintainer apply this scoring to the wrong axis (e.g., scoring scope when the axis is "what to do")? | Each axis MUST have a one-sentence definition + axis name in the rule that adopts this scale. |

## Vagueness anchors (used by `idd-diagnose` Step 3.4 Layer V)

The Vagueness attribute has two axes evaluated independently. Trigger threshold is `max(V1, V4) ≥ 4`.

**V3 (vague SCOPE) is intentionally excluded** from this rule — it overlaps with the IC_R011 sister sweep mechanism (`idd-diagnose` Step 3.6), which already surfaces "the issue is clear but spillover concerns exist" cases. Scoring V3 here would create a duplicate prompt to the user with overlapping semantics.

### V1: Vague WHAT (clarity of what should be done)

| Score | Meaning | V1 example |
|-------|---------|------------|
| 1 | Completely clear | "Change line 42 of `foo.rs` from `x = 1` to `x = 2`" |
| 2 | Clear | "Add a button to the login page that opens the help modal" |
| 3 | Mostly clear | "The export feature seems slow when handling 10k+ rows, optimize it" |
| 4 | Somewhat vague | "Improve the menu navigation, it feels off" |
| 5 | Vague | "The reports look weird, fix them" |
| 6 | Completely opaque | "Make this work better" |

### V4: Vague ACCEPTANCE (clarity of completion criteria)

| Score | Meaning | V4 example |
|-------|---------|------------|
| 1 | Completely clear | "Acceptance: function returns 200 status when input is valid email" |
| 2 | Clear | "Done when all unit tests pass and PR review approved" |
| 3 | Mostly clear | "Done when latency feels noticeably better" |
| 4 | Somewhat vague | "Make the API response cleaner" |
| 5 | Vague | "Done when it's good enough" |
| 6 | Completely opaque | "Done when done" |

### V2 (vague HOW)

V2 is **not part of Layer V** — it is already covered by `rules/sdd-integration.md` Layer P "Decision-heavy with multiple valid approaches". Routing decisions about implementation strategy belong to that layer; do not double-score.

## Why this rule lives in `.claude/rules/` not the plugin

Attribute scoring is a Claude session-wide behavior, not a plugin-internal mechanic. Placing it under `plugins/issue-driven-dev/rules/` would scope it only to plugin skill execution. Placing it under `.claude/rules/` (with a `@-import` from the project `CLAUDE.md`) makes Claude follow the rule for **any** attribute assessment in this repo, including future non-IDD scoring needs.

Trade-off (acknowledged): the rule does not travel with the plugin. Other repos installing `issue-driven-dev` will not have this file. The plugin's `idd-diagnose` Step 3.4 has a fallback that uses built-in anchors and prints a warning when the project rule is absent. If/when this rule proves stable across multiple repos, promote it to plugin internal or to global `~/.claude/CLAUDE.md`.
