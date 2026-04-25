---
name: idd-implement
description: |
  按照 diagnosis 的策略實作，嚴格控制 scope。
  只改 issue 要求的東西，每個 commit 引用 #NNN。
  Use when: diagnosis 確認後、開始寫 code 時。
  防止的失敗：scope creep — 改 #42 順手重構了三個不相關的檔案。
argument-hint: "#issue e.g. '#42'"
allowed-tools:
  - Bash(gh:*)
  - Bash(git:*)
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
  - TaskCreate
  - TaskUpdate
  - TaskList
---

# /implement — 紀律實作

按 diagnosis 的策略寫 code，不多做也不少做。每個 checklist item 都有 TaskList 條目追蹤，`idd-close` 會強制驗收。

## 核心原則

> 每一行改動都必須能追溯到 #NNN。追溯不到的改動 → 開新 issue。
>
> **Strategy 上的每個 `- [ ]` 都是契約**——`idd-implement` 開始時進 TaskList，`idd-close` 會 refuse 關任何還有未勾項的 issue。

## Configuration

按 [config-protocol](../../references/config-protocol.md) 解析 target repo:

- `--repo owner/repo` flag → per-invocation override
- Walk-up `.claude/issue-driven-dev.local.json`(從 cwd 往上找)
- Path / git predicates 自動匹配

**Group/predicate 行為**:`idd-implement` 操作既存 issue,只用 path/git 類 predicate。Group config 會 fall through 到 primary repo。

## Execution

### Step 0: Bootstrap Stage Task List（強制)

**在動任何事之前**先用 `TaskCreate` 為這個 stage 建 stage-level todo list(與 Step 2.5 的 per-Strategy-item TaskList 不同層):

```
TaskCreate(name="read_issue_and_diagnosis", description="gh issue view + 確認最新 diagnosis comment 的 Strategy")
TaskCreate(name="draft_implementation_plan", description="依 Strategy 起草 Implementation Plan 並 comment 到 issue")
TaskCreate(name="bootstrap_strategy_tasklist", description="Step 2.5: Simple complexity → 為每個 - [ ] bullet 建 TaskCreate; SDD → 跳過(spectra-apply 管)")
TaskCreate(name="execute_tdd_loop", description="對每個 strategy item: 寫測試→RED→實作→GREEN→commit→TaskUpdate completed")
TaskCreate(name="scope_guard", description="實作中發現不相關問題 → 開新 issue,不混入本 #NNN")
TaskCreate(name="sync_checklist_and_summary", description="Step 5: 把最終 checklist 狀態寫回 Implementation Complete comment")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。

> **兩層 task 的關係**:
> - **Stage-level TaskList(此 Step 0)** — 追蹤 idd-implement 本身的 6 個 execution steps
> - **Strategy-level TaskList(Step 2.5 Bootstrap)** — 追蹤具體改動清單的每個 checklist bullet
> 兩者並存。Stage-level 的 `execute_tdd_loop` 那一項,會持續等到 Strategy-level 所有 items 完成後才 mark 為 completed。

---

### Step 1: 讀取 Issue + Diagnosis

```bash
gh issue view $NUMBER --repo $GITHUB_REPO --json title,body,labels
```

回顧對話中的 diagnosis report，確認 strategy。

### Step 2: 列出變更清單並 comment 到 issue

根據 diagnosis 的 strategy，列出具體要改的檔案：

```markdown
## Implementation Plan

- [ ] 修改 src/foo.ts — {改什麼}
- [ ] 修改 src/bar.ts — {改什麼}
- [ ] 新增 tests/foo.test.ts — {測什麼}
```

**Scope check**: 清單裡的每一項都能對應到 issue 的某個要求？
- 對應不上 → 移除，或開新 issue
- Issue 的要求沒被覆蓋 → 補上

**Comment 到 issue**（留下實作計畫的紀錄）：

```bash
gh issue comment $NUMBER --repo $GITHUB_REPO --body "$IMPLEMENTATION_PLAN"
```

### Step 2.5: Bootstrap TodoList（non-Spectra case）

**判斷是否走 Spectra**：讀最新的 diagnosis comment 的 `### Complexity` 欄位：

| Complexity | 行為 |
|-----------|------|
| `Simple` | ✅ 本 step 啟動 TaskList 追蹤每個 checklist item |
| `SDD-warranted` | ⏭ 跳過本 step（由 `spectra-apply` 管 `openspec/changes/<name>/tasks.md`）|
| _(missing / unclear)_ | ✅ 預設當 Simple，啟動 TaskList（保守作法）|

**Simple case 執行**：

1. 從 Implementation Plan（Step 2 剛 comment 的）擷取每個 `- [ ]` bullet 當 task subject
2. 對每個 bullet 呼叫 `TaskCreate`，subject 用 bullet 第一行、description 用完整 bullet（含子項）
3. 保留 task IDs 的映射表（`bullet_index → task_id`），之後用來 `TaskUpdate`

