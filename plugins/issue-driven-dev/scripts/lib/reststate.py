"""reststate.py — what the state of a rest run is, and how its files are read (#478).

scripts/rest-queue.py writes the state and reads it; scripts/close-stage.py reads the review flag from it. Both
decide here whether a file found at the state's place is a state: a file that one of them takes for a state and the
other does not would let the close stage merge an issue of a run whose review flag nobody can read.

The state is below the directory the run was started in. Each issue runs in a directory of its own, and a pointer
file in the state folder of that directory names the directory the run was started in: that is how the close stage,
which runs in the directory of the issue, finds the run.
"""
import json
import os

from ghread import parse_iso

STATE_NAME = "idd-all-rest.json"
POINTER_NAME = "idd-all-rest-run.json"   # in the state folder of an issue's directory: where the run is, and which issue
STATE_VERSION = 5   # 2: the path and the default branch · 3: the review flag · 5: each issue in a directory of its own
POINTER_VERSION = 1
STATE_TTL = 24 * 3600   # the same life as the close stage's run state and the unattended marker
LEFT = (None, "none", "removed", "kept")   # what became of an issue's directory: not decided yet · it had none · …
AT_KEYS = ("head", "branch", "files", "stash")   # what next reads at the directory the run was started in


def is_time(value):
    try:
        parse_iso(value)
        return True
    except (TypeError, ValueError):
        return False


def read(path):
    """("none", None) when nothing is at the path · ("ok", value) when a file there holds JSON · ("unreadable", None)
    otherwise. A symbolic link at the path is not followed: it is unreadable, whatever it points at."""
    try:
        if os.path.islink(path):
            return "unreadable", None
        with open(path, encoding="utf-8") as fh:
            return "ok", json.load(fh)
    except (FileNotFoundError, NotADirectoryError):
        return "none", None
    except (OSError, ValueError):
        return "unreadable", None


def pointer(folder):
    """The pointer file of the state folder `folder`: ("none", None), ("unreadable", None), or
    ("ok", {"root": the directory the run was started in, "issue": the issue this directory was made for})."""
    kind, value = read(os.path.join(folder, POINTER_NAME))
    if kind != "ok":
        return kind, None
    ok = (isinstance(value, dict) and value.get("version") == POINTER_VERSION
          and isinstance(value.get("root"), str) and os.path.isabs(value["root"])
          and isinstance(value.get("issue"), int) and not isinstance(value["issue"], bool))
    return ("ok", {"root": value["root"], "issue": value["issue"]}) if ok else ("unreadable", None)


def pointer_text(root, issue):
    return json.dumps({"version": POINTER_VERSION, "root": root, "issue": issue})


def attempt_ok(a):
    """An attempt the helpers can use: every key they read is there and of its type."""
    strings = lambda v: isinstance(v, list) and all(isinstance(x, str) for x in v)
    number = lambda v: isinstance(v, int) and not isinstance(v, bool)
    at = a.get("at")
    return (number(a["issue"]) and a["outcome"] in (None, "closed", "stopped") and isinstance(a["reason"], str)
            and (a.get("dir") is None or (isinstance(a["dir"], str) and os.path.isabs(a["dir"])))
            and isinstance(a.get("made", False), bool) and a.get("left") in LEFT
            and strings(a.get("why", [])) and strings(a.get("changed", [])) and number(a.get("routing", 0))
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
