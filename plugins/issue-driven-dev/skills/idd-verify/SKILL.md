---
name: idd-verify
description: |
  驗證 uncommitted/committed/PR code 是否滿足 Issue 的所有要求。
  預設用 Agent Team（5 Claude reviewers 互相挑戰）+ Codex CLI（gpt-5.5）平行驗證。
  6 個獨立 AI、兩個模型家族、互相看不到對方的結果。
  支援 cluster verify（v2.34.0+）：多個 #N 共用 1 PR 時（如 `#34 #36 #38`），report 按 issue 分區段。
  支援 external-agent / PR mode（v2.37.0+）：`--pr <N>` 驗證外部 agent（Codex/Copilot）開的 PR，PR 是 master comment、ref'd issue 拿 pointer；`--commits N` / `--since <ref>` / `--branch <name>` 為其他輸入來源；缺 flag 時 auto-detect 本地 commits 與 open PR 並 AskUserQuestion。
  Use when: 實作完成後、commit 之前；或外部 agent 開了 PR 要回頭驗證。
  防止的失敗：自以為修好了，沒跑驗證；外部 agent 的 PR 沒走 IDD discipline。
argument-hint: "#issue [#issue ...] [engine] [--loop] [--pr N] [--commits N] [--branch X] [--since REF] [--cwd /path/to/clone] e.g. '#42', '#42 --pr 123', '#42 --commits 3', '#34 #36 #38' (cluster verify), '--pr 123' (auto-discover issues), '#43 --cwd /path/to/other/repo' (cross-repo)"
allowed-tools:
  - Bash(codex:*)
  - Bash(git:*)
  - Bash(gh:*)
  - Bash(mktemp:*)
  - Bash(rm:*)
  - Bash(wc:*)
  - Bash(sed:*)
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

## Cross-repo invocation（v2.40.0+）

支援 `--cwd /path/to/local/clone` flag,讓 verify 在指定 local clone 上跑(不依賴 Claude Code session cwd)。Step 0 解析 `--cwd` 後,後續所有 `git`/`gh` 命令依 [`references/cross-repo-cwd.md`](../../references/cross-repo-cwd.md) 的 substitution rule 改寫:

- `git X`(包含 `git diff`、`git show`、`git log`、PR mode 的 `git checkout`) → `git -C "$CWD" X`
- `gh issue/pr/repo X` → `gh ... X -R "$GITHUB_REPO"`

**特別重要**:PR mode 的 auto-restore branch 邏輯(verify 完跳回原始 branch)也必須用 `git -C "$CWD" checkout -`,否則會把錯的 repo 切回去。完整 algorithm + 失敗模式見 reference 文件。

**本 skill 內所有 bash 範例為 cwd-only 寫法以保持可讀性,執行時請套用 substitution rule。**

## Cluster-PR mode（v2.34.0+）

`idd-verify #34 #36 #38` 觸發 cluster verify：6-AI 看到所有 cluster issue 的 diagnoses + 整個 PR 的 diff，但 verify report **按 issue 分區段** — 每個 #N 都有獨立的 findings section，Aggregate PASS/FAIL 套到整個 PR。

完整契約見 [batch-and-cluster.md](../../references/batch-and-cluster.md)。Per-issue follow-up findings 仍透過 `idd-issue` auto-create（target main）。Cluster verify 只在 cluster-PR mode 才有意義（即 `idd-implement #34 #36 #38 --pr` 之後）；單發 verify N 個獨立 issue 用 batch 不對 — 應該各跑一次。

## External-agent / PR mode（v2.37.0+）

當 implement 階段委派給外部 agent（Codex / openclaw-task / 遠端 claw / Copilot Workspace）時，改動不在本地工作樹，而在某個 PR 或遠端 branch。`idd-verify` 支援三種輸入來源：

```bash
idd-verify #98 --pr 123               # PR mode：gh pr diff（最常見）
idd-verify --pr 123                   # 不帶 issue：從 PR body Refs #N auto-discover
idd-verify #98 --commits 3            # 本地：HEAD~3..HEAD（外部 agent commit 到當前 tree）
idd-verify #98 --since <ref>          # 本地：<ref>..HEAD
idd-verify #98 --branch <name>        # branch：origin/<default>...<name>（commit 但沒 PR）
```

