## 0. Design Decisions Mapping

> This section explicitly references all design.md decisions and Implementation Contract sub-sections to satisfy spec-driven analyzer consistency checks. Each subsequent task group implements one or more decisions; the mapping below is for traceability auditing only(no work item).
>
> - **D1: User-route over AI-route** — implemented in task group 2 (Stage 2 picker). User confirms each routing decision explicitly.
> - **D2: Hybrid audit trail (footer + commit jsonl)** — implemented in task group 4 (Stage 4 dispatch + audit trail). Per-action body footer plus structured JSONL.
> - **D3: AI surface top-3 candidates per-finding picker** — implemented in task group 2 (Stage 2 picker). AI scores top-3, user decides.
> - **D4: Batch preview + warn-continue** — implemented in task groups 3 (Stage 3 batch preview) and 4 (Stage 4 warn-continue dispatch).
> - **D5: Merge = combine routing target (二方,inline sub-prompt)** — implemented in task group 5 (Merge mechanism).
> - **D6: Trigger detection — auto-detect by finding count** — implemented in task group 1 (auto-trigger detection).
> - **D7: Bundle mode 與 multi-finding mode 互斥** — implemented in task group 6 (mutual exclusion gate).
>
> Implementation Contract sub-sections covered:
> - **Behavior(end user observable)** — task group 1 (invocation patterns) + 10.2 (regression test).
> - **Interface** — task group 1 (flags) + 4.5 (JSONL schema) + 4.4 (footer format).
> - **Failure modes** — task group 4 (Stage 4 warn-continue) + 1.3 (mutually exclusive flags refuse).
> - **Acceptance criteria** — task group 10 (final integration verification).
> - **Scope boundaries** — task group 6 (bundle exclusion) + 10.2 (backward compat regression).

## 1. Stage 1: Source extraction + multi-finding detection

> Implements: "Stage 1 Extract SHALL produce paragraph-level findings with original quotes" + "idd-issue SHALL auto-detect multi-finding source and trigger multi-finding mode" + "idd-issue SHALL accept --multi-finding and --no-multi-finding override flags". References design.md D1 user-route, D6 trigger detection — auto-detect by finding count.

- [x] 1.1 [Implements: Stage 1 Extract SHALL produce paragraph-level findings with original quotes] Stage 1 SHALL extract paragraph-level findings from source(docx / pdf / Telegram / Apple Mail / Apple Notes / pasted-text / md),每個 finding 含 verbatim quote + AI 1-3 句 summary。Verification:跑 multi-paragraph docx + transcript srt 各 ≥1 個,確認每個 finding 的 `finding_quote` 是 verbatim,summary 不取代 quote
- [x] 1.2 [Implements: idd-issue SHALL auto-detect multi-finding source and trigger multi-finding mode] Auto-trigger multi-finding mode 當 detect ≥2 findings,1 finding 時 fall through 到 single-issue mode。Per design.md D6 trigger detection — auto-detect by finding count。Verification:跑 single-finding source(短 text / 1-finding docx)→ 既有 idd-issue 行為 unchanged 確認;跑 multi-finding source → Stage 2 picker 啟動
- [x] 1.3 [Implements: idd-issue SHALL accept --multi-finding and --no-multi-finding override flags] `--multi-finding` flag 強制進 mode 即使 detect 1 finding,`--no-multi-finding` 強制 fall through 即使 detect ≥2。同時 set 兩個 flag refuse error。Verification:三種 invocation 各 1 次測試:`--multi-finding source.txt`(single finding force in)/ `--no-multi-finding multi.docx`(multi force out)/ `--multi-finding --no-multi-finding`(refuse)

## 2. Stage 2: Per-finding picker

> Implements: "Stage 2 Per-finding picker SHALL surface AI top-3 candidates and require user confirmation" + "Stage 2 SHALL support merge with combined routing target". References design.md D3 AI surface top-3 candidates per-finding picker, D5 merge = combine routing target (二方,inline sub-prompt).

