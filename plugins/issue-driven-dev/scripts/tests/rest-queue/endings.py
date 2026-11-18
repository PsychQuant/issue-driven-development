#!/usr/bin/env python3
"""endings.py <rest-queue.py> <process-attachments.sh> — the Example "endings of the single-issue pipeline" (#478).

One temporary repository (with a bare origin) per row of that table. What `idd-diagnose` leaves is written by
the real writer, `process-attachments.sh download`, with gh and curl replaced on PATH; the line in
routing-stats.jsonl is appended here, because its writer (idd-route) is an external program; the meeting row
repeats the two git commands of the meeting unwind; a rejecting commit hook and an ignore rule of the issue's own
branch are really installed and committed. GitHub's side of each row (the phase, `### Blocking`, the Diagnosis
type) is what that ending leaves there, so the last column is checked against the class a later run really sees.
Each row then runs `rest-queue.py settle` and checks the result, not the steps:

  exit 0  the working tree is on the default branch and `git status --porcelain` prints nothing (the check
          every issue on the PR path starts with); the branches of #5 are those of the row and the run state
          names exactly them; a path that was left over is either in the commit settle made, byte for byte, or
          it is the manifest or a file the manifest vouches for (nothing else may be discarded); a stash the row
          names can be applied again and gives the file back; and a later run does with #5 what the row says
  exit 3  HEAD, the branch, every branch tip and the output of git status are unchanged, and there is one
          reason line that names #5

A step the report tells a person to take is taken here: a kept branch without an upstream is deleted, and a new
run then hands the issue out. A row whose issue is closed has no later run to look at; there the report is
checked instead.

The row names, the exit codes, the branches afterwards and the later run are compared with the table in the spec
when the spec is on disk (a change that is not archived yet wins over the main spec).
"""
import glob
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

RQ, PA = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", "..", ".."))
GIT_ENV = dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1", GIT_TERMINAL_PROMPT="0",
               GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.invalid",
               GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.invalid")
FOLDER = ".claude/.idd/attachments/issue-5/"
M = FOLDER + "_manifest.json"
DOC = FOLDER + "spec.docx"
LOG = ".claude/.idd/routing-stats.jsonl"
PROPOSAL = "openspec/changes/idd-5-x/proposal.md"
B = "idd/5-x"
STATE = ".claude/.idd/state/idd-all-rest.json"
STASH_MESSAGE = f"idd rest: files of #5 that only {B} ignores"

# on: where the working tree is when settle runs · work: the branch has a commit of its own · leave: what the
# ending leaves · gh: the issue on GitHub after the ending (scenario.py) · exit / branches / committed (the paths
# of settle's commit, None = no commit) / discarded / later (what a later run does with #5)
ROWS = [
    dict(id="closed-before-start", on="main", outcome="closed", exit=0, branches=[], later="closed"),
    dict(id="existing-work", on="main", exit=0, branches=[], later="handed"),
    dict(id="stop-before-download", on="own", exit=0, branches=[], later="handed"),
    dict(id="stop-after-diagnose", on="own", leave=["manifest"], exit=0, branches=[], discarded=[M], later="handed"),
    dict(id="stop-after-diagnose-attachments", on="own", leave=["attachment"], exit=0, branches=[],
         discarded=[M, DOC], later="handed"),
    dict(id="stop-after-diagnose-ignored-attachments", on="own", ignore_files=True, leave=["attachment"], exit=0,
         branches=[], discarded=[M], later="handed"),
    dict(id="stop-after-diagnose-tracked-manifest", on="own", tracked_manifest=True, leave=["manifest"], exit=0,
         branches=[], discarded=[M], later="handed"),
    dict(id="stop-after-diagnose-failed-download", on="own", leave=["failed-download"], exit=0, branches=[],
         discarded=[M, DOC], later="handed"),
    dict(id="stop-after-diagnose-foreign-file", on="own", leave=["manifest", "foreign"], exit=0, branches=[B],
         committed=[M, FOLDER + "notes.txt"], later="existing"),
    dict(id="meeting", on="main", meeting=True, gh="5:diag=meeting", exit=0, branches=[B], later="meeting"),
    dict(id="stop-in-implement", on="own", work=True, leave=["edit", "proposal", "manifest"], exit=0, branches=[B],
         committed=["a.txt", PROPOSAL], discarded=[M], later="existing"),
    dict(id="stop-in-implement-attachments", on="own", work=True, leave=["edit", "attachment"], exit=0, branches=[B],
         committed=["a.txt", M, DOC], later="existing"),
    dict(id="stop-in-implement-hooks-reject", on="own", work=True, leave=["edit", "rejecting-hook"], exit=0,
         branches=[B], committed=["a.txt"], no_hooks=True, later="existing"),
    dict(id="stop-in-implement-ignored-files", on="own", work=True, work_ignore=True, leave=["ignored"], exit=0,
         branches=[B], stash=["coverage/"], later="existing"),
    dict(id="stop-after-verify-failed", on="own", work=True, leave=["manifest", "log"], gh="5:blocking=verify findings",
         exit=0, branches=[B], committed=[LOG], discarded=[M], later="blocked"),
    dict(id="stop-at-close-stage", on="own", work=True, upstream=True, leave=["manifest", "log"],
         gh="5:html=body-verified", exit=0, branches=[B], committed=[LOG], discarded=[M], later="verified"),
    dict(id="merged-and-closed", on="own", work=True, work_manifest=True, upstream=True, squash=True,
         outcome="closed", leave=["manifest", "log"], exit=0, branches=[B], committed=[LOG], discarded=[M],
         later="closed"),
    dict(id="on-another-branch", on="wip", exit=3),
    dict(id="leftover-on-default", on="main", leave=["b"], exit=3),
    dict(id="never-committed-place", on="own", work=True, leave=["lock", "edit"], exit=3),
]


