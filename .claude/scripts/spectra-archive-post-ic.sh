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
#     [--scrub-attested <light|warn|enforce>] \
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
# DRY RUN: when --dry-run is passed, nothing is written to GitHub; the composed
# body goes to /tmp/spectra-archive-ic-dryrun-body.md. Read-only lookups still run:
# checking whether a number taken from commit subjects is a pull request, so a
# dry run picks the same issue the real run will (#405). Used by Step 7's review
# pass and by the tests in .claude/scripts/tests/spectra-archive-post-ic/.
#
# --scrub-attested: the privacy level the CALLER resolved after reviewing the
# dry-run body (plugins/issue-driven-dev/rules/privacy-scrubbing.md). Required to
# post; the script cannot review text, so it never supplies this itself. The
# repository's own level is a floor: a stricter one wins, `enforce` is not posted.

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
SCRUB_ATTESTED=""
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
    --scrub-attested)  SCRUB_ATTESTED="$2"; shift 2;;
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
  echo "Usage: $0 --change-name <name> --archive-dir <path> [--spec-deltas <text>] [--linked-issue <N> | --force-linked-issue <N>] [--scrub-attested <light|warn|enforce>] [--dry-run]" >&2
  exit 2
fi

case "$SCRUB_ATTESTED" in
  ""|light|warn|enforce) ;;
  *)
    echo "ERROR: --scrub-attested must be light, warn or enforce: $SCRUB_ATTESTED" >&2
    exit 2
    ;;
esac

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

# ── A real post needs the caller's privacy review (#405) ──
# Checked before any lookup: without it nothing will be posted, so there is no
# reason to resolve candidates first.
if [ "$DRY_RUN" = "0" ] && [ -z "$SCRUB_ATTESTED" ]; then
  emit_outcome "(failed — not posted: run this step with --dry-run, review /tmp/spectra-archive-ic-dryrun-body.md per plugins/issue-driven-dev/rules/privacy-scrubbing.md, then re-run with --scrub-attested <level>; archive itself succeeded)" 0
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

# ── The archive's own repository (#405) ──
# Everything below that reads git history or names a path works in the repository
# the archive lives in, never the caller's cwd: a caller in /tmp, or in another
# repository, must not change which issue gets the comment. That repository is used
# only when its origin is $GH_REPO; anything else (a fixture tree, a home-directory
# repo, a fork checked out elsewhere) gives no commit evidence and no path prefix.
REPO_ROOT=""
ARCHIVE_REL=""
if TOP=$(git -C "$ARCHIVE_DIR" rev-parse --show-toplevel 2>/dev/null) \
   && REL=$(git -C "$ARCHIVE_DIR" rev-parse --show-prefix 2>/dev/null); then
  ORIGIN_REPO=$(git -C "$TOP" remote get-url origin 2>/dev/null \
    | sed -E 's#/*$##; s#\.git$##; s#.*[:/]([^/]+/[^/]+)$#\1#')
  if [ -n "${REL%/}" ] && [ -n "$ORIGIN_REPO" ] \
     && [ "$(printf '%s' "$ORIGIN_REPO" | tr '[:upper:]' '[:lower:]')" = "$(printf '%s' "$GH_REPO" | tr '[:upper:]' '[:lower:]')" ]; then
    REPO_ROOT="$TOP"
    ARCHIVE_REL="${REL%/}"
  fi
fi

# ── Path for the comment ──
# --archive-dir is how this machine reaches the directory. The comment goes to
# GitHub, so it only gets the path inside the repository, whatever form the
# argument took (absolute, relative to a subdirectory, through a symlink). Without
# a matching repository, use the conventional location, never the argument.
if [ -n "$ARCHIVE_REL" ]; then
  ARCHIVE_DISPLAY="$ARCHIVE_REL"
  PRE_MOVE_REL="$(dirname "$(dirname "$ARCHIVE_REL")")/$CHANGE_NAME"
else
  ARCHIVE_DISPLAY="openspec/changes/archive/$ARCHIVE_BASENAME"
  PRE_MOVE_REL=""
fi

