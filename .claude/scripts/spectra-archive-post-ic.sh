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
#  75  — a person must choose: several candidates, or one that no explicit source
#         confirms; candidates written to candidates-<change-name>.txt in the state directory
#         agent MUST prompt user via AskUserQuestion and re-invoke with --linked-issue <N>
#
# Stdout: outcome message OR IC comment URL (single line)
# Stderr: diagnostic info
# Outcome file: same content as stdout, persistent across Bash tool calls.
#   The path is DERIVED INTERNALLY from --change-name:
#     ${SPECTRA_POST_IC_STATE_DIR:-~/.cache/idd/spectra-archive}/outcome-<change-name>.txt
#   --change-name is allowlist-validated (^[A-Za-z0-9_-]+$) before being used in
#   the path, so the derived path is always traversal-safe and the formula has a
#   single source of truth (this script). A caller (SKILL.md Step 8) recomputes
#   the same path from the same --change-name to read the outcome across Bash
#   tool calls. --outcome-file may override the path but is rejected if it
#   contains '..' (path traversal) — see #56 R5-S1 / L1 verify findings.
#
# DRY RUN: when --dry-run is passed, nothing is written to GitHub. The composed body
# and the resolved issue are kept for review in a private directory,
# ${SPECTRA_POST_IC_STATE_DIR:-~/.cache/idd/spectra-archive} (mode 700), as
# body-<change>.md and target-<change>.txt. Read-only lookups still run: whether a
# candidate number is an issue or a pull request, so a dry run picks the same issue
# the real run will (#405). The real run composes the body again and posts only if
# both the body and the issue match what the dry run kept: what was reviewed is what
# is posted. Used by Step 7's review pass and by the tests in
# .claude/scripts/tests/spectra-archive-post-ic/.
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
# No outcome file until the change name has passed the allowlist and the private state
# directory exists (#405): the early refusals go to stdout only, not to a fixed name in
# the shared /tmp that another account could plant or read.
OUTCOME_FILE=""
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
      awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' "$0"
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
  [ -n "$OUTCOME_FILE" ] && { printf '%s\n' "$msg" > "$OUTCOME_FILE"; } 2>/dev/null
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

# ── The private state directory (#405) ──
# Everything this step keeps lives here, mode 700: the outcome, the candidate list, and
# the body and issue a dry run keeps for review. Not the shared /tmp, where another
# session, a test run or another account could plant, read or replace a fixed name.
STATE_DIR="${SPECTRA_POST_IC_STATE_DIR:-$HOME/.cache/idd/spectra-archive}"
if [ -L "$STATE_DIR" ] || ! mkdir -p "$STATE_DIR" 2>/dev/null || ! chmod 700 "$STATE_DIR" 2>/dev/null; then
  emit_outcome "(failed — cannot use $STATE_DIR for this step's files; nothing kept or posted, archive itself succeeded)" 0
fi
REVIEW_BODY="$STATE_DIR/body-$CHANGE_NAME.md"
REVIEW_TARGET="$STATE_DIR/target-$CHANGE_NAME.txt"
CANDIDATES_FILE="$STATE_DIR/candidates-$CHANGE_NAME.txt"

# ── Derive the change-name-scoped outcome path (single source of truth) ──
# $CHANGE_NAME has just passed the allowlist (^[A-Za-z0-9_-]+$), so it cannot
# contain '/', '.', or shell metacharacters — the derived path is traversal-safe.
# A caller (SKILL.md Step 8) recomputes this exact path from the same
# --change-name to read the outcome across separate Bash tool calls.
# Skip the reassignment when --outcome-file was explicitly given (already
# traversal-checked above) so callers retain an escape hatch / tests can override.
if [ "$OUTCOME_FILE_EXPLICIT" = "0" ]; then
  OUTCOME_FILE="$STATE_DIR/outcome-${CHANGE_NAME}.txt"
fi

# ── A real post needs the caller's privacy review (#405) ──
# Checked before any lookup: without it nothing will be posted, so there is no
# reason to resolve candidates first.
if [ "$DRY_RUN" = "0" ] && [ -z "$SCRUB_ATTESTED" ]; then
  emit_outcome "(failed — not posted: run this step with --dry-run, review $REVIEW_BODY per plugins/issue-driven-dev/rules/privacy-scrubbing.md, then re-run with --scrub-attested <level>; archive itself succeeded)" 0
