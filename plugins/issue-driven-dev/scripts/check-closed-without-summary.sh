#!/usr/bin/env bash
# check-closed-without-summary.sh — retroactive audit for the direct-commit
# auto-close trap (#151). Classifies CLOSED issues by what their
# `## Closing Summary` marker looks like — issues with none may have been
# auto-closed by a commit / PR-body close keyword, bypassing the /idd-close gate
# (checklist / semantic / sister-sweep / residue / distribution-sync).
#
# Four classes (#295) — this file is their NORMATIVE SOURCE:
#   own-comment   canonical heading at the start of a comment, with content
#   casing        same, but non-canonical form (casing / 1-3 leading spaces)
#   mid-comment   heading with content, not at the comment's start — UNVERIFIED
#   missing       none of the above
#
# Output: three sections, printed only when non-empty. MISSING and MID-COMMENT
# both carry ⚠; only MISSING invites `--retroactive`. All-clear is a single ✓
# line when every closed issue is own-comment.
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

# ── Classify: what does each CLOSED issue's summary marker actually look like? ──
#
# NORMATIVE SOURCE for the four classes (#295). The prose consumers — idd-list
# `--audit-closes` and idd-close `--retroactive` — follow these definitions;
# when they disagree with this filter, this filter is right.
#
#   own-comment  a comment starts with the canonical `## Closing Summary`
#                AND has content under it
#   casing       a comment's FIRST line is that heading in a non-canonical form
#                (different casing, or 1-3 leading spaces), with content under it
#   mid-comment  a heading with content under it appears in LIVE markdown, but
#                not at the start of its comment — **unverified**: the tool has
#                not established that what follows is really a summary
#   missing      no closing-summary heading in live markdown, or the heading has
#                nothing under it
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
# `head_re` has NO trailing `\b` on purpose: `_` is a word character, so a word
# boundary there would refuse `## closing summary_v2` — a plausible way to head
# a revised summary — and misfile a present summary as `missing`. Indentation is
# capped at three spaces (CommonMark): four or more is an indented code block,
# not a heading.
#
# Three hardenings from the #295 verify round, each reproduced before fixing:
#
# 1. LIVE MARKDOWN ONLY. The first version matched the heading on any line of any
#    comment, so merely *quoting* it exonerated an issue that had no summary —
#    and the report then asserted "the summary IS there". Reachable by ordinary
#    content, not just attack: `skills/idd-close/SKILL.md` prints the canonical
#    template inside a fence, so any comment reproducing it tripped this. The
#    HTML-comment case was worse — invisible in a browser while the audit
#    insisted a summary existed. `live_lines` drops fenced blocks, HTML comments
#    and indented code before the heading is looked for.
#
# 2. A HEADING IS NOT A SUMMARY. A comment whose entire body is `## Closing
#    Summary` used to classify own-comment and vanish from the report. Every
#    class now requires at least one non-blank line under the heading.
#
# 3. THE TITLE IS UNTRUSTED DATA. The record below is `class\t#N  title`, parsed
#    positionally downstream. Both delimiters were in-band and the title was
#    interpolated raw, so a newline in a title forged a whole row — including
#    into the one section that invites the irreversible `--retroactive`.
#    `sanitize` collapses every control character to a space, which closes the
#    forging channel, the tab-truncation bug and the ANSI-repaint channel at once.
CLASSIFY='
  # `^ {0,3}` is CommonMark: four or more spaces is an indented code block, not
  # a heading. It is REDUNDANT given `live_lines` (which already drops indented
  # lines) and therefore has NO test of its own — acid confirmed that widening
  # it back to `[ \t]*` turns nothing red, because no input can distinguish the
  # two. Kept as the second line if `live_lines` is ever simplified, and labelled
  # here rather than left to look like tested protection.
  def head_re: "^ {0,3}##[ \t]*closing[ \t]+summary";
  # Control characters are structural here (record + field delimiters) and can
  # also repaint a terminal. One substitution neutralises all three uses.
  #
  # `[[:cntrl:]]`, not a `\uXXXX` range: Oniguruma does not read ` ` as an
  # escape inside a jq string, so `[ -]` silently degrades into the
  # literal range `0`-`u` and eats most of the alphabet. Caught because every
  # fixture title came back as fragments like " y ( - - v )".
  def sanitize: (. // "") | gsub("[[:cntrl:]]"; " ") | gsub(" +"; " ");
  # Which lines are LIVE markdown, keeping the ORIGINAL index of each line.
  #
  # NOTE: this jq program lives inside a single-quoted shell string, so it must
  # contain no apostrophe anywhere -- not even in a comment. Writing a real
  # apostrophe here silently closed the string and produced a bash syntax error
  # two lines further down.
  #
  # The index matters (#295 R3): the heading must be found in live markdown --
  # a quoted heading is not a heading -- but "is there content under it" has to
  # be answered against the RAW lines. Round 2 used the live list for both, so
  # a real summary whose body sat entirely inside a fence classified missing
  # and was routed to the one class --retroactive admits. One mechanism was
  # borrowed for a second job whose semantics differ: content inside a fence is
  # still content, it just is not a heading.
  #
  # HTML comments are stripped as a SPAN, not by deleting the line, and the
  # block form is anchored at line start (CommonMark HTML block type 2). Round
  # 2 deleted any line containing an HTML-comment opener, which erased a
  # canonical heading carrying an inline marker -- and IDD itself writes
  # markers like idd:dashboard into comments, so that was reachable by the
  # conventions of this very plugin.
  def strip_html_span: gsub("<!--(?:(?!-->)[\\s\\S])*-->"; "");
  def live_pairs:
    ((. // "") | split("\n")) as $raw
    | reduce range(0; $raw | length) as $k ({f:false, h:false, out:[]};
        ($raw[$k] | strip_html_span) as $l
        | if .f     then (if ($l | test("^ {0,3}(```|~~~)")) then .f = false else . end)
          elif .h   then (if ($l | test("-->"))              then .h = false else . end)
          elif ($l | test("^ {0,3}(```|~~~)"))               then .f = true
          elif ($l | test("^ {0,3}<!--"))                    then .h = true
          elif ($l | test("^(    |\t)"))                    then .
          else .out += [[$k, $l]] end)
    | .out;
  # A heading counts only when ITS OWN section carries something non-blank.
  #
  # "Its own section" = the RAW lines after the heading, up to the next h1/h2.
  # Both halves were wrong before: round 2 asked the LIVE lines (so a summary
  # written entirely inside a fence read as empty), and round 3 first widened it
  # to every RAW line after the heading (so an unrelated later section made an
  # EMPTY summary look filled -- a heading with nothing under it then classified
  # own-comment and vanished from the report entirely). Raw lines, bounded by
  # the section, is the predicate the class definitions actually claim.
  def heading_at:
    . as $b
    | (($b // "") | split("\n")) as $raw
    | ([$b | live_pairs | .[] | select(.[1] | test(head_re; "i")) | .[0]] | first) as $k
    | if $k == null then null else
        ($raw[($k + 1):]) as $rest
        | ([range(0; $rest | length) | select($rest[.] | test("^ {0,3}#{1,2}[ \t]"))] | first) as $stop
        | (if $stop == null then $rest else $rest[0:$stop] end) as $section
        | if ($section | any(test("\\S"))) then $k else null end
      end;
  .[]
  | select((.state // "CLOSED") | ascii_upcase == "CLOSED")
  | . as $i
  | [$i.comments[]?.body // ""] as $bodies
  | (if ($bodies | any(startswith("## Closing Summary") and (heading_at == 0)))
                                                             then "own-comment"
     elif ($bodies | any(heading_at == 0))                    then "casing"
     elif ($bodies | any(heading_at != null))                 then "mid-comment"
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

# CASING says "non-canonical form", not "cased differently": the class also
# covers a heading indented one to three spaces, whose casing is perfectly
# correct. Naming the wider thing after its commonest member told the reader to
# fix something that was not wrong.
if [ -n "$CASING" ]; then
  echo "CASING — heading is not in canonical form (different casing, or 1-3 leading spaces); a summary IS under it (normalize the heading — do NOT run --retroactive):"
  printf '%s\n' "$CASING" | sed 's/^/    /'
  echo ""
fi

# MID-COMMENT is stated as UNVERIFIED and keeps the ⚠, because the tool cannot
# tell a real summary from a quoted one once the heading is not at the start of
# its comment. The first version asserted "the summary IS there" and dropped the
# glyph — a guess that switched off the only alarm. Erring loud is the whole
# point of a safety net; the earlier wording erred silent.
if [ -n "$MIDCOMMENT" ]; then
  echo "MID-COMMENT (unverified) — a heading with content under it was found, but not at the start of its comment. Whether it is a real summary or a quoted one was NOT established — inspect by hand; do NOT run --retroactive on the strength of this line alone:"
  printf '%s\n' "$MIDCOMMENT" | sed 's/^/  ⚠ /'
  echo ""
fi

echo "(advisory — legacy / pre-IDD / GitHub-UI-closed issues are expected under MISSING; narrow with --since / --limit)"
exit 0