# ── Step A: Detect linked issue with multi-candidate awareness ──
# One Python program, run isolated (-I: nothing is imported from the cwd). It prints
# one candidate per line, then `?ask` when a person must choose even with a single
# candidate. Sources, strongest first:
#   marker   `**GitHub-side tracker**: #N` in proposal.md or design.md settles it.
#   commits  the repo's commit rule (rules/commit-issue-reference.md) writes the issue
#            as a parenthesised group in the subject, `(#N)` or `(#N #M)`, or as a
#            body line `Refs #N`. Only those count; a bare `#N` in a subject is prose
#            (in the spike it was the sandbox's `PR #4`). When no commit has such a
#            group, any `#N` in the subjects is used instead. A squash adds the PR
#            number as a group too, so every commit number is checked against the
#            issues API: pull requests and numbers that do not exist are dropped,
#            and one that cannot be checked forces the question. History is read for
#            the archive path and for the path before the move: Step 7 runs before
#            the archive is committed, when the archive path has no history at all.
#   prose    `Refs|Closes|Fixes #N` (explicit) and `issue #N` (anything the change
#            talks about, a sandbox's "seed issue #1" included). `[Ii]ssue` was added
#            per #170; the ASCII lookbehind keeps `reissue #5` out.
# References to other repositories are removed from all three first.
# Commits and prose together: a number in both wins. With no overlap, commits win
# over `issue #N`, but disagreeing with an explicit Refs/Closes/Fixes they are both
# offered and a person chooses: neither alone is reliable enough to post silently.
detect_candidates() {
  [ -d "$ARCHIVE_DIR" ] || return 0
  PIC_ARCHIVE_DIR="$ARCHIVE_DIR" PIC_REPO_ROOT="$REPO_ROOT" PIC_ARCHIVE_REL="$ARCHIVE_REL" \
  PIC_PRE_MOVE_REL="$PRE_MOVE_REL" PIC_GH_REPO="$GH_REPO" python3 -I - <<'PYEOF'
import os, re, subprocess, sys

arch = os.environ["PIC_ARCHIVE_DIR"]
root = os.environ["PIC_REPO_ROOT"]
paths = [p for p in (os.environ["PIC_ARCHIVE_REL"], os.environ["PIC_PRE_MOVE_REL"]) if p]
gh_repo = os.environ["PIC_GH_REPO"]

def read(path):
    try:
        with open(path, "rb") as fh:
            return fh.read().decode("utf-8", "surrogateescape")
    except OSError:
        return ""

# owner/repo, bounded so a long token cannot make the match expensive, and never
# across a line break. Preceded by nothing that would make it part of a path.
XREF = re.compile(r"(?<![A-Za-z0-9_./-])(?:(?:-R|--repo)[ \t]+)?`?"
                  r"([A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]{1,100})`?"
                  r"(?:[ \t]+[Ii]ssue)?[ \t]*#(\d+)")
def strip(text):
    return XREF.sub(lambda m: f"issue #{m.group(2)}" if m.group(1).lower() == gh_repo.lower() else " ",
                    text)

def nums(pattern, text):
    return {int(n) for m in pattern.finditer(text) for n in re.findall(r"#(\d+)", m.group(0))}

MARKER = re.compile(r"\*\*GitHub-side tracker\*\*[^#\n]*#\d+")
STRONG = re.compile(r"(?<![A-Za-z0-9_])(?:Refs|Closes|Fixes) #\d+")
WEAK = re.compile(r"(?<![A-Za-z0-9_])[Ii]ssue #\d+")
GROUP = re.compile(r"\((?:[Rr]efs[ \t]+)?#\d+(?:[ \t,]+#\d+)*\)")
# A body line that starts with Refs: every #N on it, so "Refs #137 Refs #150" keeps both.
BODY_REFS = re.compile(r"(?im)^[ \t]*refs\b[^\n]*")
ANY = re.compile(r"#\d+")

def emit(cands, ask=False):
    for n in sorted(cands):
        print(n)
    if ask and cands:
        print("?ask")
    sys.exit(0)

markers = nums(MARKER, strip(read(os.path.join(arch, "proposal.md")) + "\n" + read(os.path.join(arch, "design.md"))))
if markers:
    emit(markers)

prose_text = strip("\n".join(read(os.path.join(arch, f)) for f in sorted(os.listdir(arch))
                             if f.endswith(".md") and os.path.isfile(os.path.join(arch, f))))
strong, weak = nums(STRONG, prose_text), nums(WEAK, prose_text)

commits = set()
if root and paths:
    out = subprocess.run(["git", "-C", root, "--literal-pathspecs", "log", "--format=%x1e%s%x1f%b",
                          "-50", "--", *paths], capture_output=True)
    records = []
    for rec in out.stdout.decode("utf-8", "surrogateescape").split("\x1e")[1:]:
        subject, _, body = rec.partition("\x1f")
        records.append((strip(subject), strip(body)))
    commits = {n for s, b in records for n in nums(GROUP, s) | nums(BODY_REFS, b)}
    if not commits:
        commits = {n for s, _ in records for n in nums(ANY, s)}

unverified = set()
for n in sorted(commits):
    r = subprocess.run(["gh", "api", f"repos/{gh_repo}/issues/{n}", "--jq",
                        'if .pull_request then "pr" else "issue" end'], capture_output=True, text=True)
    kind = r.stdout.strip() if r.returncode == 0 else ("missing" if "404" in r.stderr else "unknown")
    if kind in ("pr", "missing"):
        commits.discard(n)
    elif kind != "issue":
        unverified.add(n)

prose = strong | weak
if commits and prose:
    both = commits & prose
    if both:
        emit(both, ask=bool(both & unverified))
    if strong:
        emit(strong | commits, ask=True)
    emit(commits, ask=bool(unverified))
if commits:
    emit(commits, ask=bool(unverified))
emit(prose)
PYEOF
}

