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
  rows="${rows}${dir}\t${slug}\t${fmt}\n"
}

for root in "${ROOTS[@]}"; do
  [ -d "$root" ] || continue
  while IFS= read -r cfg; do
    case "$cfg" in
      */.claude/.idd/local.json)            emit "$(dirname "$(dirname "$(dirname "$cfg")")")" "$cfg" current ;;
      */.claude/issue-driven-dev.local.json) emit "$(dirname "$(dirname "$cfg")")" "$cfg" legacy ;;
    esac
  done < <(find "$root" \
             \( -name node_modules -o -name .git -o -name .build -o -name .venv \
                -o -name archive -o -name archived -o -path '*/.claude/worktrees' \) -prune -o \
             \( -path '*/.claude/.idd/local.json' -o -path '*/.claude/issue-driven-dev.local.json' \) \
             -print 2>/dev/null)
done

if [ "$JSON" = "1" ]; then
  printf '%b' "$rows" | jq -R -s --arg g "$GLOBAL" '
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
printf '%b' "$rows" | sort | awk -F'\t' '{printf "  %-58s %-38s %s\n", $1, $2, $3}'
echo ""
printf '%b' "$rows" | awk -F'\t' '{c[$3]++} END {printf "total: %d  (current: %d, legacy: %d)\n", NR, c["current"], c["legacy"]}'
echo "(legacy rows are migratable — see scripts/migrate-idd-config.sh, #303)"
exit 0
