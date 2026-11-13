#!/usr/bin/env bash
# test.sh — which signals turn the spectra bridge on (#502, #525)
# spec-example: spectra-bridge-detection / what turns the spectra bridge on
# spec-example: spectra-bridge-detection / where the bridge signals are listed
# spec-example: spectra-bridge-detection / which wordings list open changes as a signal
# spec-example: spectra-bridge-detection / Step 7 applies only when the bridge is on
# spec-example: spectra-bridge-detection / what the rule and the skill say about conversation context
#
# idd-comment Step 0.7 decides whether the call came from a spectra-discuss session. It used to say yes
# whenever the repository had any open Spectra change (#126, #502). This suite takes the bash block out of
# SKILL.md and runs it, one signal at a time, in an empty directory with a stand-in `spectra` on PATH that
# reports open changes and writes down every call. It then reads the four places that list the signals, the
# heading of Step 7, and what the rule and the skill say about conversation context (#525). The sentences for the
# wording rule come from the Example table in the capability's spec, so the table and the checks cannot differ.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
PLUGIN="$HERE/../../.."
SKILL="$PLUGIN/skills/idd-comment/SKILL.md"
RULE="$PLUGIN/rules/spectra-bridge.md"
SPEC="$PLUGIN/../../openspec/specs/spectra-bridge-detection/spec.md"
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
world "$NONE"; bridge_file .claude/.idd/state/bridge.json false; bridge_file .claude/state/idd-bridge.json true
assert_eq "新路徑的檔是 false、舊路徑的檔是 true → 不啟動（兩個檔都在時只讀新路徑的）" "0" "$(detect "" "")"
assert_eq "八列都沒有呼叫 spectra" "" "$(cat "$W/calls.log")"

