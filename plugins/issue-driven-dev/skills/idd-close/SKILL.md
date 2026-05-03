---
name: idd-close
description: |
  寫 closing comment 並關閉 GitHub Issue。
  強制記錄做了什麼、怎麼驗證的。
  支援 cluster close（v2.34.0+）：多個 #N（如 `#34 #36 #38`）共用 PR 的 cluster 一次關閉，**每個 issue 各寫獨立 closing summary**（不偷懶合併）。
  Use when: verify 通過後、commit 之後。
  防止的失敗：修完了但三個月後沒人知道當時做了什麼。
argument-hint: "#issue [#issue ...] e.g. '#42' or '#34 #36 #38' (cluster close after merge)"
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

## Cluster-PR mode（v2.34.0+）

`idd-close #34 #36 #38` cluster close：refuse 若任一 issue checklist gate 失敗、refuse 若 PR 未 merge。通過後 **per issue 各自 fetch 該 issue 在 PR 裡的 commits**（`git log --grep "#N"` 過濾 PR commit range），各寫獨立 closing summary，再依序 `gh issue close`。

完整契約見 [batch-and-cluster.md](../../references/batch-and-cluster.md)。**不**會合併出一份 batch summary — 每個 issue 仍要它自己的 root cause / solution / verification trail，那是 closing comment 的審計價值核心，不能省。Phase=`closed` 各自 auto-update。

設計理由：closing summary 是 IDD 紀律最神聖的部分（pretend N 個 issue 共一份 summary = 偷懶 hallucinate）。Cluster mode 只省「重複打 N 次 `/idd-close #N`」的肌肉動作，不省 audit content。

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

| 區段標題 (`## ` 或 `### `) | 當成 checklist source | Notes |
|----------------------------|---------------------|-------|
| `Strategy` | ✅ | **Superseded** when Implementation Complete > Checklist 全 `[x]`（v2.41.0+, #515）|
| `Implementation Plan` | ✅ | **Superseded** when Implementation Complete > Checklist 全 `[x]`（v2.41.0+, #515）|
| `Implementation Complete` → `Checklist` | ✅ | Canonical source of truth（`idd-implement` Step 5 寫回）。Triggers supersession of Strategy / Implementation Plan when 全 `[x]`. |
| `Todo` / `Tasks` / `Checklist` | ✅ | 永遠 scan |
| `Current Status` → `Tasks` | ✅ | 永遠 scan |
| `Problem` / `Repro` / `Steps to reproduce` / `Workaround` / `Expected` / `Actual` | ❌ 忽略 | 描述性區段，checkbox 是情境不是 todo |
| _(未列出的標題)_ | ❌ 忽略 | 保守：不掃不認識的區段 |

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

