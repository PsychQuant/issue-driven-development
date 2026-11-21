#!/usr/bin/env python3
"""rest-queue.py — which open issue /idd-all runs next when no issue was named, and where it runs (#478).

  rest-queue.py args   -- <the arguments /idd-all was called with>
  rest-queue.py list   --repo O/R [--json]
  rest-queue.py start  --cwd C --repo O/R --path PR --review yes|no [--take-over]
  rest-queue.py next   --cwd C --repo O/R --token K
  rest-queue.py where  --cwd C --repo O/R --token K
  rest-queue.py here   --cwd D --repo O/R --issue N --token K
  rest-queue.py record --cwd C --repo O/R --issue N --token K [--reason TEXT | --reason-stdin]
  rest-queue.py stop   --cwd C [--repo O/R] --token K --reason TEXT | --reason-stdin
  rest-queue.py report --cwd C --repo O/R --token K

C is the directory the run was started in, the top of its repository; D is the directory of an issue; K is the
token of the run, which start prints once.

args    classifies the invocation: {"mode": "rest" | "other" | "refuse"[, "reason"]}.
list    reads every open issue and prints its class and the run order. Read-only, no run.
start   begins a run and prints the list and the token of the run. A run whose last activity is less than 24 hours
        old and that report did not end is unfinished: start refuses it (exit 4) unless --take-over is given, which
        resumes it with a new token; the earlier token no longer counts. C must be the top of its repository. Rest
        mode runs on the PR path only: any other --path is refused. It stores the path, the default branch and the
        review flag (which a later start can add to the run and cannot drop from it). The working tree at C is not
        used: it can be on any branch, with changes, and worked in while the run goes.
next    re-reads the open issues and hands out the first one this run has not handed out yet, in a directory of
        its own: a clone at C/.claude/worktrees/rest-<N>, printed as "dir", made in a temporary folder and moved
        to its place, and bound to the issue by a mark in its git directory. A candidate with a local branch of its
        own (idd/N, idd/N-…), with something at the place of its directory, or for which the existing-work check
        does not say clear, is recorded as existing work instead and not handed out.
where   prints the directory of the issue in flight, and nothing else.
here    exits 0 when D is the directory this run made for issue N, bound to it, N is in flight, K is the token of
        the run, and the process is in D; the pipeline of an issue starts only there. The run of D is found by its
        place, R/.claude/worktrees/rest-<N>.
record  writes the outcome of the issue in flight: closed when GitHub says the issue is closed, stopped otherwise.
        It does nothing to the directory of the issue: rest mode removes no directory, the report names it.
stop    marks the whole run as stopped; next hands out nothing afterwards.
report  prints what the run did and deletes its state.

Every open issue falls into exactly one class, by TABLE (first match wins). Only candidates are run:
those with a Diagnosis first, then the others, each by ascending issue number.

The judgements are not made here: open clarity rows come from lib/intent.py, the gate group and the
Diagnosis type from lib/actionability.sh, write access and the trusted Diagnosis from lib/ghread.py, existing
work from check-existing-work.sh.

The open issues are read completely or not at all: one failed page, one missing field or one helper
that reports misuse ends the command without a list. One issue whose body GitHub does not render is not
such a failure: it gets the class unreadable and the others are classified as usual.

Run state: <C>/.claude/.idd/state/idd-all-rest.json. start refuses to begin when git would not ignore it.
In the repository at C this helper writes at three places only: that state folder, <top>/.claude/worktrees/, and
the local exclude file of the git directory (the rule for .claude/worktrees/, when git does not ignore that folder yet).

Exit: 0 done · 1 refused (args says refuse; no run; not the issue in flight; here: not the directory of that issue) ·
4 another session has this run, or may have it: a command of it holds the lock, a command was given a token that is
not the run's, or start found an unfinished run without --take-over (end the invocation; no stop, no report, no
next) · 2 usage · 3 GitHub, git or a helper could not be read, the run state could not be written, the clone of an
issue could not be made, C is not the top of its repository, or a failure nobody planned for
"""

import hashlib
import json
import os
import re
import secrets
import shutil   # read_issues: the temporary folder of the bodies it renders
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(HERE, "lib"))
import intent  # noqa: E402  open clarity rows, the close stage's reading
import rendered  # noqa: E402  GitHub's rendering of a body
import reststate  # noqa: E402  what a run state is: read here and by the close stage
from reststate import STATE_NAME, STATE_TTL, STATE_VERSION  # noqa: E402
from ghread import (TEST, Stop, can_write, gh_json, html_root, iso, issue_comments, latest_diagnosis,  # noqa: E402
                    now, parse_iso, ts)

_STEPS = [0]


def step():
    """A point between two changes this helper makes: after every command it runs, every write of the run state,
    and every file it moves or removes. Under the test suite (IDD_CLOSE_STAGE_TEST=1, as for the other test
    hooks) a run can be made to end at the n-th point, as if the process had been killed there
    (IDD_REST_STOP_AFTER_STEP=n), and to write the number of points it passed (IDD_REST_COUNT_STEPS=<file>)."""
    _STEPS[0] += 1
    if not TEST:
        return
    if os.environ.get("IDD_REST_STOP_AFTER_STEP") == str(_STEPS[0]):
        os._exit(99)
    count = os.environ.get("IDD_REST_COUNT_STEPS")
    if count:
        with open(count, "w", encoding="utf-8") as fh:
            fh.write(str(_STEPS[0]))


# git as this helper calls it: no signature lines in a log, no quoted paths, no colours, whatever the person's
# configuration says. (The one `git diff` that lists paths asks for paths from the top itself: --no-relative.)
GIT = ["git", "-c", "log.showSignature=false", "-c", "core.quotePath=false", "-c", "color.ui=false"]
# No optional locks, for every git this helper runs and every program it starts (the existing-work check, a clone):
# git status writes the refreshed index back otherwise. One guard, in the environment, so that its test has teeth.
os.environ["GIT_OPTIONAL_LOCKS"] = "0"
_print = print


def print(*args, **kw):
    """print, with a name that is not UTF-8 shown with its bytes escaped: a reason line is never a failed write."""
    _print(*[a.encode("utf-8", "backslashreplace").decode("utf-8") if isinstance(a, str) else a for a in args], **kw)


