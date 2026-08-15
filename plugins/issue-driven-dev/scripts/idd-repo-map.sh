#!/usr/bin/env bash
# idd-repo-map.sh — derive the repo map that target resolution needs (#302).
#
# WHY A MAP AT ALL
#
# Every existing resolution mechanism is single-point: it resolves ONE repo and
# can see nothing about the relationships between repos. So when a rule says
# "this belongs to the project layer", nothing can answer the prior question —
# **does that layer actually exist here?** If it does not, resolution falls
# through to whatever `cwd` happens to be, which is how work lands in the wrong
# tracker. (「地方政府在不在」— the layer can be absent.)
#
# WHY DERIVED, NEVER HAND-WRITTEN
#
# A hand-maintained registry goes stale, and staleness is the disease, not the
# cure: #301's recorded case was caused by a project being extracted into its
# own repo with **nothing anywhere updated**. A hand-written map would just move
# that same failure from walk-up into the registry. So the map is recomputed
# from the filesystem every time, and is never stored as a source of truth.
#
# BOTH CONFIG FORMATS ARE RECOGNISED (#303)
#
# Missing one format is not "one fewer row" — a repo whose config was not seen
# reads as "this layer does not exist", which triggers the wrong upward
# resolution. Measured on one machine: 20+ current-path, 17 legacy-path.
#
# Usage:
#   idd-repo-map.sh [--json] [root ...]     # default root: ~/Developer
#
# Always exits 0. Prints a table, or JSON with --json.

set -u

JSON=0
ROOTS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --json) JSON=1; shift ;;
    -h|--help) sed -n '2,/^$/p' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
    *) ROOTS+=("$1"); shift ;;
  esac
done
[ ${#ROOTS[@]} -eq 0 ] && ROOTS=("$HOME/Developer")

GLOBAL="$HOME/.claude/.idd/global.json"
rows=""

# Values read out of a config file are UNTRUSTED: the file lives inside a
# scanned repo, which in any shared checkout or cloned template is written by
# someone else. Without this, a `github_repo` containing a newline emitted a
# standalone forged row that looked exactly like real data (and corrupted the
# footer counts), a tab shifted the columns, and a raw ESC reached the terminal.
# That is the same row-forging class the sibling script spent seven verify
# rounds closing — reproduced from scratch here because the shape of the script
# was copied without its hard-won safety.
sanitize_field() {
  LC_ALL=C tr -d '\000-\010\011\013\014\016-\037\177' \
    | python3 -c 'import sys
bad = {0x061C, 0x200B, 0x200E, 0x200F, 0x2028, 0x2029, 0x2060, 0xFEFF}
bad |= set(range(0x202A, 0x202F)) | set(range(0x2066, 0x206A)) | set(range(0xE0000, 0xE0080))
s = "".join(" " if ord(c) in bad else c for c in sys.stdin.read())
sys.stdout.write(s.replace("\n", " ")[:160])'
}

emit() {  # $1=repo_dir  $2=config_path  $3=format
  local dir="$1" cfg="$2" fmt="$3" slug=""
  slug=$(jq -r '.github_repo // empty' "$cfg" 2>/dev/null | sanitize_field)
  # A config that exists but names no repo is NOT a resolved layer — say so
  # rather than letting an empty string read as a match.
  [ -z "$(printf '%s' "$slug" | tr -d '[:space:]')" ] && slug="(no github_repo)"
  dir=$(printf '%s' "$dir" | sanitize_field)
  # REAL tab and newline, not the two-character escapes `\t` / `\n`. The buffer
  # used to hold escapes and be rendered with `printf '%b'`, which expands
  # escapes in the DATA as well: a backslash inside a directory name or a
  # `github_repo` value was executed rather than printed. `\c` was the worst of
  # them — %b stops ALL output at it, so one crafted value silently deleted
  # every row after it AND the totals line, and a map missing half its rows
  # reads exactly like a machine with half as many repos. (`--json` was not
  # exempt: the same %b feeds jq, so the payload truncated the JSON row too.)
  # Real control characters cannot come back from the data, because
  # sanitize_field deletes tabs and folds newlines to spaces.
  rows="${rows}${dir}"$'\t'"${slug}"$'\t'"${fmt}"$'\n'
}

SCAN_INCOMPLETE=0
for root in "${ROOTS[@]}"; do
  [ -d "$root" ] || continue
  # `find`'s exit status is the only signal that part of the tree was
  # unreadable, and a process substitution throws it away. That matters more
  # here than in a normal scanner: this map's entire job is to answer "does this
  # layer exist?", and an unreadable directory answering "no config here" is
  # indistinguishable from "no config here" — which is precisely the wrong
  # upward resolution #301 was filed for. So: capture, then check.
  FIND_OUT=$(mktemp) || continue
  find "$root" \
    \( -name node_modules -o -name .git -o -name .build -o -name .venv \
       -o -name archive -o -name archived -o -path '*/.claude/worktrees' \) -prune -o \
    \( -path '*/.claude/.idd/local.json' -o -path '*/.claude/issue-driven-dev.local.json' \) \
    -print0 >"$FIND_OUT" 2>/dev/null
  [ $? -eq 0 ] || SCAN_INCOMPLETE=1
  while IFS= read -r -d '' cfg; do
    case "$cfg" in
      */.claude/.idd/local.json)            emit "$(dirname "$(dirname "$(dirname "$cfg")")")" "$cfg" current ;;
      */.claude/issue-driven-dev.local.json) emit "$(dirname "$(dirname "$cfg")")" "$cfg" legacy ;;
    esac
  done < "$FIND_OUT"
  rm -f "$FIND_OUT"
done
[ "$SCAN_INCOMPLETE" -eq 0 ] || \
  echo "note: parts of the scanned tree could not be read (permissions?) — this map may be INCOMPLETE, and a missing row means 'no such layer' to every consumer of it." >&2

if [ "$JSON" = "1" ]; then
  printf '%s' "$rows" | jq -R -s --arg g "$GLOBAL" '
    {global: ($g | if (. | test("^/")) then . else null end),
     global_present: false,
     repos: (split("\n") | map(select(length > 0) | split("\t")
             | {dir: .[0], github_repo: .[1], config_format: .[2]}))}' 2>/dev/null \
    | jq --argjson present "$([ -f "$GLOBAL" ] && echo true || echo false)" '.global_present = $present'
  exit 0
fi

echo "global config: $GLOBAL $([ -f "$GLOBAL" ] && echo "(present)" || echo "(absent — no global layer)")"
echo ""
if [ -z "$rows" ]; then
  echo "no IDD-configured repo found under: ${ROOTS[*]}"
  exit 0
fi
printf '%s' "$rows" | sort | awk -F'\t' '{printf "  %-58s %-38s %s\n", $1, $2, $3}'
echo ""
printf '%s' "$rows" | awk -F'\t' '{c[$3]++} END {printf "total: %d  (current: %d, legacy: %d)\n", NR, c["current"], c["legacy"]}'
echo "(legacy rows are migratable — see scripts/migrate-idd-config.sh, #303)"
exit 0
