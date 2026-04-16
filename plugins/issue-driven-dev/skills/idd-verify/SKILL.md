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

### Step 0: Bootstrap Stage Task List（強制)

**在動任何事之前**先用 `TaskCreate` 為這個 stage 建 todo list:

```
TaskCreate(name="get_diff_and_issue", description="git diff + gh issue view,存 diff 到 /tmp 供 agents 讀取")
TaskCreate(name="launch_parallel_reviewers", description="6 個 tool calls 同一 message: TeamCreate + 5 Agent(requirements/logic/security/regression/devils-advocate) + 1 Bash codex")
TaskCreate(name="wait_for_claude_agents", description="等 5 Claude teammates 全部 idle,讀 /tmp/verify_${NUMBER}_findings_*.md")
TaskCreate(name="wait_for_codex", description="等 Codex 背景任務完成,讀 /tmp/codex-verify-${NUMBER}.md")
TaskCreate(name="merge_findings", description="合併 6 個來源 findings 去重,severity 取最高")
TaskCreate(name="comment_to_issue", description="gh issue comment $NUMBER 貼合併後的 verification report")
TaskCreate(name="decide_next_action", description="根據 findings: 通過→idd-close / 有 findings→修正 / scope creep→新 issue")
TaskCreate(name="triage_followup_issues", description="Step 5b: 分類 non-blocking findings → 問使用者要不要開新 issue，確認後批次建立")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。

**鐵律**:
- `wait_for_claude_agents` 和 `wait_for_codex` 都要跑到真的有 findings 內容,不能只看到 idle notification 就 completed
- 如果某個 reviewer 沒寫 findings 檔,用 `SendMessage` 請它補寫,或 fallback 自己做 coordinator backup 檢查
- `comment_to_issue` 一定要實際 post 到 GitHub,不是只在對話中顯示

---

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

**CRITICAL: 6 個 tool calls（5 Agent + 1 Bash codex）必須在同一個 message 送出。不可分步驟。**

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
      # model 省略 → 繼承主對話模型

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
      # model 省略 → 繼承主對話模型

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
      # model 省略 → 繼承主對話模型

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
      # model 省略 → 繼承主對話模型

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
      # model 省略 → 繼承主對話模型
```

#### 2b. Codex CLI（背景執行，via companion script）

使用 `codex exec` 執行 review：

```bash
Bash({
  command: `codex exec --full-auto -c 'model_reasoning_effort="xhigh"' -o /tmp/codex-verify-$NUMBER.md "You are verifying code changes for Issue #$NUMBER: $TITLE. Go through EACH requirement: FULLY / PARTIALLY / NOT addressed. Flag scope creep and regressions. Reply in Traditional Chinese."`,
  description: "Codex review for #$NUMBER",
  run_in_background: true
})
```

完成後用 Read 讀取 `/tmp/codex-verify-$NUMBER.md`。

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

#### Step 5a: 分類 findings

合併後的每個 finding 歸入三類：

| 類別 | 判斷標準 | 處置 |
|------|---------|------|
| **Blocking** | 直接違反 issue 要求、邏輯錯誤、安全漏洞 | 必須修復後重跑 verify |
| **In-scope fix** | 屬於本 issue 範圍但非阻擋性（如 description 不精確、spec 過時） | 本次修復，不需重跑 verify |
| **Follow-up** | 不屬於本 issue 範圍的改善建議（如共用函式的行為、缺少上限） | → Step 5b 問使用者 |

在 verification report 的 Findings 表加一欄 `Action`：

```markdown
| # | Severity | Finding | Source | Action |
|---|----------|---------|--------|--------|
| 1 | MEDIUM | ... | team:logic+codex | Follow-up |
| 2 | MEDIUM | ... | team:regression | In-scope fix |
| 3 | LOW | ... | team:security | Follow-up |
```

#### Step 5b: Follow-up Issue Triage（強制，不可省略）

當有任何 finding 被標記為 `Follow-up` 時，**必須**用 AskUserQuestion 問使用者：

```
question: "驗證發現 N 個 follow-up items（不影響本 issue，但值得追蹤）。要開新 issue 嗎？"
options:
  - "全部開" — 為每個 follow-up finding 建立獨立 issue
  - "讓我選" — 逐一確認哪些要開
  - "不開" — 記錄在 verification comment 中但不建 issue
```

**如果使用者選「全部開」或選了部分**：

1. 相似的 findings 可合併（例如同一函式的多個問題 → 一個 issue）
2. 用 `gh issue create` 批次建立，body 引用 verification report 的原文：
   ```markdown
   ## Problem

   > **From verification of #NNN**:
   > 「{finding 原文}」
   > — Source: {reviewer sources}

   {解讀}

   ## Type
   {bug / enhancement}
   ```
3. 每個新 issue 的 body 加上 `Related: #NNN`
4. 輸出新建的 issue 清單

**如果使用者選「不開」**：findings 已記錄在 verification comment 中，不會遺失。

**為什麼強制問？** 歷史上的問題模式：verify 找到 5 個 follow-up items → 對話中討論了一下 → 使用者說「先 close」→ 所有 follow-up items 被遺忘。強制 triage 確保每個 finding 都有明確的去向（開 issue 或 conscious decision 不開）。

#### Step 5c: Routing

| 結果 | 動作 |
|------|------|
| 無 blocking findings + follow-up triage 完成 | 提示 `idd-close` |
| 有 blocking findings | 修正後再跑 verify |
| 有 in-scope fix | 修正 + commit，不需重跑 verify |

## Engine: codex（快速模式）

只用 Codex，不開 team。適合小改動：

```bash
codex exec --full-auto \
  -c 'model_reasoning_effort="xhigh"' \
  -o /tmp/codex-quick-review.md \
  "Review the current git diff. Flag bugs, logic errors, security issues. Reply in Traditional Chinese."
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
