#!/usr/bin/env bash
# spec-change suite (#480) — scripts/spec-change.py, the four mechanical checks
# behind "every issue leaves a spec change or a declared exemption":
#   declared   read the **Spec**: line of an Implementation Complete comment
#   archived   are the declared changes archived at a revision
#   links      does every added or changed requirement carry an executable check
#   preflight  may the wrapper start writing a spec change here
#   ic         which comment is the issue's Implementation Complete
#
# Each block below maps one `##### Example:` table of the capability
# spec-on-every-issue, one check per row, with the table's values. The markers
# name the Examples this file checks (they are read by `spec-change.py links`):
#
# spec-example: spec-on-every-issue / reading the Spec line
# spec-example: spec-on-every-issue / whether the declared changes are archived at a commit
# spec-example: spec-on-every-issue / what the link check reports
# spec-example: spec-on-every-issue / preflight by write access and Spectra state
# spec-example: spec-on-every-issue / spec directory by .spectra.yaml
# spec-example: spec-on-every-issue / choosing the Implementation Complete comment
#
# Fixture specs below use the made-up capability `cap`, so the markers inside
# them never name a real Example.

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
SC="$HERE/../../spec-change.py"
PY=$(command -v python3)
GIT=$(command -v git)
WORK=$(mktemp -d "${TMPDIR:-/tmp}/idd-spec-change.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
# Isolate git from the caller's configuration (#452 lesson).
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.test GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.test

MARK='<!-- idd:comment type=implementation-complete -->'
FENCE='```'

field() { # key — print a field of the JSON line on stdin (lists and objects as JSON)
  "$PY" -c 'import json,sys
d = json.loads(sys.stdin.read() or "{}"); v = d.get(sys.argv[1], "<missing>")
print(json.dumps(v) if isinstance(v, (list, dict)) else v)' "$1"
}
run() { # subcommand args... → OUT, RC, LINES (stdout lines)
  OUT=$("$PY" "$SC" "$@" 2>"$WORK/err"); RC=$?
  LINES=$(printf '%s' "$OUT" | grep -c . || true)
}
comment() { # name body — write a comment file, print its path
  printf '%s\n' "$2" > "$WORK/$1.md"; printf '%s' "$WORK/$1.md"
}
newrepo() { # name → REPO (an empty git repo with one empty commit)
  REPO="$WORK/$1"; mkdir -p "$REPO"
  git -C "$REPO" init -q -b main
  git -C "$REPO" commit -q --allow-empty -m init
}
put() { # path [content] — write a file into $REPO
  mkdir -p "$(dirname "$REPO/$1")"; printf '%s\n' "${2:-x}" > "$REPO/$1"
}
commit() { git -C "$REPO" add -A && git -C "$REPO" commit -q -m "${1:-c}"; git -C "$REPO" rev-parse HEAD; }

# ── declared ────────────────────────────────────────────────────────────────
echo "spec-change: declared (Example: reading the Spec line)"

declared_case() { # label body form changes-json exit
  local f; f=$(comment "decl-$RANDOM$RANDOM" "$2")
  run declared --file "$f"
  assert_eq "declared: $1 — form" "$3" "$(printf '%s' "$OUT" | field form)"
  assert_eq "declared: $1 — changes" "$4" "$(printf '%s' "$OUT" | field changes)"
  assert_exit "declared: $1 — exit" "$5" "$RC"
  assert_eq "declared: $1 — one JSON line" 1 "$LINES"
}
declared_case "marker + one change" "$MARK
## Implementation Complete
**Spec**: change idd-42-fix-timeout" change '["idd-42-fix-timeout"]' 0
declared_case "marker + two changes, in order" "$MARK
**Spec**: change idd-42-fix-timeout, idd-42-fix2" change '["idd-42-fix-timeout", "idd-42-fix2"]' 0
declared_case "marker + no behaviour change" "$MARK
**Spec**: no behaviour change" no-behaviour-change '[]' 0
declared_case "marker + third-party clone" "$MARK
**Spec**: third-party clone" third-party-clone '[]' 0
declared_case "no marker, no Spec line" "## Implementation Complete
### Checklist
- [x] done" legacy '[]' 0
declared_case "no marker, a Spec line" "## Implementation Complete
**Spec**: no behaviour change" no-behaviour-change '[]' 0
declared_case "marker, no Spec line" "$MARK
## Implementation Complete" invalid '[]' 1
declared_case "marker, two Spec lines" "$MARK
**Spec**: change idd-42-a
**Spec**: no behaviour change" invalid '[]' 1
declared_case "marker, change with no name" "$MARK
**Spec**: change" invalid '[]' 1
declared_case "marker, a name that is a path" "$MARK
**Spec**: change ../x" invalid '[]' 1
declared_case "marker, an unknown form" "$MARK
**Spec**: nothing to see" invalid '[]' 1
declared_case "marker, the only Spec line is in a code fence" "$MARK
$FENCE
**Spec**: change idd-42-fix-timeout
$FENCE" invalid '[]' 1
run declared --file "$WORK/does-not-exist.md"
assert_exit "declared: a missing file — exit 2" 2 "$RC"
assert_eq "declared: a missing file — no JSON line" 0 "$LINES"
# boundaries beyond the table
declared_case "an upper-case name" "$MARK
**Spec**: change IDD-42-x" invalid '[]' 1
declared_case "a Spec line inside a tilde fence" "$MARK
~~~
**Spec**: no behaviour change
~~~" invalid '[]' 1
run declared
assert_exit "declared: no --file is a usage error" 64 "$RC"

# ── archived ────────────────────────────────────────────────────────────────
echo "spec-change: archived (Example: whether the declared changes are archived at a commit)"

archived_case() { # label comment-body ref status not-archived-json exit
  local f; f=$(comment "arch-$RANDOM$RANDOM" "$2")
  run archived --file "$f" --cwd "$REPO" --ref "$3"
  assert_eq "archived: $1 — status" "$4" "$(printf '%s' "$OUT" | field status)"
  [ -n "$5" ] && assert_eq "archived: $1 — not archived" "$5" "$(printf '%s' "$OUT" | field not_archived)"
  assert_exit "archived: $1 — exit" "$6" "$RC"
  assert_eq "archived: $1 — one JSON line" 1 "$LINES"
}
SPEC1="$MARK
**Spec**: change idd-42-fix-timeout"
newrepo arch-pass; put openspec/changes/archive/2026-11-10-idd-42-fix-timeout/proposal.md; R=$(commit)
archived_case "absent, archived" "$SPEC1" "$R" pass '[]' 0
newrepo arch-open; put openspec/changes/idd-42-fix-timeout/proposal.md; R=$(commit)
archived_case "present, not archived" "$SPEC1" "$R" refuse '["idd-42-fix-timeout"]' 1
newrepo arch-both; put openspec/changes/idd-42-fix-timeout/proposal.md; put openspec/changes/archive/2026-11-10-idd-42-fix-timeout/proposal.md; R=$(commit)
archived_case "present and archived" "$SPEC1" "$R" refuse '["idd-42-fix-timeout"]' 1
newrepo arch-none; put openspec/specs/x/spec.md; R=$(commit)
archived_case "absent, not archived" "$SPEC1" "$R" refuse '["idd-42-fix-timeout"]' 1
newrepo arch-prefix; put openspec/changes/archive/2026-11-10-idd-42-fix-timeout/proposal.md; R=$(commit)
archived_case "only an archive whose name extends it" "$MARK
**Spec**: change idd-42-fix" "$R" refuse '["idd-42-fix"]' 1
newrepo arch-two; put openspec/changes/archive/2026-11-10-idd-42-a/proposal.md; R=$(commit)
archived_case "two changes, one archived" "$MARK
**Spec**: change idd-42-a, idd-42-b" "$R" refuse '["idd-42-b"]' 1
# the three forms that are not read: pass even with a revision that does not exist
archived_case "no behaviour change (revision not read)" "$MARK
**Spec**: no behaviour change" no-such-rev pass '[]' 0
archived_case "third-party clone (revision not read)" "$MARK
**Spec**: third-party clone" no-such-rev pass '[]' 0
archived_case "a legacy comment (revision not read)" "## Implementation Complete" no-such-rev pass '[]' 0
archived_case "an invalid comment" "$MARK
**Spec**: nothing to see" "$R" refuse "" 1
archived_case "the revision does not exist" "$SPEC1" no-such-rev error "" 2
# boundaries beyond the table
newrepo arch-twice; put openspec/changes/archive/2026-11-10-idd-42-fix-timeout/proposal.md; put openspec/changes/archive/2026-11-12-idd-42-fix-timeout/proposal.md; R=$(commit)
archived_case "archived twice under the same name" "$SPEC1" "$R" refuse '["idd-42-fix-timeout"]' 1
newrepo arch-ref; put openspec/changes/idd-42-fix-timeout/proposal.md; R1=$(commit); git -C "$REPO" rm -q -r openspec/changes/idd-42-fix-timeout; put openspec/changes/archive/2026-11-10-idd-42-fix-timeout/proposal.md; R2=$(commit)
archived_case "the revision named is the one read (older commit)" "$SPEC1" "$R1" refuse '["idd-42-fix-timeout"]' 1
archived_case "the revision named is the one read (newer commit)" "$SPEC1" "$R2" pass '[]' 0
run archived --file "$(comment arch-usage "$SPEC1")" --cwd "$REPO"
assert_exit "archived: no --ref is a usage error" 64 "$RC"

# ── links ───────────────────────────────────────────────────────────────────
echo "spec-change: links (Example: what the link check reports)"

req() { # name body-lines... — print a requirement block
  local name="$1"; shift
  printf '### Requirement: %s\n\nThe system SHALL do %s.\n\n#### Scenario: s\n\n- **WHEN** a\n- **THEN** b\n' "$name" "$name"
  for l in "$@"; do printf '\n%s\n' "$l"; done
}
spec() { # requirement blocks... — print a capability spec
  printf '## Purpose\n\nFixture.\n\n## Requirements\n\n'; for b in "$@"; do printf '%s\n\n' "$b"; done
}
links_case() { # label status missing-count exit
  run links --cwd "$REPO" --base "$BASE"
  assert_eq "links: $1 — status" "$2" "$(printf '%s' "$OUT" | field status)"
  [ -n "$3" ] && assert_eq "links: $1 — items reported" "$3" "$(printf '%s' "$OUT" | "$PY" -c 'import json,sys; print(len(json.loads(sys.stdin.read() or "{}").get("missing", [])))')"
  assert_exit "links: $1 — exit" "$4" "$RC"
  assert_eq "links: $1 — one JSON line" 1 "$LINES"
}
linked_repo() { # name — a repo whose base has spec `cap` with requirement Base (no Example); sets BASE
  newrepo "$1"; put openspec/specs/cap/spec.md "$(spec "$(req Base)")"; BASE=$(commit base)
}
EX='##### Example: alpha table'
linked_repo l-ok; put openspec/specs/cap/spec.md "$(spec "$(req Base)" "$(req Alpha "$EX")")"; put scripts/tests/x/test.sh '# spec-example: cap / alpha table'; commit >/dev/null
links_case "added, Example, marker in a test" ok 0 0
linked_repo l-nomark; put openspec/specs/cap/spec.md "$(spec "$(req Base)" "$(req Alpha "$EX")")"; commit >/dev/null
links_case "added, Example, no marker" missing 1 1
linked_repo l-openspec; put openspec/specs/cap/spec.md "$(spec "$(req Base)" "$(req Alpha "$EX")")"; put openspec/changes/c/tasks.md '- spec-example: cap / alpha table'; put openspec/notes.txt 'spec-example: cap / alpha table'; commit >/dev/null
links_case "added, Example, marker only under openspec/" missing 1 1
linked_repo l-md; put openspec/specs/cap/spec.md "$(spec "$(req Base)" "$(req Alpha "$EX")")"; put docs/notes.md 'spec-example: cap / alpha table'; commit >/dev/null
links_case "added, Example, marker only in a .md file" missing 1 1
linked_repo l-noex; put openspec/specs/cap/spec.md "$(spec "$(req Base)" "$(req Alpha)")"; commit >/dev/null
links_case "added, no Example, no reason" missing 1 1
linked_repo l-reason; put openspec/specs/cap/spec.md "$(spec "$(req Base)" "$(req Alpha 'No executable check: a model carries this out.')")"; commit >/dev/null
links_case "added, no Example, a reason" ok 0 0
linked_repo l-emptyreason; put openspec/specs/cap/spec.md "$(spec "$(req Base)" "$(req Alpha 'No executable check:')")"; commit >/dev/null
links_case "added, no Example, nothing after the colon" missing 1 1
linked_repo l-notitle; put openspec/specs/cap/spec.md "$(spec "$(req Base)" "$(req Alpha '##### Example:')")"; commit >/dev/null
links_case "added, an Example with no title" missing 1 1
linked_repo l-dup; put openspec/specs/cap/spec.md "$(spec "$(req Base '##### Example: shared')" "$(req Alpha '##### Example: shared' '##### Example: shared')")"; put scripts/tests/x/test.sh '# spec-example: cap / shared'; commit >/dev/null
links_case "added, Examples whose title is used elsewhere in the capability" missing "" 1
newrepo l-changed; put openspec/specs/cap/spec.md "$(spec "$(req Alpha '##### Example: one' '##### Example: two')")"; put scripts/tests/x/test.sh '# spec-example: cap / one'; BASE=$(commit base)
put openspec/specs/cap/spec.md "$(spec "$(req Alpha 'Changed text.' '##### Example: one' '##### Example: two')")"; commit >/dev/null
links_case "changed, two Examples, one marker" missing 1 1
linked_repo l-unchanged; put README.txt changed; commit >/dev/null
links_case "unchanged requirement without an Example" ok 0 0
newrepo l-removed; put openspec/specs/cap/spec.md "$(spec "$(req Base)" "$(req Alpha)")"; BASE=$(commit base); put openspec/specs/cap/spec.md "$(spec "$(req Base)")"; commit >/dev/null
links_case "a requirement removed in the range" ok 0 0
linked_repo l-nospec; put src/a.py 'x = 1'; commit >/dev/null
links_case "no file under openspec/specs differs" ok 0 0
linked_repo l-badbase; BASE=no-such-rev
links_case "--base names a revision that does not exist" error "" 2
run links --cwd "$REPO"
assert_exit "links: no --base is a usage error" 64 "$RC"
# boundaries beyond the table
linked_repo l-newcap; put openspec/specs/other/spec.md "$(spec "$(req Gamma "$EX")")"; put scripts/tests/x/test.sh '# spec-example: other / alpha table'; commit >/dev/null
links_case "a new capability: the marker names that capability" ok 0 0
linked_repo l-wrongcap; put openspec/specs/other/spec.md "$(spec "$(req Gamma "$EX")")"; put scripts/tests/x/test.sh '# spec-example: cap / alpha table'; commit >/dev/null
links_case "a marker naming another capability does not count" missing 1 1
linked_repo l-untracked; put openspec/specs/cap/spec.md "$(spec "$(req Base)" "$(req Alpha "$EX")")"; commit >/dev/null; put scripts/tests/x/test.sh '# spec-example: cap / alpha table'
links_case "a marker only in an untracked file does not count" missing 1 1
linked_repo l-head; put openspec/specs/cap/spec.md "$(spec "$(req Base)" "$(req Alpha "$EX")")"; H=$(commit); put scripts/tests/x/test.sh '# spec-example: cap / alpha table'; commit >/dev/null
run links --cwd "$REPO" --base "$BASE" --head "$H"
assert_eq "links: --head names the revision whose markers are read" missing "$(printf '%s' "$OUT" | field status)"
OUT_MISSING=$(printf '%s' "$OUT" | "$PY" -c 'import json,sys; m=json.loads(sys.stdin.read())["missing"][0]; print(m["capability"], "|", m["requirement"], "|", m["example"])')
assert_eq "links: a missing item names capability, requirement and Example" "cap | Alpha | alpha table" "$OUT_MISSING"
# Spectra's archive appends a requirement to an existing spec as "\n\n---\n### Requirement: …", and the
# file may end without a newline (found on this repo's own idd-verify spec). The separator and the
# trailing blank lines are not part of the block before it.
newrepo l-append; mkdir -p "$REPO/openspec/specs/cap"; printf '%s\n\n<!--\nnote\n-->' "$(spec "$(req Base)")" > "$REPO/openspec/specs/cap/spec.md"
BASE=$(commit base)
printf '%s\n\n<!--\nnote\n-->\n\n---\n%s\n' "$(spec "$(req Base)")" "$(req Alpha "$EX")" > "$REPO/openspec/specs/cap/spec.md"; put scripts/tests/x/test.sh '# spec-example: cap / alpha table'; commit >/dev/null
links_case "a requirement appended after a separator leaves the block before it unchanged" ok 0 0
newrepo l-append-changed; mkdir -p "$REPO/openspec/specs/cap"; printf '%s' "$(spec "$(req Base)")" > "$REPO/openspec/specs/cap/spec.md"; BASE=$(commit base)
printf '%s\n\n---\n%s\n' "$(spec "$(req Base 'Changed text.')")" "$(req Alpha "$EX")" > "$REPO/openspec/specs/cap/spec.md"; put scripts/tests/x/test.sh '# spec-example: cap / alpha table'; commit >/dev/null
links_case "the block before the separator really changed → still reported" missing 1 1
# Rows added by idd-480-fix1 (verify round 1 of #480).
linked_repo l-prefix; put openspec/specs/cap/spec.md "$(spec "$(req Base)" "$(req Alpha '##### Example: alpha')")"; put scripts/tests/x/test.sh '# spec-example: cap / alpha table'; commit >/dev/null
links_case "added, one Example, only a marker naming a longer title that starts with it" missing 1 1
linked_repo l-prefix-closer; put openspec/specs/cap/spec.md "$(spec "$(req Base)" "$(req Alpha '##### Example: alpha')")"; put scripts/tests/x/page.html '<!-- spec-example: cap / alpha -->'; commit >/dev/null
links_case "a marker followed only by a comment closer counts" ok 0 0
linked_repo l-badhead; put openspec/specs/cap/spec.md "$(spec "$(req Base)")
### Requirement Missing colon

The system SHALL reject invalid input."; commit >/dev/null
links_case "added, under the heading '### Requirement Missing colon'" error "" 2
linked_repo l-emptyname; put openspec/specs/cap/spec.md "$(spec "$(req Base)")
### Requirement:

The system SHALL do nothing."; commit >/dev/null
links_case "a requirement heading with no name" error "" 2
linked_repo l-nospecs; git -C "$REPO" rm -q -r openspec/specs; commit >/dev/null
links_case "openspec/specs/ holds no tracked file at the head revision" error "" 2
newrepo l-gitkeep; put openspec/specs/.gitkeep ''; BASE=$(commit base); put README.txt x; commit >/dev/null
links_case "openspec/specs/ holds only .gitkeep (a newly initialised repository)" ok 0 0

# ── preflight ───────────────────────────────────────────────────────────────
echo "spec-change: preflight (Example: preflight by write access and Spectra state)"

BIN_WITH="$WORK/bin-with"; BIN_WITHOUT="$WORK/bin-without"; mkdir -p "$BIN_WITH" "$BIN_WITHOUT"
for b in "$BIN_WITH" "$BIN_WITHOUT"; do ln -s "$GIT" "$b/git"; done
printf '#!/bin/sh\necho spectra 3.0.0\n' > "$BIN_WITH/spectra"; chmod +x "$BIN_WITH/spectra"
pf_repo() { # name linked(yes|no) openspec(yes|no) → TREE (where preflight runs)
  newrepo "$1"; [ "$3" = yes ] && { put openspec/specs/.keep; commit >/dev/null; }
  TREE="$REPO"
  if [ "$2" = yes ]; then git -C "$REPO" worktree add -q --detach "$WORK/$1-wt" HEAD; TREE="$WORK/$1-wt"; fi
}
preflight_case() { # label can-write linked spectra openspec status exit
  pf_repo "pf-$RANDOM$RANDOM" "$3" "$5"
  local bin="$BIN_WITHOUT"; [ "$4" = yes ] && bin="$BIN_WITH"
  OUT=$(PATH="$bin" "$PY" "$SC" preflight --cwd "$TREE" --can-write "$2" 2>"$WORK/err"); RC=$?
  LINES=$(printf '%s' "$OUT" | grep -c . || true)
  assert_eq "preflight: $1 — status" "$6" "$(printf '%s' "$OUT" | field status)"
  assert_exit "preflight: $1 — exit" "$7" "$RC"
  assert_eq "preflight: $1 — one JSON line" 1 "$LINES"
}
preflight_case "cannot write" no no yes yes third-party 0
preflight_case "cannot write, linked worktree, nothing installed" no yes no no third-party 0
preflight_case "linked worktree" yes yes yes yes linked-worktree 1
preflight_case "no spectra, openspec present" yes no no yes install-spectra 1
preflight_case "no spectra, no openspec" yes no no no install-spectra 1
preflight_case "spectra, no openspec" yes no yes no init-openspec 1
preflight_case "everything in place" yes no yes yes ready 0
pf_repo pf-usage no yes
run preflight --cwd "$TREE" --can-write maybe
assert_exit "preflight: --can-write other than yes or no is a usage error" 64 "$RC"
# the messages name what to do
pf_repo pf-msg no no; OUT=$(PATH="$BIN_WITHOUT" "$PY" "$SC" preflight --cwd "$TREE" --can-write yes 2>/dev/null)
assert_grep "preflight: install-spectra names how to install it" "Spectra" "$(printf '%s' "$OUT" | field message)"
pf_repo pf-msg2 no no; OUT=$(PATH="$BIN_WITH" "$PY" "$SC" preflight --cwd "$TREE" --can-write yes 2>/dev/null)
assert_grep "preflight: init-openspec names the command" "spectra init" "$(printf '%s' "$OUT" | field message)"
pf_repo pf-sub no yes; mkdir -p "$TREE/deep/er"; OUT=$(PATH="$BIN_WITH" "$PY" "$SC" preflight --cwd "$TREE/deep/er" --can-write yes 2>/dev/null)
assert_eq "preflight: run from a subdirectory, openspec/ is looked for at the top of the repository" ready "$(printf '%s' "$OUT" | field status)"

# ── spec directory (task 2.6) ───────────────────────────────────────────────
echo "spec-change: spec directory (Example: spec directory by .spectra.yaml)"
SPEC_DS="$MARK
**Spec**: change idd-42-x"
specdir_case() { # label spectra-yaml-content(or NONE) dir status exit
  newrepo "sd-$RANDOM$RANDOM"
  [ "$2" != NONE ] && put .spectra.yaml "$2"
  put "$3/changes/archive/2026-11-10-idd-42-x/proposal.md"; R=$(commit)
  archived_case "spec dir: $1" "$SPEC_DS" "$R" "$4" "" "$5"
}
specdir_case "spec_dir: docs/spectra" "spec_dir: docs/spectra" docs/spectra pass 0
specdir_case 'spec_dir: "docs/specs" (quoted)' 'spec_dir: "docs/specs"' docs/specs pass 0
specdir_case "only a commented spec_dir line → openspec" "# spec_dir: docs/specs
locale: tw" openspec pass 0
specdir_case "no .spectra.yaml → openspec" NONE openspec pass 0
specdir_case "an absolute spec_dir" "spec_dir: /srv/specs" openspec error 2
specdir_case "a spec_dir that leaves the repository" "spec_dir: ../specs" openspec error 2
specdir_case "spec_dir with no value" "spec_dir:" openspec error 2
specdir_case "the default does not apply when spec_dir names another directory" "spec_dir: docs/spectra" openspec refuse 1
# links reads the same directory, and markers under it do not count
newrepo sd-links; put .spectra.yaml "spec_dir: docs/spectra"; put docs/spectra/specs/cap/spec.md "$(spec "$(req Base)")"; BASE=$(commit base)
put docs/spectra/specs/cap/spec.md "$(spec "$(req Base)" "$(req Alpha "$EX")")"; put docs/spectra/notes.txt 'spec-example: cap / alpha table'; commit >/dev/null
links_case "spec dir docs/spectra: a new requirement there is checked; a marker under it does not count" missing 1 1
put scripts/tests/x/test.sh '# spec-example: cap / alpha table'; commit >/dev/null
links_case "spec dir docs/spectra: with a marker in a test" ok 0 0
# preflight looks for the resolved directory
pf_repo sd-pf no no; put .spectra.yaml "spec_dir: docs/spectra"; mkdir -p "$REPO/docs/spectra"; commit >/dev/null
OUT=$(PATH="$BIN_WITH" "$PY" "$SC" preflight --cwd "$TREE" --can-write yes 2>/dev/null)
assert_eq "preflight: spec_dir docs/spectra exists → ready" ready "$(printf '%s' "$OUT" | field status)"
pf_repo sd-pf2 no yes; put .spectra.yaml "spec_dir: docs/spectra"; commit >/dev/null
OUT=$(PATH="$BIN_WITH" "$PY" "$SC" preflight --cwd "$TREE" --can-write yes 2>/dev/null)
assert_eq "preflight: openspec/ exists but spec_dir names docs/spectra → init-openspec" init-openspec "$(printf '%s' "$OUT" | field status)"

# the chain with the real spectra CLI (skipped, visibly, when spectra is not installed)
if command -v spectra >/dev/null 2>&1; then
  newrepo sd-real; ( cd "$REPO" && spectra init --tools claude </dev/null >/dev/null 2>&1 ); commit init >/dev/null; BASE=$(git -C "$REPO" rev-parse HEAD)
  DIR=$(sed -nE 's/^spec_dir:[[:space:]]*//p' "$REPO/.spectra.yaml" | head -1); DIR=${DIR:-openspec}
  ( cd "$REPO" && spectra new change idd-7-demo --agent claude >/dev/null 2>&1 \
    && printf '## Why\n\nDemo.\n\n## What Changes\n\n- The demo prints hello.\n\n## Capabilities\n\n### New Capabilities\n\n- `demo`: prints hello.\n\n### Modified Capabilities\n\n(none)\n\n## Impact\n\n- Affected specs: demo\n- Affected code:\n  - New: src/demo.sh\n' | spectra new artifact proposal --change idd-7-demo --stdin >/dev/null 2>&1 \
    && printf '## Purpose\n\nThe demo capability prints a greeting.\n\n## ADDED Requirements\n\n### Requirement: Demo prints hello\n\nThe demo command SHALL print hello.\n\n#### Scenario: run it\n\n- **WHEN** the command runs\n- **THEN** it prints hello\n\n##### Example: greeting\n\n| Input | Output |\n| --- | --- |\n| none | hello |\n' | spectra new artifact spec demo --change idd-7-demo --stdin >/dev/null 2>&1 \
    && printf '## 1. Demo\n\n- [ ] 1.1 Demo prints hello (Demo prints hello). Verify: test.\n' | spectra new artifact tasks --change idd-7-demo --stdin >/dev/null 2>&1 \
    && spectra archive idd-7-demo --mark-tasks-complete -y >/dev/null 2>&1 )
  put tests/demo.sh '# spec-example: demo / greeting'; commit chain >/dev/null
  run archived --file "$(comment sd-real "$MARK
**Spec**: change idd-7-demo")" --cwd "$REPO" --ref HEAD
  assert_eq "real spectra ($DIR): the archived change passes" pass "$(printf '%s' "$OUT" | field status)"
  run links --cwd "$REPO" --base "$BASE"
  assert_eq "real spectra ($DIR): the new requirement with a marked test is ok" ok "$(printf '%s' "$OUT" | field status)"
else
  echo "  ~ skipped: spectra is not installed, the real-CLI chain was not run"
fi

# ── common behaviour (task 2.5) ─────────────────────────────────────────────
echo "spec-change: ic (Example: choosing the Implementation Complete comment)"
icj() { # name json — write a comments file, print its path
  printf '%s' "$2" > "$WORK/$1.json"; printf '%s' "$WORK/$1.json"
}
IC_O='{"author_association":"OWNER","body":"## Implementation Complete\n\n**Spec**: change idd-1-a"}'
IC_M='{"author_association":"MEMBER","body":"## Implementation Complete\n\n**Spec**: change idd-1-b"}'
IC_C='{"author_association":"COLLABORATOR","body":"## Implementation Complete\n\n**Spec**: change idd-1-c"}'
IC_X='{"author_association":"CONTRIBUTOR","body":"## Implementation Complete\n\n**Spec**: no behaviour change"}'
IC_K='{"author_association":"OWNER","body":"<!-- idd:comment type=implementation-complete -->\n## Implementation Complete\n\n**Spec**: change idd-1-k"}'
DG='{"author_association":"OWNER","body":"## Diagnosis\n\nroot cause"}'
ic_case() { # label json-or-path expected-substring(or EMPTY) exit
  local f="$2"; case "$f" in /*) ;; *) f=$(icj "ic-$RANDOM" "$2") ;; esac
  run ic --comments "$f"
  if [ "$3" = EMPTY ]; then assert_eq "ic: $1 — prints nothing" "" "$OUT"
  else assert_grep "ic: $1 — prints that body" "$3" "$OUT"; fi
  assert_exit "ic: $1 — exit" "$4" "$RC"
}
ic_case "OWNER then MEMBER → the MEMBER's body" "[$IC_O,$IC_M]" "idd-1-b" 0
ic_case "COLLABORATOR then CONTRIBUTOR → the COLLABORATOR's body" "[$IC_C,$IC_X]" "idd-1-c" 0
ic_case "a body that starts with the marker" "[$IC_K]" "idd-1-k" 0
ic_case "a Diagnosis only" "[$DG]" EMPTY 0
ic_case "no comments" "[]" EMPTY 0
ic_case "two pages, the newest on the second" "[$IC_O]
[$DG,$IC_M]" "idd-1-b" 0
ic_case "the file does not exist" "$WORK/no-such-comments.json" EMPTY 2
ic_case "the file is not JSON" "$(icj ic-notjson 'not json')" EMPTY 2
run ic --comments "$(icj ic-one "[$IC_O,$IC_M]")"
assert_eq "ic: the printed body reads as the declaration it holds" "idd-1-b" "$(printf '%s\n' "$OUT" > "$WORK/ic-out.md"; "$PY" "$SC" declared --file "$WORK/ic-out.md" | field changes | tr -d '[]" ')"
run ic
assert_exit "ic: no --comments is a usage error" 64 "$RC"

echo "spec-change: common behaviour"
mkdir -p "$WORK/not-git"
run archived --file "$(comment c-arch "$SPEC1")" --cwd "$WORK/not-git" --ref HEAD
assert_eq "archived: not a git repository → error" error "$(printf '%s' "$OUT" | field status)"
assert_exit "archived: not a git repository → exit 2" 2 "$RC"
run links --cwd "$WORK/not-git" --base HEAD
assert_eq "links: not a git repository → error" error "$(printf '%s' "$OUT" | field status)"
assert_exit "links: not a git repository → exit 2" 2 "$RC"
run preflight --cwd "$WORK/not-git" --can-write yes
assert_eq "preflight: not a git repository → error" error "$(printf '%s' "$OUT" | field status)"
assert_exit "preflight: not a git repository → exit 2" 2 "$RC"
linked_repo c-badspec; printf '\377\376 not utf-8 \377\n' > "$REPO/openspec/specs/cap/spec.md"; commit >/dev/null
run links --cwd "$REPO" --base "$BASE"
assert_eq "links: a spec file that cannot be decoded → error, not ok" error "$(printf '%s' "$OUT" | field status)"
assert_exit "links: a spec file that cannot be decoded → exit 2" 2 "$RC"
for opt in "archived --file $WORK/c-arch.md --cwd $WORK --ref" "links --cwd $WORK --base" "links --cwd $WORK --base HEAD --head"; do
  # shellcheck disable=SC2086
  run $opt --output=x
  assert_exit "a revision that starts with a dash is a usage error ($(printf '%s' "$opt" | cut -d' ' -f1))" 64 "$RC"
done
run bogus
assert_exit "an unknown subcommand is a usage error" 64 "$RC"
run
assert_exit "no subcommand is a usage error" 64 "$RC"

print_summary spec-change
