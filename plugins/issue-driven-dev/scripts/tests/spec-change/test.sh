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
# spec-example: spec-on-every-issue / markers in submodules
# spec-example: spec-on-every-issue / preflight by write access and Spectra state
# spec-example: spec-on-every-issue / spec directory by .spectra.yaml
# spec-example: spec-on-every-issue / choosing the Implementation Complete comment
# spec-example: spec-on-every-issue / reading the Spec plan line
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

# Rows added by idd-480-fix3 (verify round 3 of #480).
declared_case "marker, the only Spec line inside a four-backtick fence that holds a three-backtick line" "$MARK
\`\`\`\`
$FENCE
**Spec**: no behaviour change
\`\`\`\`" invalid '[]' 1
LS=$(printf '\342\200\250')
declared_case "marker, Spec line after U+2028 on the same line" "$MARK
intro${LS}**Spec**: no behaviour change" invalid '[]' 1

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
linked_repo l-notes; put openspec/specs/cap/spec.md "$(spec "$(req Base)")
## Requirement notes

Background only."; commit >/dev/null
links_case "a level-2 heading that mentions Requirement is not a requirement heading" ok 0 0
# Rows added by idd-480-fix2 (verify round 2 of #480).
linked_repo l-fenced-ex; put openspec/specs/cap/spec.md "$(spec "$(req Base)" "$(req Alpha "$FENCE" '##### Example: alpha table' "$FENCE")")"; put scripts/tests/x/test.sh '# spec-example: cap / alpha table'; commit >/dev/null
links_case "added, its only Example line inside a code fence" missing 1 1
linked_repo l-fenced-nc; put openspec/specs/cap/spec.md "$(spec "$(req Base)" "$(req Alpha "$FENCE" 'No executable check: a model carries this out.' "$FENCE")")"; commit >/dev/null
links_case "added, its only No executable check line inside a code fence" missing 1 1
linked_repo l-longfence; put openspec/specs/cap/spec.md "$(spec "$(req Base)" "$(req Alpha '````' "$FENCE" '##### Example: alpha table' '````')")"; put scripts/tests/x/test.sh '# spec-example: cap / alpha table'; commit >/dev/null
links_case "added, after a four-backtick fence that three backticks do not close" missing 1 1
linked_repo l-dupname; put openspec/specs/cap/spec.md "$(spec "$(req Base)" "$(req Alpha 'No executable check: a.')" "$(req Alpha 'No executable check: b.')")"; commit >/dev/null
links_case "added twice with the same name in one capability" error "" 2
linked_repo l-unclosed; put openspec/specs/cap/spec.md "$(spec "$(req Base)" "$(req Alpha 'No executable check: a.' "$FENCE")" "$(req Gamma "$EX")")"; put scripts/tests/x/test.sh '# spec-example: cap / alpha table'; commit >/dev/null
links_case "a code fence that never closes at the head revision" error "" 2
linked_repo l-indented-head; put openspec/specs/cap/spec.md "$(spec "$(req Base)")
  ### Requirement: Alpha

The system SHALL do Alpha."; commit >/dev/null
links_case "added, under a heading indented by two spaces" missing 1 1
assert_eq "links: … the item names the indented requirement, not the one before it" "Alpha" "$(printf '%s' "$OUT" | "$PY" -c 'import json,sys; m=json.loads(sys.stdin.read())["missing"]; print(m[0]["requirement"] if m else "")')"
linked_repo l-listfence; put openspec/specs/cap/spec.md "$(spec "$(req Base)" "$(req Alpha '- a list item:' '' "    $FENCE" '    No executable check: hidden in a fenced block of the list item.' "    $FENCE")")"; commit >/dev/null
links_case "added, its only No executable check line inside a fence indented four spaces in a list item" missing 1 1
linked_repo l-u2028; put openspec/specs/cap/spec.md "$(spec "$(req Base)" "$(req Alpha '##### Example: alpha')")"; put scripts/tests/x/test.sh "# spec-example: cap / alpha$(printf '\342\200\250') table"; commit >/dev/null
links_case "a marker followed by U+2028 and more text on the same line does not count" missing 1 1
linked_repo l-nonascii; put "openspec/specs/中文能力/spec.md" "$(spec "$(req Alpha)")"; commit >/dev/null
links_case "added, in a capability whose directory name is not ASCII (idd-480-fix4)" missing 1 1
linked_repo l-quote; put 'openspec/specs/quo"te/spec.md' "$(spec "$(req Alpha)")"; commit >/dev/null
links_case "added, in a capability whose directory name holds a double quote (idd-480-fix5)" missing 1 1
linked_repo l-nospecs; git -C "$REPO" rm -q -r openspec/specs; commit >/dev/null
links_case "openspec/specs/ holds no tracked file at the head revision" error "" 2
newrepo l-gitkeep; put openspec/specs/.gitkeep ''; BASE=$(commit base); put README.txt x; commit >/dev/null
links_case "openspec/specs/ holds only .gitkeep (a newly initialised repository)" ok 0 0

# ── links: markers in submodules ────────────────────────────────────────────
echo "spec-change: links (Example: markers in submodules)"

submodule_repo() { # name source path — add one Example and a local submodule; sets REPO and BASE
  linked_repo "$1"
  put openspec/specs/cap/spec.md "$(spec "$(req Base)" "$(req Alpha "$EX")")"
  git -C "$REPO" -c protocol.file.allow=always submodule add -q "$2" "$3" || exit 1
  commit >/dev/null
}
newrepo l-sub-source; put scripts/test.sh '# spec-example: cap / alpha table'; commit >/dev/null; SUB="$REPO"
newrepo l-sub-empty-source; put scripts/test.sh '# no marker'; commit >/dev/null; EMPTY_SUB="$REPO"
newrepo l-sub-md-source; put notes.md '# spec-example: cap / alpha table'; commit >/dev/null; MD_SUB="$REPO"

submodule_repo l-sub-tracked "$SUB" tests/sub
links_case "submodule row 1: tracked marker at the recorded commit" ok 0 0

newrepo l-sub-nested-source
git -C "$REPO" -c protocol.file.allow=always submodule add -q "$SUB" inner || exit 1
commit >/dev/null; NESTED_SUB="$REPO"
submodule_repo l-sub-nested "$NESTED_SUB" tests/sub
git -C "$REPO" -c protocol.file.allow=always submodule update -q --init --recursive || exit 1
links_case "submodule row 2: marker in a nested submodule" ok 0 0

submodule_repo l-sub-space "$SUB" 'tests/sub module'
links_case "submodule row 3: path with a space" ok 0 0

submodule_repo l-sub-earlier "$SUB" tests/sub
printf '# no marker\n' > "$REPO/tests/sub/scripts/test.sh"
git -C "$REPO/tests/sub" add -A; git -C "$REPO/tests/sub" commit -q -m remove-marker
links_case "submodule row 4: marker only at the recorded commit" ok 0 0

submodule_repo l-sub-later "$EMPTY_SUB" tests/sub
printf '# spec-example: cap / alpha table\n' > "$REPO/tests/sub/scripts/test.sh"
git -C "$REPO/tests/sub" add -A; git -C "$REPO/tests/sub" commit -q -m add-marker
links_case "submodule row 5: marker only at the later working-tree commit" missing 1 1
assert_eq "links: submodule row 5 — why unchanged" 'no tracked file outside openspec/ (and not .md) carries its marker' "$(printf '%s' "$OUT" | "$PY" -c 'import json,sys; m=json.load(sys.stdin)["missing"]; print(m[0]["why"] if m else "")')"

submodule_repo l-sub-md "$MD_SUB" tests/sub
links_case "submodule row 6: marker only in a .md file" missing 1 1

submodule_repo l-sub-nowhere "$EMPTY_SUB" tests/sub
links_case "submodule row 7: no marker, submodule checked out" missing 1 1

submodule_repo l-sub-deinit "$SUB" tests/sub
git -C "$REPO" submodule deinit -q -f -- tests/sub || exit 1
links_case "submodule row 8: marker in a submodule not checked out" error 0 2
assert_eq "links: submodule row 8 — reason names Example and path" "cannot decide whether the Example 'cap / alpha table' has a marker: submodule tests/sub: not checked out" "$(printf '%s' "$OUT" | field reason)"

submodule_repo l-sub-main "$SUB" tests/sub
put scripts/test.sh '# spec-example: cap / alpha table'; commit >/dev/null
git -C "$REPO" submodule deinit -q -f -- tests/sub || exit 1
links_case "submodule row 9: main marker, submodule not checked out" ok 0 0

submodule_repo l-sub-missing-commit "$EMPTY_SUB" tests/sub
git -C "$REPO" update-index --cacheinfo 160000,1111111111111111111111111111111111111111,tests/sub || exit 1
# Do not add the working tree: keep the missing commit recorded in the index.
git -C "$REPO" commit -q -m missing-submodule-commit || exit 1
links_case "submodule row 10: recorded commit absent from the object store" error 0 2
assert_eq "links: submodule row 10 — reason names Example and path" "cannot decide whether the Example 'cap / alpha table' has a marker: submodule tests/sub: recorded commit 111111111111 is not in its object store" "$(printf '%s' "$OUT" | field reason)"

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
specdir_case "a spec_dir that starts with a dash" "spec_dir: -x" openspec error 2
specdir_case "a spec_dir that names the repository root" "spec_dir: ." openspec error 2
specdir_case "a spec_dir that starts with a colon (git pathspec magic)" 'spec_dir: ":(top)openspec"' openspec error 2
specdir_case 'a " #" inside the quotes is part of the value' 'spec_dir: "docs/my # specs"' "docs/my # specs" pass 0
specdir_case "spec_dir followed only by a comment" "spec_dir: # a comment" openspec error 2
newrepo sd-yamldir; put .spectra.yaml/x y; put openspec/changes/archive/2026-11-10-idd-42-x/proposal.md; R=$(commit)
archived_case "spec dir: a directory named .spectra.yaml at the revision" "$SPEC_DS" "$R" error "" 2
newrepo sd-yamllink; put real.yaml 'spec_dir: openspec'; ln -s real.yaml "$REPO/.spectra.yaml"; put openspec/changes/archive/2026-11-10-idd-42-x/proposal.md; R=$(commit)
archived_case "spec dir: a symbolic link named .spectra.yaml at the revision" "$SPEC_DS" "$R" error "" 2
pf_repo pf-yamllink no yes; printf 'spec_dir: openspec\n' > "$TREE/real.yaml"; ln -s real.yaml "$TREE/.spectra.yaml"
OUT=$(PATH="$BIN_WITH" "$PY" "$SC" preflight --cwd "$TREE" --can-write yes 2>"$WORK/err"); RC=$?
assert_eq "preflight: .spectra.yaml is a symbolic link in the working tree → error, as at a revision" error "$(printf '%s' "$OUT" | field status)"
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
ic_case "an empty file (gh exited 0 and printed nothing)" "$(icj ic-empty '')" EMPTY 2
"$PY" -c 'import sys; sys.stdout.write("[" * 100000 + "]" * 100000)' > "$WORK/ic-deep.json"
ic_case "JSON nested a hundred thousand arrays deep" "$WORK/ic-deep.json" EMPTY 2
ic_case "a body that starts with a blank line and then the marker" '[{"author_association":"OWNER","body":"\n<!-- idd:comment type=implementation-complete -->\n**Spec**: change idd-1-w"}]' "idd-1-w" 0
ic_case "a comment whose body is not a string is not chosen" '[{"author_association":"OWNER","body":7},{"author_association":"OWNER","body":"## Implementation Complete\n\n**Spec**: change idd-1-z"}]' "idd-1-z" 0
run ic --comments "$(icj ic-one "[$IC_O,$IC_M]")"
assert_eq "ic: the printed body reads as the declaration it holds" "idd-1-b" "$(printf '%s\n' "$OUT" > "$WORK/ic-out.md"; "$PY" "$SC" declared --file "$WORK/ic-out.md" | field changes | tr -d '[]" ')"
run ic
assert_exit "ic: no --comments is a usage error" 64 "$RC"

echo "spec-change: preflight and spec_dir failures (idd-480-fix2)"
pf_repo pf-unreadable no yes; printf 'spec_dir: openspec\n' > "$TREE/.spectra.yaml"; chmod 000 "$TREE/.spectra.yaml"
if [ -r "$TREE/.spectra.yaml" ]; then echo "  (skipped: running as a user who can read mode-000 files)"
else
  OUT=$(PATH="$BIN_WITH" "$PY" "$SC" preflight --cwd "$TREE" --can-write yes 2>"$WORK/err"); RC=$?
  LINES=$(printf '%s' "$OUT" | grep -c . || true)
  assert_eq "preflight: .spectra.yaml cannot be read → error" error "$(printf '%s' "$OUT" | field status)"
  assert_exit "preflight: .spectra.yaml cannot be read → exit 2" 2 "$RC"
  assert_eq "preflight: … one JSON line" 1 "$LINES"
fi
chmod 644 "$TREE/.spectra.yaml"
pf_repo pf-dangling no yes; ln -s "$WORK/no-such-target" "$TREE/.spectra.yaml"
OUT=$(PATH="$BIN_WITH" "$PY" "$SC" preflight --cwd "$TREE" --can-write yes 2>"$WORK/err"); RC=$?
assert_eq "preflight: .spectra.yaml is a broken symlink → error, not the default directory" error "$(printf '%s' "$OUT" | field status)"
assert_exit "preflight: … exit 2" 2 "$RC"
linked_repo dash-sd; printf 'spec_dir: -x\n' > "$REPO/.spectra.yaml"; commit >/dev/null
run links --cwd "$REPO" --base "$BASE"
assert_eq "links: a spec_dir that starts with a dash → error" error "$(printf '%s' "$OUT" | field status)"
assert_exit "links: … exit 2" 2 "$RC"

echo "spec-change: no git on PATH (idd-480-fix3)"
newrepo nogit; put openspec/specs/.keep; R=$(commit)
OUT=$(PATH="$WORK/empty-path" "$PY" "$SC" archived --file "$(comment c-nogit "$SPEC1")" --cwd "$REPO" --ref "$R" 2>"$WORK/err"); RC=$?
assert_eq "archived: no git on PATH → error, not a traceback" error "$(printf '%s' "$OUT" | field status)"
assert_exit "archived: no git on PATH → exit 2" 2 "$RC"

echo "spec-change: plan (Example: reading the Spec plan line)"
PL_O='{"author_association":"OWNER","body":"## Implementation Plan (Plan tier)\n\n**Spec plan**: change idd-7-x"}'
PL_R='{"author_association":"OWNER","body":"## Implementation Plan (Plan tier)\n\n**Spec plan**: rejected (change idd-7-x left parked)"}'
PL_N='{"author_association":"MEMBER","body":"## Implementation Plan\n\n**Spec plan**: no behaviour change (a)"}'
PL_T='{"author_association":"OWNER","body":"## Implementation Plan\n\n**Spec plan**: third-party clone"}'
PL_X='{"author_association":"CONTRIBUTOR","body":"## Implementation Plan\n\n**Spec plan**: change idd-7-y"}'
PL_F='{"author_association":"OWNER","body":"## Implementation Plan\n\n```\n**Spec plan**: change idd-7-x\n```"}'
PL_2='{"author_association":"OWNER","body":"## Implementation Plan\n\n**Spec plan**: change idd-7-x\n**Spec plan**: change idd-7-z"}'
plan_case() { # label json-or-path form change exit
  local f="$2"; case "$f" in /*) ;; *) f=$(icj "pl-$RANDOM" "$2") ;; esac
  run plan --comments "$f"
  if [ "$3" = NOJSON ]; then assert_eq "plan: $1 — no JSON line" "" "$OUT"
  else
    assert_eq "plan: $1 — form" "$3" "$(printf '%s' "$OUT" | field form)"
    assert_eq "plan: $1 — change" "$4" "$(printf '%s' "$OUT" | field change)"
  fi
  assert_exit "plan: $1 — exit" "$5" "$RC"
}
plan_case "the owner's plan naming idd-7-x" "[$PL_O]" change idd-7-x 0
plan_case "no behaviour change (a)" "[$PL_N]" no-behaviour-change "" 0
plan_case "third-party clone" "[$PL_T]" third-party-clone "" 0
PL_P='{"author_association":"OWNER","body":"## Implementation Plan (Plan tier)\n\n**Spec plan**: proposed (change idd-7-x)"}'
PL_NOTES='{"author_association":"OWNER","body":"## Implementation Planning notes\n\n**Spec plan**: change idd-7-x"}'
plan_case "proposed, before plan mode (idd-480-fix5)" "[$PL_P]" proposed idd-7-x 0
plan_case "a newer Implementation Planning notes comment is not a plan" "[$PL_O,$PL_NOTES]" change idd-7-x 0
# #499: after a plan approved in plan mode, idd-implement posts the tasks of the change in a separate comment and
# leaves the approved plan alone. The reader has to keep reading that plan: a comment headed "## Spec tasks" is not
# a plan, even when it is the newer one and one of its lines looks like a Spec plan line.
PL_TASKS='{"author_association":"OWNER","body":"## Spec tasks (change idd-7-x)\n\n1.1 the first task\n1.2 the second task\n\n**Spec plan**: change idd-7-z"}'
plan_case "a newer Spec tasks comment is not a plan (#499)" "[$PL_O,$PL_TASKS]" change idd-7-x 0
plan_case "the rejected form is not a Spec plan form (idd-480-fix7)" "[$PL_R]" invalid "" 1
plan_case "a newer plan by a contributor is not the one read" "[$PL_O,$PL_X]" change idd-7-x 0
plan_case "no Implementation Plan comment" "[$DG]" none "" 0
plan_case "the only Spec plan line inside a code fence" "[$PL_F]" none "" 0
plan_case "two Spec plan lines" "[$PL_2]" invalid "" 1
plan_case "the file is not JSON" "$(icj pl-notjson 'not json')" NOJSON "" 2

pf_repo pf-hint no yes
OUT=$(PATH="$BIN_WITHOUT" "$PY" "$SC" preflight --cwd "$TREE" --can-write yes 2>"$WORK/err")
assert_grep "preflight: install-spectra names the command that installs Spectra (idd-480-fix5)" "brew install --cask spectra-app" "$(printf '%s' "$OUT" | field message)"
assert_grep "… and the project's address" "github.com/kaochenlong/spectra-app" "$(printf '%s' "$OUT" | field message)"

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
