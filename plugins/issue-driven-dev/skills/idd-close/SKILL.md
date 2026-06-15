---
name: idd-close
description: |
  寫 closing comment 並關閉 GitHub Issue。
  強制記錄做了什麼、怎麼驗證的。
  支援 cluster close（v2.34.0+）：多個 #N（如 `#34 #36 #38`）共用 PR 的 cluster 一次關閉，**每個 issue 各寫獨立 closing summary**（不偷懶合併）。
  Use when: verify 通過後、commit 之後。
  防止的失敗：修完了但三個月後沒人知道當時做了什麼。
argument-hint: "#issue [#issue ...] e.g. '#42' or '#34 #36 #38' (cluster close after merge) | --retroactive [--via <channel>] (remediate an already-closed issue that has no Closing Summary)"
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

## Retroactive remediation mode（`--retroactive`, v2.76.0+, #176）

`idd-close --retroactive #N` 修補一個**已經被 auto-close、但沒有 `## Closing Summary`** 的 issue —— 也就是被 commit / PR-body 的 close keyword 繞過 `/idd-close` gate 關掉的受害者（`/idd-list --audit-closes` / `scripts/check-closed-without-summary.sh` 抓出來的那些）。它把「人工 reconstruct + 手貼 retroactive summary」這個**已文檔化的補救程序**（見 `CLAUDE.md` → Commit Conventions →「補救：commit 已 push 且 trailer 已觸發 auto-close」）自動化。

> **`--retroactive` 不是 `--force`。** `--force`（本 skill **不給**）是繞過 OPEN issue 的 gate —— 危險。`--retroactive` 處理的 issue **已經 CLOSED**：gate 本來就 moot（沒東西可繞）、也不會 re-close。它只補回缺失的 audit trail。

本質上 retroactive mode = **正常 `/idd-close` 減掉 gate、減掉真正的 `gh issue close`**，reuse 既有 Step 2（draft）/ Step 4（publish）/ Step 6（body sync）machinery：

| 正常 `/idd-close` step | `--retroactive` 行為 |
|------------------------|----------------------|
| Step 0 / 1.5 / 1.6 gates | **跳過**（issue 已關，gate moot；非 force bypass）|
| **Precondition**（retroactive 專屬）| `state == CLOSED` **且**無**以 `## Closing Summary` 開頭**的 comment（**startswith prefix-match**，同 #151 偵測契約 —— **不是** exact-match，否則 `## Closing Summary (retroactive — …)` 會被誤判成「沒有」而 double-post）。OPEN → abort（「不是 retroactive case，跑正常 `/idd-close`」）；已有 Closing Summary → abort（「已 remediate 過」）。**post 前用同一個 startswith 再 check 一次**（防 stale list / race / double-post）。|
| Step 2 draft | **reuse，但 `### Verification` section 特別處理** —— 從 `git log --grep "#N"`（Changes）+ 該 issue 既有的 `## Diagnosis` / `## Implementation Complete` / `## Verify` comments + body reconstruct 五段式。**標題改成** `## Closing Summary (retroactive — auto-closed via <channel>)`。reconstruct 不足 → 標 **「best-effort reconstruction」**，不假裝完整。**`### Verification` 的捏造風險最高 —— 見下方「Verification honesty 鐵律」。** |
| Step 3 confirm | **semi-auto（預設）** —— 把 draft 給 user 確認再 post（reconstruct 可能錯，且 issue 已關不急）。confirm 是必要的、但**不是** verification —— cold-read + batch 容易 rubber-stamp，所以下方鐵律把誠實寫死進 draft，不靠 confirm 兜底。|
| Step 4 publish + close | **publish comment，但跳過 `gh issue close`**（已關）。|
| Step 4.5 idd-route outcome | **跳過** —— issue 是（可能幾週前）關的，現在補寫 `merged` / `abandoned` routing-stats record 會是錯的時間點 + 錯的因果歸因。|
| Step 6 body sync | **reuse** —— body Current Status phase → `closed`（若還停在舊值）。|
| Step 6.5 distribution sync | **跳過** —— 把它 auto-close 的那個 merge 早就 ship 了，distribution 不是 retroactive 的事。|
| Step 6.7 worktree GC | **跳過**。|

`<channel>` 來源：optional `--via <channel>` flag（例 `--via commit-body` / `--via pr-body`）；不給就用 generic `auto-close trap, /idd-close gate bypassed`。**不**做 GitHub timeline API 的精確 channel 偵測（重、out of scope）。

### Verification honesty 鐵律（#176 verify DA-1）

`### Verification` 是 retroactive summary 裡**最容易捏造**的一段，而這個 feature 的全部價值就是 audit-trail **誠實**，所以這條是鐵律不是建議：

- **modal victim（direct-commit `Closes #N` trap）沒有 PR、沒跑過 `idd-verify`、沒有任何 verify artifact。** 平時 fact-check「打勾的事真做了」的 `idd-close` Step 1.6 semantic gate 在 retroactive 被 skip 了 —— 也就是說，**沒有任何機制會擋住一份捏造的 Verification**。
- reconstruct `### Verification` 時**只能引用真實存在的 verify 證據**：issue 既有的 `## Verify` comment / linked PR 的 verify report / 真的有的 test commit（`git log --grep "#N"` 裡確實改了 test 檔）。
- **完全沒有 verify 證據** → Verification section **必須**原文寫：`(no verification ran before the auto-close — this comment is a retroactive audit-trail repair, NOT a post-hoc verification claim)`。**嚴禁**生出任何「測試通過 / verify PASS」之類的句子。
- **`best-effort reconstruction` 標記的觸發軸 = 「缺 verify 證據 / 缺 diagnosis」，不是 comment 數量** —— 一個 body 很長但零 verify 證據的 victim 一樣要標 best-effort + 上面那句誠實聲明。
- **Floor case**（`git log` + comments + body 幾乎全空，例如純 GitHub-UI close 的 legacy issue）：仍可從 issue title + 任一 commit 拼一份最小 summary，整份標 best-effort + 誠實聲明 —— 「至少留一句 retroactive 紀錄」勝過無 summary，但**不得假裝有內容**。

**Batch**：`idd-close --retroactive #34 #36 #38` —— 每個 issue 各自 draft + confirm + post 獨立 retroactive summary（同 cluster-close 紀律，不合併）。

**Idempotency**：`--audit-closes` 偵測本來就排除「已有 `## Closing Summary`」的 issue（含 retroactive heading，因 `startswith` 也 match），所以 remediate 過的 issue 不會被重新 surface；precondition 的 post-前再 check 是第二層保險。

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