def sh(args, cwd=None, env=None, check=True):
    return subprocess.run(args, cwd=cwd, env=env or GIT_ENV, capture_output=True, text=True, check=check)


def git(cwd, *args, check=True):
    return sh(["git", "-C", cwd, *args], check=check).stdout


def write(path, text, mode="w"):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, mode) as fh:
        fh.write(text)


def executable(path, text):
    write(path, text)
    os.chmod(path, 0o755)


def stubs(base):
    """gh and curl as process-attachments.sh calls them: an issue with or without one attachment, and its bytes;
    with CURL_STUB_MODE=fail the download breaks off after part of the file arrived."""
    d = os.path.join(base, "stub")
    os.mkdir(d)
    executable(os.path.join(d, "gh"), """#!/usr/bin/env bash
case "${1:-}" in
  issue) case "${GH_STUB_MODE:-empty}" in
           empty)    printf '{"body":"no attachment here","comments":[]}\\n' ;;
           with_url) printf '{"body":"spec: https://github.com/user-attachments/files/123/spec.docx ok","comments":[]}\\n' ;;
         esac ;;
  auth)  echo stub-token ;;
  *)     echo "gh stub: unhandled: $*" >&2; exit 1 ;;
esac
""")
    executable(os.path.join(d, "curl"), """#!/usr/bin/env bash
out=""; while [ $# -gt 0 ]; do [ "$1" = "-o" ] && out="$2"; shift; done
if [ "${CURL_STUB_MODE:-ok}" = fail ]; then [ -n "$out" ] && printf 'attach' > "$out"; exit 18; fi
[ -n "$out" ] && printf 'attachment bytes\\n' > "$out"
""")
    return d


def download(tree, stub, mode, caller, curl="ok"):
    """The real writer, run from the working tree, for issue 5."""
    env = dict(GIT_ENV, PATH=stub + os.pathsep + os.environ["PATH"], GH_STUB_MODE=mode, CURL_STUB_MODE=curl)
    env["IDD_CALLER"] = caller   # recorded in the manifest as fetched_by
    proc = sh(["bash", PA, "download", "5", "--repo", "o/r"], cwd=tree, env=env, check=False)
    if proc.returncode != 0 and curl == "ok":   # with a broken download the writer itself reports the failure
        raise RuntimeError(f"process-attachments.sh download failed: {proc.stderr.strip()[:300]}")


def template(base):
    origin, tree = os.path.join(base, "tpl", "origin.git"), os.path.join(base, "tpl", "tree")
    os.makedirs(os.path.dirname(origin))
    sh(["git", "init", "-q", "--bare", "-b", "main", origin])
    sh(["git", "init", "-q", "-b", "main", tree])
    write(os.path.join(tree, ".git", "info", "exclude"), ".claude/.idd/state/\n", "a")
    write(os.path.join(tree, "a.txt"), "a\n")
    write(os.path.join(tree, LOG), '{"issue": 1}\n')
    git(tree, "add", "-A")
    git(tree, "commit", "-q", "-m", "init")
    git(tree, "remote", "add", "origin", origin)
    git(tree, "push", "-q", "-u", "origin", "main")


