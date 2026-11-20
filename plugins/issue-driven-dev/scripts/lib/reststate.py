"""reststate.py — what the state of a rest run is (#478).

scripts/rest-queue.py writes the state and reads it; scripts/close-stage.py reads the review flag from it. Both
decide here whether a file found at the state's place is a state: a file that one of them takes for a state and the
other does not would let the close stage merge an issue of a run whose review flag nobody can read.
"""
import re

from ghread import parse_iso

STATE_NAME = "idd-all-rest.json"
STATE_VERSION = 4   # 2: the path and the default branch · 3: the review flag · 4: what git ignored at each hand-out
STATE_TTL = 24 * 3600   # the same life as the close stage's run state and the unattended marker
HEX40_RE = re.compile(r"^[0-9a-f]{40}$")
STASH_MESSAGE = "idd rest: files of #{n} that only {branch} ignores"   # settle finds its stash entries by these messages
STASH_TRACKED = "idd rest: files of #{n} that {branch} ignores and the default branch tracks"
STASH_KINDS = {"only": STASH_MESSAGE, "tracked": STASH_TRACKED}   # made after the checkout · made before it


def is_time(value):
    try:
        parse_iso(value)
        return True
    except (TypeError, ValueError):
        return False


def attempt_ok(a):
    """An attempt the helpers can use: every key they read is there and of its type."""
    kept, stashes, gone = a.get("kept", []), a.get("stashes", []), a.get("discarded", [])
    strings = lambda v: isinstance(v, list) and all(isinstance(x, str) for x in v)
    commit = lambda v: isinstance(v, str) and bool(HEX40_RE.match(v))   # these go into git commands a person is shown
    names = lambda d: all(isinstance(x, str) for key in ("paths", "shared") for x in d.get(key, [])) and isinstance(d.get("more", 0), int)
    left = a.get("left") or {}
    return (isinstance(a["issue"], int) and not isinstance(a["issue"], bool)
            and a["outcome"] in (None, "closed", "stopped") and isinstance(a["reason"], str)
            and isinstance(a.get("settled", True), bool) and isinstance(kept, list)
            and all(isinstance(k, dict) and isinstance(k.get("branch"), str) and (k.get("commit") == "" or commit(k.get("commit")))
                    and names(k) and k.get("hooks") in (None, "skipped") and isinstance(k.get("upstream", False), bool)
                    and isinstance(k.get("earlier", []), list) and all(commit(c) for c in k.get("earlier", []))
                    for k in kept)
            and strings(gone) and strings(a.get("before", [])) and strings(a.get("excluded", []))
            and strings(a.get("missing", [])) and strings(a.get("returned", []))
            and strings(a.get("holding", [])) and strings(a.get("tracks", [])) and strings(a.get("shown", []))
            and strings(a.get("excluded_lines", []))
            and isinstance(left, dict) and isinstance(left.get("branch", ""), str) and strings(left.get("ignored", []))
            and isinstance(stashes, list)
            and all(isinstance(x, dict) and commit(x.get("commit")) and isinstance(x.get("branch"), str) and names(x)
                    and x.get("kind") in STASH_KINDS and isinstance(x.get("kept", True), bool) for x in stashes))


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
