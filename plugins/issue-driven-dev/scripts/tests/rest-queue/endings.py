#!/usr/bin/env python3
"""endings.py <rest-queue.py> <process-attachments.sh> — the Example "endings of the single-issue pipeline" (#478).

One temporary repository (with a bare origin) per row of that table. What `idd-diagnose` leaves is written by
the real writer, `process-attachments.sh download`, with gh and curl replaced on PATH; the line in
routing-stats.jsonl is appended here, because its writer (idd-route) is an external program; the meeting row
repeats the two git commands of the meeting unwind. Each row then runs `rest-queue.py settle` and checks the
result, not the steps:

  exit 0  the working tree is on the default branch and `git status --porcelain` prints nothing (the check
          every issue on the PR path starts with); the branches of #5 are those of the row and the run state
          names exactly them; a path that was left over is either in the commit settle made, byte for byte, or
          it is the manifest or a file the manifest lists with its SHA-256 (nothing else may be discarded); and
          a new run hands #5 out, or records it as existing work, as the row says
  exit 3  HEAD, the branch, every branch tip and the output of git status are unchanged, and there is one
          reason line that names #5

The row names and exit codes are compared with the table in the spec when the spec is on disk.
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

# on: where the working tree is when settle runs · work: the branch has a commit of its own · leave: what the
# ending leaves · exit / branches / committed (the paths of settle's commit, None = no commit) / discarded / later
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
    dict(id="stop-after-diagnose-foreign-file", on="own", leave=["manifest", "foreign"], exit=0, branches=[B],
         committed=[M, FOLDER + "notes.txt"], later="existing"),
    dict(id="meeting", on="main", meeting=True, exit=0, branches=[B], later="existing"),
    dict(id="stop-in-implement", on="own", work=True, leave=["edit", "proposal", "manifest"], exit=0, branches=[B],
         committed=["a.txt", PROPOSAL], discarded=[M], later="existing"),
    dict(id="stop-in-implement-attachments", on="own", work=True, leave=["edit", "attachment"], exit=0, branches=[B],
         committed=["a.txt", M, DOC], later="existing"),
    dict(id="stop-after-verify", on="own", work=True, leave=["manifest", "log"], exit=0, branches=[B],
         committed=[LOG], discarded=[M], later="existing"),
    dict(id="stop-at-close-stage", on="own", work=True, upstream=True, leave=["manifest", "log"], exit=0,
         branches=[B], committed=[LOG], discarded=[M], later="existing"),
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


def stubs(base):
    """gh and curl as process-attachments.sh calls them: an issue with or without one attachment, and its bytes."""
    d = os.path.join(base, "stub")
    os.mkdir(d)
    write(os.path.join(d, "gh"), """#!/usr/bin/env bash
case "${1:-}" in
  issue) case "${GH_STUB_MODE:-empty}" in
           empty)    printf '{"body":"no attachment here","comments":[]}\\n' ;;
           with_url) printf '{"body":"spec: https://github.com/user-attachments/files/123/spec.docx ok","comments":[]}\\n' ;;
         esac ;;
  auth)  echo stub-token ;;
  *)     echo "gh stub: unhandled: $*" >&2; exit 1 ;;
esac
""")
    write(os.path.join(d, "curl"), """#!/usr/bin/env bash