def run_cmd(cmd, cwd=None, env=None):
    """(exit code, stdout, stderr) of a command. The output is read as bytes: a carriage return in a file name
    stays one (a pipe read as text turns it into a line feed, and the name then names no file), and bytes that are
    not UTF-8 survive the way back to a path."""
    try:
        proc = subprocess.run(cmd, cwd=cwd, capture_output=True, env=env)
    except OSError as exc:
        raise Stop(f"could not run {cmd[0]}: {exc.strerror or exc}")
    step()
    return proc.returncode, proc.stdout.decode("utf-8", "surrogateescape"), proc.stderr.decode("utf-8", "surrogateescape")


REPO_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
STATE_REL = ".claude/.idd/state/" + STATE_NAME
UNATTENDED_REL = ".claude/.idd/state/unattended.json"   # lib/unattended-state.sh
HELPER_PREFIX = "rest-queue: "   # what main() puts before a reason line
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
        return "refuse", ("`rest` runs every open issue that is ready and cannot be combined with an issue, a description or a file "
                          "(a description that contains the word rest is one argument: put it in quotes)")
    if not positionals or positionals == ["rest"]:
        if in_chain:
            return "refuse", "--in-chain is for a call that names an issue"
        return "rest", ""
    if positionals == ["last"]:   # the word the request for this mode first used; never the title of a new issue
        return "refuse", "`last` is not a mode: to run every open issue that is ready, call /idd-all with no argument or with `rest`"
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
        every = issue_comments(repo, node["number"])
        if len(every) < node["comments"]["totalCount"]:   # the second read is not complete either: no class is decided on part of them
            raise Stop(f"the comments of #{node['number']} could not be read completely "
                       f"({len(every)} of {node['comments']['totalCount']})")
        return every
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
        if "HTTP 403" in str(exc) and "rate limit" not in str(exc).lower():   # GitHub answers this question only to an account that can write itself
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
    return os.path.join(state_dir(cwd), STATE_NAME)   # a symbolic link there is a file that cannot be used (reststate.read)


class Busy(Stop):
    """Another session has this run, or may have it: exit 4, and the invocation ends (no stop, no report, no next)."""


_LOCK = []


def lock_run(cwd, create):
    """Hold the lock of the run at this --cwd until the process ends: the commands that write the run state do not
    overlap. Without `create`, a working tree that has no state folder has no run, and nothing is locked."""
    folder = state_dir(cwd)
    if not os.path.isdir(folder):
        if not create:
            return
        try:
            os.makedirs(folder, mode=0o700, exist_ok=True)
        except OSError as exc:
            raise Stop(f"could not make the state folder: {exc.strerror or exc}")
    wait = float(os.environ.get("IDD_REST_LOCK_WAIT", "30")) if TEST else reststate.LOCK_WAIT
    try:
        _LOCK.append(reststate.lock(folder, wait))
    except reststate.Held:
        raise Busy("another rest command for this run is going on (its lock is held) — two sessions are not to run "
                   f"the same rest run; when no other session runs it, {AGAIN}")
    except OSError as exc:
        raise Stop(f"could not open the lock of the run ({reststate.LOCK_NAME}): {exc.strerror or exc}")


def displaced(then):
    """Busy: the token is not the one of this run. Another session took the run over with start --take-over and runs
    it now; the session that holds the earlier token ends its invocation, as with a lock it cannot get."""
    return Busy("the token is not the one of this rest run: another session has taken the run over (start --take-over) "
                f"and runs it now — {then}; end this invocation: no stop, no report, no next")


def owned_state(cwd, repo, token, then):
    """The run state at this --cwd (None when there is none), for a command that is given the token of the run; Busy
    (exit 4) when the token is not the run's. The token is compared in reststate.owns, the one comparison of both helpers."""
    st, problem = read_state(cwd, repo)
    if st is None and problem.startswith(OTHER_REPO):   # replaced by a run for another repository, which only start --take-over does
        raise Busy(f"the rest run in this working tree is now one for another repository ({problem}): another session replaced "
                   f"this run with start --take-over — {then}; end this invocation: no stop, no report, no next")
    if st is not None and not reststate.owns(st, token):
        raise displaced(then)
    return st


def test_sleep(name):
    """A pause at a named point, under the test suite only (IDD_REST_SLEEP_<NAME>=seconds): two commands can then be
    made to overlap there."""
    if TEST and os.environ.get("IDD_REST_SLEEP_" + name):
        time.sleep(float(os.environ["IDD_REST_SLEEP_" + name]))


def read_state(cwd, repo=None):
    """(state, problem). The run state of this working tree; or None, with the reason when a state file is
    there and this helper cannot use it ('' when there is no file)."""
    kind, st = reststate.read(state_path(cwd))
    if kind == "none":
        return None, ""
    if kind != "ok":
        return None, "it cannot be read (a symbolic link, or not JSON)"
    if not reststate.usable(st):
        return None, "it is not a run state this helper can read"
    if repo is not None and st["repo"].lower() != repo.lower():   # GitHub does not tell owner/name apart by letter case
        return None, f"{OTHER_REPO} {one_line(st['repo'], 80)}"   # a state this helper can read: start replaces it (--take-over) and says whose it was
    return st, ""


def other_run(cwd, repo):
    """The usable state of a run for another repository in this working tree, or None."""
    kind, st = reststate.read(state_path(cwd))
    if kind == "ok" and reststate.usable(st) and st["repo"].lower() != repo.lower():
        return st
    return None


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
        step()
    except OSError as exc:
        if tmp and os.path.exists(tmp):
            os.unlink(tmp)
        raise Stop(f"could not write the run state: {exc.strerror or exc}")


def in_flight(st):
    return next((a for a in st["attempts"] if a["outcome"] is None), None)


# ── git, and the directory of an issue ─────────────────────────────────────

BRANCH_OF = r"idd/{n}(?:-.*)?"   # an issue's own branch; scripts/check-existing-work.sh own() has the same rule
OTHER_REPO = "it belongs to a run for"
NO_RUN = ("no rest run at this --cwd — before a run has started, call start; after it has, this --cwd is not the "
          "one start was given: give that one, and do not call start again")
