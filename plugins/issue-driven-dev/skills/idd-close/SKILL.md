---
name: idd-close
description: |
  寫 closing comment 並關閉 GitHub Issue。
  強制記錄做了什麼、怎麼驗證的。
  Use when: verify 通過後、commit 之後。
  防止的失敗：修完了但三個月後沒人知道當時做了什麼。
argument-hint: "#issue e.g. '#42'"
allowed-tools:
  - Bash(gh:*)
  - Bash(git:*)
  - Read
  - AskUserQuestion
---

# /close — 結案

寫 closing comment，然後關閉 issue。三分鐘的紀錄，省三十分鐘的考古。

## 核心原則

> 沒有 closing comment 就不關 issue。沒有例外。
>
> **沒打勾就不關。** 每一個 `- [ ]` 都必須變成 `- [x]`（完成）、`- [~]`（刻意跳過）、或 `- [-]`（won't fix / scope 調整）才能 close。

## Configuration

按 [config-protocol](../../references/config-protocol.md) 解析 target repo:

- `--repo owner/repo` flag → per-invocation override
- Walk-up `.claude/issue-driven-dev.local.json`(從 cwd 往上找)
- Path / git predicates 自動匹配

**Group/predicate 行為**:`idd-close` 操作既存 issue,只用 path/git 類 predicate。Group config 會 fall through 到 primary repo。**注意**:關 group 的 primary issue 不會自動關 tracking issues — 各自關閉,或加 `--close-tracked` 一併關閉並在 tracking issues 留 cross-link comment。

## Execution

### Step 0: Checklist Gate Check

在動任何 closing comment 之前先 gate — 若有未完成的 todo，**refuse close** 並列出未勾項。

**掃描範圍**：

掃 issue body + **所有 comments** 的 **結構化區段**：

| 區段標題 (`## ` 或 `### `) | 當成 checklist source |
|----------------------------|---------------------|
| `Strategy` | ✅ |
| `Implementation Plan` | ✅ |
| `Implementation Complete` → `Checklist` | ✅（這是 `idd-implement` Step 5 寫回的 source of truth）|
| `Todo` / `Tasks` / `Checklist` | ✅ |
| `Current Status` → `Tasks` | ✅ |
| `Problem` / `Repro` / `Steps to reproduce` / `Workaround` / `Expected` / `Actual` | ❌ 忽略（描述性區段，checkbox 是情境不是 todo）|
| _(未列出的標題)_ | ❌ 忽略（保守：不掃不認識的區段）|

**解析規則**：

對每個符合條件的區段，逐行匹配 regex `^\s*-\s*\[(.)\]\s*(.+)$`：

| 標記 | 意義 | Blocking? |
|------|------|-----------|
| `- [ ]` | open todo | 🔴 **阻擋 close** |
| `- [x]` / `- [X]` | 完成 | ✅ 通過 |
| `- [~]` | skipped（刻意跳過，可能以後再做）| ✅ 通過（**但需附 skip reason**，見下）|
| `- [-]` | won't fix / out of scope | ✅ 通過（**但需附 won't fix reason**）|
| `- [?]` | unknown / need input | 🟡 **阻擋 close**（語意同 open）|
| 其他 | 不識別 | ⚠️ warning，視為 open |

**Skip / Won't-fix reason 檢查**：

`- [~]` 或 `- [-]` 的 line 必須在同一行或下一個縮排 bullet 附說明原因（例如 `- [~] foo — deferred: pending upstream fix`）。若沒有 reason，**阻擋 close**——強迫使用者紀錄為什麼跳過。

**Comment 去重**：

若多個 comments 含相同 source 標題（例如使用者 re-ran `idd-implement` 並發了多個 `## Implementation Complete`），**只看最後一個**（按 comment `createdAt` desc 取第一個）——那是最新的 source of truth。

**Gate 決策**：

```
blocking_count = len([- [ ]]) + len([- [?]]) + len([- [~]] without reason) + len([- [-]] without reason)

if blocking_count > 0:
    REFUSE close
    列出每個 blocking 項目（含來源區段 + 原文）
    建議：
      - 要做的 → /idd-implement #NNN 繼續做
      - 刻意跳過的 → 用 /idd-edit 把 - [ ] 改成 - [~] 並附 reason
      - 不做的 → 用 /idd-edit 改成 - [-] 並附 won't-fix reason
else:
    PASS → 繼續 Step 1
```

**沒找到任何 checklist（legacy issue）**：