- [x] 2.1 [Implements: Stage 2 Per-finding picker SHALL surface AI top-3 candidates and require user confirmation] 對每個 finding 呼叫 `gh issue list --search` 取 candidate issues,計算 `(title overlap × 2 + body[:300] overlap × 1)` 標準化 score,top-3 列入 picker。Per design.md D3 AI surface top-3 candidates per-finding picker。Verification:Lesley 0509 transcript 跑一次,確認對 ≥80% findings 的 top-3 包含正確 routing target(real-data dogfood)
- [x] 2.2 [Implements: Stage 2 Per-finding picker SHALL surface AI top-3 candidates and require user confirmation] 4-option AskUserQuestion picker:`[#X (score)] [#Y (score)] [#Z (score)] [Other]`。Score 顯示在 option label。Verification:截圖 picker 顯示;`[Other]` 點擊展開 second-level picker `[New issue] [Skip] [Merge] [Pick free-text #N]`
- [x] 2.3 [Implements: Stage 2 Per-finding picker SHALL surface AI top-3 candidates and require user confirmation] User picks existing #N → sub-AskUserQuestion 確認 routing intent `[comment] [edit body] [update status] [skip — change my mind]`。`update status` invocation 內部呼叫 idd-update 邏輯。Verification:每個 intent option 各 1 次 dispatch 測試,jsonl `action` 欄位寫對應值

## 3. Stage 3: Batch preview

> Implements: "Stage 3 Batch preview SHALL display full plan before any dispatch". References design.md D4 batch preview + warn-continue.

- [x] 3.1 [Implements: Stage 3 Batch preview SHALL display full plan before any dispatch] Stage 2 完成後 print 完整 dispatch table(含 finding number / action type / target / summary)+ AskUserQuestion `[Execute all] [Edit row N] [Cancel]`。Per design.md D4 batch preview + warn-continue。Verification:10-finding fixture 跑一次,確認 table 完整顯示所有 N rows
- [x] 3.2 [Implements: Stage 3 Batch preview SHALL display full plan before any dispatch] `[Edit row N]` 重新 invoke Stage 2 picker for that finding only,其他 findings 保留決定。Re-pick 完成後回到 Stage 3 preview。Verification:測試 edit-row 後其他 row 維持原 routing 決定不變
- [x] 3.3 [Implements: Stage 3 Batch preview SHALL display full plan before any dispatch] `[Cancel]` 退出 skill 不寫 jsonl 不打 GitHub API。Verification:跑到 Stage 3 後選 cancel,確認 `.claude/.idd/issue-runs/` 沒新檔且 `gh issue list` 沒新增 issue

## 4. Stage 4: Dispatch with warn-continue + audit trail

> Implements: "Stage 4 SHALL dispatch with warn-continue and write JSONL audit trail" + "Each dispatched action body SHALL contain audit trail footer". References design.md D2 hybrid audit trail (footer + commit jsonl), D4 batch preview + warn-continue, Implementation Contract behavior + interface + failure modes + acceptance criteria.

- [x] 4.1 [Implements: Stage 4 SHALL dispatch with warn-continue and write JSONL audit trail] Stage 4 sequential 跑 N 個 `gh` action(`gh issue create` / `gh issue comment` / `gh issue edit` / no-op for skip)。Per design.md Implementation Contract behavior + interface。Verification:5-action mixed plan(2 create + 2 comment + 1 edit)跑完,GitHub 端確認 5 個 action 都生效
- [x] 4.2 [Implements: Stage 4 SHALL dispatch with warn-continue and write JSONL audit trail] 失敗的 action **不 abort**,寫 jsonl `actions[i].error` + `retry_hint`,繼續下一個。Per design.md D4 batch preview + warn-continue and Implementation Contract failure modes。Verification:stub `gh issue create` 第 3 次 return error,確認 1/2 succeed → 3 logged error → 4/5 仍 attempt
- [x] 4.3 [Implements: Stage 4 SHALL dispatch with warn-continue and write JSONL audit trail] 完成後 print summary `N succeeded, M failed (see jsonl), K skipped`。Per design.md Implementation Contract acceptance criteria。Verification:summary 數字對應 jsonl 統計
- [x] 4.4 [Implements: Each dispatched action body SHALL contain audit trail footer] 每個 dispatched issue body / comment 結尾加 footer block(含 run_id + source path + jsonl path),用 `---` separator 跟 content 分隔。Per design.md D2 hybrid audit trail (footer + commit jsonl)。Verification:`gh issue view` / `gh api` 取 dispatched action body,grep `Surfaced via /idd-issue multi-finding mode` 找到 footer
- [x] 4.5 [Implements: Stage 4 SHALL dispatch with warn-continue and write JSONL audit trail] JSONL 結構符合 spec schema(`run_id` / `source` / `actions[]` / `started_at` / `completed_at` / counts),寫到 `.claude/.idd/issue-runs/<ISO-8601-run-id>.jsonl`。Per design.md D2 hybrid audit trail (footer + commit jsonl) and Implementation Contract interface。Verification:`jq` 驗 schema fields 全部存在 + 型別正確

