#!/usr/bin/env bash
# spectra-archive-post-ic.sh — Post auto-generated `## Implementation Complete` comment
# to the GitHub issue linked from a Spectra archive.
#
# Extracted from .claude/skills/spectra-archive/SKILL.md Step 7 per
# PsychQuant/issue-driven-development#56 R2 verify findings (script extraction
# enables unit testing + fixes design-by-narrative anti-pattern).
#
# Usage:
#   spectra-archive-post-ic.sh \
#     --change-name <name> \
#     --archive-dir <path> \
#     [--spec-deltas <text>] \
#     [--linked-issue <N>] \
#     [--outcome-file <path>] \
#     [--gh-repo <owner/repo>] \
#     [--dry-run]
#
# Exit codes:
#   0  — success (posted, skipped due to no linked issue, or idempotent skip)
#   1  — generic error
#   2  — usage error (bad/missing args, or unsafe --outcome-file path)
#  64  — dependency missing (python3 not found)
#  75  — multi-candidate detected; candidates written to /tmp/spectra-archive-candidates.txt
#         agent MUST prompt user via AskUserQuestion and re-invoke with --linked-issue <N>
#
# Stdout: outcome message OR IC comment URL (single line)
# Stderr: diagnostic info
# Outcome file: same content as stdout, persistent across Bash tool calls.
#   The path is DERIVED INTERNALLY from --change-name:
#     /tmp/spectra-archive-ic-outcome-<change-name>.txt
#   --change-name is allowlist-validated (^[A-Za-z0-9_-]+$) before being used in
#   the path, so the derived path is always traversal-safe and the formula has a
#   single source of truth (this script). A caller (SKILL.md Step 8) recomputes
#   the same path from the same --change-name to read the outcome across Bash
#   tool calls. --outcome-file may override the path but is rejected if it
#   contains '..' (path traversal) — see #56 R5-S1 / L1 verify findings.
#
# DRY RUN: when --dry-run is passed, skip all `gh` calls; print "[DRY-RUN] $cmd"
# instead. Used by unit tests in .claude/scripts/tests/spectra-archive-post-ic/.

set -uo pipefail

# ── Defaults ──
CHANGE_NAME=""
ARCHIVE_DIR=""
SPEC_DELTAS="(see archived change directory)"
LINKED_ISSUE_RESOLVED=""
# Pre-allowlist fallback path: used only for the python3-missing / unsafe-change-name
# emit_outcome calls that fire BEFORE $CHANGE_NAME is validated. Once the allowlist
# guard passes, OUTCOME_FILE is reassigned to the change-name-derived path below.
OUTCOME_FILE="/tmp/spectra-archive-ic-outcome.txt"
OUTCOME_FILE_EXPLICIT=0
GH_REPO_ARG=""
DRY_RUN=0

# ── Parse args ──
while [ $# -gt 0 ]; do
  case "$1" in
    --change-name)     CHANGE_NAME="$2"; shift 2;;
    --archive-dir)     ARCHIVE_DIR="$2"; shift 2;;
    --spec-deltas)     SPEC_DELTAS="$2"; shift 2;;
    --linked-issue)    LINKED_ISSUE_RESOLVED="$2"; shift 2;;
    --outcome-file)    OUTCOME_FILE="$2"; OUTCOME_FILE_EXPLICIT=1; shift 2;;
    --gh-repo)         GH_REPO_ARG="$2"; shift 2;;
    --dry-run)         DRY_RUN=1; shift;;
    -h|--help)
      sed -n '/^#/,/^$/p' "$0" | head -40
      exit 0
      ;;
    *)
      echo "ERROR: unknown arg: $1" >&2
      exit 2
      ;;
  esac
done

# ── Validate required args ──
if [ -z "$CHANGE_NAME" ] || [ -z "$ARCHIVE_DIR" ]; then
  echo "ERROR: --change-name and --archive-dir are required" >&2
  echo "Usage: $0 --change-name <name> --archive-dir <path> [--spec-deltas <text>] [--linked-issue <N>] [--dry-run]" >&2
  exit 2
fi

# ── Reject path traversal in an explicit --outcome-file (closes #56 R5-S1 / L1) ──
# Must run BEFORE emit_outcome() is ever called, since emit_outcome writes to
# $OUTCOME_FILE — calling it for an unsafe path would itself perform the traversal
# write. So reject with a plain echo + exit, NOT emit_outcome.
# The default + change-name-derived paths never contain '..' (the change name is
# allowlist-validated below), so only an explicit --outcome-file can fail this.
case "$OUTCOME_FILE" in
  *..*)
    echo "ERROR: --outcome-file must not contain '..' (path traversal): $OUTCOME_FILE" >&2
    echo "(failed — unsafe --outcome-file path)"
    exit 2
    ;;
