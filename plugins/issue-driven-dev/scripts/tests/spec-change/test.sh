#!/usr/bin/env bash
# spec-change suite (#480) — scripts/spec-change.py, the four mechanical checks
# behind "every issue leaves a spec change or a declared exemption":
#   declared   read the **Spec**: line of an Implementation Complete comment
#   archived   are the declared changes archived at a revision
#   links      does every added or changed requirement carry an executable check
#   preflight  may the wrapper start writing a spec change here
#
# Each block below maps one `##### Example:` table of the capability
# spec-on-every-issue, one check per row, with the table's values. The markers
# name the Examples this file checks (they are read by `spec-change.py links`):
#
# spec-example: spec-on-every-issue / reading the Spec line
# spec-example: spec-on-every-issue / whether the declared changes are archived at a commit
# spec-example: spec-on-every-issue / what the link check reports
# spec-example: spec-on-every-issue / preflight by write access and Spectra state
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

# ── common behaviour (task 2.5) ─────────────────────────────────────────────
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
