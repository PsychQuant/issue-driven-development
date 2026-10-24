#!/usr/bin/env python3
"""bounded.py — check check-merge-completeness.sh against SPEC.md in a small world.

Every history in the world is built the way SPEC.md defines its ground truth: the
branch is a sequence of single-unit edits on top of a merge-base, and main receives
a known subset S of the branch commits as one squash (or nothing), possibly after
a commit of its own. The oracle computes the expected verdict from S; the helper
has to infer it from the trees. Each disagreement is either a known deviation, as
SPEC.md enumerates them, or a bug.

  python3 bounded.py [--max-len N] [--sample K] [--seed S] [--jobs J]
                     [--old-git SHIM_DIR] [--after] [--show N]

Exit 0 when every disagreement is a known deviation, 1 otherwise.
"""
import argparse
import itertools
import multiprocessing as mp
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
HELPER = os.path.join(HERE, "..", "..", "check-merge-completeness.sh")

# ── The world ───────────────────────────────────────────────────────────────
# Units: three line slots in f.txt (a slot holds one line or nothing), a file g.txt
# that exists (one line "G") or not, and an empty file e.txt that exists or not.
SLOTS = 3
TEXTS = ("A", "B", "C")
UNITS = tuple(range(SLOTS)) + ("g", "e")


def render(state):
    files = {"base.txt": "base\n"}
    body = []
    for i in range(SLOTS):
        body += ["-- slot %d %s --" % (i, x) for x in ("a", "b", "c")]
        if state[i] is not None:
            body.append(state[i])
    files["f.txt"] = "\n".join(body + ["-- end --"]) + "\n"
    if state["g"]:
        files["g.txt"] = "G\n"
    if state["e"]:
        files["e.txt"] = ""
    return files


def ops_from(state):
    """Every single-unit edit possible from `state`: (unit, from, to)."""
    out = []
    for i in range(SLOTS):
        for v in (None,) + TEXTS:
            if v != state[i]:
                out.append((i, state[i], v))
    for u in ("g", "e"):
        out.append((u, state[u], not state[u]))
    return out


def apply_strict(state, op):
    unit, frm, to = op
    if state[unit] != frm:
        return None
    new = dict(state)
    new[unit] = to
    return new


# ── Ground truth (SPEC.md, "Definition") ────────────────────────────────────
def oracle(mb, ops, S, main_before):
    """Expected (rc, orphans). R is main right after it received S (main_before
    when S is empty). A commit outside S is an orphan when an effect of it that the
    head still shows is not in R: the value it set, if the head still holds it, is
    missing from R; or the value it removed, if the head still lacks it, is in R."""
    head = dict(mb)
    for op in ops:
        head = apply_strict(head, op)
    R = dict(main_before)
    for k in sorted(S):
        R = apply_strict(R, ops[k])
        if R is None:
            return None   # main could not have received S as one squash
    present = lambda v: v not in (None, False)
    orphans = set()
    for k, (u, frm, to) in enumerate(ops):
        if k in S:
            continue
        set_missing = present(to) and head[u] == to and R[u] != to
        removal_missing = present(frm) and head[u] != frm and R[u] == frm
        if set_missing or removal_missing:
            orphans.add(k)
    return (3 if orphans else 0, frozenset(orphans))


