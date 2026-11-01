"""Rename fuzz for check-merge-completeness (#399 verify round 16).

A branch of 3-6 commits over one file; each commit adds a unique marker line, deletes a
base line, moves the file to a new name, puts a new file (a shim) at a name the file
left, rewrites most of the file, or adds an unrelated file. main receives a subset S of
the commits as cherry-picks folded into one squash commit (all of them, or a random
subset), sometimes after a commit of its own on an unrelated file, sometimes followed
by a follow-up on a landed line (decision A: out of scope). A case whose picks
conflict is skipped.

Ground truth: a commit outside S is an orphan when an effect it has is still in the
head: a marker it added that the head's file still has, a base line it deleted that
the head's file still lacks (while main's file has it), a shim or unrelated file it
added that the head still has, a move whose name the head's file still has. Every
effect is unique to its commit, so main can only have it by landing that commit.

usage: python3 -I fuzzrename.py <helper> <cases> <seed> [--show N]
(from this directory: python3 -I fuzzrename.py ../../check-merge-completeness.sh 80 7)
Prints counts of: agree, false clean (an expected orphan not listed, or rc 0 when one is
expected), false listing (a commit listed that is not an orphan), exit 4, skipped."""
import os
import random
import shutil
import subprocess
import sys
import tempfile

helper, cases, seed = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
show = int(sys.argv[5]) if len(sys.argv) > 5 and sys.argv[4] == "--show" else 4
rnd = random.Random(seed)
env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t",
           GIT_COMMITTER_EMAIL="t@t", GIT_CONFIG_NOSYSTEM="1", HOME="/nonexistent")
NAMES = ["f.txt", "lib/f.txt", "src/g.txt", "h.txt", "deep/x/f.txt"]


def git(d, *a, check=True):
    r = subprocess.run(["git", "-C", d] + list(a), env=env, capture_output=True)
    if check and r.returncode != 0:
        raise RuntimeError(f"git {a}: {r.stderr.decode(errors='replace')}")
    return r


def write(d, name, lines):
    p = os.path.join(d, name)
    os.makedirs(os.path.dirname(p) or d, exist_ok=True)
    with open(p, "w") as f:
        f.write("".join(l + "\n" for l in lines))


def read(d, rev, name):
    r = git(d, "show", f"{rev}:{name}", check=False)
    return None if r.returncode else r.stdout.decode(errors="replace").splitlines()


def tree_names(d, rev):
    return set(git(d, "ls-tree", "-r", "--name-only", rev).stdout.decode().splitlines())


