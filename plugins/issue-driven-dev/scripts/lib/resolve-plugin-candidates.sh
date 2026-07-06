#!/usr/bin/env bash
# resolve-plugin-candidates.sh — marketplace plugin resolution with monorepo
# host disambiguation (#68; supersedes the v1 "first match" simplification in
# references/distribution-detection.md).
#
#   resolve_plugin_candidates <repo_root> [<cwd>]
#     stdout: ALL plugin names whose marketplace source resolves inside
#             repo_root — ordered by specificity to <cwd> (default $PWD):
#             plugins whose dir is an ancestor of cwd first (deepest first),
#             then the rest in manifest order.
#   resolve_plugin_name <repo_root>
#     backward-compat wrapper: first candidate only (v1 contract).
#
# Caller contract (idd-close Step 6.5):
#   0 candidates → silent skip (not a plugin close)
#   1 candidate  → proceed
#   N>1 attended → AskUserQuestion: top-3 + Other
#   N>1 unattended → take the top (most-specific) candidate + audit note
resolve_plugin_candidates() {
  local repo_root="$1" cwd="${2:-$PWD}"
  local resolved_root current manifest manifest_dir
  resolved_root=$(cd "$repo_root" 2>/dev/null && pwd -P) || resolved_root="$repo_root"
  cwd=$(cd "$cwd" 2>/dev/null && pwd -P) || cwd="$cwd"
  current="$resolved_root"
  while :; do
    manifest="$current/.claude-plugin/marketplace.json"
    if [ -f "$manifest" ]; then
      manifest_dir=$(cd "$(dirname "$manifest")/.." 2>/dev/null && pwd -P) || \
        manifest_dir=$(dirname "$(dirname "$manifest")")
      # emit "specificity<TAB>seq<TAB>name": specificity = plugin dir path length
      # when it is an ancestor of cwd (deeper = more specific), else 0.
      local seq=0
      jq -r '.plugins[]? | select(.source | type == "string") | "\(.name)\t\(.source)"' \
        "$manifest" 2>/dev/null \
        | while IFS=$'\t' read -r pname psrc; do
            [ -z "$pname" ] && continue
            seq=$((seq + 1))
            local plugin_dir spec=0
            plugin_dir=$(cd "$manifest_dir/$psrc" 2>/dev/null && pwd -P) || continue
            case "$plugin_dir/" in
              "$resolved_root/"|"$resolved_root/"*) : ;;
              *) continue ;;
            esac
            case "$cwd/" in
              "$plugin_dir/"|"$plugin_dir/"*) spec=${#plugin_dir} ;;
            esac
            printf '%08d\t%08d\t%s\n' "$spec" "$seq" "$pname"
          done \
        | sort -t$'\t' -k1,1nr -k2,2n \
        | cut -f3
      return 0
    fi
    [ "$current" = "$HOME" ] && break
    [ "$current" = "/" ] && break
    current=$(dirname "$current")
  done
  return 0
}

resolve_plugin_name() { # v1 backward-compat: first candidate
  resolve_plugin_candidates "$1" | head -1
}
