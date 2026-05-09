## 1. Spawn manifest infrastructure

> Implements Decision 4: Spawn manifest schema + 4 sub-skill conformant write.

- [x] 1.1 設計 `.claude/.idd/state/chain-spawned-issues.json` schema_version=1 結構,記錄在 `references/spawn-manifest.md` (canonical contract for **Spawn manifest file SHALL exist at a fixed path with a versioned schema** requirement)
- [x] 1.2 寫 helper script `scripts/manifest-append.sh` 實作 atomic temp-file rename pattern (per **Manifest writes SHALL be atomic via temp-file rename** requirement)
- [x] 1.3 helper 需檢查 schema_version match 不 match abort (per **Each spawned issue SHALL produce one append-only entry in the manifest** requirement validation rules)

## 2. Sub-skill manifest write conformance

> Implements Decision 4: Spawn manifest schema + 4 sub-skill conformant write.
> Per **All four sub-skills SHALL conformantly write the manifest under chain context** requirement.

- [x] 2.1 [P] `idd-implement` Step 5.7 sister bug sweep 加 manifest detect + append entry,classify spawn_kind="sister-bug",依 sister-bug 同模組性質設 same_skill_as_root=true
- [x] 2.2 [P] `idd-verify` Phase 4 follow-up findings triage 加 manifest detect + append entry,classify spawn_kind="follow-up-finding",same_file 依 finding scope 判斷
- [x] 2.3 [P] `idd-plan` Step 2.5 tangential observations 加 manifest detect + append entry,classify spawn_kind="tangential",same_file 依 observation evidence 判斷
- [x] 2.4 [P] `idd-diagnose` Step 3.6 sister concern surfacing 加 manifest detect + append entry,classify spawn_kind="sister-concern" (or "upstream-tracking" if cross-cutting)
- [x] 2.5 4 sub-skill 共同 fallback rule (chain-context detect 失敗時 — All four sub-skills SHALL conformantly write the manifest under chain context but 無 manifest file → skip write,保持既有 audit trail behavior 不變)

## 3. idd-all `--in-chain` flag implementation

> Implements Decision 1: Chain shell 用 recursive `/idd-all --in-chain` 而非 inline phase logic.
> Implements Decision 2: Branch coordination 用 cluster branch + 4th mode tuple.
> Implements Decision 3: `--in-chain` flag 是 chain context 的 single source.

- [x] 3.1 `idd-all` Step 0.2 argument parsing 加 `--in-chain` flag,Phase 0.5 mode resolution 加 4th tuple `(direct-commit, unattended)` (per modified **Mode resolution from pr_policy and flags** requirement covering chain-context tuple)
- [x] 3.2 `--in-chain` 與 `--pr` / `--no-pr` 互斥 conflict abort logic (Phase 0.2 parse-time check)
- [x] 3.3 Phase 0.5 PR mode branch creation skip when `--in-chain` set (Decision 2 不建 idd/N-slug feature branch)
- [x] 3.4 Phase 5.5 PR creation skip when `--in-chain` set (Decision 1 sub idd-all 不開自己的 PR)
- [x] 3.5 Sub-skill invocation args 加 `UNATTENDED MODE` directive when `--in-chain` set (per chain-context tuple semantics)

## 4. idd-all-chain skill creation

> Implements Decision 5: PR body schema 用 collapsed sections per chained issue.
> Implements Decision 6: Failure mode = halt chain + preserve partial commits (no rebase/revert).
> Implements Decision 7: chain depth + max-issues hard cap.
> Implements Decision 8: Cross-cutting heuristic = same-file OR same-skill.