# ── Building a history ──────────────────────────────────────────────────────
def fast_import_stream(mb, ops, S, main_op, after_op):
    out = []
    t = [1700000000]

    def commit(ref, mark, parent, msg, state):
        t[0] += 60
        out.append("commit %s\nmark :%d\ncommitter t <t@t.t> %d +0000\n" % (ref, mark, t[0]))
        m = msg.encode()
        out.append("data %d\n%s\n" % (len(m), msg))
        if parent:
            out.append("from :%d\n" % parent)
        out.append("deleteall\n")
        for path, content in sorted(render(state).items()):
            c = content.encode()
            out.append("M 100644 inline %s\ndata %d\n%s\n" % (path, len(c), content))
        out.append("\n")

    commit("refs/heads/main", 1, None, "mb", mb)
    state = dict(mb)
    for k, op in enumerate(ops):
        state = apply_strict(state, op)
        commit("refs/heads/feat", 10 + k, 1 if k == 0 else 9 + k, "b%d" % (k + 1), state)
    mstate = dict(mb)
    mstate_files = render(mstate)
    # main moves on: an unrelated file, then main's own edit, then the squash.
    out.append("commit refs/heads/main\nmark :2\ncommitter t <t@t.t> %d +0000\ndata 1\nu\nfrom :1\n" % (t[0] + 60))
    t[0] += 60
    out.append("deleteall\n")
    for path, content in sorted(mstate_files.items()):
        out.append("M 100644 inline %s\ndata %d\n%s\n" % (path, len(content.encode()), content))
    out.append("M 100644 inline u.txt\ndata 2\nu\n\n")
    last = 2

    def main_commit(mark, msg, st):
        nonlocal last
        t[0] += 60
        out.append("commit refs/heads/main\nmark :%d\ncommitter t <t@t.t> %d +0000\n" % (mark, t[0]))
        out.append("data %d\n%s\n" % (len(msg.encode()), msg))
        out.append("from :%d\n" % last)
        out.append("deleteall\n")
        for path, content in sorted(render(st).items()):
            out.append("M 100644 inline %s\ndata %d\n%s\n" % (path, len(content.encode()), content))
        out.append("M 100644 inline u.txt\ndata 2\nu\n\n")
        last = mark

    if main_op is not None:
        mstate = apply_strict(mstate, main_op)
        main_commit(3, "main own edit", mstate)
    R = dict(mstate)
    for k in sorted(S):
        R = apply_strict(R, ops[k])
    if S:
        main_commit(4, "squash", R)
    if after_op is not None:
        after = dict(R)
        after[after_op[0]] = after_op[2]
        main_commit(5, "main after landing", after)
    return "".join(out)


SUBJ = re.compile(r'^\s+[0-9a-f]+\s+"(b\d+)"')


