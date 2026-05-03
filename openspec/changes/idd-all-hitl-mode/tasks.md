## 1. Mode resolution skeleton

- [x] 1.1 Implement Phase 0.5 mode resolution from pr_policy and flags in `plugins/issue-driven-dev/skills/idd-all/SKILL.md` — replace the hardcoded `--pr` enforcement with the precedence chain (`--pr` → `--no-pr` → fork detect → `pr_policy: always|never|ask`)
- [x] 1.2 Add the resolved-tuple notice line (e.g. `→ Path: direct-commit (attended) — pr_policy=never`) before Phase 1 begins
- [x] 1.3 Update Step 0 Bootstrap Stage Task List in idd-all/SKILL.md to add a `resolve_mode` task entry

## 2. PR path preserves v2.40.0 behavior

- [x] 2.1 Refactor Phase 0.5 branch creation into a guarded block that runs only when resolved path is `PR`; ensure `git checkout -b idd/<N>-<slug>` from default branch matches existing logic exactly
- [x] 2.2 Refactor Phase 5 to skip the `git push -u` + `gh pr create` block when path is `direct-commit`; keep it intact for path `PR` so the requirement that PR path preserves v2.40.0 behavior holds
- [x] 2.3 Audit Phase 3a / 3b sub-skill invocation args — the `UNATTENDED MODE` directive must still be passed when interaction is `unattended` so the existing PR-path callers (e.g. `/loop`) observe zero behavioral drift, satisfying "PR path preserves v2.40.0 behavior" end-to-end

## 3. Direct-commit path stays on current branch and skips PR

- [x] 3.1 Implement the "Direct-commit path stays on current branch and skips PR" branch behavior — in Phase 0.5, when path is `direct-commit`, log `→ direct-commit path: committing to <branch>, no PR will be opened` and skip the branch-creation precondition checks (uncommitted-tree / on-default-branch are not enforced)
- [x] 3.2 Phase 5 prints `→ direct-commit path: skipping push + PR` and jumps to Phase 6
- [x] 3.3 Phase 6 next-step copy branches on resolved path: PR → review-PR-and-merge instructions; direct-commit → review-recent-commits instructions

## 4. Attended interaction permits sub-skill questions

- [x] 4.1 Implement the "Attended interaction permits sub-skill questions" contract — modify Phase 3a `idd-implement` invocation to build the args string conditionally, including `UNATTENDED MODE` directive only when interaction is `unattended`
- [x] 4.2 Modify Phase 3b spectra chain (`spectra-discuss`, `spectra-propose`, `spectra-apply`) the same way — drop all unattended overrides when interaction is `attended`
- [x] 4.3 Modify Phase 4 `idd-verify` invocation similarly — pass-through attended/unattended state
- [x] 4.4 Add inline comments at each sub-skill invocation point referencing this requirement so future maintainers understand why the conditional exists

## 5. Verify is the terminal phase regardless of mode

- [x] 5.1 Phase 6 report MUST not invoke `idd-close` under any resolved mode (verify is the terminal phase regardless of mode); explicit unit-of-test sample run captures this in the trace
- [x] 5.2 Update SKILL.md core principles section: replace the `Stop before close` bullet with a mode-agnostic phrasing that holds for both PR and direct-commit paths

## 6. No silent timeout on sub-skill questions

- [x] 6.1 Add explicit documentation in idd-all/SKILL.md core principles: "Attended mode assumes a user is in session — `idd-all` imposes no silent timeout on sub-skill questions"
- [x] 6.2 Search the existing skill body for any hidden timeout / abort logic that could fire mid-question; confirm none exists or remove if found

## 7. Documentation reflects two-mode contract

- [x] 7.1 Update `plugins/issue-driven-dev/skills/idd-all/SKILL.md` frontmatter — extend `description` to mention HITL mode and `argument-hint` to include `--no-pr` (documentation reflects two-mode contract)
- [x] 7.2 Update `plugins/issue-driven-dev/references/pr-flow.md` — append an `idd-all path resolution` section stating idd-all consumes `pr_policy` per the same algorithm as `idd-implement` (no behavioral divergence)
- [x] 7.3 Add two example usage traces in idd-all/SKILL.md examples section: one `(PR, unattended)` (regression of v2.40.0) and one `(direct-commit, attended)` (new HITL behavior)

## 8. Validation and regression

- [ ] 8.1 Hand-run a sample issue through `idd-all #N --pr` against a non-fork repo with `pr_policy: ask`; confirm PR is opened and behavior matches v2.40.0 trace **(deferred to user — requires live cross-repo run after plugin-update sync; tracked as post-merge smoke test)**
- [ ] 8.2 Hand-run a sample issue through `idd-all #N --no-pr`; confirm: no branch created, no PR, sub-skill `AskUserQuestion` calls fire normally, Phase 6 prints the direct-commit completion notice **(deferred to user — same reason as 8.1)**
- [ ] 8.3 Verify the IDD plugin's own `/loop` automation pathway (or any documented automation caller) still works when explicitly passing `--pr`; smoke-test on a synthetic issue **(deferred to user — `/loop` triggers an unattended pipeline, runnable only by user)**
- [x] 8.4 Run `spectra validate --changes idd-all-hitl-mode` and confirm zero errors; address any warnings — `spectra validate` PASS, `spectra analyze` Clean (0 findings)

## 9. Release

- [x] 9.1 Bump issue-driven-dev plugin version to `2.46.0` (corrected from spec's `2.41.0` since current baseline is v2.45.0; spec wording "PR path preserves v2.40.0 behavior" remains accurate — that's when PR-path-always was set, v2.41-v2.45 didn't change it)
- [x] 9.2 Update `plugins/issue-driven-dev/CHANGELOG.md` with v2.46.0 entry summarizing mode resolution, attended-mode contract, and migration note (pure additive — no breaking change)
- [x] 9.3 Sync marketplace.json + plugin.json descriptions per `common-release-flow.md` discipline; mention this change links PsychQuant/issue-driven-development#1
