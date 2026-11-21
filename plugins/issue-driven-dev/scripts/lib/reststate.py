"""reststate.py — what the state of a rest run is, and how its files are read (#478).

scripts/rest-queue.py writes the state and reads it; scripts/close-stage.py reads the review flag from it. Both
decide here whether a file found at the state's place is a state: a file that one of them takes for a state and the
other does not would let the close stage merge an issue of a run whose review flag nobody can read.

The state is below the directory the run was started in, R, which is the top of its repository. Each issue runs in a
directory of its own at R/.claude/worktrees/rest-<N>; the helpers find the run of a directory by that place (run_of),
and accept the directory only when it is bound to its issue (bound): the mark that next wrote into its git directory,
and its origin, are those stored with the issue.

One session runs a run: the one that holds its token. Both helpers compare a token here (owns) and take the lock of a
run here (lock), so that neither can check a token, or wait for the lock, in a way the other does not.
"""
import fcntl
import hashlib
import hmac
import json
import os
import re
import stat
import subprocess
import time

from ghread import parse_iso

STATE_NAME = "idd-all-rest.json"
LOCK_NAME = "idd-all-rest.lock"
MARK_NAME = "idd-rest-mark"   # in the git directory of the directory of an issue: the value next chose for it
STATE_VERSION = 6   # 2: the path and the default branch · 3: the review flag · 5: each issue in a directory of its own · 6: one token per run
STATE_TTL = 24 * 3600   # the same life as the close stage's run state and the unattended marker
LEFT = (None, "none", "left")   # an issue's directory: not recorded yet · it had none · it is left for a person
AT_KEYS = ("head", "branch", "files", "stash")   # what next reads at the directory the run was started in
TOKEN_RE = re.compile(r"^[0-9a-f]{24}$")
DIGEST_RE = re.compile(r"^[0-9a-f]{64}$")
LOCK_WAIT = 30.0


def is_time(value):
    try:
        parse_iso(value)
        return True
    except (TypeError, ValueError):
        return False


def read(path):
    """("none", None) when nothing is at the path · ("ok", value) when a file there holds JSON · ("unreadable", None)
    otherwise. The file is opened without following a symbolic link (O_NOFOLLOW): a link at the path is unreadable,
    whatever it points at, and no check before the open can be outrun by a swap."""
    if not os.path.lexists(path):
        return "none", None
    try:   # O_NONBLOCK: a FIFO at the path does not make the open wait for a writer
        fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK | getattr(os, "O_NOFOLLOW", 0))
    except FileNotFoundError:
        return "none", None
    except OSError:
        return "unreadable", None
    try:
        if not stat.S_ISREG(os.fstat(fd).st_mode):   # only a regular file is a state
            os.close(fd)
            return "unreadable", None
        with os.fdopen(fd, encoding="utf-8") as fh:
            return "ok", json.load(fh)
    except (OSError, ValueError):
        return "unreadable", None


def age(path, now):
    """Seconds since the file at the path, a symbolic link itself included, was last written; None when nothing is there."""
    try:
        return now - os.lstat(path).st_mtime
    except OSError:
        return None


def run_of(d):
    """(R, N) when the path `d`, as given, is R/.claude/worktrees/rest-<N> — the place of the directory of issue N of the
    run whose working tree is R; None otherwise."""
    d = os.path.abspath(d)
    name, worktrees = os.path.basename(d), os.path.dirname(d)
    if os.path.basename(worktrees) != "worktrees" or os.path.basename(os.path.dirname(worktrees)) != ".claude":
        return None
    if not name.startswith("rest-") or not name[5:].isdigit() or (len(name) > 6 and name[5] == "0"):
        return None
    return os.path.dirname(os.path.dirname(worktrees)), int(name[5:])


def printable(path):
    """True when the path can be printed as it is: every character printable or a space (no control character, no
    byte that is not UTF-8, which reads back as an unprintable surrogate)."""
    return isinstance(path, str) and all(ch.isprintable() or ch == " " for ch in path)


# ── the token of a run ─────────────────────────────────────────────────────

def digest(token):
    return hashlib.sha256(token.encode("ascii")).hexdigest()


def owns(st, token):
    """True when `token` is the token of the run whose state is `st`. The one comparison of a token, for both helpers."""
    if not isinstance(token, str) or not TOKEN_RE.match(token) or not isinstance(st, dict):
        return False
    stored = st.get("token_digest")
    return isinstance(stored, str) and hmac.compare_digest(stored, digest(token))


