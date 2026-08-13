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
  - Read
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
- **不刪除既有 artifact。** 錯的 diagnosis 留著並標記為 superseded，不要抹掉 —— 「當時為什麼那樣想」是下次的資料。
- **phase 要退回。** 否則工具鏈會對這張 issue 說謊。

## 實例（本 repo，PR #297）

`#295` 的 diagnosis 判定 root cause 是「marker 的比對方式」，Strategy 是「分四類 + 解析 markdown」。走到第五輪，維護者裁定**拆掉 parser**；走到第七輪才發現真正的 root cause **根本不在分類器**，在 `gh` 的取得層（只回最舊 100 則 comment）。

下游影響：diagnosis 的 Strategy、四輪的測試斷言理由、CHANGELOG 的因果敘述、以及散文 reader 對「判準是什麼」的四份描述，全部建立在那個錯誤的 root cause 上。那次是**人工**逐一回頭修的 —— 而「散文與實作分岔」連續四輪復發，正是因為沒有一個機制在推動這種傳播。這張 skill 就是要讓那件事變成一個有步驟、有紀錄的操作。
