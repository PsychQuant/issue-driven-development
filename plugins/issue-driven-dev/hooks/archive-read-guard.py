#!/usr/bin/env python3
r"""archive-read-guard.py — PreToolUse hook: keep Claude's tools out of the
correction archive (#351).

`/idd-edit --correct` archives the prior version of a corrected comment or
issue body under `.claude/.idd/archive/edits/`. Those files hold content the
user confirmed to be wrong; an AI session that reads them inherits the error
again, which is the failure #351 exists to stop.

This hook is the first of two layers. It denies any Read / Grep / Glob / Edit /
Write / NotebookEdit call whose path argument points into the archive, and any
Bash / PowerShell / Monitor command whose text names it. It also denies a
relative path that goes below .claude/.idd/archive/ — after POSIX
normalization of each piece, joined to the working directory, or written as
archive/… or .idd/archive/… while the working directory is or is inside a
.claude/.idd directory (or is a .claude directory) or a word of the command
names one — when the working directory is near the archive or a named .claude
directory holds one; each piece is matched as written and POSIX-normalized.
The words of a command are never stat'ed; only a named .claude directory is,
after the text has matched (rounds 22–23). Near the archive, or naming a
.claude/.idd that holds one, a permission command together with any change of
directory (cd, chdir, pushd, popd, Set-Location, sl, Push-Location,
Pop-Location, and in PowerShell — the tool, or pwsh run from Bash, which is
also read as PowerShell — a module-qualified cmdlet) is denied, and so is any permission command run from inside
.claude/.idd (round 24, user decision 2026-10-19): rounds 20–22 tried to
recognize every spelling of a cd into the archive, and the step that lifts
mode 0000 is the chmod. A check that takes longer than 5 seconds denies the
call (a watchdog; a timed-out hook would let it run). It can only compare strings, so
a recursive read that never spells the path (`grep -r .`) passes here; the
second layer — archive files are mode 0000 — covers that case.

Threat model: accidental reads, not an agent deliberately working around the
guard. This hook compares text while the shell runs it, so the two can always
be made to disagree. The documented limits — the same list as the spec, the
design Risks and the CHANGELOG — are:
  1. paths or flags assembled from variables, globs, brace expansion, $'…' escapes, eval, command substitution or tilde prefixes such as ~+
  2. another program that changes modes (a python -c one-liner, for example)
  3. recursive permission changes run from a directory that is not near the archive (user decision 2026-10-18)
  4. a program option that changes directory before the permission command — env -C/--chdir, sudo -D, make -C, git -C, uv --directory, pwsh -WorkingDirectory, … (user decision 2026-10-19)
  5. a .claude named after an earlier cd, or split by a character outside [\w./~+@%-], from a directory not near the archive
  6. a working directory under .claude/ that is neither .claude nor inside .claude/.idd (a worktree), followed by a cd
  7. other ways to change directory: the zsh two-argument cd, an alias of cd, zsh AUTO_CD and bash shopt -s autocd, PowerShell's SessionState.Path.SetLocation
  8. a symlink named in the command
  9. a read without a permission change after a cd into the archive — it fails on mode 0000, except as root, which ignores the mode, and on Windows, where mode 0000 does not apply
  10. PowerShell reads with backslash paths run from Bash, PowerShell's .ForEach() and comma arrays
Those differentials are
accepted: the file
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
--recursive, or a walker such as find, xargs, fd, bfs; for PowerShell — or
pwsh / powershell run from Bash — also -r, -rec, -Recurse, -Depth and
ForEach-Object, foreach, %) anywhere is
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
import functools
import json
import os
import posixpath
import re
import stat
import sys
import threading

NEEDLE = ".claude/.idd/archive"
UNLOCK_FLAG = os.path.join("~", ".cache", "idd", "archive-read-guard.disabled")

REASON = (
    "Blocked: .claude/.idd/archive/ holds the prior versions of issue content "
    "that was corrected because it was wrong (#351). Reading it would bring the "
    "error back into this session. Do not read, search, list, copy or chmod "
    "these files. To put a corrected comment or issue body back, run the "
    "idd-edit helper's restore subcommand, which sends the archived text to "
    "GitHub without displaying it. Any command that names this path is denied, "
    "a commit message or issue body included, and so does a relative path "
    "into it (from the working directory, or after naming .claude/.idd): leave "
    "the path out of the text, "
    "or write the text with the Write tool and pass the file with -F or "
    "--body-file (a heredoc that names the path is denied too)."
)
PERMISSION_REASON = (
    "Blocked: this command holds a permission command (chmod, chown, chgrp, "
    "chflags or setfacl) and a recursive marker (-R, --recursive, -Recurse, or "
    "find / xargs / fd / ForEach-Object), run from inside a repository that "
    "holds the IDD correction archive, from the folder directly above one, or "
    "from a working directory the guard cannot list (one that was deleted, for "
    "example — cd to an existing directory first). "
    "The archive files are mode 0000 so that no recursive read reaches them "
    "(#351). The words are not attributed to commands, so another program's -R, "
    "a heredoc that writes a script, or a search for 'chmod' counts too. Change "
    "the files you mean without -R (for example chmod u+x path/to/file), run "
    "unrelated parts as separate calls, write file contents with the Write tool, "
    "and search with the Grep tool; if the words are only in a message, pass "
    "the text from a file (git commit -F, gh … --body-file). If a recursive "
    "permission change is really "
    "needed, ask the user to run it."
)

RELOCATED_REASON = (
    "Blocked: near the IDD correction archive, this command changes directory "
    "(cd, pushd, chdir, Set-Location, …) and runs a permission command (chmod, "
    "chown, chgrp, chflags or setfacl), or runs a permission command from inside "
    ".claude/.idd. The archive files are mode 0000 (#351), and a cd can lead a "
    "relative chmod into the archive without naming it. Run the permission "
    "command from the working directory with the path spelled out (for example "
    "chmod u+x scripts/run.sh), or as a separate call without a cd. Inside "
    ".claude/.idd every permission command is denied: leave that directory in a "
    "separate call first. A working directory the guard cannot list (one that "
    "was deleted, for example) counts as near the archive: cd to an existing "
    "directory in a separate call. If the words are only in a message, pass the "
    "text from a file (git commit -F, gh … --body-file); write file contents "
    "with the Write tool; search with the Grep tool."
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
    # posixpath, not os.path: on Windows ntpath would turn / back into \\ and
    # nothing would ever match NEEDLE (round 22)
    return posixpath.normpath(value.replace("\\", "/")).lower()


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
PERMISSION_COMMANDS = ("chmod", "chown", "chgrp", "chflags", "setfacl", "gchmod", "gchown", "gchgrp",
                       "zf_chmod", "zf_chown", "zf_chgrp")   # zsh/files builtins (round 28)
# commands that apply another command to a whole tree, as -R does
_TREE_WALKERS = ("find", "xargs", "fd", "gfind", "gxargs", "fdfind", "bfs")
# PowerShell-only walkers: in Bash % is arithmetic and foreach a csh/zsh loop
_PS_WALKERS = ("foreach-object", "foreach", "%")
# -R in a short-flag cluster (capital R only: -r is not recursive for these
# commands), --recursive and its GNU abbreviations (--rec…), PowerShell -Recurse
_RECURSIVE = re.compile(r"-[A-Za-z]*R[A-Za-z]*|(?i:--rec[a-z]*|-recurse)")
# PowerShell parameters ignore case and may be abbreviated: -r, -rec, -Recurs…
_PS_RECURSIVE = re.compile(r"(?i)-r(e(c(u(r(se?)?)?)?)?)?|-depth")
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


def _isdir_or_unknown(path):
    """os.path.isdir, except that an error other than "not there" (a
    permission error, for example) counts as a directory, so it cannot hide an
    archive (round 22)."""
    try:
        return stat.S_ISDIR(os.stat(path).st_mode)
    except (FileNotFoundError, NotADirectoryError):
        return False
    except OSError:
        return True


def _archives_around(cwd):
    """Archive directories of the repositories at or above cwd."""
    found, d = [], os.path.abspath(cwd)
    while True:
        candidate = os.path.join(d, NEEDLE)
        if _isdir_or_unknown(candidate):
            found.append(os.path.normpath(candidate))
        parent = os.path.dirname(d)
        if parent == d:
            return found
        d = parent


@functools.lru_cache(maxsize=8)
def _near_archive(cwd):
    """True if cwd — as given or with symlinks resolved — is inside a
    repository that holds the archive, or is the folder directly above one; a
    folder the hook cannot list counts as near (rounds 21–22)."""
    for d in dict.fromkeys((os.path.abspath(cwd), os.path.realpath(cwd))):
        if _archives_around(d):
            return True
        try:
            children = os.listdir(d)
        except OSError:
            return True
        if any(_isdir_or_unknown(os.path.join(d, c, NEEDLE)) for c in children):
            return True
    return False


def _flat_words(text, powershell=False):
    """The words of one reading, split at shell operators and grouping."""
    return [w for w in re.split(r"[\s;&|<>()`{}]+", _flat(text, powershell)) if w]


# words that change the working directory, in POSIX shells, zsh and PowerShell
_CD_COMMANDS = ("cd", "chdir", "pushd", "popd", "set-location", "sl", "push-location", "pop-location")
_IN_IDD = re.compile(r"(^|/)\.claude/\.idd(/|$)", re.I)
# a PowerShell module-qualified cmdlet, Microsoft.PowerShell.Management\Set-Location,
# after _flat turned the backslash into /: a dotted module name, then the cmdlet
_MODULE_QUALIFIED = re.compile(r"^[.&]?[a-z][\w]*(?:\.[\w]+)+/+([\w-]+)$", re.I)


def _names_pwsh(names):
    """pwsh / powershell, including packaged names such as pwsh-preview."""
    return any(n.startswith(("pwsh", "powershell")) for n in names)


def _with_pwsh_reading(reading, words):
    """When pwsh / powershell runs from Bash, add the words of the PowerShell
    reading (backtick escapes, backslash paths) to the Bash words (round 28)."""
    names = {os.path.basename(w).lstrip("=").casefold() for w in words}
    if _names_pwsh(names):
        words = words + _flat_words(reading, True)
        names |= {os.path.basename(w).lstrip("=").casefold() for w in words}
    return words, names


def _relocated_permission_change(command, cwd, powershell, named_holder):
    """A permission command that may act inside the archive without naming it
    (round 24, user decision 2026-10-19): run from inside a .claude/.idd
    directory near the archive, or together with any change of directory
    while the working directory is near the archive or the command names a
    .claude/.idd that holds one. Rounds 20–22 tried to recognize every way
    of spelling a cd into the archive and were beaten each time; the step
    that lifts mode 0000 is the permission command, so that is what is
    stopped. Checked in both readings; `named_holder` is called only if
    needed."""
    for reading in _variants(command, powershell):
        words = _flat_words(reading, powershell)
        if not powershell:
            words, names = _with_pwsh_reading(reading, words)
        else:
            names = {os.path.basename(w).lstrip("=").casefold() for w in words}
        ps = powershell or _names_pwsh(names)
        if not names & set(PERMISSION_COMMANDS):
            continue
        # the working directory as given and with symlinks resolved (round 25)
        bases = {posixpath.normpath(d.replace("\\", "/")) for d in (cwd, os.path.realpath(cwd))}
        if any(_IN_IDD.search(b) for b in bases) and _near_archive(cwd):
            return True
        # whole words only: a path ending in /cd is not a change of directory (round 25);
        # in PowerShell — the tool, or pwsh run from Bash — a module-qualified cmdlet
        # (Microsoft.PowerShell.Management\Set-Location, a dotted module prefix) is one (rounds 26–28)
        cd_words = {w.casefold() for w in words}
        if ps:
            cd_words |= {m.group(1).casefold() for m in map(_MODULE_QUALIFIED.match, words) if m}
        if cd_words & set(_CD_COMMANDS) and (_near_archive(cwd) or named_holder()):
            return True
    return False


def _permission_change_in(text, cwd, powershell=False):
    """A recursive permission change near the archive, in one reading: a
    permission command and a recursive marker (-R, --recursive and its
    abbreviations, -Recurse, or a tree walker such as find / xargs / fd /
    ForEach-Object) anywhere in the command, from a working directory near the
    archive. The words are not attributed to commands and targets are not
    resolved: every attempt to do either was beaten (rounds 18–21). From
    anywhere else a recursive permission change is not checked. PowerShell's
    -r / -rec / -Recurse / -Depth and ForEach-Object / foreach / % count for the
    PowerShell tool and when pwsh / powershell appears in the command."""
    flat = _flat_words(text, powershell)
    if not powershell:
        flat, names = _with_pwsh_reading(text, flat)
    else:
        names = {os.path.basename(w).lstrip("=").casefold() for w in flat}
    if not names & set(PERMISSION_COMMANDS):
        return False
    powershell = powershell or _names_pwsh(names)
    marker = _PS_RECURSIVE if powershell else _RECURSIVE
    walkers = set(_TREE_WALKERS + (_PS_WALKERS if powershell else ()))
    if not (names & walkers or any(_RECURSIVE.fullmatch(w) or marker.fullmatch(w) for w in flat)):
        return False
    return _near_archive(cwd)


def _recursive_permission_change(command, cwd, powershell=False):
    """A recursive permission change in either reading of the command."""
    return any(_permission_change_in(r, cwd, powershell) for r in _variants(command, powershell))


def _candidates(tool, tool_input):
    """Path-like strings of the call as written; string comparison only."""
    if tool in COMMAND_TOOLS:
        command = _as_text(tool_input.get("command"))
        yield from _command_words(command, tool == "PowerShell")
        if tool != "PowerShell" and re.search(r"(?i)pwsh|powershell", command):
            yield from _command_words(command, True)   # pwsh run from Bash (round 28)
        return
    yield from _raw_candidates(tool, tool_input)


# A relative path into the archive (rounds 22–23): judged on the text, after
# POSIX normalization of each piece (`archive//x`, `.claude/./.idd`,
# `attachments/../archive` — verify round 21). The words of a command are not
# stat'ed; round 21 did, and one stuck mount stalled the call (verify round 20).
_INTO_ARCHIVE = re.compile(r"(^|/)\.claude/\.idd/archive/[^/]", re.I)
_REL_INTO_ARCHIVE = re.compile(r"(\.idd/)?archive/[^/]", re.I)
# a word naming a .claude/.idd directory (or a .claude directory); group 1 is
# the part up to and including .claude
_IDD_DIR = re.compile(r"^(.*?(?:^|/)\.claude)(?:/\.idd(?:/|$)|/?$)", re.I)
# a working directory that is a .claude/.idd directory (or inside one), or a .claude directory
_CWD_IDD = re.compile(r"(^|/)\.claude/\.idd(/|$)|(^|/)\.claude$", re.I)
_LEADING_UP = re.compile(r"^(\.\.?/+)+")


def _relative_archive_reference(tool, tool_input, cwd):
    """A relative path that goes below .claude/.idd/archive/, judged on text:
    joined to the working directory it lands there, or it starts with
    archive/… or .idd/archive/… (after any ./ and ../), while the working
    directory is or is inside a .claude/.idd directory (or is a .claude
    directory) or a word of the command names one. Each piece is matched both
    as written and POSIX-normalized, so either form can only deny more
    (`archive/.` normalizes to the bare word). Returns (found, named): named
    lists the .claude directories the command names, relative to cwd or
    absolute, so the caller can check whether one holds an archive. The bare
    word "archive" does not count. The only file system access is
    realpath(cwd), once a relative piece mentions archive."""
    command = _as_text(tool_input.get("command")) if tool in COMMAND_TOOLS else ""
    if tool in COMMAND_TOOLS:
        pieces = _command_pieces(command, tool == "PowerShell")
    else:
        pieces = _raw_candidates(tool, tool_input)
    base = posixpath.normpath(cwd.replace("\\", "/"))
    bases = [base]
    named, relative = [], []
    for raw in dict.fromkeys(p for p in pieces if p):
        written = raw.replace("\\", "/")
        piece = posixpath.normpath(written)
        m = _IDD_DIR.match(piece)
        if m:
            named.append(m.group(1))
        if not piece.startswith(("/", "~")):
            relative.append((written, piece))
    # a symlinked working directory is also read with symlinks resolved, but only
    # once the text mentions "archive" (round 26)
    if any("archive" in w.lower() for w, _ in relative):
        bases.append(posixpath.normpath(os.path.realpath(cwd).replace("\\", "/")))
    in_idd = any(_CWD_IDD.search(b) for b in bases)
    found = False
    for written, piece in relative:
        joined = tuple(j for b in bases for j in (posixpath.join(b, written), posixpath.normpath(posixpath.join(b, piece))))
        if any(_INTO_ARCHIVE.search(j) for j in joined):
            found = True
        elif (in_idd or named) and any(_REL_INTO_ARCHIVE.match(_LEADING_UP.sub("", f)) for f in (written, piece)):
            found = True
    return found, named


def _names_archive_holder(named, cwd):
    """True if one of the named .claude directories holds the archive."""
    for claude in named:
        target = os.path.join(cwd, os.path.expanduser(claude), ".idd", "archive")
        if _isdir_or_unknown(target):
            return True
    return False


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
    if any(_hits(c) for c in _candidates(tool, tool_input)):
        return REASON
    found, named = _relative_archive_reference(tool, tool_input, cwd)
    if found and (_near_archive(cwd) or _names_archive_holder(named, cwd)):
        return REASON
    command = _as_text(tool_input.get("command")) if tool in COMMAND_TOOLS else ""
    if command and _recursive_permission_change(command, cwd, tool == "PowerShell"):
        return PERMISSION_REASON
    if command and _relocated_permission_change(command, cwd, tool == "PowerShell",
                                                lambda: _names_archive_holder(named, cwd)):
        return RELOCATED_REASON
    return None


DEADLINE_SECONDS = 5.0
DEADLINE_REASON = (
    "Blocked: the IDD archive read guard took too long to check this call (a "
    "slow or unreachable file system?). Run the command from a responsive "
    "directory or split it into simpler calls; if it keeps happening, tell the "
    "user — only they can turn the guard off."
)


def _emit(reason):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny",
            "permissionDecisionReason": reason,
        }
    }), flush=True)


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

    # A check that stalls (a stuck file system) must not run into Claude Code's
    # hook timeout: a timed-out hook lets the call go ahead. The watchdog denies
    # first (round 23). onFailure "block" is not used: it would also block every
    # call when python3 is missing or the hook cannot start.
    lock, done = threading.Lock(), []

    def deadline():
        with lock:
            if not done:
                done.append(True)
                _emit(DEADLINE_REASON)
                print("archive-read-guard: check took too long; denying", file=sys.stderr, flush=True)
                os._exit(0)

    timer = threading.Timer(DEADLINE_SECONDS, deadline)
    timer.daemon = True
    timer.start()

    if os.path.exists(os.path.expanduser(UNLOCK_FLAG)):
        with lock:
            done.append(True)
            timer.cancel()
        return 0  # a human created the unlock flag (archive-first style switch)

    cwd = _as_text(event.get("cwd")) or os.getcwd()
    try:
        reason = _decide(tool, tool_input, cwd)
    except Exception as exc:   # noqa: BLE001 — fail closed on this call (round 20)
        print(f"archive-read-guard: could not check this call ({type(exc).__name__}: {exc}); denying", file=sys.stderr)
        reason = ("Blocked: the IDD archive read guard hit an error while checking this call. "
                  "Split the command into simpler calls and try again; if it keeps happening, "
                  "tell the user — only they can turn the guard off.")
    with lock:
        if done:
            return 0
        done.append(True)
        timer.cancel()
        if reason:
            _emit(reason)
    return 0


if __name__ == "__main__":
    sys.exit(main())
