---
name: idd-config
description: |
  管理 IDD 的 target-repo config（`.claude/issue-driven-dev.local.json`）。
  四個 subcommand：show（預設）/ init / validate / which。
  按 [config-protocol](../../references/config-protocol.md) 操作；不開 issue、不改其他狀態。
  Use when: 第一次 setup、看當前 target、debug monorepo predicate routing、驗證 schema 合法。
  防止的失敗：跑 idd-issue 才發現 config 缺、predicate 寫錯只在實際 issue 創建時才報、不知 cwd 落在哪個 candidate / group。
argument-hint: "[show | init | validate | which]"
allowed-tools:
  - Bash(gh:*)
  - Bash(git:*)
  - Bash(jq:*)
  - Bash(cat:*)
  - Bash(test:*)
  - Bash(find:*)
  - Read
  - Write
  - AskUserQuestion
---

# /idd-config — 管理 IDD Target Repo Config

`.claude/issue-driven-dev.local.json` 的獨立管理入口。把原本散落在 `idd-issue` Step 0.5、`idd-list` 開頭的 config 邏輯抽出來，讓 setup / inspect / validate 可獨立呼叫。

## 為什麼要有這個 skill

在 `idd-config` 出現之前：

| 場景 | 唯一做法 |
|------|---------|
| 第一次 setup | 跑 `/idd-issue` 觸發 fork-detection 寫 config（必須順便建一個 issue 才能 setup） |
| 看現在 target | `cat .claude/issue-driven-dev.local.json`（要記得 path） |
| 驗證 monorepo predicate | 跑 `/idd-issue` 才知道 predicate 解析到哪 |
| 切換 candidate / group | 手寫 JSON |

每個都要繞 `idd-issue`、或手動編輯 JSON。`idd-config` 提供**不創 issue、不改 GH 狀態**的純 config 操作介面。

## 範圍（Phase 1，最小可用）

- `show`（沒 args 時的預設）
- `init`
- `validate`
- `which`

