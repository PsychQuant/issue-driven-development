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
#   - where this line-based reader DEPARTS from CommonMark — the list is
#     known, not exhaustive: a line reader is not a CommonMark parser, and
#     more shapes may exist. Each shape below was measured against markdown_it and is
#     pinned by test as a DOCUMENTED DIVERGENCE. Measured basis: on the live
#     snapshot (243 bodies + 164 Diagnosis comments, 2026-09-08) the reader
#     and markdown_it agree on section presence, content and verdict for all
#     217 sections; none of these shapes occurs there.
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
#     An issue author who can write any of these can also delete the real
#     blocker outright, so this list is an honesty statement, not a security
#     boundary. Converging a shape on the markdown_it render is ALLOWED by the
#     change gate below and flips its pin in the same commit; whether this
#     field should be regex-read at all is #336.
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
# function. Every message this file writes that carries an input value passes
# through it (the raw lines, the surfaced bullet, every misuse message — each
# pinned by test); the other outputs are fixed vocabulary.
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
                    printf 'idd_actionability_verdict: %s requires a value\n' "$1" | _idd_scrub >&2
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
# CHANGE GATE (round 6; normative text in spec R9) — keyed on a DIRECTION and
# an EXTERNAL ORACLE, not on the corpus alone, because the corpus samples how
# the producer writes and never contains an adversarial or edge shape:
#   (i)  VOCABULARY rules (placeholder tokens and terminators, deferral
#        vocabulary) may only move toward WITHHOLDING. A change in the other
#        direction must flip a measured corpus row, named in the commit, or be
#        a revert.
#   (ii) STRUCTURAL rules (heading, fence, bullet, section boundaries) may only
#        move toward the markdown_it render — a documented-divergence pin they
#        flip must flip to markdown_it's result — AND may not move anything
#        toward clearing on the frozen corpus, the live snapshot or a
#        direction pin. Where convergence and withholding conflict,
#        withholding wins and the case goes to #336.
# Round 4's widenings fail (i) (they cleared real blockers) and round 5's
# third form ("removes an environment dependence") would have admitted the two
# fail-opens recorded under Locale below — it is withdrawn. The bullet
# detector is where (ii)'s two halves conflict: under C it agrees with
# CommonMark (`-<NBSP>` is not a list marker there either) and still loses a
# blocker, so it is refused.
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
# The other matchers — the bullet detector in idd_blocking_section, the
# deferral grep in idd_parse_complexity, and the awk section extractor — DO
# follow the environment. Measured directions (round 6, against markdown_it):
#   - deferral grep: pinning it to C makes `Plan when<NBSP>triggered` routable
#     (#298's incident) — refused by (i), and by a direction pin;
#   - bullet detector: pinning it to C makes `- (none)` + `-<NBSP>等 #99 merge`
#     lose its blocker — refused by (ii), and by a direction pin;
#   - awk extractor: pinning it to C CONVERGES on CommonMark in both measured
#     NBSP shapes — an NBSP-indented ``` stops opening a fence (fixing a
#     fail-open) and `###<NBSP>Blocking` stops being a heading (dropping a
#     fail-closed read GitHub does not render) — and changes nothing on the
#     live snapshot (bash under C and under UTF-8 agree on all 440 documents
#     of 2026-10-06). The gate admits it; round 6 does not make it (reader
#     semantics frozen this round).
# The verify's own prescription grouped the awk with the two fail-opens; the
# mutation test showed it is not one. Which environment is canonical per
# construct is #336.
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
