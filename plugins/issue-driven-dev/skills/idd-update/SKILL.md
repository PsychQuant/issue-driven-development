---
name: idd-update
description: |
  更新 GitHub Issue body 的 Current Status 區塊，反映最新進度。
  保留原始記錄（Problem/Type/Expected），只更新狀態區塊。
  由其他 idd-* skills 自動呼叫，也可手動執行。
  支援 batch mode（v2.34.0+）：多個 #N 依序 sync（如 `#34 #36 #38`），最 idempotent 的 batch。
  Use when: issue 狀態改變時（自動）、或手動同步現狀。
  防止的失敗：issue body 過時，要讀完所有 comments 才知道現狀。
argument-hint: "#issue [#issue ...] e.g. '#42' or '#34 #36 #38' (batch)"
allowed-tools:
  - Bash(gh:*)
  - Bash(git:*)
  - Read
  - Edit
---

# /idd-update — 同步 Issue 現狀

保持 issue body 永遠反映最新狀態，不用翻 comments 就知道現在在哪。

## 核心原則

> 原始記錄不動，現狀即時更新。Comment 是歷史，Body 是現狀。

## Batch mode（v2.34.0+）

`idd-update #34 #36 #38` 對 3 個 issue 依序 fetch + 重組 Current Status + body edit。Pure idempotent，最安全的 batch 之一。完整契約見 [batch-and-cluster.md](../../references/batch-and-cluster.md)。

實用情境：phase 從 verified 進到 closed 後一次 sync N 個 issue 的 body；或重啟 session 後想看哪些 issue 卡哪一階段，先 batch update 確保 body 是最新狀態。

## When to use `idd-issue` multi-finding mode instead（v2.55.0+）

如果你要做的是「**從一個 source 文件抽多個 findings,部分 update 既存 issue Current Status**」(罕見場景:transcript 含 5 個對既存 in-flight issues 的 progress 紀錄),**不要**手動跑 `idd-update` 多次,改用 `idd-issue` multi-finding mode:

```bash
idd-issue source.docx       # auto-trigger when source contains ≥2 findings
```

差別:

| 情境 | 用 idd-update | 用 idd-issue multi-finding mode |
|------|--------------|-------------------------------|
| 純 phase sync(verified → closed)N 個 issue | ✅ batch mode | overkill |
| 從 source 文件分流多 finding,部分 update Current Status / 部分 comment / 部分 new | 5+ 次 invoke + 失 audit trail | ✅ 一次 invoke + Stage 2 picker 選 routing intent `update status` |

`update status` intent 內部仍 call `idd-update` 邏輯(reuse 現有 implementation),audit trail 串接 idd-issue 的 jsonl run log。

完整 multi-finding mode 契約見 `idd-issue` SKILL.md `## Multi-finding source mode` 段落。

## 設計

Issue body 分為兩個區域：

```markdown
## Problem            ← 不動（原始記錄）
## Type               ← 不動
## Expected           ← 不動
## Actual             ← 不動
## Impact             ← 不動

---

## Current Status     ← idd-update 管理這塊
```

**Managed zone = `## Current Status` heading 到 body 結尾**（含其上**緊鄰**的 `---`，若有）。這塊以外的所有內容 = 永遠不改。

> ⚠️ Managed zone 錨在 `## Current Status` **heading**，**不是**「第一個 `---`」。`---` 在 IDD body 語意不唯一 —— `/idd-issue` 的 parking-lot seed 會在第一個 `---` **下**放 audit blocks（`### Clarity Surface` / `### Linked-Context Siblings`）而非 Current Status。錨在 `---` 會誤刪這些 audit（#178）。只有 `## Current Status` heading 是 unambiguous 的錨。

## Configuration

按 [config-protocol](../../references/config-protocol.md) 解析 target repo:

- `--repo owner/repo` flag → per-invocation override
- Walk-up `.claude/issue-driven-dev.local.json`(從 cwd 往上找)
- Path / git predicates 自動匹配

**Group/predicate 行為**:`idd-update` 操作既存 issue,只用 path/git 類 predicate。Group config 會 fall through 到 primary repo。

## Execution

