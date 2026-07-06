# Distribution Detection Contract

> Canonical contract for detection helpers used by `/idd-close` Step 6.5 (Distribution Sync chain) and any future skill that needs to know whether a repo ships its changes to a user-facing distribution channel.

**Source**: `idd-close-distribution-sync` change for issue #45 — close-tier checkpoint that complements `che-claude-config/rules/common-release-flow.md` (release-tier).

## Purpose

For repos whose fixes reach users via plugin marketplace / MCP binary / CLI binary distribution, IDD lifecycle close has a one-more-mile dropped step: bumping `marketplace.json` or invoking `mcp-deploy`. Without a mechanical checkpoint at close time, "fixed but not shipped" anti-pattern recurs.

This contract specifies how `/idd-close` Step 6.5 detects whether the closing repo is distributed and which sync skill to chain to. Detection is **read-only** — no state changes, no network calls beyond `gh repo view` style metadata.

## Distribution types

| Type | Detection signal | Sync skill |
|------|-----------------|-----------|
| `plugin` | Repo or any subdir is listed as `plugins[].source` (string `"./plugins/<name>"`) in some ancestor `.claude-plugin/marketplace.json` | `/plugin-tools:plugin-update <plugin-name>` |
| `mcp` | `$REPO_ROOT/bin/*.sh` contains GitHub release URL pattern (`gh release download` / `gh api .../releases` / `api.github.com/.../releases` / `github.com/.../releases/(download\|tags\|latest)` — line-agnostic, matches variable-substituted URLs) AND wrapper script name matches `*-mcp-wrapper.sh` (or contains `mcp` substring) | `/mcp-tools:mcp-deploy` |
| `cli` | Same wrapper detection as MCP, but wrapper script name does NOT match MCP heuristic | `/cli-tools:cli-deploy` |
| `plugin+mcp` | Both signals trigger | `/mcp-tools:mcp-deploy` → then `/plugin-tools:plugin-update <plugin-name>` (D3 v1: explicit ordering, see below) |
| `plugin+cli` | Both signals trigger | `/cli-tools:cli-deploy` → then `/plugin-tools:plugin-update <plugin-name>` (D3 v1: explicit ordering, see below) |
| `n/a` | None of the above | — silent skip |

## Detection helpers

These are intended to be implemented inline in `idd-close/SKILL.md` Step 6.5 bash, but documented here as the canonical algorithm for any future caller.

### `is_plugin_marketplace_member(repo_root, github_repo) -> bool`

Walk-up parents from `$REPO_ROOT` looking for `.claude-plugin/marketplace.json`, **stop at `$HOME`** (same convention as `find_idd_config` in `references/config-protocol.md`).

```bash
is_plugin_marketplace_member() {
  local repo_root="$1"
  local github_repo="$2"   # owner/repo form (unused in v1 — kept for v2 git-remote variant)
  local resolved_root
  resolved_root=$(cd "$repo_root" 2>/dev/null && pwd -P) || resolved_root="$repo_root"
  local current="$resolved_root"

  # Walk up to (and including) $HOME. The do-while-style first-pass check below
  # ensures `$REPO_ROOT == $HOME` doesn't fall through unscanned.
  while :; do
    local manifest="$current/.claude-plugin/marketplace.json"
    if [ -f "$manifest" ]; then
      # Marketplace plugin schema: `"source": "./plugins/<name>"` (string, relative
      # to manifest dir). Resolve each source path and compare to repo_root —
      # match means this repo IS one of the plugins listed by the marketplace.
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
            # Match if plugin_dir IS repo_root (repo == one plugin)
            # OR plugin_dir is INSIDE repo_root (repo hosts plugins under plugins/, common monorepo layout).
            # Trailing slash check prevents prefix collisions (e.g. repo=/foo, plugin_dir=/foobar).
            case "$plugin_dir/" in
              "$resolved_root/"|"$resolved_root/"*)
                echo "match"
                break
                ;;
            esac
          done | head -1)
      if [ -n "$match" ]; then
        echo "true"
        return 0
      fi
    fi
    [ "$current" = "$HOME" ] && break
    [ "$current" = "/" ] && break
    current=$(dirname "$current")
  done
  echo "false"
}
```

**Stop conditions**: walks up through `$HOME` itself (so repos cloned directly to `$HOME` are scanned), then breaks. `/` is a safety bound. Path resolution via `pwd -P` normalizes symlinks (handles macOS `/Users` ↔ `/private/var/...` cases).