fi
# Detection only proposes (#405): four verify rounds showed that no rule can tell, from
# text and history, that a number is this change's issue. The dry run prints the issue it
# chose and its title; whoever reviews the body checks that too, and names it here.
if [ "$DRY_RUN" = "0" ] && [ -z "$LINKED_ISSUE_RESOLVED" ] && [ -z "$FORCE_LINKED_ISSUE" ]; then
  emit_outcome "(failed — not posted: name the issue you confirmed in the review with --linked-issue <N> (or --force-linked-issue <N>); the dry run printed the one it chose and its title; archive itself succeeded)" 0
fi

# ── Resolve GH_REPO ──
if [ -n "$GH_REPO_ARG" ]; then
  GH_REPO="$GH_REPO_ARG"
else
  # Resolved where the archive lives, not in the caller's cwd: running from another
  # repository must not move the comment there (#405). gh's own default (including
  # `gh repo set-default` for a fork) applies.
  GH_REPO=$( (cd "$ARCHIVE_DIR" 2>/dev/null && gh repo view --json nameWithOwner -q .nameWithOwner) 2>/dev/null || true)
fi

if [ -z "$GH_REPO" ]; then
  emit_outcome "(failed — cannot resolve GitHub repo from the archive's repository: pass --gh-repo)" 0
fi
if ! [[ "$GH_REPO" =~ ^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9_.-]+$ ]]; then
  emit_outcome "(failed — GitHub repo '$GH_REPO' is not owner/repo)" 2
fi

# ── Archive basename (no date recomputation; derived from passed archive-dir) ──
ARCHIVE_BASENAME=$(basename "$ARCHIVE_DIR")

# ── The archive's own repository (#405) ──
# Everything below that reads git history or names a path works in the repository
# the archive lives in, never the caller's cwd: a caller in /tmp, or in another
# repository, must not change which issue gets the comment. That repository is used
# only when one of its remotes (origin, or upstream for a fork) is $GH_REPO; anything
# else (a fixture tree, a home-directory repo) gives no commit evidence and no path
# prefix. Only owner/repo is compared, not the host.
REPO_ROOT=""
ARCHIVE_REL=""
lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
if TOP=$(git -C "$ARCHIVE_DIR" rev-parse --show-toplevel 2>/dev/null) \
   && REL=$(git -C "$ARCHIVE_DIR" rev-parse --show-prefix 2>/dev/null) && [ -n "${REL%/}" ]; then
  for REMOTE in $(git -C "$TOP" remote 2>/dev/null); do
    REMOTE_REPO=$(git -C "$TOP" remote get-url "$REMOTE" 2>/dev/null \
      | sed -E 's#/*$##; s#\.git$##; s#.*[:/]([^/]+/[^/]+)$#\1#')
    if [ -n "$REMOTE_REPO" ] && [ "$(lower "$REMOTE_REPO")" = "$(lower "$GH_REPO")" ]; then
      REPO_ROOT="$TOP"
      ARCHIVE_REL="${REL%/}"
      break
    fi
  done
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
# one candidate per line, then `?ask <reason>` when a person must choose even with a
# single candidate.
#
# Detection proposes; it never approves. A real post needs --linked-issue (or
# --force-linked-issue) from whoever reviewed the dry run, which prints the issue it chose
# and its title. Four verify rounds (#405) found, every round, some way of writing or some
# history (a squash, a sweeping commit, a reused change name) that made a rule pick the
# wrong issue; a reader checking the title catches what no rule here can.
#
# It proposes one issue without listing alternatives in exactly two cases:
#   1. marker   `**GitHub-side tracker**: #N` (that form, the number right after the label)
#               in proposal.md or design.md, outside code, names one issue of this
#               repository, and neither the commits nor an explicit reference name another.
#   2. commits  the commits that touched the change (the archive path and the path
#               before the move: Step 7 runs before the archive is committed) name one
#               issue, as the commit rule (rules/commit-issue-reference.md) writes it: a
#               parenthesised group in the subject, `(#N)`, a body line `Refs #N`, or a
#               squash body's `* subject (#N)` line; and no explicit reference, in the
#               change's text or in those commit messages, names another issue.
# Everything else is offered (exit 75, with the reason): explicit prose (GitHub's closing
# keywords and ref/refs, any case, with or without a colon, lists included, and
# `referencing issue #N`, the form /spectra-propose writes) outside code; weak prose
# (`issue #N`, `(#N)`, `（#N）`, this repository's issue URLs, and explicit forms inside
# code, which quote something); a tracker line in any other form; and a bare `#N` in a
# subject when no commit has a group (the spike's subject named the sandbox's `PR #4`).
# When none of these finds anything, any `#N` outside code is offered.
# References to other repositories are removed first; this repository's full form
# `owner/repo#N` keeps its role. Every number is checked against the issues API: pull
# requests (a squash adds the PR number as a group) and numbers that do not exist are
# dropped, and one that cannot be checked forces the question.
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

