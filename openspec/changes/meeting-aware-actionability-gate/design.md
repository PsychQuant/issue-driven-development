## Context

actionability gate（#316）是四個路由端（`idd-list`、`idd-all`、`idd-implement`、`idd-plan`）共用的「這張 issue 現在能不能動」判定，實作在 `plugins/issue-driven-dev/scripts/lib/actionability.sh`。它只看三個訊號：`### Complexity` 能不能解析成四個 tier 之一、有沒有 `parking-lot` label、`### Blocking` 是否非空。

meeting 類型（#57）比 gate 早三個月上線，規格明定 meeting 不產生 Simple／Plan／Spectra 判定，`/idd-plan` 要為它產出 Meeting Plan、不接 `/idd-implement`，`/idd-close` 另有 meeting 專屬 gate。gate 設計時沒有考慮這個類型，也沒有 issue type 這個輸入，於是 meeting Diagnosis 一律被判成 `complexity-unparseable` 或 `complexity-missing`。

約束：

- 判定邏輯只能有一份共用實作（actionability-gate 規格 "Single shared implementation of parsing and verdict"）
- 既有 Diagnosis 不需要遷移（"Existing diagnoses require no migration"），三份 frozen fixture 的判定逐筆不變
- 四份 gate block 由測試要求逐 byte 相同（`idd-all` 只把 `$N` 換成 `$NUMBER`）
- `idd-list` 的 blocked 群組標題、banner、footer 不得改變（"Blocked-state output is preserved"）
- type 的解析順序以 `/idd-diagnose` Step 1 為準

## Goals / Non-Goals

**Goals:**

- type=meeting 的 issue 能通過 gate，並被各呼叫端送到 meeting 的正確下一步
- `parking-lot` label 與 `### Blocking` 對 meeting issue 照樣生效
- issue type 解析只有一份實作，住在共用 helper
- `idd-update` 能把有 `## Meeting Plan` 的 issue 推到 `planning`
- 未傳新參數的呼叫行為與現在逐 byte 相同

**Non-Goals:**

- 不改 `/idd-diagnose` 的 meeting 分支與它寫出的 Diagnosis 格式
- 不改 `/idd-close` 的 meeting 專屬 gate
- 不在 unattended 模式自動產出 Meeting Plan（見決策「unattended 下 meeting 停在 diagnosed」）
- 不改 `idd-all` 的 SLUG 截斷行為（另案）
- 不處理 bug／feature／refactor／docs 的路由，它們的判定結果不變

## Decisions

### issue type 解析放進共用 helper（idd_issue_type）

新增 `idd_issue_type` 函式，四個呼叫端都呼叫它，不各自解析 label 或 body。

替代方案：呼叫端各自判 type 再短路（選項 a）。被否決：那會產生四份私有實作，正是 #298 → #316 收斂掉的「多份私有窄化」形狀，也違反「單一共用實作」規格。

### verdict 新增選填 --issue-type，未傳時行為不變

`idd_actionability_verdict` 新增選填的 `--issue-type`。未傳、或值不是 `meeting` 時，判定與現在完全相同；三份 frozen fixture 不帶這個參數跑，所以結果逐筆不變。

替代方案：把 type 設成必填。被否決：所有呼叫端與測試都要同時改，影響範圍變大，也無法用「不帶參數」證明向後相容。

### meeting 只略過 complexity 訊號，parking-lot 與 Blocking 照評

`--issue-type meeting` 時，`--complexity-exit` 仍必填並照常驗證（0／3／4／5），但不產生任何理由；`parking-lot-label` 與 `blocking-nonempty` 照常判定。

理由：meeting 也可能被人擱置或卡在外部，那兩個訊號的語意對 meeting 一樣成立；只有 complexity 這個訊號依規格對 meeting 不存在。

**verify r1 修正：豁免只在 Diagnosis 存在時成立。** exit 4 同時代表「Diagnosis 沒有 `### Complexity`」與「完全沒有受信任的 Diagnosis」。第一版把兩者一起略過，於是從未診斷過的 meeting 也被判為可動：`idd-plan` 會在沒有 Diagnosis 時寫 Meeting Plan，`idd-list` 會把新開的 meeting 移出 *Needs diagnosis*。verdict 因此新增 `--diagnosis-present yes|no`，由 consumer 依 `LATEST_DIAGNOSIS`（已過作者過濾）設定；`--issue-type meeting` 時必填，兩個預設值都不安全（`yes` 重開這個洞，`no` 讓豁免靜默失效）。非 meeting 時只驗證值、不影響判定。

### 不在 Complexity 寫 meeting 哨兵值

否決選項 (c)：讓 meeting Diagnosis 在 `### Complexity` 寫 `meeting`。它違反 meeting-issue-type 規格「不產生判定」，而且既有的 meeting Diagnosis 都要遷移，與「不需遷移」規格衝突。

### unattended 下 meeting 停在 diagnosed

`idd-all` 遇到 meeting 時：attended 送 meeting 版 `/idd-plan`；unattended 不跑 `/idd-plan`，停在 diagnosed，並在 Phase 6 的 Action items 記一條「meeting 需要有人在場跑 /idd-plan」。兩種模式都不進 implement、verify，也不開 PR。

理由：Meeting Plan 的價值是人核准的審議紀錄，unattended 沒有人可以核准。這是本 change 未經人確認的假設，已寫進 proposal，可以挑戰；若要改，只需改 `idd-all` 的分派列。

