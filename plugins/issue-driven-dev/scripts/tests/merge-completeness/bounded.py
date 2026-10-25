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
def oracle(mb, ops, S, main_before, extra=None):
    """Expected (rc, orphans). R is main right after it received S (main_before
    when S is empty), including an edit of its own made in the same step (extra).
    A commit outside S is an orphan when an effect of it that the head still shows
    is not in R: the value it set, if the head still holds it, is missing from R;
    or the value it removed, if the head still lacks it, is in R."""
    head = dict(mb)
    for op in ops:
        head = apply_strict(head, op)
    R = dict(main_before)
    for k in sorted(S):
        R = apply_strict(R, ops[k])
        if R is None:
            return None   # main could not have received S as one squash
    if extra is not None:
        R = apply_strict(R, extra)
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
def fast_import_stream(mb, ops, S, main_op, after_op, extra=None, landing="plain"):
    """main: mb, an unrelated commit u, main's own edit (main_op), then S lands:
    plain  one squash commit holding exactly main_before + S;
    own    one squash commit that also carries an edit of main's own (extra);
    merge  S is squashed on a side branch, another PR's edit (extra) follows it
           there, main makes an unrelated commit u2 and merges the side branch
           (a release merge, or the merge `git pull` makes).
    after_op is one more main edit after landing (out of scope by decision A)."""
    out = []
    t = [1700000000]

    def emit(ref, mark, parents, msg, st, utext=None):
        t[0] += 60
        out.append("commit %s\nmark :%d\ncommitter t <t@t.t> %d +0000\n" % (ref, mark, t[0]))
        out.append("data %d\n%s\n" % (len(msg.encode()), msg))
        if parents:
            out.append("from :%d\n" % parents[0])
            for p in parents[1:]:
                out.append("merge :%d\n" % p)
        out.append("deleteall\n")
        files = render(st)
        if utext is not None:
            files["u.txt"] = utext
        for path, content in sorted(files.items()):
            c = content.encode()
            out.append("M 100644 inline %s\ndata %d\n%s\n" % (path, len(c), content))
        out.append("\n")

    emit("refs/heads/main", 1, None, "mb", mb)
    state = dict(mb)
    for k, op in enumerate(ops):
        state = apply_strict(state, op)
        emit("refs/heads/feat", 10 + k, [1 if k == 0 else 9 + k], "b%d" % (k + 1), state)
    utext = "u\n"
    emit("refs/heads/main", 2, [1], "u", mb, utext)
    last = 2
    mstate = dict(mb)
    if main_op is not None:
        mstate = apply_strict(mstate, main_op)
        emit("refs/heads/main", 3, [last], "main own edit", mstate, utext)
        last = 3
    RS = dict(mstate)
    for k in sorted(S):
        RS = apply_strict(RS, ops[k])
    R = apply_strict(dict(RS), extra) if extra is not None else RS
    if S and landing in ("plain", "own"):
        emit("refs/heads/main", 4, [last], "squash", R, utext)
        last = 4
    elif S and landing == "merge":
        emit("refs/heads/dev", 4, [last], "squash", RS, utext)
        side = 4
        if extra is not None:
            emit("refs/heads/dev", 6, [4], "another PR", R, utext)
            side = 6
        utext = "u\nu2\n"
        emit("refs/heads/main", 7, [last], "u2", mstate, utext)
        emit("refs/heads/main", 8, [7, side], "merge dev", R, utext)
        last = 8
    if after_op is not None:
        after = dict(R)
        after[after_op[0]] = after_op[2]
        emit("refs/heads/main", 5, [last], "main after landing", after, utext)
    return "".join(out)


SUBJ = re.compile(r'^\s+[0-9a-f]+\s+"(b\d+)"')


def run_case(case):
    mb, ops, S, main_op, after_op, extra, landing, shim = case
    d = tempfile.mkdtemp(prefix="mcb-")
    try:
        env = dict(os.environ)
        subprocess.run(["git", "init", "-q", d], check=True, env=env)
        stream = fast_import_stream(mb, ops, S, main_op, after_op, extra, landing)
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


