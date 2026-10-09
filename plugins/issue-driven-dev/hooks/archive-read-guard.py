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
guard.

Shell commands are checked word by word, quoted strings included (`sh -c`,
`python3 -c` read files from inside them). Only the value of a message option
(-m, --message, --body, --title, --notes, --subject) is skipped: a commit
message or issue body that mentions the path does not open it. The file ~/.cache/idd/archive-read-guard.disabled, created
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
    "GitHub without displaying it."
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


# Values of these options are prose (commit messages, issue bodies), not paths;
# they may mention the archive without reading it. Closed list — every other
# quoted string is still scanned, because `sh -c "cat <archive>"` and
# `python3 -c "open('<archive>')"` read the archive from inside a quoted string.
MESSAGE_FLAGS = ("-m", "--message", "--body", "--title", "--notes", "--subject")


def _command_words(command):
    """Path candidates in a shell command: every shell word, and every piece of
    a word split on whitespace and quoting/grouping characters — except the
    value of a message option, which is prose."""
    # Backslashes become '/' before splitting: PowerShell paths use them as
    # separators, and POSIX shlex would otherwise eat them as escapes.
    command = command.replace("\\", "/")
    try:
        words = shlex.split(command, posix=True)
    except ValueError:
        words = command.split()
    previous = ""
    for word in words:
        is_message = previous in MESSAGE_FLAGS or any(
            word.startswith(flag + "=") for flag in MESSAGE_FLAGS if flag.startswith("--")
        )
        previous = word
        # A message value is prose only if the shell will not execute part of
        # it: `--body "$(cat <archive>)"` posts the archive (parser differential
        # between shlex and the real shell).
        if is_message and not any(t in word for t in ("$(", "`", "<(", ">(")):
            continue
        for piece in re.split(r"[\s'\"`()=;|&<>]+", word):
            if piece:
                yield _norm_path(piece)


def _candidates(tool, tool_input):
    if tool in COMMAND_TOOLS:
        yield from _command_words(_as_text(tool_input.get("command")))
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

    if any(_hits(c) for c in _candidates(tool, tool_input)):
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