PR mode 下：
- **Master comment** post 到 PR（外部 agent owner 看 PR、code review 在 PR）
- **Pointer comment** post 到每個 PR ref'd 的 issue（1 行指回 PR 的 verify comment URL）
- **Issue ↔ PR 對應強制**：PR body 沒任何 `Refs #N` → abort；user 給的 issue 不在 PR 的 Refs set 裡 → abort

完整契約見 [external-agent-delegation.md](../../references/external-agent-delegation.md)。

## 參數

```
/idd-verify #42                     → Agent Team (5) + Codex 平行（預設）；auto-detect input source
/idd-verify #42 codex               → 只用 Codex CLI
/idd-verify #42 team                → 只用 Agent Team（不跑 Codex）
/idd-verify #42 --loop              → 驗證 + ralph-loop 自動修復迴圈
/idd-verify #42 --pr 123            → PR mode（master 落在 PR、issue 拿 pointer）
/idd-verify --pr 123                → PR mode 不帶 issue：從 PR body Refs #N 自動 discover
/idd-verify #42 --commits 3         → 本地 mode：HEAD~3..HEAD
/idd-verify #42 --since <ref>       → 本地 mode：<ref>..HEAD
/idd-verify #42 --branch <name>     → branch mode：origin/<default>...<name>
/idd-verify                         → 通用 code review（無 issue）
```

## Configuration

按 [config-protocol](../../references/config-protocol.md) 解析 target repo:

- `--repo owner/repo` flag → per-invocation override
- Walk-up `.claude/issue-driven-dev.local.json`(從 cwd 往上找)
- Path / git predicates 自動匹配

如完全找不到 config,詢問 `github_repo` 並建立 `$PWD/.claude/issue-driven-dev.local.json`。

**Group/predicate 行為**:`idd-verify` 操作既存 issue,只用 path/git 類 predicate。Group config 會 fall through 到 primary repo。

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
└── Codex CLI（gpt-5.5 xhigh，獨立 process）
    └── 完全獨立，看不到 team 的討論

→ 6 個 findings 合併去重 → 呈現結果
```

**為什麼 6 個？**
- 5 個 Claude teammates 在同一個 team 裡**互相挑戰**（不是各自獨立報告）
- Devil's Advocate 的工作是**試著證明其他 4 個的通過判斷是錯的**
- Codex 是完全不同的模型家族（gpt-5.5），提供**跨模型盲驗**

## Execution

### Step 0: Bootstrap Stage Task List（強制)

**在動任何事之前**先用 `TaskCreate` 為這個 stage 建 todo list:

```
TaskCreate(name="resolve_input_source", description="Step 0.5: 解析 --pr / --commits / --branch / --since flag；都沒帶就跑 auto-detect（count Refs #N commits since origin/<default>，再 gh pr list 找 open PR），有歧義時 AskUserQuestion 確認")
TaskCreate(name="gate_pr_correspondence", description="Step 0.7: PR mode 下強制檢查 issue↔PR 對應 — gh pr view --json body 抓 Refs #N，跟 user 指定的 issue 比對；PR 沒任何 Refs 或 user issue 不在 set 內 → abort 並告訴使用者怎麼修")
TaskCreate(name="get_diff_and_issue", description="依 input source 取 diff（gh pr diff / git diff HEAD~N / git diff origin/<default>...<branch>） + gh issue view,存 diff 到 /tmp 供 agents 讀取；PR mode 額外做 gh pr checkout 並記住原 branch")
TaskCreate(name="check_attachments", description="確認 .claude/.idd/attachments/issue-NNN/ 存在,把 attachment 路徑塞進 reviewer agent prompt 作為 source-of-truth context。manifest 缺漏 → 警告繼續(reviewer 仍跑,但 verification 完整度受限)。依 rules/process-attachments.md。")
TaskCreate(name="launch_parallel_reviewers", description="6 個 tool calls 同一 message: TeamCreate + 5 Agent(requirements/logic/security/regression/devils-advocate) + 1 Bash codex,prompt 中引用 attachment 路徑")
TaskCreate(name="wait_for_claude_agents", description="等 5 Claude teammates 全部 idle,讀 /tmp/verify_${NUMBER}_findings_*.md")
TaskCreate(name="wait_for_codex", description="等 Codex 背景任務完成,讀 /tmp/codex-verify-${NUMBER}.md")
TaskCreate(name="merge_findings", description="合併 6 個來源 findings 去重,severity 取最高")
TaskCreate(name="post_master_and_pointers", description="PR mode: master 貼到 PR + capture URL → 為每個 ref'd issue 貼 pointer comment；本地 mode: 貼到 issue（單 issue 直接貼／多 issue 用 SOP master+pointer）")
TaskCreate(name="restore_working_tree", description="PR mode 結束後 git checkout 回原 branch（Step 0.5 記住的）")
TaskCreate(name="decide_next_action", description="根據 findings: 通過→idd-close / 有 findings→修正 / scope creep→新 issue")
TaskCreate(name="triage_followup_issues", description="Step 5b: 分類 non-blocking findings → 問使用者要不要開新 issue，確認後批次建立")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。

