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
be made to disagree (a path or a flag assembled from variables, globs, brace
expansion, the escapes inside $'…', eval, another program that changes modes
such as a python -c one-liner). Those differentials are accepted: the file
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

A recursive permission change would undo the second layer, after which a
recursive read gets the files (round 3). A command that holds a permission
command (chmod, chown, chgrp, chflags, setfacl) and a recursive marker (-R,
--recursive, -Recurse, or find / xargs / fd / ForEach-Object) is therefore
refused from inside a repository that holds the archive, whatever its target;
elsewhere it is refused when any word is the archive, a repository root that
holds one, or a folder directly above such a repository, or when the command
holds something the guard cannot resolve ($, a backtick, a glob or brace
character, quotes shlex cannot balance). The words are not attributed to
commands: every attempt to do so was beaten (rounds 18–20). A directory more
than one level above a repository is not searched from outside it. The file
~/.cache/idd/archive-read-guard.disabled, created by a human, turns the guard
off.

Input that is not a JSON object is allowed (a note goes to stderr): a bug in
the caller must not block every tool call in the session, and the file mode
still protects the archive. An error while checking a well-formed call denies
that call (round 20).
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
    "Blocked: a recursive permission change (chmod, chown, chgrp, chflags or "
    "setfacl with -R / --recursive, or run by find, xargs, fd or ForEach-Object). "
    "Inside a repository that holds the IDD correction archive every one is "
    "refused, and elsewhere one whose target is the archive, a directory above "
    "it, or something the guard cannot resolve (a variable, a glob, a command "
    "substitution) — the archive files are mode 0000 so that no recursive read "
    "reaches them (#351). Change the files you mean without -R (for example "
    "chmod u+x path/to/file), and search text with the Grep tool rather than a "
    "shell command that mentions chmod -R."
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


# Every Bash / PowerShell / Monitor command is read as flat text: quotes removed and
# escapes resolved, as the shell joins its words (`arch\ive`, `arch""ive` and
# `'a b'`), then cut into path-like pieces. Nothing is skipped — not a commit
# message, a comment or a heredoc body — so a command that only mentions the
# path is denied too, and such text goes in a file (-F, --body-file). Verify
# #351 rounds 3–16 let message values through, which needed a model of shell
# word splitting; every rewrite of that model opened a new way past the guard,
# so the guard fails closed instead (user decision 2026-10-18).
PERMISSION_COMMANDS = ("chmod", "chown", "chgrp", "chflags", "setfacl", "gchmod", "gchown", "gchgrp")
# commands that apply another command to a whole tree, as -R does
_TREE_WALKERS = ("find", "xargs", "fd", "foreach-object")
# -R in a short-flag cluster (capital R only: -r is not recursive for these
# commands), --recursive and its GNU abbreviations (--rec…), PowerShell -Recurse
_RECURSIVE = re.compile(r"-[A-Za-z]*R[A-Za-z]*|(?i:--rec[a-z]*|-recurse)")
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
        command = command.replace("`\r\n", "`\n")
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
    """True if `target` is the archive or inside it, a repository root that
    holds one (or its .claude / .claude/.idd), or a folder whose direct
    subdirectory is such a repository (`..` from a sibling repository).
    A directory further up is not searched (round 20)."""
    if _hits(_norm_path(target)):
        return True
    for suffix in (NEEDLE, ".idd/archive", "archive"):
        candidate = os.path.join(target, suffix)
        if os.path.isdir(candidate) and _hits(_norm_path(candidate)):
            return True
    try:
        children = os.listdir(target) if os.path.isdir(target) else ()
    except OSError:
        return False
    return any(os.path.isdir(os.path.join(target, c, NEEDLE)) for c in children)


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
    whole and glued operators trimmed (`"a b";`), or None when shlex cannot
    split it (round 19–20)."""
    try:
        words = shlex.split(text.replace("\\", "/") if powershell else text)
    except ValueError:
        return None
    return [w.strip(";&|()<>") for w in words]


def _permission_change_in(text, cwd, powershell=False):
    """A recursive permission change that could reach the archive, in one
    reading. A permission command and a recursive marker (-R, --recursive and
    its abbreviations, -Recurse, or a tree walker such as find / xargs / fd /
    ForEach-Object) anywhere in the command make it one; the words are not
    attributed to commands (round 20: every attribution rule was beaten).
    - From inside a repository that holds the archive, every such command is
      refused, whatever its target.
    - Elsewhere, every word counts as a target — the flat pieces and the
      shell's whole words — and the command is refused when one is the archive
      or a directory above it, or when a target cannot be resolved: a
      variable, a command substitution, a glob or brace pattern, or quotes
      shlex cannot balance."""
    flat = [w for w in re.split(r"[\s;&|<>()`{}]+", _flat(text, powershell)) if w]
    names = {os.path.basename(w).casefold() for w in flat}
    if not names & set(PERMISSION_COMMANDS):
        return False
    if not (names & set(_TREE_WALKERS) or any(_RECURSIVE.fullmatch(w) for w in flat)):
        return False
    if _archives_around(cwd):
        return True
    if re.search(r"[$`*?\[{]", text):
        return True
    shell = _shell_words(text, powershell)
    if shell is None:
        return True
    for w in flat + shell:
        if not w or w.startswith("-"):
            continue
        if _archive_below(os.path.normpath(os.path.join(cwd, os.path.expanduser(w)))):
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
    try:
        if any(_hits(c) for c in _candidates(tool, tool_input)):
            reason = REASON
        elif command and _recursive_permission_change(command, cwd, tool == "PowerShell"):
            reason = PERMISSION_REASON
    except Exception as exc:   # noqa: BLE001 — fail closed on this call (round 20)
        print(f"archive-read-guard: could not check this call ({type(exc).__name__}: {exc}); denying", file=sys.stderr)
        reason = ("Blocked: the IDD archive read guard could not check this call (see stderr); "
                  "rephrase the command, or create ~/.cache/idd/archive-read-guard.disabled to turn the guard off.")
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
