#!/usr/bin/env bash
# idd-edit-helper.sh — Robust runtime support for /idd-edit skill.
#
# Extracted from plugins/issue-driven-dev/skills/idd-edit/SKILL.md per #154
# (proper proposal after R1/R2/R3 bash-incremental failure on PR #153). Pattern
# follows .claude/scripts/spectra-archive-post-ic.sh precedent.
#
# Subcommands:
#   parse-args <args...>         — Parse /idd-edit flags + emit shell exports
#                                  (eval-friendly KEY="VALUE" lines on stdout)
#   validate-target <comment-id> — Fetch comment author_association/login,
#                                  enforce R5 (non-OWNER refuse) unless override
#   section-replace <body-file> <heading-regex> <target-comment-file>
#                                — awk-getline pattern replacing named section
#                                  with body-file content. BSD/gnu awk safe.
#
# Exit codes:
#   0  — success
#   1  — generic error
#   2  — usage error (missing/invalid args)
#   3  — R4 gate refused (--replace missing --scope/--section)
#   4  — R5 gate refused (non-OWNER, no --override-user-content)
#   5  — --body-file unreadable
#
# Each subcommand prints diagnostics to stderr; stdout reserved for
# machine-parseable output (eval lines / extracted text / etc.).

set -uo pipefail

SUBCMD="${1:-}"
shift || true

# ── R4/R5 helpful messages (constants) ──
R4_MSG='Refuse: --replace requires --scope whole-comment OR --section <heading> (action-scoped discipline per plugins/issue-driven-dev/rules/append-vs-modify.md spec Requirement 4)'
R5_MSG_TEMPLATE='Refuse: comment %s was authored by %s (author_association=%s, non-OWNER non-bot) and is verbatim-preserve per IC_R007; pass --override-user-content --reason="..." to explicitly modify user content (spec Requirement 5)'

