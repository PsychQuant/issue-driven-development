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
count is Blocking (also in exhaustive-all).

The report's coverage and reviewers lines (#607), recorded in the round by the gate:
- an incomplete coverage line (`X / Y requirements addressed`, X < Y) counts as one
  Blocking finding in every rule above, so the loop fixes it under the same stop rules
  and a stop merges only once it is complete — the close stage refuses a merge without
  it. A round recorded before #607 has no field and counts as incomplete, as there;
- an incomplete reviewers line (`R / T reviewers completed`, R < T) is a degraded verify
  that a fix does not change: a stop that would merge stops without a merge.
The gate may read the newest round's report again (the same report, so no new round); a
line counts as complete only when the round and that latest read both say so (`last_gate`
carries the two values; one written before this change does not, and then the line counts
as incomplete). A run without a stop mode keeps its counts: the gap is added only in the table.

Two rules hold in every run (verify round 1 of #595):
- a gate result that `next` already answered with fix (same commit, same report or no
  report) is answered stop without a merge: a new round brings a new commit or a new
  report, so the loop always ends, and a round whose result was not recorded never
  reuses the previous answer;
- a stop-mode stop does not merge while the round leaves an In-scope fix finding of
  severity CRITICAL, HIGH, P0 or P1 (`high_in_scope`; the close stage checks it too).
"""

MODES = ("early", "exhaustive-blocking", "exhaustive-all")
NO_MODE_ROUNDS = {"unattended": 2, "attended": 1}


def coverage_gap(r):
    """1 when the round's coverage line is not recorded as complete (#607): it counts as a Blocking finding."""
    return 0 if r.get("coverage_complete") is True else 1


def blocking(r):
    """The round's Blocking count, with an incomplete coverage line counted as one more (#607)."""
    return r["blocking"] + coverage_gap(r)


def to_fix(r, blocking_only, gap=True):
    """Blocking plus the In-scope fix findings above LOW; `gap` adds an incomplete coverage line as one Blocking
    finding, which only the stop modes do (#607 r1: a run without a stop mode keeps its counts)."""
    b = blocking(r) if gap else r["blocking"]
    if blocking_only:
        return b
    return b + r["in_scope"] - (r.get("low_in_scope") or 0)


COMPLETENESS = ("coverage_complete", "reviewers_complete")


def effective_rounds(st):
    """The round record, with the newest round's coverage and reviewers lines complete only when the round and the
    latest gate read of its report both say so (#607 r1: the gate may read the same report again, which adds no
    round). A latest read without the value (written by a gate from before #607) does not confirm it, so the line
    counts as incomplete, as the close stage reads it (#607 r2)."""
    rounds = list(st.get("rounds") or [])
    last = st.get("last_gate") or {}
    if rounds and last.get("report_id") == rounds[-1].get("report_id"):
        cur = dict(rounds[-1])
        for field in COMPLETENESS:
            cur[field] = cur.get(field) is True and last.get(field) is True
        rounds[-1] = cur
    return rounds


def _brief(r, blocking_only=False, gap=True):
    out = {k: r.get(k) for k in ("round", "sha", "status", "blocking", "in_scope", "low_in_scope", "report_id")}
    out["to_fix"] = to_fix(r, blocking_only, gap) if _counted(r) else None     # Phase 6 lists it per round
    return out


def _answer(decision, merge, reason, mode, rounds, blocking_only=False, **extra):
    return dict({"decision": decision, "merge": merge, "reason": reason, "mode": mode,
                 "rounds": [_brief(r, blocking_only, gap=mode is not None) for r in rounds]}, **extra)


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
    if k == 0:   # no gate result recorded yet (verify r3 #3): nothing to decide on
        return _answer("stop", False, "no verify round is recorded in the run state yet", None, rounds,
                       decided=False, **extra)
    if status == "clean":
        if k > limit:
            return _answer("stop", False, f"round {k} is clean, but a run without a stop mode allows {limit} "
                           "verify round(s)", None, rounds, **extra)
        return _answer("stop", not never_merges, f"round {k} is clean", None, rounds, **extra)
    if k >= limit:
        return _answer("stop", False, f"no stop mode: {limit} verify round(s) for an {interaction} run, and round {k} "
                       f"is {status or 'not judged'}", None, rounds, **extra)
    return _answer("fix", False, f"no stop mode: round {k} of {limit} is {status or 'not judged'}", None, rounds, **extra)


def fix_key(st):
    """The gate result an answer is about: the commit and the report the gate read last."""
    last = st.get("last_gate") or {}
    return {"sha": last.get("sha"), "report_id": last.get("report_id")}


def answered_fix(st, key=None):
    """Whether `next` already answered fix for this gate result (the last one, unless `key` names another)."""
    key = key or fix_key(st)
    return any(isinstance(f, dict) and f.get("sha") == key["sha"] and f.get("report_id") == key["report_id"]
               for f in st.get("fix_answers") or [])


def decide(st):
    """The answer for the newest recorded round, after the two rules that hold in every run (module docstring)."""
    ans = _decide(st)
    # Whatever this result reads as now (verify r2 #3: an unreadable report that later reads clean), a result that
    # was answered fix is not answered again: stop, no merge.
    if answered_fix(st) and (ans["decision"] == "fix" or ans["merge"]):
        return dict(ans, decision="stop", merge=False,
                    reason=f"no new report or commit followed the fix answer for this result ({ans['reason']})")
    rounds = effective_rounds(st)
    # A degraded verify (#607): fixing the code does not complete the reviewers line, so the stop does not merge.
    if ans["merge"] and ans.get("mode") is not None and rounds and rounds[-1].get("reviewers_complete") is not True:
        return dict(ans, merge=False, reason=f"{ans['reason']}; the report's reviewers line is incomplete (a degraded "
                    "verify), so the stop does not merge")
    high = rounds[-1].get("high_in_scope") if rounds else None
    if ans["merge"] and ans.get("mode") is not None and isinstance(high, int) and high > 0:
        return dict(ans, merge=False, reason=f"{ans['reason']}; {high} In-scope fix finding(s) of severity CRITICAL, "
                    "HIGH, P0 or P1 are left, so the stop does not merge")
    return ans


def _decide(st):
    mode = st.get("verify_stop")
    if mode is None:
        return _no_mode(st)
    rounds = effective_rounds(st)
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
    gap = "; its coverage line is incomplete, which counts as one Blocking finding" if coverage_gap(cur) else ""
    if mode == "early":
        if tf == 0:
            return _answer("stop", may_merge and blocking(cur) == 0, f"round {k} leaves nothing to fix",
                           mode, rounds, never_merges, round=k, to_fix=tf)
        if prev is not None and tf >= to_fix(prev, never_merges):
            p = to_fix(prev, never_merges)
            return _answer("stop", may_merge and blocking(cur) == 0, f"the to-fix count did not fall ({p} → {tf}){gap}",
                           mode, rounds, never_merges, round=k, to_fix=tf)
        return _answer("fix", False, f"round {k} has {tf} finding(s) to fix{gap}", mode, rounds, never_merges, round=k, to_fix=tf)
    if mode == "exhaustive-blocking":
        if blocking(cur) == 0:
            return _answer("stop", may_merge, f"round {k} has no Blocking finding", mode, rounds, never_merges, round=k, to_fix=tf)
        if k >= 3 and all(_counted(r) for r in rounds[-3:]):
            a, b, c = (blocking(r) for r in rounds[-3:])
            if c >= b and b >= a:
                return _answer("stop", False, f"Blocking did not fall in the last two rounds ({a} → {b} → {c}){gap}",
                               mode, rounds, never_merges, round=k, to_fix=tf)
        return _answer("fix", False, f"round {k} has {cur['blocking']} Blocking finding(s){gap}", mode, rounds, never_merges, round=k, to_fix=tf)
    # exhaustive-all: no round limit; LOW In-scope fix findings count too
    left = blocking(cur) + (0 if never_merges else cur["in_scope"])
    if left == 0:
        why = f"round {k} has no Blocking finding" if never_merges else f"round {k} leaves no finding"
        return _answer("stop", may_merge, why, mode, rounds, never_merges, round=k, to_fix=0)
    return _answer("fix", False, f"round {k} leaves {left} finding(s){gap}", mode, rounds, never_merges, round=k, to_fix=left)
