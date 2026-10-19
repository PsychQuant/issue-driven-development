## Context

#351 的起點是老師的回饋：issue 是下游 skill 與日後 session 的記憶，錯誤留在原處、只在後面追加更正，讀的人仍會照錯的做。現況有四處跟這個需求衝突：

- `append-vs-modify` 規則把已發佈的 comment 歸為 `append-only`，把 issue 正文 `---` 以上整段歸為 `verbatim-preserve`。
- `idd-comment --type errata` 的流程是另貼一則 errata，再到原 comment 頂端加警示；錯的內容留在原處。
- `idd-edit` 只能編 comment（#347），備份寫在 `/tmp/idd-edit-backup/`、約七天後消失，marker 寫出備份路徑。
- IDD plugin 只有 SessionStart hook，沒有任何擋讀取的機制。

使用者在 #351 與 spectra-discuss 已定案：AI 提議、使用者確認後才取代；只更正你自己（目前登入的 gh 使用者）寫的內容，別人寫的（含 OWNER 由別人執行時、bot）不改（2026-10-17 使用者決定）；`Original text` 引用區不改；舊版存 `.claude/.idd/archive/edits/`、不進 git、本機永久保留，遠端的永久紀錄交給 GitHub 自帶的編輯紀錄；hook 擋 AI 讀取；GitHub 編輯紀錄不擋。

## Goals / Non-Goals

**Goals:**

- `idd-edit --correct` 能就地取代 comment 或 issue 正文中確定錯誤的段落，取代前歸檔舊版。
- 歸檔內容不進 git、不出現在任何 diff，Claude 的工具讀不到。
- 規則與 spec 明寫這條路，其他 skill 只能提議、不能自己改。

**Non-Goals:**

- `idd-edit` 對正文的 `--append`、`--replace`、`--prepend-note`（留在 #347）。
- 擋 GitHub 自帶的編輯紀錄（`userContentEdits`）。
- 防範刻意繞過的 agent（例如自己 `chmod` 後讀檔）；本設計防的是無意間讀到。
- 跨機器同步歸檔。
- 判定某段內容「是不是錯的」的自動化；判定一律由人確認。

## Decisions

### 新增第 8 類 in-place-correction，不放寬既有類別

在封閉列舉加一類，並把 `verbatim-preserve` 縮成「`Original text` 引用區塊＋OWNER、bot、目前 gh 使用者以外的人寫的 comment」兩種。bot 的 comment 不在 `verbatim-preserve` 內，但仍是第三方的話，`--correct` 不改（verify 第 2 輪）；OWNER 寫的內容在別人執行時也一樣，`--correct` 只改執行者自己寫的（2026-10-17 使用者決定）。issue 正文的作者以開 issue 的人為準，這是近似：別人開的 issue 正文裡後來由維護者或 IDD skill 寫入的段落改不到，你的 issue 正文裡協作者寫的段落改得到；使用者接受這個近似（2026-10-17），前者用 `/idd-comment --type correction` 追加更正。替代方案是直接放寬 `append-only`，但 `append-only` 也管 CHANGELOG 與 Spectra 歸檔快照，一起放寬會讓不該改的東西變得可改。spec 的類別數寫進了需求名稱（`Canonical 7-category enumeration ...`），因此以 REMOVED＋ADDED 換成不含數字的名稱，避免下次加類別又要改名。

### --correct 是獨立模式，不是 --replace 加旗標

模式與類別一對一：`--replace` 維持 `bounded-section-replace`（一般改寫），`--correct` 對應 `in-place-correction`（錯誤更正，強制歸檔、禁止 override）。共用 `--scope whole-comment`／`--section` 與 section-replace 邏輯。替代方案 `--replace --error` 會讓同一模式依旗標落在兩個類別，違反「每個動作宣告一個類別」。

### 正文目標只接受 --section，並拒絕保護區

正文目標語法 `issue:<N>`，只接受 `--section <heading>`。整段取代正文會一起覆蓋 `Original text`、`## Current Status`、`### Clarity Surface`，所以不開放。保護區判定由 helper 的 `check-correction` 子命令執行：

- 受管區：`## Current Status`（含其下巢狀標題，歸 `idd-update`）與 `### Clarity Surface`（歸 `idd-clarify`）。目標段落本身是受管區 → exit 6。`### Clarity Surface` 常巢狀在 `## Related` 底下：第 1 版把「包含受管區」也一律拒絕，手動驗收發現這讓 `## Related` 永遠改不了，所以改成更正的段落遇到受管標題（或 `---`）就結束，只換它上面的內容（使用者 2026-10-10 決定）。
- verbatim 區塊：原 section 中「連續以 `>` 開頭、且其中一行含 `Original text`、`**Original**` 或 `**Point `（封閉列舉三個標籤）」的最大區塊，必須在取代內容中逐 byte 出現 → 否則 exit 6。

### 確認後才歸檔，歸檔成功才 PATCH

