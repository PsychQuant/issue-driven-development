## Context

actionability gate（#316）是四個路由端（`idd-list`、`idd-all`、`idd-implement`、`idd-plan`）共用的「這張 issue 現在能不能動」判定，實作在 `plugins/issue-driven-dev/scripts/lib/actionability.sh`。它只看三個訊號：`### Complexity` 能不能解析成四個 tier 之一、有沒有 `parking-lot` label、`### Blocking` 是否非空。

meeting 類型（#57）比 gate 早三個月上線，規格明定 meeting 不產生 Simple／Plan／Spectra 判定，`/idd-plan` 要為它產出 Meeting Plan、不接 `/idd-implement`，`/idd-close` 另有 meeting 專屬 gate。gate 設計時沒有考慮這個類型，也沒有 type 這個輸入，於是 meeting Diagnosis 一律被判成 `complexity-unparseable` 或 `complexity-missing`。

約束：

- 判定邏輯只能有一份共用實作（actionability-gate 規格 "Single shared implementation of parsing and verdict"）
- 既有 Diagnosis 不需要遷移（"Existing diagnoses require no migration"），三份 frozen fixture 的判定逐筆不變
- 四份 gate block 由測試要求逐 byte 相同（`idd-all` 只把 `$N` 換成 `$NUMBER`）
- `idd-list` 的 blocked 群組標題、banner、footer 不得改變（"Blocked-state output is preserved"）
- 決定路由的輸入不得來自 issue 作者能自由改寫的文字（gate 對 `## Diagnosis` 早就只信 OWNER／MEMBER／COLLABORATOR，理由相同）

## Goals / Non-Goals

**Goals:**

- type=meeting 的 issue 能通過 gate，並被各呼叫端送到 meeting 的正確下一步
- `parking-lot` label 與 `### Blocking` 對 meeting issue 照樣生效
- meeting 的判定只依受信任的 Diagnosis；`/idd-diagnose` 只在 type label 或受信任作者的本文宣告 meeting 時才寫進 `### Type`，所以 repo 成員以外的 issue 作者改本文不能讓 issue 變成 meeting
- `idd-update` 能把有 `## Meeting Plan` 的 issue 推到 `planning`
- 未傳新參數的呼叫行為與現在逐 byte 相同

**Non-Goals:**

- 不改 `/idd-diagnose` 的 meeting 分支與它寫出的 Diagnosis 格式。type 判定只改 meeting 這一項（見決策「本文的 meeting 只採信受信任作者」）；其他 type 如何從 label／本文判定仍屬 #385
- 不改 `/idd-close` 的 meeting 專屬 gate
- 不在 unattended 模式自動產出 Meeting Plan（見決策「unattended 下 meeting 停在 diagnosed」）
- 不改 `idd-all` 的 SLUG 截斷行為（#388）
- 不處理 bug／feature／refactor／docs 的路由，它們的判定結果不變

## Decisions

### meeting 的判定只看最新受信任 Diagnosis 的 `### Type`

新增 `idd_diagnosis_type <diagnosis>`：讀 Diagnosis 文字中 `### Type` 底下第一個非空行的開頭英文字，與 `### Complexity` 用同一支 section reader。呼叫端傳入的是 gate block 已經取得的 `LATEST_DIAGNOSIS`——最新一則、作者為 OWNER／MEMBER／COLLABORATOR 的 `## Diagnosis` comment。沒有這樣的 comment 時回 `none`。

這是 verify 第 4 輪之後的裁決（maintainer 2026-10-14）。前四輪用的是 `idd_issue_type`：先看 type label，沒有 label 時讀 issue 本文的 `## Type`。它有兩個無法靠補丁收斂的問題：

