#!/usr/bin/env bash
# check-closed-without-summary.sh — retroactive audit for the direct-commit
# auto-close trap (#151). Classifies CLOSED issues by what their
# `## Closing Summary` marker looks like — issues with none may have been
# auto-closed by a commit / PR-body close keyword, bypassing the /idd-close gate
# (checklist / semantic / sister-sweep / residue / distribution-sync).
#
# Four destinations (#295) — this file is their NORMATIVE SOURCE:
#   missing    no heading-shaped line anywhere in any comment (RAW text)
#   present    such a line exists, but no comment leads with one, or the one that
#              does has nothing under it — UNVERIFIED
#   casing     a comment leads with it WITH content under it, non-canonical form
#   (quiet)    a comment leads with the canonical `## Closing Summary`, with
#              content under it
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
    # Print the whole leading comment block, however long it grows. The old
    # fixed range (2,16p) silently dropped Usage and the "ALWAYS exits 0"
    # promise the moment the header grew past line 16.
    -h|--help)   sed -n '2,/^$/p' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
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
# direction.
#
# HOW FAR THAT ACTUALLY GOES — round 5 claimed here that the expensive direction
# was "unreachable by construction". That was FALSE, and every lens said so: the
# recogniser had simply become the new single point of failure, and an emoji-
# decorated h2, an h3, a setext heading and a non-breaking space all still routed
# real summaries to `missing`. Round 6 widened the recogniser and split it in two
# (see CLASSIFY), which closes those. The honest statement is narrower: the
# destructive class is reached only when NO line in any comment resembles the
# heading, and the recogniser is deliberately generous about what resembles it.
# It is not a proof, and the shapes it still misses are listed in the tests.
#
# ONE KNOWN BLIND SPOT, stated rather than fixed: only COMMENTS are fetched, so a
# summary someone wrote into the ISSUE BODY instead of a comment reads as
# missing. Writing it there is not the documented flow (idd-close posts a
# comment), and widening the fetch would change the contract idd-list mirrors --
# but the consequence lands on the destructive path, so it is recorded here and
# in the idd-close precondition rather than left for a seventh round to find.
#
# `casing` and `present` keep the information the old two-way marker threw away
# (10 of 43 closed issues in a real repo had drifted to `## Closing summary`),
# but neither authorises anything. `casing` additionally requires content under
# the heading, so it can state that the summary is there; `present` states
# nothing at all beyond existence.
#
# The recognisers deliberately have no trailing `\b`: `_` is a word character, so
# a word boundary would refuse `## closing summary_v2` — a plausible way to head
# a revised summary — and misfile a present summary as missing.
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
  # TWO PREDICATES, NOT ONE (round 6). Rounds 1-5 used a single heading regex to
  # answer two questions whose SAFE DIRECTIONS ARE OPPOSITE, and round 5 failed
  # on exactly that: blockquote prefixes and unlimited indentation were added to
  # make the presence test permissive, the same regex then decided the lead test,
  # and a comment that merely QUOTED the heading was announced as "the summary is
  # there" with the warning glyph withheld. That is the round-1 defect restored.
  #
  #   present_re / bare_re   Q1: could a reader see a closing-summary heading
  #     ANYWHERE? Over-detecting withholds the destructive action, so these are
  #     deliberately permissive: any indentation, blockquote markers, one to six
  #     hashes (fullwidth included), any non-letter decoration between the hashes
  #     and the words -- emoji headings are this plugin house style, idd-comment
  #     ships six of them -- and non-breaking or ideographic spaces inside the
  #     phrase. `bare_re` additionally catches a line that is ESSENTIALLY JUST the
  #     phrase, which covers setext headings and bold pseudo-headings.
  #
  #   lead_re   Q2: does this comment LEAD with a real heading? Over-detecting
  #     exonerates an issue with a positive claim, so this one is strict: a
  #     genuine ATX heading, no blockquote prefix, at most three spaces of indent.
  #
  # Hash count is 1-6, not 1-2. Excluding h3 bought nothing -- a subsection like
  # `### Problem` does not contain the phrase -- while sending a summary written
  # at h3 straight to the destructive class.
  def present_re: "^[ \t>]*[#\\x{FF03}]{1,6}[^\\p{L}\\p{N}]*closing[\\s\\x{00A0}\\x{200B}\\x{3000}]+summary";
  def bare_re:    "^[ \t>]*[^\\p{L}\\p{N}]*closing[\\s\\x{00A0}\\x{200B}\\x{3000}]+summary[^\\p{L}\\p{N}]*$";
  def lead_re:    "^ {0,3}#{1,6}[^\\p{L}\\p{N}]*closing[\\s\\x{00A0}\\x{200B}\\x{3000}]+summary";
  # Control characters are structural here (record + field delimiters) and can
  # also repaint a terminal; U+2028/U+2029 and the bidi controls can forge or
  # reorder a row in any renderer that honours them. One substitution covers all.
  #
  # U+200C ZWNJ and U+200D ZWJ are deliberately NOT in the class: they are
  # letter-joining controls in Persian and the Indic scripts, and ZWJ is what
  # holds an emoji sequence together -- stripping it splits a woman-technologist
  # into two people. Neither can forge or reorder a row, which is what this
  # substitution is for. The first cut wrote the range 200B-200F and did exactly
  # that damage.
  #
  # POSIX class names, not a numeric escape range: Oniguruma does not read the
  # backslash-u form inside a jq string, so a range written that way silently
  # degrades into the literal range 0 to u and eats most of the alphabet. It was
  # caught only because every fixture title came back as fragments.
  def sanitize:
    (. // "")
    | gsub("[[:cntrl:]\\p{Zl}\\p{Zp}\\x{061C}\\x{200B}\\x{200E}\\x{200F}\\x{202A}-\\x{202E}"
           + "\\x{2060}-\\x{2064}\\x{2066}-\\x{2069}\\x{FEFF}\\x{E0000}-\\x{E007F}]"; " ")
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
  # would have sent every marker that is not on line 1 to missing, which is the
  # failure this rewrite exists to make unreachable.
  def has_heading_anywhere:
    ((. // "") | split("\n"))
    | any(test(present_re; "i") or test(bare_re; "i"));
  # Does anything non-blank follow the lead line? A heading with nothing under it
  # is not a summary, and letting it read as compliant made such an issue
  # INVISIBLE -- printed in no section at all, while --retroactive also aborts on
  # it. Anyone who can comment could silence a closed issue permanently by
  # posting a bare heading. It now lands in `present`: visible, authorising
  # nothing.
  def lead_has_content:
    ((. // "") | split("\n")) as $l
    | ([range(0; $l | length) | select(($l[.] | test("^[ \t]*$") | not)
                                       and ($l[.] | test("^[ \t]*<!--.*-->[ \t]*$") | not))] | first) as $k
    | if $k == null then false
      else
        # Content is either something non-blank on a LATER line, or something
        # substantive left on the heading line once the heading itself is
        # removed -- a one-line summary such as
        # `## Closing Summary: fixed the parser, suite green` is a summary.
        # The first cut asked whether the lead line contained a 20-character
        # unbroken run, which no ordinary sentence has; it failed that exact
        # fixture.
        (($l[($k + 1):] | any(test("\\S")))
         or ($l[$k] | sub(present_re; ""; "i") | test("\\S\\S\\S")))
      end;
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
  #
  # `state` absent or null now reads as NOT closed. It used to default to CLOSED,
  # which was the one default in the file leaning toward the destructive action.
  .[]
  | select(((.state // "") | ascii_upcase) == "CLOSED")
  | . as $i
  | [$i.comments[]?.body // ""] as $bodies
  | (if   ($bodies | any((lead_line | startswith("## Closing Summary")) and lead_has_content))
                                                                        then "compliant"
     elif ($bodies | any((lead_line | test(lead_re; "i")) and lead_has_content))
                                                                        then "casing"
     elif ($bodies | any(has_heading_anywhere))                         then "present"
     else "missing" end) as $class
  | "\($class)\t#\($i.number | tostring | sanitize)  \($i.title | sanitize)"
'
# jq errors must NOT become a false all-clear: stderr is captured and a non-zero
# exit aborts with a note instead of printing "✓ nothing missing" over a filter
# that died halfway (the same fail-safe direction as the malformed-JSON guard).
JQ_ERR=$(mktemp "${TMPDIR:-/tmp}/csw_jq_err.XXXXXX") || JQ_ERR=""
if ! CLASSIFIED=$(printf '%s' "$ISSUES_JSON" | jq -r "$CLASSIFY" 2>"${JQ_ERR:-/dev/null}"); then
  echo "note: classification filter failed — audit skipped, no conclusion drawn." >&2
  # jq quotes the offending INPUT in its message, so this text is untrusted:
  # control characters and bidi overrides here would bypass `sanitize` entirely
  # and repaint the terminal. Strip them, and cap the volume.
  [ -n "$JQ_ERR" ] && LC_ALL=C tr -d "\000-\010\013\014\016-\037\177" < "$JQ_ERR" \
    | head -5 | sed "s/^/      jq: /" >&2
  [ -n "$JQ_ERR" ] && rm -f "$JQ_ERR"
  exit 0
fi
[ -n "$JQ_ERR" ] && rm -f "$JQ_ERR"

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
  echo "CASING — a comment leads with the heading and has content under it, but the heading is not canonical (casing, indentation, or a suffix like _v2). Normalize the heading — do NOT run --retroactive:"
  printf '%s\n' "$CASING" | sed 's/^/    /'
  echo ""
fi

echo "(advisory — legacy / pre-IDD / GitHub-UI-closed issues are expected under MISSING; narrow with --since / --limit)"
exit 0
