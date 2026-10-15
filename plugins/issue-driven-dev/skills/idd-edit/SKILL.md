---
name: idd-edit
description: |
  編輯既有 GitHub issue comment。支援 append/replace/prepend-note/correct 四種 mode；`--correct` 也能更正 issue 正文（`issue:<N>`，#351）。
  必 show 原 body + preview 新 body 讓 user confirm。用 `gh api -F body=@file` 避免 backtick escape bug。
  支援 batch mode（v2.34.0+）：多個 comment 套同一段 edit（如 `comment:NNN comment:MMM --replace --body '...'`），每個 comment 仍 per-confirm。
  Use when: 補既有 comment 說明（如圖片下方解釋）；內容有錯（打錯字、事實錯誤、被推翻的結論都算）→ `--correct` 就地取代（舊版歸檔、AI 讀不到）。
  防止的失敗：手動 `gh api PATCH` 字串 escape 錯誤、誤覆蓋未 backup 的原內容。
argument-hint: "comment:<id>[ comment:<id>...]|#issue --last|issue:<N> (--append|--replace [--scope whole-comment|--section <heading>]|--prepend-note|--correct (--scope whole-comment|--section <heading>)) [--body=... | --body-file=...] [--reason=...] [--override-user-content --reason='...']"
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

**v2.81.0+ R4/R5 在 batch mode 下 per-target 評估**:
- R4 (`--replace` 必要 scope) 一次套用全 batch
- R5 (author check) **per-target**:mixed OWNER + non-OWNER 批次採**語意 (i) per-comment refuse + 繼續**（#158 拍板 2026-07-11）— OWNER 的照做、non-OWNER 的逐條 refuse 記錄後 `continue`,絕不因單一 refuse 殺整批;`--override-user-content` 語意為 **all-targets + reason 共用**（全 batch 啟用 override,一個 reason 進所有 audit markers）
- 批次結束輸出 outcome report（`edited / refused` + 顯著標記,見 Step 7.5）;exit contract:全數成功 → 0,任一 refused（M>0 → exit 4,單 target 退化等價 — 契約鎖於 tests/idd-edit fixture 14）

完整契約見 [batch-and-cluster.md](../../references/batch-and-cluster.md)。罕見場景：跨 issue 的 typo 統一修、補同一段 errata note、把多個 stale comment 統一標 deprecated。

## When to use `idd-issue` multi-finding mode instead（v2.55.0+）

> **例外（#351）**：內容**確定是錯的**（打錯字、事實錯誤、被推翻的結論）一律走 `--correct`，不走 multi-finding 的 `edit body` —— 後者不歸檔、不檢查 Original text，錯的舊版會留在 AI 讀得到的地方。

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

## 四種 Edit Mode

| Mode | 動作 | 原 body | 適用 | 強制 flags |
|------|------|--------|------|-----------|
| `--append` | 在末尾加 `---\n**Edit YYYY-MM-DD**: {reason}\n\n{body}` | 保留 | 補充 / 更正（保留歷史） | `--reason` |
| `--replace` | 完全替換 body 或指定 section | 寫入 backup 檔 | 大幅改寫（如補圖說明） | `--reason` + **`--scope whole-comment` OR `--section <heading>`**（R4 enforced）|
| `--prepend-note` | 在最上方加 `> ⚠️ {reason}\n\n---\n\n` | 保留 | 標示「此 comment 已過時」 | `--reason` |
| `--correct` | 就地取代確定錯誤的整則 comment 或指定 section，區段末尾加帶 `backup-id` 的標記 | 歸檔到 correction archive（不進 git、權限 0000、hook 擋 AI 讀取） | 內容確定是錯的、使用者已確認（#351） | `--scope whole-comment` OR `--section <heading>`；`issue:<N>` 只接受 `--section`；不接受 `--override-user-content` |

## 動作分類 (per [`#150` action-scoped modify discipline](../../rules/append-vs-modify.md))

