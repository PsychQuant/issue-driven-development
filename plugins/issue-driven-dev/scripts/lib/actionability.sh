#!/usr/bin/env bash
# actionability.sh — the single shared implementation of "can this issue be
# worked on right now?" (PsychQuant/issue-driven-development#298 → #316)
#
# Source this from a skill or test runner:
#   . "$CLAUDE_PLUGIN_ROOT/scripts/lib/actionability.sh" \
#     || { echo "FATAL: missing $CLAUDE_PLUGIN_ROOT/scripts/lib/actionability.sh" >&2; exit 1; }
#
# WHY THIS FILE EXISTS
# Before #298 there were three private narrowings of the `### Complexity` field
# and they disagreed. idd-list truncated `Simple when triggered` to `Simple` and
# routed a parked issue to /idd-implement; idd-all and idd-implement produced a
# non-tier string that matched no dispatch row and was not `UNKNOWN` either, so
# the existing abort net could not catch it. One implementation, four consumers,
# no private parsing — that is the whole point of this file. Do not re-inline a
# regex in a SKILL.md; extend here instead.
#
# THE RULE (round 2, validated on all 159 real diagnoses in this repo: 159/159
# as hand-reviewed — 149 routable, 9 deferral, 1 correctly reported missing;
# 0 false positives — see /idd-diagnose #316 and the frozen corpus fixture)
#   1. strip leading/trailing markdown decoration (`**`, `` ` ``, `_`)
#   2. the value must BEGIN WITH one of  Simple | Plan | Spectra | SDD-warranted
#      (whole word; longest match first). That leading word IS the tier.
#      Everything after it — same-line rationale, a parenthetical, an em-dash
#      note, a ` via <source>` provenance suffix — is legal and ignored for
#      tier extraction. 93% of the corpus writes the tier this way; a closed
#      value domain (round 1, PR #318) would have rejected 42% of it.
#   3. scan the ENTIRE value (not just the part after the tier) for deferral
#      vocabulary:  when triggered | parking lot | deferred | 暫緩
#      (case-insensitive; hyphen/underscore/space tolerant). A hit withholds
#      the issue under its own reason, because a deferral is a legitimate
#      state — not a data defect to repair.
#
# WHAT THE FROZEN BLOCKING CORPUS DOES AND DOES NOT PROVE (verify #318 round 3)
#   scripts/tests/actionability-gate/fixtures/corpus-blocking.json holds every
#   `### Blocking` section in this repo's issue bodies — 55 rows, 54 sections
#   under CommonMark (#290's heading sits below an unclosed fence); 54 rows are
#   CLOSED issues the gate never evaluates — signal 3's live effect on
#   2026-09-07 was one issue, #316 itself. The reader agrees with the hand
#   review on 54/55 rows;
#   row #1 is an accepted false positive (an informational second bullet). Each
#   row now carries the original body, so the shared extractor — fences,
#   headings, CR — is exercised by the corpus, not bypassed by a synthesised
#   body. The corpus is a legitimate sample of producer style; it is NOT proof
#   of gate correctness on the live backlog.
#
# RISK POSTURE
#   The `parking-lot` label is the PRIMARY parked signal (human-authored,
#   mutable, removable). Deferral vocabulary is a SECONDARY high-precision net:
#   a miss falls back to pre-#298 behaviour, a false positive is a hard stop —
#   so the vocabulary stays conservative. It is a heuristic, NOT a closed
#   enumeration; do not "complete" it by analogy.
#
# REASON VOCABULARY (this one IS closed — five values)
#   complexity-unparseable | complexity-missing | complexity-deferral-marker
#   parking-lot-label      | blocking-nonempty

