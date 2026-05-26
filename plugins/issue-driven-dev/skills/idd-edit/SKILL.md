---
name: idd-edit
description: |
  編輯既有 GitHub issue comment。支援 append/replace/prepend-note 三種 mode。
  必 show 原 body + preview 新 body 讓 user confirm。用 `gh api -F body=@file` 避免 backtick escape bug。
  支援 batch mode（v2.34.0+）：多個 comment 套同一段 edit（如 `comment:NNN comment:MMM --replace --body '...'`），每個 comment 仍 per-confirm。
  Use when: 補既有 comment 說明（如圖片下方解釋）、修 typo、標示「此 comment 已被後續 errata 修正」。
  防止的失敗：手動 `gh api PATCH` 字串 escape 錯誤、誤覆蓋未 backup 的原內容。
argument-hint: "comment:<id>[ comment:<id>...]|#issue --last (--append|--replace [--scope whole-comment|--section <heading>]|--prepend-note) [--body=... | --body-file=...] [--reason=...] [--override-user-content --reason='...']"
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

`idd-edit comment:NNN comment:MMM --replace --scope whole-comment --body '...'` 把同一段內容套到多個 comment。Edit 是破壞性動作，batch 把破壞範圍放大 N 倍 — preview + per-comment confirm 仍照舊（不允許 `--yes-to-all`），但每個 confirm 後就推進，不需要 N 次重打命令。