> **為什麼用 harness-level TaskList 而不是只靠 comment checkbox?**
> Comment checkbox 是**紀錄**，TaskList 是**即時狀態**。TaskList 讓進度在 UI 可視化、session 中斷不會丟狀態、完成一項就打勾。兩者並存：TaskList 是工作中的 source of truth，`## Implementation Complete` comment 是工作後的不可變紀錄。

### Step 3: TDD 執行 + Task tracking

每個變更項依序執行：

0. **TaskUpdate → `in_progress`**（開始做這一項之前）

1. **寫測試**（RED）
   - 測試描述用 issue 的語言
   - 測 behavior，不測 implementation

2. **跑測試確認失敗**
   - 失敗原因必須是「功能還沒實作」，不是「測試寫錯」

3. **寫最小實作**（GREEN）
   - 只寫讓測試通過的 code
   - 不「順便」優化、重構、加功能

4. **跑測試確認通過**
   - 全部測試，不只新的

5. **Commit**
   ```bash
   git add {changed files}
   git commit -m "fix: {description} (#NNN)"
   ```

6. **TaskUpdate → `completed`**（確認該項真的做完了才打勾）

**鐵律**：

- 測試還在 red → 不能 `completed`
- 只改了一半、等使用者確認 → 維持 `in_progress`
- 完全不做了（scope 調整、won't fix）→ 用 `TaskUpdate` 改 subject 加 `[SKIP]` 前綴，維持 `pending` 或改 `deleted`；之後在 `## Implementation Complete` comment 裡寫成 `- [~]` 或 `- [-]`（見 CLAUDE.md Checklist Conventions）

### Step 4: Scope 守衛

實作過程中發現的問題：

| 發現 | 處理 |
|------|------|
| 不相關的 bug | 開新 issue，繼續 #NNN |
| 不相關的 code smell | 開新 issue，繼續 #NNN |
| #NNN 的前置依賴 | 確認是否 blocker。是 → 先處理依賴；不是 → 記錄在 issue comment |
| 比預期更大的改動 | 停下來，回到 diagnosis 重新評估 |

**鐵律**：不在 #NNN 的 branch 上修不相關的東西。

### Step 5: Checklist Sync + 完成確認

所有變更清單項目完成後：

**Step 5a: Checklist Sync**

呼叫 `TaskList` 取當前所有 task 狀態，對照 Implementation Plan 的 bullet，把最終狀態寫回 `## Implementation Complete` comment 的 checkbox：

| TaskList status | Comment checkbox | 意義 |
|-----------------|------------------|------|
| `completed` | `- [x]` | 做完，測試通過 |
| `in_progress` | `- [ ]` | ⚠️ 還沒做完——**不該走到 Step 5** |
| `pending` | `- [ ]` | ⚠️ 還沒開始——**不該走到 Step 5** |
| subject 含 `[SKIP]` | `- [~]` | 刻意跳過（須在 comment 附說明原因）|
| `deleted` | `- [-]` | 決定不做（scope 調整 / won't fix）|

**鐵律**：若 TaskList 還有 `pending` 或 `in_progress` 的 task，**停下**——回到 Step 3 做完，或明確改成 `[SKIP]` / `deleted` 並說明原因。不能用 `- [x]` 假裝做完了。

```bash
git status --short
git diff --stat HEAD~{N}
```

**Step 5b: 回顧**

- 每個 commit 都引用了 #NNN？
- 變更範圍跟 diagnosis 的 strategy 一致？
- 沒有超出 scope 的改動？
- TaskList 最終狀態與 `## Implementation Complete` comment 的 checkbox 一致？

**如果有產出圖表**，上傳到 attachments release：

```bash
# 讀取 .claude/issue-driven-dev.local.json 的 attachments_release 設定
gh release upload $ATTACHMENTS_RELEASE {figure_files}.png \
  --repo $GITHUB_REPO --clobber
```

圖片 URL 格式：`https://github.com/$GITHUB_REPO/releases/download/$ATTACHMENTS_RELEASE/{filename}.png`

**Comment 實作摘要到 issue**（含圖片）：

