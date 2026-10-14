## 1. 測試先行（RED）

- [x] 1.1 新增 fixture `plugins/issue-driven-dev/scripts/tests/actionability-gate/fixtures/meeting-routing.json`，列出 meeting issue 的組合（Complexity 不可解析／缺段 × 有無 `parking-lot` × Blocking 空與否），並在 `test.sh` 加 assertion：`idd_actionability_verdict --issue-type meeting` 對每列給出預期的 exit 與 reasons（對應 Requirement「Actionability gate evaluates three signals disjunctively」的 meeting scenario）。驗證：執行 `bash plugins/issue-driven-dev/scripts/tests/actionability-gate/test.sh`，新 assertion 因 `--issue-type` 尚未支援而失敗
- [x] 1.2 在 `test.sh` 加 `idd_issue_type` 的 assertion，涵蓋 spec 的 resolution table 六列，以及未知參數、缺值 flag 回 exit 2（對應 Requirement「Issue type resolution is part of the shared implementation」）。驗證：執行 `test.sh`，這些 assertion 因函式不存在而失敗
- [x] 1.3 在 `test.sh` 加回歸 assertion：三份既有 fixture（`corpus-complexity.json`、`corpus-blocking.json`、`parked-routing.json`）不帶 `--issue-type` 時判定逐筆不變，並另跑一次帶 `--issue-type bug` 確認結果相同（對應 scenario「Omitted issue type preserves the existing verdict」）。驗證：執行 `test.sh`，這組 assertion 現在就通過，作為後續修改的護欄

## 2. 共用 helper（GREEN）

- [x] 2.1 issue type 解析放進共用 helper（idd_issue_type）：在 `plugins/issue-driven-dev/scripts/lib/actionability.sh` 新增 `idd_issue_type --labels <newline 分隔> --body <text>`，依 design 的 Interface 回傳 `bug`／`feature`／`refactor`／`docs`／`meeting`／`unknown`，body 的 `## Type` 只認 code fence 之外、行首的標題，參數錯誤回 exit 2。驗證：1.2 的 assertion 全數轉綠
- [x] 2.2 verdict 新增選填 --issue-type，未傳時行為不變；meeting 只略過 complexity 訊號，parking-lot 與 Blocking 照評：`--complexity-exit` 仍必填並照常驗證，`--issue-type` 值不在六個之中時回 exit 2。驗證：1.1 的 assertion 轉綠，1.3 的回歸 assertion 仍綠

## 3. gate block 與呼叫端

- [x] 3.1 gate block 機器行加 TYPE 欄位：`plugins/issue-driven-dev/references/actionability-gate.md` 的 canonical gate block 與四份副本（`idd-implement` Step 0.35 與 Step 2.5、`idd-plan` Step 1、`idd-all` Phase 2）以相同改法加入 `ISSUE_TYPE=$(idd_issue_type …)`（labels 取自 `ISSUE_JSON`）、把 `--issue-type "$ISSUE_TYPE"` 傳給 verdict，機器行改為 `gate #N: VEXIT= TIER= REASONS= TYPE=`；同步更新 `test.sh` 的 canonical shape assertion。驗證：`test.sh` 的「gate block 逐 byte 相同」與「canonical shape」assertion 通過
- [x] 3.2 `idd-all`（Routing consumers honour the meeting type）：分派表加 meeting 列——attended 送 meeting 版 `/idd-plan`；unattended 下 meeting 停在 diagnosed，並在 Phase 6 Action items 記「meeting 需要有人在場跑 /idd-plan」；兩種模式都跳過 Phase 3a／3b、Phase 4 verify 與 Phase 5 push／PR。驗證：在 `test.sh` 加 grep assertion，確認 `plugins/issue-driven-dev/skills/idd-all/SKILL.md` 含 meeting 分派列、unattended 的 Action item 文字與 Phase 4 的 meeting skip
- [x] 3.3 `idd-plan`：Step 1 的 gate 表加 meeting 列——`TYPE=meeting` 且 VEXIT=0 時進入 meeting-adapted Plan，不再走 tier 分派。驗證：`test.sh` grep assertion 確認 `plugins/issue-driven-dev/skills/idd-plan/SKILL.md` 的 meeting 列存在
- [x] 3.4 `idd-implement`：gate 表加 meeting 列——拒絕並說明 meeting 不走 implement、下一步是 `/idd-plan` 或 `/idd-close`，不要求修正 Diagnosis。驗證：`test.sh` grep assertion 確認 `plugins/issue-driven-dev/skills/idd-implement/SKILL.md` 的訊息存在，且「gate 在建 branch 之前」的既有 assertion 仍通過
- [x] 3.5 [P] idd-list 不新增 meeting 群組：`plugins/issue-driven-dev/skills/idd-list/SKILL.md` Step 3.7 把 issue type 傳入 verdict，Step 5 對 actionable 的 meeting issue 依 phase 建議 `/idd-plan`（`diagnosed`）或 `/idd-close`（已有 Meeting Plan）。驗證：`test.sh` 既有的 blocked 群組標題、banner、footer 逐字 assertion 仍通過，新增的 meeting 下一步 assertion 通過