顯示 warning `(no checklist detected — legacy issue pattern)`，**不阻擋**（向後相容），但建議使用者考慮先跑 `idd-update` 補 Current Status。

### Step 0.5: Bootstrap Stage Task List（強制)

Gate check 通過後,用 `TaskCreate` 為 close stage 建 todo list:

```
TaskCreate(name="check_prerequisites", description="gh issue view 確認 OPEN + git log --grep=#NNN 確認有 commit 引用")
TaskCreate(name="check_open_prs", description="Step 1.5: gh pr list 找引用 #NNN 的 open PR；若有 unmerged PR → refuse close")
TaskCreate(name="semantic_gate_check", description="Step 1.6: 對每個 - [x] bullet 做 keyword extraction → 驗證對應 artifact 真存在/有 commit。Warn-only。")
TaskCreate(name="draft_closing_comment", description="起草 Problem / Root Cause / Solution / Verification / Changes 五段式")
TaskCreate(name="review_with_user", description="顯示 closing comment 給使用者確認(若已明確 /idd-close 可省略此步)")
TaskCreate(name="publish_and_close", description="gh issue comment + gh issue close")
TaskCreate(name="auto_update_body", description="跑 /idd-update #NNN 把 issue body 的 Current Status phase 改 closed（Step 6，常被漏）")
TaskCreate(name="report_result", description="輸出關閉後的 issue URL 與 commits chain")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。**TaskCreate 清單 = 真實的步驟清單；任何寫在 skill 裡但沒列進 TaskCreate 的步驟，都視為 skill 的 bug，必須補進 Task 清單。**

---

### Step 1: 檢查前置條件

```bash
gh issue view $NUMBER --repo $GITHUB_REPO --json state,title,body
```

確認：
- Issue 是 open 狀態
- 有相關的 commit 引用 #NNN

```bash
git log --oneline --grep="#$NUMBER" | head -10
```

如果沒有相關 commit，警告使用者：「找不到引用 #NNN 的 commit。確定要關嗎？」

### Step 1.5: PR Gate Check

掃描有沒有引用本 issue 的 open PR — 若有 **unmerged** PR，refuse close（PR path 走完才能 close issue）。

```bash
OPEN_PRS=$(gh pr list --repo "$GITHUB_REPO" --state open \
    --search "in:body \"#${NUMBER}\"" \
    --json number,url,headRefName,mergeable)
```

| 結果 | 行為 |
|------|------|
| 沒有 open PR | ✅ 通過（可能走 direct-commit path，或 PR 已 merged 變 closed state） |
| 有 1+ open PR 引用 #NNN | 🔴 **Refuse close** — 列出 PR URL，提示 `gh pr merge <N>` 後再回來 |
| 找到 open PR 但 mergeable=`CONFLICTING` | 🔴 **Refuse close** — 提示先解 conflict |

**為什麼是阻擋而非 warn**：呼應「沒打勾就不關」的設計哲學。Open PR 代表「這個改動還沒進 main」，先 close issue 就是 audit trail 斷裂——三個月後會看到 closed issue 但 main 沒對應 commit。

**Override**：若使用者真的要 close（PR 廢棄、走別路修了等）：先去 GitHub 手動 close 那個 PR，然後 `idd-close` 就會通過（找不到 open PR）。多一步動作，逼使用者表態 PR 的去向，正是 gate 的目的。

完整 PR/direct-commit path contract 見 [pr-flow.md](../../references/pr-flow.md)。

### Step 1.6: Semantic Checklist Gate (v2.29.0+)

Step 0 的 structural gate 防 **honest forgetting**(`- [ ]` 沒打勾不能關)。Step 1.6 的 semantic gate 防 **motivated cheating**(打勾了但實際沒做)—— 對每個 `- [x]` bullet 做 keyword extraction,確認對應 artifact 真的存在或真的有 #NNN 的 commit。

> **這一層讓 IDD 從繼承 TDD 的 falsifiability 變成嚴格大於**:TDD 只能驗證「test 跑得過」(machine check); IDD Step 1.6 額外驗證「這個 issue 的 commit 真的有改 test」(audit-level machine check)。Process compliance + outcome verification 兩者兼具。

#### Keyword → Check 對映

對 Step 0 通過的 `- [x]` bullets 逐行掃,套用以下三類 pattern。**互斥**(一個 bullet 命中第一個 pattern 就跳出)。

| # | Pattern (regex / keyword) | Semantic check | Skip 條件 |
|---|---------------------------|----------------|----------|
| 1 | `(?i)\b(test|tests|regression|unit test|integration test|e2e|coverage)\b` | `git log --oneline --grep="#${N}" -- '**/*test*' '**/test/**' '**/tests/**' '**/__tests__/**' '**/spec/**' '**/*_test.*' '**/*.test.*' '**/*.spec.*'` 必須返回 ≥1 commit | SDD path(spectra-apply 管 tasks.md;不重檢) |
| 2 | `openspec/changes/[\w-]+/(?:proposal|design|tasks|spec)\.md` 或 backtick 包的 spec artifact path | 對應 file 存在 | — |
| 3 | bullet 含 `` `path/like/this.ext` `` (backtick + 相對 path + 副檔名) | 該 path 出現在 `git log --oneline --grep="#${N}" --name-only` 輸出中 | 純 doc bullet (file 是 `*.md` 在 README/docs/ 下) |
| _其他_ | (無命中)| skip,計入 "unchecked" 統計 | — |

#### 實作

```bash
# 1. 從 Step 0 拿到所有 - [x] bullets(已通過 structural gate)
CHECKED_BULLETS=$(...)  # 結構: [(source_section, bullet_text), ...]

