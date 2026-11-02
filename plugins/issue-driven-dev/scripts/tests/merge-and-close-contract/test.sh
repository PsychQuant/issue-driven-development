#!/usr/bin/env bash
# merge-and-close-contract suite (#392) — the three layers that state where
# /idd-all ends must agree: the idd-all skill, the idd-close skill, and the
# MANIFESTO doctrine (plus the batch reference). Before #392 all three said
# "stop at verified, never merge, never close"; the change moves the end to
# "clean verify → merge (or push) → /idd-close". A layer that still carries the
# old sentence contradicts the others, and the executor follows whichever one
# it reads last.
#
# The forbidden old sentences are matched as fixed strings assembled from parts,
# so this file never contains them whole (a scanner reading this file would
# otherwise find them here).

# No pipefail: assert_grep pipes the haystack into `grep -q`, and idd-all's
# SKILL.md is larger than a pipe buffer — grep exits at the first match, printf
# takes SIGPIPE, and under pipefail the pipeline reports 141, i.e. "not found".
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
PLUGIN="$(cd "$HERE/../../.." && pwd)"
ALL="$PLUGIN/skills/idd-all/SKILL.md"
CLOSE="$PLUGIN/skills/idd-close/SKILL.md"
MANI="$PLUGIN/MANIFESTO.md"
PORCH="$PLUGIN/references/parallel-orchestration.md"

read_file() { [ -f "$1" ] && cat "$1" || printf ''; }
section() { # file heading-prefix — the lines from the heading to the next heading of the same or higher level
  python3 - "$1" "$2" <<'EOF'
import sys, re
path, head = sys.argv[1], sys.argv[2]
try:
    lines = open(path, encoding="utf-8").read().splitlines()
except OSError:
    sys.exit(0)
level = len(head) - len(head.lstrip("#"))
out, on, fence = [], False, False
for line in lines:
    if re.match(r"^\s*(```|~~~)", line):
        fence = not fence
    m = None if fence else re.match(r"^(#+) ", line)
    if on and m and len(m.group(1)) <= level:
        break
    if line.startswith(head):
        on = True
    if on:
        out.append(line)
print("\n".join(out))
EOF
}
frontmatter_description() {
  python3 - "$1" <<'EOF'
import sys
try:
    text = open(sys.argv[1], encoding="utf-8").read()
except OSError:
    sys.exit(0)
parts = text.split("\n---\n", 1)
head = parts[0]
out, on = [], False
for line in head.splitlines():
    if line.startswith("description:"):
        on = True
        out.append(line)
        continue
    if on:
        if line and not line.startswith(" "):
            break
        out.append(line)
print("\n".join(out))
EOF
}

ALL_TXT=$(read_file "$ALL")
CLOSE_TXT=$(read_file "$CLOSE")
MANI_TXT=$(read_file "$MANI")
PORCH_TXT=$(read_file "$PORCH")

NEVER="永""不"; ALWAYS_NOT="永遠""不"; AC="auto-""close"; AM="auto-""merge"

echo "idd-all: close stage"
STAGE=$(section "$ALL" "### Phase 5c")
assert_grep "close stage heading exists" "Close stage" "$STAGE"
assert_grep "Step 0 task list has the close stage" 'TaskCreate(name="close_stage"' "$ALL_TXT"
assert_grep "close stage calls the verify gate" "verify-gate.py" "$STAGE"
assert_grep "guardrail: CI checks" "gh pr checks" "$STAGE"
assert_grep "guardrail: 15-minute wait for pending checks" "15" "$STAGE"
assert_grep "guardrail: auto-close trap scan" "Step 0.8" "$STAGE"
assert_grep "guardrail: squash with an explicit subject" "--subject" "$STAGE"
assert_grep "guardrail: squash with an explicit body" "--body" "$STAGE"
assert_grep "merge is a squash merge" "gh pr merge" "$STAGE"
assert_grep "direct-commit pushes the verified commit, not HEAD" "git push origin <sha>:refs/heads/<default>" "$STAGE"
assert_grep "close is invoked with the orchestrated directive" "ORCHESTRATED BY /idd-all" "$STAGE"
assert_grep "--review keeps the run at verified" "--review" "$STAGE"
assert_grep "--in-chain never merges" "--in-chain" "$STAGE"
assert_grep "meeting never merges" "meeting" "$STAGE"
assert_grep "a stopped close after a merge says so" "/idd-close #" "$STAGE"