AGAIN = "then run the same /idd-all command again (same flags)"
PATHS_KEPT = 10
WORKTREES = ".claude/worktrees"   # at the top of the repository the run was started in: the directories of the issues
DIR_RE = re.compile(r"^rest-(0|[1-9][0-9]*)$")
EXCLUDED_IN_DIR = (".claude/.idd/state/", ".claude/worktrees/", ".claude/.idd/tree-lock*")   # the clone's own exclude file
CARRIED = ("user.name", "user.email")   # the configuration a directory takes from the repository the run was started in
CHECK_SCRIPT = os.path.join(HERE, "check-existing-work.sh")


class GitFailed(Stop):
    """A git step failed: what was being done, git's own words, and what a person does next."""

    def __init__(self, what, err, todo=""):
        super().__init__(f"{what} ({err})" + (f" — {todo}" if todo else ""))
        self.what, self.err, self.todo = what, err, todo


def git(cwd, args, what, todo=""):
    """git's stdout in the repository that holds `cwd`; GitFailed naming `what`, git's reason and `todo` when git fails."""
    rc, out, err = run_cmd([*GIT, "-C", cwd] + args)
    if rc != 0:
        raise GitFailed(what, one_line(err, 200) or "git exited " + str(rc), todo)
    return out


def git_ok(cwd, args):
    return run_cmd([*GIT, "-C", cwd] + args)[0] == 0


def git_in(d):
    """git for the directory of an issue. The git directory and the working tree are named, so git never looks
    further up: a folder below the working tree that holds no usable repository would otherwise be answered for by
    the repository the run was started in."""
    return [*GIT, "--git-dir", os.path.join(d, ".git"), "--work-tree", d]


def in_dir(d, args):
    """(exit code, stdout, stderr) of a git command in the directory of an issue."""
    return run_cmd(git_in(d) + args, cwd=d)


def line_of(out):
    """One line of output without its line end, and nothing else taken off: a path may end in a space."""
    return out[:-1] if out.endswith("\n") else out


def ensure_ignored(cwd):
    """Refuse a working tree in which git would not ignore the run state: an untracked state file would show in
    the working tree the run was started in (#564 makes idd-all add the rule itself)."""
    for probe in (STATE_REL, UNATTENDED_REL):   # the folder, not one file: the unattended marker and the close stage's state live there too
        rc, _, err = run_cmd([*GIT, "-C", cwd, "check-ignore", "-q", "--", probe])
        if rc == 1:
            raise Stop("git would not ignore the run state in .claude/.idd/state/ — add the line .claude/.idd/state/ to "
                       ".git/info/exclude (or .gitignore), then start again")
        if rc != 0:
            raise Stop(f"git cannot tell whether .claude/.idd/state/ is ignored here (is this a git working tree?): "
                       f"{one_line(err, 200) or 'git check-ignore exited ' + str(rc)}")


def top_of(cwd):
    return line_of(git(cwd, ["rev-parse", "--show-toplevel"], "could not read the top of the repository",
                       f"check that git can read this working tree, {AGAIN}"))


def ensure_top(cwd):
    """The top of the repository at --cwd, which --cwd must be: the state of a run is then where the directories of
    its issues show it (R/.claude/worktrees/rest-<N> belongs to the run whose state is below R). Called before
    anything is written, the state folder included. The path of the top must be printable as it is: the report names
    directories by their paths, and a path that cannot be shown exactly cannot be looked at and deleted."""
    top = top_of(cwd)
    if not reststate.printable(top):
        raise Stop("the path of this repository holds a character that cannot be printed as it is (a control character, "
                   "or a byte that is not UTF-8): rest mode names the directories of its issues by their paths — move "
                   "the repository to a path without one, then start again")
    if os.path.realpath(cwd) != os.path.realpath(top):
        raise Stop(f"rest mode starts at the top of the repository, {one_line(top, 200)}, not in a folder below it — give "
                   "that directory as --cwd (/idd-all there), then start again")
    return top


def ensure_dirs_ignored(top):
    """Make git ignore the folder of the directories at the top, through the plugin's writer for local runtime
    paths (the local exclude file; no tracked file is changed). Stop when git still would not ignore it."""
    probe = WORKTREES + "/rest-0/x"
    ignored = lambda: run_cmd([*GIT, "-C", top, "check-ignore", "-q", "--", probe])[0] == 0
    if ignored():
        return
    run_cmd(["bash", "-c", '. "$1" && idd_ignore_runtime_paths "$2"', "_", os.path.join(HERE, "lib", "runtime-ignore.sh"), top])
    if not ignored():
        raise Stop(f"git would not ignore {WORKTREES}/ at the top of this repository, where the directory of each issue is "
                   f"made — add the line {WORKTREES}/ to .git/info/exclude, then start again")


def idd_branches(cwd):
    """{issue number: [local branch names idd/N or idd/N-…]} of the repository the run was started in."""
    out = git(cwd, ["for-each-ref", "--format=%(refname)", "refs/heads/idd/"], "could not list the local branches",
              f"check that git can read this working tree, {AGAIN}")
    found = {}
    for ref in out.splitlines():
        m = re.match(r"^refs/heads/idd/(0|[1-9][0-9]*)(?:-.*)?$", ref)   # BRANCH_OF, for any issue number as it is written (no leading zero)
        if m:
            found.setdefault(int(m.group(1)), []).append(ref[len("refs/heads/"):])
    return {n: sorted(b) for n, b in found.items()}


STATUS = ["status", "--porcelain=v1", "-z", "--untracked-files=all", "--ignore-submodules=none", "--no-renames"]


def entries_of(out):
    """[(XY, path)] of git status -z: one entry per file (an untracked folder is not folded into one entry; a
    rename is a deletion and an addition). This is the one way the helper reads a working tree: what git is
    configured to show (untracked files, renames, a branch line) does not change the answer."""
    return [(e[:2], e[3:]) for e in out.split("\0") if len(e) > 3 and e[2] == " " and not e.startswith("## ")]


def current_branch(cwd):
    return line_of(run_cmd([*GIT, "-C", cwd, "symbolic-ref", "--quiet", "--short", "HEAD"])[1])


def branch_name_ok(cwd, name):
    """A name that can only be a branch: not an option, and well formed as refs/heads/<name> (the --branch form
    of check-ref-format would also expand @{-1})."""
    return bool(name) and not name.startswith("-") and git_ok(cwd, ["check-ref-format", "refs/heads/" + name])


def listed(paths):
    """At most ten of the names, each on one line, then the number of the others."""
    return (", ".join(one_line(p, 120) for p in paths[:PATHS_KEPT])
            + (f" and {len(paths) - PATHS_KEPT} more" if len(paths) > PATHS_KEPT else ""))