**v2.75.0+ R4/R5 在 batch mode 下 per-target 評估**:
- R4 (`--replace` 必要 scope) 一次套用全 batch
- R5 (author check) **per-target**:N 個 targets 若 mixed OWNER + non-OWNER,目前 single-target 邏輯 refuse 第一個 non-OWNER target 並印 hint;`--override-user-content` 套用所有 targets(全 batch 啟用 override)
- 完整 batch + R5 semantics (per-comment refuse vs transactional abort vs pre-flight scan) 設計 deferred to **[#158](https://github.com/PsychQuant/issue-driven-development/issues/158)** follow-up

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

| Mode | 動作 | 原 body | 適用 | 強制 flags |
|------|------|--------|------|-----------|
| `--append` | 在末尾加 `---\n**Edit YYYY-MM-DD**: {reason}\n\n{body}` | 保留 | 補充 / 更正（保留歷史） | `--reason` |
| `--replace` | 完全替換 body 或指定 section | 寫入 backup 檔 | 大幅改寫（如補圖說明） | `--reason` + **`--scope whole-comment` OR `--section <heading>`**（R4 enforced）|
| `--prepend-note` | 在最上方加 `> ⚠️ {reason}\n\n---\n\n` | 保留 | 標示「此 comment 已過時」（errata flow 用） | `--reason` |

## 動作分類 (per [`#150` action-scoped modify discipline](../../rules/append-vs-modify.md))

| Mode | Category | Scope contract |
|------|----------|---------------|
| `--append` | `audit-block-append` | trailing block,inherently bounded — no `--scope` needed |
| `--replace --scope whole-comment` | `bounded-section-replace` | scope = whole comment(explicit acknowledgment of full overwrite）|
| `--replace --section <heading>` | `bounded-section-replace` | scope = named markdown subsection only |
| `--prepend-note` | `audit-block-append` | leading errata marker,inherently bounded — no `--scope` needed |

## Runtime gates (#154, v2.75.0+)

`/idd-edit` enforces 2 SHALL requirements at runtime via `plugins/issue-driven-dev/scripts/idd-edit-helper.sh` (extracted parser + validator per #154 to avoid R1/R2/R3-style bash inline bugs):

| Requirement | Gate | Refuse code |
|-------------|------|-------------|
| **R4** (spec) | `--replace` without `--scope`/`--section` → refuse | exit 3 |
| **R5** (spec) | Comment author non-OWNER non-bot,無 `--override-user-content --reason="..."` → refuse | exit 4 |

Override pathway:`--override-user-content --reason="<rationale>"` 顯式同意修改 user content。 Audit marker `<!-- idd:edit override-user-content date=... reason="..." -->` 自動 append。

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

### Step 1: Parse arguments via helper (R4 gate enforced)

**v2.75.0+ (#154)**: Parser extracted to `plugins/issue-driven-dev/scripts/idd-edit-helper.sh parse-args` per [`#154`](https://github.com/PsychQuant/issue-driven-development/issues/154) (R1/R2/R3 bash-inline failure on PR #153 → 3-iteration verify cycle showed AI-generated inline parsers introduce bugs each pass). Helper provides positional shift + missing-value guards + eq-form support + body-file readability check + R4 gate refuse + R5 override-reason pair guard, all unit-tested via `plugins/issue-driven-dev/scripts/tests/idd-edit/` 23 fixtures.

```bash
# Parse + R4 gate (refuse if --replace lacks --scope/--section)
# CRITICAL: split stdout (eval-safe assignments) from stderr (diagnostic text).
# Closes #154 verify Round 1 H2 — previously used `2>&1` which mixed
# stderr (potentially containing $() from cat-on-directory failure etc.)
# into the eval input, defeating printf %q quoting safety.
PARSE_ERR_FILE="/tmp/idd-edit-parse-err-$$"
PARSE_OUT=$(bash $CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.sh parse-args "$@" 2>"$PARSE_ERR_FILE")
PARSE_EXIT=$?
PARSE_ERR=$(cat "$PARSE_ERR_FILE")
rm -f "$PARSE_ERR_FILE"

case $PARSE_EXIT in
  0) eval "$PARSE_OUT" ;;   # imports MODE/SCOPE_FLAG/SECTION_FLAG/BODY_INPUT/etc.
  3) echo "$PARSE_ERR" >&2; exit 3 ;;   # R4 refuse — actionable message
  *) echo "$PARSE_ERR" >&2; exit $PARSE_EXIT ;;
esac

# Resolve TARGETS array → RESOLVED_COMMENT_IDS array (one entry per comment to edit).
# Closes R2 H7 (#154 Round 2): previously this loop closed BEFORE Steps 1.5-7,
# so batch mode `comment:NNN comment:MMM` silently only processed the LAST target.
# Fix: resolution loop accumulates; per-target processing happens in OUTER loop
# wrapping Steps 1.5 through 7 (see "Per-target outer loop" note below).
RESOLVED_COMMENT_IDS=()
for target in "${TARGETS[@]}"; do
    local id=""
    case "$target" in
        comment:*)
            id="${target#comment:}"
            ;;
        \#*)
            ISSUE_NUMBER="${target#\#}"
            # Validate issue number is numeric before substitution into gh api URL
            [[ "$ISSUE_NUMBER" =~ ^[0-9]+$ ]] || { echo "ERROR: invalid issue number: $ISSUE_NUMBER" >&2; exit 2; }
            if [ "$LAST" = "true" ]; then
                id=$(gh api repos/$REPO/issues/$ISSUE_NUMBER/comments --jq '.[-1].id')
            else
                gh api repos/$REPO/issues/$ISSUE_NUMBER/comments \
                  --jq '.[] | "\(.id) | \(.created_at) | \(.body | .[0:80])"'
                # Use AskUserQuestion to select → id="<selected-id>"
            fi
            ;;
    esac

    # R4/R5 security gate: id MUST be numeric before any URL / filename substitution.
    # Closes #154 verify finding C2 — unsanitized id flows into:
    #   - gh api repos/.../comments/$id (REST path traversal)
    #   - /tmp/idd-edit-repl-${id}.md (arbitrary local file write via embedded `/` + `..`)
    [[ "$id" =~ ^[0-9]+$ ]] || { echo "ERROR: invalid comment ID (must be numeric): $id" >&2; exit 2; }

    RESOLVED_COMMENT_IDS+=("$id")
done
```

#### Per-target outer loop (wraps Steps 1.5 — 7)

**v2.75.0+ (#154 R3 fix for H7)**: Each resolved comment ID runs through the full pipeline (validate → fetch → preview → confirm → PATCH → verify) independently. Batch mode = N iterations of the same sequence, per-comment confirmation discipline preserved.

```bash
for COMMENT_ID in "${RESOLVED_COMMENT_IDS[@]}"; do
    # === Steps 1.5 through 7 run here, per-target ===
    # The bash blocks below show single-target templates; in batch mode
    # they execute N times, once per resolved COMMENT_ID.
    # ...
done
```
```

### Step 1.5: Validate target (R5 author gate)

**v2.75.0+ (#154)**: R5 gate refuses modifications to user-authored comments (non-OWNER non-bot) unless `--override-user-content --reason="..."` provided。 Helper does single `gh api` call,checks `author_association` + `user.login`,applies bot allowlist (`*[bot]` pattern + `OWNER` passthrough)。

```bash
bash $CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.sh \
    validate-target "$COMMENT_ID" "$REPO" "$OVERRIDE_USER_CONTENT"
VALIDATE_EXIT=$?
case $VALIDATE_EXIT in
  0) ;;   # proceed (OWNER, bot, or override active)
  4)
    # R5 refuse — actionable message already on stderr
    # If called from /idd-comment errata flow: print additional helpful hint
    if [ "${IDD_CALLER:-}" = "idd-comment-errata" ]; then
      echo "" >&2
      echo "Hint: errata target was user-authored; manually run:" >&2
      echo "  /idd-edit comment:$COMMENT_ID --prepend-note --override-user-content --reason='errata clarification per IDD discipline'" >&2
    fi
    exit 4
    ;;
  *) exit $VALIDATE_EXIT ;;
esac
```

### Step 2: Fetch current body + backup

```bash
mkdir -p /tmp/idd-edit-backup
BACKUP_FILE="/tmp/idd-edit-backup/comment-${COMMENT_ID}-$(date +%s).md"

gh api repos/$REPO/issues/comments/$COMMENT_ID --jq '.body' > "$BACKUP_FILE"

echo "✓ Backup: $BACKUP_FILE"
```

### Step 3: Show original body

```
=== Original comment (ID: $COMMENT_ID) ===
{首 30 行 + "..."}
===
```

### Step 4: Build new body per mode

> **v2.75.0+ (#154)**: audit markers are built via `bash $CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.sh emit-audit-marker` — centralizes HTML-comment-escape (`-->` stripping) so attacker-controlled `$REASON` / `$SECTION_FLAG` cannot forge audit trail (closes #154 verify finding C3).

#### Mode: `--append`

```bash
EDIT_MARKER=$(bash $CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.sh emit-audit-marker edit mode=append)
NEW_BODY="$(cat $BACKUP_FILE)

---

**Edit $(date +%Y-%m-%d)**: $REASON

$BODY_INPUT

$EDIT_MARKER"

# Append R5 override audit marker if applicable
if [ "$OVERRIDE_USER_CONTENT" = "true" ]; then
    OVERRIDE_MARKER=$(bash $CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.sh emit-audit-marker override mode=append reason="$REASON")
    NEW_BODY="$NEW_BODY

$OVERRIDE_MARKER"
fi
```

#### Mode: `--replace`

R4 gate already enforced in Step 1 — `SCOPE_FLAG` or `SECTION_FLAG` is guaranteed non-empty here.

```bash
if [ "$SCOPE_FLAG" = "whole-comment" ]; then
    # Whole-comment replacement
    EDIT_MARKER=$(bash $CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.sh emit-audit-marker edit mode=replace scope=whole-comment backup="$BACKUP_FILE")
    NEW_BODY="$BODY_INPUT

$EDIT_MARKER"
elif [ -n "$SECTION_FLAG" ]; then
    # Named section replacement via getline pattern (closes R3 C3 BSD awk newline reject)
    REPL_FILE="/tmp/idd-edit-repl-${COMMENT_ID}.md"
    echo "$BODY_INPUT" > "$REPL_FILE"
    NEW_BODY=$(bash $CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.sh \
                  section-replace "$BACKUP_FILE" "$SECTION_FLAG" "$REPL_FILE")
    rm -f "$REPL_FILE"
    EDIT_MARKER=$(bash $CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.sh emit-audit-marker edit mode=replace section="$SECTION_FLAG" backup="$BACKUP_FILE")
    NEW_BODY="$NEW_BODY

$EDIT_MARKER"
fi

# Append R5 override audit marker if applicable
if [ "$OVERRIDE_USER_CONTENT" = "true" ]; then
    OVERRIDE_MARKER=$(bash $CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.sh emit-audit-marker override mode=replace reason="$REASON")
    NEW_BODY="$NEW_BODY

$OVERRIDE_MARKER"
fi
```

**警告**：`--replace` 是 `bounded-section-replace` 動作（per [#150 rule](../../rules/append-vs-modify.md)）。必顯示 diff preview，使用者確認後才 PATCH。 R4 強制 `--scope`/`--section` 避免「忘記講動作範圍 = 全 comment overwrite」silent footgun。

#### Mode: `--prepend-note`

```bash
EDIT_MARKER=$(bash $CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.sh emit-audit-marker edit mode=prepend-note)
NEW_BODY="> ⚠️ **Edit $(date +%Y-%m-%d)**: $REASON

---

$(cat $BACKUP_FILE)

$EDIT_MARKER"

# Append R5 override audit marker if applicable
if [ "$OVERRIDE_USER_CONTENT" = "true" ]; then
    OVERRIDE_MARKER=$(bash $CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.sh emit-audit-marker override mode=prepend-note reason="$REASON")
    NEW_BODY="$NEW_BODY

$OVERRIDE_MARKER"
fi
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

gh api repos/$REPO/issues/comments/$COMMENT_ID \
    -X PATCH \
    -F body=@"$TMP_BODY_FILE"

rm "$TMP_BODY_FILE"
```

### Step 7: Verify edit + report

```bash
# Re-fetch 確認
UPDATED=$(gh api repos/$REPO/issues/comments/$COMMENT_ID --jq '.body' | head -5)
echo "✓ Comment updated"
echo "  URL: $(gh api repos/$REPO/issues/comments/$COMMENT_ID --jq '.html_url')"
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

### 補既有 comment 的圖片說明（自己發的 comment,whole-comment scope）

```
/idd-edit comment:4241327867 --replace \
  --scope whole-comment \
  --body-file=/tmp/new-implementation-summary.md \
  --reason="依新 skill 規則補圖下方資料/統計/結論說明"
```

### 修 typo（單 section replace）

```
/idd-edit #18 --last --append \
  --body="修正：上一段 frac_p<.05=57.5% 應為 56.3%（重跑後更新）" \
  --reason="p-value 計算誤差"
```

### 修 Diagnosis comment 內某 ### 區段（自己發的 comment）

```
/idd-edit comment:4530594011 --replace \
  --section="### Strategy" \
  --body-file=/tmp/new-strategy.md \
  --reason="重新拆 Block A → B 依賴順序"
```

### 標記 comment 已過時（errata flow,自己發的 comment）

```
/idd-edit comment:4241327867 --prepend-note \
  --reason="See errata at https://github.com/.../issuecomment-4241609713 — Holm 校正後結論不同"
```

### Errata 修別人發的 comment（需顯式 override）

R5 強制非 OWNER 非 bot comment 必須 explicit consent。 `/idd-comment --type=errata` auto-call 在 R5 refuse 時印 helpful message,指引你手動加 flag:

```
/idd-edit comment:9999999 --prepend-note \
  --override-user-content \
  --reason="errata clarification per IDD discipline — see new errata at <URL>"
```

Audit marker `<!-- idd:edit override-user-content date=... reason="..." -->` 自動 append 到 body 留 audit trail。

## 鐵律

- **原 body 必 backup**：存到 `/tmp/idd-edit-backup/` 保留 7 天（或 session 結束）
- **Preview 必 show**：即使是 `--append` 也要 show 最終 body 讓使用者確認
- **`-F body=@file` 不是 `-f body=""`**：避免 backtick escape（`gh api` 會把 heredoc 裡的 backtick escape 成 `\`）
- **Metadata marker 不覆蓋**：每次 edit 加新 marker，保留 history
- **`--replace` 預設 confirm = NO**：破壞性動作不自動 yes
- **Log 每次 edit**：顯示 URL 讓使用者能立即 verify
- **`--body-file` path 由 user 負責**（v2.75.0+ #154 H5）：helper 不限制路徑,`--body-file=/etc/passwd` 之類 absolute path 會被讀取並進入 PATCH body → public GitHub comment。 Preview gate 是最後一道防線。 未來增強:限制到 repo subtree 或 user-home(out of scope for #154)。 Programmatic caller(`/idd-comment` errata)若接受 user-supplied `--body-file` 必須先 validate path

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

# 回復某次 edit (set REPO=owner/repo first)
gh api repos/$REPO/issues/comments/<id> \
    -X PATCH \
    -F body=@/tmp/idd-edit-backup/comment-<id>-<timestamp>.md
```

backup 檔案命名：`comment-<id>-<unix-timestamp>.md`，方便 time-series 追溯。

## Next Step

Edit 後通常不需要後續 skill。如果是修 diagnosis comment，可能要重跑 `/idd-verify`。
如果是 errata flow，由 `/idd-comment` 統一 orchestrate。
