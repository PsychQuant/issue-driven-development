#!/usr/bin/env python3
"""rest-queue.py — which open issue /idd-all runs next when no issue was named (#478).

  rest-queue.py args   -- <the arguments /idd-all was called with>
  rest-queue.py list   --repo O/R [--json]
  rest-queue.py start  --cwd C --repo O/R --path PR
  rest-queue.py next   --cwd C --repo O/R
  rest-queue.py record --cwd C --repo O/R --issue N [--reason TEXT]
  rest-queue.py settle --cwd C --repo O/R --issue N
  rest-queue.py stop   --cwd C [--repo O/R] --reason TEXT
  rest-queue.py report --cwd C --repo O/R

args    classifies the invocation: {"mode": "rest" | "other" | "refuse"[, "reason"]}.
list    reads every open issue and prints its class and the run order. Read-only, no run.
start   begins a run, or resumes one whose last activity is less than 24 hours old, and prints the list. Rest mode
        runs on the PR path only: any other --path is refused. A new run stores the path and the default branch.
next    re-reads the open issues and hands out the first one this run has not handed out yet. A candidate with a
        local branch of its own (idd/N, idd/N-…) is recorded as existing work instead and not handed out.
record  writes the outcome of the issue in flight: closed when GitHub says the issue is closed, stopped otherwise.
settle  between two issues: discards the records idd-diagnose writes again, commits what else the issue recorded
        last left on its own branch (locally), returns to the default branch, fast-forwards it when it is behind
        and checks that the working tree is clean. next waits until it has run.
stop    marks the whole run as stopped; next hands out nothing afterwards.
report  prints what the run did and deletes its state.

Every open issue falls into exactly one class, by TABLE (first match wins). Only candidates are run:
those with a Diagnosis first, then the others, each by ascending issue number.

The judgements are not made here: open clarity rows come from lib/intent.py, the gate group and the
Diagnosis type from lib/actionability.sh, write access and the trusted Diagnosis from lib/ghread.py.

The open issues are read completely or not at all: one failed page, one missing field or one helper
that reports misuse ends the command without a list. One issue whose body GitHub does not render is not
such a failure: it gets the class unreadable and the others are classified as usual.

Run state: <cwd>/.claude/.idd/state/idd-all-rest.json. start refuses to begin when git would not ignore it.

Exit: 0 done · 1 refused (args says refuse; no run; not the issue in flight; not the issue recorded last; next before
settle) · 2 usage · 3 GitHub, git or a helper could not be read, the run state could not be written, the working tree
could not be settled, or a failure nobody planned for
"""

import hashlib
import json
import os
import re
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(HERE, "lib"))
import intent  # noqa: E402  open clarity rows, the close stage's reading
import rendered  # noqa: E402  GitHub's rendering of a body
from ghread import (Stop, can_write, gh_json, html_root, iso, issue_comments, latest_diagnosis,  # noqa: E402
                    now, parse_iso, run_cmd, ts)

REPO_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
STATE_TTL = 24 * 3600   # the same life as the close stage's run state and the unattended marker
STATE_NAME = "idd-all-rest.json"
STATE_REL = ".claude/.idd/state/" + STATE_NAME
UNATTENDED_REL = ".claude/.idd/state/unattended.json"   # lib/unattended-state.sh
STATE_VERSION = 2   # 2: the run stores its path and the default branch
PAGE = 50
REASON_MAX = 300
FLAGS = ("--pr", "--no-pr", "--review", "--in-chain")
TRACKER_LABELS = {"north-star", "epic"}
PARKING_LABEL = "parking-lot"
GROUPS = ("actionable", "parked", "blocked", "undiagnosed")

# The decision table: ordered, the first rule whose test holds decides the class.
TABLE = (
    ("outsider", lambda f: not (f["author_writes"] and f["editor_writes"] and f["commenters_write"])),
    ("tracker", lambda f: f["tracker"]),
    ("unreadable", lambda f: not f["readable"]),
    ("needs-person", lambda f: f["open_clarity"]),
    ("parked", lambda f: f["group"] == "parked"),
    ("blocked", lambda f: f["group"] == "blocked"),
    ("meeting", lambda f: f["meeting"]),
    ("verified", lambda f: f["verified"]),
    ("candidate", lambda f: True),
)
CLASSES = tuple(name for name, _ in TABLE)
LABELS = {
    "candidate": "to run",
    "needs-person": "waiting for a person",
    "blocked": "blocked",
    "verified": "already verified",
    "unreadable": "the body has text but GitHub returned no rendering of it",
    "parked": "parked",
    "meeting": "meeting",
    "tracker": "tracker",
    "outsider": "holds text from an account without write access (author, last editor or a commenter)",
}
NOT_RUN = ("blocked", "verified", "unreadable", "parked", "meeting", "tracker", "outsider")   # the order they are listed in
# What the report adds to a class whose issues go on only when a person names them.
REPORT_NOTES = {"verified": ", continues when it is named (/idd-all #N)"}
EXISTING_WORK = "existing work:"   # how idd-all starts the reason of an issue it did not take over


# ── the two tables ─────────────────────────────────────────────────────────

def classify(facts):
    """The class of an issue, from: author_writes, editor_writes, commenters_write, tracker, readable, open_clarity,
    group, meeting, verified."""
    for name, test in TABLE:
        if test(facts):
            return name
    raise Stop("the decision table has no rule for this issue")   # unreachable: the last rule always holds


def classify_args(argv):
    """(mode, reason) for the arguments /idd-all was called with: rest, other or refuse."""
    positionals, in_chain, i = [], False, 0
    while i < len(argv):
        arg = argv[i]
        if arg == "--cwd":
            if i + 1 >= len(argv) or argv[i + 1] == "" or argv[i + 1].startswith("--"):
                return "refuse", "--cwd needs a path"
            i += 2
            continue
        if arg.startswith("--cwd="):
            if arg == "--cwd=":
                return "refuse", "--cwd needs a path"
        elif arg in FLAGS:
            in_chain = in_chain or arg == "--in-chain"
        elif arg.startswith("--"):
            return "refuse", "unknown flag " + one_line(arg, 40)
        elif not arg.strip():
            return "refuse", "an empty argument: give an issue, a description or a file, or nothing at all"
        else:
            positionals.append(arg)
        i += 1
    if len(positionals) >= 2 and "rest" in positionals:
        return "refuse", ("`rest` runs every remaining issue and cannot be combined with an issue, a description or a file "
                          "(a description that contains the word rest is one argument: put it in quotes)")
    if not positionals or positionals == ["rest"]:
        if in_chain:
            return "refuse", "--in-chain is for a call that names an issue"
        return "rest", ""
    if positionals == ["last"]:   # the word the request for this mode first used; never the title of a new issue
        return "refuse", "`last` is not a mode: to run every remaining issue, call /idd-all with no argument or with `rest`"
    return "other", ""


