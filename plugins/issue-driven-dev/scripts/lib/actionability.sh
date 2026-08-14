#!/usr/bin/env bash
# actionability.sh — the single shared implementation of "can this issue be
# worked on right now?" (PsychQuant/issue-driven-development#298)
#
# Source this from a skill or test runner:
#   . "$(dirname "${BASH_SOURCE[0]}")/actionability.sh"
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
# CLOSED DOMAINS (both are closed — do NOT extend by analogy)
#   tier    : Simple | Plan | Spectra | SDD-warranted
#             optionally followed by " via <source>" (provenance suffix, v2.50+)
#   reason  : complexity-unparseable | complexity-missing
#             parking-lot-label | blocking-nonempty
#
# Deferral state does NOT live in the tier field. It lives in the `parking-lot`
# label, because deferral is mutable (a trigger firing should un-park an issue)
# and a Diagnosis comment is append-only. Storing mutable state in an immutable
# artifact is the root cause #298 diagnosed; keeping tier pure is the fix.

# ── contract 1: parse the Complexity field ───────────────────────────────────
#
# idd_parse_complexity <diagnosis-comment-body>
#   stdout : canonical tier, when the value is inside the closed domain
#   exit 0 : in domain
#   exit 3 : section present, value outside the domain
#            → stderr: "unparseable-complexity: <raw value>"
#   exit 4 : no `### Complexity` section at all
#            → stderr: "missing-complexity"
#
# The raw value is ALWAYS surfaced on the exit-3 path. Never truncate a
# non-domain value down to its tier prefix — that silent narrowing is the
# incident this file prevents.
idd_parse_complexity() {
    local body="${1-}"
    local raw

    # First non-blank line under the `### Complexity` heading. Anchored at line
    # start so a mention inside prose ("the ### Complexity field") cannot match.
    raw=$(printf '%s\n' "$body" | awk '
        /^###[[:space:]]+Complexity[[:space:]]*$/ { grab = 1; next }
        grab && /^###[[:space:]]/               { exit }
        grab && NF                              { print; exit }
    ')

    if [ -z "$raw" ]; then
        printf 'missing-complexity\n' >&2
        return 4
    fi

    # Strip markdown bold/italic/code decoration around the value. Diagnoses in
    # the wild wrote `**Spectra**`; the decoration is presentation, not value.
    local val="$raw"
    val="${val#"${val%%[![:space:]]*}"}"        # ltrim
    val="${val%"${val##*[![:space:]]}"}"        # rtrim
    val="$(printf '%s' "$val" | sed -E 's/^[*`_]+//; s/[*`_]+$//')"
    val="${val#"${val%%[![:space:]]*}"}"
    val="${val%"${val##*[![:space:]]}"}"

    # Provenance suffix: everything from the first " via " onward is source
    # attribution, not part of the tier. `Plan via Layer V` → `Plan`.
    local tier="${val%% via *}"
    tier="${tier%"${tier##*[![:space:]]}"}"

    case "$tier" in
        Simple|Plan|Spectra|SDD-warranted)
            printf '%s\n' "$tier"
            return 0
            ;;
        *)
            # Surface the ORIGINAL line, not the decoration-stripped form — the
            # operator needs to see exactly what the artifact says.
            printf 'unparseable-complexity: %s\n' "$raw" >&2
            return 3
            ;;
    esac
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
idd_actionability_verdict() {
    local cexit="" label="" blocking=""

    while [ $# -gt 0 ]; do
        case "$1" in
            --complexity-exit) cexit="${2-}"; shift 2 ;;
            --parking-label)   label="${2-}";  shift 2 ;;
            --blocking-section) blocking="${2-}"; shift 2 ;;
            *) printf 'idd_actionability_verdict: unknown argument: %s\n' "$1" >&2; return 2 ;;
        esac
    done

    # Fail loud on missing or malformed input. A gate that silently treats an
    # unanswered signal as "clear" would re-open the exact hole #298 closed —
    # this is the Lazy Developer lens: the cheap path must not be the unsafe one.
    case "$cexit" in
        0|3|4) ;;
        *) printf 'idd_actionability_verdict: --complexity-exit must be 0, 3 or 4 (got: %s)\n' "${cexit:-<empty>}" >&2; return 2 ;;
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
    [ "$cexit" = "3" ]   && reasons+=("complexity-unparseable")
    [ "$cexit" = "4" ]   && reasons+=("complexity-missing")
    [ "$label" = "yes" ] && reasons+=("parking-lot-label")
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

# ── display helper: which group does a not-actionable issue belong to? ───────
#
# idd_actionability_group <reason-list>
#   stdout : "blocked" | "parked"
#
# Reason `blocking-nonempty` ALONE keeps the pre-#298 blocked-state grouping
# (#84) intact — its heading, banner and footer counts are user-facing behavior
# that must not regress. Everything else lands in the parked group.
idd_actionability_group() {
    local reasons="${1-}"
    case "$reasons" in
        "blocking-nonempty") printf 'blocked\n' ;;
        *)                   printf 'parked\n'  ;;
    esac
}
