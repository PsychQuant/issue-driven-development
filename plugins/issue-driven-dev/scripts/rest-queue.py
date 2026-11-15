#!/usr/bin/env python3
"""rest-queue.py — which open issue /idd-all runs next when no issue was named (#478).

  rest-queue.py args   -- <the arguments /idd-all was called with>
  rest-queue.py list   --repo O/R [--json]
  rest-queue.py start  --cwd C --repo O/R
  rest-queue.py next   --cwd C --repo O/R
  rest-queue.py record --cwd C --repo O/R --issue N [--reason TEXT]
  rest-queue.py stop   --cwd C [--repo O/R] --reason TEXT
  rest-queue.py report --cwd C --repo O/R

args    classifies the invocation: {"mode": "rest" | "other" | "refuse"[, "reason"]}.
list    reads every open issue and prints its class and the run order. Read-only, no run.
start   begins a run, or resumes one whose last activity is less than 24 hours old, and prints the list.
next    re-reads the open issues and hands out the first one this run has not handed out yet.
record  writes the outcome of the issue in flight: closed when GitHub says the issue is closed, stopped otherwise.
stop    marks the whole run as stopped; next hands out nothing afterwards.
report  prints what the run did and deletes its state.

Every open issue falls into exactly one class, by TABLE (first match wins). Only candidates are run:
those with a Diagnosis first, then the others, each by ascending issue number.

The judgements are not made here: open clarity rows come from lib/intent.py, the gate group and the
Diagnosis type from lib/actionability.sh, write access and the trusted Diagnosis from lib/ghread.py.

The open issues are read completely or not at all: one failed page, one missing field or one helper
that reports misuse ends the command without a list.

Run state: <cwd>/.claude/.idd/state/idd-all-rest.json.

Exit: 0 done · 1 refused (args says refuse; no run; not the issue in flight) · 2 usage · 3 GitHub or a helper could not be read
"""

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
                    now, run_cmd, ts)

REPO_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
STATE_TTL = 24 * 3600   # the same life as the close stage's run state and the unattended marker
STATE_NAME = "idd-all-rest.json"
PAGE = 50
REASON_MAX = 300
FLAGS = ("--pr", "--no-pr", "--review", "--in-chain")
TRACKER_LABELS = {"north-star", "epic"}
PARKING_LABEL = "parking-lot"
GROUPS = ("actionable", "parked", "blocked", "undiagnosed")

# The decision table: ordered, the first rule whose test holds decides the class.
TABLE = (
    ("author", lambda f: not (f["author_writes"] and f["editor_writes"])),
    ("tracker", lambda f: f["tracker"]),
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
    "parked": "parked",
    "meeting": "meeting",
    "tracker": "tracker",
    "author": "opened or edited by an account without write access",
}


# ── the two tables ─────────────────────────────────────────────────────────

def classify(facts):
    """The class of an issue, from: author_writes, editor_writes, tracker, open_clarity, group, meeting, verified."""
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
        else:
            positionals.append(arg)
        i += 1
    if len(positionals) >= 2 and "rest" in positionals:
        return "refuse", "`rest` runs every remaining issue and cannot be combined with an issue, a description or a file"
    if not positionals or positionals == ["rest"]:
        if in_chain:
            return "refuse", "--in-chain is for a call that names an issue"
        return "rest", ""
    return "other", ""


# ── reading GitHub ─────────────────────────────────────────────────────────

QUERY = ("query($o:String!,$r:String!,$c:String){repository(owner:$o,name:$r){"
         "issues(states:OPEN,first:%d,after:$c,orderBy:{field:CREATED_AT,direction:ASC}){"
         "pageInfo{hasNextPage endCursor} nodes{number author{login} editor{login} "
         "labels(first:100){totalCount nodes{name}} body bodyHTML "
         "comments(last:100){totalCount nodes{authorAssociation body}}}}}}" % PAGE)


def lacks(what):
    return Stop(f"could not read the open issues: {what}")