# ── reading GitHub ─────────────────────────────────────────────────────────

QUERY = ("query($o:String!,$r:String!,$c:String){repository(owner:$o,name:$r){"
         "issues(states:OPEN,first:%d,after:$c,orderBy:{field:CREATED_AT,direction:ASC}){"
         "pageInfo{hasNextPage endCursor} nodes{number author{login} editor{login} lastEditedAt "
         "labels(first:100){totalCount nodes{name}} body bodyHTML "
         "comments(last:100){totalCount nodes{authorAssociation body author{login __typename}}}}}}}" % PAGE)


def lacks(what):
    return Stop(f"could not read the open issues: {what}")


def checked(node):
    """The issue node, after checking every field the classification reads."""
    try:
        ok = (isinstance(node["number"], int) and not isinstance(node["number"], bool)
              and all(node[k] is None or isinstance(node[k]["login"], str) for k in ("author", "editor"))
              and (node["lastEditedAt"] is None or isinstance(node["lastEditedAt"], str))
              and isinstance(node["body"], str) and isinstance(node["bodyHTML"], str)
              and isinstance(node["labels"]["totalCount"], int)
              and all(isinstance(l["name"], str) for l in node["labels"]["nodes"])
              and isinstance(node["comments"]["totalCount"], int)
              and all(isinstance(c["authorAssociation"], str) and isinstance(c["body"], str)
                      and (c["author"] is None or (isinstance(c["author"]["login"], str)
                                                   and isinstance(c["author"]["__typename"], str)))
                      for c in node["comments"]["nodes"]))
    except (KeyError, TypeError):
        ok = False
    if not ok:
        raise lacks("an issue in the answer lacks an expected field")
    if node["labels"]["totalCount"] > len(node["labels"]["nodes"]):
        raise lacks(f"issue #{node['number']} has more labels than one read returns")
    return node


def read_issues(repo):
    """Every open issue of the repository, oldest first."""
    owner, name = repo.split("/", 1)
    nodes, numbers, cursor, cursors = [], set(), None, set()
    while True:
        args = ["api", "graphql", "-f", f"query={QUERY}", "-f", f"o={owner}", "-f", f"r={name}"]
        if cursor is not None:
            args += ["-f", f"c={cursor}"]
        data = gh_json(args, "the open issues")
        try:
            conn = data["data"]["repository"]["issues"]
            page, more, cursor = conn["nodes"], conn["pageInfo"]["hasNextPage"], conn["pageInfo"]["endCursor"]
        except (KeyError, TypeError):
            raise lacks("the answer lacks an expected field")
        if not isinstance(page, list) or not isinstance(more, bool):
            raise lacks("the answer lacks an expected field")
        for node in page:
            node = checked(node)
            if node["number"] not in numbers:   # a page boundary that moved while reading
                numbers.add(node["number"])
                nodes.append(node)
        if not more:
            return nodes
        if not isinstance(cursor, str) or not cursor or cursor in cursors:
            raise lacks("a further page was announced without a usable cursor")
        cursors.add(cursor)


# One bash process evaluates the gate for every issue. Bodies and Diagnoses are passed as files:
# one argument of a command line is limited to 128 KB on Linux, and an issue body can be larger.
GATE_SH = r'''
. "$1/lib/actionability.sh" || exit 9
for d in "$2"/*/; do
  n=$(basename "$d")
  body=$(cat "$d/body") || exit 9
  diag=$(cat "$d/diag") || exit 9
  park=$(cat "$d/park") || exit 9
  line=$(idd_blocking_section "$body") || exit 9
  if [ -n "$line" ]; then blocking=yes; else blocking=no; fi
  dtype=$(idd_diagnosis_type "$diag") || exit 9
  if tier=$(idd_parse_complexity "$diag" 2>/dev/null); then cexit=0; else cexit=$?; fi
  case "$cexit" in 0|3|4|5) ;; *) exit 9 ;; esac
  if verdict=$(idd_actionability_verdict --complexity-exit "$cexit" --parking-label "$park" \
       --blocking-section "$blocking" --diagnosis-type "$dtype" 2>&1); then
    group=actionable
  else
    [ $? -eq 1 ] || exit 9
    group=$(idd_actionability_group "${verdict#not-actionable: }") || exit 9
  fi
  printf '%s\t%s\t%s\n' "$n" "$group" "$dtype"
done
'''


def put(path, text):
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)


def comments_of(repo, node):
    """Every comment of the issue as {assoc, body, login, type}: the ones the query returned, or all of them
    (one more read) when it returned only the newest — the Diagnosis the run routes on may be older, and so
    may a comment by an account without write access."""
    got = node["comments"]["nodes"]
    if node["comments"]["totalCount"] > len(got):
        return issue_comments(repo, node["number"])
    return [{"assoc": c["authorAssociation"], "body": c["body"],
             "login": (c["author"] or {}).get("login"), "type": (c["author"] or {}).get("__typename")} for c in got]


def gate_groups(nodes, comments):
    """{issue number: (gate group, Diagnosis type)}, from lib/actionability.sh."""
    if not nodes:
        return {}
    work = tempfile.mkdtemp(prefix="idd-rest-queue-")
    try:
        for node in nodes:
            d = os.path.join(work, str(node["number"]))
            os.mkdir(d)
            put(os.path.join(d, "body"), node["body"])
            put(os.path.join(d, "diag"), latest_diagnosis(comments[node["number"]]))
            put(os.path.join(d, "park"), "yes" if any(l["name"] == PARKING_LABEL for l in node["labels"]["nodes"]) else "no")
        rc, out, err = run_cmd(["bash", "-c", GATE_SH, "_", HERE, work])
    finally:
        shutil.rmtree(work, ignore_errors=True)
    if rc != 0:
        raise Stop("the actionability gate could not be evaluated (lib/actionability.sh reported misuse or is missing)")
    groups = {}
    for line in out.splitlines():
        parts = line.split("\t")
        if len(parts) != 3 or not parts[0].isdigit() or parts[1] not in GROUPS:
            raise Stop("the actionability gate printed a line this helper cannot read")
        groups[int(parts[0])] = (parts[1], parts[2])
    if set(groups) != {node["number"] for node in nodes}:
        raise Stop("the actionability gate did not answer for every issue")
    return groups


