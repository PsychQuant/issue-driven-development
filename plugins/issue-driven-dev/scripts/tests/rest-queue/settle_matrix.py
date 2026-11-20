#!/usr/bin/env python3
"""settle_matrix.py <rest-queue.py> — every combination of the settle inputs, run for real (#478).

where the working tree is × what is left over × the local default branch against origin × whether the issue's
branch has a commit × whether it has an upstream: 4 × 6 × 2 × 2 × 2 = 192 temporary repositories, and, where the
working tree is on the issue's branch and that branch has a commit, what that commit did to the ignore rules
(deleted a folder with its own rules; rewrote the top rules): 6 × 2 × 2 × 2 = 48 more. Every repository holds
files that were there before the run and that git ignores, and its run state is written by the real `start`,
`next` and `record`. Each runs `rest-queue.py settle`. What the single-issue pipeline really leaves, ending by
ending, is endings.py; this file checks that the same invariants hold over the whole input space:

  always  every file that was in the working tree is accounted for, read from the file system (treecheck.py);
          what git did not track when #5 was handed out is where it was, with the same content
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

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import treecheck  # noqa: E402

RQ = os.path.abspath(sys.argv[1])
ENV = dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1", GIT_TERMINAL_PROMPT="0",
           IDD_GH=os.path.join(HERE, "fake-gh.py"), IDD_CLOSE_STAGE_TEST="1",
           GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.invalid",
           GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.invalid")
WHERE = {"own": "idd/5-x", "default": "main", "other": "idd/7-y", "detached": "<detached>"}
LEFT = ("none", "plain", "manifest", "attachment", "lock", "manifest+lock")   # attachment: the manifest and a file it lists
REMOTE = ("behind", "ahead")
WORK = (0, 1)
UPSTREAM = (0, 1)
RULES = ("kept", "folder-deleted", "rewritten")   # what the commit of the issue did to the ignore rules
# in the working tree before the run, and ignored there (the top rule `local/`, the rule `.env` of tools/.gitignore)
HERE_BEFORE = {"tools/.env": "TOKEN=ghp_secret\n", "local/settings.json": '{"mine": true}\n'}
FOLDER = ".claude/.idd/attachments/issue-5/"


def expected(where, left, remote, work, up, rules="kept"):
    """(exit code, settle made a commit on idd/5-x, idd/5-x still exists) — from the spec. What the commit of the
    issue did to the ignore rules changes none of the three: a path from before the run is no leftover."""
    if where in ("other", "detached"):              # row 3
        return 3, False, True
    if where == "default":                          # row 2: any leftover stops
        return (3, False, True) if left != "none" else (0, False, bool(work or up))
    if left in ("lock", "manifest+lock"):           # row 1, step 2: a place that is never committed; nothing is discarded first
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
    write(os.path.join(tree, "a.txt"), "a\n")
    write(os.path.join(tree, "tools", "run.sh"), "#!/bin/sh\n")
    write(os.path.join(tree, "tools", ".gitignore"), ".env\n")
    write(os.path.join(tree, ".gitignore"), "local/\n")
    git(tree, "add", "-A")
    git(tree, "commit", "-q", "-m", "init")
    git(tree, "remote", "add", "origin", origin)
    git(tree, "push", "-q", "-u", "origin", "main")
    for path, text in HERE_BEFORE.items():   # a person's own files: there before any run, and ignored
        write(os.path.join(tree, path), text)
    return root


def rq(tree, gh_dir, *args):
    return subprocess.run([sys.executable, RQ, args[0], "--cwd", tree, "--repo", "o/r", *args[1:]],
                          env=dict(ENV, FAKE_GH_DIR=gh_dir), capture_output=True, text=True)


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as fh:
        fh.write(text)


def snapshot(tree):
    return (git(tree, "rev-parse", "HEAD"), git(tree, "symbolic-ref", "--quiet", "--short", "HEAD", check=False),
            git(tree, "for-each-ref", "--format=%(refname) %(objectname)", "refs/heads/"),
            git(tree, "status", "--porcelain", "--untracked-files=all"))


def one(base, case):
    where, left, remote, work, up, rules = case
    root = tempfile.mkdtemp(prefix="m.", dir=base)
    shutil.copytree(os.path.join(base, "tpl"), root, dirs_exist_ok=True, symlinks=True)
    origin, tree, gh_dir = os.path.join(root, "origin.git"), os.path.join(root, "tree"), os.path.join(root, "gh")
    git(tree, "remote", "set-url", "origin", origin)
    os.mkdir(gh_dir)
    subprocess.run([sys.executable, os.path.join(HERE, "scenario.py"), gh_dir, "5"], env=ENV, check=True)
    # the run, as idd-all calls it: start and next on the clean default branch
    started = rq(tree, gh_dir, "start", "--path", "PR", "--review", "no")
    at_handout = treecheck.handout(tree)
    handed = rq(tree, gh_dir, "next")
    if started.returncode != 0 or '"next": 5' not in handed.stdout:
        shutil.rmtree(root, ignore_errors=True)
        return case, [f"fixture: start or next failed: {started.stderr.strip()[:120]} {handed.stdout.strip()[:80]} {handed.stderr.strip()[:120]}"]
    git(tree, "branch", "--no-track", "idd/5-x", "origin/main")
    if work:
        git(tree, "checkout", "-q", "idd/5-x")
        write(os.path.join(tree, "w.txt"), "w\n")
        git(tree, "add", "--", "w.txt")   # staged by name, as idd-implement does
        if rules == "folder-deleted":
            git(tree, "rm", "-q", "-r", "tools")
        elif rules == "rewritten":
            write(os.path.join(tree, ".gitignore"), "coverage/\n")
            git(tree, "add", "--", ".gitignore")
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
    if left in ("manifest", "manifest+lock"):
        write(os.path.join(tree, FOLDER + "_manifest.json"), json.dumps({"issue": 5, "files": []}))
    elif left == "attachment":
        write(os.path.join(tree, FOLDER + "spec.docx"), "bytes\n")
        write(os.path.join(tree, FOLDER + "_manifest.json"), json.dumps({"issue": 5, "files": [
            {"filename": "spec.docx", "url": "https://example.invalid/spec.docx", "sha256": hashlib.sha256(b"bytes\n").hexdigest()}]}))
    if left in ("lock", "manifest+lock"):
        write(os.path.join(tree, ".claude/.idd/tree-lock"), "pid\n")
    recorded = rq(tree, gh_dir, "record", "--issue", "5", "--reason", "x")
    if recorded.returncode != 0:
        shutil.rmtree(root, ignore_errors=True)
        return case, [f"fixture: record failed: {recorded.stderr.strip()[:160]}"]
    before, tip, files = snapshot(tree), git(tree, "rev-parse", "idd/5-x"), treecheck.snapshot(tree)
    proc = rq(tree, gh_dir, "settle", "--issue", "5")
    exists = subprocess.run(["git", "-C", tree, "show-ref", "--verify", "--quiet", "refs/heads/idd/5-x"], env=ENV).returncode == 0
    got = (proc.returncode, exists and git(tree, "rev-parse", "idd/5-x") != tip, exists)
    want = expected(*case)
    with open(os.path.join(tree, ".claude/.idd/state/idd-all-rest.json")) as fh:
        attempt = json.load(fh)["attempts"][0]
    refs = [before[0], tip, "refs/heads/main", "refs/heads/idd/5-x" if exists else "", *(k.get("commit") for k in attempt.get("kept", []))]
    for st in attempt.get("stashes", []):
        refs += [st.get("commit", ""), st.get("commit", "") + "^3"]
    problems = treecheck.account(tree, at_handout, files, refs=refs, discarded=attempt.get("discarded", []))
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
        kept = sorted(k["branch"] for k in attempt.get("kept", []))
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
        cases = [(*c, "kept") for c in itertools.product(WHERE, LEFT, REMOTE, WORK, UPSTREAM)]
        cases += [("own", left, remote, 1, up, rules) for left, remote, up, rules in itertools.product(LEFT, REMOTE, UPSTREAM, RULES[1:])]
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