REPO = r"[A-Za-z0-9][A-Za-z0-9-]{0,38}/[A-Za-z0-9_.-]{1,100}"
# Another repository's reference, in every shape the change's text uses: `owner/repo#N`,
# `owner/repo issue #N`, a backticked `owner/repo` before either, and `-R`/`--repo owner/repo
# [issue] #N`. `owner/repo #N` with only a space is not one (`issue/PR #400` is prose). Bounded
# so a long token cannot make the match expensive, never across a line break, and preceded by
# nothing that would make it part of a path.
XREF = re.compile(r"(?<![A-Za-z0-9_./-])(?:"
                  r"(?:-R|--repo)[ \t]+`?(?P<r1>" + REPO + r")`?[ \t]+(?:(?P<i1>[Ii]ssue)[ \t]+)?"
                  r"|`(?P<r2>" + REPO + r")`(?:[ \t]+(?P<i2>[Ii]ssue))?[ \t]*"
                  r"|(?P<r3>" + REPO + r")(?:[ \t]+(?P<i3>[Ii]ssue)[ \t]+)?"
                  r")#(?P<n>\d+)")
URL = re.compile(r"https?://github\.com/(?P<r>" + REPO + r")/(?:issues|pull)/(?P<n>\d+)[^\s)\]>]*")
# GitHub's closing keywords (close, closes, closed, fix, fixes, fixed, resolve, resolves,
# resolved, in any case) and ref/refs, with or without a colon. The two branches keep the
# match linear on a keyword followed by a long run of blanks.
KW = r"(?i:close[sd]?|fix(?:e[sd])?|resolve[sd]?|refs?)(?:[ \t]*:[ \t]*|[ \t]*)"
# This repository's full form keeps its role. In a commit, after `(`, a keyword or another
# number of the same group it becomes `#N`, so `(owner/repo#52)` stays a group. In prose,
# only after a keyword or `issue `, so `Closes owner/repo#10` stays explicit; anywhere else
# it is a mention, `issue #N`, so it is never lost.
SHAPE_COMMIT = re.compile(r"(?:\(|" + KW + r"|#\d+[ \t,]+)$")
SHAPE_PROSE = re.compile(r"(?:" + KW + r"|[Ii]ssue[ \t]+)$")
def strip(text, prose=True):
    shape = SHAPE_PROSE if prose else SHAPE_COMMIT
    def keep(repo, mention, n, start):
        if repo.lower() != gh_repo.lower():
            return " "
        if mention or not shape.search(text[max(0, start - 16):start]):
            return f"issue #{n}"
        return f"#{n}"
    text = URL.sub(lambda m: keep(m.group("r"), False, m.group("n"), m.start()), text)
    return XREF.sub(lambda m: keep(m.group("r1") or m.group("r2") or m.group("r3"),
                                   m.group("i1") or m.group("i2") or m.group("i3"),
                                   m.group("n"), m.start()), text)

def nums(pattern, text):
    return {int(n) for m in pattern.finditer(text) for n in re.findall(r"#(\d+)", m.group(0))}

# One marker runs to the next marker or the end of its line. Only the anchored form is a
# declaration: the label, then this repository's `#N` right away (`owner/repo#N` allowed for
# this repository), then the end of the number. A sentence in that place is offered.
MARKER = re.compile(r"\*\*GitHub-side tracker\*\*(?:(?!\*\*GitHub-side tracker\*\*)[^\n])*")
ANCHORED = re.compile(r"\*\*GitHub-side tracker\*\*[ \t]*:?[ \t]*(?:\*\*)?(?:(?P<r>" + REPO + r"))?#(?P<n>\d+)"
                      r"(?=[\s.,;:)）。，、*]|$)")
STRONG = re.compile(r"(?<![A-Za-z0-9_])(?:" + KW + r"\[?#\d+(?:(?:(?:[ \t]*,)+[ \t]*|[ \t]+and[ \t]+)(?:issue[ \t]+)?\[?#\d+)*"
                    r"|[Rr]eferenc(?:e|es|ed|ing)[ \t]+issue[ \t]+#\d+)")