順序是預覽 → 確認 → 重抓目標比對 → `archive` → PATCH。確認之後重新抓一次目標，與預覽時的原文比對；不一致就拒絕、不歸檔也不 PATCH，避免使用者確認的版本與實際被取代的內容不同。歸檔的是預覽時給使用者看的那份原文（第 5 輪起由 correct-apply 在行程內寫入，不再經過 `archive --from-file`），不自己向 GitHub 重抓：重抓可能拿到中間被改過的版本，歸檔就不再等於實際被取代的內容。apply 結束時刪掉工作副本。歸檔是受保護、Claude 的工具讀不到的那一份，不是唯一的一份：GitHub 的編輯紀錄保有舊版，暫存與 scratch 副本也可能留下舊版，後者在 #378 追蹤。使用者拒絕時不留任何檔案；歸檔失敗（不在 git work tree、路徑沒被 ignore、寫入失敗）一律不 PATCH（`archive` 子命令回 exit 7；在一次 run 裡記為 `REASON=archive`，`finish` 回 4）。替代方案「先歸檔再確認」會在拒絕時留下沒有對應更正的歸檔檔。

### 歸檔寫進 .git/info/exclude，不改 tracked 的 .gitignore

helper 用既有的 `scripts/git-ignore-block.sh --direction exclude` 把 `.claude/.idd/archive/` 寫進 `.git/info/exclude`，再用 `git check-ignore` 驗證。`.git/info/exclude` 是每個 clone 自己的設定、不會被 commit，不會在其他使用者的 repo 裡改動 tracked 檔（與 #192 third-party clone 的做法一致）。本 repo 另在 `.gitignore` 加一行，讓維護者在任何 clone 都一致。使用者決定的本意是「不進 git」，這個做法達成同一件事；若使用者要求一律改 `.gitignore`，只需換掉 helper 的寫入目標。使用者已於 2026-10-10 確認採用 `.git/info/exclude`。

歸檔根目錄是 main worktree（由 `git rev-parse --git-common-dir` 推出），不是當下的 linked worktree：從 linked worktree 寫入的歸檔才不會隨 `git worktree remove` 消失。

### 雙層擋讀：hook 加上檔案權限 0000

第一層是 PreToolUse hook：工具參數或指令字串含 `.claude/.idd/archive` 就拒絕，並告訴 AI 原因與正確的還原方式。比對不分大小寫（macOS 檔案系統不分大小寫），路徑欄位先以 `os.path.normpath` 正規化，Glob／Grep 另外檢查 `path` 與 `pattern`／`glob` 合併後的路徑。第二層是歸檔檔權限 `0000`：hook 只能比對字串，攔不到 `grep -r . `、`rg --no-ignore` 這類不寫出路徑的遞迴讀取；權限讓這些指令讀不到內容。`restore` 是唯一會暫時開放讀取權限的地方，並在結束時（含失敗）設回 `0000`。

### hook 以 Python 實作，輸入無法解析時放行

hook 腳本 `hooks/archive-read-guard.py` 用 stdlib `json` 解析 stdin，與 helper 同屬 Python 層（bash 字串解析在 #154 已證明難收斂）。輸入不是 JSON 物件時放行並寫一行 stderr：若改成拒絕，呼叫端的 bug 會擋掉整個 session 的所有工具呼叫；第二層權限仍在。輸入正常、但檢查過程出錯時，拒絕這一次呼叫（第 20 輪）。matcher 用確切名稱清單 `Read|Grep|Glob|Edit|Write|NotebookEdit|Bash|PowerShell|Monitor`（官方文件：只含字母與 `|` 的 matcher 是精確比對，`Bash` 不會誤中其他工具）。

### read guard fail-closed：不豁免訊息，遞迴改權限只在歸檔附近檢查（第 18–21 輪）

第 3 到 17 輪 hook 讓「提到路徑的訊息參數」放行，為此得模擬 shell 的斷詞；每次改寫都被 verify 找到新的繞法（verify 第 13–16 輪連續 HIGH）。2026-10-18 使用者決定 fail-closed：指令文字只要提到歸檔路徑就擋，訊息改由檔案傳（`-F`、`--body-file`）。

遞迴改權限的檢查重蹈同一條路：第 19 輪把旗標與目標歸給「權限指令之後」的詞，第 20 輪改成不歸屬、但在 repo 外解析每個目標，verify 第 18、19 輪各找到 5 與 7 個 HIGH（黏住的運算子、撇號、`cd` 後的相對目標、括號路徑），而且在沒有歸檔的 repo 裡把寫 script 的 heredoc 擋下（使用者真實紀錄：1 筆增為 237 筆）。2026-10-18 使用者第二次決定（第 21 輪）：只在歸檔附近檢查——工作目錄在含歸檔的 repo 內、或是其上一層資料夾、或無法列出時，指令同時含權限指令與遞迴標記就擋，不看目標；其他地方不檢查，寫成已知限制。

第 26–28 輪：verify 第 24–26 輪已沒有實質 HIGH，修的是邊角：PowerShell 模組限定的 cmdlet（`Microsoft.PowerShell.Management\Set-Location`，只認點分模組名前綴，`tools/cd` 不算）、symlink 工作目錄也以 realpath 判斷、從 Bash 跑 `pwsh` 時指令名與路徑也用 PowerShell 讀法、zsh 的 `=chmod` 與 `zf_chmod`。已知限制整理成一份完整清單（Risks 第一條），spec、hook docstring、CHANGELOG 同一份。

