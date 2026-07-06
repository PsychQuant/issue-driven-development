#!/usr/bin/env bash
# unattended-state.sh — the reliable in-harness unattended signal (#123).
#
# WHY A STATE FILE: Claude Code's Bash tool spawns a fresh shell per call, so
# "idd-all exports IDD_ALL_UNATTENDED=1 for its sub-skills" cannot work as a
# literal env var hand-off. And a TTY heuristic ([ ! -t 0 ]) is ALWAYS true
# inside the harness (#222) — useless as an attended/unattended discriminator.
# The orchestrator therefore marks unattended mode in a state file; detectors
# consult it (plus the env var, kept as a compat layer for real subprocesses
# like plugin-tools' plugin-update, which idd-all launches with the variable
# prefixed on the command line).
#
# Contract (references/unattended-contract.md is the normative doc):
#   mark_unattended <repo_root> <by>     write the flag (idd-all Phase 0.5)
#   clear_unattended <repo_root>         remove it (Phase 6 + all abort paths)
#   is_unattended <repo_root>            exit 0 iff active AND fresh (<24h)
#                                        stale file → exit 1 + warning + auto-clear
STATE_REL=".claude/.idd/state/unattended.json"

mark_unattended() { # repo_root by
  local root="$1" by="${2:-idd-all}"
  mkdir -p "$root/.claude/.idd/state"
  printf '{"active":true,"by":"%s","started_at":"%s"}\n' \
    "$by" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" > "$root/$STATE_REL"
}

clear_unattended() { # repo_root
  rm -f "$1/$STATE_REL"
}

is_unattended() { # repo_root
  local root="$1" f="$1/$STATE_REL"
  # env var wins immediately (compat layer — real subprocess hand-off)
  [ "${IDD_ALL_UNATTENDED:-}" = "1" ] && return 0
  [ -f "$f" ] || return 1
  # TTL guard: a crashed orchestrator must not leave attended sessions
  # permanently mis-detected. started_at older than 24h = stale → warn + clear.
  local started now age
  started=$(python3 -c '
import json,sys,datetime
try:
    d=json.load(open(sys.argv[1]))
    t=datetime.datetime.strptime(d["started_at"], "%Y-%m-%dT%H:%M:%SZ")
    print(int(t.replace(tzinfo=datetime.timezone.utc).timestamp()))
except Exception:
    print(0)
' "$f" 2>/dev/null || echo 0)
  now=$(date +%s)
  age=$(( now - started ))
  if [ "$started" -eq 0 ] || [ "$age" -gt 86400 ]; then
    echo "⚠ stale/corrupt unattended flag ($f, age ${age}s) — clearing; treating session as ATTENDED." >&2
    rm -f "$f"
    return 1
  fi
  return 0
}