WEAK = re.compile(r"(?<![A-Za-z0-9_])[Ii]ssue[ \t]+#\d+|[（(]#\d+[）)]")
GROUP = re.compile(r"\((?:[Rr]efs[ \t]+)?#\d+(?:[ \t,]+#\d+)*\)")
# A body line that starts with Refs: every #N on it, so "Refs #137 Refs #150" keeps both.
BODY_REFS = re.compile(r"(?im)^[ \t]*refs\b[^\n]*")
# A squash commit lists the PR's commits as `* subject (#N)` lines in its body.
SQUASH_LINE = re.compile(r"(?m)^[ \t]*[*-][ \t]+[^\n]*")
ANY = re.compile(r"#\d+")
REPO_WORD = re.compile(r"(?<![A-Za-z0-9_./:-])(" + REPO + r")")
# A Refs/Closes/Fixes inside code (a fence or `inline`) quotes something, often another
# repository's PR body; it counts only as weak prose. The spike quoted the sandbox's
# `Refs #1` and `Refs #3` this way. Examples of the tracker marker in code are not markers.
CODE = re.compile(r"(?ms)^[ \t]*(```|~~~).*?^[ \t]*\1|`[^`\n]*`")
def blank_code(text, fill=" "):
    """Code replaced by `fill`, keeping every offset, so a span found here is the same span
    in the raw text."""
    return CODE.sub(lambda m: fill * len(m.group(0)), text)

LIMIT = 40
kinds = {}
def kind(n):
    """issue, pr, missing or unknown. Only gh's own (HTTP 404) means missing: a transport
    error prints the request URL, and that may contain 404 anywhere."""
    if n not in kinds:
        if len(kinds) >= LIMIT:
            fail(f"more than {LIMIT} numbers to check; name the issue with --force-linked-issue")
        r = subprocess.run(["gh", "api", f"repos/{gh_repo}/issues/{n}", "--jq",
                            'if .pull_request then "pr" else "issue" end'], capture_output=True, text=True)
        if r.returncode == 0:
            v = r.stdout.strip()
            kinds[n] = v if v in ("issue", "pr") else "unknown"
        elif "(HTTP 404)" in r.stderr:
            repo_readable()
            kinds[n] = "missing"
        else:
            kinds[n] = "unknown"
    return kinds[n]

readable = []
def repo_readable():
    """GitHub answers 404 for every issue of a repository you cannot see, so a 404 is
    only "missing" once the repository itself answers. Otherwise detection fails."""
    if not readable:
        r = subprocess.run(["gh", "api", f"repos/{gh_repo}", "--jq", ".full_name"],
                           capture_output=True, text=True)
        if r.returncode != 0:
            fail(f"cannot read repos/{gh_repo}, so every issue would look missing")
        readable.append(True)

def postable(numbers):
    """The numbers that are issues or could not be checked, and whether any could not."""
    keep = {n for n in numbers if kind(n) in ("issue", "unknown")}
    return keep, any(kinds[n] == "unknown" for n in keep)

# Why a person must choose, when one is needed. Every reason is shown, the unchecked
# issue/PR first, because it is the one a title cannot settle.
reasons = []
# Where each number came from, printed for the review: a title alone cannot tell an old
# issue with the same subject from this change's own.
sources = {}
def note(numbers, how):
    for n in numbers:
        sources.setdefault(n, [])
        if how not in sources[n] and len(sources[n]) < 3:
            sources[n].append(how)

def fail(reason):
    print("?fail " + reason)
    sys.exit(0)

def emit(cands, ask=None, check=True):
    if ask:
        reasons.append(ask)
    unsure = False
    if check:
        cands, unsure = postable(cands)
    shown = (["could not check whether every number is an issue or a pull request"] if unsure else []) \
        + [r for i, r in enumerate(reasons) if r not in reasons[:i]]
    for n in sorted(cands):
        print(n)
        print(f"?src {n} " + "; ".join(sources.get(n, ["the text of the change"])))
    if shown and cands:
        print("?ask " + "; ".join(shown))
    sys.exit(0)

# ── Evidence ──
raw_md = read(os.path.join(arch, "proposal.md")) + "\n" + read(os.path.join(arch, "design.md"))
markers, marker_offer, marker_problem = set(), set(), None
def other_repo_on(seg):
    """Whether a tracker line names another repository anywhere: a reference, a URL, or a
    bare owner/repo word."""
    return (any((x.group("r1") or x.group("r2") or x.group("r3")).lower() != gh_repo.lower()
                for x in XREF.finditer(seg))
            or any(x.group("r").lower() != gh_repo.lower() for x in URL.finditer(seg))
            or any(t.lower() != gh_repo.lower() for t in REPO_WORD.findall(URL.sub(" ", seg))))