def rq(tree, gh_dir, *args):
    env = dict(GIT_ENV, IDD_GH=os.path.join(HERE, "fake-gh.py"), FAKE_GH_DIR=gh_dir, IDD_CLOSE_STAGE_TEST="1")
    scoped = [] if args[0] == "list" else ["--cwd", tree]
    return sh([sys.executable, RQ, args[0], *scoped, "--repo", "o/r", *args[1:]], env=env, check=False)


def state_of(tree):
    with open(os.path.join(tree, STATE)) as fh:
        return json.load(fh)


def answer(proc):
    try:
        return json.loads(proc.stdout)
    except ValueError:
        return {}


def left_over(tree):
    out = git(tree, "status", "--porcelain=v1", "-z", "--untracked-files=all")
    return sorted(e[3:] for e in out.split("\0") if len(e) > 3)


def tips(tree):
    return git(tree, "for-each-ref", "--format=%(refname:short) %(objectname)", "refs/heads/")


def branches_of_5(tree):
    return sorted(b for b in git(tree, "for-each-ref", "--format=%(refname:short)", "refs/heads/idd/").split() if re.match(r"^idd/5(-.*)?$", b))


def regenerated(tree, path):
    """True for the manifest, and for a file the manifest vouches for: it lists the file with the SHA-256 the
    file has, or as a download that failed (the spec's rule)."""
    if path == M:
        return True
    try:
        with open(os.path.join(tree, M)) as fh:
            listed = {f.get("filename"): f for f in json.load(fh)["files"]}
        with open(os.path.join(tree, path), "rb") as fh:
            digest = hashlib.sha256(fh.read()).hexdigest()
    except (OSError, ValueError, KeyError):
        return False
    row = listed.get(path[len(FOLDER):]) if path.startswith(FOLDER) else None
    return bool(row) and (row.get("sha256") == digest or bool(row.get("error")))


