#!/usr/bin/env bash
# check-closed-without-summary.sh — retroactive audit for the direct-commit
# auto-close trap (#151). Lists CLOSED issues whose comments contain NO
# `## Closing Summary` heading — i.e. issues that may have been auto-closed by a
# commit / PR-body close keyword, bypassing the /idd-close gate (checklist /
# semantic / sister-sweep / residue / distribution-sync).
#
# Advisory only — ALWAYS exits 0. Output: one line per flagged issue.
#
# Usage:
#   check-closed-without-summary.sh [--repo owner/repo] [--limit N] [--since YYYY-MM-DD]
#   check-closed-without-summary.sh --json-file <path>     # test / offline mode
#
# Consumed by idd-list `--audit-closes`. The `## Closing Summary` heading is the
# same marker idd-list Step 3 keys on for phase inference.

set -u

JSON_FILE=""
REPO=""
LIMIT=50
SINCE=""
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --json-file) JSON_FILE="${2:-}"; shift 2 ;;
    --repo)      REPO="${2:-}"; shift 2 ;;
    --limit)     LIMIT="${2:-50}"; shift 2 ;;
    --since)     SINCE="${2:-}"; shift 2 ;;
    --dry-run)   DRY_RUN=1; shift ;;   # gh mode: print the composed gh command + exit (offline introspection / test seam)
    -h|--help)   sed -n '2,16p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)           echo "unknown arg: $1" >&2; shift ;;
  esac
done

# ── Acquire issue JSON ──
if [ -n "$JSON_FILE" ]; then
  [ -f "$JSON_FILE" ] || { echo "✗ --json-file not found: $JSON_FILE" >&2; exit 0; }
  ISSUES_JSON=$(cat "$JSON_FILE")
else
  # Resolve repo: --repo flag → walk-up .claude/.idd config → gh default repo.
  if [ -z "$REPO" ]; then
    dir="$PWD"
    while [ "$dir" != "/" ]; do
      for cfg in "$dir/.claude/.idd/local.json" "$dir/.claude/issue-driven-dev.local.json"; do
        if [ -f "$cfg" ]; then
          REPO=$(jq -r '.github_repo // empty' "$cfg" 2>/dev/null)
          [ -n "$REPO" ] && break
        fi
      done
      [ -n "$REPO" ] && break
      [ "$dir" = "$HOME" ] && break
      dir=$(dirname "$dir")
    done
  fi
  GH_ARGS=(issue list --state closed --json number,title,state,comments --limit "$LIMIT")
  [ -n "$REPO" ]  && GH_ARGS+=(--repo "$REPO")
  [ -n "$SINCE" ] && GH_ARGS+=(--search "closed:>=$SINCE")
  if [ "$DRY_RUN" = "1" ]; then
    # Print the composed gh invocation + exit (no network). Lets the test suite
    # assert repo-resolution + arg composition for the live-gh branch (#151 verify).
    printf 'gh %s\n' "${GH_ARGS[*]}"
    exit 0
  fi
  if ! ISSUES_JSON=$(gh "${GH_ARGS[@]}" 2>/dev/null); then
    echo "note: 'gh issue list' failed (auth / network / old gh CLI) — audit skipped." >&2
    exit 0
  fi
fi

# Fail-safe: if the acquired payload is NOT valid JSON (e.g. gh returned 0 with a
# truncated stream / proxy HTML, or a hand-edited fixture is malformed), do NOT
# fall through to the filter and print a false "✓ all-clear" — that's the worst
# direction for a safety-net audit (false reassurance). Warn + exit, no verdict.
if ! printf '%s' "$ISSUES_JSON" | jq empty 2>/dev/null; then
  echo "note: issue payload is not valid JSON — audit skipped, no conclusion drawn." >&2
  exit 0
fi

