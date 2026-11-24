#!/usr/bin/env python3
"""stop-mode-log.py — a record of how each /idd-all verify loop with a stop mode ended (#603).

A finished run leaves nothing to measure otherwise: the per-round counts live only in the run state
(.claude/.idd/state/, read for 24 hours, deleted by the next reset of the same issue) and the run report's
`stop mode:` line is printed to the conversation only. Spec: openspec idd-pr-hitl-modes, "A run with a stop
mode leaves a record of how its verify loop ended".

  append  --cwd <dir> --repo owner/repo --issue <n> --answer <next's JSON> [--gate <JSON> | --gate-file <path>]
          When the run has a stop mode and the answer is not `fix`, append one JSON line to the record.
          A run without a stop mode, a fix answer, no readable run state, or a run another /idd-all replaced
          (`replaced` in next's or the gate's answer, #602) writes nothing (exit 0): a replaced run no longer
          owns the run state on disk, which belongs to the run that replaced it.
          Exit 1 when the line could not be written; idd-all Phase 4 only warns then.
  summary [--json]
          Group the records by mode, the last line per (repo, issue, created_at): runs, how many `next`
          answered merge, rounds per run, the to-fix sequences and the stop reasons. A merge answer is not a
          merged PR: the close stage can still stop the run (#607), so the record says what `next` answered.

The record file is ~/.claude/.idd/stop-mode-runs.jsonl, or IDD_STOP_LOG. It is outside every repository, so
it never dirties a working tree; it holds repository names and issue numbers of this machine's runs and is
never posted anywhere.

Not derived here: how many findings a round fixed versus newly found (each round's report_id is kept, so it
can be derived from the verify reports), and whether a merged run later needed a follow-up.
"""
import datetime
import importlib.util
import json
import os
import sys

sys.dont_write_bytecode = True      # before any import from lib/ or close-stage.py: no __pycache__ in the plugin
HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "lib"))
from stopmode import MODES, _brief  # noqa: E402  (one definition of a round's to-fix count)