# Code is filled with a letter, not blanks, so `**GitHub-side tracker**: `other/x`#9` cannot
# turn into an anchored `#9`; the raw span is what is checked for other repositories.
for m in MARKER.finditer(blank_code(raw_md, "x")):
    a = ANCHORED.match(m.group(0))
    seg = raw_md[m.start():m.end()]
    elsewhere = other_repo_on(seg)
    if a and not elsewhere and (not a.group("r") or a.group("r").lower() == gh_repo.lower()):
        markers.add(int(a.group("n")))
        note([int(a.group("n"))], "the GitHub-side tracker")
    else:
        marker_problem = ("the GitHub-side tracker is not `**GitHub-side tracker**: #N` "
                          "for an issue of this repository")
        # Its numbers are offered, unless the line is about another repository: then they
        # are that repository's (a sandbox's PR, say).
        if not elsewhere:
            found = nums(ANY, strip(seg))
            marker_offer |= found
            note(found, "a GitHub-side tracker line not in the anchored form")
if markers:
    good, unsure = postable(markers)
    if markers - good:
        marker_problem = "the GitHub-side tracker is a pull request or does not exist"
    if unsure and not marker_problem:
        marker_problem = "could not check whether the tracker is an issue or a pull request"
    markers = good

raw_text = "\n".join(read(os.path.join(arch, f)) for f in sorted(os.listdir(arch))
                     if f.endswith(".md") and os.path.isfile(os.path.join(arch, f)))
# Emphasis is dropped for reading references, so `**Closes**: #400` is a Closes.
prose_text = strip(raw_text).replace("**", "")
outside_code = blank_code(prose_text)
strong = nums(STRONG, outside_code)
weak = nums(WEAK, prose_text) | nums(STRONG, prose_text)
note(strong, "an explicit reference in the change's text")
note(weak - strong, "a mention in the change's text")

commits, fallback = set(), set()
if root and paths:
    out = subprocess.run(["git", "-C", root, "--literal-pathspecs", "log", "--format=%x1e%h%x1f%s%x1f%b",
                          "-50", "--", *paths], capture_output=True)
    records = []
    for rec in out.stdout.decode("utf-8", "surrogateescape").split("\x1e")[1:]:
        sha, _, rest = rec.partition("\x1f")
        subject, _, body = rest.partition("\x1f")
        records.append((sha, strip(subject, prose=False), strip(body, prose=False)))
    for sha, s, b in records:
        named = nums(GROUP, s) | nums(BODY_REFS, b) | {k for line in SQUASH_LINE.findall(b) for k in nums(GROUP, line)}
        commits |= named
        note(named, f"commit {sha} {s[:60].strip()}")
        # An explicit keyword in a commit message is an anchor too: `Closes #400` in the body
        # of a commit whose group is (#20) names a second issue.
        kw = nums(STRONG, s) | nums(STRONG, b)
        strong |= kw
        note(kw - named, f"an explicit reference in commit {sha}")
    if not commits:
        fallback = {n for _, s, _ in records for n in nums(ANY, s)}
        note(fallback, "a bare number in a commit subject")

commits, _ = postable(commits)
strong, _ = postable(strong)

# ── Decision: two proposals without a question, everything else offered ──
# Case 1: the tracker, when nothing explicit and no commit names another issue.
if markers and not marker_problem:
    others = (strong | commits) - markers
    if not others:
        emit(markers, check=False)
    emit(markers | others, ask="the tracker and the commits or an explicit reference name different issues",
         check=False)
if marker_problem:
    reasons.append(marker_problem)
extra = markers | marker_offer

# Case 2: the commits name one issue, nothing explicit names another, and no tracker
# disagrees (a tracker problem is already a reason to ask).
if len(commits) == 1 and not (strong - commits):
    emit(commits | extra)
if commits:
    reason = ("an explicit reference names an issue that no commit names" if strong - commits
              else "the commits name more than one issue")
    emit(commits | strong | extra, ask=reason)
reason = ("only a bare number in a commit subject names it" if fallback
          else "only the text of the change names it")
offer, _ = postable(strong | weak | fallback | extra)
# Nothing recognised at all: any `#N` outside code is offered rather than reporting no
# linked issue, because a missed issue loses its Implementation Complete without a word.
# Other repositories' references are removed first, in every shape strip() knows.
if not offer:
    found = nums(ANY, blank_code(strip(raw_text)))
    note(found, "a bare number in the change's text")
    offer, _ = postable(found)
    reason = "only a bare number in the text of the change names it"
if not offer and marker_problem:
    # A tracker was declared and cannot be used, and nothing else names an issue: that is a
    # failure to report, not "no linked issue".
    fail(marker_problem + ", and nothing else names an issue")
emit(offer, ask=reason)
PYEOF
}