**Pre-implementation supersession check (v2.41.0+, #515 fix;canonical IC_R011 reference v2.43.0+, #525)**：

> **Note**: this is a **gate logic** fix (recognize Implementation Complete > Checklist as canonical when supersession active), NOT an IC_R011 checkpoint. The IC_R011 checkpoint for `/idd-close` (closing summary follow-up keyword scan) is tracked separately in [#527](https://github.com/kiki830621/ai_martech_global_scripts/issues/527) and will cite [`references/ic-r011-checkpoint.md`](../../references/ic-r011-checkpoint.md) when implemented.



`Strategy` 跟 `Implementation Plan` 是 **pre-implementation snapshots**——它們在 `idd-diagnose` / `idd-plan` 階段寫進 issue,記錄當時的 design intent。`idd-implement` Step 5 「Checklist Sync」**只**回寫 `## Implementation Complete > ### Checklist`（自己發的 comment 內），**不會** PATCH `Strategy` / `Implementation Plan` comments 的 checkbox。

因此即使 work 真正完成,Strategy / Plan 的 `- [ ]` 仍停留在 pre-impl 狀態,gate 會誤判為「有未完成 todo」,refuse close（observed in #455 / #510 close, 2026-05-03）。

修法：當 `Implementation Complete > Checklist` 存在 **且其所有 items 全部 `- [x]`** 時，視為 **canonical state of truth**,Strategy 跟 Implementation Plan 的 `- [ ]` 一律當 superseded（skip gate）。

```
impl_complete = scan_subsection("## Implementation Complete > ### Checklist")
                # 若多個 ## Implementation Complete comments，按 createdAt desc 取最新

supersession_active = (impl_complete exists)
                      AND (len(impl_complete.items) > 0)
                      AND (all items in impl_complete are - [x])

if supersession_active:
    # Narrow scan：只 gate 真正 canonical 的 sources
    sources = [Implementation Complete > Checklist,
               Current Status > Tasks,
               Todo / Tasks / Checklist (top-level headings)]
    log "  ✅ Pre-implementation snapshots superseded by Implementation Complete > Checklist"
else:
    # Legacy / partial state：fall back to full spec table
    sources = [Strategy, Implementation Plan, Implementation Complete > Checklist,
               Todo / Tasks / Checklist, Current Status > Tasks]
```

**為什麼 supersession 是安全的**：

- 防 motivated cheating：若 user 沒跑 `idd-implement`（Implementation Complete 不存在或不完整）就嘗試 close,fall back 維持 strict gate scan
- 防 honest forgetting：若 Implementation Complete 內仍有 `- [ ]`，supersession 不 trigger,gate 正常擋
- 解 #515 friction：完整 lifecycle（diagnose → plan → implement → close）的 happy path,user 不需手動 `gh api PATCH` Strategy / Plan comments

**邊界 case**：

| Implementation Complete > Checklist 狀態 | 行為 |
|---|---|
| 不存在（legacy issue 或 idd-implement 沒跑) | Legacy fallback：scan all 5 sources（含 Strategy / Implementation Plan）|
| 存在但 0 items | 視同不存在 → Legacy fallback |
| 存在,某些 `- [ ]` | Legacy fallback：scan all 5 sources（仍會 catch Implementation Complete 內未完項目)|
| 存在,全部 `- [x]` | **Supersession active**：only scan canonical sources |
| 存在,全部 `- [x]` 但有 `- [~]` / `- [-]` 含 reason | Supersession active（reason'd skips 本就 pass）|

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
TaskCreate(name="check_attachments", description="確認 closing comment 即將引用的 attachment 在 .claude/.idd/attachments/issue-NNN/ 仍存在(防止使用者搬檔造成失效引用);manifest 對照 issue 當下 attachment list,新增的不重新 fetch(那是 idd-diagnose 工作)。依 rules/process-attachments.md。")
TaskCreate(name="check_open_prs", description="Step 1.5: gh pr list 找引用 #NNN 的 open PR；若有 unmerged PR → refuse close")
TaskCreate(name="semantic_gate_check", description="Step 1.6: 對每個 - [x] bullet 做 keyword extraction → 驗證對應 artifact 真存在/有 commit。Warn-only。")
TaskCreate(name="draft_closing_comment", description="起草 Problem / Root Cause / Solution / Verification / Changes 五段式")
TaskCreate(name="review_with_user", description="顯示 closing comment 給使用者確認(若已明確 /idd-close 可省略此步)")
TaskCreate(name="closing_followup_keyword_scan", description="Step 3.5: scan drafted closing summary for trigger phrases (follow-up / deferred / future / 之後 / 順便 etc); orphan mentions without #NNN cross-link → AskUserQuestion 3-option per canonical references/ic-r011-checkpoint.md; PATCH closing summary inline + add `### Closing Follow-ups Filed` audit trail (advisory, non-blocking, per IC_R011 #527)")
TaskCreate(name="publish_and_close", description="gh issue comment + gh issue close")
TaskCreate(name="auto_update_body", description="跑 /idd-update #NNN 把 issue body 的 Current Status phase 改 closed（Step 6，常被漏）")
TaskCreate(name="report_result", description="輸出關閉後的 issue URL 與 commits chain")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。**TaskCreate 清單 = 真實的步驟清單；任何寫在 skill 裡但沒列進 TaskCreate 的步驟，都視為 skill 的 bug，必須補進 Task 清單。**