第 25 輪（使用者 2026-10-19 第二個決定）：verify 第 23 輪指出換目錄字的清單是開放的——`env -C`、`sudo -D`、`make -C`、`git -C`、`uv --directory`、`pwsh -WorkingDirectory` 這類程式選項也會換目錄。使用者決定寫成已知限制：threat model 是無意間讀到，agent 碰到 Permission denied 的自然反應（`cat`、`cd` 後 `cat`、`chmod u+r`）都已擋下，用程式選項換目錄去改歸檔權限不是無意間會做的事。同輪修正：symlink 工作目錄也以 realpath 判斷是否在 `.claude/.idd` 內；換目錄字只比整個字；模組 docstring 改成 raw（`\w` 跳脫在 warnings-as-errors 下會讓 hook 無法啟動、等於放行）。

第 24 輪（使用者 2026-10-19 決定）：第 20–22 輪都在補「用某種寫法 cd 進歸檔，再非遞迴 `chmod u+r` 加 `cat`」，每輪都有新寫法（`cd -P`、`cd archive/.`、`cd ../archive`、續行、反引號、zsh `chdir`、PowerShell `Set-Location`）。解除 `0000` 的那一步是改權限，所以改擋那一步：在歸檔附近（或指令指名有歸檔的 `.claude/.idd`），指令同時含換目錄字與權限指令就擋；工作目錄在 `.claude/.idd` 內時任何權限指令都擋。不再辨認 cd 的寫法（刪掉 `_CD_ARCHIVE`）；相對路徑規則原始與正規化兩種都比對。代價：含歸檔的 repo 裡，同一個指令只要有任何 `cd`（包括 `cd /tmp` 這種與歸檔無關的目錄）又有 `chmod`，就被擋，例如 `cd scripts && chmod +x run.sh`、`cd /tmp && … && chmod +x probe.sh`；改成不 cd、寫出路徑，或把 chmod 拆成另一個呼叫；工作目錄在 `.claude/.idd` 內時要先在另一個呼叫離開。實測（使用者真實紀錄，排除測試 guard 本身的指令）：歸檔附近新增 94 筆拒絕（不排除時 107 筆：68＋39），其中 62 筆在本 repo（約占本 repo 4,383 筆指令的 1.4%），32 筆來自已不存在的工作目錄（無法列出，視同歸檔附近）。往後：同時含換目錄字與權限字的指令共 1,298 筆、分布在 19 個頂層目錄，那些 repo 一旦跑過 `--correct`（有了歸檔），這類指令就會被擋。cd 進歸檔之後只讀不改權限，會因 `0000` 讀不到；Windows 沒有 `0000`，此時無保護（已列入限制）。

第 23 輪：每個片段先做 POSIX 正規化（`archive//`、`.claude/./.idd`、中間的 `..`）；指令裡指名的 `.claude/.idd` 若確實有歸檔，從任何工作目錄都擋（只在文字已符合後 stat 那個目錄）；`cd archive` 也算；工作目錄只是在 `.claude/` 底下（例如 worktree）不觸發；檢查超過 5 秒由 watchdog 拒絕。`onFailure: "block"` 不採用：它在 python3 不存在或 hook 無法啟動時會擋下每一個呼叫，與「hook 的 bug 不得擋住整個 session」相衝。

第 22 輪：歸檔附近的相對路徑也改成純文字判斷——指向 `archive/` 之下的相對路徑，配上工作目錄或指令裡的 `.claude`／`.claude/.idd`，就擋；不再 stat 指令裡的詞。Windows：正規化改用 `posixpath`，第一層的字串比對在 Windows 上才會成立；第二層（權限 `0000`）在 Windows 上本來就無效，且未在 Windows 實機測過。

代價：在含歸檔的 repo 與其上一層資料夾，同時含兩個字的指令都被擋（別的程式的 `-R`、`cp -R` 加 `chmod +x`、`gh … -R owner/repo` 加 `chmod 600`、寫 script 的 heredoc、`grep -R chmod .`），拒絕訊息指向分開執行、Write 工具、Grep 工具與不加 `-R` 的寫法。限制：從其他目錄指名這個 repo（或在同一行 `cd` 進去）的遞迴改權限不檢查。

### 標記只留 backup-id，放在被取代區段末端

標記 `<!-- idd:edit mode="correct" backup-id="..." date="..." -->` 不含路徑。放在被取代區段的最後一行：放在正文最尾會落進 `## Current Status`，下次 `idd-update` 重建該區時會被刪掉。沿用既有 `emit-audit-marker` 產生，維持引號與 `-->` 的跳脫；`backup-id` 值不符格式時 `emit-audit-marker` 回 exit 2，讓「標記不含路徑」由程式保證。實際寫入的標記由 `_correct_marker` 組成，`date` 是本地日期（第 12 輪，#406）；`emit-audit-marker` 也用同一個本地日期（第 13 輪，兩者原本一個用 UTC、一個用本地）。

### 還原整個目標，內容不經 stdout