_NO_ACCOUNT = set()


def writes(repo, login):
    """True when the account can push to the repository. An account GitHub does not know as a
    collaborator (HTTP 404: an outsider on a private repository, or an app's bot account) cannot;
    any other failure to read the permission ends the command."""
    if not login or login in _NO_ACCOUNT:
        return False
    try:
        return can_write(repo, login)
    except Stop as exc:
        if "HTTP 404" in str(exc):
            _NO_ACCOUNT.add(login)
            return False
        if "HTTP 403" in str(exc):   # GitHub answers this question only to an account that can write itself
            raise Stop("rest mode needs an account with write access to this repository: GitHub would not say "
                       "who can write to it (HTTP 403)")
        raise


PHASE_RE = re.compile(r"^Phase\s*[:：]\s*(\S+)")


def phase_of(root):
    """The value of the first Phase line GitHub shows outside code blocks, lower case, or ''."""
    for _, run, _ in rendered.lines(root):
        found = PHASE_RE.match(rendered.line_text(run))
        if found:
            return found.group(1).lower()
    return ""


def read_classes(repo):
    """[{number, class, group, questions}] for every open issue."""
    nodes = read_issues(repo)
    comments = {node["number"]: comments_of(repo, node) for node in nodes}
    groups = gate_groups(nodes, comments)
    out = []
    for node in nodes:
        number = node["number"]
        group, dtype = groups[number]
        author = (node["author"] or {}).get("login")
        # GitHub returns no editor both for a body nobody edited and for one edited by an account it cannot
        # return; only the time of the last edit tells them apart. Edited by an unknown account = not trusted.
        edited = node["lastEditedAt"] is not None or node["editor"] is not None
        facts = {
            "author_writes": writes(repo, author),
            "editor_writes": not edited or writes(repo, (node["editor"] or {}).get("login")),
            # bots are exempt, as in the close stage: a repository admin installed them
            "commenters_write": all(c.get("type") == "Bot" or writes(repo, c.get("login")) for c in comments[number]),
            "tracker": any(l["name"].lower() in TRACKER_LABELS for l in node["labels"]["nodes"]),
            "group": group,
            "meeting": dtype == "meeting",
        }
        # The accounts are judged above without the rendering. A body GitHub does not render (text, but an
        # empty rendering: one HTML comment is enough) is one issue this run cannot read, not a failed read
        # of the repository: anyone who can open an issue could otherwise stop every run.
        try:
            root = html_root(node["bodyHTML"], node["body"])
            rows = intent.open_clarity_rows({"body_html": node["bodyHTML"], "body": node["body"]})
            phase, readable = phase_of(root), True
        except Exception:   # Stop, or anything else the rendering of this one body set off (a nesting too deep, …)
            rows, phase, readable = [], "", False
        facts.update(readable=readable, open_clarity=bool(rows), verified=phase == "verified")
        out.append({"number": number, "class": classify(facts), "group": group, "questions": rows})
    return out


def listing(repo):
    issues = read_classes(repo)
    classes = {name: sorted(i["number"] for i in issues if i["class"] == name) for name in CLASSES}
    candidates = [i for i in issues if i["class"] == "candidate"]
    diagnosed = sorted(i["number"] for i in candidates if i["group"] == "actionable")
    others = sorted(i["number"] for i in candidates if i["group"] != "actionable")
    return {"repo": repo, "open": len(issues), "classes": classes, "order": diagnosed + others, "diagnosed": diagnosed,
            "questions": {str(i["number"]): [one_line(q) for q in i["questions"]]   # the whole row, so a long Source does not cut off the question
                          for i in issues if i["class"] == "needs-person"}}


# ── run state ──────────────────────────────────────────────────────────────

def state_dir(cwd):
    """<cwd>/.claude/.idd/state, refusing a symlink on the way (the same rule as close-stage.py)."""
    cwd = os.path.realpath(cwd)
    d = os.path.join(cwd, ".claude", ".idd", "state")
    probe = d
    while probe and probe != cwd and probe != os.path.dirname(probe):
        if os.path.islink(probe):
            raise Stop(f"{probe} is a symlink — refusing to read or write run state through it")
        probe = os.path.dirname(probe)
    return d


def state_path(cwd):
    path = os.path.join(state_dir(cwd), STATE_NAME)
    if os.path.islink(path):
        raise Stop(f"{path} is a symlink — refusing to use it")
    return path


def read_state(cwd, repo=None):
    """(state, problem). The run state of this working tree; or None, with the reason when a state file is
    there and this helper cannot use it ('' when there is no file)."""
    path = state_path(cwd)
    try:
        with open(path, encoding="utf-8") as fh:
            raw = fh.read()
    except (FileNotFoundError, NotADirectoryError):
        return None, ""
    except (OSError, ValueError) as exc:
        return None, f"it cannot be read ({type(exc).__name__})"
    try:
        st = json.loads(raw)
        ok = (st["version"] == STATE_VERSION and isinstance(st["repo"], str) and st["path"] == "PR"
              and isinstance(st["default"], str) and bool(st["default"]) and is_time(st["started_at"])
              and is_time(st["updated_at"]) and isinstance(st["attempts"], list)
              and all(attempt_ok(a) for a in st["attempts"])
              and (st["stop"] is None or isinstance(st["stop"]["reason"], str)))
    except (ValueError, KeyError, TypeError, AttributeError):
        ok = False
    if not ok:
        return None, "it is not a run state this helper can read"
    if repo is not None and st["repo"] != repo:
        return None, f"it belongs to a run for {one_line(st['repo'], 80)}"
    return st, ""


def is_time(value):
    try:
        parse_iso(value)
        return True
    except (TypeError, ValueError):
        return False


def attempt_ok(a):
    """An attempt this helper can use: every key it reads is there and of its type."""
    kept = a.get("kept", [])
    return (isinstance(a["issue"], int) and not isinstance(a["issue"], bool)
            and a["outcome"] in (None, "closed", "stopped") and isinstance(a["reason"], str)
            and isinstance(a.get("settled", True), bool) and isinstance(kept, list)
            and all(isinstance(k, dict) and isinstance(k.get("branch"), str) and isinstance(k.get("commit"), str)
                    and all(isinstance(x, str) for key in ("paths", "shared") for x in k.get(key, []))
                    and isinstance(k.get("more", 0), int) for k in kept))


