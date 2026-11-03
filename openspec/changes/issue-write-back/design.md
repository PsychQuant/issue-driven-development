## Context

IDD 已有就地更正的工具：`/idd-edit --correct`（#351）可以改自己寫的 comment 或 issue 正文的一個段落，舊版歸檔、可還原；`/idd-comment` 有 decision、note、errata、correction 等分類；`/idd-update` 管 Current Status。缺的是「討論中的改變寫回哪裡」的規則，而且有兩處現行行為和 #424 的決定衝突：

1. `in-place-correction` 規定 `--correct` 要使用者確認（預設 NO），`idd-edit` Step 3 第 5 點照做。
2. `idd-diagnose` Step 4 Stage 1 要調整診斷時用 `gh issue comment` 追加修正，而不是改 Diagnosis 本身。

#424 的決策紀錄：Diagnosis 的「決策」段（D1–D3）、decision comment（2026-10-25），以及四輪 verify 之後的維護者決定（comment 6600258374、6611450882、6615341615、6616229678）。

## Goals / Non-Goals

**Goals:**

- 使用者在 session 裡定案的改變，由 AI 判斷類別並寫回對的位置：問題 → issue 正文段落；診斷 → Diagnosis 段落與其相依紀錄；新資訊與決定 → 新的 comment。
- 改寫自己的內容不再停下來確認；每次寫回都在對話裡回報，改寫的段落留一行可見文字。
- skill 之外的討論也套用（SessionStart 一行）。

**Non-Goals:**

- 別人的 comment 自動觸發寫回：只在使用者於 session 提到時處理（D11）。
- 偵測到錯誤的 skill 自動更正：`idd-verify`、`idd-diagnose`、`idd-reorganize` 照 3.6.0 的提議流程（D11）。
- 改寫別人的內容：別人的 comment 與 issue 正文永遠只用 errata 或 correction comment 回應。
- `--append`、`--replace` 的確認：維持現狀。
- 改 `Original text`：受保護區塊規則不動。
- 修改 helper 的作者判斷：沿用既有的 `validate-target ... --correct`。
- 機械化「這次改變屬於哪一類」或「是不是定案」：由 AI 判斷，錯了由可見文字與編輯歷史承接。

## Decisions

### D1 `--correct` 不再確認，其餘安全步驟保留

`/idd-edit --correct` 只放行自己的內容（helper 的作者閘），舊版歸檔在執行它的那份 clone，GitHub 的編輯歷史也保留每個舊版，所以拿掉確認不會讓錯誤變成不可逆。保留的步驟：diff 與預覽仍完整顯示（改為回報）、privacy 自審（見 D6）、#272 閘（reply template 帶使用者貼來的第三方原話時仍要問）、apply 時重讀目標與比對預覽、歸檔。替代方案「使用者直接下指令時才確認」被否決：同一個指令兩種行為，讀 skill 的人分不清。偵測 skill 的提議流程裡，使用者選「現在執行」那一題就是確認。

### D1b `--prepend-note` 只在自己的內容上不確認

D2 的 verify 報告註記要用 `--prepend-note`，但這個 mode 的作者閘會放行 OWNER 與 bot，而使用者是 repo ADMIN、GitHub 允許改別人的 comment。所以不確認的前提是目標通過 `validate-target <id> <repo> false --correct`（`--correct` 的嚴格作者判斷，exit 0 才算自己的內容）；不通過就照原本的確認流程。

### D2 verify 報告只加一行註記

診斷更正後，既有 verify 報告的 findings 不動，只用 `--prepend-note` 在開頭加一行「依據的診斷已於 YYYY-MM-DD 更正，見 <Diagnosis 連結>」。verify 報告記錄的是某個凍結 head 的驗證結果，改寫 findings 會讓它不再對應那個 head。Implementation Plan 是往前看的計畫，受影響的段落用 `--correct` 改寫。

### D3 規則放 plugin 層，SessionStart 加一行

討論大多發生在沒有 skill 執行的時候，只寫進 SKILL.md 碰不到。依 `rules-layering`，約束所有 IDD 使用者、主戰場在 skill 之外的規則放 plugin 層並加 SessionStart 注入。現有輸出 4 行（commit 紀律），加一行剛好 5 行，標題由「IDD commit 紀律」改為「IDD 紀律」；那一行印出規則檔的安裝路徑，沒有 skill 在跑的 session 才找得到它。替代方案「另開一支 hook」被否決：多付一份 context，還要另寫 drift guard。

### D6 不問的路徑上，隱私命中就停；只限有寫入權的 repo（verify 第 1 輪）

`privacy-scrubbing` 的 `warn`「default proceed」成立的前提是後面還有人工確認，D1 拿掉確認後就沒有人攔了。所以不問的路徑上，對這次加入的文字做語意自審：`enforce`、`warn` 命中就停，`light` 只有新加入的第三方逐字內容算命中；停下的就問，unattended 捨棄。目標裡原本就有的內容已經公開，命中只回報。沒有寫入權的 repo 與查不到權限時（helper 判為 `enforce`）回到確認流程。

### D7 定案門檻與可見文字（verify 第 1 輪，2026-11-03 維護者決定，comment 6600258374）

- **定案**：只有使用者在 session 裡明確定案才算改變，假設與提問不算。已關閉的 issue 不改，避免和 Closing Summary 對不起來。
- **可見文字**：`--correct` 由 helper 固定加一行 `_更正於 YYYY-MM-DD（AI 判斷）：原因_`。放在 helper 而非規則，才不會忘；原因寫正確內容，不重述錯的值。GitHub 編輯不寄通知，標記又看不見，沒有這行，讀者無從知道。

### D8 實作後的更正走 idd-reorganize