> **Submodule boundary (#162)**：`which` 執行時同時跑 `scripts/lib/resolve-submodule-route.sh`（source 後呼叫 `resolve_submodule_route <submodules值>`）並顯示偵測結果 — cwd 在 submodule 內時，顯示將路由到 submodule origin 還是 parent config（依 `submodules` key，預設 `auto`）。

**不做**（v2 再加）：
- `set-target` / `add-candidate` / `add-group` / `remove-*` 等 mutating subcommands（先用直接編輯 JSON）
- 全局 config（`~/.claude/issue-driven-dev.global.json`）— config-protocol 目前 only walked-up local config

## Subcommand 規格

### `show`（預設）

不傳 args、或傳 `show`：列出當前 cwd 解析到的 config + 來源 + resolved target。

```bash
/idd-config           # 等同 /idd-config show
/idd-config show
```

#### Steps

```
TaskCreate(name="show_walk_config", description="從 cwd 往上 walk 找 IDD config（新路徑 .claude/.idd/local.json 優先,legacy 次之,#195）")
TaskCreate(name="show_resolve_target", description="若有 candidates/groups，跑 path-class predicate 解析 tentative target")
TaskCreate(name="show_print", description="輸出 config path / github_repo / tracking_upstream / candidates / groups / resolved")
```

#### Output 範例

```
=== IDD Config (cwd: /Users/che/Library/CloudStorage/Dropbox/...) ===

Config file:    /Users/che/Library/CloudStorage/.../.claude/issue-driven-dev.local.json
Format:         JSON (legacy MD format also supported, see config-protocol.md)

Default target: kiki830621/collaboration_guo_analysis
Tracking upstream: (none)
Attachments release: attachments

Candidates: (none)
Groups: (none)
ask_each_time: false

Resolved for current cwd: kiki830621/collaboration_guo_analysis (default github_repo)
```

若無 config：

```
=== IDD Config (cwd: ...) ===
No config found. Walked up to / and didn't find .claude/issue-driven-dev.local.json.
Run `/idd-config init` to create one.
```

### `init`

互動式建立 `.claude/issue-driven-dev.local.json`。等同抽出 `idd-issue` Step 0.5.E (fork-aware detection)。

```bash
/idd-config init
```

#### Steps

```
TaskCreate(name="init_check_existing", description="若 .claude/.idd/local.json（或 legacy .claude/issue-driven-dev.local.json）已存在 → AskUserQuestion 確認覆蓋")
TaskCreate(name="init_detect_origin", description="git remote get-url origin → 取 owner/repo")
TaskCreate(name="init_check_fork", description="gh repo view --json isFork,parent,viewerPermission → fork + third-party 偵測(#192)")
TaskCreate(name="init_ask_target", description="AskUserQuestion: fork → Upstream/Own fork/Both;third-party → Upstream/tracking repo/local-only(順序 E2 fork → E-TP → E1)")
TaskCreate(name="init_write_config", description="寫新路徑 .claude/.idd/local.json（#195；mkdir -p .claude/.idd 先）")
TaskCreate(name="init_show_result", description="show 一次驗收")
```

#### Algorithm（與 idd-issue Step 0.5.E 等價）

```bash
ORIGIN=$(git remote get-url origin 2>/dev/null | sed -E 's#(\.git)?$##; s#.*[:/]([^/]+/[^/]+)$#\1#')

if [ -z "$ORIGIN" ]; then
  AskUserQuestion(
    question="No git remote found at $PWD. Manually specify owner/repo?",
    options=["Enter owner/repo", "Cancel"]
  )
  # if Enter → prompt for "owner/repo" string
fi

REPO_JSON=$(gh repo view "$ORIGIN" --json isFork,parent,viewerPermission 2>/dev/null)
IS_FORK=$(echo "$REPO_JSON" | jq -r '.isFork')
UPSTREAM=$(echo "$REPO_JSON" | jq -r '.parent.nameWithOwner // empty')

# third-party clone 偵測(hybrid,#192;同 idd-issue Step 0.5.E)
ORIGIN_OWNER="${ORIGIN%%/*}"
SELF_LOGIN=$(gh api user --jq .login 2>/dev/null)
IS_THIRD_PARTY=false
if [ -n "$SELF_LOGIN" ] && [ "$ORIGIN_OWNER" != "$SELF_LOGIN" ]; then
  VPERM=$(echo "$REPO_JSON" | jq -r '.viewerPermission // empty')
  case "$VPERM" in
    WRITE|MAINTAIN|ADMIN) IS_THIRD_PARTY=false ;;
    READ|TRIAGE)          IS_THIRD_PARTY=true  ;;
    *)                    IS_THIRD_PARTY=true        # 空 / NONE / probe 失敗 → fail-safe，且明示提示
                          echo "ℹ third-party detection: push-permission probe unavailable for $ORIGIN (viewerPermission='$VPERM') — applying conservative third-party default." >&2 ;;
  esac
fi

# 解析順序(同 Step 0.5.E):E2 fork → E-TP third-party → E1 own
TRACKING_UPSTREAM=""; PR_POLICY_OUT=""
if [ "$IS_FORK" = "true" ] && [ -n "$UPSTREAM" ]; then
  # E2: fork → AskUserQuestion three-option
  AskUserQuestion(
    question="$ORIGIN is a fork of $UPSTREAM. Where do new issues go by default?",
    options=[
      "Upstream ($UPSTREAM)",                # bug reports / contributions
      "Own fork ($ORIGIN)",                  # personal TODOs / customization
      "Both — primary upstream + tracking origin"  # ad-hoc group
    ]
  )
  case "$choice":
    "Upstream":   TARGET="$UPSTREAM"; TRACKING_UPSTREAM="$UPSTREAM"
    "Own fork":   TARGET="$ORIGIN";   TRACKING_UPSTREAM="$UPSTREAM"
    "Both":       TARGET="$UPSTREAM"; TRACKING_UPSTREAM="$ORIGIN"
                  # writes a group entry instead — see below
elif [ "$IS_THIRD_PARTY" = "true" ]; then
  # E-TP: third-party clone(無 push 權,#192)→ 三選項,預設不污染對方 repo
  AskUserQuestion(
    question="$ORIGIN looks like a third-party clone (not yours, no push access). Where do issues go?",
    options=[
      "Upstream ($ORIGIN) — ⚠ public, visible to the author",
      "Your own tracking repo (enter owner/repo) — not auto-created",
      "Local-only — no GitHub issues"
    ]
  )
  case "$choice":
    "Upstream":            TARGET="$ORIGIN"
    "Your tracking repo":  TARGET="<entered owner/repo>"
    "Local-only":          TARGET=""        # 不寫 github_repo;提示 GitHub-backed idd-* 暫不可用
  PR_POLICY_OUT="never"                      # 無 push 權 → local direct-commit
  # third-party 寫法見下方 "third-party 額外寫入"
else
  # E1: 你自己的 repo / 你能寫的 org repo → 直接用 origin
  TARGET="$ORIGIN"
fi

# #195: write the new path .claude/.idd/local.json (matches config-protocol;
# legacy issue-driven-dev.local.json still resolves via walk-up fallback).
mkdir -p .claude/.idd
cat > .claude/.idd/local.json <<EOF
{
  "github_repo": "$TARGET",
  "github_owner": "$(echo $TARGET | cut -d/ -f1)",
  "attachments_release": "attachments"$([ -n "$TRACKING_UPSTREAM" ] && echo ",
  \"tracking_upstream\": \"$TRACKING_UPSTREAM\"")
}
EOF
```

#### E-TP（third-party clone）額外寫入（#192）

若走 E-TP 分支且選了 target（非 Local-only），**不**用上面的 cat block，改用 third-party 寫法（同 `idd-issue` Step 0.5.E F 段）：

1. config 寫到**新路徑** `.claude/.idd/local.json`，含 `"pr_policy": "never"`：

```bash
mkdir -p .claude/.idd
cat > .claude/.idd/local.json <<EOF
{
  "github_repo": "$TARGET",
  "github_owner": "$(echo $TARGET | cut -d/ -f1)",
  "attachments_release": "attachments",
  "pr_policy": "never"
}
EOF
```

2. 用共用 helper 把 IDD config 寫進 `.git/info/exclude`（per-clone、不 commit/push、不動對方 `.gitignore`）：

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/git-ignore-block.sh" \
  --target "$(git rev-parse --git-dir)/info/exclude" \
  --marker "IDD third-party clone config (#192)" \
  --direction exclude \
  ".claude/.idd/" ".claude/issue-driven-dev.local.json" ".claude/issue-driven-dev.local.md"
```

Local-only（`TARGET=""`）：不寫 `github_repo`，提示 GitHub-backed idd-* 暫不可用。

#### "Both" 模式特殊處理

若使用者選 Both，寫 ad-hoc group：

```jsonc
{
  "github_repo": "$UPSTREAM",      // primary
  "github_owner": "...",
  "tracking_upstream": "$ORIGIN",
  "attachments_release": "attachments",
  "groups": [
    {
      "label": "fork-cross-link",
      "repos": [
        { "github_repo": "$UPSTREAM", "role": "primary" },
        { "github_repo": "$ORIGIN", "role": "tracking" }
      ]
    }
  ]
}
```

### `validate`

讀 IDD config（新路徑 `.claude/.idd/local.json` 優先,legacy `.claude/issue-driven-dev.local.json` 次之,#195），schema 檢查。

```bash
/idd-config validate
```

#### Steps

```
TaskCreate(name="validate_load", description="讀 IDD config（.claude/.idd/local.json 優先,legacy 次之,#195），JSON parse")
TaskCreate(name="validate_schema", description="檢查 required fields + 各 candidates/groups 結構")
TaskCreate(name="validate_collaborators", description="若有 collaborators[]：github_login 必填+格式、display_name 必填、role enum、aliases 全域唯一；email 出現→PII warning（#86）")
TaskCreate(name="validate_repo_exists", description="對 github_repo / candidates[].github_repo / groups[].repos[].github_repo 跑 gh repo view 驗證實際存在")
TaskCreate(name="validate_predicate_form", description="when 區塊 path_contains / title_matches 等 key 是 known set")
TaskCreate(name="validate_report", description="輸出 PASS / list of issues")
```

#### Schema check rules

- **required**: `github_repo`（除非有 `groups[]` 含 primary）
- `github_repo` 形式：`owner/repo`（regex `^[\w\-\.]+/[\w\-\.]+$`）
- `candidates[].github_repo` 同上
- `groups[]` 必須有**剛好一個** `role: "primary"`
- `collaborators[]`（若存在，schema 見 [config-protocol.md](../../references/config-protocol.md)「`collaborators[]` field」）：每個 entry `github_login` **必填**且符合 GitHub login charset `^[A-Za-z0-9-]+$`（明顯錯字如含空白/`@`/中文 → error）；`display_name` **必填**非空；`role`（若有）∈ `{maintainer, collaborator, advisor, external}`（其餘 → warning）；**`aliases` 全域唯一** —— 跨所有 entry 的 `aliases` + `github_login` 攤平後不得重複（否則 fuzzy match 會 ambiguous，這是 error）
- `collaborators[].email` 若出現 → **PII 提醒**（warning，非 error）：email 是可識別個資，不該進 committed/public config，只放 private/gitignored config layer（見 config-protocol.md「PII boundary」）
- `when.path_contains` / `path_matches` / `title_matches` / `label_in` / `git_remote_matches` / `git_branch_matches` / `all` / `any` / `not` — 不認識的 key → warning（不 fail）
- `gh repo view` 對每個 repo 跑（warning 而非 error，因為 private repo 無權限會失敗但 config 本身可能合法）

#### Output

```
✓ JSON valid
✓ github_repo: kiki830621/collaboration_guo_analysis (exists)
✓ tracking_upstream: PsychQuant/macdoc (exists)
⚠ candidates[0].when has unknown key 'directory_contains' (did you mean 'path_contains'?)
✓ groups: 1 group, 1 primary, 1 tracking
PASS (1 warning)
```

### `which`

dry-run target resolution at current cwd — 顯示「如果現在跑 `/idd-issue` 會 route 到哪」。可帶 mock title / labels 模擬 content predicate。

```bash
/idd-config which
/idd-config which --title "fix MCP tool error"
/idd-config which --title "..." --label bug,P0
```

#### Steps

```
TaskCreate(name="which_load_config", description="load config")
TaskCreate(name="which_phase05", description="跑 path-class predicates → tentative_default")
TaskCreate(name="which_phase25", description="若有 --title/--labels → 跑 content predicates → final match")
TaskCreate(name="which_print", description="顯示 step-by-step resolution trace")
```

#### Output

```
=== Resolution trace (cwd: /Users/che/Library/.../teaching/2025/0821 guo) ===

Phase 0.5 (path/git predicates):
  candidates[0] "Music workspace" when.path_contains="creative/music" → MISS
  candidates[1] "Plugin marketplace" when.title_matches="..." → SKIP (Phase 0.5 doesn't evaluate content)
  → tentative_default: kiki830621/collaboration_guo_analysis (config.github_repo fallback)

Phase 2.5 (content predicates, with --title="fix MCP tool error" --label="bug"):
  candidates[1] "Plugin marketplace" when.title_matches="(?i)\\b(plugin|mcp|skill)\\b" → MATCH (mcp)
  → would prompt: "switch from collaboration_guo_analysis to PsychQuant/psychquant-claude-plugins?"

Final (assuming user picks default): kiki830621/collaboration_guo_analysis
Final (if user accepts switch): PsychQuant/psychquant-claude-plugins
```

## Cross-skill 影響（informational, this skill 不動）

`idd-issue` Step 0.5.E 邏輯仍保留以維持 backward compat，但 SKILL.md 應加一句「也可預先用 `/idd-config init` 建好」。等所有 idd-* skills 都引用統一 helper 後，可在 v3.0 把 fork-detection 從 idd-issue 抽掉。

## 不做的事

- **不開 issue**：不論 subcommand 都不呼叫 `gh issue create`
- **不改 GitHub state**：純 local config 操作（`gh repo view` 只是 read 驗證）
- **不寫 `~/.claude/`**：global config 在 config-protocol 還沒設計好，先不做
- **不替你 commit `.claude/issue-driven-dev.local.json`**：那是 user 的 local 決定，且該檔通常 gitignored

## 與其他 IDD skills 的關係

| | `idd-config` | `idd-issue` | `idd-list` |
|---|---|---|---|
| 創 issue | ✗ | ✓ | ✗ |
| 讀 config | ✓ | ✓（內嵌） | ✓（內嵌） |
| 寫 config | ✓ init | ✓ E1/E2 fallback | ✗ |
| 解析 target | show / which | Step 0.5 + 2.5 | Step 0.5（path-only） |
| 改 GH state | ✗ | ✓ | ✗ |

## Next Step

設好之後接 `/idd-issue` 開第一個 issue：

```bash
/idd-config init
/idd-config validate
/idd-issue ...
```
