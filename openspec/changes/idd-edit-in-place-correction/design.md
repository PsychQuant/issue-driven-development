## Context

#351 的起點是老師的回饋：issue 是下游 skill 與日後 session 的記憶，錯誤留在原處、只在後面追加更正，讀的人仍會照錯的做。現況有四處跟這個需求衝突：

- `append-vs-modify` 規則把已發佈的 comment 歸為 `append-only`，把 issue 正文 `---` 以上整段歸為 `verbatim-preserve`。
- `idd-comment --type errata` 的流程是另貼一則 errata，再到原 comment 頂端加警示；錯的內容留在原處。
- `idd-edit` 只能編 comment（#347），備份寫在 `/tmp/idd-edit-backup/`、約七天後消失，marker 寫出備份路徑。
- IDD plugin 只有 SessionStart hook，沒有任何擋讀取的機制。

使用者在 #351 與 spectra-discuss 已定案：AI 提議、使用者確認後才取代；協作者寫的 comment 不改；`Original text` 引用區不改；舊版存 `.claude/.idd/archive/edits/`、不進 git、本機永久保留，遠端的永久紀錄交給 GitHub 自帶的編輯紀錄；hook 擋 AI 讀取；GitHub 編輯紀錄不擋。

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

在封閉列舉加一類，並把 `verbatim-preserve` 縮成「`Original text` 引用區塊＋OWNER、bot、目前 gh 使用者以外的人寫的 comment」兩種。bot 的 comment 不在 `verbatim-preserve` 內，但仍是第三方的話，`--correct` 不改（verify 第 2 輪）。替代方案是直接放寬 `append-only`，但 `append-only` 也管 CHANGELOG 與 Spectra 歸檔快照，一起放寬會讓不該改的東西變得可改。spec 的類別數寫進了需求名稱（`Canonical 7-category enumeration ...`），因此以 REMOVED＋ADDED 換成不含數字的名稱，避免下次加類別又要改名。

### --correct 是獨立模式，不是 --replace 加旗標

模式與類別一對一：`--replace` 維持 `bounded-section-replace`（一般改寫），`--correct` 對應 `in-place-correction`（錯誤更正，強制歸檔、禁止 override）。共用 `--scope whole-comment`／`--section` 與 section-replace 邏輯。替代方案 `--replace --error` 會讓同一模式依旗標落在兩個類別，違反「每個動作宣告一個類別」。

### 正文目標只接受 --section，並拒絕保護區

正文目標語法 `issue:<N>`，只接受 `--section <heading>`。整段取代正文會一起覆蓋 `Original text`、`## Current Status`、`### Clarity Surface`，所以不開放。保護區判定由 helper 的 `check-correction` 子命令執行：

- 受管區：`## Current Status`（含其下巢狀標題，歸 `idd-update`）與 `### Clarity Surface`（歸 `idd-clarify`）。目標段落本身是受管區 → exit 6。`### Clarity Surface` 常巢狀在 `## Related` 底下：第 1 版把「包含受管區」也一律拒絕，手動驗收發現這讓 `## Related` 永遠改不了，所以改成更正的段落遇到受管標題（或 `---`）就結束，只換它上面的內容（使用者 2026-10-10 決定）。
- verbatim 區塊：原 section 中「連續以 `>` 開頭、且其中一行含 `Original text`」的最大區塊，必須在取代內容中逐 byte 出現 → 否則 exit 6。

### 確認後才歸檔，歸檔成功才 PATCH

順序是預覽 → 確認 → 重抓目標比對 → `archive` → PATCH。確認之後重新抓一次目標，與預覽時的原文比對；不一致就拒絕、不歸檔也不 PATCH，避免使用者確認的版本與實際被取代的內容不同。`archive` 以 `--from-file` 讀入預覽時給使用者看的那份原文，不自己向 GitHub 重抓：重抓可能拿到中間被改過的版本，歸檔就不再等於實際被取代的內容。PATCH 成功後刪掉 `/tmp` 裡的工作副本。歸檔是受保護、Claude 的工具讀不到的那一份，不是唯一的一份：GitHub 的編輯紀錄保有舊版，暫存與 scratch 副本也可能留下舊版，後者在 #378 追蹤。使用者拒絕時不留任何檔案；歸檔失敗（不在 git work tree、路徑沒被 ignore、寫入失敗）一律 exit 7，skill 不 PATCH。替代方案「先歸檔再確認」會在拒絕時留下沒有對應更正的歸檔檔。