**Match logic**: marketplace.json plugins use `"source": "./plugins/<name>"` (string, relative to manifest dir). For each plugin entry, resolve `<manifest_dir>/<source>` to absolute path and compare to canonicalized `$REPO_ROOT`. A match means this repo IS one of the plugins published by that marketplace — could be the marketplace's own repo (self-publishing) or a submodule path.

**Schema note**: object form `{"source": {"git": "..."}}` is not currently used in any inspected real marketplace.json (37/37 use string form). If future marketplace.json adopts object form, jq filter would need a parallel branch — but the `select(type == "string")` guard makes the current filter safe (skips non-string sources rather than erroring).

### `has_binary_wrapper(repo_root) -> bool`

Scan `$REPO_ROOT/bin/*.sh` (literal pattern, not recursive) for known distribution patterns.

```bash
has_binary_wrapper() {
  local repo_root="$1"
  local bin_dir="$repo_root/bin"

  [ -d "$bin_dir" ] || { echo "false"; return; }

  # Real-world wrappers (e.g. `che-apple-mail-mcp-wrapper.sh`, `agent-cacher`)
  # construct GitHub URLs in variables (`API_URL=https://api.github.com/...`,
  # `asset_url="https://github.com/.../releases/download/..."`) then call
  # curl on a separate line. Line-anchored regex misses these. The pattern
  # below matches any line containing GitHub release URL patterns OR explicit
  # `gh release download` / `gh api .../releases` invocations.
  # Match either explicit gh CLI invocations or GitHub URL patterns. Use .* between
  # github.com and `releases` to accept variable-substituted single-segment paths
  # (e.g. `https://github.com/${GITHUB_REPO}/releases/...` where the variable holds
  # the full `owner/repo`); grep is line-based so .* won't span lines.
  local pattern='gh release download|gh api[[:space:]]+.*/releases|api\.github\.com/.*/releases|github\.com/.*/releases/(download|tags|latest)'

  # Glob may not match — guard with a 2>/dev/null + null-check
  local match=""
  shopt -s nullglob 2>/dev/null
  for f in "$bin_dir"/*.sh; do
    [ -f "$f" ] || continue
    if grep -qE "$pattern" "$f" 2>/dev/null; then
      match="$f"
      break
    fi
  done
  shopt -u nullglob 2>/dev/null

  [ -n "$match" ] && echo "true" || echo "false"
}
```

**Why `bin/*.sh` only**: build/dev scripts typically live under `scripts/` or `Sources/`;user-facing distribution wrappers conventionally live under `bin/`. False-positive on a non-distribution `bin/*.sh` is covered by AskUserQuestion `not applicable` opt-out (see Step 6.5 prose).

**Detection keywords (broadened from v1)**: matches:
- `gh release download` — explicit GitHub CLI download
- `gh api[[:space:]]+.*/releases` — GitHub API via gh CLI
- `api\.github\.com/repos/.../releases` — direct REST API URL (real-world pattern: `che-apple-mail-mcp-wrapper.sh`)
- `github\.com/.../releases/(download|tags|latest)` — public release URLs (real-world pattern: `cacher-mcp-wrapper.sh` `asset_url=`)

Empirically validated: matches all 13 PsychQuant MCP wrappers + `idd-route` CLI wrapper. Future patterns (wget, npm) covered by Extension protocol below.

### `resolve_plugin_name(repo_root) -> string`

Returns the **plugin `name` field** from the marketplace.json entry whose `source` resolves to `repo_root` (or a subdir of it). Required when chain target is `plugin-update <plugin-name>` — Step 6.5 calls this AFTER `is_plugin_marketplace_member` returns true. Empty output if no match (caller must check).

```bash
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
      # Iterate plugin entries with both name and source. For each, resolve source
      # path and check if matches repo_root prefix; emit name on match.
      local name_match
      name_match=$(jq -r '.plugins[]? | select(.source | type == "string") | "\(.name)\t\(.source)"' \
        "$manifest" 2>/dev/null \
        | while IFS=$'\t' read -r pname psrc; do
            [ -z "$pname" ] && continue
            local plugin_dir
            plugin_dir=$(cd "$manifest_dir/$psrc" 2>/dev/null && pwd -P) || continue
            case "$plugin_dir/" in
              "$resolved_root/"|"$resolved_root/"*)
                echo "$pname"
                break
                ;;
            esac
          done | head -1)
      [ -n "$name_match" ] && { echo "$name_match"; return 0; }
    fi
    [ "$current" = "$HOME" ] && break
    [ "$current" = "/" ] && break
    current=$(dirname "$current")
  done
  # No match — return empty (caller checks via [ -z "$NAME" ])
  echo ""
}
```

**Monorepo host case（v2, #68）**: `scripts/lib/resolve-plugin-candidates.sh` 的 `resolve_plugin_candidates <repo_root> [<cwd>]` 回**全部**匹配 plugin，依 cwd specificity 排序（plugin dir 是 cwd 祖先者最前、越深越前；path-boundary 安全 — `beta-extra` 不被 `beta` 前綴誤吃）。Caller（Step 6.5）契約：0 → silent skip（非 plugin close）；1 → proceed；N>1 attended → AskUserQuestion（top-3 + Other）；N>1 unattended → 取最 specific 候選 + audit note（non-blocking）。`resolve_plugin_name` 保留為 v1 相容 wrapper（首候選）。測試：`scripts/tests/resolve-plugin-candidates/`。

### `infer_distribution_type(repo_root, github_repo) -> string`

Orchestrator returning one of: `plugin` / `mcp` / `cli` / `plugin+mcp` / `plugin+cli` / `n/a`.

```bash
infer_distribution_type() {
  local repo_root="$1"
  local github_repo="$2"

  local is_plugin=$(is_plugin_marketplace_member "$repo_root" "$github_repo")
  local has_wrapper=$(has_binary_wrapper "$repo_root")

  local binary_kind=""
  if [ "$has_wrapper" = "true" ]; then
    # MCP vs CLI heuristic via wrapper script name
    local mcp_match=$(ls "$repo_root/bin"/*.sh 2>/dev/null \
      | grep -E '(-mcp-wrapper\.sh$|/[^/]*mcp[^/]*\.sh$)' | head -1)
    if [ -n "$mcp_match" ]; then
      binary_kind="mcp"
    else
      binary_kind="cli"
    fi
  fi

  if [ "$is_plugin" = "true" ] && [ -n "$binary_kind" ]; then
    echo "plugin+$binary_kind"
  elif [ "$is_plugin" = "true" ]; then
    echo "plugin"
  elif [ -n "$binary_kind" ]; then
    echo "$binary_kind"
  else
    echo "n/a"
  fi
}
```

## D3 — Mixed-type handling (v1: explicit ordering, fallback-safe)

When `infer_distribution_type` returns `plugin+mcp` or `plugin+cli`, **chain BOTH skills with explicit ordering**: binary-deploy first (`mcp-deploy` or `cli-deploy`), then `plugin-update` to bump plugin shell pointing at the new binary version.

**Rationale (v1)**: ordering binary-first is correctness-safe regardless of whether `plugin-update` cascades. If cascade exists (per `common-plugins.md` claim), calling binary-deploy first means `plugin-update`'s Phase 1.5 detection sees the already-bumped binary and skips its own cascade prompt (idempotent). If cascade doesn't exist or has changed, calling both ensures both shells stay in sync — exact anti-pattern #45 was designed to prevent.

**Why not v2 superset rule yet**: the original Plan tier proposed "chain `plugin-update` only" relying on Phase 1.5 cascade per `che-claude-config/rules/common-plugins.md`. PsychQuant/issue-driven-development#66 audit was filed during /idd-plan to verify this claim empirically before relying on it. Until #66 confirms cascade behavior matches doc claim, **v1 default is "chain both" for safety**.

**Future v2 (post-#66 audit)**: if #66 confirms `plugin-update` v1.11+ Phase 1.5 reliably cascades to `mcp-deploy` / `cli-deploy`, this contract may change to "chain `plugin-update` only" superset rule. v2 contract would document explicit cascade dependency on `plugin-update` v1.11+ and include version check.

## Skill resolution table (v1)

| `infer_distribution_type` returns | Sync skills to chain (in order) |
|----------------------------------|---------------------------------|
| `plugin` | `/plugin-tools:plugin-update <plugin-name>` |
| `mcp` | `/mcp-tools:mcp-deploy` |
| `cli` | `/cli-tools:cli-deploy` |
| `plugin+mcp` | `/mcp-tools:mcp-deploy` → then `/plugin-tools:plugin-update <plugin-name>` |
| `plugin+cli` | `/cli-tools:cli-deploy` → then `/plugin-tools:plugin-update <plugin-name>` |
| `n/a` | — silent skip, no chain |

**Plugin name resolution** (when `<plugin-name>` is needed): parse the matched `marketplace.json` entry — its `name` field IS the plugin name to pass to `plugin-update`.

## Caller skill `--source-issue` flag

`/idd-close` Step 6.5 v1 invokes target skill **without** `--source-issue` flag — caller skills (`plugin-update` / `mcp-deploy` / `cli-deploy`) in `psychquant-claude-plugins` repo don't yet support it (deferred to sister issue per #45 Step 4.7 scope clarification). Graceful: target skills ignore unknown flags.

When sister issue lands flag support, this contract gains a v2 invocation form: `/plugin-tools:plugin-update <name> --source-issue $NUMBER` so the resulting marketplace commit message includes the source issue ref for traceability.

## Escape hatch / rollback

Env var `IDD_DISTRIBUTION_SYNC_PROMPT=false` silently skips Step 6.5 prompt entirely (still 1-line audit `Distribution sync prompt skipped (IDD_DISTRIBUTION_SYNC_PROMPT=false)` in closing comment for traceability).

**Detection-based silent skip** (non-distribution repo) is **always-on** — env var only suppresses the prompt for distribution-detected repos.

Rationale: CI / batch runs need disable to avoid AskUserQuestion blocking. Pattern-symmetric with IC_R011 `AI_LOW_BAR_ISSUE_FILING=false` rollback (see `references/ic-r011-checkpoint.md` §5).

## Extension protocol — adding distribution patterns

If a user's wrapper uses unlisted keyword (e.g. `wget`, `npm install`, `brew install`):

1. **Update the regex in TWO places** (helpers are inlined in skill, not sourced from this doc):
   - `has_binary_wrapper` regex in this contract (canonical spec)
   - `has_binary_wrapper` regex inlined in `plugins/issue-driven-dev/skills/idd-close/SKILL.md` Step 6.5 detection block
2. Document the new pattern in this contract under "Detection keywords" section
3. Smoke-test against the repo that has the unusual wrapper

**Rationale**: this contract is the canonical spec — Step 6.5 inlines the algorithm rather than sourcing the doc at runtime (skills don't `source` reference markdown). Two-location update is unavoidable until skills gain a doc-import mechanism;the contract doc is the source of truth that drift checks should compare against.

## Test fixtures (manual smoke matrix)

(No automated test framework yet — covered by PsychQuant/issue-driven-development#62 follow-up.)

| # | Repo | Setup | `infer_distribution_type` returns |
|---|------|-------|-----------------------------------|
| 1 | `issue-driven-dev` plugin via marketplace | `cd ~/Developer/issue-driven-development;` `marketplace.json` ancestor at `~/Developer/psychquant-claude-plugins/.claude-plugin/marketplace.json` lists this repo | `plugin` |
| 2 | Pure MCP binary | `cd ~/Developer/some-mcp;` `bin/some-mcp-wrapper.sh` contains `gh release download` | `mcp` |
| 3 | Pure CLI binary | `cd ~/Developer/some-cli;` `bin/install.sh` contains `curl https://github.com/.../releases/download/...` | `cli` |
| 4 | Mixed plugin + MCP (`che-zotero-mcp`) | both signals | `plugin+mcp` |
| 5 | Non-distribution (this repo without marketplace context) | no `bin/*.sh` matching, no marketplace.json ancestor | `n/a` |

## Cross-references

- `idd-close/SKILL.md` Step 6.5 — primary consumer of this contract
- `che-claude-config/rules/common-release-flow.md` — complementary release-tier trigger (post-release marketplace sync)
- `references/ic-r011-checkpoint.md` — canonical 3-option AskUserQuestion pattern that Step 6.5 conforms to
- `references/config-protocol.md` `find_idd_config` — same walk-up convention used by `is_plugin_marketplace_member`
- PsychQuant/issue-driven-development#66 — audit of `common-plugins.md` plugin-update Phase 1.5 cascade claim that D3 superset rule depends on
- PsychQuant/issue-driven-development#62 — test infra follow-up (will eventually validate the smoke matrix above)

## Versioning

This contract is **v1**. Breaking changes (e.g. adding required fields to `infer_distribution_type` output) increment to v2 and require coordinated update of all consumers (currently only `idd-close/SKILL.md`).
