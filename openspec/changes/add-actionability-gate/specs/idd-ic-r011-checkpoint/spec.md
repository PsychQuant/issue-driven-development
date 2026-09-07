## MODIFIED Requirements

### Requirement: Skip path SHALL require explicit 3-category taxonomy disambiguation

When the user requests to skip filing one or more candidates (via explicit user prompt, env var bypass, or `# Disable IC_R011` flag), the skill SHALL present a second-level `AskUserQuestion` for each skip-candidate forcing selection among three categories: `(a) unactionable observation`, `(b) infeasible but understood`, or `(c) blocked on external state`. Selecting `(a)` SHALL skip filing and record `Skipped: (a) unactionable observation` in the audit trail. Selecting `(b)` or `(c)` SHALL still file the candidate via `gh issue create` with an added repository label of `parking-lot` or `parking-lot` respectively, and SHALL record `Skipped: (b) infeasible — filed as #NNN with `parking-lot` label` (or the `(c)` equivalent).

#### Scenario: user skips one of three candidates with category (a)

- **WHEN** the user invokes skip for 1 out of 3 surfaced candidates and selects `(a) unactionable observation` from the second-level picker
- **THEN** the skill MUST file the other 2 candidates via `gh issue create` AND MUST NOT file the skipped candidate AND MUST record the skip reason in the audit trail with the literal string `Skipped: (a) unactionable observation`

#### Scenario: user skips with category (b)

- **WHEN** the user selects `(b) infeasible but understood` for a candidate
- **THEN** the skill MUST still call `gh issue create` for that candidate AND MUST attach the label `parking-lot` via the `--label` flag AND MUST record `Skipped: (b) infeasible — filed as #<newly-created-number> with `parking-lot` label` in the audit trail

##### Example: skip-and-file audit trail entries

- **GIVEN** 3 candidates [X, Y, Z], user skips Z with category (c)
- **WHEN** the skill executes
- **THEN** the audit trail contains both `Filed: #X-num, #Y-num` and `Skipped: (c) blocked-on-external — filed as #Z-num with `parking-lot` label`


<!-- @trace
source: idd-ic-r011-default-file
updated: 2026-05-25
code:
  - .agents/skills/spectra-archive/SKILL.md
-->

---

> Modified by `add-actionability-gate` (#316 round 3): the (b) / (c) skip categories file the candidate with the `parking-lot` label instead of `blocker:infeasible` / `blocker:waiting`. Those two labels were never created in any repository using IDD, while `parking-lot` is in use and — since 3.1.0 — is the primary parked signal of the actionability gate, so a sister issue filed under (b) / (c) is born parked and stays out of routing until a human removes the label. The reference (`ic-r011-checkpoint.md`), `idd-issue`, and `idd-diagnose` were converged in the same change; this delta brings the live spec's MUST into agreement.
