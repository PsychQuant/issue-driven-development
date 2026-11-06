## Context

IDD 已有就地更正的工具：`/idd-edit --correct`（#351）可以改自己寫的 comment 或 issue 正文的一個段落，舊版歸檔、可還原；`/idd-comment` 有 decision、note、errata、correction 等分類；`/idd-update` 管 Current Status。缺的是「討論中的改變寫回哪裡」的規則，而且有兩處現行行為和 #424 的決定衝突：

1. `in-place-correction` 規定 `--correct` 要使用者確認（預設 NO），`idd-edit` Step 3 第 5 點照做。
2. `idd-diagnose` Step 4 Stage 1 要調整診斷時用 `gh issue comment` 追加修正，而不是改 Diagnosis 本身。

#424 的決策紀錄：Diagnosis 的「決策」段（D1–D3）、decision comment（2026-10-25），以及五輪 verify 之後的維護者決定（comment 6600258374、6611450882、6615341615、6616229678、6617788666）。

## Goals / Non-Goals

**Goals:**

- 使用者在 session 裡定案的改變，由 AI 判斷類別並寫回對的位置：問題 → issue 正文段落；診斷 → Diagnosis 段落與 Implementation Plan；新資訊與決定 → 新的 comment。
- 改寫自己的內容不再停下來確認；每次寫回都在對話裡回報，改寫的段落留一行可見文字。
- skill 之外的討論也套用（SessionStart 一行）。

**Non-Goals:**

- 別人的 comment 自動觸發寫回：只在使用者於 session 提到時處理（D11）。
- 偵測到錯誤的 skill 自動更正：`idd-verify`、`idd-diagnose`、`idd-reorganize` 照 3.6.0 的提議流程（D11）。
- 改寫別人的內容：別人的 comment 與 issue 正文永遠只用 errata 或 correction comment 回應。
- 改 verify 報告或在報告上加註記（D12，撤回 D2）。
- `--body-file` 的私人路徑閘、`/idd-edit` 的 unattended 分支（D12）。
- `--prepend-note`、`--append`、`--replace` 的確認：維持現狀。
- 改 `Original text`：受保護區塊規則不動。
- 修改 helper 的作者判斷：沿用既有的 `validate-target ... --correct`。
- 機械化「這次改變屬於哪一類」或「是不是定案」：由 AI 判斷，錯了由可見文字與編輯歷史承接。

## Decisions

### D1 `--correct` 不再確認，其餘安全步驟保留

`/idd-edit --correct` 只放行自己的內容（helper 的作者閘），舊版歸檔在執行它的那份 clone，GitHub 的編輯歷史也保留每個舊版，所以拿掉確認不會讓錯誤變成不可逆。保留的步驟：diff 與預覽仍完整顯示（改為回報）、privacy 自審（見 D6）、#272 閘（reply template 帶使用者貼來的第三方原話時仍要問）、apply 時重讀目標與比對預覽、歸檔。替代方案「使用者直接下指令時才確認」被否決：同一個指令兩種行為，讀 skill 的人分不清。偵測 skill 的提議流程裡，使用者選「現在執行」那一題就是確認。

### D1b、D2（第 5 輪撤回，見 D12）

原本診斷更正後要在每份自己的 verify 報告開頭用 `--prepend-note` 加一行註記（D2），並讓 `--prepend-note` 在嚴格作者檢查通過時不確認（D1b）。D12 撤回兩者。

### D3 規則放 plugin 層，SessionStart 加一行

討論大多發生在沒有 skill 執行的時候，只寫進 SKILL.md 碰不到。依 `rules-layering`，約束所有 IDD 使用者、主戰場在 skill 之外的規則放 plugin 層並加 SessionStart 注入。現有輸出 4 行（commit 紀律），加一行剛好 5 行，標題由「IDD commit 紀律」改為「IDD 紀律」；那一行印出規則檔的安裝路徑，沒有 skill 在跑的 session 才找得到它。替代方案「另開一支 hook」被否決：多付一份 context，還要另寫 drift guard。

### D6 不問的路徑上，隱私命中就停；只限有寫入權的 repo（verify 第 1 輪）

`privacy-scrubbing` 的 `warn`「default proceed」成立的前提是後面還有人工確認，D1 拿掉確認後就沒有人攔了。所以不問的路徑上，對這次加入的文字做語意自審：`enforce`、`warn` 命中就停，`light` 只有新加入的第三方逐字內容算命中；停下的就問。目標裡原本就有的內容已經公開，命中只回報。沒有寫入權的 repo 與查不到權限時（helper 判為 `enforce`）回到確認流程。密鑰、token、密碼這類 credential 在任何等級都算命中（verify 第 5 輪）。

### D7 定案門檻與可見文字（verify 第 1 輪，2026-11-03 維護者決定，comment 6600258374）