## 4. idd-update

- [x] 4.1 [P] Meeting Plan advances the phase to planning：`plugins/issue-driven-dev/skills/idd-update/SKILL.md` 的 phase 表加 `Meeting Plan` → `planning`，比對規則沿用其他標題的寬鬆比對。驗證：`test.sh` grep assertion 確認 phase 表與判斷依據兩處都列出 `## Meeting Plan`

## 5. 文件與發布

- [x] 5.1 `plugins/issue-driven-dev/references/actionability-gate.md` 補 meeting 一節：issue type 輸入、meeting 只略過 complexity 訊號、不在 Complexity 寫 meeting 哨兵值的理由，並引用 meeting-issue-type 規格。驗證：人工核對該節與 design 的 Decisions 一致，`test.sh` 通過
- [x] 5.2 `plugins/issue-driven-dev/CHANGELOG.md` 新增 3.3.1（Fixed：#383），`plugins/issue-driven-dev/.claude-plugin/plugin.json` 與 `.claude-plugin/marketplace.json` 的版本都改為 3.3.1。驗證：`jq -r .version` 兩處都印 `3.3.1`，CHANGELOG 最上方是 3.3.1
- [x] 5.3 執行 `plugins/issue-driven-dev/scripts/tests/` 底下全部 `test.sh`，確認沒有其他 drift guard 因 SKILL.md 改動而失敗。驗證：全部 suite exit 0

## 6. verify round 1 修正

- [x] 6.1 verdict 加 `--diagnosis-present yes|no`（meeting 必填）；五個 gate block 由 `LATEST_DIAGNOSIS` 設 `HAS_DIAGNOSIS`；沒有 Diagnosis 的 meeting 仍是 `complexity-missing`。驗證：fixture 兩列 undiagnosed meeting、run_block 兩種 stub、誤用四條
- [x] 6.2 `idd_issue_type`：fence 依開頭字元與長度關閉、≥4 空白不算 fence、略過 HTML 註解；label 在 LC_ALL=C 下 ASCII 小寫比對。驗證：11 條 pin
- [x] 6.3 `idd-all`：meeting 分派前 unwind Phase 0.5 branch；Phase 5 code guard；Phase 6 meeting report 與 Action item 重建（不靠 shell 狀態）；Action item 改為 plan 選填。驗證：8 條 pin
- [x] 6.4 `idd-implement` meeting 列只在 VEXIT=0；`idd-list` 依 phase `planning` 給 `/idd-close`、Step 3 fallback 認 `## Meeting Plan`；回歸檢查擴到三份 corpus；description v3.3.1。驗證：`test.sh` 797 passed

## 7. verify round 2 修正

- [x] 7.1 （blocking #4）meeting unwind 在 code 裡判斷 type；manifest commit 在 feature branch 並保留（#6）；只有沒有 commit、沒有 upstream 的空 branch 才刪；每個 git 步驟都檢查。驗證：行為測試在暫存 repo 跑三種情況
- [x] 7.2 Phase 5 type guard 移進 PR 分支、與 push 同一個 shell（#12、#5）；meeting report 補 `clear_unattended`（#9）；meeting Action item 只看 root、不受 Meeting Plan comment 影響、失敗時列出（#14、#28）；abort 表補列（#20）。驗證：行為測試 + pin
- [x] 7.3 （blocking #1／#7）spec delta 再補兩個 MODIFIED：Single shared implementation、Existing diagnoses require no migration；proposal／design 的 API 描述更新；回歸檢查涵蓋五種非 meeting type（2140 組）
- [x] 7.4 type reader：lone CR、info string 含反引號、type-1／type-6 HTML block、heading 只接受空白或 tab、type 字詞邊界；divergence 清單寫明方向。驗證：12 條 pin，預期值以 markdown-it 4.0.0 核對
- [x] 7.5 idd-list meeting 兩列改為真正的封閉列舉並更正 fallback 說法（#10、#16）；idd-plan 中止列補 meeting 版本（#23）。驗證：`test.sh` 1109 passed

## 8. verify round 3 修正

