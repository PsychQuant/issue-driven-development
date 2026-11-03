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
- 修改 helper 的作者判斷：沿用既有的 `validate-target ... --correct`。（第 1 輪後 helper 只加 `--note`、`discard --reason` 與路徑閘清單。）
- 機械化「這次改變屬於哪一類」：由 AI 判斷，不另設 gate。

## Decisions

### D1 `--correct` 不再確認，其餘安全步驟保留

`/idd-edit --correct` 只放行自己的內容（helper 的作者閘），舊版歸檔在執行它的那份 clone，GitHub 的編輯歷史也保留每個舊版，所以拿掉確認不會讓錯誤變成不可逆。保留的步驟：diff 與預覽仍完整顯示（改為回報）、privacy 自審（任何等級命中都停，見 D6）、#272 閘（reply template 帶使用者貼來的第三方原話時仍要問）、apply 時重讀目標與比對預覽、歸檔。替代方案「使用者直接下指令時才確認」被否決：同一個指令兩種行為，讀 skill 的人分不清。

### D1b `--prepend-note` 只在自己的內容上不確認

D2 的 verify 報告註記要用 `--prepend-note`，但這個 mode 的作者閘會放行 OWNER 與 bot，而使用者是 repo ADMIN、GitHub 允許改別人的 comment。所以不確認的前提是目標通過 `validate-target <id> <repo> false --correct`（`--correct` 的嚴格作者判斷，exit 0 才算自己的內容）；不通過就照原本的確認流程。

### D2 verify 報告只加一行註記

診斷更正後，既有 verify 報告的 findings 不動，只用 `--prepend-note` 在開頭加一行「依據的診斷已於 YYYY-MM-DD 更正，見 <Diagnosis 連結>」。verify 報告記錄的是某個凍結 head 的驗證結果，改寫 findings 會讓它不再對應那個 head。Implementation Plan 是往前看的計畫，受影響的段落用 `--correct` 改寫。

### D3 規則放 plugin 層，SessionStart 加一行

討論大多發生在沒有 skill 執行的時候，只寫進 SKILL.md 碰不到。依 `rules-layering`，約束所有 IDD 使用者、主戰場在 skill 之外的規則放 plugin 層並加 SessionStart 注入。現有輸出 4 行（commit 紀律），加一行剛好 5 行，標題由「IDD commit 紀律」改為「IDD 紀律」；drift-guard 測試的 ≤5 行上限不變。替代方案「另開一支 hook」被否決：多付一份 context，還要另寫 drift guard。

### D4 偵測到錯誤的 skill 直接套用

`in-place-correction` 的「propose, not apply」改為「apply and report」，範圍收窄到 D7 列的段落。自己的內容走 `/idd-edit --correct`；別人的內容只列出，attended 報告貼出後才問要不要貼 errata（使用者 2026-10-25 同意的是「自己的內容直接套用」，通知寄出就收不回）。報告段落由 `### Proposed Corrections` 改名 `### Applied Corrections`，每項寫目標、段落、錯在哪、結果（backup id、comment 連結，或拒絕原因）。替代方案「只有討論觸發的寫回不確認、偵測到的仍只列不做」被否決：兩套行為並存，#399 那種累積會繼續發生。

### D5 別人的 comment 在下一次讀取時觸發

沒有任何事件機制會在別人留言時叫醒 AI。`idd-diagnose`、`idd-plan`、`idd-update` 執行時用 `scripts/writeback-candidates.py` 列出別人的新 comment，使用者也可能在 session 裡談到這張 issue；這兩個時點就是觸發點。`idd-update` 在每個階段結束都會跑，所以幾乎每次都讀得到。`idd-verify` 不跑這一步：驗收中不該改驗收依據。

### D6 不問的路徑上，隱私命中一律停；只限有寫入權的 repo（verify 第 1 輪）