def owes_settle(st):
    """The attempt recorded last when settle has not run for it yet, else None."""
    last = st["attempts"][-1] if st["attempts"] else None
    return last if last and last["outcome"] is not None and not last.get("settled", True) else None


def load_state(cwd, repo=None):
    """The run state of this working tree, or None when there is none this helper can use."""
    return read_state(cwd, repo)[0]


def save_state(cwd, st):
    path = state_path(cwd)
    st["updated_at"] = iso(now())
    tmp = None
    try:
        os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
        fd, tmp = tempfile.mkstemp(prefix=STATE_NAME + ".", dir=os.path.dirname(path))
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(st, fh)
        os.replace(tmp, path)
    except OSError as exc:
        if tmp and os.path.exists(tmp):
            os.unlink(tmp)
        raise Stop(f"could not write the run state: {exc.strerror or exc}")


def in_flight(st):
    return next((a for a in st["attempts"] if a["outcome"] is None), None)


# ── the working tree ───────────────────────────────────────────────────────

# Places whose writer keeps them out of git (closed list, the spec's): the run state, edit backups that hold other
# people's words, the tree lock and worktrees. Each writer enforces its own ignore rule; a file that shows up here
# anyway is never committed.
KEEP_OUT_DIRS = (".claude/.idd/" + "archive/", ".claude/.idd/state/", ".claude/worktrees/")
KEEP_OUT_PREFIX = ".claude/.idd/tree-lock"
ATTACHMENTS = ".claude/.idd/attachments/"   # issue-<N>/ below it: what idd-diagnose downloads, again on every run
SHARED_LOG_RE = re.compile(r"(^|/)\.claude/\.idd/(routing-stats\.jsonl$|issue-runs/)")   # appended to for every issue
BRANCH_OF = r"idd/{n}(?:-.*)?"   # an issue's own branch; scripts/check-existing-work.sh own() has the same rule
PATHS_KEPT = 10
UNMERGED = {"DD", "AU", "UD", "UA", "DU", "AA", "UU"}


def keep_out(path, pre):
    """True when `path` (relative to the top of the repository) lies in a place that is never committed.
    `pre` is where --cwd lies below the top ('' or 'sub/'): IDD's own folders are relative to --cwd."""
    if not path.startswith(pre):
        return False
    rel = path[len(pre):]
    return rel.startswith(KEEP_OUT_DIRS) or rel.startswith(KEEP_OUT_PREFIX)


def git(cwd, args, what, todo=""):
    """git's stdout; Stop naming `what`, git's reason and `todo` (what a person does next) when git fails."""
    rc, out, err = run_cmd(["git", "-C", cwd] + args)
    if rc != 0:
        raise Stop(f"{what} ({one_line(err, 200) or 'git exited ' + str(rc)})" + (f" — {todo}" if todo else ""))
    return out


def git_ok(cwd, args):
    return run_cmd(["git", "-C", cwd] + args)[0] == 0


def ensure_ignored(cwd):
    """Refuse a working tree in which git would not ignore the run state: an untracked state file makes every
    issue stop at its clean-tree check (#564 makes idd-all add the rule itself)."""
    for probe in (STATE_REL, UNATTENDED_REL):   # the folder, not one file: the unattended marker and the close stage's state live there too
        rc, _, err = run_cmd(["git", "-C", cwd, "check-ignore", "-q", "--", probe])
        if rc == 1:
            raise Stop("git would not ignore the run state in .claude/.idd/state/ — add the line .claude/.idd/state/ to "
                       ".git/info/exclude (or .gitignore), then start again")
        if rc != 0:
            raise Stop(f"git cannot tell whether .claude/.idd/state/ is ignored here (is this a git working tree?): "
                       f"{one_line(err, 200) or 'git check-ignore exited ' + str(rc)}")


def idd_branches(cwd):
    """{issue number: [local branch names idd/N or idd/N-…]}."""
    out = git(cwd, ["for-each-ref", "--format=%(refname)", "refs/heads/idd/"], "could not list the local branches",
              f"check that git can read this working tree, {AGAIN}")
    found = {}
    for ref in out.splitlines():
        m = re.match(r"^refs/heads/idd/([0-9]+)(?:-.*)?$", ref)   # BRANCH_OF, for any issue number
        if m:
            found.setdefault(int(m.group(1)), []).append(ref[len("refs/heads/"):])
    return {n: sorted(b) for n, b in found.items()}


def leftovers(cwd):
    """(paths, unmerged): every changed or untracked path git does not ignore, relative to the repository root,
    one entry per file (an untracked folder is not folded into one entry)."""
    out = git(cwd, ["status", "--porcelain=v1", "-z", "--untracked-files=all", "--ignore-submodules=none"],
              "could not read the working tree", f"check that git can read this working tree, {AGAIN}")
    fields, paths, unmerged, i = out.split("\0"), [], False, 0
    while i < len(fields):
        entry = fields[i]
        i += 1
        if len(entry) < 4:
            continue
        xy, path = entry[:2], entry[3:]
        paths.append(path)
        unmerged = unmerged or xy in UNMERGED
        if xy[0] in "RC":   # a rename or copy names its source in the next field
            if i < len(fields) and fields[i]:
                paths.append(fields[i])
            i += 1
    return sorted(set(paths)), unmerged


def operation_in_progress(cwd):
    for ref, name in (("MERGE_HEAD", "merge"), ("CHERRY_PICK_HEAD", "cherry-pick"), ("REVERT_HEAD", "revert")):
        if git_ok(cwd, ["rev-parse", "-q", "--verify", ref]):
            return name
    for d in ("rebase-merge", "rebase-apply"):
        where = git(cwd, ["rev-parse", "--git-path", d], "could not read the git folder",
                    f"check that git can read this working tree, {AGAIN}").strip()
        if os.path.isdir(where if os.path.isabs(where) else os.path.join(cwd, where)):
            return "rebase"
    return ""


def some(paths):
    shown = ", ".join(one_line(p, 60) for p in paths[:3])
    return shown + (f" and {len(paths) - 3} more" if len(paths) > 3 else "")