# ── Classify: what does each CLOSED issue's summary marker actually look like? ──
#
# NORMATIVE SOURCE for the four classes (#295). The prose consumers — idd-list
# `--audit-closes` and idd-close `--retroactive` — follow these definitions;
# when they disagree with this filter, this filter is right.
#
#   own-comment  a comment starts with the canonical `## Closing Summary`
#   casing       a comment's FIRST line is the heading in some other casing
#   mid-comment  the heading appears, but not at the start of its comment
#   missing      no closing-summary heading anywhere
#
# Why four and not two: the two-way version asked only `startswith("## Closing
# Summary")`, which misreported 11 of 43 closed issues in a real repo (26%) —
# ten were `## Closing summary`, one had the summary appended below an
# Implementation Complete in the same comment. Every one of them had a real,
# complete summary. A flag wrong a quarter of the time gets ignored, and the
# ignoring is the damage: eleven false alarms hide the twelfth that is real.
#
# The sharper reason is that `idd-close --retroactive` uses the SAME marker as
# its precondition, so a false positive here does not merely add noise — it
# posts a duplicate summary onto an issue that already has one. Only `missing`
# may reach that path, which is why the other two classes are printed with an
# explicit "do NOT run --retroactive".
#
# Order matters. The canonical `startswith` is tested FIRST so that
# `## Closing Summary (retroactive — …)` keeps classifying as own-comment —
# that shape is deliberate (see idd-close SKILL.md: a remediated issue must not
# be re-surfaced), and letting the casing branch claim it would break
# idempotency.
#
# `HEAD_RE` has NO trailing `\b` on purpose: `_` is a word character, so a word
# boundary there would refuse `## closing summary_v2` — a plausible way to head
# a revised summary — and misfile a present summary as `missing`.
CLASSIFY='
  def head_re: "^[ \t]*##[ \t]*closing[ \t]+summary";
  def has_heading($b): ($b | split("\n") | any(test(head_re; "i")));
  def first_line_heading($b): ($b | split("\n") | .[0] // "" | test(head_re; "i"));
  .[]
  | select((.state // "CLOSED") | ascii_upcase == "CLOSED")
  | . as $i
  | [$i.comments[]?.body // ""] as $bodies
  | (if ($bodies | any(startswith("## Closing Summary")))      then "own-comment"
     elif ($bodies | any(first_line_heading(.)))               then "casing"
     elif ($bodies | any(has_heading(.)))                      then "mid-comment"
     else "missing" end) as $class
  | "\($class)\t#\($i.number)  \($i.title)"
'
CLASSIFIED=$(printf '%s' "$ISSUES_JSON" | jq -r "$CLASSIFY" 2>/dev/null)

pick() { printf '%s\n' "$CLASSIFIED" | awk -F'\t' -v c="$1" '$1 == c { print $2 }'; }

MISSING=$(pick missing)
CASING=$(pick casing)
MIDCOMMENT=$(pick mid-comment)

if [ -z "$MISSING" ] && [ -z "$CASING" ] && [ -z "$MIDCOMMENT" ]; then
  echo "✓ No closed issue is missing a ## Closing Summary (within the scanned window)."
  exit 0
fi

if [ -n "$MISSING" ]; then
  echo "MISSING — no ## Closing Summary anywhere (possible auto-close-trap bypass; remediate: idd-close --retroactive #N):"
  printf '%s\n' "$MISSING" | sed 's/^/  ⚠ /'
  echo ""
fi

if [ -n "$CASING" ]; then
  echo "CASING — heading cased differently; the summary IS there (normalize the heading — do NOT run --retroactive):"
  printf '%s\n' "$CASING" | sed 's/^/    /'
  echo ""
fi

if [ -n "$MIDCOMMENT" ]; then
  echo "MID-COMMENT — heading is not at the start of its comment; the summary IS there (split it into its own comment — do NOT run --retroactive):"
  printf '%s\n' "$MIDCOMMENT" | sed 's/^/    /'
  echo ""
fi

echo "(advisory — legacy / pre-IDD / GitHub-UI-closed issues are expected under MISSING; narrow with --since / --limit)"
exit 0