def dir_of(top, n):
    return os.path.join(top, ".claude", "worktrees", f"rest-{n}")


def link_on_the_way(top, path):
    """The first symbolic link among `path` and the folders above it, up to (not including) `top`; '' when none."""
    probe = path
    while probe and probe != top and probe != os.path.dirname(probe):
        if os.path.islink(probe):
            return probe
        probe = os.path.dirname(probe)
    return ""


def own_top(d):
    """True when `d` is a folder (not a link) that holds a git directory of its own which git can use."""
    g = os.path.join(d, ".git")
    if os.path.islink(d) or not os.path.isdir(d) or os.path.islink(g) or not os.path.isdir(g):
        return False
    return in_dir(d, ["rev-parse", "--git-dir"])[0] == 0


def kept_dirs(top):
    """{issue number: path} of what is at the place of a directory, whatever it is (read by name)."""
    base = os.path.join(top, ".claude", "worktrees")
    try:
        names = os.listdir(base)
    except OSError:
        return {}
    return {int(m.group(1)): os.path.join(base, name) for name in names for m in [DIR_RE.match(name)] if m}


class Taken(Stop):
    """The place of the directory of an issue is taken: rest mode removes no directory."""


def taken(d, n, why):
    return Taken(f"its directory could not be made: {why} {d} (an earlier next was ended part of the way, or a person or "
                 "another program put it there) — rest mode removes no directory: look at it, delete it, and a later "
                 "rest run starts the issue over")


def adopt(flight):
    """True when the place of the directory holds the directory an earlier next of this run finished: a repository
    of its own on the default branch, bound to the issue (the move into the place is the last step of make_dir)."""
    d = flight["dir"]
    return own_top(d) and not reststate.bound(flight, d)


def make_dir(cwd, top, st, flight, save):
    """Make the directory of the issue in flight: a clone of its own, on the default branch as origin has it.

    The clone is made in a temporary folder whose name only this process knows, so that a clone that fails, and git's
    own clean-up of it, touch nothing but that folder; the folder is recorded with the issue before the clone starts,
    so that the report names it when this next is ended. The configuration, the exclude lines and the mark are written
    there. Then the place of the directory is taken with mkdir (it fails when anything is there) and the clone is moved
    into the empty folder this process just made; a rename onto a folder that is not empty fails, so nothing a person or
    another program put there is replaced. Taken when the place is taken; the temporary folder is left as it is."""
    d, n = flight["dir"], flight["issue"]
    todo = f"look at {one_line(d, 200)} and at what git says, {AGAIN}"
    test_sleep("BEFORE_MAKE")
    base = os.path.dirname(d)
    link = link_on_the_way(top, base)
    if link:
        raise Stop(f"{one_line(link, 200)} is a symbolic link: the directory of #{n} is not made through it")
    if os.path.lexists(d):   # rest mode removes no directory: an earlier next that was ended part of the way left something there
        raise taken(d, n, "something is at")
    try:
        os.makedirs(base, exist_ok=True)
        tmp = tempfile.mkdtemp(prefix=f".rest-{n}-", dir=base)   # never a directory name (DIR_RE): kept_dirs does not take it for one
    except OSError as exc:
        raise Stop(f"could not make a folder in {WORKTREES}/: {exc.strerror or exc}")
    flight.setdefault("tmps", []).append(tmp)
    save()   # recorded before the clone: an interrupted next leaves a folder the report names
    url = line_of(git(cwd, ["remote", "get-url", "origin"], "could not read the origin of this repository", todo))
    if "://" not in url and not os.path.isabs(url) and os.path.exists(os.path.join(top, url)):
        url = os.path.realpath(os.path.join(top, url))   # a path relative to this repository would point elsewhere from the clone
    test_sleep("BEFORE_CLONE")
    rc, _, err = run_cmd([*GIT, "clone", "--quiet", "--reference-if-able", top, "--dissociate", "--branch", st["default"], "--", url, tmp])
    if rc != 0:
        raise GitFailed(f"could not make the directory of #{n} (git clone)", one_line(err, 200) or "git exited " + str(rc), todo)
    if not own_top(tmp) or line_of(in_dir(tmp, ["symbolic-ref", "--quiet", "--short", "HEAD"])[1]) != st["default"]:
        raise Stop(f"the clone of #{n} was made but is not a repository of its own on {one_line(st['default'], 60)} — {todo}")
    for key in CARRIED:
        rc, value, _ = run_cmd([*GIT, "-C", cwd, "config", "--get", key])
        if rc == 0 and line_of(value):
            if in_dir(tmp, ["config", key, line_of(value)])[0] != 0:
                raise Stop(f"could not set {key} in the clone of #{n} — {todo}")
    exclude = os.path.join(tmp, ".git", "info", "exclude")   # one of the two files the helper writes into the clone
    link = link_on_the_way(tmp, exclude)
    if link:
        raise Stop(f"{one_line(link, 200)} in the clone of #{n} is a symbolic link: nothing is written through it — {todo}")
    try:
        with open(exclude, "a", encoding="utf-8") as fh:
            fh.write("\n# rest mode (#478): what the plugin keeps out of git in the directory of an issue\n"
                     + "".join(line + "\n" for line in EXCLUDED_IN_DIR))
        step()
        fd = os.open(os.path.join(tmp, ".git", reststate.MARK_NAME),   # the other one: the mark that binds it to the issue
                     os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0), 0o644)
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump({"mark": flight["mark"]}, fh)
        step()
    except OSError as exc:
        raise Stop(f"could not write into the clone of #{n}: {exc.strerror or exc} — {todo}")
    flight["origin"] = reststate.origin_of(tmp) or ""
    if flight["origin"] != url:
        raise Stop(f"the clone of #{n} does not name the origin it was cloned from — {todo}")
    save()
    link = link_on_the_way(top, base)   # again: the folder may have been swapped for a link while the clone was made
    if link:
        raise Stop(f"{one_line(link, 200)} is a symbolic link: the directory of #{n} is not made through it — {todo}")
    try:
        os.mkdir(d)   # the place, taken: mkdir fails when anything is there
    except OSError:
        raise taken(d, n, "something was put at the place while the clone was made:")
    step()
    try:
        os.rename(tmp, d)   # onto the empty folder this process just made; a folder that is no longer empty is not replaced
    except OSError:
        raise taken(d, n, "something was put at the place while the clone was moved there:")
    step()
    flight["tmps"].remove(tmp)


