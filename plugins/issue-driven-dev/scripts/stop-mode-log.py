#!/usr/bin/env python3
"""stop-mode-log.py — a record of how each /idd-all verify loop with a stop mode ended (#603).

A finished run leaves nothing to measure otherwise: the per-round counts live only in the run state
(.claude/.idd/state/, read for 24 hours, deleted by the next reset of the same issue) and the run report's
`stop mode:` line is printed to the conversation only. Spec: openspec idd-pr-hitl-modes, "A run with a stop
mode leaves a record of how its verify loop ended".

  append  --cwd <dir> --repo owner/repo --issue <n> --answer <next's JSON>
          When the run has a stop mode and the answer is not `fix`, append one JSON line to the record.
          A run without a stop mode, a fix answer, or no readable run state writes nothing (exit 0).
          Exit 1 when the line could not be written; idd-all Phase 4 only warns then.
  summary [--json]
          Group the records by mode, the last line per (repo, issue, created_at): runs, merged, rounds per
          run, the to-fix sequences and the stop reasons.

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


def cmd_append(argv):
    a = parse(argv, ("--cwd", "--repo", "--issue", "--answer"))
    if a is None or len(a) != 4 or not a["--issue"].isdigit():
        return usage("append needs --cwd <dir> --repo owner/repo --issue <digits> --answer <json>")
    try:
        answer = json.loads(a["--answer"])
    except ValueError:
        return usage("--answer is not JSON")
    if not isinstance(answer, dict) or answer.get("decision") == "fix":
        return 0
    cs = close_stage()
    try:
        st = cs.read_state(a["--cwd"], a["--repo"], a["--issue"])
    except cs.Stop:
        return 0                                   # no readable run state: nothing to record
    mode = st.get("verify_stop")
    if mode not in MODES:
        return 0                                   # no stop mode: nothing to record
    blocking_only = bool(st.get("review") or st.get("in_chain"))
    rounds = [_brief(r, blocking_only) for r in st.get("rounds") or []]
    line = {
        "repo": a["--repo"], "issue": int(a["--issue"]), "created_at": st.get("created_at"),
        "mode": mode, "interaction": st.get("interaction"), "review": bool(st.get("review")),
        "in_chain": bool(st.get("in_chain")),
        "decision": answer.get("decision"), "merge": bool(answer.get("merge")),
        "decided": answer.get("decided", True) is not False, "reason": answer.get("reason"),
        "rounds": rounds,
        "written_at": datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    path = record_path()
    try:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "a", encoding="utf-8") as fh:
            fh.write(json.dumps(line, ensure_ascii=False) + "\n")
    except OSError as exc:
        print(f"stop-mode-log: could not write {path}: {exc}", file=sys.stderr)
        return 1
    return 0


def read_records(path):
    """The last line per (repo, issue, created_at); unreadable lines are skipped and counted."""
    runs, bad = {}, 0
    try:
        with open(path, encoding="utf-8") as fh:
            for raw in fh:
                try:
                    rec = json.loads(raw)
                    key = (rec["repo"], rec["issue"], rec["created_at"])
                except (ValueError, KeyError, TypeError):
                    bad += 1
                    continue
                runs[key] = rec
    except FileNotFoundError:
        pass
    return list(runs.values()), bad


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
        m = modes.setdefault(rec.get("mode"), {"runs": 0, "merged": 0, "rounds": [], "to_fix": [], "reasons": {}})
        m["runs"] += 1
        m["merged"] += 1 if rec.get("merge") else 0
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
        print(f"{mode}: {m['runs']} run(s), {m['merged']} merged; rounds {m['rounds']}")
        for seq in m["to_fix"]:
            print(f"  to-fix {seq}")
        for reason, k in sorted(m["reasons"].items(), key=lambda kv: -kv[1]):
            print(f"  stopped {k}×: {reason}")
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