# ── section extraction (shared by both readers below) ────────────────────────
#
# _idd_section_lines <body> <heading-text>
#   stdout : every non-blank, non-subheading line under `### <heading-text>`,
#            in order; empty when the section is absent or empty
# _idd_section_first_line <body> <heading-text>
#   stdout : the first of those lines (the scalar-field reader)
#
#   - a trailing CR is stripped first: GitHub's web textarea submits CRLF, and
#     awk's default FS does not treat `\r` as blank, so a CRLF "empty line" has
#     NF=1 and would be taken as the value (verify #318 round-2 HIGH)
#   - heading anchored at line start, so prose mentioning "### Complexity"
#     cannot match
#   - ``` and ~~~ fences are tracked: a template example quoted inside a
#     fence is not a section (verify #318 H4)
#   - fences follow the two CommonMark rules that decide what GitHub shows:
#     a fence runs until its own closer, and an UNCLOSED fence runs to the end
#     of the body — everything below it is code, not a section. That is a producer
#     defect in the body (live instance #290: one ``` at line 8; GitHub shows
#     its `### Blocking` as code, and so does this reader), to be detected and
#     surfaced — tracked in #336 — never patched around here. Round 4 tried
#     "odd marker count → stop tracking fences for this body": it did not
#     change #290's gate verdict, it exposed FENCED TEMPLATES as real sections
#     (a closed ``` block containing a `~~~` line; a fenced example followed
#     by one stray opener), and the state-machine variant ("stop tracking if
#     still open at EOF") failed the same shape. Any "detect imbalance → stop
#     tracking" rule is a one-key switch. Do not reintroduce one.
#   - where this line-based reader DEPARTS from markdown-it or CommonMark —
#     the list is known, not exhaustive: a line reader is not a parser, and
#     more shapes may exist. Each shape below was measured against
#     markdown-it-py 4.0.0 and (round 7) pandoc 3.10's CommonMark reader, and
#     is pinned by test as a DOCUMENTED DIVERGENCE. The two oracles are not the
#     same: markdown-it strips NBSP / U+3000 from heading text, CommonMark
#     strips only spaces and tabs (D10). Measured basis: on the snapshot of
#     2026-09-08 (243 bodies + 164 Diagnosis comments) the reader and
#     markdown-it agree on section presence, content and verdict for all 217
#     sections; none of D1–D7 occurs there, and no body of the 2026-10-06
#     snapshot (273) contains NBSP or U+3000.
#       D1 fence length is not compared — a ```` opener is closed by the first
#          ``` line, so a nested example is read as outside (either direction)
#       D2 indentation is not checked — a ``` indented 4+ spaces or by a tab
#          is indented code in CommonMark but opens a fence here; left open it
#          hides the real section below (fail-open)
#       D3 a ``` line with trailing text closes a fence here; CommonMark does
#          not count it as a closer (either direction)
#       D4 an opener whose info string contains a backtick (a paragraph line
#          that starts with an inline span written with three backticks) is
#          not a fence in CommonMark but opens one here that never closes
#          (fail-open)
#       D5 a closer indented 4+ spaces inside a fence closes it here; in
#          CommonMark it is content and the fence continues (either direction)
#       D6 a fence opened on a list-item line (`- ```…`) is not seen here; its
#          indented closer is then taken as an opener that runs to the end of
#          the body (fail-open). A fence inside a blockquote is NOT a
#          divergence: neither side reads its contents.
#       D7 an HTML comment holding a fake `### Blocking` is hidden by GitHub
#          but read here — the first matching heading wins (either direction)
#     Round 7, measured under C.UTF-8 on macOS. The awk follows the locale AND
#     the platform: on glibc + gawk (Ubuntu 24.04) NBSP is not blank, so the
#     NBSP shapes behave as under C, and `### Blocking<U+3000>` is read. The
#     D8–D10 pins take their expected value from the platform awk:
#       D8 an NBSP-indented ``` opens a fence here; both oracles read paragraph
#          text, so the section below is hidden (fail-open)
#       D9 `###<NBSP>X` / `##<NBSP>X` count as headings here; neither oracle
#          treats them as headings — `###<NBSP>Blocking` is read as the section
#          (either direction), `##<NBSP>Next` ends it early (fail-open)
#       D10 trailing NBSP / U+3000 after the heading text: `### Blocking<NBSP>`
#          is read (markdown-it agrees, CommonMark does not), `### Blocking
#          <U+3000>` is not (CommonMark agrees, markdown-it does not)
#       D11 an ATX heading indented 1–3 spaces is not read; both oracles read
#          it (fail-open)
#       D12 an ATX heading with a closing sequence (`### Blocking ###`) is not
#          read; both oracles read it (fail-open)
#     Anyone who can edit the body can also delete a blocker outright, so for
#     text the author wrote this list is an honesty statement. Third-party text
#     copied INTO a body (idd-issue --from-discussion) is held back only by its
#     per-line `>` quoting, a prose rule today — #372. Changing any of these
#     shapes is a structural change: frozen until a requirement names its
#     oracle (spec R9; #336).
#   - the section ends at the next heading of the same or higher level;
#     a deeper `####` line is skipped, never taken as a value
_idd_section_lines() {
    local body="${1-}" heading="${2-}"
    printf '%s\n' "$body" | awk -v h="$heading" '
        { sub(/\r$/, "") }
        {
            if (fence != "") {
                if (fence == "`" && $0 ~ /^[[:space:]]*```/) fence = ""
                else if (fence == "~" && $0 ~ /^[[:space:]]*~~~/) fence = ""
                next
            }
            if ($0 ~ /^[[:space:]]*```/) { fence = "`"; next }
            if ($0 ~ /^[[:space:]]*~~~/) { fence = "~"; next }
        }
        !grab && $0 ~ ("^###[[:space:]]+" h "[[:space:]]*$") { grab = 1; next }
        grab && /^(#|##|###)[[:space:]]/                    { exit }
        grab && /^####/                                     { next }
        grab && NF                                          { print }
    '
}
_idd_section_first_line() {
    # No `| head -n 1`: closing the pipe early makes the upstream awk exit 141
    # under `pipefail`. Capture, then take the first line.
    local all
    all=$(_idd_section_lines "$1" "$2")
    printf '%s\n' "${all%%$'\n'*}"
}

# Third-party text leaves this file with C0 control characters (0x00–0x1F
# except TAB and LF) and DEL removed — that is ALL this layer does. It stops a
# `\r` or a 7-bit ANSI escape from repainting the operator's terminal. It does
# NOT touch bidi overrides (U+202E), zero-width characters, U+2028, or 8-bit
# C1 controls, and it cannot do anything about prose that reads like an
# instruction: surfaced values are DATA, never instructions, and that boundary
# is the consumer's delimiter (see the canonical gate print), not this
# function. What passes through it: the two raw lines idd_parse_complexity
# surfaces, the bullet idd_blocking_section surfaces, and the eight misuse
# messages that echo an argument value (six in the verdict, one in the group
# helper, one in idd_issue_type — #383 added --issue-type, --diagnosis-present
# and that helper) —
# each pinned by test. The "requires a value" messages of the verdict and of
# idd_issue_type echo only a flag name already matched by `case`; the private
# `_idd_section_*` readers return raw text to the functions above and no
# consumer calls them. Everything else this file prints is fixed vocabulary.
_idd_scrub() {
    LC_ALL=C tr -d '\000-\010\013-\037\177'
}

# ── contract 1: parse the Complexity field ───────────────────────────────────
#
# idd_parse_complexity <diagnosis-comment-body>
#   stdout : the leading tier — only on exit 0
#   exit 0 : routable
#   exit 3 : section present, value does not begin with a tier
#            → stderr: "unparseable-complexity: <raw value>"
#   exit 4 : no `### Complexity` section at all
#            → stderr: "missing-complexity"
#   exit 5 : tier is well-formed but deferral vocabulary is present
#            → stderr: "deferral-marker: <raw value>"
#
# On every non-zero path NOTHING is written to stdout — a consumer that
# captured a tier there could route on it, which is exactly the incident.
# The raw (undecorated) line is surfaced on 3 and 5 so the operator sees what
# the artifact actually says.
#
# Callers under `set -e` MUST use the conditional-capture shape:
#   if TIER=$(idd_parse_complexity "$BODY" 2>"$err"); then CEXIT=0; else CEXIT=$?; fi
idd_parse_complexity() {
    local body="${1-}"
    local raw

    raw=$(_idd_section_first_line "$body" Complexity)

    if [ -z "$raw" ]; then
        printf 'missing-complexity\n' >&2
        return 4
    fi

    # Strip markdown bold/italic/code decoration around the value. Diagnoses in
    # the wild write `**Spectra**`; the decoration is presentation, not value.
    local val="$raw"
    val="${val#"${val%%[![:space:]]*}"}"        # ltrim
    val="${val%"${val##*[![:space:]]}"}"        # rtrim
    val="$(printf '%s' "$val" | sed -E 's/^[*`_]+//; s/[*`_]+$//')"
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"

    # Tier = leading whole word. Longest first so `SDD-warranted` is tried before
    # anything that could be its prefix; the boundary class keeps `Simpler`
    # from reading as `Simple` while letting `Spectra（…）` / `Plan — …` /
    # `Spectra**(…)` / `Plan via …` all through.
    local tier="" t
    for t in SDD-warranted Spectra Simple Plan; do
        case "$val" in
            "$t"|"$t"[!A-Za-z0-9]*) tier="$t"; break ;;
        esac
    done

    if [ -z "$tier" ]; then
        printf 'unparseable-complexity: %s\n' "$raw" | _idd_scrub >&2
        return 3
    fi

    # Deferral vocabulary anywhere in the value — including inside a
    # parenthetical or after a ` via ` suffix (verify #318 H3). Conservative on
    # purpose: see RISK POSTURE above before adding a term.
    if printf '%s\n' "$val" | grep -qiE 'when[[:space:]_-]+triggered|parking[[:space:]_-]*lot|deferred|暫緩'; then
        printf 'deferral-marker: %s\n' "$raw" | _idd_scrub >&2
        return 5
    fi

    printf '%s\n' "$tier"
    return 0
}

# ── contract 2: the three-signal gate ────────────────────────────────────────
#
# idd_actionability_verdict --complexity-exit N --parking-label yes|no --blocking-section yes|no
#                           [--issue-type bug|feature|refactor|docs|meeting|unknown]
#                           [--diagnosis-present yes|no]   (required with --issue-type meeting)
#   stdout : "actionable"
#            "not-actionable: <reason>[; <reason>...]"
#   exit 0 : actionable      exit 1 : not actionable      exit 2 : bad usage
#
# Pass requires ALL THREE signals clear. The `- [~]` Strategy skip marker is NOT
# an input: it is a close-time per-item disposition owned by idd-close, and
# reusing it here would answer a different question than the one being asked.
#
# Exit 2 is API misuse and MUST NOT be conflated with "not actionable" by a
# consumer — it means the consumer fed the gate garbage, not that the issue is
# parked.
#
# --issue-type (#383, optional; resolve it with idd_issue_type): when it is
# `meeting`, the Complexity signal contributes NO reason — the meeting type
# deliberately writes no tier (#57), so unparseable / missing / deferral there
# says nothing about whether the issue can move. --complexity-exit is still
# required and still validated, and parking-lot and ### Blocking are evaluated
# as usual: parking a meeting is the label's job. Omitted, or any other type,
# and the verdict is exactly what it was before this flag existed. Passed but
# empty is misuse (exit 2) — a consumer whose type lookup came back empty must
# not be read as "no type given".
#
# --diagnosis-present (#383 verify r1): exit 4 means two things — a Diagnosis
# with no ### Complexity section, and NO trusted Diagnosis comment at all
# (LATEST_DIAGNOSIS empty after the author filter). Only the second is "never
# diagnosed", and only the consumer can tell them apart. So the meeting
# exemption applies only when the consumer says a Diagnosis exists; with `no`
# the Complexity reasons are evaluated exactly as for any other type, and an
# undiagnosed meeting stays complexity-missing → the undiagnosed group. It is
# REQUIRED with --issue-type meeting (exit 2 if absent): defaulting it to
# `yes` would re-open the hole, defaulting to `no` would silently undo the
# exemption. For any other type it is validated and has no effect.
idd_actionability_verdict() {
    local cexit="" label="" blocking="" itype="" itype_set=0 dpres="" dpres_set=0

    while [ $# -gt 0 ]; do
        case "$1" in
            --complexity-exit|--parking-label|--blocking-section|--issue-type|--diagnosis-present)
                # A value-less flag must be a named error, not an infinite loop
                # (verify #318 H1: `shift 2` on a single remaining arg fails
                # without shifting, so the loop never advanced).
                if [ $# -lt 2 ]; then
                    printf 'idd_actionability_verdict: %s requires a value\n' "$1" | _idd_scrub >&2
                    return 2
                fi
                case "$1" in
                    --complexity-exit)  cexit="$2"    ;;
                    --parking-label)    label="$2"    ;;
                    --blocking-section) blocking="$2" ;;
                    --issue-type)       itype="$2"; itype_set=1 ;;
                    --diagnosis-present) dpres="$2"; dpres_set=1 ;;
                esac
                shift 2
                ;;
            *)
                printf 'idd_actionability_verdict: unknown argument: %s\n' "$1" | _idd_scrub >&2
                return 2
                ;;
        esac
    done

    # Fail loud on missing or malformed input. A gate that silently treats an
    # unanswered signal as "clear" would re-open the exact hole #298 closed —
    # this is the Lazy Developer lens: the cheap path must not be the unsafe one.
    case "$cexit" in
        0|3|4|5) ;;
        *) printf 'idd_actionability_verdict: --complexity-exit must be 0, 3, 4 or 5 (got: %s)\n' "${cexit:-<empty>}" | _idd_scrub >&2; return 2 ;;
    esac
    case "$label" in
        yes|no) ;;
        *) printf 'idd_actionability_verdict: --parking-label must be yes or no (got: %s)\n' "${label:-<empty>}" | _idd_scrub >&2; return 2 ;;
    esac
    case "$blocking" in
        yes|no) ;;
        *) printf 'idd_actionability_verdict: --blocking-section must be yes or no (got: %s)\n' "${blocking:-<empty>}" | _idd_scrub >&2; return 2 ;;
    esac
    if [ "$itype_set" -eq 1 ]; then
        case "$itype" in
            bug|feature|refactor|docs|meeting|unknown) ;;
            *) printf 'idd_actionability_verdict: --issue-type must be bug, feature, refactor, docs, meeting or unknown (got: %s)\n' "${itype:-<empty>}" | _idd_scrub >&2; return 2 ;;
        esac
    fi
    if [ "$dpres_set" -eq 1 ]; then
        case "$dpres" in
            yes|no) ;;
            *) printf 'idd_actionability_verdict: --diagnosis-present must be yes or no (got: %s)\n' "${dpres:-<empty>}" | _idd_scrub >&2; return 2 ;;
        esac
    elif [ "$itype" = "meeting" ]; then
        printf 'idd_actionability_verdict: --issue-type meeting requires --diagnosis-present yes|no\n' | _idd_scrub >&2
        return 2
    fi

    local reasons=()
    if [ "$itype" != "meeting" ] || [ "$dpres" != "yes" ]; then
        [ "$cexit" = "3" ]  && reasons+=("complexity-unparseable")
        [ "$cexit" = "4" ]  && reasons+=("complexity-missing")
        [ "$cexit" = "5" ]  && reasons+=("complexity-deferral-marker")
    fi
    [ "$label" = "yes" ]    && reasons+=("parking-lot-label")
    [ "$blocking" = "yes" ] && reasons+=("blocking-nonempty")

    if [ ${#reasons[@]} -eq 0 ]; then
        printf 'actionable\n'
        return 0
    fi

    local joined
    joined=$(printf '%s; ' "${reasons[@]}")
    printf 'not-actionable: %s\n' "${joined%; }"
    return 1
}

# ── contract 3: the third signal — `### Blocking` in the issue body ──────────
#
# idd_blocking_section <issue-body>
#   stdout : the first line of the `### Blocking` section that states a real
#            blocker; empty when the section is absent or every bullet is a
#            none-placeholder
#   exit 0 : always
#
# `### Blocking` is a LIST field (idd-update's template is a bullet list), so
# unlike `### Complexity` it is read per bullet: any bullet that is not a
# placeholder makes the section non-empty. Round 2 read only the first line —
# `- (none)` followed by a real `- 等 …` bullet came back empty (verify #318
# round-2, logic HIGH-1). Lines that do not start a bullet are continuations
# of the bullet above and are not judged on their own.
#
# A placeholder is judged on its LEADING TOKEN, because the producer's real
# style is "placeholder + annotation" (`- (none — 可動)`, `- (none) — closed`):
# of the 55 rows frozen in scripts/tests/actionability-gate/fixtures/
# corpus-blocking.json (54 sections under CommonMark), 48 are semantically
# empty, and round 2 — which anchored the match to the whole line — withheld
# 30 of them when it read the original bodies, #316 itself among them. The rule
# below agrees with the hand review on 54 of the 55 rows; two other candidate
# rules were tested there and rejected (one cleared every real blocker, one
# left 21 false positives). Counts measured under a UTF-8 locale.
#
# Recognised token, any case, optionally bulleted / decorated / parenthesised:
#   none · n/a · 無     followed by end of line, a closing paren, or a
#   separator (— – - , 、 : ： ;). A bare bullet or bare decoration is also
#   empty. A full stop is NOT a terminator: round 4 added `.` / `。` with no
#   corpus need (0/55 rows) and `- None. Waiting on X` / `- 無。等 #99 merge`
#   read as "no blocker" — the fail-open direction; round 5 reverted it. The
#   bare `- None.` therefore reads as a blocker (fail-closed, visible; the
#   corpus has no such row).
#
# THE RULE FOR MISSES, stated as a rule (not as examples — see
# common-spec-prose-enumeration): the leading token decides the bullet. Both
# directions follow from that and are accepted, documented, and pinned by test:
#   fail-open  : a placeholder token followed by a clause (`- (none) but
#                actually blocked by #86`, `- n/a — blocked by #99`) reads as
#                EMPTY; a real blocker written as an ordered-list item, a `+`
#                bullet, a blockquote, a table row, a `####` line or a bare
#                paragraph AFTER a placeholder bullet is a continuation and is
#                NOT read (only `-` / `*` bullets, or the section's first
#                line, are judged);
#   fail-closed: a lead-in sentence before the first bullet (`目前阻塞如下：`
#                then `- (none)`) is judged as the first line and reads as a
#                BLOCKER.
# The live corpus has zero cases of either shape. The bullet class is NOT
# widened (`- * +`, `1.`, `1)`): the corpus is insensitive to it (0/55 rows
# change, measured in verify #318 round 4), so the choice is a design judgment,
# not a measured result — it is left narrow because widening enlarges the
# fail-closed side, and whether this field should be regex-read at all is
# #336. Do not extend this by analogy; change #336 first.
#
# CHANGE GATE (round 7) — the normative text is spec R9 (openspec/changes/
# add-actionability-gate/specs/actionability-gate/spec.md); in one line each:
#   (i)  VOCABULARY rules (placeholder tokens and terminators, deferral
#        vocabulary, and the locale of the greps that apply them) move only
#        toward WITHHOLDING, unless the change is a revert or every element it
#        adds is required by a measured corpus row named in the commit;
#   (ii) STRUCTURAL rules (heading, fence, bullet and section boundaries, the
#        Complexity trim, and the locale of the matchers that implement them)
#        are FROZEN until a requirement names the oracle they converge on and
#        the measured shapes they change (#336).
# Round 6 tried a property here ("toward the markdown_it render, never toward
# clearing on the corpus, the live snapshot or a direction pin"); the round-6
# verify showed it gives no determinate answer, so it is withdrawn.
#
# Locale: multibyte characters are written as alternations, never inside a
# bracket expression (under LC_ALL=C a bracket splits into bytes and `— – 、 ：`
# turned every kana / CJK-punctuation lead byte into a separator — both
# directions flipped and the suite itself failed 3 assertions). That fixed the
# members but not the classes: `[[:space:]]` counts U+3000 / NBSP as blank in
# a UTF-8 locale and not in C, so `- none　` was empty under one and a blocker
# under the other. The two placeholder greps below therefore run as
# `LC_ALL=C command grep`: C, the same choice `_idd_scrub` makes, and `command`
# because production is not BSD grep — skills `.`-source this file in Claude
# Code's zsh, whose shell snapshot defines `grep` as a ugrep function that
# ignores LC_ALL. Consequence, pinned by VALUE in both locales and under a
# shadowing grep function: `- none　` reads as a blocker (withholding side; the
# corpus has no such row). That is the whole locale claim: the PLACEHOLDER rule
# does not depend on the environment.
# The known environment dependences of the other matchers — known, not
# exhaustive — measured in round 7 on macOS (bash under C.UTF-8 and C, the
# production zsh) and on Ubuntu 24.04 (GNU grep 3.11, gawk, mawk). The platform
# matters as much as the locale: macOS's C library classifies NBSP as blank
# under a UTF-8 locale and glibc does not; U+3000 is blank to grep on both, to
# gawk, and not to macOS's awk or mawk. With what a C-locale pin would do:
#   - deferral grep: `Simple when<U+3000>triggered` is withheld under UTF-8 on
#     both platforms and routable under C; `Plan when<NBSP>triggered` is
#     withheld only on macOS under UTF-8 — on Linux it routes in any locale. A
#     C pin makes both routable everywhere measured (#298's incident) — refused
#     by (i), and by the U+3000 direction pin in the test;
#   - bullet detector: `- (none)` + `-<U+3000>等 #99 merge` is a blocker under
#     UTF-8 on both platforms and empty under C; with NBSP instead, a blocker
#     only on macOS under UTF-8. A C pin loses both — a structural change,
#     frozen by (ii), and caught by the U+3000 direction pin;
#   - awk section extractor: MIXED on macOS. A C pin moves D8 and `##<NBSP>Next`
#     (D9) toward withholding and toward both oracles; moves `###<NBSP>Blocking`
#     (D9), an NBSP-indented closer inside a fence, and an NBSP-led line that
#     leaves a fence unclosed toward clearing, also toward both oracles; and on
#     `### Blocking<NBSP>` (D10) it clears a blocker that markdown-it reads
#     and CommonMark does not. Round 6 judged this pin harmless from two
#     shapes; that was wrong. On glibc + gawk the NBSP shapes already take the
#     C path and a C pin instead stops reading `### Blocking<U+3000>`. Frozen by
#     (ii); the D8–D10 pins, keyed on the platform awk, catch it;
#   - Complexity trim (the `[![:space:]]` parameter expansions):
#     `<NBSP>Plan` routes as Plan on macOS under UTF-8 and is unparseable
#     (exit 3) under C and on Linux; `### Complexity<NBSP>` is a section on
#     macOS under UTF-8 and missing (exit 4) otherwise. Recorded per platform.
# Which environment, and which oracle, is canonical per construct is #336.
#
# Rejected candidate rules (measured on the same 55 rows against the SEMANTIC
# hand review — 48 empty / 7 real blockers; kept so nobody re-derives them):
#   '^[[:space:]]*([-*][[:space:]]+)?[_*`（(]*[[:space:]]*(none|n/a|無|-)([^[:alnum:]]|$)'
#       → 0 FP but 7 FN: the optional bullet group lets `-` in the token set
#         eat the bullet dash, so every `- 等 …` bullet read as empty.
#   '^[[:space:]]*([-*][[:space:]]+)?[_*`]*[(（]?[[:space:]]*(none|n/a|無)[[:space:]]*([)）]|$)'
#       → 21 FP, 0 FN: requires `)` or EOL right after the token, so
#         `- (none — 可動)` (#316 itself) still read as a blocker. (Against the
#         fixture's rule-oriented `expect_empty` — 47 / 8 — it is 20 FP; the
#         one-row difference is row #1, the accepted false positive.)
_idd_is_none_placeholder() { # line
    printf '%s\n' "$1" | LC_ALL=C command grep -qiE '^[[:space:]]*([-*][[:space:]]+)?[_*`]*(（|\()?[[:space:]]*[_*`]*(none|n/a|無)[_*`]*[[:space:]]*(\)|）|$|[,:;-]|—|–|、|：)' \
    || printf '%s\n' "$1" | LC_ALL=C command grep -qE '^[[:space:]]*[-*]?[_*`]*[[:space:]]*$'
}
idd_blocking_section() {
    local body="${1-}" line first=1
    while IFS= read -r line; do
        if [ "$first" = 1 ] || printf '%s\n' "$line" | grep -qE '^[[:space:]]*[-*][[:space:]]'; then
            first=0
            if ! _idd_is_none_placeholder "$line"; then
                printf '%s\n' "$line" | _idd_scrub
                return 0
            fi
        fi
    done < <(_idd_section_lines "$body" Blocking)
    return 0
}

# ── display helper: which group does a not-actionable issue belong to? ───────
#
# idd_actionability_group <reason-list>
#   stdout : "blocked" | "parked" | "undiagnosed"      exit 2 : empty/unknown reasons
#
#   parked      — any of parking-lot-label / complexity-deferral-marker /
#                 complexity-unparseable is present (a human parked it, the
#                 diagnosis said so, or the value is a defect to repair)
#   blocked     — otherwise, blocking-nonempty is present (alone, or together
#                 with complexity-missing — spec R6 "Missing diagnosis with a
#                 real blocker is blocked"): the pre-#298 blocked-state grouping
#                 (#84) — heading, banner and footer counts — must not regress
#   undiagnosed — otherwise (complexity-missing alone): the issue has simply
#                 not been diagnosed yet. That is every issue's birth state, not
#                 a parked state — on the live backlog it is the DOMINANT state
#                 (11 of 14 open issues on 2026-09-07, measured before this change
#                 filed its own follow-ups), and filing it under
#                 "Parked" hid `→ /idd-diagnose #N` from the operator (verify
#                 #318 round-2 DA-CRIT-1). The display keeps that command.
idd_actionability_group() {
    local reasons="${1-}"
    case "$reasons" in
        *parking-lot-label*|*complexity-deferral-marker*|*complexity-unparseable*) printf 'parked\n' ;;
        *blocking-nonempty*)                                                        printf 'blocked\n' ;;
        *complexity-missing*)                                                       printf 'undiagnosed\n' ;;
        *) # an empty or unknown reason list is API misuse (called on an
           # actionable issue?) — fail loud like the verdict does, never
           # quietly park a routable issue
           printf 'idd_actionability_group: empty or unknown reason list (got: %s)\n' "${reasons:-<empty>}" | _idd_scrub >&2; return 2 ;;
    esac
}

