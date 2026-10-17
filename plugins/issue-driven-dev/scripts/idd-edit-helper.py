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
                                 --correct only the gh user's own content
                                 passes (#351).
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


def _under_folded(path, prefix):
    """_path_is_under, ignoring letter case: APFS, macOS's default, opens
    ~/.SSH/x as ~/.ssh/x, and realpath keeps the case it was given (verify
    #351 round 10)."""
    return _path_is_under(path.casefold(), prefix.casefold())


def _homes():
    """HOME and the account's home directory: overriding or unsetting HOME
    must not move the credential directories out of reach (verify #351 round 11)."""
    homes = [os.environ.get("HOME", "")]
    try:
        import pwd
        homes.append(pwd.getpwuid(os.getuid()).pw_dir)
    except (ImportError, KeyError):
        pass
    return [h for h in dict.fromkeys(homes) if h]


def _gh_config_dirs():
    """Where gh may keep its token store (hosts.yml), found the way gh finds
    it: GH_CONFIG_DIR, then $XDG_CONFIG_HOME/gh, then ~/.config/gh. All of
    them are refused, not only the one gh uses now (verify #351 round 10)."""
    dirs = [os.environ.get("GH_CONFIG_DIR", "")]
    if os.environ.get("XDG_CONFIG_HOME"):
        dirs.append(os.path.join(os.environ["XDG_CONFIG_HOME"], "gh"))
    dirs += [os.path.join(home, ".config", "gh") for home in _homes()]
    # as named and as resolved, like the path compared with them (/tmp is a
    # link on macOS)
    return [form(d) for d in dirs if d for form in (os.path.abspath, os.path.realpath)]


def validate_body_file_path(raw_path):
    """Refuse sensitive system/credential paths for --body-file.

    Canonicalizes the raw input first, then checks the canonical path against
    refused prefixes. Honors the IDD_EDIT_HELPER_ALLOW_UNSAFE_BODY_FILE=1
    escape hatch, except for gh's token store. Returns (ok, exit_code).
    """
    # Canonicalize FIRST. realpath resolves `..`, duplicate slashes, and
    # symlinks against the real filesystem, collapsing every bypass vector
    # to its true target before we inspect it.
    canonical = os.path.realpath(raw_path)
    # A link inside a credential directory is refused by the name it was given
    # as well as by what it resolves to (verify #351 round 11).
    named = (os.path.abspath(raw_path), canonical)

    # gh's own token store is never a body, escape hatch or not (#351 rounds 9–10)
    if any(_under_folded(path, d) for path in named for d in _gh_config_dirs()):
        err(f"ERROR: --body-file refuses credential path: {raw_path}")
        return False, 5

    # Escape hatch (documented advanced use).
    if os.environ.get("IDD_EDIT_HELPER_ALLOW_UNSAFE_BODY_FILE") == "1":
        return True, 0

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
        if _under_folded(canonical, prefix):
            err(f"ERROR: --body-file refuses sensitive system path: {raw_path}")
            err(
                "       Use IDD_EDIT_HELPER_ALLOW_UNSAFE_BODY_FILE=1 to "
                "override (audit your reason)."
            )
            return False, 5

    # Refuse credential directories. Check by path component so a realpath
    # landing in any `.ssh` / `.aws` / ... directory is caught regardless of
    # which home it lives under.
    for cred in _REFUSED_CREDENTIAL_DIRS:
        for path in named:
            if cred.casefold() not in path.casefold().split(os.sep):
                continue
            # Only refuse credential dirs under a home directory: matches the
            # bash reference's $HOME/.ssh/* etc. scope while staying robust to
            # symlinks that resolve into the real home.
            if any(
                _under_folded(path, os.path.join(home, cred))
                or _under_folded(path, os.path.realpath(home))
                for home in _homes()
            ):
                err(f"ERROR: --body-file refuses credential path: {raw_path}")
                err(
                    "       Use IDD_EDIT_HELPER_ALLOW_UNSAFE_BODY_FILE=1 to "
                    "override (audit your reason)."
                )
                return False, 5

    return True, 0


def _home_path(raw_path):
    """A leading `~`, `$HOME` or `${HOME}` names the user's home: the skill
    single-quotes its arguments, so the shell no longer expands them, and the
    proposed commands of idd-verify / idd-diagnose / idd-reorganize use
    `$HOME/.cache/idd/corrections/…` (verify #351 round 8)."""
    for prefix in ("$HOME/", "${HOME}/"):
        if raw_path.startswith(prefix):
            return os.path.join(os.path.expanduser("~"), raw_path[len(prefix):].lstrip("/"))
    return os.path.expanduser(raw_path) if raw_path.startswith("~") else raw_path


def read_body_file(raw_path):
    """Validate path safety + readability, return (ok, exit_code, content)."""
    raw_path = _home_path(raw_path)
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


def _parse_args(argv):
    """(exit code, parsed state, targets) — parse-args and run-start share it."""
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
                return 2, None, None
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
                        return code, None, None
                    state["body_file"] = value
                    state["body_input"] = content
                else:
                    state[_VALUE_FLAGS[flag]] = value
                i += 1
                continue
            err(f"ERROR: unknown argument: {arg}")
            return 2, None, None

        # Space-form value flags (--flag value): GUARDED.
        if arg in _VALUE_FLAGS:
            # Missing-value guard: flag is the last argument.
            if i + 1 >= n:
                err(f"ERROR: {arg} requires value (no argument follows)")
                return 2, None, None
            nxt = argv[i + 1]
            # Next-flag-eats-value guard: a following token that looks like a
            # flag means the user forgot the value (do NOT consume it).
            if nxt.startswith("--"):
                err(
                    f"ERROR: {arg} value cannot start with '--' (got: {nxt}). "
                    "Did you forget the value?"
                )
                return 2, None, None
            if arg == "--body-file":
                ok, code, content = read_body_file(nxt)
                if not ok:
                    return code, None, None
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
        return 2, None, None

    # ── R4 gate: --replace requires --scope=whole-comment OR --section ──
    if state["mode"] == "--replace" and not state["scope_flag"] and not state["section_flag"]:
        err(R4_MSG)
        return 3, None, None
    # Every mode reads --scope the same way. --append and --prepend-note took
    # any value here, and every later step refused the run (verify #351 round 10).
    if state["scope_flag"] and state["scope_flag"] != "whole-comment":
        err(
            "Refuse: --scope value must be 'whole-comment' (got: "
            f"'{state['scope_flag']}'). Use --section <heading> for named "
            "subsection scope."
        )
        return 3, None, None

    # --section names an ATX heading line: section-replace matches it as a whole
    # line and reads its level from the leading '#'s, so `Expected` or
    # `##Expected` matched nothing or the wrong level (verify #351 round 2).
    if state["section_flag"] and not _ATX_HEADING_RE.fullmatch(state["section_flag"]):
        err(
            "Refuse: --section must be a markdown heading line such as '## Expected' "
            f"(one to six '#', a space, then the title; got: '{state['section_flag']}')."
        )
        return 2, None, None

    # ── --correct gates (#351) ──
    issue_targets = [t for t in targets if t.startswith("issue:")]
    for t in issue_targets:
        if not re.fullmatch(r"issue:[0-9]+", t):
            err(f"ERROR: issue target must be issue:<numeric issue number> (got: {t})")
            return 2, None, None
    if issue_targets and len(targets) > 1:
        err(
            "Refuse: an issue:<N> target must be the only target of the invocation "
            "(mixing it with comment targets, or naming two issues, is not supported)."
        )
        return 2, None, None
    if issue_targets and state["mode"] != "--correct":
        err(
            "Refuse: an issue:<N> (issue body) target is only accepted with --correct. "
            "Other edit modes on the issue body are tracked in #347."
        )
        return 2, None, None
    if state["mode"] == "--correct":
        if state["override"] == "true":
            err(
                "Refuse: --correct cannot override user-authored content. It rewrites only "
                "your own content; for anyone else's comment, the OWNER's and a bot's "
                "included, propose the correction with /idd-comment --type errata (#351)."
            )
            return 2, None, None
        if not state["scope_flag"] and not state["section_flag"]:
            err(CORRECT_SCOPE_MSG)
            return 3, None, None
        if state["scope_flag"] and state["section_flag"]:
            err("Refuse: --correct takes exactly one of --scope whole-comment or --section <heading>.")
            return 3, None, None
        if not state["body_input"].strip():
            err(
                "Refuse: --correct needs the corrected text (--body or --body-file); "
                "without it the region would be emptied (#351)."
            )
            return 2, None, None
        if issue_targets and state["scope_flag"]:
            err(
                "Refuse: an issue-body correction requires --section <heading>; "
                "replacing the whole body would also overwrite the Original text "
                "quotation and the sections owned by idd-update and idd-clarify."
            )
            return 3, None, None

    if not targets:
        err("ERROR: no target given (comment:<id>, #<issue> or issue:<N>); nothing to edit")
        return 2, None, None

    # ── R5-pair guard: --override-user-content requires --reason ──
    if state["override"] == "true" and not state["reason"]:
        err(
            "ERROR: --override-user-content requires "
            '--reason="<rationale>" (spec Requirement 5 audit)'
        )
        return 2, None, None

    return 0, state, targets


def parse_args_subcmd(argv):
    rc, state, targets = _parse_args(argv)
    if rc != 0:
        return rc
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
    if not _REPO_RE.fullmatch(repo) or ".." in repo:
        err(f"ERROR: repo must be owner/repo (got: {repo})")
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
                + ("/idd-comment --type correction (an issue body has no comment id for --type errata)"
                   if is_issue else "/idd-comment --type errata") + " instead (#351)."
            )
            return 4
        err(f"✓ Bot author: {login} (skip R5 gate)")
        return 0

    # OWNER passes — except for --correct, which rewrites only your own words:
    # when someone else is the OWNER, the OWNER's comment is a third party's
    # too (user decision 2026-10-17, verify #351 round 6).
    if assoc == "OWNER" and mode != "--correct":
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
            "rewrites your own content. If you wrote it under another GitHub account, "
            "switch to it (`gh auth switch`) and run again; otherwise propose the correction with "
            + ("/idd-comment --type correction (an issue body has no comment id for --type errata)"
               if is_issue else "/idd-comment --type errata") + " instead (#351)."
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
        self.setext_spans = {}   # first line → (text lines…, underline) as a tuple
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
                if not token.markup.startswith("#"):
                    self.setext_spans[token.map[0]] = tuple(lines[token.map[0]:token.map[1]])
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
    rc, marker = _audit_marker(argv)
    if rc == 0:
        print(marker)
    return rc