還原分兩步。先查：`restore --target <comment:<id>|issue:<N>> --repo R` 列出這份 clone 為這個目標與 repo 歸檔的每個版本（第 13 輪起以本機歸檔為準，標記只用來註明它是否還在目標上），每個印一行 `BACKUP_ID=<id>`，不寫入任何東西；標記是 GitHub 上誰都能寫的內容，所以 agent 不從標記抄值進指令（verify 第 8、9 輪）。第 11 輪在只剩一個 id 時直接還原，第 12 輪（verify 第 10 輪）改為一律只查詢，讓寫入一定跟在使用者確認要還原哪一版之後。再寫：使用者選定版本後，`restore '<BACKUP_ID>' --repo R` 驗證 id 格式（擋路徑穿越），從 id 推出目標，把歸檔內容經 stdin 交給 `gh api -X PATCH ... -F body=@-`，只印目標 URL 與 byte 數。還原的是整個目標，更正之後的修改（例如 `idd-update` 重建的 Current Status）會一起還原；skill 在確認提示中明說這點。沿用既有「災難復原不經 egress 網」的理由：還原的是先前已公開的內容。

### Key Decisions 改為每次重建

`idd-update` 的 Key Decisions 原本只追加、沿用上一版；被 `--correct` 就地更正的決定會一直留在摘要裡，正好重演 #351 要解決的問題。改為每次執行都從 comments 當下的內容重建。使用者於 2026-10-10 決定。

### 偵測錯誤的 skill 只提議

`idd-verify`、`idd-diagnose`、`idd-reorganize` 在自己的報告加 `### Proposed Corrections`，每項含目標、段落、一句話說明錯在哪、可直接執行的指令。指令那一格是提議：它貼在 GitHub 上，協作者改得到，所以 attended 執行時由 skill 用自己的值重組引數（目標 id 全為數字、section 是 ATX 標題行），照 idd-edit Step 1 以單引號包住每個引數，不照貼那一格；`--correct` 不發佈 `--reason`，指令也不帶它（第 12 輪）。attended 逐項問是否現在執行；unattended 只列不做。這三個 skill 不碰歸檔、不 PATCH，所以 hook 只需放行 helper 一個寫入者。

### idd-comment errata 依作者分流

目前 gh 使用者本人的 comment → 轉給 `idd-edit --correct --repo <檢查作者時用的 repo>`，不另貼 errata comment；更正被拒絕或寫入失敗（exit 4）時改貼 errata，再提議 `--prepend-note` 指向它（第一個非空行是 ATX 標題或 IDD 標記時不加，以免其他 skill 認不出這則 comment；拒絕原因是 egress 時不轉述更正內容）。其他人的 comment（含 OWNER 由別人執行時、bot）→ 只貼 errata comment，不加指標（2026-10-17 使用者決定：別人的話不動）。

### --correct 的流程在 helper，不在 SKILL 的 bash

第 1 到第 4 輪 verify 每輪都在 SKILL.md 的 `--correct` bash 流程上找到缺陷，第 3、4 輪的 blocking 還都出自前一輪自己的修正（findings 42 → 52 → 63）。共同原因是這段流程（讀原文、檢查、組內文、egress、歸檔、寫入、讀回）只有字串層的契約測試，從沒有被實際執行過——第 4 輪的 CRITICAL（macOS 的 `$TMPDIR` 被路徑閘門擋下）就是這樣溜過去的。這與 #154 → #155 同類，處理方式也相同：流程搬進 helper 的 `correct-prepare`／`correct-apply`／`correct-discard`，SKILL 只剩「準備、顯示預覽、套用或丟棄」，`scripts/tests/correct-flow/` 用假的 gh 端到端地跑整條流程（含 `TMPDIR` 在 `/var` 下的情況）。歸檔改在行程內呼叫，不再經過 `--from-file` 的路徑閘門。使用者 2026-10-16 選定此做法。

### 整次執行的狀態在 helper，不在 shell（第 9 輪）

第 6、7 輪的 HIGH 同源：SKILL 把一次 `/idd-edit` 寫成橫跨使用者確認的一段 bash，但預覽、確認、寫入是不同的 Bash 呼叫，shell 變數、陣列、迴圈的 `continue` 與整次的結束碼都留不下來。第 8 輪只補印了 WORK／STATE，確認區塊仍讀 `MODE`、`TARGET`、結果陣列，而且在 zsh 下 `continue` 會讓已寫入的呼叫以 exit 1 結束；本分支還讓 `--append` 等既有 mode 的確認後步驟依賴前面設的變數。使用者 2026-10-17 選定把整次執行的狀態搬進 helper：`run-start`／`prepare`／`apply`／`discard`／`finish`，狀態放在私有 run 目錄，SKILL 每一步只是一行指令、只帶前一步印出的字面值，結束碼由 `finish` 算。`scripts/tests/edit-run/` 把 SKILL 的每個區塊抽出來，用空環境的 zsh 與 bash 各跑一次。替代方案是只讓 `--correct` 的區塊自足、其他 mode 還原：改動較小，但兩套做法並存，而既有 mode 的同一個缺陷仍在。

### 不屬於任何標題的文字是已知限制

