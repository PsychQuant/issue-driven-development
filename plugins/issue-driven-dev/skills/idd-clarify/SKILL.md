---
name: idd-clarify
description: Scan an existing GitHub issue body for terminology / ambiguity / missing-context gaps and annotate via surfacing-only `### Clarity Surface` block. Standalone primitive — also delegated by `idd-issue` Step 4.6, gated by `idd-diagnose` Step 0.5.
---

# /idd-clarify — 語意校正 surface

第三條 IDD quality axis(terminology / semantic accuracy)的執行者。**不替 user resolve**,只在 issue body annotate 疑點讓 downstream 看到。

## 核心原則

> Surface-only。AI 不是 oracle,user 也不一定是 oracle。Clarity Surface 把 doubt 放到 audit trail,讓 future reader / 自動化 chain 都看得到。

## Skill graph 三軸位置

| Axis | Existing safeguard | Skill |
|---|---|---|
| Confidence(客戶是否真的反映)| IC_R010 | `idd-issue` Step 4.4 + `idd-diagnose` Step 3.4 |
| Verbatim(原文是否被改寫)| IC_R007 | `idd-issue` Step 1 source preservation |
| **Terminology / Semantic accuracy** | **無** | **本 skill `idd-clarify`** |

## Composability

```
/idd-clarify <#N>                  ← standalone primitive(retroactive 對既存 issue)
    ↑ delegated by
idd-issue (Step 4.6 auto-invoke)   ← orchestrator(zero UX burden)
    ↑ gated by
idd-diagnose (Step 0.5 PR Gate)    ← refuse 進 diagnose 直到 unresolved rows 處理
```

## Configuration

按 [config-protocol](../../references/config-protocol.md) 解析 target repo:

- `--repo owner/repo` flag → per-invocation override
- Walk-up `.claude/issue-driven-dev.local.json`(從 cwd 往上找)
- Path / git predicates 自動匹配

**Group/predicate 行為**:本 skill 操作既存 issue,只用 path/git 類 predicate。Group config 會 fall through 到 primary repo。

## 參數

```
/idd-clarify #42                          → 對 #42 scan + annotate(default invocation)
/idd-clarify #42 --status resolved=2,reason → update row 2 → resolved
/idd-clarify #42 --status dismissed=3,reason → update row 3 → dismissed
/idd-clarify #42 --cwd /path/to/clone     → cross-repo invocation(per references/cross-repo-cwd.md)
```

`--status` update mode `(category: state-field-update, scope: "### Clarity Surface" row status field)` — 修改 named row 的 status enum field(resolved / dismissed),row 內 prose 不動。 依 [`rules/append-vs-modify.md`](../../rules/append-vs-modify.md)。

## Cross-repo invocation

支援 `--cwd /path/to/local/clone` flag,語意同 `idd-diagnose` / `idd-verify`。Step 0 解析 `--cwd` 後,後續所有 `git`/`gh` 命令依 [`references/cross-repo-cwd.md`](../../references/cross-repo-cwd.md) substitution rule 改寫。

## Execution

### Step 0: Bootstrap Stage Task List(強制)

**在動任何事之前**用 `TaskCreate` 建 stage-level task list:

```
TaskCreate(name="parse_args", description="Step 1: 解析 #N + 可選 --status flag + --cwd flag")
TaskCreate(name="resolve_target", description="Step 2: target repo 解析(per config-protocol)")
TaskCreate(name="read_issue_body", description="Step 3: gh issue view #N 讀 body")
TaskCreate(name="dispatch_by_mode", description="Step 4: 依 args 走 scan mode(無 --status)或 update mode(有 --status)")
TaskCreate(name="scan_or_update", description="Step 5: scan mode → 三類 detect + compose;update mode → grep row + patch status")
TaskCreate(name="patch_body", description="Step 6: gh issue edit #N --body 寫回 annotated body")
TaskCreate(name="report_and_stop", description="Step 7: echo summary(N rows surfaced 或 row X marked Y)")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。

### Step 1: Parse args

```bash
NUMBER=""           # 必要,gh issue number
STATUS_ACTION=""    # "" | "resolved" | "dismissed"
STATUS_ROW_IDX=""
STATUS_REASON=""
CWD_FLAG=""

