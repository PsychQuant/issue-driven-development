#!/usr/bin/env python3
"""treecheck.py — what `rest-queue.py settle` did to the files of a working tree, read from the file system (#478).

The requirement "Between two issues one helper settles the working tree" says that every file that was in the
working tree when an issue was handed out is accounted for after settle. The checks of that requirement used to
list "what was left" with `git status` on the issue's branch, which is the view settle itself works from; a file
that git does not show there was never looked at. This module does not ask git what is there. It walks the
folder.

  handout(tree)   before `next`: {path: digest} of every file git does not track (at that moment: what it ignores)
  snapshot(tree)  before `settle`: {path: digest} of every file
  account(...)    after `settle`: the problems, as text; an empty list means every file is accounted for

A file is accounted for when it is unchanged, or when its content from before settle is held by a commit or a
stash that the caller names (the tip of the issue's branch before settle, the commits and stashes settle recorded,
the default branch afterwards), or when settle reported it as a regenerated record it discarded. A file git did
not track at hand-out has one way only: it is where it was, with the content it had at hand-out.

As a command it checks itself:  treecheck.py --self-test
"""
import hashlib
import os
import subprocess
import sys

SKIP_DIRS = (".git", os.path.join(".claude", ".idd", "state"))   # git's own folder, and the helper's run state


def digest_of(path):
    if os.path.islink(path):
        return "link:" + os.readlink(path)
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def snapshot(tree):
    """{path relative to tree: digest} of every file and symlink below tree, outside SKIP_DIRS."""
    found = {}
    for base, dirs, files in os.walk(tree):
        rel = os.path.relpath(base, tree)
        rel = "" if rel == "." else rel
        dirs[:] = [d for d in dirs if os.path.join(rel, d) not in SKIP_DIRS and not os.path.islink(os.path.join(base, d))]
        for name in files + [d for d in os.listdir(base) if os.path.islink(os.path.join(base, d)) and d not in files]:
            path = os.path.join(rel, name)
            found[path.replace(os.sep, "/")] = digest_of(os.path.join(base, name))
    return found


def git(tree, *args):
    return subprocess.run(["git", "-C", tree, *args], capture_output=True)


def handout(tree):
    """{path: digest} of the files git does not track right now. Called on the clean default branch, before `next`."""
    tracked = set(git(tree, "ls-files", "-z").stdout.decode("utf-8", "replace").split("\0"))
    return {p: d for p, d in snapshot(tree).items() if p not in tracked}


def held_by(tree, ref, path, digest):
    """True when ref:path exists and holds the content with this digest."""
    proc = git(tree, "cat-file", "blob", f"{ref}:{path}")
    return proc.returncode == 0 and hashlib.sha256(proc.stdout).hexdigest() == digest


def account(tree, at_handout, before, refs=(), discarded=()):
    """The problems after settle. `at_handout` is handout() from before `next`, `before` is snapshot() from before
    settle, `refs` are commits that may hold what settle took out of the working tree, `discarded` are the
    regenerated records settle reported."""
    after, problems = snapshot(tree), []
    for path, digest in sorted(at_handout.items()):
        if path not in after:
            problems.append(f"{path} was in the working tree before the issue was handed out and is gone")
        elif after[path] != digest:
            problems.append(f"{path} was in the working tree before the issue was handed out and its content changed")
    for path, digest in sorted(before.items()):
        if path in at_handout or after.get(path) == digest or path in discarded:
            continue
        if digest.startswith("link:") or not any(held_by(tree, ref, path, digest) for ref in refs if ref):
            problems.append(f"{path} was in the working tree before settle; it is {'gone' if path not in after else 'changed'} "
                            "and no commit or stash that settle recorded holds what it was")
    return problems


def self_test():
    import shutil
    import tempfile
    env = dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1", GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.invalid",
               GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.invalid")
    base = tempfile.mkdtemp(prefix="treecheck.")
    run = lambda *a: subprocess.run(["git", "-C", base, *a], env=env, capture_output=True, check=True)
    put = lambda rel, text: (os.makedirs(os.path.dirname(os.path.join(base, rel)) or base, exist_ok=True), open(os.path.join(base, rel), "w").write(text))
    bad = []
    try:
        subprocess.run(["git", "init", "-q", "-b", "main", base], env=env, check=True)
        put("a.txt", "a\n"); put(".gitignore", "local/\n"); put("local/s.json", "mine\n")
        run("add", "a.txt", ".gitignore"); run("commit", "-q", "-m", "init")
        first = handout(base)
        if sorted(first) != ["local/s.json"]:
            bad.append(f"handout lists {sorted(first)}")
        put("a.txt", "changed\n"); put("new.txt", "n\n")
        before = snapshot(base)
        if account(base, first, before):
            bad.append("an unchanged tree is reported")
        run("checkout", "-q", "-b", "idd/5-x"); run("add", "-A"); run("commit", "-q", "-m", "keep"); run("checkout", "-q", "main")
        if account(base, first, before, refs=["idd/5-x"]):
            bad.append(f"files held by a named commit are reported: {account(base, first, before, refs=['idd/5-x'])}")
        if len(account(base, first, before)) != 2:
            bad.append("files that no named commit holds are not reported")
        os.unlink(os.path.join(base, "local/s.json"))
        if not any("local/s.json" in p and "gone" in p for p in account(base, first, before, refs=["idd/5-x"])):
            bad.append("a deleted file from before the hand-out is not reported")
        put("local/s.json", "other\n")
        if not any("local/s.json" in p and "changed" in p for p in account(base, first, before, refs=["idd/5-x"])):
            bad.append("a changed file from before the hand-out is not reported")
    finally:
        shutil.rmtree(base, ignore_errors=True)
    for b in bad:
        print("FAIL treecheck:", b)
    print(f"treecheck self-test: {len(bad)} failure(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(self_test() if sys.argv[1:] == ["--self-test"] else 2)
