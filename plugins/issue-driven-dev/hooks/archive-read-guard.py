#!/usr/bin/env python3
"""archive-read-guard.py — PreToolUse hook: keep Claude's tools out of the
correction archive (#351).

`/idd-edit --correct` archives the prior version of a corrected comment or
issue body under `.claude/.idd/archive/edits/`. Those files hold content the
user confirmed to be wrong; an AI session that reads them inherits the error
again, which is the failure #351 exists to stop.

This hook is the first of two layers. It denies any Read / Grep / Glob / Edit /
Write / NotebookEdit call whose path argument points into the archive, and any
Bash / PowerShell / Monitor command whose text names it. It can only compare strings, so
a recursive read that never spells the path (`grep -r .`) passes here; the
second layer — archive files are mode 0000 — covers that case.

Threat model: accidental reads, not an agent deliberately working around the
guard. This hook compares text while the shell runs it, so the two can always
be made to disagree (a path assembled from variables, globs, brace expansion,
eval). Those differentials are accepted: the file
mode is what guarantees an unreadable archive; this hook only stops the
ordinary `cat`/`grep`/Read that would otherwise happen by accident.

Shell commands are read as flat text — quotes removed, escapes resolved — and
cut into path-like pieces; any piece naming the archive denies the call. No
part of a command is exempt: a commit message, an issue body, a comment or a
heredoc that only mentions the path is denied too, and goes in a file instead
(-F, --body-file). Earlier rounds exempted message values, which needed a model
of shell word splitting that could always be made to disagree with the shell
(verify #351 rounds 3–16; fail-closed by user decision 2026-10-18).

Each command is checked in two readings — line continuations joined, and read
as line breaks — so either can only deny more (round 19).

A recursive permission change (chmod/chown/chgrp/chflags/setfacl with -R or
--recursive, or run by find / xargs / fd) on the archive or any directory above
it is denied too: it would undo the second layer, after which a recursive read
gets the files (round 3). The flag and the target must follow the permission
command, a quoted target with a space is one word, letter case is ignored, and
a target the guard cannot resolve (a variable, a command substitution) is
refused (rounds 18–19). The file ~/.cache/idd/archive-read-guard.disabled,
created by a human, turns the guard off.

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
    "a commit message or issue body included: leave the path out of the text, "
    "or write the text with the Write tool and pass the file with -F or "
    "--body-file (a heredoc that names the path is denied too)."
)
PERMISSION_REASON = (
    "Blocked: this looks like a recursive permission change (-R, --recursive, "
    "or find / xargs / fd running chmod, chown, chgrp, chflags or setfacl) on "
    ".claude/.idd/archive/ or a directory above it, or on a target the guard "
    "cannot resolve (a variable or a command substitution). The archive files "
    "are mode 0000 so that no recursive read reaches them (#351). Name the "
    "directories you mean explicitly, below the archive's parent; if the "
    "command does not change permissions, run its parts separately."
)

PATH_FIELDS = {
    "Read": ("file_path",),
    "Edit": ("file_path",),
    "Write": ("file_path",),
    "NotebookEdit": ("notebook_path",),
    "Grep": ("path",),
    "Glob": ("path",),
}
COMMAND_TOOLS = ("Bash", "PowerShell", "Monitor")   # Monitor runs a shell command too


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
# -R in a short-flag cluster, --recursive and its GNU abbreviations (--rec…)
_RECURSIVE = re.compile(r"-[A-Za-z]*R[A-Za-z]*|--rec[a-z]*")
_NOT_PATH = re.compile(r"[^\w./~+@%-]+")


_ESCAPE = re.compile(r"\\(.)", re.S)


def _variants(command, powershell=False):
    """Two readings of the command, both checked, so either can only deny
    more: line continuations joined (a path or a command name split by a
    backslash-newline is one word), and line continuations read as line
    breaks (inside a comment the shell does not join them). Escapes are
    scanned in pairs, so an escaped backslash before a newline is no
    continuation (round 19). PowerShell continues a line with a backtick."""
    if powershell:
        return (command.replace("`\n", ""), command.replace("`\n", "\n"))
    return (_ESCAPE.sub(lambda m: "" if m.group(1) == "\n" else m.group(0), command),
            _ESCAPE.sub(lambda m: "\n" if m.group(1) == "\n" else m.group(0), command))


def _flat(text, powershell=False):
    """One reading with quotes removed and escapes resolved: every escape
    character is dropped, nested ones included (a doubled backslash in `bash
    -c`), which can only join text; `$'…'` and `$"…"` are quotes too.
    PowerShell's escape is the backtick, and its backslashes separate paths."""
    if powershell:
        text = text.replace("`", "").replace("\\", "/")
    else:
        text = text.replace("\\", "")
    text = text.replace("$'", "'").replace('$"', '"')
    return text.replace("'", "").replace('"', "")