def _audit_marker(argv):
    """(exit code, marker line) — emit-audit-marker and the run's composer."""
    if not argv:
        err("ERROR: emit-audit-marker requires <kind> arg")
        return 2, None
    kind = argv[0]
    rest = argv[1:]

    if kind not in ("edit", "override"):
        err(f"ERROR: emit-audit-marker kind must be 'edit' or 'override' (got: {kind})")
        return 2, None

    marker = "<!-- idd:edit"
    if kind == "override":
        marker += " override-user-content"

    has_date = False
    for kv in rest:
        if "=" not in kv:
            err(f"ERROR: emit-audit-marker arg must be key=value (got: {kv})")
            return 2, None
        key, _, val = kv.partition("=")
        key = _sanitize_marker_key(key)
        if key == "backup-id":
            m = BACKUP_ID_RE.fullmatch(val)
            if not m:
                err(f"ERROR: backup-id is not a correction backup id (got: {val})")
                return 2, None
        val = _sanitize_marker_value(val)
        marker += f' {key}="{val}"'
        if key == "date":
            has_date = True

    if not has_date:
        # The local date, as the --correct write uses; the backup id keeps its
        # UTC time with Z (verify #351 round 11, #406).
        marker += f' date="{datetime.date.today().isoformat()}"'

    marker += " -->"
    return 0, marker


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
# Closed list of three labels (spec in-place-correction): the idd-issue
# template's `Original text`, the idd-comment decision template's `**Original**`
# and the idd-comment reply template's `**Point i**` (a reviewer's words quoted
# verbatim — verify #351 round 7).
_VERBATIM_LABELS = ("Original text", "**Original**", "**Point ")
_CLARITY_PREFIX = "### Clarity Surface"


def _read_normalized(path):
    with open(path, "r", encoding="utf-8", errors="replace") as fh:
        return fh.read().replace("\r\n", "\n").replace("\r", "\n")


def _lines_of(text):
    lines = text.split("\n")
    if text.endswith("\n"):
        lines = lines[:-1]
    return lines


def _raw_lines(path):
    """The file's lines with their own endings, one per _lines_of line, so the
    text outside a corrected section is written back byte for byte (CRLF from
    the web editor, no final newline — verify #351 round 6)."""
    with open(path, "r", encoding="utf-8", errors="replace", newline="") as fh:
        raw = fh.read()
    return re.findall(r"[^\r\n]*(?:\r\n|\r|\n)|[^\r\n]+$", raw) or [""], raw


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


def _verbatim_spans(lines):
    """(first, end) of each verbatim block, end exclusive: a maximal run of
    lines starting with `>` in which some line holds one of _VERBATIM_LABELS."""
    spans, first = [], None
    for idx, line in enumerate(lines + [None]):
        if line is not None and line.startswith(">"):
            if first is None:
                first = idx
            continue
        if first is not None and any(label in l for l in lines[first:idx] for label in _VERBATIM_LABELS):
            spans.append((first, idx))
        first = None
    return spans


def _verbatim_runs(lines, opaque=frozenset(), offset=0):
    """(block text, the line after it or None, hidden) for each verbatim block;
    hidden = some line of it sits in a code or HTML block (index + offset)."""
    return [
        ("\n".join(lines[first:end]), lines[end] if end < len(lines) else None,
         any((k + offset) in opaque for k in range(first, end)))
        for first, end in _verbatim_spans(lines)
    ]


def _region_text(region, originals):
    """region's lines, each ending in LF, except an Original text quotation the
    replaced region held: that is written with the original's own bytes. The
    check compares quotations with line endings normalised, so a CRLF quotation
    copied into an LF replacement passes it (verify #351 round 10)."""
    spans, out, i = dict(_verbatim_spans(region)), [], 0
    while i < len(region):
        own = originals.get("\n".join(region[i:spans[i]])) if i in spans else None
        # A lone \r ending the quotation would join the next LF line into one
        # CRLF and swallow the blank line after it: such a quotation is written
        # with LF (verify #351 round 11).
        if own and not any(r.endswith("\r") for r in own[0]):
            out.extend(r if r.endswith(("\n", "\r")) else r + "\n" for r in own.pop(0))
            i = spans[i]
            continue
        out.append(region[i] + "\n")
        i += 1
    return "".join(out)


def _is_marker(line):
    return bool(IDD_MARKER_LINE_RE.fullmatch(line))


def _opening_line(lines):
    """The line readers identify a comment by: the first non-blank line that is
    not an IDD marker (dashboard comments put the marker on line 1)."""
    return next((l for l in lines if l.strip() and not _is_marker(l)), "")


def _top_markers(old_lines):
    """The IDD marker lines at the top of a comment (a dashboard's line 1)."""
    lead = 0
    while lead < len(old_lines) and (_is_marker(old_lines[lead]) or not old_lines[lead].strip()):
        lead += 1
    return [l for l in old_lines[:lead] if _is_marker(l)]


def _drop_top_markers(old_lines, new_lines):
    """The replacement without its copies of the original's top markers
    (outside code), leading blank lines trimmed."""
    head = _top_markers(old_lines)
    if not head:
        return new_lines
    try:
        code = _Blocks(new_lines).code
    except ParserUnavailable:
        code = set()
    kept = [l for i, l in enumerate(new_lines) if i in code or l not in head]
    while kept and not kept[0].strip():
        kept.pop(0)
    return kept


def _adds_setext(old_lines, blocks, start, end, new_lines, new_blocks):
    """A correction must not create the setext shape it refuses: the next
    correction of the section would be refused (verify #351 round 6)."""
    # Whole headings, text and underline, counted: a changed underline or a
    # second copy is a setext heading the correction adds (round 7).
    from collections import Counter
    old_setext = Counter(span for i, span in blocks.setext_spans.items() if start <= i < end)
    new_setext = Counter(new_blocks.setext_spans.values())
    if any(n > old_setext[span] for span, n in new_setext.items()):
        err("Refuse: the replacement adds a setext heading (a line of text over '---' or '==='); "
            "use an ATX heading or put a blank line before the '---' (#351).")
        return True
    return False


def check_correction_subcmd(argv):
    return _check_correction(argv)[0]


