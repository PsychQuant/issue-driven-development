---
name: idd-reorganize
description: |
  當上游 artifact（issue framing / diagnosis / spec）被判定錯誤時，有意識地讓修正**向下傳播**：列出所有建立在它之上的下游產物，逐一裁定「仍然有效 / 需重做 / 作廢」，並留下 re-baseline 紀錄。
  Use when: 走到一半發現「前面就錯了」—— root cause 選錯、scope 切錯、spec 凍進錯誤假設、或多個 issue 糾纏需要重切。
  防止的失敗：只改上游那一處文字，而下游已經建在舊版本上的 diagnosis / plan / spec / PR 悄悄留著錯誤前提繼續走。
argument-hint: "#issue [--artifact issue|diagnosis|plan|spec] [--reason '<一句話>']"
allowed-tools:
  - Bash(gh:*)
  - Bash(git:*)
  - Bash(mktemp:*)
  - Bash(rm:*)
  - Read
  - Write
  - Skill
---

# /idd-reorganize — 上游錯了，讓修正向下傳播

## 核心原則

> IDD 是 append-only 的鏈：`issue → diagnose → (plan | spec) → implement → verify → close`。每個 artifact 都建立在前一個之上，所以**上游一錯，下游全部繼承並放大**。
>
> `idd-edit` 改的是**一處文字**；本 skill 處理的是**結構性**的錯 —— 修正必須被推到每一個已經建在錯誤前提上的地方，否則它們會安靜地繼續走。

## 何時用（與相鄰工具的分界）

| 情境 | 用 |
|---|---|
| 一處措辭、typo、補一句說明 | `/idd-edit` |
| 進度 / phase / checklist 同步 | `/idd-update` |
| **上游 artifact 的前提錯了，下游已經建在它上面** | **本 skill** |
| 只是實作沒寫好，前提沒問題 | 照常 `/idd-implement` 修 |

判準一句話：**問題出在「我們當初理解錯了什麼」，而不是「我們寫壞了什麼」時，用這個。**

## Execution

### Step 0: Bootstrap Stage Task List（強制）