out=""; while [ $# -gt 0 ]; do [ "$1" = "-o" ] && out="$2"; shift; done
[ -n "$out" ] && printf 'attachment bytes\\n' > "$out"
""")
    for name in ("gh", "curl"):
        os.chmod(os.path.join(d, name), 0o755)
    return d


def download(tree, stub, mode, caller):
    """The real writer, run the way idd-diagnose runs it: from the working tree, for issue 5."""
    env = dict(GIT_ENV, PATH=stub + os.pathsep + os.environ["PATH"], GH_STUB_MODE=mode, IDD_CALLER=caller)
    proc = sh(["bash", PA, "download", "5", "--repo", "o/r"], cwd=tree, env=env, check=False)
    if proc.returncode != 0:
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
    return sh([sys.executable, RQ, args[0], "--cwd", tree, "--repo", "o/r", *args[1:]], env=env, check=False)


def left_over(tree):
    out = git(tree, "status", "--porcelain=v1", "-z", "--untracked-files=all")
    return sorted(e[3:] for e in out.split("\0") if len(e) > 3)


def tips(tree):
    return git(tree, "for-each-ref", "--format=%(refname:short) %(objectname)", "refs/heads/")


def branches_of_5(tree):
    return sorted(b for b in git(tree, "for-each-ref", "--format=%(refname:short)", "refs/heads/idd/").split() if re.match(r"^idd/5(-.*)?$", b))


def regenerated(tree, path):
    """True for the manifest, and for a file the manifest lists with the SHA-256 the file has (the spec's rule)."""
    if path == M:
        return True
    try:
        with open(os.path.join(tree, M)) as fh:
            listed = {f.get("filename"): f.get("sha256") for f in json.load(fh)["files"]}
        with open(os.path.join(tree, path), "rb") as fh:
            digest = hashlib.sha256(fh.read()).hexdigest()
    except (OSError, ValueError, KeyError):
        return False
    return path.startswith(FOLDER) and listed.get(path[len(FOLDER):]) == digest


def build(base, stub, row):
    root = tempfile.mkdtemp(prefix=row["id"] + ".", dir=base)
    shutil.copytree(os.path.join(base, "tpl"), root, dirs_exist_ok=True, symlinks=True)
    origin, tree, gh_dir = os.path.join(root, "origin.git"), os.path.join(root, "tree"), os.path.join(root, "gh")
    git(tree, "remote", "set-url", "origin", origin)
    os.mkdir(gh_dir)
    sh([sys.executable, os.path.join(HERE, "scenario.py"), gh_dir, "5"])
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
    write(os.path.join(tree, ".claude/.idd/state/idd-all-rest.json"), json.dumps({
        "version": 2, "repo": "o/r", "path": "PR", "default": "main", "started_at": stamp, "updated_at": stamp,
        "stop": None, "attempts": [{"issue": 5, "outcome": outcome, "reason": "" if outcome == "closed" else "x",
                                    "handed_at": stamp, "recorded_at": stamp, "settled": False}]}))
    if row["on"] == "own" or row.get("meeting"):
        git(tree, "checkout", "-q", "--no-track", "-b", B, "origin/main")   # as Phase 0.5 creates it
    if row.get("work"):
        write(os.path.join(tree, "w.txt"), "w\n")
        if row.get("work_manifest"):   # the run's own commit carried the manifest
            download(tree, stub, "empty", "idd-issue")
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
    if row.get("meeting"):   # the meeting unwind: commit the attachment folder on the branch, return to the default branch
        download(tree, stub, "empty", "idd-diagnose")
        git(tree, "add", "--", FOLDER.rstrip("/"))
        git(tree, "commit", "-q", "-m", "chore: keep the attachments of the meeting issue (#5)")
        git(tree, "checkout", "-q", "main")
    if row["on"] == "wip":
        git(tree, "checkout", "-q", "-b", "wip")
    return root, origin, tree, gh_dir


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
    with open(os.path.join(tree, ".claude/.idd/state/idd-all-rest.json")) as fh:
        attempt = json.load(fh)["attempts"][0]
    kept = attempt.get("kept", [])
    if sorted(k["branch"] for k in kept) != row["branches"]:
        problems.append(f"the run state keeps {[k['branch'] for k in kept]}, want {row['branches']}")
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
    for p in left:
        if p in discarded:
            continue
        held = git(tree, "rev-parse", "-q", "--verify", f"{B}:{p}", check=False).strip() if tip else ""
        if p in blobs and held != blobs[p]:
            problems.append(f"{p} was left over and is not on {B} as it was")
    if set(left) - discarded - set(committed or []):
        problems.append(f"neither kept nor discarded: {sorted(set(left) - discarded - set(committed or []))}")
    later = row["later"]
    if later != "closed":
        rq(tree, gh_dir, "report")
        started = rq(tree, gh_dir, "start", "--path", "PR")
        nxt = rq(tree, gh_dir, "next")
        try:
            answer = json.loads(nxt.stdout)
        except ValueError:
            answer = {}
        if later == "handed" and answer.get("next") != 5:
            problems.append(f"a new run does not hand #5 out: start {started.returncode}, next {nxt.stdout.strip()[:120]!r} {nxt.stderr.strip()[:120]!r}")
        if later == "existing":
            with open(os.path.join(tree, ".claude/.idd/state/idd-all-rest.json")) as fh:
                again = json.load(fh)["attempts"]
            if answer.get("next") is not None or not again or not again[0]["reason"].startswith("existing work: local branch " + B):
                problems.append(f"a new run does not record #5 as existing work: {nxt.stdout.strip()[:120]!r}")
    return problems


def spec_rows():
    """{row id: exit code} of the table in the spec, or None when no spec with that Example is on disk."""
    for path in [os.path.join(ROOT, "openspec/specs/idd-all-rest/spec.md")] + sorted(glob.glob(os.path.join(ROOT, "openspec/changes/*/specs/idd-all-rest/spec.md"))):
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
                rows[m.group(1)] = int(cells[3])
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
        elif table != {r["id"]: r["exit"] for r in ROWS}:
            bad += 1
            print(f"FAIL the rows here and the table in the spec differ: {sorted(set(table) ^ {r['id'] for r in ROWS})}")
        print(f"endings: {len(ROWS)} rows, {bad} failure(s)")
        return 1 if bad else 0
    finally:
        shutil.rmtree(base, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
