## Context

IDD 已有就地更正的工具：`/idd-edit --correct`（#351）可以改自己寫的 comment 或 issue 正文的一個段落，舊版歸檔、可還原；`/idd-comment` 有 decision、note、errata、correction 等分類；`/idd-update` 管 Current Status。缺的是「討論中的改變寫回哪裡」的規則，而且有三處現行行為和 #424 的決定衝突：

1. `in-place-correction` 規定 `--correct` 要使用者確認（預設 NO），`idd-edit` Step 3 第 5 點照做。
2. 同一份 spec 規定偵測到錯誤的 skill（`idd-verify`、`idd-diagnose`、`idd-reorganize`）只列 `### Proposed Corrections`，unattended 時只列不做。
3. `idd-diagnose` Step 4 Stage 1 要調整診斷時用 `gh issue comment` 追加修正，而不是改 Diagnosis 本身。

#424 的決策紀錄：Diagnosis 的「決策」段（D1–D3）與 decision comment（五條假設，2026-10-25）。

## Goals / Non-Goals

**Goals:**

- 討論中的改變由 AI 判斷類別並寫回對的位置：問題 → issue 正文段落；診斷 → Diagnosis 段落與其相依紀錄；新資訊與決定 → 新的 comment。
- 改寫自己的內容不再停下來確認；每次寫回都在對話裡回報。
- 偵測到錯誤的 skill 直接套用更正，attended 與 unattended 一致。
- skill 之外的討論也套用（SessionStart 一行）。

**Non-Goals:**

- 即時觸發：不做 GitHub Action、webhook 或輪詢；別人的 comment 在下一次被讀到時才處理。
- 改寫別人的內容：別人的 comment 與 issue 正文永遠只用 errata 或 correction comment 回應。
- `--append`、`--replace` 的確認：維持現狀。
- 改 `Original text`：受保護區塊規則不動。
- 修改 helper（`idd-edit-helper.py`）：作者判斷沿用既有的 `validate-target ... --correct`。
- 機械化「這次改變屬於哪一類」：由 AI 判斷，不另設 gate。

## Decisions

### D1 `--correct` 不再確認，其餘安全步驟保留

`/idd-edit --correct` 只放行自己的內容（helper 的作者閘），舊版一律歸檔、可還原，所以拿掉確認不會讓錯誤變成不可逆。保留的步驟：diff 與預覽仍完整顯示（改為回報）、privacy 自審（`enforce` 命中就 discard）、#272 閘（reply 帶使用者貼來的第三方原話時仍要問）、apply 時重讀目標與比對預覽、歸檔。替代方案「使用者直接下指令時才確認」被否決：同一個指令兩種行為，讀 skill 的人分不清。

### D1b `--prepend-note` 只在自己的內容上不確認

D2 的 verify 報告註記要用 `--prepend-note`，但這個 mode 的作者閘會放行 OWNER 與 bot，而使用者是 repo ADMIN、GitHub 允許改別人的 comment。所以不確認的前提是目標通過 `validate-target <id> <repo> false --correct`（`--correct` 的嚴格作者判斷，exit 0 才算自己的內容）；不通過就照原本的確認流程。

### D2 verify 報告只加一行註記

診斷更正後，既有 verify 報告的 findings 不動，只用 `--prepend-note` 在開頭加一行「依據的診斷已於 YYYY-MM-DD 更正，見 <Diagnosis 連結>」。verify 報告記錄的是某個凍結 head 的驗證結果，改寫 findings 會讓它不再對應那個 head。Implementation Plan 是往前看的計畫，受影響的段落用 `--correct` 改寫。

### D3 規則放 plugin 層，SessionStart 加一行

討論大多發生在沒有 skill 執行的時候，只寫進 SKILL.md 碰不到。依 `rules-layering`，約束所有 IDD 使用者、主戰場在 skill 之外的規則放 plugin 層並加 SessionStart 注入。現有輸出 4 行（commit 紀律），加一行剛好 5 行，標題由「IDD commit 紀律」改為「IDD 紀律」；drift-guard 測試的 ≤5 行上限不變。替代方案「另開一支 hook」被否決：多付一份 context，還要另寫 drift guard。

### D4 偵測到錯誤的 skill 直接套用