# ── contract 4: issue type (#383) ────────────────────────────────────────────
#
# idd_issue_type --labels <newline-separated label names> --body <issue body>
#   stdout : bug | feature | refactor | docs | meeting | unknown
#   exit 0 : resolved (`unknown` included)      exit 2 : bad usage
#
# WHY HERE: the gate has to know whether an issue is a meeting, because the
# meeting type (#57) deliberately writes no Complexity tier and every meeting
# Diagnosis would otherwise read unparseable or missing (#383). Resolving the
# type is parsing, so it lives in this file like every other parse — a
# consumer that reads labels or `## Type` on its own is the private-narrowing
# shape #298 → #316 removed.
#
# THE ORDER is /idd-diagnose Step 1's:
#   1. exactly one IDD type name among the labels → that type; more than one
#      distinct IDD type label → `unknown` (a conflict is not a meeting)
#   2. no IDD type label → the leading word of the first non-empty line under a
#      line-anchored `## Type` heading outside fenced code, if it is an IDD
#      type name (`meeting（…）` and `**meeting**` both read as meeting)
#   3. otherwise `unknown`
# `unknown` means "not meeting": the gate then evaluates Complexity exactly as
# it did before the type existed. The default is deliberately NOT meeting —
# reading an ordinary issue as a meeting would skip its Complexity signal.
#
# The `## Type` reader is its own awk on purpose: `_idd_section_lines` reads
# only `###` headings and its structural rules are frozen (spec R9, #336). It
# runs under LC_ALL=C so `[[:space:]]` and the letter class mean ASCII on every
# platform, and it uses no grep, so a body without the heading cannot fail a
# caller running under `pipefail`.
#
# Its unsafe direction is a FALSE meeting (that drops the Complexity signal).
# The baseline is GitHub's renderer (cmark-gfm, checked with `gh api markdown`),
# because that is what a maintainer reads (verify #383 r3). Rules, each pinned
# in test.sh: line endings are CRLF, LF or a lone CR; a fence closes only on the
# opener's character at no less than its length with nothing after it; a
# backtick opener's info string has no backtick; a run indented 4+ spaces is not
# a fence; HTML comments and HTML blocks of types 1, 3, 4, 5 and 6 (GitHub's tag
# list) are skipped; the heading needs a space or tab after `##`; the type word
# ends at a non-word character once closing emphasis is stripped.
#
# BACKSTOP, renderer-independent: a body-derived `meeting` needs exactly one
# `## Type` heading line in the whole body; with two or more the result is
# `unknown`. Three verify rounds kept finding concealment shapes (list-item
# fences, HTML block variants, renderer tag-list drift) and every one put a
# second `## Type` where the reader and GitHub disagree. The backstop never
# upgrades a result, and an issue filed by idd-issue carries a type label,
# which wins over the body.
#
# Known divergences that the backstop does NOT cover — a single `## Type`
# hidden by a construct the reader does not model (a fence nested in a list
# item or block quote that the reader misses, a type-7 HTML block) can still
# read as meeting. Trust in a body-only type is tracked in #385.
idd_issue_type() {
    local labels="" body="" found="" word

    while [ $# -gt 0 ]; do
        case "$1" in
            --labels|--body)
                if [ $# -lt 2 ]; then
                    printf 'idd_issue_type: %s requires a value\n' "$1" | _idd_scrub >&2
                    return 2
                fi
                case "$1" in
                    --labels) labels="$2" ;;
                    --body)   body="$2"   ;;
                esac
                shift 2
                ;;
            *)
                printf 'idd_issue_type: unknown argument: %s\n' "$1" | _idd_scrub >&2
                return 2
                ;;
        esac
    done

    # Labels under LC_ALL=C too (verify #383 r1, findings 17 and 25): ASCII
    # case-folded like the body value, and trimmed of ASCII space/tab ONLY. A
    # locale-aware trim made `meeting<NBSP>` a meeting under en_US.UTF-8 and
    # `unknown` under C — the gate-relaxing signal must not follow the locale.
    found=$(printf '%s\n' "$labels" | LC_ALL=C awk '
        { sub(/\r$/, ""); sub(/^[ \t]+/, ""); sub(/[ \t]+$/, ""); l = tolower($0) }
        l ~ /^(bug|feature|refactor|docs|meeting)$/ && !(l in seen) { seen[l] = 1; n++; last = l }
        END { if (n == 1) print last; else if (n > 1) print "unknown" }
    ')
    if [ -n "$found" ]; then printf '%s\n' "$found"; return 0; fi

    # A lone CR is a line ending in CommonMark: normalise CRLF, then every
    # remaining CR, before the line-based awk (verify #383 r2 #3 — an opener
    # after a lone CR used to be read mid-line and miss its rule).
    word=$(printf '%s\n' "$body" | LC_ALL=C sed 's/\r$//' | LC_ALL=C tr '\r' '\n' | LC_ALL=C awk '
        # fence_run: length of the backtick/tilde run that opens this line as a
        # fence (indent of at most 3 spaces), or 0. No interval expressions —
        # some awks lack them, and a terminator that never matches captures to EOF.
        function fence_run(line, ch,    ind, rest) {
            match(line, /^ */); ind = RLENGTH
            if (ind > 3) return 0
            rest = substr(line, ind + 1)
            if (ch == "`") { if (!match(rest, /^`+/)) return 0 }
            else           { if (!match(rest, /^~+/)) return 0 }
            if (RLENGTH < 3) return 0
            # A backtick fence info string cannot contain a backtick — such a
            # line is a paragraph with a code span, not an opener (r2 #11/#17).
            if (ch == "`" && opener && index(substr(rest, RLENGTH + 1), "`")) return 0
            return RLENGTH
        }
        # html_block: the HTML block type a line opens, or 0. Tag list and end
        # conditions follow GitHub (cmark-gfm), the renderer a maintainer reads
        # — not CommonMark 0.31, which added `search` and is not what GitHub
        # renders (verify #383 r3 #25). 1 pre/script/style/textarea, 3 <?,
        # 4 <!X, 5 <![CDATA[, 6 block tag (until a blank line).
        function html_block(line,    ind, rest, low) {
            match(line, /^ */); ind = RLENGTH
            if (ind > 3) return 0
            rest = substr(line, ind + 1); low = tolower(rest)
            if (low ~ /^<(pre|script|style|textarea)([ \t>]|$)/) return 1
            if (low ~ /^<\?/) return 3
            if (low ~ /^<!\[cdata\[/) return 5
            if (low ~ /^<![a-z]/) return 4
            if (low ~ /^<\/?(address|article|aside|base|basefont|blockquote|body|caption|center|col|colgroup|dd|details|dialog|dir|div|dl|dt|fieldset|figcaption|figure|footer|form|frame|frameset|h1|h2|h3|h4|h5|h6|head|header|hr|html|iframe|legend|li|link|main|menu|menuitem|nav|noframes|ol|optgroup|option|p|param|section|source|summary|table|tbody|td|tfoot|th|thead|title|tr|track|ul)([ \t>]|\/>|$)/) return 6
            return 0
        }
        function html_ends(type, line,    low) {
            low = tolower(line)
            if (type == 1) return low ~ /<\/(pre|script|style|textarea)>/
            if (type == 3) return index(line, "?>") > 0
            if (type == 4) return index(line, ">") > 0
            if (type == 5) return index(line, "]]>") > 0
            return 0
        }
        # Every `## Type` heading line in the body, wherever it sits: the
        # renderer-independent backstop (r3) — see END.
        $0 ~ /^##[ \t]+Type[ \t]*$/ { ntype++ }
        {
            # Inside a fence: only the same character, at no less than the
            # opener length, with nothing but whitespace after it, closes it
            # (verify #383 r1, finding 5 — a ```` block used to close at ```).
            if (fence != "") {
                opener = 0; k = fence_run($0, fence)
                if (k >= flen) {
                    match($0, /^ */); tail = substr($0, RLENGTH + 1 + k)
                    if (tail ~ /^[ \t]*$/) fence = ""
                }
                next
            }
            # HTML blocks are not read (r2 #21, r3 #11/#18/#25).
            if (htmlb == 6) { if ($0 ~ /^[ \t]*$/) htmlb = 0; next }
            if (htmlb)      { if (html_ends(htmlb, $0)) htmlb = 0; next }
            # An HTML comment block is not rendered and not read (findings 21, 24).
            if (incomment) { if (index($0, "-->")) incomment = 0; next }
            if ($0 ~ /^[ \t]*<!--/) {
                rest = substr($0, index($0, "<!--") + 4)
                if (!index(rest, "-->")) incomment = 1
                next
            }
            opener = 1
            k = fence_run($0, "`"); if (k) { fence = "`"; flen = k; next }
            k = fence_run($0, "~"); if (k) { fence = "~"; flen = k; next }
            h = html_block($0)
            if (h == 6) { htmlb = 6; next }
            if (h)      { if (!html_ends(h, $0)) htmlb = h; next }
        }
        # The input is always read to the end (no `exit`): the backstop needs
        # every line, and an early exit would SIGPIPE the upstream sed/tr under
        # a caller running `set -euo pipefail` (r3 #31).
        !grab && !done && $0 ~ /^##[ \t]+Type[ \t]*$/  { grab = 1; next }
        grab && /^##?[ \t]/                             { grab = 0; done = 1; next }
        grab && NF {
            line = $0
            sub(/^[ \t]*[*`_]*/, "", line)
            # The word ends at a non-word character once closing emphasis is
            # stripped: `meeting-notes`, `meeting2`, `meeting_x` are not meeting,
            # `_meeting_` and `**meeting**` are (r2 #26, r3 #12).
            if (match(line, /^[A-Za-z]+/)) {
                w = substr(line, 1, RLENGTH); rest = substr(line, RLENGTH + 1)
                sub(/^[*_`]+/, "", rest)
                if (rest !~ /^[A-Za-z0-9_-]/) word = tolower(w)
            }
            grab = 0; done = 1; next
        }
        # Backstop: a body-derived meeting needs exactly ONE `## Type` heading
        # line. Every concealment shape found across three verify rounds put a
        # second one somewhere the reader and GitHub disagree about; with two or
        # more, meeting becomes unknown (the safe direction). Never upgrades.
        END { if (word == "meeting" && ntype > 1) print "unknown"; else print word }
    ')
    case "$word" in
        bug|feature|refactor|docs|meeting) printf '%s\n' "$word" ;;
        *)                                 printf 'unknown\n' ;;
    esac
    return 0
}