# Writes the candidate list in the state directory, by rename, and checks it landed as a
# regular file. Where each one came from goes to stderr for the person choosing.
write_candidates() {
  local tmp f="$CANDIDATES_FILE"
  rm -f "$f" 2>/dev/null
  tmp=$(mktemp "$STATE_DIR/.candidates.XXXXXX") && printf '%s\n' "$CANDIDATES" > "$tmp" \
    && mv -f "$tmp" "$f" && [ -f "$f" ] && [ ! -L "$f" ] || {
      rm -f "${tmp:-}"
      emit_outcome "(failed — could not write the candidate list in $STATE_DIR; candidates: $(printf '%s ' $CANDIDATES); re-run the dry run with --linked-issue <N>)" 0
    }
  [ -n "$SOURCES" ] && printf '%s\n' "$SOURCES" | sed 's/^\([0-9]*\) /candidate #\1 from: /' >&2
}

# A title is text whoever opened the issue wrote: control characters and bidi overrides are
# removed and it is cut short, so it reads as data in the line the reviewer acts on.
clean_title() {
  printf '%s' "$1" | LC_ALL=C tr -d '\000-\037\177' \
    | LC_ALL=C sed $'s/\xe2\x80[\xaa-\xae]//g; s/\xe2\x81[\xa6-\xa9]//g' | cut -c1-200
}

# Runs detection and splits its answer: CANDIDATES (one per line) and ASK (1 when a
# person must choose). A detection that fails is reported, never read as "none".
run_detection() {
  local out fail
  if ! out=$(detect_candidates); then
    emit_outcome "(failed — candidate detection errored; nothing posted, archive itself succeeded; pass --force-linked-issue <N> if you know the issue)" 0
  fi
  fail=$(printf '%s\n' "$out" | sed -n 's/^?fail //p' | head -1)
  if [ -n "$fail" ]; then
    emit_outcome "(failed — candidate detection: $fail; nothing posted, archive itself succeeded; pass --force-linked-issue <N> if you know the issue)" 0
  fi
  CANDIDATES=$(printf '%s\n' "$out" | grep -E '^[0-9]+$' || true)
  SOURCES=$(printf '%s\n' "$out" | sed -n 's/^?src //p')
  ASK=0
  ASK_REASON=$(printf '%s\n' "$out" | sed -n 's/^?ask //p' | head -1)
  [ -n "$ASK_REASON" ] && ASK=1
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
  # Read-only, so the dry run checks it too: `gh issue view` also succeeds for a pull
  # request, so the issues API says which it is (#405).
  FORCED_KIND=$(gh api "repos/$GH_REPO/issues/$FORCE_LINKED_ISSUE" \
    --jq 'if .pull_request then "pr" else "issue" end' 2>/dev/null) || FORCED_KIND=""
  case "$FORCED_KIND" in
    issue) ;;
    pr) emit_outcome "(failed — --force-linked-issue $FORCE_LINKED_ISSUE is a pull request in $GH_REPO, not an issue)" 0 ;;
    *)  emit_outcome "(failed — --force-linked-issue $FORCE_LINKED_ISSUE: issue not found in $GH_REPO, or it could not be read)" 0 ;;
  esac
  FORCED_TITLE=$(clean_title "$(gh issue view "$FORCE_LINKED_ISSUE" --repo "$GH_REPO" --json title -q .title 2>/dev/null || true)")
  SOURCES="$FORCE_LINKED_ISSUE --force-linked-issue"
  echo "→ FORCE-LINKED to #${FORCE_LINKED_ISSUE}: ${FORCED_TITLE} (authoritative override — detection & membership bypassed)" >&2
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
  # A candidate whose issue/PR check could not run is offered, not trusted: the number the
  # reviewer names must be an issue (#405).
  LINKED_KIND=$(gh api "repos/$GH_REPO/issues/$LINKED_ISSUE_RESOLVED" \
    --jq 'if .pull_request then "pr" else "issue" end' 2>/dev/null) || LINKED_KIND=""
  case "$LINKED_KIND" in
    issue) ;;
    pr) emit_outcome "(failed — --linked-issue $LINKED_ISSUE_RESOLVED is a pull request in $GH_REPO, not an issue)" 0 ;;
    *)  emit_outcome "(failed — --linked-issue $LINKED_ISSUE_RESOLVED: could not check that it is an issue in $GH_REPO; nothing posted)" 0 ;;
  esac
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
      # One candidate is used without asking, unless detection flagged it (#405): its
      # issue/PR check could not run, or the tracker marker could not be used.
      if [ "$ASK" = 1 ]; then
        write_candidates
        emit_outcome "(pending — 1 candidate needs confirmation ($ASK_REASON): $CANDIDATES; see candidates-$CHANGE_NAME.txt in the state directory; re-run the dry run with --linked-issue <N>)" 75
      fi
      LINKED_ISSUE="$CANDIDATES"
      ;;
    *)
      # Multi-candidate: write to file + exit 75 → agent prompts + re-invokes
      write_candidates
      emit_outcome "(pending — $CANDIDATE_COUNT candidates detected${ASK_REASON:+ ($ASK_REASON)}: $(echo "$CANDIDATES" | tr '\n' ' '); see candidates-$CHANGE_NAME.txt in the state directory; re-run the dry run with --linked-issue <N>)" 75
      ;;
  esac
