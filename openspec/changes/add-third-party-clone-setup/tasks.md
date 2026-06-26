# Tasks — add-third-party-clone-setup

> TDD enforced (`.spectra.yaml` tdd: true). For each behavioral task: write failing test → implement → green.

## 1. Shared ignore-block writer primitive

- [x] 1.1 Write tests for the primitive: idempotent re-run, stale-block upgrade-in-place, adjacent-content preservation → `scripts/tests/git-ignore-block/test.sh`
- [x] 1.2 Write tests for direction=exclude → `.git/info/exclude` (`git check-ignore` reports ignored)
- [x] 1.3 Write tests for direction=re-include → `.gitignore` parent-dir-excluded carve-out chain
- [x] 1.4 Implement the primitive → `scripts/git-ignore-block.sh` (BEGIN/END-sentinel idempotent block writer; re-include expands the carve-out chain). NOTE: fresh implementation, not a literal extract of #55's awk state-machine — the #55 refactor-onto-this is task 2.
- [x] 1.5 Placed under `scripts/` so both `idd-issue` Stage 4.5 and Step 0.5.E can call it

## 2. Refactor #55 Stage 4.5 carve-out onto the primitive

- [ ] 2.1 Port existing #55 fixtures (root .gitignore / .git/info/exclude / global / stacked / nested) into byte-equivalence harness
- [ ] 2.2 Refactor Stage 4.5 carve-out to call the primitive
- [ ] 2.3 Assert byte-equivalent output for every fixture; assert gate options / summary / `JSONL_GITIGNORE_DECISION` unchanged

## 3. idd-issue Step 0.5.E third-party branch

- [ ] 3.1 Write tests: owner-mismatch + push=false → third-party; owner-match → E1 (no probe); owner-mismatch + push=true → E1; fork → E2 (no third-party); probe failure → fail-safe third-party
- [ ] 3.2 Implement hybrid detection (owner pre-filter → conditional push probe) inside the `IS_FORK=false` branch, ordered after E2
- [ ] 3.3 Implement 3-option routing (upstream + visibility warning / tracking repo via --target, no auto-create / local-only)
- [ ] 3.4 On chosen option: write `.claude/.idd/local.json` (github_repo + `pr_policy: never`) + call primitive (direction=exclude, target=`.git/info/exclude`, pattern `.claude/.idd/`)
- [ ] 3.5 Update Step 0 Bootstrap `detect_target_repo` TaskCreate description (resolution order fork E2 → third-party → E1)

## 4. config-protocol documentation

- [ ] 4.1 Add third-party detection clause + ordering to mechanism 5
- [ ] 4.2 Add config-placement × ignore-mechanism decision matrix (own repo / third-party / monorepo)

## 5. idd-config init parity

- [ ] 5.1 Write test: `/idd-config init` in third-party clone presents 3-option + writes config + exclude + pr_policy never
- [ ] 5.2 Implement parity (reuse Step 0.5.E detection + routing)

## 6. idd-all Phase 0.5 third-party default

- [ ] 6.1 Write test: third-party clone + no explicit pr_policy/flag → `(direct-commit, attended)` with third-party reason; explicit `--pr` still overrides
- [ ] 6.2 Implement third-party → `pr_policy: never` default in Phase 0.5 resolution precedence (below explicit flags, beside fork override)

## 7. Backward-compat regression

- [ ] 7.1 E1 (own new repo) silent-write unchanged — existing tests green
- [ ] 7.2 E2 (fork) 3-option unchanged — existing tests green
- [ ] 7.3 Existing config present → mechanism 4 short-circuits, no re-detection

## 8. Version + changelog

- [ ] 8.1 Bump `idd-issue` / `idd-config` / `idd-all` plugin version
- [ ] 8.2 CHANGELOG entry referencing #192