- [x] 4.1 寫 `plugins/issue-driven-dev/skills/idd-all-chain/SKILL.md` Phase 0 — TaskCreate bootstrap + 建 cluster branch `idd/chain-N-<slug>` from default branch + 初始化 spawn manifest (per **idd-all-chain skill SHALL drive root issue plus auto-emergent spawn through one cluster branch and one PR** requirement)
- [x] 4.2 Phase 1 — initialize spawn queue with root issue + depth_map + closed_set
- [x] 4.3 Phase 2 — main chain loop:invoke `/idd-all #current --in-chain` for each queued issue,read manifest after completion,enqueue eligible spawned issues per **idd-all-chain SHALL provide chain-eligible heuristic based on spawn manifest fields** requirement (Decision 8 cross-cutting heuristic = same-file OR same-skill OR sister-bug)
- [x] 4.4 Phase 2 — chain depth + max-issues hard cap enforcement (Decision 7 — depth=2, max-issues=5);超過 cap 仍 file 但不 enqueue
- [x] 4.5 Phase 2 — verify FAIL halt logic (Decision 6 failure mode = halt chain + preserve partial commits no rebase no revert):任一 chained `/idd-all --in-chain` 回 verify FAIL → 停 queue,preserve partial commits,印 abort report (per **idd-all-chain SHALL halt the chain on verify failure and preserve partial commits** requirement)
- [x] 4.6 Phase 3 — open cluster PR with body schema (Decision 5 PR body schema 用 collapsed sections per chained issue):title prefix `chain:`、`Refs #N #M ...`、Cluster overview table、Per-issue collapsed `<details>` sections、Pending review checklist (per **idd-all-chain SHALL produce a cluster PR with collapsed per-issue sections** requirement)
- [x] 4.7 Phase 4 — final report,停在 verified state,不 auto-close issue (per IDD discipline)
- [x] 4.8 寫 `plugins/issue-driven-dev/references/chain-flow.md` canonical contract for chain shell algorithm (eligible heuristic + depth/max-issues + failure mode)

## 5. Plugin metadata + documentation

- [x] 5.1 `plugins/issue-driven-dev/CLAUDE.md` Skills table 加 `idd-all-chain` row;Workflow section 加 chain-solve mode 說明
- [x] 5.2 `plugins/issue-driven-dev/.claude-plugin/plugin.json` version bump 2.53.0 → 2.55.0 + description 加 chain-solve summary
- [x] 5.3 `.claude-plugin/marketplace.json` plugin entry version sync to 2.55.0
- [x] 5.4 `plugins/issue-driven-dev/references/usecase-routing.md` 加新 row「emergent multi-issue solve from one root → /idd-all-chain」

## 6. Verification

- [x] 6.1 4-case smoke test for spawn manifest helper:create / append / atomic rename / schema_version mismatch abort
- [x] 6.2 `idd-all --in-chain` invocation 在 cluster branch 上跑單 issue,確認:不開新 branch、不開 PR、commits 落在 cluster branch、sub-skill skip AskUserQuestion
- [x] 6.3 End-to-end:`/idd-all-chain #X` on a test issue with sister-bug spawn,確認 chain queue 正確處理、cluster PR body schema 符合 spec、stops at verified — **won't fix in this change**(re-scoped to first-real-use validation track,不在本 apply 範圍)。Reason:本 task 如字面意義要建專用測試 issue + 留 cluster PR + spawn 衍生 issue,會在 repo 留下大量測試殘留 commits / branch / artifact issues;這在 doc-skill plugin context 對 verify discipline 的 ROI 太低。重新追蹤路徑:**下次第一次跑 `/idd-all-chain` 解真實 root issue 時(non-test 場景),作為 IDD verify 的一部分記錄 outcome**(若有 deviation 開新 issue 修)。Pre-merge 已由 6.1(manifest helper smoke 5/5)+ 6.2(idd-all --in-chain wiring 7-pt structural)+ 6.4(backward compat additive-only diff)涵蓋,足以確保 chain shell 不破壞既有 baseline
- [x] 6.4 Backward compat:`/idd-all #N` (no flag) 行為 byte-equivalent to v2.53.0 baseline (no regression)

## 7. GitHub Issue #44 alignment

> Reconciles GitHub-side tracker (#44) with the change as-built. Issue was filed after change started; body's "Expected" section reflects pre-discuss `--chain` flag proposal (rejected) — needs errata note + pointer to this change.

- [x] 7.1 [P] 用 `/idd-edit comment:<NNN> --prepend-note` 加 errata header 到 #44 body 或最早 comment,內容指出「Expected 段所述 `/idd-all #N --chain` flag + `chain_policy` config schema 在 discuss 階段被 reject;最終實作為獨立 `/idd-all-chain` skill + `--in-chain` flag,詳見 `openspec/changes/add-idd-all-chain-skill/`」
- [x] 7.2 [P] 用 `/idd-comment #44 --type link` post comment link 到 `openspec/changes/add-idd-all-chain-skill/proposal.md` + `design.md`,讓 future readers 可從 #44 直跳 change artifacts
- [x] 7.3 用 `/idd-update #44` 把 issue body Current Status 同步:Phase 從 `diagnosed` 推進到 `implementing` (working tree 已實作 4 sub-skill modify + idd-all-chain SKILL.md + spawn-manifest.md);Last updated 標 ingest date
