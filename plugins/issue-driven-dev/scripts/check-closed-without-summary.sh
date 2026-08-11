#!/usr/bin/env bash
# check-closed-without-summary.sh — retroactive audit for the direct-commit
# auto-close trap (#151). Classifies CLOSED issues by what their
# `## Closing Summary` marker looks like — issues with none may have been
# auto-closed by a commit / PR-body close keyword, bypassing the /idd-close gate
# (checklist / semantic / sister-sweep / residue / distribution-sync).
#
# Four destinations (#295) — this file is their NORMATIVE SOURCE:
#   missing    no heading-shaped line anywhere in any comment (RAW text)
#   present    such a line exists, but no comment leads with one — UNVERIFIED
#   casing     a comment leads with it, in a non-canonical form
#   (quiet)    a comment leads with the canonical `## Closing Summary`
#
# Output: three sections, printed only when non-empty. MISSING and PRESENT both
# carry ⚠; only MISSING invites `--retroactive`. All-clear is a single ✓ line.
#
# No markdown parsing: the destructive gate turns on ABSENCE alone, so a quoted
# heading and a real one count the same. That under-reports on purpose — see the
# rationale above CLASSIFY.
#
# Advisory only — ALWAYS exits 0.
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

# ── Classify: may a human be told "this issue was closed with no summary"? ──
#
# NORMATIVE SOURCE (#295). The prose consumers — idd-list `--audit-closes` and
# idd-close `--retroactive` — follow these definitions; when they disagree with
# this filter, this filter is right.
#
#   missing    NO line in ANY comment looks like a closing-summary heading.
#              This is the only class that invites `--retroactive`.
#   present    Such a line exists, but no comment LEADS with one. Printed with a
#              warning and an explicit "do NOT run --retroactive" — the tool has
#              established nothing about it beyond its existence.
#   casing     A comment leads with the heading in a non-canonical form
#              (different casing, indented, `##closing summary`, `_v2`, …).
#              Actionable, but the action is to normalise the heading.
#   (quiet)    A comment leads with the canonical `## Closing Summary`.
#              Printed nowhere, so the report stays quiet for compliant repos.
#
# WHY THE DESTRUCTIVE GATE ASKS ONLY ABOUT ABSENCE (the round-5 rewrite).
#
# `idd-close --retroactive` shares this marker as its PRECONDITION, so a false
# positive here is not noise — it posts a duplicate summary onto an issue that
# already has one. The two error directions therefore cost wildly different
# amounts: over-flagging is irreversible, under-flagging is a missed detection
# in a tool that is advisory and reactive by design.
#
# Rounds 1 through 4 tried to earn precision by parsing markdown in jq — fenced
# blocks, HTML comments, indented code, section bounds, indent caps. Each new
# mechanism grew its own one-way failure, and every one of them failed in the
# SAME direction: a real summary the parser could not follow became `missing`,
# the one class that authorises the irreversible action. Four verify rounds
# found nine such shapes (h2 subsections, a `~~~` line closing a ``` fence, an
# empty decoy heading before a real one, a one-line summary on the heading line,
# an unclosed fence, an unclosed HTML comment, a space+tab indent, …), and the
# list was still growing when the parser was removed.
#
# So the parser is gone. Absence is judged on RAW TEXT: any line, any comment,
# any indentation, blockquote markers allowed, case-insensitive. Nothing about
# fences, HTML comments or section structure can change the answer, because a
# quoted heading and a real one are treated alike — deliberately. The price is
# stated plainly: an issue whose ONLY mention of the marker is a quotation is no
# longer reported as missing. That is a missed detection, and it is the cheap
# direction. The expensive direction is now unreachable by construction rather
# than by getting a parser exactly right.
#
# `casing` and `present` keep the information the old two-way marker threw away
# (10 of 43 closed issues in a real repo had drifted to `## Closing summary`),
# but neither authorises anything.
#
# `head_re` deliberately has no trailing `\b`: `_` is a word character, so a word
# boundary would refuse `## closing summary_v2` — a plausible way to head a
# revised summary — and misfile a present summary as missing.
#
# THE TITLE AND NUMBER ARE UNTRUSTED DATA. The record below is `class\t#N  title`,
# parsed positionally downstream. Both delimiters are in-band, so a newline in a
# title forged a whole row — including into the section that invites the
# irreversible `--retroactive`. `sanitize` collapses control characters AND the
# non-Cc characters that can forge or reorder a visual row (U+2028/U+2029 line
# and paragraph separators, and the bidi overrides and isolates). It stops short
# of all of `\p{Cf}`: that would eat zero-width joiners and split emoji
# sequences in ordinary titles.
CLASSIFY='
  # NOTE: this jq program lives inside a single-quoted shell string, so it must
  # contain no apostrophe anywhere -- not even in a comment. Writing a real
  # apostrophe here silently closes the string and produces a bash syntax error
  # further down. For the same reason every escape below is written as text:
  # pasting a literal control character here once left two NUL bytes in this
  # file, which made GitHub serve it as a binary blob (the whole diff rendered
  # as "Binary file not shown") and made plain grep skip it in silence.
  #
  # Deliberately permissive: any indentation, blockquote markers allowed, one or
  # two hashes, no space required after them. This regex answers only "could a
  # reader see a closing-summary heading here", and every ambiguity resolves
  # toward yes, because yes is the direction that withholds the destructive
  # action. `###` is excluded -- an h3 is a subsection of a summary, not one.
  def head_re: "^[ \t>]*#{1,2}[ \t]*closing[ \t]+summary";
  # Control characters are structural here (record + field delimiters) and can
  # also repaint a terminal; U+2028/U+2029 and the bidi controls can forge or
  # reorder a row in any renderer that honours them. One substitution covers all.
  #
  # POSIX class names, not a numeric escape range: Oniguruma does not read the
  # backslash-u form inside a jq string, so a range written that way silently
  # degrades into the literal range 0 to u and eats most of the alphabet. It was
  # caught only because every fixture title came back as fragments.
  def sanitize:
    (. // "")
    | gsub("[[:cntrl:]\\p{Zl}\\p{Zp}\\x{200E}\\x{200F}\\x{202A}-\\x{202E}\\x{2066}-\\x{2069}]"; " ")
    | gsub(" +"; " ");
  # The first line a reader actually sees: blank lines and whole-line HTML
  # markers are skipped, because this plugin mandates a marker on line 1 for
  # machine-locatable comments (references/dashboard-comment.md), and a leading
  # marker must not demote a byte-perfect summary.
  def lead_line:
    ((. // "") | split("\n"))
    | map(select((test("^[ \t]*$") | not) and (test("^[ \t]*<!--.*-->[ \t]*$") | not)))
    | (first // "");
  # Oniguruma anchors ^ to the START OF THE STRING, not to each line -- verified,
  # not assumed. Lines are therefore split explicitly; relying on the anchor
  # would have sent every mid-comment marker to missing, which is precisely the
  # failure this rewrite exists to make unreachable.
  def has_heading_anywhere:
    ((. // "") | split("\n")) | any(test(head_re; "i"));
  # Four destinations, in order. Only the LAST one authorises anything, and it
  # is reached solely by the absence of any heading-shaped line anywhere.
  #
  # The canonical test comes first so that `## Closing Summary (retroactive - ...)`
  # -- the heading this very skill writes when it remediates -- stays quiet
  # instead of being claimed by the casing branch. That is what makes
  # `--retroactive` idempotent.
  #
  # Known and accepted: a lead line of `## Closing Summary (draft, do not use)`
  # also reads as compliant and so is reported nowhere. Bounding the heading tail
  # is exactly the kind of parsing this rewrite removed, and the residual error
  # is a missed detection, not a duplicate post.
  .[]
  | select((.state // "CLOSED") | ascii_upcase == "CLOSED")
  | . as $i
  | [$i.comments[]?.body // ""] as $bodies
  | (if   ($bodies | any(lead_line | startswith("## Closing Summary"))) then "compliant"
     elif ($bodies | any(lead_line | test(head_re; "i")))               then "casing"
     elif ($bodies | any(has_heading_anywhere))                         then "present"
     else "missing" end) as $class
  | "\($class)\t#\($i.number | tostring | sanitize)  \($i.title | sanitize)"
'
# jq errors must NOT become a false all-clear: stderr is captured and a non-zero
# exit aborts with a note instead of printing "✓ nothing missing" over a filter
# that died halfway (the same fail-safe direction as the malformed-JSON guard).
if ! CLASSIFIED=$(printf '%s' "$ISSUES_JSON" | jq -r "$CLASSIFY" 2>/tmp/csw_jq_err.$$); then
  echo "note: classification filter failed — audit skipped, no conclusion drawn." >&2
  sed 's/^/      jq: /' /tmp/csw_jq_err.$$ >&2
  rm -f /tmp/csw_jq_err.$$
  exit 0
fi
rm -f /tmp/csw_jq_err.$$

pick() { printf '%s\n' "$CLASSIFIED" | awk -F'\t' -v c="$1" '$1 == c { print $2 }'; }

MISSING=$(pick missing)
CASING=$(pick casing)
PRESENT=$(pick present)

if [ -z "$MISSING" ] && [ -z "$CASING" ] && [ -z "$PRESENT" ]; then
  echo "✓ No closed issue is missing a ## Closing Summary (within the scanned window)."
  exit 0
fi

if [ -n "$MISSING" ]; then
  echo "MISSING — no closing-summary heading appears anywhere in the comments (possible auto-close-trap bypass; remediate: idd-close --retroactive #N):"
  printf '%s\n' "$MISSING" | sed 's/^/  ⚠ /'
  echo ""
fi

# PRESENT keeps the ⚠ and says plainly that nothing was established. The heading
# exists somewhere but no comment leads with one, and this audit deliberately no
# longer tries to tell a real summary from a quoted one — four rounds of trying
# produced nine ways to misjudge it, every one of them routing a real summary to
# MISSING. A human decides here; the tool only points.
if [ -n "$PRESENT" ]; then
  echo "PRESENT (unverified) — a closing-summary heading exists in the comments, but no comment starts with one. Whether it is a real summary or a quotation was NOT established — inspect by hand; do NOT run --retroactive on the strength of this line:"
  printf '%s\n' "$PRESENT" | sed 's/^/  ⚠ /'
  echo ""
fi

# CASING says "non-canonical form", not "cased differently": the class also
# covers a heading indented one to three spaces, whose casing is perfectly
# correct. Naming the wider thing after its commonest member told the reader to
# fix something that was not wrong. No ⚠ — the summary is where it should be and
# only the heading needs normalising.
if [ -n "$CASING" ]; then
  echo "CASING — a comment leads with the heading but not in canonical form (casing, indentation, or a suffix like _v2); the summary is there (normalize the heading — do NOT run --retroactive):"
  printf '%s\n' "$CASING" | sed 's/^/    /'
  echo ""
fi

echo "(advisory — legacy / pre-IDD / GitHub-UI-closed issues are expected under MISSING; narrow with --since / --limit)"
exit 0