def vouched(top, folder, manifest, path):
    """True when the manifest on disk lists `path` (a file directly in the issue's attachment folder) with the
    SHA-256 the file has: idd-diagnose downloads that file again on the next run of the issue."""
    name = path[len(folder):]
    full = os.path.join(top, path)
    if "/" in name or os.path.islink(full) or not os.path.isfile(full):
        return False
    try:
        with open(os.path.join(top, manifest), encoding="utf-8") as fh:
            listed = [f for f in json.load(fh)["files"] if isinstance(f, dict) and f.get("filename") == name]
        digest = hashlib.sha256()
        with open(full, "rb") as fh:
            for chunk in iter(lambda: fh.read(1 << 20), b""):
                digest.update(chunk)
    except (OSError, ValueError, KeyError, TypeError):
        return False
    return any(isinstance(f.get("sha256"), str) and f["sha256"] == digest.hexdigest() for f in listed)


def regenerated(top, pre, n, paths, fresh):
    """The leftovers settle discards (the requirement's step 1): the manifest when it is the only leftover in
    the issue's attachment folder; on a branch without a commit of its own or an upstream (`fresh`), all the
    leftovers when each is the manifest or a file the manifest vouches for. Nothing else, ever."""
    folder = f"{pre}{ATTACHMENTS}issue-{n}/"
    manifest = folder + "_manifest.json"
    inside = [p for p in paths if p.startswith(folder)]
    if inside == [manifest]:
        return [manifest]
    if fresh and inside and len(inside) == len(paths) and all(
            p == manifest or vouched(top, folder, manifest, p) for p in inside):
        return inside
    return []


def discard(cwd, top, path, what, todo):
    """Restore a tracked file to its committed content; delete an untracked one."""
    spec = ":(top,literal)" + path
    if git_ok(cwd, ["cat-file", "-e", "HEAD:" + path]):
        git(cwd, ["checkout", "-q", "HEAD", "--", spec], what, todo)
        return
    git(cwd, ["rm", "-q", "-f", "--cached", "--ignore-unmatch", "--", spec], what, todo)
    try:
        os.unlink(os.path.join(top, path))
    except FileNotFoundError:
        pass
    except OSError as exc:
        raise Stop(f"{what} ({exc.strerror or exc}) — {todo}")


def own_commits(cwd, default, branch, what, todo):
    """How many commits the branch has that origin's default branch lacks."""
    return int(git(cwd, ["rev-list", "--count", f"refs/remotes/origin/{default}..refs/heads/{branch}"], what, todo).strip() or "0")


def upstream_of(cwd, branch, what, todo):
    return git(cwd, ["for-each-ref", "--format=%(upstream)", f"refs/heads/{branch}"], what, todo).strip()


# ── output ─────────────────────────────────────────────────────────────────

def one_line(text, limit=None):
    """The text on one line, without control characters; cut to `limit` characters when one is given."""
    text = " ".join("".join(ch if ch.isprintable() else " " for ch in str(text)).split())
    return text if limit is None or len(text) <= limit else text[:limit - 1] + "…"


def nums(numbers):
    return " ".join(f"#{n}" for n in numbers) or "-"


def emit(obj, code=0):
    print(json.dumps(obj, ensure_ascii=False))
    return code


def refuse(msg):
    print(f"rest-queue: {msg}", file=sys.stderr)
    return 1


def usage(msg):
    print(f"rest-queue: {msg}\n{__doc__.split(chr(10) + chr(10))[1]}", file=sys.stderr)
    return 2


def list_lines(lst, attempted=(), branches=None):
    """`branches`: {issue: [local branch names]} of the working tree, when there is one to look at."""
    branches = branches or {}
    local = [n for n in lst["order"] if n not in attempted and n in branches]
    todo = [n for n in lst["order"] if n not in attempted and n not in branches]
    diagnosed = sum(1 for n in todo if n in lst["diagnosed"])
    lines = [f"open issues: {lst['open']}",
             f"to run ({len(todo)}): {nums(todo)}",
             f"  diagnosed {diagnosed}, not diagnosed {len(todo) - diagnosed}"]
    if local:
        lines.append(f"candidates with a local branch, recorded as existing work when their turn comes ({len(local)}): {nums(local)}")
    if attempted:
        lines.append(f"already attempted in this run ({len(attempted)}): {nums(sorted(attempted))}")
    for name in ("needs-person",) + NOT_RUN:
        lines.append(f"{LABELS[name]} ({len(lst['classes'][name])}): {nums(lst['classes'][name])}")
    return lines


# ── commands ───────────────────────────────────────────────────────────────

EMPTY_OK = {"--reason"}   # an empty reason reads as none given; every other value must be there


def repo_ok(repo):
    """owner/name, each part of the characters GitHub allows and neither `.` nor `..` (the value goes into API paths)."""
    return bool(REPO_RE.match(repo)) and all(part not in (".", "..") for part in repo.split("/"))


def parse(argv, valued, switches=()):
    """{flag: value} for the flags in `valued`, True for those in `switches`; None on a malformed command line."""
    out, i = {}, 0
    while i < len(argv):
        flag = argv[i]
        if flag in switches and flag not in out:
            out[flag] = True
            i += 1
        elif flag in valued and flag not in out and i + 1 < len(argv) and (argv[i + 1] != "" or flag in EMPTY_OK):
            out[flag] = argv[i + 1]
            i += 2
        else:
            return None
    return out


def common(argv, valued, need, switches=()):
    a = parse(argv, valued, switches)
    if a is None or any(k not in a for k in need):
        return None
    if "--cwd" in a and not os.path.isdir(a["--cwd"]):
        return None
    if "--repo" in a and not repo_ok(a["--repo"]):
        return None
    if "--issue" in a and not re.match(r"^[0-9]{1,9}$", a["--issue"]):
        return None
    return a


def cmd_args(argv):
    mode, reason = classify_args(argv[1:] if argv[:1] == ["--"] else argv)
    return emit({"mode": mode, "reason": reason} if mode == "refuse" else {"mode": mode}, 1 if mode == "refuse" else 0)


def cmd_list(argv):
    a = common(argv, {"--repo"}, ["--repo"], {"--json"})
    if a is None:
        return usage("list --repo O/R [--json]")
    lst = listing(a["--repo"])
    if a.get("--json"):
        return emit(lst)
    print("\n".join(list_lines(lst)))
    return 0