### Step 0: Bootstrap Stage Task List（強制)

**在動任何事之前**先用 `TaskCreate` 為這個 stage 建 todo list,確保每個 sub-step 都被追蹤:

```
TaskCreate(name="read_issue", description="gh issue view #NNN 取 title/body/labels/state/comments")
TaskCreate(name="determine_phase", description="掃 comments 標題（Diagnosis / Implementation Plan / Implementation Complete / Verify / Closing Summary）推斷 phase")
TaskCreate(name="extract_key_info", description="從 comments 提取 Key Decisions / Scope Changes / Blocking / Related Commits 四類")
TaskCreate(name="assemble_current_status", description="組 ## Current Status 區塊 markdown（Phase / Last updated / 四類分節）")
TaskCreate(name="update_body", description="gh issue edit：body 有 ## Current Status → 替換該 heading（含其上緊鄰 ---）到結尾；無則 append 新區塊（保留全部既有內容，不論幾個 ---）(category: bounded-section-replace, scope: \"## Current Status\")")
TaskCreate(name="report_update", description="輸出 ✓ Issue #NNN status updated → {phase}（取代原 Step 6「靜默完成」的 silent path）")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。**TaskCreate 清單 = 真實的步驟清單；任何寫在 skill 裡但沒列進 TaskCreate 的步驟，都視為 skill 的 bug，必須補進 Task 清單。**

特別提醒：原 Step 6 的「靜默完成」設計本意是「不打擾 caller」，但**「不輸出 = 不可見 = 沒人發現是否真的跑完」**。新的 `report_update` task 確保即使被其他 skill 呼叫，task list 仍會記錄完成狀態 — 這是「`idd-close` 的 Auto-Update 漏跑」這類 bug 的根因之一。

---

### Step 1: 讀取 Issue 完整資訊

```bash
gh issue view $NUMBER --repo $GITHUB_REPO --json title,body,labels,state,comments
```

### Step 2: 判斷當前 Phase

從 comments 中推斷 issue 目前所在階段：

| 最後的 comment 類型 | Phase |
|---------------------|-------|
| 無 comment | `created` |
| Diagnosis | `diagnosed` |
| Implementation Plan | `planning` |
| Implementation Complete | `implemented` |
| Verify (PASS) | `verified` |
| Verify (FAIL / findings) | `needs-fix` |
| Closing Summary | `closed` |

判斷依據：掃描 comments 中的 `## Diagnosis`、`## Implementation Plan`、`## Implementation Complete`、`## Verify`、`## Closing Summary` 標題。

#### Authoritative source resolution (v2.73.0+, #150)

當需要從 body 讀取 Tasks / Checklist 作為 phase derivation 上下文(罕見:phase 推斷因 comment 結構模糊 fall back to body),套用 [`rules/append-vs-modify.md`](../../rules/append-vs-modify.md) 的 `authoritative_source` priority order:

```
authoritative_source = first_exists([
  "## Implementation Complete > ### Checklist",
  "## Current Status > ### Tasks",
  "## Todo" | "## Tasks" | "## Checklist"
])
```

無 authoritative_source → fall back 掃所有 sections(legacy issue 行為);此 fallback 保留 backward compat。

### Step 3: 從 Comments 提取關鍵資訊

掃描所有 comments，提取：

1. **Key Decisions**：策略改變、重要發現、scope 調整
   - 從 diagnosis 的 Strategy 區塊
   - 從 implementation 中的 scope 說明
   - 從 verify 的 findings

2. **Scope Changes**：跟原始 issue 不同的地方
   - 新增的需求
   - 移除的需求
   - 調整的做法

3. **Blocking**：當前的阻塞項
   - verify 未通過的 findings
   - 等待使用者確認的問題
   - 依賴其他 issue

4. **Related Commits**：引用此 issue 的 commits

```bash
git log --oneline --grep="#$NUMBER" | head -10
```

### Step 4: 組裝 Current Status 區塊

```markdown
---

## Current Status

**Phase**: {phase}
**Last updated**: {YYYY-MM-DD} by {which idd-* skill}

### Key Decisions
- {decision 1}
- {decision 2}

### Scope Changes
- {change 1, or "(none)"}

### Blocking
- {blocker 1, or "(none)"}

### Commits
- `{hash}` {message}
```