- 沒有 label 的 issue，type 來自 issue 作者可以隨時改寫的本文。作者可以在 maintainer 診斷之後把本文改成 meeting，關掉 Complexity 訊號（r4 #19）；也可以在 implement 跑完之後改，讓 `idd-all` 的 Phase 4／5 跳過 verify 與 push（r4 #35）。
- 本文的 `## Type` 要照 GitHub 的渲染判斷「看得見的那一個」。四輪 verify 每一輪都找到新的隱藏寫法（清單裡的 fence、各類 HTML block、setext heading、渲染器 tag 清單差異），reader 永遠追不完。

Diagnosis 的 `### Type` 是 `/idd-diagnose` 依模板寫的，comment 經作者過濾；Complexity 訊號本來就讀同一份文字。meeting 的 Diagnosis 依模板一定有 `### Type` / `meeting`（已在一張真實 issue 上查證：沒有 IDD type label，OWNER 寫的 Diagnosis 記 `meeting（…）`）。

作者過濾只保證「誰貼的」，不保證「`### Type` 的值從哪來」：`/idd-diagnose` 在沒有 type label 時照抄本文的 `## Type`。r5 #3 指出這條路——`/idd-all` 每次都重跑 `/idd-diagnose`，所以作者改本文之後的下一次 run 就會貼出一份 meeting 的受信任 Diagnosis。下一個決策把這個值的來源也收緊。

### 本文的 meeting 只採信受信任作者

`/idd-diagnose` Step 1 只在兩種情況把 `meeting` 寫進 `### Type`：issue 有 `meeting` type label；或沒有 type label、本文 `## Type` 宣告 meeting，且 issue 作者的 `author_association` 是 OWNER／MEMBER／COLLABORATOR（與 Diagnosis 過濾同一組）。依內容推斷不得產生 meeting；查不到 association 視同不受信任。外部作者要走 meeting，由維護者加 label——label 只有 triage 以上權限能加。

這是 r5 之後的裁決（maintainer 2026-10-15）。替代方案「接受殘餘、交給 #385」被否決：r4 裁決的前提是「issue 作者改不到」，這一步讓那個前提對 repo 成員以外的作者成立（成員本來就在信任集合內）。只收緊 meeting，因為 gate 只對 `meeting` 放寬（`idd_actionability_verdict` 只比對這個值）；其他 type 的判定不影響 gate，留在 #385。

替代方案：保留 `idd_issue_type` 並繼續補 reader（選項「維持設計」）。被否決，理由如上。`idd_issue_type` 在本 change 尚未發布，直接移除，連同它的 markdown reader。

### verdict 新增選填 --diagnosis-type，未傳時行為不變

`idd_actionability_verdict` 新增選填的 `--diagnosis-type <bug|feature|refactor|docs|meeting|unknown|none>`。值為 `meeting` 時不評 Complexity 訊號；未傳、或其他值時，判定與現在完全相同。三份 frozen fixture 不帶這個參數跑，也帶每一個非 meeting 的值跑，結果逐筆不變。

`meeting` 只可能來自存在的受信任 Diagnosis，所以 r1 的「沒有 Diagnosis 的 meeting 也被放行」不可能發生：沒有 Diagnosis 時值是 `none`，照常回報 `complexity-missing`。r1 加的 `--diagnosis-present` 因此不再需要，與 `--issue-type` 一起由這一個參數取代。

### meeting 只略過 complexity 訊號，parking-lot 與 Blocking 照評

`--diagnosis-type meeting` 時，`--complexity-exit` 仍必填並照常驗證（0／3／4／5），但不產生任何理由；`parking-lot-label` 與 `blocking-nonempty` 照常判定。

理由：meeting 也可能被人擱置或卡在外部，那兩個訊號的語意對 meeting 一樣成立；只有 complexity 這個訊號依規格對 meeting 不存在。

### 不在 Complexity 寫 meeting 哨兵值

否決選項 (c)：讓 meeting Diagnosis 在 `### Complexity` 寫 `meeting`。它違反 meeting-issue-type 規格「不產生判定」，而且既有的 meeting Diagnosis 都要遷移，與「不需遷移」規格衝突。`### Type` 已經記著 type，不必再造一個值。

