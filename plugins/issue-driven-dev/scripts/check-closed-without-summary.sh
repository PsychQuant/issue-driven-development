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
# Advisory only in AUDIT mode — it ALWAYS exits 0 there.
#
# `--issue N` is the exception, and deliberately so. Audit mode reports to a
# human; `--issue N` is a GATE for `/idd-close --retroactive`, whose action is
# irreversible (it posts a second summary onto an issue that may already have
# one). A gate that always exits 0 is not a gate — the caller has to interpret
# prose, which is how seven rounds of work on this classifier stayed advisory
# while the destructive path went on deciding for itself.
#
# Usage:
#   check-closed-without-summary.sh [--repo owner/repo] [--limit N] [--since YYYY-MM-DD]
#   check-closed-without-summary.sh --json-file <path>     # test / offline mode
#   check-closed-without-summary.sh --issue N [--repo …]   # single-issue GATE
#
# `--issue N` prints one JSON object and exits:
#   0  class == missing, comment set known complete   -> --retroactive may run
#   1  any other class                                -> refuse, it has one
#   2  could not determine (not closed / truncated /  -> refuse
#      fetch or parse failure / no such issue)
# Everything that is not a confident `missing` refuses. Fail-closed is the only
# safe default when the action cannot be undone.
#
# Consumed by idd-list `--audit-closes`. The `## Closing Summary` heading is the
# same marker idd-list Step 3 keys on for phase inference.

set -u

JSON_FILE=""
REPO=""
LIMIT=50
SINCE=""
DRY_RUN=0
GATE_ISSUE=""
# Whether `--issue` was PASSED, tracked separately from whether it has a value.
# Keying gate mode off `[ -n "$GATE_ISSUE" ]` meant `--issue ""` — which is what
# `--issue "$NUMBER"` expands to when NUMBER is unset — skipped the whole gate
# block and fell through to AUDIT mode, whose contract is to always exit 0. The
# caller read that 0 as "confirmed missing, go ahead and post". The validator's
# own `''` arm was unreachable for the same reason.
GATE_SEEN=0
GATE_ERR=""

while [ $# -gt 0 ]; do
  case "$1" in
    # `shift 2` with only one argument left is a no-op in some shells, so a
    # trailing value-taking flag looped forever — the advisory contract promises
    # exit 0, and never exiting breaks it harder than any wrong verdict.
    --json-file) JSON_FILE="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --issue)     GATE_SEEN=1; GATE_ISSUE="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --repo)      REPO="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --limit)     LIMIT="${2:-50}"; shift; [ $# -gt 0 ] && shift ;;
    --since)     SINCE="${2:-}"; shift; [ $# -gt 0 ] && shift ;;
    --dry-run)   DRY_RUN=1; shift ;;   # gh mode: print the composed gh command + exit (offline introspection / test seam)
    # Print the whole leading comment block, however long it grows. The old
    # fixed range (2,16p) silently dropped Usage and the "ALWAYS exits 0"
    # promise the moment the header grew past line 16.
    -h|--help)   sed -n '2,/^$/p' "$0" | sed 's/^#\{1,\} \{0,1\}//'; exit 0 ;;
    *)           echo "unknown arg: $1" >&2; shift ;;
  esac
done

# ── Gate mode plumbing (--issue N) ──
# One JSON object on stdout, and an exit code the caller cannot misread. Every
# path that is not a confident `missing` on a complete comment set exits 2 (or
# 1), because the caller is about to do something irreversible.
gate_out() {  # $1=class-or-empty  $2=state-or-empty  $3=complete(true/false)  $4=error-or-empty  $5=exit code
  jq -n --arg n "$GATE_ISSUE" --arg c "${1:-}" --arg s "${2:-}" \
        --argjson complete "${3:-false}" --arg e "${4:-}" \
    '{number: ($n | tonumber? // null),
      state: (if $s == "" then null else $s end),
      class: (if $c == "" then null else $c end),
      comments_complete: $complete,
      error: (if $e == "" then null else $e end)}'
  exit "$5"
}
if [ "$GATE_SEEN" = 1 ]; then
  # Validated before it is interpolated into an API path, and before anything
  # downstream compares it numerically. Gated on GATE_SEEN, not on the value:
  # an empty value is exactly the case that must be refused, and testing the
  # value here would skip the refusal for it.
  case "$GATE_ISSUE" in
    ''|*[!0-9]*) gate_out "" "" false "--issue expects an integer issue number" 2 ;;
  esac
fi