def cmd_start(argv):
    a = common(argv, {"--cwd", "--repo", "--path"}, ["--cwd", "--repo", "--path"])
    if a is None:
        return usage("start --cwd C --repo O/R --path PR")
    cwd, repo, path = a["--cwd"], a["--repo"], a["--path"]
    if path != "PR":   # between two issues, what an issue left is kept on its own branch: only the PR path has one
        raise Stop(f"rest mode runs on the PR path only, and this run resolved to {one_line(path, 40)} — pass --pr "
                   "(/idd-all --pr), or name the issues one at a time (/idd-all #N)")
    ensure_ignored(cwd)   # before anything is read or written
    st, problem = read_state(cwd, repo)
    resumed = st is not None and now() - ts(st["updated_at"]) < STATE_TTL
    lst = listing(repo)   # before anything is written: a failed read leaves no run behind
    branches = idd_branches(cwd)
    if not resumed:
        default = gh_json(["repo", "view", repo, "--json", "defaultBranchRef"],
                          f"the default branch of {repo}").get("defaultBranchRef") or {}
        default = default.get("name") if isinstance(default, dict) else None
        if not isinstance(default, str) or not default or default.startswith("-") \
                or not git_ok(cwd, ["check-ref-format", "--branch", default]):
            raise Stop(f"could not read the default branch of {repo} from GitHub")
        st = {"version": STATE_VERSION, "repo": repo, "path": path, "default": default, "started_at": iso(now()),
              "updated_at": "", "attempts": [], "stop": None}
    save_state(cwd, st)   # a resumed run too: starting is activity, and the 24 hours count from the last one
    attempted = [x["issue"] for x in st["attempts"]]
    head = f"rest run for {repo} — "
    head += (f"resumed (started {one_line(st['started_at'], 40)}, {len(attempted)} attempt(s) so far)" if resumed
             else f"new (started {one_line(st['started_at'], 40)})")
    print(head)
    if problem:   # said, not silent: the attempts of that state are not carried over
        print(f"a run state was found in this working tree but cannot be used ({problem}) — this is a new run, and it replaces that file")
    if st["stop"]:
        print(f"this run stopped earlier: {one_line(st['stop']['reason'], REASON_MAX)} — next hands out nothing; call report to end it")
    flight = in_flight(st)
    if flight:
        print(f"in flight, no result recorded yet: #{flight['issue']}")
    print("\n".join(list_lines(lst, attempted, branches)))
    print("a candidate with a pull request or a branch on GitHub is not run either: it is recorded as existing work when its turn comes")
    return 0


def cmd_next(argv):
    a = common(argv, {"--cwd", "--repo"}, ["--cwd", "--repo"])
    if a is None:
        return usage("next --cwd C --repo O/R")
    cwd, repo = a["--cwd"], a["--repo"]
    st = load_state(cwd, repo)
    if st is None:
        return refuse("no rest run in this working tree — call start first")
    if st["stop"]:
        return emit({"next": None, "stopped": one_line(st["stop"]["reason"], REASON_MAX)})
    owed = owes_settle(st)
    if owed:
        return refuse(f"#{owed['issue']} is recorded but its working tree is not settled — call settle for #{owed['issue']} first")
    flight = in_flight(st)
    if flight:
        print(f"→ #{flight['issue']} is still in flight: finish it and call record", file=sys.stderr)
        mine = idd_branches(cwd).get(flight["issue"], [])   # none: the issue had not reached the step that creates it
        return emit({"next": flight["issue"], "in_flight": True, "branch": mine[0] if mine else None})
    attempted = {x["issue"] for x in st["attempts"]}
    todo = [n for n in listing(repo)["order"] if n not in attempted]
    branches = idd_branches(cwd)
    while todo and todo[0] in branches:   # work an earlier run or a person started: a person decides about it
        stamp = iso(now())
        st["attempts"].append({"issue": todo[0], "handed_at": stamp, "outcome": "stopped", "recorded_at": stamp,
                               "reason": one_line(f"{EXISTING_WORK} local branch {branches[todo[0]][0]}", REASON_MAX),
                               "settled": True})
        print(f"→ #{todo[0]} has the local branch {branches[todo[0]][0]}: recorded as existing work", file=sys.stderr)
        todo.pop(0)
    if not todo:
        save_state(cwd, st)
        return emit({"next": None, "done": True})
    st["attempts"].append({"issue": todo[0], "handed_at": iso(now()), "outcome": None, "reason": "", "recorded_at": None})
    save_state(cwd, st)
    print(f"→ next: #{todo[0]} ({len(todo) - 1} more after it)", file=sys.stderr)
    return emit({"next": todo[0], "in_flight": False, "remaining": len(todo) - 1})


def cmd_record(argv):
    a = common(argv, {"--cwd", "--repo", "--issue", "--reason"}, ["--cwd", "--repo", "--issue"])
    if a is None:
        return usage("record --cwd C --repo O/R --issue N [--reason TEXT]")
    cwd, repo, n = a["--cwd"], a["--repo"], int(a["--issue"])
    st = load_state(cwd, repo)
    if st is None:
        return refuse("no rest run in this working tree — call start first")
    flight = in_flight(st)
    if flight is None or flight["issue"] != n:
        return refuse(f"#{n} is not the issue in flight" + (f" (#{flight['issue']} is)" if flight else " (none is)"))
    state = gh_json(["issue", "view", str(n), "--repo", repo, "--json", "state"], f"the state of #{n}").get("state")
    if state not in ("OPEN", "CLOSED"):
        raise Stop(f"could not read the state of #{n}")
    flight["outcome"] = "closed" if state == "CLOSED" else "stopped"
    flight["reason"] = "" if state == "CLOSED" else (one_line(a.get("--reason", ""), REASON_MAX) or "no reason given")
    flight["recorded_at"] = iso(now())
    flight["settled"] = False   # next waits for settle
    save_state(cwd, st)
    return emit({"issue": n, "outcome": flight["outcome"], "reason": flight["reason"]})


