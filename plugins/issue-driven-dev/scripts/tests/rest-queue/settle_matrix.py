#!/usr/bin/env python3
"""settle_matrix.py <rest-queue.py> — every combination of the settle inputs, run for real (#478).

where the working tree is × what is left over × the local default branch against origin × whether the issue's
branch has a commit × whether it has an upstream: 4 × 5 × 2 × 2 × 2 = 160 temporary repositories. Each runs
`rest-queue.py settle`. What the single-issue pipeline really leaves, ending by ending, is endings.py; this file
checks that the same invariants hold over the whole input space:

  exit 3  nothing changed (HEAD, the branch, every branch tip, git status) and one reason line names #5
  exit 0  the working tree is on main, `git status --porcelain` prints nothing, and the run state keeps exactly
          the branches of #5 that still exist

and that the exit code, the commit and the branch are those of EXPECTED, which is written from the requirement
"Between two issues one helper settles the working tree" and does not call or copy the helper.
"""
import concurrent.futures
import hashlib
import itertools
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

RQ = os.path.abspath(sys.argv[1])
ENV = dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1", GIT_TERMINAL_PROMPT="0",
           GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.invalid",
           GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.invalid")
WHERE = {"own": "idd/5-x", "default": "main", "other": "idd/7-y", "detached": "<detached>"}
LEFT = ("none", "plain", "manifest", "attachment", "lock")   # attachment: the manifest and a file it lists
REMOTE = ("behind", "ahead")
WORK = (0, 1)
UPSTREAM = (0, 1)
FOLDER = ".claude/.idd/attachments/issue-5/"


def expected(where, left, remote, work, up):
    """(exit code, settle made a commit on idd/5-x, idd/5-x still exists) — from the spec."""
    if where in ("other", "detached"):              # row 3
        return 3, False, True
    if where == "default":                          # row 2: any leftover stops
        return (3, False, True) if left != "none" else (0, False, bool(work or up))
    if left == "lock":                              # row 1, step 2: a place that is never committed
        return 3, False, True
    fresh = not work and not up
    committed = left == "plain" or (left == "attachment" and not fresh)   # step 1 discards the rest
    return 0, committed, bool(committed or work or up)


def git(cwd, *args, check=True):
    return subprocess.run(["git", "-C", cwd, *args], env=ENV, capture_output=True, text=True, check=check).stdout.strip()


def template(root):
    origin, tree = os.path.join(root, "origin.git"), os.path.join(root, "tree")
    subprocess.run(["git", "init", "-q", "--bare", "-b", "main", origin], env=ENV, check=True)
    subprocess.run(["git", "init", "-q", "-b", "main", tree], env=ENV, check=True)
    with open(os.path.join(tree, ".git", "info", "exclude"), "a") as fh:
        fh.write(".claude/.idd/state/\n")
    with open(os.path.join(tree, "a.txt"), "w") as fh:
        fh.write("a\n")
    git(tree, "add", "a.txt")
    git(tree, "commit", "-q", "-m", "init")
    git(tree, "remote", "add", "origin", origin)
    git(tree, "push", "-q", "-u", "origin", "main")
    return root


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(text)


def snapshot(tree):
    return (git(tree, "rev-parse", "HEAD"), git(tree, "symbolic-ref", "--quiet", "--short", "HEAD", check=False),
            git(tree, "for-each-ref", "--format=%(refname) %(objectname)", "refs/heads/"),
            git(tree, "status", "--porcelain", "--untracked-files=all"))