def _check_correction(argv):
    """(exit code, refusal reason) — the reason feeds correct-prepare/apply's
    REASON=; the CLI keeps the exit code only."""
    if len(argv) != 3:
        err("ERROR: check-correction requires <old-file> <section-heading|-> <new-file>")
        return 2, "check-failed"
    old_file, heading, new_file = argv
    for f in (old_file, new_file):
        if not os.path.isfile(f) or not os.access(f, os.R_OK):
            err(f"ERROR: file not readable: {f}")
            return 5, "check-failed"
    old_lines = _lines_of(_read_normalized(old_file))
    new_lines = _strip_target_heading(_lines_of(_read_normalized(new_file)), heading)
    if heading == "-":
        # compose keeps the original's top markers on top and drops a copy of
        # them from the replacement; check what compose will write (round 7).
        new_lines = _drop_top_markers(old_lines, new_lines)
    try:
        blocks = _Blocks(old_lines)
    except ParserUnavailable as e:
        err(f"ERROR: {e}; the correction was not checked")
        return EXIT_PARSER, "parser-unavailable"
    if heading != "-" and _heading_count(old_lines, heading, blocks) > 1:
        err(f"Refuse: '{heading}' occurs more than once, so it does not name one section (#351).")
        return EXIT_AMBIGUOUS, "section-ambiguous"

    # Line view, fenced or not: idd-update and idd-clarify find their heading by
    # exact line match, so even a fenced copy could be taken for the real one.
    for line in new_lines:
        if line.startswith(_CURRENT_STATUS) or line.startswith(_CLARITY_PREFIX):
            err(
                f"Refuse: the replacement introduces '{line}', a heading managed by "
                f"{'idd-update' if line.startswith(_CURRENT_STATUS) else 'idd-clarify'} (#351)."
            )
            return 6, "protected"
    try:
        new_blocks = _Blocks(new_lines)
    except ParserUnavailable as e:
        err(f"ERROR: {e}; the correction was not checked")
        return EXIT_PARSER, "parser-unavailable"

    if heading == "-":
        start, end = 0, len(old_lines)
        if _adds_setext(old_lines, blocks, start, end, new_lines, new_blocks):
            return 6, "setext"
    else:
        rng = _section_range(old_lines, heading, stop_at_rule=True, blocks=blocks)
        if rng is None:
            err(f"ERROR: heading not found in input: {heading}")
            return 1, "section-not-found"
        start, end = rng
        if any(i in blocks.setext for i in range(start + 1, end)):
            err(
                "Refuse: the section holds a setext heading (a line of text over '---' or "
                "'==='), so where it ends is ambiguous; put a blank line before the '---' or "
                "make it an ATX heading, then correct (#351)."
            )
            return 6, "setext"
        if _adds_setext(old_lines, blocks, start, end, new_lines, new_blocks):
            return 6, "setext"
        # A heading of the target's level or higher, or a thematic break, would
        # split the section: the next correction would reach only part of it.
        level = blocks.headings[start]
        if any(lvl <= level for lvl in new_blocks.headings.values()) or new_blocks.rules:
            err(
                "Refuse: the replacement adds a heading of the section's level or higher, "
                "or a thematic break, which would split the corrected section (#351)."
            )
            return 6, "protected"
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
                return 6, "protected"

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
            return 6, "protected"
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
            return 6, "protected"
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
            return 6, "protected"
    for block, follow, _ in new_runs:
        if follow is not None and follow.strip() and (block, follow) not in old_follow:
            err(
                "Refuse: the line after an Original text quotation would join the "
                "quotation when rendered; leave a blank line after it (#351)."
            )
            return 6, "protected"
    return 0, None


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
    if heading == "-" and head:
        # The original's top markers stay on top (a dashboard comment is found
        # by its first line); a copy in the replacement is dropped, wherever the
        # replacement put it (verify #351 round 6).
        body_lines = [l for i, l in enumerate(body_lines) if i in body_blocks.code or l not in head]
        while body_lines and not body_lines[0].strip():
            body_lines.pop(0)
        try:
            body_blocks = _Blocks(body_lines)
        except ParserUnavailable as e:
            err(f"ERROR: {e}; nothing was composed")
            return EXIT_PARSER, None
    # A copy in the replacement stands in for a live marker only where it is
    # still one: outside code and the first line of its own HTML block. A copy
    # moved inside a <script> or <div> block is text there (verify #351 round 10).
    present = [i for i, l in enumerate(body_lines)
               if _is_marker(l) and i not in body_blocks.code and i in body_blocks.html_starts]
    in_body = {body_lines[i] for i in present}
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
    # Every marker the body keeps, carried or standing in, is checked where it
    # ends up in the composed body.
    marker_lines = [len(head) + i for i in present]
    marker_lines += range(len(head) + len(body_lines) + 1, len(head) + len(region))
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
    raw_lines, raw = _raw_lines(old_file)
    ends_open = raw.endswith(("\n", "\r"))
    originals = {}
    for first, stop in _verbatim_spans(old_lines[start + 1:end]):
        first, stop = first + start + 1, stop + start + 1
        originals.setdefault("\n".join(old_lines[first:stop]), []).append(raw_lines[first:stop])
    region_text = _region_text(region, originals)
    if heading == "-":
        text = "".join(l + "\n" for l in head) + region_text
        return 0, text if ends_open else text[:-1]
    # Head and tail are the original's own bytes; only the region is new.
    head_text = "".join(raw_lines[: start + 1])
    if not head_text.endswith(("\n", "\r")):
        head_text += "\n"
    tail_text = "".join(raw_lines[end:])
    if not (tail_text or ends_open):
        region_text = region_text[:-1]
    return 0, head_text + region_text + ("\n" + tail_text if tail_text else "")



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
    decoded here instead. A response without a body field, or a null comment
    body, is a failed read, not an empty one (round 6); an issue body may be
    null, which is empty."""
    proc = _gh(["api", endpoint])
    if proc is None or proc.returncode != 0:
        return False
    try:
        record = json.loads(proc.stdout.decode("utf-8"))
    except ValueError:
        return False
    if not isinstance(record, dict) or "body" not in record:
        return False
    body = record["body"]
    if body is None and "/issues/comments/" not in endpoint:
        body = ""
    if not isinstance(body, str):
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
    # The local date, as the other modes' markers have; the backup id keeps
    # UTC with its Z (verify #351 round 10, #406).
    return f'<!-- idd:edit mode="correct" backup-id="{backup_id}" date="{datetime.date.today().isoformat()}" -->'


def _floor(scrub, path):
    """The least tier a body may go out at. A reply quoting user-pasted points
    carries both markers of idd-comment's reply template, and gh-egress refuses
    it at light (#272). prepare checks at the floor and prints FLOOR=272; the
    agent asks the #272 question and attests warn itself — apply refuses light
    for such a body and never raises the tier on the agent's behalf (verify
    #351 rounds 10–11)."""
    return "warn" if scrub == "light" and _reply_272(path) else scrub


def _reply_272(path):
    """The body quotes user-pasted points: both markers of idd-comment's reply
    template. The #272 question is asked at every tier, as idd-comment asks it
    (rules/privacy-scrubbing.md; verify #351 round 12)."""
    with open(path, encoding="utf-8", errors="replace") as fh:
        text = fh.read()
    return "type=reply" in text and "points-from=user-pasted" in text


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
    m = _TARGET_RE.fullmatch(target or "")
    # The privacy self-review is attested by the caller, never assumed here:
    # gh-egress refuses a missing attestation (D2), and a default would defeat
    # it (verify #351 round 6).
    if rest or not m or not repo or not body_file or not scrub or not _REPO_RE.fullmatch(repo) or ".." in repo:
        err("ERROR: correct-prepare requires --target comment:<id>|issue:<n> --repo <owner/repo> "
            "(--section <heading> | --scope whole-comment) --body-file <path> --scrub-attested <level>")
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
    return _correct_prepare_text(target, kind, num, repo, section, scrub, content)


def _correct_prepare_text(target, kind, num, repo, section, scrub, content, keep=None):
    """correct-prepare once the corrected text is in hand. A run passes the
    text of its own body.md here instead of a path: the body-file gate only
    admits the temp dir of the current call, and a run may move between a
    sandboxed and an unsandboxed one (verify #351 round 9)."""
    if not content.strip() or not "\n".join(_strip_target_heading(
            _lines_of(content.replace("\r\n", "\n").replace("\r", "\n")), section or "-")).strip():
        # Only the target heading is no text either: it would empty the section.
        err("Refuse: --correct needs the corrected text; the body file is empty (#351).")
        return 2

    _remove_stale_work_dirs(keep=keep)
    work = tempfile.mkdtemp(prefix=CORRECT_WORK_PREFIX)   # mode 0700
    try:
        return _correct_prepare(work, target, kind, num, repo, section, scrub, content)
    except Exception as exc:   # noqa: BLE001 — never leave the wrong text behind
        err(f"✗ {target}: {type(exc).__name__}: {exc} — nothing was prepared")
        return _refused("check-failed", work)


def _correct_prepare(work, target, kind, num, repo, section, scrub, content):
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
    # The archive must be writable before the user is asked to confirm (round
    # 5); checked after the read and the author gate, so a target that will be
    # refused anyway leaves nothing behind in the repository (round 7).
    problem = _archive_preflight()
    if problem:
        err(f"Refuse: {problem}; nothing was prepared (#351).")
        return _refused("archive", work)
    heading = section or "-"
    if heading == "-":
        with open(backup, encoding="utf-8", errors="replace") as fh:
            old_lines = _lines_of(fh.read().replace("\r\n", "\n").replace("\r", "\n"))
        if not "\n".join(_drop_top_markers(old_lines, _lines_of(content.replace("\r\n", "\n")))).strip():
            # Only a copy of the top marker is no text either (round 7).
            err("Refuse: --correct needs the corrected text; the replacement holds only the comment's marker (#351).")
            return _refused("empty", work)
    rc, reason = _check_correction([backup, heading, body])
    if rc != 0:
        return _refused(reason or "check-failed", work)
    rc, text = _compose(backup, heading, body, PLACEHOLDER_MARKER)
    if rc != 0:
        # compose's own exit 6 is a block the replacement leaves open (round 7)
        return _refused("unclosed-block" if rc == 6 else _CHECK_REASONS.get(rc, "check-failed"), work)
    with open(preview, "w", encoding="utf-8", newline="") as fh:
        fh.write(text)
    ok, mentions = _existing_mentions(backup)
    if not ok:
        return _refused("egress", work)
    # The egress gates run before the preview, so a body gh-egress would refuse
    # is never confirmed or archived (round 3). Mentions the target already had
    # were published already; a mention the correction adds is still refused.
    floor = _floor(scrub, preview)
    if _egress(["check", "--body-file", preview, "--scrub-attested", floor]
               + _mention_args(mentions)) != 0:
        return _refused("egress", work)
    state = {
        "target": target, "kind": kind, "num": num, "repo": repo, "heading": heading,
        "scrub": scrub, "mentions": mentions,
        "sha": {n: _sha256(os.path.join(work, n)) for n in ("backup.md", "body.md", "preview.md")},
    }
    state_path = os.path.join(work, "state.json")
    with open(state_path, "w", encoding="utf-8") as fh:
        json.dump(state, fh)
    diff = os.path.join(work, "diff.txt")
    _write_diff(backup, preview, diff)
    print(f"WORK={work}")
    print(f"PREVIEW={preview}")
    print(f"DIFF={diff}")
    _print_floor(preview)
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
    # Every existing component must be a directory and the deepest one
    # writable, or the archive write fails after confirmation (round 6).
    path = root
    for part in ARCHIVE_REL.split(os.sep):
        path = os.path.join(path, part)
        if not os.path.exists(path):
            path = os.path.dirname(path)
            break
        if not os.path.isdir(path):
            return f"cannot create the archive directory: {os.path.relpath(path, root)} is not a directory"
    if not os.access(path, os.W_OK | os.X_OK):
        return f"cannot create the archive directory: {os.path.relpath(path, root)} is not writable"
    return _ensure_ignored(root, os.path.join(ARCHIVE_REL, "preflight.md"))


def _remove_stale_work_dirs(max_age=86400, keep=None):
    """Working directories left by a run that never reached apply or discard
    (a closed session) hold the uncorrected text; drop those older than a day.
    `keep` holds the run being served and its working copies: a user may
    answer the next day (verify #351 rounds 10–11)."""
    tmp = os.path.realpath(tempfile.gettempdir())
    try:
        names = os.listdir(tmp)
    except OSError:
        return
    now = datetime.datetime.now().timestamp()
    for name in names:
        # a --correct working copy or an abandoned run: both hold the old text
        if not name.startswith((CORRECT_WORK_PREFIX, RUN_PREFIX)):
            continue
        path = os.path.join(tmp, name)
        if keep and os.path.realpath(path) in keep:
            continue
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
    sha = state.get("sha")
    if (not isinstance(sha, dict) or set(sha) != {"backup.md", "body.md", "preview.md"}
            or not all(isinstance(v, str) and re.fullmatch(r"[0-9a-f]{64}", v) for v in sha.values())):
        return "the prepared file hashes are malformed"
    return None


def _own_work_dir(work, any_parent=False):
    """The working directory prepare made, else None: a direct child of this
    user's temp directory with the prefix, a real directory owned by this user
    and closed to others, holding state.json. Within a run (any_parent), the
    path comes from the run's own ledger and may sit in another call's temp
    dir (round 8)."""
    if not work:
        return None
    real = os.path.realpath(work)
    if ((not any_parent and os.path.dirname(real) != os.path.realpath(tempfile.gettempdir()))
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


def _correct_apply(work, state_sha, scrub=None):
    import hashlib
    state_path = os.path.join(work, "state.json")
    # One read: the bytes that are hashed are the bytes that are used (round 6).
    with open(state_path, "rb") as fh:
        state_bytes = fh.read()
    if hashlib.sha256(state_bytes).hexdigest() != state_sha:
        err("✗ the prepared state changed after the preview — nothing archived or written")
        return _refused("differs-from-preview")
    try:
        state = json.loads(state_bytes.decode("utf-8"))
    except (ValueError, UnicodeDecodeError):
        state = {}
    problem = _state_problem(state) if isinstance(state, dict) else "the prepared state is malformed"
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
    # The gates run again before anything is written — on the previewed copy,
    # which the re-fetch below must still equal — so the network round-trips
    # they need sit before the re-fetch, not between it and the write (round 6).
    rc = validate_target_subcmd([num if kind == "comment" else f"issue:{num}", repo, "false", "--correct"])
    if rc != 0:
        return _refused({4: "R5", 1: "author-unknown"}.get(rc, "check-failed"))
    rc, reason = _check_correction([backup, heading, body])
    if rc != 0:
        return _refused(reason or "check-failed")
    rc, text = _compose(backup, heading, body, PLACEHOLDER_MARKER)
    with open(preview, encoding="utf-8", newline="") as fh:
        if rc != 0 or text != fh.read():
            return _refused("differs-from-preview")
    endpoint = _endpoint(kind, num, repo)
    current = os.path.join(work, "current.md")
    if not _fetch_body(endpoint, current):
        err(f"✗ cannot re-read {state['target']} — nothing archived or written")
        return _refused("fetch-failed")
    if _sha256(current) != state["sha"]["backup.md"]:
        err(f"✗ {state['target']} changed since the preview — nothing archived or written; run again to see the new version")
        return _refused("changed-since-preview")
    attested = scrub or state["scrub"]
    if _floor(attested, preview) != attested:
        # before the archive: the write would be refused anyway (#272, round 12)
        err(f"✗ {state['target']} quotes user-pasted points (#272): prepare it again with --scrub-attested warn "
            "after the #272 question — nothing archived or written")
        return _refused("egress")
    with open(backup, "rb") as fh:
        rc, backup_id = _archive_write(kind, num, fh.read(), repo)
    if rc != 0:
        return _refused("archive")
    if scrub:
        # the tier the privacy review attested at apply, at least the prepared one (round 9)
        state = dict(state, scrub=scrub)
    try:
        return _correct_write(work, state, endpoint, backup, body, backup_id)
    except Exception as exc:   # noqa: BLE001 — after the archive, report honestly
        # The write may or may not have happened; "nothing changed" would be a
        # guess. The archive exists, so its id is printed (round 6).
        err(f"⚠ {state['target']}: {type(exc).__name__}: {exc} after archiving — check it by hand")
        print("RESULT=unverified")
        print("REASON=exception")
        print(f"BACKUP_ID={backup_id}")
        return 7


def _correct_write(work, state, endpoint, backup, body, backup_id):
    kind, num, repo, heading = state["kind"], state["num"], state["repo"], state["heading"]
    rc, new_text = _compose(backup, heading, body, _correct_marker(backup_id))
    if rc != 0:
        return _refused("replace", extra=(f"BACKUP_ID={backup_id}",))
    new_file = os.path.join(work, "new.md")
    with open(new_file, "w", encoding="utf-8", newline="") as fh:
        fh.write(new_text)
    print(f"SCRUB={state['scrub']}")   # the tier the write goes out at
    verb = ["edit-comment", num] if kind == "comment" else ["edit", num]
    rc = _egress(verb + ["--repo", repo, "--body-file", new_file, "--scrub-attested", state["scrub"]]
                 + _mention_args(state["mentions"]))
    if rc >= 10:
        return _refused("egress", extra=(f"BACKUP_ID={backup_id}",))
    if rc != 0:
        # A failed call does not prove nothing was written: read it back (round 5).
        after = os.path.join(work, "after-failure.md")
        readable = _fetch_body(endpoint, after)
        if readable and _sha256(after) == state["sha"]["backup.md"]:
            err(f"✗ gh failed the write for {state['target']} (rc={rc}); re-read shows it unchanged. The archive {backup_id} stays.")
            print("RESULT=write-failed")
            print(f"RC={rc}")
            print(f"BACKUP_ID={backup_id}")
            return 4
        why = "no longer reads as before" if readable else "could not be read again"
        err(f"⚠ gh reported a failed write for {state['target']} (rc={rc}), but the target {why} — check it by hand")
        print("RESULT=unverified")
        print(f"BACKUP_ID={backup_id}")
        return 7
    # Byte for byte: a body with extra newlines or other line endings is not
    # what was sent (round 6).
    readback = os.path.join(work, "readback.md")
    confirmed = _fetch_body(endpoint, readback)
    if confirmed:
        with open(readback, "rb") as fh:
            confirmed = fh.read() == new_text.encode("utf-8")
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



# ───────────────────────────────────────────────────────────────────────
# One /idd-edit run: run-start → prepare → apply | discard → finish (#351)
# ───────────────────────────────────────────────────────────────────────
# The preview, the user's confirmation and the write are separate tool calls,
# and shell state does not survive them: verify rounds 6 and 7 found a skill
# whose post-confirmation blocks read variables, arrays, a loop and an exit
# code that a new call no longer had. The run's state lives here instead, in a
# private run directory; every skill block is one command that takes only the
# values an earlier block printed (RUN, TARGET, SCRUB, and STATE for
# --correct). The run's exit code comes from `finish`.
RUN_PREFIX = "idd-run-"
BACKUP_DIR_NAME = "idd-edit-backup"
_OUTCOMES = ("prepared", "edited", "refused", "declined", "write-failed", "unverified", "egress-refused")


def _write_diff(old_path, new_path, dest):
    import difflib
    # Lines end at \r\n, \r or \n, as CommonMark and GitHub read them:
    # splitlines also breaks at \x0c, \x85 and the like and marked those as
    # the end of the file (rounds 10–11).
    split = re.compile(r"[^\r\n]*(?:\r\n|\r|\n)|[^\r\n]+$")
    with open(old_path, encoding="utf-8", errors="replace", newline="") as fh:
        old = split.findall(fh.read())
    with open(new_path, encoding="utf-8", errors="replace", newline="") as fh:
        new = split.findall(fh.read())
    with open(dest, "w", encoding="utf-8", newline="") as fh:
        for line in difflib.unified_diff(old, new, "current", "after this edit"):
            if line.endswith("\r"):
                # a lone \r would put the next record on the same screen line (round 12)
                line = line[:-1] + "\n"
            # as diff(1) does: a last line without a newline would otherwise be
            # glued to the next one on screen (verify #351 round 9)
            fh.write(line if line.endswith(("\n", "\r")) else line + "\n\\ No newline at end of file\n")


def _captured(fn, *args):
    """(exit code, stdout) of a subcommand function, its stdout replayed."""
    import contextlib
    import io
    buf = io.StringIO()
    with contextlib.redirect_stdout(buf):
        rc = fn(*args)
    out = buf.getvalue()
    sys.stdout.write(out)
    return rc, out


def _kv(text):
    out = {}
    for line in text.splitlines():
        key, sep, value = line.partition("=")
        if sep and re.fullmatch(r"[A-Z_]+", key) and key not in out:
            out[key] = value
    return out


def _scrub_tier(repo):
    """rules/privacy-scrubbing.md: third-party → enforce, own public → warn,
    own private → light. A failed probe is third-party (fail-safe)."""
    proc = _gh(["repo", "view", repo, "--json", "viewerPermission,isPrivate"])
    data = {}
    if proc is not None and proc.returncode == 0:
        try:
            data = json.loads(proc.stdout.decode("utf-8"))
        except ValueError:
            data = {}
    if isinstance(data, dict) and data.get("viewerPermission") in ("WRITE", "MAINTAIN", "ADMIN"):
        return "light" if data.get("isPrivate") is True else "warn"
    return "enforce"


def _own_run_dir(run):
    """The run directory run-start made, else None: named idd-run-*, a real
    directory owned by this user and closed to others, holding run.json. Not
    tied to this call's temp dir: a sandboxed call and an unsandboxed one see
    different TMPDIRs, and a run must survive both (verify #351 round 8)."""
    if not run:
        return None
    real = os.path.realpath(run)
    if not os.path.basename(real).startswith(RUN_PREFIX) or os.path.islink(run):
        return None
    try:
        st = os.lstat(real)
    except OSError:
        return None
    if st.st_uid != os.getuid() or st.st_mode & 0o077 or not os.path.isfile(os.path.join(real, "run.json")):
        return None
    # What run-start writes, and nothing else: a run directory is found by its
    # path alone, so its contents are checked as run-start would have made
    # them — the same gates (R5's reason pair, the repo shape, the tier), and a
    # body that is a plain file, not a link to one (verify #351 round 9).
    body = os.path.join(real, "body.md")
    if os.path.islink(body) or not os.path.isfile(body):
        return None
    try:
        meta = _run_meta(real)
    except (OSError, ValueError):
        return None
    if _run_meta_problem(meta):
        return None
    return real


def _run_meta(real):
    with open(os.path.join(real, "run.json"), encoding="utf-8") as fh:
        return json.load(fh)


def _run_meta_problem(meta):
    if not isinstance(meta, dict) or meta.get("mode") not in _MODE_FLAGS:
        return "mode"
    repo = str(meta.get("repo", ""))
    if not _REPO_RE.fullmatch(repo) or ".." in repo:
        return "repo"
    if meta.get("scrub") not in _SCRUB_LEVELS or meta.get("override") not in ("true", "false"):
        return "settings"
    if meta["override"] == "true" and not meta.get("reason"):
        return "override without reason"
    if meta.get("scope") not in ("", "whole-comment"):
        return "scope"
    if meta.get("section") and not _ATX_HEADING_RE.fullmatch(str(meta["section"])):
        return "section"
    targets, picks = meta.get("targets"), meta.get("picks")
    if (not isinstance(targets, list) or not all(isinstance(x, str) and _TARGET_RE.fullmatch(x) for x in targets)
            or not isinstance(picks, list) or not all(isinstance(x, str) and re.fullmatch(r"[0-9]{1,18}", x) for x in picks)):
        return "targets"
    return None


def _comment_issue(repo, num):
    """(True, the issue number a comment belongs to, or None), or (False, None)
    when the comment cannot be read."""
    proc = _gh(["api", f"repos/{repo}/issues/comments/{num}", "--jq", ".issue_url"])
    if proc is None or proc.returncode != 0:
        return False, None
    m = re.search(r"/issues/([0-9]+)$", proc.stdout.decode("utf-8", errors="replace").strip())
    return True, (m.group(1) if m else None)


def _record(real, target, outcome, **extra):
    rec = {"target": target, "outcome": outcome}
    rec.update({k: v for k, v in extra.items() if v})
    with open(os.path.join(real, "ledger.jsonl"), "a", encoding="utf-8") as fh:
        fh.write(json.dumps(rec) + "\n")
    os.utime(real)   # a run in use is not stale: the sweep reads the directory's mtime


def _latest(real):
    """[(target, its last record)] in the order targets first appeared."""
    order, last = [], {}
    try:
        with open(os.path.join(real, "ledger.jsonl"), encoding="utf-8") as fh:
            for line in fh:
                if not line.strip():
                    continue
                rec = json.loads(line)
                if rec["target"] not in last:
                    order.append(rec["target"])
                elif last[rec["target"]].get("pick") and not rec.get("pick"):
                    rec["pick"] = last[rec["target"]]["pick"]   # which #N it came from stays known
                last[rec["target"]] = rec
    except FileNotFoundError:
        pass
    return [(t, last[t]) for t in order]


def run_start_subcmd(argv):
    default_repo, rest = _take_flag(argv, "--default-repo")
    if not rest or rest[0] != "--":
        err("ERROR: run-start requires [--default-repo owner/repo] -- <the /idd-edit arguments>")
        return 2
    rc, state, targets = _parse_args(rest[1:])
    if rc != 0:
        return rc
    if not state["mode"]:
        # without one, prepare treated the run as a --replace (round 8)
        err("ERROR: give a mode: --append, --replace, --prepend-note or --correct")
        return 2
    if state["mode"] == "--correct" and state["reason"]:
        err("Note: --correct does not publish --reason (its marker carries only the backup id "
            "and the date); say why in the conversation, or add an --append note (#351).")
    if state["mode"] == "--correct" and not "\n".join(_strip_target_heading(
            _lines_of(state["body_input"].replace("\r\n", "\n")), state["section_flag"] or "-")).strip():
        err("Refuse: --correct needs the corrected text; the body holds only the target heading (#351).")
        return 2
    repo = state["repo"] or default_repo or ""
    if not _REPO_RE.fullmatch(repo) or ".." in repo:
        err("ERROR: no repository: pass --repo owner/repo, or --default-repo from the IDD config")
        return 2
    resolved, picks = [], []
    for target in targets:
        if target.startswith(("comment:", "issue:")):
            if not _TARGET_RE.fullmatch(target):
                err(f"ERROR: invalid target (the id must be numeric): {target}")
                return 2
            resolved.append(target)
            continue
        number = target[1:]
        if not re.fullmatch(r"[0-9]{1,18}", number):
            err(f"ERROR: invalid issue number: {target}")
            return 2
        number = str(int(number))   # #007 is #7 (verify #351 round 10)
        if state["last"] != "true":
            picks.append(number)
            continue
        # every page: the newest comment is on the last one (round 4)
        proc = _gh(["api", f"repos/{repo}/issues/{number}/comments", "--paginate", "--jq", ".[-1].id"])
        if proc is None or proc.returncode != 0:
            err(f"✗ cannot read the comments of #{number}; nothing was changed")
            return 1
        ids = proc.stdout.decode("utf-8", errors="replace").split()
        if not ids or not re.fullmatch(r"[0-9]+", ids[-1]):
            err(f"ERROR: #{number} has no comments; nothing to edit")
            return 2
        resolved.append(f"comment:{ids[-1]}")
    resolved = list(dict.fromkeys(resolved))   # a target named twice is edited once
    picks = list(dict.fromkeys(picks))
    _remove_stale_work_dirs()   # every mode, not only --correct, leaves runs holding old text
    scrub = _scrub_tier(repo)
    run = tempfile.mkdtemp(prefix=RUN_PREFIX)   # mode 0700
    with open(os.path.join(run, "body.md"), "w", encoding="utf-8", newline="") as fh:
        fh.write(state["body_input"])
    meta = {"mode": state["mode"], "scope": state["scope_flag"], "section": state["section_flag"],
            "reason": state["reason"], "override": state["override"], "repo": repo, "scrub": scrub,
            "targets": resolved, "picks": picks}
    with open(os.path.join(run, "run.json"), "w", encoding="utf-8") as fh:
        json.dump(meta, fh)
    print(f"RUN={run}")
    print(f"REPO={repo}")
    print(f"SCRUB={scrub}")
    for target in resolved:
        print(f"TARGET={target}")
    for number in picks:
        print(f"PICK=#{number}")
    return 0


def _run_args(argv, *flags):
    """(run dir, target, {flag: value}) or None when the call is malformed."""
    run, rest = _take_flag(argv, "--run")
    target, rest = _take_flag(rest, "--target")
    values = {}
    for flag in flags:
        values[flag], rest = _take_flag(rest, flag)
    real = _own_run_dir(run)
    if rest or real is None or not _TARGET_RE.fullmatch(target or ""):
        return None
    return real, target, values


def prepare_subcmd(argv):
    parsed = _run_args(argv, "--pick")
    if parsed is None:
        err("ERROR: prepare requires --run <RUN> --target <TARGET> [--pick <N>], as run-start printed them")
        return 2
    real, target, values = parsed
    meta = _run_meta(real)
    pick = values["--pick"] or ""
    if pick and not re.fullmatch(r"[0-9]{1,18}", pick):
        err(f"ERROR: --pick takes an issue number (got: {pick})")
        return 2
    if pick:
        pick = str(int(pick))   # #007 is #7 (verify #351 round 10)
    rows = dict(_latest(real))
    if pick:
        # A PICK is settled by its own record: which #N chose which comment,
        # checked to be that issue's comment (verify #351 round 9: counting
        # extra targets named the wrong #N, or let a wrong one through).
        if pick not in meta["picks"] or f"#{pick}" in rows or any(r.get("pick") == pick for r in rows.values()):
            err(f"ERROR: #{pick} is not an open PICK of this run")
            return 2
        readable, issue = (_comment_issue(meta["repo"], target.split(":", 1)[1])
                           if target.startswith("comment:") else (True, None))
        if not readable:
            # not recorded: the PICK stays open for a retry (verify #351 round 10)
            err(f"✗ cannot read {target} — nothing changed; #{pick} can be prepared again")
            print("RESULT=refused")
            print("REASON=fetch-failed")
            return 4
        if issue != pick:
            err(f"✗ {target} is not a comment of #{pick} — nothing changed")
            _record(real, f"#{pick}", "refused", reason="not-in-pick")
            print("RESULT=refused")
            print("REASON=not-in-pick")
            return 4
        if target in rows:
            # the pick names a target this run already has: settled by it
            _record(real, f"#{pick}", "merged", via=target)
            print(f"RESULT=merged")
            return 0
    elif target not in meta["targets"]:
        err(f"ERROR: {target} is not a target of this run; run-start printed its targets "
            "(a comment chosen for a PICK=#N is prepared with --pick N)")
        return 2
    if target in rows:
        err(f"ERROR: {target} was already prepared in this run")
        return 2
    if meta["mode"] == "--correct":
        with open(os.path.join(real, "body.md"), encoding="utf-8", newline="") as fh:
            content = fh.read()
        kind, num = target.split(":", 1)
        # the run and the working copies its ledger names are the run's own
        keep = {real} | {os.path.realpath(r["work"]) for r in rows.values() if r.get("work")}
        rc, out = _captured(_correct_prepare_text, target, kind, num, meta["repo"],
                            meta["section"] or None, meta["scrub"], content, keep)
        result = _kv(out)
        if rc == 0:
            _record(real, target, "prepared", work=result.get("WORK"), pick=pick)
        elif not (pick and result.get("REASON") in _UNREAD):
            # a PICK whose comment could not be read stays open (round 11)
            _record(real, target, "refused", reason=result.get("REASON") or "check-failed", pick=pick)
        return rc
    kind, num = target.split(":", 1)
    if kind != "comment":
        err("Refuse: an issue:<N> target is only accepted with --correct")
        return 2
    return _edit_prepare(real, meta, target, num, pick)


# a read that failed: a PICK it happened on stays open for a retry (rounds 11–12)
_UNREAD = ("fetch-failed", "author-unknown")


def _edit_refused(real, target, reason, pick=""):
    if not (pick and reason in _UNREAD):
        # a PICK whose comment could not be read stays open (round 11)
        _record(real, target, "refused", reason=reason, pick=pick)
    print("RESULT=refused")
    print(f"REASON={reason}")
    return 4


def _edit_backup(num, text):
    """A copy of the comment before the edit, kept after the run so it can be
    put back: <temp dir>/idd-edit-backup/comment-<id>-<unix time>.md."""
    base = _backup_dir()
    if base is None:
        return None
    stem = f"comment-{num}-{int(datetime.datetime.now().timestamp())}"
    for k in range(1, 100):
        path = os.path.join(base, stem + ("" if k == 1 else f"-{k}") + ".md")
        try:
            fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
        except FileExistsError:
            continue
        except OSError:
            return None
        with os.fdopen(fd, "w", encoding="utf-8", newline="") as fh:
            fh.write(text)
        return path
    return None


def _backup_dir():
    """<temp dir>/idd-edit-backup, private to this user. 3.4.0 made it with
    `mkdir -p` (0755): ours, so it is tightened rather than refused, which
    failed every edit after an upgrade on Linux (verify #351 round 8). One
    owned by someone else, or a symlink, is not used; a per-user name is."""
    root = os.path.realpath(tempfile.gettempdir())
    for name in (BACKUP_DIR_NAME, f"{BACKUP_DIR_NAME}-{os.getuid()}"):
        base = os.path.join(root, name)
        try:
            os.makedirs(base, mode=0o700, exist_ok=True)
            st = os.lstat(base)
        except OSError:
            continue
        if os.path.islink(base) or not os.path.isdir(base) or st.st_uid != os.getuid():
            continue
        if st.st_mode & 0o077:
            try:
                os.chmod(base, 0o700)
            except OSError:
                continue
        return base
    # Both names taken by someone else (a shared /tmp): a fresh private one,
    # printed as BACKUP= like any other (verify #351 round 9).
    try:
        return tempfile.mkdtemp(prefix=f"{BACKUP_DIR_NAME}-")
    except OSError:
        return None


def _backup_ref(path):
    """How a --replace marker names its backup: the directory and file name,
    not the machine's temp path (it was published, and refused by egress when
    the temp dir sits under /Users — verify #351 round 8)."""
    return os.path.join(os.path.basename(os.path.dirname(path)), os.path.basename(path))


def _edit_compose(meta, old_text, body_path, backup, work):
    """(reason or None, new body) for --append / --replace / --prepend-note —
    the text the skill's Step 4 built in bash before (#351 round 9)."""
    with open(body_path, encoding="utf-8", newline="") as fh:
        body_input = fh.read()
    mode, reason = meta["mode"], meta["reason"]
    today = datetime.date.today().isoformat()   # local date, as `date +%Y-%m-%d`
    old = old_text.rstrip("\n")                  # as $(cat file) read it
    if mode == "--append":
        rc, marker = _audit_marker(["edit", "mode=append"])
        text = f"{old}\n\n---\n\n**Edit {today}**: {reason}\n\n{body_input}\n\n{marker}"
    elif mode == "--prepend-note":
        rc, marker = _audit_marker(["edit", "mode=prepend-note"])
        text = f"> ⚠️ **Edit {today}**: {reason}\n\n---\n\n{old}\n\n{marker}"
    elif meta["scope"] == "whole-comment":
        rc, marker = _audit_marker(["edit", "mode=replace", "scope=whole-comment", f"backup={_backup_ref(backup)}"])
        text = f"{body_input}\n\n{marker}"
    else:
        repl = os.path.join(work, "replacement.md")
        old_file = os.path.join(work, "old.md")
        with open(repl, "w", encoding="utf-8", newline="") as fh:
            fh.write(body_input + "\n")
        import contextlib
        import io
        buf = io.StringIO()
        with contextlib.redirect_stdout(buf):
            src = section_replace_subcmd([old_file, meta["section"], repl])
        if src != 0:
            return {8: "parser-unavailable", EXIT_AMBIGUOUS: "section-ambiguous"}.get(src, "section-not-found"), None
        rc, marker = _audit_marker(["edit", "mode=replace", f"section={meta['section']}", f"backup={_backup_ref(backup)}"])
        text = f"{buf.getvalue().rstrip(chr(10))}\n\n{marker}"
    if rc != 0:
        return "check-failed", None
    if meta["override"] == "true":
        rc, override = _audit_marker(["override", f"mode={mode[2:]}", f"reason={reason}"])
        if rc != 0:
            return "check-failed", None
        text += f"\n\n{override}"
    return None, text + "\n"


def _edit_prepare(real, meta, target, num, pick=""):
    repo = meta["repo"]
    rc = validate_target_subcmd([num, repo, meta["override"], meta["mode"]])
    if rc == 4:
        return _edit_refused(real, target, "R5", pick)
    if rc != 0:
        return _edit_refused(real, target, "author-unknown" if rc == 1 else "check-failed", pick)
    work = os.path.join(real, f"comment-{num}")
    # the target has no record yet: a copy here is from a PICK attempt whose
    # read failed and was not recorded (round 11)
    shutil.rmtree(work, ignore_errors=True)
    os.mkdir(work, 0o700)
    old = os.path.join(work, "old.md")
    if not _fetch_body(_endpoint("comment", num, repo), old):
        err(f"✗ cannot read {target} — nothing changed")
        return _edit_refused(real, target, "fetch-failed", pick)
    ok, mentions = _existing_mentions(old)
    if not ok:
        return _edit_refused(real, target, "egress", pick)
    with open(old, encoding="utf-8", newline="") as fh:
        old_text = fh.read()
    backup = _edit_backup(num, old_text)
    if backup is None:
        err(f"✗ cannot write the backup of {target} — nothing changed")
        return _edit_refused(real, target, "stage-failed", pick)
    reason, new_text = _edit_compose(meta, old_text, os.path.join(real, "body.md"), backup, work)
    if reason:
        return _edit_refused(real, target, reason, pick)
    new = os.path.join(work, "new.md")
    with open(new, "w", encoding="utf-8", newline="") as fh:
        fh.write(new_text)
    diff = os.path.join(work, "diff.txt")
    _write_diff(old, new, diff)
    # The egress gates run before the preview, so a body gh-egress would refuse
    # is never shown for confirmation (round 9; --correct did this since round 3).
    floor = _floor(meta["scrub"], new)
    if _egress(["check", "--body-file", new, "--scrub-attested", floor]
               + _mention_args(mentions)) != 0:
        return _edit_refused(real, target, "egress", pick)
    with open(os.path.join(work, "state.json"), "w", encoding="utf-8") as fh:
        json.dump({"sha": _sha256(new), "old_sha": _sha256(old), "mentions": mentions}, fh)
    _record(real, target, "prepared", backup=backup, pick=pick)
    print(f"PREVIEW={new}")
    print(f"DIFF={diff}")
    print(f"BACKUP={backup}")
    _print_floor(new)
    return 0


def _print_floor(path):
    """FLOOR=272 when the body falls under #272, at any tier. No SCRUB= line:
    the agent copies SCRUB= into apply, and a printed warn would skip the
    question (verify #351 round 12); it attests warn itself once asked."""
    if _reply_272(path):
        print("FLOOR=272")


def apply_subcmd(argv):
    parsed = _run_args(argv, "--scrub-attested", "--state")
    if parsed is None:
        err("ERROR: apply requires --run <RUN> --target <TARGET> --scrub-attested <SCRUB> [--state <STATE>]")
        return 2
    real, target, values = parsed
    meta = _run_meta(real)
    attested = values["--scrub-attested"]
    if attested not in _SCRUB_LEVELS or _SCRUB_LEVELS.index(attested) > _SCRUB_LEVELS.index(meta["scrub"]):
        # _SCRUB_LEVELS runs strictest first; a review may raise the tier, never lower it (round 8)
        err(f"ERROR: --scrub-attested must be this run's tier ({meta['scrub']}) or stricter, given after "
            "the privacy self-review of the preview (rules/privacy-scrubbing.md)")
        return 2
    meta = dict(meta, scrub=attested)
    last = dict(_latest(real)).get(target)
    if not last or last["outcome"] != "prepared":
        err(f"ERROR: {target} has no prepared edit in this run")
        return 2
    prepared = (os.path.join(last["work"], "preview.md") if last.get("work")
                else os.path.join(real, f"comment-{target.split(':', 1)[1]}", "new.md"))
    if os.path.isfile(prepared) and _floor(attested, prepared) != attested:
        # Not recorded: retried with --scrub-attested warn once the user has
        # answered the #272 question (verify #351 round 11).
        err(f"ERROR: {target} quotes user-pasted points (#272): ask the user whether that third-party "
            "text may be posted, then pass --scrub-attested warn (or enforce)")
        return 2
    if meta["mode"] == "--correct":
        work = _own_work_dir(last.get("work"), any_parent=True)
        if work is None:
            err(f"ERROR: the working copy of {target} is gone; run /idd-edit again")
            return 2
        state = values["--state"] or ""
        if _sha256(os.path.join(work, "state.json")) != state:
            # A mistyped STATE is retried, not recorded: the preview the user
            # confirmed is still there (round 8).
            err(f"ERROR: --state is not the STATE= prepare printed for {target}; copy it again")
            return 2
        try:
            rc, out = _captured(_correct_apply, work, state, attested)
        except Exception as exc:   # noqa: BLE001 — before the archive (after it, _correct_apply reports)
            err(f"✗ {target}: {type(exc).__name__}: {exc} — nothing archived or written")
            rc, out = 4, "RESULT=refused\nREASON=check-failed\n"
            print(out, end="")
        finally:
            shutil.rmtree(work, ignore_errors=True)
        result = _kv(out)
        outcome = result.get("RESULT") if result.get("RESULT") in ("edited", "write-failed", "unverified") else "refused"
        _record(real, target, outcome, reason=result.get("REASON"), backup_id=result.get("BACKUP_ID"), url=result.get("URL"))
        return rc
    stage = {"writing": False}
    try:
        return _edit_apply(real, meta, target, stage)
    except Exception as exc:   # noqa: BLE001 — report what is known
        if not stage["writing"]:
            err(f"✗ {target}: {type(exc).__name__}: {exc} — nothing written")
            return _edit_refused(real, target, "check-failed")
        err(f"⚠ {target}: {type(exc).__name__}: {exc} — the write may have happened; check it by hand")
        _record(real, target, "unverified", reason="exception")
        print("RESULT=unverified")
        return 7


def _edit_apply(real, meta, target, stage):
    num = target.split(":", 1)[1]
    work = os.path.join(real, f"comment-{num}")
    with open(os.path.join(work, "state.json"), encoding="utf-8") as fh:
        st = json.load(fh)
    new = os.path.join(work, "new.md")
    if _sha256(new) != st["sha"]:
        err(f"✗ the prepared body of {target} changed after the preview — nothing written")
        return _edit_refused(real, target, "differs-from-preview")
    # What prepare checked, checked again right before the write, as --correct
    # does: the author gate, then the target itself — an edit made after the
    # preview would otherwise be overwritten with the old text (round 9).
    rc = validate_target_subcmd([num, meta["repo"], meta["override"], meta["mode"]])
    if rc != 0:
        return _edit_refused(real, target, "R5" if rc == 4 else ("author-unknown" if rc == 1 else "check-failed"))
    endpoint = _endpoint("comment", num, meta["repo"])
    current = os.path.join(work, "current.md")
    if not _fetch_body(endpoint, current):
        err(f"✗ cannot re-read {target} — nothing written")
        return _edit_refused(real, target, "fetch-failed")
    if _sha256(current) != st["old_sha"]:
        err(f"✗ {target} changed since the preview — nothing written; run again to see the new version")
        return _edit_refused(real, target, "changed-since-preview")
    tier = meta["scrub"]
    print(f"SCRUB={tier}")   # the tier the write goes out at
    stage["writing"] = True
    rc = _egress(["edit-comment", num, "--repo", meta["repo"], "--body-file", new,
                  "--scrub-attested", tier] + _mention_args(st["mentions"]))
    if rc >= 10:
        # wrapper refusal band (#227): its own bucket, warn-continue (#273).
        # The run's exit is idd-edit's own space (any refusal = 4); the band
        # (10–15) is consumed per comment — per-comment 分類消費 band（10–15）.
        _record(real, target, "egress-refused", reason=f"rc={rc}")
        print("RESULT=refused")
        print("REASON=egress")
        return 4
    if rc != 0:
        after = os.path.join(work, "after.md")
        readable = _fetch_body(endpoint, after)
        if readable and _sha256(after) == st["old_sha"]:
            err(f"✗ gh failed the write for {target} (rc={rc}); re-read shows it unchanged")
            _record(real, target, "write-failed", reason=f"rc={rc}")
            print("RESULT=write-failed")
            return 4
        why = "no longer reads as before" if readable else "could not be read again"
        err(f"⚠ gh reported a failed write for {target} (rc={rc}), but the target {why} — check it by hand")
        _record(real, target, "unverified")
        print("RESULT=unverified")
        return 7
    readback = os.path.join(work, "readback.md")
    confirmed = _fetch_body(endpoint, readback)
    if confirmed:
        with open(readback, "rb") as fh, open(new, "rb") as fn:
            confirmed = fh.read() == fn.read()
    if not confirmed:
        err(f"⚠ {target} was written but does not read back as sent — check it by hand")
        _record(real, target, "unverified")
        print("RESULT=unverified")
        return 7
    proc = _gh(["api", endpoint, "--jq", ".html_url"])
    url = proc.stdout.decode("utf-8", errors="replace").strip() if proc is not None and proc.returncode == 0 else ""
    _record(real, target, "edited", url=url)
    print("RESULT=edited")
    print(f"URL={url}")
    return 0


def discard_subcmd(argv):
    parsed = _run_args(argv)
    if parsed is None:
        err("ERROR: discard requires --run <RUN> --target <TARGET>, as run-start printed them")
        return 2
    real, target, _ = parsed
    last = dict(_latest(real)).get(target)
    if not last or last["outcome"] != "prepared":
        err(f"ERROR: {target} has no prepared edit in this run")
        return 2
    if last.get("work"):
        work = _own_work_dir(last["work"], any_parent=True)
        if work:
            shutil.rmtree(work, ignore_errors=True)
    else:
        shutil.rmtree(os.path.join(real, f"comment-{target.split(':', 1)[1]}"), ignore_errors=True)
    _record(real, target, "declined")
    print("RESULT=declined")
    return 0


def finish_subcmd(argv):
    run, rest = _take_flag(argv, "--run")
    real = _own_run_dir(run)
    if rest or real is None:
        err("ERROR: finish requires --run <RUN>, as run-start printed it")
        return 2
    rows = _latest(real)
    meta = _run_meta(real)
    # A target run-start listed but nobody prepared, or a #N nobody picked, is
    # not a success (round 8: a half-done batch reported 0).
    seen = {t for t, _ in rows}
    settled = {r.get("pick") for _, r in rows if r.get("pick")} | {t[1:] for t in seen if t.startswith("#")}
    rows += [(t, {"target": t, "outcome": "refused", "reason": "not-prepared"})
             for t in meta["targets"] if t not in seen]
    rows += [(f"#{n}", {"target": f"#{n}", "outcome": "refused", "reason": "not-picked"})
             for n in meta["picks"] if n not in settled]
    for target, rec in rows:
        if rec["outcome"] == "prepared":
            # Prepared but neither applied nor discarded: nothing was written,
            # and a --correct working copy holds the wrong text — remove it.
            work = _own_work_dir(rec.get("work"), any_parent=True) if rec.get("work") else None
            if work:
                shutil.rmtree(work, ignore_errors=True)
            # Never confirmed: counted with the declines (9), so a caller such
            # as idd-comment does not act on an abandoned preview (round 11).
            rec.update(outcome="declined", reason="not-applied")
    shutil.rmtree(real, ignore_errors=True)
    count = {o: sum(1 for _, r in rows if r["outcome"] == o) for o in _OUTCOMES}
    refused = count["refused"] + count["egress-refused"]
    print("── idd-edit batch outcome ──")
    print(f"edited: {count['edited']} / refused: {refused}")
    for target, rec in rows:
        o, why = rec["outcome"], rec.get("reason", "")
        if o == "merged":
            print(f"  = {target} → {rec.get('via', '')}（已在這次執行裡）")
        elif o == "edited":
            print(f"  ✓ EDITED {target}" + (f"  {rec['url']}" if rec.get("url") else "")
                  + (f"（#{rec['pick']}）" if rec.get("pick") else ""))
        elif o == "refused":
            hint = ""
            if why == "R5" and meta["mode"] != "--correct":
                hint = "（override: --override-user-content --reason='...'）"   # --correct has none
            print(f"  ✗ REFUSED({why or 'check-failed'}) {target}{hint}")
        elif o == "egress-refused":
            print(f"  ✗ REFUSED(egress) {target} {why} — band 語意見 #227（10 privacy / 11 mention / 13 tier-floor #272 / 15 empty-body #275）")
        elif o == "declined" and why == "not-applied":
            print(f"  – DECLINED {target}（預覽後沒有寫入：沒有完成 apply，也沒有 discard）")
        elif o == "declined":
            print(f"  – DECLINED {target}（使用者在預覽時拒絕，未寫入）")
        elif o == "write-failed":
            print(f"  ✗ FAILED(write) {target}（gh 自身錯誤，重讀確認未寫入）")
        elif o == "unverified":
            print(f"  ⚠ UNVERIFIED {target}（已寫入，但重讀失敗或內容不符 — 請手動確認）")
        if rec.get("backup_id"):
            print(f"    backup id: {rec['backup_id']}")
    if not rows:
        print("  nothing was prepared")
        return 4
    # First match wins. idd-comment's errata path routes on these; none
    # overlaps an argument error (2 / 3 / 5 come from run-start).
    if refused or count["write-failed"]:
        return 4
    if count["unverified"]:
        return 7
    if count["declined"]:
        return 9
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
    A missing value or a value starting with '--' yields value "" (usage error).
    An explicit empty word (`--state ""`) is the value "" and is consumed —
    before, it stayed in rest and the call was a usage error (verify #351 round 8)."""
    rest, value, i = [], None, 0
    while i < len(argv):
        a = argv[i]
        if a == flag:
            has_next = i + 1 < len(argv) and not argv[i + 1].startswith("--")
            value = argv[i + 1] if has_next else ""
            i += 2 if has_next else 1
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


def _archived_versions(target, repo):
    """[(backup id, whether the target still carries its marker)] for every
    archive entry this clone holds for the target and this repository, oldest
    first, or None when the target cannot be read. The archive is the source,
    not the markers: a --replace or a restore removes a correction's marker
    from GitHub while its archived text stays restorable (verify #351 round
    11). Nothing from GitHub reaches a shell; the markers only annotate."""
    kind, num = target.split(":", 1)
    work = tempfile.mkdtemp(prefix=CORRECT_WORK_PREFIX)
    try:
        body = os.path.join(work, "current.md")
        if not _fetch_body(_endpoint(kind, num, repo), body):
            return None
        with open(body, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
    finally:
        shutil.rmtree(work, ignore_errors=True)
    marked = {found for m in CORRECT_MARKER_RE.finditer(text)
              for found in re.findall(r'backup-id="([^"]*)"', m.group(0))}
    want = f"comment-{num}" if kind == "comment" else f"issue-{num}-body"
    edits = os.path.join(_main_worktree(), ARCHIVE_REL)
    try:
        names = sorted(os.listdir(edits))
    except OSError:
        names = []
    versions = []
    for name in names:
        idm = BACKUP_ID_RE.fullmatch(name[:-3]) if name.endswith(".md") else None
        if not idm or idm.group(1) != want:
            continue
        path = os.path.join(edits, name)
        side = path[:-3] + ".repo"
        if (os.path.islink(path) or not os.path.isfile(path)
                or os.path.islink(side) or not os.path.isfile(side)):
            continue
        try:
            with open(side, encoding="utf-8") as fh:
                if fh.read().strip() != repo:
                    continue
        except OSError:
            continue
        versions.append((name[:-3], name[:-3] in marked))
    # oldest first: the time, then the -N a same-second write got (round 12)
    def order(version):
        suffix = BACKUP_ID_RE.fullmatch(version[0]).group(2) or ""
        return (version[0][: len(version[0]) - len(suffix)], int(suffix[1:]) if suffix else 1)
    return sorted(versions, key=order)


def restore_subcmd(argv):
    repo, rest = _take_flag(argv, "--repo")
    target, rest = _take_flag(rest, "--target")
    if target is not None:
        if rest or not _TARGET_RE.fullmatch(target) or not repo or not _REPO_RE.fullmatch(repo) or ".." in repo:
            err("ERROR: restore requires --target comment:<id>|issue:<n> --repo <owner/repo>")
            return 2
        root = _main_worktree()
        if root is None:
            err("Refuse: restore needs the git work tree that holds the archive.")
            return 7
        # what restore <id> refuses, the lookup does not offer (round 12)
        problem = _archive_path_problem(root) or _tracks_archive(root)
        if problem:
            err(f"Refuse: {problem}, so its entries are not this helper's; nothing is offered.")
            return 2
        versions = _archived_versions(target, repo)
        if versions is None:
            err(f"✗ cannot read {target}; nothing was restored")
            return 1
        if not versions:
            err(f"ERROR: this clone holds no archived version of {target} for {repo}")
            return 2
        # A lookup, never a write: the user confirms the version (verify #351
        # round 10). Each id puts back the text from before that correction.
        err(f"{target}: {len(versions)} archived version(s), oldest first. Each puts back the text "
            "from before that correction (the id carries its UTC time). Show them to the user and run "
            "`restore '<BACKUP_ID>' --repo …` with the one they confirm:")
        for bid, marked in versions:
            print(f"BACKUP_ID={bid}")
            err(f"  {bid}  marker: {'on the target' if marked else 'gone'}")
        return 0
    if len(rest) != 1 or not repo:
        err("ERROR: restore requires <backup-id> --repo <owner/repo> (or --target <target> --repo <owner/repo>)")
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
      override flag is "true"; mode --correct passes only the gh user's own content.

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
  restore --target comment:<id>|issue:<n> --repo <owner/repo>
      Look up only: print BACKUP_ID= for each version this clone archived for the
      target and repository, oldest first (stderr says whether its marker is still
      on the target; the user then confirms one); exit 1 when the target cannot be
      read, 2 when there is none, 7 outside the git work tree.

Exit codes:
  0=success, 1=generic, 2=usage, 3=R4-refuse, 4=R5-refuse (correct-*: not done),
  5=unreadable-file, 6=protected-region, 7=archive-refused (correct-apply:
  written but unverified), 8=markdown-parser-unavailable, 9=ambiguous-section

  existing-mentions <file>
      Print, comma-separated, the logins the file already mentions (gh-egress's scan).

  correct-prepare --target comment:<id>|issue:<n> --repo R (--section H | --scope whole-comment)
                  --body-file F --scrub-attested L
      The whole --correct flow up to the preview; prints WORK=, PREVIEW=, DIFF= and
      STATE= (the caller keeps WORK and STATE for the next call). Refusals print
      RESULT=refused and REASON= (archive, fetch-failed, R5, author-unknown, protected,
      setext, unclosed-block, empty, section-not-found, section-ambiguous,
      parser-unavailable, egress, check-failed).
  correct-apply --work <dir> --state <digest>
      Re-check, re-read, archive, write and read back byte for byte; prints RESULT=
      (edited | refused | write-failed | unverified), REASON=, BACKUP_ID=, URL=.
  correct-discard --work <dir>   Throw the prepared correction away (the user declined).

One /idd-edit run, all modes (the skill calls only these; #351 round 9):
  run-start [--default-repo owner/repo] -- <the /idd-edit arguments>
      Parse (R4 and the other parse-args gates), resolve the targets and the privacy
      tier; prints RUN=, REPO=, SCRUB=, then TARGET= (and PICK=#N to choose from).
  prepare --run RUN --target T [--pick N]
      Author gate, fetch, backup, compose, egress check; prints PREVIEW=, DIFF= and
      BACKUP= (or WORK=, PREVIEW=, DIFF=, STATE= for --correct), or RESULT=refused.
      Takes a target run-start listed, or with --pick N a comment of issue N chosen
      for PICK=#N (REASON=not-in-pick otherwise; RESULT=merged when it is a listed
      target; an unreadable comment is fetch-failed and the PICK stays open).
  apply --run RUN --target T --scrub-attested SCRUB [--state STATE]
      Write after the user confirmed; prints RESULT= (edited | refused | write-failed |
      unverified). SCRUB is the run's tier or stricter, attested after the privacy
      review. A reply quoting user-pasted points (#272): prepare prints FLOOR=272 at
      any tier, the user answers the #272 question, and apply refuses light for it
      (exit 2) — attest warn instead.
  discard --run RUN --target T   The user declined.
  finish --run RUN
      Print the outcome report, remove the run; exit 4 refused or failed, 7 unverified,
      9 declined (a prepared target never applied or discarded included), 0 otherwise.
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
    if subcmd == "run-start":
        return run_start_subcmd(rest)
    if subcmd == "prepare":
        return prepare_subcmd(rest)
    if subcmd == "apply":
        return apply_subcmd(rest)
    if subcmd == "discard":
        return discard_subcmd(rest)
    if subcmd == "finish":
        return finish_subcmd(rest)
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