def cmd_settle(argv):
    a = common(argv, {"--cwd", "--repo", "--issue"}, ["--cwd", "--repo", "--issue"])
    if a is None:
        return usage("settle --cwd C --repo O/R --issue N")
    cwd, repo, n = a["--cwd"], a["--repo"], int(a["--issue"])
    st = load_state(cwd, repo)
    if st is None:
        return refuse("no rest run in this working tree — call start first")
    last = st["attempts"][-1] if st["attempts"] else None
    if last is None or last["issue"] != n or last["outcome"] is None:
        held = "none is" if last is None else (f"#{last['issue']} is in flight" if last["outcome"] is None
                                               else f"#{last['issue']} was")
        return refuse(f"#{n} is not the issue recorded last ({held})")
    if last.get("settled", True):   # settled already (or recorded as existing work by next): change nothing
        return emit({"issue": n, "settled": True, "kept": last.get("kept", []), "again": True})
    branch = run_cmd(["git", "-C", cwd, "symbolic-ref", "--quiet", "--short", "HEAD"])[1].strip()
    try:
        kept, gone = settle_tree(cwd, n, st["default"], branch, last, st)
    except Stop as exc:   # whichever step failed, the reason names the issue and where the working tree is now
        text = str(exc)
        if text.startswith(f"#{n} "):
            raise
        now_on = run_cmd(["git", "-C", cwd, "symbolic-ref", "--quiet", "--short", "HEAD"])[1].strip()
        raise Stop(f"#{n} (working tree on {one_line(now_on or 'no branch', 60)}): {text}")
    last["kept"], last["settled"] = kept, True
    save_state(cwd, st)
    return emit({"issue": n, "settled": True, "kept": kept, "discarded": gone})


AGAIN = "then run the same /idd-all command again, with the flags you used"


def trouble(n, on, problem, todo, paths=()):
    """One reason line for a settle that stops: the issue and the branch, what is wrong, what a person does next,
    and only then up to three paths — cut so that the whole line fits the limit for a reason."""
    head = f"#{n} (working tree on {one_line(on, 60)}): {problem} — {todo}, {AGAIN}"
    room = REASON_MAX - len(head) - 3
    return Stop(head + (f" ({one_line(some(paths), room)})" if paths and room > 20 else ""))


def settle_tree(cwd, n, default, branch, last, st):
    """The closed table of the requirement, then the default branch against origin. Returns (the kept branches,
    the regenerated records it discarded). Every reason it stops with names the issue and the branch, and says
    what a person does next."""
    on = branch or "no branch"
    look = f"check that git can read this working tree, {AGAIN}"
    busy = operation_in_progress(cwd)
    paths, unmerged = leftovers(cwd)
    if busy or unmerged:
        raise trouble(n, on, f"git reports an unfinished {busy or 'merge'}", "finish or abort it")
    pre = git(cwd, ["rev-parse", "--show-prefix"], "could not read where the working tree lies in the repository", look).strip()
    top = git(cwd, ["rev-parse", "--show-toplevel"], "could not read the top of the repository", look).strip()
    prior = {k["branch"]: k for k in last.get("kept", [])}   # what an earlier, interrupted call recorded
    gone = []
    if re.fullmatch(BRANCH_OF.format(n=n), branch or ""):         # row 1: the issue's own branch
        fresh = (own_commits(cwd, default, branch, f"could not compare {branch} with origin/{default}", look) == 0
                 and not upstream_of(cwd, branch, f"could not read the upstream of {branch}", look))
        gone = regenerated(top, pre, n, paths, fresh)             # step 1: what idd-diagnose writes again
        for p in gone:
            discard(cwd, top, p, f"could not discard {one_line(p, 80)}", f"remove it by hand, check out {default}")
        paths = [p for p in paths if p not in gone]
        bad = [p for p in paths if keep_out(p, pre)]              # step 2: places that are never committed
        if bad:
            raise trouble(n, on, "it holds files IDD keeps out of git",
                          f"have git ignore them, commit or remove what else is left, check out {default}", bad)
        if paths:                                                 # step 3: everything else stays with the issue
            todo = f"commit or remove what is left on {on}, check out {default}"
            git(cwd, ["add", "-A", "--", ":(top)"], f"could not stage what the run left on {on}", f"{todo}, {AGAIN}")
            git(cwd, ["commit", "-q", "-m", f"chore: keep what the run of #{n} left (#{n})"],
                f"could not commit what the run left on {on}", f"{todo}, {AGAIN}")
            commit = git(cwd, ["rev-parse", "HEAD"], f"could not read the new commit on {on}",
                         f"check out {default}, {AGAIN}").strip()
            prior[branch] = {"branch": branch, "commit": commit, "paths": paths[:PATHS_KEPT],
                             "more": max(0, len(paths) - PATHS_KEPT),
                             "shared": [p for p in paths if SHARED_LOG_RE.search(p)][:PATHS_KEPT]}
            last["kept"] = list(prior.values())                   # saved now: a later step may still fail
            save_state(cwd, st)
        git(cwd, ["checkout", "-q", default], f"could not check out {default}", f"check out {default} by hand, {AGAIN}")
    elif branch == default:                                       # row 2: nothing may be left here
        if paths:
            raise trouble(n, on, f"{default} has changes that no branch of the issue holds",
                          "commit them elsewhere or remove them", paths)
    else:                                                         # row 3
        raise trouble(n, on, f"it is neither {default} nor a branch of #{n}", f"check out {default}")
    git(cwd, ["fetch", "-q", "origin", default], f"could not fetch {default} from origin",
        f"check that origin can be reached, {AGAIN}")
    compare = f"could not compare {default} with origin/{default}"
    behind = int(git(cwd, ["rev-list", "--count", f"refs/heads/{default}..refs/remotes/origin/{default}"], compare, look).strip() or "0")
    ahead = int(git(cwd, ["rev-list", "--count", f"refs/remotes/origin/{default}..refs/heads/{default}"], compare, look).strip() or "0")
    if behind and not ahead:   # a default branch with commits of its own is left alone: a PR-path issue starts from origin's
        git(cwd, ["merge", "-q", "--ff-only", f"refs/remotes/origin/{default}"],
            f"{default} could not be fast-forwarded to origin/{default}",
            f"bring {default} level with origin/{default} by hand, {AGAIN}")
    if git(cwd, ["status", "--porcelain"], "could not read the working tree", look).strip():   # the check every PR-path issue starts with
        raise trouble(n, default, f"the working tree is not clean on {default}", "commit or remove what is there",
                      leftovers(cwd)[0])
    kept = []
    for b in idd_branches(cwd).get(n, []):   # every one of them was created by this run: next skips an issue that had one
        if (own_commits(cwd, default, b, f"could not compare {b} with origin/{default}", look) == 0
                and not upstream_of(cwd, b, f"could not read the upstream of {b}", look)
                and git_ok(cwd, ["branch", "-q", "-D", b])):   # no commit is lost: each is on origin's default branch
            continue
        kept.append(prior.get(b) or {"branch": b, "commit": ""})
    return kept, gone


