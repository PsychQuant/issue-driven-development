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
FORCE_LINKED_ISSUE=""
# The egress gate lives in the plugin tree of this repository. Resolved from this
# script, not from the caller's cwd: the audited repo must not supply its own gate.
EGRESS="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." 2>/dev/null && pwd)/plugins/issue-driven-dev/scripts/gh-egress.sh"

# ── Parse args ──
while [ $# -gt 0 ]; do
  case "$1" in
    --change-name)     CHANGE_NAME="$2"; shift 2;;
    --archive-dir)     ARCHIVE_DIR="$2"; shift 2;;
    --spec-deltas)     SPEC_DELTAS="$2"; shift 2;;
    --linked-issue)    LINKED_ISSUE_RESOLVED="$2"; shift 2;;
    --force-linked-issue) FORCE_LINKED_ISSUE="$2"; shift 2;;
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
  echo "Usage: $0 --change-name <name> --archive-dir <path> [--spec-deltas <text>] [--linked-issue <N> | --force-linked-issue <N>] [--dry-run]" >&2
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

# ── Path for the comment (#405) ──
# --archive-dir is how this machine reaches the directory. The comment goes to
# GitHub, so it only ever gets the path inside the repository. --show-prefix
# answers that whatever form the argument took (absolute, relative to a
# subdirectory, through a symlink). Outside a git repository there is no such
# path: use the conventional location, never the argument as given.
ARCHIVE_DISPLAY=$(git -C "$ARCHIVE_DIR" rev-parse --show-prefix 2>/dev/null) || ARCHIVE_DISPLAY=""
ARCHIVE_DISPLAY="${ARCHIVE_DISPLAY%/}"
[ -n "$ARCHIVE_DISPLAY" ] || ARCHIVE_DISPLAY="openspec/changes/archive/$ARCHIVE_BASENAME"

# ── Step A: Detect linked issue with multi-candidate awareness ──

# Reads text, writes it back without references to other repositories (#405), so a
# number from a sandbox or an upstream never becomes a candidate here. The same
# repository's full form is kept, rewritten to the short one.
strip_cross_repo_refs() {
  GH_REPO_ENV="$GH_REPO" python3 -c '
import os, re, sys
repo = os.environ["GH_REPO_ENV"].lower()
ref = re.compile(r"(?:(?:-R|--repo)\s+)?`?([A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+)`?(?:\s+[Ii]ssue)?\s*#(\d+)")
sys.stdout.write(ref.sub(lambda m: f"issue #{m.group(2)}" if m.group(1).lower() == repo else " ",
                         sys.stdin.read()))
'
}

# Issue numbers in the subjects of the commits that touched a path.
commit_refs() {
  git log --format=%s -50 -- "$1" 2>/dev/null \
    | strip_cross_repo_refs | grep -oE '#[0-9]+' | tr -d '#' | LC_ALL=C sort -u
}