### unattended 下 meeting 停在 diagnosed

`idd-all` 遇到 meeting 時：attended 送 meeting 版 `/idd-plan`；unattended 不跑 `/idd-plan`，停在 diagnosed，並在 Phase 6 的 Action items 記一條，下一步是 `/idd-plan` 或 `/idd-close`。兩種模式都不進 implement、verify，也不開 PR。

理由：Meeting Plan 的價值是人核准的審議紀錄，unattended 沒有人可以核准。maintainer 2026-10-14 確認維持。meeting 的 close gate 在沒有 plan 時退回 Diagnosis 的 Phase C，所以 plan 寫成選填。

### idd-all 的後續 phase 也只讀受信任的 Diagnosis

shell 狀態不跨 Bash 呼叫，所以 meeting unwind、Phase 4、Phase 5、Phase 6 要判斷 meeting 時都重新取得 type。來源一律是受信任 Diagnosis 的 `### Type`，不是 issue 本文：本文在執行中途可被作者改寫（r4 #35）。

### idd-list 不新增 meeting 群組

meeting 判定為 actionable 時，`idd-list` 照常列在 actionable 區，只把建議的下一步依 phase 改成 `/idd-plan`（非 `planning`）或 `/idd-close`（`planning`）。`idd_actionability_group` 不改，blocked 群組的標題、banner、footer 都不動。

### gate block 機器行加 TYPE 欄位

四份 gate block 以相同改法取得 Diagnosis type，機器行由 `gate #N: VEXIT= TIER= REASONS=` 改為 `gate #N: VEXIT= TIER= REASONS= TYPE=`，`TYPE` 印 Diagnosis type（七個值的封閉集合），讓執行者在輸出裡看得到判定用的 type。

## Implementation Contract

**Behavior**

- 受信任 Diagnosis 的 `### Type` 是 meeting、沒有 `parking-lot` label、`### Blocking` 為空的 issue：gate 判為 actionable，不論 Diagnosis 的 Complexity 寫什麼或有沒有寫
- 沒有受信任 Diagnosis 的 issue（含本文寫 meeting 的）：照常 `complexity-missing`，歸 undiagnosed
- `idd-all`：attended 時送 meeting 版 `/idd-plan`；unattended 時停在 diagnosed 並記 Action item；兩者都不呼叫 `idd-implement`、`idd-verify`，不 push、不開 PR；PR 模式把 diagnose 寫的 manifest commit 在 Phase 0.5 branch 上並保留（不 push），回到預設 branch
- `idd-plan`：產出 Meeting Plan，不接 `/idd-implement`
- `idd-implement`：拒絕可動的 meeting issue，訊息說明 meeting 不走 implement、下一步是 `/idd-plan` 或 `/idd-close`，不要求「修正 Diagnosis」
- `idd-list`：meeting 的 actionable 列建議 `/idd-plan`（非 `planning`）或 `/idd-close`（`planning`）
- `idd-update`：最新的 phase-bearing comment 是 `## Meeting Plan` 時，phase 為 `planning`

**Interface**

- `idd_diagnosis_type <diagnosis>` → stdout 印一個值：`bug`、`feature`、`refactor`、`docs`、`meeting`、`unknown` 或 `none`；exit 0
  - 參數為空（沒有受信任 Diagnosis）→ `none`
  - 讀 `### Type` section（與 `### Complexity` 同一支 reader）的第一個非空行，去掉開頭的 markdown 裝飾，取開頭英文字（ASCII 小寫比對，後接非字詞字元）；是 IDD type 就回該值，否則 `unknown`
  - 參數不是恰好一個 → stderr 具名錯誤、exit 2
