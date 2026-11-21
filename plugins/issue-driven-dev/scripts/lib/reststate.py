"""reststate.py — what the state of a rest run is, and how its files are read (#478).

scripts/rest-queue.py writes the state and reads it; scripts/close-stage.py reads the review flag from it. Both
decide here whether a file found at the state's place is a state: a file that one of them takes for a state and the
other does not would let the close stage merge an issue of a run whose review flag nobody can read.

The state is below the directory the run was started in. Each issue runs in a directory of its own at
R/.claude/worktrees/rest-<N>, and the helpers find the run of a directory by that place (run_of), not by a file in it.
"""
import json
import os
import stat

from ghread import parse_iso

STATE_NAME = "idd-all-rest.json"
STATE_VERSION = 5   # 2: the path and the default branch · 3: the review flag · 5: each issue in a directory of its own
STATE_TTL = 24 * 3600   # the same life as the close stage's run state and the unattended marker
LEFT = (None, "none", "left")   # an issue's directory: not recorded yet · it had none · it is left for a person
AT_KEYS = ("head", "branch", "files", "stash")   # what next reads at the directory the run was started in


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


def attempt_ok(a):
    """An attempt the helpers can use: every key they read is there and of its type."""
    strings = lambda v: isinstance(v, list) and all(isinstance(x, str) for x in v)
    number = lambda v: isinstance(v, int) and not isinstance(v, bool)
    at = a.get("at")
    return (number(a["issue"]) and a["outcome"] in (None, "closed", "stopped") and isinstance(a["reason"], str)
            and (a.get("dir") is None or (isinstance(a["dir"], str) and os.path.isabs(a["dir"])))
            and isinstance(a.get("made", False), bool) and a.get("left") in LEFT
            and isinstance(a.get("token", ""), str) and strings(a.get("changed", []))
            and (at is None or (isinstance(at, dict) and all(isinstance(at.get(k), str) for k in AT_KEYS))))


def usable(st):
    """True when this is a state of a rest run that the helpers of this version can read."""
    try:
        return bool(st["version"] == STATE_VERSION and isinstance(st["repo"], str) and st["path"] == "PR"
                    and isinstance(st["default"], str) and st["default"] and isinstance(st["review"], bool)
                    and is_time(st["started_at"]) and is_time(st["updated_at"]) and isinstance(st["attempts"], list)
                    and all(attempt_ok(a) for a in st["attempts"])
                    and (st["stop"] is None or isinstance(st["stop"]["reason"], str)))
    except (KeyError, TypeError, AttributeError):
        return False
