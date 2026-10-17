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

Shell commands are checked word by word, quoted strings included (`sh -c`,
`python3 -c` read files from inside them); `#` is text, not a comment, so a
comment line cannot hide the commands after it (round 13). Only the value of a
message option (-m, --message, --body, --title, --notes, --subject, and
idd-edit's --reason) is skipped, and only when it is prose (it holds
whitespace) given to a subcommand that takes a message (`git commit`, `gh
issue`, … or any subcommand of the IDD helpers) before a `--`: a commit message
or issue body that mentions the path does not open it, while `sort -m
<archive>` and `git diff -m <archive>` still name a file (verify #351 rounds
3, 11–13).

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
    "GitHub without displaying it. A commit or PR message that only mentions "
    "the path is fine as a separate single-quoted -m or --body value of more "
    "than one word, with no $, backtick, < or > (git commit -m '...', gh issue "
    "comment --body '...'); otherwise pass it from a file (-F, --body-file). A "
    "$(...) or heredoc inside the message is checked as a command."
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
MESSAGE_FLAGS = ("-m", "--message", "--body", "--title", "--notes", "--subject", "--reason")
MESSAGE_COMMANDS = ("git", "gh", "hg", "jj", "svn", "gh-egress.sh", "idd-edit-helper.py")
# For these commands only the listed subcommands take a message; elsewhere a
# flag such as `git diff -m` takes no value and the next word is a path
# (verify #351 round 12). Closed lists; IDD's own scripts take one everywhere.
MESSAGE_SUBCOMMANDS = {
    "git": ("commit", "commit-tree", "tag", "notes", "merge", "stash"),
    "gh": ("issue", "pr", "release"),
    "hg": ("commit", "ci", "tag", "amend", "import", "backout", "shelve"),
    "jj": ("commit", "describe", "new", "split", "squash"),
    "svn": ("commit", "ci", "import", "mkdir", "copy", "cp", "move", "mv", "delete", "del", "rm", "remove", "lock"),
}
# options before the subcommand that take a value (`git -C <dir> commit`)
_PRE_SUBCOMMAND_VALUE_OPTIONS = (
    "-C", "-c", "--git-dir", "--work-tree", "--namespace", "--config-env", "--attr-source",
    "-R", "--repo", "--repository", "--cwd", "--config", "--encoding", "--at-op", "--color",
    "--username", "--password", "--config-dir", "--config-option",
)
# git's combined short options ending in m (`git commit -am '...'`)
_COMBINED_MESSAGE_FLAG = re.compile(r"-[A-Za-z]+m")
# A script run through an interpreter is named by the script (IDD posts through
# `bash .../gh-egress.sh comment N --body "..."` — verify #351 round 4).
INTERPRETERS = ("bash", "sh", "zsh", "env", "python", "python3")
_ENV_ASSIGNMENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*=")
SEPARATORS = (";", "&&", "||", "|", "&", "|&", "&|")
PERMISSION_COMMANDS = ("chmod", "chown", "chgrp", "chflags", "setfacl")


def _newlines_as_separators(command):
    """An unquoted newline ends a command, as `;` does; a backslash before it
    continues the line (verify #351 round 12: the next line kept the previous
    command's name)."""
    out, quote, i = [], None, 0
    while i < len(command):
        c = command[i]
        if c == "\\" and quote is None and command[i + 1:i + 2] == "\n":
            i += 2   # a line continuation joins the lines (round 13)
            continue
        if c == "\\" and quote != "'" and i + 1 < len(command):
            out.append(command[i:i + 2])
            i += 2
            continue
        if quote:
            if c == quote:
                quote = None
        elif c in "'\"":
            quote = c
        elif c == "\n":
            out.append(" ; ")
            i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


def _split_words(command):
    command = _newlines_as_separators(command)
    # Backslashes become '/' before splitting: PowerShell paths use them as
    # separators, and POSIX shlex would otherwise eat them as escapes.
    command = command.replace("\\", "/")
    try:
        # `;`, `&` and `|` split words even when glued to them (`a&&b`), as
        # the shell reads them (round 12).
        lex = shlex.shlex(command, posix=True, punctuation_chars=";&|")
        lex.whitespace_split = True
        # shlex.split turns comments off; a bare shlex.shlex reads `#` as one,
        # even mid-word, and dropped the rest of the command (round 13)
        lex.commenters = ""
        return list(lex)
    except ValueError:
        return command.split()