# ───────────────────────────────────────────────────────────────────────
# Subcommand: parse-args
# ───────────────────────────────────────────────────────────────────────
# Parses /idd-edit flags. Emits shell-eval'able assignments on stdout.
# Caller does: eval "$(./idd-edit-helper.sh parse-args "$@")"
#
# Recognized flags (all support both --flag=value and --flag value forms):
#   --append / --replace / --prepend-note  (mode flag, mutually exclusive)
#   --scope=<value>                         (R4 explicit scope)
#   --section=<heading>                     (R4 named subsection)
#   --reason=<text>
#   --body=<text>                           (single-line body)
#   --body-file=<path>                      (multi-line body via file)
#   --repo=<owner/repo>
#   --cwd=<path>
#   --last                                  (idiomatic: take last comment)
#   --override-user-content                 (R5 bypass, must pair with --reason)
#
# Positional: comment:<id> | #<issue> | comment:<id> comment:<id>... (batch)
#
# Output (stdout): one assignment per line, shell-quoted values
#   MODE='--replace'
#   SCOPE_FLAG='whole-comment'
#   SECTION_FLAG='### Foo'
#   BODY_INPUT='multi-line content with newlines preserved'
#   TARGETS=('comment:123' 'comment:456')
#   ...
parse_args_subcmd() {
    local mode="" scope_flag="" section_flag="" reason="" body_input=""
    local body_file="" repo="" cwd="" last="false" override="false"
    local -a targets=()

    while [ $# -gt 0 ]; do
        local arg="$1"
        case "$arg" in
            # Mode flags (mutually exclusive)
            --append|--replace|--prepend-note)
                if [ -n "$mode" ] && [ "$mode" != "$arg" ]; then
                    echo "ERROR: conflicting mode flags: $mode and $arg" >&2
                    return 2
                fi
                mode="$arg"
                shift
                ;;

            # Bare boolean flags
            --last)
                last="true"
                shift
                ;;
            --override-user-content)
                override="true"
                shift
                ;;

            # Eq-form flags (--flag=value): SAFE — no value-eating risk
            --scope=*)         scope_flag="${arg#--scope=}";        shift ;;
            --section=*)       section_flag="${arg#--section=}";    shift ;;
            --reason=*)        reason="${arg#--reason=}";           shift ;;
            --body=*)          body_input="${arg#--body=}";         shift ;;
            --body-file=*)
                body_file="${arg#--body-file=}"
                # R3 H1 guard: readability pre-check (silent overwrite was R3 bug)
                if [ ! -r "$body_file" ]; then
                    echo "ERROR: --body-file not readable: $body_file" >&2
                    return 5
                fi
                body_input="$(cat "$body_file")"
                shift
                ;;
            --repo=*)          repo="${arg#--repo=}";               shift ;;
            --cwd=*)           cwd="${arg#--cwd=}";                 shift ;;

            # Space-form flags (--flag value): GUARDED — close R2 + R3 bugs
            #   R2 B3-NEW-1/2: literal capture when next arg looks like a flag
            #   R3 C1/C2: infinite loop on shift 2 when $#=1; flag-eats-flag
            --scope|--section|--reason|--body|--body-file|--repo|--cwd)
                # R3 C1 guard: missing-value when flag is last arg
                if [ $# -lt 2 ]; then
                    echo "ERROR: ${arg} requires value (no argument follows)" >&2
                    return 2
                fi
                local next="$2"
                # R3 C2 guard: next arg looks like a flag → user forgot value
                if [[ "$next" == --* ]]; then
                    echo "ERROR: ${arg} value cannot start with '--' (got: ${next}). Did you forget the value?" >&2
                    return 2
                fi
                case "$arg" in
                    --scope)        scope_flag="$next"   ;;
                    --section)      section_flag="$next" ;;
                    --reason)       reason="$next"       ;;
                    --body)         body_input="$next"   ;;
                    --body-file)
                        body_file="$next"
                        if [ ! -r "$body_file" ]; then
                            echo "ERROR: --body-file not readable: $body_file" >&2
                            return 5
                        fi
                        body_input="$(cat "$body_file")"
                        ;;
                    --repo)         repo="$next"         ;;
                    --cwd)          cwd="$next"          ;;
                esac
                shift 2
                ;;

            # Positional: comment:<id> or #<issue>
            comment:*|\#*)
                targets+=("$arg")
                shift
                ;;

            *)
                echo "ERROR: unknown argument: $arg" >&2
                return 2
                ;;
        esac
    done

    # ── R4 gate: --replace requires --scope=whole-comment OR --section <heading> ──
    # Tightened by #154 verify Round 1 H1: previously only checked non-empty,
    # `--scope typo` passed but downstream had no matching branch → undefined NEW_BODY.
    if [ "$mode" = "--replace" ]; then
        if [ -z "$scope_flag" ] && [ -z "$section_flag" ]; then
            echo "$R4_MSG" >&2
            return 3
        fi
        # If --scope provided, value MUST be exactly "whole-comment" (no other valid scopes today)
        if [ -n "$scope_flag" ] && [ "$scope_flag" != "whole-comment" ]; then
            echo "Refuse: --scope value must be 'whole-comment' (got: '$scope_flag'). Use --section <heading> for named subsection scope." >&2
            return 3
        fi
    fi

    # ── R5-pair guard: --override-user-content requires --reason ──
    if [ "$override" = "true" ] && [ -z "$reason" ]; then
        echo 'ERROR: --override-user-content requires --reason="<rationale>" (spec Requirement 5 audit)' >&2
        return 2
    fi

    # ── Emit eval-friendly output ──
    # printf %q produces shell-safe quoted form preserving newlines
    printf 'MODE=%q\n'           "$mode"
    printf 'SCOPE_FLAG=%q\n'     "$scope_flag"
    printf 'SECTION_FLAG=%q\n'   "$section_flag"
    printf 'REASON=%q\n'         "$reason"
    printf 'BODY_INPUT=%q\n'     "$body_input"
    printf 'BODY_FILE=%q\n'      "$body_file"
    printf 'REPO=%q\n'           "$repo"
    printf 'CWD=%q\n'            "$cwd"
    printf 'LAST=%q\n'           "$last"
    printf 'OVERRIDE_USER_CONTENT=%q\n' "$override"
    # Arrays via space-separated quoted form (caller: eval "TARGETS=( $TARGETS )")
    local targets_quoted=""
    for t in "${targets[@]+"${targets[@]}"}"; do
        targets_quoted+=" $(printf '%q' "$t")"
    done
    printf 'TARGETS=(%s )\n' "$targets_quoted"
}

