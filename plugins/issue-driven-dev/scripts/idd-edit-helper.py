#!/usr/bin/env python3
"""idd-edit-helper.py — Robust runtime support for /idd-edit skill.

Python reimplementation of the failed bash helper (R1/R2/R3 on PR #153)
per issue #155. Bash proved to be the wrong layer for this adversarial
parsing/enforcement load — each round introduced new bugs. Python
(argparse-style manual parser + os.path.realpath + html escaping) eliminates
the bug classes *by construction*.

Subcommands:
  parse-args <args...>         — Parse /idd-edit flags, run R4 + body-file
                                 gates, emit shell-eval'able assignments on
                                 stdout (KEY=value lines, bash %q-quoted).
  validate-target <comment-id> <repo> <override>
                               — Enforce R5: non-OWNER non-bot author refuse
                                 unless --override-user-content active.
  section-replace <input-file> <heading-line> <replacement-file>
                               — Replace a named markdown section, level-aware,
                                 CRLF-safe. Emits modified body to stdout.
  emit-audit-marker <kind> <key=value>...
                               — Emit HTML-comment audit marker with safe
                                 escaping (no breakout, no attribute injection).

Exit codes:
  0  — success
  1  — generic error
  2  — usage error (missing/invalid args)
  3  — R4 gate refused (--replace missing --scope/--section)
  4  — R5 gate refused (non-OWNER non-bot, no --override-user-content)
  5  — --body-file unreadable / refused

Each subcommand prints diagnostics to stderr; stdout is reserved for
machine-parseable output (eval lines / extracted text / markers).
"""

import datetime
import html
import json
import os
import re
import sys

# ── R4/R5 helpful messages (constants, must match bash reference substrings) ──
R4_MSG = (
    "Refuse: --replace requires --scope whole-comment OR --section <heading> "
    "(action-scoped discipline per plugins/issue-driven-dev/rules/append-vs-modify.md "
    "spec Requirement 4)"
)
R5_MSG_TEMPLATE = (
    "Refuse: comment {cid} was authored by {login} (author_association={assoc}, "
    "non-OWNER non-bot) and is verbatim-preserve per IC_R007; pass "
    '--override-user-content --reason="..." to explicitly modify user content '
    "(spec Requirement 5)"
)


def err(msg):
    """Print a diagnostic line to stderr."""
    print(msg, file=sys.stderr)


# ───────────────────────────────────────────────────────────────────────
# bash `printf %q` faithful reimplementation (single-line values)
# ───────────────────────────────────────────────────────────────────────
# The test runner asserts substrings against the bash-shaped output, e.g.
#   BODY_INPUT=hello\ world      (fixture 07)
#   REASON=errata\ clarification\ per\ IDD\ discipline  (fixture 13)
#   BODY_INPUT=safe\ content     (fixture 23)
# so single-line values are emitted in bash `%q` form. The empty string is
# rendered as ''. For multiline values (fixture 06) we deliberately emit the
# raw value so per-line substrings (`line 1`, `line 2`, `backtick`) match —
# this is the bug the bash reference had (it `%q`-escaped newlines into a
# single line, breaking the substring assertions).

# Characters bash `%q` leaves unescaped in the "no-quoting-needed" word form.
_BASH_Q_SAFE = set(
    "abcdefghijklmnopqrstuvwxyz"
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "0123456789"
    "_-./=:@%+,"
)


def bash_quote(value):
    """Reproduce `printf %q` for a single-line value (no newlines).

    Newlines are handled by the caller (multiline path emits raw).
    """
    if value == "":
        return "''"
    out = []
    for ch in value:
        if ch in _BASH_Q_SAFE:
            out.append(ch)
        elif ch == "\t":
            out.append("$'\\t'")
        elif ch == "\r":
            out.append("$'\\r'")
        else:
            # Backslash-escape everything else (matches bash for the
            # shell-metacharacter / whitespace cases the fixtures exercise:
            # space, $, ", ', \, `, ;, |, &, (, ), *, #, ~, etc.)
            out.append("\\" + ch)
    return "".join(out)


