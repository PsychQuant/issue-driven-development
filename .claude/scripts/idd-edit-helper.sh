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

    # ── R4 gate: --replace requires --scope OR --section ──
    if [ "$mode" = "--replace" ] && [ -z "$scope_flag" ] && [ -z "$section_flag" ]; then
        echo "$R4_MSG" >&2
        return 3
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

    # Fetch author info (single API call, two fields)
    local author_data
    author_data=$(gh api "repos/$repo/issues/comments/$comment_id" \
                    --jq '{login: .user.login, assoc: .author_association}' 2>&1) || {
        echo "ERROR: gh api fetch failed for comment $comment_id: $author_data" >&2
        return 1
    }

    local author_login author_assoc
    author_login=$(echo "$author_data" | jq -r '.login')
    author_assoc=$(echo "$author_data" | jq -r '.assoc')

    # Known-bot allowlist
    case "$author_login" in
        github-actions\[bot\]|dependabot\[bot\]|*\[bot\])
            # All [bot] accounts pass (idd-bot, github-actions[bot], etc.)
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

    # Verify heading exists
    if ! grep -Fxq "$heading_line" "$input_file"; then
        echo "ERROR: heading not found in input: $heading_line" >&2
        return 1
    fi

    # Determine heading level (count leading #s) to know when section ends
    local heading_level
    heading_level=$(echo "$heading_line" | grep -oE '^#+' | head -c 10 | wc -c | tr -d ' ')
    # Sanity: 1-6
    if [ "$heading_level" -lt 1 ] || [ "$heading_level" -gt 6 ]; then
        echo "ERROR: invalid heading level ($heading_level) for: $heading_line" >&2
        return 2
    fi

    # awk pattern:
    #   When heading line matches, enter "skipping" mode, getline-print replacement
    #   "Skipping" ends at next heading of level <= heading_level
    #   Outside skipping → print line as-is
    awk -v target="$heading_line" \
        -v level="$heading_level" \
        -v repl_file="$replacement_file" '
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
    ' "$input_file"
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