`in-place-correction` 的「propose, not apply」改為「apply and report」。自己的內容走 `/idd-edit --correct`；別人的內容自動貼 errata 或 correction comment（屬全域規則「GitHub 紀錄不用問」的第 1 類）。報告段落由 `### Proposed Corrections` 改名 `### Applied Corrections`，每項寫目標、段落、錯在哪、結果（backup id、comment 連結，或拒絕原因）。替代方案「只有討論觸發的寫回不確認、偵測到的仍只列不做」被否決：兩套行為並存，#399 那種累積會繼續發生。

### D5 別人的 comment 在下一次讀取時觸發

沒有任何事件機制會在別人留言時叫醒 AI；IDD skill 本來就會在 diagnose、plan、verify、update 時讀 comments，使用者也可能在 session 裡談到這張 issue。這兩個時點就是觸發點。

## Implementation Contract

**行為（使用者看得到的）**

- session 裡討論一張 issue 時，AI 判斷改變屬於三類之一並寫回，不問；每次寫回在對話裡回報一行：類別、目標（`issue:N` 的段落或 `comment:<id>`）、連結，`--correct` 另附 backup id。
- `/idd-edit ... --correct`：顯示 diff 與預覽後直接 apply；privacy 自審命中 `enforce` 或使用者在 #272 題答否時 discard，finish 以 9 結束。
- `/idd-edit ... --prepend-note`：目標通過嚴格作者檢查時不確認；否則照舊確認。`--append`、`--replace` 照舊確認。
- `idd-verify`、`idd-diagnose`、`idd-reorganize` 的報告：`### Applied Corrections` 取代 `### Proposed Corrections`，unattended 也直接套用。
- `idd-diagnose` Step 4 Stage 1：使用者要調整診斷時，用 `/idd-edit comment:<Diagnosis id> --correct --section ...` 改寫，不追加 comment。
- SessionStart 輸出第 5 行提醒寫回規則。

**介面**

- 新檔 `plugins/issue-driven-dev/rules/issue-write-back.md`：三類分流表（封閉列舉）、觸發來源兩種（封閉列舉）、作者邊界、回報格式、privacy 自審、相依紀錄更新（Implementation Plan、verify 報告）。
- helper 介面不變；skill 用既有的 `validate-target <id> <repo> false --correct` 判斷自己的內容。

**驗收**

- `scripts/tests/issue-write-back/test.sh`：規則檔存在且含三類分流、兩種觸發、作者邊界、回報、privacy；SessionStart 輸出含寫回提醒且 ≤5 行；`idd-edit` Step 3 對 `--correct` 不再要求確認、`--prepend-note` 引用嚴格作者檢查；`idd-diagnose` Stage 1 用 `--correct`、不再寫「追加修正」。
- `scripts/tests/in-place-correction/test.sh`：三個偵測 skill 斷言 `### Applied Corrections`、`--correct`，並反向斷言不再含「只列不做」。
- `run-all-tests.sh` 全部通過。

**範圍**

- 範圍內：上列規則、hook、四個 SKILL.md、兩份測試、`append-vs-modify` 規則的對應說明、版本與文件。
- 範圍外：helper 程式、即時觸發、改寫別人的內容、`--append`／`--replace`。

## Risks / Trade-offs

- [AI 判斷錯類別，把新決定寫進正文] → 每次寫回都回報類別與目標；舊版歸檔，可用 `/idd-edit --restore` 還原。
- [不確認後，privacy 自審變成唯一的人工把關點之外的防線] → 自審仍在 apply 前執行，`enforce` 命中就 discard；gh-egress 的機械閘照常。
- [ADMIN 帳號可改別人的 comment] → 不確認的路徑一律先過 `--correct` 的嚴格作者檢查（D1b）。
- [verify 在飛時被改到 Diagnosis] → 寫回的是 issue 上的文字，不是 PR 的程式；verify 讀的 context 以啟動時為準，報告結束後才可能被加註記。
- [SessionStart 第 5 行是每個 session 的 context 成本] → 一行、指向規則檔，drift guard 鎖住上限。

## Migration Plan

- plugin 版本 3.7.0（3.6.0 已發布給 #399、#465）。
- 回滾：還原這個 change 的 commit 即回到「確認後才寫」；已寫回的內容都有歸檔或在 comment 歷史中。

## Open Questions

（none）