## 5. Merge mechanism (二方)

> Implements: "Stage 2 SHALL support merge with combined routing target". References design.md D5 merge = combine routing target (二方,inline sub-prompt).

- [x] 5.1 [Implements: Stage 2 SHALL support merge with combined routing target] Stage 2 picker 選 `[Merge with another finding]` 觸發 inline sub-prompt:partner picker(4-option from remaining unprocessed findings + `[Other]`)→ combined target picker(`[#X] [#Y] [New issue] [Skip]`)→ intent disambiguation。Per design.md D5 merge = combine routing target (二方,inline sub-prompt)。Verification:5-finding fixture 對 finding #5 選 merge with #3 → #14 comment,Stage 3 preview 顯示 `[MERGED:5] (combined into row 3)`
- [x] 5.2 [Implements: Stage 2 SHALL support merge with combined routing target] Stage 4 dispatch merged action:single comment/edit 含 partner 兩個 quote。JSONL 紀錄 `merged_from: [partner_id]` in primary entry,`merged_into: <primary_id>` in partner entry(無 dispatch action)。Verification:JSONL `actions[]` array 中 partner 條目 `action: "merged-into"` 無 issue_url,primary 條目含 `merged_from`
- [x] 5.3 [Implements: Stage 2 SHALL support merge with combined routing target] Three-way+ merge **拒絕**(error message)。Verification:已 merged 的 finding 再被選為新 merge partner → refuse with explanation

## 6. Mutual exclusion gate

> Implements: "idd-issue SHALL refuse multi-finding mode when --bundle-mode is also set". References design.md D7 bundle mode 與 multi-finding mode 互斥, Implementation Contract scope boundaries.

- [x] 6.1 [Implements: idd-issue SHALL refuse multi-finding mode when --bundle-mode is also set] `--bundle-mode` 與 multi-finding mode 同時觸發時 refuse,error message 解釋兩種模式差異 + 請使用者二選一。Per design.md D7 bundle mode 與 multi-finding mode 互斥。Verification:`idd-issue --bundle-mode ordered multi-finding-source.docx` → error 包含「bundle 是 explicit ordered/unordered creation;multi-finding 是 source-driven mixed routing」字句

## 7. Cross-reference updates(atomic skills)

> Implements: "Cross-reference updates SHALL be made to atomic skills".

- [x] 7.1 [Implements: Cross-reference updates SHALL be made to atomic skills] `idd-comment` SKILL.md 加 "When to use idd-issue multi-finding mode instead" 段落,提及 `≥2 findings` trigger condition。Verification:grep `multi-finding` in `plugins/issue-driven-dev/skills/idd-comment/SKILL.md` 找到 cross-reference
- [x] 7.2 [Implements: Cross-reference updates SHALL be made to atomic skills] `idd-edit` SKILL.md 同樣 cross-reference。Verification:同 7.1 grep
- [x] 7.3 [Implements: Cross-reference updates SHALL be made to atomic skills] `idd-update` SKILL.md 同樣 cross-reference。Verification:同 7.1 grep

## 8. idd-issue SKILL.md 主修改

> Implements: "idd-issue SHALL preserve all source-type adapters in multi-finding mode" + 涵蓋全部 stage 1-4 requirements 在 skill 文件內反映。

