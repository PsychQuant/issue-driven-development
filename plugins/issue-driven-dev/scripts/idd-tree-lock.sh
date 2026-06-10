#!/usr/bin/env bash
# idd-tree-lock.sh — lock the shared working tree so concurrent IDD sessions in
# SEPARATE terminals/instances isolate instead of colliding
# (PsychQuant/issue-driven-development#183).
#
# Scope (per #183 verify rescope): CROSS-TERMINAL. The lock records a PERSISTENT
# process pid — the harness shell `$PPID`, which is stable across a `claude`
# instance's Bash calls and dies when that instance exits. A separate instance
# has a different live pid; liveness (`kill -0`) answers "is the holder's
# session still alive?", never "is the holder done?" (idle != done). Same-INSTANCE
# concurrency (sub-agents sharing one `$PPID`) is the already-deferred Case A
# (worktree-isolation.md) — out of scope here.
#
# NB the default pid MUST be persistent. Recording `$$` (this helper's own
# subprocess, dead the instant it returns) made the lock a no-op — every later
# acquire saw a dead holder and stole the lock (verify B1). `$PPID` is the fix.
#
# Subcommands:
#   acquire   exit 0 acquired / 3 held-by-live-other / 4 lock infra unwritable
#             (caller fails open) / 2 usage.
#   release   release the lock IF held by --id. exit 0.
#   holder    print holder info (exit 0 if held, 1 if free).
#   reclaim-stale  drop the lock iff the recorded holder is not live. exit 0.
#
# Flags: --repo <root> (default git toplevel) --id <session>
#        (default $IDD_SESSION_ID or tree-$PPID) --pid <pid> (default $PPID).
#
# Lock = a FILE (.claude/.idd/tree-lock) created with `set -C` (noclobber) so
# create-with-content is ATOMIC — no two-step mkdir/write window (verify B2).
# Stale reclaim moves the file aside atomically (one winner) before re-creating
# (verify B3). Holder identity / liveness via pid + heartbeat/mtime TTL backup.
set -u

SUB="${1:-}"; shift 2>/dev/null || true
REPO="" ; ID="${IDD_SESSION_ID:-tree-$PPID}" ; PID="$PPID"
TTL="${IDD_TREE_LOCK_TTL:-1800}"   # staleness window (s) when the pid is unverifiable
usage() { echo "usage: idd-tree-lock.sh <acquire|release|holder|reclaim-stale> [--repo <root>] [--id <id>] [--pid <pid>]" >&2; exit 2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --repo) REPO="${2:-}"; shift 2 || usage ;;
    --id)   ID="${2:-}";   shift 2 || usage ;;
    --pid)  PID="${2:-}";  shift 2 || usage ;;
    *) usage ;;
  esac
done
[ -n "$SUB" ] || usage

# Sanitize identity inputs. id is written into the lock file; pid is fed to
# `kill -0`. pid MUST be a positive integer — `kill -0 0` probes the caller's own
# process group (always alive → un-reclaimable wedge, verify S-1), and negatives
# signal a whole group.
case "$ID" in ''|*[!A-Za-z0-9._-]*) echo "bad --id (allowed: A-Za-z0-9._-)" >&2; exit 2 ;; esac
case "$PID" in ''|*[!0-9]*) echo "bad --pid (must be a positive integer)" >&2; exit 2 ;; esac
[ "$PID" -gt 0 ] 2>/dev/null || { echo "bad --pid (must be > 0)" >&2; exit 2; }

if [ -z "$REPO" ]; then
  REPO="$(git rev-parse --show-toplevel 2>/dev/null)" || { echo "not a git repo; pass --repo" >&2; exit 2; }
fi
LOCK_PARENT="$REPO/.claude/.idd"
LOCK="$LOCK_PARENT/tree-lock"

now_epoch()  { date +%s; }
now_iso()    { date -u +%Y-%m-%dT%H:%M:%SZ; }
file_mtime() { stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null; }
field()      { [ -f "$LOCK" ] && sed -n "s/^$1=//p" "$LOCK" | head -1; }
valid_pid()  { printf '%s' "$1" | grep -qE '^[0-9]+$' && [ "$1" -gt 0 ] 2>/dev/null; }

# Is the recorded holder still LIVE? pid liveness is primary; an unverifiable pid
# (missing / non-numeric / 0, incl. the brief atomic-create window) falls back to
# a freshness TTL on the stored epoch, then on the file mtime — a FRESH lock with
# no usable pid is treated as held (someone mid-acquire), a STALE one as reclaimable.
holder_is_live() {
  local hpid hepoch age mtime
  hpid="$(field pid)"
  if valid_pid "$hpid"; then
    kill -0 "$hpid" 2>/dev/null && return 0 || return 1
  fi
  hepoch="$(field epoch)"
  if printf '%s' "$hepoch" | grep -qE '^[0-9]+$'; then
    age=$(( $(now_epoch) - hepoch )); [ "$age" -lt "$TTL" ] && return 0 || return 1
  fi
  mtime="$(file_mtime "$LOCK")"
  if printf '%s' "$mtime" | grep -qE '^[0-9]+$'; then
    age=$(( $(now_epoch) - mtime )); [ "$age" -lt "$TTL" ] && return 0 || return 1
  fi
  return 1
}