`privacy-scrubbing` 的 `warn`「default proceed」成立的前提是後面還有人工確認，D1 拿掉確認後就沒有人攔了。所以不問的路徑上，語意自審在任何等級命中都停：attended 問，unattended 捨棄。自己的 public repo 是 `warn`，而外流代價不對稱（通知已寄出、編輯歷史公開）。沒有寫入權的 repo 與查不到權限時（helper 判為 `enforce`）回到確認流程。

### D7 信任邊界、驗收條件、定案門檻、可見文字（2026-11-03 維護者決定，comment 6600258374）

- **來源**：只有 OWNER、MEMBER、COLLABORATOR 的 comment 能導致寫回，事實主張 AI 要自己查證；其他人的只告訴使用者。否則外人的話會以維護者署名進入 Diagnosis，繞過 #383 的作者過濾。`### Type`、`### Complexity` 不由 comment 改。
- **偵測 skill**：只改 Diagnosis 的 `### Root Cause / Analysis`、`### Impact`、`### Risks`，主 agent 親自用 repo 證據查證。`## Expected`、`### Strategy`、checklist 是驗收依據，verify 不能動自己的判準。
- **定案**：只有明確定案才算改變，假設與提問不算。已關閉的 issue 不改，避免和 Closing Summary 對不起來。
- **可見文字**：`--correct` 由 helper 固定加一行 `_更正於 YYYY-MM-DD（AI 判斷）：原因_`。放在 helper 而非規則，才不會忘；原因寫正確內容，不重述錯的值。GitHub 編輯不寄通知，標記又看不見，沒有這行，讀者無從知道。

### D9 verify 只列；自動更正限 bug、只改 Diagnosis（verify 第 2 輪，2026-11-03 維護者決定）

feature issue 的 `### Root Cause / Analysis` 就是需求拆解，而 verify 查證用的「repo 內的證據」正是受驗的 code，自動更正會變成「把 Diagnosis 改得符合 code」。所以 `idd-verify` 不改任何東西，已發表內容的錯誤一律是 finding；`## Expected`、範圍、checklist、Type、Complexity 的錯誤是 Blocking。`idd-diagnose`、`idd-reorganize` 只在 `### Type` 是 bug、issue 開著時改自己 Diagnosis 的三段，證據取自預設分支；Implementation Plan、前提被推翻的情況都列出。交給人的 `listed` 經 `idd-update` 進 `### Blocking`，既有的 actionability gate 就會停下 unattended 的 run，不另造機制。

### D10 「定案」寫成封閉列舉

第 2 輪指出「明確定案」只靠一句總括判準，無法查核。改成兩類封閉列舉（使用者在 session 說要改或說定了；受信任作者的 decision comment 或明說定案），每次回報寫依據（使用者原話或 comment 連結），寫回一律帶 `--note`。不做 Likert 評分：這是二元判斷，錯了的後果由可見文字與編輯歷史承接。

### D8 實作後的更正走 idd-reorganize

更正讓既有實作的前提不成立，或問題改變時，只改文字會留下 PASS 與舊的 phase。`idd-reorganize` 本來就處理下游枚舉與退 phase，不另造機制。Spectra tier 的 artifact 也由它處理。

## Implementation Contract

**行為（使用者看得到的）**

- session 裡討論一張 issue 時，AI 判斷改變屬於三類之一並寫回，不問；每次寫回在對話裡回報一行：類別、目標（`issue:N` 的段落或 `comment:<id>`）、連結，`--correct` 另附 backup id。
- `/idd-edit ... --correct`：顯示 diff 與預覽後直接 apply，改寫段落尾留一行可見文字；隱私自審只看這次加入的文字，`enforce`、`warn` 命中、`light` 下新加入的第三方逐字內容、或 #272 題沒確認時不寫（attended 問，unattended 捨棄），finish 以 9 結束並寫出原因。沒有寫入權的 repo 照舊確認。
- `/idd-edit ... --prepend-note`：目標通過嚴格作者檢查時不確認；否則照舊確認。`--append`、`--replace` 照舊確認。unattended 下任何問題都改成捨棄。
- `idd-verify`、`idd-diagnose`、`idd-reorganize` 的報告：`idd-verify` 只列成 finding；`idd-diagnose`、`idd-reorganize` 的 `### Applied Corrections` 取代 `### Proposed Corrections`，只限 bug、只改 D7 列的段落，其餘列出不改；unattended 相同。
- `idd-diagnose` Step 4 Stage 1：使用者要調整診斷時，用 `/idd-edit comment:<Diagnosis id> --correct --section ...` 改寫，不追加 comment。
- SessionStart 輸出第 5 行提醒寫回規則。

