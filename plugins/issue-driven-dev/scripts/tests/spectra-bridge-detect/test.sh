#!/usr/bin/env bash
# test.sh — which signals turn the spectra bridge on (#502)
# spec-example: spectra-bridge-detection / what turns the spectra bridge on
# spec-example: spectra-bridge-detection / where the bridge signals are listed
#
# idd-comment Step 0.7 decides whether the call came from a spectra-discuss session. It used to say yes
# whenever the repository had any open Spectra change (#126, #502). This suite takes the bash block out of
# SKILL.md and runs it, one signal at a time, in an empty directory with a stand-in `spectra` on PATH that
# reports open changes and writes down every call. It then reads the four places that list the signals.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
PLUGIN="$HERE/../../.."
SKILL="$PLUGIN/skills/idd-comment/SKILL.md"
RULE="$PLUGIN/rules/spectra-bridge.md"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT

# ── The block: the first bash fence under the "### Step 0.7" heading ──
awk '/^### Step 0\.7/{f=1; next} f && /^### Step /{exit} f && /^```bash$/{g=1; next} g && /^```$/{exit} g' "$SKILL" > "$W/block.sh"
assert_true "Step 0.7 的 bash 區塊抽得出來" '[ -s "$W/block.sh" ] && grep -q "^SPECTRA_BRIDGE_ACTIVE=0$" "$W/block.sh"'

# ── A stand-in spectra: prints what list.json holds, and writes every call to calls.log ──
mkdir -p "$W/bin"
cat > "$W/bin/spectra" <<EOF
#!/bin/sh
echo "spectra \$*" >> "$W/calls.log"
case "\$*" in "list --json") cat "$W/list.json" ;; esac
EOF
chmod +x "$W/bin/spectra"
EIGHT='{"changes":[{"name":"a"},{"name":"b"},{"name":"c"},{"name":"d"},{"name":"e"},{"name":"f"},{"name":"g"},{"name":"h"}]}'
NONE='{"changes":[]}'

# The stand-in must really be the `spectra` the block would reach, or "no call was written down" proves nothing.
: > "$W/calls.log"; printf '%s' "$EIGHT" > "$W/list.json"
GOT=$(PATH="$W/bin:$PATH" spectra list --json | jq '.changes | length')
assert_eq "假的 spectra 在 PATH 上，回報 8 個開著的 change" "8" "$GOT"
assert_eq "假的 spectra 會記下呼叫" "spectra list --json" "$(cat "$W/calls.log")"
: > "$W/calls.log"

# world <list.json content>  → a new empty working directory and that many open changes
world() { rm -rf "$W/cwd"; mkdir -p "$W/cwd"; printf '%s' "$1" > "$W/list.json"; }
# bridge_file <path under the working directory> <true|false>
bridge_file() { mkdir -p "$W/cwd/$(dirname "$1")"; printf '{"active_spectra_session": %s}' "$2" > "$W/cwd/$1"; }
# detect <--resume-spectra value> <--source value>  → SPECTRA_BRIDGE_ACTIVE after the block ran
detect() {
  ( cd "$W/cwd" && RESUME_SPECTRA="$1" SOURCE="$2" PATH="$W/bin:$PATH" \
      bash -c '. "$0" >/dev/null 2>&1; printf "%s" "${SPECTRA_BRIDGE_ACTIVE-unset}"' "$W/block.sh" )
}

# ── Example: what turns the spectra bridge on (one check per row) ──
world "$EIGHT"
assert_eq "只有 8 個開著的 change → 不啟動" "0" "$(detect "" "")"
world "$NONE"
assert_eq "什麼訊號都沒有 → 不啟動" "0" "$(detect "" "")"
world "$NONE"
assert_eq "只有 --resume-spectra → 啟動" "1" "$(detect "my topic" "")"
world "$NONE"
assert_eq "只有 --source 含 spectra-discuss（大小寫不拘）→ 啟動" "1" "$(detect "" "Spectra-Discuss session")"
world "$NONE"; bridge_file .claude/.idd/state/bridge.json true
assert_eq "只有新路徑的 bridge 檔（active_spectra_session: true）→ 啟動" "1" "$(detect "" "")"
world "$NONE"; bridge_file .claude/state/idd-bridge.json true
assert_eq "只有舊路徑的 bridge 檔（active_spectra_session: true）→ 啟動" "1" "$(detect "" "")"
world "$EIGHT"; bridge_file .claude/.idd/state/bridge.json false
assert_eq "bridge 檔的 active_spectra_session 是 false，另有 8 個開著的 change → 不啟動" "0" "$(detect "" "")"
assert_eq "七列都沒有呼叫 spectra" "" "$(cat "$W/calls.log")"

# ── Example: where the bridge signals are listed ──
OPEN_CHANGES='spectra list|[Ii]n-flight|[Oo]pen [A-Za-z ]*changes?'   # for table rows: no row may be about open changes
LISTED='spectra list|[Ii]n-flight'                                    # for a sentence that may say they are NOT a signal

RULE_ROWS=$(awk '/^## Detection/{f=1; next} f && /^## /{exit} f && /^\|/' "$RULE")
assert_true "規則的偵測表抽得出來" '[ "$(printf "%s\n" "$RULE_ROWS" | grep -c .)" -ge 4 ]'
refute_grep_re "規則的偵測表沒有把開著的 change 列為訊號" "$OPEN_CHANGES" "$RULE_ROWS"
assert_grep "規則的偵測表寫的是 bridge 檔的 active_spectra_session" 'active_spectra_session' "$RULE_ROWS"

TASK_LINE=$(grep -F 'name="detect_spectra_context"' "$SKILL")
assert_eq "idd-comment 只有一個 detect_spectra_context 的 task 描述" "1" "$(printf '%s\n' "$TASK_LINE" | grep -c .)"
refute_grep_re "task 描述沒有把開著的 change 列為訊號" "$LISTED" "$TASK_LINE"

for doc in CLAUDE.md README.md; do
  LINE=$(grep -F 'Step 0.7 Detect' "$PLUGIN/$doc")
  assert_eq "$doc 只有一句列出訊號" "1" "$(printf '%s\n' "$LINE" | grep -c .)"
  refute_grep_re "$doc 那一句沒有把開著的 change 列為訊號" "$LISTED" "$LINE"
  assert_grep "$doc 那一句寫的是 bridge 檔的 active_spectra_session" 'active_spectra_session' "$LINE"
done

print_summary "spectra-bridge-detect"