def digest(text):
    return hashlib.sha256(text.encode("utf-8", "surrogateescape")).hexdigest()


def root_now(cwd):
    """What a helper can see of the working tree the run was started in: the commit and the branch checked out,
    what git lists as changed or untracked, and the stash."""
    out = lambda args: run_cmd([*GIT, "-C", cwd] + args)[1]
    return {"head": line_of(out(["rev-parse", "-q", "--verify", "HEAD"])), "branch": current_branch(cwd),
            "files": digest(git(cwd, STATUS, "could not read the working tree", f"check that git can read this working tree, {AGAIN}")),
            "stash": digest(out(["stash", "list", "--format=%H"]))}


CHANGED = {"head": "the checked-out commit", "branch": "the branch", "files": "the files", "stash": "the stash"}


def no_tag_pruning():
    """The environment of the existing-work check: its fetch in the working tree the run was started in may remove
    remote-tracking branches that origin no longer has, and never a local tag, whatever fetch.pruneTags or
    remote.origin.pruneTags say (configuration given in the environment comes after every configuration file)."""
    env = dict(os.environ)
    count = int(env.get("GIT_CONFIG_COUNT", "0") or 0) if (env.get("GIT_CONFIG_COUNT", "0") or "0").isdigit() else 0
    for i, key in enumerate(("fetch.pruneTags", "remote.origin.pruneTags")):
        env[f"GIT_CONFIG_KEY_{count + i}"], env[f"GIT_CONFIG_VALUE_{count + i}"] = key, "false"
    env["GIT_CONFIG_COUNT"] = str(count + 2)
    return env


def existing_work(cwd, repo, n):
    """'' when the existing-work check says clear for the issue; otherwise the reason it is not handed out."""
    rc, out, err = run_cmd(["bash", CHECK_SCRIPT, "--cwd", cwd, repo, str(n)], env=no_tag_pruning())
    try:
        found = json.loads(out)["issues"][str(n)]
        verdict, reason = found["verdict"], one_line(found.get("reason") or "", 200)
    except (ValueError, KeyError, TypeError):
        verdict, reason = None, one_line(err, 200) or f"the check exited {rc} without an answer"
    if rc == 0 and verdict == "clear":
        return ""
    if rc == 0 and verdict in ("resume", "blocked"):
        return f"{EXISTING_WORK} {reason or verdict}"
    return f"{EXISTING_WORK} could not be determined ({reason or verdict or 'no answer'}) — look at the issue's pull requests and branches"


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


def list_lines(lst, attempted=(), branches=None, dirs=None):
    """`branches`: {issue: [local branch names]} of the repository the run was started in; `dirs`: {issue: what is
    at the place of its directory}; both when there is a working tree to look at."""
    there = set(branches or {}) | set(dirs or {})
    local = [n for n in lst["order"] if n not in attempted and n in there]
    todo = [n for n in lst["order"] if n not in attempted and n not in there]
    diagnosed = sum(1 for n in todo if n in lst["diagnosed"])
    lines = [f"open issues: {lst['open']}",
             f"to run ({len(todo)}): {nums(todo)}",
             f"  diagnosed {diagnosed}, not diagnosed {len(todo) - diagnosed}"]
    if local:
        lines.append(f"candidates with a local branch or a directory an earlier run kept, recorded as existing work when their turn comes ({len(local)}): {nums(local)}")
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
    if "--token" in a and not reststate.TOKEN_RE.match(a["--token"]):   # the form start prints: 24 hexadecimal digits
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
    a = common(argv, {"--cwd", "--repo", "--path", "--review"}, ["--cwd", "--repo", "--path", "--review"], {"--take-over"})
    if a is None or a["--review"] not in ("yes", "no"):
        return usage("start --cwd C --repo O/R --path PR --review yes|no [--take-over]")
    cwd, repo, path, review = a["--cwd"], a["--repo"], a["--path"], a["--review"] == "yes"
    if path != "PR":   # every issue runs on a branch of its own and is handed over as a pull request
        raise Stop(f"rest mode runs on the PR path only, and this run resolved to {one_line(path, 40)} — give the same "
                   "command again with --pr (in place of --no-pr when the command has it) and the other flags kept; when "
                   "the path was downgraded because the ralph-loop plugin is missing, install it first; or name the "
                   "issues one at a time")
    top = ensure_top(cwd)   # before anything is written, the state folder included
    ensure_ignored(cwd)   # before anything is read or written
    lock_run(cwd, True)
    st, problem = read_state(cwd, repo)
    again = "then give the same command again (same flags)"
    if st is None and problem and not problem.startswith(OTHER_REPO) and state_written_within(cwd, STATE_TTL):
        # the review flag of that run cannot be read: a new run in its place would drop it
        raise Stop(f"a run state file is in this working tree and cannot be used ({problem}): {STATE_REL} — it was written in "
                   "the last 24 hours, so it is not replaced; delete it when no rest run is going on in this working tree, "
                   f"{again}")
    resumed = st is not None and now() - ts(st["updated_at"]) < STATE_TTL
    if resumed and not a.get("--take-over"):   # a session may be running it: taking it over is said, not done by default
        raise Busy(f"an unfinished rest run is in this working tree (started {one_line(st['started_at'], 40)}, last active "
                   f"{one_line(st['updated_at'], 40)}) and a session may be running it — when no other session runs it, take it "
                   "over with start --take-over and the same flags; the session that ran it then ends at its next command")
    other = other_run(cwd, repo) if st is None else None
    if other and now() - ts(other["updated_at"]) < STATE_TTL and not a.get("--take-over"):
        raise Busy(f"an unfinished rest run for {one_line(other['repo'], 80)} is in this working tree (last active "
                   f"{one_line(other['updated_at'], 40)}) and a session may be running it — when no other session runs it, "
                   "start --take-over replaces it with a run for this repository; the session that ran it then ends at its next command")
    unreported = [] if resumed else forgotten(st if st is not None else other) if (st or other) else []   # a run nobody ended with its report
    lst = listing(repo)   # before anything is written: a failed read leaves no run behind
    branches = idd_branches(cwd)
    differs = ""
    if resumed:
        if st["review"] and not review:
            differs = "the review flag differs: this run was started with --review and keeps it (ending the run with its report is the way to drop it)"
        elif review and not st["review"]:
            flight = in_flight(st)
            differs = ("the review flag differs: --review is added to this run, every issue handed out from here on stops at verified"
                       + (f"; a close stage that is already running for #{flight['issue']} is not stopped by it (it read the flag "
                          "when it started)" if flight else ""))
        st["review"] = st["review"] or review
    else:
        default = gh_json(["repo", "view", repo, "--json", "defaultBranchRef"],
                          f"the default branch of {repo}").get("defaultBranchRef") or {}
        default = default.get("name") if isinstance(default, dict) else None
        if not isinstance(default, str) or not branch_name_ok(cwd, default):
            raise Stop(f"could not read the default branch of {repo} from GitHub")
        st = {"version": STATE_VERSION, "repo": repo, "path": path, "default": default, "review": review,
              "started_at": iso(now()), "updated_at": "", "attempts": [], "stop": None}
    token = secrets.token_hex(12)   # printed once, below; the state keeps only its digest
    st["token_digest"] = reststate.digest(token)
    ensure_dirs_ignored(top)   # the directory of each issue is made below the top: git is not to list it there
    save_state(cwd, st)   # a resumed run too: starting is activity, and the 24 hours count from the last one
    attempted = [x["issue"] for x in st["attempts"]]
    head = f"rest run for {repo} — "
    head += (f"resumed (started {one_line(st['started_at'], 40)}, {len(attempted)} attempt(s) so far)" if resumed
             else f"new (started {one_line(st['started_at'], 40)})")
    print(head)
    print(f"token: {token}")
    print("keep the token with the run (the task list): every command of this run takes it as --token, and it is printed "
          "only here; a start --take-over gives a new one, and this one then no longer counts")
    if resumed:
        print("taken over: the token of the session that ran this run no longer counts; that session ends its invocation "
              "at its next command")
    print("review: " + ("yes — every issue stops at verified, nothing is merged" if st["review"] else "no — an issue whose verify is clean is merged and closed"))
    print(f"each issue runs in a directory of its own below {WORKTREES}/; this working tree is not used and can be worked in meanwhile")
    if differs:
        print(differs)
    if problem.startswith(OTHER_REPO):   # said, not silent: the attempts of that state are not carried over
        print(f"a run state was found in this working tree, and {problem}; this is a new run, and it replaces that file")
    elif problem:
        print(f"a run state was found in this working tree but cannot be used ({problem}) — it is older than 24 hours; this is a new run, and it replaces that file")
    if unreported:
        print("an earlier rest run in this working tree was never ended with its report; what it kept and nobody was told:")
        print("\n".join(unreported))
    if st["stop"]:
        print(f"this run stopped earlier: {one_line(st['stop']['reason'], REASON_MAX)} — next hands out nothing; call report to end it")
    flight = in_flight(st)
    if flight:
        print(f"in flight, no result recorded yet: #{flight['issue']}" + (f" in {flight['dir']}" if flight.get("dir") else ""))
    mine = {x["issue"] for x in st["attempts"] if x.get("dir")}   # the directories of this run are not existing work
    print("\n".join(list_lines(lst, attempted, branches, {n: p for n, p in kept_dirs(top).items() if n not in mine})))
    print("a candidate with a pull request or a branch on GitHub is not run either: it is recorded as existing work when its turn comes")
    return 0