issue 正文最後一條 `---` 之下（IC_R011 的 `**Source**` 註腳）或第一個標題之前的文字，`--section` 搆不到，issue 正文也沒有整則範圍。使用者 2026-10-17 決定列為已知限制、不新增範圍：這類錯誤用 `/idd-comment --type correction` 追加更正（`--type errata` 需要 comment id，正文沒有）。

## Implementation Contract

**helper 子命令（`plugins/issue-driven-dev/scripts/idd-edit-helper.py`）**

| 子命令 | 輸入 | 成功輸出 | 失敗 |
| --- | --- | --- | --- |
| `parse-args` | 新增 `--correct` 與 `issue:<N>` target | eval 用的 assignments，`MODE=--correct`（沿用既有以旗標為值的慣例），`TARGETS` 保留 `issue:<N>` 原樣（第 9 輪起 SKILL 不再 eval 這些輸出：run-start 在行程內解析）；多行 `--body-file` 內容以 ANSI-C quoting（`$'...'`）輸出 | `--correct` 缺 scope/section 或正文用 whole → exit 3；`--correct` 併用 `--override-user-content` → exit 2；`issue:<N>` 配 `--correct` 以外的模式 → exit 2 並指向 #347；id 非數字 → exit 2 |
| `check-correction <old-file> <section|-> <new-file>` 的段落不存在 | — | — | exit 1（與 `section-replace` 一致） |
| `check-correction <old-file> <section-heading|-> <new-file>` | 原文、目標段落（`-` 表示整則 comment）、新段落（開頭與目標相同的標題行先去掉） | 無輸出，exit 0 | 受管區或 verbatim 區塊被改、替換內容新增同級以上標題或分隔線 → exit 6，stderr 指名區域與負責 skill；範圍內有 setext 標題、或替換內容新增 setext 標題 → exit 6（prepare／apply 記為 `setext`）；標題重複 → exit 9 |
| `validate-target <comment-id|issue:<N>> <repo> <override> [<mode>]` | 新增 `issue:<N>`（檢查 issue 作者）與「目前登入的 gh 使用者本人」放行（四種 mode 都適用）；第 4 個參數為 `--correct` 時只放行本人（OWNER 由別人執行時不放行、bot 不放行、override 不適用，判斷在 override 之前；2026-10-17 使用者決定）；test mode 不呼叫 `gh api user`，`GH_USER` 只在作者資料也是 mock 時採用 | exit 0 | 作者不是 OWNER、bot 或目前登入的 gh 使用者（且未 override）→ exit 4；`--correct` 時 bot 或他人 exit 4，訊息指向 errata、不提 override；`--correct` 且查不到 gh 使用者 → exit 1 |
| `compose-correction <old-file> <section|-> <body-file> <marker>` | 原文、目標段落（`-` 為整則）、更正內容、標記（預覽用 `(assigned after confirmation)` 佔位） | 寫入用的完整內文：段落換成新內容，開頭重複的目標標題去掉，區段內所有整行 IDD 標記（`<!-- idd:… -->`）保留一次、放在新標記之前；替換範圍以外的內容逐位元組保留（CRLF、結尾有無換行）；整則更正時原文頂端的標記固定在頂端，替換內容裡的重複一份刪掉 | 檔案不可讀 → exit 5；標記格式不符 → exit 2；段落不存在 → exit 1；標題重複 → exit 9；組好的內文在區段外的解析結果改變、或標記不自成 HTML 區塊／落在 code 裡（替換內容留下沒關閉的 fence 或 HTML 註解）→ exit 6；Markdown parser 缺或版本不符 → exit 8 |
| `correct-prepare --target T --repo R (--section H \| --scope whole-comment) --body-file F --scrub-attested L` | 目標、repo、範圍、更正內容 | stdout `WORK=`、`PREVIEW=`、`STATE=`（state.json 的 sha256，由 SKILL 保存、交給 apply）；工作目錄（使用者暫存目錄下、0700）存 backup、body、preview 與帶各檔 sha256 的 state.json；開始前清掉一天以上的殘留工作目錄 | 參數錯、缺 `--scrub-attested`（helper 不代填）、更正內容去掉目標標題後為空 → exit 2；範圍錯（issue 正文用 whole-comment 等）→ exit 3；body file 被擋 → exit 5；其餘拒絕 → exit 4 並印 `RESULT=refused`、`REASON=`（fetch-failed〔含回應沒有 body 欄位、comment 的 body 為 null〕、R5、author-unknown、archive〔歸檔前置檢查，含目錄能否建立〕、empty〔整則更正只剩頂端標記〕、protected、setext、unclosed-block、section-not-found、section-ambiguous、parser-unavailable、egress、check-failed），工作目錄刪除；stdout 另有 `DIFF=`。順序：抓原文（`gh api` 的 JSON `body`，原樣）→ 作者閘門 → 歸檔前置檢查（被拒的目標不在 repo 裡留下任何東西）→ 受管區與範圍檢查 → 組預覽 → egress 預檢 |
| `correct-apply --work W --state S` | prepare 印出的工作目錄與 `STATE`（在一次 run 裡由 `apply` 從 Step 2 prepare 印出的值照抄、轉給它） | `RESULT=edited`、`BACKUP_ID=`、`URL=`；結束時刪除工作目錄 | 不是 prepare 建的目錄 → exit 2；state.json 只讀一次（算雜湊與解析用同一份位元組），sha 不符、欄位格式不對、檔案被動過、重組不等於預覽 → `differs-from-preview`；作者閘門與受管區檢查在重抓之前重跑，拒絕理由同 prepare；重抓失敗 → `fetch-failed`；目標變了 → `changed-since-preview`；歸檔失敗 → `archive`；egress 拒絕 → `egress`（以上 exit 4）；gh 寫入報錯時重讀一次：仍等於 backup → `RESULT=write-failed`（exit 4，歸檔已寫），否則（含讀不到）→ `RESULT=unverified`（exit 7）；讀回與送出的不是逐位元組相同 → `RESULT=unverified`（exit 7）；歸檔之後的任何例外 → `RESULT=unverified`、`REASON=exception`（exit 7）。已歸檔的結果都印 `BACKUP_ID=` |
| `correct-discard --work W` | 同上 | 刪除工作目錄 | 不是 prepare 建的目錄 → exit 2 |
| `run-start [--default-repo R] -- <args>`（`--body-file` 開頭的 `~`／`$HOME` 展開為家目錄；同一 target 只列一次；沒有 mode、`--correct` 只剩目標標題、`#N --last` 沒有 comment → exit 2） | `/idd-edit` 的引數（經 parse-args 的全部閘門）、config 解析出的 repo | stdout `RUN=`、`REPO=`、`SCRUB=`（隱私等級：third-party enforce／own public warn／private light，查不到 → enforce）、每個 target 一行 `TARGET=`，`#N` 沒有 `--last` 時 `PICK=#N`；run 目錄（使用者暫存目錄下、`idd-run-` 開頭、0700）存解析結果與內文 | parse-args 的碼原樣（2／3／5）；沒有 repo → exit 2；`--last` 讀不到 comments → exit 1 |
| `prepare --run RUN --target T [--pick N]` | run 與 target；T 只能是 run-start 列出的 `TARGET=`，或為尚未處理的 `PICK=#N` 選出的 comment（帶 `--pick N`，helper 確認它屬於 #N） | `--correct`：轉給 correct-prepare，另印 `DIFF=`；其他 mode：作者閘門（含 override）、讀原文、備份到使用者暫存目錄的 `idd-edit-backup/`、組新內文、egress 預檢，印 `PREVIEW=`、`DIFF=`、`BACKUP=`；PICK 選到的是這次 run 已有的 target → 印 `RESULT=merged`、exit 0，由那個 target 處理 | 沒列出、也沒帶 `--pick` 的 target → exit 2；`--pick N` 不是這次 run 尚未處理的 PICK → exit 2；選出的 comment 不屬於 #N → exit 4，`RESULT=refused`、`REASON=not-in-pick`；其他拒絕 → exit 4，`RESULT=refused`、`REASON=`（R5、author-unknown、fetch-failed、stage-failed、egress、section-not-found、section-ambiguous、parser-unavailable，及 correct-prepare 的各項）；同一 target 第二次 prepare → exit 2 |
| `apply --run RUN --target T --scrub-attested L [--state S]` | 前一步印出的值 | `RESULT=edited`、`URL=`（`--correct` 另有 `BACKUP_ID=`）；寫入以 L 送出（`SCRUB=` 印出實際等級；L 可以比 run 的等級嚴、不可以寬，`--correct` 也一樣）；帶 `type=reply` 與 `points-from=user-pasted` 的 reply comment 受 #272 約束（不論等級，第 14 輪）：prepare 至少以 `warn` 預檢並印 `FLOOR=272`（不印會被照抄的 `SCRUB=`），skill 問過 #272 那一題才 apply，run 的等級是 light 時改以 `warn` 證明；apply 對這種內文拒收 `light`（exit 2、不記錄），helper 不代為升級（第 13 輪：第 12 輪由 helper 自動升級，等於放行了沒問過的第三方原話） | L 比這個 run 的等級寬 → exit 2（更嚴可以）；`--state` 與 prepare 印的不符 → exit 2、不記錄，可重抄再試；`--state ""` 是空值（非 `--correct`）；沒有 prepared 的紀錄 → exit 2；新內文被動過 → `differs-from-preview`；作者閘門重跑（R5／author-unknown）；重抓失敗 → `fetch-failed`；目標在預覽後被改過 → `changed-since-preview`（與 `--correct` 相同，不覆蓋別人的新修改）；egress 拒絕（rc ≥ 10）→ egress 桶；gh 寫入報錯 → 重讀：未變 `write-failed`（exit 4）、已變或讀不到 `unverified`（exit 7）；讀回不是逐位元組相同 → `unverified` |
| `discard --run RUN --target T` | 同上 | 記為 declined，刪除工作副本 | 沒有 prepared 的紀錄 → exit 2 |
| `finish --run RUN` | 同上 | outcome report；刪除 run 目錄，以及 prepare 後沒有 apply／discard 的 `--correct` 工作副本；任何 mode 的這種 target 都記為 `not-applied`、算 declined | 結束碼依序：有拒絕（含 Step 1 列出卻沒 prepare 的 `not-prepared`、沒選的 PICK `not-picked`）或寫入失敗 4、有 unverified 7、有 declined（含 prepare 後沒有 apply 或 discard 的 `not-applied`，第 13 輪起）9、否則 0；沒有任何 target 被 prepare → 4 |
| `existing-mentions <file>` | 目標原文 | 以逗號分隔的、原文已經提及的帳號（用 gh-egress 同一個 parser 與 token 規則） | 掃描失敗 → exit 1 |
| `section-replace ... [--stop-at-rule]` | 既有子命令，新增 `--stop-at-rule` | 取代後全文 | 段落邊界取自 Markdown parser：同級或更高的頂層 ATX 標題（setext 不結束段落，`--replace` 照舊取代過去）；標題重複 → exit 9；`--stop-at-rule` 時另有頂層分隔線與受管標題；code、HTML 區塊內的行不結束段落；`--section` 不是標題 → exit 2；parser 缺或版本不符 → exit 8，不改任何東西 |
| `parse-args` | — | 每個值 eval 後與原值相同：含換行或控制字元的值用 ANSI-C quoting，`=` 一律跳脫 | `--section` 不是 markdown 標題行 → exit 2（每個 mode）；`--correct` 沒有替換內容 → exit 2；`--body-file` 含 NUL → exit 5 |
| `archive <comment|issue> <id> --from-file <path> --repo R` | 目標類型、id、預覽用的原文檔（經 #155 路徑閘門）、repo | stdout 只有 backup-id；另寫 `<backup-id>.repo` sidecar 記錄 repo | 原文檔不可讀 → exit 5；不在 git work tree／未被 ignore／寫入失敗 → exit 7，不留檔；歸檔路徑上任一層是 symlink 或巢狀 git repo → exit 7；`.md` 與 `.repo` 都以 exclusive 方式建立，任一已存在就換下一個後綴 |
| `emit-audit-marker edit mode=correct backup-id=<id>` | 既有子命令 | 標記一行 | `backup-id` 不符格式 → exit 2 |
| `restore --target <comment:<id>\|issue:<N>> --repo R` | 目標與 repo（都不從 GitHub 抄值） | 只查詢：列出這份 clone 為這個目標、這個 repo（sidecar）歸檔的每個版本，依時間由舊到新各印一行 `BACKUP_ID=<id>`，stderr 註明目標上是否還有它的標記（第 13 輪起以本機歸檔為準：`--replace` 或 restore 會拿掉標記，原本就找不到仍在的版本）；不寫入任何東西，只有一個 id 時也一樣（第 11 輪會直接還原）。寫入是使用者確認要還原哪一版之後的 `restore '<BACKUP_ID>' --repo R`；有 id 時 exit 0 | 參數不符格式 → exit 2；不在有歸檔的 git work tree → exit 7；讀不到目標 → exit 1；沒有任何已檢查的 id → exit 2 |
| `restore <backup-id> --repo R` | backup-id | stdout：目標 URL 與 byte 數 | id 格式不符、歸檔或 sidecar 是 symlink、歸檔被 git 追蹤、sidecar 缺少或其 repo 與 `--repo` 不符 → exit 2；檔案不存在 → exit 5；PATCH 失敗 → 透傳 gh 非零碼；歸檔路徑上任一層是 symlink 或巢狀 git repo、repo 追蹤歸檔目錄下任何路徑（不分大小寫）→ exit 2 |

