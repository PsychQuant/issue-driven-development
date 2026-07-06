#!/usr/bin/env bash
# test.sh — monorepo host plugin disambiguation (#68)
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
. "$HERE/../../lib/resolve-plugin-candidates.sh"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

# fixture: marketplace host with 3 plugins
mkdir -p "$W/host/.claude-plugin" "$W/host/plugins/alpha" "$W/host/plugins/beta" "$W/host/plugins/beta-extra"
cat > "$W/host/.claude-plugin/marketplace.json" <<'JSON'
{"plugins":[
  {"name":"alpha","source":"./plugins/alpha"},
  {"name":"beta","source":"./plugins/beta"},
  {"name":"beta-extra","source":"./plugins/beta-extra"}
]}
JSON

# 1. host root cwd → all 3, manifest order（無 specificity 信號）
OUT=$(resolve_plugin_candidates "$W/host" "$W/host")
assert_eq "host cwd → 3 candidates manifest order" "alpha
beta
beta-extra" "$OUT"

# 2. cwd inside beta → beta first
OUT=$(resolve_plugin_candidates "$W/host" "$W/host/plugins/beta")
assert_eq "beta cwd → beta 排最前" "beta" "$(echo "$OUT" | head -1)"

# 3. beta-extra cwd 不被 beta 前綴誤吃（path-boundary 正確）
OUT=$(resolve_plugin_candidates "$W/host" "$W/host/plugins/beta-extra")
assert_eq "beta-extra cwd → beta-extra 排最前" "beta-extra" "$(echo "$OUT" | head -1)"

# 4. 單一 plugin repo（非 host）→ 唯一候選
mkdir -p "$W/solo/.claude-plugin" "$W/solo/p"
printf '{"plugins":[{"name":"solo-p","source":"./p"}]}' > "$W/solo/.claude-plugin/marketplace.json"
OUT=$(resolve_plugin_candidates "$W/solo")
assert_eq "solo repo → 1 candidate" "solo-p" "$OUT"

# 5. 無 marketplace → 空（silent skip 語意）
mkdir -p "$W/plain"
OUT=$(resolve_plugin_candidates "$W/plain")
assert_eq "非 marketplace repo → empty" "" "$OUT"

# 6. v1 wrapper 相容
assert_eq "resolve_plugin_name = 首候選" "alpha" "$(cd "$W/host" && resolve_plugin_name "$W/host")"

print_summary "resolve-plugin-candidates"