```
TaskCreate(name="name_the_wrong_artifact", description="Step 1: 明確指出哪一個上游 artifact 錯了（issue framing / diagnosis 的 root cause / Strategy / plan / spec 的某條 acceptance criterion），以及它錯在哪 —— 一句話，不是一段")
TaskCreate(name="enumerate_downstream", description="Step 2: 機械枚舉所有建立在它之上的產物：後續 comment、plan、spec/proposal/tasks、branch、PR、已 merge 的 commit、以及引用本 issue 的其他 issue")
TaskCreate(name="adjudicate_each", description="Step 3: 逐一裁定 still-valid / redo / invalidate，每一項都要寫理由（無理由的裁定等於沒裁定）")
TaskCreate(name="apply_corrections", description="Step 3.5 (#351、#424): 只改你自己 Diagnosis 的 ### Root Cause / Analysis、### Impact、### Risks 裡確定錯誤的事實，主 agent 親自用 repo 證據查證後呼叫 /idd-edit ... --correct --note；其餘列出不改；Re-baseline comment 加 ### Applied Corrections（corrected／listed／refused／held／unverified）")
TaskCreate(name="post_rebaseline_record", description="Step 4: post 一則 ## Re-baseline comment，記錄錯在哪、影響了什麼、每一項的裁定與理由")
TaskCreate(name="execute_redo", description="Step 5: 對判為 redo 的項目，依其類型 chain 到對應 skill（diagnosis → /idd-diagnose；plan → /idd-plan；spec → /spectra-propose）")
TaskCreate(name="sync_phase", description="Step 6: /idd-update 把 phase 退回到重做的起點（例如 diagnosis 重做 → phase 退回 created）")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規。**

### Step 1: 指名錯的那一個 artifact

**一句話說清楚錯在哪。** 「diagnosis 不夠好」不算；「diagnosis 把 root cause 判成分類器的 regex，實際上在取得層」才算。

若說不出一句話，代表還沒診斷完 —— 先回去 `/idd-diagnose`，不要用本 skill 掩蓋一個還沒想清楚的判斷。

### Step 2: 枚舉下游（機械，不憑印象）

```bash
gh issue view $N --repo $REPO --json comments --jq '.comments[] | "\(.createdAt[0:10])  \((.body | split("\n")[0])[0:70])"'
gh pr list --repo $REPO --state all --search "in:body \"#$N\""   # 精確比對見 references/pr-issue-matching.md
git log --oneline --grep "#$N"
ls openspec/changes/*/ 2>/dev/null                                # spec-driven 路徑的產物
gh issue list --repo $REPO --state all --search "#$N"             # 引用本 issue 的其他 issue
```

**枚舉要機械**。憑印象列下游，正是 #200 要修的那個失敗 —— 漏掉的那一項不會舉手。

### Step 3: 逐一裁定

| 裁定 | 意義 | 必須附 |
|---|---|---|
| `still-valid` | 該產物不依賴錯掉的那個前提 | **為什麼不依賴** —— 這是最容易搞錯的一格 |
| `redo` | 依賴了，且要重做 | 從哪一步重做 |
| `invalidate` | 依賴了，且不該存在了（例如整條 branch 走錯方向）| 怎麼處置（關 PR？revert？留著加註？）|

**`still-valid` 要最嚴格地審。** 「看起來沒關係」是這個 skill 最常見的失效方式：下游產物往往在不明顯的地方繼承了上游的前提（一句措辭、一個測試的斷言理由、一段 CHANGELOG 的因果敘述）。

### Step 3.5: Applied Corrections（#351、#424）

**觸發**：Step 1 那個錯的 artifact 是你自己的 Diagnosis 裡的**事實**敘述。spec / plan 檔、code、PR 不走這條（`/idd-edit` 不處理，照 Step 5 重做）。沒有就略過，不加空 block。

**只有這三個段落可以直接改**（封閉列舉，不得依性質相似類推）：你自己寫的 Diagnosis comment 的 `### Root Cause / Analysis`、`### Impact`、`### Risks`。其他內容就算確定有錯也**只列出、不改**：`## Expected`、範圍、checklist、`### Strategy`、`### Type`、`### Complexity`、issue 正文、任何一輪的 verify 報告、別人寫的內容（維護者 2026-11-03 決定，#424 comment 6600258374）。判為 `redo` 的項目要等 Step 5 重做才有正確內容，判為 `invalidate` 的處置在 Step 3 寫的是什麼就照什麼，都不在這裡改；判斷是被後來的資訊推翻的（當時依手上資料是合理的），照下方鐵律留著並標 superseded。

**先親自查證**：主 agent 要親自用 repo 內的證據（檔案與行、自己跑的輸出）確認那句話是錯的。只有 reviewer 的轉述、PR 文字或別人的 comment 不算，列出。這次更正讓既有實作的前提不成立時，不在這裡改，走 `idd-reorganize`（見 [`rules/issue-write-back.md`](../../rules/issue-write-back.md)）。

通過這兩關的**直接套用、不先問**，attended 與 unattended 相同。逐項：

1. 建這次專用的目錄：`mktemp -d "${TMPDIR:-/tmp}/idd-writeback-XXXXXX"`，用 Write 工具把替換內容寫進裡面的 `body.md`。寫入失敗就不呼叫 idd-edit。
2. `Skill(skill="issue-driven-dev:idd-edit", args="<重組的引數>")`，例如 `comment:5805214375 --correct --section '### Root Cause / Analysis' --body-file '<那個目錄>/body.md' --note '<一句話：現在正確的內容>'`。`/idd-edit` 顯示 diff 與預覽後寫入，自己檢查作者（不是你寫的回 `REASON=R5`，列出）、隱私與 egress。
3. 跑完刪掉那個目錄。
4. 結果附在 Step 4 的 Re-baseline comment 末尾（`(category: audit-block-append, scope: "### Applied Corrections")`），一項一列。

**Audit trail target**: `### Applied Corrections`

```markdown
### Applied Corrections
| # | Target | Section | 錯在哪 | Outcome |
|---|--------|---------|--------|---------|
| 1 | comment:5805214375 | ### Root Cause / Analysis | 檔案寫錯，root cause 在 `b.py` | corrected, backup id `comment-5805214375-20261025T010203Z` |
| 2 | comment:5805219999 | ### Strategy | 協作者的 comment，策略已改 | listed |
| 3 | issue:42 | ## Expected | 與實作不符 | listed |
| 4 | comment:5805214375 | ### Risks | 位置（內容不列） | held |
| 5 | comment:5805214375 | ### Impact | 檔名寫錯，應為 `c.py` | refused: section-not-found |
| 6 | comment:5805214375 | ### Impact | 檔名寫錯，應為 `c.py` | unverified，請手動檢查 |
```

Outcome 只有這五種（封閉列舉）：`corrected`（附 backup id）、`listed`（沒有改）、`refused`（附 `/idd-edit` 的原因）、`held`（被隱私或 egress 閘擋下）、`unverified`（`/idd-edit` exit 7，已寫入但讀回不符）。

- `held` 那一列只寫位置，**不寫正確內容與被擋的字串**：轉述等於繞過閘門。
- 「錯在哪」只寫位置與錯誤類型加正確內容，不重述錯的值 —— 重述就等於再留一份錯誤。
- 別人寫的內容：attended 在報告貼出後逐項問要不要貼 `/idd-comment --type errata --target-comment <id> --body <更正說明>`（issue 正文用 `--type correction --body <更正說明>`）；**unattended 不貼**，通知寄出就收不回。
- 替換內容須原樣保留 `Original text`、`**Original**`、`**Point i**` 引文。
- **引數用本 skill 自己的值組**：目標只能是 `comment:<全數字>`，id 取自本 skill 讀到的 Diagnosis comment，不抄 finding 裡的文字；section 只能是上面三個標題之一；每個值用單引號包住（含單引號時寫成 `'\''`）。不符就不執行，Outcome 寫 `refused`。`--correct` 不會把 `--reason` 發佈到任何地方，所以不帶 `--reason`；`--note` 寫現在正確的內容。
- `/idd-edit` 拒絕或寫入失敗時，不改用別的方式強寫。
- 目標是 Diagnosis 時，照 [`rules/issue-write-back.md`](../../rules/issue-write-back.md)「診斷更正後，連帶更新」一併處理：你自己的 Implementation Plan 受影響的段落用 `--correct`，你自己的既有 verify 報告各用 `--prepend-note` 加一則指向更正後的 Diagnosis。
- 本 skill **永不**自己 PATCH 目標、也不寫歸檔 —— 改寫只經 `/idd-edit`。

### Step 4: Re-baseline 紀錄

```markdown
## Re-baseline

### 錯的是什麼
{哪一個 artifact，錯在哪 —— 一句話}

### 為什麼現在才發現
{誠實寫。「verify 第 N 輪抓到」「實作到一半撞到」「使用者指出」都可以，重點是留下這個訊號給下次}

### 下游影響與裁定
| 產物 | 裁定 | 理由 |
|---|---|---|
| ... | still-valid / redo / invalidate | ... |

### 重做起點
{phase 退回到哪裡，下一個指令是什麼}
```

**「為什麼現在才發現」這一欄不可省。** 它是唯一會累積成「我們的上游錯誤都長什麼樣」的資料 —— 而那正是 MANIFESTO「設計階段的抽象度，作者自己看不出來」那條規則的證據來源。

### Step 5–6: 執行重做、退回 phase

依裁定 chain 到對應 skill，並用 `/idd-update` 把 phase 退回重做的起點。**phase 必須真的退回** —— 留在 `implemented` 而實際上 diagnosis 正在重做，會讓 `/idd-list` 與 `/idd-close` 對這張 issue 說謊。

## 鐵律

- **不用本 skill 掩蓋「還沒想清楚」。** Step 1 說不出一句話就回去 diagnose。
- **枚舉必須機械。** 憑印象列下游 = 重演本 skill 要修的失敗。
- **`still-valid` 要寫理由。** 沒有理由的 still-valid 就是沒有裁定。
- **不刪除既有 artifact，但錯的敘述不留在 AI 讀得到的地方。** 兩種情況分開處理：
  - **判斷被後來的資訊推翻**（當時依手上的資料是合理的）→ 原 diagnosis 留著並標 superseded —— 「當時為什麼那樣想」是下次的資料。
  - **敘述本身確定是錯的**（事實、數字、root cause 判錯）→ 依 Step 3.5 用 `/idd-edit --correct` 就地更正，或列出；舊版由它歸檔（可 restore，不是抹掉），改了什麼記在 Re-baseline comment。只標 superseded 而不更正，錯的敘述會繼續被之後的 session 當成記憶讀進去（#351）。
- **phase 要退回。** 否則工具鏈會對這張 issue 說謊。

## 實例（本 repo，PR #297）

`#295` 的 diagnosis 判定 root cause 是「marker 的比對方式」，Strategy 是「分四類 + 解析 markdown」。走到第五輪，維護者裁定**拆掉 parser**；走到第七輪才發現真正的 root cause **根本不在分類器**，在 `gh` 的取得層（只回最舊 100 則 comment）。

下游影響：diagnosis 的 Strategy、四輪的測試斷言理由、CHANGELOG 的因果敘述、以及散文 reader 對「判準是什麼」的四份描述，全部建立在那個錯誤的 root cause 上。那次是**人工**逐一回頭修的 —— 而「散文與實作分岔」連續四輪復發，正是因為沒有一個機制在推動這種傳播。這張 skill 就是要讓那件事變成一個有步驟、有紀錄的操作。