helper 子命令既有的 exit code（0／1／2／3／4／5）語意不變；一次 `/idd-edit` 的結束碼改由 `finish` 決定，既有 mode 的變化見 Migration Plan 第 2 項與 CHANGELOG。所有子命令都不得把歸檔內容寫到 stdout 或 stderr。

**hook（`plugins/issue-driven-dev/hooks/archive-read-guard.py`）**：輸入為 PreToolUse JSON；命中時輸出 `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"..."}}` 並 exit 0；未命中或無法解析時無輸出、exit 0。

**`idd-edit` SKILL.md**：`--correct` 模式標註 `(category: in-place-correction)`；Task 清單是六項（start_run、prepare_targets、privacy_scrub_gate、preview_and_confirm、apply_or_discard、finish_run；第 9 輪起取代 `check_correction` 與 `archive_before_patch`）；執行的 bash 中不得出現歸檔路徑字面值；「Backup 管理」改寫為 `restore` 用法，並說明人要讀歸檔時在自己的終端機 `chmod u+r`，不要經過 Claude。

**驗收（自動化）**：`scripts/tests/in-place-correction/test.sh` 涵蓋 parse-args、check-correction 的四列範例、標記格式與位置；`scripts/tests/correction-archive/test.sh` 涵蓋 archive 的命名、碰撞、exclude 與 check-ignore、權限 0000、遞迴 grep 讀不到、restore 的 id 驗證與輸出不含內容、hook 對每種工具與欄位的 deny／allow；兩支都納入 `run-all-tests`。既有 `scripts/tests/idd-edit/` 與 `scripts/tests/idd-edit-contract/` 維持全綠。