def emit_assignment(key, value):
    """Print one shell-eval'able assignment line.

    Single-line values use bash `%q` quoting; multiline values are emitted
    raw so that downstream substring assertions on individual lines match.
    """
    if "\n" in value:
        # Raw multiline: KEY=<line0>\n<line1>... — preserves human-readable
        # content for substring matching (fixture 06).
        print(f"{key}={value}")
    else:
        print(f"{key}={bash_quote(value)}")


# ───────────────────────────────────────────────────────────────────────
# --body-file path safety (THE critical gate — closes R3 5-way bypass)
# ───────────────────────────────────────────────────────────────────────
# Canonicalize with os.path.realpath FIRST, then prefix-check the CANONICAL
# path. NEVER string-prefix-match the raw input — that is exactly how the R3
# bypasses worked (`//etc/passwd`, `/tmp/../etc/passwd`, `../../etc/passwd`,
# symlinks into refused dirs all defeat raw-string matching but collapse to a
# refused canonical path).
#
# Returns: (ok: bool, exit_code: int). ok=True → proceed; ok=False → refuse
# with the already-printed stderr message and the given exit code.

# Absolute system path prefixes that are always refused.
_REFUSED_SYSTEM_PREFIXES = (
    "/etc",
    "/var",
    "/sys",
    "/proc",
    "/private/etc",
    "/private/var",
)

# Credential directory basenames refused under $HOME (and, defensively,
# anywhere — a realpath landing in any user's ~/.ssh is sensitive).
_REFUSED_CREDENTIAL_DIRS = (
    ".ssh",
    ".aws",
    ".gnupg",
    ".kube",
    ".docker",
)


def _path_is_under(canonical, prefix):
    """True if canonical == prefix or canonical is strictly under prefix.

    Component-aware: `/etc` matches `/etc/passwd` and `/etc` but NOT
    `/etcetera`. Both args are already absolute (realpath output / abs prefix).
    """
    prefix = prefix.rstrip("/")
    if canonical == prefix:
        return True
    return canonical.startswith(prefix + "/")


def validate_body_file_path(raw_path):
    """Refuse sensitive system/credential paths for --body-file.

    Canonicalizes the raw input first, then checks the canonical path against
    refused prefixes. Honors the IDD_EDIT_HELPER_ALLOW_UNSAFE_BODY_FILE=1
    escape hatch. Returns (ok, exit_code).
    """
    # Escape hatch (documented advanced use).
    if os.environ.get("IDD_EDIT_HELPER_ALLOW_UNSAFE_BODY_FILE") == "1":
        return True, 0

    # Canonicalize FIRST. realpath resolves `..`, duplicate slashes, and
    # symlinks against the real filesystem, collapsing every bypass vector
    # to its true target before we inspect it.
    canonical = os.path.realpath(raw_path)

    # Refuse sensitive absolute system paths (component-aware prefix match).
    for prefix in _REFUSED_SYSTEM_PREFIXES:
        if _path_is_under(canonical, prefix):
            err(f"ERROR: --body-file refuses sensitive system path: {raw_path}")
            err(
                "       Use IDD_EDIT_HELPER_ALLOW_UNSAFE_BODY_FILE=1 to "
                "override (audit your reason)."
            )
            return False, 5

    # Refuse credential directories. Check by path component so a realpath
    # landing in any `.ssh` / `.aws` / ... directory is caught regardless of
    # which home it lives under.
    home = os.environ.get("HOME", "")
    components = canonical.split(os.sep)
    for cred in _REFUSED_CREDENTIAL_DIRS:
        if cred in components:
            # Only refuse credential dirs under a home directory: matches the
            # bash reference's $HOME/.ssh/* etc. scope while staying robust to
            # symlinks that resolve into the real home.
            if home and (
                _path_is_under(canonical, os.path.join(home, cred))
                or canonical.startswith(os.path.realpath(home) + os.sep)
            ):
                err(f"ERROR: --body-file refuses credential path: {raw_path}")
                err(
                    "       Use IDD_EDIT_HELPER_ALLOW_UNSAFE_BODY_FILE=1 to "
                    "override (audit your reason)."
                )
                return False, 5

    return True, 0