# ───────────────────────────────────────────────────────────────────────
# Subcommand: validate-target
# ───────────────────────────────────────────────────────────────────────
# Enforces R5: fetch comment's author_association + login, refuse if non-OWNER
# and non-bot unless --override-user-content was passed.
#
# Usage: validate-target <comment-id> <repo> <override-flag> [--print-author]
#   override-flag: "true" / "false" (from parse-args OVERRIDE_USER_CONTENT)
#
# Exit codes:
#   0  — proceed (OWNER, bot, or override active)
#   4  — R5 refuse
validate_target_subcmd() {
    local comment_id="${1:-}"
    local repo="${2:-}"
    local override="${3:-false}"

    if [ -z "$comment_id" ] || [ -z "$repo" ]; then
        echo "ERROR: validate-target requires <comment-id> <repo> <override>" >&2
        return 2
    fi

    # Fetch author info (single API call, two fields).
    # Test hook: when IDD_EDIT_HELPER_GH_MOCK is set, read mock JSON from that
    # path instead of calling gh api. Format expected:
    #   {"login": "alice", "assoc": "OWNER"}
    # Closes #154 verify Round 1 H3 — adds validate-target unit-test surface.
    local author_data
    if [ -n "${IDD_EDIT_HELPER_GH_MOCK:-}" ]; then
        if [ ! -r "$IDD_EDIT_HELPER_GH_MOCK" ]; then
            echo "ERROR: IDD_EDIT_HELPER_GH_MOCK file not readable: $IDD_EDIT_HELPER_GH_MOCK" >&2
            return 1
        fi
        author_data=$(cat "$IDD_EDIT_HELPER_GH_MOCK")
    else
        author_data=$(gh api "repos/$repo/issues/comments/$comment_id" \
                        --jq '{login: .user.login, assoc: .author_association}' 2>&1) || {
            echo "ERROR: gh api fetch failed for comment $comment_id: $author_data" >&2
            return 1
        }
    fi

    local author_login author_assoc
    author_login=$(echo "$author_data" | jq -r '.login // "<null>"')
    author_assoc=$(echo "$author_data" | jq -r '.assoc // "<null>"')

    # M6 guard: refuse if either field is null (malformed gh API response)
    if [ "$author_login" = "<null>" ] || [ "$author_assoc" = "<null>" ]; then
        echo "ERROR: gh api response missing required fields (login/author_association) for comment $comment_id" >&2
        return 1
    fi

    # Known-bot allowlist: any *[bot] suffix matches (github-actions[bot],
    # dependabot[bot], renovate[bot], custom org bots, etc.). M3 cleanup
    # of dead-code redundant patterns from Round 1.
    # NOTE: non-[bot]-suffixed bot accounts (e.g. "myorg-bot", "coderabbitai")
    # currently bypass this allowlist → fall through to OWNER/override path.
    # Document this limitation; future enhancement could read explicit allowlist
    # from config (out of scope for #154).
    case "$author_login" in
        *\[bot\])
            echo "✓ Bot author: $author_login (skip R5 gate)" >&2
            return 0
            ;;
    esac

    # OWNER passes
    if [ "$author_assoc" = "OWNER" ]; then
        echo "✓ OWNER author: $author_login (skip R5 gate)" >&2
        return 0
    fi

    # Non-OWNER non-bot: require override
    if [ "$override" = "true" ]; then
        echo "⚠ Override active: editing $author_login ($author_assoc) content" >&2
        return 0
    fi

    # Refuse with R5 message
    # shellcheck disable=SC2059
    printf "$R5_MSG_TEMPLATE\n" "$comment_id" "$author_login" "$author_assoc" >&2
    return 4
}