**v2.32.0+ tagging 規則**：若 Verify findings comment 要 @-tag 寫 code 的人或要求審閱者，**必須**遵循 [`rules/tagging-collaborators.md`](../../rules/tagging-collaborators.md) 5 步協定（gh api → fuzzy match → AskUserQuestion fallback → @login 不用 display name → post 前 verify）。違反 = 通知錯人，不可逆。

**鐵律**:
- `wait_for_claude_agents` 和 `wait_for_codex` 都要跑到真的有 findings 內容,不能只看到 idle notification 就 completed
- 如果某個 reviewer 沒寫 findings 檔,用 `SendMessage` 請它補寫,或 fallback 自己做 coordinator backup 檢查
- `comment_to_issue` 一定要實際 post 到 GitHub,不是只在對話中顯示

---

### Step 0.5: 解析 input source（v2.37.0+）

依 [external-agent-delegation.md](../../references/external-agent-delegation.md) resolution algorithm：

```
1. --pr <N>          → PR mode（gh pr diff <N>）
2. --branch <name>   → branch mode（git diff origin/<default>...<name>）
3. --commits <N>     → 本地 mode（HEAD~N..HEAD）
4. --since <ref>     → 本地 mode（<ref>..HEAD）
5. 都沒帶            → auto-detect:
   a. N=$(git log --grep "#$NUMBER" origin/$DEFAULT_BRANCH..HEAD --oneline | wc -l)
      N>0  → 本地 mode HEAD~N..HEAD
      N=0  → b
   b. PRS=$(gh pr list --search "#$NUMBER in:body" --state open --json number,headRefName,author)
      1 PR  → AskUserQuestion「Verify PR #X 還是本地 diff？」
      2+ PR → AskUserQuestion 列全部
      0 PR  → fall back HEAD~1（保留 v2.36 行為）
```

PR mode 額外做：

```bash
# 記住原 branch 供 restore
ORIGINAL_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# pre-condition: working tree clean
[ -z "$(git status --porcelain)" ] || { echo "Working tree not clean — abort"; exit 1; }

# checkout PR head
gh pr checkout $PR --repo $GITHUB_REPO
```

### Step 0.7: PR ↔ issue 對應強制（PR mode only，v2.37.0+）

```bash
DISCOVERED=$(gh pr view $PR --repo $GITHUB_REPO --json body -q .body | grep -oE '#[0-9]+' | sort -u)

if [ -z "$DISCOVERED" ]; then
  echo "ABORT: PR #$PR has no Refs #N — violates IDD discipline."
  echo "Add 'Refs #N' to PR body and retry."
  exit 1
fi

# user 給的 issue 必須在 discovered set 裡
for ISSUE in $USER_ISSUES; do
  echo "$DISCOVERED" | grep -q "#$ISSUE" || {
    echo "ABORT: PR #$PR does not ref #$ISSUE — correspondence broken."
    exit 1
  }
done

# discovered 比 user 給的多 → AskUserQuestion 確認 scope
EXTRA=$(comm -23 <(echo "$DISCOVERED") <(echo "$USER_ISSUES" | sort -u))
[ -n "$EXTRA" ] && AskUserQuestion "PR also refs $EXTRA — verify those too, or scope to $USER_ISSUES only?"
```

### Step 1: 取得 diff 和 issue

依 Step 0.5 resolved source：

```bash
# PR mode
git diff --stat origin/$DEFAULT_BRANCH...HEAD          # PR head 已 checkout
gh pr diff $PR --repo $GITHUB_REPO > /tmp/diff_$NUMBER.patch

# 本地 mode
git diff --stat                                         # uncommitted
git diff --stat HEAD~$COMMITS                           # explicit --commits
git diff --stat $SINCE_REF                              # explicit --since

# branch mode
git diff --stat origin/$DEFAULT_BRANCH...$BRANCH

# 取 issue（每個 ref'd issue 都要抓）
for I in $REFD_ISSUES; do
  gh issue view $I --repo $GITHUB_REPO --json title,body > /tmp/issue_$I.json
done
```