# 2. 收集 #NNN 的 commit log + changed files
COMMIT_LOG=$(git log --oneline --grep="#${N}" 2>/dev/null)
CHANGED_FILES=$(git log --name-only --grep="#${N}" --pretty=format: 2>/dev/null | sort -u | grep -v '^$')

if [ -z "$COMMIT_LOG" ]; then
    echo "(no commits referencing #${N} found — semantic gate skipped, fall back to structural gate only)"
    exit 0
fi

# 3. 逐 bullet 套 pattern
WARNINGS=()
UNCHECKED=0
PASSED=0

for bullet in CHECKED_BULLETS:
    if matches Pattern 1 (test keyword):
        if not (CHANGED_FILES grep '/test/\|test\.\|\.test\.\|\.spec\.\|/tests/\|__tests__/\|/spec/'):
            WARNINGS.append((bullet, "claims test work but no test file changed in #${N} commits"))
        else:
            PASSED++
    elif matches Pattern 2 (spec artifact path):
        path = extract path from bullet
        if not file_exists(path):
            WARNINGS.append((bullet, f"claims {path} but file does not exist"))
        else:
            PASSED++
    elif matches Pattern 3 (backtick file path):
        path = extract from backticks
        if path not in CHANGED_FILES:
            WARNINGS.append((bullet, f"mentions `{path}` but it's not in #${N} commits"))
        else:
            PASSED++
    else:
        UNCHECKED++

# 4. 報告
echo "Semantic gate: ${PASSED} passed, ${#WARNINGS[@]} warnings, ${UNCHECKED} unchecked (no recognized pattern)"
for (bullet, reason) in WARNINGS:
    echo "  ⚠️  ${bullet}"
    echo "      → ${reason}"
```

#### 行為:warn-only,不直接 refuse

| Warning count | 行為 |
|---------------|------|
| 0 | ✅ 通過,繼續 Step 2 |
| ≥ 1 | 🟡 印出 warnings + AskUserQuestion 三選一: |
|     | (a) **Proceed** — 接受 warning 繼續 close (e.g. test 是預先寫好的,確實沒新 commit) |
|     | (b) **Investigate** — abort,user 自己去 verify 那些 bullet 真假 |
|     | (c) **Edit checklist** — 改 `- [x]` 為 `- [~]` + reason,重跑 idd-close |

**為什麼不像 structural gate 那樣硬 refuse**:keyword extraction 有 false positive — 例如「為 X 加 regression test」的 commit 可能在更早的 PR 已合進 main、不在 #NNN 的 commit log 裡。硬 refuse 會把合理 case 卡死。Warn + AskUser 讓 user 表態,既保留可疑信號又不阻擋 legitimate close。

> **Falsifiability claim 的 footnote**:Step 1.6 落地後,`idd-close` 同時做 structural check (gate v2.17.0) + semantic check (gate v2.29.0),前者保 audit completeness、後者保 audit truthfulness。IDD 的 falsifiability surface = TDD's (test pass/fail,繼承自 idd-implement Step 3) ∪ SDD's (spec/code conformance,繼承自 spectra-apply) ∪ checklist semantic verification (Step 1.6) — strict superset 兩者。

### Step 2: 寫 Closing Comment

根據 issue body、diagnosis、commits 自動生成：

```markdown
## Closing Summary

### Problem
{問題是什麼，影響範圍}

### Root Cause
{為什麼會發生（bug）/ 需求背景（feature）}