- **定案**：只有使用者在 session 裡明確定案才算改變，假設與提問不算。已關閉的 issue 不改，避免和 Closing Summary 對不起來。
- **可見文字**：`--correct` 由 helper 固定加一行 `_更正於 YYYY-MM-DD：原因_`（第 6 輪後拿掉「AI 判斷」，見 D13）。放在 helper 而非規則，才不會忘；原因寫正確內容，不重述錯的值。GitHub 編輯不寄通知，標記又看不見，沒有這行，讀者無從知道。

### D8 實作之後的三種去處（第 5 輪改，見 D12；第 7 輪改，見 D14）

實作之後定案的改變，實作在同一個 PR 裡跟著改（例如 verify-fix 期間改了設計；direct-commit 時是結案前的同一條 branch），照一般的寫回改 Diagnosis 與 Implementation Plan。PR 合併後才擴大範圍、已建好的東西照樣有效：開新 issue 承接，原 issue 貼 link comment（D14）。已建好的東西要作廢或重做，才走 `idd-reorganize`：只改文字會留下 PASS 與舊的 phase，而 `idd-reorganize` 本來就處理下游枚舉與退 phase，Spectra tier 的 artifact 也由它處理。第一版把所有實作後的更正都送去 `idd-reorganize`，它會再貼一則新的 Diagnosis，正是 #399 的情況。

### D11 只留核心（verify 第 4 輪，2026-11-04 維護者決定，comment 6616229678）

第一版還有兩塊：別人的 comment 在 skill 讀到時自動觸發寫回（舊 D5），偵測到錯誤的 skill 自動更正（舊 D4）。四輪 verify 都沒過，而且不收斂：每輪為了守住這兩塊新加的機件（信任邊界、候選清單與它的時間截止點、`listed` 與 Blocking、只改 bug 的 Diagnosis 三段），下一輪都在機件上找到新的 HIGH（外人的話進入維護者署名的 Diagnosis、沒看過的 comment 永久漏掉、verify 改到自己的驗收依據、改到剛被取代的舊 Diagnosis）。核心的討論寫回四輪都沒被打到。所以兩塊都砍：別人的 comment 只在使用者於 session 提到時處理，採不採信由使用者決定；偵測 skill 回到 3.6.0 的提議流程（attended 逐項問、unattended 只列不做）。

### D12 再拿掉三樣、實作後同 PR 就地寫回（verify 第 5 輪，2026-11-04 維護者決定，comment 6617788666）

第 5 輪的 HIGH 只剩一處殘留，其餘發現多半落在為已砍部分留下的機件上。維護者決定：verify 報告不加註記（註記會擠掉報告首行的標題，讓認首行的 skill 認不出報告；#424 每改一次 Diagnosis 就要加 8 則），`--prepend-note` 回到 main 一律先問；`--body-file` 的私人路徑閘拿掉（規則自己的寫回檔在暫存目錄，本來就不受它檢查，卻在四種 mode 誤擋一般檔案），回到 main 的系統與 credential 目錄檢查；`/idd-edit` 的 unattended 分支拿掉（砍掉自動更正後已沒有 unattended 流程呼叫它，只會被殘留的旗標觸發）；實作之後同一個 PR 跟著改的設計改變就地寫回（D8）。

### D13 改了診斷的決定兩處都寫，可見文字拿掉「AI 判斷」（verify 第 6 輪，2026-11-04 維護者決定，comment 6619279709）

Devil's Advocate 指出 #424 自己跑了六輪，每次定案的都是改策略的決定，實作者每次都只貼 decision comment，Diagnosis 與 Current Status 停在第 1 輪：三類擇一讓這類決定只能選一邊，歸第 2 類使用者的原話沒有位置，歸第 3 類 Diagnosis 不更新。所以改了診斷的決定兩處都寫。「AI 判斷」出自 D7，當時偵測 skill 還會自動更正；D11 之後每條 `--correct` 路徑都是使用者定案或選了執行，這幾個字的前提不在。同一輪的發現也讓替換文字不再逐行剝除（剝除會誤刪 code fence 範例與其他段落的更正紀錄），第 7 輪改成拒絕結尾以外的舊行，第 8 輪再改成照樣保留（見 D14）；寫回檔改放 `$HOME/.cache/idd/writeback/` 下的新目錄（`$TMPDIR` 在 sandbox 內外不同，路徑閘會拒絕另一邊的暫存目錄）。

### D14 合併後擴大的範圍開新 issue（verify 第 7 輪，2026-11-04 維護者決定，comment 6620544269）

第 7 輪為了補「實作之後、沒有 PR 承載」的缺口，實作端自己加了「寫回後走 `idd-reorganize`」，沒有經過決定；它在 direct-commit 的 repo 會把一般的 verify-fix 改變也送去 `idd-reorganize`，而 `idd-reorganize` 會再貼一則新的 Diagnosis。維護者決定：這種改變是新的工作，開新 issue 承接，不改原 issue 的 Expected。同一輪也把替換文字的處理改成只動結尾那一組：第 6 輪的逐行剝除會改到沒人看過的文字，第 7 輪的拒絕又擋住 main 接受的整則更正，所以結尾之前的文字一律照樣保留。