def one(base, case):
    where, left, remote, work, up = case
    root = tempfile.mkdtemp(prefix="m.", dir=base)
    shutil.copytree(os.path.join(base, "tpl"), root, dirs_exist_ok=True, symlinks=True)
    origin, tree = os.path.join(root, "origin.git"), os.path.join(root, "tree")
    git(tree, "remote", "set-url", "origin", origin)
    git(tree, "branch", "--no-track", "idd/5-x", "origin/main")
    if work:
        git(tree, "checkout", "-q", "idd/5-x")
        write(os.path.join(tree, "w.txt"), "w\n")
        git(tree, "add", "w.txt")
        git(tree, "commit", "-q", "-m", "work")
        git(tree, "checkout", "-q", "main")
    if up:
        git(tree, "push", "-q", "-u", "origin", "idd/5-x")
    if remote == "behind":   # origin gets a commit the working tree lacks
        tree_id = git(origin, "rev-parse", "main^{tree}")
        c = git(origin, "commit-tree", tree_id, "-p", "main", "-m", "remote")
        git(origin, "update-ref", "refs/heads/main", c)
    else:                    # the local default branch gets a commit origin lacks
        write(os.path.join(tree, "c.txt"), "c\n")
        git(tree, "add", "c.txt")
        git(tree, "commit", "-q", "-m", "local")
    if where == "own":
        git(tree, "checkout", "-q", "idd/5-x")
    elif where == "other":
        git(tree, "checkout", "-q", "-b", "idd/7-y", "main")
    elif where == "detached":
        git(tree, "checkout", "-q", "--detach", "main")
    if left == "plain":
        write(os.path.join(tree, "a.txt"), "changed\n")
    elif left == "manifest":
        write(os.path.join(tree, FOLDER + "_manifest.json"), json.dumps({"issue": 5, "files": []}))
    elif left == "attachment":
        write(os.path.join(tree, FOLDER + "spec.docx"), "bytes\n")
        write(os.path.join(tree, FOLDER + "_manifest.json"), json.dumps({"issue": 5, "files": [
            {"filename": "spec.docx", "url": "https://example.invalid/spec.docx", "sha256": hashlib.sha256(b"bytes\n").hexdigest()}]}))
    elif left == "lock":
        write(os.path.join(tree, ".claude/.idd/tree-lock"), "pid\n")
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    write(os.path.join(tree, ".claude/.idd/state/idd-all-rest.json"), json.dumps({
        "version": 2, "repo": "o/r", "path": "PR", "default": "main", "started_at": stamp, "updated_at": stamp, "stop": None,
        "attempts": [{"issue": 5, "outcome": "stopped", "reason": "x", "handed_at": stamp, "recorded_at": stamp,
                      "settled": False}]}))
    before, tip = snapshot(tree), git(tree, "rev-parse", "idd/5-x")
    proc = subprocess.run([sys.executable, RQ, "settle", "--cwd", tree, "--repo", "o/r", "--issue", "5"],
                          env=ENV, capture_output=True, text=True)
    exists = subprocess.run(["git", "-C", tree, "show-ref", "--verify", "--quiet", "refs/heads/idd/5-x"], env=ENV).returncode == 0
    got = (proc.returncode, exists and git(tree, "rev-parse", "idd/5-x") != tip, exists)
    want = expected(*case)
    problems = []
    if got != want:
        problems.append(f"got {got}, want {want}: {proc.stderr.strip()[:160]}")
    if proc.returncode == 0:
        if git(tree, "symbolic-ref", "--quiet", "--short", "HEAD", check=False) != "main":
            problems.append("exit 0 but the working tree is not on main")
        if git(tree, "status", "--porcelain"):
            problems.append("exit 0 but git status --porcelain prints something")
        if remote == "behind" and git(tree, "rev-parse", "HEAD") != git(origin, "rev-parse", "main"):
            problems.append("exit 0, main was behind, and HEAD is not the commit of origin/main")
        if remote == "ahead" and git(tree, "rev-list", "--count", "origin/main..main") != "1":
            problems.append("exit 0 and main lost its own commit")
        with open(os.path.join(tree, ".claude/.idd/state/idd-all-rest.json")) as fh:
            kept = sorted(k["branch"] for k in json.load(fh)["attempts"][0].get("kept", []))
        if kept != (["idd/5-x"] if exists else []):
            problems.append(f"the run state keeps {kept} and idd/5-x {'exists' if exists else 'is gone'}")
    elif proc.returncode == 3:
        if snapshot(tree) != before:
            problems.append("exit 3 but something changed")
        lines = proc.stderr.strip().splitlines()
        if len(lines) != 1 or "#5" not in lines[0]:
            problems.append(f"exit 3 without exactly one reason line that names #5: {proc.stderr.strip()[:200]!r}")
    shutil.rmtree(root, ignore_errors=True)
    return case, problems


def main():
    base = tempfile.mkdtemp(prefix="idd-settle-matrix.")
    try:
        os.mkdir(os.path.join(base, "tpl"))
        template(os.path.join(base, "tpl"))
        cases = list(itertools.product(WHERE, LEFT, REMOTE, WORK, UPSTREAM))
        bad = 0
        with concurrent.futures.ThreadPoolExecutor(max_workers=min(16, os.cpu_count() or 2)) as pool:
            for case, problems in pool.map(lambda c: one(base, c), cases):
                for p in problems:
                    bad += 1
                    print(f"MISMATCH {case}: {p}")
        print(f"settle matrix: {len(cases)} cases, {bad} mismatch(es)")
        return 1 if bad else 0
    finally:
        shutil.rmtree(base, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
