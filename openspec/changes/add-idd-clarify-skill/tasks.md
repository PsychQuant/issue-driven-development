## Phase 1: Skill Implementation

- [x] T1. 建 `plugins/issue-driven-dev/skills/idd-clarify/SKILL.md` — primitive skill 完整實作
   - Step 0 Bootstrap stage TaskCreate batch(scan_body / detect_terminology / detect_ambiguity / detect_missing_context / compose_block / patch_body / parse_status_arg / update_row_status / report_and_stop)
   - Behavior 1 主流程(per spec idd-clarify-skill scenario): read issue → load `references/terminology-canonical.md` → scan body 三類 marker → compose `### Clarity Surface(idd-clarify run <ISO>)` block → PATCH body via `gh issue edit`
   - Behavior 2 `--status <action>=<row_idx>[,<reason>]` flag 解析 + per-row update + invalid index actionable error + dismissed→resolved transition with history preservation
   - Library reload-per-invocation(no cache)+ IC_R007 verbatim preservation guard(不 touch blockquote)
   - Empty surface 也 emit passed marker row(避免 missing-block 跟 not-yet-run 歧義)

- [x] [P] T2. 建 `plugins/issue-driven-dev/references/terminology-canonical.md` — initial seed library
   - 6 rows from #135 body + #804 incident(per design D4):特徵值 / PCA-K-means / 回歸-ANOVA / 準確率-regression / P值-Bayesian / 分群-classification
   - Document rule-of-three promotion threshold(同 misuse 3 次升格)
   - Document open PR contribution flow + future plugin-level extension placeholder(未實作但描述)
   - File header normative comment block citing MP102-style binding(per IDD MANIFESTO category)

## Phase 2: Existing Skill Patches

- [x] T3. Patch `plugins/issue-driven-dev/skills/idd-issue/SKILL.md` — 加 Step 4.6 Clarity Surface auto-delegate
   - Insert Step 4.6 section between 現有 Step 4.5 Milestone(line 807-)跟 Step 4.7 Linked-Context Sister Sweep(line 831-)
   - 加 Step 0 Bootstrap TaskCreate entry:`TaskCreate(name="clarity_surface", description="Step 4.6: delegate to /idd-clarify $NEW_ISSUE_NUMBER per IC clarity axis")` 插入 milestone 跟 sister sweep task 之間
   - 加 trigger predicate logic:source ∈ {doc, pasted-text} AND NOT `--multi-finding` mode → delegate
   - 加 failure-handling block:`/idd-clarify` 呼叫失敗 → emit warning to stderr + 寫 `### Clarity Surface (deferred — see retry hint)` placeholder + continue to Step 4.7
   - 更新 Files Bound section(若 existing)+ DOC_R009 三層同步說明

- [x] T4. Patch `plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md` — 加 Step 0.5 Clarity Surface PR Gate
   - Insert Step 0.5 section between 現有 Step 0 Bootstrap 跟 Step 1 Read Issue
   - 加 Step 0 Bootstrap TaskCreate entry:`TaskCreate(name="clarity_gate_check", description="Step 0.5: grep issue body for ### Clarity Surface unresolved rows; refuse if any per IC clarity axis hard-refuse rule")` 插入 read_issue task 之後(因 Step 0.5 需 body 資料,但 Step 0.5 自己讀;ordering 概念上 read_issue 之後)
   - 加 grep + count + REFUSE structured message 邏輯:body has `### Clarity Surface` block AND any row Status=surfaced → exit non-zero with actionable guidance
   - 加 backward compat scenario:body 無 `### Clarity Surface` block → log `[Step 0.5] no Clarity Surface block found (legacy issue — pre-v2.71.0)` + proceed to Step 1
   - 加 unattended mode contract reference:link 到 sister #137,標 `(unattended contract deferred to sister #137; current behavior: fail-fast)`
   - 更新 Files Bound section + DOC_R009 三層同步

## Phase 3: Documentation