esac

# ── Helper: write outcome to stdout + outcome file, exit ──
emit_outcome() {
  local msg="$1"
  local code="${2:-0}"
  echo "$msg"
  printf '%s\n' "$msg" > "$OUTCOME_FILE" 2>/dev/null || true
  exit "$code"
}

# ── Dependency check: python3 (for safe checklist substitution) ──
if ! command -v python3 >/dev/null 2>&1; then
  emit_outcome "(failed — python3 not found; required for safe checklist substitution)" 64
fi

# ── Allowlist guard: $CHANGE_NAME ──
if ! [[ "$CHANGE_NAME" =~ ^[A-Za-z0-9_-]+$ ]]; then
  emit_outcome "(skipped — change name contains unsafe characters: $CHANGE_NAME)" 0
fi

# ── Derive the change-name-scoped outcome path (single source of truth) ──
# $CHANGE_NAME has just passed the allowlist (^[A-Za-z0-9_-]+$), so it cannot
# contain '/', '.', or shell metacharacters — the derived path is traversal-safe.
# A caller (SKILL.md Step 8) recomputes this exact path from the same
# --change-name to read the outcome across separate Bash tool calls.
# Skip the reassignment when --outcome-file was explicitly given (already
# traversal-checked above) so callers retain an escape hatch / tests can override.
if [ "$OUTCOME_FILE_EXPLICIT" = "0" ]; then
  OUTCOME_FILE="/tmp/spectra-archive-ic-outcome-${CHANGE_NAME}.txt"
fi

# ── Resolve GH_REPO ──
if [ -n "$GH_REPO_ARG" ]; then
  GH_REPO="$GH_REPO_ARG"
else
  GH_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null || true)
fi

if [ -z "$GH_REPO" ]; then
  emit_outcome "(failed — cannot resolve GitHub repo: pass --gh-repo or run from a git repo with remote)" 0
fi

# ── Archive basename (no date recomputation; derived from passed archive-dir) ──
ARCHIVE_BASENAME=$(basename "$ARCHIVE_DIR")