更正讓既有實作的前提不成立，或問題改變時，只改文字會留下 PASS 與舊的 phase。`idd-reorganize` 本來就處理下游枚舉與退 phase，不另造機制。Spectra tier 的 artifact 也由它處理。

### D11 只留核心（verify 第 4 輪，2026-11-04 維護者決定，comment 6616229678）

第一版還有兩塊：別人的 comment 在 skill 讀到時自動觸發寫回（舊 D5），偵測到錯誤的 skill 自動更正（舊 D4）。四輪 verify 都沒過，而且不收斂：每輪為了守住這兩塊新加的機件（信任邊界、候選清單與它的時間截止點、`listed` 與 Blocking、只改 bug 的 Diagnosis 三段），下一輪都在機件上找到新的 HIGH（外人的話進入維護者署名的 Diagnosis、沒看過的 comment 永久漏掉、verify 改到自己的驗收依據、改到剛被取代的舊 Diagnosis）。核心的討論寫回四輪都沒被打到。所以兩塊都砍：別人的 comment 只在使用者於 session 提到時處理，採不採信由使用者決定；偵測 skill 回到 3.6.0 的提議流程（attended 逐項問、unattended 只列不做）。

## Implementation Contract

**行為（使用者看得到的）**

- session 裡討論一張開著的 issue，使用者定案時，AI 判斷改變屬於三類之一並寫回，有寫入權的 repo 不問；每次寫回在對話裡回報一行：類別、目標、連結、依據（使用者的原話），`--correct` 另附 backup id。
- `/idd-edit ... --correct`：顯示 diff 與預覽後直接 apply，改寫段落尾留一行可見文字；隱私自審只看這次加入的文字，`enforce`、`warn` 命中、`light` 下新加入的第三方逐字內容、或 #272 題沒確認時不寫（attended 問，unattended 捨棄），finish 以 9 結束並寫出原因。沒有寫入權的 repo 照舊確認。
- `/idd-edit ... --prepend-note`：目標通過嚴格作者檢查時不確認；否則照舊確認。`--append`、`--replace` 照舊確認。unattended 下任何問題都改成捨棄。
- `idd-diagnose` Step 4 Stage 1：使用者要調整診斷時，用 `/idd-edit comment:<Diagnosis id> --correct --section ...` 改寫，不追加 comment。
- 偵測 skill 照 3.6.0 的提議流程；選「現在執行」後 `/idd-edit --correct` 不再問第二次。
- SessionStart 輸出第 5 行提醒寫回規則。

**介面**

- 新檔 `plugins/issue-driven-dev/rules/issue-write-back.md`：定案門檻、三類分流表（封閉列舉）、作者邊界、回報格式、privacy 自審、被拒時的去處（封閉列舉）、相依紀錄更新（Implementation Plan、verify 報告）。
- helper：`run-start` 接受 `--note`（只限 `--correct`），在替換內容尾端加可見文字，先移除尾端舊的可見文字與標記；`discard` 接受 `--reason held-privacy|held-272|held-unattended`；`--body-file` 路徑閘多擋家目錄下的 dotfile、`~/.claude`（job 的 `tmp/` 除外）、`~/.config/git` 與含密鑰的檔名。

**驗收**

- `scripts/tests/edit-run/test.sh`：`--note` 與可見文字、舊行與舊標記被換掉、只有標記的替換內容仍回 empty、`--note` 拒絕的字元、私人路徑、`discard --reason` 的 finish 報告。
- `scripts/tests/issue-write-back/test.sh`：規則檔含定案門檻、三類分流、作者邊界、回報、privacy、被拒時的去處；`idd-edit` Step 3 對 `--correct` 不再要求確認、`--prepend-note` 引用嚴格作者檢查、unattended 不提問；`idd-diagnose` Stage 1 用 `--correct`、不再寫「追加修正」；`idd-close` 讀 Residue 時略過可見文字與標記。
- `scripts/tests/in-place-correction/test.sh`：三個偵測 skill 保留 `### Proposed Corrections` 與「只列不做」，選執行後不再寫「仍走自己的 preview + confirm」。
- `run-all-tests.sh` 全部通過。

**範圍**

- 範圍內：上列規則、hook、helper、`idd-edit`、`idd-diagnose` Stage 1、`idd-comment` errata 的文字、`idd-close` 的 Residue 讀取、三個偵測 skill 選執行後的那一句、`append-vs-modify` 規則的對應說明、版本與文件。
- 範圍外：作者判斷、別人的 comment 自動觸發、偵測 skill 自動更正、改寫別人的內容、`--append`／`--replace`、機械化判斷類別或定案。

## Risks / Trade-offs

- [AI 判斷錯類別，把新決定寫進正文] → 每次寫回都回報類別、目標與依據；段落尾的可見文字讓讀者看得到；舊版用 GitHub 編輯歷史取回，或在同一份 clone 用 `/idd-edit` 的 `restore`（會蓋掉之後的更正）。
- [不確認後，privacy 自審是語意上唯一的防線] → 命中就停（D6）；gh-egress 的機械閘照常。自審本身可能漏判，沒有機械防線，這一點接受。
- [ADMIN 帳號可改別人的 comment] → 不確認的路徑一律先過 `--correct` 的嚴格作者檢查（D1b）。
- [「定案」只靠 AI 判斷] → 回報帶依據（使用者原話），可見文字與編輯歷史讓錯誤可以被發現與還原。
- [SessionStart 第 5 行是每個 session 的 context 成本] → 一行、指向規則檔，drift guard 鎖住上限。

## Migration Plan

- plugin 版本 3.7.0（3.6.0 已發布給 #399、#465）。
- 回滾：還原這個 change 的 commit 即回到「確認後才寫」；已寫回的內容都有歸檔或在 comment 歷史中。

## Open Questions

（none）