# ───────────────────────────────────────────────────────────────────────
# Subcommand: section-replace
# ───────────────────────────────────────────────────────────────────────
# Replace a named section within a markdown file using awk-getline pattern.
# This closes R3 C3 (BSD awk -v cannot handle newline in value) by reading
# replacement body via getline from a file.
#
# Usage: section-replace <input-file> <heading-line> <replacement-file>
#   input-file: original markdown
#   heading-line: exact section heading (e.g. "### Sister Concerns Filed")
#                 Section ends at next heading of same OR higher level (e.g.
#                 "### Foo" ends at next "###" or "##" or "#"). EOF also ends.
#   replacement-file: file containing replacement body (preserved newlines)
#
# Output: modified markdown to stdout
# Exit: 0 on success, 1 if heading not found in input
section_replace_subcmd() {
    local input_file="${1:-}"
    local heading_line="${2:-}"
    local replacement_file="${3:-}"

    if [ -z "$input_file" ] || [ -z "$heading_line" ] || [ -z "$replacement_file" ]; then
        echo "ERROR: section-replace requires <input-file> <heading-line> <replacement-file>" >&2
        return 2
    fi
    if [ ! -r "$input_file" ]; then
        echo "ERROR: input-file not readable: $input_file" >&2
        return 5
    fi
    if [ ! -r "$replacement_file" ]; then
        echo "ERROR: replacement-file not readable: $replacement_file" >&2
        return 5
    fi

    # Strip CRLF from input + replacement (closes #154 verify Round 1 H4 part 2:
    # CRLF input broke grep -Fxq exact match: `## Foo\r` != `## Foo`).
    local clean_input="/tmp/idd-edit-clean-input-$$"
    local clean_repl="/tmp/idd-edit-clean-repl-$$"
    tr -d '\r' < "$input_file" > "$clean_input"
    tr -d '\r' < "$replacement_file" > "$clean_repl"

    # Verify heading exists in cleaned input
    if ! grep -Fxq "$heading_line" "$clean_input"; then
        echo "ERROR: heading not found in input: $heading_line" >&2
        rm -f "$clean_input" "$clean_repl"
        return 1
    fi

    # Determine heading level (count leading #s).
    # Closes #154 verify Round 1 H4 part 1: previous `wc -c` included trailing
    # newline → off-by-one (`## Foo` got level=3 instead of 2). Use awk char-by-char.
    local heading_level
    heading_level=$(printf '%s' "$heading_line" | awk '{
        n = 0
        for (i = 1; i <= length($0); i++) {
            if (substr($0, i, 1) == "#") n++
            else break
        }
        print n
    }')

    # Sanity: 1-6
    if [ "$heading_level" -lt 1 ] || [ "$heading_level" -gt 6 ]; then
        echo "ERROR: invalid heading level ($heading_level) for: $heading_line" >&2
        rm -f "$clean_input" "$clean_repl"
        return 2
    fi

    # awk pattern:
    #   When heading line matches, enter "skipping" mode, getline-print replacement
    #   "Skipping" ends at next heading of level <= heading_level
    #   Outside skipping → print line as-is
    awk -v target="$heading_line" \
        -v level="$heading_level" \
        -v repl_file="$clean_repl" '
        BEGIN { skipping = 0; replaced = 0 }
        # Detect heading line by exact match
        $0 == target && replaced == 0 {
            # Print the heading itself
            print $0
            # Print replacement body via getline
            while ((getline new_line < repl_file) > 0) {
                print new_line
            }
            close(repl_file)
            skipping = 1
            replaced = 1
            next
        }
        # If we are skipping, check for next heading of same/higher level
        skipping == 1 {
            # Match next heading: ^#{1,level} followed by space
            if (match($0, "^#{1," level "}[[:space:]]")) {
                skipping = 0
                print $0
                next
            }
            # Still in old section → skip
            next
        }
        # Normal line outside skipping
        { print $0 }
    ' "$clean_input"
    local awk_exit=$?

    rm -f "$clean_input" "$clean_repl"
    return $awk_exit
}

