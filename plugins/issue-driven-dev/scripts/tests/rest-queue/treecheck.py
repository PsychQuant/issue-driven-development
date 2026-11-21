#!/usr/bin/env python3
"""treecheck.py — what a repository holds, read from the file system and from git (#478).

The requirement "A rest run leaves the working tree it was started in as it was" is checked by listing the
repository before `start` and after `report` and comparing the two listings. The listing does not go by what
`git status` shows: it walks the folder, so a file git ignores is in it like any other.

  treecheck.py list <tree>    one line per fact: every file and link with its content, every folder, the commit and
                              the branch checked out, the index, the local branches, the tags and the stash
  treecheck.py same <before> <after>   exit 0 when the second listing is the first one, with nothing but new tags
                              added: a fetch brings the tags origin has, and changes none that is there
  treecheck.py --self-test    checks that the listing changes when one of those facts changes, and does not change
                              for the places a rest run may write

The places a rest run may write are left out (the closed list of the requirement): the state folder
(.claude/.idd/state/), the folder of the directories (.claude/worktrees/), the routing log
(.claude/.idd/routing-stats.jsonl) and git's own folder, in which the local exclude file is; remote-tracking
branches are not listed either, because a fetch moves them.
"""
import hashlib
import os
import subprocess
import sys
import tempfile

SKIP_DIRS = (".git", ".claude/.idd/state", ".claude/worktrees")
SKIP_FILES = (".claude/.idd/routing-stats.jsonl",)


def digest_of(path):
    if os.path.islink(path):
        return "link:" + os.readlink(path)
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 16), b""):
            h.update(chunk)
    return h.hexdigest()


def git(tree, *args):
    return subprocess.run(["git", "-C", tree, *args], capture_output=True).stdout.decode("utf-8", "surrogateescape")


def listing(tree):
    lines = []
    for base, dirs, files in os.walk(tree):
        rel = os.path.relpath(base, tree).replace(os.sep, "/")
        rel = "" if rel == "." else rel + "/"
        links = [d for d in dirs if os.path.islink(os.path.join(base, d))]
        dirs[:] = [d for d in dirs if rel + d not in SKIP_DIRS and d not in links]
        lines += [f"dir {rel}{d}" for d in dirs if rel + d not in (".claude", ".claude/.idd")]   # a run may make the folders its places are in
        for name in files + links:
            if rel + name not in SKIP_FILES:
                lines.append(f"file {rel}{name} {digest_of(os.path.join(base, name))}")
    lines.append("head " + git(tree, "rev-parse", "-q", "--verify", "HEAD").strip())
    lines.append("on " + git(tree, "symbolic-ref", "-q", "HEAD").strip())
    index = git(tree, "rev-parse", "--git-path", "index").strip()
    index = index if os.path.isabs(index) else os.path.join(tree, index)
    lines.append("index " + (digest_of(index) if os.path.exists(index) else "none"))   # the bytes: a refreshed stat cache is a change
    lines += ["ref " + line for line in git(tree, "for-each-ref", "--format=%(refname) %(objectname)", "refs/heads").splitlines()]
    lines += ["tag " + line for line in git(tree, "for-each-ref", "--format=%(refname) %(objectname)", "refs/tags").splitlines()]
    lines += ["stash " + line for line in git(tree, "stash", "list", "--format=%H").splitlines()]
    return sorted(lines)


def same(before, after):
    """True when `after` holds every line of `before`, and nothing else but tags whose name `before` does not have."""
    names = {line.split(" ")[1] for line in before if line.startswith("tag ")}
    extra = [line for line in after if line not in set(before)]
    return set(before) <= set(after) and all(line.startswith("tag ") and line.split(" ")[1] not in names for line in extra)