```bash
gh issue comment $NUMBER --repo $GITHUB_REPO --body "$(cat <<'EOF'
## Implementation Complete

### Checklist (synced from TaskList)
- [x] {plan item 1} → commit {hash}
- [x] {plan item 2} → commit {hash}
- [~] {plan item 3} — skipped: {reason why we chose not to do this now}
- [-] {plan item 4} — won't fix: {why this is out of scope}

> Legend: `- [x]` done · `- [~]` skipped (may revisit) · `- [-]` won't fix (scope)
> `idd-close` will refuse to close if any `- [ ]` remains in this checklist.

### Changes
- {commit 1 hash}: {description}
- {commit 2 hash}: {description}

### Files Changed
{git diff --stat output}

### Figures (if any)

**鐵律：每張圖下方必須附內容說明**。圖不會自己解釋自己——只貼圖沒文字，讀者需要回去翻 script 才能理解。說明必須包含三個要素：

1. **資料**：N、變項、組別、誤差線意義（圖上看不到的資訊要補）
2. **統計**：檢定方法、p-value、effect size、CI（若有）
3. **結論**：一句話說明圖在講什麼（方向、顯著性、實務意義）

格式：

```markdown
![{description}](https://github.com/$GITHUB_REPO/releases/download/$ATTACHMENTS_RELEASE/{filename}.png)

**圖 X. {Figure title}** — {資料描述}。{統計結果}。{結論一句話}。
```

實際範例：

```markdown
![5-group total score](https://.../fig1.png)

**圖 1. 5-group 記憶表現比較** — 每組 N=13（Speaker / NN / NY / YN / YY），誤差線 ± SE。ANCOVA (group + MS_c) 中 RobotAgent contrast β=+1.09, p=.005；加 Age + MoCA 後 p=.0005。Speaker (53.8%) 顯著低於 Exp2 四組平均 (71.0%)，差距 17 個百分點——老師「Speaker 最佳」假設被反駁。
```

若圖是探索性/視覺化、沒跑特定檢定：說明仍要寫圖呈現的模式（何者高何者低、分布特徵）與是否符合主結論。

### Scope Compliance
{是否有超出範圍的改動，如有則說明}

### Next: verification pending
EOF
)"
```

提示下一步：`/issue-driven-dev:idd-verify #NNN`

## Commit 規範

```
<type>: <description> (#NNN)
```

- type: `fix` / `feat` / `refactor` / `docs` / `test` / `chore`
- description: 用 issue 的語言描述改了什麼
- **必須**引用 issue：用 `(#NNN)` 或 `Refs #NNN`（會產生 cross-link 但**不會** auto-close）

### 禁止用 `Closes` / `Fixes` / `Resolves` trailer

**Do NOT** use GitHub 的 auto-close trailers in IDD commits:

```
❌ fix: resolve foo (#42)\n\nCloses #42
❌ fix: resolve foo\n\nFixes #42
❌ fix: resolve foo\n\nResolves #42
✅ fix: resolve foo (#42)
✅ fix: resolve foo — Refs #42
```

**為什麼禁止**：

1. **Auto-close 繞過 `idd-close` 的 Step 0 Checklist Gate Check**。GitHub 直接把 issue closed，`idd-close` 從未執行，沒人驗收 `Strategy` / `Implementation Plan` 的 checkbox 狀態——這違反 v2.17.0 的核心契約「沒打勾就不關」。
2. **沒有 Closing Summary**。auto-close 只改 issue state，不 post 任何 comment。3 個月後回來看 issue 只會看到 diagnosis + implementation plan，然後突然 closed——沒有 Solution / Verification / Root Cause 的最終紀錄。
3. **Issue 流程的 audit trail 斷裂**。IDD 的承諾是「每個 issue 都有 verified resolution」。auto-close 跳過這層驗證，變成「實作完就算結案」，退化成純 GitHub workflow。

### 正確的 close 流程

close 一律透過 `/idd-close #NNN` skill 走：

1. `idd-close` Step 0 掃 checklist gate
2. 若有未勾 todo → refuse（v2.17.0 行為）
3. 若全部勾完 → post Closing Summary
4. 最後由 skill 呼叫 `gh issue close` 關閉

這樣 gate 和 summary 都有保障，而且 issue 仍然會被實際關掉。

### 如果不小心用了 trailer 怎麼辦

1. Push 之後 GitHub 立刻 auto-close — 來不及挽救
2. 補救做法：
   - 仍然走 `/idd-close` 的精神，用 retroactive mode：post 一個標明 `(retroactive — auto-closed via Closes trailer)` 的 Closing Summary，確保 audit trail 完整
   - 不要 reopen → re-close，這是 noise
3. Amend commit 拿掉 trailer 只在 **commit 尚未 push** 時可行；push 之後 trailer 的 side effect（auto-close）無法 undo

**歷史脈絡**：`Closes` trailer 看起來很方便，#1/#2/#6 的 zombie issue 就是因為**沒用** trailer 而堆積 26 天。但 v2.17.0 introduced gate check 後，trailer 的「方便」變成了 gate bypass。正確的合成：**用 skill 關 issue**，skill 會負責既 enforce gate 又實際 close 掉（透過 `gh issue close`），兩全其美。

## Auto-Update

Implementation comment 完成後，自動執行 `idd-update` 更新 issue body 的 Current Status（phase → `implemented`）。

## Next Step

實作完成後，進入 `verify`：

```
/issue-driven-dev:idd-verify #NNN
```