def cmd_stop(argv):
    a = common(argv, {"--cwd", "--repo", "--reason"}, ["--cwd", "--reason"])
    if a is None:
        return usage("stop --cwd C [--repo O/R] --reason TEXT")
    st = load_state(a["--cwd"], a.get("--repo"))
    if st is None:
        return refuse("no rest run in this working tree")
    if not st["stop"]:   # the first reason stands
        st["stop"] = {"reason": one_line(a["--reason"], REASON_MAX) or "no reason given", "at": iso(now())}
        save_state(a["--cwd"], st)
    return emit({"stopped": one_line(st["stop"]["reason"], REASON_MAX)})


def held(k, default):
    """': the paths of settle's commit', with a note when one of them is a log shared by all issues."""
    paths = k.get("paths", [])
    if not paths:
        return ""
    text = ": " + ", ".join(one_line(p, 120) for p in paths) + (f" and {k['more']} more" if k.get("more") else "")
    shared = k.get("shared", [])
    if shared:
        text += (f" — {', '.join(one_line(p, 120) for p in shared)} is a log shared by all issues: its new lines are on "
                 f"this branch, not on {one_line(default, 60)}")
    return text


def cmd_report(argv):
    a = common(argv, {"--cwd", "--repo"}, ["--cwd", "--repo"])
    if a is None:
        return usage("report --cwd C --repo O/R")
    cwd, repo = a["--cwd"], a["--repo"]
    st = load_state(cwd, repo)
    if st is None:
        return refuse("no rest run in this working tree")
    try:
        lst, unread = listing(repo), ""
    except Exception as exc:   # whatever went wrong, the attempts below are what this run did
        lst, unread = None, str(exc) if isinstance(exc, Stop) else f"{type(exc).__name__}: {exc}"
    closed = [x for x in st["attempts"] if x["outcome"] == "closed"]
    stopped = [x for x in st["attempts"] if x["outcome"] == "stopped"]
    flight = [x for x in st["attempts"] if x["outcome"] is None]
    out = [f"rest run report — {repo}",
           f"started {one_line(st['started_at'], 40)}, {len(st['attempts'])} issue(s) attempted",
           f"closed ({len(closed)}): {nums(x['issue'] for x in closed)}"]
    # An issue this run handed out is named once, here, with the questions it now waits on.
    asked = lst["questions"] if lst else {}
    rows_of = lambda n: [f"    - {q}" for q in asked.get(str(n), [])]
    open_now = {n for numbers in lst["classes"].values() for n in numbers} if lst else set()
    for x in closed:
        if x["issue"] in open_now:   # recorded as closed by this run, and someone reopened it since
            out.append(f"  #{x['issue']} — open again")
            out += rows_of(x["issue"])
        for k in (k for k in x.get("kept", []) if k["commit"]):   # a merged branch is named only when settle added to it
            out.append(f"  #{x['issue']} — what the run left is kept on {one_line(k['branch'], 120)} (commit {one_line(k['commit'], 40)[:7]}){held(k, st['default'])}")
    out.append(f"stopped ({len(stopped)}):" + ("" if stopped else " -"))
    for x in stopped:
        out.append(f"  #{x['issue']} — {one_line(x['reason'], REASON_MAX)}")
        for k in x.get("kept", []):
            out.append(f"    branch {one_line(k['branch'], 120)} is kept"
                       + (f", with commit {one_line(k['commit'], 40)[:7]} holding what the run left{held(k, st['default'])}" if k["commit"] else ""))
        out += rows_of(x["issue"])
    if any(x.get("kept") for x in stopped) or any(k["commit"] for x in closed for k in x.get("kept", [])):
        out.append("  a later rest run records an issue with a kept branch as existing work; to have the issue started over, "
                   "delete the branch (git branch -D <branch>); to keep its work, look at the branch first")
    if any(x["reason"].startswith(EXISTING_WORK) for x in stopped):
        out.append("  an issue stopped with existing work is left for a person: its reason names the pull request or branch to look at")
    if flight:
        out.append(f"handed out, no result recorded ({len(flight)}): {nums(x['issue'] for x in flight)}")
        for x in flight:
            out += rows_of(x["issue"])
    if lst is None:
        out.append(f"the open issues could not be read, so the issues that were not run are not listed: {one_line(unread, REASON_MAX)}")
    else:
        attempted = {x["issue"] for x in st["attempts"]}   # these are listed above, with what happened to them
        waiting = [n for n in lst["classes"]["needs-person"] if n not in attempted]
        out.append(f"{LABELS['needs-person']} ({len(waiting)}):" + ("" if waiting else " -"))
        for n in waiting:
            out.append(f"  #{n}")
            out += rows_of(n)
        for name in NOT_RUN:
            rest = [n for n in lst["classes"][name] if n not in attempted]
            out.append(f"not run — {LABELS[name]}{REPORT_NOTES.get(name, '')} ({len(rest)}): {nums(rest)}")
        left = [n for n in lst["order"] if n not in attempted]
        if left:
            out.append(f"still to run ({len(left)}): {nums(left)}")
    if st["stop"]:
        out.append(f"run stopped: {one_line(st['stop']['reason'], REASON_MAX)}")
    print("\n".join(out))
    try:
        os.unlink(state_path(cwd))
    except OSError as exc:
        raise Stop(f"the report is printed, but the run state could not be deleted: {exc.strerror or exc}")
    return 0


COMMANDS = {"args": cmd_args, "list": cmd_list, "start": cmd_start, "next": cmd_next,
            "record": cmd_record, "settle": cmd_settle, "stop": cmd_stop, "report": cmd_report}


def main(argv):
    if not argv or argv[0] not in COMMANDS:
        return usage("unknown or missing subcommand")
    try:
        return COMMANDS[argv[0]](argv[1:])
    except Stop as exc:
        print("rest-queue: " + one_line(exc, 400), file=sys.stderr)   # one reason line, whatever gh printed
        return 3
    except Exception as exc:   # not a wrong call (1, 2): one reason line and 3, never a traceback
        print("rest-queue: unexpected failure — " + one_line(f"{type(exc).__name__}: {exc}", 400), file=sys.stderr)
        return 3


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