### 歸檔寫進 .git/info/exclude，不改 tracked 的 .gitignore

helper 用既有的 `scripts/git-ignore-block.sh --direction exclude` 把 `.claude/.idd/archive/` 寫進 `.git/info/exclude`，再用 `git check-ignore` 驗證。`.git/info/exclude` 是每個 clone 自己的設定、不會被 commit，不會在其他使用者的 repo 裡改動 tracked 檔（與 #192 third-party clone 的做法一致）。本 repo 另在 `.gitignore` 加一行，讓維護者在任何 clone 都一致。使用者決定的本意是「不進 git」，這個做法達成同一件事；若使用者要求一律改 `.gitignore`，只需換掉 helper 的寫入目標。使用者已於 2026-10-10 確認採用 `.git/info/exclude`。

歸檔根目錄是 main worktree（由 `git rev-parse --git-common-dir` 推出），不是當下的 linked worktree：從 linked worktree 寫入的歸檔才不會隨 `git worktree remove` 消失。

### 雙層擋讀：hook 加上檔案權限 0000

第一層是 PreToolUse hook：工具參數或指令字串含 `.claude/.idd/archive` 就拒絕，並告訴 AI 原因與正確的還原方式。比對不分大小寫（macOS 檔案系統不分大小寫），路徑欄位先以 `os.path.normpath` 正規化，Glob／Grep 另外檢查 `path` 與 `pattern`／`glob` 合併後的路徑。第二層是歸檔檔權限 `0000`：hook 只能比對字串，攔不到 `grep -r . `、`rg --no-ignore` 這類不寫出路徑的遞迴讀取；權限讓這些指令讀不到內容。`restore` 是唯一會暫時開放讀取權限的地方，並在結束時（含失敗）設回 `0000`。

### hook 以 Python 實作，輸入無法解析時放行

hook 腳本 `hooks/archive-read-guard.py` 用 stdlib `json` 解析 stdin，與 helper 同屬 Python 層（bash 字串解析在 #154 已證明難收斂）。輸入無法解析時放行並寫一行 stderr：若改成拒絕，hook 本身的 bug 會擋掉整個 session 的所有工具呼叫；第二層權限仍在。matcher 用確切名稱清單 `Read|Grep|Glob|Edit|Write|NotebookEdit|Bash|PowerShell`（官方文件：只含字母與 `|` 的 matcher 是精確比對，`Bash` 不會誤中其他工具）。

### 標記只留 backup-id，放在被取代區段末端

標記 `<!-- idd:edit mode="correct" backup-id="..." date="..." -->` 不含路徑。放在被取代區段的最後一行：放在正文最尾會落進 `## Current Status`，下次 `idd-update` 重建該區時會被刪掉。沿用既有 `emit-audit-marker` 產生，維持引號與 `-->` 的跳脫；`backup-id` 值不符格式時 `emit-audit-marker` 回 exit 2，讓「標記不含路徑」由程式保證。

### 還原整個目標，內容不經 stdout

`restore <backup-id> --repo R` 驗證 id 格式（擋路徑穿越），從 id 推出目標，把歸檔內容經 stdin 交給 `gh api -X PATCH ... -F body=@-`，只印目標 URL 與 byte 數。還原的是整個目標，更正之後的修改（例如 `idd-update` 重建的 Current Status）會一起還原；skill 在確認提示中明說這點。沿用既有「災難復原不經 egress 網」的理由：還原的是先前已公開的內容。

### Key Decisions 改為每次重建

`idd-update` 的 Key Decisions 原本只追加、沿用上一版；被 `--correct` 就地更正的決定會一直留在摘要裡，正好重演 #351 要解決的問題。改為每次執行都從 comments 當下的內容重建。使用者於 2026-10-10 決定。

### 偵測錯誤的 skill 只提議

`idd-verify`、`idd-diagnose`、`idd-reorganize` 在自己的報告加 `### Proposed Corrections`，每項含目標、段落、一句話說明錯在哪、可直接執行的指令。attended 逐項問是否現在執行；unattended 只列不做。這三個 skill 不碰歸檔、不 PATCH，所以 hook 只需放行 helper 一個寫入者。