fi

# ── Step B: Idempotent guard (per-archive sentinel) ──
SENTINEL="auto-posted by spectra-archive for ${ARCHIVE_BASENAME}"
ANCHOR_SUFFIX="${FORCE_NOTE:-}"

# Read-only, so the dry run runs it too: an archive already posted is not reviewed again.
# Only comments by the repository's owner, members or collaborators count, so nobody else
# can block the post by writing the sentinel (#405).
ALREADY_POSTED=$(gh issue view "$LINKED_ISSUE" --repo "$GH_REPO" --json comments \
  --jq '.comments[] | select(.authorAssociation == "OWNER" or .authorAssociation == "MEMBER" or .authorAssociation == "COLLABORATOR") | .body' 2>/dev/null \
  | grep -Fc -- "$SENTINEL" \
  | tr -d ' ')
# grep -Fc returns "0" with exit 1 when no match; pipeline status doesn't propagate
# so the value is clean. wc -l is more portable but grep -Fc handles fine here.
ALREADY_POSTED="${ALREADY_POSTED:-0}"

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

# A private directory (mktemp -d is 700) for the body that is compared and posted, so no
# other account can plant or swap a name between the comparison and the post (#405).
WORK_DIR=$(mktemp -d /tmp/spectra-archive-ic.XXXXXX) || {
  emit_outcome "(failed — mktemp errored)" 0
}
trap 'rm -rf "$WORK_DIR"' EXIT
BODY_FILE="$WORK_DIR/body.md"

# The archive's own date (its directory name), so the body a dry run kept still matches
# when the post comes after midnight UTC; the current UTC date only without one.
case "$ARCHIVE_BASENAME" in
  [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]-*) ARCHIVE_DATE="${ARCHIVE_BASENAME%"${ARCHIVE_BASENAME#??????????}"}" ;;
  *) ARCHIVE_DATE=$(date -u +%Y-%m-%d) ;;
esac

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
**Archived**: {archive_date}

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
# The repository as GitHub names it, host included: a dry run for one host or one name
# does not authorise a post to another (#405).
REPO_URL=$(gh repo view "$GH_REPO" --json url -q .url 2>/dev/null) || REPO_URL=""
if [ -z "$REPO_URL" ]; then
  emit_outcome "(failed — could not read $GH_REPO's URL (gh auth or network?); nothing kept or posted, archive itself succeeded)" 0
fi
REVIEW_KEY="$(printf '%s' "$REPO_URL" | tr '[:upper:]' '[:lower:]')#$LINKED_ISSUE"
if [ "$DRY_RUN" = "1" ]; then
  # Keep the body and the issue for review (#405). A new file in a 700 directory is
  # renamed over the old name, so a symlink planted at that name is replaced, never
  # followed, and nobody else can read a body the review may reject.
  if [ -L "$STATE_DIR" ] || ! mkdir -p "$STATE_DIR" || ! chmod 700 "$STATE_DIR"; then
    rm -f "$BODY_FILE"
    emit_outcome "(failed — cannot use $STATE_DIR for the review copy; nothing kept)" 0
  fi
  # rm first: mv onto a symlink to a directory would move the file into that directory.
  rm -f "$REVIEW_BODY" "$REVIEW_TARGET" 2>/dev/null
  KEEP_BODY=$(mktemp "$STATE_DIR/.body.XXXXXX") && KEEP_TARGET=$(mktemp "$STATE_DIR/.target.XXXXXX") \
    && cat "$BODY_FILE" > "$KEEP_BODY" && printf '%s\n' "$REVIEW_KEY" > "$KEEP_TARGET" \
    && mv -f "$KEEP_BODY" "$REVIEW_BODY" && mv -f "$KEEP_TARGET" "$REVIEW_TARGET" \
    && [ -f "$REVIEW_BODY" ] && [ ! -L "$REVIEW_BODY" ] && [ -f "$REVIEW_TARGET" ] && [ ! -L "$REVIEW_TARGET" ] || {
      rm -f "$BODY_FILE" "${KEEP_BODY:-}" "${KEEP_TARGET:-}"
      emit_outcome "(failed — could not write the review copy in $STATE_DIR; nothing kept)" 0
    }
  rm -f "$BODY_FILE"
  PROPOSED=$(gh issue view "$LINKED_ISSUE" --repo "$GH_REPO" --json state,title -q '"\(.state)\t\(.title)"' 2>/dev/null || true)
  PROPOSED_STATE=$(clean_title "${PROPOSED%%$'\t'*}")
  PROPOSED_TITLE=$(clean_title "${PROPOSED#*$'\t'}")
  FROM=$(printf '%s\n' "${SOURCES:-}" | sed -n "s/^$LINKED_ISSUE //p" | head -1)
  echo "body for review: $REVIEW_BODY" >&2
  echo "issue for review: $REVIEW_KEY (${PROPOSED_STATE:-state unknown}) — ${PROPOSED_TITLE:-(title could not be read)}" >&2
  echo "  proposed from: ${FROM:-the text of the change}" >&2
  echo "  check it against this change's proposal (Step 7b) before naming it in the post" >&2
  emit_outcome "https://github.com/${GH_REPO}/issues/${LINKED_ISSUE}#issuecomment-DRY-RUN" 0