def read_body_file(raw_path):
    """Validate path safety + readability, return (ok, exit_code, content)."""
    ok, code = validate_body_file_path(raw_path)
    if not ok:
        return False, code, None
    if not os.path.isfile(raw_path) or not os.access(raw_path, os.R_OK):
        err(f"ERROR: --body-file not readable: {raw_path}")
        return False, 5, None
    try:
        with open(raw_path, "r", encoding="utf-8", errors="replace") as fh:
            return True, 0, fh.read()
    except OSError:
        err(f"ERROR: --body-file not readable: {raw_path}")
        return False, 5, None


# ───────────────────────────────────────────────────────────────────────
# Subcommand: parse-args
# ───────────────────────────────────────────────────────────────────────
# Recognized flags (both --flag=value and --flag value forms):
#   --append / --replace / --prepend-note  (mode, mutually exclusive)
#   --scope=<value>  --section=<heading>  --reason=<text>
#   --body=<text>  --body-file=<path>  --repo=<owner/repo>  --cwd=<path>
#   --last  --override-user-content
# Positional: comment:<id> | #<issue> (one or more, batch).

_VALUE_FLAGS = {
    "--scope": "scope_flag",
    "--section": "section_flag",
    "--reason": "reason",
    "--body": "body_input",
    "--body-file": "body_file",
    "--repo": "repo",
    "--cwd": "cwd",
}
_MODE_FLAGS = ("--append", "--replace", "--prepend-note")


def parse_args_subcmd(argv):
    state = {
        "mode": "",
        "scope_flag": "",
        "section_flag": "",
        "reason": "",
        "body_input": "",
        "body_file": "",
        "repo": "",
        "cwd": "",
        "last": "false",
        "override": "false",
    }
    targets = []

    i = 0
    n = len(argv)
    while i < n:
        arg = argv[i]

        # Mode flags (mutually exclusive).
        if arg in _MODE_FLAGS:
            if state["mode"] and state["mode"] != arg:
                err(f"ERROR: conflicting mode flags: {state['mode']} and {arg}")
                return 2
            state["mode"] = arg
            i += 1
            continue

        # Bare boolean flags.
        if arg == "--last":
            state["last"] = "true"
            i += 1
            continue
        if arg == "--override-user-content":
            state["override"] = "true"
            i += 1
            continue

        # Eq-form value flags (--flag=value): SAFE, no value-eating risk.
        if arg.startswith("--") and "=" in arg:
            flag, _, value = arg.partition("=")
            if flag in _VALUE_FLAGS:
                if flag == "--body-file":
                    ok, code, content = read_body_file(value)
                    if not ok:
                        return code
                    state["body_file"] = value
                    state["body_input"] = content
                else:
                    state[_VALUE_FLAGS[flag]] = value
                i += 1
                continue
            err(f"ERROR: unknown argument: {arg}")
            return 2

        # Space-form value flags (--flag value): GUARDED.
        if arg in _VALUE_FLAGS:
            # Missing-value guard: flag is the last argument.
            if i + 1 >= n:
                err(f"ERROR: {arg} requires value (no argument follows)")
                return 2
            nxt = argv[i + 1]
            # Next-flag-eats-value guard: a following token that looks like a
            # flag means the user forgot the value (do NOT consume it).
            if nxt.startswith("--"):
                err(
                    f"ERROR: {arg} value cannot start with '--' (got: {nxt}). "
                    "Did you forget the value?"
                )
                return 2
            if arg == "--body-file":
                ok, code, content = read_body_file(nxt)
                if not ok:
                    return code
                state["body_file"] = nxt
                state["body_input"] = content
            else:
                state[_VALUE_FLAGS[arg]] = nxt
            i += 2
            continue

        # Positional targets: comment:<id> or #<issue>.
        if arg.startswith("comment:") or arg.startswith("#"):
            targets.append(arg)
            i += 1
            continue

        err(f"ERROR: unknown argument: {arg}")
        return 2

    # ── R4 gate: --replace requires --scope=whole-comment OR --section ──
    if state["mode"] == "--replace":
        if not state["scope_flag"] and not state["section_flag"]:
            err(R4_MSG)
            return 3
        if state["scope_flag"] and state["scope_flag"] != "whole-comment":
            err(
                "Refuse: --scope value must be 'whole-comment' (got: "
                f"'{state['scope_flag']}'). Use --section <heading> for named "
                "subsection scope."
            )
            return 3

    # ── R5-pair guard: --override-user-content requires --reason ──
    if state["override"] == "true" and not state["reason"]:
        err(
            "ERROR: --override-user-content requires "
            '--reason="<rationale>" (spec Requirement 5 audit)'
        )
        return 2

    # ── Emit eval-friendly output ──
    emit_assignment("MODE", state["mode"])
    emit_assignment("SCOPE_FLAG", state["scope_flag"])
    emit_assignment("SECTION_FLAG", state["section_flag"])
    emit_assignment("REASON", state["reason"])
    emit_assignment("BODY_INPUT", state["body_input"])
    emit_assignment("BODY_FILE", state["body_file"])
    emit_assignment("REPO", state["repo"])
    emit_assignment("CWD", state["cwd"])
    emit_assignment("LAST", state["last"])
    emit_assignment("OVERRIDE_USER_CONTENT", state["override"])
    targets_quoted = " ".join(bash_quote(t) for t in targets)
    print(f"TARGETS=( {targets_quoted} )" if targets_quoted else "TARGETS=(  )")
    return 0


