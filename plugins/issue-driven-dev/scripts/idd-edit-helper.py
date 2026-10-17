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
  validate-target <comment-id> <repo> <override> [<mode>]
                               — Enforce R5: refuse an author who is not OWNER,
                                 a bot, or the gh user, unless
                                 --override-user-content is active. With mode
                                 --correct a bot is refused too (#351).
  section-replace <input-file> <heading-line> <replacement-file>
                               — Replace a named markdown section, level-aware,
                                 CRLF-safe. Emits modified body to stdout.
  emit-audit-marker <kind> <key=value>...
                               — Emit HTML-comment audit marker with safe
                                 escaping (no breakout, no attribute injection).
  check-correction <old-file> <section-heading|-> <new-file>
                               — Refuse a --correct replacement that touches a
                                 protected region (#351).
  compose-correction <old-file> <section-heading|-> <body-file> <marker>
                               — Print the full corrected body that is both
                                 previewed and written (#351).
  archive <comment|issue> <id> --from-file <path> --repo <owner/repo>
                               — Write the prior text to the correction
                                 archive; print only the backup id (#351).
  restore <backup-id> --repo <owner/repo>
                               — PATCH a target back to its archived text
                                 without displaying it (#351).

Exit codes:
  0  — success
  1  — generic error
  2  — usage error (missing/invalid args)
  3  — R4 gate refused (--replace missing --scope/--section)
  4  — R5 gate refused (author is neither OWNER, a bot, nor you; no
       --override-user-content), or --correct on anyone else's content;
       correct-prepare / correct-apply: not done (RESULT= / REASON= say why)
  5  — --body-file unreadable / refused
  6  — check-correction refused a protected region
  7  — archive: refused (not a git work tree / path not ignored / write
       failed); correct-apply: written but not confirmed on read-back
  8  — the pinned Markdown parser (markdown-it-py 4.0.0) is missing or differs
  9  — the --section heading occurs more than once (section-ambiguous)

Each subcommand prints diagnostics to stderr; stdout is reserved for
machine-parseable output (eval lines / extracted text / markers).
"""

import datetime
import html
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile

# ── R4/R5 helpful messages (constants, must match bash reference substrings) ──
R4_MSG = (
    "Refuse: --replace requires --scope whole-comment OR --section <heading> "
    "(action-scoped discipline per plugins/issue-driven-dev/rules/append-vs-modify.md "
    "spec Requirement 4)"
)
CORRECT_SCOPE_MSG = (
    "Refuse: --correct requires --scope whole-comment OR --section <heading> "
    "(an issue:<N> target accepts --section only; #351)"
)
R5_MSG_TEMPLATE = (
    "Refuse: comment {cid} was authored by {login} (author_association={assoc}, "
    "neither OWNER, a bot, nor you) and is verbatim-preserve per IC_R007; pass "
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
    "_-./:@%+,"
)
# '=' is deliberately absent: zsh expands `=cmd` at the start of a word and
# after ':' in an assignment value (verify #351 rounds 2 and 3).


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
    # Control characters go through ANSI-C quoting too: bash command
    # substitution drops a NUL, so `\<NUL>;` from the backslash form collapsed
    # into `\;` + a live `;` under eval (verify #351 round 3).
    if "\n" in value or any(ord(ch) < 0x20 or ord(ch) >= 0x7F for ch in value):
        # ANSI-C quoting ($'...'). The raw form this replaced (KEY=<line0>
        # newline <line1>...) made `eval` run every line after the first as a
        # shell command — `$(...)` and backticks in a body file executed — and
        # left KEY unset (verify #351 round 1). Lines stay readable inside the
        # quote, so fixture 06's per-line substrings still match.
        print(f"{key}={ansi_c_quote(value)}")
    else:
        print(f"{key}={bash_quote(value)}")


def _shell_word(value):
    """One value as a shell word that evals back to itself in bash and zsh."""
    if "\n" in value or any(ord(ch) < 0x20 or ord(ch) >= 0x7F for ch in value):
        return ansi_c_quote(value)
    return bash_quote(value)


def ansi_c_quote(value):
    """bash $'...' quoting: every byte round-trips through eval, nothing expands."""
    out = []
    for ch in value:
        if ch == "\\":
            out.append("\\\\")
        elif ch == "'":
            out.append("\\'")
        elif ch == "\n":
            out.append("\\n")
        elif ch == "\t":
            out.append("\\t")
        elif ch == "\r":
            out.append("\\r")
        elif ord(ch) < 0x20 or ord(ch) == 0x7F:
            out.append("\\x%02x" % ord(ch))
        elif ord(ch) > 0x7F:
            # Raw multibyte text is read per the shell's locale; in zh_TW.Big5 a
            # trail byte 0x5C is a backslash to zsh (verify #351 round 4). Byte
            # escapes rebuild the exact UTF-8 bytes whatever the locale.
            out.extend("\\x%02x" % b for b in ch.encode("utf-8"))
        else:
            out.append(ch)
    return "$'" + "".join(out) + "'"


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

    # The user's own temporary directory is not a system path, even where it
    # lives under /var (macOS: /var/folders/<..>/T). Refusing it made every
    # idd-edit working copy unreadable to `archive` on macOS (verify #351
    # round 4). Only a directory strictly below it counts, and only when the
    # temp root is not itself one of the refused roots.
    tmp_root = os.path.realpath(tempfile.gettempdir())
    in_user_tmp = (
        tmp_root not in ("/",) + _REFUSED_SYSTEM_PREFIXES
        and canonical != tmp_root
        and _path_is_under(canonical, tmp_root)
    )

    # Refuse sensitive absolute system paths (component-aware prefix match).
    for prefix in () if in_user_tmp else _REFUSED_SYSTEM_PREFIXES:
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
            content = fh.read()
    except OSError:
        err(f"ERROR: --body-file not readable: {raw_path}")
        return False, 5, None
    if "\x00" in content:
        err(f"ERROR: --body-file contains a NUL byte, which no issue text can hold: {raw_path}")
        return False, 5, None
    return True, 0, content


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
_MODE_FLAGS = ("--append", "--replace", "--prepend-note", "--correct")
_ATX_HEADING_RE = re.compile(r"#{1,6}[ \t]+\S.*")


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

        # Positional targets: comment:<id>, #<issue>, or issue:<N> (issue
        # body; --correct only, #351).
        if arg.startswith("comment:") or arg.startswith("#") or arg.startswith("issue:"):
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

    # --section names an ATX heading line: section-replace matches it as a whole
    # line and reads its level from the leading '#'s, so `Expected` or
    # `##Expected` matched nothing or the wrong level (verify #351 round 2).
    if state["section_flag"] and not _ATX_HEADING_RE.fullmatch(state["section_flag"]):
        err(
            "Refuse: --section must be a markdown heading line such as '## Expected' "
            f"(one to six '#', a space, then the title; got: '{state['section_flag']}')."
        )
        return 2

    # ── --correct gates (#351) ──
    issue_targets = [t for t in targets if t.startswith("issue:")]
    for t in issue_targets:
        if not re.fullmatch(r"issue:[0-9]+", t):
            err(f"ERROR: issue target must be issue:<numeric issue number> (got: {t})")
            return 2
    if issue_targets and len(targets) > 1:
        err(
            "Refuse: an issue:<N> target must be the only target of the invocation "
            "(mixing it with comment targets, or naming two issues, is not supported)."
        )
        return 2
    if issue_targets and state["mode"] != "--correct":
        err(
            "Refuse: an issue:<N> (issue body) target is only accepted with --correct. "
            "Other edit modes on the issue body are tracked in #347."
        )
        return 2
    if state["mode"] == "--correct":
        if state["override"] == "true":
            err(
                "Refuse: --correct cannot override user-authored content. It rewrites only "
                "content by the OWNER or by you; for anyone else's comment, a bot's "
                "included, propose the correction with /idd-comment --type errata (#351)."
            )
            return 2
        if not state["scope_flag"] and not state["section_flag"]:
            err(CORRECT_SCOPE_MSG)
            return 3
        if state["scope_flag"] and state["section_flag"]:
            err("Refuse: --correct takes exactly one of --scope whole-comment or --section <heading>.")
            return 3
        if state["scope_flag"] and state["scope_flag"] != "whole-comment":
            err(
                "Refuse: --scope value must be 'whole-comment' (got: "
                f"'{state['scope_flag']}'). Use --section <heading> for named "
                "subsection scope."
            )
            return 3
        if not state["body_input"].strip():
            err(
                "Refuse: --correct needs the corrected text (--body or --body-file); "
                "without it the region would be emptied (#351)."
            )
            return 2
        if issue_targets and state["scope_flag"]:
            err(
                "Refuse: an issue-body correction requires --section <heading>; "
                "replacing the whole body would also overwrite the Original text "
                "quotation and the sections owned by idd-update and idd-clarify."
            )
            return 3

    if not targets:
        err("ERROR: no target given (comment:<id>, #<issue> or issue:<N>); nothing to edit")
        return 2

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
    targets_quoted = " ".join(_shell_word(t) for t in targets)
    print(f"TARGETS=( {targets_quoted} )" if targets_quoted else "TARGETS=(  )")
    return 0


# ───────────────────────────────────────────────────────────────────────
# Subcommand: validate-target (R5 author check)
# ───────────────────────────────────────────────────────────────────────
def _load_author_data(comment_id, repo, issue=False):
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
                    f"repos/{repo}/issues/{comment_id}" if issue else f"repos/{repo}/issues/comments/{comment_id}",
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


def _current_gh_login():
    """Login of the authenticated gh user, or "" when unknown. In test mode
    IDD_EDIT_HELPER_GH_USER stands in for `gh api user` (ignored otherwise)."""
    if os.environ.get("IDD_EDIT_HELPER_TEST_MODE") == "1":
        # Test mode never reaches the network: the current user is whatever the
        # fixture says, or unknown (verify #351 round 2 — R5 fixtures ran gh).
        # The stand-in counts only when the author data is mocked too, so a
        # real author is never paired with a fake identity (round 3).
        if os.environ.get("IDD_EDIT_HELPER_GH_MOCK"):
            return os.environ.get("IDD_EDIT_HELPER_GH_USER", "")
        return ""
    try:
        proc = subprocess.run(["gh", "api", "user", "--jq", ".login"], capture_output=True, text=True)
    except FileNotFoundError:
        return ""
    return proc.stdout.strip() if proc.returncode == 0 else ""


def validate_target_subcmd(argv):
    comment_id = argv[0] if len(argv) >= 1 else ""
    repo = argv[1] if len(argv) >= 2 else ""
    override = argv[2] if len(argv) >= 3 else "false"
    mode = argv[3] if len(argv) >= 4 else ""

    if not comment_id or not repo:
        err("ERROR: validate-target requires <comment-id> <repo> <override>")
        return 2

    # `issue:<N>` checks the issue author (issue-body corrections, #351).
    is_issue = comment_id.startswith("issue:")
    target_num = comment_id[len("issue:"):] if is_issue else comment_id
    if not re.fullmatch(r"[0-9]+", target_num):
        err(f"ERROR: comment-id must be numeric (got: {comment_id})")
        return 2

    ok, code, data = _load_author_data(target_num, repo, issue=is_issue)
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

    # Known-bot allowlist: any *[bot] suffix matches — except for --correct. A
    # review bot's comment is a third party's words; it is answered with an
    # errata comment, never rewritten (verify #351 round 2).
    if login.endswith("[bot]"):
        if mode == "--correct":
            err(
                f"Refuse: {comment_id} was written by {login}, a bot; --correct only "
                "rewrites your own content. Propose the correction with "
                "/idd-comment --type errata instead (#351)."
            )
            return 4
        err(f"✓ Bot author: {login} (skip R5 gate)")
        return 0

    # OWNER passes.
    if assoc == "OWNER":
        err(f"✓ OWNER author: {login} (skip R5 gate)")
        return 0

    # The authenticated user's own content passes whatever the association —
    # in an organization repository a maintainer's own comment is MEMBER, and
    # an OWNER-only gate made --correct unusable there (verify #351 round 1).
    me = _current_gh_login()
    if me and login == me:
        err(f"✓ Own content: {login} ({assoc})")
        return 0

    # --correct has no override (checked before it — verify #351 round 3), and
    # an unknown current user is not a verdict: idd-comment routes errata on
    # this answer, so guessing "someone else" sent your own comment to errata.
    if mode == "--correct":
        if not me:
            err(
                f"ERROR: cannot determine the authenticated gh user, so whether {comment_id} "
                "is your own content is unknown; nothing was changed (check `gh auth status`)."
            )
            return 1
        err(
            f"Refuse: {comment_id} was written by {login} ({assoc}); --correct only "
            "rewrites content by the OWNER or by you. Propose the correction with "
            "/idd-comment --type errata instead (#351)."
        )
        return 4

    # Neither OWNER, a bot, nor you: require override.
    if override == "true":
        err(f"⚠ Override active: editing {login} ({assoc}) content")
        return 0
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


EXIT_PARSER = 8
EXIT_AMBIGUOUS = 9   # the --section heading occurs more than once (round 5)


class ParserUnavailable(Exception):
    """The pinned Markdown parser is missing or a different version."""


class _Blocks:
    """The parser's view of a body, by line index (verify #351 rounds 2–3).

    - opaque:   lines inside a fenced or indented code block or an HTML block;
                nothing there is a heading or a rule.
    - code:     the fenced and indented code lines alone.
    - html_starts: first line of each HTML block (an IDD marker is one).
    - headings: line of each top-level heading → its level, setext included.
    - rules:    lines of top-level thematic breaks (a setext underline is not one).

    Section boundaries come from here, never from `#` at the start of a line:
    the line view ended a section at a `# comment` inside a fence (round 2),
    and at a `## x` inside an HTML comment or a setext underline (round 3).
    The ranges come from the same pinned CommonMark parser gh-egress uses
    (scripts/requirements-egress.txt)."""

    def __init__(self, lines):
        try:
            from markdown_it import MarkdownIt, __version__ as markdown_version
        except ImportError:
            raise ParserUnavailable(
                "markdown-it-py is not installed; install scripts/requirements-egress.txt"
            )
        if markdown_version != "4.0.0":
            raise ParserUnavailable(
                f"markdown-it-py {markdown_version} is not the pinned 4.0.0 "
                "(scripts/requirements-egress.txt)"
            )
        self.opaque, self.code, self.html_starts = set(), set(), set()
        self.headings, self.rules = {}, set()
        self.atx, self.setext = set(), set()
        # Tables on, like the gh-egress scanner: without the rule a GFM table
        # followed by `---` reads as one setext heading (verify #351 round 4).
        for token in MarkdownIt("commonmark").enable("table").parse("\n".join(lines)):
            if token.map is None:
                continue
            if token.type in ("fence", "code_block", "html_block"):
                self.opaque.update(range(*token.map))
                if token.type == "html_block":
                    self.html_starts.add(token.map[0])
                else:
                    self.code.update(range(*token.map))
            elif token.type == "heading_open" and token.level == 0:
                self.headings[token.map[0]] = int(token.tag[1])
                (self.atx if token.markup.startswith("#") else self.setext).add(token.map[0])
            elif token.type == "hr" and token.level == 0:
                self.rules.add(token.map[0])


def _find_heading(lines, heading_line, blocks):
    """Index of the first line equal to heading_line that the parser reads as a
    top-level heading, else None."""
    for i, line in enumerate(lines):
        if line == heading_line and i in blocks.atx:
            return i
    return None


def _heading_count(lines, heading_line, blocks):
    """How many top-level ATX headings equal heading_line. More than one means
    --section cannot say which section it names (round 5: the first one was
    corrected silently)."""
    return sum(1 for i, line in enumerate(lines) if line == heading_line and i in blocks.atx)


def _section_end(lines, start, blocks, stop_at_rule):
    """End (exclusive) of the section headed at `start`: the next top-level
    heading of the same or a higher level; with stop_at_rule also a thematic
    break or a heading managed by another skill."""
    # Only ATX headings delimit sections — the only form --section can name.
    # A setext heading ("text" over "---") would end a section before the text
    # it underlines, leaving that text in place while the run reports success
    # (round 5); check-correction refuses a range that holds one instead.
    level = blocks.headings[start]
    for i in range(start + 1, len(lines)):
        if i in blocks.atx and blocks.headings[i] <= level:
            return i
        if stop_at_rule and (
            i in blocks.rules
            or (i not in blocks.opaque and (lines[i] == _CURRENT_STATUS or lines[i].startswith(_CLARITY_PREFIX)))
        ):
            return i
    return len(lines)


def section_replace_subcmd(argv):
    stop_at_rule = "--stop-at-rule" in argv
    argv = [a for a in argv if a != "--stop-at-rule"]
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

    # Strip CRLF: normalize \r\n and lone \r to \n (closes the CRLF exact-match
    # break — `## Foo\r` != `## Foo`).
    input_text = _read_normalized(input_file)
    repl_text = _read_normalized(replacement_file)

    input_lines = input_text.split("\n")
    # split() yields a trailing "" when the file ends with a newline; track it
    # so the output's trailing-newline shape is preserved.
    trailing_newline = input_text.endswith("\n")
    if trailing_newline and input_lines and input_lines[-1] == "":
        input_lines = input_lines[:-1]

    if not _ATX_HEADING_RE.fullmatch(heading_line):
        err(f"ERROR: not a markdown heading line: {heading_line}")
        return 2
    try:
        blocks = _Blocks(input_lines)
    except ParserUnavailable as e:
        err(f"ERROR: {e}; nothing was replaced")
        return EXIT_PARSER
    if _heading_count(input_lines, heading_line, blocks) > 1:
        err(f"Refuse: '{heading_line}' occurs more than once; nothing was replaced (#351).")
        return EXIT_AMBIGUOUS
    start = _find_heading(input_lines, heading_line, blocks)
    if start is None:
        err(f"ERROR: heading not found in input: {heading_line}")
        return 1
    end = _section_end(input_lines, start, blocks, stop_at_rule)

    # Replacement body lines (preserve internal newlines; drop the trailing
    # empty produced by a final newline so we don't inject a blank line).
    repl_lines = repl_text.split("\n")
    if repl_text.endswith("\n") and repl_lines and repl_lines[-1] == "":
        repl_lines = repl_lines[:-1]

    out = input_lines[: start + 1] + repl_lines + input_lines[end:]
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


BACKUP_ID_RE = re.compile(
    r"(comment-[0-9]+|issue-[0-9]+-body)-[0-9]{8}T[0-9]{6}Z(-[0-9]+)?"
)


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
    backup_day = None
    for kv in rest:
        if "=" not in kv:
            err(f"ERROR: emit-audit-marker arg must be key=value (got: {kv})")
            return 2
        key, _, val = kv.partition("=")
        key = _sanitize_marker_key(key)
        if key == "backup-id":
            m = BACKUP_ID_RE.fullmatch(val)
            if not m:
                err(f"ERROR: backup-id is not a correction backup id (got: {val})")
                return 2
            stamp = re.search(r"-([0-9]{8})T", val).group(1)
            backup_day = f"{stamp[:4]}-{stamp[4:6]}-{stamp[6:]}"
        val = _sanitize_marker_value(val)
        marker += f' {key}="{val}"'
        if key == "date":
            has_date = True

    if not has_date:
        # Same day as the backup id (UTC) when there is one, so the marker and
        # the id never disagree across the Taipei midnight-to-08:00 window.
        marker += f' date="{backup_day or datetime.date.today().isoformat()}"'

    marker += " -->"
    print(marker)
    return 0


# ───────────────────────────────────────────────────────────────────────
# Subcommand: check-correction (protected regions for --correct, #351)
# ───────────────────────────────────────────────────────────────────────
# Closed list of protected regions — do not extend by analogy (spec
# `in-place-correction`, Requirement "Protected regions SHALL NOT be corrected"):
#   1. `## Current Status` and every heading nested inside it  → idd-update
#   2. a heading beginning with `### Clarity Surface`          → idd-clarify
#   (either one as the target, or contained in the target section)
#   3. verbatim blocks: a maximal run of lines starting with `>` in which some
#      line contains `Original text`; it must survive byte-identical.
_CURRENT_STATUS = "## Current Status"
# Closed list of two labels (spec in-place-correction): the idd-issue template's
# `Original text` and the idd-comment decision template's `**Original**`.
_VERBATIM_LABELS = ("Original text", "**Original**")
_CLARITY_PREFIX = "### Clarity Surface"


def _read_normalized(path):
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        return fh.read().replace("\r\n", "\n").replace("\r", "\n")


def _lines_of(text):
    lines = text.split("\n")
    if text.endswith("\n"):
        lines = lines[:-1]
    return lines


def _section_range(lines, heading_line, stop_at_rule=False, blocks=None):
    """(start, end) of the section headed by heading_line, end exclusive, or
    None when absent. Same boundary rule as section-replace."""
    start = _find_heading(lines, heading_line, blocks)
    if start is None:
        return None
    return start, _section_end(lines, start, blocks, stop_at_rule)


def _strip_target_heading(lines, heading):
    """A replacement may start with the target heading; it is the same line, not
    a new heading (check and compose agree on this — round 5)."""
    if heading != "-" and lines and lines[0] == heading:
        return lines[1:]
    return lines


def _line_heading(line):
    """Level of an ATX heading line by plain text, else 0 — the way idd-update
    and idd-clarify find their sections."""
    lvl = _heading_level(line)
    return lvl if 1 <= lvl <= 6 and len(line) > lvl and line[lvl].isspace() else 0


def _managed_ranges(lines):
    """(start, end, owner, heading) for each region another skill owns, found by
    exact line match — fenced or not — because that is how idd-update and
    idd-clarify find them. A region runs to the next ATX heading of the same or
    a higher level (verify #351 round 3: a code-aware view here let an unclosed
    fence hide ## Current Status from the check)."""
    ranges = []
    for i, line in enumerate(lines):
        if line == _CURRENT_STATUS:
            owner = "idd-update"
        elif line.startswith(_CLARITY_PREFIX):
            owner = "idd-clarify"
        else:
            continue
        level = _line_heading(line) or 3
        end = len(lines)
        if owner == "idd-update":
            # idd-update rewrites from its heading to the end of the body.
            ranges.append((i, end, owner, line))
            continue
        for j in range(i + 1, len(lines)):
            lvl = _line_heading(lines[j])
            if lvl and lvl <= level:
                end = j
                break
        ranges.append((i, end, owner, line))
    return ranges


def _verbatim_runs(lines, opaque=frozenset(), offset=0):
    """(block text, the line after it or None, hidden) for each verbatim block;
    hidden = some line of it sits in a code or HTML block (index + offset)."""
    runs, run, first = [], [], 0
    for idx, line in enumerate(lines + [None]):
        if line is not None and line.startswith(">"):
            if not run:
                first = idx
            run.append(line)
            continue
        if run and any(label in r for r in run for label in _VERBATIM_LABELS):
            hidden = any((k + offset) in opaque for k in range(first, idx))
            runs.append(("\n".join(run), line, hidden))
        run = []
    return runs


def _is_marker(line):
    return bool(IDD_MARKER_LINE_RE.fullmatch(line))


def _opening_line(lines):
    """The line readers identify a comment by: the first non-blank line that is
    not an IDD marker (dashboard comments put the marker on line 1)."""
    return next((l for l in lines if l.strip() and not _is_marker(l)), "")


def check_correction_subcmd(argv):
    if len(argv) != 3:
        err("ERROR: check-correction requires <old-file> <section-heading|-> <new-file>")
        return 2
    old_file, heading, new_file = argv
    for f in (old_file, new_file):
        if not os.path.isfile(f) or not os.access(f, os.R_OK):
            err(f"ERROR: file not readable: {f}")
            return 5
    old_lines = _lines_of(_read_normalized(old_file))
    new_lines = _strip_target_heading(_lines_of(_read_normalized(new_file)), heading)
    try:
        blocks = _Blocks(old_lines)
    except ParserUnavailable as e:
        err(f"ERROR: {e}; the correction was not checked")
        return EXIT_PARSER
    if heading != "-" and _heading_count(old_lines, heading, blocks) > 1:
        err(f"Refuse: '{heading}' occurs more than once, so it does not name one section (#351).")
        return EXIT_AMBIGUOUS

    # Line view, fenced or not: idd-update and idd-clarify find their heading by
    # exact line match, so even a fenced copy could be taken for the real one.
    for line in new_lines:
        if line.startswith(_CURRENT_STATUS) or line.startswith(_CLARITY_PREFIX):
            err(
                f"Refuse: the replacement introduces '{line}', a heading managed by "
                f"{'idd-update' if line.startswith(_CURRENT_STATUS) else 'idd-clarify'} (#351)."
            )
            return 6
    try:
        new_blocks = _Blocks(new_lines)
    except ParserUnavailable as e:
        err(f"ERROR: {e}; the correction was not checked")
        return EXIT_PARSER

    if heading == "-":
        start, end = 0, len(old_lines)
    else:
        rng = _section_range(old_lines, heading, stop_at_rule=True, blocks=blocks)
        if rng is None:
            err(f"ERROR: heading not found in input: {heading}")
            return 1
        start, end = rng
        if any(i in blocks.setext for i in range(start + 1, end)):
            err(
                "Refuse: the section holds a setext heading (a line of text over '---' or "
                "'==='), so where it ends is ambiguous; put a blank line before the '---' or "
                "make it an ATX heading, then correct (#351)."
            )
            return 6
        # A heading of the target's level or higher, or a thematic break, would
        # split the section: the next correction would reach only part of it.
        level = blocks.headings[start]
        if any(lvl <= level for lvl in new_blocks.headings.values()) or new_blocks.rules:
            err(
                "Refuse: the replacement adds a heading of the section's level or higher, "
                "or a thematic break, which would split the corrected section (#351)."
            )
            return 6
    # The protection scan reads lines the way the owners do. A whole-comment
    # target contains every managed region in it (round 2); a nested heading
    # under Clarity Surface belongs to idd-clarify (round 3).
    managed = _managed_ranges(old_lines)
    for idx in range(start, end):
        for m_start, m_end, who, m_heading in managed:
            if m_start <= idx < m_end:
                what = "comment" if heading == "-" else "section"
                where = "is" if idx == m_start == start else ("is inside" if idx == start else "contains")
                err(
                    f"Refuse: the target {what} {where} '{m_heading}', which is managed by "
                    f"{who}; update it with {who} instead of --correct (#351)."
                )
                return 6

    if heading == "-":
        # Other skills find a comment by its opening heading (## Diagnosis,
        # ## Implementation Complete, …); a whole-comment correction keeps it.
        old_first = _opening_line(old_lines)
        new_first = _opening_line(new_lines)
        if _line_heading(old_first) and new_first != old_first:
            err(
                f"Refuse: the comment opens with '{old_first}', which other skills use "
                "to recognise it; keep it as the first line of the replacement (#351)."
            )
            return 6
    else:
        start += 1  # the heading line itself is kept

    old_runs = _verbatim_runs(old_lines[start:end], blocks.opaque, start)
    new_runs = _verbatim_runs(new_lines, new_blocks.opaque)
    if sorted(b for b, _, _ in old_runs) != sorted(b for b, _, _ in new_runs):
        # Multiset equality, not substring: appending to a quote, adding a quote
        # line, or un-quoting it all used to pass (verify #351 round 1).
        for block, _, _ in old_runs or new_runs:
            first = block.split("\n", 1)[0]
            err(
                "Refuse: the replacement does not preserve an Original text quotation "
                f"byte-for-byte (block starting '{first[:60]}'). Original-source "
                "quotations are verbatim-preserve; keep the block and correct the "
                "text around it (#351)."
            )
            return 6
    # A non-blank line right after the quotation joins it as a lazy
    # continuation, so the rendered quote changes while the bytes match
    # (verify #351 round 3). Allowed only where the original already had it.
    old_follow = {(b, f) for b, f, _ in old_runs}
    old_hidden = {b for b, _, h in old_runs if h}
    for block, _, hidden in new_runs:
        if hidden and block not in old_hidden:
            err(
                "Refuse: the replacement moves an Original text quotation into a code "
                "block or an HTML comment, where it no longer shows (#351)."
            )
            return 6
    for block, follow, _ in new_runs:
        if follow is not None and follow.strip() and (block, follow) not in old_follow:
            err(
                "Refuse: the line after an Original text quotation would join the "
                "quotation when rendered; leave a blank line after it (#351)."
            )
            return 6
    return 0


# The marker emit-audit-marker writes for --correct. Earlier markers in the
# replaced region are carried forward, so a second correction of the same
# section keeps the first backup id reachable (verify #351 round 2).
CORRECT_MARKER_RE = re.compile(
    r'<!-- idd:edit mode="correct" backup-id="[^"]*"(?: [a-z-]+="[^"]*")* -->'
)
# Any whole-line IDD marker (idd:edit, idd:comment, idd:dashboard, …). Other
# skills find comments by these, so a correction carries them forward.
IDD_MARKER_LINE_RE = re.compile(r"<!-- idd:[^\n]*-->")


def _compose(old_file, heading, body_file, marker):
    """Print the full corrected body: the section (or whole comment) replaced
    by the new text, the IDD markers it held, and the new marker last. The
    skill shows this exact text at confirmation and PATCHes it afterwards, so
    the preview is the write (verify #351 round 2)."""
    for f in (old_file, body_file):
        if not os.path.isfile(f) or not os.access(f, os.R_OK):
            err(f"ERROR: file not readable: {f}")
            return 5, None
    if not CORRECT_MARKER_RE.fullmatch(marker):
        err("ERROR: the marker must be one emit-audit-marker wrote for mode=correct")
        return 2, None
    old_lines = _lines_of(_read_normalized(old_file))
    body_lines = _read_normalized(body_file).split("\n")
    while body_lines and body_lines[-1].strip() == "":
        body_lines.pop()
    try:
        blocks = _Blocks(old_lines)
    except ParserUnavailable as e:
        err(f"ERROR: {e}; nothing was composed")
        return EXIT_PARSER, None

    if heading == "-":
        # Markers at the top stay at the top: a dashboard comment's first line
        # is its marker (verify #351 round 4).
        lead = 0
        while lead < len(old_lines) and (_is_marker(old_lines[lead]) or not old_lines[lead].strip()):
            lead += 1
        head = [l for l in old_lines[:lead] if _is_marker(l)]
        start, end = lead - 1, len(old_lines)
        tail = []
    else:
        if _heading_count(old_lines, heading, blocks) > 1:
            err(f"Refuse: '{heading}' occurs more than once (#351).")
            return EXIT_AMBIGUOUS, None
        rng = _section_range(old_lines, heading, stop_at_rule=True, blocks=blocks)
        if rng is None:
            err(f"ERROR: heading not found in input: {heading}")
            return 1, None
        start, end = rng
        # A replacement that starts with the target heading would print it twice.
        body_lines = _strip_target_heading(body_lines, heading)
        head, tail = old_lines[: start + 1], old_lines[end:]
    # Line view, like the owners of these markers: every IDD marker line in the
    # replaced region is kept once, before the new marker.
    try:
        body_blocks = _Blocks(body_lines)
    except ParserUnavailable as e:
        err(f"ERROR: {e}; nothing was composed")
        return EXIT_PARSER, None
    # A marker inside a fenced example is text, not a marker (round 4): it is
    # neither carried nor allowed to stand in for a live one.
    in_body = {l for i, l in enumerate(body_lines) if i not in body_blocks.code}
    if heading == "-":
        # A top marker the replacement repeats stays where the replacement puts it.
        head = [l for l in head if l not in in_body]
    carried = []
    for i in range(start + 1, end):
        line = old_lines[i]
        if (_is_marker(line) and i not in blocks.code and line not in in_body
                and line not in carried and line != marker and line not in head):
            carried.append(line)
    region = body_lines + [""] + carried + [marker]
    out = head + region + ([""] + tail if tail else [])

    # Invariant: nothing outside the replaced region may change how it parses,
    # and every marker must still be a marker — outside code, and the first line
    # of its own HTML block (a marker is an HTML comment, so an unclosed `<!--`
    # before it would swallow it). A replacement that leaves a fence or an HTML
    # comment open fails this (verify #351 round 3).
    try:
        new_blocks = _Blocks(out)
    except ParserUnavailable as e:
        err(f"ERROR: {e}; nothing was composed")
        return EXIT_PARSER, None
    marker_lines = range(len(head) + len(body_lines) + 1, len(head) + len(region))
    broken = any(i in new_blocks.code or i not in new_blocks.html_starts for i in marker_lines)
    tail_at = len(head) + len(region) + 1
    for k in range(len(tail)):
        o, n = end + k, tail_at + k
        if (o in blocks.opaque) != (n in new_blocks.opaque) or (o in blocks.headings) != (n in new_blocks.headings):
            broken = True
            break
    if broken:
        err(
            "Refuse: the replacement leaves a code block or an HTML comment open, so "
            "the marker or the text after the corrected region would render as code. "
            "Close it and try again (#351)."
        )
        return 6, None
    return 0, "\n".join(out) + "\n"



def compose_correction_subcmd(argv):
    if len(argv) != 4:
        err("ERROR: compose-correction requires <old-file> <section-heading|-> <body-file> <marker>")
        return 2
    rc, text = _compose(*argv)
    if rc == 0:
        sys.stdout.write(text)
    return rc

def existing_mentions_subcmd(argv):
    """Logins the target already mentions, found exactly the way gh-egress finds
    them (its parser, then its token pattern). They were published already, so
    keeping them in an edit notifies no one new; the skill attests them and
    gh-egress still refuses any mention the correction adds (round 3)."""
    if len(argv) != 1 or not os.path.isfile(argv[0]):
        err("ERROR: existing-mentions requires <file>")
        return 2
    ok, logins = _existing_mentions(argv[0])
    if not ok:
        return 1
    print(logins)
    return 0


def _existing_mentions(path):
    """(True, "a,b") with the logins `path` already mentions, or (False, "")."""
    scanner = os.path.join(os.path.dirname(os.path.abspath(__file__)), "lib", "mention_scan_text.py")
    with open(path, "rb") as fh:
        data = fh.read()
    proc = subprocess.run([sys.executable, scanner], input=data, capture_output=True)
    if proc.returncode != 0:
        err("ERROR: the mention scan failed (install scripts/requirements-egress.txt)")
        return False, ""
    text = proc.stdout.decode("utf-8", errors="replace")
    logins = sorted({m for m in re.findall(r"(?:^|[^A-Za-z0-9_])@([A-Za-z0-9][A-Za-z0-9-]*)", text)})
    return True, ",".join(logins)


# ───────────────────────────────────────────────────────────────────────
# Subcommands: correct-prepare / correct-apply / correct-discard (#351)
# ───────────────────────────────────────────────────────────────────────
# The whole --correct flow lives here, not in SKILL.md bash: four verify rounds
# kept finding defects in a bash flow whose only tests were string contracts
# (same class as #154 → #155). The skill now runs prepare, shows the preview,
# then runs apply or discard; scripts/tests/correct-flow runs it end to end.
#
# stdout carries only KEY=value lines: WORK / PREVIEW / STATE from prepare;
# RESULT (edited | refused | write-failed | unverified), REASON, BACKUP_ID, URL
# from apply. Exit codes: 0 done, 2 usage, 3 scope error (prepare), 4 not done
# (RESULT/REASON say why; a failed write too), 5 body file refused, 7 written
# but not confirmed on read-back.
CORRECT_WORK_PREFIX = "idd-correct-"
PLACEHOLDER_MARKER = '<!-- idd:edit mode="correct" backup-id="(assigned after confirmation)" -->'
_TARGET_RE = re.compile(r"(comment|issue):([0-9]+)")
_SCRUB_LEVELS = ("enforce", "warn", "light")


def _sha256(path):
    import hashlib
    with open(path, "rb") as fh:
        return hashlib.sha256(fh.read()).hexdigest()


def _gh(args):
    try:
        return subprocess.run(["gh"] + args, capture_output=True)
    except FileNotFoundError:
        return None


def _endpoint(kind, num, repo):
    return f"repos/{repo}/issues/comments/{num}" if kind == "comment" else f"repos/{repo}/issues/{num}"


def _fetch_body(endpoint, dest):
    """The target's body, byte for byte. `--jq .body` prints text plus a
    newline, so the archive and restore were not exact (round 5); the JSON is
    decoded here instead."""
    proc = _gh(["api", endpoint])
    if proc is None or proc.returncode != 0:
        return False
    try:
        body = json.loads(proc.stdout.decode("utf-8")).get("body") or ""
    except (ValueError, AttributeError):
        return False
    with open(dest, "w", encoding="utf-8", newline="") as fh:
        fh.write(body)
    return True


def _egress(args):
    """Run gh-egress.sh; its stdout goes to our stderr so stdout keeps only the
    KEY=value lines. Returns the exit code."""
    script = os.path.join(os.path.dirname(os.path.abspath(__file__)), "gh-egress.sh")
    proc = subprocess.run(["bash", script] + args, stdout=subprocess.PIPE)
    if proc.stdout:
        sys.stderr.write(proc.stdout.decode("utf-8", errors="replace"))
    return proc.returncode


def _correct_marker(backup_id):
    stamp = re.search(r"-([0-9]{8})T", backup_id).group(1)
    return f'<!-- idd:edit mode="correct" backup-id="{backup_id}" date="{stamp[:4]}-{stamp[4:6]}-{stamp[6:]}" -->'


def _refused(reason, work=None, extra=()):
    if work:
        shutil.rmtree(work, ignore_errors=True)
    print("RESULT=refused")
    print(f"REASON={reason}")
    for line in extra:
        print(line)
    return 4


def _mention_args(mentions):
    return [f"--mention-attested={mentions}"] if mentions else []


def correct_prepare_subcmd(argv):
    target, rest = _take_flag(argv, "--target")
    repo, rest = _take_flag(rest, "--repo")
    section, rest = _take_flag(rest, "--section")
    scope, rest = _take_flag(rest, "--scope")
    body_file, rest = _take_flag(rest, "--body-file")
    scrub, rest = _take_flag(rest, "--scrub-attested")
    scrub = scrub or "warn"
    m = _TARGET_RE.fullmatch(target or "")
    if rest or not m or not repo or not body_file or not _REPO_RE.fullmatch(repo) or ".." in repo:
        err("ERROR: correct-prepare requires --target comment:<id>|issue:<n> --repo <owner/repo> "
            "(--section <heading> | --scope whole-comment) --body-file <path> [--scrub-attested <level>]")
        return 2
    kind, num = m.group(1), m.group(2)
    if bool(section) == bool(scope) or (scope and scope != "whole-comment"):
        err("Refuse: pass exactly one of --section <heading> or --scope whole-comment")
        return 3
    if kind == "issue" and scope:
        err("Refuse: an issue-body correction requires --section <heading> (#351).")
        return 3
    if section and not _ATX_HEADING_RE.fullmatch(section):
        err(f"ERROR: --section must be a markdown heading line (got: {section})")
        return 2
    if scrub not in _SCRUB_LEVELS:
        err(f"ERROR: --scrub-attested must be one of {', '.join(_SCRUB_LEVELS)}")
        return 2
    ok, code, content = read_body_file(body_file)
    if not ok:
        return code
    if not content.strip():
        err("Refuse: --correct needs the corrected text; the body file is empty (#351).")
        return 2

    _remove_stale_work_dirs()
    # The archive must be writable before the user is asked to confirm
    # (round 5: a non-git cwd was refused only after confirmation).
    problem = _archive_preflight()
    if problem:
        err(f"Refuse: {problem}; nothing was prepared (#351).")
        return _refused("archive")
    work = tempfile.mkdtemp(prefix=CORRECT_WORK_PREFIX)   # mode 0700
    backup, body, preview = (os.path.join(work, n) for n in ("backup.md", "body.md", "preview.md"))
    with open(body, "w", encoding="utf-8") as fh:
        fh.write(content)
    endpoint = _endpoint(kind, num, repo)
    # Read first: a target that cannot be read is fetch-failed, not an author
    # question.
    if not _fetch_body(endpoint, backup):
        err(f"✗ cannot read {target} — nothing changed")
        return _refused("fetch-failed", work)
    rc = validate_target_subcmd([num if kind == "comment" else f"issue:{num}", repo, "false", "--correct"])
    if rc != 0:
        return _refused({4: "R5", 1: "author-unknown"}.get(rc, "check-failed"), work)
    heading = section or "-"
    rc = check_correction_subcmd([backup, heading, body])
    if rc != 0:
        return _refused(_CHECK_REASONS.get(rc, "check-failed"), work)
    rc, text = _compose(backup, heading, body, PLACEHOLDER_MARKER)
    if rc != 0:
        return _refused(_CHECK_REASONS.get(rc, "check-failed"), work)
    with open(preview, "w", encoding="utf-8") as fh:
        fh.write(text)
    ok, mentions = _existing_mentions(backup)
    if not ok:
        return _refused("egress", work)
    # The egress gates run before the preview, so a body gh-egress would refuse
    # is never confirmed or archived (round 3). Mentions the target already had
    # were published already; a mention the correction adds is still refused.
    if _egress(["check", "--body-file", preview, "--scrub-attested", scrub] + _mention_args(mentions)) != 0:
        return _refused("egress", work)
    state = {
        "target": target, "kind": kind, "num": num, "repo": repo, "heading": heading,
        "scrub": scrub, "mentions": mentions,
        "sha": {n: _sha256(os.path.join(work, n)) for n in ("backup.md", "body.md", "preview.md")},
    }
    state_path = os.path.join(work, "state.json")
    with open(state_path, "w", encoding="utf-8") as fh:
        json.dump(state, fh)
    print(f"WORK={work}")
    print(f"PREVIEW={preview}")
    # The caller keeps this hash and hands it back to apply: the binding to what
    # the user confirmed lives outside the working directory (round 5).
    print(f"STATE={_sha256(state_path)}")
    return 0


_CHECK_REASONS = {6: "protected", 1: "section-not-found", EXIT_PARSER: "parser-unavailable",
                  EXIT_AMBIGUOUS: "section-ambiguous"}


def _archive_preflight():
    """Why the archive could not be written from here, or None."""
    root = _main_worktree()
    if root is None:
        return "the correction archive needs a git work tree; run from inside the repository clone"
    problem = _archive_path_problem(root) or _tracks_archive(root)
    if problem:
        return problem
    return _ensure_ignored(root, os.path.join(ARCHIVE_REL, "preflight.md"))


def _remove_stale_work_dirs(max_age=86400):
    """Working directories left by a run that never reached apply or discard
    (a closed session) hold the uncorrected text; drop those older than a day."""
    tmp = os.path.realpath(tempfile.gettempdir())
    try:
        names = os.listdir(tmp)
    except OSError:
        return
    now = datetime.datetime.now().timestamp()
    for name in names:
        if not name.startswith(CORRECT_WORK_PREFIX):
            continue
        path = os.path.join(tmp, name)
        try:
            st = os.lstat(path)
        except OSError:
            continue
        if st.st_uid == os.getuid() and not os.path.islink(path) and now - st.st_mtime > max_age:
            shutil.rmtree(path, ignore_errors=True)


def _state_problem(state):
    """Why a state.json cannot be trusted as prepare wrote it, or None."""
    m = _TARGET_RE.fullmatch(str(state.get("target", "")))
    if not m or m.group(1) != state.get("kind") or m.group(2) != state.get("num"):
        return "the prepared target is malformed"
    repo = str(state.get("repo", ""))
    if not _REPO_RE.fullmatch(repo) or ".." in repo:
        return "the prepared repository is malformed"
    heading = state.get("heading")
    if heading != "-" and not _ATX_HEADING_RE.fullmatch(str(heading)):
        return "the prepared section is malformed"
    if state.get("scrub") not in _SCRUB_LEVELS or not re.fullmatch(r"[A-Za-z0-9,-]*", str(state.get("mentions", ""))):
        return "the prepared egress settings are malformed"
    return None


def _own_work_dir(work):
    """The working directory prepare made, else None: a direct child of this
    user's temp directory with the prefix, a real directory owned by this user
    and closed to others, holding state.json."""
    if not work:
        return None
    real = os.path.realpath(work)
    if (os.path.dirname(real) != os.path.realpath(tempfile.gettempdir())
            or not os.path.basename(real).startswith(CORRECT_WORK_PREFIX)
            or os.path.islink(work)):
        return None
    try:
        st = os.lstat(real)
    except OSError:
        return None
    if st.st_uid != os.getuid() or st.st_mode & 0o077 or not os.path.isfile(os.path.join(real, "state.json")):
        return None
    return real


def correct_discard_subcmd(argv):
    work, rest = _take_flag(argv, "--work")
    real = _own_work_dir(work)
    if rest or real is None:
        err("ERROR: correct-discard requires --work <the WORK directory correct-prepare printed>")
        return 2
    shutil.rmtree(real, ignore_errors=True)
    return 0


def correct_apply_subcmd(argv):
    work, rest = _take_flag(argv, "--work")
    state_sha, rest = _take_flag(rest, "--state")
    real = _own_work_dir(work)
    if rest or real is None or not state_sha or not re.fullmatch(r"[0-9a-f]{64}", state_sha):
        err("ERROR: correct-apply requires --work <WORK> --state <STATE>, both as correct-prepare printed them")
        return 2
    try:
        return _correct_apply(real, state_sha)
    finally:
        # The working copies hold the wrong text; nothing of them outlives apply.
        shutil.rmtree(real, ignore_errors=True)


def _correct_apply(work, state_sha):
    state_path = os.path.join(work, "state.json")
    if _sha256(state_path) != state_sha:
        err("✗ the prepared state changed after the preview — nothing archived or written")
        return _refused("differs-from-preview")
    with open(state_path, encoding="utf-8") as fh:
        state = json.load(fh)
    problem = _state_problem(state)
    if problem:
        err(f"✗ {problem} — nothing archived or written")
        return _refused("differs-from-preview")
    backup, body, preview = (os.path.join(work, n) for n in ("backup.md", "body.md", "preview.md"))
    for name in ("backup.md", "body.md", "preview.md"):
        path = os.path.join(work, name)
        if not os.path.isfile(path) or _sha256(path) != state["sha"][name]:
            err(f"✗ {name} changed after the preview — nothing archived or written")
            return _refused("differs-from-preview")
    kind, num, repo, heading = state["kind"], state["num"], state["repo"], state["heading"]
    endpoint = _endpoint(kind, num, repo)
    current = os.path.join(work, "current.md")
    if not _fetch_body(endpoint, current):
        err(f"✗ cannot re-read {state['target']} — nothing archived or written")
        return _refused("fetch-failed")
    if _sha256(current) != state["sha"]["backup.md"]:
        err(f"✗ {state['target']} changed since the preview — nothing archived or written; run again to see the new version")
        return _refused("changed-since-preview")
    # The gates run again on what is about to be written, not only at prepare.
    rc = validate_target_subcmd([num if kind == "comment" else f"issue:{num}", repo, "false", "--correct"])
    if rc != 0:
        return _refused({4: "R5", 1: "author-unknown"}.get(rc, "check-failed"))
    rc = check_correction_subcmd([backup, heading, body])
    if rc != 0:
        return _refused(_CHECK_REASONS.get(rc, "check-failed"))
    rc, text = _compose(backup, heading, body, PLACEHOLDER_MARKER)
    with open(preview, encoding="utf-8") as fh:
        if rc != 0 or text != fh.read():
            return _refused("differs-from-preview")
    with open(backup, "rb") as fh:
        rc, backup_id = _archive_write(kind, num, fh.read(), repo)
    if rc != 0:
        return _refused("archive")
    rc, new_text = _compose(backup, heading, body, _correct_marker(backup_id))
    if rc != 0:
        return _refused("replace", extra=(f"BACKUP_ID={backup_id}",))
    new_file = os.path.join(work, "new.md")
    with open(new_file, "w", encoding="utf-8") as fh:
        fh.write(new_text)
    verb = ["edit-comment", num] if kind == "comment" else ["edit", num]
    rc = _egress(verb + ["--repo", repo, "--body-file", new_file, "--scrub-attested", state["scrub"]]
                 + _mention_args(state["mentions"]))
    if rc >= 10:
        return _refused("egress", extra=(f"BACKUP_ID={backup_id}",))
    if rc != 0:
        # A failed call does not prove nothing was written: read it back (round 5).
        after = os.path.join(work, "after-failure.md")
        if _fetch_body(endpoint, after) and _sha256(after) == state["sha"]["backup.md"]:
            err(f"✗ gh failed the write for {state['target']} (rc={rc}); re-read shows it unchanged. The archive {backup_id} stays.")
            print("RESULT=write-failed")
            print(f"RC={rc}")
            print(f"BACKUP_ID={backup_id}")
            return 4
        err(f"⚠ gh reported a failed write for {state['target']} (rc={rc}), but the target no longer reads as before — check it by hand")
        print("RESULT=unverified")
        print(f"BACKUP_ID={backup_id}")
        return 7
    readback = os.path.join(work, "readback.md")
    def _norm(s):
        return s.replace("\r\n", "\n").rstrip("\n")
    confirmed = _fetch_body(endpoint, readback)
    if confirmed:
        with open(readback, encoding="utf-8", errors="replace") as fh:
            confirmed = _norm(fh.read()) == _norm(new_text)
    if not confirmed:
        err(f"⚠ {state['target']} was written but does not read back as sent — check it by hand")
        print("RESULT=unverified")
        print(f"BACKUP_ID={backup_id}")
        return 7
    proc = _gh(["api", endpoint, "--jq", ".html_url"])
    url = proc.stdout.decode("utf-8", errors="replace").strip() if proc is not None and proc.returncode == 0 else ""
    print("RESULT=edited")
    print(f"BACKUP_ID={backup_id}")
    print(f"URL={url}")
    return 0


def _main_worktree():
    """The main worktree's root (parent of the common git dir), so that an
    archive written from a linked worktree survives `git worktree remove`."""
    proc = _git(["rev-parse", "--path-format=absolute", "--git-common-dir"])
    if proc is None or proc.returncode != 0:
        return None
    common = proc.stdout.strip()
    if os.path.basename(common.rstrip(os.sep)) == ".git":
        return os.path.dirname(common.rstrip(os.sep))
    return _git_toplevel()


# ───────────────────────────────────────────────────────────────────────
# Subcommands: archive / restore (correction archive, #351)
# ───────────────────────────────────────────────────────────────────────
# Prior versions of corrected targets live under ARCHIVE_REL in the git work
# tree. Three guarantees (spec `correction-archive`):
#   - never tracked: the dir is written to .git/info/exclude and checked with
#     `git check-ignore` before any write (exit 7 otherwise — a tracked archive
#     would ride into review diffs, where no hook can stop an AI reading it);
#   - unreadable at rest: files are chmod 0000 right after the write, so
#     recursive reads that never spell the path (`grep -r .`) get nothing;
#   - never displayed: archived bytes never reach stdout or stderr.
ARCHIVE_REL = os.path.join(".claude", ".idd", "archive", "edits")
ARCHIVE_IGNORE_PATTERN = ".claude/.idd/archive/"
ARCHIVE_EXCLUDE_MARKER = "IDD correction archive (#351)"
_REPO_RE = re.compile(r"[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+")
_MAX_COLLISIONS = 1000


def _git(args, cwd=None):
    try:
        return subprocess.run(["git"] + args, cwd=cwd, capture_output=True, text=True)
    except FileNotFoundError:
        return None


def _git_toplevel():
    proc = _git(["rev-parse", "--show-toplevel"])
    if proc is None or proc.returncode != 0:
        return None
    return proc.stdout.strip() or None


def _now_utc():
    override = os.environ.get("IDD_EDIT_HELPER_NOW")
    if override:
        if os.environ.get("IDD_EDIT_HELPER_TEST_MODE") != "1":
            err("ERROR: IDD_EDIT_HELPER_NOW is a test-only hook; refuses in production.")
            return None
        try:
            return datetime.datetime.strptime(override, "%Y-%m-%dT%H:%M:%SZ")
        except ValueError:
            err(f"ERROR: IDD_EDIT_HELPER_NOW must be YYYY-MM-DDTHH:MM:SSZ (got: {override})")
            return None
    return datetime.datetime.now(datetime.timezone.utc)


def _take_flag(argv, flag):
    """Split `flag value` / `flag=value` out of argv → (value or None, rest).
    A missing value or a value starting with '--' yields value "" (usage error)."""
    rest, value, i = [], None, 0
    while i < len(argv):
        a = argv[i]
        if a == flag:
            nxt = argv[i + 1] if i + 1 < len(argv) else ""
            value = "" if nxt.startswith("--") else nxt
            i += 2 if value else 1
            continue
        if a.startswith(flag + "="):
            value = a.partition("=")[2]
            i += 1
            continue
        rest.append(a)
        i += 1
    return value, rest


def _ensure_ignored(toplevel, rel_path):
    """Write the exclude block and confirm rel_path is ignored. Returns an
    error message, or None when the path is ignored."""
    proc = _git(["rev-parse", "--git-path", "info/exclude"], cwd=toplevel)
    if proc is None or proc.returncode != 0:
        return "cannot locate .git/info/exclude"
    exclude = proc.stdout.strip()
    if not os.path.isabs(exclude):
        exclude = os.path.join(toplevel, exclude)
    os.makedirs(os.path.dirname(exclude), exist_ok=True)
    block = os.path.join(os.path.dirname(os.path.abspath(__file__)), "git-ignore-block.sh")
    proc = subprocess.run(
        ["bash", block, "--target", exclude, "--marker", ARCHIVE_EXCLUDE_MARKER,
         "--direction", "exclude", "--", ARCHIVE_IGNORE_PATTERN],
        capture_output=True, text=True,
    )
    if proc.returncode != 0:
        return f"git-ignore-block failed: {proc.stderr.strip()}"
    proc = _git(["check-ignore", "-q", "--", rel_path], cwd=toplevel)
    if proc is None or proc.returncode != 0:
        return (
            f"{rel_path} is not ignored by git after writing .git/info/exclude "
            "(a .gitignore rule re-includes it?)"
        )
    return None


def _archive_path_problem(root):
    """A symlink on any directory between the work tree and the archive would
    let a cloned repository point restore at files it ships, or send an
    archive write elsewhere (verify #351 round 2: only the last component was
    checked). Returns a message, or None when every level is a real directory
    or absent."""
    cur = root
    for part in ARCHIVE_REL.split(os.sep):
        cur = os.path.join(cur, part)
        if os.path.islink(cur):
            return f"{os.path.relpath(cur, root)} is a symlink"
        # A nested repository (a submodule at .claude, say) tracks files that
        # the superproject's `git ls-files` never lists (round 3).
        if os.path.lexists(os.path.join(cur, ".git")):
            return f"{os.path.relpath(cur, root)} is inside a nested git repository"
    return None


def _tracks_archive(root):
    """A message when the repository tracks anything under the archive path in
    any letter case, else None. A case-insensitive filesystem resolves
    .claude/... to a tracked .CLAUDE/... that ls-files does not match by name
    (round 3); archive refuses too, or it would hand out an id restore rejects
    (round 4)."""
    listing = _git(["ls-files", "-z"], cwd=root)
    if listing is None or listing.returncode != 0:
        return "cannot list tracked files to confirm the archive path is untracked"
    prefix = ARCHIVE_IGNORE_PATTERN.casefold()
    if any(p.casefold().startswith(prefix) for p in listing.stdout.split("\0") if p):
        return "the repository tracks files under the archive path"
    return None


def _is_ignored(root, rel_path):
    proc = _git(["check-ignore", "-q", "--", rel_path], cwd=root)
    return proc is not None and proc.returncode == 0


def archive_subcmd(argv):
    from_file, rest = _take_flag(argv, "--from-file")
    repo, rest = _take_flag(rest, "--repo")
    if len(rest) != 2 or not from_file or not repo:
        err("ERROR: archive requires <comment|issue> <id> --from-file <path> --repo <owner/repo>")
        return 2
    kind, target_id = rest
    if kind not in ("comment", "issue"):
        err(f"ERROR: archive target kind must be 'comment' or 'issue' (got: {kind})")
        return 2
    if not re.fullmatch(r"[0-9]+", target_id):
        err(f"ERROR: archive target id must be numeric (got: {target_id})")
        return 2
    if not _REPO_RE.fullmatch(repo) or ".." in repo:
        err(f"ERROR: --repo must be <owner>/<repo> (got: {repo})")
        return 2
    # Same sensitive-path gate as --body-file (#155): archive + restore would
    # otherwise carry any readable local file to GitHub (verify #351 round 1).
    ok, code = validate_body_file_path(from_file)
    if not ok:
        return code
    if not os.path.isfile(from_file) or not os.access(from_file, os.R_OK):
        err(f"ERROR: --from-file not readable: {from_file}")
        return 5
    with open(from_file, "rb") as fh:
        data = fh.read()
    rc, backup_id = _archive_write(kind, target_id, data, repo)
    if rc == 0:
        print(backup_id)
    return rc


def _archive_write(kind, target_id, data, repo):
    """Write `data` as the archive entry for a target; (0, backup_id) or
    (code, None) after printing the reason. Called in-process by correct-apply,
    so the working copy never goes through the --from-file gate (round 4)."""
    now = _now_utc()
    if now is None:
        return 2, None

    root = _main_worktree()
    if root is None:
        err("Refuse: the correction archive needs a git work tree; run from inside the repository clone (#351).")
        return 7, None
    problem = _archive_path_problem(root) or _tracks_archive(root)
    if problem:
        err(f"Refuse: {problem}; nothing was written (#351).")
        return 7, None
    prefix = f"comment-{target_id}" if kind == "comment" else f"issue-{target_id}-body"
    base_id = f"{prefix}-{now.strftime('%Y%m%dT%H%M%SZ')}"
    problem = _ensure_ignored(root, os.path.join(ARCHIVE_REL, base_id + ".md"))
    if problem:
        err(f"Refuse: {problem}. The archive must never be tracked; nothing was written (#351).")
        return 7, None

    archive_dir = os.path.join(root, ARCHIVE_REL)
    try:
        os.makedirs(archive_dir, mode=0o700, exist_ok=True)
    except OSError as e:
        err(f"Refuse: cannot create the archive directory: {e.strerror}")
        return 7, None
    for n in range(1, _MAX_COLLISIONS + 1):
        backup_id = base_id if n == 1 else f"{base_id}-{n}"
        rel = os.path.join(ARCHIVE_REL, backup_id + ".md")
        path = os.path.join(root, rel)
        side = path[:-3] + ".repo"
        # Both names must be free: an orphan or symlinked sidecar is never
        # written through (verify #351 round 3).
        if os.path.lexists(path) or os.path.lexists(side):
            continue
        # Every name actually written is checked, not only the base name: a
        # rule can re-include `<id>-2.md` alone (verify #351 round 1).
        if not _is_ignored(root, rel) or not _is_ignored(root, rel[:-3] + ".repo"):
            err(f"Refuse: {rel} is not ignored by git. The archive must never be tracked; nothing was written (#351).")
            return 7, None
        try:
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError:
            continue
        except OSError as e:
            err(f"Refuse: cannot create the archive file: {e.strerror}")
            return 7, None
        try:
            sfd = os.open(side, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError:
            os.close(fd)
            os.remove(path)
            continue
        except OSError as e:
            os.close(fd)
            os.remove(path)
            err(f"Refuse: cannot create the archive sidecar: {e.strerror}")
            return 7, None
        try:
            with os.fdopen(fd, "wb") as out:
                out.write(data)
            with os.fdopen(sfd, "w", encoding="utf-8") as side_fh:
                side_fh.write(repo)
            os.chmod(path, 0)
        except OSError as e:
            for leftover in (path, side):
                try:
                    os.chmod(leftover, 0o600)
                    os.remove(leftover)
                except OSError:
                    pass
            err(f"Refuse: writing the archive file failed: {e.strerror}")
            return 7, None
        return 0, backup_id
    err(f"Refuse: more than {_MAX_COLLISIONS} archives share the id {base_id}")
    return 7, None


def restore_subcmd(argv):
    repo, rest = _take_flag(argv, "--repo")
    if len(rest) != 1 or not repo:
        err("ERROR: restore requires <backup-id> --repo <owner/repo>")
        return 2
    backup_id = rest[0]
    m = BACKUP_ID_RE.fullmatch(backup_id)
    if not m:
        err(f"ERROR: not a correction backup id: {backup_id}")
        return 2
    if not _REPO_RE.fullmatch(repo) or ".." in repo:
        err(f"ERROR: --repo must be <owner>/<repo> (got: {repo})")
        return 2
    root = _main_worktree()
    if root is None:
        err("Refuse: restore needs the git work tree that holds the archive.")
        return 7
    problem = _archive_path_problem(root)
    if problem:
        err(f"Refuse: {problem}, so this helper did not write the entry; nothing was read.")
        return 2
    rel = os.path.join(ARCHIVE_REL, backup_id + ".md")
    path = os.path.join(root, rel)
    if not os.path.lexists(path):
        err(f"ERROR: no archive entry named {backup_id}")
        return 5
    # Only entries this helper wrote are restored: a regular file, not a
    # symlink, untracked, with a sidecar naming this repo. A cloned repository
    # can ship a tracked symlink here (verify #351 round 1).
    if os.path.islink(path) or not os.path.isfile(path):
        err(f"Refuse: {backup_id} is not a regular archive file; nothing was read.")
        return 2
    tracked = _git(["ls-files", "--error-unmatch", "--", rel], cwd=root)
    if tracked is not None and tracked.returncode == 0:
        err(f"Refuse: {backup_id} is tracked by git, so this helper did not write it; nothing was read.")
        return 2
    tracked_problem = _tracks_archive(root)
    if tracked_problem:
        err(f"Refuse: {tracked_problem}, so its entries are not this helper's; nothing was read.")
        return 2
    side = path[:-3] + ".repo"
    try:
        if os.path.islink(side):
            raise OSError("symlinked sidecar")
        with open(side, "r", encoding="utf-8") as fh:
            recorded = fh.read().strip()
    except OSError:
        recorded = ""
    if recorded != repo:
        err(f"Refuse: {backup_id} belongs to '{recorded or 'unknown'}', not '{repo}'; nothing was sent.")
        return 2

    target = m.group(1)
    num = re.search(r"[0-9]+", target).group(0)
    if target.startswith("comment-"):
        endpoint = f"repos/{repo}/issues/comments/{num}"
    else:
        endpoint = f"repos/{repo}/issues/{num}"

    try:
        os.chmod(path, 0o400)
        with open(path, "rb") as fh:
            data = fh.read()
    except OSError as e:
        err(f"ERROR: cannot read the archive entry: {e.strerror}")
        return 5
    finally:
        try:
            os.chmod(path, 0)
        except OSError:
            pass

    try:
        proc = subprocess.run(
            ["gh", "api", "-X", "PATCH", endpoint, "-F", "body=@-", "--jq", ".html_url"],
            input=data, capture_output=True,
        )
    except FileNotFoundError:
        err("ERROR: gh not found")
        return 1
    if proc.returncode != 0:
        err(f"ERROR: gh api PATCH {endpoint} failed (rc={proc.returncode})")
        return proc.returncode
    url = proc.stdout.decode("utf-8", errors="replace").strip()
    print(f"restored {url} ({len(data)} bytes)")
    return 0


# ───────────────────────────────────────────────────────────────────────
# Dispatch
# ───────────────────────────────────────────────────────────────────────
HELP_TEXT = """idd-edit-helper.py — Runtime support for /idd-edit skill.

Subcommands:
  parse-args <args...>
      Parse /idd-edit flags, emit shell-eval'able assignments to stdout.

  validate-target <comment-id> <repo> <override-flag> [<mode>]
      Enforce R5: refuse an author who is not OWNER, a bot, or the gh user unless
      override flag is "true"; mode --correct also refuses a bot.

  section-replace <input-file> <heading-line> <replacement-file>
      Replace named markdown section (level-aware, CRLF-safe).

  emit-audit-marker <kind> <key=value>...
      Emit HTML-comment audit marker with safe escaping. Kinds: edit / override.
      A backup-id value must be a correction backup id.

  check-correction <old-file> <section-heading|-> <new-file>
      Refuse (exit 6) a --correct replacement that touches a protected region.

  compose-correction <old-file> <section-heading|-> <body-file> <marker>
      Print the full corrected body (earlier correction markers kept, the new one last).

  archive <comment|issue> <id> --from-file <path> --repo <owner/repo>
      Archive the prior text (never tracked, mode 0000, <id>.repo sidecar); print the backup id.

  restore <backup-id> --repo <owner/repo>
      PATCH the target back to its archived text; print URL and byte count.

Exit codes:
  0=success, 1=generic, 2=usage, 3=R4-refuse, 4=R5-refuse (correct-*: not done),
  5=unreadable-file, 6=protected-region, 7=archive-refused (correct-apply:
  written but unverified), 8=markdown-parser-unavailable, 9=ambiguous-section

  existing-mentions <file>
      Print, comma-separated, the logins the file already mentions (gh-egress's scan).

  correct-prepare --target comment:<id>|issue:<n> --repo R (--section H | --scope whole-comment)
                  --body-file F [--scrub-attested L]
      The whole --correct flow up to the preview; prints WORK= and PREVIEW=.
  correct-apply --work <dir>     Archive, write and read back; prints RESULT= / BACKUP_ID= / URL=.
  correct-discard --work <dir>   Throw the prepared correction away (the user declined).
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
    if subcmd == "check-correction":
        return check_correction_subcmd(rest)
    if subcmd == "compose-correction":
        return compose_correction_subcmd(rest)
    if subcmd == "existing-mentions":
        return existing_mentions_subcmd(rest)
    if subcmd == "correct-prepare":
        return correct_prepare_subcmd(rest)
    if subcmd == "correct-apply":
        return correct_apply_subcmd(rest)
    if subcmd == "correct-discard":
        return correct_discard_subcmd(rest)
    if subcmd == "archive":
        return archive_subcmd(rest)
    if subcmd == "restore":
        return restore_subcmd(rest)
    if subcmd in ("-h", "--help", "help", ""):
        err(HELP_TEXT)
        return 2 if subcmd == "" else 0

    err(f"ERROR: unknown subcommand: {subcmd}")
    err("Run with --help for usage.")
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