def extra_ops(before, touched, mop):
    """An edit of main's own in the landing step: a unit the branch does not touch
    and main's earlier edit did not touch either."""
    for u in UNITS:
        if u in touched or (mop is not None and u == mop[0]):
            continue
        if u in ("g", "e"):
            yield (u, before[u], not before[u])
        else:
            for v in (None,) + TEXTS:
                if v != before[u]:
                    yield (u, before[u], v)


def cases(args):
    out = []
    for mb in MBS:
        for ops in branches(mb, args.max_len):
            n = len(ops)
            touched = {op[0] for op in ops}
            for r in range(0, n + 1):
                for S in itertools.combinations(range(n), r):
                    if args.landing != "plain" and not S:
                        continue
                    for mop in main_ops(mb, touched):
                        before = dict(mb)
                        if mop is not None:
                            before = apply_strict(before, mop)
                        if args.landing == "plain":
                            extras = [None]
                        elif args.landing == "own":
                            extras = list(extra_ops(before, touched, mop))
                        else:
                            extras = [None] + list(extra_ops(before, touched, mop))
                        for extra in extras:
                            exp = oracle(mb, ops, set(S), before, extra)
                            if exp is None:
                                continue
                            if not args.after:
                                out.append((mb, ops, frozenset(S), mop, None, extra, args.landing, exp))
                            elif S:
                                R = dict(before)
                                for k in S:
                                    R = apply_strict(R, ops[k])
                                if extra is not None:
                                    R = apply_strict(R, extra)
                                for aop in after_ops(R, touched):
                                    out.append((mb, ops, frozenset(S), mop, aop, extra, args.landing, exp))
    return out


# ── Where the helper checks each commit (SPEC.md, D1) ───────────────────────
def path_of(u):
    return "f" if isinstance(u, int) else u


