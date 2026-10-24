# Issue Write-back（討論中持續更新 issue，#424）

> **Scope**：任何使用 IDD 的 repo，只要在討論一張 issue —— 在 session 裡（不論當下有沒有 IDD skill 在跑），或在 issue 的 comments 裡。
>
> 本檔是 canonical：`plugins/issue-driven-dev/rules/issue-write-back.md`。SessionStart hook（`hooks/session-start-commit-rule.sh`）注入一行提醒；drift guard：`scripts/tests/issue-write-back/test.sh`、`scripts/tests/session-start-commit-rule/test.sh`。

Issue 正文說「現在的問題是什麼」，Diagnosis comment 說「現在的診斷是什麼」，其餘 comments 是過程。討論改變了哪一樣，就寫回哪一樣，讀者不必把整串讀完自己拼。

## 三類分流

以下是封閉列舉，**只有這三類**，不得依性質相似類推第四類：

| 改變的是 | 寫回哪裡 | 指令 |
|---|---|---|
| **問題本身**：issue 要回答的問題、範圍、`## Expected` | issue 正文裡持有它的那一段 | `/idd-edit issue:<N> --correct --section <heading>` |
| **診斷**：root cause、策略、分流 | Diagnosis comment 裡持有它的那一段 | `/idd-edit comment:<Diagnosis id> --correct --section <heading>` |
| **新的資訊、決定、討論過程** | 新增一則 comment | `/idd-comment #N --type <decision\|note\|question\|link>` |

每一類的邊界：

- **問題本身**只指 issue 要回答什麼、範圍到哪、怎樣算完成。怎麼做不算，那是診斷。
- **診斷**只指 Diagnosis comment 裡已經寫下的分析與策略。一個決定若改了策略（例如改選另一個做法），它屬於診斷；只是記下選了什麼、診斷本身不變，就是決定，貼 decision comment。
- 一個改變同時屬於問題與診斷 → **兩處都寫**。拿不準屬於哪一類，就照兩類都寫；不要因此把它降級成一則 comment。
- `Original text` 引文永遠不動（受保護區塊，helper 也會拒絕）。問題變了，改的是引文之外的解讀、Expected、範圍。
- 寫回發生在**討論當下**，不等討論結束才一次補。

例子（spec `issue-write-back` 的 Example）：

| 討論中提出的改變 | 類別 | 寫回 |
|---|---|---|
| 「範圍也要包含 Y」 | 問題本身 | `/idd-edit issue:N --correct --section "## Expected"` |
| 「root cause 在 b.py，不是 a.py」 | 診斷 | `/idd-edit comment:<Diagnosis id> --correct --section "### Root Cause / Analysis"` |
| 「這要在 11/1 前上線」 | 新的資訊 | `/idd-comment #N --type note` |
| 「我們選方案 B」（診斷不變） | 決定 | `/idd-comment #N --type decision` |

## 觸發

以下是封閉列舉，**只有這兩種**：

1. 使用者在 **session 裡討論**這張 issue。
2. 任何人在 issue 上留的 comment，在**下一次讀到**時處理：IDD skill 讀 comments 的時候（diagnose、plan、verify、update 都會讀），或這張 issue 在 session 裡被提起的時候。

不需要即時觸發：不做 GitHub Action、webhook 或輪詢。別人的 comment 本身不改（見下一節），寫回的是它對問題或診斷造成的改變。

## 只改自己的內容

寫回只改寫**呼叫者自己寫的內容**。判斷一律用 helper 的嚴格作者檢查 `validate-target <id> <repo> false --correct`，exit 0 才算自己的：

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/idd-edit-helper.py" validate-target '<comment id 或 issue:N>' '<owner/repo>' false --correct
```

不是自己的內容，改用 comment 回應：

- 別人寫的 comment → `/idd-comment #N --type errata --target-comment <id>`
- 別人開的 issue 正文 → `/idd-comment #N --type correction`
- 正文裡不屬於任何標題的文字（自己開的 issue 也一樣，`--section` 搆不到）→ `/idd-comment #N --type correction`

為什麼要用 `--correct` 的嚴格檢查、不用一般閘門：一般閘門放行 OWNER 與 bot，而 repo ADMIN 在 GitHub 上本來就能改別人的 comment。不問就寫的路徑，只能落在「確定是自己的」內容上。

## 不先問，但每次都回報

- AI 判斷類別、直接寫回，**不先問**。自己的內容改壞了有歸檔可還原，貼錯的 comment 可以再更正：這些是留痕、可回復的寫入，屬 [Foresay](https://github.com/kiki830621/foresay) 的 traceable 分支，做完回報即可。
- **每次寫回在對話裡回報一行**：類別、目標（`issue:<N>` 與段落，或 `comment:<id>` 與段落）、連結；`--correct` 另附 backup id。寫錯類別時，告訴使用者，用 `/idd-edit` 的 restore 還原後重寫到對的位置。
- **寫回前跑隱私自審**：對要寫入的文字做 [`rules/privacy-scrubbing.md`](privacy-scrubbing.md) 的語意檢查。`enforce` 命中 → 這次不寫，遮蔽之前不送出，並回報擋下了什麼、為什麼；`warn` 命中 → 一行提醒後照寫；`light` 仍守「原始第三方逐字內容不進 remote」。
- 要寫入的文字含使用者貼來的第三方原話時，`/idd-edit` 的 #272 那一題照問，這不在「不先問」的範圍內。

## 診斷更正後，連帶更新依賴它的紀錄

Diagnosis 被寫回後：

- **Implementation Plan**：受影響的段落用 `/idd-edit comment:<id> --correct --section <heading>` 改寫。計畫是往前看的，要跟著新的診斷走。
- **verify 報告**：每份既有報告用 `/idd-edit comment:<id> --prepend-note --reason "依據的診斷已於 YYYY-MM-DD 更正，見 <Diagnosis 連結>"` 在開頭加一行。findings 不改：報告記錄的是它驗證的那個 head 的結果，改寫 findings 會讓它不再對應那個 head。`--prepend-note` 只在目標通過上面的嚴格作者檢查時才不問。
- **Current Status**：跑 `/idd-update #N`，Key Decisions 會從更正後的 comments 重建。

## 和其他規則的關係

- [`append-vs-modify.md`](append-vs-modify.md)：每一種寫回對應的分類（`--correct` 是 `in-place-correction`、`--prepend-note` 是 `audit-block-append`、新 comment 是 append）。
- `/idd-edit --correct` 的完整流程與安全步驟（作者閘門、受保護區塊、egress 預檢、歸檔、apply 前重讀）在 `skills/idd-edit/SKILL.md`；拿掉的只有確認那一步。
- 偵測到已發表內容有錯的 skill（`idd-verify`、`idd-diagnose`、`idd-reorganize`）也照本檔直接套用，報告寫成 `### Applied Corrections`。

## 為什麼

- **#399**：verify 跑了八輪，設計一路在變，Diagnosis 的 Strategy 與 Risks、Implementation Plan 都停在第一版；偵測到的錯誤依當時的規則「只列不做」，累積成五份更正稿，要等 merge 之後才一次補。讀那張 issue 的人看到的現狀，是已經被推翻的版本。
- **舊的 `idd-diagnose` Stage 1**：使用者要調整診斷時，流程是追加一則修正 comment，不是改 Diagnosis 本身。錯的舊版留在讀者（和 AI）最先讀到的地方。
- **分類寫成封閉列舉**，是因為「什麼改變寫到哪裡」若寫成一句總括判準，讀者會在沒想到的邊界上自己推出第四類；每一類都寫出邊界，日後也不要把它「總括」回一句話。