def build(base, stub, row):
    root = tempfile.mkdtemp(prefix=row["id"] + ".", dir=base)
    shutil.copytree(os.path.join(base, "tpl"), root, dirs_exist_ok=True, symlinks=True)
    origin, tree, gh_dir = os.path.join(root, "origin.git"), os.path.join(root, "tree"), os.path.join(root, "gh")
    git(tree, "remote", "set-url", "origin", origin)
    os.mkdir(gh_dir)
    sh([sys.executable, os.path.join(HERE, "scenario.py"), gh_dir, row.get("gh", "5")])
    if row.get("ignore_files"):   # the documented rule: the downloaded files are ignored, the manifest is not
        write(os.path.join(tree, ".gitignore"), ".claude/.idd/attachments/*/*\n!.claude/.idd/attachments/*/_manifest.json\n")
        git(tree, "add", ".gitignore")
    if row.get("tracked_manifest"):   # an earlier run committed the manifest on the default branch
        download(tree, stub, "empty", "idd-issue")
        git(tree, "add", M)
    if row.get("ignore_files") or row.get("tracked_manifest"):
        git(tree, "commit", "-q", "-m", "earlier")
        git(tree, "push", "-q", "origin", "main")
    outcome = row.get("outcome", "stopped")
    if outcome == "closed":
        write(os.path.join(gh_dir, "state-5"), "CLOSED\n")
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    write(os.path.join(tree, STATE), json.dumps({
        "version": 3, "repo": "o/r", "path": "PR", "default": "main", "review": False, "started_at": stamp,
        "updated_at": stamp, "stop": None,
        "attempts": [{"issue": 5, "outcome": outcome, "reason": "" if outcome == "closed" else "x",
                      "handed_at": stamp, "recorded_at": stamp, "settled": False}]}))
    if row["on"] == "own" or row.get("meeting"):
        git(tree, "checkout", "-q", "--no-track", "-b", B, "origin/main")   # as Phase 0.5 creates it
    if row.get("work"):
        write(os.path.join(tree, "w.txt"), "w\n")
        if row.get("work_manifest"):   # the run's own commit carried the manifest
            download(tree, stub, "empty", "idd-issue")
        if row.get("work_ignore"):     # a commit of the issue adds an ignore rule the default branch lacks
            write(os.path.join(tree, ".gitignore"), "coverage/\n")
        git(tree, "add", "-A")
        git(tree, "commit", "-q", "-m", "work of #5 (#5)")
    if row.get("upstream"):
        git(tree, "push", "-q", "-u", "origin", B)
    if row.get("squash"):   # GitHub squash-merged the pull request: origin/main gets one new commit
        c = git(origin, "commit-tree", git(origin, "rev-parse", B + "^{tree}").strip(), "-p", "main", "-m", "squash (#5)").strip()
        git(origin, "update-ref", "refs/heads/main", c)
    for kind in row.get("leave", []):
        if kind == "manifest":
            download(tree, stub, "empty", "idd-diagnose")
        elif kind == "attachment":
            download(tree, stub, "with_url", "idd-diagnose")
        elif kind == "failed-download":
            download(tree, stub, "with_url", "idd-diagnose", curl="fail")
        elif kind == "foreign":
            write(os.path.join(tree, FOLDER, "notes.txt"), "a person's notes\n")
        elif kind == "edit":
            write(os.path.join(tree, "a.txt"), "changed\n")
        elif kind == "proposal":
            write(os.path.join(tree, PROPOSAL), "## Why\n")
        elif kind == "log":
            write(os.path.join(tree, LOG), '{"issue": 5}\n', "a")
        elif kind == "b":
            write(os.path.join(tree, "b.txt"), "b\n")
        elif kind == "lock":
            write(os.path.join(tree, ".claude/.idd/tree-lock"), "pid\n")
        elif kind == "rejecting-hook":   # a lint hook: it rejects what the run left
            executable(os.path.join(tree, ".git", "hooks", "pre-commit"), "#!/bin/sh\necho 'lint: a.txt fails' >&2\nexit 1\n")
        elif kind == "ignored":          # written by the run, ignored by the rule the issue's commit added
            write(os.path.join(tree, "coverage", "report.txt"), "the report\n")
    if row.get("meeting"):   # the meeting unwind: commit the attachment folder on the branch, return to the default branch
        download(tree, stub, "empty", "idd-diagnose")
        git(tree, "add", "--", FOLDER.rstrip("/"))
        git(tree, "commit", "-q", "-m", "chore: keep the attachments of the meeting issue (#5)")
        git(tree, "checkout", "-q", "main")
    if row["on"] == "wip":
        git(tree, "checkout", "-q", "-b", "wip")
    return root, origin, tree, gh_dir


def later_run(tree, gh_dir, row, problems):
    """What a later run does with #5: the last column of the table."""
    later = row["later"]
    started = rq(tree, gh_dir, "start", "--path", "PR", "--review", "no")
    if started.returncode != 0:
        problems.append(f"a new run does not start after settle: {started.stderr.strip()[:200]}")
        return
    nxt = answer(rq(tree, gh_dir, "next"))
    attempts = state_of(tree)["attempts"]
    if later == "handed":
        if nxt.get("next") != 5:
            problems.append(f"a later run does not hand #5 out: {nxt}")
    elif later == "existing":
        if nxt.get("next") is not None or not attempts or not attempts[0]["reason"].startswith("existing work: local branch " + B):
            problems.append(f"a later run does not record #5 as existing work: {nxt} {attempts[:1]}")
    else:   # no longer a candidate: listed under its class, not handed out, not recorded
        classes = answer(rq(tree, gh_dir, "list", "--json")).get("classes", {})
        if 5 not in classes.get(later, []):
            problems.append(f"#5 is not in the class {later} for a later run: {classes}")
        if nxt.get("next") is not None or attempts:
            problems.append(f"a later run hands out or records #5 although it is {later}: {nxt} {attempts[:1]}")
    rq(tree, gh_dir, "report")