- `idd_actionability_verdict` 新增 `--diagnosis-type <bug|feature|refactor|docs|meeting|unknown|none>`（選填）
- 呼叫端在 gate block 內 `DIAG_TYPE=$(idd_diagnosis_type "$LATEST_DIAGNOSIS")`，傳給 verdict，並印在機器行

**Failure modes**

- `--diagnosis-type` 帶空值、缺值，或值不在上述七個之中 → stderr 具名錯誤、exit 2；呼叫端照既有規則把 exit 2 當成 gate 誤用（FATAL），不得當成 not-actionable
- 共用 helper 缺檔 → 沿用既有的 fail-loud 規則，不得退回私有解析

**Acceptance criteria**

- `scripts/tests/actionability-gate/test.sh` 全數通過，包括 meeting 與 Diagnosis type 的 assertion
- 三份既有 fixture 在不帶 `--diagnosis-type`、或帶任何非 meeting 的值時判定逐筆不變
- 新 fixture `meeting-routing.json` 的每一列判定與預期相同，包括「本文寫 meeting、Diagnosis 寫 bug」不得放行
- 四份 gate block 逐 byte 相同的既有 assertion 仍通過

**Scope**

- In scope：共用 helper、四份 gate block、四個呼叫端的 meeting 分派、`idd-all` 的 meeting unwind 與 Phase 4／5／6、`idd-update` 的 phase 表、`/idd-diagnose` Step 1 對本文 meeting 的採信條件、`references/actionability-gate.md`、兩份規格的 delta、CHANGELOG 與版本號
- Out of scope：`/idd-diagnose` 的 meeting 分支與 Diagnosis 格式、`/idd-close` 的 meeting 行為、非 meeting type 的判定（#385）、`idd-all` 的 SLUG 截斷、非 meeting 類型的路由

## Risks / Trade-offs

- [type 誤判成 meeting，一般 issue 跳過 complexity gate] → 只有受信任 Diagnosis 的 `### Type` 明寫 meeting 才算；而 `/idd-diagnose` 只在 type label 或受信任作者的本文宣告時寫 meeting，所以 repo 成員以外的 issue 作者改不到
- [同一張 issue 同時有兩個 run，或受信任成員在 implement 之後貼出 meeting 的 Diagnosis] → `idd-all` Phase 4／5 讀到 meeting 時 fail-closed：不 verify、不 push，明講 commit 留在哪（r5 #11）
- [maintainer 改了 type label 但沒重新 diagnose] → gate 仍依舊 Diagnosis 判斷，直到重新 diagnose；與 Complexity 訊號的既有語意一致（Diagnosis 是判定的紀錄）
- [四份 gate block 改不一致] → 既有的逐 byte 相同 assertion 會擋下
- [機器行格式變更影響讀這一行的人或工具] → 只在行尾加 `TYPE=` 欄位，既有欄位順序與名稱不變；reference 文件與測試一起更新
- [unattended 下 meeting 停在 diagnosed，使用者以為跑完了] → Phase 6 Action items 明確列出

## Migration Plan

不需遷移：新參數選填，既有 Diagnosis 依模板已有 `### Type`，呼叫方式不變。回復方式是還原本 change 的 commit。

## verify 歷程（摘要）

- r1：豁免連「沒有 Diagnosis」也放行 → 加 `--diagnosis-present`（r4 後由 `--diagnosis-type` 取代）
- r2：unwind 只靠註解限定 meeting，會刪掉非 meeting 的 branch → 在 code 裡判斷；spec 殘留兩條無條件 scenario
- r3：spec 又一條無條件 scenario；spec 與保留 branch 的行為不一致
- r4：Deferral 的 parenthetical scenario 未限定；type 來自作者可改的本文（#19、#35）→ 改以受信任 Diagnosis 為準
- r5：`idd-all` 每次重跑 `/idd-diagnose`，而它照抄本文的 `## Type`，r4 #19 在這條路徑上沒有關閉（#3）→ `/idd-diagnose` 只採信受信任作者本文的 meeting
