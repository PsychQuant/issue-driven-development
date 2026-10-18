#!/usr/bin/env python3
"""archive-read-guard.py — PreToolUse hook: keep Claude's tools out of the
correction archive (#351).

`/idd-edit --correct` archives the prior version of a corrected comment or
issue body under `.claude/.idd/archive/edits/`. Those files hold content the
user confirmed to be wrong; an AI session that reads them inherits the error
again, which is the failure #351 exists to stop.

This hook is the first of two layers. It denies any Read / Grep / Glob / Edit /
Write / NotebookEdit call whose path argument points into the archive, and any
Bash / PowerShell command whose text names it. It can only compare strings, so
a recursive read that never spells the path (`grep -r .`) passes here; the
second layer — archive files are mode 0000 — covers that case.

Threat model: accidental reads, not an agent deliberately working around the
guard. This hook parses the command with Python's shlex while the shell runs
it, so the two can always be made to disagree (a path assembled from
variables, ANSI-C escapes, eval). Those differentials are accepted: the file
mode is what guarantees an unreadable archive; this hook only stops the
ordinary `cat`/`grep`/Read that would otherwise happen by accident.

Shell commands are read as flat text — quotes removed, escapes resolved — and
cut into path-like pieces; any piece naming the archive denies the call. No
part of a command is exempt: a commit message, an issue body, a comment or a
heredoc that only mentions the path is denied too, and goes in a file instead
(-F, --body-file). Earlier rounds exempted message values, which needed a model
of shell word splitting that could always be made to disagree with the shell
(verify #351 rounds 3–16; fail-closed by user decision 2026-10-18).

A recursive permission change (chmod/chown/chgrp/chflags/setfacl with -R) on
the archive or any directory above it is denied too: it would undo the second
layer, after which a recursive read gets the files (round 3). The file ~/.cache/idd/archive-read-guard.disabled, created
by a human, turns the guard off.

Input that cannot be parsed is allowed (a note goes to stderr): a bug in this
hook must not block every tool call in the session, and the file mode still
protects the archive.
"""
import json
import os
import re
import shlex
import sys

NEEDLE = ".claude/.idd/archive"
UNLOCK_FLAG = os.path.join("~", ".cache", "idd", "archive-read-guard.disabled")

REASON = (
    "Blocked: .claude/.idd/archive/ holds the prior versions of issue content "
    "that was corrected because it was wrong (#351). Reading it would bring the "
    "error back into this session. Do not read, search, list, copy or chmod "
    "these files. To put a corrected comment or issue body back, run the "
    "idd-edit helper's restore subcommand, which sends the archived text to "
    "GitHub without displaying it. Any command that names this path is denied, "
    "a commit message or issue body included: put such text in a file and pass "
    "it with -F or --body-file."
)

PATH_FIELDS = {
    "Read": ("file_path",),
    "Edit": ("file_path",),
    "Write": ("file_path",),
    "NotebookEdit": ("notebook_path",),
    "Grep": ("path",),
    "Glob": ("path",),
}
COMMAND_TOOLS = ("Bash", "PowerShell")


def _as_text(value):
    return value if isinstance(value, str) else ""


def _norm_path(value):
    if not value:
        return ""
    return os.path.normpath(value.replace("\\", "/")).lower()


def _hits(candidate):
    """NEEDLE as a path segment: followed by '/' or the end, so that
    `archive-notes.md` or `archived/` next to it is not mistaken for it."""
    start = candidate.find(NEEDLE)
    while start != -1:
        end = start + len(NEEDLE)
        if end == len(candidate) or candidate[end] == "/":
            return True
        start = candidate.find(NEEDLE, start + 1)
    return False


# Every Bash / PowerShell command is read as flat text: quotes removed and
# escapes resolved, as the shell joins its words (`arch\ive`, `arch""ive` and
# `'a b'`), then cut into path-like pieces. Nothing is skipped — not a commit
# message, a comment or a heredoc body — so a command that only mentions the
# path is denied too, and such text goes in a file (-F, --body-file). Verify
# #351 rounds 3–16 let message values through, which needed a model of shell
# word splitting; every rewrite of that model opened a new way past the guard,
# so the guard fails closed instead (user decision 2026-10-18).
PERMISSION_COMMANDS = ("chmod", "chown", "chgrp", "chflags", "setfacl")
# commands that apply another command to a whole tree, as -R does
_TREE_WALKERS = ("find", "xargs", "fd")
_NOT_PATH = re.compile(r"[^\w./~+@%-]+")