def check(base, stub, row):
    problems = []
    root, origin, tree, gh_dir = build(base, stub, row)
    before = dict(head=git(tree, "rev-parse", "HEAD"), on=git(tree, "symbolic-ref", "--short", "HEAD"),
                  status=git(tree, "status", "--porcelain", "--untracked-files=all"), tips=tips(tree))
    left = left_over(tree)
    blobs = {p: git(tree, "hash-object", "--", p).strip() for p in left if os.path.isfile(os.path.join(tree, p))}
    may_go = {p for p in left if regenerated(tree, p)}
    tip_before = git(tree, "rev-parse", "-q", "--verify", "refs/heads/" + B, check=False).strip()
    proc = rq(tree, gh_dir, "settle", "--issue", "5")
    if proc.returncode != row["exit"]:
        problems.append(f"exit {proc.returncode}, want {row['exit']}: {proc.stderr.strip()[:200]}")
        return problems
    if row["exit"] == 3:
        after = dict(head=git(tree, "rev-parse", "HEAD"), on=git(tree, "symbolic-ref", "--short", "HEAD"),
                     status=git(tree, "status", "--porcelain", "--untracked-files=all"), tips=tips(tree))
        if after != before:
            problems.append("exit 3 but something changed")
        lines = proc.stderr.strip().splitlines()
        if len(lines) != 1 or "#5" not in lines[0]:
            problems.append(f"exit 3 without exactly one reason line that names #5: {proc.stderr.strip()[:200]!r}")
        return problems
    if git(tree, "symbolic-ref", "--short", "HEAD").strip() != "main":
        problems.append("the working tree is not on the default branch")
    if git(tree, "status", "--porcelain"):   # the literal check of Phase 0.5
        problems.append("git status --porcelain prints something: the next issue would stop")
    if branches_of_5(tree) != row["branches"]:
        problems.append(f"branches of #5: {branches_of_5(tree)}, want {row['branches']}")
    attempt = state_of(tree)["attempts"][0]
    kept = attempt.get("kept", [])
    if sorted(k["branch"] for k in kept) != row["branches"]:
        problems.append(f"the run state keeps {[k['branch'] for k in kept]}, want {row['branches']}")
    if kept and kept[0].get("upstream") is not bool(row.get("upstream")):
        problems.append(f"the run state says upstream {kept[0].get('upstream')!r}, the branch has {'one' if row.get('upstream') else 'none'}")
    discarded = set(row.get("discarded", []))
    if not discarded <= set(left):
        problems.append(f"fixture: {sorted(discarded - set(left))} was not left over")
    if not discarded <= may_go:
        problems.append(f"the row discards something the manifest does not vouch for: {sorted(discarded - may_go)}")
    committed = row.get("committed")
    tip = git(tree, "rev-parse", "-q", "--verify", "refs/heads/" + B, check=False).strip()
    if committed is None:
        if tip and tip != tip_before:
            problems.append("settle made a commit and the row has none")
        if any(k.get("commit") for k in kept):
            problems.append("the run state names a commit and the row has none")
    else:
        names = sorted(git(tree, "show", "--name-only", "--format=", B).split("\n")[:-1]) if tip else []
        if names != sorted(committed):
            problems.append(f"the commit holds {names}, want {sorted(committed)}")
        if not kept or kept[0].get("commit") != tip or sorted(kept[0].get("paths", [])) != sorted(committed):
            problems.append(f"the run state does not record the commit and its paths: {kept}")
        body = git(tree, "log", "-1", "--format=%b", B) if tip else ""
        skipped = "hooks" in body and "skipped" in body
        if bool(row.get("no_hooks")) is not skipped or bool(row.get("no_hooks")) is not (bool(kept) and kept[0].get("hooks") == "skipped"):
            problems.append(f"hooks skipped: the commit message says {skipped}, the run state {kept[0].get('hooks') if kept else None!r}, the row {bool(row.get('no_hooks'))}")
    for p in left:
        if p in discarded:
            continue
        held = git(tree, "rev-parse", "-q", "--verify", f"{B}:{p}", check=False).strip() if tip else ""
        if p in blobs and held != blobs[p]:
            problems.append(f"{p} was left over and is not on {B} as it was")
    if set(left) - discarded - set(committed or []):
        problems.append(f"neither kept nor discarded: {sorted(set(left) - discarded - set(committed or []))}")
    stash = attempt.get("stash")
    if row.get("stash"):
        listed = git(tree, "stash", "list", "--format=%H %gs")
        if not stash or stash.get("paths") != row["stash"] or stash.get("commit", "?") not in listed or STASH_MESSAGE not in listed:
            problems.append(f"the stash is not recorded with its commit and paths: state {stash}, stash list {listed.strip()[:160]!r}")
    elif stash or git(tree, "stash", "list"):
        problems.append(f"a stash was made and the row has none: {stash}")
    report = rq(tree, gh_dir, "report").stdout
    if row["later"] == "closed":   # no later run hands a closed issue out: what the report says about it is what is left to check
        lines = [ln for ln in report.splitlines() if B in ln]
        if committed is None and lines:
            problems.append(f"the report names a branch of the closed issue: {lines[0][:160]}")
        if committed is not None and not any(tip[:7] in ln and all(p in ln for p in committed) for ln in lines):
            problems.append(f"the report does not name {B}, the commit and its paths under the closed issue: {lines[:1]}")
    else:
        if row.get("no_hooks") and "without the repository's commit hooks" not in report:
            problems.append("the report does not say that the commit was made without the commit hooks")
        advice = "deleting it lets a later rest run start the issue over" in report
        want_advice = bool(row["branches"]) and not row.get("upstream")
        if advice is not want_advice:
            problems.append(f"the report {'gives' if advice else 'does not give'} the delete-the-branch step; the row {'has a kept branch without an upstream' if want_advice else 'has none'}")
        later_run(tree, gh_dir, row, problems)
        if want_advice and row["later"] == "existing":   # the step the report gives, taken: the issue is then handed out
            git(tree, "branch", "-D", B)
            again = dict(row, later="handed")
            later_run(tree, gh_dir, again, problems)
    if row.get("stash") and stash:   # the other step the report gives: the stash applied on that branch gives the file back
        if f"git stash apply {stash['commit']}" not in report:
            problems.append("the report does not say how to get the stashed files back")
        if not branches_of_5(tree):
            git(tree, "branch", B, tip)   # deleted above to take the report's first step; the stash is applied where the report says
        git(tree, "checkout", "-q", B)
        applied = sh(["git", "-C", tree, "stash", "apply", "-q", stash["commit"]], check=False)
        path = os.path.join(tree, "coverage", "report.txt")
        if applied.returncode != 0 or not os.path.isfile(path) or open(path).read() != "the report\n":
            problems.append(f"the stash does not give coverage/report.txt back: {applied.stderr.strip()[:160]}")
    return problems