### idd-comment errata 依作者分流

OWNER 或目前 gh 使用者本人的 comment → 轉給 `idd-edit --correct`，不另貼 errata comment。其他人的 comment（含 bot）→ 只貼 errata comment，不再嘗試 prepend-note（舊流程會被 R5 擋下並印出 override 提示，而新規則下協作者 comment 不改，提示 override 會誤導）。

### --correct 的流程在 helper，不在 SKILL 的 bash

第 1 到第 4 輪 verify 每輪都在 SKILL.md 的 `--correct` bash 流程上找到缺陷，第 3、4 輪的 blocking 還都出自前一輪自己的修正（findings 42 → 52 → 63）。共同原因是這段流程（讀原文、檢查、組內文、egress、歸檔、寫入、讀回）只有字串層的契約測試，從沒有被實際執行過——第 4 輪的 CRITICAL（macOS 的 `$TMPDIR` 被路徑閘門擋下）就是這樣溜過去的。這與 #154 → #155 同類，處理方式也相同：流程搬進 helper 的 `correct-prepare`／`correct-apply`／`correct-discard`，SKILL 只剩「準備、顯示預覽、套用或丟棄」，`scripts/tests/correct-flow/` 用假的 gh 端到端地跑整條流程（含 `TMPDIR` 在 `/var` 下的情況）。歸檔改在行程內呼叫，不再經過 `--from-file` 的路徑閘門。使用者 2026-10-16 選定此做法。

## Implementation Contract

**helper 子命令（`plugins/issue-driven-dev/scripts/idd-edit-helper.py`）**