**介面**

- 新檔 `plugins/issue-driven-dev/rules/issue-write-back.md`：三類分流表（封閉列舉）、觸發來源兩種（封閉列舉）、作者邊界、回報格式、privacy 自審、相依紀錄更新（Implementation Plan、verify 報告）。
- helper：`run-start` 接受 `--note`（只限 `--correct`）；`discard` 接受 `--reason held-privacy|held-272|held-unattended`；`--body-file` 路徑閘多擋 `.netrc`、shell 歷史、`.claude.json`、`.claude/projects`。新 script `scripts/writeback-candidates.py --repo <r> --issue <n>`：每列 `TRUSTED|UNTRUSTED <comment id> <login> <association>`，截止點是你自己最新的 Diagnosis、Implementation Plan、Implementation Complete 的 `updated_at` 往前一天，比 comment 的 `updated_at`；bot 一律 UNTRUSTED；抓不到回 1。

**驗收**

- `scripts/tests/writeback-candidates/test.sh`（fake gh）：信任分類、自己的不列、日期截止、關閉的 issue、抓取失敗。`scripts/tests/edit-run/test.sh`：`--note` 與可見文字、`discard --reason` 的 finish 報告。
- `scripts/tests/issue-write-back/test.sh`：規則檔存在且含三類分流、兩種觸發、信任邊界、定案門檻、作者邊界、回報、privacy；SessionStart 輸出含寫回提醒且 ≤5 行；`idd-edit` Step 3 對 `--correct` 不再要求確認、`--prepend-note` 引用嚴格作者檢查；`idd-diagnose` Stage 1 用 `--correct`、不再寫「追加修正」。
- `scripts/tests/in-place-correction/test.sh`：三個偵測 skill 斷言 `### Applied Corrections`、`--correct`，並反向斷言不再含「只列不做」。
- `run-all-tests.sh` 全部通過。

**範圍**

- 範圍內：上列規則、hook、四個 SKILL.md、兩份測試、`append-vs-modify` 規則的對應說明、版本與文件。
- 範圍外：作者判斷、即時觸發、改寫別人的內容、`--append`／`--replace`、機械化判斷類別。

## Risks / Trade-offs

- [AI 判斷錯類別，把新決定寫進正文] → 每次寫回都回報類別與目標；段落尾的可見文字讓讀者看得到；舊版用 GitHub 編輯歷史取回，或在同一份 clone 用 `/idd-edit` 的 `restore`（會蓋掉之後的更正）。
- [不確認後，privacy 自審是語意上唯一的防線] → 任何等級命中都停（D6）；gh-egress 的機械閘照常。自審本身可能漏判，沒有機械防線，這一點接受。
- [ADMIN 帳號可改別人的 comment] → 不確認的路徑一律先過 `--correct` 的嚴格作者檢查（D1b）。
- [verify 期間 Diagnosis 或正文被改] → verify 自己不改任何東西（D9）；另一個 session 可能改，所以 Step 1 記下 issue 正文雜湊與 Diagnosis 的 `updated_at`，Step 2.9 再比，不同就在報告註明。
- [SessionStart 第 5 行是每個 session 的 context 成本] → 一行、指向規則檔，drift guard 鎖住上限。

## Migration Plan

- plugin 版本 3.7.0（3.6.0 已發布給 #399、#465）。
- 回滾：還原這個 change 的 commit 即回到「確認後才寫」；已寫回的內容都有歸檔或在 comment 歷史中。

## Open Questions

（none）