# ── Acquire issue JSON ──
if [ -n "$JSON_FILE" ]; then
  if [ ! -f "$JSON_FILE" ]; then
    [ -n "$GATE_ISSUE" ] && gate_out "" "" false "--json-file not found: $JSON_FILE" 2
    echo "✗ --json-file not found: $JSON_FILE" >&2; exit 0
  fi
  ISSUES_JSON=$(cat "$JSON_FILE")
  if [ -n "$GATE_ISSUE" ]; then
    # Narrow to the one issue. An offline payload carries whatever comments the
    # fixture author put there, so completeness is whatever the fixture says.
    ISSUES_JSON=$(printf '%s' "$ISSUES_JSON" \
      | jq --argjson n "$GATE_ISSUE" '[.[] | select(.number == $n)]' 2>/dev/null) \
      || gate_out "" "" false "could not read the offline payload" 2
    [ "$(printf '%s' "$ISSUES_JSON" | jq 'length' 2>/dev/null)" = "1" ] \
      || gate_out "" "" false "issue #$GATE_ISSUE is not in the payload" 2
  fi
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
    # The global layer (#302). Nothing read it before: the walk-up only ever
    # checked `local.json` and the legacy name, so the CHANGELOG's claim that
    # the path was "already on the walk-up route, just recognise one more
    # filename" described a change that had not been made. It is made here.
    #
    # It is a LAST resort and it is not a repo boundary: `$HOME` is not a repo,
    # which is exactly why the file is named `global.json` rather than
    # `local.json` — the latter would make the walk-up read `$HOME` as one.
    if [ -z "$REPO" ] && [ -f "$HOME/.claude/.idd/global.json" ]; then
      REPO=$(jq -r '.default_github_repo // .github_repo // empty' \
               "$HOME/.claude/.idd/global.json" 2>/dev/null)
      [ -n "$REPO" ] && echo "note: repo resolved from the global layer ($REPO) — no repo-local config found." >&2
    fi
  fi
  if [ -n "$GATE_ISSUE" ]; then
    # Gate mode fetches ONE issue, and fetches its comments through REST with
    # --paginate rather than the nested `--json comments` connection. That is
    # not a preference: the nested form is hard-capped at the OLDEST 100, and a
    # closing summary is by construction the NEWEST comment. The audit path
    # repairs that after the fact; the gate simply never takes the broken road.
    GATE_REPO="$REPO"
    [ -z "$GATE_REPO" ] && GATE_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
    [ -n "$GATE_REPO" ] || gate_out "" "" false "could not resolve the target repo" 2
    META=$(gh issue view "$GATE_ISSUE" --repo "$GATE_REPO" --json number,title,state 2>/dev/null) \
      || gate_out "" "" false "could not fetch issue #$GATE_ISSUE from $GATE_REPO" 2
    # `gh ... | jq -s 'add // []'` in one pipeline was the #320 CRITICAL, found
    # independently by four lenses. This script sets `set -u` and nothing else,
    # so `if !` observed JQ's status — and `jq -s 'add // []'` exits 0 on empty
    # stdin, printing `[]`. A 403, a 5xx, or a `--paginate` leg dying halfway
    # was therefore INDISTINGUISHABLE from "this issue has no comments", and the
    # classifier answered `missing` — the sole authorisation for an irreversible
    # duplicate post. The partial case is the worse one and is not exotic:
    # --paginate streams OLDEST first, so a mid-pagination failure keeps the old
    # comments and drops the newest, which is by construction where a closing
    # summary lives.
    #
    # Two syscalls, two checks. gh writes to a file; ITS status is tested; only
    # then is the text parsed, and jq's failure is a separate refusal.
    CMTS_RAW=$(mktemp) || gate_out "" "" false "could not create a temp file" 2
    if ! gh api "repos/$GATE_REPO/issues/$GATE_ISSUE/comments" --paginate \
           --jq '[.[] | {body}]' >"$CMTS_RAW" 2>/dev/null; then
      rm -f "$CMTS_RAW"
      gate_out "" "" false "could not fetch the comments of #$GATE_ISSUE (network / auth / rate limit / partial pagination)" 2
    fi
    if ! CMTS=$(jq -s 'add // []' <"$CMTS_RAW" 2>/dev/null); then
      rm -f "$CMTS_RAW"
      gate_out "" "" false "the comment fetch returned unparseable JSON" 2
    fi
    rm -f "$CMTS_RAW"
    printf '%s' "$CMTS" | jq -e 'type == "array"' >/dev/null 2>&1 \
      || gate_out "" "" false "the comment fetch returned something that is not an array" 2
    ISSUES_JSON=$(printf '%s' "$META" | jq --argjson c "$CMTS" '[. + {comments: $c}]' 2>/dev/null) \
      || gate_out "" "" false "could not assemble the issue payload" 2
  else
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

  # ── The acquisition layer truncates, and it truncates the wrong end ──
  #
  # `gh issue list --json comments` resolves the nested GraphQL connection as
  # `comments(first: 100)`. It is hard-capped, it does NOT paginate, and the 100
  # it returns are the OLDEST. Verified against a public repo, not assumed:
  #
  #   gh issue list -R microsoft/vscode --state closed --search "comments:>150" \
  #     --json number,comments --limit 3   ->  every row returns exactly 100
  #   gh api repos/microsoft/vscode/issues/301011 --jq .comments   ->  155
  #   first returned comment createdAt == REST comments?page=1 created_at  ->  oldest
  #
  # A closing summary is by construction the NEWEST comment, so on any issue past
  # 100 comments it is precisely the element guaranteed to be dropped — and the
  # classifier then sees no heading and says `missing`, the one class that invites
  # the irreversible `--retroactive`. Six verify rounds worked on the classifier
  # and none of them could have found this: it is not in the classifier.
  #
  # It also falsified this file's own normative definition. "NO line in ANY
  # comment" is a property the filter could not evaluate, because it never had
  # all the comments.
  #
  # Fix: re-fetch in full, per issue, but only for the issues that are actually
  # at the cap. `length >= 100` is the truncation signal.
  TRUNCATED=$(printf '%s' "$ISSUES_JSON" | jq -r '[.[] | select((.comments | length) >= 100) | .number] | .[]' 2>/dev/null)
  if [ -n "$TRUNCATED" ]; then
    RESOLVED_REPO="$REPO"
    [ -z "$RESOLVED_REPO" ] && RESOLVED_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
    for n in $TRUNCATED; do
      # `gh api --paginate --jq` emits ONE JSON ARRAY PER PAGE, concatenated —
      # NOT one value. Verified against microsoft/vscode#301011 (155 comments):
      # the output fails to parse ("Extra data: line 2 column 1"), so --argjson
      # rejected it, jq died, ISSUES_JSON became empty, and the empty-payload
      # guard silently disabled the WHOLE audit on any repo containing a long
      # issue. `jq -s add` folds the pages into one array. (`--slurp` is not an
      # option here: gh refuses it together with --jq.)
      #
      # `.number` is validated as an integer first: it is fetched data, and it
      # is being interpolated into an API path.
      case "$n" in
        ''|*[!0-9]*) echo "note: skipping non-numeric issue id in re-fetch" >&2; continue ;;
      esac
      FULL=$(gh api "repos/$RESOLVED_REPO/issues/$n/comments" --paginate \
               --jq '[.[] | {body}]' 2>/dev/null | jq -s 'add // []' 2>/dev/null)
      # An empty/!valid result must NOT be treated as success: a partial re-fetch
      # that SHRINKS the comment set would route a real summary to `missing`.
      if [ -n "$FULL" ] && printf '%s' "$FULL" | jq -e 'type == "array" and length > 0' >/dev/null 2>&1; then
        # Refuse a re-fetch that returns FEWER comments than we already had —
        # that is a partial page, and swapping it in would delete evidence.
        ISSUES_JSON=$(printf '%s' "$ISSUES_JSON" \
          | jq --argjson full "$FULL" --argjson n "$n" '
              map(if (.number | tostring) == ($n | tostring)
                  then (if ($full | length) >= (.comments | length)
                        then .comments = $full
                        else .idd_comments_truncated = true end)
                  else . end)') || ISSUES_JSON=""
        [ -z "$ISSUES_JSON" ] && { echo "note: re-fetch merge failed — audit skipped, no conclusion drawn." >&2; exit 0; }
      else
        # Could not complete the fetch. Do NOT let a partial comment set decide
        # the destructive class: mark it so the classifier can never call it
        # `missing`. Same fail-safe direction as the malformed-JSON guard.
        ISSUES_JSON=$(printf '%s' "$ISSUES_JSON" \
          | jq --argjson n "$n" 'map(if .number == $n then .idd_comments_truncated = true else . end)')
        echo "note: issue #$n has more comments than one page and the full fetch failed — it will never be reported as missing." >&2
      fi
    done
  fi
  fi
fi

# Fail-safe: if the acquired payload is NOT valid JSON (e.g. gh returned 0 with a
# truncated stream / proxy HTML, or a hand-edited fixture is malformed), do NOT
# fall through to the filter and print a false "✓ all-clear" — that's the worst
# direction for a safety-net audit (false reassurance). Warn + exit, no verdict.
# In gate mode the same conditions must exit 2, not 0: `exit 0` there would
# read as "confirmed missing, go ahead and post".
if [ -z "$(printf '%s' "$ISSUES_JSON" | tr -d '[:space:]')" ]; then
  [ -n "$GATE_ISSUE" ] && gate_out "" "" false "issue payload is empty" 2
  echo "note: issue payload is empty — audit skipped, no conclusion drawn." >&2
  exit 0
fi
if ! printf '%s' "$ISSUES_JSON" | jq -e 'type == "array"' >/dev/null 2>&1; then
  [ -n "$GATE_ISSUE" ] && gate_out "" "" false "issue payload is not a JSON array" 2
  echo "note: issue payload is not a JSON array — audit skipped, no conclusion drawn." >&2
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
  # Two forms. (a) a line that is ESSENTIALLY JUST the phrase — setext titles,
  # bare title lines. The trailing anchor is what keeps ordinary prose ("I forgot
  # the closing summary, sorry") out of the presence test, which matters: 5 of 9
  # genuinely-missing issues in a real repo mention the phrase in prose and must
  # stay flagged. (b) an EMPHASISED heading, which may carry a tail — the `$`
  # anchor alone sent `**Closing Summary** - fixed the parser` to `missing`.
  def bare_re:    "^[ \t>]*[^\\p{L}\\p{N}]*closing[\\s\\x{00A0}\\x{200B}\\x{3000}]+summary[^\\p{L}\\p{N}]*$";
  def emph_re:    "^[ \t>]*(\\*\\*|__|\\*|_)[^\\p{L}\\p{N}]*closing[\\s\\x{00A0}\\x{200B}\\x{3000}]+summary";
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
  # ONE notion of "a line a reader sees", used by BOTH the lead test and the
  # content test. They used to disagree: lead_line skipped whole-line HTML
  # markers, lead_has_content did not, so an HTML comment counted as the summary
  # under a heading. `## Closing Summary` + `<!-- TODO -->` read as compliant --
  # printed in NO section at all, and --retroactive refuses it too -- which is
  # the silencing channel the content test was added to close, reopened one
  # level down. A blank line and an invisible line are the same thing to a
  # reader, so they are the same thing here.
  #
  # Only SINGLE-LINE HTML comments are recognised, deliberately. Spanning ones
  # need the fence/comment state machine that rounds 1-4 removed, and the
  # residual error is on the cheap side: it hides an issue rather than
  # authorising a duplicate post.
  def invisible_line: test("^[ \t]*$") or test("^[ \t]*<!--.*-->[ \t]*$");
  def lead_line:
    ((. // "") | split("\n"))
    | map(select(invisible_line | not))
    | (first // "");
  # Oniguruma anchors ^ to the START OF THE STRING, not to each line -- verified,
  # not assumed. Lines are therefore split explicitly; relying on the anchor
  # would have sent every marker that is not on line 1 to missing, which is the
  # failure this rewrite exists to make unreachable.
  def has_heading_anywhere:
    ((. // "") | split("\n"))
    | any(test(present_re; "i") or test(bare_re; "i") or test(emph_re; "i"));
  # Does anything non-blank follow the lead line? A heading with nothing under it
  # is not a summary, and letting it read as compliant made such an issue
  # INVISIBLE -- printed in no section at all, while --retroactive also aborts on
  # it. Anyone who can comment could silence a closed issue permanently by
  # posting a bare heading. It now lands in `present`: visible, authorising
  # nothing.
  def lead_has_content:
    ((. // "") | split("\n")) as $l
    | ([range(0; $l | length) | select($l[.] | invisible_line | not)] | first) as $k
    | if $k == null then false
      else
        # Content is either something non-blank on a LATER line, or something
        # substantive left on the heading line once the heading itself is
        # removed -- a one-line summary such as
        # `## Closing Summary: fixed the parser, suite green` is a summary.
        # The first cut asked whether the lead line contained a 20-character
        # unbroken run, which no ordinary sentence has; it failed that exact
        # fixture.
        # "Content" means letters or digits, not merely non-space. Asking for
        # non-space let three dots stand in for a summary, which re-opened the
        # silencing channel this check exists to close: anyone who can comment
        # could post `## Closing Summary` + `...` and remove a closed issue from
        # the audit permanently.
        # Later lines are filtered through the SAME visibility rule as the lead
        # line before being counted -- see `invisible_line`.
        (($l[($k + 1):] | map(select(invisible_line | not)) | any(test("[\\p{L}\\p{N}]")))
         or ($l[$k] | sub(present_re; ""; "i") | test("[\\p{L}\\p{N}].*[\\p{L}\\p{N}]")))
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
     # A comment set we know is incomplete can never justify the destructive
     # class: absence of evidence is not evidence of absence when the evidence
     # was truncated at the fetch. Falls to `present`, which authorises nothing.
     elif ($i.idd_comments_truncated == true)                           then "present"
     else "missing" end) as $class
  | "\($class)\t#\($i.number | tostring | sanitize)  \($i.title | sanitize)"
'
# jq errors must NOT become a false all-clear: stderr is captured and a non-zero
# exit aborts with a note instead of printing "✓ nothing missing" over a filter
# that died halfway (the same fail-safe direction as the malformed-JSON guard).
JQ_ERR=$(mktemp "${TMPDIR:-/tmp}/csw_jq_err.XXXXXX") || JQ_ERR=""
if ! CLASSIFIED=$(printf '%s' "$ISSUES_JSON" | jq -r "$CLASSIFY" 2>"${JQ_ERR:-/dev/null}"); then
  echo "note: classification filter failed — audit skipped, no conclusion drawn." >&2
  # jq may quote the offending INPUT in its message, so treat this text as
  # untrusted and cap the volume.
  #
  # WHAT THIS ACTUALLY STRIPS, stated precisely because the comment used to
  # claim more than the code did: ASCII control characters, and nothing else.
  # `tr` under LC_ALL=C works on BYTES, so it cannot see U+202E, U+2028 or the
  # bidi isolates — they are multi-byte, and deleting their bytes individually
  # would corrupt the surrounding UTF-8. Only `sanitize` (inside CLASSIFY) has
  # the Unicode-aware version, and this path is precisely the one where CLASSIFY
  # did not run.
  #
  # Whether that gap is reachable was measured, not assumed: three payloads
  # (U+202E, U+2028, ESC) planted where a bare string reaches `.state` produce
  # `Cannot index string with string ("state")` on jq 1.7 — the value is NOT
  # echoed, so nothing attacker-controlled arrives here at all. Recorded as a
  # clean negative rather than fixed: a Unicode-aware scrub would mean a second
  # copy of the character class, and a divergent copy of a safety definition is
  # the failure mode this file has the longest history with. If a jq that does
  # echo the value ever shows up, this is the line to change.
  [ -n "$JQ_ERR" ] && LC_ALL=C tr -d "\000-\010\013\014\016-\037\177" < "$JQ_ERR" \
    | head -5 | sed "s/^/      jq: /" >&2
  [ -n "$JQ_ERR" ] && rm -f "$JQ_ERR"
  [ -n "$GATE_ISSUE" ] && gate_out "" "" false "classification filter failed" 2
  exit 0
fi
[ -n "$JQ_ERR" ] && rm -f "$JQ_ERR"

# ── Gate verdict ──
# CLASSIFY only emits a row for issues whose state is CLOSED, so an empty result
# here means "not closed" — which is not a retroactive case at all, and is
# exactly the state in which posting a second summary would be worst.
if [ -n "$GATE_ISSUE" ]; then
  GATE_STATE=$(printf '%s' "$ISSUES_JSON" | jq -r '.[0].state // ""' 2>/dev/null)
  GATE_TRUNC=$(printf '%s' "$ISSUES_JSON" | jq -r 'if .[0].idd_comments_truncated == true then "true" else "false" end' 2>/dev/null)
  GATE_CLASS=$(printf '%s\n' "$CLASSIFIED" | awk -F'\t' 'NF { print $1; exit }')
  [ -n "$GATE_CLASS" ] || gate_out "" "$GATE_STATE" false \
    "issue #$GATE_ISSUE is not CLOSED — not a retroactive case" 2
  if [ "$GATE_TRUNC" = "true" ]; then
    gate_out "$GATE_CLASS" "$GATE_STATE" false \
      "the comment set is known to be incomplete — absence proves nothing" 2
  fi
  case "$GATE_CLASS" in
    missing) gate_out missing "$GATE_STATE" true "" 0 ;;
    *)       gate_out "$GATE_CLASS" "$GATE_STATE" true \
               "class is $GATE_CLASS, not missing — this issue already carries a closing-summary marker" 1 ;;
  esac
fi

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
  echo "PRESENT (unverified) — nothing was established here. Either a closing-summary heading exists but no comment leads with one (real summary or quotation: not determined), or the comment set could not be read in full. Inspect by hand; do NOT run --retroactive on the strength of this line:"
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