| 子命令 | 輸入 | 成功輸出 | 失敗 |
| --- | --- | --- | --- |
| `parse-args` | 新增 `--correct` 與 `issue:<N>` target | eval 用的 assignments，`MODE=--correct`（沿用既有以旗標為值的慣例），`TARGETS` 保留 `issue:<N>` 原樣、由 SKILL 依前綴分辨目標類型；多行 `--body-file` 內容以 ANSI-C quoting（`$'...'`）輸出 | `--correct` 缺 scope/section 或正文用 whole → exit 3；`--correct` 併用 `--override-user-content` → exit 2；`issue:<N>` 配 `--correct` 以外的模式 → exit 2 並指向 #347；id 非數字 → exit 2 |
| `check-correction <old-file> <section|-> <new-file>` 的段落不存在 | — | — | exit 1（與 `section-replace` 一致） |
| `check-correction <old-file> <section-heading|-> <new-file>` | 原文、目標段落（`-` 表示整則 comment）、新段落 | 無輸出，exit 0 | 受管區或 verbatim 區塊被改 → exit 6，stderr 指名區域與負責 skill |
| `validate-target <comment-id|issue:<N>> <repo> <override> [<mode>]` | 新增 `issue:<N>`（檢查 issue 作者）與「目前登入的 gh 使用者本人」放行（四種 mode 都適用）；第 4 個參數為 `--correct` 時只放行 OWNER 與本人（bot 不放行、override 不適用，判斷在 override 之前）；test mode 不呼叫 `gh api user`，`GH_USER` 只在作者資料也是 mock 時採用 | exit 0 | 作者不是 OWNER、bot 或目前登入的 gh 使用者（且未 override）→ exit 4；`--correct` 時 bot 或他人 exit 4，訊息指向 errata、不提 override；`--correct` 且查不到 gh 使用者 → exit 1 |
| `compose-correction <old-file> <section|-> <body-file> <marker>` | 原文、目標段落（`-` 為整則）、更正內容、標記（預覽用 `(assigned after confirmation)` 佔位） | 寫入用的完整內文：段落換成新內容，開頭重複的目標標題去掉，區段內所有整行 IDD 標記（`<!-- idd:… -->`）保留一次、放在新標記之前 | 檔案不可讀 → exit 5；標記格式不符 → exit 2；段落不存在 → exit 1；組好的內文在區段外的解析結果改變、或標記不自成 HTML 區塊／落在 code 裡（替換內容留下沒關閉的 fence 或 HTML 註解）→ exit 6；Markdown parser 缺或版本不符 → exit 8 |
| `correct-prepare --target T --repo R (--section H \| --scope whole-comment) --body-file F [--scrub-attested L]` | 目標、repo、範圍、更正內容 | stdout `WORK=`、`PREVIEW=`、`STATE=`（state.json 的 sha256，由 SKILL 保存、交給 apply）；工作目錄（使用者暫存目錄下、0700）存 backup、body、preview 與帶各檔 sha256 的 state.json；開始前清掉一天以上的殘留工作目錄 | 參數錯 → exit 2；範圍錯（issue 正文用 whole-comment 等）→ exit 3；body file 被擋 → exit 5；其餘拒絕 → exit 4 並印 `RESULT=refused`、`REASON=`（archive〔歸檔前置檢查〕、fetch-failed、R5、author-unknown、protected、section-not-found、section-ambiguous、parser-unavailable、egress、check-failed），工作目錄刪除。順序：歸檔前置檢查 → 抓原文（`gh api` 的 JSON `body`，原樣）→ 作者閘門 → 受管區與範圍檢查 → 組預覽 → egress 預檢 |
| `correct-apply --work W --state S` | prepare 印出的工作目錄與 `STATE` | `RESULT=edited`、`BACKUP_ID=`、`URL=`；結束時刪除工作目錄 | 不是 prepare 建的目錄 → exit 2；state 的 sha 不符、欄位格式不對、檔案被動過、重組不等於預覽 → `differs-from-preview`；重抓失敗 → `fetch-failed`；目標變了 → `changed-since-preview`；作者閘門與受管區檢查重跑，拒絕理由同 prepare；歸檔失敗 → `archive`；egress 拒絕 → `egress`（以上 exit 4）；gh 寫入報錯時重讀一次：仍等於 backup → `RESULT=write-failed`（exit 4，歸檔已寫），否則 → `RESULT=unverified`（exit 7）；讀回不符 → `RESULT=unverified`（exit 7）。已歸檔的結果都印 `BACKUP_ID=` |
| `correct-discard --work W` | 同上 | 刪除工作目錄 | 不是 prepare 建的目錄 → exit 2 |
| `existing-mentions <file>` | 目標原文 | 以逗號分隔的、原文已經提及的帳號（用 gh-egress 同一個 parser 與 token 規則） | 掃描失敗 → exit 1 |
| `section-replace ... [--stop-at-rule]` | 既有子命令，新增 `--stop-at-rule` | 取代後全文 | 段落邊界取自 Markdown parser：同級或更高的頂層標題（含 setext）；`--stop-at-rule` 時另有頂層分隔線與受管標題；code、HTML 區塊內的行不結束段落；`--section` 不是標題 → exit 2；parser 缺或版本不符 → exit 8，不改任何東西 |
| `parse-args` | — | 每個值 eval 後與原值相同：含換行或控制字元的值用 ANSI-C quoting，`=` 一律跳脫 | `--section` 不是 markdown 標題行 → exit 2（每個 mode）；`--correct` 沒有替換內容 → exit 2；`--body-file` 含 NUL → exit 5 |
| `archive <comment|issue> <id> --from-file <path> --repo R` | 目標類型、id、預覽用的原文檔（經 #155 路徑閘門）、repo | stdout 只有 backup-id；另寫 `<backup-id>.repo` sidecar 記錄 repo | 原文檔不可讀 → exit 5；不在 git work tree／未被 ignore／寫入失敗 → exit 7，不留檔；歸檔路徑上任一層是 symlink 或巢狀 git repo → exit 7；`.md` 與 `.repo` 都以 exclusive 方式建立，任一已存在就換下一個後綴 |
| `emit-audit-marker edit mode=correct backup-id=<id>` | 既有子命令 | 標記一行 | `backup-id` 不符格式 → exit 2 |
| `restore <backup-id> --repo R` | backup-id | stdout：目標 URL 與 byte 數 | id 格式不符、歸檔或 sidecar 是 symlink、歸檔被 git 追蹤、sidecar 缺少或其 repo 與 `--repo` 不符 → exit 2；檔案不存在 → exit 5；PATCH 失敗 → 透傳 gh 非零碼；歸檔路徑上任一層是 symlink 或巢狀 git repo、repo 追蹤歸檔目錄下任何路徑（不分大小寫）→ exit 2 |