**Authoritative source resolution (v2.73.0+, #150 — generalizes v2.41.0 #515 supersession bridge across all 4 gate sites)**：

> **Note**: this is a **gate logic** pattern (resolve canonical source per `authoritative_source` priority order), NOT an IC_R011 checkpoint. The IC_R011 checkpoint for `/idd-close` (closing summary follow-up keyword scan) is tracked separately in [#527](https://github.com/kiki830621/ai_martech_global_scripts/issues/527) and cites [`references/ic-r011-checkpoint.md`](../../references/ic-r011-checkpoint.md). This Step 0 logic implements the `authoritative_source` resolution pattern from `plugins/issue-driven-dev/rules/append-vs-modify.md`.

`Strategy` 跟 `Implementation Plan` 是 **pre-implementation snapshots**——它們在 `idd-diagnose` / `idd-plan` 階段寫進 issue,記錄當時的 design intent。`idd-implement` Step 5 「Checklist Sync」**只**回寫 `## Implementation Complete > ### Checklist`（自己發的 comment 內），**不會** PATCH `Strategy` / `Implementation Plan` comments 的 checkbox。

因此即使 work 真正完成,Strategy / Plan 的 `- [ ]` 仍停留在 pre-impl 狀態。 v2.41.0 (`#515`) 引入 supersession bridge 修正 idd-close;v2.73.0 generalize 為 4 個 gate 通用 pattern。

修法 — Gate logic SHALL resolve authoritative source by priority order:

```
authoritative_source = first_exists([
  "## Implementation Complete > ### Checklist",       # priority 1
  "## Current Status > ### Tasks",                    # priority 2
  "## Todo" | "## Tasks" | "## Checklist"             # priority 3 (top-level headings)
])
```

當 authoritative source 存在時,Strategy 跟 Implementation Plan 的 `- [ ]` 一律當 superseded snapshot(skip gate)。 當沒任何 authoritative source 存在時(legacy issue pattern 或 pre-implementation 狀態) → fall back legacy scan all sources(保留 backward compat)。

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
TaskCreate(name="merge_completeness_gate", description="Step 1.55 (v2.84.0+, #184): resolve issue branch via merged-PR headRefOid (SHA — survives GitHub branch-delete-on-merge) → local idd/<N>-* → VISIBLE skip note; bash scripts/check-merge-completeness.sh --branch <sha> --baseline origin/<default> (line-presence content-verify); rc=3 orphans → AskUserQuestion 3-option (close anyway / abort+land / mis-detection), warn-only; rc=4/no-branch print a note (never silent). Never hard-blocks.")
TaskCreate(name="semantic_gate_check", description="Step 1.6: 對每個 - [x] bullet 做 keyword extraction → 驗證對應 artifact 真存在/有 commit。Warn-only。")
TaskCreate(name="draft_closing_comment", description="起草 Problem / Root Cause / Solution / Verification / Changes 五段式")
TaskCreate(name="review_with_user", description="顯示 closing comment 給使用者確認(若已明確 /idd-close 可省略此步)")
TaskCreate(name="closing_followup_keyword_scan", description="Step 3.5: scan drafted closing summary for trigger phrases (follow-up / deferred / future / 之後 / 順便 etc); orphan mentions without #NNN cross-link → AskUserQuestion 3-option per canonical references/ic-r011-checkpoint.md; PATCH closing summary inline + add `### Closing Follow-ups Filed` audit trail (advisory, non-blocking, per IC_R011 #527)")
TaskCreate(name="residue_acknowledgement", description="Step 3.6 (v2.66.0+, #105): read latest ## Diagnosis ### Residue section; if non-empty (not `(none)`), AskUserQuestion 3-option (still residue / file follow-up / skip); silent skip when residue is `(none)` or section missing. Audit trail PATCH to closing summary. Non-blocking, IC_R011 rollback respected. Closes the F3 write-only loop from #103.")
TaskCreate(name="publish_and_close", description="gh issue comment + gh issue close")
TaskCreate(name="auto_update_body", description="跑 /idd-update #NNN 把 issue body 的 Current Status phase 改 closed（Step 6，常被漏）")
TaskCreate(name="distribution_sync_chain_detection", description="Step 6.5 (v2.56.0+, #45): infer_distribution_type detection per references/distribution-detection.md; if hit → AskUserQuestion 3-option (chain to plugin-update/mcp-deploy/cli-deploy / skip — manual later / not applicable); patch closing comment with ### Distribution Sync section. Silent skip for non-distribution repos. IDD_DISTRIBUTION_SYNC_PROMPT=false env var bypasses prompt entirely (still 1-line audit).")
TaskCreate(name="worktree_gc", description="Step 6.7 (v2.75.0+, #167): best-effort worktree GC — bash $CLAUDE_PLUGIN_ROOT/scripts/idd-worktree.sh cleanup <N>; absent helper or dirty-refuse (exit 5) → one-line warning + close still completes; never blocks close")
TaskCreate(name="release_tree_lock", description="Step 6.8 (v2.85.0+, #183): best-effort release of the shared working-tree lock from idd-implement Step 0.4 — bash $CLAUDE_PLUGIN_ROOT/scripts/idd-tree-lock.sh release --repo <cwd> --id <session>; holder-scoped + idempotent (no lock / not-holder / absent helper → silent no-op); stale lock otherwise auto-reclaimed by next acquire via PID liveness. Never blocks close")
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
- `2` — manifest 損毀/格式錯(0-byte / 非 JSON object / 缺 `files` array,#189)→ verify 無法判讀,**不可當成 exit 0「全在」放行**;引導使用者重跑 `download` 重建 manifest。修正前 #189 此情況會 false-PASS exit 0,讓 close gate 漏判

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

### Step 1.55: Merge-completeness Gate（warn-only，v2.84.0+，#184）

Step 1.5 只確認 PR **merged**——但 **merged ≠ branch 上所有 work 真的進了 main**。當 PR merge 的是 **partial** 版本（cluster branch 某些 commit 沒被帶進 merge、或 branch 分歧），feature branch 上的 fix commit 變成 **orphan**：issue 被當「完成」關掉，但 bug 還活在 main 上（real incident：ai_martech `#1066` crash fix 漏到 5 公司共用的 origin/main，沒人發現）。`git branch --merged` 抓不到（merge context sha 不同）、PR「merged」status 也抓不到（merge 的是 partial）。

本 gate 偵測「branch 上 content 沒進 baseline」的 commit，**warn**（不硬擋——因 squash-merge 會讓 patch-id 全變、有 false-positive）。

```bash
WORKDIR="${CWD:-$PWD}"   # idd-close has no --cwd parser; default to process cwd (align w/ Step 6.7)

# Defensive: $NUMBER must be a plain issue number before it enters gh/git.
if ! printf '%s' "$NUMBER" | grep -qE '^[0-9]+$'; then
  echo "note: Step 1.55 skipped — issue ref '$NUMBER' is not numeric"
else
  # 1. Resolve the issue's branch HEAD. PREFER the merged PR's headRefOid — a
  #    commit SHA that stays resolvable after GitHub auto-deletes the head branch
  #    on merge (a bare branch NAME does not; #184 DA-1). Fall back to a local
  #    idd/<N>-* branch ref.
  BRANCH_REF=$(gh pr list --repo "$GITHUB_REPO" --state merged \
      --search "in:body \"#${NUMBER}\"" --json headRefOid -q '.[0].headRefOid' 2>/dev/null)
  if [ -z "$BRANCH_REF" ]; then
      BRANCH_REF=$(git -C "$WORKDIR" branch --list "idd/${NUMBER}-*" --format='%(refname:short)' | head -1)
  fi

  if [ -z "$BRANCH_REF" ]; then
    # No merged PR + no local branch → most likely direct-commit path (no feature
    # branch ⇒ no orphan possible). Print a VISIBLE note — "skipped" must never be
    # confused with "ran clean" (#184 DA-1: the original silent skip hid the gap).
    echo "note: Step 1.55 skipped — no merged PR / feature branch for #$NUMBER (direct-commit path, no orphan possible)"
  else
    DEFAULT=$(gh repo view "$GITHUB_REPO" --json defaultBranchRef -q .defaultBranchRef.name)
    git -C "$WORKDIR" fetch -q origin -- "$DEFAULT" 2>/dev/null   # fresh baseline (-- guards $DEFAULT)
    OUT=$(bash "$CLAUDE_PLUGIN_ROOT/scripts/check-merge-completeness.sh" \
            --repo "$WORKDIR" --branch "$BRANCH_REF" --baseline "origin/$DEFAULT" 2>/dev/null)
    RC=$?
    case "$RC" in
      0) : ;;  # clean — all branch content is in origin/<default>
      3) echo "⚠️  Merge-completeness: commits on the issue branch did NOT land in origin/$DEFAULT:"
         echo "$OUT" | sed 's/^/    /'
         # → AskUserQuestion (see below)
         ;;
      4) echo "note: Step 1.55 skipped — branch SHA '$BRANCH_REF' unresolvable in $WORKDIR (could not verify; close continues)" ;;
      *) echo "note: merge-completeness gate errored (rc=$RC) — close continues" ;;
    esac
  fi
fi
```

**RC=3 → AskUserQuestion**（3 選項，warn-only，不阻擋）：

| 選項 | 行為 |
|------|------|
| **close anyway** | orphan 是 intentional / out-of-scope — 繼續 close，closing summary 加 `### Merge-completeness` 註記列出 orphan + 理由 |
| **abort + land orphans** | 暫停 close，印 `git cherry-pick <sha>`（到 `$DEFAULT`）的指令讓使用者把 orphan 補進 main，補完再 `/idd-close` |
| **mis-detection** | 判定為 false-positive（content-verify 沒抓到的 edge case），繼續 close，註記「judged false-positive」 |

> **為什麼 warn 而非 refuse（對比 Step 1.5 硬擋）**：Step 1.5 的「有 open PR」是明確事實；orphan 偵測是 **probabilistic**。squash-merge 讓 `git cherry` 把所有 commit 標 `+`，helper 改用 **line-presence content-verify**（檢查 candidate commit 的 added lines 是否已存在 baseline 對應檔案）過濾 squash false-positive —— 這比 cherry-pick 3-way 穩健（#184 DA-2：cherry-pick 在「同檔被多 commit 改 + squash」時 conflict 誤判，line-presence 不會）。但仍 best-effort：抓不到純刪除型 orphan、added line 可能巧合出現他處。硬 refuse 會卡合理的 squash-merged close。判定邏輯與 fixture 契約見 `scripts/check-merge-completeness.sh` + `scripts/tests/merge-completeness/test.sh`（6 fixtures：genuine-orphan / squash-content-present NOT flagged / same-file-squash NOT flagged (DA-2) / no-branch skip / partial-merge orphan / SHA-after-branch-deleted (DA-1)）。
>
> **Branch resolution 用 headRefOid 不用 branch name（#184 DA-1）**：`idd-close` 在 merge **之後**跑，此時 GitHub 預設已 auto-delete head branch、local branch 也常被 `git branch -d`、cross-clone closer 根本沒有它。所以 gate 必須用 merged PR 的 **headRefOid（commit SHA，object 持久）** 解析，而非易逝的 branch name —— 否則正是「partial-merge orphan」這個它要抓的場景會 silent skip。
>
> **Skip 一律 VISIBLE**：無 merged PR + 無 feature branch（direct-commit path，不可能 orphan）→ 印一行 note，**不留零 output**（DA-1：silent skip 與 "ran clean" 無法區分是原本的缺陷）。

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

### Step 3.5: Closing Summary Follow-up Keyword Scan

**Rule (SHOULD)**: closing-summary keyword scan SHOULD surface follow-up mentions and ask the user via legacy 3-option AskUserQuestion `[file all] / [file selected] / [skip]`.

**Per IC_R011 follow-up filing checkpoint** (see [`references/ic-r011-checkpoint.md`](../../references/ic-r011-checkpoint.md))。

**SHOULD-tier (not SHALL)**: Per canonical Section 6, closure is a wrap-up moment, NOT a deliberation moment. Default-flip from v2.72.0+ does NOT apply here.

**Trigger condition**: 在 `gh issue close` 前 (Step 4)，scan 已 drafted closing comment for trigger phrases per canonical Section 2 (`follow-up` / `follow up` / `deferred` / `future` / `TODO` / `later` / `之後` / `未來` / `待` / `待 follow` / `順便` / `我之前觀察到` / `之後再` / `改天`)。For each match, read the surrounding paragraph and look for `#NNN` cross-link — orphan mentions (no `#NNN`, or stale 404 link) surface as candidates.

**Behavior**: Use the **legacy 3-option ask** path per canonical Section 1.6 (NOT the file-by-default path of Section 1.1):

```
question: "Found N closing follow-up mention(s). File as follow-up issues?"
options:
  - label: "file all"
  - label: "file selected"
  - label: "skip"
```

**Per-step deviation**:
- Keyword scan on closing summary text (per existing trigger phrase heuristic above)
- Light-touch advisory — empty list legitimate, never blocks close
- Source link: closing summary comment URL
- When filing (file all / file selected), inline replace each mention in closing summary with `(see #NEW)` cross-link before publish (Step 3.5 runs **before** Step 4). `(category: inline-replace-before-publish)` per [`rules/append-vs-modify.md`](../../rules/append-vs-modify.md) — modify happens in draft phase before `gh issue comment` publishes; post-publish the closing summary falls under `append-only` discipline.
- Audit block PATCH `### Closing Follow-ups Filed` to the Closing Summary comment after publish — `(category: audit-block-append, scope: "### Closing Follow-ups Filed")`. Adds new audit block without modifying existing summary text.
- Issue body MUST contain `**Source**: surfaced during /idd-close #$NNN closing summary scan (Step 3.5)` per canonical Section 7

**Audit trail target**: `### Closing Follow-ups Filed (v2.45.0+ #527)` in Closing Summary comment

**Default behavior**: Per canonical Section 1.6 (legacy 3-option ask) — NOT default file.

> **Disambiguation from #515 supersession**: Step 0 supersession (#515 v2.41.0) is **gate logic** preventing false-positive checklist refusals — it operates on pre-implementation Strategy/Plan checkboxes. Step 3.5 (this step, #527) is the **IC_R011 checkpoint** for orphan keyword mentions in the drafted closing summary. The two are orthogonal: Step 0 runs at gate time, Step 3.5 runs after summary draft + before final close.

### Step 3.6: Residue Acknowledgement (v2.66.0+, #105)

**Compliance**: this step closes the F3 `### Residue` write-only loop introduced in #103 v2.64.0. Producer was `idd-diagnose` Step 3 template + `>` explanatory paragraph; consumer was never implemented. Per Devil's Advocate D2 in PR #104 verify: "latent capacity for the section to drift into ritual filler with no consumer pressure to keep it honest". Step 3.6 gives Residue its first downstream consumer — the user is asked at close time "what happened to the residue declared at diagnose time?".

**Rule (SHOULD, advisory)**: 在 `gh issue close` 前 (Step 4)，read the **latest** `## Diagnosis` comment's `### Residue` section. If non-empty (not `(none)` and not missing), AskUserQuestion 3-option per IC_R011 canonical pattern. **Non-blocking** — user can pick skip with audit trail. Silent skip when residue is `(none)` (the common case for clear-scope issues).

#### Detection (bash)

```bash
# Pull the latest ## Diagnosis comment body (newest by createdAt desc, mirrors Step 0 supersession discipline)
DIAG_BODY=$(gh issue view "$NUMBER" --repo "$GITHUB_REPO" --json comments \
  --jq '[.comments[] | select(.body | startswith("## Diagnosis"))] | sort_by(.createdAt) | reverse | .[0].body // ""')

# Extract the ### Residue section content — between the heading and either the next ###/## or EOF
RESIDUE_CONTENT=$(printf '%s\n' "$DIAG_BODY" \
  | awk '/^### Residue/{flag=1; next} flag && /^###? /{flag=0} flag' \
  | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//' \
  | awk 'NF' \
  | head -c 4000)

# Trigger logic — silent skip when:
#   - No Diagnosis comment exists at all (legacy issue pattern, pre-v2.64.0)
#   - ### Residue section missing (pre-v2.64.0 Diagnosis template)
#   - Content is exactly `(none)` (the explicit empty-state marker required by template)
RESIDUE_TRIGGER="false"
if [ -z "$DIAG_BODY" ]; then
  AUDIT_REASON="no Diagnosis comment (legacy issue or pre-v2.64.0 — no Residue section to acknowledge)"
elif ! printf '%s' "$DIAG_BODY" | grep -q '^### Residue'; then
  AUDIT_REASON="Diagnosis has no \`### Residue\` section (pre-v2.64.0 format)"
elif [ "$RESIDUE_CONTENT" = "(none)" ] || [ -z "$RESIDUE_CONTENT" ]; then
  AUDIT_REASON="residue declared as \`(none)\` at diagnose time — no acknowledgement needed"
else
  RESIDUE_TRIGGER="true"
fi
```

#### AskUserQuestion 3-option (prose — NOT a bash function call)

When `RESIDUE_TRIGGER == "true"`, AskUserQuestion per IC_R011 canonical pattern. Surface the captured `$RESIDUE_CONTENT` so the user sees the exact text being acknowledged:

> "Residue declared at diagnose time:
> > <quoted RESIDUE_CONTENT>
>
> 該 residue 在 #${NUMBER} 完成期間有變動嗎?"
>
> Options (default = first):
> - **`still residue — acknowledge as-is`** — record acknowledgement in closing summary that residue stayed as residue. No new issue. Audit trail: `Acknowledged as still residue (text quoted in audit block).`
> - **`file as follow-up issue(s)`** — surface candidate decompositions if residue has multiple distinct items; user picks which to file. Each filed issue gets `**Source**: residue from #${NUMBER} at /idd-close time` for traceability.
> - **`skip — record in audit trail only`** — no new issue, no acknowledgement; just log the user's choice. Audit trail: `Skipped per user choice (residue not addressed).`

#### File issues (if user picks `file`)

```bash
# Loop per-item: if residue has multiple distinct items (decided via inline AskUserQuestion for picker)
for item in $selected_items; do
  NEW_ISSUE_URL=$(gh issue create --repo "$GITHUB_REPO" \
    --title "[<type>] <description> (residue from #${NUMBER})" \
    --body "$BODY_WITH_RESIDUE_QUOTE_AND_SOURCE_LINK" \
    --label "<type>,confidence:confirmed,priority:P3")

  # Chain context manifest write (per spawn-manifest contract, v2.55+ #44; v2.60+ #46 schema v2)
  ROOT_ID_FOR_MANIFEST="${IDD_CHAIN_CURRENT_ROOT_ID:-${NUMBER:-}}"
  if [ -n "$ROOT_ID_FOR_MANIFEST" ]; then
    NEW_ISSUE=$(basename "$NEW_ISSUE_URL")
    bash "$CLAUDE_PLUGIN_ROOT/scripts/manifest-append.sh" \
      "$REPO_ROOT" "$NEW_ISSUE" "idd-close" "Step 3.6 residue acknowledgement" \
      "residue-followup" "$item_same_file" "$item_same_skill" "$item_title" "$ROOT_ID_FOR_MANIFEST" \
      2>/dev/null || true   # silent skip when chain context inactive
  fi
done
```

Body MUST contain `**Source**: residue from #${NUMBER} at /idd-close time (Step 3.6)` for traceability. Manifest write is **additive** — when chain context inactive, helper exits 0 silently. See `references/spawn-manifest.md`.

#### Audit trail PATCH

The closing summary (Step 2 已 drafted but not yet posted, same pattern as Step 3.5) gets a `### Residue Acknowledgement` section appended per canonical heading conventions:

| User choice | Audit block content |
|---|---|
| `still residue — acknowledge as-is` | `**Acknowledged as still residue**: <RESIDUE_CONTENT quoted>` |
| `file as follow-up issue(s)` (1+ filed) | `**Filed**: #X, #Y, #Z` |
| `skip — record in audit trail only` | `**Skipped per user choice** (residue text quoted for posterity): <RESIDUE_CONTENT quoted>` |
| silent skip (triggered=false) | `**$AUDIT_REASON**` (one line, no separate block) |
| `AI_LOW_BAR_ISSUE_FILING=false` env var | `**Skipped** (AI_LOW_BAR_ISSUE_FILING=false, per IC_R011 rollback)` |

**Rollback escape hatch**: per canonical reference doc §5 — `AI_LOW_BAR_ISSUE_FILING=false` env var silently skips Step 3.6 while preserving the audit trail line.

**Why advisory not blocking**: same reasoning as Step 3.5 — closure is mostly mechanical action; hard-blocking on every residue declaration would multiply close-time friction. The value is making "residue is real, what happened to it?" a visible deliberation moment, not enforcing a particular answer. Silent skip when `(none)` keeps clear-scope issues frictionless.

**Why placed here (between Step 3.5 keyword scan and Step 4 publish+close)**: Step 3.5 already established the "scan drafted closing summary + AskUserQuestion before publish" pattern. Step 3.6 mirrors it — same drafting/scan/PATCH flow, different source (Residue section vs orphan keyword mentions). Both must run **before** Step 4 so the audit trail PATCH happens to the same in-memory draft, not a post-hoc edit.

**Why use only the latest Diagnosis comment** (mirrors Step 0 supersession): re-diagnoses after clarification produce multiple `## Diagnosis` comments — only the latest reflects the issue's current state. Earlier drafts' residue is part of the issue's deliberation history, not its current acceptance contract. If user wants to surface older residue, they can manually file follow-up from comment history.

### Step 4: 發佈並關閉

```bash
# Capture the comment URL → ID for downstream PATCH (Step 6.5 Distribution Sync audit trail).
# IMPORTANT: don't use `2>&1 | tail -1` — that mixes stderr into stdout, and gh's
# deprecation/warning messages can interleave with the URL, leading to a garbage ID.
# `gh issue comment` prints ONLY the comment URL to stdout on success;errors go to stderr.
# `set -e` (or explicit `|| abort`) guarantees we don't proceed with empty URL on failure.
CLOSING_COMMENT_URL=$(gh issue comment $NUMBER --repo $GITHUB_REPO --body "$CLOSING_COMMENT") || {
  echo "ERROR: gh issue comment failed for #$NUMBER" >&2
  exit 1
}

# `sed -n '...p'` only prints the line if the regex matched, so a malformed URL
# yields an empty CLOSING_COMMENT_ID rather than the unmodified input string.
CLOSING_COMMENT_ID=$(printf '%s' "$CLOSING_COMMENT_URL" | sed -nE 's|.*#issuecomment-([0-9]+).*|\1|p')
if [ -z "$CLOSING_COMMENT_ID" ]; then
  echo "ERROR: failed to extract comment ID from URL: $CLOSING_COMMENT_URL" >&2
  exit 1
fi

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

### Step 6.5: Distribution Sync chain (v2.56.0+, #45)

**Compliance**: this step implements close-tier distribution-sync checkpoint per IC_R011-style 3-option AskUserQuestion + audit trail pattern (canonical reference: [`references/ic-r011-checkpoint.md`](../../references/ic-r011-checkpoint.md)). Complements `che-claude-config/rules/common-release-flow.md` (release-tier trigger).

**Why this step**: for plugin/MCP/CLI repos, fix lands in main but user-facing distribution channel (marketplace.json / binary release) needs separate sync. Without Step 6.5 mechanical checkpoint, "marketplace.json sync" relies on user memory → 「修了卻沒修」 anti-pattern (e.g. `che-apple-mail-mcp#72` PR #75 merged but marketplace.json not bumped → users `/plugin update` got old binary).

**Rule**: Step 6 (auto-update phase=closed) completes → Step 6.5 runs detection. If detection returns `n/a` → silent skip + 1-line audit (`(detection: not a distribution repo)`). Otherwise AskUserQuestion 3-option per IC_R011 canonical pattern.

**Placement rationale**: phase=closed locks audit at Step 6 (lifecycle gate complete);Step 6.5 is follow-up action not lifecycle gate. The closing comment's `### Distribution Sync` section heading clearly separates from main summary so audit trail timeline is unambiguous.

#### Detection (bash) — define helpers inline, then call

Per [`references/distribution-detection.md`](../../references/distribution-detection.md) canonical contract. **Helpers MUST be defined before first call** — the silent-skip path below references them, so define-then-call ordering matters (bash treats undefined function calls as `command not found` exit 127).

```bash
# ── Step 6.5 prelude: resolve REPO_ROOT (must be non-empty before helpers fire) ──
# Earlier steps don't define REPO_ROOT. Detection helpers depend on absolute path
# resolution + walk-up — empty input causes infinite loops in `dirname` and false
# positives via `cd "" && pwd`. Resolve from git first;fallback to PWD.
REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
if [ -z "$REPO_ROOT" ] || [ ! -d "$REPO_ROOT" ]; then
  echo "WARN: cannot resolve REPO_ROOT — Step 6.5 silent-skip" >&2
  AUDIT_LINE="

### Distribution Sync

- **Detected**: skipped (REPO_ROOT not resolvable — likely not in git work tree)
- **At**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
"
  # Note: patch_closing_comment_append requires CLOSING_COMMENT_ID to be set;
  # if it's also empty, the helper warns and returns without aborting close.
  # Agent: skip remaining Step 6.5 logic, advance to Step 7 in skill order.
fi

# ── Helpers (inlined from references/distribution-detection.md) ──

# patch_closing_comment_append — appends a markdown block to the closing comment
# captured in Step 4 ($CLOSING_COMMENT_ID). All silent-skip and prompt-resolution
# paths in this step call this helper, so define it FIRST.
patch_closing_comment_append() {
  local append_block="$1"
  local existing
  existing=$(gh api "/repos/${GITHUB_REPO}/issues/comments/${CLOSING_COMMENT_ID}" -q .body 2>/dev/null) || {
    echo "WARN: gh api fetch failed for comment $CLOSING_COMMENT_ID — audit trail PATCH skipped" >&2
    return 0
  }
  jq -n --arg b "${existing}${append_block}" '{body: $b}' > /tmp/distribution_sync_patch.json
  gh api -X PATCH "/repos/${GITHUB_REPO}/issues/comments/${CLOSING_COMMENT_ID}" \
    --input /tmp/distribution_sync_patch.json -q '.html_url' >/dev/null || \
    echo "WARN: gh api PATCH failed — audit trail incomplete" >&2
}

# resolve_plugin_name — emit matched plugin's `name` field from marketplace entry
# (called AFTER is_plugin_marketplace_member returned true; required for SKILL_NAME
# composition `/plugin-tools:plugin-update <plugin-name>`)
resolve_plugin_name() {
  local repo_root="$1"
  local resolved_root
  resolved_root=$(cd "$repo_root" 2>/dev/null && pwd -P) || resolved_root="$repo_root"
  local current="$resolved_root"
  while :; do
    local manifest="$current/.claude-plugin/marketplace.json"
    if [ -f "$manifest" ]; then
      local manifest_dir
      manifest_dir=$(cd "$(dirname "$manifest")/.." 2>/dev/null && pwd -P) || \
        manifest_dir=$(dirname "$(dirname "$manifest")")
      local name_match
      name_match=$(jq -r '.plugins[]? | select(.source | type == "string") | "\(.name)\t\(.source)"' \
        "$manifest" 2>/dev/null \
        | while IFS=$'\t' read -r pname psrc; do
            [ -z "$pname" ] && continue
            local plugin_dir
            plugin_dir=$(cd "$manifest_dir/$psrc" 2>/dev/null && pwd -P) || continue
            case "$plugin_dir/" in
              "$resolved_root/"|"$resolved_root/"*) echo "$pname"; break ;;
            esac
          done | head -1)
      [ -n "$name_match" ] && { echo "$name_match"; return 0; }
    fi
    [ "$current" = "$HOME" ] && break
    [ "$current" = "/" ] && break
    current=$(dirname "$current")
  done
  echo ""
}

# is_plugin_marketplace_member — walk-up scan for marketplace.json listing this repo
is_plugin_marketplace_member() {
  local repo_root="$1"
  local resolved_root
  resolved_root=$(cd "$repo_root" 2>/dev/null && pwd -P) || resolved_root="$repo_root"
  local current="$resolved_root"
  while :; do
    local manifest="$current/.claude-plugin/marketplace.json"
    if [ -f "$manifest" ]; then
      local manifest_dir
      manifest_dir=$(cd "$(dirname "$manifest")/.." 2>/dev/null && pwd -P) || \
        manifest_dir=$(dirname "$(dirname "$manifest")")
      local match
      match=$(jq -r '.plugins[]?.source // empty | select(type == "string")' \
        "$manifest" 2>/dev/null \
        | while IFS= read -r src; do
            [ -z "$src" ] && continue
            local plugin_dir
            plugin_dir=$(cd "$manifest_dir/$src" 2>/dev/null && pwd -P) || continue
            case "$plugin_dir/" in
              "$resolved_root/"|"$resolved_root/"*) echo "match"; break ;;
            esac
          done | head -1)
      [ -n "$match" ] && { echo "true"; return 0; }
    fi
    [ "$current" = "$HOME" ] && break
    [ "$current" = "/" ] && break
    current=$(dirname "$current")
  done
  echo "false"
}

# has_binary_wrapper — scan bin/*.sh for GitHub release patterns (line-agnostic)
has_binary_wrapper() {
  local repo_root="$1"
  local bin_dir="$repo_root/bin"
  [ -d "$bin_dir" ] || { echo "false"; return; }
  local pattern='gh release download|gh api[[:space:]]+.*/releases|api\.github\.com/.*/releases|github\.com/.*/releases/(download|tags|latest)'
  local match=""
  shopt -s nullglob 2>/dev/null
  for f in "$bin_dir"/*.sh; do
    [ -f "$f" ] || continue
    if grep -qE "$pattern" "$f" 2>/dev/null; then match="$f"; break; fi
  done
  shopt -u nullglob 2>/dev/null
  [ -n "$match" ] && echo "true" || echo "false"
}

# infer_distribution_type — orchestrator returning plugin/mcp/cli/plugin+mcp/plugin+cli/n/a
infer_distribution_type() {
  local repo_root="$1"
  local is_plugin=$(is_plugin_marketplace_member "$repo_root")
  local has_wrapper=$(has_binary_wrapper "$repo_root")
  local binary_kind=""
  if [ "$has_wrapper" = "true" ]; then
    local mcp_match=$(ls "$repo_root/bin"/*.sh 2>/dev/null \
      | grep -E '(-mcp-wrapper\.sh$|/[^/]*mcp[^/]*\.sh$)' | head -1)
    [ -n "$mcp_match" ] && binary_kind="mcp" || binary_kind="cli"
  fi
  if [ "$is_plugin" = "true" ] && [ -n "$binary_kind" ]; then
    echo "plugin+$binary_kind"
  elif [ "$is_plugin" = "true" ]; then echo "plugin"
  elif [ -n "$binary_kind" ]; then echo "$binary_kind"
  else echo "n/a"; fi
}

# ── Detection invocation ──
DISTRIBUTION_TYPE=$(infer_distribution_type "$REPO_ROOT")
# Returns: plugin / mcp / cli / plugin+mcp / plugin+cli / n/a

# Resolve plugin name when applicable (required for plugin-update <name> chain).
# Empty string for pure mcp/cli/n/a — caller branches handle empty case.
PLUGIN_NAME=""
case "$DISTRIBUTION_TYPE" in
  plugin|plugin+*)
    PLUGIN_NAME=$(resolve_plugin_name "$REPO_ROOT")
    if [ -z "$PLUGIN_NAME" ]; then
      # Detection said plugin but name resolution failed — schema ambiguity.
      # Demote to n/a (with audit) so we don't fire AskUserQuestion with
      # malformed chain command.
      echo "WARN: distribution type=$DISTRIBUTION_TYPE but plugin name unresolvable — demoting to n/a" >&2
      DISTRIBUTION_TYPE="n/a"
    fi
    ;;
esac

# Silent skip: non-distribution repo
if [ "$DISTRIBUTION_TYPE" = "n/a" ]; then
  AUDIT_LINE="

### Distribution Sync

- **Detected**: not a distribution repo (skipped)
- **At**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
"
  patch_closing_comment_append "$AUDIT_LINE"
  # Silent skip — proceed to Step 7 (do NOT use `exit 0` here; in markdown-skill
  # context that would terminate the entire close flow including Step 7 batch
  # close special rules. Instead, the agent reading this skill branches at
  # agent level: `n/a` path is complete, advance to Step 7 in skill order.)
fi

# Silent skip: env var rollback (overrides prompt for distribution-detected repos)
if [ "$DISTRIBUTION_TYPE" != "n/a" ] && [ "$IDD_DISTRIBUTION_SYNC_PROMPT" = "false" ]; then
  AUDIT_LINE="

### Distribution Sync

- **Detected**: $DISTRIBUTION_TYPE
- **Choice**: prompt skipped (IDD_DISTRIBUTION_SYNC_PROMPT=false, per IC_R011-style rollback)
- **At**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
"
  patch_closing_comment_append "$AUDIT_LINE"
  # Same agent-level advance: skip prompt, proceed to Step 7.
fi
```

If detection returned a real type AND env var didn't suppress → enter the AskUserQuestion deliberation moment described below.

#### AskUserQuestion 3-option (prose — NOT a bash function call)

> **Why prose**: AskUserQuestion is a Claude Code agent-level tool, not a bash function. Embedding `AskUserQuestion(...)` inside fenced bash was a category error caught in #47 P1 finding 2 (idd-all-chain Step 0.4). Same pattern applies here — agent reads bash detection, branches at agent level on `DISTRIBUTION_TYPE != "n/a"`, then handles deliberation as prose.

When `DISTRIBUTION_TYPE` is plugin/MCP/CLI/mixed, the agent **first** composes the chain command from the resolution table below using `$DISTRIBUTION_TYPE` and `$PLUGIN_NAME` (set in Detection invocation), then invokes **AskUserQuestion** per IC_R011 canonical 3-option pattern:

```bash
# Compose chain command(s) — referenced as $CHAIN_DESC in AskUserQuestion below.
# For mixed types, this is two skills with explicit ordering (D3 v1).
case "$DISTRIBUTION_TYPE" in
  plugin)       CHAIN_DESC="/plugin-tools:plugin-update ${PLUGIN_NAME}" ;;
  mcp)          CHAIN_DESC="/mcp-tools:mcp-deploy" ;;
  cli)          CHAIN_DESC="/cli-tools:cli-deploy" ;;
  plugin+mcp)   CHAIN_DESC="/mcp-tools:mcp-deploy → /plugin-tools:plugin-update ${PLUGIN_NAME}" ;;
  plugin+cli)   CHAIN_DESC="/cli-tools:cli-deploy → /plugin-tools:plugin-update ${PLUGIN_NAME}" ;;
esac
```

Then AskUserQuestion:

> "Issue #${NUMBER} closed. Detected distribution type: **${DISTRIBUTION_TYPE}**. Sync to user-facing channel?"
>
> Options (default = first):
> - **`chain to ${CHAIN_DESC} now`** — invoke the resolved skill(s) at agent level (Skill tool, NOT bash);outcome recorded in audit trail
> - **`skip — I'll sync manually later`** — record `### Distribution Sync Pending` audit + provide manual command;close completes
> - **`not applicable — this issue doesn't ship`** — record `### Distribution Sync — Not Applicable`;e.g. test infra fix, internal refactor, docs-only change that doesn't reach user

#### D3 Skill resolution table (v1: explicit ordering, fallback-safe)

Per #45 Plan tier D3 + #66 audit dependency: until `plugin-update` Phase 1.5 cascade is empirically confirmed (see #66), v1 chains BOTH skills explicitly for mixed types — binary-deploy first, then plugin-update.

| `DISTRIBUTION_TYPE` | Sync skill(s) to invoke (in order) |
|---------------------|-----------------------------------|
| `plugin` | `/plugin-tools:plugin-update <plugin-name>` |
| `mcp` | `/mcp-tools:mcp-deploy` |
| `cli` | `/cli-tools:cli-deploy` |
| `plugin+mcp` | `/mcp-tools:mcp-deploy` → then `/plugin-tools:plugin-update <plugin-name>` |
| `plugin+cli` | `/cli-tools:cli-deploy` → then `/plugin-tools:plugin-update <plugin-name>` |

**Plugin name resolution**: `<plugin-name>` is the `name` field of the matched `marketplace.json` `plugins[]` entry (algorithm in `references/distribution-detection.md`).

**Why ordering matters for mixed types**: bumping the binary first means `plugin-update`'s Phase 1.5 dependency check (if cascade exists) sees the already-bumped binary and skips its own cascade prompt — idempotent. If `plugin-update` doesn't cascade (per #66 audit risk), explicit ordering ensures both shells are still in sync. Either way safer than relying on superset behavior unverified.

**v1 caller-flag note**: Step 6.5 v1 invokes target skill **without** `--source-issue` flag (caller skills in `psychquant-claude-plugins` repo don't yet support it — sister issue tracks). Graceful: target skills ignore unknown flags. Audit trail still complete via closing comment patch.

#### Audit trail PATCH (any choice)

Regardless of user's choice, PATCH the closing comment (captured in Step 4 as `$CLOSING_COMMENT_ID`) to append `### Distribution Sync` section. The `patch_closing_comment_append` helper was defined inline at the top of this Step 6.5 detection block (above) — reuse it here.

```bash
# Build outcome line per choice. Match against the AskUserQuestion option labels
# emitted in the prose section above (substring match on the leading verb works
# because options have distinct first words: "chain", "skip", "not applicable").
case "$USER_CHOICE" in
  "chain to "*)
    # Invoke target skill(s) via Skill(...) tool at agent level (NOT inside this
    # bash block — the Skill tool is a Claude Code agent-level tool). Per D3
    # mixed-type ordering: for plugin+mcp/plugin+cli, invoke binary-deploy
    # first, then plugin-update. Capture outcome summary from each invocation.
    OUTCOME="invoked \`${CHAIN_DESC}\`, see chained skill output above"
    ;;
  "skip"*)
    OUTCOME="pending — run \`${CHAIN_DESC}\` when ready"
    ;;
  "not applicable"*)
    OUTCOME="this fix doesn't reach user-facing distribution surface"
    ;;
esac

AUDIT_BLOCK="

### Distribution Sync

- **Detected**: ${DISTRIBUTION_TYPE}
- **Choice**: ${USER_CHOICE}
- **Outcome**: ${OUTCOME}
- **At**: $(date -u +%Y-%m-%dT%H:%M:%SZ)
"

patch_closing_comment_append "$AUDIT_BLOCK"
```

#### Failure-mode summary

| Scenario | Behavior |
|----------|----------|
| `REPO_ROOT` cannot be resolved (rare — `pwd` fallback covers non-git case;this branch fires only when both `git rev-parse` AND `pwd` fail or return non-existent dir) | Silent skip + 1-line audit `(REPO_ROOT not resolvable)`;close still completes |
| Non-distribution repo (detection returns `n/a`) | Silent skip + 1-line audit `(detection: not a distribution repo)` |
| `IDD_DISTRIBUTION_SYNC_PROMPT=false` | Silent skip + 1-line audit citing env var |
| Detection hit + user picks `chain` | Skill invoked + outcome appended to audit trail |
| Detection hit + user picks `skip` | Manual command recorded for later use |
| Detection hit + user picks `not applicable` | Reason recorded;close completes cleanly |
| `gh api PATCH` fails (network / auth) | `patch_closing_comment_append` prints warning to stderr;close still proceeds (audit trail loss is non-blocking) |
| Plugin name resolution fails (marketplace.json missing/malformed) | Demote `DISTRIBUTION_TYPE` to `n/a` + WARN to stderr;close completes via standard `n/a` path (no separate audit error category — keeps schema simple) |

> **Future hook for `idd-implement` Step 5.x early-surface**: same `infer_distribution_type` helper could power an earlier prompt (at PR-open time rather than close time). Out of scope for #45 v1 — separate follow-up if value confirmed.

### Step 6.7: Worktree Garbage Collection (v2.75.0+, #167)

Issue 關閉後,**best-effort** 回收這個 issue 的並行 worktree(`.claude/worktrees/idd-<N>/`)。`idd-close` 是 IDD 的終點,也是 issue worktree 生命週期的自然終結——清掉它,免得 abandoned worktree 堆積。

完整契約見 [`references/worktree-isolation.md`](../../references/worktree-isolation.md)(D6 Auto-GC trigger)。

**核心紀律:GC 永不阻擋 close**。worktree 回收是清理動作,不是 lifecycle gate。Step 6(phase=closed)跑完、issue 已關之後才跑;不論成敗,close 都已完成。

呼叫 helper(對 repo root 跑,不是對 worktree 內部):

```bash
# 此時 issue 已 closed(Step 4)。worktree GC 是 post-close cleanup,不影響 close 結果。
# helper 路徑用 $CLAUDE_PLUGIN_ROOT 解析;舊版 plugin 沒這個 script → 視為「helper 缺席」分支。
WT_HELPER="$CLAUDE_PLUGIN_ROOT/scripts/idd-worktree.sh"

if [ ! -f "$WT_HELPER" ]; then
  # Helper 缺席(older plugin / 未安裝)— 一行 warning,close 已完成。
  echo "⚠️  worktree GC skipped: helper not found ($WT_HELPER). 若有殘留 worktree,手動跑 idd-worktree.sh cleanup $NUMBER --force" >&2
else
  # cleanup 對 repo root 跑。明確傳 --repo-root(honors --cwd;預設 $PWD),helper
  # 內部會 anchor 到該 repo 的 MAIN worktree,所以即使從 linked worktree 內呼叫
  # 也能正確找到並移除 .claude/worktrees/idd-N。(#167 verify P2 — codex)
  bash "$WT_HELPER" cleanup "$NUMBER" --repo-root "${CWD:-$PWD}"
  WT_RC=$?
  if [ "$WT_RC" -eq 5 ]; then
    # Exit 5 = refuse-dirty:worktree 有 uncommitted changes,helper 拒絕刪,worktree 原封不動。
    echo "⚠️  worktree GC refused: .claude/worktrees/idd-$NUMBER/ 有未提交變更,已保留。手動處理:commit/stash 後 idd-worktree.sh cleanup $NUMBER,或 idd-worktree.sh cleanup $NUMBER --force 強制刪除。" >&2
  elif [ "$WT_RC" -ne 0 ]; then
    # 其他非零(generic / not-git / usage)— 同樣 warn-only,不影響已完成的 close。
    echo "⚠️  worktree GC failed (exit $WT_RC): .claude/worktrees/idd-$NUMBER/ 可能殘留。手動跑 idd-worktree.sh cleanup $NUMBER 查看。" >&2
  fi
  # WT_RC=0 → worktree 已移除(或本來就不存在,idempotent no-op),靜默成功。
fi
```

| 結果 | exit code | 行為 |
|------|-----------|------|
| Helper 缺席(older plugin) | — | 🟡 一行 warning(建議手動 cleanup),close 已完成 |
| Worktree 移除成功 / 本來就不存在 | `0` | ✅ 靜默(idempotent no-op 也算成功) |
| Dirty-refuse(未提交變更,無 `--force`) | `5` | 🟡 一行 warning(保留 worktree + 提示 commit/stash 或 `--force`),close 已完成 |
| 其他錯誤(generic / not-git / usage) | `1`/`2`/`3`/`4` | 🟡 一行 warning,close 已完成 |

**為什麼 best-effort 而非 hard gate**:issue 已經關了(Step 4)。worktree 殘留只是磁碟上的暫存目錄,`idd-worktree.sh list` 隨時能 surface 出 orphan 讓使用者手動 `cleanup`。為了一個清理動作去 fail 一個已完成的 close,會把 audit trail 弄得不一致(issue closed 但 skill 報 error)。Dirty-refuse 尤其要尊重——使用者可能還沒 commit 的工作不該被靜默刪掉。

### Step 6.8: Tree-lock Release（v2.85.0+, #183）

釋放 `idd-implement` Step 0.4 取得的 shared working-tree lock，讓下一個 session 能立刻 acquire（而非等 stale-reclaim TTL）。同 worktree GC 一樣 **best-effort**：lock 不存在、helper 缺席、或非本 session 持有都靜默無害（release 是 holder-scoped + idempotent）。

```bash
TREE_LOCK="$CLAUDE_PLUGIN_ROOT/scripts/idd-tree-lock.sh"
if [ -f "$TREE_LOCK" ]; then
  # Same id derivation as idd-implement Step 0.4 (tree-$PPID, the persistent
  # harness shell) so release matches within the same claude instance. A
  # different instance / mismatched id → holder-scoped no-op (lock left for the
  # holder's own close or for liveness reclaim — never steals another's lock).
  bash "$TREE_LOCK" release --repo "${CWD:-$PWD}" --id "${IDD_SESSION_ID:-tree-$PPID}" 2>/dev/null
fi
```

> **為什麼放 close 而非更早**：lock 的語意是「這個 session 還在這棵 tree 上工作」。工作橫跨 implement→verify→close，所以 close 是 session 結束、該還鎖的點。若 session 異常結束沒跑到這裡，留下的 stale lock 由下一個 starter 的 `acquire` 用 PID-liveness 自動 reclaim（見 `idd-tree-lock.sh`），不會永久卡死。release 是優化（即時還鎖），reclaim 是兜底（liveness 回收）。

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
