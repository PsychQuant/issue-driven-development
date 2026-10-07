#!/usr/bin/env bash
# test.sh — fixture suite for check-existing-work.sh (#366, Spectra change add-existing-work-lookup).
#
# Real git, shimmed gh: the branches, ancestry and tips are a local bare "origin" so stale-merged and E6 are
# decided by git itself; only the GitHub API is faked. Every scenario of the spec idd-existing-work-lookup has a
# test here, and each case builds its own fixtures so one cannot leak into the next.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../check-existing-work.sh"
. "$HERE/../../lib/assert-helpers.sh"
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
GIT_ENV=(-c user.name=t -c user.email=t@t -c init.defaultBranch=main)

# ── hermetic gh ─────────────────────────────────────────────────────────────
FX="$W/fx"; mkdir -p "$W/bin" "$FX"
cat > "$W/bin/gh" <<'SHIM'
#!/usr/bin/env bash
echo "$*" >> "$FX/calls.log"
case "$1 $2" in
  "pr list")
    state=open; prev=""
    for a in "$@"; do [ "$prev" = "--state" ] && state="$a"; prev="$a"; done
    [ -f "$FX/fail_pr_$state" ] && { echo "boom" >&2; exit 1; }
    if [ -f "$FX/pr_$state.jsonl" ]; then jq -s . "$FX/pr_$state.jsonl"; else echo '[]'; fi ;;
  "repo view")
    [ -f "$FX/fail_repo_view" ] && { echo "boom" >&2; exit 1; }
    echo '{"defaultBranchRef":{"name":"main"}}' ;;
  "issue view")
    n="$3"; [ -f "$FX/issue_$n.json" ] && cat "$FX/issue_$n.json" || { echo "no issue" >&2; exit 1; } ;;
  "api repos"*|"api "*)
    case "$2" in
      repos/*/issues/*/events) n="${2#repos/*/issues/}"; n="${n%/events}"
        [ -f "$FX/events_$n.json" ] && cat "$FX/events_$n.json" || echo '[]' ;;
      *) echo "unexpected api $2" >&2; exit 1 ;;
    esac ;;
  *) echo "unexpected gh $*" >&2; exit 1 ;;
esac
SHIM
chmod +x "$W/bin/gh"
export FX

# ── real git origin ─────────────────────────────────────────────────────────
git "${GIT_ENV[@]}" init -q --bare "$W/origin.git"
git "${GIT_ENV[@]}" clone -q "$W/origin.git" "$W/work" 2>/dev/null
( cd "$W/work" && git "${GIT_ENV[@]}" checkout -q -b main && git "${GIT_ENV[@]}" commit -q --allow-empty -m "init" \
  && git "${GIT_ENV[@]}" push -q origin main 2>/dev/null && git "${GIT_ENV[@]}" remote set-head origin main >/dev/null 2>&1 )

mkbr() { # name message → creates origin branch with one commit on top of main, prints its tip
  ( cd "$W/work" && git "${GIT_ENV[@]}" checkout -q -b "$1" origin/main 2>/dev/null \
    && git "${GIT_ENV[@]}" commit -q --allow-empty -m "$2" && git "${GIT_ENV[@]}" push -q origin "$1" 2>/dev/null \
    && git rev-parse HEAD; git "${GIT_ENV[@]}" checkout -q main )
}