def one_case(i):
    d = tempfile.mkdtemp(prefix="fzr")
    try:
        git(d, "init", "-q", "-b", "main")
        git(d, "config", "commit.gpgsign", "false")
        nb = rnd.randint(8, 12)
        lines = []
        for k in range(nb):
            lines += [f"base {k}", f"pad {k} a", f"pad {k} b", f"pad {k} c"]
        cur = "f.txt"
        write(d, cur, lines)
        write(d, "other.txt", ["other"])
        git(d, "add", "-A"); git(d, "commit", "-qm", "base")
        git(d, "checkout", "-q", "-b", "feat")
        n = rnd.randint(3, 6)
        effects = []          # per commit: list of (kind, value)
        left = []             # names the file left that hold nothing now
        used = {cur}
        for c in range(n):
            ops = ["add", "add", "del", "move", "move", "other"]
            if left:
                ops.append("shim")
            if c > 0:
                ops.append("rewrite")
            op = rnd.choice(ops)
            eff = []
            if op == "add":
                pos = rnd.randrange(0, len(lines) // 4) * 4 + 2
                m = f"M{c} marker"
                lines = lines[:pos] + [m] + lines[pos:]
                write(d, cur, lines); eff.append(("line", m))
            elif op == "del":
                cands = [l for l in lines if l.startswith("base ")]
                if not cands:
                    op = "other"
                else:
                    b = rnd.choice(cands)
                    lines = [l for l in lines if l != b]
                    write(d, cur, lines); eff.append(("gone", b))
            if op == "move":
                free = [x for x in NAMES if x not in used]
                if not free:
                    op = "other"
                else:
                    new = rnd.choice(free)
                    used.add(new)
                    os.makedirs(os.path.dirname(os.path.join(d, new)) or d, exist_ok=True)
                    git(d, "mv", cur, new)
                    left.append(cur); eff.append(("name", new)); eff.append(("path gone", cur)); cur = new
            if op == "shim":
                at = left.pop(rnd.randrange(len(left)))
                write(d, at, [f"shim {c} 1", f"shim {c} 2"]); eff.append(("file", at))
            if op == "rewrite":
                idx = [k for k, l in enumerate(lines) if l.startswith("pad ")]
                rnd.shuffle(idx)
                for k in idx[: int(len(idx) * 0.7)]:
                    lines[k] = f"R{c} {k}"
                write(d, cur, lines); eff.append(("line", f"R{c} {idx[0]}"))
            if op == "other":
                write(d, f"u{c}.txt", [f"unrelated {c}"]); eff.append(("file", f"u{c}.txt"))
            git(d, "add", "-A"); git(d, "commit", "-qm", f"c{c}: {op}")
            effects.append((op, eff))
        shas = git(d, "rev-list", "--reverse", "main..feat").stdout.decode().split()
        # main
        git(d, "checkout", "-q", "main")
        if rnd.random() < 0.3:
            write(d, "mainown.txt", ["main"]); git(d, "add", "-A"); git(d, "commit", "-qm", "main own")
        S = sorted(rnd.sample(range(n), rnd.randint(1, n))) if rnd.random() < 0.8 else list(range(n))
        before = git(d, "rev-parse", "HEAD").stdout.decode().strip()
        for k in S:
            r = git(d, "cherry-pick", shas[k], check=False)
            if r.returncode != 0:
                git(d, "cherry-pick", "--abort", check=False)
                return "skip", None
        git(d, "reset", "-q", "--soft", before)
        git(d, "commit", "-qm", "PR (squash)")
        fu = None
        if rnd.random() < 0.3:
            # a follow-up on a landed marker line (out of scope by decision A)
            hn = [x for x in tree_names(d, "HEAD") if x in NAMES]
            if hn:
                fl = read(d, "HEAD", hn[0]) or []
                mk = [k for k, l in enumerate(fl) if l.startswith("M")]
                if mk:
                    fu = fl[mk[0]]
                    fl[mk[0]] = fl[mk[0]] + " (follow-up)"
                    write(d, hn[0], fl); git(d, "commit", "-qam", "follow-up")
        # truth
        head_files = tree_names(d, "feat")
        main_files = tree_names(d, "main")
        head_lines = set(read(d, "feat", cur) or [])
        main_txt = set()
        for x in tree_names(d, "main"):
            main_txt |= set(read(d, "main", x) or [])
        exp = set()
        for k in range(n):
            if k in S:
                continue
            op, eff = effects[k]
            for kind, v in eff:
                if kind == "line" and v in head_lines:
                    exp.add(k)
                elif kind == "gone" and v not in head_lines and v in main_txt:
                    exp.add(k)
                elif kind == "file" and v in head_files:
                    exp.add(k)
                elif kind == "name" and v == cur:
                    exp.add(k)
                elif kind == "name" and v in head_files:
                    exp.add(k)
                elif kind == "path gone" and v not in head_files and v in main_files:
                    exp.add(k)
        # commits git cherry already finds in main are not candidates: never listed
        ch = git(d, "cherry", "main", "feat").stdout.decode().split("\n")
        plus = {l.split()[1] for l in ch if l.startswith("+")}
        exp = {k for k in exp if shas[k] in plus}
        pr = subprocess.run(["bash", helper, "--repo", d, "--branch", "feat", "--baseline", "main"],
                            capture_output=True, env=dict(os.environ))
        out = pr.stdout.decode(errors="replace")
        rows = {l.split()[0] for l in out.splitlines() if l.startswith("  ") and l.split()}
        listed = {k for k in range(n) if any(shas[k].startswith(r) for r in rows if len(r) >= 7)}
        if pr.returncode == 4:
            return "exit4", (S, effects, pr.stderr.decode(errors="replace").strip())
        if pr.returncode not in (0, 3):
            return "error", (pr.returncode, pr.stderr.decode(errors="replace"))
        if exp - listed:
            return "false clean", (S, effects, sorted(exp), sorted(listed), pr.returncode)
        extra = listed - exp
        # SPEC D1+D2: when the landed commits are not a prefix of the branch they are
        # checked at the tip, where main's follow-up on a landed line is part of the target
        if extra and fu is not None and S != list(range(len(S))):
            extra = {k for k in extra if not any(kind == "line" and v == fu for kind, v in effects[k][1])}
            if not extra:
                return "D1+D2 follow-up at the tip", None
        if extra:
            return "false listing", (S, effects, sorted(exp), sorted(listed), pr.returncode, fu)
        return "agree", None
    finally:
        keep = os.environ.get("FZR_KEEP", "")
        if keep and str(i) in keep.split(","):
            dst = os.path.join(keep_dir, f"case{i}")
            shutil.rmtree(dst, ignore_errors=True); shutil.copytree(d, dst, symlinks=True)
        shutil.rmtree(d, ignore_errors=True)


keep_dir = os.environ.get("FZR_KEEP_DIR", "/tmp")
counts = {}
shown = {}
for i in range(cases):
    try:
        kind, info = one_case(i)
    except RuntimeError as e:
        kind, info = "setup error", str(e)[:200]
    counts[kind] = counts.get(kind, 0) + 1
    if info is not None and shown.get(kind, 0) < show:
        shown[kind] = shown.get(kind, 0) + 1
        print(f"[{kind} #{i}] {info}", flush=True)
print(counts, flush=True)