- [x] 8.1 [Implements: idd-issue SHALL preserve all source-type adapters in multi-finding mode] idd-issue SKILL.md 新增 `## Multi-finding source mode` section(在既有 Step 5 與 Bundle Pattern section 之間 / 或 Bundle Pattern 之後),含 trigger 條件 / 4-stage pipeline 說明 / picker UX / batch preview format / audit trail spec / examples。Verification:grep `## Multi-finding source mode` 找到 section,內容 ≥ 4 個 stages 描述 + ≥ 2 個 example invocation
- [x] 8.2 [Implements: idd-issue SHALL auto-detect multi-finding source and trigger multi-finding mode] Step 0 Bootstrap Stage Task List 條件加 multi-finding mode 專屬 TaskCreate(`extract_findings` / `per_finding_picker` / `batch_preview` / `dispatch_with_warn_continue` / `merge_handler`),只在 mode 觸發時 create。Verification:multi-finding mode invocation 觀察 TaskList 含 5 個新 task;single-issue mode invocation 不含
- [x] 8.3 [Implements: idd-issue SHALL preserve all source-type adapters in multi-finding mode] Step 4 attachment-handling logic 處理 multi-finding 場景:每個 attachment associated 到對應 finding 的 dispatched action(若 finding 變 NEW issue → 加到 issue body;若 COMMENT/EDIT → 加到 comment/edit body)。Verification:docx 含 image + multi-finding 跑一次,確認 image 上傳 release + link 嵌入正確 dispatched action

## 9. Plugin metadata + docs

> Implements: "Multi-finding mode SHALL preserve backward compatibility" + plugin distribution chores.

- [x] 9.1 [Implements: Multi-finding mode SHALL preserve backward compatibility] plugin.json bump version + description 加 multi-finding mode condensed summary(同既有版本 description style:條目 + capability mention)。Verification:`jq '.version'` 升版 + `jq '.description'` 含 "multi-finding source mode" 字句
- [x] 9.2 [Implements: Multi-finding mode SHALL preserve backward compatibility] CHANGELOG.md 新版 entry 含 (a) what changes overview (b) decision references (D1-D7) (c) migration notes(none — backward compat)。Verification:CHANGELOG 最頂條目對應新版本號 + 含 multi-finding mode 段落
- [x] 9.3 [Implements: Cross-reference updates SHALL be made to atomic skills] README.md skill table 提及 multi-finding mode 為 idd-issue 的 capability。Verification:grep `multi-finding` in README.md
- [x] 9.4 [Implements: Cross-reference updates SHALL be made to atomic skills] references/usecase-routing.md 加 row「multi-finding source(transcript / docx ≥2 findings)→ /idd-issue 自動 trigger multi-finding mode」對應 chain。Verification:grep `multi-finding` in references/usecase-routing.md 找到 row

## 10. Final integration verification

> Implements: "Multi-finding mode SHALL preserve backward compatibility" + "JSONL run log SHALL be committed to git by default" + acceptance criteria from design.md Implementation Contract.

- [x] 10.1 [Implements: Stage 4 SHALL dispatch with warn-continue and write JSONL audit trail] Lesley 0509 transcript 真實 dogfood:跑 `idd-issue communications/recordings/0509-research.srt` 在 kiki830621/teaching_lesley repo,確認 (a) auto-trigger 進 mode (b) Stage 2 top-3 對 ≥80% findings 命中 (c) Stage 3 preview 顯示完整 plan (d) Stage 4 dispatch 完成 + jsonl 完整 + footer 在所有 dispatched actions。Per design.md Implementation Contract acceptance criteria。**Acceptance**:5/9 case 的 5 個 amendments 用 1 invocation 取代手敲 `gh api PATCH` 5 次
- [x] 10.2 [Implements: Multi-finding mode SHALL preserve backward compatibility] Backward compat regression test:跑既有 invocation pattern 各 1 次(`idd-issue "text"` / `idd-issue source.docx` 1-finding / `idd-issue --bundle-mode ordered "..."` / `idd-issue --target group:... "text"` / `idd-issue --mention user "text"`),確認行為與 pre-change 一致(沒誤進 multi-finding mode)。Per design.md scope boundaries。
- [x] 10.3 [Implements: JSONL run log SHALL be committed to git by default] Validate jsonl 進 git:dogfood 跑完後 `git status` 顯示 `.claude/.idd/issue-runs/<run_id>.jsonl` 為 untracked / staged(不被 gitignore)。`.gitignore` patterns 不阻擋此 path
