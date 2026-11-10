#!/usr/bin/env python3
"""The small world of bounded.py with a branch that lands twice, merging main in between.

#399 verify round 19 (devil's advocate): a branch lands as a first PR (a squash of all its
commits so far), the author presses GitHub's Update branch (the branch merges main), goes
on, and main squashes the branch again as a second PR. Main may edit the first PR's lines
after the merge and before the second PR (#399's own shape: a follow-up). Every round up to
19 and 3.5.0 listed the first PR's commits then, because after the merge the merge-base
already holds them, the second PR is where the whole branch landed, and their lines are no
longer in place there. bounded.py never merged main into the branch.

The world (SPEC.md, "The small world"): the same units and merge-bases; the branch is every
sequence of 1 to N single-unit edits, split into a first part (at least one commit) and the
rest. Main makes an unrelated commit and squashes S1, any subset of the first part that
applies in order (PR1: all of it, its first commits with the rest pushed before the merge, or
a squash that left some out; round 21); with --pre-edit (round 22) main then edits a unit PR1
changed; the branch merges main (the branch's side kept where the two differ), makes the rest
of its commits, main optionally edits a unit PR1 changed (the follow-up), and then squashes
S2: when PR1 took the whole first part, any subset of the rest that applies in order, else the
whole rest (PR2; none: no second PR).

The answer is the Definition's, for a landing in several steps: the first part is received by
PR1; the branch landed at the first step after which main holds the head's net change (from
the merge-base, which after the merge is main at PR1); R is main right after it. P0 comes
first. Only the answers are compared (exit code and list): where the helper checks each
commit is not modelled here.

Usage: bounded_sync.py [--max-len N] [--jobs J] [--sample K --seed S] [--show K]
                       [--empty-first | --new-shapes | --pre-edit]
Exit 0 when every case agrees or is a documented deviation (printed by class).
"""
import argparse
import itertools
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import bounded as W  # noqa: E402  (the world: units, rendering, edits)

HELPER = os.environ.get("BOUNDED_HELPER") or os.path.join(HERE, "..", "..", "check-merge-completeness.sh")
SUBJ = re.compile(r'^\s+[0-9a-f]+\s+"(b\d+)"')


def apply_all(state, ops):
    for op in ops:
        state = W.apply_strict(state, op)
        if state is None:
            return None
    return state


def compose(mb, ops, S):
    st = dict(mb)
    for k in sorted(S):
        st = W.apply_strict(st, ops[k])
        if st is None:
            return None
    return st


def fu_options(M, units):
    """main's edits of the given units: each to another value (or away and back for g, e)."""
    fus = []
    for u in sorted(units, key=str):
        if u in ("g", "e"):
            fus.append((u, M[u], not M[u]))
        else:
            fus += [(u, M[u], v) for v in (None,) + W.TEXTS if v != M[u]]
    return fus


def cases(max_len, pre_edit=False):
    """(mb, ops, j, S1, fu, S2, pre): the branch merges main after its first j commits; PR1
    is a squash of S1, any subset of those j that applies in order (all of them, or the
    first i with the rest pushed after PR1 and before the merge, or a squash that left some
    out); pre (only with pre_edit, round 22) is main's edit of a unit PR1 changed, after PR1
    and before the merge; the merge keeps the branch's side where the two differ; fu is
    main's edit of a unit PR1 changed, after the merge; S2 is what PR2 brings: none, or,
    when PR1 took the whole first part, any subset of the commits after the merge that
    applies in order, and otherwise the whole rest of the branch (a squash of the head)."""
    out = []
    for mb in W.MBS:
        for ops in W.branches(mb, max_len):
            n = len(ops)
            for j in range(1, n + 1):
                p1head = apply_all(dict(mb), ops[:j])
                for r1 in range(1, j + 1):
                    for S1 in itertools.combinations(range(j), r1):
                        n1 = compose(mb, ops, S1)
                        if n1 is None:
                            continue
                        M1 = W.land(dict(mb), mb, n1)
                        touched1 = {e[0] for k in S1 for e in W.edits(ops[k])}
                        for pre in (fu_options(M1, touched1) if pre_edit else [None]):
                            M1p = W.apply_strict(dict(M1), pre) if pre else M1
                            Mg = W.land(dict(M1p), mb, p1head)
                            head = apply_all(dict(Mg), ops[j:])
                            if head is None:
                                continue
                            fus = [None] + fu_options(M1p, touched1)
                            full = set(S1) == set(range(j))
                            if full:
                                rest = list(range(j, n))
                                S2s = [frozenset(c) for r in range(0, len(rest) + 1) for c in itertools.combinations(rest, r)
                                       if compose(Mg, ops, c) is not None]
                            else:
                                S2s = [frozenset(), frozenset(set(range(n)) - set(S1))]
                            for fu in fus:
                                for S2 in S2s:
                                    out.append((mb, tuple(ops), j, frozenset(S1), fu, S2, pre))
    return out