def _flat(command, powershell=False):
    """The command with quotes removed and escapes resolved. PowerShell paths
    use backslashes as separators, so they become `/` there instead."""
    if powershell:
        command = command.replace("\\", "/")
    else:
        command = re.sub(r"\\(.)", r"\1", command, flags=re.S)
    return command.replace("'", "").replace('"', "")


def _command_words(command, powershell=False):
    """Path candidates in a shell command: every path-like piece of its flat
    text, whatever the shell would make of the surrounding syntax."""
    for piece in _NOT_PATH.split(_flat(command, powershell)):
        if piece:
            yield _norm_path(piece)


def _archive_below(target):
    """True if `target` is the archive, inside it, or a directory above it."""
    if _hits(_norm_path(target)):
        return True
    for suffix in (NEEDLE, ".idd/archive", "archive"):
        candidate = os.path.join(target, suffix)
        if os.path.isdir(candidate) and _hits(_norm_path(candidate)):
            return True
    return False


def _archives_around(cwd):
    """Archive directories of the repositories at or above cwd."""
    found, d = [], os.path.abspath(cwd)
    while True:
        candidate = os.path.join(d, NEEDLE)
        if os.path.isdir(candidate):
            found.append(os.path.normpath(candidate))
        parent = os.path.dirname(d)
        if parent == d:
            return found
        d = parent


def _recursive_permission_change(command, cwd, powershell=False):
    """A recursive permission change (-R, --recursive, or a command run over a
    tree by find / xargs / fd) anywhere in the command, together with any word
    that is the archive or a directory above it, resolved against the tool
    call's working directory. The words are not attributed to a command: a
    command that only has both is denied too (round 18)."""
    words = [w for w in re.split(r"[\s;&|<>()`]+", _flat(command, powershell)) if w]
    if not any(os.path.basename(w) in PERMISSION_COMMANDS for w in words):
        return False
    if not any(w == "--recursive" or re.fullmatch(r"-[A-Za-z]*R[A-Za-z]*", w)
               or os.path.basename(w) in _TREE_WALKERS for w in words):
        return False
    archives = _archives_around(cwd)
    for w in words:
        if w.startswith("-"):
            continue
        target = os.path.normpath(os.path.join(cwd, os.path.expanduser(w)))
        # The archive itself, a directory just above it, or any directory
        # that contains this repository's archive (`chmod -R u+r ..`, round 4).
        if _archive_below(target) or any(
            arch == target or arch.startswith(target.rstrip(os.sep) + os.sep) for arch in archives
        ):
            return True
    return False


def _candidates(tool, tool_input):
    if tool in COMMAND_TOOLS:
        yield from _command_words(_as_text(tool_input.get("command")), tool == "PowerShell")
        return
    for field in PATH_FIELDS.get(tool, ()):
        yield _norm_path(_as_text(tool_input.get(field)))
    base = _as_text(tool_input.get("path"))
    extra = ""
    if tool == "Glob":
        extra = _as_text(tool_input.get("pattern"))
    elif tool == "Grep":
        extra = _as_text(tool_input.get("glob"))
    if extra:
        yield _norm_path(extra)
        yield _norm_path(os.path.join(base, extra) if base else extra)


def main():
    raw = sys.stdin.read()
    try:
        event = json.loads(raw)
        tool = event.get("tool_name", "")
        tool_input = event.get("tool_input") or {}
        if not isinstance(tool, str) or not isinstance(tool_input, dict):
            raise ValueError("unexpected input shape")
    except (ValueError, AttributeError) as exc:
        print(f"archive-read-guard: input not understood ({exc}); allowing", file=sys.stderr)
        return 0

    if os.path.exists(os.path.expanduser(UNLOCK_FLAG)):
        return 0  # a human created the unlock flag (archive-first style switch)

    cwd = _as_text(event.get("cwd")) or os.getcwd()
    command = _as_text(tool_input.get("command")) if tool in COMMAND_TOOLS else ""
    if any(_hits(c) for c in _candidates(tool, tool_input)) or (
        command and _recursive_permission_change(command, cwd, tool == "PowerShell")
    ):
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": REASON,
            }
        }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
