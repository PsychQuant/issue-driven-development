---
name: idd-issue
description: |
  建立 well-documented GitHub Issue。每個改動的起點。
  Use when: 報 bug、追蹤需求、任何需要正式記錄的工作。
  防止的失敗：改了東西卻沒有文件記錄「為什麼改」。
argument-hint: "[description or path to .docx]"
allowed-tools:
  - Bash(gh:*)
  - Bash(cp:*)
  - Bash(ls:*)
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
---

# /issue — 定義問題

每個改動都從 issue 開始。Issue 是人和 AI 的介面。

## Configuration

讀取 `.claude/issue-driven-dev.local.md` frontmatter：

```yaml
---
github_repo: "owner/repo"
github_owner: "owner"
attachments_release: "attachments"
---
```

**如果不存在，進入 fork-aware 偵測流程**（見 Step 0.5）。偵測結果會寫回 config，之後不再詢問。

### Fork-aware Target Selection（為什麼）

Fork 有兩種相反的使用情境：

| 情境 | 正確 target |
|------|------------|
| **Contributor fork** — 要回饋上游、報 bug、提問 | upstream |
| **Customization fork** — fork 下來自己用、記個人 TODO | own fork |
| **Divergent fork** — 路線分岔後變成自己的專案 | own fork |

硬性預設任何一邊都會錯一半情境。所以第一次執行必須**強制讓使用者選**，然後記住。

## Execution

### Step 0: Bootstrap Stage Task List（強制)

**在動任何事之前**先用 `TaskCreate` 為這個 stage 建 todo list,確保每個 sub-step 都被追蹤:

```
TaskCreate(name="detect_target_repo", description="Step 0.5: 讀 config,若無則偵測 fork 並讓使用者選 target repo(upstream/own fork/both)")
TaskCreate(name="read_source", description="讀取來源(docx → mcp__che-word-mcp 讀文字 + 列圖片)")
TaskCreate(name="gather_info", description="蒐集 title / type / priority / description")
TaskCreate(name="create_issue", description="gh issue create(或文件來源時批次建多個)")
TaskCreate(name="attach_images", description="上傳圖片到 attachments release 並編輯 issue body 嵌入(若有)")
TaskCreate(name="create_milestone", description="來源為文件時自動建立 milestone 並指派(見 Step 4.5)")
TaskCreate(name="report_and_stop", description="回報 issue number/URL,停下等使用者決定下一步")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。中途若發現要分更多 sub-tasks(例如批次建 10+ issues),用 `TaskCreate` 補加。

**為什麼**:確保文件來源等多要點情境,「建 issue」→「建 milestone」→「上傳圖片」→「指派 issues」等步驟不會漏掉。歷史上看到「建完 issue 忘了建 milestone」的錯誤(見 idd-issue 2.18.0 之前的 5 個 source-file labels 全部沒 milestone 的 incident)。

---

### Step 0.5: 偵測並確認 Target Repo（fork-aware）

**Step 1 ~ 5 使用的 `$GITHUB_REPO` 必須在這一步決定。不可在沒有 config 時靜默 fallback 成 origin。**

#### A. 如果 `.claude/issue-driven-dev.local.md` 已存在

直接讀 `github_repo` / `github_owner` / `attachments_release`，進入 Step 1。不詢問、不偵測。

#### B. 如果 config 不存在 → 偵測 + 詢問

```bash
# 1. 拿到 origin 的 owner/repo
ORIGIN=$(git remote get-url origin 2>/dev/null | sed -E 's#.*[:/]([^/]+/[^/]+)(\.git)?$#\1#')

# 2. 查 origin 是不是 fork，以及 upstream 是誰
REPO_JSON=$(gh repo view "$ORIGIN" --json isFork,parent 2>/dev/null)
IS_FORK=$(echo "$REPO_JSON" | jq -r '.isFork')
UPSTREAM=$(echo "$REPO_JSON" | jq -r '.parent.nameWithOwner // empty')
```

#### C. 根據偵測結果決定流程

**C1. `IS_FORK=false`（不是 fork）**

直接用 origin，寫入 config，繼續。不需要詢問。

**C2. `IS_FORK=true` 且 `UPSTREAM` 存在** → **強制使用 `AskUserQuestion` 呈現三選項**：

| 選項 | target | 適合情境 |
|------|--------|---------|
| **Upstream** (`$UPSTREAM`) | upstream | Bug report、feature 提議、跟原作者討論架構、PR 先行討論 |
| **Own fork** (`$ORIGIN`) | origin | 個人 TODO、客製化筆記、只給自己看的追蹤、路線分岔後的獨立專案 |
| **Both (cross-linked)** | upstream 主 + origin 追蹤 | 想貢獻上游但同時要在自己 fork 記錄進度 |

「Both」模式：先在 upstream 建主 issue，拿到 `#N`，然後在 origin 建追蹤 issue，body 首行加 `Tracking upstream: owner/repo#N`，並在 upstream issue 留 comment 反向連結 origin issue。

#### D. 寫回 config

無論 C1/C2/C3 選了什麼，都把結果寫入 `.claude/issue-driven-dev.local.md`：

