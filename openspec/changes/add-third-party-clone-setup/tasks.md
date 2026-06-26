# Tasks — add-third-party-clone-setup

> TDD enforced (`.spectra.yaml` tdd: true). For each behavioral task: write failing test → implement → green.

## 1. Shared ignore-block writer primitive

- [x] 1.1 Write tests for the primitive: idempotent re-run, stale-block upgrade-in-place, adjacent-content preservation → `scripts/tests/git-ignore-block/test.sh`
- [x] 1.2 Write tests for direction=exclude → `.git/info/exclude` (`git check-ignore` reports ignored)
- [x] 1.3 Write tests for direction=re-include → `.gitignore` parent-dir-excluded carve-out chain
- [x] 1.4 Implement the primitive → `scripts/git-ignore-block.sh` (BEGIN/END-sentinel idempotent block writer; re-include expands the carve-out chain). NOTE: fresh implementation, not a literal extract of #55's awk state-machine — the #55 refactor-onto-this is task 2.
- [x] 1.5 Placed under `scripts/` so both `idd-issue` Stage 4.5 and Step 0.5.E can call it

## 2. Refactor #55 Stage 4.5 carve-out onto the primitive

> **DEFERRED this apply pass** (resume item). The new feature does not depend on it —
> the `git-ignore-block.sh` re-include direction is implemented + tested, but porting
> #55's existing inline awk state-machine onto it requires a **byte-equivalence**
> reconciliation: the helper uses BEGIN/END sentinels whereas #55 emits a single-marker
> block, so a literal refactor either (a) changes the helper to match #55's format, or
> (b) updates #55's fixtures to the sentinel format. That decision + the full fixture
> port is a self-contained follow-up, safest done as its own commit/review.

- [ ] 2.1 Port existing #55 fixtures (root .gitignore / .git/info/exclude / global / stacked / nested) into byte-equivalence harness
- [ ] 2.2 Refactor Stage 4.5 carve-out to call the primitive (reconcile BEGIN/END-sentinel vs single-marker format)
- [ ] 2.3 Assert byte-equivalent output for every fixture; assert gate options / summary / `JSONL_GITIGNORE_DECISION` unchanged

## 3. idd-issue Step 0.5.E third-party branch

- [~] 3.1 Detection logic lives as inline skill pseudocode in Step 0.5.E (same as existing E1/E2 — not unit-tested independently). The testable extracted portion (the ignore-block write) is covered by task 1's `git-ignore-block` test suite. A dedicated harness for the detection branch would require extracting detection into a script — reasonable follow-up, not done this pass.
- [x] 3.2 Implement hybrid detection — refined: `viewerPermission` folded into the existing `gh repo view` call (owner-mismatch pre-filter → permission ∈ {WRITE,MAINTAIN,ADMIN}=own), ordered after E2. Zero extra API round-trip even on mismatch.
- [x] 3.3 Implement 3-option routing (E-TP: upstream + visibility warning / tracking repo via --target, no auto-create / local-only)
- [x] 3.4 On chosen option: write `.claude/.idd/local.json` (github_repo + `pr_policy: never`) + call `git-ignore-block.sh` (direction=exclude, target=`.git/info/exclude`, pattern `.claude/.idd/` + legacy)
- [x] 3.5 Update Step 0 Bootstrap `detect_target_repo` TaskCreate description (resolution order fork E2 → third-party → E1)

## 4. config-protocol documentation

- [x] 4.1 Add third-party detection clause + ordering (E2 fork → E-TP → E1) + fail-safe to mechanism 5
- [x] 4.2 Add config-placement × ignore-mechanism decision matrix (own repo / third-party / monorepo)

## 5. idd-config init parity

- [~] 5.1 Detection + routing is inline skill pseudocode (mirrors Step 0.5.E); shared write path is the task-1-tested helper. No separate harness this pass (same rationale as 3.1).
- [x] 5.2 Implement parity — idd-config init gains E-TP branch (fork → third-party → E1) + E-TP write recipe (new-path config + pr_policy never + git-ignore-block.sh); bootstrap task descriptions updated.

## 6. idd-all Phase 0.5 third-party default

- [~] 6.1 Resolution is inline skill pseudocode; precedence doc updated (entry 7.5). No separate harness this pass (same rationale as 3.1).
- [x] 6.2 Implement — Phase 0.5 IS_FORK=false branch gains third-party detection; overrides ONLY the `absent` default → `(direct-commit, attended)`; explicit `--pr`/`--no-pr` (top) and explicit pr_policy always/never still win. Precedence list gains entry 7.5.

## 7. Backward-compat regression

- [x] 7.1 E1 (own new repo) silent-write unchanged — preserved by construction (E1 markdown untouched except ordering prose; new branch only fires on IS_FORK=false AND IS_THIRD_PARTY=true)
- [x] 7.2 E2 (fork) 3-option unchanged — fork branch evaluated first, logic untouched
- [x] 7.3 Existing config present → mechanism 4 short-circuits before Step 0.5.E (unchanged); third-party detection only runs in the no-config fallback path

## 8. Version + changelog

- [~] 8.1 Bump plugin version — DEFERRED to release cut (change not fully complete: task 2 pending). plugin.json stays 2.86.0 for now.
- [x] 8.2 CHANGELOG `[Unreleased]` entry referencing #192