既有 exit code（0／1／2／3／4／5）語意不變。所有子命令都不得把歸檔內容寫到 stdout 或 stderr。

**hook（`plugins/issue-driven-dev/hooks/archive-read-guard.py`）**：輸入為 PreToolUse JSON；命中時輸出 `{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"..."}}` 並 exit 0；未命中或無法解析時無輸出、exit 0。

**`idd-edit` SKILL.md**：`--correct` 模式標註 `(category: in-place-correction)`；Task 清單新增 `check_correction` 與 `archive_before_patch`；執行的 bash 中不得出現歸檔路徑字面值；「Backup 管理」改寫為 `restore` 用法，並說明人要讀歸檔時在自己的終端機 `chmod u+r`，不要經過 Claude。

**驗收（自動化）**：`scripts/tests/in-place-correction/test.sh` 涵蓋 parse-args、check-correction 的四列範例、標記格式與位置；`scripts/tests/correction-archive/test.sh` 涵蓋 archive 的命名、碰撞、exclude 與 check-ignore、權限 0000、遞迴 grep 讀不到、restore 的 id 驗證與輸出不含內容、hook 對每種工具與欄位的 deny／allow；兩支都納入 `run-all-tests`。既有 `scripts/tests/idd-edit/` 與 `scripts/tests/idd-edit-contract/` 維持全綠。

**驗收（手動，一次）**：在本 repo 對一則測試 comment 跑完整 `--correct` 流程，確認 GitHub 上只剩更正版與標記、`git status` 乾淨、Claude 的 `Read` 與 `Grep` 讀歸檔被拒絕。

**範圍**：In — 上表子命令、hook、`idd-edit`／`idd-comment`／`idd-verify`／`idd-diagnose`／`idd-reorganize` 的 SKILL.md、規則檔、本 repo `.gitignore`、CHANGELOG 與版本。Out — Non-Goals 所列各項。

## Risks / Trade-offs

- [hook 用 shlex 解析、實際執行的是 shell，兩者必然有解析差異（變數拼出路徑、ANSI-C 跳脫、eval）；背景安全審查連續回報三次] → 接受：hook 只擋無意間的 `cat`／`grep`／Read，訊息參數含 `$`、反引號或程序替換時一律檢查；保證讀不到的是第二層權限 `0000`。threat model 是「無意間讀到」，不是刻意繞過。
- [以 root 執行的程序不受權限限制] → 不處理；IDD 不以 root 執行。
- [本機歸檔只在一台機器] → GitHub 編輯紀錄保有每一版；歸檔是可用 ID 找到的本機副本。
- [restore 會蓋掉更正之後的修改] → 確認提示明說；還原後可再跑 `idd-update` 重建 Current Status。
- [ripgrep 遇到權限 0000 的檔案會在 stderr 印 Permission denied] → 只洩漏檔名，檔名本身只含 comment id 與時間。
- [errata 對自己 comment 的行為改變] → CHANGELOG 標為行為面 BREAKING，說明新舊差異。
- [hook 套用在所有 IDD 使用者的每一次 Read／Grep／Glob／Edit／Write／Bash 呼叫，實測每次約 31 ms（Python 啟動）] → 接受：比對只做字串運算、無 I/O；若日後成為瓶頸，改成先用 shell 內建字串比對過濾、命中才啟動 Python。

## Migration Plan

1. 實作與測試完成後 bump plugin 版本、更新 CHANGELOG 與 `plugin.json` 描述，經 `/plugin-update` 發佈。
2. 既有 `/tmp/idd-edit-backup/` 的備份不搬遷（本來就是暫存）；`--replace` 仍寫 `/tmp`，行為不變。
3. 封存（archive）本 change 後，把 `append-vs-modify-discipline` spec 的 Purpose 段落從「7-category」改為「8-category」（Purpose 不在 delta 範圍內，封存不會改到）。
4. 回滾：移除 `hooks.json` 中的 PreToolUse 項目、revert 規則與 SKILL.md；已寫入的歸檔檔留在原處，不影響其他功能。

## Open Questions

（無）