def self_test():
    env = {"GIT_CONFIG_GLOBAL": os.devnull, "GIT_CONFIG_NOSYSTEM": "1", "GIT_AUTHOR_NAME": "t", "GIT_AUTHOR_EMAIL": "t@example.invalid",
           "GIT_COMMITTER_NAME": "t", "GIT_COMMITTER_EMAIL": "t@example.invalid"}
    os.environ.update(env)
    failed = []
    with tempfile.TemporaryDirectory() as tree:
        run = lambda *args: subprocess.run(["git", "-C", tree, *args], capture_output=True, check=True)
        put = lambda rel, text: (os.makedirs(os.path.dirname(os.path.join(tree, rel)) or tree, exist_ok=True),
                                 open(os.path.join(tree, rel), "w").write(text))
        run("init", "-q", "-b", "main")
        put("a.txt", "a\n"); put(".gitignore", "local/\n"); put("local/notes.txt", "mine\n")
        run("add", "a.txt", ".gitignore"); run("commit", "-q", "-m", "init")
        base = [listing(tree)]
        no_index = lambda lines: [ln for ln in lines if not ln.startswith("index ")]

        def expect(name, changes, act, undo):
            base[0] = listing(tree)   # the git commands of an earlier undo may have written the index
            act()
            if (listing(tree) != base[0]) != changes:
                failed.append(name)
            undo()
            if no_index(listing(tree)) != no_index(base[0]):
                failed.append(name + " (not undone: the self-test is wrong)")

        rm = lambda rel: os.unlink(os.path.join(tree, rel))
        expect("a changed tracked file", True, lambda: put("a.txt", "b\n"), lambda: put("a.txt", "a\n"))
        expect("a changed ignored file", True, lambda: put("local/notes.txt", "x\n"), lambda: put("local/notes.txt", "mine\n"))
        expect("a new untracked file", True, lambda: put("b.txt", "b\n"), lambda: rm("b.txt"))
        expect("a removed ignored file", True, lambda: rm("local/notes.txt"), lambda: put("local/notes.txt", "mine\n"))
        expect("a staged change", True, lambda: (put("a.txt", "s\n"), run("add", "a.txt")),
               lambda: (run("reset", "-q", "HEAD", "a.txt"), put("a.txt", "a\n")))
        expect("a new branch", True, lambda: run("branch", "side"), lambda: run("branch", "-D", "side"))
        expect("a new tag", True, lambda: run("tag", "v1"), lambda: run("tag", "-d", "v1"))
        run("tag", "v0")
        tagged = listing(tree)
        run("tag", "v1")
        if not same(tagged, listing(tree)):
            failed.append("same: a new tag is allowed")
        run("tag", "-f", "v0", "HEAD~0"); run("commit", "-q", "--allow-empty", "-m", "two"); run("tag", "-f", "v0")
        if same(tagged, listing(tree)):
            failed.append("same: a moved tag and a new commit are not")
        run("reset", "-q", "--hard", "HEAD~1"); run("tag", "-d", "v0"); run("tag", "-d", "v1")
        expect("a checkout of another branch", True, lambda: run("checkout", "-q", "-b", "other"),
               lambda: (run("checkout", "-q", "main"), run("branch", "-D", "other")))
        expect("a refreshed index", True, lambda: (os.utime(os.path.join(tree, "a.txt"), (0, 0)), subprocess.run(["git", "-C", tree, "status"], capture_output=True)),
               lambda: None)
        expect("a stash", True, lambda: (put("a.txt", "st\n"), run("stash")), lambda: (run("stash", "drop"), put("a.txt", "a\n")))
        expect("the state folder", False, lambda: put(".claude/.idd/state/x.json", "{}"), lambda: rm(".claude/.idd/state/x.json"))
        expect("the folder of the directories", False, lambda: put(".claude/worktrees/rest-5/a.txt", "x"), lambda: rm(".claude/worktrees/rest-5/a.txt"))
        expect("the routing log", False, lambda: put(".claude/.idd/routing-stats.jsonl", "{}\n"), lambda: rm(".claude/.idd/routing-stats.jsonl"))
        expect("the local exclude file", False, lambda: put(".git/info/exclude", "x\n"), lambda: put(".git/info/exclude", ""))
        expect("another file below .claude/.idd", True, lambda: put(".claude/.idd/local.json", "{}"), lambda: rm(".claude/.idd/local.json"))
    for name in failed:
        print("FAIL: " + name)
    print(f"treecheck self-test: {17 - len(failed)} of 17 pass")
    return 1 if failed else 0


if __name__ == "__main__":
    if sys.argv[1:] == ["--self-test"]:
        sys.exit(self_test())
    if len(sys.argv) == 4 and sys.argv[1] == "same":
        sys.exit(0 if same(*[open(p, encoding="utf-8", errors="surrogateescape").read().splitlines() for p in sys.argv[2:4]]) else 1)
    if len(sys.argv) == 3 and sys.argv[1] == "list":
        print("\n".join(listing(sys.argv[2])))
        sys.exit(0)
    print(__doc__, file=sys.stderr)
    sys.exit(2)
