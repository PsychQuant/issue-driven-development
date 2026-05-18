---
name: idd-verify
description: |
  驗證 uncommitted/committed/PR code 是否滿足 Issue 的所有要求。
  預設用 5 個 general-purpose Agents（Claude reviewers 互相挑戰）+ Codex CLI（gpt-5.5）平行驗證。
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
/idd-verify #42                     → 5 general-purpose Agents + Codex 平行（預設）；auto-detect input source
/idd-verify #42 codex               → 只用 Codex CLI
/idd-verify #42 team                → 只用 5 general-purpose Agents（不跑 Codex；legacy alias `team` 保留 backward compat）
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
├── 5 general-purpose Agents（Claude reviewers，互相挑戰；file-based output）
│   ├── Requirements — issue 要求覆蓋率
│   ├── Logic — 邏輯正確性、edge cases、null handling
│   ├── Security — injection、權限、hardcoded secrets
│   ├── Regression — scope creep、副作用、既有功能
│   └── Devil's Advocate — 反駁前四個的「通過」判斷
│
└── Codex CLI（gpt-5.5 xhigh，獨立 process）
    └── 完全獨立，看不到其他 reviewer Agents 的 findings 檔

→ 6 個 findings 合併去重 → 呈現結果
```

**為什麼 6 個？**
- 5 個 Claude reviewers 各為獨立 `Agent(subagent_type=general-purpose)` call，平行 spawn 並寫 file-based output；Devil's Advocate 透過 polling 等其他 4 個 findings 檔產生後讀取 + 反駁（v2.59.0+, #52 重構自 pre-2.59 TeamCreate model — 詳見 Step 2 Engine note）
- Devil's Advocate 的工作是**試著證明其他 4 個的通過判斷是錯的**
- Codex 是完全不同的模型家族（gpt-5.5），提供**跨模型盲驗**

## Execution

### Step 0: Bootstrap Stage Task List（強制)

**在動任何事之前**先用 `TaskCreate` 為這個 stage 建 todo list:

```
TaskCreate(name="resolve_input_source", description="Step 0.5: 解析 --pr / --commits / --branch / --since flag；都沒帶就跑 auto-detect（count Refs #N commits since origin/<default>，再 gh pr list 找 open PR），有歧義時 AskUserQuestion 確認")
TaskCreate(name="gate_pr_correspondence", description="Step 0.7: PR mode 下強制檢查 issue↔PR 對應 — gh pr view --json body 抓 Refs #N，跟 user 指定的 issue 比對；PR 沒任何 Refs 或 user issue 不在 set 內 → abort 並告訴使用者怎麼修")
TaskCreate(name="scan_pr_body_trailers", description="Step 0.8: PR mode 下用 gh pr view --json closingIssuesReferences 查本 PR 是否 linked-to-auto-close 任何 issue（GitHub 權威解析）— 非空則 warn（merge 時會 auto-close issue、bypass /idd-close gate）。Warn-only，不 abort")
TaskCreate(name="get_diff_and_issue", description="依 input source 取 diff（gh pr diff / git diff HEAD~N / git diff origin/<default>...<branch>） + gh issue view,存 diff 到 /tmp 供 agents 讀取；PR mode 額外做 gh pr checkout 並記住原 branch")
TaskCreate(name="check_attachments", description="確認 .claude/.idd/attachments/issue-NNN/ 存在,把 attachment 路徑塞進 reviewer agent prompt 作為 source-of-truth context。manifest 缺漏 → 警告繼續(reviewer 仍跑,但 verification 完整度受限)。依 rules/process-attachments.md。")
TaskCreate(name="launch_parallel_reviewers", description="6 個 tool calls 同一 message: 5 Agent(subagent_type=general-purpose) for requirements/logic/security/regression/devils-advocate + 1 Bash codex(run_in_background:true),prompt 中引用 attachment 路徑 + 強制 file-output rule (per #52 v2.59.0+,replaces TeamCreate model from #47 incident)")
TaskCreate(name="wait_for_claude_agents", description="5 Agent calls 是 blocking,return 後立刻 ls /tmp/verify_${NUMBER}_findings_*.md 確認 5 個 findings 檔都 non-empty;缺者進 Step 2.5 Recovery Protocol")
TaskCreate(name="recovery_protocol", description="Step 2.5 (NEW per #52): 缺 findings 檔者 SendMessage retry with FULL context re-paste(不假設 context 倖存 idle/wake);二次 idle → coordinator self-review for that role + 在 master report 標 process gap")
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
- `wait_for_claude_agents` 和 `wait_for_codex` 都要跑到真的有 findings 內容,不能只看到 Agent return / idle notification 就 completed — 必須 `ls /tmp/verify_${NUMBER}_findings_*.md` 確認 5 個檔案 + non-empty
- 如果某個 reviewer 沒寫 findings 檔 → 進 Step 2.5 Recovery Protocol(SendMessage retry with FULL context re-paste);二次 idle → coordinator self-review fallback + master report 標 process gap
- `comment_to_issue` 一定要實際 post 到 GitHub,不是只在對話中顯示
- **絕對禁用** `subagent_type=Explore` for reviewer agents — Explore 是 read-only,**沒有 Write tool**,無法寫 findings 檔(#47 incident proved this; per #52 v2.59.0+ 強制 general-purpose)

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

### Step 0.8: PR auto-close detection（PR mode only，#87/#74）

`/idd-close` 的 checklist gate + closing summary 只在實際跑 `/idd-close` skill 時生效。若 PR 帶 GitHub auto-close 連結（PR body 內 `Closes #N` 等 trailer），GitHub 在 merge 時會直接 close 對應 issue，**完全 bypass** `/idd-close` — gate 沒跑、closing summary 沒寫，audit trail 斷裂。本 step 在 verify 時偵測，命中就 warn，讓使用者在 merge 前 strip。

偵測用 GitHub 自己的 `closingIssuesReferences` —— 這是 GitHub 對「本 PR merge 後會 auto-close 哪些 issue」的**權威解析**，已涵蓋所有 GitHub 承認的 trailer 形式（`Closes #N`、colon form `Closes: #N`、cross-repo、issue URL 等）。**不自寫 regex** 掃 PR body：自寫 regex 必然是 GitHub keyword parser 的脆弱近似（`/idd-verify --pr 94` R1 verify 實證 regex 漏了 colon form `Closes: #87`）。`closingIssuesReferences` 是 GitHub 算好的結果，定義上零漏判、零誤判。

這是**防禦縱深**：真正的修法是各 skill 的 PR-body template 不嵌 trailer（idd-implement / idd-all / idd-all-chain / pr-flow.md 已於 #87/#74 cluster 修正）；本 gate 是第二層 —— 即使未來某個 template regression 漏掉、或使用者手動貼了 trailer，verify 仍能在 merge 前抓到。

```bash
# PR mode only — skip in local / branch / commits mode.
# closingIssuesReferences = GitHub's own authoritative parse of which issues this
# PR auto-closes on merge. Covers every trailer form GitHub honors; zero false
# positive (it IS what GitHub will do) and zero parser-reimplementation risk.
CLOSING_REFS=$(gh pr view "$PR" --repo "$GITHUB_REPO" \
  --json closingIssuesReferences \
  -q '.closingIssuesReferences[].number' 2>/dev/null || true)

if [ -n "$CLOSING_REFS" ]; then
  echo "⚠️  WARNING: PR #$PR is linked to auto-close issue(s): $(printf '%s' "$CLOSING_REFS" | tr '\n' ' ')"
  echo "    On merge GitHub will auto-close these, bypassing /idd-close's checklist"
  echo "    gate + closing summary. Strip the close trailer from the PR body before merge:"
  echo "      gh pr edit $PR --repo $GITHUB_REPO --body '<body without the Closes/Fixes/Resolves #N trailer>'"
fi
```

**Warn-only，不 abort**：gate 的價值是把風險在 merge 前 surface 給使用者，由使用者決定是否 `gh pr edit`。語意同 `idd-close` Step 1.6 semantic gate（也是 warn-only）。`/idd-close #N` 這類 skill invocation 不會出現在 `closingIssuesReferences`（hyphenated token，GitHub 不當 close keyword），因此天然零誤判 —— 不需像自寫 regex 那樣特別排除。

**Regex 設計**：涵蓋 GitHub 全部 inflection（`close`/`closes`/`closed`/`fix`/`fixes`/`fixed`/`resolve`/`resolves`/`resolved`），case-insensitive。關鍵字前綴用 `(^|[^-/[:alnum:]])` 而非 `\b` —— `\b` 會把 `/idd-close #N`（IDD skill 呼叫指令，hyphenated token）誤判為 trailer，但 GitHub 實際**不會** auto-close `/idd-close #N`（hyphen 前綴）。前綴排除 `-` `/` 與英數字，精確對齊 GitHub 真實行為，同時保留對 `(Closes #N)` / `**Closes #N**` 等 context-blind 命中（`(` `*` 等非英數前綴仍命中，正是本 bug 要抓的）。

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

### Step 2: 平行啟動 5 Reviewer Agents + Codex (v2.59.0+, #52)

**CRITICAL: 6 個 tool calls（5 Agent + 1 Bash codex）必須在同一個 message 送出。不可分步驟。**

> **Engine note (#47 incident lesson, #52 v2.59.0+ fix)**：
>
> **絕對禁用** `subagent_type=Explore` for reviewer agents。Explore agent 是 read-only（per Agent tool docs：「All tools except Agent, ExitPlanMode, Edit, Write, NotebookEdit」），**沒有 Write tool**，無法寫 findings 檔。`#47` verify 真實發生過：spawn 5 個 Explore agents，5 個全部 idle without output，verify 退化成 1-AI (Codex only)。
>
> **正確選擇** `subagent_type=general-purpose`：含完整 tool set (Read/Grep/Glob/Bash/**Write**/Edit)，可寫 `/tmp/verify_<NUMBER>_findings_<role>.md`。
>
> **不用 TeamCreate**（pre-v2.59.0 model）的原因：
> - TeamCreate teammates 必須在 `tools` field 顯式列出 Write，現有 prompt template 配置只給 Read/Grep/Glob/Bash —— 同 Explore 一樣 Write-missing failure mode
> - TeamCreate's `wait_for_idle` 在 idle/wake cycle 後 context 流失（#47 觀察到）
> - **Side benefit**：no team → no `TeamDelete` cleanup gap (#70 dissolves structurally)
>
> 完整 #47 process gap 詳細 root cause 三層見 issue body。

#### 2a. 5 Reviewer Agents（parallel, file-based output）

每個 reviewer 用 single `Agent` tool call（**not** TeamCreate teammate）。所有 5 個 + 1 個 Bash codex **必須在同一個 message** 一起發出（單 message 多 tool calls = parallel）。

> **Pre-spawn prompt persistence (per /idd-verify --pr 73 round 1 P1.2)**: BEFORE invoking the 5 Agent calls, coordinator MUST save each reviewer's full prompt to `/tmp/verify_${NUMBER}_prompt_<role>.md`. Step 2.5b Recovery Protocol re-paste step reads these files; if they don't exist, retry fails. Save via:
>
> ```bash
> # Coordinator runs BEFORE Agent invocations
> cat > /tmp/verify_${NUMBER}_prompt_requirements.md <<'EOF'
> 你是 Requirements Reviewer for Issue #...
> (full prompt body here, exactly as passed to Agent below)
> EOF
> # ... same for logic, security, regression, devils-advocate
> ```
>
> Do this once per verify invocation (paths include `${NUMBER}` so different issues don't collide). The 5 prompt files + 5 findings files share the same `verify_<NUMBER>_*` naming convention.

**Prompt template 強制要素**（每個 reviewer 都必含這 3 條，違反 = process gap）：

1. **明示 file output path**：`Write your findings to /tmp/verify_${NUMBER}_findings_<role>.md when done.`
2. **明示 DO NOT idle**：`Your task is NOT complete until the file is written. Do NOT idle without producing the output file.`
3. **明示 retry context expectation**：`If you receive a later SendMessage with the same prompt re-pasted, treat that as a retry signal; the original context may have been lost across an idle/wake cycle.`

```
Agent({
  description: "Requirements review for #${NUMBER}",
  subagent_type: "general-purpose",
  prompt: `你是 Requirements Reviewer for Issue #${NUMBER}: ${TITLE}.

Issue body:
${BODY}

Diff path: /tmp/diff_${NUMBER}.patch
Attachment paths (if any): .claude/.idd/attachments/issue-${NUMBER}/...

你的任務：逐一檢查 issue 的每個要求是否在 code 中被實現。
對每個要求標記：FULLY / PARTIALLY / NOT addressed。
用 Read/Grep 工具實際去看相關檔案確認。

OUTPUT (mandatory): Write your findings to /tmp/verify_${NUMBER}_findings_requirements.md when done.
Your task is NOT complete until the file is written. Do NOT idle without producing the output file.
If you receive a later SendMessage with the same prompt re-pasted, treat that as a retry signal — the original context may have been lost across an idle/wake cycle.`
})

Agent({
  description: "Logic review for #${NUMBER}",
  subagent_type: "general-purpose",
  prompt: `你是 Logic Reviewer for Issue #${NUMBER}: ${TITLE}.

Diff path: /tmp/diff_${NUMBER}.patch

你的任務：檢查邏輯正確性。
- Edge cases（null、empty、boundary values）
- 型別安全（numeric vs character、NA handling）
- 控制流程（if/else 覆蓋、switch fall-through）
用 Read 工具查看完整函數上下文。

OUTPUT (mandatory): Write findings to /tmp/verify_${NUMBER}_findings_logic.md.
Your task is NOT complete until the file is written. Do NOT idle without producing output.
If you receive a later SendMessage with the same prompt re-pasted, treat as retry signal.`
})

Agent({
  description: "Security review for #${NUMBER}",
  subagent_type: "general-purpose",
  prompt: `你是 Security Reviewer for Issue #${NUMBER}: ${TITLE}.

Diff path: /tmp/diff_${NUMBER}.patch

你的任務：檢查安全問題。
- SQL injection（字串拼接 vs parameterized）
- Hardcoded secrets
- 權限檢查
- 輸入驗證

OUTPUT (mandatory): Write findings to /tmp/verify_${NUMBER}_findings_security.md.
Your task is NOT complete until the file is written. Do NOT idle without producing output.
If you receive a later SendMessage with the same prompt re-pasted, treat as retry signal.`
})

Agent({
  description: "Regression review for #${NUMBER}",
  subagent_type: "general-purpose",
  prompt: `你是 Regression Reviewer for Issue #${NUMBER}: ${TITLE}.

Diff path: /tmp/diff_${NUMBER}.patch

你的任務：
1. 有沒有改到 issue 範圍外的東西（scope creep）？
2. 改動有沒有破壞既有功能？
3. 有沒有引入新的 dependency 但沒處理？
用 Grep 搜尋被改動的函數在哪裡被呼叫。

OUTPUT (mandatory): Write findings to /tmp/verify_${NUMBER}_findings_regression.md.
Your task is NOT complete until the file is written. Do NOT idle without producing output.
If you receive a later SendMessage with the same prompt re-pasted, treat as retry signal.`
})

Agent({
  description: "Devil's Advocate review for #${NUMBER}",
  subagent_type: "general-purpose",
  prompt: `你是 Devil's Advocate for Issue #${NUMBER}: ${TITLE}.

Diff path: /tmp/diff_${NUMBER}.patch

你的任務：**等其他 4 個 reviewer 完成後**，讀取他們的結論，然後試著反駁每一個「通過」的判斷。

**Sequencing protocol** (因為 5 個 Agent 是 parallel spawn，沒有 TeamCreate 的 wait_for_idle):
先用 bash polling loop 等其他 4 個 findings 檔案產生，再開始你的 review:

\`\`\`bash
# Poll for sibling findings files (max 30 iterations × 5s = 2.5 min timeout)
for i in $(seq 1 30); do
  ready=0
  for role in requirements logic security regression; do
    [ -s /tmp/verify_${NUMBER}_findings_$role.md ] && ready=$((ready+1))
  done
  [ "$ready" = "4" ] && break
  sleep 5
done

if [ "$ready" != "4" ]; then
  # Timeout fallback: write SENTINEL marker so Step 2.5 recovery scan detects
  # the timeout case (rather than treating non-empty file as valid review).
  # Sentinel = literal first line "[STAGE 2.5 RECOVERY: DEVILS_ADVOCATE_TIMEOUT_<ready>/4]"
  # Step 2.5a file existence check looks for this sentinel and DELETES the file
  # so retry/fallback's -s test correctly sees it as missing (per round 2 P1.1 fix).
  #
  # NOTE on quoting (per /idd-verify --pr 73 round 2 P1.2): bash single quotes
  # CANNOT escape apostrophes via backslash. Use printf '%s\n%s\n' "header" "body"
  # with double-quoted args (where backslash-apostrophe is unnecessary).
  printf '%s\n\n%s\n' \
    "[STAGE 2.5 RECOVERY: DEVILS_ADVOCATE_TIMEOUT_${ready}/4]" \
    "Devil's Advocate skipped: timeout waiting for sibling findings (${ready}/4 ready after 2.5min). Coordinator detects this sentinel and routes to retry once siblings arrive, or coordinator self-review fallback." \
    > /tmp/verify_${NUMBER}_findings_devils-advocate.md
  exit 0
fi
\`\`\`

After polling succeeds, read the 4 sibling findings files, then:
- 如果他們說「FULLY addressed」，找理由說它其實沒有
- 如果他們說「no security issues」，找他們漏掉的攻擊向量
- 如果找不到反駁的理由，才承認確實通過

這是對抗性驗證 — 你的存在是為了防止群體盲點。

OUTPUT (mandatory): Write findings to /tmp/verify_${NUMBER}_findings_devils-advocate.md.
Your task is NOT complete until the file is written. Do NOT idle without producing output.
If you receive a later SendMessage with the same prompt re-pasted, treat as retry signal.`
})
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

### Step 2.5: Recovery Protocol（NEW v2.59.0+, #52）

5 個 reviewer Agent calls return 後，**先做 file existence check**（不是直接進 Step 3 merge）。Coordinator 負責偵測哪些 reviewer 沒寫 findings 檔，並執行兩階段 recovery。

**Rule**: Step 3 merge logic 假設所有 5 個 findings 檔都存在 + non-empty。任何缺漏 = process gap，必須在 master report 顯式標示，**不可靜默繼續**。

#### 2.5a — File existence check

```bash
EXPECTED_FILES=(
  "/tmp/verify_${NUMBER}_findings_requirements.md"
  "/tmp/verify_${NUMBER}_findings_logic.md"
  "/tmp/verify_${NUMBER}_findings_security.md"
  "/tmp/verify_${NUMBER}_findings_regression.md"
  "/tmp/verify_${NUMBER}_findings_devils-advocate.md"
)

MISSING_ROLES=()
for f in "${EXPECTED_FILES[@]}"; do
  role=$(basename "$f" | sed -E 's/^verify_[0-9]+_findings_(.*)\.md$/\1/')
  if [ ! -s "$f" ]; then
    # File missing or empty
    MISSING_ROLES+=("$role")
  elif head -1 "$f" | grep -q '^\[STAGE 2.5 RECOVERY: DEVILS_ADVOCATE_TIMEOUT_'; then
    # Devil's Advocate sentinel — file exists but reviewer didn't actually run
    # (timed out waiting for siblings, per Step 2 DA polling loop fallback).
    # DELETE the sentinel file so downstream 2.5b retry polling (`-s` check)
    # and 2.5c fallback (`! -s` check) correctly see it as missing
    # (per /idd-verify --pr 73 round 2 P1.1 fix — sentinel file IS non-empty,
    # so without `rm` it would silently pass downstream -s checks).
    echo "→ Detected DEVILS_ADVOCATE_TIMEOUT sentinel for $role — deleting + routing to retry/fallback"
    rm -f "$f"
    MISSING_ROLES+=("$role")
  fi
done

if [ ${#MISSING_ROLES[@]} -eq 0 ]; then
  echo "→ All 5 reviewer findings files present + valid. Proceeding to Step 3 merge."
else
  echo "→ Recovery Protocol fires for: ${MISSING_ROLES[*]}"
  # 進 2.5b
fi
```

#### 2.5b — Retry with FULL context re-paste

對每個缺漏的 role：

1. **Send retry message** to that Agent's running instance via `SendMessage` (if Agent name is addressable; else this step is moot — Agent already returned to coordinator).
2. **CRITICAL**: re-paste the **FULL original prompt** including issue title / body / diff path / attachment paths / file output path. **不要假設 context 倖存 idle/wake cycle** — 這是 #47 incident 的核心 root cause。
3. Wait up to 90s (18 × 5s polling) for the file to appear.

```bash
for role in "${MISSING_ROLES[@]}"; do
  # Build retry prompt with full context re-paste
  RETRY_PROMPT="[RETRY] Original prompt re-pasted because the previous instance idled without producing output. Treat this as the canonical task instruction; do not assume any prior context.

$(cat /tmp/verify_${NUMBER}_prompt_${role}.md)"   # Coordinator saved prompts before spawn

  # If Agent instance is addressable via SendMessage (named team member or running agent):
  SendMessage(to="verify-${NUMBER}-${role}", body="$RETRY_PROMPT")  # OR spawn a fresh Agent if previous returned

  # Poll for file (90s max)
  for i in $(seq 1 18); do
    [ -s "/tmp/verify_${NUMBER}_findings_${role}.md" ] && break
    sleep 5
  done
done
```

> **Note on `SendMessage` applicability**: standalone `Agent` calls return to coordinator after completion (no persistent addressable instance). The retry path therefore typically means **spawn a fresh `Agent(subagent_type=general-purpose, ...)` with the retry prompt** rather than literal `SendMessage`. The retry distinction matters most for context-re-paste discipline — always re-paste the FULL original prompt.

#### 2.5c — Second-idle fallback: coordinator self-review

如果 retry 後仍缺檔（90s timeout），coordinator 自己做 self-review for that role：

```bash
for role in "${MISSING_ROLES[@]}"; do
  if [ ! -s "/tmp/verify_${NUMBER}_findings_${role}.md" ]; then
    # Coordinator self-review
    echo "## ${role} review (coordinator self-review — process gap)" \
      > "/tmp/verify_${NUMBER}_findings_${role}.md"
    echo "" >> "/tmp/verify_${NUMBER}_findings_${role}.md"
    echo "(${role} Agent failed to produce output after retry. Coordinator self-reviewed:)" \
      >> "/tmp/verify_${NUMBER}_findings_${role}.md"

    # Coordinator reads diff + issue + does role-specific review inline
    # (Quality lower than independent reviewer; flagged as process gap.)
    PROCESS_GAPS+=("${role}: Agent failed → coordinator fallback")
  fi
done
```

#### 2.5d — Process gap noting in master report

Step 4 master report **必須** 標示 process gap：

```markdown
### Process Gaps (if any)
- requirements: Agent failed → coordinator fallback (lower-quality review)
- (other roles as applicable)
```

無 gap 時不顯示此 section。

> **Why explicit process gap section?** Hiding "1 of 5 reviewers failed" inside aggregate metrics looks like clean PASS but is actually 4-AI not 5-AI ensemble. Verify discipline = explicitly mark engine degradation. Future maintainers reading old verify comments can spot when an Agent class was systematically failing (e.g. infrastructure issue, prompt bug) by grepping `Process Gaps` sections.

---

### Step 3: 合併 Findings

等 5 reviewer Agents（Step 2.5 Recovery Protocol 已 satisfy: 所有 findings 檔 present + non-empty）和 Codex 都完成後：

1. 收集 5 個 reviewer Agents 的 findings（從 `/tmp/verify_${NUMBER}_findings_*.md`）
2. 收集 Codex 的 findings（從 `/tmp/codex-verify-${NUMBER}.md`）
3. **去重**：相同檔案 + 相似描述 → 合併，標註來源 `[agents:logic+codex]`
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
5 general-purpose Agents (Claude reviewers, file-based output) + Codex (gpt-5.5, run_in_background)

### 要求覆蓋率
X / Y requirements addressed

### Findings（合併後）
| # | Severity | Finding | Source |
|---|----------|---------|--------|
| 1 | P1 | ... | agents:logic+codex |
| 2 | P2 | ... | agents:security |
| 3 | — | (devil's advocate 未能反駁) | agents:devils-advocate |

### Scope Check
{有沒有超出 issue 範圍的改動}
```

格式（PR mode，cluster 時 per-issue 分區段）：
```markdown
## Verify Report — PR #PPP

### Engine
5 general-purpose Agents (Claude reviewers, file-based output) + Codex (gpt-5.5, run_in_background)

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
| 1 | P1 | ... | agents:logic+codex | Blocking |

---

### #105 — {issue 105 title}

**Requirements coverage**: X/Y addressed

| # | Severity | Finding | Source | Action |
|---|----------|---------|--------|--------|
| 2 | P3 | ... | agents:security | Follow-up |
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
| 1 | MEDIUM | ... | agents:logic+codex | Follow-up |
| 2 | MEDIUM | ... | agents:regression | In-scope fix |
| 3 | LOW | ... | agents:security | Follow-up |
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
4. **Chain context manifest write** (per spawn-manifest contract, v2.55+ #44; v2.60+ #46 schema v2):每建一個 follow-up issue,額外呼叫 manifest helper:
   ```bash
   NEW_ISSUE_URL=$(gh issue create ...)   # existing
   NEW_ISSUE=$(basename "$NEW_ISSUE_URL")

   # `same_file` / `same_skill` 依 finding scope 判斷:
   # - finding 在同 file 內 → same_file=true
   # - finding 跨 module 但同 skill (e.g. 同個 idd-* skill 不同 step) → same_skill=true
   # - cross-cutting (跟 verified diff 完全無關) → 兩個都 false
   # 9th arg root_id: prefer chain shell's exported IDD_CHAIN_CURRENT_ROOT_ID env var;
   # fallback to current verified issue's $NUMBER (single-root chain or root self-spawn).
   # Defensive guard (v2.60+ #46 L2): skip explicitly if no root_id available, instead
   # of letting helper reject empty arg and `|| true` swallow silently.
   ROOT_ID_FOR_MANIFEST="${IDD_CHAIN_CURRENT_ROOT_ID:-${NUMBER:-}}"
   if [ -n "$ROOT_ID_FOR_MANIFEST" ]; then
     bash "$CLAUDE_PLUGIN_ROOT/scripts/manifest-append.sh" \
       "$REPO_ROOT" "$NEW_ISSUE" "idd-verify" "Phase 4 follow-up findings triage" \
       "follow-up-finding" "$same_file" "$same_skill" "$NEW_TITLE" "$ROOT_ID_FOR_MANIFEST" \
       2>/dev/null || true   # silent skip when chain context inactive
   fi
   ```
   See `references/spawn-manifest.md` for cross-skill contract. Manifest write is **additive** — baseline audit trail unchanged when manifest absent.
5. 輸出新建的 issue 清單

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

## Engine: team（只用 5 Reviewer Agents，alias `team` 保留為 backward-compat）

只 spawn 5 個 `Agent(subagent_type=general-purpose)` reviewer，不跑 Codex。適合不需要跨模型驗證、或 Codex 不可用的場景。CLI alias `team` 保留為 backward compat（pre-v2.59.0 model name），實際底層為 standalone Agent calls。

## Loop 模式

加上 `--loop` 後，用 ralph-loop 驅動驗證-修復迴圈。每輪用完整的 6-AI 驗證。

### Step 0a: ralph-loop dependency gate（v2.53+, #28）

當 invocation 含 `--loop` flag,**Step 0 Bootstrap 之前**先 invoke detector:

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/check-ralph-loop.sh" || exit 1
```

helper 行為見 `scripts/check-ralph-loop.sh`:exit 0 if installed, exit 1 with structured message + install hint if missing。Bypass 用 `IDD_SKIP_RALPH_CHECK=1`。

**為什麼 fail-fast 不 degrade**:`--loop` 是 user explicit feature request。沒裝 ralph-loop 時 silent fall back to single-pass verify 會違反 user 預期(以為跑了多輪 actually 沒跑)。abort + clear install hint 讓 user 自行選 install / 改 attended 模式。

對比 `idd-all` 的 Phase 0.6 是 **graceful degrade** — 因為 `idd-all` (PR, unattended) 是 v2.40.0 default(implicit invocation),break 既有 caller 不可接受。兩條 path 對 ralph-loop 缺失的處理不同,各有理由。

## 鐵律

- **不跳過驗證**。「看起來對了」不算。
- **有 findings 就不 close**。先修，再 verify。
- **Devil's Advocate 是必要的**。防止 4 個 reviewer 的群體盲點。
- **Codex 是獨立的**。它看不到 5 reviewer Agents 的 findings 檔，提供真正的盲驗。

## Auto-Update

Verify comment 完成後，自動執行 `idd-update` 更新 issue body 的 Current Status。

## Next Step

驗證通過後：`/issue-driven-dev:idd-close #NNN`