### Step 1.5: 檢查 Attachment(下游,給 reviewer agents 用)

依 [`rules/process-attachments.md`](../../rules/process-attachments.md):

```bash
IDD_CALLER=idd-verify bash $CLAUDE_PLUGIN_ROOT/scripts/process-attachments.sh check $NUMBER
```

Exit code:
- `0` — manifest 完整,reviewer prompt 可引用 `.claude/.idd/attachments/issue-NNN/` 下檔案
- `1` — manifest 缺漏或有新增 attachment → 警告但繼續(reviewer 仍跑,但 verification 完整度受限,在 final report 註明)

把 attachment 路徑列入 Step 2 的 reviewer prompt 作為 source-of-truth context(尤其 requirements reviewer 需要原始需求文件)。**禁止**只在 prompt 寫「issue 有附件」而不給具體 path — reviewer agents 看不到 path 等於沒附件。

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
  command: `codex exec --full-auto -c 'model="gpt-5.5"' -c 'model_reasoning_effort="xhigh"' -c 'service_tier="fast"' -o /tmp/codex-verify-$NUMBER.md "You are verifying code changes for Issue #$NUMBER: $TITLE. Go through EACH requirement: FULLY / PARTIALLY / NOT addressed. Flag scope creep and regressions. Reply in Traditional Chinese."`,
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

### Step 4: Comment（master + pointer 規則）

依 Step 0.5 resolved mode 決定 master comment 落在哪：

| Mode | Master comment 落地 | Pointer comments |
|------|-------------------|------------------|
| 本地 / branch（單 issue）| `gh issue comment $NUMBER` | 無 |
| 本地 / branch（cluster ≥2 issue）| `gh issue comment $HUB_ISSUE`（第一個 #N 當 hub） | 其餘 #N 各貼 1 行 pointer |
| **PR mode** | `gh pr comment $PR` | **每個** PR ref'd issue 都貼 pointer |

#### PR mode（v2.37.0+）

```bash
# 1. Post master to PR, capture URL
MASTER_URL=$(gh pr comment $PR --repo $GITHUB_REPO --body-file /tmp/master.md 2>&1 | tail -1)

# 2. Compose pointer body using captured PR comment URL
sed "s|__MASTER_URL__|$MASTER_URL|g" /tmp/pointer_template.md > /tmp/pointer.md

# 3. Post pointer to each ref'd issue in parallel
for I in $REFD_ISSUES; do
  gh issue comment $I --repo $GITHUB_REPO --body-file /tmp/pointer.md &
done
wait
```

Pointer template:

```markdown
## Verify (via PR #__PR__)
**Result**: __PASS_OR_FAIL__ — __SUMMARY__
**Full report**: __MASTER_URL__

This issue's findings: see "#__ISSUE__" section in the linked report.
```

#### 本地 / branch mode

單 issue：直接貼到 issue。

```bash
gh issue comment $NUMBER --repo $GITHUB_REPO --body "$MERGED_FINDINGS"
```

Cluster（≥2 issue 共用一份 verify report）：

**Rule**: 一定先 post master comment 到 hub issue, **capture 回傳的 URL**（`gh issue comment` 輸出的 `https://...#issuecomment-NNN` 那一行），**才**寫 pointer comment body。Pointer 必須使用剛 capture 的 URL，不可從先前對話裡複製貌似的 URL（容易誤用 Implementation Plan / Diagnosis 等更早的 comment URL）。

**為什麼是 SOP**: 此模式被多次重複犯錯（che-word-mcp #62 batch triage、Bundle A v3.15.2 ship comment）。每犯一次需用 `gh api repos/.../issues/comments/<id> -X PATCH -F body=...` 批次補丁 N 個 comment。把 capture-then-write 升格為 SOP 預防 recurrence。

**Helper pattern**:
```bash
# 1. Post master, capture URL
MASTER_URL=$(gh issue comment $HUB_ISSUE --repo $REPO --body-file /tmp/master.md 2>&1 | tail -1)

# 2. Compose pointer body using captured URL
sed "s|__MASTER_URL__|$MASTER_URL|g" /tmp/pointer_template.md > /tmp/pointer.md

# 3. Post pointers in parallel
for I in $POINTER_ISSUES; do
  gh issue comment $I --repo $REPO --body-file /tmp/pointer.md &
done
wait
```