def state_written_within(cwd, seconds):
    """True when the run state file was written less than `seconds` ago (by the file's own time)."""
    old = reststate.age(state_path(cwd), now())
    return old is not None and old < seconds


def paths_of(x):
    """[(label, path)] of the closed list the report names for an attempt, each only while something is at it: the
    directory of the issue; what was at its place when next found the place taken; a temporary folder of its clone."""
    out = []
    if x.get("dir") and (x.get("made") or not x.get("place")) and os.path.lexists(x["dir"]):
        out.append(("its directory" if x.get("made") else "its directory, not finished", x["dir"]))
    if x.get("place") and os.path.lexists(x["place"]):
        out.append(("what is at the place of its directory", x["place"]))
    out += [("a temporary folder of its clone, left by a next that was ended", t)
            for t in x.get("tmps", []) if os.path.lexists(t)]
    return out


def forgotten(st):
    """What a run that was never ended with its report left, as lines: only its report would have said it. The paths
    are printed as they are (a state with a path that cannot be printed is not usable)."""
    lines = []
    for x in st["attempts"]:
        found = paths_of(x)
        if found:
            lines.append(f"  #{x['issue']} — " + ("handed out, no outcome recorded" if x["outcome"] is None else x["outcome"]))
            lines += [f"    {label}: {p}" for label, p in found]
    return lines


def stopped_attempt(n, reason, place=None):
    stamp = iso(now())
    return {"issue": n, "handed_at": stamp, "outcome": "stopped", "recorded_at": stamp,
            "reason": one_line(reason, REASON_MAX), "dir": None, "made": False, "left": "none", "place": place}


def finish_dir(cwd, top, st, flight):
    """Make (or take up) the directory of the issue in flight and mark it as made. False when its place is taken:
    the issue is then recorded as stopped, with the place, and nothing is removed."""
    save = lambda: save_state(cwd, st)
    try:
        if os.path.lexists(flight["dir"]) and adopt(flight):   # an earlier next moved it there and was ended before it said so
            pass
        else:
            make_dir(cwd, top, st, flight, save)
    except Taken as exc:
        flight.update({"outcome": "stopped", "reason": one_line(exc, REASON_MAX), "recorded_at": iso(now()), "left": "none",
                       "place": flight["dir"]})
        save()
        print(f"→ #{flight['issue']} is not handed out: {one_line(exc, REASON_MAX)}", file=sys.stderr)
        return False
    flight["made"] = True
    save()
    return True


