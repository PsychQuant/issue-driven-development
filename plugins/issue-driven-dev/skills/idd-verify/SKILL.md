---
name: idd-verify
description: |
  驗證 uncommitted/committed code 是否滿足 Issue 的所有要求。
  預設用 Agent Team（5 Claude reviewers 互相挑戰）+ Codex CLI（gpt-5.4）平行驗證。
  6 個獨立 AI、兩個模型家族、互相看不到對方的結果。
  Use when: 實作完成後、commit 之前。
  防止的失敗：自以為修好了，沒跑驗證。
argument-hint: "#issue [engine] [--loop] e.g. '#42', '#42 codex', '#42 --loop'"
allowed-tools:
  - Bash(codex:*)
  - Bash(git:*)
  - Bash(gh:*)
  - Bash(mktemp:*)
  - Bash(rm:*)
  - Bash(wc:*)
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Agent
  - TeamCreate
  - SendMessage
  - AskUserQuestion
---

# /idd-verify — 驗證實作

6 個獨立 AI 交叉驗證。Claude 修、獨立 AI 群驗。

## 核心原則

> 「應該沒問題」不是驗證。跑了驗證、看了輸出、確認通過，才是驗證。

## 參數

```
/idd-verify #42                     → Agent Team (5) + Codex 平行（預設）
/idd-verify #42 codex               → 只用 Codex CLI
/idd-verify #42 team                → 只用 Agent Team（不跑 Codex）
/idd-verify #42 --loop              → 驗證 + ralph-loop 自動修復迴圈
/idd-verify                         → 通用 code review（無 issue）
```

## Configuration

讀取 `.claude/issue-driven-dev.local.md` frontmatter。如不存在，詢問 `github_repo` 並建立。

## 驗證架構（預設）

```
idd-verify #NNN
│
├── Agent Team（5 Claude teammates，互相挑戰）
│   ├── Requirements — issue 要求覆蓋率
│   ├── Logic — 邏輯正確性、edge cases、null handling
│   ├── Security — injection、權限、hardcoded secrets
│   ├── Regression — scope creep、副作用、既有功能
│   └── Devil's Advocate — 反駁前四個的「通過」判斷
│
└── Codex CLI（gpt-5.4 xhigh，獨立 process）
    └── 完全獨立，看不到 team 的討論

→ 6 個 findings 合併去重 → 呈現結果
```

**為什麼 6 個？**
- 5 個 Claude teammates 在同一個 team 裡**互相挑戰**（不是各自獨立報告）
- Devil's Advocate 的工作是**試著證明其他 4 個的通過判斷是錯的**
- Codex 是完全不同的模型家族（gpt-5.4），提供**跨模型盲驗**

## Execution

### Step 1: 取得 diff 和 issue

```bash
# 如果有 uncommitted changes
git diff --stat
# 如果已 committed
git diff --stat HEAD~1

# 取 issue
gh issue view $NUMBER --repo $GITHUB_REPO --json title,body
```

### Step 2: 平行啟動 Agent Team + Codex

**同時啟動，不等對方**。

#### 2a. Agent Team（5 reviewers）

用 TeamCreate 建立 team：

```
TeamCreate:
  name: "verify-{NUMBER}"
  teammates:
    - name: "requirements"
      prompt: |
        你是 Requirements Reviewer。
        Review code changes for Issue #{NUMBER}: {title}

        Issue body:
        {body}

        你的任務：逐一檢查 issue 的每個要求是否在 code 中被實現。
        對每個要求標記：FULLY / PARTIALLY / NOT addressed。
        用 Read/Grep 工具實際去看相關檔案確認。
      tools: Read, Grep, Glob, Bash
      model: sonnet

    - name: "logic"
      prompt: |
        你是 Logic Reviewer。
        Review code changes for Issue #{NUMBER}: {title}

        Changes:
        {diff}

        你的任務：檢查邏輯正確性。
        - Edge cases（null、empty、boundary values）
        - 型別安全（numeric vs character、NA handling）
        - 控制流程（if/else 覆蓋、switch fall-through）
        用 Read 工具查看完整函數上下文。
      tools: Read, Grep, Glob, Bash
      model: sonnet

    - name: "security"
      prompt: |
        你是 Security Reviewer。
        Review code changes for Issue #{NUMBER}: {title}

        Changes:
        {diff}

        你的任務：檢查安全問題。
        - SQL injection（字串拼接 vs parameterized）
        - Hardcoded secrets
        - 權限檢查
        - 輸入驗證
      tools: Read, Grep, Glob, Bash
      model: sonnet

    - name: "regression"
      prompt: |
        你是 Regression Reviewer。
        Review code changes for Issue #{NUMBER}: {title}

        Changes:
        {diff}

        你的任務：
        1. 有沒有改到 issue 範圍外的東西（scope creep）？
        2. 改動有沒有破壞既有功能？
        3. 有沒有引入新的 dependency 但沒處理？
        用 Grep 搜尋被改動的函數在哪裡被呼叫。
      tools: Read, Grep, Glob, Bash
      model: sonnet

    - name: "devils-advocate"
      prompt: |
        你是 Devil's Advocate。
        Review code changes for Issue #{NUMBER}: {title}

        你的任務：等其他 4 個 reviewer 完成後，
        讀取他們的結論，然後**試著反駁每一個「通過」的判斷**。

        如果他們說「FULLY addressed」，你要找理由說它其實沒有。
        如果他們說「no security issues」，你要找他們漏掉的攻擊向量。
        如果你找不到反駁的理由，才承認確實通過。

        這是對抗性驗證 — 你的存在是為了防止群體盲點。
      tools: Read, Grep, Glob, Bash
      model: sonnet
```

