#!/usr/bin/env python3
"""settle_matrix.py <rest-queue.py> — every combination of the settle inputs, run for real (#478).

path × where the working tree is × what is left over × the local default branch against origin × whether the
issue's branch has a commit: 2 × 4 × 4 × 3 × 2 = 192 temporary repositories. Each runs `rest-queue.py settle`
and is compared with EXPECTED below, which is written from the requirement "Between two issues one helper
settles the working tree" and does not call or copy the helper. Prints one line per mismatch and a count.
"""
import concurrent.futures
import itertools
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time

RQ = sys.argv[1]
ENV = dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1", GIT_TERMINAL_PROMPT="0",
           GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.invalid",
           GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.invalid")
PATHS = ("PR", "direct-commit")
WHERE = {"own": "idd/5-x", "default": "main", "other": "idd/7-y", "detached": "<detached>"}
LEFT = ("none", "plain", "manifest", "keep-out")
REMOTE = ("even", "behind", "ahead")
WORK = (0, 1)


def expected(path, where, left, remote, work):
    """(exit code, settle made a commit on idd/5-x, branch at the end, idd/5-x still exists) — from the spec."""
    stay = WHERE[where]
    if path == "direct-commit":
        if where != "default" or left != "none":   # row 4: on the default branch and clean, or exit 3
            return 3, False, stay, True
        if remote == "ahead":                       # after the table: unpushed commits on the default branch
            return 3, False, "main", True
        return 0, False, "main", True               # no branch is deleted in direct-commit
    if where in ("other", "detached"):              # row 3
        return 3, False, stay, True
    if where == "default":                          # row 2: any leftover stops
        if left != "none":
            return 3, False, "main", True
        committed = False
    else:                                           # row 1: own branch
        if left == "keep-out":
            return 3, False, "idd/5-x", True
        committed = left != "none"
    if remote == "ahead":
        return 3, committed, "main", True
    return 0, committed, "main", committed or work == 1   # an empty branch without upstream is deleted


def git(cwd, *args):
    return subprocess.run(["git", "-C", cwd, *args], env=ENV, capture_output=True, text=True, check=True).stdout.strip()


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


def one(base, case):
    path, where, left, remote, work = case
    root = tempfile.mkdtemp(prefix="m.", dir=base)
    shutil.copytree(os.path.join(base, "tpl"), root, dirs_exist_ok=True, symlinks=True)
    origin, tree = os.path.join(root, "origin.git"), os.path.join(root, "tree")
    git(tree, "remote", "set-url", "origin", origin)
    git(tree, "branch", "idd/5-x", "main")
    if work:
        git(tree, "checkout", "-q", "idd/5-x")
        write(os.path.join(tree, "w.txt"), "w\n")
        git(tree, "add", "w.txt")
        git(tree, "commit", "-q", "-m", "work")
        git(tree, "checkout", "-q", "main")
    if remote == "behind":   # origin gets a commit the working tree lacks
        tree_id = git(origin, "rev-parse", "main^{tree}")
        c = git(origin, "commit-tree", tree_id, "-p", "main", "-m", "remote")
        git(origin, "update-ref", "refs/heads/main", c)
    elif remote == "ahead":  # the local default branch gets a commit origin lacks
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
        write(os.path.join(tree, ".claude/.idd/attachments/issue-5/_manifest.json"), "{}\n")
    elif left == "keep-out":
        write(os.path.join(tree, ".claude/.idd/attachments/issue-5/raw.png"), "png\n")
    stamp = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    write(os.path.join(tree, ".claude/.idd/state/idd-all-rest.json"), json.dumps({
        "version": 1, "repo": "o/r", "started_at": stamp, "updated_at": stamp, "stop": None,
        "attempts": [{"issue": 5, "outcome": "stopped", "reason": "x", "handed_at": stamp, "recorded_at": stamp,
                      "settled": False}]}))
    before = git(tree, "rev-parse", "idd/5-x")
    proc = subprocess.run([sys.executable, RQ, "settle", "--cwd", tree, "--repo", "o/r", "--issue", "5",
                           "--default", "main", "--path", path], env=ENV, capture_output=True, text=True)
    exists = subprocess.run(["git", "-C", tree, "show-ref", "--verify", "--quiet", "refs/heads/idd/5-x"], env=ENV).returncode == 0
    after = git(tree, "rev-parse", "idd/5-x") if exists else before
    head = subprocess.run(["git", "-C", tree, "symbolic-ref", "--quiet", "--short", "HEAD"], env=ENV,
                          capture_output=True, text=True).stdout.strip() or "<detached>"
    got = (proc.returncode, after != before, head, exists)
    want = expected(*case)
    problems = []
    if got != want:
        problems.append(f"got {got}, want {want}")
    if proc.returncode == 0:
        if git(tree, "status", "--porcelain", "--untracked-files=all"):
            problems.append("exit 0 but the working tree is not clean")
        if git(tree, "rev-parse", "HEAD") != git(origin, "rev-parse", "main"):
            problems.append("exit 0 but HEAD is not the commit of origin/main")
    elif proc.returncode == 3 and len(proc.stderr.strip().splitlines()) != 1:
        problems.append(f"exit 3 without exactly one reason line: {proc.stderr.strip()[:200]!r}")
    shutil.rmtree(root, ignore_errors=True)
    return case, problems


def main():
    base = tempfile.mkdtemp(prefix="idd-settle-matrix.")
    try:
        os.mkdir(os.path.join(base, "tpl"))
        template(os.path.join(base, "tpl"))
        cases = list(itertools.product(PATHS, WHERE, LEFT, REMOTE, WORK))
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