def cmd_next(argv):
    a = common(argv, {"--cwd", "--repo", "--token"}, ["--cwd", "--repo", "--token"])
    if a is None:
        return usage("next --cwd C --repo O/R --token K")
    cwd, repo = a["--cwd"], a["--repo"]
    top = ensure_top(cwd)
    lock_run(cwd, False)
    st = owned_state(cwd, repo, a["--token"], "nothing is handed out")
    if st is None:
        return refuse(NO_RUN)
    if st["stop"]:
        return emit({"next": None, "stopped": one_line(st["stop"]["reason"], REASON_MAX)})
    review = "yes" if st["review"] else "no"   # from the run state, so that it does not depend on anyone remembering it
    root = os.path.realpath(cwd)
    flight = in_flight(st)
    if flight and not flight.get("made"):   # an earlier next was ended before the directory was complete
        flight = flight if finish_dir(cwd, top, st, flight) else None
    if flight:
        print(f"→ #{flight['issue']} is still in flight: finish it in its directory and call record", file=sys.stderr)
        on = line_of(in_dir(flight["dir"], ["symbolic-ref", "--quiet", "--short", "HEAD"])[1]) if own_top(flight["dir"]) else ""
        mine = bool(re.fullmatch(BRANCH_OF.format(n=flight["issue"]), on))   # none: the issue had not reached the step that creates it
        return emit({"next": flight["issue"], "in_flight": True, "dir": flight["dir"], "root": root,
                     "branch": on if mine else None, "review": review})
    attempted = {x["issue"] for x in st["attempts"]}
    todo = [n for n in listing(repo)["order"] if n not in attempted]
    branches = idd_branches(cwd)
    while todo:
        n = todo.pop(0)
        # work that exists is for a person: three questions, in this order (closed list, the spec's)
        if n in branches:
            found, place = f"{EXISTING_WORK} local branch {branches[n][0]}", None
        elif os.path.lexists(dir_of(top, n)):
            place = dir_of(top, n)
            found = f"{EXISTING_WORK} directory {place} — rest mode removes no directory: look at it and delete it"
        else:
            found, place = existing_work(cwd, repo, n), None
        if found:
            st["attempts"].append(stopped_attempt(n, found, place))
            save_state(cwd, st)
            print(f"→ #{n} is not handed out: {one_line(found, REASON_MAX)}", file=sys.stderr)
            continue
        flight = {"issue": n, "handed_at": iso(now()), "outcome": None, "reason": "", "recorded_at": None,
                  "dir": dir_of(top, n), "made": False, "left": None, "at": root_now(cwd), "mark": secrets.token_hex(16),
                  "origin": "", "tmps": []}
        st["attempts"].append(flight)
        save_state(cwd, st)   # the directory is named before it is made
        if not finish_dir(cwd, top, st, flight):   # its place was taken while it was made: the following candidate
            continue
        print(f"→ next: #{n} in {one_line(flight['dir'], 200)} ({len(todo)} more after it)", file=sys.stderr)
        return emit({"next": n, "in_flight": False, "dir": flight["dir"], "root": root, "remaining": len(todo),
                     "review": review})
    save_state(cwd, st)
    return emit({"next": None, "done": True})


def cmd_where(argv):
    a = common(argv, {"--cwd", "--repo", "--token"}, ["--cwd", "--repo", "--token"])
    if a is None:
        return usage("where --cwd C --repo O/R --token K")
    st = owned_state(a["--cwd"], a["--repo"], a["--token"], "do not change to the directory of the issue")
    if st is None:
        return refuse(NO_RUN)
    flight = in_flight(st)
    if not flight or not flight.get("made"):
        return refuse("no issue of this run is in flight with a directory that was made — call next first")
    print(flight["dir"])   # the path and nothing else: the skill takes it from here, not by writing it into a command
    return 0


def cmd_here(argv):
    a = common(argv, {"--cwd", "--repo", "--issue", "--token"}, ["--cwd", "--repo", "--issue", "--token"])
    if a is None:
        return usage("here --cwd D --repo O/R --issue N --token K")
    d, repo, n = os.path.abspath(a["--cwd"]), a["--repo"], int(a["--issue"])   # as given: a symbolic link is not resolved away
    place = reststate.run_of(d)
    if place is None:
        st = load_state(d, repo) if os.path.isdir(d) else None
        flight = in_flight(st) if st else None
        if flight and flight["issue"] == n and flight.get("dir"):
            return refuse(f"{one_line(d, 200)} is not the directory of #{n}, which is {one_line(flight['dir'], 200)}: change to "
                          "that directory and use it as the working directory of the issue")
        return refuse(f"no rest run has #{n} in flight there ({one_line(d, 200)})")
    root_dir, m = place
    if m != n:
        return refuse(f"{one_line(d, 200)} is not the directory of #{n}")
    st = load_state(root_dir, repo) if os.path.isdir(root_dir) else None
    flight = in_flight(st) if st else None
    if st is not None and not reststate.owns(st, a["--token"]):   # before anything else of the run is looked at
        raise displaced("stop working on the issue here")
    if not flight or flight["issue"] != n or not flight.get("made") or flight["dir"] != d:
        return refuse(f"no rest run has #{n} in flight there ({one_line(d, 200)})")
    link = link_on_the_way(root_dir, d)
    if link:
        return refuse(f"a symbolic link is on the way to the directory of #{n}: {one_line(link, 200)}")
    if not own_top(d):
        return refuse(f"the directory of #{n} is not a repository of its own")
    unbound = reststate.bound(flight, d)
    if unbound:
        return refuse(f"the directory of #{n} is not bound to #{n}: {unbound} — do not run the pipeline of the issue there")
    try:
        here_now = os.path.realpath(os.getcwd())
    except OSError:
        here_now = ""
    if here_now != d:   # what writes by the shell's directory writes there
        return refuse(f"the current directory is {one_line(here_now or 'unknown', 200)}, not the directory of #{n}: the shell "
                      "does not keep its directory between commands, or it was changed — do not run the pipeline of the issue")
    return emit({"here": n, "root": root_dir})


def reason_given(a):
    """The reason of record or stop: the value of --reason, or all of standard input with --reason-stdin (text
    from outside does not have to pass through a shell argument). None when both forms are given."""
    if "--reason" in a and a.get("--reason-stdin"):
        return None
    if a.get("--reason-stdin"):   # bytes that are not UTF-8 become replacement characters, not a failure
        return sys.stdin.buffer.read().decode("utf-8", "replace")
    return a.get("--reason", "")