**驗收（手動，一次）**：在本 repo 對一則測試 comment 跑完整 `--correct` 流程，確認 GitHub 上只剩更正版與標記、`git status` 乾淨、Claude 的 `Read` 與 `Grep` 讀歸檔被拒絕。

**範圍**：In — 上表子命令、hook、`idd-edit`／`idd-comment`／`idd-verify`／`idd-diagnose`／`idd-reorganize` 的 SKILL.md、規則檔、本 repo `.gitignore`、CHANGELOG 與版本。Out — Non-Goals 所列各項。

## Risks / Trade-offs

- [已知限制（完整清單，spec、hook docstring、CHANGELOG 同一份）：（1）paths or flags assembled from variables, globs, brace expansion, `$'…'` escapes, eval, command substitution or tilde prefixes such as `~+`；（2）another program that changes modes (a `python -c` one-liner, for example)；（3）recursive permission changes run from a directory that is not near the archive (user decision 2026-10-18)；（4）a program option that changes directory before the permission command — `env -C`/`--chdir`, `sudo -D`, `make -C`, `git -C`, `uv --directory`, `pwsh -WorkingDirectory`, … (user decision 2026-10-19)；（5）a `.claude` named after an earlier `cd`, or split by a character outside `[\w./~+@%-]`, from a directory not near the archive；（6）a working directory under `.claude/` that is neither `.claude` nor inside `.claude/.idd` (a worktree), followed by a `cd`；（7）other ways to change directory: the zsh two-argument `cd`, an alias of `cd`, zsh `AUTO_CD` and bash `shopt -s autocd`, a `cd` inside a sourced file or a shell function, PowerShell's `SessionState.Path.SetLocation`；（8）a symlink named in the command；（9）a read without a permission change after a `cd` into the archive — it fails on mode 0000, except as root, which ignores the mode, and on Windows, where mode 0000 does not apply；（10）PowerShell's `.ForEach()` and comma arrays, and a pwsh run from Bash through a path the guard does not read as a program name (a quoted Windows path to `pwsh.exe`)] → 接受（使用者 2026-10-18、2026-10-19 決定）：threat model 是無意間讀到。