# ───────────────────────────────────────────────────────────────────────
# Subcommand: validate-target (R5 author check)
# ───────────────────────────────────────────────────────────────────────
def _load_author_data(comment_id, repo):
    """Return (ok, exit_code, author_dict).

    In test mode (IDD_EDIT_HELPER_TEST_MODE=1) reads the mock JSON named by
    IDD_EDIT_HELPER_GH_MOCK. The mock is *only* honored in test mode — a
    security property: an attacker-supplied env var must never override the
    real author check in production. Otherwise calls `gh api`.
    """
    mock = os.environ.get("IDD_EDIT_HELPER_GH_MOCK")
    if mock:
        if os.environ.get("IDD_EDIT_HELPER_TEST_MODE") != "1":
            err("ERROR: IDD_EDIT_HELPER_GH_MOCK is a test-only hook; refuses in production.")
            err("       Pair with IDD_EDIT_HELPER_TEST_MODE=1 if invoking from test runner.")
            return False, 1, None
        if not os.path.isfile(mock) or not os.access(mock, os.R_OK):
            err(f"ERROR: IDD_EDIT_HELPER_GH_MOCK file not readable: {mock}")
            return False, 1, None
        try:
            with open(mock, "r", encoding="utf-8") as fh:
                raw = fh.read()
        except OSError:
            err(f"ERROR: IDD_EDIT_HELPER_GH_MOCK file not readable: {mock}")
            return False, 1, None
    else:
        import subprocess

        try:
            proc = subprocess.run(
                [
                    "gh",
                    "api",
                    f"repos/{repo}/issues/comments/{comment_id}",
                    "--jq",
                    "{login: .user.login, assoc: .author_association}",
                ],
                capture_output=True,
                text=True,
            )
        except FileNotFoundError:
            err(f"ERROR: gh api fetch failed for comment {comment_id}: gh not found")
            return False, 1, None
        if proc.returncode != 0:
            err(
                f"ERROR: gh api fetch failed for comment {comment_id}: "
                f"{proc.stderr.strip() or proc.stdout.strip()}"
            )
            return False, 1, None
        raw = proc.stdout

    try:
        data = json.loads(raw)
    except (ValueError, TypeError):
        data = {}
    if not isinstance(data, dict):
        data = {}
    return True, 0, data


def validate_target_subcmd(argv):
    comment_id = argv[0] if len(argv) >= 1 else ""
    repo = argv[1] if len(argv) >= 2 else ""
    override = argv[2] if len(argv) >= 3 else "false"

    if not comment_id or not repo:
        err("ERROR: validate-target requires <comment-id> <repo> <override>")
        return 2

    # comment-id must validate as digits before any use.
    if not re.fullmatch(r"[0-9]+", comment_id):
        err(f"ERROR: comment-id must be numeric (got: {comment_id})")
        return 2

    ok, code, data = _load_author_data(comment_id, repo)
    if not ok:
        return code

    login = data.get("login")
    assoc = data.get("assoc")

    # Fail-closed: refuse if either required field is missing/empty.
    if not login or not assoc:
        err(
            "ERROR: gh api response missing or unparseable required fields "
            f"(login/author_association) for comment {comment_id}"
        )
        return 1

    # Known-bot allowlist: any *[bot] suffix matches.
    if login.endswith("[bot]"):
        err(f"✓ Bot author: {login} (skip R5 gate)")
        return 0

    # OWNER passes.
    if assoc == "OWNER":
        err(f"✓ OWNER author: {login} (skip R5 gate)")
        return 0

    # Non-OWNER non-bot: require override.
    if override == "true":
        err(f"⚠ Override active: editing {login} ({assoc}) content")
        return 0

    # Refuse with R5 message.
    err(R5_MSG_TEMPLATE.format(cid=comment_id, login=login, assoc=assoc))
    return 4