def model(case):
    """(head, M1, steps, tip, M1p): M1 is main right after PR1, M1p main when the branch
    merges it (M1, or M1 with main's edit before the merge); steps are main's states right
    after each PR."""
    mb, ops, j, S1, fu, S2, pre = case
    p1head = apply_all(dict(mb), ops[:j])
    M1 = W.land(dict(mb), mb, compose(mb, ops, S1))
    M1p = W.apply_strict(dict(M1), pre) if pre else M1
    Mg = W.land(dict(M1p), mb, p1head)
    head = apply_all(dict(Mg), ops[j:])
    pre2 = W.apply_strict(dict(M1p), fu) if fu else dict(M1p)
    steps = [M1]
    tip = pre2
    if S2:
        if set(S2) | set(S1) == set(range(len(ops))):
            net2 = head
        else:
            net2 = compose(Mg, ops, S2)
        tip = W.land(pre2, M1p, net2)
        steps.append(tip)
    return head, M1, steps, tip, M1p


def oracle(case, minus):
    mb, ops, j, S1, fu, S2, pre = case
    head, M1, steps, tip, M1p = model(case)
    cands = [k for k in range(len(ops)) if "b%d" % (k + 1) not in minus]
    if not cands:
        return (0, frozenset())
    # P0: on every path a candidate touched, the tip has exactly what the head has
    paths = {W.path_of(e[0]) for k in cands for e in W.edits(ops[k])}
    if all(head[u] == tip[u] for u in W.UNITS if W.path_of(u) in paths):
        return (0, frozenset())
    # the branch landed at the first step after which main holds the head's net change
    # from the merge-base (main when the branch merged it)

    def holds_net(st):
        return all((st[u] == head[u]) if head[u] not in (None, False) else (st[u] != M1p[u])
                   for u in W.UNITS if head[u] != M1p[u])
    # (none holds it: main right after the last step, as bounded.py's oracle does)
    first = next((i for i, st in enumerate(steps[:-1]) if holds_net(st)), len(steps) - 1)
    R = steps[first]
    S = set(S1) | (set(S2) if first == 1 else set())
    present = lambda v: v not in (None, False)  # noqa: E731
    orphans = set()
    for k, op in enumerate(ops):
        if k in S or "b%d" % (k + 1) in minus:
            continue
        for u, frm, to in W.edits(op):
            if (present(to) and head[u] == to and R[u] != to) or (present(frm) and head[u] != frm and R[u] == frm):
                orphans.add(k)
    return (3 if orphans else 0, frozenset("b%d" % (k + 1) for k in orphans))


def stream(case):
    mb, ops, j, S1, fu, S2, pre = case
    head, M1, steps, tip, M1p = model(case)
    p1head = apply_all(dict(mb), ops[:j])
    Mg = W.land(dict(M1p), mb, p1head)
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
        files = W.render(st)
        if utext is not None:
            files["u.txt"] = utext
        for path, content in sorted(files.items()):
            out.append("M 100644 inline %s\ndata %d\n%s\n" % (path, len(content.encode()), content))
        out.append("\n")

    emit("refs/heads/main", 1, None, "mb", mb)
    st = dict(mb)
    last = 1
    for k in range(j):
        st = W.apply_strict(st, ops[k])
        emit("refs/heads/feat", 10 + k, [last], "b%d" % (k + 1), st)
        last = 10 + k
    emit("refs/heads/main", 2, [1], "u", mb, "u\n")
    emit("refs/heads/main", 3, [2], "PR1", M1, "u\n")
    mlast = 3
    if pre:
        emit("refs/heads/main", 7, [3], "pre-merge edit", M1p, "u\n")
        mlast = 7
    emit("refs/heads/feat", 4, [last, mlast], "Merge main into feat", Mg, "u\n")
    last = 4
    st = dict(Mg)
    for k in range(j, len(ops)):
        st = W.apply_strict(st, ops[k])
        emit("refs/heads/feat", 10 + k, [last], "b%d" % (k + 1), st, "u\n")
        last = 10 + k
    if fu:
        emit("refs/heads/main", 5, [mlast], "follow-up", W.apply_strict(dict(M1p), fu), "u\n")
        mlast = 5
    if S2:
        emit("refs/heads/main", 6, [mlast], "PR2", tip, "u\n")
    return "".join(out)