**v2.32.0+ tagging 規則**：若 Closing Summary comment 要 @-tag 相關 stakeholder（例如要通知 reporter），**必須**遵循 [`rules/tagging-collaborators.md`](../../rules/tagging-collaborators.md) 5 步協定（gh api → fuzzy match → AskUserQuestion fallback → @login 不用 display name → post 前 verify）。違反 = 通知錯人，不可逆。

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

### Step 1.4: 檢查 Attachment Disk Integrity

依 [`rules/process-attachments.md`](../../rules/process-attachments.md):

```bash
IDD_CALLER=idd-close bash $CLAUDE_PLUGIN_ROOT/scripts/process-attachments.sh verify $NUMBER
```

Exit code:
- `0` — manifest 列出的檔案在 disk 上都還在(closing comment 的 path 引用安全)
- `1` — 至少一個檔案被搬走 / 刪掉 → 警告使用者(closing comment 寫到失效引用)。**不 abort close**,讓使用者決定是否搬回或修改 closing comment 引用

無 manifest(issue 從未處理 attachment)→ 跳過此 step,exit 0。

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

### Step 3.5: Closing Summary Follow-up Keyword Scan (v2.45.0+, kiki830621/ai_martech_global_scripts#527)

**Compliance**: this step implements [IC_R011](https://github.com/kiki830621/ai_martech_global_scripts/issues/516) commercial low-bar filing for the **closure window** per the canonical [`references/ic-r011-checkpoint.md`](../../references/ic-r011-checkpoint.md) pattern (3-option AskUserQuestion + audit trail + rollback hatch).

**Why this step**: closing summaries often contain phrases like 「will follow up later」 / 「之後再做」 / 「deferred to next sprint」 — but if the mention isn't linked to an actual issue, it vanishes into the closing comment never to be tracked. By scan time, the user has just typed the summary, the matched phrase fresh in context — best moment to prompt.

**Rule (SHOULD, advisory)**: 在 `gh issue close` 前 (Step 4)，scan 已 drafted closing comment for trigger phrases (per canonical reference doc). 命中且 paragraph 沒 cross-link 到既有 issue → AskUserQuestion 3-option。**Non-blocking** — user 可選 skip 直接 close (per canonical eligibility criteria: closure tier is SHOULD not SHALL)。

**Trigger phrase regex** (per canonical reference doc §2):

```
follow-up | follow up | deferred | future | TODO | later |
之後 | 未來 | 待 | 待 follow | 順便 | 我之前觀察到 | 之後再 | 改天
```

**Cross-link detection logic** (decide whether matched paragraph already covered):

For each trigger-phrase match:
1. Read the paragraph (line containing match + adjacent lines if continuous)
2. Look for `#NNN` issue number reference within the paragraph
3. If found:
   - `gh issue view NNN --repo $GITHUB_REPO --json state,title -q .state` → if OPEN/CLOSED with relevant title, treat as covered
   - Stale link (404 or wrong title scope) → still treat as orphan mention, prompt user to file new
4. If no `#NNN` reference → orphan mention, surface as candidate

**Procedure**:

1. **Scan + classify**: AI surfaces orphan-mention list (per match: paragraph excerpt + suggested issue title):

   ```
   {N}. [paragraph: "{quoted excerpt}"] suggests: {1-line follow-up description}
        Trigger phrase: {matched phrase}
        Proposed type: bug / refactor / docs / test
        Proposed labels: confidence:confirmed, priority:P3
   ```

2. **AskUserQuestion** 3-option (per canonical reference doc §1, with closure-specific framing):
   - `file all` → loop `gh issue create` per orphan mention; replace each mention in closing summary with `(see #NEW)` cross-link
   - `file selected` → numbered checklist for cherry-pick
   - `skip` → keep closing summary as-is, but append audit-trail line documenting the choice

3. **File issues** (if `file all` or `file selected`):

   ```bash
   for item in $selected_items; do
     gh issue create --repo "$GITHUB_REPO" \
       --title "[$type] $description (closing follow-up from #$NNN)" \
       --body "$BODY_WITH_SOURCE_LINK" \
       --label "$type,confidence:confirmed,priority:P3"
   done
   ```

   Body MUST contain `**Source**: surfaced during /idd-close #$NNN closing summary scan (Step 3.5)` for traceability.

4. **Update closing summary** (Step 2 已 drafted but not yet posted, since Step 3.5 runs **before** Step 4):
   - Inline replacement: `「will follow up X later」` → `「will follow up X later (see #NEW)」`
   - Append `### Closing Follow-ups Filed (v2.45.0+ #527)` audit-trail section per canonical heading conventions table:
     - "file all/selected" → `Filed: #NNN, #MMM, #PPP`
     - "skip" → `Skipped per user choice (kept inline mentions without cross-links: brief list)`
     - empty surface list → `(none — no orphan mentions in closing summary)`
     - `AI_LOW_BAR_ISSUE_FILING=false` env var → `skipped (AI_LOW_BAR_ISSUE_FILING=false, per IC_R011 rollback)`

**Why advisory not blocking**: per canonical reference doc §6 — closure is mostly mechanical action with text artifact. Hard-blocking on every "future" keyword would 友 friction. Empty-list and skip-with-reason are both legitimate outcomes;the value is making the orphan-mention pattern visible at the moment of decision, not enforcing filing.

**Rollback escape hatch**: per canonical reference doc §5 — `AI_LOW_BAR_ISSUE_FILING=false` env var or `# Disable IC_R011` flag in repo CLAUDE.md silently skips checkpoint while preserving audit trail.

> **Disambiguation from #515 supersession**: Step 0 supersession (#515 v2.41.0) is **gate logic** preventing false-positive checklist refusals — it operates on pre-implementation Strategy/Plan checkboxes. Step 3.5 (this step, #527) is the **IC_R011 checkpoint** for orphan keyword mentions in the drafted closing summary. The two are orthogonal: Step 0 runs at gate time, Step 3.5 runs after summary draft + before final close.

### Step 4: 發佈並關閉

```bash
gh issue comment $NUMBER --repo $GITHUB_REPO --body "$CLOSING_COMMENT"
gh issue close $NUMBER --repo $GITHUB_REPO
```

> **數學公式格式**：GitHub 支援 `$...$`（inline）和 `$$...$$`（display）。含底線的程式變數名**不放 math mode**，改用 backtick code。

### Step 4.5: Finalize routing outcome (v2.38.0+, optional)

If `idd-route` is installed, append a final outcome record (corresponds to the `in_review` record `idd-verify` Step 5d wrote earlier). Powers data-driven recommendation in future `idd-diagnose` calls. **Skip silently if binary missing.**

> **NOTE**: `update-outcome` ships in `idd-route-swift` v0.3.0 (P2 of plan). Until then, this Step gracefully no-ops on `command not found`.

```bash
if command -v idd-route &>/dev/null; then
  REPO_PATH=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  STATS="$REPO_PATH/.claude/.idd/routing-stats.jsonl"

  # Determine outcome:
  #   - PR was merged → merged
  #   - Issue closed without merge (wontfix, abandoned) → abandoned
  if [[ -n "$PR_NUMBER" ]] && \
     gh pr view "$PR_NUMBER" --repo "$GITHUB_REPO" --json merged -q .merged 2>/dev/null | grep -q true; then
    OUTCOME="merged"
  else
    OUTCOME="abandoned"
  fi

  idd-route update-outcome \
    --stats-file "$STATS" \
    --issue "$NUMBER" --issue-repo "$GITHUB_REPO" \
    --outcome "$OUTCOME" \
    2>/dev/null || echo "idd-route update-outcome failed or unavailable (non-fatal)" >&2
fi
```

Append-only — original `in_review` record from `idd-verify` Step 5d stays for audit trail.

Full integration contract: [`references/agent-routing.md`](../../references/agent-routing.md).

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
