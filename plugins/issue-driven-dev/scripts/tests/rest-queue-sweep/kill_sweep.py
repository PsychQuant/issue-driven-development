#!/usr/bin/env python3
"""kill_sweep.py <rest-queue.py> <process-attachments.sh> — settle, killed at every point and run again (#478).

The requirement "Between two issues one helper settles the working tree" says that a `settle` which is killed and
run again ends where an uninterrupted one ends. This file checks that over every point at which the helper can
be killed, for the endings of ../rest-queue/endings.py listed in ROWS:

  1. the ending is built and `settle` runs once, undisturbed: the number of points it passes, and where it ends;
  2. for every k below that number the ending is built again, `settle` is made to end at point k (the helper's
     test hook: as if the process had been killed there), and then runs once more without the hook.

  at the kill  every file that was in the working tree before the issue was handed out is where it was, or in the
               folder settle moves such files to for the checkout (and listed there), and nowhere else
  afterwards   the second run exits as the undisturbed one did, and ends in the same place: every file of the
               working tree (read from the file system), the branch, `git status`, the branches of the issue and
               what each tip holds, what the run state records as kept, stashed, discarded, excluded, returned and
               missing, the stash list and the local exclude file
"""
import concurrent.futures
import json
import os
import shutil
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "rest-queue"))
import endings  # noqa: E402  (reads the two paths from sys.argv)
import treecheck  # noqa: E402

ROWS = ("stop-after-diagnose", "stop-in-implement", "stop-in-implement-attachments", "stop-in-implement-hooks-reject",
        "stop-in-implement-ignored-files", "stop-before-commit-ignored-files", "stop-rule-deleted", "merged-rule-deleted",
        "stop-tracks-file-from-before", "stop-hook-stages-everything", "merged-and-closed", "file-the-default-branch-tracks",
        "merged-file-untracked")
HELD = ".claude/.idd/state/rest-held-5"


def settle(tree, gh_dir, **extra):
    env = dict(endings.GIT_ENV, IDD_GH=os.path.join(HERE, "..", "rest-queue", "fake-gh.py"), FAKE_GH_DIR=gh_dir,
               IDD_CLOSE_STAGE_TEST="1", **extra)
    return endings.sh([sys.executable, endings.RQ, "settle", "--cwd", tree, "--repo", "o/r", "--issue", "5"], env=env, check=False)


def where(tree):
    """Where a settle ended, without what differs between two runs of the same thing (commit ids, times)."""
    g = lambda *a: endings.git(tree, *a, check=False)
    attempt = endings.state_of(tree)["attempts"][0]
    return {
        # the manifest holds the time of its download: two builds of one ending differ in it, so only its presence is compared
        "files": {p: ("there" if p == endings.M else d) for p, d in treecheck.snapshot(tree).items()},
        "on": g("symbolic-ref", "--quiet", "--short", "HEAD").strip(),
        "status": g("status", "--porcelain=v1", "--untracked-files=all"),
        "branches": {b: g("ls-tree", "-r", "--name-only", b) for b in endings.branches_of_5(tree)},
        "new commits": {b: sorted(g("log", "--format=%s", f"origin/main..{b}").splitlines()) for b in endings.branches_of_5(tree)},
        "kept": sorted((k["branch"], tuple(sorted(k.get("paths", []))), k.get("hooks"), k.get("upstream"), bool(k.get("commit")))
                       for k in attempt.get("kept", [])),
        "stashes": sorted((s["kind"], tuple(s.get("paths", [])), s.get("kept")) for s in attempt.get("stashes", [])),
        "stash list": sorted(line.split(": ", 1)[-1] for line in g("stash", "list", "--format=%gs").splitlines()),
        "discarded": sorted(attempt.get("discarded", [])),
        "excluded": sorted(attempt.get("excluded", [])),
        "returned": sorted(attempt.get("returned", [])),
        "missing": sorted(attempt.get("missing", [])),
        "settled": attempt.get("settled"),
        "exclude file": open(os.path.join(tree, ".git", "info", "exclude")).read(),
    }


def at_the_kill(tree, at_handout):
    """The files from before the hand-out that are neither where they were nor in the folder of files set aside."""
    lost = []
    held = {}
    listing = os.path.join(tree, HELD, "held.json")
    if os.path.isfile(listing):
        for e in json.load(open(listing)):
            path = os.path.join(tree, HELD, e["name"])
            if os.path.lexists(path):
                held[e["path"]] = treecheck.digest_of(path)
    for path, digest in sorted(at_handout.items()):
        here = os.path.join(tree, path)
        now = treecheck.digest_of(here) if os.path.lexists(here) else held.get(path)
        if now != digest:
            lost.append(f"{path} is {'gone' if now is None else 'changed'}")
    return lost


def reference(base, stub, row):
    root, origin, tree, gh_dir, at_handout = endings.build(base, stub, row)
    count = os.path.join(root, "steps")
    proc = settle(tree, gh_dir, IDD_REST_COUNT_STEPS=count)
    steps = int(open(count).read()) if os.path.isfile(count) else 0
    found = (proc.returncode, where(tree))
    shutil.rmtree(root, ignore_errors=True)
    return steps, found


def killed(base, stub, row, k, want):
    problems = []
    root = None
    try:
        root, origin, tree, gh_dir, at_handout = endings.build(base, stub, row)
        first = settle(tree, gh_dir, IDD_REST_STOP_AFTER_STEP=str(k))
        if first.returncode != 99:
            return [f"point {k}: the run was not killed there (exit {first.returncode})"]
        problems += [f"point {k}, at the kill: {p}" for p in at_the_kill(tree, at_handout)]
        second = settle(tree, gh_dir)
        got = (second.returncode, where(tree))
        if got[0] != want[0]:
            problems.append(f"point {k}: the second run exits {got[0]}, the undisturbed one {want[0]}: {second.stderr.strip()[:200]}")
        else:
            for key in want[1]:
                if got[1][key] != want[1][key]:
                    a, b = got[1][key], want[1][key]
                    if key == "files":
                        a = sorted(p for p in set(a) | set(b) if a.get(p) != b.get(p))
                        b = "(the paths that differ)"
                    problems.append(f"point {k}: {key} differs after the second run: {str(a)[:200]} — undisturbed: {str(b)[:160]}")
    except Exception as exc:
        problems.append(f"point {k}: {type(exc).__name__}: {str(exc)[:200]}")
    finally:
        if root:
            shutil.rmtree(root, ignore_errors=True)
    return problems


def main():
    base = tempfile.mkdtemp(prefix="idd-kill-sweep.")
    bad = points = 0
    try:
        endings.template(base)
        stub = endings.stubs(base)
        rows = [r for r in endings.ROWS if r["id"] in ROWS]
        if len(rows) != len(ROWS):
            print(f"FAIL: endings.py lacks {sorted(set(ROWS) - {r['id'] for r in rows})}")
            return 1
        with concurrent.futures.ThreadPoolExecutor(max_workers=min(16, os.cpu_count() or 2)) as pool:
            for row in rows:
                steps, want = reference(base, stub, row)
                if want[0] != 0 or steps < 5:
                    bad += 1
                    print(f"FAIL {row['id']}: the undisturbed run exits {want[0]} after {steps} points")
                    continue
                points += steps - 1
                for problems in pool.map(lambda k: killed(base, stub, row, k, want), range(1, steps)):
                    for p in problems:
                        bad += 1
                        print(f"FAIL {row['id']}: {p}")
        print(f"kill sweep: {len(rows)} endings, {points} kill points, {bad} failure(s)")
        return 1 if bad else 0
    finally:
        shutil.rmtree(base, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
