"""Second rename fuzz for check-merge-completeness (#399 round 18).

Round 17's verify found that fuzzrename.py never builds the shapes that broke round 17:
two files swapping names, a file moved back to an old name, a copy and then the
original deleted, main moving a file itself, and a branch that merges main after main
squashed part of it. This generator builds them.

Two tracked files, A and B. Every line names its file ("base A3", "pad B2 a", "R4 A7"),
and every line is unique, so which file sits at a name is read from the lines (the
majority id), not from the name. Ops per branch commit: add a marker, delete a base
line, move a file to a free name, move it back to a name it had, swap A and B (three
commits: A to a temporary name, B to A's name, the temporary name to B's), copy a file
to a new name and delete the original in the next commit, rewrite most of a file, put a
shim at a name a file left, add an unrelated file.

main: sometimes its own unrelated commit, sometimes a move of A to a name of its own
(before the picks), then a squash of a random subset S of the branch's commits (each
cherry-picked; a conflict skips the case). In sync mode the branch then merges main and
adds 1-3 more commits, and main sometimes squashes a subset of those as well.

Ground truth (decision A: did the branch's content land): a commit outside S is an
orphan when one of its effects is in the head and not on main:
  line m     the marker m is in the head's text and not in main's
  gone v     the base line v is not in the head's text and is in main's
  at X v     the head has file X at name v, and main does not
  path X u   the head does not have file X at u, and main does
Effects are unique to their commit, so main can only have one by landing that commit.
A disagreement is tagged "(not a prefix)" when the landed commits are not a prefix of the
branch: SPEC.md's M1 (shape 1) accepts wrong answers there when the branch moved, swapped or
copied a file. Run from this directory: python3 -I fuzzrename2.py ../../check-merge-completeness.sh 60 1

usage: python3 -I fuzzrename2.py <helper> <cases> <seed> [--show N] [--sync P]
"""
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile

helper, cases, seed = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
args = sys.argv[4:]
show = int(args[args.index("--show") + 1]) if "--show" in args else 4
psync = float(args[args.index("--sync") + 1]) if "--sync" in args else 0.25
rnd = random.Random(seed)
env = dict(os.environ, GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@t", GIT_COMMITTER_NAME="t",
           GIT_COMMITTER_EMAIL="t@t", GIT_CONFIG_NOSYSTEM="1", HOME="/nonexistent")
POOL = ["lib/f.txt", "src/g.txt", "h.txt", "deep/x/f.txt", "k.txt", "z/q.txt", "t1.txt", "t2.txt"]
IDRE = re.compile(r"^(?:base|pad|R\d+) ([AB])\d")
keep_dir = os.environ.get("FZR_KEEP_DIR", tempfile.gettempdir())


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


def ident(lines):
    if not lines:
        return None
    c = {"A": 0, "B": 0}
    for l in lines:
        m = IDRE.match(l)
        if m:
            c[m.group(1)] += 1
    if c["A"] == c["B"] == 0:
        return None
    return "A" if c["A"] > c["B"] else "B"


def state(d, rev):
    names = tree_names(d, rev)
    txt, at = set(), {}
    for x in names:
        ls = read(d, rev, x) or []
        txt |= set(ls)
        at[x] = ident(ls)
    return names, txt, at