echo "idd-all: the close stage runs in one helper process"
# The selector, the guardrails and the merge used to be inline bash split over
# several fences; a Stopped in one fence did not stop the next (#392 verify r1 #9).
# They now live in scripts/close-stage.py (its own suite: tests/close-stage/).
assert_grep "Phase 4 judges each round through close-stage.py gate" "close-stage.py\" gate" "$(section "$ALL" "### Phase 4")"
assert_grep "Phase 4 binds the gate to the current HEAD" "--sha \"\$HEAD_SHA\"" "$(section "$ALL" "### Phase 4")"
assert_grep "Phase 5c runs close-stage.py run" "close-stage.py\" run" "$STAGE"
assert_grep "Phase 5c runs it in the background, not split over calls" "run_in_background" "$STAGE"
assert_grep "Step 0.7 records the run state" "close-stage.py\" init" "$ALL_TXT"
refute_grep "no hard-coded issue number in the PR body template" "guardrails pass (#392)" "$ALL_TXT"
refute_grep "no hard-coded issue number in the idd-close directive" "close stage of #392" "$ALL_TXT"
assert_grep "idd-close is called with --repo" "#\$N --repo \$GITHUB_REPO" "$STAGE"

echo "idd-all: round-2 fixes stay in the text"
assert_grep "Step 0.7 passes --review as an explicit yes/no" '--review "$REVIEW_YN"' "$ALL_TXT"
assert_grep "Step 0.7 records the requested path" '--requested-path "$REQUESTED_PATH"' "$ALL_TXT"
assert_grep "Phase 4 pins verify to the whole branch" "--branch \$(git -C" "$ALL_TXT"
assert_grep "Phase 4 binds the gate to the merge-base range" '--base "$BASE_SHA"' "$(section "$ALL" "### Phase 4")"
assert_grep "Phase 5 reuses an already open PR" "reusing" "$ALL_TXT"
assert_grep "5c.3 confirms the close positively" "close-stage.py\" confirm-close" "$STAGE"
assert_grep "5c.2 calls /idd-close only after a merge or push" "merged|pushed" "$STAGE"
refute_grep "the ask prompt no longer promises no push" "stay on current branch + no push + no PR" "$ALL_TXT"
assert_grep "batch: direct-commit does not switch branches" "direct-commit** 的 batch 不切換 branch" "$ALL_TXT"
assert_grep "Spectra-tier runs are reminded to archive" "/spectra-archive" "$(section "$ALL" "### Phase 6")"

echo "idd-all: round-3 fixes stay in the text"
assert_grep "Step 0.4 resets the previous run's state" 'close-stage.py" reset --cwd' "$ALL_TXT"
assert_grep "Step 0.7 refuses a missing issue number" "FATAL: Step 0.7: issue number is missing" "$ALL_TXT"
assert_grep "chain and --review runs keep the auto-detected verify range" 'VERIFY_ARGS="#$N --cwd $CWD"' "$(section "$ALL" "### Phase 4")"
assert_grep "the close stage requires confirmed intent" "意圖沒有確認過" "$STAGE"
assert_grep "abort removes the run state" "close-stage.py reset --cwd" "$(section "$ALL" "## Failure Modes")"