def run_case(case):
    d = tempfile.mkdtemp(prefix="mcs-")
    try:
        subprocess.run(["git", "init", "-q", d], check=True)
        subprocess.run(["git", "-C", d, "fast-import", "--quiet"], input=stream(case).encode(), check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        env = dict(os.environ)
        trace = os.path.join(d, ".trace")
        env["CHECK_MERGE_COMPLETENESS_TRACE"] = trace
        r = subprocess.run(["bash", HELPER, "--repo", d, "--branch", "feat", "--baseline", "main"],
                           capture_output=True, env=env)
        listed = frozenset(m.group(1) for m in map(SUBJ.match, r.stdout.decode("utf-8", "replace").splitlines()) if m)
        dash = subprocess.run(["git", "-C", d, "cherry", "main", "feat"], capture_output=True, text=True).stdout
        msgs = subprocess.run(["git", "-C", d, "log", "--format=%H %s", "--all"], capture_output=True, text=True).stdout
        sha_subj = dict(l.split(" ", 1) for l in msgs.splitlines())
        minus = frozenset(sha_subj.get(l[2:], "?") for l in dash.splitlines() if l.startswith("- "))
        text = r.stdout.decode("utf-8", "replace") + r.stderr.decode("utf-8", "replace")
        sides = {}
        if os.path.exists(trace):
            for l in open(trace):
                f = l.split()
                if f and f[0] == "side":
                    sides[sha_subj.get(f[1], "?")] = f[2]
                elif f and f[0] == "landing":
                    sides["@landing"] = sha_subj.get(f[1], f[1])
        return r.returncode, listed, minus, text, sides
    finally:
        shutil.rmtree(d, ignore_errors=True)


def classify(case, exp, got, sides):
    """The SPEC.md deviation every differing commit belongs to, or None (a bug): D1+D2, a
    commit checked at the tip (one of the second part that PR2 did not bring, or any commit
    when the first part changes nothing) where the tip rule (D2) computed on the model's head
    and tip gives the helper's answer; B2, a commit checked at a commit of main's own (the
    follow-up, or the edit before the merge) taken as the landing commit, with its effects in
    place there."""
    mb, ops, j, S1, fu, S2, pre = case
    rc, listed = got
    if rc not in (0, 3):
        return None
    head, M1, steps, tip, M1p = model(case)
    present = lambda v: v not in (None, False)  # noqa: E731
    # D1's cause for a commit of the first part at the tip: the first part changes nothing
    # (a branch with no net change lands at the merge-base, and the commits after a prefix
    # that landed later, here in main's own follow-up, are checked at the tip)
    empty_first = all(M1[u] == mb[u] for u in W.UNITS)
    # (round 22) or the branch has no net change after the merge: main's edit before the
    # merge made the head's values itself, so the branch lands at the merge-base
    no_net = all(head[u] == M1p[u] for u in W.UNITS)
    # and D1's other causes: a commit main never received, or what main received is not a
    # prefix of the branch (a squash that left some out)
    received = set(S1) | set(S2)
    not_prefix = received != set(range(len(received)))
    classes = set()
    for name in (exp[1] - listed) | (listed - exp[1]):
        k = int(name[1:]) - 1
        if sides.get(name) == "tip" and (k not in received or not_prefix or empty_first or no_net):
            if W.tip_says_orphan(ops[k], head, tip) != (name in listed):
                return None
            classes.add("D1+D2 tip check")
        elif sides.get(name) == "land" and name not in listed and (
                (sides.get("@landing") in ("follow-up", "pre-merge edit")
                 and holds_at(ops[k], head, W.apply_strict(dict(M1p), fu) if sides.get("@landing") == "follow-up" else M1p))
                or (pre and k < j and holds_at(ops[k], head, M1p, exact=True))):
            # B2: a commit of main's own holds the commit's effects and counts as where it
            # landed: the follow-up or the edit before the merge taken as the landing commit
            # (an added text may be in place elsewhere in the file there: main put the same
            # text there itself, the header's blind spot), or (round 22) a commit before the
            # merge checked again at the merged main commit, where main's own edit before the
            # merge holds its effects
            classes.add("B2 main's own commit holds the net change")
        else:
            return None
    return " + ".join(sorted(classes))


def holds_at(op, head, st, exact=False):
    """The commit's effects the head shows are in place in st: an added value where it was put
    (or, unless exact, anywhere in the same file: a slot's text), a deleted one no longer there."""
    present = lambda v: v not in (None, False)  # noqa: E731
    for u, frm, to in W.edits(op):
        if present(to) and head[u] == to and st[u] != to:
            if exact or isinstance(to, bool) or to not in {st[v] for v in W.UNITS if W.path_of(v) == W.path_of(u)}:
                return False
        if present(frm) and head[u] != frm and st[u] == frm:
            return False
    return True


def describe(case):
    mb, ops, j, S1, fu, S2, pre = case
    fmt = lambda op: "%s:%s->%s" % op  # noqa: E731
    return "mb=%s first=[%s] PR1=%s pre-merge=%s rest=[%s] follow-up=%s PR2=%s" % (
        "+ge" if mb["g"] else "-ge", ", ".join(fmt(o) for o in ops[:j]), sorted("b%d" % (k + 1) for k in S1),
        fmt(pre) if pre else "-", ", ".join(fmt(o) for o in ops[j:]), fmt(fu) if fu else "-",
        sorted("b%d" % (k + 1) for k in S2) or "none")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max-len", type=int, default=2)
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) // 2))
    ap.add_argument("--sample", type=int, default=0)
    ap.add_argument("--seed", type=int, default=399)
    ap.add_argument("--show", type=int, default=10)
    ap.add_argument("--empty-first", action="store_true", help="only the cases whose first PR changes nothing")
    ap.add_argument("--new-shapes", action="store_true",
                    help="only the cases round 21 added: PR1 not the whole first part")
    ap.add_argument("--pre-edit", action="store_true",
                    help="only the cases round 22 added: main edits a unit PR1 changed before the merge")
    args = ap.parse_args()
    all_cases = cases(args.max_len, args.pre_edit)
    if args.empty_first:
        all_cases = [c for c in all_cases if all(model(c)[1][u] == c[0][u] for u in W.UNITS)]
    if args.new_shapes:
        all_cases = [c for c in all_cases if set(c[3]) != set(range(c[2]))]
    if args.sample and args.sample < len(all_cases):
        all_cases = random.Random(args.seed).sample(all_cases, args.sample)
    import multiprocessing
    with multiprocessing.Pool(args.jobs) as pool:
        results = pool.map(run_case, all_cases, chunksize=4)
    ok, bad, known = 0, [], {}
    for case, (rc, listed, minus, text, sides) in zip(all_cases, results):
        exp = oracle(case, minus)
        if (rc, listed) == exp:
            ok += 1
            continue
        cls = classify(case, exp, (rc, listed), sides)
        if cls:
            known[cls] = known.get(cls, 0) + 1
        else:
            bad.append((case, exp, (rc, listed), text))
    print("cases: %d  agree: %d  known deviations: %s  unexplained: %d"
          % (len(all_cases), ok, dict(sorted(known.items())) or "none", len(bad)))
    for case, exp, got, text in bad[: args.show]:
        print("  ✗ %s\n      expected %s %s, got %s %s" % (describe(case), exp[0], sorted(exp[1]), got[0], sorted(got[1])))
        for line in text.splitlines()[-2:]:
            print("      | " + line)
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