class Branch:
    def __init__(self, d):
        self.d = d
        self.files = {}     # id -> {"name", "lines", "had": [names]}
        self.left = []      # names a file left, free now
        self.shas, self.effects = [], []

    def held(self):
        return {f["name"] for f in self.files.values()}

    def free(self):
        tn = tree_names(self.d, "HEAD")
        return [x for x in POOL if x not in tn]

    def commit(self, msg, eff):
        git(self.d, "add", "-A")
        git(self.d, "commit", "-qm", msg)
        self.shas.append(git(self.d, "rev-parse", "HEAD").stdout.decode().strip())
        self.effects.append((msg, eff))

    def mv(self, X, new):
        old = self.files[X]["name"]
        os.makedirs(os.path.dirname(os.path.join(self.d, new)) or self.d, exist_ok=True)
        git(self.d, "mv", old, new)
        self.files[X]["name"] = new
        self.files[X]["had"].append(new)
        return old

    def reload(self):
        for X, f in self.files.items():
            ls = read(self.d, "HEAD", f["name"])
            if ls is not None:
                f["lines"] = ls

    def step(self, c):
        """One op; returns the number of commits it made (0 if none applied)."""
        X = rnd.choice(sorted(self.files))
        f = self.files[X]
        ops = ["add", "add", "del", "move", "move", "other", "swap", "copydel", "moveback"]
        if self.left:
            ops.append("shim")
        if c > 0:
            ops.append("rewrite")
        op = rnd.choice(ops)
        if op == "add":
            pos = rnd.randrange(0, max(1, len(f["lines"]) // 4)) * 4 + 2
            m = f"M{c} {X} marker"
            f["lines"] = f["lines"][:pos] + [m] + f["lines"][pos:]
            write(self.d, f["name"], f["lines"])
            self.commit(f"c{c}: add {X}", [("line", m)])
            return 1
        if op == "del":
            cands = [l for l in f["lines"] if l.startswith("base ")]
            if cands:
                b = rnd.choice(cands)
                f["lines"] = [l for l in f["lines"] if l != b]
                write(self.d, f["name"], f["lines"])
                self.commit(f"c{c}: del {X}", [("gone", b)])
                return 1
            op = "other"
        if op == "rewrite":
            idx = [k for k, l in enumerate(f["lines"]) if l.startswith("pad ")]
            if idx:
                rnd.shuffle(idx)
                for k in idx[: int(len(idx) * 0.7)]:
                    f["lines"][k] = f"R{c} {X}{k}"
                write(self.d, f["name"], f["lines"])
                self.commit(f"c{c}: rewrite {X}", [("line", f"R{c} {X}{idx[0]}")])
                return 1
            op = "other"
        if op == "move":
            fr = self.free()
            if fr:
                new = rnd.choice(fr)
                old = self.mv(X, new)
                self.left.append(old)
                self.commit(f"c{c}: move {X} {old} -> {new}", [("at", X, new), ("path", X, old)])
                return 1
            op = "other"
        if op == "moveback":
            tn = tree_names(self.d, "HEAD")
            back = [x for x in f["had"][:-1] if x not in tn]
            if back:
                to = rnd.choice(back)
                old = self.mv(X, to)
                if to in self.left:
                    self.left.remove(to)
                self.left.append(old)
                self.commit(f"c{c}: move {X} back {old} -> {to}", [("at", X, to), ("path", X, old)])
                return 1
            op = "other"
        if op == "swap":
            fr = self.free()
            if len(self.files) == 2 and fr:
                t = rnd.choice(fr)
                a, b = self.files["A"]["name"], self.files["B"]["name"]
                self.mv("A", t)
                self.commit(f"c{c}: swap 1 A {a} -> {t}", [("at", "A", t), ("path", "A", a)])
                self.mv("B", a)
                self.commit(f"c{c + 1}: swap 2 B {b} -> {a}", [("at", "B", a), ("path", "B", b)])
                self.mv("A", b)
                self.commit(f"c{c + 2}: swap 3 A {t} -> {b}", [("at", "A", b), ("path", "A", t)])
                return 3
            op = "other"
        if op == "copydel":
            fr = self.free()
            if fr:
                v = rnd.choice(fr)
                old = f["name"]
                m = f"C{c} {X} copy marker"
                f["lines"] = f["lines"] + [m]
                write(self.d, v, f["lines"])
                self.commit(f"c{c}: copy {X} {old} -> {v}", [("at", X, v), ("line", m)])
                git(self.d, "rm", "-q", old)
                f["name"] = v
                f["had"].append(v)
                self.left.append(old)
                self.commit(f"c{c + 1}: delete {X} at {old}", [("path", X, old)])
                return 2
            op = "other"
        if op == "shim":
            at = self.left.pop(rnd.randrange(len(self.left)))
            if at not in tree_names(self.d, "HEAD"):
                write(self.d, at, [f"shim {c} 1", f"shim {c} 2"])
                self.commit(f"c{c}: shim at {at}", [("line", f"shim {c} 1")])
                return 1
        write(self.d, f"u{c}.txt", [f"unrelated {c}"])
        self.commit(f"c{c}: other", [("line", f"unrelated {c}")])
        return 1


def squash(d, picks, msg):
    before = git(d, "rev-parse", "HEAD").stdout.decode().strip()
    for s in picks:
        r = git(d, "cherry-pick", s, check=False)
        if r.returncode != 0:
            git(d, "cherry-pick", "--abort", check=False)
            return False
    git(d, "reset", "-q", "--soft", before)
    if git(d, "diff", "--cached", "--quiet", check=False).returncode != 0:
        git(d, "commit", "-qm", msg)
    return True


def one_case(i):
    d = tempfile.mkdtemp(prefix="fzr2")
    try:
        git(d, "init", "-q", "-b", "main")
        git(d, "config", "commit.gpgsign", "false")
        br = Branch(d)
        for X, name in (("A", "f.txt"), ("B", "g.txt")):
            nb = rnd.randint(6, 10)
            ls = []
            for k in range(nb):
                ls += [f"base {X}{k}", f"pad {X}{k} a", f"pad {X}{k} b", f"pad {X}{k} c"]
            write(d, name, ls)
            br.files[X] = {"name": name, "lines": ls, "had": [name]}
        write(d, "other.txt", ["other"])
        git(d, "add", "-A"); git(d, "commit", "-qm", "base")
        git(d, "checkout", "-q", "-b", "feat")
        sync = rnd.random() < psync
        c = 0
        for _ in range(rnd.randint(2, 4)):
            c += br.step(c)
        n1 = len(br.shas)
        git(d, "checkout", "-q", "main")
        mode = []
        if rnd.random() < 0.3:
            write(d, "mainown.txt", ["main"]); git(d, "add", "-A"); git(d, "commit", "-qm", "main own")
            mode.append("own")
        if not sync and rnd.random() < 0.2:
            git(d, "mv", "f.txt", "mm.txt"); git(d, "commit", "-qm", "main: move f.txt to mm.txt")
            mode.append("main-move")
        S = sorted(rnd.sample(range(n1), rnd.randint(1, n1))) if rnd.random() < 0.8 else list(range(n1))
        if not squash(d, [br.shas[k] for k in S], "PR (squash)"):
            return "skip", None
        if sync:
            mode.append("sync")
            git(d, "checkout", "-q", "feat")
            if git(d, "merge", "-q", "--no-edit", "main", check=False).returncode != 0:
                git(d, "merge", "--abort", check=False)
                return "skip", None
            br.reload()
            for X, f in br.files.items():
                if read(d, "HEAD", f["name"]) is None:
                    return "skip", None
            for _ in range(rnd.randint(1, 3)):
                c += br.step(c)
            git(d, "checkout", "-q", "main")
            n2 = len(br.shas)
            if rnd.random() < 0.5:
                S2 = sorted(rnd.sample(range(n1, n2), rnd.randint(1, n2 - n1)))
                if not squash(d, [br.shas[k] for k in S2], "PR 2 (squash)"):
                    return "skip", None
                S = S + S2
        n = len(br.shas)
        hnames, htxt, hat = state(d, "feat")
        mnames, mtxt, mat = state(d, "main")
        exp = set()
        for k in range(n):
            if k in S:
                continue
            for e in br.effects[k][1]:
                if e[0] == "line" and e[1] in htxt and e[1] not in mtxt:
                    exp.add(k)
                elif e[0] == "gone" and e[1] not in htxt and e[1] in mtxt:
                    exp.add(k)
                elif e[0] == "at" and hat.get(e[2]) == e[1] and mat.get(e[2]) != e[1]:
                    exp.add(k)
                elif e[0] == "path" and hat.get(e[2]) != e[1] and mat.get(e[2]) == e[1]:
                    exp.add(k)
        ch = git(d, "cherry", "main", "feat").stdout.decode().split("\n")
        plus = {l.split()[1] for l in ch if l.startswith("+")}
        exp = {k for k in exp if br.shas[k] in plus}
        pr = subprocess.run(["bash", helper, "--repo", d, "--branch", "feat", "--baseline", "main"],
                            capture_output=True, env=dict(os.environ))
        out = pr.stdout.decode(errors="replace")
        rows = [l.split()[0] for l in out.splitlines() if l.startswith("  ") and l.split()
                and re.fullmatch(r"[0-9a-f]{7,40}", l.split()[0])]
        listed = {k for k in range(n) if any(br.shas[k].startswith(r) for r in rows)}
        unmapped = [r for r in rows if not any(s.startswith(r) for s in br.shas)]
        info = (mode, S, [m for m, _ in br.effects], sorted(exp), sorted(listed), pr.returncode)
        # the landed commits a prefix of the branch (or none, or all) — else SPEC D1's tip route
        tag = "" if S == list(range(len(S))) else " (not a prefix)"
        if pr.returncode == 4:
            return "exit4", (mode, pr.stderr.decode(errors="replace").strip()[:300])
        if pr.returncode not in (0, 3):
            return "error", (pr.returncode, pr.stderr.decode(errors="replace")[:300])
        if exp - listed:
            return "false clean" + tag, info
        if (listed - exp) or unmapped:
            return "false listing" + tag, info + (unmapped,)
        return "agree", None
    finally:
        keep = os.environ.get("FZR_KEEP", "")
        if keep and str(i) in keep.split(","):
            dst = os.path.join(keep_dir, f"case{i}")
            shutil.rmtree(dst, ignore_errors=True); shutil.copytree(d, dst, symlinks=True)
        shutil.rmtree(d, ignore_errors=True)


counts, shown = {}, {}
for i in range(cases):
    try:
        k, info = one_case(i)
    except RuntimeError as e:
        k, info = "skip", str(e)[:200]
    counts[k] = counts.get(k, 0) + 1
    if k not in ("agree", "skip", "D1+D2") and shown.get(k, 0) < show:
        shown[k] = shown.get(k, 0) + 1
        print(f"case {i} {k}: {info}")
print("counts:", " ".join(f"{k}={v}" for k, v in sorted(counts.items())))
