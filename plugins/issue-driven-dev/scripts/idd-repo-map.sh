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

emit() {  # $1=repo_dir  $2=config_path  $3=format
  local dir="$1" cfg="$2" fmt="$3" slug=""
  slug=$(jq -r '.github_repo // empty' "$cfg" 2>/dev/null)
  # A config that exists but names no repo is NOT a resolved layer — say so
  # rather than letting an empty string read as a match.
  [ -z "$slug" ] && slug="(no github_repo)"
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
             \( -name node_modules -o -name .git -o -name .build -o -name .venv \) -prune -o \
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
