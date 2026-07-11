## 1. Contract + tests first (RED)

- [x] 1.1 (Design D1; Req: the contract and GraphQL templates live in one shared reference) Write plugins/issue-driven-dev/references/discussions-intake.md — the three normative constraints (no-auto-file / dedup / resolution-detection with `answerChosenAt` as the mechanical boundary), the `hasDiscussionsEnabled` probe query, the discussions list query (first 50: number, title, url, category name, answerChosenAt, updatedAt, author login), the single-discussion fetch query, and the schema-assumption note (field names + date). Verify: file exists and contains all three constraint names + three query blocks.
- [x] 1.2 (Design D4) Write plugins/issue-driven-dev/scripts/tests/discussions-intake/test.sh (assert-helpers): asserts idd-list documents `--discussions` + disabled-repo no-op + category/answered/dedup filter + dedicated block; idd-issue documents `--from-discussion` + Provenance blockquote + draft-and-confirm reply + unattended draft-only; reference doc carries constraints + queries; both skills cite the reference. Run it: RED (SKILL prose absent), reference assertions GREEN.

## 2. idd-list Step 2.7 (GREEN part 1)

- [x] 2.1 (Design D2; Req: idd-list surfaces actionable Discussions on opt-in) Add Step 2.7 to plugins/issue-driven-dev/skills/idd-list/SKILL.md: opt-in `--discussions` flag parse (Step 1 table row), probe → skip-note on disabled, fetch → filter (Q&A/Ideas AND answerChosenAt null) → dedup (search issue bodies for the discussion URL, both states) → `Discussions (actionable)` block after the issues table with per-row `→ /idd-issue --from-discussion <url>` + footer count; zero-actionable one-line note; GraphQL failure degrades to the same skip-note (never aborts idd-list). Bootstrap TaskCreate list gains a `fetch_discussions` entry. Verify: discussions-intake suite idd-list assertions GREEN.

## 3. idd-issue --from-discussion (GREEN part 2)

- [x] 3.1 (Design D3; Req: idd-issue seeds an issue from a Discussion with verbatim provenance; Req: the intake bridge never auto-files and never auto-posts) Add `--from-discussion <url|number>` to plugins/issue-driven-dev/skills/idd-issue/SKILL.md: fetch via the reference's single-discussion query, seed draft body with `## Provenance` (URL + author + verbatim blockquote of opening post), continue unchanged pipeline; after creation, draft back-reference reply — attended: AskUserQuestion confirm then `addDiscussionComment`; unattended: print draft in Step 5 report marked not-posted, never mutate. Bootstrap TaskCreate list gains a `seed_from_discussion` entry. Verify: discussions-intake suite idd-issue assertions GREEN.

## 4. Docs + full-suite regression

- [x] 4.1 Add the two flags to plugins/issue-driven-dev/references/usecase-routing.md (one new scenario row: "user report arrived as a Discussion") and a short README section under the skills table noting the opt-in Discussions bridge (#221). Verify: discussions-intake suite doc assertions GREEN.
- [x] 4.2 Run the full plugin test set (all suites under plugins/issue-driven-dev/scripts/tests/) and `spectra validate discussions-intake-bridge`. Verify: no suite regresses; validate clean.