verify r1（#16）指出兩點，記在這裡供裁決：預設設定下 `idd-all` 一律是 unattended，所以 meeting 預設永遠不會自動走 `/idd-plan`；而 meeting 的 close gate 在沒有 plan 時會退回 Diagnosis 的 Phase C，plan 是選填。所以 Action item 與 `idd-implement` 的訊息改寫成「`/idd-plan` 或 `/idd-close`」，不再把 plan 寫成必要步驟；停在 diagnosed 的行為不變，留給 maintainer 決定。

### idd-list 不新增 meeting 群組

meeting 判定為 actionable 時，`idd-list` 照常列在 actionable 區，只把建議的下一步依 phase 改成 `/idd-plan`（`diagnosed`）或 `/idd-close`（已有 Meeting Plan）。`idd_actionability_group` 不改，blocked 群組的標題、banner、footer 都不動。

### gate block 機器行加 TYPE 欄位

四份 gate block 以相同改法加入 type 解析，機器行由 `gate #N: VEXIT= TIER= REASONS=` 改為 `gate #N: VEXIT= TIER= REASONS= TYPE=`，讓執行者在輸出裡看得到判定用的 type。

## Implementation Contract

**Behavior**

- type=meeting、沒有 `parking-lot` label、`### Blocking` 為空的 issue：gate 判為 actionable，不論 Diagnosis 的 Complexity 寫什麼或有沒有寫
- `idd-all`：attended 時送 meeting 版 `/idd-plan`；unattended 時停在 diagnosed 並記 Action item；兩者都不呼叫 `idd-implement`、`idd-verify`，不 push、不開 PR
- `idd-plan`：產出 Meeting Plan，不接 `/idd-implement`（既有規格行為，現在不再被 gate 擋）
- `idd-implement`：拒絕 meeting issue，訊息說明 meeting 不走 implement、下一步是 `/idd-plan` 或 `/idd-close`，不要求「修正 Diagnosis」
- `idd-list`：meeting 的 actionable 列建議 `/idd-plan`（phase `diagnosed`）或 `/idd-close`（已有 Meeting Plan）
- `idd-update`：最新的 phase-bearing comment 是 `## Meeting Plan` 時，phase 為 `planning`

**Interface**

- `idd_issue_type --labels <newline 分隔的 label 名> --body <issue body>` → stdout 印一個值：`bug`、`feature`、`refactor`、`docs`、`meeting` 或 `unknown`；exit 0
  - label 中恰好有一個 IDD type 名稱 → 回該值；有多個不同的 IDD type → 回 `unknown`
  - label 中沒有 IDD type → 讀 body 中位於 code fence 之外、行首為 `## Type` 的標題，取其後第一個非空行的開頭英文字（小寫比對）；是 IDD type 就回該值
  - 都沒有 → `unknown`
- `idd_actionability_verdict` 新增 `--issue-type <bug|feature|refactor|docs|meeting|unknown>`（選填）與 `--diagnosis-present <yes|no>`（`--issue-type meeting` 時必填；其他 type 只驗證、不影響判定；verify r1 加入）
- 呼叫端取得 labels 的方式：`jq -r '[.labels[].name] | join("\n")'`，來源是 gate block 已經抓好的 `ISSUE_JSON`

**Failure modes**

- `idd_issue_type` 的未知參數或缺值 flag → stderr 具名錯誤、exit 2（與 verdict 的參數錯誤同一形狀）
- `--issue-type` 的值不在上述六個之中 → stderr 具名錯誤、exit 2；呼叫端照既有規則把 exit 2 當成 gate 誤用（FATAL），不得當成 not-actionable
- 共用 helper 缺檔 → 沿用既有的 fail-loud 規則，不得退回私有解析

**Acceptance criteria**

- `scripts/tests/actionability-gate/test.sh` 全數通過，包括新加的 meeting 與 type 解析 assertion
- 三份既有 fixture 在不帶 `--issue-type`、或帶任何非 meeting 的 type（含 `--diagnosis-present yes|no`）時判定逐筆不變
- `--issue-type meeting` 但沒有 `--diagnosis-present`、或其值為空或不是 `yes`／`no` → stderr 具名錯誤、exit 2
- 新 fixture `meeting-routing.json` 的每一列判定與預期相同
- 四份 gate block 逐 byte 相同的既有 assertion 仍通過

**Scope**

- In scope：共用 helper、四份 gate block、四個呼叫端的 meeting 分派、`idd-update` 的 phase 表、`references/actionability-gate.md`、兩份規格的 delta、CHANGELOG 與版本號
- Out of scope：`/idd-diagnose` 與 `/idd-close` 的 meeting 行為、`idd-all` 的 SLUG 截斷、非 meeting 類型的路由

## Risks / Trade-offs

- [type 誤判成 meeting，一般 issue 跳過 complexity gate] → 預設回 `unknown`；只有 label 恰好一個 `meeting`，或沒有 type label 而 body `## Type` 明寫 meeting，才判為 meeting
- [四份 gate block 改不一致] → 既有的逐 byte 相同 assertion 會擋下
- [機器行格式變更影響讀這一行的人或工具] → 只在行尾加 `TYPE=` 欄位，既有欄位順序與名稱不變；reference 文件與測試一起更新
- [unattended 下 meeting 停在 diagnosed，使用者以為跑完了] → Phase 6 Action items 明確列出

## Migration Plan

不需遷移：新參數選填，既有 Diagnosis 與呼叫方式不變。回復方式是還原本 change 的 commit。