detect_candidates() {
  local archive_dir="$1"
  local candidates="" prose="" at_archive="" before_move=""
  [ -d "$archive_dir" ] || return 0

  # An explicit **GitHub-side tracker** marker settles it.
  candidates=$(cat "$archive_dir/proposal.md" "$archive_dir/design.md" 2>/dev/null \
    | strip_cross_repo_refs \
    | grep -oE '\*\*GitHub-side tracker\*\*[^#]*#[0-9]+' \
    | grep -oE '#[0-9]+' | tr -d '#' | LC_ALL=C sort -u)
  if [ -n "$candidates" ]; then
    echo "$candidates"
    return 0
  fi

  # Without a marker there are two weak sources, wrong in different ways (#405):
  #   prose    names whatever the change talks about. `[Ii]ssue` was added per #170
  #            because /spectra-propose writes "referencing issue #N", but the same
  #            words describe a sandbox's "seed issue #1", and nothing marks the
  #            difference. The `(^|[^[:alnum:]_])` prefix keeps `reissue #5` out.
  #   commits  carry the issue by rule, but a squash subject adds the PR number and
  #            a cluster commit adds other issues.
  # So a number in both is the answer, and commits win when they do not meet: a
  # lone prose number with commits saying otherwise would otherwise be posted to
  # silently. Commits are read from the archive path and from the path before the
  # move, because Step 7 runs before the archive is committed: at that moment the
  # archive path has no history at all. `:/` makes the second path repo-relative
  # from any cwd. No `--follow`: it tracks single files only (#56 R2 N5).
  prose=$(for f in "$archive_dir"/*.md; do
      [ -f "$f" ] && { cat "$f"; echo; }
    done \
    | strip_cross_repo_refs \
    | grep -oE '(^|[^[:alnum:]_])(Refs|Closes|Fixes|[Ii]ssue) #[0-9]+' \
    | grep -oE '#[0-9]+' | tr -d '#' | LC_ALL=C sort -u)
  at_archive=$(commit_refs "$archive_dir")
  before_move=$(commit_refs ":/openspec/changes/$CHANGE_NAME")

  candidates=$(LC_ALL=C comm -12 <(printf '%s\n' "$prose") \
    <(printf '%s\n%s\n' "$at_archive" "$before_move" | sed '/^$/d' | LC_ALL=C sort -u))
  [ -n "$candidates" ] || candidates="${at_archive:-${before_move:-$prose}}"

  echo "$candidates"
}

# ── Resolve LINKED_ISSUE ──
# Two flags, two intents (#172): --linked-issue is the exit-75 DISAMBIGUATION
# re-invoke (validated against the detected candidate set); --force-linked-issue
# is the AUTHORITATIVE override (caller knows the number; detection bypassed
# entirely, existence-checked instead). The old "empty candidate set turns
# --linked-issue authoritative" escape hatch is REMOVED — its emptiness was
# timing/context-dependent (#172 fragility 2), and conflating the intents is
# what made #170's fix fragile in the first place.
if [ -n "$FORCE_LINKED_ISSUE" ] && [ -n "$LINKED_ISSUE_RESOLVED" ]; then
  emit_outcome "(failed — pass either --linked-issue or --force-linked-issue, not both)" 0
fi
FORCE_NOTE=""
if [ -n "$FORCE_LINKED_ISSUE" ]; then
  if ! [[ "$FORCE_LINKED_ISSUE" =~ ^[1-9][0-9]*$ ]]; then
    emit_outcome "(failed — --force-linked-issue $FORCE_LINKED_ISSUE is not a positive integer)" 0
  fi
  # Existence checkpoint (#172 direction 2): catches nonexistent numbers; a
  # wrong-but-existing number is inherent to an explicit override — mitigated
  # by the loud confirmation + the annotated anchor below.
  if [ "$DRY_RUN" = "0" ]; then
    FORCED_TITLE=$(gh issue view "$FORCE_LINKED_ISSUE" --repo "$GH_REPO" --json title -q .title 2>/dev/null) ||       emit_outcome "(failed — --force-linked-issue $FORCE_LINKED_ISSUE: issue not found in $GH_REPO)" 0
    echo "→ FORCE-LINKED to #${FORCE_LINKED_ISSUE}: ${FORCED_TITLE} (authoritative override — detection & membership bypassed)" >&2
  else
    echo "[DRY-RUN] existence check skipped for --force-linked-issue $FORCE_LINKED_ISSUE" >&2
  fi
  LINKED_ISSUE="$FORCE_LINKED_ISSUE"
  FORCE_NOTE=" via --force-linked-issue"
elif [ -n "$LINKED_ISSUE_RESOLVED" ]; then
  # Validate integer FIRST (clearer error; emit_outcome exits, so this must
  # precede the membership check to be reachable). (#170)
  # `^[1-9][0-9]*$` is strictly positive — GitHub issue numbers start at 1, so
  # `0` (and leading-zero forms) are invalid; the prior `^[0-9]+$` let `--linked-issue 0`
  # through to post at /issues/0 despite the "positive integer" message (#170 verify).
  if ! [[ "$LINKED_ISSUE_RESOLVED" =~ ^[1-9][0-9]*$ ]]; then
    emit_outcome "(failed — --linked-issue $LINKED_ISSUE_RESOLVED is not a positive integer)" 0
  fi
  # Pure disambiguation semantics (#172): --linked-issue is ALWAYS validated
  # against the candidate set. Empty set = nothing to disambiguate = this is
  # the wrong flag; the authoritative path is --force-linked-issue (which
  # existence-checks instead of membership-checks).
  CANDIDATES=$(detect_candidates "$ARCHIVE_DIR")
  if [ -z "$CANDIDATES" ]; then
    emit_outcome "(failed — --linked-issue $LINKED_ISSUE_RESOLVED given but detection found no candidates; if you know the issue number authoritatively, re-invoke with --force-linked-issue $LINKED_ISSUE_RESOLVED)" 0
  fi
  if ! echo "$CANDIDATES" | grep -qx -- "$LINKED_ISSUE_RESOLVED"; then
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
ANCHOR_SUFFIX="${FORCE_NOTE:-}"

if [ "$DRY_RUN" = "0" ]; then
  ALREADY_POSTED=$(gh issue view "$LINKED_ISSUE" --repo "$GH_REPO" --json comments \
    --jq '.comments[].body' 2>/dev/null \
    | grep -Fc -- "$SENTINEL" \
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
export FORCE_NOTE_ENV="${FORCE_NOTE:-}"
export CHANGE_NAME_ENV="$CHANGE_NAME"
export ARCHIVE_DIR_ENV="$ARCHIVE_DISPLAY"
export SPEC_DELTAS_ENV="$SPEC_DELTAS"
export ARCHIVE_DATE_ENV="$ARCHIVE_DATE"
export BODY_FILE_ENV="$BODY_FILE"

python3 <<'PYEOF'
import os, sys

template = """## Implementation Complete (auto-posted by spectra-archive for {basename}{force_note})

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
    force_note=os.environ.get("FORCE_NOTE_ENV", ""),
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
unset CHECKLIST_BODY_ENV ARCHIVE_BASENAME_ENV FORCE_NOTE_ENV CHANGE_NAME_ENV ARCHIVE_DIR_ENV SPEC_DELTAS_ENV ARCHIVE_DATE_ENV BODY_FILE_ENV

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

# Every GitHub write goes through the egress gate (#202, #405). Each refusal below
# posts nothing and says why. The archive has already succeeded, so all of them
# still exit 0; the outcome line is how the caller finds out.
if [ ! -f "$EGRESS" ]; then
  rm -f "$BODY_FILE"
  emit_outcome "(failed — gh-egress.sh not found at $EGRESS; nothing posted, archive itself succeeded)" 0
fi

# The attestation level comes from the repository, as rules/privacy-scrubbing.md
# resolves it. `enforce` means a person must look at the text first, and nobody is
# here to do that, so this script does not post at that level.
case "$(gh repo view "$GH_REPO" --json viewerPermission,isPrivate \
        --jq '"\(.viewerPermission)/\(.isPrivate)"' 2>/dev/null)" in
  ADMIN/true|MAINTAIN/true|WRITE/true)    SCRUB_LEVEL=light ;;
  ADMIN/false|MAINTAIN/false|WRITE/false) SCRUB_LEVEL=warn ;;
  *)                                      SCRUB_LEVEL=enforce ;;
esac
if [ "$SCRUB_LEVEL" = "enforce" ]; then
  rm -f "$BODY_FILE"
  emit_outcome "(failed — could not confirm write access to $GH_REPO, so the comment needs a person to post it; archive itself succeeded)" 0
fi

EGRESS_ERR=$(mktemp /tmp/spectra-archive-ic-err.XXXXXX) || {
  rm -f "$BODY_FILE"
  emit_outcome "(failed — mktemp errored)" 0
}
COMMENT_URL=$(bash "$EGRESS" comment "$LINKED_ISSUE" --repo "$GH_REPO" --body-file "$BODY_FILE" \
  --scrub-attested "$SCRUB_LEVEL" 2>"$EGRESS_ERR")
EGRESS_RC=$?
EGRESS_REASON=$(grep -m1 . "$EGRESS_ERR" | LC_ALL=C tr -d '\000-\037' | cut -c1-200)
rm -f "$BODY_FILE" "$EGRESS_ERR"

# The wrapper keeps its own exit codes at 10 and above; below that is gh's.
if [ "$EGRESS_RC" -ge 10 ]; then
  emit_outcome "(failed — gh-egress refused the comment (exit $EGRESS_RC): $EGRESS_REASON; archive itself succeeded)" 0
fi
if [ "$EGRESS_RC" -ne 0 ] || [ -z "$COMMENT_URL" ]; then
  emit_outcome "(failed — gh issue comment errored; archive itself succeeded, check gh auth + network)" 0
fi

emit_outcome "$COMMENT_URL" 0