# ───────────────────────────────────────────────────────────────────────
# Subcommand: section-replace (level-aware, CRLF-safe)
# ───────────────────────────────────────────────────────────────────────
def _heading_level(line):
    """Count leading '#' chars (markdown heading level), 0 if not a heading."""
    n = 0
    for ch in line:
        if ch == "#":
            n += 1
        else:
            break
    return n


def section_replace_subcmd(argv):
    input_file = argv[0] if len(argv) >= 1 else ""
    heading_line = argv[1] if len(argv) >= 2 else ""
    replacement_file = argv[2] if len(argv) >= 3 else ""

    if not input_file or not heading_line or not replacement_file:
        err(
            "ERROR: section-replace requires <input-file> <heading-line> "
            "<replacement-file>"
        )
        return 2
    if not os.path.isfile(input_file) or not os.access(input_file, os.R_OK):
        err(f"ERROR: input-file not readable: {input_file}")
        return 5
    if not os.path.isfile(replacement_file) or not os.access(replacement_file, os.R_OK):
        err(f"ERROR: replacement-file not readable: {replacement_file}")
        return 5

    with open(input_file, "r", encoding="utf-8", errors="replace") as fh:
        input_text = fh.read()
    with open(replacement_file, "r", encoding="utf-8", errors="replace") as fh:
        repl_text = fh.read()

    # Strip CRLF: normalize \r\n and lone \r to \n (closes the CRLF exact-match
    # break — `## Foo\r` != `## Foo`).
    input_text = input_text.replace("\r\n", "\n").replace("\r", "\n")
    repl_text = repl_text.replace("\r\n", "\n").replace("\r", "\n")

    input_lines = input_text.split("\n")
    # split() yields a trailing "" when the file ends with a newline; track it
    # so the output's trailing-newline shape is preserved.
    trailing_newline = input_text.endswith("\n")
    if trailing_newline and input_lines and input_lines[-1] == "":
        input_lines = input_lines[:-1]

    # Determine target heading level.
    level = _heading_level(heading_line)
    if level < 1 or level > 6:
        err(f"ERROR: invalid heading level ({level}) for: {heading_line}")
        return 2

    # Verify heading exists (exact line match on cleaned input).
    if heading_line not in input_lines:
        err(f"ERROR: heading not found in input: {heading_line}")
        return 1

    # Replacement body lines (preserve internal newlines; drop the trailing
    # empty produced by a final newline so we don't inject a blank line).
    repl_lines = repl_text.split("\n")
    if repl_text.endswith("\n") and repl_lines and repl_lines[-1] == "":
        repl_lines = repl_lines[:-1]

    # Level-aware section boundary: a `### Foo` section ends at the next
    # heading of the SAME-or-higher level (subsections under it, being a
    # *lower* level / more '#'s, are part of the section and replaced as a
    # unit). EOF also ends the section.
    out = []
    replaced = False
    skipping = False
    for line in input_lines:
        if not replaced and line == heading_line:
            out.append(line)
            out.extend(repl_lines)
            replaced = True
            skipping = True
            continue
        if skipping:
            lvl = _heading_level(line)
            # A heading of same-or-higher level (lvl <= target, lvl >= 1)
            # followed by whitespace ends the section.
            if 1 <= lvl <= level and len(line) > lvl and line[lvl].isspace():
                skipping = False
                out.append(line)
                continue
            # Still inside the old section → drop the line.
            continue
        out.append(line)

    result = "\n".join(out)
    if trailing_newline:
        result += "\n"
    sys.stdout.write(result)
    return 0