### Solution
{改了什麼，關鍵邏輯}

### Verification
{怎麼驗證的：verify 結果、測試、截圖}

### Changes
{相關 commit 列表}
```

### Step 3: 確認

將 closing comment 顯示給使用者確認。

### Step 4: 發佈並關閉

```bash
gh issue comment $NUMBER --repo $GITHUB_REPO --body "$CLOSING_COMMENT"
gh issue close $NUMBER --repo $GITHUB_REPO
```

> **數學公式格式**：GitHub 支援 `$...$`（inline）和 `$$...$$`（display）。含底線的程式變數名**不放 math mode**，改用 backtick code。

### Step 5: 發佈完成回報

```
✓ Issue #NNN closed
  Closing comment: {URL}
  Commits: {list}
```

### Step 6: Auto-Update Issue Body（強制，不可省略）

Close 成功後**立即**執行，更新 issue body 的 `Current Status` 區塊（phase → `closed`）：

```
Skill(skill="issue-driven-dev:idd-update", args="#NNN")
```

或等價的手動等效動作：用 `gh api PATCH /repos/:owner/:repo/issues/:number` 更新 body 裡的 Current Status 區塊。

**這一步設計上是工作流的真實終點，但最容易被漏掉**——因為 Step 5「發佈完成回報」後畫面看起來「全綠」，腦袋會以為結束了。沒做 Step 6 的後果：

- Issue body 的 Current Status phase 停留在舊值（`implementing` / `diagnosed`），GitHub state 已是 `CLOSED` → 兩邊資料不一致
- `gh issue view` 搭配 jq 掃 body metadata 的腳本會誤判
- 幾個月後考古：「這 issue 狀態是啥？」body 說 implementing，state 說 closed → 只能翻 comments 重建

**批次 close 時**：每一個 issue 都要分別跑 idd-update，不是跑一次。

### Step 7: 批次 close 特殊規則

若這次 `/idd-close` 是批次的其中一輪（例如 archive 之後同時 close #1 #2 #3），Step 5 和 Step 6 要對**每個 issue 各跑一次**。不要把多個 issue 的回報合併。TaskCreate 清單裡為每個 issue id 各建一份 `auto_update_body_N`。

## Closing Comment 的價值

| 沒有 closing comment | 有 closing comment |
|---------------------|-------------------|
| 三個月後：「這個 issue 改了什麼？」→ 翻 git log 猜 | 三個月後：直接看 closing comment |
| 類似 bug 再出現：「上次怎麼修的？」→ 不知道 | 類似 bug 再出現：參考上次的 root cause + solution |
| 新人接手：「為什麼這段 code 長這樣？」→ 沒人知道 | 新人接手：issue 裡有完整的脈絡 |

## 鐵律

- **沒打勾就不關。** Step 0 的 Structural Gate 是硬性 gate，不給 `--force` bypass。刻意跳過的 todo 必須明確改為 `- [~]` / `- [-]` 並附 reason——這本身就是一個 decision，值得留紀錄。
- **打勾沒做要 warn**。Step 1.6 的 Semantic Gate(v2.29.0+)用 keyword extraction 驗證打勾的 bullet 真有對應 commit/file。Warn-only,但需 user 明確 acknowledge 才繼續。兩個 gate 一起 cover「忘記」+「假裝」兩種失敗模式。
- **不跳過 closing comment**。即使是小 fix 也要寫。
- **Closing comment 要有 Root Cause**。「改了 X」不夠，要寫「因為 Y 所以改了 X」。
- **列出所有相關 commit**。讓 issue 成為這次改動的完整入口。
- **Step 6 Auto-Update 是工作流的真實終點**，不是可選 nice-to-have。跳過 Step 6 = 沒跑完 `/idd-close`。批次 close 時每個 issue 都要分別 auto-update。
- **TaskCreate 清單即步驟清單**。skill 裡任何寫出來的步驟都必須在 Step 0.5 的 TaskCreate bootstrap 裡列出；遺漏就是 skill bug。

## 為什麼不給 `--force`？

「強制關掉」是肌肉記憶殺手。第一次是 "我趕時間"，第三次就變成「反正都 force」。Gate check 的意義是**強迫使用者面對那個未勾項**——要嘛做完、要嘛明確標記「不做，因為 X」，兩種都比 silent 跳過好。

要真的 override，應該走 `/idd-edit #NNN` 把 `- [ ]` 改成 `- [~]` 並寫 reason。多打 30 秒的字，換回 3 個月後的可追溯性。