## Implementation Contract

**行為（使用者看得到的）**

- session 裡討論一張開著的 issue，使用者定案時，AI 判斷改變屬於三類之一並寫回，有寫入權的 repo 不問；每次寫回在對話裡回報一行：類別、目標、連結、依據（使用者的原話），`--correct` 另附 backup id。
- `/idd-edit ... --correct`：顯示 diff 與預覽後直接 apply，改寫段落尾留一行可見文字；隱私自審只看這次加入的文字，`enforce`、`warn` 命中、`light` 下新加入的第三方逐字內容、任何等級的 credential，或 #272 題沒確認時先問，使用者不寫就以 9 結束。沒有寫入權的 repo 照舊確認。
- `/idd-edit ... --prepend-note`、`--append`、`--replace`：照舊確認。
- `idd-diagnose` Step 4 Stage 1：使用者要調整診斷時，用 `/idd-edit comment:<Diagnosis id> --correct --section ...` 改寫，不追加 comment。
- 偵測 skill 照 3.6.0 的提議流程；選「現在執行」後 `/idd-edit --correct` 不再問第二次。
- SessionStart 輸出第 5 行提醒寫回規則。

**介面**

- 新檔 `plugins/issue-driven-dev/rules/issue-write-back.md`：定案門檻、三類分流表（封閉列舉）、作者邊界、回報格式、privacy 自審、被拒時的去處（封閉列舉）、相依紀錄更新（Implementation Plan；verify 報告不動）、實作之後的去處。
- helper：`run-start` 接受 `--note`（只限 `--correct`），在替換內容尾端加可見文字，先移除尾端舊的可見文字與標記。

**驗收**

- `scripts/tests/edit-run/test.sh`：`--note` 與可見文字、結尾的舊行與舊標記被換掉、結尾之前的文字（含 code fence 範例與同形正文）保留、只有標記的替換內容被拒、`--note` 拒絕的字元。
- `scripts/tests/issue-write-back/test.sh`：規則檔含定案門檻、三類分流、作者邊界、回報、privacy、被拒時的去處；`idd-edit` Step 3 對 `--correct` 不再要求確認、其他 mode 照舊確認、沒有 unattended 分支；`idd-diagnose` Stage 1 用 `--correct`、不再寫「追加修正」；`idd-close` 讀 Residue 時略過可見文字與標記。
- `scripts/tests/in-place-correction/test.sh`：三個偵測 skill 保留 `### Proposed Corrections` 與「只列不做」，選執行後不再寫「仍走自己的 preview + confirm」，問句附替換內容全文、引數帶 `--repo`。
- `run-all-tests.sh` 全部通過。

**範圍**

- 範圍內：上列規則、hook、helper、`idd-edit`、`idd-diagnose` Stage 1、`idd-comment` errata 的文字、`idd-close` 的 Residue 讀取、三個偵測 skill 選執行後的那一句、`append-vs-modify` 規則的對應說明、版本與文件。
- 範圍外：作者判斷、別人的 comment 自動觸發、偵測 skill 自動更正、改寫別人的內容、verify 報告、`--prepend-note`／`--append`／`--replace`、`--body-file` 路徑閘、`/idd-edit` 的 unattended 處理、機械化判斷類別或定案。

## Risks / Trade-offs

- [AI 判斷錯類別，把新決定寫進正文] → 每次寫回都回報類別、目標與依據；段落尾的可見文字讓讀者看得到；舊版用 GitHub 編輯歷史取回，或在同一份 clone 用 `/idd-edit` 的 `restore`（會蓋掉之後的更正）。
- [不確認後，privacy 自審是語意上唯一的防線] → 命中就停，credential 在任何等級都算（D6）；gh-egress 的機械閘與 main 的 `--body-file` 路徑閘照常。自審本身可能漏判，沒有機械防線，這一點接受。
- [ADMIN 帳號可改別人的 comment] → 不確認的路徑一律先過 `--correct` 的嚴格作者檢查（D1b）。
- [「定案」只靠 AI 判斷] → 回報帶依據（使用者原話），可見文字與編輯歷史讓錯誤可以被發現與還原。
- [SessionStart 第 5 行是每個 session 的 context 成本] → 一行、指向規則檔，drift guard 鎖住上限。

## Migration Plan

- plugin 版本 3.7.0（3.6.0 已發布給 #399、#465）。
- 回滾：還原這個 change 的 commit 即回到「確認後才寫」；已寫回的內容都有歸檔或在 comment 歷史中。

## Open Questions

（none）