# Runs detection and splits its answer: CANDIDATES (one per line) and ASK (1 when a
# person must choose). A detection that fails is reported, never read as "none".
run_detection() {
  local out
  if ! out=$(detect_candidates); then
    emit_outcome "(failed — candidate detection errored; nothing posted, archive itself succeeded; pass --force-linked-issue <N> if you know the issue)" 0
  fi
  CANDIDATES=$(printf '%s\n' "$out" | grep -E '^[0-9]+$' || true)
  ASK=0
  printf '%s\n' "$out" | grep -qx '?ask' && ASK=1
  return 0
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
  run_detection
  if [ -z "$CANDIDATES" ]; then
    emit_outcome "(failed — --linked-issue $LINKED_ISSUE_RESOLVED given but detection found no candidates; if you know the issue number authoritatively, re-invoke with --force-linked-issue $LINKED_ISSUE_RESOLVED)" 0
  fi
  if ! echo "$CANDIDATES" | grep -qx -- "$LINKED_ISSUE_RESOLVED"; then
    emit_outcome "(failed — --linked-issue $LINKED_ISSUE_RESOLVED not in candidate set: $(echo "$CANDIDATES" | tr '\n' ' '))" 0
  fi
  LINKED_ISSUE="$LINKED_ISSUE_RESOLVED"
else
  run_detection
  CANDIDATE_COUNT=$(echo "$CANDIDATES" | grep -c . || true)
  # Normalize empty/blank cases
  if [ -z "$CANDIDATES" ]; then CANDIDATE_COUNT=0; fi

  case "$CANDIDATE_COUNT" in
    0)
      emit_outcome "(none — no linked issue detected)" 0
      ;;
    1)
      # One candidate is used without asking, unless detection flagged it: its
      # issue/PR check could not run, so it might be a pull request (#405).
      if [ "$ASK" = 1 ]; then
        echo "$CANDIDATES" > /tmp/spectra-archive-candidates.txt
        emit_outcome "(pending — 1 candidate needs confirmation (could not check whether #$CANDIDATES is an issue or a pull request): $CANDIDATES; see /tmp/spectra-archive-candidates.txt; re-invoke with --linked-issue <N>)" 75
      fi
      LINKED_ISSUE="$CANDIDATES"
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

python3 -I - <<'PYEOF'
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

# The level is the caller's (it reviewed the dry-run body); the repository's level,
# as rules/privacy-scrubbing.md resolves it, is a floor that can only make it
# stricter. `enforce` means a person must post it, so this script does not.
if ! PERM=$(gh repo view "$GH_REPO" --json viewerPermission,isPrivate \
        --jq '"\(.viewerPermission)/\(.isPrivate)"' 2>/dev/null) || [ -z "$PERM" ]; then
  rm -f "$BODY_FILE"
  emit_outcome "(failed — could not read your permissions on $GH_REPO (gh auth or network?); nothing posted, archive itself succeeded)" 0
fi
case "$PERM" in
  ADMIN/true|MAINTAIN/true|WRITE/true)    REPO_LEVEL=light ;;
  ADMIN/false|MAINTAIN/false|WRITE/false) REPO_LEVEL=warn ;;
  *)                                      REPO_LEVEL=enforce ;;
esac
rank() { case "$1" in light) echo 0 ;; warn) echo 1 ;; *) echo 2 ;; esac; }
SCRUB_LEVEL="$SCRUB_ATTESTED"
[ "$(rank "$REPO_LEVEL")" -gt "$(rank "$SCRUB_LEVEL")" ] && SCRUB_LEVEL="$REPO_LEVEL"
if [ "$SCRUB_LEVEL" = "enforce" ]; then
  rm -f "$BODY_FILE"
  emit_outcome "(failed — not posted at level enforce (your permission on $GH_REPO: ${PERM%%/*}); post the dry-run body by hand after review; archive itself succeeded)" 0
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
  emit_outcome "(failed — gh-egress refused the comment (exit $EGRESS_RC): $EGRESS_REASON; nothing posted, archive itself succeeded; do not edit the archived files: post a corrected copy of the dry-run body by hand through gh-egress.sh)" 0
fi
if [ "$EGRESS_RC" -ne 0 ] || [ -z "$COMMENT_URL" ]; then
  emit_outcome "(failed — gh issue comment errored (exit $EGRESS_RC): ${EGRESS_REASON:-no message}; archive itself succeeded)" 0
fi

emit_outcome "$COMMENT_URL" 0
