---
name: idd-edit
description: |
  編輯既有 GitHub issue comment。支援 append/replace/prepend-note 三種 mode。
  必 show 原 body + preview 新 body 讓 user confirm。用 `gh api -F body=@file` 避免 backtick escape bug。
  支援 batch mode（v2.34.0+）：多個 comment 套同一段 edit（如 `comment:NNN comment:MMM --replace --body '...'`），每個 comment 仍 per-confirm。
  Use when: 補既有 comment 說明（如圖片下方解釋）、修 typo、標示「此 comment 已被後續 errata 修正」。
  防止的失敗：手動 `gh api PATCH` 字串 escape 錯誤、誤覆蓋未 backup 的原內容。
argument-hint: "comment:<id>[ comment:<id>...]|#issue --last [--append|--replace|--prepend-note] [--body=\"...\"] (multi-comment = batch)"
allowed-tools:
  - Bash(gh:*)
  - Read
  - Write
---

# /idd-edit — Edit existing issue comment

解決手動 `gh api PATCH` 的痛點：字串 escape（backtick 常炸）、容易誤覆蓋、沒 audit trail。

## 核心原則

> Edit 是破壞性動作。**原 body 必 backup，新 body 必 preview，修改必留 metadata**。

## Batch mode（v2.34.0+）

`idd-edit comment:NNN comment:MMM --replace --body '...'` 把同一段內容套到多個 comment。Edit 是破壞性動作，batch 把破壞範圍放大 N 倍 — preview + per-comment confirm 仍照舊（不允許 `--yes-to-all`），但每個 confirm 後就推進，不需要 N 次重打命令。

完整契約見 [batch-and-cluster.md](../../references/batch-and-cluster.md)。罕見場景：跨 issue 的 typo 統一修、補同一段 errata note、把多個 stale comment 統一標 deprecated。

## When to use `idd-issue` multi-finding mode instead（v2.55.0+）

如果你要做的是「**從一個 source 文件抽多個 findings,部分 edit 既存 issue body**」(典型場景:transcript 含 5 個對既存 issues body 的修正,e.g. 「H4 hypothesis 重新表述」「reputation 變 core IV 改 framing」),**不要**手動跑 `idd-edit` 多次,改用 `idd-issue` multi-finding mode:

```bash
idd-issue source.docx       # auto-trigger when source contains ≥2 findings
```

差別:

| 情境 | 用 idd-edit | 用 idd-issue multi-finding mode |
|------|------------|-------------------------------|
| 已知 N 個 comment 套同一段 edit | ✅ batch mode | overkill |
| 從 source 文件分流多 finding,部分 edit body / 部分 comment / 部分 new | 5+ 次 invoke + 失 audit trail | ✅ 一次 invoke + Stage 2 picker 對每筆選 routing intent(`comment` / `edit body` / `update status`) |
| 需要 per-action footer 連結回 source | 手動加 | ✅ 自動加 |

完整 multi-finding mode 契約見 `idd-issue` SKILL.md `## Multi-finding source mode` 段落。

## 三種 Edit Mode

| Mode | 動作 | 原 body | 適用 |
|------|------|--------|------|
| `--append` | 在末尾加 `---\n**Edit YYYY-MM-DD**: {reason}\n\n{body}` | 保留 | 補充 / 更正（保留歷史） |
| `--replace` | 完全替換 body | 寫入 backup 檔 | 大幅改寫（如補圖說明） |
| `--prepend-note` | 在最上方加 `> ⚠️ {reason}\n\n---\n\n` | 保留 | 標示「此 comment 已過時」（errata flow 用） |

## Configuration

按 [config-protocol](../../references/config-protocol.md) 解析 target repo:

- `--repo owner/repo` flag → per-invocation override
- Walk-up `.claude/issue-driven-dev.local.json`(從 cwd 往上找)
- Path / git predicates 自動匹配

**Group/predicate 行為**:`idd-edit` 操作既存 comment,只用 path/git 類 predicate。Group config 會 fall through 到 primary repo。

## Target Comment 指定方式

兩種都支援（方便 AI 編輯）：

