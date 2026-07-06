#!/usr/bin/env bash
# test.sh — #220 doc-sync sweep 的機械枚舉契約（防 glob-miss incident 重演）
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
git -C "$W" init -q; git -C "$W" config user.email t@t.t; git -C "$W" config user.name t
touch "$W/README.md" "$W/README_zh-TW.md" "$W/readme.markdown" "$W/CLAUDE.md" "$W/docs/x" 2>/dev/null
mkdir -p "$W/plugins/p"; touch "$W/plugins/p/CLAUDE.md" "$W/plugins/p/README.md" "$W/NOTREADME.txt" "$W/build-readme-gen.js"
( cd "$W" && git add -A && git commit -qm x )

ENUM='(^|/)(readme[^/]*\.(md|markdown)|claude\.md)$'
GOT=$(git -C "$W" ls-files | grep -icE "$ENUM")
assert_eq "枚舉命中 6 份 doc（含 zh-TW 變體與 plugin 層）" "6" "$GOT"
git -C "$W" ls-files | grep -iE "$ENUM" > "$W/hits"
assert_grep "README_zh-TW.md 命中（incident 形狀）" "README_zh-TW.md" "$(cat "$W/hits")"
assert_grep "plugin 層 CLAUDE.md 命中" "plugins/p/CLAUDE.md" "$(cat "$W/hits")"
refute_grep "非 doc 檔不誤中" "NOTREADME.txt" "$(cat "$W/hits")"
refute_grep "readme-字根的程式檔不誤中" "build-readme-gen.js" "$(cat "$W/hits")"

# SKILL.md drift-lock：Step 6.3 與枚舉 regex 存在
SKILL="$HERE/../../../skills/idd-close/SKILL.md"
assert_grep "SKILL.md 含 Step 6.3 doc-sync sweep" "Step 6.3: Doc-sync sweep" "$(cat "$SKILL")"
assert_grep "SKILL.md 含 task list 項 doc_sync_sweep" 'name="doc_sync_sweep"' "$(cat "$SKILL")"

print_summary "doc-sync-sweep"