fi

# What is posted is what was reviewed: the same body bytes, to the same issue (#405).
# A body that changed (tasks.md edited, other --spec-deltas, a date after midnight UTC)
# or an issue that detection now resolves differently means a new dry run and review.
if [ ! -f "$REVIEW_BODY" ] || [ -L "$REVIEW_BODY" ] || ! cmp -s "$BODY_FILE" "$REVIEW_BODY" \
   || [ -L "$REVIEW_TARGET" ] || [ "$(cat "$REVIEW_TARGET" 2>/dev/null)" != "$REVIEW_KEY" ]; then
  rm -f "$BODY_FILE"
  emit_outcome "(failed — not posted: the body, the repository or the issue ($REVIEW_KEY) is not the one the dry run kept in $STATE_DIR; run the dry run again with the same arguments, review, then post; archive itself succeeded)" 0
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
if [ "$REPO_LEVEL" != enforce ] && [ "$(rank "$REPO_LEVEL")" -gt "$(rank "$SCRUB_LEVEL")" ]; then
  rm -f "$BODY_FILE"
  emit_outcome "(failed — not posted: --scrub-attested $SCRUB_ATTESTED is below $GH_REPO's own level $REPO_LEVEL; review $REVIEW_BODY at $REPO_LEVEL per rules/privacy-scrubbing.md, then re-run with --scrub-attested $REPO_LEVEL; archive itself succeeded)" 0
fi
if [ "$SCRUB_LEVEL" = "enforce" ] || [ "$REPO_LEVEL" = "enforce" ]; then
  rm -f "$BODY_FILE"
  emit_outcome "(failed — not posted at level enforce (your permission on $GH_REPO: ${PERM%%/*}); post $REVIEW_BODY by hand after review; archive itself succeeded)" 0
fi

EGRESS_ERR=$(mktemp "$WORK_DIR/err.XXXXXX") || {
  rm -f "$BODY_FILE"
  emit_outcome "(failed — mktemp errored)" 0
}
# Run from /: the wrapper's own Python reads its program from stdin, so the caller's
# cwd would come first on its import path. Every path it gets is absolute.
COMMENT_URL=$(cd / && bash "$EGRESS" comment "$LINKED_ISSUE" --repo "$GH_REPO" --body-file "$BODY_FILE" \
  --scrub-attested "$SCRUB_LEVEL" 2>"$EGRESS_ERR")
EGRESS_RC=$?
EGRESS_REASON=$(grep -v '^[[:space:]]*$' "$EGRESS_ERR" | head -3 | tr '\n' ' ' | LC_ALL=C tr -d '\000-\037' | cut -c1-300)
rm -f "$BODY_FILE" "$EGRESS_ERR"

# The wrapper's own refusals are 10 to 15; below that is gh's, and 126, 127 or 128+n
# mean the wrapper did not run to the end.
if [ "$EGRESS_RC" -ge 10 ] && [ "$EGRESS_RC" -le 15 ]; then
  emit_outcome "(failed — gh-egress refused the comment (exit $EGRESS_RC): $EGRESS_REASON; nothing posted, archive itself succeeded; do not edit the archived files: post a corrected copy of $REVIEW_BODY by hand through gh-egress.sh)" 0
fi
if [ "$EGRESS_RC" -ne 0 ] || [ -z "$COMMENT_URL" ]; then
  emit_outcome "(failed — gh-egress or gh issue comment errored (exit $EGRESS_RC): ${EGRESS_REASON:-no message}; archive itself succeeded)" 0
fi

rm -f "$REVIEW_BODY" "$REVIEW_TARGET"
emit_outcome "$COMMENT_URL" 0