# ── the lock of a run ──────────────────────────────────────────────────────

class Held(Exception):
    """The lock of the run is held by another command beyond the wait."""


def lock(folder, wait=LOCK_WAIT):
    """An open descriptor that holds the exclusive lock of the run whose state folder is `folder`; the lock lasts until
    the descriptor is closed (or the process ends). The lock file is opened without following a symbolic link. Held
    when another command keeps it for longer than `wait` seconds; OSError when the file cannot be opened."""
    fd = os.open(os.path.join(folder, LOCK_NAME), os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0), 0o600)
    until = time.monotonic() + wait
    while True:
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return fd
        except BlockingIOError:
            if time.monotonic() >= until:
                os.close(fd)
                raise Held()
            time.sleep(0.1)


# ── the directory of an issue ──────────────────────────────────────────────

def mark_of(d):
    """The mark in the git directory of `d`, or None: the file is read through read() (no symbolic link, no FIFO, a
    regular file only), and the git directory itself must be a folder, not a link."""
    g = os.path.join(d, ".git")
    if os.path.islink(g) or not os.path.isdir(g):
        return None
    kind, v = read(os.path.join(g, MARK_NAME))
    return v.get("mark") if kind == "ok" and isinstance(v, dict) and isinstance(v.get("mark"), str) else None


def origin_of(d):
    """remote.origin.url as the clone's own configuration file says (that file only, no include), or None."""
    cfg = os.path.join(d, ".git", "config")
    if os.path.islink(os.path.join(d, ".git")) or os.path.islink(cfg) or not os.path.isfile(cfg):
        return None
    try:
        proc = subprocess.run(["git", "config", "--file", cfg, "--get", "remote.origin.url"], capture_output=True)
    except OSError:
        return None
    out = proc.stdout.decode("utf-8", "surrogateescape")
    return (out[:-1] if out.endswith("\n") else out) if proc.returncode == 0 else None


def bound(flight, d):
    """'' when the directory `d` is bound to the issue of `flight` (its mark and its origin are those stored with the
    issue); otherwise what does not hold."""
    mark, origin = flight.get("mark"), flight.get("origin")
    if not isinstance(mark, str) or not mark or not isinstance(origin, str):
        return "the run state holds no mark for it"
    if mark_of(d) != mark:
        return "it does not hold the mark next wrote for the issue (another folder is at that place)"
    if origin_of(d) != origin:
        return "its origin is not the one it was cloned from"
    return ""


def attempt_ok(a):
    """An attempt the helpers can use: every key they read is there and of its type."""
    strings = lambda v: isinstance(v, list) and all(isinstance(x, str) for x in v)
    number = lambda v: isinstance(v, int) and not isinstance(v, bool)
    path = lambda v: isinstance(v, str) and os.path.isabs(v) and printable(v)
    at = a.get("at")
    return (number(a["issue"]) and a["outcome"] in (None, "closed", "stopped") and isinstance(a["reason"], str)
            and (a.get("dir") is None or path(a["dir"])) and (a.get("place") is None or path(a["place"]))
            and isinstance(a.get("tmps", []), list) and all(path(t) for t in a.get("tmps", []))
            and isinstance(a.get("mark", ""), str) and isinstance(a.get("origin", ""), str)
            and isinstance(a.get("made", False), bool) and a.get("left") in LEFT and strings(a.get("changed", []))
            and (at is None or (isinstance(at, dict) and all(isinstance(at.get(k), str) for k in AT_KEYS))))


def usable(st):
    """True when this is a state of a rest run that the helpers of this version can read."""
    try:
        return bool(st["version"] == STATE_VERSION and isinstance(st["repo"], str) and st["path"] == "PR"
                    and isinstance(st["default"], str) and st["default"] and isinstance(st["review"], bool)
                    and isinstance(st["token_digest"], str) and DIGEST_RE.match(st["token_digest"])
                    and is_time(st["started_at"]) and is_time(st["updated_at"]) and isinstance(st["attempts"], list)
                    and all(attempt_ok(a) for a in st["attempts"])
                    and (st["stop"] is None or isinstance(st["stop"]["reason"], str)))
    except (KeyError, TypeError, AttributeError):
        return False