# Parse positional + flags
ARGS=("$@")
for ((i=0; i<${#ARGS[@]}; i++)); do
  arg="${ARGS[i]}"
  case "$arg" in
    "#"*) NUMBER="${arg#\#}" ;;
    --status)
      i=$((i+1))
      STATUS_RAW="${ARGS[i]}"
      # Parse "resolved=2,reason text" or "dismissed=3"
      STATUS_ACTION="${STATUS_RAW%%=*}"
      STATUS_TAIL="${STATUS_RAW#*=}"
      STATUS_ROW_IDX="${STATUS_TAIL%%,*}"
      STATUS_REASON="${STATUS_TAIL#*,}"
      [ "$STATUS_REASON" = "$STATUS_TAIL" ] && STATUS_REASON=""  # no comma → no reason
      ;;
    --cwd) i=$((i+1)); CWD_FLAG="${ARGS[i]}" ;;
    --cwd=*) CWD_FLAG="${arg#--cwd=}" ;;
  esac
done

# Validate
[ -z "$NUMBER" ] && abort "Missing issue number. Usage: /idd-clarify #N [--status action=row[,reason]]"
[[ ! "$NUMBER" =~ ^[0-9]+$ ]] && abort "Invalid issue number: $NUMBER"
```

### Step 2: Resolve target

Per [config-protocol](../../references/config-protocol.md):

```bash
CWD="${CWD_FLAG:-$PWD}"
[ -d "$CWD" ] || abort "--cwd path '$CWD' does not exist"
git -C "$CWD" rev-parse --git-dir > /dev/null 2>&1 || abort "$CWD is not a git repo"

# Walk-up config
GITHUB_REPO=""
DIR="$CWD"
while [ "$DIR" != "/" ]; do
  # New path wins at the same level, legacy fallback (config-protocol mechanism 4, #195)
  if [ -f "$DIR/.claude/.idd/local.json" ]; then
    GITHUB_REPO=$(jq -r '.github_repo // empty' "$DIR/.claude/.idd/local.json" 2>/dev/null)
    [ -n "$GITHUB_REPO" ] && break
  fi
  if [ -f "$DIR/.claude/issue-driven-dev.local.json" ]; then
    GITHUB_REPO=$(jq -r '.github_repo // empty' "$DIR/.claude/issue-driven-dev.local.json" 2>/dev/null)
    [ -n "$GITHUB_REPO" ] && break
  fi
  [ "$DIR" = "$HOME" ] && break
  DIR=$(dirname "$DIR")
done

# Fallback: derive from origin
if [ -z "$GITHUB_REPO" ]; then
  GITHUB_REPO=$(git -C "$CWD" remote get-url origin 2>/dev/null \
    | sed -E 's#(\.git)?$##; s#.*[:/]([^/]+/[^/]+)$#\1#')
fi
[ -z "$GITHUB_REPO" ] && abort "Could not resolve target repo. Pass --repo owner/repo or set walked-up config."
```

### Step 3: Read issue body

```bash
BODY=$(gh issue view "$NUMBER" --repo "$GITHUB_REPO" --json body --jq '.body' 2>&1)
[ $? -ne 0 ] && abort "Cannot read issue #$NUMBER from $GITHUB_REPO: $BODY"
```

### Step 4: Dispatch by mode

```
if [ -z "$STATUS_ACTION" ]; then
  → Step 5a (scan mode)
else
  → Step 5b (update mode)
fi
```

### Step 4.8.A: Unattended mode detection (v2.74.0+, #137)

Step 5a (scan mode) 開始前,偵測 unattended mode。 若 unattended → 寫的 surfaced rows 全部用 `deferred` status + cite-registered reason literal,而非 `surfaced`。 Step 0.5 gate 對 reason-matched `deferred` rows proceed-with-warn,unattended chain 不再 silent break。

**Detection（#123/#222 — 經 unattended-contract 統一，TTY heuristic 移除）**:

```bash
# TTY check 在 harness 內恆真（#222）— 不得用。唯一可靠訊號 = state file + env var
# （contract 見 references/unattended-contract.md）。
. "$CLAUDE_PLUGIN_ROOT/scripts/lib/unattended-state.sh"
IS_UNATTENDED="false"
if is_unattended "$(git rev-parse --show-toplevel 2>/dev/null || pwd)"; then
  IS_UNATTENDED="true"