def _command_words(command, powershell=False):
    """Path candidates in a shell command: every path-like piece of the flat
    text of each reading, whatever the shell would make of the syntax."""
    for reading in _variants(command, powershell):
        for piece in _NOT_PATH.split(_flat(reading, powershell)):
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


def _shell_words(text, powershell=False):
    """The shell's own words of one reading, a quoted path with a space kept
    whole, as far as shlex can tell; nothing when it cannot (round 19)."""
    try:
        return shlex.split(text.replace("\\", "/") if powershell else text)
    except ValueError:
        return []


def _after_permission(words):
    """The words after the first permission command, or None without one."""
    for i, w in enumerate(words):
        if os.path.basename(w) in PERMISSION_COMMANDS:
            return words[i + 1:]
    return None


def _permission_change_in(text, cwd, powershell=False):
    """A recursive permission change on the archive or a directory above it.
    Words are not attributed to one command, but the recursive flag and the
    target must follow the permission command, as they do in one (so `grep -R
    chmod .` is a search); a tree walker (find / xargs / fd) makes the whole
    command count. A target the guard cannot resolve — a variable or a command
    substitution — denies (round 19)."""
    flat = [w for w in re.split(r"[\s;&|<>()`]+", _flat(text, powershell)) if w]
    after = _after_permission(flat)
    if after is None:
        return False
    walker = any(os.path.basename(w) in _TREE_WALKERS for w in flat)
    scope = flat if walker else after
    if not walker and not any(_RECURSIVE.fullmatch(w) for w in scope):
        return False
    if "$" in text or (not powershell and "`" in text):
        return True   # `$PWD`, `$(pwd)`, `$(git rev-parse --show-toplevel)`: unresolved, refused
    shell = _shell_words(text, powershell)
    shell_after = _after_permission(shell)
    targets = scope + ((shell if walker else shell_after) or [])
    archives = [a.casefold() for a in _archives_around(cwd)]
    for w in targets:
        if w.startswith("-"):
            continue
        target = os.path.normpath(os.path.join(cwd, os.path.expanduser(w)))
        folded = target.casefold().rstrip(os.sep)
        # The archive itself, a directory just above it, or any directory
        # that contains this repository's archive (`chmod -R u+r ..`, round 4);
        # letter case ignored, as on APFS (round 19).
        if _archive_below(target) or any(a == folded or a.startswith(folded + os.sep) for a in archives):
            return True
    return False


def _recursive_permission_change(command, cwd, powershell=False):
    """A recursive permission change in either reading of the command."""
    return any(_permission_change_in(r, cwd, powershell) for r in _variants(command, powershell))


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
    reason = None
    if any(_hits(c) for c in _candidates(tool, tool_input)):
        reason = REASON
    elif command and _recursive_permission_change(command, cwd, tool == "PowerShell"):
        reason = PERMISSION_REASON
    if reason:
        print(json.dumps({
            "hookSpecificOutput": {
                "hookEventName": "PreToolUse",
                "permissionDecision": "deny",
                "permissionDecisionReason": reason,
            }
        }))
    return 0


if __name__ == "__main__":
    sys.exit(main())