### Step 5: 更新 Issue Body

Managed zone 錨在 **`## Current Status` heading**，**不是**第一個 `---`。依 body 現狀走兩分支：

**Branch A — body 已有 `## Current Status`**：從該 heading 起（含其上**緊鄰**的 `---`，若有）到 body 結尾，整段替換為新的 Current Status 區塊。`## Current Status` 以上的所有內容（原始記錄 + 任何 audit blocks）**逐字保留**。

**Branch B — body 無 `## Current Status`**：**append** 新區塊（`\n---\n\n## Current Status...`）到 body 結尾，**保留所有既有內容**，不論 body 有幾個 `---`、`---` 下是什麼。

> **為何不錨在第一個 `---`（#178）**：`/idd-issue` 的 parking-lot seed 在第一個 `---` 下放的是 **audit blocks**（`### Clarity Surface` / `### Linked-Context Siblings`），不是 Current Status。錨在「第一個 `---` 以下全替換」會**靜默刪掉**這些 audit。`---` 在 IDD body 語意不唯一（既分隔 original/audit，也分隔 audit/status），不能當 managed-zone 的唯一錨。
>
> **Backward-compat**：既有「`---` 緊鄰 `## Current Status`」的 body，Branch A 與舊「replace below first `---`」產出**同結果**。只有「多個 `---`、audit 夾在中間」的 body 行為改變 —— 那正是修復（舊邏輯誤刪、新邏輯保留）。Fix **strictly safer**：只保留更多、不刪更多。

```bash
gh issue edit $NUMBER --repo $GITHUB_REPO --body "$UPDATED_BODY"
```

### Step 6: Report Update

無論是被其他 skill 呼叫還是手動呼叫，**必須**輸出至少一行 task 完成證據：

```
✓ Issue #NNN status updated → {phase}
```

這是 task tracking 的硬性要求 — 沒有輸出 = task list 看不到結束 = 等同沒跑（這正是 2.18.x 之前 idd-close Auto-Update 漏跑的根因）。

**模式差異**：

- **被其他 skill 自動呼叫**（idd-diagnose / idd-implement / idd-verify / idd-close 等的 Step N Auto-Update）：只輸出上面那一行作為 noise minimum，不顯示完整 Current Status 區塊內容
- **手動呼叫** `/idd-update #NNN`：除了那一行外，額外顯示完整的新 Current Status 內容讓使用者看清楚改了什麼

**禁止靜默**：不論呼叫情境，「不輸出任何訊息然後直接 return」是違規。任務追蹤必須有可見證據。

## 被其他 Skills 呼叫

每個 idd-* skill 在最後一步呼叫 idd-update：

```
# 在 idd-diagnose 結尾
→ idd-update #NNN（自動，phase = diagnosed）

# 在 idd-plan 結尾（v2.36.0+ Plan tier）
→ idd-update #NNN（自動，phase = planning，標示「Plan tier approval gate 已通過」）

# 在 idd-implement 結尾
→ idd-update #NNN（自動，phase = implemented）

# 在 idd-verify 結尾
→ idd-update #NNN（自動，phase = verified 或 needs-fix）

# 在 idd-close 結尾
→ idd-update #NNN（自動，phase = closed）
```

## 手動呼叫

```
/issue-driven-dev:idd-update #42
```

用途：
- 手動補充 comments 後同步 body
- Issue 長時間沒動，重新整理現狀
- 修正 Current Status 中的過時資訊

## 鐵律

- **永遠不改 `## Current Status` managed zone 以外的內容**。原始記錄 + audit blocks（`### Clarity Surface` / `### Linked-Context Siblings` 等）都是審計軌跡。錨在 `## Current Status` heading，**不是**第一個 `---`（`---` 語意不唯一，錨在它會誤刪 audit — #178）。
- **Key Decisions 只加不刪**。新的加在最上面，舊的保留。
- **簡潔**。每個 bullet 一行，不超過 100 字。
- **Phase 必須準確**。如果推斷不出來，標 `unknown` 並提醒使用者。