def _command_words(command):
    """Path candidates in a shell command: every shell word, and every piece of
    a word split on whitespace and quoting/grouping characters — except the
    value of a message option, which is prose."""
    previous, command_name, via_interpreter, subcommand, options_ended = "", None, False, None, False
    for word in _split_words(command):
        if command_name is None or via_interpreter:
            # `NAME=value cmd` and `bash script` name the command by what runs,
            # through a chain such as `env A=1 python3 script`.
            if _ENV_ASSIGNMENT.match(word) or (via_interpreter and word.startswith("-")):
                pass
            else:
                base = os.path.basename(word)
                via_interpreter = base in INTERPRETERS and (command_name is None or via_interpreter)
                command_name, subcommand, options_ended = base, None, False
        elif (subcommand is None and not word.startswith("-")
                and previous not in _PRE_SUBCOMMAND_VALUE_OPTIONS):
            subcommand = word
        allowed = MESSAGE_SUBCOMMANDS.get(command_name)
        flag = previous in MESSAGE_FLAGS or (command_name == "git" and _COMBINED_MESSAGE_FLAG.fullmatch(previous))
        is_message = (
            command_name in MESSAGE_COMMANDS and (allowed is None or subcommand in allowed)
            and not options_ended
            and (flag or any(word.startswith(f + "=") for f in MESSAGE_FLAGS if f.startswith("--")))
        )
        if word == "--" and command_name in MESSAGE_SUBCOMMANDS:
            # after `--`, git's `-m` is a pathspec (round 13); run-start uses
            # `--` to pass /idd-edit's own arguments, --reason among them
            options_ended = True
        # `2>&1`: an `&` after a redirection is not a separator
        separator = (word in SEPARATORS and not (word == "&" and previous.endswith((">", "<")))) or word.endswith(";")
        previous = word
        if separator:
            command_name = subcommand = None
            options_ended = False
        # A message value is prose only if the shell will not execute part of
        # it: `--body "$(cat <archive>)"` posts the archive (parser differential
        # between shlex and the real shell). Prose has whitespace: a one-word
        # value is scanned, so a separator this parser misses cannot carry a
        # path through as a message (rounds 11–13).
        if is_message and not any(t in word for t in ("$", "`", "<", ">")) and re.search(r"\s", word):
            continue
        for piece in re.split(r"[\s'\"`()=;|&<>]+", word):
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


def _recursive_permission_change(command, cwd):
    """A -R permission change whose target is the archive or a directory above
    it (resolved against the tool call's working directory)."""
    words = _split_words(command)
    i = 0
    while i < len(words):
        if os.path.basename(words[i]) not in PERMISSION_COMMANDS:
            i += 1
            continue
        args = []
        i += 1
        while i < len(words) and words[i] not in SEPARATORS:
            args.append(words[i])
            i += 1
        recursive = any(
            a == "--recursive" or (a.startswith("-") and not a.startswith("--") and "R" in a)
            for a in args
        )
        if not recursive:
            continue
        archives = _archives_around(cwd)
        for a in args:
            if a.startswith("-"):
                continue
            target = os.path.normpath(os.path.join(cwd, os.path.expanduser(a)))
            # The archive itself, a directory just above it, or any directory
            # that contains this repository's archive (`chmod -R u+r ..`, round 4).
            if _archive_below(target) or any(
                arch == target or arch.startswith(target.rstrip(os.sep) + os.sep) for arch in archives
            ):
                return True
    return False


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

    cwd = _as_text(event.get("cwd")) or os.getcwd()
    command = _as_text(tool_input.get("command")) if tool in COMMAND_TOOLS else ""
    if any(_hits(c) for c in _candidates(tool, tool_input)) or (
        command and _recursive_permission_change(command, cwd)
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