def checked(node):
    """The issue node, after checking every field the classification reads."""
    try:
        ok = (isinstance(node["number"], int) and not isinstance(node["number"], bool)
              and all(node[k] is None or isinstance(node[k]["login"], str) for k in ("author", "editor"))
              and isinstance(node["body"], str) and isinstance(node["bodyHTML"], str)
              and isinstance(node["labels"]["totalCount"], int)
              and all(isinstance(l["name"], str) for l in node["labels"]["nodes"])
              and isinstance(node["comments"]["totalCount"], int)
              and all(isinstance(c["authorAssociation"], str) and isinstance(c["body"], str)
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


def gate_groups(repo, nodes):
    """{issue number: (gate group, Diagnosis type)}, from lib/actionability.sh."""
    if not nodes:
        return {}
    work = tempfile.mkdtemp(prefix="idd-rest-queue-")
    try:
        for node in nodes:
            comments = [{"assoc": c["authorAssociation"], "body": c["body"]} for c in node["comments"]["nodes"]]
            if node["comments"]["totalCount"] > len(comments):
                # the query returned only the newest ones; the Diagnosis the run routes on may be older
                comments = issue_comments(repo, node["number"])
            d = os.path.join(work, str(node["number"]))
            os.mkdir(d)
            put(os.path.join(d, "body"), node["body"])
            put(os.path.join(d, "diag"), latest_diagnosis(comments))
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
    groups = gate_groups(repo, nodes)
    out = []
    for node in nodes:
        number = node["number"]
        try:
            root = html_root(node["bodyHTML"], node["body"])
            rows = intent.open_clarity_rows({"body_html": node["bodyHTML"], "body": node["body"]})
        except Stop:
            raise Stop(f"could not read GitHub's rendering of issue #{number}")
        group, dtype = groups[number]
        author = (node["author"] or {}).get("login")
        facts = {
            "author_writes": writes(repo, author),
            "editor_writes": node["editor"] is None or writes(repo, node["editor"]["login"]),
            "tracker": any(l["name"].lower() in TRACKER_LABELS for l in node["labels"]["nodes"]),
            "open_clarity": bool(rows),
            "group": group,
            "meeting": dtype == "meeting",
            "verified": phase_of(root) == "verified",
        }
        out.append({"number": number, "class": classify(facts), "group": group, "questions": rows})
    return out


def listing(repo):
    issues = read_classes(repo)
    classes = {name: sorted(i["number"] for i in issues if i["class"] == name) for name in CLASSES}
    candidates = [i for i in issues if i["class"] == "candidate"]
    diagnosed = sorted(i["number"] for i in candidates if i["group"] == "actionable")
    others = sorted(i["number"] for i in candidates if i["group"] != "actionable")
    return {"repo": repo, "open": len(issues), "classes": classes, "order": diagnosed + others, "diagnosed": diagnosed,
            "questions": {str(i["number"]): [one_line(q, REASON_MAX) for q in i["questions"]]
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


def load_state(cwd, repo=None):
    """The run state of this working tree, or None when there is none this helper can use."""
    path = state_path(cwd)
    try:
        with open(path, encoding="utf-8") as fh:
            st = json.load(fh)
    except (OSError, ValueError):
        return None
    try:
        ok = (st["version"] == 1 and isinstance(st["repo"], str) and (repo is None or st["repo"] == repo)
              and isinstance(st["started_at"], str) and isinstance(st["updated_at"], str)
              and isinstance(st["attempts"], list)
              and all(isinstance(a["issue"], int) and a["outcome"] in (None, "closed", "stopped") for a in st["attempts"])
              and (st["stop"] is None or isinstance(st["stop"]["reason"], str)))
    except (KeyError, TypeError):
        ok = False
    return st if ok else None


def save_state(cwd, st):
    path = state_path(cwd)
    os.makedirs(os.path.dirname(path), mode=0o700, exist_ok=True)
    st["updated_at"] = iso(now())
    fd, tmp = tempfile.mkstemp(prefix=STATE_NAME + ".", dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(st, fh)
        os.replace(tmp, path)
    except OSError as exc:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise Stop(f"could not write the run state: {exc.strerror or exc}")


def in_flight(st):
    return next((a for a in st["attempts"] if a["outcome"] is None), None)


# ── output ─────────────────────────────────────────────────────────────────

def one_line(text, limit):
    text = " ".join("".join(ch if ch.isprintable() else " " for ch in str(text)).split())
    return text if len(text) <= limit else text[:limit - 1] + "…"


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


def list_lines(lst, attempted=()):
    todo = [n for n in lst["order"] if n not in attempted]
    diagnosed = sum(1 for n in todo if n in lst["diagnosed"])
    lines = [f"open issues: {lst['open']}",
             f"to run ({len(todo)}): {nums(todo)}",
             f"  diagnosed {diagnosed}, not diagnosed {len(todo) - diagnosed}"]
    if attempted:
        lines.append(f"already attempted in this run ({len(attempted)}): {nums(sorted(attempted))}")
    for name in ("needs-person", "blocked", "verified", "parked", "meeting", "tracker", "author"):
        lines.append(f"{LABELS[name]} ({len(lst['classes'][name])}): {nums(lst['classes'][name])}")
    return lines


# ── commands ───────────────────────────────────────────────────────────────

def parse(argv, valued, switches=()):
    """{flag: value} for the flags in `valued`, True for those in `switches`; None on a malformed command line."""
    out, i = {}, 0
    while i < len(argv):
        flag = argv[i]
        if flag in switches and flag not in out:
            out[flag] = True
            i += 1
        elif flag in valued and flag not in out and i + 1 < len(argv) and argv[i + 1] != "":
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
    if "--repo" in a and not REPO_RE.match(a["--repo"]):
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
    a = common(argv, {"--cwd", "--repo"}, ["--cwd", "--repo"])
    if a is None:
        return usage("start --cwd C --repo O/R")
    cwd, repo = a["--cwd"], a["--repo"]
    st = load_state(cwd, repo)
    resumed = st is not None and now() - ts(st["updated_at"]) < STATE_TTL
    lst = listing(repo)   # before anything is written: a failed read leaves no run behind
    if not resumed:
        st = {"version": 1, "repo": repo, "started_at": iso(now()), "updated_at": "", "attempts": [], "stop": None}
        save_state(cwd, st)
    attempted = [x["issue"] for x in st["attempts"]]
    head = f"rest run for {repo} — "
    head += (f"resumed (started {st['started_at']}, {len(attempted)} attempt(s) so far)" if resumed
             else f"new (started {st['started_at']})")
    print(head)
    if st["stop"]:
        print(f"this run stopped earlier: {st['stop']['reason']} — next hands out nothing; call report to end it")
    flight = in_flight(st)
    if flight:
        print(f"in flight, no result recorded yet: #{flight['issue']}")
    print("\n".join(list_lines(lst, attempted)))
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
        return emit({"next": None, "stopped": st["stop"]["reason"]})
    flight = in_flight(st)
    if flight:
        print(f"→ #{flight['issue']} is still in flight: finish it and call record", file=sys.stderr)
        return emit({"next": flight["issue"], "in_flight": True})
    attempted = {x["issue"] for x in st["attempts"]}
    todo = [n for n in listing(repo)["order"] if n not in attempted]
    if not todo:
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
    save_state(cwd, st)
    return emit({"issue": n, "outcome": flight["outcome"], "reason": flight["reason"]})


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
    return emit({"stopped": st["stop"]["reason"]})


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
    except Stop as exc:
        lst, unread = None, str(exc)
    closed = [x for x in st["attempts"] if x["outcome"] == "closed"]
    stopped = [x for x in st["attempts"] if x["outcome"] == "stopped"]
    flight = [x for x in st["attempts"] if x["outcome"] is None]
    out = [f"rest run report — {repo}",
           f"started {st['started_at']}, {len(st['attempts'])} issue(s) attempted",
           f"closed ({len(closed)}): {nums(x['issue'] for x in closed)}",
           f"stopped ({len(stopped)}):" + ("" if stopped else " -")]
    out += [f"  #{x['issue']} — {x['reason']}" for x in stopped]
    if flight:
        out.append(f"handed out, no result recorded ({len(flight)}): {nums(x['issue'] for x in flight)}")
    if lst is None:
        out.append(f"the open issues could not be read, so the issues that were not run are not listed: {one_line(unread, REASON_MAX)}")
    else:
        waiting = lst["classes"]["needs-person"]
        out.append(f"{LABELS['needs-person']} ({len(waiting)}):" + ("" if waiting else " -"))
        for n in waiting:
            out.append(f"  #{n}")
            out += [f"    - {q}" for q in lst["questions"].get(str(n), [])]
        for name in ("blocked", "verified", "parked", "meeting", "tracker", "author"):
            out.append(f"not run — {LABELS[name]} ({len(lst['classes'][name])}): {nums(lst['classes'][name])}")
        attempted = {x["issue"] for x in st["attempts"]}
        left = [n for n in lst["order"] if n not in attempted]
        if left:
            out.append(f"still to run ({len(left)}): {nums(left)}")
    if st["stop"]:
        out.append(f"run stopped: {st['stop']['reason']}")
    print("\n".join(out))
    try:
        os.unlink(state_path(cwd))
    except OSError as exc:
        raise Stop(f"the report is printed, but the run state could not be deleted: {exc.strerror or exc}")
    return 0


COMMANDS = {"args": cmd_args, "list": cmd_list, "start": cmd_start, "next": cmd_next,
            "record": cmd_record, "stop": cmd_stop, "report": cmd_report}


def main(argv):
    if not argv or argv[0] not in COMMANDS:
        return usage("unknown or missing subcommand")
    try:
        return COMMANDS[argv[0]](argv[1:])
    except Stop as exc:
        print(f"rest-queue: {exc}", file=sys.stderr)
        return 3


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