def close_stage():
    """close-stage.py as a module: its run-state reader is the only one (no second parser)."""
    spec = importlib.util.spec_from_file_location("close_stage", os.path.join(HERE, "close-stage.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def record_path():
    return os.environ.get("IDD_STOP_LOG") or os.path.join(os.path.expanduser("~"), ".claude", ".idd",
                                                          "stop-mode-runs.jsonl")


def usage(msg):
    print(f"stop-mode-log: {msg}", file=sys.stderr)
    return 64


def parse(argv, flags):
    out, i = {}, 0
    while i < len(argv):
        if argv[i] not in flags or argv[i] in out or i + 1 >= len(argv):
            return None
        out[argv[i]] = argv[i + 1]
        i += 2
    return out


def gate_answer(a):
    """The gate's answer, or (None, why) when one was asked for and cannot be used. Neither --gate nor --gate-file:
    a direct call, no gate check ({}). #603 r3: an answer given but empty, unreadable, not a JSON object, or from
    another round than next's cannot tell a replaced run apart, so it is not used."""
    if "--gate-file" in a:
        try:
            with open(a["--gate-file"], encoding="utf-8") as fh:
                text = fh.read()
        except (OSError, ValueError):
            return None, f"the gate's answer file {a['--gate-file']} cannot be read"
    elif "--gate" in a:
        text = a["--gate"]
    else:
        return {}, None
    if not text.strip():
        return None, "no gate's answer was given (it is empty)"
    try:
        gate = json.loads(text)
    except ValueError:
        return None, "the gate's answer is not JSON"
    if not isinstance(gate, dict):
        return None, "the gate's answer is not a JSON object"
    return gate, None


def cmd_append(argv):
    a = parse(argv, ("--cwd", "--repo", "--issue", "--answer", "--gate", "--gate-file"))
    if (a is None or not {"--cwd", "--repo", "--issue", "--answer"} <= set(a) or not a["--issue"].isdigit()
            or {"--gate", "--gate-file"} <= set(a)):
        return usage("append needs --cwd <dir> --repo owner/repo --issue <digits> --answer <json>"
                     " [--gate <json> | --gate-file <path>]")
    try:
        answer = json.loads(a["--answer"])
    except ValueError:
        return usage("--answer is not JSON")
    # #603 r3: first every case that writes nothing whatever the gate said, silently: a fix answer, a replaced
    # next answer (#602), no readable run state, no stop mode. Only then is the gate's answer needed.
    if not isinstance(answer, dict) or answer.get("decision") == "fix" or answer.get("replaced"):
        return 0
    cs = close_stage()
    try:
        st = cs.read_state(a["--cwd"], a["--repo"], a["--issue"])
    except cs.Stop:
        return 0                                   # no readable run state: nothing to record
    mode = st.get("verify_stop")
    if mode not in MODES:
        return 0                                   # no stop mode: nothing to record
    gate, why = gate_answer(a)
    if gate is None:
        # a missing line is better than one under another run's key; next's answer is not asked again
        print(f"stop-mode-log: {why}; the record is not written (the run goes on as next answered)", file=sys.stderr)
        return 0
    if "round" in gate and "round" in answer and gate["round"] != answer["round"]:
        print(f"stop-mode-log: the gate's answer is from round {gate['round']}, next's from round {answer['round']}; "
              "the record is not written", file=sys.stderr)
        return 0
    # #603 r1: after a replaced gate, next reads the new run's state and its answer carries no flag
    if gate.get("replaced"):
        return 0
    blocking_only = bool(st.get("review") or st.get("in_chain"))
    rounds = [_brief(r, blocking_only) for r in st.get("rounds") or []]
    line = {
        "repo": a["--repo"], "issue": int(a["--issue"]), "created_at": st.get("created_at"),
        "mode": mode, "interaction": st.get("interaction"), "review": bool(st.get("review")),
        "in_chain": bool(st.get("in_chain")),
        "decision": answer.get("decision"), "next_merge": bool(answer.get("merge")),     # next's answer, not the outcome
        "decided": answer.get("decided", True) is not False, "reason": answer.get("reason"),
        "rounds": rounds,
        "written_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    path = record_path()
    try:
        os.makedirs(os.path.dirname(path) or ".", exist_ok=True)
        # the user's own record: 0600 when created, and a symbolic link at its path is not followed
        fd = os.open(path, os.O_RDWR | os.O_APPEND | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0), 0o600)
        with os.fdopen(fd, "a+b") as fh:
            # a last line without its newline (an interrupted write, a hand edit) would swallow this one
            fh.seek(0, os.SEEK_END)
            lead = b""
            if fh.tell():
                fh.seek(-1, os.SEEK_END)
                lead = b"" if fh.read(1) == b"\n" else b"\n"
            fh.write(lead + (json.dumps(line, ensure_ascii=False) + "\n").encode("utf-8"))
    except OSError as exc:
        print(f"stop-mode-log: could not write {path}: {exc}", file=sys.stderr)
        return 1
    return 0


def read_records(path):
    """The last line per (repo, issue, created_at); unreadable lines are skipped and counted."""
    runs, bad = {}, 0
    try:
        with open(path, "rb") as fh:               # bytes: one line that is not UTF-8 must not stop the rest
            for raw in fh:
                try:
                    rec = json.loads(raw.decode("utf-8"))
                    key = (rec["repo"], rec["issue"], rec["created_at"])
                    hash(key)
                except (ValueError, KeyError, TypeError):  # UnicodeDecodeError is a ValueError
                    bad += 1
                    continue
                if not well_formed(rec):       # parses, but not a line append writes
                    bad += 1
                    continue
                runs[key] = rec
    except FileNotFoundError:
        pass
    return list(runs.values()), bad


def well_formed(rec):
    rounds = rec.get("rounds", [])
    return (isinstance(rec, dict) and isinstance(rec.get("mode"), str)
            and isinstance(rounds, list) and all(isinstance(r, dict) for r in rounds)
            and (rec.get("reason") is None or isinstance(rec.get("reason"), str)))


def printable(text):
    """Stored text that cannot drive the terminal: control characters (C0 and C1) are shown escaped."""
    return "".join(c if c.isprintable() else c.encode("unicode_escape").decode("ascii") for c in str(text))


def sequence(rec):
    counts = [r.get("to_fix") for r in rec.get("rounds") or []]
    return " → ".join("?" if c is None else str(c) for c in counts) or "(no round)"


def cmd_summary(argv):
    if argv not in ([], ["--json"]):
        return usage("summary takes no argument but an optional --json")
    path = record_path()
    records, bad = read_records(path)
    modes = {}
    for rec in records:
        m = modes.setdefault(rec.get("mode"), {"runs": 0, "next_merge": 0, "rounds": [], "to_fix": [], "reasons": {}})
        m["runs"] += 1
        m["next_merge"] += 1 if rec.get("next_merge") else 0
        m["rounds"].append(len(rec.get("rounds") or []))
        m["to_fix"].append(sequence(rec))
        reason = rec.get("reason") or "(none)"
        m["reasons"][reason] = m["reasons"].get(reason, 0) + 1
    if argv == ["--json"]:
        print(json.dumps({"record": path, "unreadable_lines": bad, "modes": modes}, ensure_ascii=False))
        return 0
    print(f"stop-mode record: {path} ({len(records)} run(s){f', {bad} unreadable line(s)' if bad else ''})")
    for mode in sorted(modes):
        m = modes[mode]
        print(f"{printable(mode)}: {m['runs']} run(s), next answered merge in {m['next_merge']}; rounds {m['rounds']}")
        for seq in m["to_fix"]:
            print(f"  to-fix {printable(seq)}")
        for reason, k in sorted(m["reasons"].items(), key=lambda kv: -kv[1]):
            print(f"  stopped {k}×: {printable(reason)}")
    return 0


def main(argv):
    if not argv:
        return usage("append … | summary [--json]")
    cmd, rest = argv[0], argv[1:]
    if cmd == "append":
        return cmd_append(rest)
    if cmd == "summary":
        return cmd_summary(rest)
    return usage(f"unknown command {cmd!r}")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