# ── Example: which wordings list open changes as a signal (one check per row of the table in the spec) ──
# lists_open_changes <sentence> → succeeds when the sentence lists open changes as a signal, by the four steps of
# the Example. The sentence is cut with the shell's own substitution and the patterns are plain alternations: a
# bracket expression holding CJK punctuation would match single bytes under LC_ALL=C.
MENTION='(^|[^A-Za-z])[Cc]hange|變更|提案|spectra list|[Ii]n-flight'
REMARK="不算|不是訊號|not a signal|not signals|do not count|does not count|don't count|not counted"
lists_open_changes() {
  local s="$1" sep nl='
'
  for sep in '(' ')' '（' '）' ',' '，' '、' ';' '；' '。' '. '; do s=${s//$sep/$nl}; done            # step 1: clauses
  printf '%s\n' "$s" | grep -E -- "$MENTION" | grep -Ev -- "($MENTION).*($REMARK)" | grep -q .   # steps 2 to 4
}
assert_file_exists "讀得到 capability 的規格" "$SPEC"
WORDING_ROWS=$(awk '/^##### Example: which wordings list open changes as a signal$/{f=1; next} f && /^#/{exit} f && /^\| /' "$SPEC" 2>/dev/null | sed '1,2d')
assert_eq "規格裡這個 Example 的表有 29 列" "29" "$(printf '%s\n' "$WORDING_ROWS" | grep -c .)"
ROW_NO=0
while IFS= read -r row; do
  [ -n "$row" ] || continue
  ROW_NO=$((ROW_NO + 1))
  row=${row#| }; row=${row% |}
  want=${row##* | }; sentence=${row% | *}
  if [ "$want" = yes ]; then require "第 $ROW_NO 列算列入：$sentence" lists_open_changes "$sentence"
  elif [ "$want" = no ]; then refute "第 $ROW_NO 列不算列入：$sentence" lists_open_changes "$sentence"
  else fail "第 $ROW_NO 列的第二欄是 yes 或 no" "got [$want]"; fi
done <<EOF
$WORDING_ROWS
EOF

# ── Example: where the bridge signals are listed ──
# A table row may not mention open changes at all; a sentence may, as long as it only says they do not count.
RULE_ROWS=$(awk '/^## Detection/{f=1; next} f && /^## /{exit} f && /^\|/' "$RULE")
assert_true "規則的偵測表抽得出來" '[ "$(printf "%s\n" "$RULE_ROWS" | grep -c .)" -ge 4 ]'
refute_grep_re "規則的偵測表沒有任何一列提到 Spectra change" "$MENTION" "$RULE_ROWS"
assert_grep "規則的偵測表寫的是 bridge 檔的 active_spectra_session" 'active_spectra_session' "$RULE_ROWS"

TASK_LINE=$(grep -F 'name="detect_spectra_context"' "$SKILL")
assert_eq "idd-comment 只有一個 detect_spectra_context 的 task 描述" "1" "$(printf '%s\n' "$TASK_LINE" | grep -c .)"
refute "task 描述沒有把開著的 change 列為訊號" lists_open_changes "$TASK_LINE"

for doc in CLAUDE.md README.md; do
  LINE=$(grep -F 'Step 0.7 Detect' "$PLUGIN/$doc")
  assert_eq "$doc 只有一句列出訊號" "1" "$(printf '%s\n' "$LINE" | grep -c .)"
  refute "$doc 那一句沒有把開著的 change 列為訊號" lists_open_changes "$LINE"
  assert_grep "$doc 那一句寫的是 bridge 檔的 active_spectra_session" 'active_spectra_session' "$LINE"
done

# ── Example: Step 7 applies only when the bridge is on ──
STEP7=$(grep -E '^### Step 7' "$SKILL")
assert_eq "idd-comment 只有一個 Step 7 的標題" "1" "$(printf '%s\n' "$STEP7" | grep -c .)"
assert_grep "Step 7 的標題寫的是「僅當 SPECTRA_BRIDGE_ACTIVE=1」" '僅當 SPECTRA_BRIDGE_ACTIVE=1' "$STEP7"

# ── Example: what the rule and the skill say about conversation context (one group of checks per row) ──
# Row 1: the signal rows of the detection table.
SIGNAL_ROWS=$(printf '%s\n' "$RULE_ROWS" | sed '1,2d')   # without the header row and the |---| row
assert_eq "規則的偵測表剛好三列訊號" "3" "$(printf '%s\n' "$SIGNAL_ROWS" | grep -c .)"
assert_grep "三列訊號之一是 --resume-spectra 旗標" '--resume-spectra' "$SIGNAL_ROWS"
assert_grep "三列訊號之一是 --source 引數" '--source' "$SIGNAL_ROWS"
assert_grep "三列訊號之一是 bridge 檔" 'bridge.json' "$SIGNAL_ROWS"
# Row 2: no row mentions conversation context, in English or as 對話脈絡.
refute_grep_re "偵測表沒有任何一列提到對話脈絡（中英文）" '[Cc]onversation context|[Ii]mplicit|對話脈絡' "$RULE_ROWS"
# Row 3: below the table. RULE_BELOW holds the lines of the Detection section after its last table row.
RULE_BELOW=$(awk '/^## Detection/{f=1; next} f && /^## /{exit} f && /^\|/{buf=""; t=1; next} f && t {buf = buf $0 "\n"} END {printf "%s", buf}' "$RULE")
RULE_NOTE=$(printf '%s\n' "$RULE_BELOW" | grep -E -- '[Cc]onversation context is not a signal')
assert_eq "規則的偵測表下方有一行寫明對話脈絡不是訊號" "1" "$(printf '%s\n' "$RULE_NOTE" | grep -c .)"
assert_grep "那一行寫明從 spectra-discuss 中途呼叫要帶 --resume-spectra" '--resume-spectra' "$RULE_NOTE"
assert_grep "那一行說的是 spectra-discuss 的討論中途" 'spectra-discuss' "$RULE_NOTE"
# Row 4: below the block of Step 0.7 in the skill.
STEP07_BELOW=$(awk '/^### Step 0\.7/{f=1; next} f && /^### Step /{exit} f && /^```$/{t=1; next} f && t' "$SKILL")
SKILL_NOTE=$(printf '%s\n' "$STEP07_BELOW" | grep -F -- '對話脈絡')
assert_eq "idd-comment Step 0.7 的區塊下方有一行提到對話脈絡" "1" "$(printf '%s\n' "$SKILL_NOTE" | grep -c .)"
assert_grep_re "那一行寫的是對話脈絡不是訊號" '對話脈絡.*不是訊號' "$SKILL_NOTE"
assert_grep "那一行寫明要帶 --resume-spectra" '--resume-spectra' "$SKILL_NOTE"
# Row 5: the skill's rule that a spectra context must not be ignored silently.
IRON=$(grep -F -- 'Spectra context 不可靜默忽略' "$SKILL")
assert_eq "idd-comment 只有一條「Spectra context 不可靜默忽略」" "1" "$(printf '%s\n' "$IRON" | grep -c .)"
assert_grep "那一條以 SPECTRA_BRIDGE_ACTIVE=1 為準" 'SPECTRA_BRIDGE_ACTIVE=1' "$IRON"
assert_grep "那一條寫明不從對話推斷" '不從對話推斷' "$IRON"

print_summary "spectra-bridge-detect"