ensure_parent() { mkdir -p "$LOCK_PARENT" 2>/dev/null; }

# Self-add the lock to .gitignore — the lock holds a live PID + heartbeat, which
# is per-machine ephemeral state that must never be committed (spec Req 1). This
# is a plugin-distributed primitive, so downstream-installed repos won't have a
# hand-written rule; mirror idd-worktree.sh's create-time self-ignore.
ensure_ignored() {
  local gi="$REPO/.gitignore" line=".claude/.idd/tree-lock"
  [ -f "$gi" ] && grep -qxF "$line" "$gi" 2>/dev/null && return 0
  [ -f "$gi" ] && grep -qE '^\.claude/(\.idd/)?$' "$gi" 2>/dev/null && return 0
  {
    [ -s "$gi" ] && printf '\n'
    printf '# IDD tree-lock (idd-tree-lock.sh #183) — per-machine session state, not tracked\n'
    printf '%s\n' "$line"
  } >> "$gi" 2>/dev/null || true
}

# Atomic create-with-content. `set -C` makes `>` fail if the file exists, so the
# create and the content write are one indivisible step.
try_create() {
  ( set -C; printf 'holder=%s\npid=%s\nheartbeat=%s\nepoch=%s\n' \
      "$ID" "$PID" "$(now_iso)" "$(now_epoch)" > "$LOCK" ) 2>/dev/null
}

# Overwrite the lock with my own current info — only safe when the lock is already
# MINE (re-entrant refresh). Not atomic; never called on another holder's lock.
write_info() {
  printf 'holder=%s\npid=%s\nheartbeat=%s\nepoch=%s\n' \
    "$ID" "$PID" "$(now_iso)" "$(now_epoch)" > "$LOCK" 2>/dev/null
}

case "$SUB" in
  acquire)
    ensure_parent || { echo "lock dir unwritable: $LOCK_PARENT" >&2; exit 4; }
    ensure_ignored
    try_create && exit 0                       # first-come: acquired atomically
    # Re-entrant: the lock is already MINE (same id) — e.g. this instance reusing
    # the tree after an aborted issue that never released. Re-own + refresh; do NOT
    # treat my own live $PPID as a "live other" and spuriously self-escalate (#183 R2 F1).
    [ "$(field holder)" = "$ID" ] && { write_info; exit 0; }
    holder_is_live && exit 3                    # held by a LIVE other session
    # Stale → reclaim inside an atomic `mkdir` mutex so concurrent reclaimers
    # SERIALIZE. A bare mv-aside has a lap window — a late reclaimer's mv can move
    # the winner's FRESH lock → double-acquire (#183 R2-1). Only one reclaimer
    # enters; it re-checks liveness (a prior reclaimer may have re-created a live
    # lock) before replacing.
    if mkdir "$LOCK.reclaim" 2>/dev/null; then
      if holder_is_live; then RC=3; else rm -f "$LOCK" 2>/dev/null; try_create && RC=0 || RC=1; fi
      rmdir "$LOCK.reclaim" 2>/dev/null
      [ "$RC" = 0 ] && exit 0
      exit 3
    fi
    # Another reclaimer holds the mutex (normal) — or it was orphaned by a killed
    # reclaimer. Clear a clearly-stale mutex (>10s) once; either way back off and
    # re-probe (conservatively held — a later acquire retries the reclaim).
    MX_MTIME="$(file_mtime "$LOCK.reclaim" 2>/dev/null)"
    if printf '%s' "$MX_MTIME" | grep -qE '^[0-9]+$' && [ $(( $(now_epoch) - MX_MTIME )) -gt 10 ]; then
      rmdir "$LOCK.reclaim" 2>/dev/null
    fi
    holder_is_live && exit 3 || exit 3
    ;;
  release)
    [ -f "$LOCK" ] || exit 0
    [ "$(field holder)" = "$ID" ] && rm -f "$LOCK" 2>/dev/null
    exit 0                                       # not ours → leave it (holder-scoped)
    ;;
  holder)
    [ -f "$LOCK" ] || exit 1
    cat "$LOCK" 2>/dev/null
    exit 0
    ;;
  reclaim-stale)
    [ -f "$LOCK" ] || exit 0
    holder_is_live || rm -f "$LOCK" 2>/dev/null
    exit 0
    ;;
  *) usage ;;
esac