echo "idd-all: fix loop and report"
P4=$(section "$ALL" "### Phase 4")
assert_grep "Phase 4 consults the verify gate each round" "verify-gate.py --expect-sha" "$P4"
assert_grep "Phase 4 fixes In-scope fix findings when unattended" "In-scope fix" "$P4"
P6=$(section "$ALL" "### Phase 6")
assert_grep "report starts with Done:" "Done:" "$P6"
assert_grep "report has an Undo: section" "Undo:" "$P6"
assert_grep "report names where it stopped" "Stopped:" "$P6"
assert_grep "undo reopens the issue" "gh issue reopen" "$P6"
assert_grep "undo reverts on the default branch" 'checkout ${DEFAULT} && git -C ${CWD} pull --ff-only' "$P6"
assert_grep "undo reverts the commit" 'revert ${MERGE_SHA}' "$P6"

echo "idd-all: description and old sentences"
DESC=$(frontmatter_description "$ALL")
assert_grep "description says a clean verify merges and closes" "verify 乾淨" "$DESC"
assert_grep "description states the meeting exception" "meeting" "$DESC"
refute_grep "no 'never auto-close' in idd-all" "${NEVER} ${AC}" "$ALL_TXT"
refute_grep "no 'never auto-close' (no space) in idd-all" "${NEVER}${AC}" "$ALL_TXT"
refute_grep "no 'never auto-merge PR' rule in idd-all" "${ALWAYS_NOT} ${AM}" "$ALL_TXT"
refute_grep "no 'always stop at verified' rule in idd-all" "永遠""停在 verified" "$ALL_TXT"
refute_grep "no terminal-phase requirement in idd-all" "Verify is the terminal phase ""regardless of mode" "$ALL_TXT"
refute_grep "Phase 0.5.1 no longer calls close irreversible" "擋的是不可逆的 ""close" "$ALL_TXT"
refute_grep "no 'never auto-invoke idd-close' in idd-all" "**${NEVER}**自動跑 \`/idd-close\`" "$ALL_TXT"

echo "idd-close: orchestrated directive"
ORCH=$(section "$CLOSE" "## Orchestrated close")
assert_grep "idd-close has an orchestrated section" "ORCHESTRATED BY /idd-all" "$ORCH"
for step in "Step 1.55" "Step 1.6" "Step 3.5" "Step 3.6" "Step 6.5"; do
  assert_grep "orchestrated defaults cover $step" "$step" "$ORCH"
done
assert_grep "without the directive nothing changes" "沒有收到指示" "$ORCH"
for step in "### Step 1.55" "### Step 1.6" "### Step 3.5" "### Step 3.6" "### Step 6.5"; do
  assert_grep "$step points to the orchestrated default" "ORCHESTRATED" "$(section "$CLOSE" "$step")"
done

echo "MANIFESTO: auto-merge doctrine"
AMS=$(section "$MANI" "### auto-merge 的合法性與限制")
assert_grep "auto-merge section keeps 'verify is the gate'" "verify is the gate" "$AMS"
assert_grep "auto-merge section adds the reversible/traceable reason" "traceable" "$AMS"
assert_grep "auto-merge section points to #392" "#392" "$AMS"
refute_grep "auto-merge section no longer hands auto-merge to #37" "由 #37 處理" "$AMS"
refute_grep "auto-merge section no longer keeps the never-merge rule" "${ALWAYS_NOT} ${AM}" "$AMS"
refute_grep "auto-merge section no longer says idd-all does not auto-merge" "預設**不**做 ${AM}" "$AMS"
VGS=$(section "$MANI" "### \`verify-gated\`")
assert_grep "verify-gated section names merge and close" "close" "$VGS"

echo "parallel-orchestration: batch end state"
refute_grep "batch reference no longer stops at verified" "5. Stop at verified." "$PORCH_TXT"
assert_grep "batch reference merges and closes each issue" "merge" "$(section "$PORCH" "## How \`idd-all\` multi-issue mode")"
assert_grep "batch reference updates the default branch between issues" "--ff-only" "$PORCH_TXT"

print_summary
