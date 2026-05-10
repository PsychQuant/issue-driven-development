# Distribution Detection Contract

> Canonical contract for detection helpers used by `/idd-close` Step 6.5 (Distribution Sync chain) and any future skill that needs to know whether a repo ships its changes to a user-facing distribution channel.

**Source**: `idd-close-distribution-sync` change for issue #45 — close-tier checkpoint that complements `che-claude-config/rules/common-release-flow.md` (release-tier).

## Purpose

For repos whose fixes reach users via plugin marketplace / MCP binary / CLI binary distribution, IDD lifecycle close has a one-more-mile dropped step: bumping `marketplace.json` or invoking `mcp-deploy`. Without a mechanical checkpoint at close time, "fixed but not shipped" anti-pattern recurs.

This contract specifies how `/idd-close` Step 6.5 detects whether the closing repo is distributed and which sync skill to chain to. Detection is **read-only** — no state changes, no network calls beyond `gh repo view` style metadata.

## Distribution types

| Type | Detection signal | Sync skill |
|------|-----------------|-----------|
| `plugin` | Repo is referenced as `plugins[].source.git` in some ancestor `.claude-plugin/marketplace.json` | `/plugin-tools:plugin-update <plugin-name>` |
| `mcp` | `$REPO_ROOT/bin/*.sh` contains `gh release download` or `curl.*github.com.*releases` AND wrapper script name matches `*-mcp-wrapper.sh` (or contains `mcp` substring) | `/mcp-tools:mcp-deploy` |
| `cli` | Same wrapper detection as MCP, but wrapper script name does NOT match MCP heuristic | `/cli-tools:cli-deploy` |
| `plugin+mcp` / `plugin+cli` | Both signals trigger | `/plugin-tools:plugin-update <plugin-name>` (per D3 superset rule, see below) |
| `n/a` | None of the above | — silent skip |

## Detection helpers

These are intended to be implemented inline in `idd-close/SKILL.md` Step 6.5 bash, but documented here as the canonical algorithm for any future caller.

### `is_plugin_marketplace_member(repo_root, github_repo) -> bool`

Walk-up parents from `$REPO_ROOT` looking for `.claude-plugin/marketplace.json`, **stop at `$HOME`** (same convention as `find_idd_config` in `references/config-protocol.md`).

```bash
is_plugin_marketplace_member() {
  local repo_root="$1"
  local github_repo="$2"   # owner/repo form
  local current="$repo_root"

  while [ "$current" != "$HOME" ] && [ "$current" != "/" ]; do
    local manifest="$current/.claude-plugin/marketplace.json"
    if [ -f "$manifest" ]; then
      # Check if any plugins[].source.git matches our repo
      # Normalize trailing .git for comparison
      local match=$(jq -r --arg repo "$github_repo" \
        '.plugins[]?.source.git // empty
         | sub(".git$"; "")
         | select(endswith($repo))' \
        "$manifest" 2>/dev/null | head -1)
      if [ -n "$match" ]; then
        echo "true"
        return 0
      fi
    fi
    current=$(dirname "$current")
  done
  echo "false"
}
```

**Stop conditions**: walking past `$HOME` is a strong signal we've left the user's project tree;`/` is a safety bound. Marketplace repos are by convention under `$HOME/Developer/` or similar.

**Match logic**: `jq` extracts `plugins[].source.git` URLs (e.g. `https://github.com/PsychQuant/issue-driven-development.git`), strips trailing `.git`, then checks if any URL ends with the `owner/repo` form. This is robust to https vs ssh URLs and trailing `.git` variations.

### `has_binary_wrapper(repo_root) -> bool`

Scan `$REPO_ROOT/bin/*.sh` (literal pattern, not recursive) for known distribution patterns.

```bash
has_binary_wrapper() {
  local repo_root="$1"
  local bin_dir="$repo_root/bin"

  [ -d "$bin_dir" ] || { echo "false"; return; }

  local match=$(ls "$bin_dir"/*.sh 2>/dev/null \
    | xargs grep -l -E 'gh release download|curl.*github\.com.*releases' 2>/dev/null \
    | head -1)
  [ -n "$match" ] && echo "true" || echo "false"
}
```

**Why `bin/*.sh` only**: build/dev scripts typically live under `scripts/` or `Sources/`;user-facing distribution wrappers conventionally live under `bin/`. False-positive on a non-distribution `bin/*.sh` is covered by AskUserQuestion `not applicable` opt-out (see Step 6.5 prose).

**Detection keywords**: limited to GitHub-native distribution per #45 issue body scope. Future extension covered below.

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

## D3 — Mixed-type superset rule

When `infer_distribution_type` returns `plugin+mcp` or `plugin+cli`, **chain `plugin-update` only**.

**Rationale**: per `che-claude-config/rules/common-plugins.md`, `plugin-tools:plugin-update` v1.11+ is **dependency-aware orchestrator** — its Phase 1.5 detects `.mcp.json` / wrapper / session-start hook dependencies and AskUserQuestion-prompts the cascade ("順便更新 binary?" → invokes `mcp-deploy` / `cli-deploy`). Calling `plugin-update` is the superset action;calling both separately would either duplicate work or skip the plugin shell sync.

**Caveat**: this claim is **unverified empirically** (filed as PsychQuant/issue-driven-development#66 audit). If audit reveals stale claim, this contract should change to "chain both with explicit ordering" — `mcp-deploy` first to bump binary, then `plugin-update` to bump plugin shell pointing at new binary version.

## Skill resolution table

| `infer_distribution_type` returns | Sync skill to chain |
|----------------------------------|--------------------|
| `plugin` | `/plugin-tools:plugin-update <plugin-name>` |
| `mcp` | `/mcp-tools:mcp-deploy` |
| `cli` | `/cli-tools:cli-deploy` |
| `plugin+mcp` | `/plugin-tools:plugin-update <plugin-name>` (D3) |
| `plugin+cli` | `/plugin-tools:plugin-update <plugin-name>` (D3) |
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

1. **Don't edit `idd-close/SKILL.md`** — the SKILL.md delegates to this contract, not inline keywords
2. Edit `has_binary_wrapper` regex in this doc + the inline implementation in `idd-close/SKILL.md` Step 6.5 bash to add the pattern
3. Document the new pattern in this contract under "Detection keywords" section
4. Smoke-test against the repo that has the unusual wrapper

**Rationale**: encapsulating detection logic here lets future extension touch one canonical doc rather than hunting through skill prose.

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
