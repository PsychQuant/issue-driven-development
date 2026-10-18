#!/usr/bin/env python3
"""archive-read-guard.py — PreToolUse hook: keep Claude's tools out of the
correction archive (#351).

`/idd-edit --correct` archives the prior version of a corrected comment or
issue body under `.claude/.idd/archive/edits/`. Those files hold content the
user confirmed to be wrong; an AI session that reads them inherits the error
again, which is the failure #351 exists to stop.

This hook is the first of two layers. It denies any Read / Grep / Glob / Edit /
Write / NotebookEdit call whose path argument points into the archive, and any
Bash / PowerShell / Monitor command whose text names it; each path-like piece is
also resolved against the working directory and against every existing
directory the command names, so `cat archive/edits/a.md` from inside
.claude/.idd and `cd .claude/.idd && cat archive/edits/a.md` are caught; a
joined path counts only when the archive directory it names exists
(round 21). It can only compare strings, so
a recursive read that never spells the path (`grep -r .`) passes here; the
second layer — archive files are mode 0000 — covers that case.

Threat model: accidental reads, not an agent deliberately working around the
guard. This hook compares text while the shell runs it, so the two can always
be made to disagree (a path or a flag assembled from variables, globs, brace
expansion, the escapes inside $'…', eval, a relative path after more than one
cd step, another program that changes modes such as a python -c
one-liner). Those differentials are accepted: the file
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
--recursive; for PowerShell -r, -rec, -Recurse; or a walker such as find,
xargs, fd, ForEach-Object, %) anywhere is
therefore refused when the working directory is inside a repository that holds
the archive or is the folder directly above one (or cannot be listed),
whatever the command's target. The words are not attributed to commands and
targets are not resolved: every attempt to do either was beaten (rounds
18–20). From any other working directory a recursive permission change is not
checked (round 21, user decision 2026-10-18): checking it there meant resolving
targets, and it denied scripts in repositories that have no archive. The file
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
    "Blocked: this command holds a permission command (chmod, chown, chgrp, "
    "chflags or setfacl) and a recursive marker (-R, --recursive, -Recurse, or "
    "find / xargs / fd / ForEach-Object), run from inside a repository that "
    "holds the IDD correction archive or from the folder directly above one. "
    "The archive files are mode 0000 so that no recursive read reaches them "
    "(#351). The words are not attributed to commands, so another program's -R, "
    "a heredoc that writes a script, or a search for 'chmod' counts too. Change "
    "the files you mean without -R (for example chmod u+x path/to/file), run "
    "unrelated parts as separate calls, write file contents with the Write tool, "
    "and search with the Grep tool. If a recursive permission change is really "
    "needed, ask the user to run it."
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
_TREE_WALKERS = ("find", "xargs", "fd", "gfind", "gxargs", "fdfind", "foreach-object", "foreach", "%")
# -R in a short-flag cluster (capital R only: -r is not recursive for these
# commands), --recursive and its GNU abbreviations (--rec…), PowerShell -Recurse
_RECURSIVE = re.compile(r"-[A-Za-z]*R[A-Za-z]*|(?i:--rec[a-z]*|-recurse)")
# PowerShell parameters ignore case and may be abbreviated: -r, -rec, -Recurs…
_PS_RECURSIVE = re.compile(r"(?i)-r(e(c(u(r(se?)?)?)?)?)?")
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


def _command_pieces(command, powershell=False):
    """Path-like pieces of the flat text of each reading, as written."""
    for reading in _variants(command, powershell):
        for piece in _NOT_PATH.split(_flat(reading, powershell)):
            if piece:
                yield piece


def _command_words(command, powershell=False):
    """Normalized path-like pieces of the flat text of each reading, whatever
    the shell would make of the syntax."""
    for piece in _command_pieces(command, powershell):
        yield _norm_path(piece)


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


def _near_archive(cwd):
    """True if cwd is inside a repository that holds the archive, or is the
    folder directly above one; a folder the hook cannot list counts as near
    (round 21)."""
    if _archives_around(cwd):
        return True
    try:
        children = os.listdir(cwd)
    except OSError:
        return True
    return any(os.path.isdir(os.path.join(cwd, c, NEEDLE)) for c in children)


def _permission_change_in(text, cwd, powershell=False):
    """A recursive permission change near the archive, in one reading: a
    permission command and a recursive marker (-R, --recursive and its
    abbreviations, -Recurse, or a tree walker such as find / xargs / fd /
    ForEach-Object) anywhere in the command, from a working directory near the
    archive. The words are not attributed to commands and targets are not
    resolved: every attempt to do either was beaten (rounds 18–21). From
    anywhere else a recursive permission change is not checked."""
    flat = [w for w in re.split(r"[\s;&|<>()`{}]+", _flat(text, powershell)) if w]
    names = {os.path.basename(w).casefold() for w in flat}
    if not names & set(PERMISSION_COMMANDS):
        return False
    marker = _PS_RECURSIVE if powershell else _RECURSIVE
    if not (names & set(_TREE_WALKERS) or any(_RECURSIVE.fullmatch(w) or marker.fullmatch(w) for w in flat)):
        return False
    return _near_archive(cwd)


def _recursive_permission_change(command, cwd, powershell=False):
    """A recursive permission change in either reading of the command."""
    return any(_permission_change_in(r, cwd, powershell) for r in _variants(command, powershell))


def _candidates(tool, tool_input, cwd):
    """Path-like strings of the call, each also resolved against the working
    directory and, for a command, against every existing directory the
    command names — so `cat archive/edits/a.md` from inside .claude/.idd and
    `cd .claude/.idd && cat archive/edits/a.md` are caught (round 21). The
    words are not attributed to commands. A join can name the archive only if
    the piece or the base contains "archive", so only those joins are made,
    and a join counts only when the archive it names exists — a repository
    without one may still have .claude/.idd next to an unrelated archive/
    folder."""
    if tool in COMMAND_TOOLS:
        pieces = list(dict.fromkeys(_command_pieces(_as_text(tool_input.get("command")), tool == "PowerShell")))
    else:
        pieces = [c for c in _raw_candidates(tool, tool_input) if c]
    bases = [cwd]
    if tool in COMMAND_TOOLS:
        bases += [d for d in (os.path.join(cwd, os.path.expanduser(p)) for p in pieces) if os.path.isdir(d)]
    near = [p for p in pieces if "archive" in p.lower()]
    for piece in pieces:
        yield _norm_path(piece)
    for base in dict.fromkeys(bases):
        for piece in (pieces if "archive" in base.lower() else near):
            joined = os.path.normpath(os.path.join(base, os.path.expanduser(piece)))
            if _names_existing_archive(joined):
                yield _norm_path(joined)


_ARCHIVE_SEGMENT = re.compile(r"\.claude/\.idd/archive(?=/|$)", re.I)


def _names_existing_archive(path):
    """True if `path` passes through a .claude/.idd/archive directory that
    exists on disk."""
    return any(os.path.isdir(path[:m.end()]) for m in _ARCHIVE_SEGMENT.finditer(path))


def _raw_candidates(tool, tool_input):
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


def _decide(tool, tool_input, cwd):
    """The denial reason for one well-formed call, or None to allow it."""
    if any(_hits(c) for c in _candidates(tool, tool_input, cwd)):
        return REASON
    command = _as_text(tool_input.get("command")) if tool in COMMAND_TOOLS else ""
    if command and _recursive_permission_change(command, cwd, tool == "PowerShell"):
        return PERMISSION_REASON
    return None


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
    try:
        reason = _decide(tool, tool_input, cwd)
    except Exception as exc:   # noqa: BLE001 — fail closed on this call (round 20)
        print(f"archive-read-guard: could not check this call ({type(exc).__name__}: {exc}); denying", file=sys.stderr)
        reason = ("Blocked: the IDD archive read guard hit an error while checking this call. "
                  "Split the command into simpler calls and try again; if it keeps happening, "
                  "tell the user — only they can turn the guard off.")
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