#### Restore working tree（PR mode only）

Step 4 完成後 restore：

```bash
git checkout $ORIGINAL_BRANCH   # Step 0.5 記住的
```

格式（本地 / branch mode）：
```markdown
## Verify: #NNN

### Engine
Agent Team (5 Claude reviewers) + Codex (gpt-5.5)

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

格式（PR mode，cluster 時 per-issue 分區段）：
```markdown
## Verify Report — PR #PPP

### Engine
Agent Team (5 Claude reviewers) + Codex (gpt-5.5)

### Aggregate
**PASS / FAIL** — N blocking, M follow-up

### Scope coverage
PR refs: #98, #105
Verified scope: #98, #105

---

### #98 — {issue 98 title}

**Requirements coverage**: X/Y addressed

| # | Severity | Finding | Source | Action |
|---|----------|---------|--------|--------|
| 1 | P1 | ... | team:logic+codex | Blocking |

---

### #105 — {issue 105 title}

**Requirements coverage**: X/Y addressed

| # | Severity | Finding | Source | Action |
|---|----------|---------|--------|--------|
| 2 | P3 | ... | team:security | Follow-up |
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

#### Step 5d: Record routing outcome (v2.38.0+, optional)

If `idd-route` is installed, record this verify outcome to the routing-stats jsonl. Powers data-driven recommendation in future `idd-diagnose` calls. **Skip silently if binary missing.**

```bash
if command -v idd-route &>/dev/null; then
  REPO_PATH=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  STATS="$REPO_PATH/.claude/.idd/routing-stats.jsonl"

  # Detect which agent implemented this round.
  # Heuristic: PR head commit author / branch prefix.
  #   codex/* branch or codex-* commit author → codex-gpt-5.5-xhigh
  #   other → claude-opus-4.7 (default; user can override --agent)
  AGENT=$(detect_agent_from_commits)

  # Scope from PR diff or commit range
  SCOPE_FILES=$(echo "$VERIFIED_DIFF" | grep -c '^diff --git')
  SCOPE_LOC=$(echo "$VERIFIED_DIFF" | grep -cE '^[+-][^+-]')

  # Round trips: count implement→verify cycles seen for this issue
  ROUND_TRIPS=$(count_round_trips "$NUMBER")

  # Findings from merged report
  BLOCKING=<count>; MEDIUM=<count>; LOW=<count>; FOLLOWUPS=<count>

  COMPLEXITY=$(parse_complexity_from_diagnosis)  # Simple/Plan/Spectra
  SIGNALS=$(detect_signals)  # comma-separated controlled vocabulary

  idd-route record \
    --stats-file "$STATS" \
    --issue "$NUMBER" --issue-repo "$GITHUB_REPO" \
    --agent "$AGENT" \
    --complexity "$COMPLEXITY" \
    --scope-files "$SCOPE_FILES" --scope-loc "$SCOPE_LOC" \
    --signals "$SIGNALS" \
    --round-trips "$ROUND_TRIPS" \
    --verify-blocking "$BLOCKING" --verify-medium "$MEDIUM" --verify-low "$LOW" \
    --followups "$FOLLOWUPS" \
    --outcome in_review \
    --recorded-by "idd-verify-2.38.0" \
    2>/dev/null || echo "idd-route record failed (non-fatal)" >&2
fi
```

`idd-close` will append a follow-up record finalizing outcome to `merged` or `abandoned`. Append-only; original `in_review` stays for audit.

Full integration contract: [`references/agent-routing.md`](../../references/agent-routing.md).

## Engine: codex（快速模式）

只用 Codex，不開 team。適合小改動：

```bash
codex exec --full-auto \
  -c 'model="gpt-5.5"' \
  -c 'model_reasoning_effort="xhigh"' \
  -c 'service_tier="fast"' \
  -o /tmp/codex-quick-review.md \
  "Review the current git diff. Flag bugs, logic errors, security issues. Reply in Traditional Chinese."
```

> **Fast mode note**: `service_tier="fast"` 加速 GPT-5.5 回應（需較多 credits,換取 2-5x 速度）。驗證場景對速度敏感（user 在等 findings），預設開啟;若要省 credit 可移除此 flag。

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