def run_case(case):
    mb, ops, S, main_op, after_op, shim = case
    d = tempfile.mkdtemp(prefix="mcb-")
    try:
        env = dict(os.environ)
        subprocess.run(["git", "init", "-q", d], check=True, env=env)
        stream = fast_import_stream(mb, ops, S, main_op, after_op)
        subprocess.run(["git", "-C", d, "fast-import", "--quiet"], input=stream.encode(),
                       check=True, env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        if shim:
            env["PATH"] = shim + os.pathsep + env["PATH"]
        trace = os.path.join(d, ".trace")
        env["CHECK_MERGE_COMPLETENESS_TRACE"] = trace
        r = subprocess.run(["bash", HELPER, "--repo", d, "--branch", "feat", "--baseline", "main"],
                           capture_output=True, env=env)
        listed = frozenset(m.group(1) for m in map(SUBJ.match, r.stdout.decode("utf-8", "replace").splitlines()) if m)
        dash = subprocess.run(["git", "-C", d, "cherry", "main", "feat"], capture_output=True, text=True).stdout
        dashes = sum(1 for l in dash.splitlines() if l.startswith("-"))
        msgs = subprocess.run(["git", "-C", d, "log", "--format=%H %s", "main..feat"], capture_output=True, text=True).stdout
        minus = set()
        sha_subj = dict(l.split(" ", 1) for l in msgs.splitlines())
        for l in dash.splitlines():
            if l.startswith("- "):
                minus.add(sha_subj.get(l[2:], "?"))
        sides = {}
        if os.path.exists(trace):
            for l in open(trace):
                f = l.split()
                if f[0] == "side":
                    sides[sha_subj.get(f[1], "?")] = f[2]
        return (r.returncode, listed, frozenset(minus), r.stdout.decode("utf-8", "replace") + r.stderr.decode("utf-8", "replace"), sides)
    finally:
        shutil.rmtree(d, ignore_errors=True)


# ── Cases ───────────────────────────────────────────────────────────────────
MBS = (
    {0: "A", 1: None, 2: "B", "g": False, "e": False},
    {0: "A", 1: None, 2: "B", "g": True, "e": True},
)


def branches(mb, max_len):
    seqs = [[]]
    for n in range(1, max_len + 1):
        nxt = []
        for seq in seqs:
            st = dict(mb)
            for op in seq:
                st = apply_strict(st, op)
            for op in ops_from(st):
                nxt.append(seq + [op])
        for s in nxt:
            yield s
        seqs = nxt


def main_ops(mb, touched):
    yield None
    for u in UNITS:
        if u in touched:
            continue
        if u in ("g", "e"):
            yield (u, mb[u], not mb[u])
        else:
            for v in (None,) + TEXTS:
                if v != mb[u]:
                    yield (u, mb[u], v)


def after_ops(R, touched):
    for u in sorted(touched, key=str):
        if u in ("g", "e"):
            yield (u, R[u], not R[u])
        else:
            for v in (None,) + TEXTS:
                if v != R[u]:
                    yield (u, R[u], v)


def cases(args):
    out = []
    for mb in MBS:
        for ops in branches(mb, args.max_len):
            n = len(ops)
            touched = {op[0] for op in ops}
            for r in range(0, n + 1):
                for S in itertools.combinations(range(n), r):
                    for mop in main_ops(mb, touched):
                        before = dict(mb)
                        if mop is not None:
                            before = apply_strict(before, mop)
                        exp = oracle(mb, ops, set(S), before)
                        if exp is None:
                            continue
                        if not args.after:
                            out.append((mb, ops, frozenset(S), mop, None, exp))
                        elif S:
                            R = dict(before)
                            for k in S:
                                R = apply_strict(R, ops[k])
                            for aop in after_ops(R, touched):
                                out.append((mb, ops, frozenset(S), mop, aop, exp))
    return out


# ── Known deviations (SPEC.md, "Known deviations") ──────────────────────────
def tip_says_orphan(op, head, tip):
    """The helper's tip rule (SPEC.md D2) applied to the model: an added line or path
    the head has and the tip lacks, or a deleted one the head lacks and the tip has.
    Lines are compared by presence over f.txt; g.txt holds the line "G"."""
    unit, frm, to = op
    def lines(state):
        return {state[u] for u in range(SLOTS) if state[u] is not None}
    if unit == "g":
        return (head["g"] and not tip["g"]) if to else (not head["g"] and tip["g"])
    if unit == "e":
        return (head["e"] and not tip["e"]) if to else (not head["e"] and tip["e"])
    h, t = lines(head), lines(tip)
    added = to is not None and to in h and to not in t
    kept = frm is not None and frm not in h and frm in t
    return added or kept


def classify(case, exp, got, args, text, sides):
    """Name the SPEC.md deviation a disagreement belongs to, or None (a bug).
    A disagreement is known when every commit the two answers differ on was checked
    at the tip (D1) and the helper's answer for it is what the tip rule gives on the
    model's head and tip (D2). The rule is computed from the model, never taken from
    the helper's answer."""
    mb, ops, S, mop, aop = case
    rc, listed, minus = got
    erc, elisted = exp
    diff = (elisted - listed) | (listed - elisted)
    if not diff:
        return None
    head = dict(mb)
    for op in ops:
        head = apply_strict(head, op)
    tip = dict(mb)
    if mop is not None:
        tip = apply_strict(tip, mop)
    for k in sorted(S):
        tip = apply_strict(tip, ops[k])
    if aop is not None:
        tip = dict(tip)
        tip[aop[0]] = aop[2]
    def texts(op):
        unit, frm, to = op
        if unit in ("g", "e"):
            return {unit}
        return {frm, to} - {None}
    classes = set()
    for name in diff:
        k = int(name[1:]) - 1
        op = ops[k]
        if sides.get(name) == "tip":
            if tip_says_orphan(op, head, tip) != (name in listed):
                return None
            classes.add("D1+D2 tip check")
        elif sides.get(name) == "land" and name in listed:
            # D3: listed at the landing commit although it landed, when another branch
            # commit adds or removes the same text and the verdict is right.
            if rc != erc or not any(texts(op) & texts(o) for j, o in enumerate(ops) if j != k):
                return None
            classes.add("D3 shared text")
        elif sides.get(name) == "land":
            # B1, a listed blind spot: a commit that set its unit back to the merge-base
            # value, left out after an earlier commit already held the branch's net
            # change (the branch has no net change, so it lands at the merge-base).
            if op[2] != mb[op[0]] or not S or head != mb:
                return None
            classes.add("B1 restore to the merge-base")
        else:
            return None
    return "+".join(sorted(classes))


def describe(case, exp, got):
    mb, ops, S, mop, aop = case
    names = ["b%d" % (k + 1) for k in range(len(ops))]
    return ("mb=%s ops=%s S=%s main_op=%s after=%s expected=%s got=(rc %s, %s, cherry- %s)"
            % ({k: v for k, v in mb.items()}, [(names[k],) + op for k, op in enumerate(ops)],
               sorted(names[k] for k in S), mop, aop, (exp[0], sorted(exp[1])), got[0], sorted(got[1]), sorted(got[2])))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-len", type=int, default=2)
    ap.add_argument("--sample", type=int, default=0, help="run a random sample of this size (0 = all)")
    ap.add_argument("--seed", type=int, default=399)
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 2))
    ap.add_argument("--old-git", default="", help="a directory with a git shim that refuses merge-tree --write-tree")
    ap.add_argument("--after", action="store_true", help="add one main edit after the squash (out of scope by decision A)")
    ap.add_argument("--show", type=int, default=10)
    ap.add_argument("--dump", default="", help="write every unexplained case to this file, one JSON object per line")
    ap.add_argument("--reclassify", default="", help="classify the cases of a --dump file again, without running the helper")
    args = ap.parse_args()
    if args.reclassify:
        import json
        known = {}; bugs = []
        for line in open(args.reclassify):
            r = json.loads(line)
            mb = {(int(k) if k.isdigit() else k): v for k, v in r["mb"].items()}
            ops = [tuple(o) for o in r["ops"]]
            case = (mb, ops, frozenset(r["S"]), tuple(r["main_op"]) if r["main_op"] else None,
                    tuple(r["after"]) if r["after"] else None)
            exp = (r["expected"][0], frozenset(r["expected"][1]))
            got = (r["got"][0], frozenset(r["got"][1]), frozenset())
            sides = dict(re.findall(r"'(b\d+)': '(\w+)'", r["text"].split("sides=")[-1]))
            k = classify(case, exp, got, args, r["text"], sides)
            if k:
                known[k] = known.get(k, 0) + 1
            else:
                bugs.append((case, exp, got, r["text"]))
        print("reclassified: %d  known deviations: %s  unexplained: %d"
              % (sum(known.values()) + len(bugs), dict(sorted(known.items())) or "none", len(bugs)))
        for case, exp, got, text in bugs[: args.show]:
            print("  ✗ " + describe(case, exp, got))
            print("      | " + text.split("sides=")[-1].strip())
        return 1 if bugs else 0

    all_cases = cases(args)
    if args.sample and args.sample < len(all_cases):
        all_cases = random.Random(args.seed).sample(all_cases, args.sample)
    work = [(c[0], c[1], c[2], c[3], c[4], args.old_git) for c in all_cases]
    with mp.Pool(args.jobs) as pool:
        results = pool.map(run_case, work, chunksize=8)

    ok = 0; known = {}; bugs = []
    for c, res in zip(all_cases, results):
        mb, ops, S, mop, aop, exp = c
        rc, listed, minus, text, sides = res
        names = {"b%d" % (k + 1) for k in exp[1]}
        exp_named = (exp[0], frozenset(names) - minus)
        if rc == exp_named[0] and (rc != 3 or listed == exp_named[1]):
            ok += 1
            continue
        k = classify((mb, ops, S, mop, aop), exp_named, (rc, listed, minus), args, text, sides)
        if k:
            known[k] = known.get(k, 0) + 1
        else:
            bugs.append(((mb, ops, S, mop, aop), exp_named, (rc, listed, minus), text + " sides=%s" % sides))
    print("cases: %d  agree: %d  known deviations: %s  unexplained: %d"
          % (len(all_cases), ok, dict(sorted(known.items())) or "none", len(bugs)))
    if args.dump:
        import json
        with open(args.dump, "w") as f:
            for case, exp, got, text in bugs:
                mb, ops, S, mop, aop = case
                f.write(json.dumps({"mb": {str(k): v for k, v in mb.items()}, "ops": ops, "S": sorted(S),
                                    "main_op": mop, "after": aop, "expected": [exp[0], sorted(exp[1])],
                                    "got": [got[0], sorted(got[1])], "text": text}) + "\n")
    for case, exp, got, text in bugs[: args.show]:
        print("  ✗ " + describe(case, exp, got))
        for line in text.splitlines()[-3:]:
            print("      | " + line)
    return 1 if bugs else 0


if __name__ == "__main__":
    sys.exit(main())