```yaml
---
github_repo: "chosen/repo"
github_owner: "chosen"
attachments_release: "attachments"
# Optional, only for Both mode:
tracking_repo: "origin/fork"
---
```

下次執行時走 A 路徑，不再詢問。

#### E. 使用者想改變 target

直接編輯 `.claude/issue-driven-dev.local.md`，或刪掉讓 skill 重新問一次。

---

### Step 1: 讀取來源（如果是 .docx）

```
mcp__che-word-mcp__get_document_text(source_path: "path")
mcp__che-word-mcp__list_images(source_path: "path")
```

### Step 2: 蒐集資訊

缺少的話詢問使用者：

1. **Title** — 一句話描述問題
2. **Type** — bug / feature / refactor / docs
3. **Priority** — P0（立即）/ P1（本週）/ P2（排程）/ P3（有空再做）
4. **Description** — 問題描述（bug: 重現步驟 + expected + actual；feature: 需求 + 目的）

### Step 3: 建立 Issue

```bash
gh issue create \
  --repo $GITHUB_REPO \
  --title "$TITLE" \
  --body "$(cat <<'EOF'
## Problem

> **Original text**:
> 「...exact original text...」
> — Source: {source}

{Plain language interpretation}

## Type
{bug / feature / refactor / docs}

## Expected
...

## Actual
...

## Impact
...
EOF
)" \
  --label "$TYPE"
```

> **CRITICAL**: 來自文件的 issue **必須**逐字引用原文。AI 摘要會失真，原文是唯一不會漂移的東西。

> **CRITICAL**: 所有原文引用**必須**使用 blockquote（`>`）格式。不論出現在 issue body 或 comment 中，只要是逐字引用的原文，都要用 `>` 包住整段。這是審計軌跡，必須在視覺上與分析/解讀明確區分。

> **數學公式格式**：GitHub 支援 `$...$`（inline）和 `$$...$$`（display）。含底線的程式變數名**不放 math mode**，改用 backtick code。混合寫法：`$R_I = J \cdot$` `` `mse_info` ``。

### Step 4: 附加圖片（如果有）

```bash
# 確保 attachments release 存在
gh release view $ATTACHMENTS_RELEASE --repo $GITHUB_REPO 2>/dev/null || \
  gh release create $ATTACHMENTS_RELEASE --repo $GITHUB_REPO \
    --title "Attachments" --notes "Issue attachments and figures"

# 上傳圖片到 release
gh release upload $ATTACHMENTS_RELEASE issue_${NUMBER}_${DESC}.png \
  --repo $GITHUB_REPO --clobber

# 圖片 URL 格式（private 和 public repo 都適用）
# https://github.com/$GITHUB_REPO/releases/download/$ATTACHMENTS_RELEASE/issue_${NUMBER}_${DESC}.png

# 編輯 issue body 加入圖片連結
gh issue edit $NUMBER --repo $GITHUB_REPO --body "..."
```

> **Private repo 圖片渲染**：Release asset URL 在 issue/comment 的 markdown 中可以正常渲染，前提是查看者是 repo 的 collaborator 且已登入 GitHub。不需要把 repo 改成 public。

### Step 4.5: 自動建立 Milestone（來源為文件時）

當來源是一整個文件（.docx 等），所有 issues 建完後自動建立 milestone 並指派：

```bash
# 從檔案名稱或文件標題推導 milestone 名稱
# 例：「網站調整內容.docx」→ milestone 名稱問使用者，預設用文件標題

# 建立 milestone
gh api repos/$GITHUB_REPO/milestones \
  -f title="$MILESTONE_NAME" \
  -f description="來源：$SOURCE_FILE — $ISSUE_COUNT 個 issues (#first-#last)" \
  -f state="open"

# 所有剛建立的 issues 都指派到此 milestone
for n in $ALL_ISSUE_NUMBERS; do
  gh issue edit $n --repo $GITHUB_REPO --milestone "$MILESTONE_NAME"
done
```

**觸發條件**：來源為文件（.docx, .pdf, .md 等）且建立了 2 個以上 issues。
**命名**：優先用文件內的主標題，沒有則問使用者。
**不觸發**：單一 issue 或非文件來源。

### Step 5: 回報並停止

輸出：issue number、URL、labels、type。
如果有 milestone：輸出 milestone name、URL、issue count。

提示下一步：`/issue-driven-dev:idd-diagnose #NNN`

> **CRITICAL: 建立 issue 後必須停止。不要自動開始 diagnose 或 implement。**
> Issue 建立是人的決定點 — 人決定優先級、分配、時機。
> AI 不應該擅自開始解決問題。等使用者明確說「開始做」或呼叫 `idd-diagnose` 才繼續。

## 來源文件規則

### One Point = One Issue

- **每個要點**獨立建一個 issue
- **不合併** — 類似主題也分開
- **不跳過** — 重複可以之後關，遺漏 = 遺忘
- 處理完畢後驗證：`文件要點數 == 建立的 issue 數`

## Next Step

建立 issue 後，進入 `diagnose`：

```
/issue-driven-dev:idd-diagnose #NNN
```