- [x] 8.1 （blocking #5）spec delta MODIFIED「Complexity tier extraction tolerates trailing rationale」，「Non-tier prefix is not routable」限定非 meeting；Deferral 兩條 scenario 同樣限定。以同一標準逐行掃過 canonical spec，沒有其他無條件的 complexity 理由句
- [x] 8.2 （blocking #1／#22）meeting-issue-type delta 改寫：PR 模式 commit manifest、保留 branch 不 push，只有沒有 commit 與 upstream 時才刪；新增 scenario
- [x] 8.3 type reader 改以 GitHub（cmark-gfm）為基準：type-6 清單去 `search` 加 `source`、補 type 3／4／5；backstop：body 不只一個 `## Type` 時 meeting → unknown；`_meeting_` 邊界；讀完整份 input（無 SIGPIPE）。驗證：12 條 pin，預期值以 `gh api markdown` 核對
- [x] 8.4 idd-all：unwind 驗 N、PATH_AXIS 遺失時明確失敗、branch 由 git 判斷、direct-commit 不 fetch、保留 branch 時說明怎麼處理；Phase 6 meeting item 用 `$N`、只在 phase diagnosed 且非 Step 0.5.1 擋下時列；Plan 預設文字；Step 0 task 清單。驗證：行為測試（unwind 7 情況、Phase 5 正向對照、Phase 6 四情況）
- [x] 8.5 idd-plan 對照表補 meeting 列、Next Step 補 meeting 例外；idd-list meeting 列寫明 tracker 優先；reference 機器行說明補 TYPE。驗證：`test.sh` 1135 passed

## 9. verify round 4 修正：type 改以受信任 Diagnosis 為準（maintainer 2026-10-14 裁決）

- [x] 9.1 spec：三訊號 requirement 定義「diagnosed meeting issue」並禁止從 label／本文取 type；Deferral 的 parenthetical scenario 限定非 meeting（r4 blocking #2／#5／#9）；ADDED requirement 改為「The meeting type is read from the latest trusted Diagnosis」；meeting-issue-type delta 改寫並加 scenario（本文被改寫不影響路由；undiagnosed scenario 限定，#11）。這次逐條檢查了 delta 自己的每個 scenario，不只 canonical spec
- [x] 9.2 helper：新增 `idd_diagnosis_type`（與 `### Complexity` 同一支 section reader）；verdict 以 `--diagnosis-type` 取代 `--issue-type` 與 `--diagnosis-present`；移除 `idd_issue_type` 與它的 markdown reader（r4 #19／#35 與 reader 一整類）。驗證：fixture 10 列、Diagnosis type 12 條、誤用與舊旗標、三份 corpus × 6 個非 meeting 值（1284 組）
- [x] 9.3 五個 gate block 改為 `DIAG_TYPE=$(idd_diagnosis_type "$LATEST_DIAGNOSIS")`；gate block 實跑加「本文改成 meeting、Diagnosis 寫 bug → 仍被擋」
- [x] 9.4 idd-all：unwind、Phase 5、Phase 6 改讀受信任 Diagnosis；unwind 先判 type 再要求 PATH_AXIS（#3／#8）、direct-commit 說明 manifest（#26）、kept-branch 據實描述並提醒重跑會停在 Phase 0.5（#17／#25）；Phase 6 只排除 blocked 行（#4）、遺失狀態要列（#12）、phase 非 diagnosed 的提示（#16）；Phase 5 註解（#20）；Next Step、task 清單、idd-plan description（#14）。驗證：行為測試，含撇號造成的語法錯誤被實跑抓到
- [x] 9.5 reference meeting 一節與 contract 表（#22）；版本 3.3.1 → 3.4.0（新增 helper 與旗標，#34；5.2 的 3.3.1 由此取代）；CHANGELOG 3.4.0。驗證：`test.sh` 853 passed

## 實作備註

- NOTE（1.3）：任務寫「現在就通過」，實際上帶 `--issue-type bug|unknown` 的回歸 assertion 在 2.2 之前是 RED——當時 verdict 不認得這個參數（exit 2）。2.2 之後全綠，行為正確；只是任務描述的預期與當時實況不同。
- NOTE（5.3）：在作者的 clone 上 `plan-routing-consistency` 失敗 1 項，命中的是 gitignore 的本機 `.spectra/snapshots/2026-05-10-add-idd-all-chain-skill/…/spec.md`（2026-05-04 的本機檔）。乾淨的 `origin/main` worktree 放進同一份 `.spectra/` 也失敗，所以這是既有問題，已有 #335 追蹤：該測試以 `grep -r` 掃整棵樹，連 ignored 檔也掃到。本分支在不含本機 `.spectra/` 的 worktree 跑：22 passed／0 failed。不在本 change 範圍內修。