# ───────────────────────────────────────────────────────────────────────
# Subcommand: emit-audit-marker
# ───────────────────────────────────────────────────────────────────────
# Emit a single-line HTML-comment audit marker with `-->` tokens stripped
# from value content. Centralizes escaping so all 3 modes (--replace /
# --append / --prepend-note) and the override pathway can share one
# safe code path.
#
# Closes #154 verify finding C3:
#   `<!-- idd:edit override-user-content reason="$REASON" -->`
#   interpolated $REASON raw → `--reason='legit --> <!-- forged'`
#   produced a forged audit trail.
#
# Usage: emit-audit-marker <kind> <key=value> [<key=value>...]
#   kind: 'edit' (mode-only) or 'override' (override-user-content)
#   Each value has `-->` collapsed to `--\\>` (visual) so the HTML
#   comment cannot be terminated early by attacker-controlled input.
emit_audit_marker_subcmd() {
    local kind="${1:-}"
    shift || true

    if [ -z "$kind" ]; then
        echo "ERROR: emit-audit-marker requires <kind> arg" >&2
        return 2
    fi

    case "$kind" in
        edit|override) ;;
        *)
            echo "ERROR: emit-audit-marker kind must be 'edit' or 'override' (got: $kind)" >&2
            return 2
            ;;
    esac

    local marker="<!-- idd:edit"
    if [ "$kind" = "override" ]; then
        marker="$marker override-user-content"
    fi

    # Pre-set date if not in kv args
    local has_date="false"

    for kv in "$@"; do
        case "$kv" in
            *=*)
                local key="${kv%%=*}"
                local val="${kv#*=}"
                # Strip --> tokens (collapse to --\> visual placeholder)
                val="${val//-->/-\\>}"
                # Strip newlines (markers must be single-line)
                val="${val//$'\n'/ }"
                # Strip control characters (anything < 0x20 except space)
                val=$(printf '%s' "$val" | tr -d '\000-\010\013\014\016-\037')
                marker="$marker $key=\"$val\""
                [ "$key" = "date" ] && has_date="true"
                ;;
            *)
                echo "ERROR: emit-audit-marker arg must be key=value (got: $kv)" >&2
                return 2
                ;;
        esac
    done

    # Auto-add date if not provided
    if [ "$has_date" = "false" ]; then
        marker="$marker date=\"$(date +%Y-%m-%d)\""
    fi

    marker="$marker -->"
    printf '%s\n' "$marker"
}

# ───────────────────────────────────────────────────────────────────────
# Dispatch
# ───────────────────────────────────────────────────────────────────────
case "$SUBCMD" in
    parse-args)
        parse_args_subcmd "$@"
        ;;
    validate-target)
        validate_target_subcmd "$@"
        ;;
    section-replace)
        section_replace_subcmd "$@"
        ;;
    emit-audit-marker)
        emit_audit_marker_subcmd "$@"
        ;;
    -h|--help|help|"")
        cat <<EOF >&2
idd-edit-helper.sh — Runtime support for /idd-edit skill.

Subcommands:
  parse-args <args...>
      Parse /idd-edit flags, emit shell-eval'able assignments to stdout.

  validate-target <comment-id> <repo> <override-flag>
      Enforce R5: refuse non-OWNER non-bot unless override flag is "true".

  section-replace <input-file> <heading-line> <replacement-file>
      Replace named markdown section via awk-getline (BSD/gnu safe).

  emit-audit-marker <kind> <key=value>...
      Emit HTML-comment audit marker with --> tokens stripped from values.
      Closes #154 verify finding C3 — REASON HTML-comment-out injection.
      Kinds: edit / override.

Exit codes:
  0=success, 1=generic, 2=usage, 3=R4-refuse, 4=R5-refuse, 5=unreadable-file
EOF
        [ "$SUBCMD" = "" ] && exit 2 || exit 0
        ;;
    *)
        echo "ERROR: unknown subcommand: $SUBCMD" >&2
        echo "Run with --help for usage." >&2
        exit 2
        ;;
esac