BRANCH_CELL = {"none": [], "unchanged": None}   # cells that begin with `idd/5-x` keep that branch
LATER_CELL = {"handed out": "handed", "existing work": "existing", "#5 is closed": "closed", "—": None,
              "not run: verified": "verified", "not run: blocked": "blocked", "not run: meeting": "meeting"}


def spec_rows():
    """{row id: (exit code, branches afterwards, later run)} of the table in the spec, or None when no spec
    with that Example is on disk."""
    for path in sorted(glob.glob(os.path.join(ROOT, "openspec/changes/*/specs/idd-all-rest/spec.md"))) + [os.path.join(ROOT, "openspec/specs/idd-all-rest/spec.md")]:
        try:
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
        except OSError:
            continue
        if "##### Example: endings of the single-issue pipeline" not in text:
            continue
        part = text.split("##### Example: endings of the single-issue pipeline", 1)[1].split("\n#####", 1)[0]
        rows = {}
        for line in part.splitlines():
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            m = re.match(r"^`([a-z-]+)`:", cells[0]) if len(cells) == 6 else None
            if m:
                kept = [B] if cells[4].startswith(f"`{B}`") else BRANCH_CELL.get(cells[4].split(",")[0].strip(), "?")
                rows[m.group(1)] = (int(cells[3]), kept, LATER_CELL.get(cells[5], "?"))
        return rows
    return None


def main():
    base = tempfile.mkdtemp(prefix="idd-endings.")
    bad = 0
    try:
        template(base)
        stub = stubs(base)
        for row in ROWS:
            try:
                problems = check(base, stub, row)
            except Exception as exc:   # a fixture that cannot be built is a failure of that row
                problems = [f"{type(exc).__name__}: {str(exc)[:300]}"]
            for p in problems:
                bad += 1
                print(f"FAIL {row['id']}: {p}")
        table = spec_rows()
        if table is None:
            print("endings: no spec with the table on disk; the row names were not compared")
        else:
            here = {r["id"]: (r["exit"], r.get("branches"), r.get("later")) for r in ROWS}
            for name in sorted(set(table) | set(here)):
                if table.get(name) != here.get(name):
                    bad += 1
                    print(f"FAIL {name}: the table in the spec says {table.get(name)}, the row here {here.get(name)}")
        print(f"endings: {len(ROWS)} rows, {bad} failure(s)")
        return 1 if bad else 0
    finally:
        shutil.rmtree(base, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
