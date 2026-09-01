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

判斷依據：掃描 comments 中的 `## Diagnosis`、`## Implementation Plan`、`## Implementation Complete`、`## Verify`、`## Closing Summary` 標題。**比對大小寫不敏感、1-6 個井號、井號與字之間的裝飾字元（emoji）**（#295）—— 這些 heading 全部由 LLM 依模板生成、寫入端沒有任何 normalization，所以 `## Closing summary` 這類漂移是預期而非例外；此處硬要求大小寫只會讓 phase 停在舊值，而 phase 停在舊值正是 `idd-close` Step 6 存在的理由。

**比對維持寬鬆（`present_re` 那一側），但 `Closing Summary → closed` 這一條額外要求 issue 的 GitHub `state` 真的是 `CLOSED`。**

> **上一版在這裡過度矯正了，而且是我自己造成的回歸。** 當時把五個 heading 全部改用嚴格的 `lead_re`（必須是 comment 首行、不得帶 blockquote 前綴），理由是「phase 是正面斷言，寬鬆比對會讓一則**引用**模板的 comment 把還開著的 issue 推成 `closed`」。那個顧慮是真的 —— 但那個修法**打掉了 `#295` 自己量到的真實案例**：43 張 closed issue 的 11 個誤報裡，有一個正是「summary 併進 Implementation Complete 那一則」。真 summary 併在別的 comment 中間，`lead_re` 看不到，phase 就永遠停在 `implemented`。而 phase 停在舊值，正是這一步存在的理由。
>
> 更糟的是，它跟上面那句「硬要求大小寫只會讓 phase 停在舊值」**直接矛盾**——我留著那句話，同時引進了另一條讓 phase 停在舊值的路。
>
> 真正的判準不是「比對要多嚴」，而是**這個正面斷言有沒有獨立證據**。`closed` 的權威來源不是某個 heading 長什麼樣，是 GitHub 自己的 `state` 欄位——免費、精確、無法被 comment 內容偽造。所以：
>
> - **引用造成的偽 `closed`**：issue 還開著 → `state != CLOSED` → 擋掉。這是原本要防的那個 harm，防住了。
> - **併進 IC 的真 summary**：issue 已關 → `state == CLOSED` → phase 正確推到 `closed`。回歸修好了。
>
> 其餘四個 heading（Diagnosis / Implementation Plan / Implementation Complete / Verify）沒有對應的權威狀態欄位，維持寬鬆比對：它們推錯的代價是 phase 顯示錯（良性、下一次 sync 會更正），不是宣告一張開著的 issue 已結案。

> **本步是這個 marker 的寫端 reader（#295 family-wide scope 的第 6 個）**。它**不做**四分類分流。分類的 normative source 是 [`scripts/check-closed-without-summary.sh`](../../scripts/check-closed-without-summary.sh)，消費者是 `--audit-closes` 與 `--retroactive`。

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

{### Tasks —— **僅在**給了 --tasks-file 或 body 已有此小節時出現；否則整節省略。
 見下方「### Tasks 小節」。**不得**照本模板無條件輸出——那會製造一個假的
 authoritative source，讓 gate 對一份不存在的 checklist 放行。}

### Commits
- `{hash}` {message}
```

#### `### Tasks` 小節：priority 2 的 producer（#290）

`## Current Status > ### Tasks` 是 `authoritative_source` 優先序的**第二層**（見
[`rules/append-vs-modify.md`](../../rules/append-vs-modify.md)）。在 #290 之前它**沒有任何
producer**——三個 consumer 讀它，卻沒有 skill 寫它，於是優先序實務上塌縮成「只有第一層」，
而第一層只有 `idd-implement` Step 5a 產生。**任何繞過 `idd-implement` 的路徑因此沒有
authoritative source**，fallback 去掃 pre-implementation 的 Strategy checkbox。

本小節是那個 producer。

**`--tasks-file <path>`（選填）**：指向一個含 checkbox 行的 markdown 檔（例如外部
spec-driven 工具維護的任務清單）。給定時，把該檔的 checkbox 行逐行複製進 `### Tasks`，
保留 `[ ]` / `[x]` / `[~]` / `[-]` 標記與原文。

