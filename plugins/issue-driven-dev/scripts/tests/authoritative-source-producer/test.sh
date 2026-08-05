#!/usr/bin/env bash
# test.sh — #290 authoritative_source 的 priority-2 producer 與 exists 判準
#
# 兩個缺口：
#   (1) priority 2（`## Current Status > ### Tasks`）沒有任何 producer —— 三個
#       consumer 讀它，卻沒有 skill 寫它，於是 chain 退化成「只有 priority 1」。
#   (2) `first_exists` 的 `exists` 未定義 —— 只有 idd-close 寫出 len>0，且只對
#       priority 1。
#
# 本檔驗兩件事：判準的機制（fixture）＋ 規範文字在位（drift-lock）。
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

# ── 機制 1：exists ＝ heading 在「且」至少一個可解析項目 ───────────────────
# checkbox regex 與 idd-close Step 0 同源（`^\s*-\s*\[(.)\]\s*(.+)$`）。
count_items() {  # <file> — heading 底下到下一個 ### 之前的 checkbox 行數
  awk '/^### Tasks/{f=1;next} f && /^###? /{f=0} f' "$1" \
    | grep -cE '^[[:space:]]*-[[:space:]]*\[.\][[:space:]]*.+$'
}
resolves() { [ "$(count_items "$1")" -gt 0 ]; }

printf '## Current Status\n\n### Tasks\n\n### Commits\n- x\n' > "$W/zero.md"
printf '## Current Status\n\n### Tasks\n- [ ] 還沒做\n' > "$W/one-open.md"
printf '## Current Status\n\n### Tasks\n- [x] a\n- [x] b\n- [x] c\n' > "$W/three-done.md"
printf '## Current Status\n\n### Commits\n- x\n' > "$W/absent.md"

assert_eq "heading ＋ 0 項 → 0"        "0" "$(count_items "$W/zero.md")"
assert_eq "heading ＋ 1 項未勾 → 1"    "1" "$(count_items "$W/one-open.md")"
assert_eq "heading ＋ 3 項已勾 → 3"    "3" "$(count_items "$W/three-done.md")"
assert_eq "heading 缺席 → 0"           "0" "$(count_items "$W/absent.md")"
refute  "heading ＋ 0 項不 resolve（空節不得命中）" resolves "$W/zero.md"
require "heading ＋ 1 項未勾 resolve"               resolves "$W/one-open.md"
require "heading ＋ 3 項已勾 resolve"               resolves "$W/three-done.md"
refute  "heading 缺席不 resolve"                    resolves "$W/absent.md"

# ── 機制 2：toplevel 圍籬（用真的第二個 worktree，不是換字串的假 fixture）──
# 實測遇到的正是「同 repo 跨 worktree」——外部工具的 registry 不是 cwd-scoped，
# 回傳的路徑可能指向 sibling worktree。假陽性（讀到別處已完成的清單而放行未完成
# 的 issue）比假陰性嚴重得多，所以這道圍籬必須用真情境驗。
R="$W/repo"; mkdir -p "$R"
git -C "$R" init -q; git -C "$R" config user.email t@t.t; git -C "$R" config user.name t
mkdir -p "$R/changes/a"; printf -- '- [x] done\n' > "$R/changes/a/tasks.md"
( cd "$R" && git add -A && git commit -qm x )
git -C "$R" worktree add -q -b other "$W/repo-other" 2>/dev/null

within_toplevel() {  # <cwd> <path> — 路徑是否落在 cwd 的 git toplevel 內
  local top; top="$(git -C "$1" rev-parse --show-toplevel 2>/dev/null)" || return 1
  local abs; abs="$(cd "$(dirname "$2")" 2>/dev/null && pwd -P)/$(basename "$2")" || return 1
  case "$abs/" in "$top/"*) return 0 ;; *) return 1 ;; esac
}

assert_true "第二個 worktree 真的建起來了" "[ -d '$W/repo-other/changes' ]"
require "同一工作樹內的路徑通過"       within_toplevel "$R" "$R/changes/a/tasks.md"
refute  "sibling worktree 的路徑被拒（實測遇到的形狀）" \
        within_toplevel "$R" "$W/repo-other/changes/a/tasks.md"
refute  "repo 之外的路徑被拒"          within_toplevel "$R" "$W/zero.md"

# ── drift-lock：規範文字在位 ───────────────────────────────────────────────
RULE="$HERE/../../../rules/append-vs-modify.md"
UPD="$HERE/../../../skills/idd-update/SKILL.md"
ALL="$HERE/../../../skills/idd-all/SKILL.md"

assert_grep "rule 定義 exists 需至少一個項目" "至少一個可解析" "$(cat "$RULE")"
assert_grep "rule 按角色描述、且角色非互斥" "以 producer 身分執行時不評估 resolution" "$(cat "$RULE")"
assert_grep "rule 指名 priority 2 的 producer" "tasks-file" "$(cat "$RULE")"
assert_grep "rule 的不變式要求「具名或明示無」而非「必須有」" "明示「無自動 producer" "$(cat "$RULE")"
assert_grep "idd-update 有 --tasks-file flag" "--tasks-file" "$(cat "$UPD")"
assert_grep "idd-update 寫明 toplevel 圍籬" "show-toplevel" "$(cat "$UPD")"
assert_grep "idd-all 在 Spectra 分支傳 --tasks-file" "--tasks-file" "$(cat "$ALL")"

# ── 本輪 cross-model verify 逼出的兩個嚴重缺陷，各鎖一條 ──────────────────
# (1) 未給 flag 時必須「保留」既有 ### Tasks。managed zone 是整段替換,
#     若寫成「不輸出」,下一次不帶 flag 的 update 就會抹掉它——修法在自己的
#     pipeline 裡活不過一步（3b.5 寫入 → Phase 4 的 Auto-Update 抹掉）。
assert_grep "idd-update 規定未給 flag 時保留既有 ### Tasks" "逐字保留既有內容" "$(cat "$UPD")"
assert_grep "idd-update 點名這是本 pipeline 的既定流程而非理論風險" "Auto-Update" "$(cat "$UPD")"
# (2) toplevel 解析失敗必須 fail-closed。TOP="" 時 pattern 變 `/*`,任何絕對
#     路徑都通過——圍籬看起來在,實際形同虛設。
assert_grep "圍籬對 toplevel 解析失敗 fail-closed" "fail-closed" "$(cat "$UPD")"
assert_grep "圍籬解析整條路徑而非只有 dirname（擋最後一段 symlink）" "readlink -f" "$(cat "$UPD")"
assert_grep "拒絕訊息印使用者給的原始值" 'RAW' "$(cat "$UPD")"

print_summary "authoritative-source-producer"