def cmd_record(argv):
    a = common(argv, {"--cwd", "--repo", "--issue", "--reason", "--token"}, ["--cwd", "--repo", "--issue", "--token"], {"--reason-stdin"})
    reason = None if a is None else reason_given(a)
    if reason is None:
        return usage("record --cwd C --repo O/R --issue N --token K [--reason TEXT | --reason-stdin]")
    cwd, repo, n = a["--cwd"], a["--repo"], int(a["--issue"])
    lock_run(cwd, False)
    st = owned_state(cwd, repo, a["--token"], "nothing is recorded")
    if st is None:
        return refuse(NO_RUN)
    test_sleep("AFTER_READ")
    x = in_flight(st)
    last = st["attempts"][-1] if st["attempts"] else None
    again = x is None and last and last["issue"] == n and last["outcome"] is not None and last.get("dir")
    if again:   # this issue was recorded last, and nothing was handed out since: what was recorded is printed again
        x = last
    elif x is None or x["issue"] != n:
        return refuse(f"#{n} is not the issue in flight" + (f" (#{x['issue']} is)" if x else " (none is)"))
    if not again:
        state = gh_json(["issue", "view", str(n), "--repo", repo, "--json", "state"], f"the state of #{n}").get("state")
        if state not in ("OPEN", "CLOSED"):
            raise Stop(f"could not read the state of #{n}")
        seen = root_now(cwd) if x.get("at") else None   # what a helper can see of this working tree, against the hand-out
        x["changed"] = [CHANGED[k] for k in reststate.AT_KEYS if seen and seen[k] != x["at"][k]]
        x["outcome"] = "closed" if state == "CLOSED" else "stopped"
        # a closed issue keeps the reason too: closed while its run reported a stop is not a finished run
        x["reason"] = one_line(reason, REASON_MAX) or ("" if state == "CLOSED" else "no reason given")
        x["recorded_at"] = iso(now())
        x["left"] = "left" if x.get("dir") and x.get("made") else "none"   # rest mode removes no directory
        save_state(cwd, st)
    return emit({"issue": n, "outcome": x["outcome"], "reason": x["reason"],
                 **({"dir": x["dir"]} if x.get("left") == "left" else {})})


def cmd_stop(argv):
    a = common(argv, {"--cwd", "--repo", "--reason", "--token"}, ["--cwd", "--token"], {"--reason-stdin"})
    reason = None if a is None or ("--reason" not in a and not a.get("--reason-stdin")) else reason_given(a)
    if reason is None:
        return usage("stop --cwd C [--repo O/R] --token K --reason TEXT | --reason-stdin")
    lock_run(a["--cwd"], False)
    st = owned_state(a["--cwd"], a.get("--repo"), a["--token"], "the run is not stopped")
    if st is None:
        return refuse("no rest run in this working tree")
    if not st["stop"]:   # the first reason stands
        reason = one_line(reason)
        if reason.startswith(HELPER_PREFIX):   # a line copied from this helper: without the prefix its end fits the limit
            reason = reason[len(HELPER_PREFIX):]
        st["stop"] = {"reason": one_line(reason, REASON_MAX) or "no reason given", "at": iso(now())}
        save_state(a["--cwd"], st)
    return emit({"stopped": one_line(st["stop"]["reason"], REASON_MAX)})


def about(x):
    """The lines under the entry of an attempt: every path of the closed list the report names (paths_of), each as it
    is on a line of its own, and the working tree the run was started in when it changed while the issue ran."""
    lines = [f"    {label}: {p}" for label, p in paths_of(x)]
    if x.get("changed"):
        lines.append(f"    while it ran, this working tree changed ({', '.join(x['changed'])}); rest mode does not write "
                     "there: when that was neither you nor another session, look at it")
    return lines


def cmd_report(argv):
    a = common(argv, {"--cwd", "--repo", "--token"}, ["--cwd", "--repo", "--token"])
    if a is None:
        return usage("report --cwd C --repo O/R --token K")
    cwd, repo = a["--cwd"], a["--repo"]
    lock_run(cwd, False)
    st = owned_state(cwd, repo, a["--token"], "no report is printed and the run goes on")
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
        if x["reason"]:              # closed, and its run reported a stop all the same
            out.append(f"  #{x['issue']} — its run reported: {one_line(x['reason'], REASON_MAX)}")
        if x["issue"] in open_now:   # recorded as closed by this run, and someone reopened it since
            out.append(("    " if x["reason"] else f"  #{x['issue']} — ") + "open again")
            out += rows_of(x["issue"])
        more = about(x)
        if more and not x["reason"] and x["issue"] not in open_now:
            out.append(f"  #{x['issue']}")   # the entry, named once; the lines below belong to it
        out += more
    out.append(f"stopped ({len(stopped)}):" + ("" if stopped else " -"))
    for x in stopped:
        out.append(f"  #{x['issue']} — {one_line(x['reason'], REASON_MAX)}")
        out += about(x)
        out += rows_of(x["issue"])
    if any(paths_of(x) for x in st["attempts"]):
        out.append("  rest mode removes no directory. A directory may hold work that exists nowhere else: commits that were not "
                   "pushed, changes that were not committed, a stash, a tag, records of the plugin. Look at a directory and "
                   "delete it; a later rest run does not take up an issue whose directory is still there")
    if any(x["reason"].startswith(EXISTING_WORK) for x in st["attempts"] if x["outcome"]):
        out.append("  an issue stopped with existing work is left for a person: its reason names the pull request, the branch or the directory to look at")
    if flight:
        out.append(f"handed out, no outcome recorded ({len(flight)}): {nums(x['issue'] for x in flight)}")
        for x in flight:
            out.append(f"  #{x['issue']}")
            out += about(x)
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


COMMANDS = {"args": cmd_args, "list": cmd_list, "start": cmd_start, "next": cmd_next, "where": cmd_where, "here": cmd_here,
            "record": cmd_record, "stop": cmd_stop, "report": cmd_report}
# The commands that do not take the token of a run (closed list): every other command is given it and refuses another.
NO_TOKEN = ("args", "list", "start")


def main(argv):
    if not argv or argv[0] not in COMMANDS:
        return usage("unknown or missing subcommand")
    try:
        return COMMANDS[argv[0]](argv[1:])
    except Busy as exc:
        print("rest-queue: " + one_line(exc, 400), file=sys.stderr)
        return 4
    except Stop as exc:
        print("rest-queue: " + one_line(exc, 400), file=sys.stderr)   # one reason line, whatever gh printed
        return 3
    except Exception as exc:   # not a wrong call (1, 2): one reason line and 3, never a traceback
        print("rest-queue: unexpected failure — " + one_line(f"{type(exc).__name__}: {exc}", 400), file=sys.stderr)
        return 3


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
