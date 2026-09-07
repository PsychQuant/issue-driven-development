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
#   `### Blocking` section in this repo's issue bodies (55; 54 of them CLOSED
#   issues the gate never evaluates — signal 3's live effect on 2026-09-07 was
#   one issue, #316 itself). The reader agrees with the hand review on 54/55;
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
#   - the section ends at the next heading of the same or higher level;
#     a deeper `####` line is skipped, never taken as a value
_idd_section_lines() {
    local body="${1-}" heading="${2-}" nfence nofence=0
    # An UNCLOSED fence would otherwise swallow every later section (live
    # instance #290: one ``` at line 8, `### Blocking` at line 39 → empty →
    # a real blocker below it would read as "no blocker"). Fence tracking is
    # only trustworthy when fences are balanced; with an odd count it is
    # disabled for that body. A balanced fenced template example is still
    # skipped (verify #318 H4).
    nfence=$(printf '%s\n' "$body" | grep -cE '^[[:space:]]*(```|~~~)' || true)
    [ $((nfence % 2)) -eq 1 ] && nofence=1
    printf '%s\n' "$body" | awk -v h="$heading" -v nofence="$nofence" '
        { sub(/\r$/, "") }
        nofence == 1 { }
        nofence == 0 {
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

# Third-party text leaves this file with C0 control characters (and DEL)
# removed — TAB and LF kept — so a `\r` or an ANSI sequence inside an issue
# body cannot repaint the operator's terminal or the executing model's prompt.
# Surfaced values are DATA, never instructions.
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
idd_actionability_verdict() {
    local cexit="" label="" blocking=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --complexity-exit|--parking-label|--blocking-section)
                # A value-less flag must be a named error, not an infinite loop
                # (verify #318 H1: `shift 2` on a single remaining arg fails
                # without shifting, so the loop never advanced).
                if [ $# -lt 2 ]; then
                    printf 'idd_actionability_verdict: %s requires a value\n' "$1" >&2
                    return 2
                fi
                case "$1" in
                    --complexity-exit)  cexit="$2"    ;;
                    --parking-label)    label="$2"    ;;
                    --blocking-section) blocking="$2" ;;
                esac
                shift 2
                ;;
            *)
                printf 'idd_actionability_verdict: unknown argument: %s\n' "$1" >&2
                return 2
                ;;
        esac
    done

    # Fail loud on missing or malformed input. A gate that silently treats an
    # unanswered signal as "clear" would re-open the exact hole #298 closed —
    # this is the Lazy Developer lens: the cheap path must not be the unsafe one.
    case "$cexit" in
        0|3|4|5) ;;
        *) printf 'idd_actionability_verdict: --complexity-exit must be 0, 3, 4 or 5 (got: %s)\n' "${cexit:-<empty>}" >&2; return 2 ;;
    esac
    case "$label" in
        yes|no) ;;
        *) printf 'idd_actionability_verdict: --parking-label must be yes or no (got: %s)\n' "${label:-<empty>}" >&2; return 2 ;;
    esac
    case "$blocking" in
        yes|no) ;;
        *) printf 'idd_actionability_verdict: --blocking-section must be yes or no (got: %s)\n' "${blocking:-<empty>}" >&2; return 2 ;;
    esac

    local reasons=()
    [ "$cexit" = "3" ]      && reasons+=("complexity-unparseable")
    [ "$cexit" = "4" ]      && reasons+=("complexity-missing")
    [ "$cexit" = "5" ]      && reasons+=("complexity-deferral-marker")
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
# style is "placeholder + annotation": of the 55 `### Blocking` sections in
# this repo, 48 are semantically empty and 31 of those carry text after the
# token (`- (none — 可動)`, `- (none) — closed`, `（無）`). Round 2 anchored the
# match to the whole line and withheld all 31 — including #316 itself. The rule
# below agrees with the hand review on 54 of the 55 rows frozen in
# scripts/tests/actionability-gate/fixtures/corpus-blocking.json; two other
# candidate rules were tested there and rejected (one cleared every real
# blocker, one left 20 false positives).
#
# Recognised token, any case, optionally bulleted / decorated / parenthesised:
#   none · n/a · 無     followed by end of line, a closing paren, a full stop,
#   or a separator (— – - , 、 : ： ;). A bare bullet or bare decoration is
#   also empty.
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
# The live corpus has zero cases of either shape. Widening the bullet class
# was measured and rejected in verify #318 round 3 — it enlarges the
# fail-closed side, and whether this field should be regex-read at all is
# #336. Do not extend this by analogy; change #336 first.
#
# Multibyte characters are written as alternations, never inside a bracket
# expression: under LC_ALL=C a bracket splits into bytes and `— – 、 ：`
# turned every kana / CJK-punctuation lead byte into a separator (both
# directions flipped; the suite itself failed 3 assertions). The rule below is
# locale-independent and the test runs it under LC_ALL=C.
#
# Rejected candidate rules (measured on the same 55 rows; kept so nobody
# re-derives them):
#   '^[[:space:]]*([-*][[:space:]]+)?[_*`（(]*[[:space:]]*(none|n/a|無|-)([^[:alnum:]]|$)'
#       → 0 FP but 7 FN: the optional bullet group lets `-` in the token set
#         eat the bullet dash, so every `- 等 …` bullet read as empty.
#   '^[[:space:]]*([-*][[:space:]]+)?[_*`]*[(（]?[[:space:]]*(none|n/a|無)[[:space:]]*([)）]|$)'
#       → 20 FP: requires `)` or EOL right after the token, so `- (none — 可動)`
#         (#316 itself) still read as a blocker.
_idd_is_none_placeholder() { # line
    printf '%s\n' "$1" | grep -qiE '^[[:space:]]*([-*][[:space:]]+)?[_*`]*(（|\()?[[:space:]]*[_*`]*(none|n/a|無)[_*`]*[[:space:]]*(\)|）|$|\.|。|[,:;-]|—|–|、|：)' \
    || printf '%s\n' "$1" | grep -qE '^[[:space:]]*[-*]?[_*`]*[[:space:]]*$'
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
#                 (11 of 14 open issues on 2026-09-07), and filing it under
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
           printf 'idd_actionability_group: empty or unknown reason list (got: %s)\n' "${reasons:-<empty>}" >&2; return 2 ;;
    esac
}