**路徑從何而來**：由**呼叫端查詢外部工具取得**，不由任何一方從「change 名稱 ＋ 目錄慣例」
組出。組路徑只是把佈局知識換個位置，對方改佈局會**靜默失效**。本 skill 只知道「一個含
checkbox 的檔案」，樹內不出現任何外部工具的目錄名。

##### 圍籬：路徑必須落在當前 git toplevel 之內（normative）

```bash
RAW="$TASKS_FILE"                      # 訊息要印**使用者給的**值，不是解析後的
refuse() { printf '✗ --tasks-file 拒絕採用：%s\n    給定路徑：%s\n    當前 toplevel：%s\n' \
             "$1" "$RAW" "${TOP:-<無法解析>}" >&2; TASKS_FILE=""; }

# (1) toplevel 解析失敗 → **fail-closed**。少了這一步，TOP="" 會讓 pattern 變成
#     `/*`，任何絕對路徑都通過——圍籬整個失效。
TOP=$(git -C "$CWD" rev-parse --show-toplevel 2>/dev/null) || TOP=""
TOP=$(cd "$TOP" 2>/dev/null && pwd -P) || TOP=""      # 與 ABS 同樣 physical，避免 symlink checkout 誤拒
[ -n "$TOP" ] || { refuse "無法解析當前 git toplevel"; }

# (2) 必須是**可讀的一般檔案**——目錄（例如 toplevel 本身）不是 checklist
[ -n "$TASKS_FILE" ] && [ -f "$TASKS_FILE" ] && [ -r "$TASKS_FILE" ] \
  || { [ -n "$TASKS_FILE" ] && refuse "不是可讀的一般檔案"; }

# (3) **整條路徑**（含最後一段）都要解析 symlink。只解析 dirname 會被
#     `ln -s /別處/tasks.md "$TOP/link.md"` 繞過——ABS 看起來在樹內，讀取卻落在樹外。
if [ -n "$TASKS_FILE" ]; then
  ABS=$(readlink -f "$TASKS_FILE" 2>/dev/null || python3 -c 'import os,sys;print(os.path.realpath(sys.argv[1]))' "$TASKS_FILE")
  case "$ABS/" in
    "$TOP/"*) : ;;                     # 通過
    *) refuse "落在當前工作樹之外" ;;   # 不 emit，但**不中止** idd-update 其餘工作
  esac
fi
```

三道各有其失敗模式，缺一不可：**(1) 缺了會 fail-open**（最嚴重——圍籬看起來在但形同虛設）；
**(2) 缺了**會把目錄當檔案讀；**(3) 只解析 dirname** 會被最後一段的 symlink 繞過。

**為何是必要而非防禦性過度**：外部工具的 change registry **不一定 cwd-scoped**。實測有
回傳**同一 repo 另一個 git worktree** 路徑的情形——worktree 共用 `.git` 但 toplevel 不同，
所以這個檢查抓得到。若原樣採用，gate 會讀另一個工作樹的完成狀態。

方向是最壞的那種：另一工作樹的清單若全部完成，**一個沒做完的 issue 會通過 close gate**。
修一個假陰性（該過不過）卻引入假陽性（不該過卻過）——**後者嚴重得多**，因為前者會被人擋下
（被擋住的人會抱怨），後者不會（沒人會發現 gate 放行了不該放的）。

**拒絕時必須印出兩個路徑**：只說「拒絕」會讓使用者分不出這是設定錯誤還是真的越界。

##### 未給 flag 時 **MUST 保留** body 既有的 `### Tasks`（normative）

本 skill 的 managed zone 是「`## Current Status` 到結尾**整段替換**」。若「未給 flag ＝ 不
輸出」，則**下一次**任何不帶 flag 的 idd-update 都會把先前寫入的 `### Tasks` 抹掉——
authoritative source 消失，chain 又塌回去。

這不是理論風險，是**本 pipeline 的既定流程**：

```
Phase 3b.5  idd-update --tasks-file   → 寫入 ### Tasks           ✓
Phase 4     idd-verify 的 Auto-Update → idd-update（無 flag）→ 整段重建、被抹掉  ✗
```

所以規則是：

| 情形 | 行為 |
|---|---|
| 給了合法 `--tasks-file` | 由該檔**重建** `### Tasks` |
| **未給 flag，但 body 已有 `### Tasks`** | **逐字保留既有內容**（不重建、不刪除）|
| 未給 flag，body 也沒有 | 不 emit |
| 路徑不存在 / 不可讀 / 越界 / 零個 checkbox 行 | **視同未給 flag**——套用上面兩列（有就保留，沒有就不 emit）|

最後一列的關鍵：**拒絕一個壞路徑不得順帶刪掉一份好的既有 checklist**。

不 emit（而非 emit 空節）的理由：依 canonical 定義，heading 在而項目數為 0 **不會 resolve**，
兩者在 gate 層等價。選擇不 emit **不是可讀性偏好**——一個空的 `### Tasks` 出現在 issue 上，
讀的人會問「這是壞了還是本來就沒有」，那是需要解釋的雜訊。不製造它。

### Step 5: 更新 Issue Body

Managed zone 錨在 **`## Current Status` heading**，**不是**第一個 `---`。依 body 現狀走兩分支：

**Branch A — body 已有 `## Current Status`**：從該 heading 起（含其上**緊鄰**的 `---`，若有）到 body 結尾，整段替換為新的 Current Status 區塊。`## Current Status` 以上的所有內容（原始記錄 + 任何 audit blocks）**逐字保留**。

**Branch B — body 無 `## Current Status`**：**append** 新區塊（`\n---\n\n## Current Status...`）到 body 結尾，**保留所有既有內容**，不論 body 有幾個 `---`、`---` 下是什麼。

> **為何不錨在第一個 `---`（#178）**：`/idd-issue` 的 parking-lot seed 在第一個 `---` 下放的是 **audit blocks**（`### Clarity Surface` / `### Linked-Context Siblings`），不是 Current Status。錨在「第一個 `---` 以下全替換」會**靜默刪掉**這些 audit。`---` 在 IDD body 語意不唯一（既分隔 original/audit，也分隔 audit/status），不能當 managed-zone 的唯一錨。
>
> **Backward-compat**：既有「`---` 緊鄰 `## Current Status`」的 body，Branch A 與舊「replace below first `---`」產出**同結果**。只有「多個 `---`、audit 夾在中間」的 body 行為改變 —— 那正是修復（舊邏輯誤刪、新邏輯保留）。Fix **strictly safer**：只保留更多、不刪更多。

```bash
# （#226）egress 經 gh-egress.sh 派送：$SCRUB_LEVEL 依 rules/privacy-scrubbing.md 解析
# （third-party=enforce / own-public=warn / private=light），派送前先跑 LLM 隱私自審；
# 有 @mention 時另帶 --mention-attested（rules/tagging-collaborators.md 5-step 後）。
bash "$CLAUDE_PLUGIN_ROOT/scripts/gh-egress.sh" edit $NUMBER --repo $GITHUB_REPO --body "$UPDATED_BODY" --scrub-attested "$SCRUB_LEVEL"
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
/issue-driven-dev:idd-update #42 --tasks-file <path>   # 見 Step 4 的 ### Tasks 小節
```

用途：
- 手動補充 comments 後同步 body
- Issue 長時間沒動，重新整理現狀
- 修正 Current Status 中的過時資訊
- 為走「非 `idd-implement` 路徑」的 issue 補上 authoritative source（`--tasks-file`）

## 鐵律

- **永遠不改 `## Current Status` managed zone 以外的內容**。原始記錄 + audit blocks（`### Clarity Surface` / `### Linked-Context Siblings` 等）都是審計軌跡。錨在 `## Current Status` heading，**不是**第一個 `---`（`---` 語意不唯一，錨在它會誤刪 audit — #178）。
- **Key Decisions 只加不刪**。新的加在最上面，舊的保留。
- **簡潔**。每個 bullet 一行，不超過 100 字。
- **Phase 必須準確**。如果推斷不出來，標 `unknown` 並提醒使用者。