#### 2b. Codex CLI（背景執行）

```bash
PROMPT_FILE=$(mktemp /tmp/codex_verify_XXXXX)
{
  echo "You are verifying code changes for Issue #$NUMBER: $TITLE"
  echo ""
  echo "Issue requirements:"
  echo "$BODY"
  echo ""
  echo "YOUR PRIMARY TASK:"
  echo "1. Go through EACH requirement"
  echo "2. For each: FULLY / PARTIALLY / NOT addressed"
  echo "3. Flag scope creep and regressions"
  echo "4. Reply in Traditional Chinese"
  echo ""
  echo "=== CHANGES ==="
  git diff HEAD~1  # or git diff if uncommitted
} > "$PROMPT_FILE"

codex review -c 'model="gpt-5.4"' -c 'model_reasoning_effort="xhigh"' - < "$PROMPT_FILE" &
```

### Step 3: 合併 Findings

等 Agent Team 和 Codex 都完成後：

1. 收集 5 個 teammates 的 findings
2. 收集 Codex 的 findings
3. **去重**：相同檔案 + 相似描述 → 合併，標註來源 `[team:logic+codex]`
4. **severity 以最高為準**：如果 logic 說 P2 但 codex 說 P1 → P1
5. Devil's Advocate 的反駁如果成立 → 升級 severity

### Step 4: Comment 到 issue

```bash
gh issue comment $NUMBER --repo $GITHUB_REPO --body "$MERGED_FINDINGS"
```

格式：
```markdown
## Verify: #NNN

### Engine
Agent Team (5 Claude reviewers) + Codex (gpt-5.4)

### 要求覆蓋率
X / Y requirements addressed

### Findings（合併後）
| # | Severity | Finding | Source |
|---|----------|---------|--------|
| 1 | P1 | ... | team:logic+codex |
| 2 | P2 | ... | team:security |
| 3 | — | (devil's advocate 未能反駁) | team:devils-advocate |

### Scope Check
{有沒有超出 issue 範圍的改動}
```

### Step 5: 後續動作

| 結果 | 動作 |
|------|------|
| 全部通過 + Devil's Advocate 無法反駁 | 提示 `idd-close` |
| 有 findings | 修正後再跑 |
| Scope creep | 開新 issue |

## Engine: codex（快速模式）

只用 Codex，不開 team。適合小改動：

```bash
codex review -c 'model="gpt-5.4"' -c 'model_reasoning_effort="xhigh"' - < "$PROMPT_FILE"
```

## Engine: team（只用 Agent Team）

只開 5 人 team，不跑 Codex。適合不需要跨模型驗證的場景。

## Loop 模式

加上 `--loop` 後，用 ralph-loop 驅動驗證-修復迴圈。每輪用完整的 6-AI 驗證。

## 鐵律

- **不跳過驗證**。「看起來對了」不算。
- **有 findings 就不 close**。先修，再 verify。
- **Devil's Advocate 是必要的**。防止 4 個 reviewer 的群體盲點。
- **Codex 是獨立的**。它看不到 team 的討論，提供真正的盲驗。

## Auto-Update

Verify comment 完成後，自動執行 `idd-update` 更新 issue body 的 Current Status。

## Next Step

驗證通過後：`/issue-driven-dev:idd-close #NNN`