| Mode | Category | Scope contract |
|------|----------|---------------|
| `--append` | `audit-block-append` | trailing block,inherently bounded — no `--scope` needed |
| `--replace --scope whole-comment` | `bounded-section-replace` | scope = whole comment(explicit acknowledgment of full overwrite）|
| `--replace --section <heading>` | `bounded-section-replace` | scope = named markdown subsection only |
| `--prepend-note` | `audit-block-append` | leading errata marker,inherently bounded — no `--scope` needed |
| `--correct` | `in-place-correction` | 一個 bounded region（整則 comment 或一個 section）；歸檔後才寫入 — `(category: in-place-correction)` |

## Runtime gates (#154, v2.81.0+)

`/idd-edit` enforces 2 SHALL requirements at runtime via the **Python helper** `plugins/issue-driven-dev/scripts/idd-edit-helper.py` (#155 — replaces inline bash that was non-convergent over 3 verify rounds; the Python layer eliminates the R1/R2/R3 bug classes by-construction). Call `python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" <subcmd> ...` and branch on its exit code:

| Requirement | Gate | Refuse code |
|-------------|------|-------------|
| **R4** (spec) | `--replace` without `--scope`/`--section` → refuse | exit 3 |
| **R5** (spec) | 作者不是 OWNER、bot 或你自己（目前的 gh 使用者），且沒有 `--override-user-content --reason="..."` → refuse；`--correct` 只放行 OWNER 與你自己（bot 也拒絕、沒有 override；查不到 gh 使用者 → exit 1） | exit 4 |
| `--correct` scope | 缺 `--scope`/`--section`，或 `issue:<N>` 用 whole scope → refuse | exit 3 |
| `--correct` override | `--correct` 併用 `--override-user-content` → refuse（協作者 comment 只提議、不改） | exit 2 |
| Protected regions | `check-correction`：目標是或包含 `## Current Status`／`### Clarity Surface`（含其下的子標題，逐行比對、與 idd-update 相同）、替換內容帶入這些標題、`Original text`／`**Original**` 引用被改或後面緊接文字、整則更正拿掉開頭的型別標題 → refuse。`compose-correction`：替換內容留下沒關閉的 fence 或 HTML 註解 → refuse。段落邊界取自 Markdown parser（頂層標題、分隔線；code 與 HTML 區塊裡的行不算） | exit 6 |
| Markdown parser | `section-replace`／`check-correction`／`compose-correction` 需要 `markdown-it-py` 4.0.0（`scripts/requirements-egress.txt`）；缺或版本不符 → refuse、不改任何東西 | exit 8 |
| Archive | 不在 git work tree、歸檔路徑沒被 ignore、寫入失敗 → refuse，不 PATCH | exit 7 |

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
| `issue:<N>` | issue #N 的**正文**（只限 `--correct --section`；其他模式見 #347） |

## Execution

### Step 0: Bootstrap Stage Task List（強制)

**在動任何事之前**先用 `TaskCreate` 為這個 stage 建 todo list,確保每個 sub-step 都被追蹤:

```
TaskCreate(name="parse_and_resolve_target", description="Parse comment:<id> / #NNN [--last] / issue:<N>，解析成 RESOLVED_TARGETS（每項 kind:number，每個 iteration 自己決定目標）")
TaskCreate(name="fetch_body_and_backup", description="gh api 取現 body 寫入本次執行的私有工作目錄（mktemp -d 於 ${TMPDIR:-/tmp}）；失敗 → fetch-failed")
TaskCreate(name="show_original", description="顯示原 comment 前 30 行讓使用者看清楚要動什麼")
TaskCreate(name="build_new_body", description="按 mode（append / replace / prepend-note）組新 body 字串")
TaskCreate(name="check_correction", description="--correct only：helper check-correction 擋受管區與 Original text 引用區塊（exit 6；section 不存在 → section-not-found），再以 compose-correction 組出預覽全文")
TaskCreate(name="preview_and_confirm", description="顯示新 body 並用 AskUserQuestion 確認；--replace / --correct 模式必須通過；--correct 顯示 compose-correction 組好的全文；拒絕 → 刪工作副本、記 declined")
TaskCreate(name="archive_before_patch", description="--correct only：確認後重抓目標與預覽比對（不同 → changed since preview，拒絕），helper archive --from-file --repo 歸檔舊版（exit 7 → 不 PATCH），加 backup-id 標記、compose-correction 組出 NEW_BODY（與預覽同一個子命令，失敗即拒絕）；PATCH 後刪 /tmp 工作副本")
TaskCreate(name="execute_patch", description="經 gh-egress.sh edit-comment 派送 PATCH（#273 — 全網套用；rc>=10 → EGRESS_REFUSED 桶 warn-continue）；-F body=@file 避免 escape")
TaskCreate(name="verify_and_report", description="re-fetch comment 比對寫入結果，輸出 ✓ Edit applied + diff summary")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。**TaskCreate 清單 = 真實的步驟清單；任何寫在 skill 裡但沒列進 TaskCreate 的步驟，都視為 skill 的 bug，必須補進 Task 清單。**

特別提醒：**idd-edit 是破壞性動作**，每一步都必須在 task list 留痕。`fetch_body_and_backup` 跳過 = 沒有 backup，誤改後無法復原；`preview_and_confirm` 跳過 = 跳過使用者把關。

---

### Step 1: Parse arguments via helper (R4 gate enforced)

**#155 Python layer**: parsing + enforcement live in `plugins/issue-driven-dev/scripts/idd-edit-helper.py parse-args` (per [`#154`](https://github.com/PsychQuant/issue-driven-development/issues/154) → [`#155`](https://github.com/PsychQuant/issue-driven-development/issues/155): R1/R2/R3 bash-inline failure on PR #159 — 3 verify rounds, fix-velocity 91%→55%→40%, each pass introduced new parser bugs → bash ruled empirically non-convergent → ratified Python). The helper is a stdlib-only argparse-style parser with missing-value / next-`--`-eats-value / eq-form guards, **`--body-file` path safety via `os.path.realpath` canonicalize-first** (refuses `/etc`, credential dirs, and the `//etc` / `/tmp/../etc` / symlink bypass vectors), the R4 gate, and the R5 override-reason guard — all by-construction, covered by `plugins/issue-driven-dev/scripts/tests/idd-edit/` 23 adversarial fixtures.

```bash
# Parse + R4 gate (refuse if --replace lacks --scope/--section)
# CRITICAL: split stdout (eval-safe assignments) from stderr (diagnostic text).
# Closes #154 verify Round 1 H2 — previously used `2>&1` which mixed
# stderr (potentially containing $() from cat-on-directory failure etc.)
# into the eval input, defeating printf %q quoting safety.
PARSE_ERR_FILE="/tmp/idd-edit-parse-err-$$"
PARSE_OUT=$(python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" parse-args "$@" 2>"$PARSE_ERR_FILE")
PARSE_EXIT=$?
PARSE_ERR=$(cat "$PARSE_ERR_FILE")
rm -f "$PARSE_ERR_FILE"

case $PARSE_EXIT in
  0) eval "$PARSE_OUT" || { echo "✗ the parsed arguments did not evaluate — nothing was changed" >&2; exit 2; } ;;   # imports MODE/SCOPE_FLAG/SECTION_FLAG/BODY_INPUT/etc.
  3) echo "$PARSE_ERR" >&2; exit 3 ;;   # R4 refuse — actionable message
  *) echo "$PARSE_ERR" >&2; exit $PARSE_EXIT ;;
esac

# Resolve TARGETS array → RESOLVED_TARGETS array, one `kind:number` entry per
# target (`comment:<id>` or `issue:<N>`). Each iteration derives its own kind —
# a global flag here once sent a comment's correction to the issue body (#351).
# Closes R2 H7 (#154 Round 2): previously this loop closed BEFORE Steps 1.5-7,
# so batch mode `comment:NNN comment:MMM` silently only processed the LAST target.
# Fix: resolution loop accumulates; per-target processing happens in OUTER loop
# wrapping Steps 1.5 through 7 (see "Per-target outer loop" note below).
RESOLVED_TARGETS=()
for target in "${TARGETS[@]}"; do
    local id=""
    case "$target" in
        issue:*)
            # --correct only, and the only target (parse-args refused anything else)
            RESOLVED_TARGETS+=("$target")
            continue
            ;;
        comment:*)
            id="${target#comment:}"
            ;;
        \#*)
            ISSUE_NUMBER="${target#\#}"
            # Validate issue number is numeric before substitution into gh api URL
            [[ "$ISSUE_NUMBER" =~ ^[0-9]+$ ]] || { echo "ERROR: invalid issue number: $ISSUE_NUMBER" >&2; exit 2; }
            if [ "$LAST" = "true" ]; then
                # every page: the newest comment is on the last one (round 4)
                id=$(gh api "repos/$REPO/issues/$ISSUE_NUMBER/comments" --paginate --jq '.[-1].id' | tail -1)
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

    RESOLVED_TARGETS+=("comment:$id")
done
```

#### Per-target outer loop (wraps Steps 1.5 — 7)

**v2.81.0+ (#154 R3 fix for H7)**: Each resolved target runs through the full pipeline (validate → fetch → preview → confirm → PATCH → verify) independently. Batch mode = N iterations of the same sequence, per-comment confirmation discipline preserved.

```bash
# One private directory per run (mode 0700): every working copy lives here, so
# no other local user can swap one between the preview and the write (verify
# #351 round 3 — a shared fixed directory under /tmp allowed it).
# macOS puts $TMPDIR under /var; the helper's path gate accepts the user's own
# temp directory (verify #351 round 4 — before that, archive refused every
# working copy here after the user had confirmed).
WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/idd-edit-XXXXXX") || {
  echo "✗ cannot create a private working directory — nothing was changed" >&2; exit 1; }
EDITED_COUNT=0        # incremented after each successful per-target Step 7 verify
REFUSED_TARGETS=()    # "<kind:number> <reason>" — reason: R5 / author-unknown / fetch-failed / stage-failed / protected / section-not-found / parser-unavailable / check-failed / egress / changed-since-preview / differs-from-preview / archive / replace (#158 (i): recorded, not fatal)
DECLINED_TARGETS=()   # the user answered NO at Step 5 — reported, not a refusal
UNVERIFIED_TARGETS=() # written, but the re-read at Step 7 failed or did not match
WRITE_FAILED_TARGETS=() # gh itself failed the PATCH (rc 1–9): not a refusal (#273), but nothing was written
EGRESS_REFUSED_TARGETS=()   # egress-band refusals rc>=10（#273 — tier-floor/privacy/mention/empty-body），warn-continue
for TARGET in "${RESOLVED_TARGETS[@]}"; do
    TARGET_KIND="${TARGET%%:*}"     # comment | issue — derived per iteration
    TARGET_NUM="${TARGET#*:}"
    COMMENT_ID=""
    [ "$TARGET_KIND" = "comment" ] && COMMENT_ID="$TARGET_NUM"
    # === Steps 1.5 through 7 run here, per-target ===
    # ...
done
```

#### Step 7.5: Batch outcome report（#158，語意 (i) 落地）

批次（含退化的單 target）跑完後**必須**輸出 outcome report — 部分成功絕不偽裝成全成功：

```bash
echo "── idd-edit batch outcome ──"
REFUSED_TOTAL=$(( ${#REFUSED_TARGETS[@]} + ${#EGRESS_REFUSED_TARGETS[@]} ))
echo "edited: $EDITED_COUNT / refused: $REFUSED_TOTAL"
for entry in ${REFUSED_TARGETS[@]+"${REFUSED_TARGETS[@]}"}; do
  # entry = "<kind:number> <reason>"; reason ∈ the list at REFUSED_TARGETS above.
  # Only R5 has an override, and only outside --correct.
  echo "  ✗ REFUSED(${entry##* }) ${entry% *}"
done
for did in ${DECLINED_TARGETS[@]+"${DECLINED_TARGETS[@]}"}; do
  echo "  – DECLINED $did（使用者在預覽時拒絕，未寫入）"
done
for wid in ${WRITE_FAILED_TARGETS[@]+"${WRITE_FAILED_TARGETS[@]}"}; do
  echo "  ✗ FAILED(write) $wid（gh 自身錯誤，未寫入）"
done
for uid in ${UNVERIFIED_TARGETS[@]+"${UNVERIFIED_TARGETS[@]}"}; do
  echo "  ⚠ UNVERIFIED $uid（已寫入，但重讀失敗或內容不符 — 請手動確認）"
done
for rid in ${EGRESS_REFUSED_TARGETS[@]+"${EGRESS_REFUSED_TARGETS[@]}"}; do
  echo "  ✗ REFUSED(egress) $rid — band 語意見 #227（10 privacy / 11 mention / 13 tier-floor #272 / 15 empty-body #275）"
done
# Exit contract（fixture 14/15；M = REFUSED_TOTAL；M>0 → exit 4，單 target 退化等價）：
# final exit 仍不套 #227 碼帶 — batch 的聚合碼是 idd-edit 自身空間（任一 refusal = 4）；
# per-comment 分類消費 band（10–15）— 這正是 band 存在的目的（#273）。
# Final exit codes, first match wins (verify #351 rounds 3–4). Callers such as
# idd-comment's errata path route on them, so none overlaps an argument error
# (2 / 3 / 5 come straight from parse-args, before anything is fetched):
#   4 = something was refused or a write failed — nothing was changed for it
#   7 = written, but the read-back failed or differed — check it by hand
#   9 = nothing refused or failed, but the user declined at least one preview
[ "$REFUSED_TOTAL" -gt 0 ] && exit 4
[ "${#WRITE_FAILED_TARGETS[@]}" -gt 0 ] && exit 4
[ "${#UNVERIFIED_TARGETS[@]}" -gt 0 ] && exit 7
[ "${#DECLINED_TARGETS[@]}" -gt 0 ] && exit 9
exit 0
```

### Step 1.5: Validate target (R5 author gate)

**v2.81.0+ (#154)**: R5 gate refuses modifications to content whose author is not `OWNER`, a bot, or the authenticated `gh` user, unless `--override-user-content --reason="..."` provided（`gh` 使用者本人的內容在 org repo 是 `MEMBER`，所以本人另外放行 —— 四種 mode 都適用，#351）。Helper does single `gh api` call, checks `author_association` + `user.login`。**`--correct` 不放行 bot**：review bot 的 comment 是第三方原話，只能另貼 errata（#351 verify 第 2 輪）。

```bash
# comment → its author; issue:<N> → the issue author. OWNER, a bot, or the
# authenticated gh user pass (org maintainers are MEMBER — #351); with
# --correct a bot does not (its words are a third party's).
VALIDATE_ARG="$COMMENT_ID"
[ "$TARGET_KIND" = "issue" ] && VALIDATE_ARG="issue:$TARGET_NUM"
python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" \
    validate-target "$VALIDATE_ARG" "$REPO" "$OVERRIDE_USER_CONTENT" "$MODE"
VALIDATE_EXIT=$?
case $VALIDATE_EXIT in
  0) ;;   # proceed (OWNER, bot outside --correct, own content, or override active)
  4)
    # R5 refuse — actionable message already on stderr.
    # (--correct has no override: a collaborator's comment is corrected by
    #  proposing an errata comment, never by editing it — #351.)
    # #158 語意 (i)：記錄後 continue,不中斷 batch（#158 語意 (i)）— 本 target 跳過
    # Steps 2-7,其餘 targets 照常;單 target 退化等價（記錄 → loop 自然結束 → report → exit 4）。
    REFUSED_TARGETS+=("$TARGET R5")
    continue
    ;;
  1)
    # Only --correct turns "the gh user is unknown" into exit 1; elsewhere an
    # exit 1 is a transport error and ends the run as before (round 4).
    [ "$MODE" = "--correct" ] || exit 1
    REFUSED_TARGETS+=("$TARGET author-unknown")
    continue
    ;;
  *) exit $VALIDATE_EXIT ;;
esac
```

### Step 2: Fetch current body + backup

```bash
# In the run's private $WORK_DIR: an unpredictable name in a directory only
# this user can write, so nothing else can swap the file between the preview
# and the archive step.
BACKUP_FILE=$(mktemp "$WORK_DIR/${TARGET_KIND}-${TARGET_NUM}-XXXXXX") || {
  echo "✗ cannot stage the working copy of $TARGET — skipped" >&2
  REFUSED_TARGETS+=("$TARGET stage-failed"); continue; }
if [ "$TARGET_KIND" = "issue" ]; then
    TARGET_ENDPOINT="repos/$REPO/issues/$TARGET_NUM"            # issue body (--correct only)
else
    TARGET_ENDPOINT="repos/$REPO/issues/comments/$COMMENT_ID"
fi
if ! gh api "$TARGET_ENDPOINT" --jq '.body' > "$BACKUP_FILE"; then
    # An empty file is not the target's body: comparing two failed fetches
    # would match and archive nothing (verify #351 round 2).
    echo "✗ cannot read $TARGET — nothing changed" >&2
    rm -f "$BACKUP_FILE"
    REFUSED_TARGETS+=("$TARGET fetch-failed")
    continue
fi
# Logins the target already mentions: published already, so keeping them in
# an edit notifies no one new. They are attested to gh-egress (Step 4 check and
# Step 6); a mention the edit ADDS is still refused there (verify #351 round 3 —
# any existing mention used to make every edit of the target fail at egress).
EXISTING_MENTIONS=$(python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" existing-mentions "$BACKUP_FILE") || {
    echo "✗ cannot scan $TARGET for existing mentions — skipped" >&2
    rm -f "$BACKUP_FILE"
    REFUSED_TARGETS+=("$TARGET egress"); continue; }

echo "✓ Backup: $BACKUP_FILE"
```

### Step 3: Show original body

```
=== Original ($TARGET) ===
{首 30 行 + "..."}
===
```

### Step 4: Build new body per mode

> **v2.81.0+ (#154)**: audit markers are built via `python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" emit-audit-marker` — centralizes HTML-comment-escape (`-->` stripping) so attacker-controlled `$REASON` / `$SECTION_FLAG` cannot forge audit trail (closes #154 verify finding C3).

#### Mode: `--append`

```bash
EDIT_MARKER=$(python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" emit-audit-marker edit mode=append)
NEW_BODY="$(cat $BACKUP_FILE)

---

**Edit $(date +%Y-%m-%d)**: $REASON

$BODY_INPUT

$EDIT_MARKER"

# Append R5 override audit marker if applicable
if [ "$OVERRIDE_USER_CONTENT" = "true" ]; then
    OVERRIDE_MARKER=$(python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" emit-audit-marker override mode=append reason="$REASON")
    NEW_BODY="$NEW_BODY

$OVERRIDE_MARKER"
fi
```

#### Mode: `--replace`

R4 gate already enforced in Step 1 — `SCOPE_FLAG` or `SECTION_FLAG` is guaranteed non-empty here.

```bash
if [ "$SCOPE_FLAG" = "whole-comment" ]; then
    # Whole-comment replacement
    EDIT_MARKER=$(python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" emit-audit-marker edit mode=replace scope=whole-comment backup="$BACKUP_FILE")
    NEW_BODY="$BODY_INPUT

$EDIT_MARKER"
elif [ -n "$SECTION_FLAG" ]; then
    # Named section replacement via getline pattern (closes R3 C3 BSD awk newline reject)
    # Per-run, because this file becomes part of an edited GitHub comment.
    # The #288 scan exempted this whole directory on the strength of a reason
    # that named only the backup directory — so two egress bodies inherited an
    # exemption written for something else.
    REPL_FILE=$(mktemp "$WORK_DIR/repl-XXXXXX") || {
      echo "✗ cannot stage the replacement text for $TARGET — skipped" >&2
      REFUSED_TARGETS+=("$TARGET stage-failed"); continue; }
    printf '%s\n' "$BODY_INPUT" > "$REPL_FILE"
    NEW_BODY=$(python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" \
                  section-replace "$BACKUP_FILE" "$SECTION_FLAG" "$REPL_FILE") || {
        SR_RC=$?   # an empty NEW_BODY here used to be written as the section (verify #351 round 3)
        rm -f "$REPL_FILE"
        case $SR_RC in
          8) REFUSED_TARGETS+=("$TARGET parser-unavailable") ;;
          *) REFUSED_TARGETS+=("$TARGET section-not-found") ;;
        esac
        continue
    }
    rm -f "$REPL_FILE"
    EDIT_MARKER=$(python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" emit-audit-marker edit mode=replace section="$SECTION_FLAG" backup="$BACKUP_FILE")
    NEW_BODY="$NEW_BODY

$EDIT_MARKER"
fi

# Append R5 override audit marker if applicable
if [ "$OVERRIDE_USER_CONTENT" = "true" ]; then
    OVERRIDE_MARKER=$(python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" emit-audit-marker override mode=replace reason="$REASON")
    NEW_BODY="$NEW_BODY

$OVERRIDE_MARKER"
fi
```

**警告**：`--replace` 是 `bounded-section-replace` 動作（per [#150 rule](../../rules/append-vs-modify.md)）。必顯示 diff preview，使用者確認後才 PATCH。 R4 強制 `--scope`/`--section` 避免「忘記講動作範圍 = 全 comment overwrite」silent footgun。

#### Mode: `--correct`（#351）

`(category: in-place-correction)` — 內容確定是錯的，使用者確認後就地取代。先檢查保護區，再預覽；**歸檔與標記在 Step 5.5（確認之後）**，所以這一步只準備取代內容，不產生 `NEW_BODY`。

```bash
REPL_FILE=$(mktemp "$WORK_DIR/repl-XXXXXX") || {
  echo "✗ cannot stage the replacement text for $TARGET — skipped" >&2
  rm -f "$BACKUP_FILE"; REFUSED_TARGETS+=("$TARGET stage-failed"); continue; }
printf '%s\n' "$BODY_INPUT" > "$REPL_FILE"
python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" \
    check-correction "$BACKUP_FILE" "${SECTION_FLAG:--}" "$REPL_FILE"
CHECK_RC=$?
if [ "$CHECK_RC" -ne 0 ]; then
    rm -f "$REPL_FILE" "$BACKUP_FILE"
    case $CHECK_RC in
      6) REFUSED_TARGETS+=("$TARGET protected") ;;          # stderr 已指名區域與負責的 skill
      1) REFUSED_TARGETS+=("$TARGET section-not-found") ;;
      8) REFUSED_TARGETS+=("$TARGET parser-unavailable") ;; # 安裝 scripts/requirements-egress.txt
      *) REFUSED_TARGETS+=("$TARGET check-failed") ;;
    esac
    continue
fi
# The preview is the text that will be written: the same subcommand composes
# it again in Step 5.5 with the real backup id (verify #351 round 2 — the
# preview used to show only the replacement, not the assembled body).
PLACEHOLDER_MARKER='<!-- idd:edit mode="correct" backup-id="(assigned after confirmation)" -->'
PREVIEW_BODY=$(python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" \
    compose-correction "$BACKUP_FILE" "${SECTION_FLAG:--}" "$REPL_FILE" "$PLACEHOLDER_MARKER") || {
    COMPOSE_RC=$?
    rm -f "$REPL_FILE" "$BACKUP_FILE"
    case $COMPOSE_RC in
      6) REFUSED_TARGETS+=("$TARGET protected") ;;          # a fence or HTML comment left open
      8) REFUSED_TARGETS+=("$TARGET parser-unavailable") ;;
      *) REFUSED_TARGETS+=("$TARGET check-failed") ;;
    esac
    continue
}
# The egress gates run on the composed body BEFORE the preview, so a body that
# gh-egress would refuse never reaches confirmation or the archive (verify #351
# round 3 — a refusal after archiving left an orphan entry each time).
PREVIEW_FILE=$(mktemp "$WORK_DIR/preview-XXXXXX") || {
    rm -f "$REPL_FILE" "$BACKUP_FILE"; REFUSED_TARGETS+=("$TARGET stage-failed"); continue; }
printf '%s\n' "$PREVIEW_BODY" > "$PREVIEW_FILE"
SCRUB_LEVEL="${SCRUB_LEVEL:-warn}"   # 依 rules/privacy-scrubbing.md 解析（同 Step 6）
if ! bash "$CLAUDE_PLUGIN_ROOT/scripts/gh-egress.sh" check --body-file "$PREVIEW_FILE" \
       --scrub-attested "$SCRUB_LEVEL" ${EXISTING_MENTIONS:+--mention-attested="$EXISTING_MENTIONS"}; then
    rm -f "$PREVIEW_FILE" "$REPL_FILE" "$BACKUP_FILE"
    REFUSED_TARGETS+=("$TARGET egress")   # stderr 已說明是哪一道（隱私、mention、…）
    continue
fi
rm -f "$PREVIEW_FILE"
```

預覽（Step 5）顯示 `$PREVIEW_BODY` **全文**（不截斷），並註明「確認後舊版會歸檔、`(assigned after confirmation)` 換成實際的 backup id」。替換內容若以目標標題開頭，`compose-correction` 會去掉重複的那一行；同一段先前的更正標記會保留，新標記排在最後。

#### Mode: `--prepend-note`

```bash
EDIT_MARKER=$(python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" emit-audit-marker edit mode=prepend-note)
NEW_BODY="> ⚠️ **Edit $(date +%Y-%m-%d)**: $REASON

---

$(cat $BACKUP_FILE)

$EDIT_MARKER"

# Append R5 override audit marker if applicable
if [ "$OVERRIDE_USER_CONTENT" = "true" ]; then
    OVERRIDE_MARKER=$(python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" emit-audit-marker override mode=prepend-note reason="$REASON")
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

使用 AskUserQuestion。預設 NO（破壞性動作）。`--correct` 的預覽是 `$PREVIEW_BODY` 全文，不只首 40 行。

使用者拒絕（NO）時：

```bash
# The working copies hold the wrong text; /tmp is outside the read guard.
[ "$MODE" = "--correct" ] && rm -f "$REPL_FILE" "$BACKUP_FILE"
DECLINED_TARGETS+=("$TARGET")
continue
```

### Step 5.5: Archive before PATCH（`--correct` only）

確認之後才歸檔，歸檔成功才 PATCH（使用者拒絕 = 刪掉工作副本、不留任何檔案）。helper 自己算歸檔路徑；**本 skill 執行的 bash 不寫出歸檔路徑**，否則會被 archive-read-guard hook 擋下。

確認後先重抓目標：預覽期間若有人（或 `idd-update`）改過，這次更正會蓋掉那些修改，所以內容不同就拒絕（changed since preview），請使用者重跑。GitHub 沒有條件式寫入，重抓到 PATCH 之間仍有極短的競爭窗。

```bash
CURRENT_FILE=$(mktemp "$WORK_DIR/${TARGET_KIND}-${TARGET_NUM}-now-XXXXXX") || {
    rm -f "$REPL_FILE" "$BACKUP_FILE"; REFUSED_TARGETS+=("$TARGET stage-failed"); continue; }
if ! gh api "$TARGET_ENDPOINT" --jq '.body' > "$CURRENT_FILE"; then
    echo "✗ cannot re-read $TARGET — nothing archived or written" >&2
    rm -f "$CURRENT_FILE" "$REPL_FILE" "$BACKUP_FILE"
    REFUSED_TARGETS+=("$TARGET fetch-failed")
    continue
fi
if ! cmp -s "$BACKUP_FILE" "$CURRENT_FILE"; then
    echo "✗ $TARGET changed since preview — nothing archived or written; run again to see the new version" >&2
    rm -f "$CURRENT_FILE" "$REPL_FILE" "$BACKUP_FILE"
    REFUSED_TARGETS+=("$TARGET changed-since-preview")
    continue
fi
rm -f "$CURRENT_FILE"
# What gets archived and written must be what was previewed: compose again with
# the placeholder and compare, before anything is archived (verify #351 round 3).
RECHECK_BODY=$(python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" \
    compose-correction "$BACKUP_FILE" "${SECTION_FLAG:--}" "$REPL_FILE" "$PLACEHOLDER_MARKER")
if [ "$?" -ne 0 ] || [ "$RECHECK_BODY" != "$PREVIEW_BODY" ]; then
    echo "✗ the body to be written differs from the preview — nothing archived or written" >&2
    rm -f "$REPL_FILE" "$BACKUP_FILE"
    REFUSED_TARGETS+=("$TARGET differs-from-preview")
    continue
fi
BACKUP_ID=$(python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" \
    archive "$TARGET_KIND" "$TARGET_NUM" --from-file "$BACKUP_FILE" --repo "$REPO") || {
    # exit 7：不在 git work tree / 路徑沒被 ignore / 寫入失敗；exit 5：路徑閘門 — 目標不動
    rm -f "$REPL_FILE" "$BACKUP_FILE"
    REFUSED_TARGETS+=("$TARGET archive")
    continue
}
CORRECT_MARKER=$(python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" \
    emit-audit-marker edit mode=correct backup-id="$BACKUP_ID")
# 標記是被取代區段的最後一行，不會落進 idd-update 管的 ## Current Status。
# compose-correction 與預覽同一個子命令：`---`、受管標題與下一個同級標題結束
# 區段，code block 裡的行不算；先前的更正標記保留在新標記之前。
NEW_BODY=$(python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" \
    compose-correction "$BACKUP_FILE" "${SECTION_FLAG:--}" "$REPL_FILE" "$CORRECT_MARKER") || {
    rm -f "$REPL_FILE" "$BACKUP_FILE"
    REFUSED_TARGETS+=("$TARGET replace")   # archived already; target untouched
    continue
}
rm -f "$REPL_FILE"
```

### Step 6: Execute PATCH

> **Scrub level**：`$SCRUB_LEVEL` 依 [`rules/privacy-scrubbing.md`](../../rules/privacy-scrubbing.md) 解析（repo visibility → tier；#226 rollout 慣例），互動情境預設 `warn`。

**關鍵**：用 `-F body=@file`（不是 `-f body=""`）避免 backtick / 多行字串的 escape bug。

```bash
# Per-run: this is the body that gets PATCHed into someone's comment. A fixed
# name keyed only on the comment id collides between two sessions editing the
# same comment, and the loser's text is what gets published.
TMP_BODY_FILE=$(mktemp "$WORK_DIR/new-XXXXXX") || {
  echo "✗ cannot stage the new body for $TARGET — skipped" >&2
  [ "$MODE" = "--correct" ] && rm -f "$BACKUP_FILE"
  REFUSED_TARGETS+=("$TARGET stage-failed"); continue; }
printf '%s\n' "$NEW_BODY" > "$TMP_BODY_FILE"   # printf, not echo: zsh echo rewrites backslashes (#330)

# #273：comment surgery 進 egress 網 — 原 raw `gh api` PATCH 完全繞過所有網
# （#226 rollout 的 tracked-separately 欠帳，於此結清）。
SCRUB_LEVEL="${SCRUB_LEVEL:-warn}"   # 依 rules/privacy-scrubbing.md 解析（repo tier；互動預設 warn，#226 慣例）
if [ "$TARGET_KIND" = "issue" ]; then
    # issue 正文（--correct only）走 gh issue edit
    bash "$CLAUDE_PLUGIN_ROOT/scripts/gh-egress.sh" edit "$TARGET_NUM" \
        --repo "$REPO" --body-file "$TMP_BODY_FILE" --scrub-attested "$SCRUB_LEVEL" \
        ${EXISTING_MENTIONS:+--mention-attested="$EXISTING_MENTIONS"}
else
    bash "$CLAUDE_PLUGIN_ROOT/scripts/gh-egress.sh" edit-comment "$COMMENT_ID" \
        --repo "$REPO" --body-file "$TMP_BODY_FILE" --scrub-attested "$SCRUB_LEVEL" \
        ${EXISTING_MENTIONS:+--mention-attested="$EXISTING_MENTIONS"}
fi
EGRESS_RC=$?
rm "$TMP_BODY_FILE"
if [ "$EGRESS_RC" -ge 10 ]; then
    # wrapper refusal band（#227）— per-comment 分類消費 band（10–15）：
    # 記錄 + warn-continue（#158 語意 (i) 同款）。wrapper 已對本 target 印明確 stderr。
    EGRESS_REFUSED_TARGETS+=("$TARGET rc=$EGRESS_RC")
    [ "$MODE" = "--correct" ] && rm -f "$BACKUP_FILE"
    continue
elif [ "$EGRESS_RC" -ne 0 ]; then
    # 0 < rc < 10 = gh 自身錯誤（auth / network），非 refusal — 誠實分流，不進 refused 桶
    echo "✗ gh api PATCH failed for $TARGET (rc=$EGRESS_RC, gh 自身碼) — skip this target" >&2
    [ "$MODE" = "--correct" ] && rm -f "$BACKUP_FILE"
    # Its own bucket and a non-zero exit: without it a single failed write ended
    # with exit 0 and idd-comment reported the comment as corrected (round 4).
    WRITE_FAILED_TARGETS+=("$TARGET rc=$EGRESS_RC")
    continue
fi
# --correct：舊版已在歸檔，刪掉 /tmp 工作副本（它含錯誤內容，且 hook 不擋 /tmp）
[ "$MODE" = "--correct" ] && rm -f "$BACKUP_FILE"
```

> `--correct` 的 PATCH 若失敗：歸檔已寫入但目標沒變。歸檔檔留著無害（不進 git、AI 讀不到）；重跑會產生新的 backup-id。

### Step 7: Verify edit + report

```bash
# Re-fetch 確認：讀回失敗或內容不符，就不算成功（verify #351 round 3）
UPDATED=$(gh api "$TARGET_ENDPOINT" --jq '.body')
UPDATED_RC=$?
if [ "$UPDATED_RC" -ne 0 ]; then
    echo "⚠ $TARGET was written but could not be read back — check it by hand" >&2
    UNVERIFIED_TARGETS+=("$TARGET")
    continue
fi
if [ "$UPDATED" != "$NEW_BODY" ]; then
    echo "⚠ $TARGET reads back differently from what was sent — check it by hand" >&2
    UNVERIFIED_TARGETS+=("$TARGET")
    continue
fi
echo "✓ $TARGET updated"
echo "  URL: $(gh api "$TARGET_ENDPOINT" --jq '.html_url')"
[ "$MODE" = "--correct" ] && echo "  Backup id: $BACKUP_ID" || echo "  Backup: $BACKUP_FILE"
echo "  First 5 lines of new body: $(printf '%s\n' "$UPDATED" | head -5)"
EDITED_COUNT=$((EDITED_COUNT + 1))
```

## Metadata Marker

每次 edit 在 body 加 HTML comment：

```html
<!-- idd:edit mode=<mode> date=<date> [backup=<path>] -->
```

`--correct` 的標記只帶 backup id、不帶路徑，放在被取代區段的最後一行：

```html
<!-- idd:edit mode="correct" backup-id="comment-5805214375-20261009T100000Z" date="2026-10-09" -->
```

多次 edit 會 **append 多個 marker**（不覆蓋前次），形成 edit history。

## 使用範例

### 補既有 comment 的圖片說明（自己發的 comment,whole-comment scope）

```
/idd-edit comment:4241327867 --replace \
  --scope whole-comment \
  --body-file=~/notes/new-implementation-summary.md \
  --reason="依新 skill 規則補圖下方資料/統計/結論說明"
```

### 修錯的數字或錯字（`--correct`，單 section）

錯的值直接換掉，不在後面追加「修正：…」（#351：追加的更正會讓錯的原文繼續被讀到）。

```
/idd-edit #18 --last --correct --section "### Results" \
  --body-file=~/notes/fixed-results.md \
  --reason="p-value 計算誤差，重跑後為 56.3%"
```

### 修 Diagnosis comment 內某 ### 區段（自己發的 comment）

```
/idd-edit comment:4530594011 --replace \
  --section="### Strategy" \
  --body-file=~/notes/new-strategy.md \
  --reason="重新拆 Block A → B 依賴順序"
```

### 更正確定錯誤的內容（`--correct`，#351）

```
/idd-edit comment:4241327867 --correct --section "### Strategy" \
  --body-file=~/notes/fixed-strategy.md \
  --reason="備份位置寫錯，實際不進 git"

/idd-edit issue:351 --correct --section "## Expected" \
  --body-file=~/notes/fixed-expected.md \
  --reason="誤讀了需求"
```

協作者發的 comment 不用 `--correct`：改用 `/idd-comment --type errata` 另貼更正（`--correct` 沒有 override）。

## 鐵律

- **原 body 必 backup**：`--append`/`--replace`/`--prepend-note` 存在本次執行的私有工作目錄 `${TMPDIR:-/tmp}/idd-edit-XXXXXX/`（暫存，Step 2 印出路徑）；`--correct` 確認後歸檔到 correction archive（永久、不進 git、AI 讀不到），PATCH 後刪 `/tmp` 副本
- **Preview 必 show**：即使是 `--append` 也要 show 最終 body 讓使用者確認
- **`-F body=@file` 不是 `-f body=""`**：避免 backtick escape（`gh api` 會把 heredoc 裡的 backtick escape 成 `\`）
- **Metadata marker 不覆蓋**：每次 edit 加新 marker，保留 history
- **`--replace` 預設 confirm = NO**：破壞性動作不自動 yes
- **Log 每次 edit**：顯示 URL 讓使用者能立即 verify
- **`--body-file` path safety（#155）**：helper **canonicalize（`os.path.realpath`）後拒絕** sensitive system paths（`/etc` `/var` `/sys` `/proc` `/private/etc|var`）+ credential dirs（`.ssh` `.aws` `.gnupg` `.kube` `.docker`），含 `//etc` / `/tmp/../etc` / symlink / relative-traversal bypass vectors → exit 5 refuse。Escape hatch：`IDD_EDIT_HELPER_ALLOW_UNSAFE_BODY_FILE=1`（須自審 reason）。合法 repo / `/tmp` / `$HOME/Developer` 路徑照常讀。Preview gate 仍是最後一道防線。

## 與 idd-comment 的配合

**errata flow**（#351 起依 target 作者分流，由 `/idd-comment --type errata` 決定）：

```
/idd-comment #NNN --type=errata --target-comment=XXX ...
  ├─ XXX 是你本人或 OWNER 寫的 → /idd-edit comment:XXX --correct ...（不另貼 comment）
  └─ 其他作者（含 bot）       → 只貼 errata comment，不呼叫 idd-edit
```

## Backup 管理

**`--append` / `--replace` / `--prepend-note`**：備份在這次執行的私有工作目錄（`${TMPDIR:-/tmp}/idd-edit-XXXXXX/`，權限 0700），由 `mktemp` 命名 `<kind>-<number>-XXXXXX`；Step 2 會印出完整路徑。

```bash
ls -la "${TMPDIR:-/tmp}"/idd-edit-*/
# 回復（set REPO=owner/repo first；災難復原刻意走 raw gh api、不經 egress 網 —
#  還原的是先前已公開發佈的內容，#273 接線範圍是 Step 6 正常路徑）
gh api "repos/$REPO/issues/comments/<id>" \
    -X PATCH \
    -F body=@"<Step 2 印出的備份路徑>"
```

**`--correct`**：舊版在 correction archive，用 backup id（標記裡那個）還原。內容直接送給 GitHub、不顯示；還原的是**整個**目標，更正之後的修改（例如 `idd-update` 重建的 Current Status）會一起被蓋掉，執行前用 AskUserQuestion 說明這點並確認。

```bash
python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" restore "$BACKUP_ID" --repo "$REPO"
```

歸檔檔不經過 Claude 讀取（hook 會擋、檔案權限 0000）。人要看舊版時，在自己的終端機 `chmod u+r` 該檔後用編輯器開，不要透過 Claude；看完 `chmod 000` 改回，否則 `grep -r` 這類不寫出路徑的遞迴讀取會讀到它。

歸檔是被 git ignore 的檔案：`git clean -X`（或 `-x`）會把它刪掉，而它是更正前內容在本機唯一能還原的一份 —— 在有歸檔的 clone 裡不要跑這兩個指令（移到更安全位置的討論在 #407）。

歸檔只存在**執行 `--correct` 的那份 clone**（它的主 worktree）。同一個 repo 在別處的 clone 沒有這份歸檔，`restore` 會回報找不到；要還原就回到原本那份 clone 執行。

## Next Step

Edit 後通常不需要後續 skill。如果是修 diagnosis comment，可能要重跑 `/idd-verify`。
如果是 errata flow，由 `/idd-comment` 統一 orchestrate。

## SKILL↔helper Contract（#163）

本 SKILL 的 bash 與 `scripts/idd-edit-helper.py` 之間的變數契約由 **`scripts/tests/idd-edit-contract/`** 靜態鎖定：SKILL fenced bash 內消費的每個大寫 `$VAR` 必有出處 —（a）SKILL block 內賦值、（b）helper `emit_assignment` / `TARGETS` emit（**helper 源碼即 source of truth**，本節不重列變數清單）、（c）環境 allowlist（`CLAUDE_PLUGIN_ROOT`、`IDD_CALLER` #161 等，明文列於 checker）。此層封殺 #154 R1 B1（`$APPEND_BODY`）/ B2（`$GITHUB_REPO`）的「fixtures 全綠、production 壞掉」class。

**掃描邊界**：只掃 fenced bash blocks（heredoc 在內 — B1 就住在 heredoc）；single-quote 不展開造成的 false positive 由 allowlist 消化；loop 結構 class（R2 H7）不在此層 — 由 `scripts/tests/idd-edit/` fixture 14 的 prose 契約覆蓋。編輯本 SKILL 引入新變數時：在 block 內賦值、或經 helper emit、或（僅環境變數）進 checker allowlist — 三者皆非會被 suite 擋下。