| 語法 | 意義 |
|------|------|
| `comment:<numeric-id>` | 直接用 GitHub comment ID（從 URL 尾部 `#issuecomment-<id>` 取） |
| `#NNN --last` | issue #NNN 的**最後一個** comment |
| `#NNN` | issue #NNN → 列出所有 comments 讓使用者選（AskUserQuestion） |

## Execution

### Step 0: Bootstrap Stage Task List（強制)

**在動任何事之前**先用 `TaskCreate` 為這個 stage 建 todo list,確保每個 sub-step 都被追蹤:

```
TaskCreate(name="parse_and_resolve_target", description="Parse comment:<id> 或 #NNN [--last] 並解析出實際 COMMENT_ID")
TaskCreate(name="fetch_body_and_backup", description="gh api 取現 body 並寫入 /tmp/idd-edit-backup/comment-<id>-<ts>.md")
TaskCreate(name="show_original", description="顯示原 comment 前 30 行讓使用者看清楚要動什麼")
TaskCreate(name="build_new_body", description="按 mode（append / replace / prepend-note）組新 body 字串")
TaskCreate(name="preview_and_confirm", description="顯示新 body 並用 AskUserQuestion 確認；--replace 模式必須通過")
TaskCreate(name="execute_patch", description="gh api PATCH /repos/.../issues/comments/<id> 用 -F body=@file 避免 escape")
TaskCreate(name="verify_and_report", description="re-fetch comment 比對寫入結果，輸出 ✓ Edit applied + diff summary")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。**TaskCreate 清單 = 真實的步驟清單；任何寫在 skill 裡但沒列進 TaskCreate 的步驟，都視為 skill 的 bug，必須補進 Task 清單。**

特別提醒：**idd-edit 是破壞性動作**，每一步都必須在 task list 留痕。`fetch_body_and_backup` 跳過 = 沒有 backup，誤改後無法復原；`preview_and_confirm` 跳過 = 跳過使用者把關。

---

### Step 1: Parse arguments + resolve target

```bash
# 解析 target
if [[ "$ARG" == comment:* ]]; then
    COMMENT_ID=${ARG#comment:}
elif [[ "$ARG" == \#* ]]; then
    ISSUE_NUMBER=${ARG#\#}
    if [[ "$LAST" == "true" ]]; then
        # 取最後一個 comment id
        COMMENT_ID=$(gh api repos/$GITHUB_REPO/issues/$ISSUE_NUMBER/comments --jq '.[-1].id')
    else
        # 列出供使用者選
        gh api repos/$GITHUB_REPO/issues/$ISSUE_NUMBER/comments \
          --jq '.[] | "\(.id) | \(.created_at) | \(.body | .[0:80])"'
        # 用 AskUserQuestion 選
    fi
fi
```

### Step 2: Fetch current body + backup

```bash
mkdir -p /tmp/idd-edit-backup
BACKUP_FILE="/tmp/idd-edit-backup/comment-${COMMENT_ID}-$(date +%s).md"

gh api repos/$GITHUB_REPO/issues/comments/$COMMENT_ID --jq '.body' > "$BACKUP_FILE"

echo "✓ Backup: $BACKUP_FILE"
```

### Step 3: Show original body

```
=== Original comment (ID: $COMMENT_ID) ===
{首 30 行 + "..."}
===
```

### Step 4: Build new body per mode

#### Mode: `--append`

```bash
NEW_BODY="$(cat $BACKUP_FILE)

---

**Edit $(date +%Y-%m-%d)**: $REASON

$APPEND_BODY

<!-- idd:edit mode=append date=$(date +%Y-%m-%d) -->"
```

#### Mode: `--replace`

```bash
NEW_BODY="$REPLACE_BODY

<!-- idd:edit mode=replace date=$(date +%Y-%m-%d) backup=$BACKUP_FILE -->"
```

**警告**：`--replace` 完全覆蓋原 body。必顯示 diff preview，使用者確認後才 PATCH。

#### Mode: `--prepend-note`

```bash
NEW_BODY="> ⚠️ **Edit $(date +%Y-%m-%d)**: $REASON

---

$(cat $BACKUP_FILE)

<!-- idd:edit mode=prepend-note date=$(date +%Y-%m-%d) -->"
```

### Step 5: Preview + confirm

```
=== Preview (new body, mode: $MODE) ===
{首 40 行 + "..."}
===

Confirm edit? (y/n)
```

使用 AskUserQuestion。預設 NO（破壞性動作）。

### Step 6: Execute PATCH

**關鍵**：用 `-F body=@file`（不是 `-f body=""`）避免 backtick / 多行字串的 escape bug。

```bash
TMP_BODY_FILE="/tmp/idd-edit-new-${COMMENT_ID}.md"
echo "$NEW_BODY" > "$TMP_BODY_FILE"

gh api repos/$GITHUB_REPO/issues/comments/$COMMENT_ID \
    -X PATCH \
    -F body=@"$TMP_BODY_FILE"

rm "$TMP_BODY_FILE"
```

### Step 7: Verify edit + report

```bash
# Re-fetch 確認
UPDATED=$(gh api repos/$GITHUB_REPO/issues/comments/$COMMENT_ID --jq '.body' | head -5)
echo "✓ Comment updated"
echo "  URL: $(gh api repos/$GITHUB_REPO/issues/comments/$COMMENT_ID --jq '.html_url')"
echo "  Backup: $BACKUP_FILE"
echo "  First 5 lines of new body: $UPDATED"
```

## Metadata Marker

每次 edit 在 body 加 HTML comment：

```html
<!-- idd:edit mode=<mode> date=<date> [backup=<path>] -->
```

多次 edit 會 **append 多個 marker**（不覆蓋前次），形成 edit history。

## 使用範例

### 補既有 comment 的圖片說明（剛才 #13 的痛點）

```
/idd-edit comment:4241327867 --replace \
  --body-file=/tmp/new-implementation-summary.md \
  --reason="依新 skill 規則補圖下方資料/統計/結論說明"
```

### 修 typo

```
/idd-edit #18 --last --append \
  --body="修正：上一段 frac_p<.05=57.5% 應為 56.3%（重跑後更新）" \
  --reason="p-value 計算誤差"
```

### 標記 comment 已過時（errata flow）

```
/idd-edit comment:4241327867 --prepend-note \
  --reason="See errata at https://github.com/.../issuecomment-4241609713 — Holm 校正後結論不同"
```

## 鐵律

- **原 body 必 backup**：存到 `/tmp/idd-edit-backup/` 保留 7 天（或 session 結束）
- **Preview 必 show**：即使是 `--append` 也要 show 最終 body 讓使用者確認
- **`-F body=@file` 不是 `-f body=""`**：避免 backtick escape（`gh api` 會把 heredoc 裡的 backtick escape 成 `\`）
- **Metadata marker 不覆蓋**：每次 edit 加新 marker，保留 history
- **`--replace` 預設 confirm = NO**：破壞性動作不自動 yes
- **Log 每次 edit**：顯示 URL 讓使用者能立即 verify

## 與 idd-comment 的配合

**errata flow**（idd-comment --type=errata 會自動 trigger 這裡）：

```
使用者 /idd-comment #NNN --type=errata --target-comment=XXX --body="..."
  ↓
idd-comment 建立 errata comment
  ↓
idd-comment 自動 call: /idd-edit comment:XXX --prepend-note --reason="See errata at <URL>"
  ↓
Target comment 頂部加警示「⚠️ See errata below」
```

## Backup 管理

```bash
# 列出所有 backup
ls -la /tmp/idd-edit-backup/

# 回復某次 edit
gh api repos/$GITHUB_REPO/issues/comments/<id> \
    -X PATCH \
    -F body=@/tmp/idd-edit-backup/comment-<id>-<timestamp>.md
```

backup 檔案命名：`comment-<id>-<unix-timestamp>.md`，方便 time-series 追溯。

## Next Step

Edit 後通常不需要後續 skill。如果是修 diagnosis comment，可能要重跑 `/idd-verify`。
如果是 errata flow，由 `/idd-comment` 統一 orchestrate。
