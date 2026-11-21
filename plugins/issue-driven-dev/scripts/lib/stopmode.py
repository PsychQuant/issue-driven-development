"""stopmode.py — when /idd-all's fix loop stops, and whether that stop merges (#595).

`decide(state)` reads only the run-state record that close-stage.py keeps: the stop
mode (`verify_stop`), the round record (`rounds`, one entry per verify report the
gate read) and the latest gate result (`last_gate`). It never asks GitHub and never
reads the model's memory, so the same record always gives the same answer.

The table (openspec idd-pr-hitl-modes, "A configured stop mode decides when the fix
loop stops and whether the run merges"):

  early                stop when the to-fix count is 0, or, from round 2 on, it is
                       not lower than the previous round's; merge when Blocking is 0
  exhaustive-blocking  stop when Blocking is 0 (merge), or when Blocking was not lower
                       than the round before in each of the last two rounds (no merge)
  exhaustive-all       stop when Blocking and In-scope fix (LOW included) are 0; merge
  no mode              2 rounds unattended, 1 attended (a round is a verify attempt, one per HEAD
                       the gate judged); merge only a clean round within the limit

The to-fix count is what the loop fixes: Blocking plus the In-scope fix findings above
LOW. A run with --review or --in-chain fixes Blocking only and never merges, so its
count is Blocking.
"""

MODES = ("early", "exhaustive-blocking", "exhaustive-all")
NO_MODE_ROUNDS = {"unattended": 2, "attended": 1}


def to_fix(r, blocking_only):
    if blocking_only:
        return r["blocking"]
    return r["blocking"] + r["in_scope"] - (r.get("low_in_scope") or 0)


def _brief(r, blocking_only=False):
    out = {k: r.get(k) for k in ("round", "sha", "status", "blocking", "in_scope", "low_in_scope", "report_id")}
    out["to_fix"] = to_fix(r, blocking_only) if _counted(r) else None     # Phase 6 lists it per round
    return out


def _answer(decision, merge, reason, mode, rounds, blocking_only=False, **extra):
    return dict({"decision": decision, "merge": merge, "reason": reason, "mode": mode,
                 "rounds": [_brief(r, blocking_only) for r in rounds]}, **extra)


def _counted(r):
    return all(isinstance(r.get(k), int) for k in ("blocking", "in_scope"))


def _no_mode(st):
    """Without a stop mode: the rules from before #595, with the round count read from the record (#591).
    A round is a verify attempt — a new commit, or a new report on the same commit — so a round whose report was
    missing or unreadable, or whose fix pass made no commit, still counts. Every answer carries `round` and `limit`. Rejected findings and the clean
    test stay with the gate (close-stage.py gate_stop); only the limit is decided here."""
    rounds = st.get("rounds") or []
    interaction = st.get("interaction") or "unattended"
    limit = NO_MODE_ROUNDS.get(interaction, 1)
    k = len(st.get("attempts") or [])
    status = (st.get("last_gate") or {}).get("status")
    never_merges = bool(st.get("review") or st.get("in_chain"))
    extra = {"round": k, "limit": limit}
    if status == "clean":
        if k > limit:
            return _answer("stop", False, f"round {k} is clean, but a run without a stop mode allows {limit} "
                           "verify round(s)", None, rounds, **extra)
        return _answer("stop", not never_merges, f"round {k} is clean", None, rounds, **extra)
    if k >= limit:
        return _answer("stop", False, f"no stop mode: {limit} verify round(s) for an {interaction} run, and round {k} "
                       f"is {status or 'not judged'}", None, rounds, **extra)
    return _answer("fix", False, f"no stop mode: round {k} of {limit} is {status or 'not judged'}", None, rounds, **extra)


def decide(st):
    """The answer for the newest recorded round. Anything that cannot be judged is a stop without a merge."""
    mode = st.get("verify_stop")
    if mode is None:
        return _no_mode(st)
    rounds = st.get("rounds") or []
    last = st.get("last_gate") or {}
    never_merges = bool(st.get("review") or st.get("in_chain"))
    if not rounds:
        return _answer("stop", False, "no verify round is recorded in the run state yet", mode, rounds, decided=False)
    cur, k = rounds[-1], len(rounds)
    if last.get("status") == "unparseable" or not _counted(cur):
        return _answer("stop", False, f"the latest verify gate result is unparseable ({last.get('reason') or 'no counts'})",
                       mode, rounds, never_merges, round=k)
    if last.get("report_id") != cur.get("report_id"):
        return _answer("stop", False, "the latest gate result is not the newest recorded round", mode, rounds,
                       never_merges, round=k)
    if cur.get("rejected"):
        return _answer("stop", False, f"round {k} marks {cur['rejected']} finding(s) Rejected; a person decides",
                       mode, rounds, never_merges, round=k)
    if mode not in MODES:
        return _answer("stop", False, f"the run state names an unknown stop mode '{mode}'", mode, rounds, never_merges, round=k)
    tf = to_fix(cur, never_merges)
    prev = rounds[-2] if k >= 2 and _counted(rounds[-2]) else None
    may_merge = not never_merges
    if mode == "early":
        if tf == 0:
            return _answer("stop", may_merge and cur["blocking"] == 0, f"round {k} leaves nothing to fix",
                           mode, rounds, never_merges, round=k, to_fix=tf)
        if prev is not None and tf >= to_fix(prev, never_merges):
            p = to_fix(prev, never_merges)
            return _answer("stop", may_merge and cur["blocking"] == 0, f"the to-fix count did not fall ({p} → {tf})",
                           mode, rounds, never_merges, round=k, to_fix=tf)
        return _answer("fix", False, f"round {k} has {tf} finding(s) to fix", mode, rounds, never_merges, round=k, to_fix=tf)
    if mode == "exhaustive-blocking":
        if cur["blocking"] == 0:
            return _answer("stop", may_merge, f"round {k} has no Blocking finding", mode, rounds, never_merges, round=k, to_fix=tf)
        if k >= 3 and all(_counted(r) for r in rounds[-3:]):
            a, b, c = (r["blocking"] for r in rounds[-3:])
            if c >= b and b >= a:
                return _answer("stop", False, f"Blocking did not fall in the last two rounds ({a} → {b} → {c})",
                               mode, rounds, never_merges, round=k, to_fix=tf)
        return _answer("fix", False, f"round {k} has {cur['blocking']} Blocking finding(s)", mode, rounds, never_merges, round=k, to_fix=tf)
    # exhaustive-all: no round limit; LOW In-scope fix findings count too
    left = cur["blocking"] + (0 if never_merges else cur["in_scope"])
    if left == 0:
        return _answer("stop", may_merge, f"round {k} leaves no finding", mode, rounds, never_merges, round=k, to_fix=0)
    return _answer("fix", False, f"round {k} leaves {left} finding(s)", mode, rounds, never_merges, round=k, to_fix=left)