# ───────────────────────────────────────────────────────────────────────
# Subcommand: emit-audit-marker (safe HTML-comment audit marker)
# ───────────────────────────────────────────────────────────────────────
# Escape values safely so attacker-controlled --reason cannot break out of the
# HTML comment or forge attributes:
#   - `"`  → `&quot;`  (prevent attribute-quote breakout)
#   - `-->`→ `--\>`    (prevent early HTML-comment termination)
#   - control chars \x00-\x1f and newlines → stripped/spaced (single-line)
# No regex back-reference traps (fixture 20): plain string replaces only.
_CONTROL_CHARS = "".join(chr(c) for c in range(0x00, 0x20))


def _sanitize_marker_value(val):
    # Quote-escape first (prevents attribute injection). Use explicit replace
    # of `"` → `&quot;` — NOT a regex with `&` in the replacement (that is the
    # bash back-reference trap; in Python re.sub `\g<0>`/`&` differ, but we
    # avoid regex entirely here).
    val = val.replace('"', "&quot;")
    # Collapse `-->` so the comment cannot be terminated early.
    val = val.replace("-->", "--\\>")
    # Strip newlines (markers are single-line).
    val = val.replace("\r", " ").replace("\n", " ")
    # Strip all remaining control characters.
    val = "".join(ch for ch in val if ch not in _CONTROL_CHARS)
    return val


def _sanitize_marker_key(key):
    # Keys: remove `"` and `-->` entirely (no current caller threads user
    # input into keys; defense in depth).
    key = key.replace('"', "")
    key = key.replace("-->", "")
    key = "".join(ch for ch in key if ch not in _CONTROL_CHARS)
    return key


def emit_audit_marker_subcmd(argv):
    if not argv:
        err("ERROR: emit-audit-marker requires <kind> arg")
        return 2
    kind = argv[0]
    rest = argv[1:]

    if kind not in ("edit", "override"):
        err(f"ERROR: emit-audit-marker kind must be 'edit' or 'override' (got: {kind})")
        return 2

    marker = "<!-- idd:edit"
    if kind == "override":
        marker += " override-user-content"

    has_date = False
    for kv in rest:
        if "=" not in kv:
            err(f"ERROR: emit-audit-marker arg must be key=value (got: {kv})")
            return 2
        key, _, val = kv.partition("=")
        key = _sanitize_marker_key(key)
        val = _sanitize_marker_value(val)
        marker += f' {key}="{val}"'
        if key == "date":
            has_date = True

    if not has_date:
        marker += f' date="{datetime.date.today().isoformat()}"'

    marker += " -->"
    print(marker)
    return 0


# ───────────────────────────────────────────────────────────────────────
# Dispatch
# ───────────────────────────────────────────────────────────────────────
HELP_TEXT = """idd-edit-helper.py — Runtime support for /idd-edit skill.

Subcommands:
  parse-args <args...>
      Parse /idd-edit flags, emit shell-eval'able assignments to stdout.

  validate-target <comment-id> <repo> <override-flag>
      Enforce R5: refuse non-OWNER non-bot unless override flag is "true".

  section-replace <input-file> <heading-line> <replacement-file>
      Replace named markdown section (level-aware, CRLF-safe).

  emit-audit-marker <kind> <key=value>...
      Emit HTML-comment audit marker with safe escaping. Kinds: edit / override.

Exit codes:
  0=success, 1=generic, 2=usage, 3=R4-refuse, 4=R5-refuse, 5=unreadable-file
"""


def main(argv):
    subcmd = argv[0] if argv else ""
    rest = argv[1:]

    if subcmd == "parse-args":
        return parse_args_subcmd(rest)
    if subcmd == "validate-target":
        return validate_target_subcmd(rest)
    if subcmd == "section-replace":
        return section_replace_subcmd(rest)
    if subcmd == "emit-audit-marker":
        return emit_audit_marker_subcmd(rest)
    if subcmd in ("-h", "--help", "help", ""):
        err(HELP_TEXT)
        return 2 if subcmd == "" else 0

    err(f"ERROR: unknown subcommand: {subcmd}")
    err("Run with --help for usage.")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