- [hook 比對文字、實際執行的是 shell，兩者必然有落差（各項見上一條的完整清單）] → 接受：hook 只擋無意間的 `cat`／`grep`／Read；保證讀不到的是第二層權限 `0000`。threat model 是「無意間讀到」，不是刻意繞過。fail-closed 的決定與代價見 Decisions〈read guard fail-closed〉。另一個代價：IDD 自己的發文若在指令裡帶了提到路徑的文字，會先被擋一次，改用 `--body-file` 即可。
- [以 root 執行的程序不受權限限制] → 見 Risks 第一條完整清單第 9 項；IDD 不以 root 執行。
- [本機歸檔只在一台機器] → GitHub 編輯紀錄保有每一版；歸檔是可用 ID 找到的本機副本。
- [restore 會蓋掉更正之後的修改] → 確認提示明說；還原後可再跑 `idd-update` 重建 Current Status。
- [ripgrep 遇到權限 0000 的檔案會在 stderr 印 Permission denied] → 只洩漏檔名，檔名本身只含 comment id 與時間。
- [errata 對自己 comment 的行為改變] → CHANGELOG 標為行為面 BREAKING，說明新舊差異。
- [hook 套用在所有 IDD 使用者的每一次 Read／Grep／Glob／Edit／Write／NotebookEdit／Bash／PowerShell／Monitor 呼叫，實測每次約 40–45 ms（Python 啟動；第 20 輪量測）] → 接受：比對全是字串運算，從不 stat 指令裡的詞（第 21 輪曾對每個詞 `isdir`，一個卡住的掛載點就讓呼叫卡到逾時，第 22 輪拿掉）；只有在含權限指令與遞迴標記、或出現指向歸檔內部的相對路徑時，才查工作目錄（往上各層一次 `stat`、一次 `listdir`）。hook 設 10 秒逾時，hook 內另有 5 秒的 watchdog 先行拒絕（逾時本身會讓呼叫照常執行）；系統呼叫卡在不可中斷的等待時 watchdog 也無法讓程序準時結束，此時由第二層權限兜底；若日後成為瓶頸，改成先用 shell 內建字串比對過濾、命中才啟動 Python。

## Migration Plan

1. 實作與測試完成後 bump plugin 版本、更新 CHANGELOG 與 `plugin.json` 描述，經 `/plugin-update` 發佈。
2. 既有 mode 的備份改到使用者暫存目錄下的 `idd-edit-backup/`（Linux 上通常仍是 `/tmp`；macOS 在 `/var/folders/…`），3.4.0 留下的 0755 目錄由 helper 收緊為 0700；舊備份不搬遷（本來就是暫存）。`--replace` 標記的 `backup=` 改寫成 `idd-edit-backup/<檔名>`，不帶本機絕對路徑。結束碼見 run 的契約列：拒絕預覽 9、寫入失敗 4、讀回不符 7（3.4.0 都是 0）。
3. 封存（archive）本 change 後，把 `append-vs-modify-discipline` spec 的 Purpose 段落從「7-category」改為「8-category」（Purpose 不在 delta 範圍內，封存不會改到）。
4. 回滾：移除 `hooks.json` 中的 PreToolUse 項目、revert 規則與 SKILL.md；已寫入的歸檔檔留在原處，不影響其他功能。

## Open Questions

（無）