- [x] [P] T5. Migrate #135 conversation chain into `openspec/changes/add-idd-clarify-skill/discussion.md`
   - Quote v1 → v2 → v3 → v4 design iteration chain(per design.md Context section recursive-evidence)
   - Quote 4 Open Questions + their Resolution(per design.md Open Questions section Q1-Q4)
   - Cite #135 + #136 + #137 + #138 cross-link
   - Cite #804 K-means 特徵值 incident as triggering case study

- [x] [P] T6. Patch `plugins/issue-driven-dev/README.md`
   - 加 row 進 Skills matrix:`idd-clarify` standalone primitive + delegated-by idd-issue Step 4.6 / gated-by idd-diagnose Step 0.5
   - 加 changelog row(per existing v2.53.0 / v2.54.0 row pattern):`v2.71.0 | 2026-05-22 | /idd-clarify terminology trust gap skill (#135 v4 composable primitive) ...`

- [x] [P] T7. Patch `plugins/issue-driven-dev/MANIFESTO.md`
   - 加 三軸 framing 段落(confidence / verbatim / terminology)到 quality-axis section(若無則新建 section)
   - Cite #135 design comment 三軸表格 + recursive evidence 段落
   - Cross-link 到 sister #136 (idd-edit/idd-update symmetry) + #137 (unattended contract)

## Phase 4: Validation + Versioning

- [x] T8. Bump plugin minor version in `plugins/issue-driven-dev/plugin.json`
   - Current(check) → v2.71.0(minor bump — new skill = backward compat additive)
   - 更新 plugin description 加 idd-clarify

- [~] T9. Self-test:跑 `/idd-clarify <existing-issue-#N>` against ai_martech_global_scripts #804(或 fixture issue) — **deferred to post-merge smoke**
   - 驗證 6 個 seed pattern 至少 detect 「特徵值 + K-means context」這一條(real-data integration smoke)
   - 驗證 `--status dismissed=N` 跟 `--status resolved=N` 都正確 PATCH
   - 驗證 dismissed → resolved transition 保留歷史
   - **Skip reason**: requires plugin reload — Claude Code session 載入的是 pre-merge plugin version,新 skill 檔案在 disk 但 runtime 尚未 wire。post-merge `claude plugin update issue-driven-dev` 後 user 手動 smoke。本 PR 保留 SKILL.md 內 4 個 Example sections 作為手動 smoke test plan。

- [~] T10. Self-test idd-issue Step 4.6:跑 `/idd-issue` 對 doc source(fixture .docx) — **deferred to post-merge smoke**
   - 驗證 new issue body 末段含 `### Clarity Surface` annotation block
   - 驗證 `--multi-finding` mode 跑同 source 時 skip Step 4.6
   - 驗證 idd-clarify fail simulation(temp rename library file)→ deferred placeholder 寫入
   - **Skip reason**: 同 T9 — Step 4.6 是 SKILL.md prose patch,需 plugin reload 後 idd-issue 才會 delegate 新 step。手動 smoke per spec idd-issue-clarity-step scenarios。

- [~] T11. Self-test idd-diagnose Step 0.5:跑 `/idd-diagnose <N>` — **deferred to post-merge smoke**
   - Against issue with surfaced row → exit non-zero with REFUSE message
   - Against issue with all dismissed → proceed normally
   - Against legacy issue (no block) → proceed normally with log line
   - **Skip reason**: 同 T9 — Step 0.5 是 SKILL.md prose patch。手動 smoke per spec idd-diagnose-clarity-gate scenarios(4 個 Behavior scenarios + backward compat scenario)。

## Phase 5: Cross-co Verify(per IC_P002 commercial consumer impact)

- [x] T12. IC_P002 cross-consumer check
   - `kiki830621/ai_martech_global_scripts`:既有 issue 全 legacy(無 Clarity Surface block)→ Step 0.5 proceed,無 break
   - 5 公司 consumer(QEF_DESIGN / D_RACING / MAMBA / WISER / kitchenMAMA):本 PR 不 touch shared code,只動 IDD plugin own files,unaffected
   - Commit message 加 `Verified:` trailer 列驗證 scope