# ── fixture builders ────────────────────────────────────────────────────────
reset_fx() { rm -f "$FX"/*; }
issue() { # n state created
  jq -n --arg c "$3" --arg s "$2" '{createdAt:$c,state:$s}' > "$FX/issue_$1.json"; }
pr() { # state number head headOid created mergedAt body
  jq -n --argjson n "$2" --arg h "$3" --arg o "$4" --arg c "$5" --arg m "$6" --arg b "$7" \
     '{number:$n,headRefName:$h,headRefOid:$o,createdAt:$c,mergedAt:(if $m=="" then null else $m end),body:$b,url:("https://x/pull/"+($n|tostring))}' >> "$FX/pr_$1.jsonl"; }
run() { PATH="$W/bin:$PATH" bash "$SCRIPT" --cwd "$W/work" test/repo "$@" 2>"$W/stderr"; }
field() { python3 -c 'import json,sys; d=json.loads(sys.argv[1]); print(eval(sys.argv[2]))' "$1" "$2" 2>/dev/null; }
kinds() { field "$1" "sorted(e['kind'] for e in d['issues']['$2']['evidence'])"; }
verdict() { field "$1" "d['issues']['$2']['verdict']"; }

ISSUE_T=2026-10-01T00:00:00Z; NEWER=2026-10-05T10:00:00Z; OLDER=2026-09-01T00:00:00Z

# ── 1. declared vs mentioned ────────────────────────────────────────────────
reset_fx; issue 258 OPEN $ISSUE_T; issue 265 OPEN $ISSUE_T
pr open 10 "codex/x" aaa $NEWER "" $'Refs #258\n\nbody'
pr open 11 "codex/y" bbb $NEWER "" $'## Recorded, not changed here\n- #265: tabs reads every tab twice'
OUT=$(run 258 265)
assert_eq "declared line → E1" "['E1']" "$(kinds "$OUT" 258)"
assert_eq "declared foreign PR → blocked" "blocked" "$(verdict "$OUT" 258)"
assert_eq "only mentioned → E2" "['E2']" "$(kinds "$OUT" 265)"
assert_eq "only mentioned → not blocked (clear)" "clear" "$(verdict "$OUT" 265)"

# ── 2. fenced declaration, cross-repo form, older than the issue ────────────
reset_fx; issue 42 OPEN $ISSUE_T; issue 7 OPEN $ISSUE_T; issue 50 OPEN $ISSUE_T
pr open 12 "codex/f" ccc $NEWER "" $'example:\n```\nCloses #42\n```\n'
pr open 13 "codex/c" ddd $NEWER "" $'Refs codex-pro#7\nsee PsychQuant/foo#7 and #70'
pr open 14 "codex/o" eee $OLDER "" $'Refs #50'
OUT=$(run 42 7 50)
refute_grep "fenced Closes is not E1" "E1" "$(kinds "$OUT" 42)"
assert_eq "cross-repo / longer-number forms do not match #7" "[]" "$(kinds "$OUT" 7)"
assert_eq "PR older than the issue is not reported" "[]" "$(kinds "$OUT" 50)"

# ── 3. branches: other prefix, stale merged, unmerged idd/N ─────────────────
reset_fx; issue 124 OPEN $ISSUE_T; issue 255 OPEN $ISSUE_T; issue 300 OPEN $ISSUE_T
mkbr "codex/119-124-install-contract" "no trailer here" >/dev/null
TIP255=$(mkbr "idd/255-js-fewer-roundtrips" "work for 255")
mkbr "idd/300-x" "work for 300" >/dev/null
pr merged 256 "idd/255-js-fewer-roundtrips" "$TIP255" $NEWER $NEWER "Refs #255"
OUT=$(run 124 255 300)
assert_eq "other-prefix multi-number branch is not reported" "[]" "$(kinds "$OUT" 124)"
refute_grep "stale-merged branch is not E4" "E4" "$(kinds "$OUT" 255)"
assert_eq "unmerged idd/N-* branch → E4" "['E4']" "$(kinds "$OUT" 300)"
assert_eq "E4 alone → resume" "resume" "$(verdict "$OUT" 300)"

# ── 4. E6: Refs in an unmerged commit; not on a stale branch ────────────────
reset_fx; issue 77 OPEN $ISSUE_T; issue 78 OPEN $ISSUE_T
mkbr "feature/x" $'subject\n\nRefs #77' >/dev/null
TIPS=$(mkbr "feature/stale" $'subject\n\nRefs #78')
pr merged 90 "feature/stale" "$TIPS" $NEWER $NEWER "done"
OUT=$(run 77 78)
assert_eq "unmerged commit with Refs → E6" "['E6']" "$(kinds "$OUT" 77)"
assert_eq "E6 alone does not block" "clear" "$(verdict "$OUT" 77)"
assert_eq "Refs on a stale-merged branch is not E6" "[]" "$(kinds "$OUT" 78)"

# ── 4b. the default branch comes from GitHub, not from a possibly stale local origin/HEAD ──
# (found on real data: a clone whose origin/HEAD pointed at an old feature branch reported every commit on main
#  that carried `Refs #N` as E6)
reset_fx; issue 61 OPEN $ISSUE_T
mkbr "idd/999-stale" "unrelated" >/dev/null
( cd "$W/work" && git "${GIT_ENV[@]}" checkout -q main && git "${GIT_ENV[@]}" commit -q --allow-empty -m $'subject\n\nRefs #61' \
  && git "${GIT_ENV[@]}" push -q origin main 2>/dev/null && git "${GIT_ENV[@]}" remote set-head origin idd/999-stale >/dev/null 2>&1 )
OUT=$(run 61)
assert_eq "a Refs commit on the default branch is not E6, even when local origin/HEAD is stale" "[]" "$(kinds "$OUT" 61)"
touch "$FX/fail_repo_view"; OUT=$(run 61)
assert_eq "default branch from GitHub unavailable → falls back to origin/HEAD (here stale → reported, not hidden)" "['E6']" "$(kinds "$OUT" 61)"
rm -f "$FX/fail_repo_view"
( cd "$W/work" && git "${GIT_ENV[@]}" remote set-head origin main >/dev/null 2>&1 )

# ── 5. E3 and the reopen exception ──────────────────────────────────────────
reset_fx; issue 12 OPEN $ISSUE_T
pr merged 20 "codex/m" mmm $NEWER 2026-10-06T00:00:00Z $'Closes #12'
OUT=$(run 12)
assert_eq "merged declaring PR, issue open → E3" "['E3']" "$(kinds "$OUT" 12)"
assert_eq "…and blocked" "blocked" "$(verdict "$OUT" 12)"
printf '[{"event":"reopened","created_at":"2026-10-07T00:00:00Z"}]' > "$FX/events_12.json"
OUT=$(run 12)
assert_eq "reopened after merge → still listed" "['E3']" "$(kinds "$OUT" 12)"
refute_grep "reopened after merge → not blocked" "blocked" "$(verdict "$OUT" 12)"
printf '[{"event":"reopened","created_at":"2026-10-05T00:00:00Z"}]' > "$FX/events_12.json"
OUT=$(run 12)
assert_eq "reopened BEFORE merge does not excuse" "blocked" "$(verdict "$OUT" 12)"
issue 12 CLOSED $ISSUE_T; rm -f "$FX/events_12.json"
OUT=$(run 12)
assert_eq "issue CLOSED → no E3" "[]" "$(kinds "$OUT" 12)"
reset_fx; issue 13 OPEN $ISSUE_T; pr open 21 "codex/q" qqq $NEWER "" 'Refs #13'
: > "$FX/calls.log"; run 13 >/dev/null
refute_grep "timeline is not queried without an E3 hit" "events" "$(cat "$FX/calls.log")"

# ── 6. own PR / foreign PR ──────────────────────────────────────────────────
reset_fx; issue 258 OPEN $ISSUE_T
pr open 30 "idd/258-isolated-bootstrap-test-timeout" ooo $NEWER "" 'Refs #258'
OUT=$(run 258)
assert_eq "own idd/N-* PR → resume" "resume" "$(verdict "$OUT" 258)"
pr open 31 "codex/258-x" ppp $NEWER "" 'Refs #258'
OUT=$(run 258)
assert_eq "own PR plus a foreign declaring PR → blocked" "blocked" "$(verdict "$OUT" 258)"

# ── 7. failure and truncation are unknown, never clear ──────────────────────
reset_fx; issue 9 OPEN $ISSUE_T; touch "$FX/fail_pr_open"
OUT=$(run 9); rc=$?
assert_exit "gh failure still produces a result (exit 0)" 0 $rc
assert_eq "gh failure → unknown" "unknown" "$(verdict "$OUT" 9)"
assert_true "gh failure carries a reason" "[ -n \"$(field "$OUT" "d['issues']['9'].get('reason','')")\" ]"
reset_fx; issue 9 OPEN $ISSUE_T
for i in $(seq 1 100); do pr open "$((1000 + i))" "x/$i" "o$i" $NEWER "" "nothing here"; done
OUT=$(run 9)
assert_eq "open list at its limit → truncated" "True" "$(field "$OUT" "d['truncated']")"
assert_eq "…and an issue without evidence is unknown, not clear" "unknown" "$(verdict "$OUT" 9)"

# ── 8. one fetch for the whole call ─────────────────────────────────────────
reset_fx; issue 1 OPEN $ISSUE_T; issue 2 OPEN $ISSUE_T; issue 3 OPEN $ISSUE_T
run 1 2 3 >/dev/null
assert_eq "open PR list fetched once for three issues" "1" "$(grep -c 'pr list.*--state open' "$FX/calls.log")"
assert_eq "merged PR list fetched once for three issues" "1" "$(grep -c 'pr list.*--state merged' "$FX/calls.log")"
assert_eq "one entry per issue" "['1', '2', '3']" "$(field "$(run 1 2 3)" "sorted(d['issues'])")"

# ── 9. usage ────────────────────────────────────────────────────────────────
PATH="$W/bin:$PATH" bash "$SCRIPT" >/dev/null 2>&1; assert_exit "no arguments → exit 2" 2 $?
PATH="$W/bin:$PATH" bash "$SCRIPT" test/repo abc >/dev/null 2>&1; assert_exit "non-numeric issue → exit 2" 2 $?

# ── 10. wiring: every consumer calls the helper, in the right place, with no private matcher (tasks 3.2 to 3.6) ──
SK="$HERE/../../../skills"
line() { grep -n -F -m1 -- "$2" "$1" | cut -d: -f1; }                      # first line number of a fixed string
section() { awk -v a="$2" -v b="$3" 'index($0,a)==1{f=1} f&&index($0,b)==1&&!index($0,a){exit} f' "$1"; }
before() { [ -n "$1" ] && [ -n "$2" ] && [ "$1" -lt "$2" ]; }

ALL="$SK/idd-all/SKILL.md"; CHAIN="$SK/idd-all-chain/SKILL.md"; IMPL="$SK/idd-implement/SKILL.md"
DIAG="$SK/idd-diagnose/SKILL.md"; CLOSE="$SK/idd-close/SKILL.md"
assert_true "idd-all: the check precedes the PR-mode branch setup" 'before "$(line "$ALL" "#### Step 0.5.1: Existing-work check")" "$(line "$ALL" "**PR mode branch setup**")"'
assert_grep "idd-all: calls the helper" "check-existing-work.sh" "$(section "$ALL" "#### Step 0.5.1" "**PR mode branch setup**")"
assert_grep "idd-all: tells idd-implement the check is done" "--existing-work-checked" "$(cat "$ALL")"
assert_grep "idd-all: prints the verdict (the model only sees Bash output)" 'echo "→ Existing work' "$(section "$ALL" "#### Step 0.5.1" "**PR mode branch setup**")"
assert_true "idd-all-chain: the check precedes the cap preflight" 'before "$(line "$CHAIN" "#### Step 0.4.1: Existing-work check")" "$(line "$CHAIN" "#### Step 0.4.5")"'
assert_grep "idd-all-chain: calls the helper" "check-existing-work.sh" "$(section "$CHAIN" "#### Step 0.4.1" "#### Step 0.4.5")"
assert_true "idd-implement: the check precedes tree-lock" 'before "$(line "$IMPL" "### Step 0.37: Existing-work check")" "$(line "$IMPL" "### Step 0.4: Tree-lock")"'
assert_true "idd-implement: the check follows the actionability gate" 'before "$(line "$IMPL" "### Step 0.35")" "$(line "$IMPL" "### Step 0.37")"'
assert_grep "idd-implement: honours --existing-work-checked" '--existing-work-checked' "$(section "$IMPL" "### Step 0.37" "### Step 0.4: Tree-lock")"
assert_grep "idd-implement: the flag is in the argument hint" '[--existing-work-checked]' "$(sed -n '9p' "$IMPL")"
DSEC="$(section "$DIAG" "### Step 1.6: Existing work" "### Step 2: ")"
assert_grep "idd-diagnose: calls the helper" "check-existing-work.sh" "$DSEC"
assert_grep "idd-diagnose: says it never stops" "絕不停止" "$DSEC"
refute_grep_re "idd-diagnose: no abort or exit in the step" '(^|[^A-Za-z])(abort|exit [0-9])' "$(printf '%s\n' "$DSEC" | grep -v '^\*\*\|^診斷是唯讀')"
assert_grep "idd-diagnose: the Diagnosis template has the section" "### Existing work" "$(cat "$DIAG")"
CSEC="$(section "$CLOSE" "### Step 1.5: PR Gate Check" "### Step 1.55")"
assert_grep "idd-close: Step 1.5 calls the helper" "check-existing-work.sh" "$CSEC"
refute_grep "idd-close: Step 1.5 has no private open-PR search" 'gh pr list --repo "$GITHUB_REPO" --state open' "$CSEC"
assert_grep "idd-close: refuses when the open PR list is unknown" "fail-closed" "$CSEC"
assert_grep "idd-close: Step 1.55 keeps its own matching (not migrated)" 'gh pr list --repo "$GITHUB_REPO" --state merged' "$(section "$CLOSE" "### Step 1.55" "### Step 1.6")"

# ── 11. a lookup that observed nothing is never read as an answer (skill snippets, executed) ──
# Each skill's own first bash block is run, not grepped. Two shapes of the same defect:
#   (a) the helper crashes (no stdout). `|| EW_JSON=""` handed jq an empty input, and jq given no input prints
#       nothing, so `// "unknown"` never fired and the verdict came out EMPTY: no row of the table, not unknown.
#   (b) idd-close Step 1.5 when `gh issue view` fails: the issue gets no evidence at all, the gate only refused on
#       open-PR list errors, so an open PR declaring the issue was never matched and the gate passed.
snippet() { printf '%s\n' "$1" | awk '/^```bash/{f=1; next} f&&/^```/{exit} f'; }
CRASH="$W/crashroot"; mkdir -p "$CRASH/scripts"
printf '#!/usr/bin/env bash\nexit 1\n' > "$CRASH/scripts/check-existing-work.sh"
crashed() { # prelude section → what the skill prints when the helper produced no output
  CLAUDE_PLUGIN_ROOT="$CRASH" CWD="$W/work" GITHUB_REPO=test/repo PATH="$W/bin:$PATH" bash -c "$1
$(snippet "$2")" _ 2>&1; }
assert_grep "idd-all: a crashed lookup prints verdict=unknown" "verdict=unknown" \
  "$(crashed 'IN_CHAIN=""; N=5' "$(section "$ALL" "#### Step 0.5.1" "**PR mode branch setup**")")"
assert_grep "idd-all-chain: a crashed lookup prints verdict=unknown" "verdict=unknown" \
  "$(crashed 'ROOT_ISSUES_SORTED=(5)' "$(section "$CHAIN" "#### Step 0.4.1" "#### Step 0.4.5")")"
assert_grep "idd-implement: a crashed lookup prints verdict=unknown" "verdict=unknown" \
  "$(crashed 'ISSUE_NUMBERS=(5)' "$(section "$IMPL" "### Step 0.37" "### Step 0.4: Tree-lock")")"
assert_grep "idd-diagnose: a crashed lookup prints verdict=unknown" "verdict=unknown" "$(crashed 'NUMBER=5' "$DSEC")"

reset_fx                                    # no issue_5.json → `gh issue view 5` fails
pr open 20 "codex/z" ccc $NEWER "" $'Refs #5\n\nbody'
CLOSE_OUT=$(CLAUDE_PLUGIN_ROOT="$HERE/../../.." WORKDIR="$W/work" GITHUB_REPO=test/repo NUMBER=5 PATH="$W/bin:$PATH" \
  bash -c "$(snippet "$CSEC")" 2>&1); CLOSE_RC=$?
assert_eq "idd-close: an issue the lookup could not read does not pass the PR gate" 1 "$CLOSE_RC"
assert_grep "idd-close: and says why" "refusing to close" "$CLOSE_OUT"

print_summary "check-existing-work"