fi
```

**Reason literal**:cite [`rules/append-vs-modify.md` § Reason pattern registry](../../rules/append-vs-modify.md#reason-pattern-registry) — literal `unattended-auto-Step-4.6-deferred` 是 **single source of truth**;本 SKILL.md **不**內嵌字面拷貝。 Implementation 讀 registry table row corresponding to「originating action: `/idd-clarify` Step 4.8.A」。

**Behavior dispatch**:

| Mode | Action |
|------|--------|
| Attended (`IS_UNATTENDED=false`) | proceed to Step 5a normal — emit `surfaced` rows + AskUserQuestion downstream |
| Unattended (`IS_UNATTENDED=true`) | Step 5a emits rows with `status=deferred` + `reason=<registry-cited literal>` instead of `surfaced` (see Step 5a unattended variant below) |

`(category: state-field-update, scope: "### Clarity Surface" row status field — extended for unattended branch per #137)` per [`rules/append-vs-modify.md`](../../rules/append-vs-modify.md)。

### Step 5a: Scan mode — three-class detect

**Library load**:每次 invocation **fresh read**,no cache(per spec idd-clarify-skill scenario):

```bash
LIBRARY_FILE="$CLAUDE_PLUGIN_ROOT/references/terminology-canonical.md"
[ -f "$LIBRARY_FILE" ] || abort "Terminology library missing: $LIBRARY_FILE"
LIBRARY_CONTENT=$(cat "$LIBRARY_FILE")
```

**IC_R007 verbatim preservation guard**:

- **不** 修改 source blockquote(以 `>` 開頭的 line)— 只 annotate 在 body 末段加新 section
- **不** 修改任何既存 `### ` heading 內容

**Three-class scan**:

1. **Terminology** — body 內 domain term 對照 library row 的 "source term" + "context" pattern。Match → 預期 row:
   ```
   | terminology | "<quoted body excerpt>" | <library suggested_canonical> | surfaced |
   ```

2. **Ambiguity** — body 內 phrase 有 multiple plausible interpretations 且 critical variable under-specified。Heuristic:
   - "我們的 X / your X" 沒指明 X
   - "做 K-means" 沒指明 k value 範圍
   - Acronym 沒 expand 過(`API`/`MLM`/`PCA` 等)
   - Conflicting modifier(「快速但精確」)
   
   Match → 預期 row:
   ```
   | ambiguity | "<quoted body excerpt>" | <detected-interpretation candidates 列表> | surfaced |
   ```

3. **Missing-context** — body 描述 analysis / implementation 需要 input X 但 source 未指定。Heuristic:
   - "分析需要 customer data" 但無 customer table 來源
   - "join with sales" 但無 sales table 來源 / schema
   - "用 review 評分" 但無 review 評分 prompt / pipeline 規格
   
   Match → 預期 row:
   ```
   | missing-context | "<quoted body excerpt>" | <gap description: '<X> 來源未指定'> | surfaced |
   ```

**Compose `### Clarity Surface` block**:

```markdown
### Clarity Surface(idd-clarify run <ISO 8601 timestamp>)

| Type | Source | Suggested canonical | Status |
|---|---|---|---|
| terminology | "..." | ... | surfaced |
| ambiguity | "..." | ... | surfaced |
| missing-context | "..." | ... | surfaced |
```

**Empty surface case**:no detection → 仍 emit:

```markdown
### Clarity Surface(idd-clarify run <ISO 8601 timestamp>)

| Type | Source | Suggested canonical | Status |
|---|---|---|---|
| (none) | — | no issues detected | passed |
```

**Why emit empty marker**:避免 `Step 0.5` gate 把「沒跑過 clarify」跟「跑過、通過」混淆。passed row 是顯式 declaration。

**Unattended variant (v2.74.0+, #137)** — when Step 4.8.A detected `IS_UNATTENDED=true`,every detected surfaced row is written with `status=deferred` + `reason=unattended-auto-Step-4.6-deferred` (cited from rules/append-vs-modify.md § Reason pattern registry) **instead of** `surfaced`。 Schema extends to 5-column table:

```markdown
### Clarity Surface(idd-clarify run <ISO 8601 timestamp>, unattended)

| Type | Source | Suggested canonical | Status | Reason |
|---|---|---|---|---|
| terminology | "..." | ... | deferred | unattended-auto-Step-4.6-deferred |
| ambiguity | "..." | ... | deferred | unattended-auto-Step-4.6-deferred |
```

Attended-mode schema unchanged (4-column, no Reason). `/idd-diagnose` Step 0.5 gate handles both schemas — backward compatible。 Reason column absent → treated as legacy/manual `deferred` row(REFUSE behavior preserved per `rules/append-vs-modify.md` Backward-compat fallback section)。

### Step 5b: Update mode — row status mutation

```bash
# Validate row index
[[ ! "$STATUS_ROW_IDX" =~ ^[0-9]+$ ]] && abort "Invalid row index: $STATUS_ROW_IDX"

# Validate action
case "$STATUS_ACTION" in
  resolved|dismissed) ;;
  *) abort "Invalid status action: $STATUS_ACTION (must be resolved or dismissed)" ;;
esac

# Grep `### Clarity Surface` block in body
if ! echo "$BODY" | grep -q "^### Clarity Surface"; then
  abort "Issue #$NUMBER has no Clarity Surface block. Run /idd-clarify #$NUMBER first to populate."
fi

# Find row N (1-indexed within block)
# Extract block content, locate row N data line (skip header + separator)
# NOTE (v2.74.1+, #137 verify R1 fix): naive `awk '/^### Clarity Surface/,/^### /'`
# collapses on line 1 because start regex matches end regex (both `^### `),
# losing all rows. Use flag-based pattern + drop GNU-only `head -n -1`.
BLOCK=$(echo "$BODY" | awk '/^### Clarity Surface/{flag=1; print; next} flag && /^### /{flag=0} flag')
ROW_LINES=$(echo "$BLOCK" | grep -E "^\| (terminology|ambiguity|missing-context|\(none\))" | head -n "$STATUS_ROW_IDX" | tail -n 1)

[ -z "$ROW_LINES" ] && abort "Row index $STATUS_ROW_IDX out of range. Valid indices: 1..N (run /idd-clarify #$NUMBER without --status to see current rows)"

# Check transition: if current status is dismissed and new is resolved, preserve history
CURRENT_STATUS=$(echo "$ROW_LINES" | awk -F'|' '{print $5}' | sed 's/^ *//; s/ *$//')
TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

if [[ "$CURRENT_STATUS" =~ ^dismissed && "$STATUS_ACTION" = "resolved" ]]; then
  # Preserve dismissal timestamp
  OLD_TS=$(echo "$CURRENT_STATUS" | grep -oE '@ [0-9TZ:-]+' | head -1)
  NEW_STATUS="resolved (was: dismissed $OLD_TS; reason: $STATUS_REASON)"
elif [[ "$CURRENT_STATUS" =~ ^resolved && "$STATUS_ACTION" = "dismissed" ]]; then
  # Reverse transition (rare) — also preserve
  OLD_TS=$(echo "$CURRENT_STATUS" | grep -oE '@ [0-9TZ:-]+' | head -1)
  NEW_STATUS="dismissed (was: resolved $OLD_TS; reason: $STATUS_REASON)"
else
  # Plain transition from surfaced
  NEW_STATUS="$STATUS_ACTION @ $TIMESTAMP"
  [ -n "$STATUS_REASON" ] && NEW_STATUS="$STATUS_ACTION @ $TIMESTAMP (reason: $STATUS_REASON)"
fi

# Build sed replacement for that specific row in body
# (Implementation detail: use awk row indexing not blind sed substitution to avoid mismatching identical content)
```

### Step 6: PATCH body via gh issue edit

```bash
gh issue edit "$NUMBER" --repo "$GITHUB_REPO" --body "$NEW_BODY" 2>&1 | tail -1
```

### Step 7: Report and stop

**Scan mode**:
```
✓ /idd-clarify #N complete
  Rows surfaced: <count> (status=surfaced, awaiting resolution)
  Empty marker: <yes/no>
  Block location: end of issue body

Next:
  - Review each surfaced row in https://github.com/$GITHUB_REPO/issues/$NUMBER
  - Resolve: /idd-clarify #$NUMBER --status resolved=<idx>,<reason>
  - Dismiss: /idd-clarify #$NUMBER --status dismissed=<idx>,<reason>
```

**Update mode**:
```
✓ /idd-clarify #N row $ROW_IDX marked $STATUS_ACTION
  Status: $NEW_STATUS
  Block updated in issue body

Next:
  - View: gh issue view #$NUMBER -R $GITHUB_REPO
  - If all surfaced rows resolved/dismissed, /idd-diagnose #$NUMBER will no longer refuse
```

## Failure modes

| Situation | Behavior |
|---|---|
| Issue doesn't exist | abort with `gh issue view #N` exit code passthrough |
| Library file missing | abort with explicit path; suggest reinstall plugin |
| Empty `--status` reason | warning but proceed(reason 是 SHOULD,不是 SHALL)|
| `--status` row index out-of-range | abort with valid indices listed |
| `--status` action invalid | abort with `resolved|dismissed` 二選一錯誤 |
| `gh issue edit` fails | abort,body 未變更,user 重跑 |
| Already-resolved row + same action | idempotent — overwrite reason / no-op,exit 0 |
| Race condition(body 改變)| acceptable — last-write-wins per gh issue edit semantics |

## Behavior contracts

詳細 normative requirements 見 `openspec/specs/idd-clarify-skill/spec.md`。

四個 capability requirements:
1. Standalone primitive surfacing(scan mode)
2. Status resolution interface(update mode)
3. Operates on existing issues only
4. Terminology library reload per invocation

## 鐵律

- **Surface-only**:不替 user 找答案,不 PATCH 既存 blockquote。
- **Library fresh-read every invocation**:無 cache,user 改 library 立即生效。
- **Audit trail forever**:`--status` 更新 row,**不**刪 row(歷史保留)。
- **Empty surface 仍 emit passed marker**:`Step 0.5` gate 需區分「沒跑」跟「跑過通過」。
- **IC_R007 verbatim preservation**:不動 source blockquote,annotation 加在 body 末段。

## Examples

### Example 1: scan mode against #804(K-means 特徵值 case)

```bash
/idd-clarify #804
```

Expected output:
```
✓ /idd-clarify #804 complete
  Rows surfaced: 2
  Empty marker: no

Annotation appended:

### Clarity Surface(idd-clarify run 2026-05-22T03:42:18Z)

| Type | Source | Suggested canonical | Status |
|---|---|---|---|
| terminology | "可否 prompt 跟他說各群要有至少一個最高得分的特徵值" | 分群變數 / distinguishing variable (per K-means context, library row 1) | surfaced |
| missing-context | "請根據上面網址的Ｋ欄的情感、人、場..." | customer × attribute score 來源未指定(GSheet 只有 metadata) | surfaced |
```

### Example 2: dismiss a false positive

```bash
/idd-clarify #804 --status dismissed=1,客戶確認特徵值在這 context 是 eigenvalue 意義
```

Output:
```
✓ /idd-clarify #804 row 1 marked dismissed
  Status: dismissed @ 2026-05-22T03:48:12Z (reason: 客戶確認特徵值在這 context 是 eigenvalue 意義)
```

### Example 3: resolved after domain expert clarification

```bash
/idd-clarify #804 --status resolved=2,老師確認從 review AI 評分產生 df_qef_customer_attributes
```

### Example 4: dismissed → resolved transition

```bash
# Step 1: dismissed earlier
/idd-clarify #100 --status dismissed=3,看似 misuse 其實正確

# Step 2: 後來 domain expert push back
/idd-clarify #100 --status resolved=3,確認是 misuse,改用 canonical
```

After step 2 the row status:
```
| ... | resolved (was: dismissed @ 2026-05-21T22:18:33Z; reason: 確認是 misuse, 改用 canonical) |
```

Original dismissal timestamp preserved per audit-trail rule。

## Next Step

依使用 mode 而異:

- 跑完 scan mode → user review surfaced rows,用 `--status` resolve / dismiss 處理
- 跑完 update mode → 確認後 `/idd-diagnose #N` 進 routing(若全 resolve/dismiss)
- 對 issue ready 進 IDD pipeline → `/idd-diagnose #N`