# ── Step A: Detect linked issue (3-fallback) with multi-candidate awareness ──
detect_candidates() {
  local archive_dir="$1"
  local candidates=""

  # Fallback 1: explicit **GitHub-side tracker** marker
  if [ -d "$archive_dir" ]; then
    candidates=$(grep -hoE '\*\*GitHub-side tracker\*\*[^#]*#[0-9]+' \
      "$archive_dir/proposal.md" "$archive_dir/design.md" 2>/dev/null \
      | grep -oE '#[0-9]+' | tr -d '#' | sort -u)
  fi

  # Fallback 2: Refs / Closes / Fixes / Issue pattern (only if F1 yielded nothing).
  # `[Ii]ssue` added per #170 — /spectra-propose writes the link in IDD-prose form
  # ("referencing issue #N"), not as a Refs/Closes/Fixes trailer, so the narrower
  # regex missed it and detection fell through to "(none)".
  # The `(^|[^[:alnum:]_])` prefix is a word boundary (#170 verify): without it
  # `[Ii]ssue` substring-matches `reissue #5` / `tissue #9`. The downstream
  # `grep -oE '#[0-9]+'` strips the captured prefix char, so only the number
  # survives. NOTE (known limitation, tracked separately): this is still
  # context-blind to legitimate cross-references in prose ("see issue #164"),
  # which can surface a spurious candidate — handled fail-safe by the
  # multi-candidate exit-75 prompt, but see the membership-semantics follow-up.
  if [ -z "$candidates" ] && [ -d "$archive_dir" ]; then
    candidates=$(grep -rhoE '(^|[^[:alnum:]_])(Refs|Closes|Fixes|[Ii]ssue) #[0-9]+' \
      "$archive_dir"/*.md 2>/dev/null \
      | grep -oE '#[0-9]+' | tr -d '#' | sort -u)
  fi

  # Fallback 3: recent commits referencing the archived path
  # (no --follow; --follow only tracks single files, not directories — per #56 R2 N5 finding)
  if [ -z "$candidates" ] && [ -d "$archive_dir" ]; then
    candidates=$(git log --oneline -50 -- "$archive_dir" 2>/dev/null \
      | grep -oE '#[0-9]+' | tr -d '#' | sort -u)
  fi

  echo "$candidates"
}

# ── Resolve LINKED_ISSUE ──
if [ -n "$LINKED_ISSUE_RESOLVED" ]; then
  # Validate integer FIRST (clearer error; emit_outcome exits, so this must
  # precede the membership check to be reachable). (#170)
  # `^[1-9][0-9]*$` is strictly positive — GitHub issue numbers start at 1, so
  # `0` (and leading-zero forms) are invalid; the prior `^[0-9]+$` let `--linked-issue 0`
  # through to post at /issues/0 despite the "positive integer" message (#170 verify).
  if ! [[ "$LINKED_ISSUE_RESOLVED" =~ ^[1-9][0-9]*$ ]]; then
    emit_outcome "(failed — --linked-issue $LINKED_ISSUE_RESOLVED is not a positive integer)" 0
  fi
  # Membership validation applies ONLY when detection actually found candidates
  # (the multi-candidate disambiguation re-invoke). When the candidate set is
  # EMPTY, --linked-issue is the authoritative escape hatch — detection always
  # has gaps (prose-only #N refs etc.), so the override MUST NOT depend on
  # detection succeeding, or both fail together exactly when the fallback is
  # needed (the #170 root cause). (#170)
  CANDIDATES=$(detect_candidates "$ARCHIVE_DIR")
  if [ -n "$CANDIDATES" ] && ! echo "$CANDIDATES" | grep -qx "$LINKED_ISSUE_RESOLVED"; then
    emit_outcome "(failed — --linked-issue $LINKED_ISSUE_RESOLVED not in candidate set: $(echo "$CANDIDATES" | tr '\n' ' '))" 0
  fi
  LINKED_ISSUE="$LINKED_ISSUE_RESOLVED"
else
  CANDIDATES=$(detect_candidates "$ARCHIVE_DIR")
  CANDIDATE_COUNT=$(echo "$CANDIDATES" | grep -c . || true)
  # Normalize empty/blank cases
  if [ -z "$CANDIDATES" ]; then CANDIDATE_COUNT=0; fi

  case "$CANDIDATE_COUNT" in
    0)
      emit_outcome "(none — no linked issue detected)" 0
      ;;
    1)
      LINKED_ISSUE="$CANDIDATES"
      # Single-candidate AskUserQuestion confirmation (per R2 N6 fix — even single is attacker-controllable):
      # signal to caller via a dedicated outcome to optionally prompt. Default: trust the
      # single candidate (it's the most common path); if `--strict-single-candidate` becomes
      # needed, add as future flag. For now, single candidate auto-uses.
      ;;
    *)
      # Multi-candidate: write to file + exit 75 → agent prompts + re-invokes
      echo "$CANDIDATES" > /tmp/spectra-archive-candidates.txt
      emit_outcome "(pending — $CANDIDATE_COUNT candidates detected: $(echo "$CANDIDATES" | tr '\n' ' '); see /tmp/spectra-archive-candidates.txt; re-invoke with --linked-issue <N>)" 75
      ;;
  esac
fi

# ── Step B: Idempotent guard (per-archive sentinel) ──
SENTINEL="auto-posted by spectra-archive for ${ARCHIVE_BASENAME}"

if [ "$DRY_RUN" = "0" ]; then
  ALREADY_POSTED=$(gh issue view "$LINKED_ISSUE" --repo "$GH_REPO" --json comments \
    --jq '.comments[].body' 2>/dev/null \
    | grep -Fc "$SENTINEL" \
    | tr -d ' ')
  # grep -Fc returns "0" with exit 1 when no match; pipeline status doesn't propagate
  # so the value is clean. wc -l is more portable but grep -Fc handles fine here.
  ALREADY_POSTED="${ALREADY_POSTED:-0}"
else
  ALREADY_POSTED=0
fi

if [ "$ALREADY_POSTED" -gt 0 ] 2>/dev/null; then
  emit_outcome "(skipped — already auto-posted for $ARCHIVE_BASENAME to #${LINKED_ISSUE})" 0
fi

# ── Step C: Compose comment body ──

# Derive checklist from tasks.md, filtering to completed (- [x]) only.
# Rationale: /idd-close Step 0 supersession requires all items - [x] to trigger
# (per #515 fix). Including - [~] / - [-] would defeat the purpose. Archived
# tasks.md remains the canonical audit trail for skipped/won't-fix items.
TASKS_FILE="$ARCHIVE_DIR/tasks.md"
if [ -f "$TASKS_FILE" ]; then
  CHECKLIST_BODY=$(grep -E '^- \[x\] ' "$TASKS_FILE" 2>/dev/null || true)
fi
if [ -z "${CHECKLIST_BODY:-}" ]; then
  CHECKLIST_BODY="- [x] (no completed tasks found in archived tasks.md)"
fi

# Portable mktemp (macOS BSD doesn't accept extension after XXXXXX template)
TMP_BODY=$(mktemp /tmp/spectra-archive-ic.XXXXXX) || {
  emit_outcome "(failed — mktemp errored)" 0
}
BODY_FILE="${TMP_BODY}.md"
mv "$TMP_BODY" "$BODY_FILE" 2>/dev/null || BODY_FILE="$TMP_BODY"

ARCHIVE_DATE=$(date -u +%Y-%m-%d)

# Build body via Python (env-var input, not shell-interpolated into -c source).
# This closes the R2 N1 critical Python3 RCE finding: $CHECKLIST_BODY is read from
# os.environ inside a single-quoted heredoc, so attacker-controlled content
# (triple quotes, backticks, shell metacharacters) cannot break out of string
# context or execute code.
export CHECKLIST_BODY_ENV="$CHECKLIST_BODY"
export ARCHIVE_BASENAME_ENV="$ARCHIVE_BASENAME"
export CHANGE_NAME_ENV="$CHANGE_NAME"
export ARCHIVE_DIR_ENV="$ARCHIVE_DIR"
export SPEC_DELTAS_ENV="$SPEC_DELTAS"
export ARCHIVE_DATE_ENV="$ARCHIVE_DATE"
export BODY_FILE_ENV="$BODY_FILE"

python3 <<'PYEOF'
import os, sys

template = """## Implementation Complete (auto-posted by spectra-archive for {basename})

> Auto-posted by `/spectra-archive` after archiving `{change_name}`. This comment is the canonical Implementation Complete anchor for `/idd-close` Step 0 supersession gate.

**Spectra change**: `{archive_dir}/`
**Spec deltas applied**: {spec_deltas}
**Auto-posted**: {archive_date}

### Checklist

{checklist_body}

> Note: only completed (`- [x]`) tasks shown. For skipped (`- [~]`) and won't-fix (`- [-]`) items with reasons, see archived `{archive_dir}/tasks.md` — the canonical audit trail.

---

*The canonical record of what was implemented is the archived change directory + main spec at `openspec/specs/<capability>/spec.md`. This comment exists to satisfy `/idd-close` Step 0 supersession gate.*
"""

body = template.format(
    basename=os.environ.get("ARCHIVE_BASENAME_ENV", ""),
    change_name=os.environ.get("CHANGE_NAME_ENV", ""),
    archive_dir=os.environ.get("ARCHIVE_DIR_ENV", ""),
    spec_deltas=os.environ.get("SPEC_DELTAS_ENV", ""),
    archive_date=os.environ.get("ARCHIVE_DATE_ENV", ""),
    checklist_body=os.environ.get("CHECKLIST_BODY_ENV", ""),
)

with open(os.environ["BODY_FILE_ENV"], "w") as f:
    f.write(body)

PYEOF

PY_EXIT=$?
unset CHECKLIST_BODY_ENV ARCHIVE_BASENAME_ENV CHANGE_NAME_ENV ARCHIVE_DIR_ENV SPEC_DELTAS_ENV ARCHIVE_DATE_ENV BODY_FILE_ENV

if [ "$PY_EXIT" -ne 0 ]; then
  rm -f "$BODY_FILE"
  emit_outcome "(failed — Python body composition errored, exit $PY_EXIT)" 0
fi

# Body size sanity check (GitHub comment limit 65536; we use 60KB headroom)
BODY_SIZE=$(wc -c < "$BODY_FILE" | tr -d ' ')
if [ "$BODY_SIZE" -gt 60000 ]; then
  rm -f "$BODY_FILE"
  emit_outcome "(failed — body size ${BODY_SIZE} bytes exceeds 60KB safety limit)" 0
fi

# ── Step D: Post comment ──
if [ "$DRY_RUN" = "1" ]; then
  # In dry-run mode, write body to a known path for test inspection + return synthetic URL
  cp "$BODY_FILE" "/tmp/spectra-archive-ic-dryrun-body.md"
  rm -f "$BODY_FILE"
  emit_outcome "https://github.com/${GH_REPO}/issues/${LINKED_ISSUE}#issuecomment-DRY-RUN" 0
fi

COMMENT_URL=$(gh issue comment "$LINKED_ISSUE" --repo "$GH_REPO" --body-file "$BODY_FILE" 2>/dev/null)
rm -f "$BODY_FILE"

if [ -z "$COMMENT_URL" ]; then
  emit_outcome "(failed — gh issue comment errored; archive itself succeeded, check gh auth + network)" 0
fi

emit_outcome "$COMMENT_URL" 0