def model_sides(mb, ops, S, mop, aop, extra, landing, minus, old_git):
    """Where the documented landing algorithm checks each candidate, computed on
    the model: 'land' or 'tip' per branch commit not matched by git cherry. Also
    returns whether a prefix landed after the whole branch landed at the
    merge-base (the B1 condition). Mirrors the helper's header, step 2."""
    n = len(ops)
    states = [dict(mb)]
    for op in ops:
        states.append(apply_strict(states[-1], op))
    head = states[-1]
    before = apply_strict(dict(mb), mop) if mop is not None else dict(mb)
    RS = dict(before)
    for k in sorted(S):
        RS = apply_strict(RS, ops[k])
    R = apply_strict(dict(RS), extra) if extra is not None else RS
    # main's first-parent commits after the merge-base: (state, paths it touched)
    def touched(a, b):
        return {path_of(u) for u in UNITS if a[u] != b[u]}
    seq = [(dict(mb), {"u"})]
    if mop is not None:
        seq.append((before, touched(mb, before)))
    if S and landing in ("plain", "own"):
        seq.append((R, touched(before, R)))
    elif S and landing == "merge":
        seq.append((before, {"u"}))
        seq.append((R, touched(before, R)))
    if aop is not None:
        after = dict(R)
        after[aop[0]] = aop[2]
        seq.append((after, touched(R, after)))

    def holds(c, ref):
        return all(c[u] == ref[u] for u in UNITS if ref[u] != mb[u])

    def find_landing(ref):
        if holds(mb, ref):
            return "mb"
        net = {path_of(u) for u in UNITS if ref[u] != mb[u]}
        for i, (st, paths) in enumerate(seq):
            if i > 0 and not (paths & net):
                continue
            if holds(st, ref):
                return i
        return None

    def prefix_search():
        for k in range(n - 1, 0, -1)[:20]:
            lk = find_landing(states[k])
            if lk == "mb" or lk is None:
                continue
            return lk, k
        return None, None

    L, prefix, later = (None, None, False)
    if not old_git:
        L = find_landing(head)
        if L is None:
            L, prefix = prefix_search()
        elif L == "mb":
            pl, pk = prefix_search()
            if pl is not None:
                L, prefix, later = pl, pk, True
        if L == "mb" and minus:
            L = None
        if L is not None and L != "mb":
            prev = seq[L - 1][0] if L > 0 else mb
            ref = states[prefix] if prefix else head
            if any(prev[u] != mb[u] and ref[u] != mb[u] and prev[u] != ref[u] for u in UNITS):
                L, prefix = None, None
    sides = {}
    for k in range(n):
        name = "b%d" % (k + 1)
        if name in minus:
            continue
        sides[name] = "land" if L is not None and (prefix is None or k + 1 <= prefix) else "tip"
    land_state = None
    if L == "mb":
        land_state = dict(mb)
    elif L is not None:
        land_state = seq[L][0]
    return sides, later, land_state


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
    Nothing here is taken from the helper's own answer: where each commit is
    checked comes from the model of the landing algorithm (model_sides), and a
    trace that disagrees with it is a bug in the landing step, whatever the list
    says. Then every commit the two answers differ on must fall in one class:
    checked at the tip, and the tip rule (D2) computed on the model's head and tip
    gives the helper's answer (D1+D2); checked at the landing commit, listed,
    sharing a text with another branch commit, with the right verdict (D3);
    checked at the landing commit while the landing step carried an edit of main's
    own (own, merge) touching a text the commit added or removed, where that text
    is not in the landed part's net change on the same side, so the helper counts
    it (D4); or checked at the landing commit, missed, and B1 holds in the model."""
    mb, ops, S, mop, aop, extra, landing = case
    rc, listed, minus = got
    erc, elisted = exp
    if rc not in (0, 3):
        return None
    want, later, land_state = model_sides(mb, ops, S, mop, aop, extra, landing, minus, bool(args.old_git))
    if any(sides.get(name) != side for name, side in want.items()):
        return None
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
    if extra is not None:
        tip = apply_strict(tip, extra)
    if aop is not None:
        tip = dict(tip)
        tip[aop[0]] = aop[2]
    def texts(op):
        unit, frm, to = op
        if unit in ("g", "e"):
            return {unit}
        return {frm, to} - {None}
    # At the landing commit the helper checks each commit in its own place: undoing
    # it changes the head (for a one-unit edit, the head no longer holds the value
    # from before it) and changes nothing on the landing commit (which still holds
    # that value). That is the helper's answer for every commit checked there.
    def placed_orphan(op):
        unit, frm, to = op
        return land_state is not None and land_state[unit] == frm and head[unit] != frm
    classes = set()
    for name in diff:
        k = int(name[1:]) - 1
        op = ops[k]
        side = want.get(name)
        if side == "land" and (name in listed) != placed_orphan(op):
            return None
        if side == "tip":
            if tip_says_orphan(op, head, tip) != (name in listed):
                return None
            classes.add("D1+D2 tip check")
        elif side == "land" and name in listed:
            if rc != erc:
                return None
            classes.add("D3 its place, not its value")
        elif side == "land":
            if op[2] != mb[op[0]] or not S or head != mb or later:
                return None
            classes.add("B1 restore to the merge-base")
        else:
            return None
    return "+".join(sorted(classes))


def describe(case, exp, got):
    mb, ops, S, mop, aop, extra, landing = case
    names = ["b%d" % (k + 1) for k in range(len(ops))]
    return ("mb=%s ops=%s S=%s main_op=%s landing=%s extra=%s after=%s expected=%s got=(rc %s, %s, cherry- %s)"
            % ({k: v for k, v in mb.items()}, [(names[k],) + op for k, op in enumerate(ops)],
               sorted(names[k] for k in S), mop, landing, extra, aop, (exp[0], sorted(exp[1])),
               got[0], sorted(got[1]), sorted(got[2])))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-len", type=int, default=2)
    ap.add_argument("--sample", type=int, default=0, help="run a random sample of this size (0 = all)")
    ap.add_argument("--seed", type=int, default=399)
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 2))
    ap.add_argument("--old-git", default="", help="a directory with a git shim that refuses merge-tree --write-tree")
    ap.add_argument("--after", action="store_true", help="add one main edit after the squash (out of scope by decision A)")
    ap.add_argument("--landing", choices=("plain", "own", "merge"), default="plain",
                    help="how main receives S: one squash (plain), a squash with an edit of main's own (own), "
                         "or a merge of a side branch holding the squash and another PR's edit (merge)")
    ap.add_argument("--show", type=int, default=10)
    ap.add_argument("--dump", default="", help="write every unexplained case to this file, one JSON object per line")
    ap.add_argument("--reclassify", default="", help="classify the cases of a --dump file again, without running the helper")
    args = ap.parse_args()

    def tup(v):
        return tuple(v) if v else None

    if args.reclassify:
        import json
        known = {}; bugs = []
        for line in open(args.reclassify):
            r = json.loads(line)
            mb = {(int(k) if k.isdigit() else k): v for k, v in r["mb"].items()}
            ops = [tuple(o) for o in r["ops"]]
            case = (mb, ops, frozenset(r["S"]), tup(r["main_op"]), tup(r["after"]),
                    tup(r.get("extra")), r.get("landing", "plain"))
            exp = (r["expected"][0], frozenset(r["expected"][1]))
            got = (r["got"][0], frozenset(r["got"][1]), frozenset(r.get("minus", [])))
            k = classify(case, exp, got, args, r["text"], r.get("sides", {}))
            if k:
                known[k] = known.get(k, 0) + 1
            else:
                bugs.append((case, exp, got, r["text"]))
        print("reclassified: %d  known deviations: %s  unexplained: %d"
              % (sum(known.values()) + len(bugs), dict(sorted(known.items())) or "none", len(bugs)))
        for case, exp, got, text in bugs[: args.show]:
            print("  ✗ " + describe(case, exp, got))
        return 1 if bugs else 0

    all_cases = cases(args)
    if args.sample and args.sample < len(all_cases):
        all_cases = random.Random(args.seed).sample(all_cases, args.sample)
    work = [(c[0], c[1], c[2], c[3], c[4], c[5], c[6], args.old_git) for c in all_cases]
    with mp.Pool(args.jobs) as pool:
        results = pool.map(run_case, work, chunksize=8)

    ok = 0; known = {}; bugs = []; wrong = {}
    for c, res in zip(all_cases, results):
        mb, ops, S, mop, aop, extra, landing, exp = c
        rc, listed, minus, text, sides = res
        names = frozenset("b%d" % (k + 1) for k in exp[1]) - minus
        exp_named = (3 if names else 0, names)
        if rc == exp_named[0] and (rc != 3 or listed == exp_named[1]):
            ok += 1
            continue
        case = (mb, ops, S, mop, aop, extra, landing)
        k = classify(case, exp_named, (rc, listed, minus), args, text, sides)
        if k:
            known[k] = known.get(k, 0) + 1
            if rc != exp_named[0]:
                key = "%s (%d->%d)" % (k, exp_named[0], rc)
                wrong[key] = wrong.get(key, 0) + 1
        else:
            bugs.append((case, exp_named, (rc, listed, minus), text, sides))
    print("cases: %d  agree: %d  known deviations: %s  unexplained: %d"
          % (len(all_cases), ok, dict(sorted(known.items())) or "none", len(bugs)))
    print("wrong verdict among known deviations: %s" % (dict(sorted(wrong.items())) or "none"))
    # Coverage: a run whose cases never reach the landing commit (every candidate
    # matched by git cherry, or checked at the tip) says nothing about that step.
    print("cases with a commit checked at a landing commit: %d"
          % sum(1 for res in results if "land" in res[4].values()))
    if args.dump:
        import json
        with open(args.dump, "w") as f:
            for case, exp, got, text, sides in bugs:
                mb, ops, S, mop, aop, extra, landing = case
                f.write(json.dumps({"mb": {str(k): v for k, v in mb.items()}, "ops": ops, "S": sorted(S),
                                    "main_op": mop, "after": aop, "extra": extra, "landing": landing,
                                    "expected": [exp[0], sorted(exp[1])], "got": [got[0], sorted(got[1])],
                                    "minus": sorted(got[2]), "sides": sides, "text": text}) + "\n")
    for case, exp, got, text, sides in bugs[: args.show]:
        print("  ✗ " + describe(case, exp, got))
        print("      | sides=%s" % sides)
        for line in text.splitlines()[-2:]:
            print("      | " + line)
    return 1 if bugs else 0


if __name__ == "__main__":
    sys.exit(main())
