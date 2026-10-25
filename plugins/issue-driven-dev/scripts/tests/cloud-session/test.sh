#!/usr/bin/env bash
# test.sh — cloud-session runtime contract (#416, change cloud-session-idd-all).
#
#   lib      scripts/lib/cloud-session.sh — CLAUDE_CODE_REMOTE / CLAUDE_CODE_SESSION_ATTENDED are
#            read as exact literals; anything else is "not cloud" / "unattended".
#   notes    every in-scope skill carries the supported runtime note, every unsupported one the stop
#            note, and the reference maps every porcelain form the spec lists (drift guard).
#   wiring   idd-all resolves the cloud mode before fork / pr_policy; idd-verify skips the Codex leg.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/../../lib/assert-helpers.sh"
LIB="$HERE/../../lib/cloud-session.sh"

# ── lib: detection ──────────────────────────────────────────────────────────
is_cloud() { env -u CLAUDE_CODE_REMOTE ${1:+CLAUDE_CODE_REMOTE="$1"} bash -c '. "$0"; idd_is_cloud_session' "$LIB"; }
interaction() { env -u CLAUDE_CODE_SESSION_ATTENDED ${1:+CLAUDE_CODE_SESSION_ATTENDED="$1"} bash -c '. "$0"; idd_cloud_interaction' "$LIB"; }

is_cloud true;  require "CLAUDE_CODE_REMOTE=true → cloud" test $? -eq 0
is_cloud "";    refute  "CLAUDE_CODE_REMOTE unset → not cloud" test $? -eq 0
is_cloud 1;     refute  "CLAUDE_CODE_REMOTE=1 → not cloud (literal true only)" test $? -eq 0
is_cloud TRUE;  refute  "CLAUDE_CODE_REMOTE=TRUE → not cloud (case-sensitive)" test $? -eq 0
is_cloud false; refute  "CLAUDE_CODE_REMOTE=false → not cloud" test $? -eq 0
( export CLAUDE_CODE_REMOTE=""; bash -c '. "$0"; idd_is_cloud_session' "$LIB" ); refute "CLAUDE_CODE_REMOTE empty → not cloud" test $? -eq 0

assert_eq "attended signal 1 → attended"           "attended"   "$(interaction 1)"
assert_eq "attended signal unset → unattended"     "unattended" "$(interaction "")"
assert_eq "attended signal 0 → unattended"         "unattended" "$(interaction 0)"
assert_eq "attended signal true → unattended (literal 1 only)" "unattended" "$(interaction true)"

# sourcing must not leak set -e / set -u changes or print anything
OUT="$(bash -c 'set +u; . "$0"; echo "u=$-"' "$LIB")"
refute_grep "sourcing does not turn on nounset" "u" "${OUT#u=}"
assert_eq "sourcing prints nothing" "" "$(bash -c '. "$0"' "$LIB")"

# ── notes: runtime notes and the reference (drift guard) ────────────────────
SK="$HERE/../../../skills"
REF="$HERE/../../../references/claude-code-remote-tools.md"
SUPPORTED_MARK='> **Cloud session（#416）**：'
STOP_MARK='> **Cloud session（#416）— 不支援**：'
for s in idd-all idd-issue idd-diagnose idd-plan idd-implement idd-verify idd-update idd-clarify idd-list; do
  assert_output_grep "$s: supported runtime note" "$SUPPORTED_MARK" "$SK/$s/SKILL.md"
  assert_output_grep "$s: note links the reference" "../../references/claude-code-remote-tools.md" "$SK/$s/SKILL.md"
  refute_output_grep "$s: no stop note" "$STOP_MARK" "$SK/$s/SKILL.md"
done
for s in idd-find idd-report idd-discuss idd-ask; do
  assert_output_grep "$s: stop runtime note" "$STOP_MARK" "$SK/$s/SKILL.md"
  refute_output_grep "$s: no supported note" "$SUPPORTED_MARK" "$SK/$s/SKILL.md"
done
for form in "gh issue view" "gh issue list" "gh issue create" "gh issue comment" "gh issue edit" \
            "gh pr list" "gh pr view" "gh pr create" "gh repo view" "gh label list" "gh auth status"; do
  assert_output_grep "reference maps \`$form\`" "| \`$form" "$REF"
done
# the setup-script pins are the egress requirements, spelled out (the script may run before checkout)
while IFS= read -r req; do
  case "$req" in ''|'#'*) continue ;; esac
  assert_output_grep "reference setup script pins $req" "$req" "$REF"
done < "$HERE/../../requirements-egress.txt"

# ── wiring: idd-all mode resolution and idd-verify Codex leg ────────────────
ALL="$SK/idd-all/SKILL.md"; VER="$SK/idd-verify/SKILL.md"
line() { grep -n -F -m1 -- "$2" "$1" | cut -d: -f1; }
before() { [ -n "$1" ] && [ -n "$2" ] && [ "$1" -lt "$2" ]; }
assert_output_grep "idd-all: sources the cloud-session helper" 'scripts/lib/cloud-session.sh' "$ALL"
assert_true "idd-all: cloud rule precedes fork detection in the resolution bash" \
  'before "$(line "$ALL" "elif idd_is_cloud_session")" "$(line "$ALL" "IS_FORK_RAW=")"'
assert_output_grep "idd-all: precedence table names (PR, attended)" "(PR, attended)" "$ALL"
assert_output_grep "idd-all: auth gate falls back to gh api user" '{ gh auth status > /dev/null 2>&1 || gh api user --jq .login > /dev/null 2>&1; }' "$ALL"
refute_output_grep "idd-all: no bare gh auth status gate" 'gh auth status > /dev/null 2>&1 || abort' "$ALL"
# executed, not grepped: run idd-all's own Phase 0.5 resolution block per scenario
block_with() { awk -v needle="$2" '/^```bash/{buf=""; f=1; next} f&&/^```/{if (index(buf, needle)) {printf "%s", buf; exit} f=0; next} f{buf=buf $0 "\n"}' "$1"; }
RESOLVE="$(block_with "$ALL" 'PR_POLICY="absent"')"
assert_true "idd-all: the Phase 0.5 resolution block was found" '[ -n "$RESOLVE" ]'
W="$(mktemp -d)"; trap 'rm -rf "$W"' EXIT
# gh stub: answers the fork probe only when FAKE_IS_FORK is set; everything else fails like a blocked call
printf '#!/usr/bin/env bash\ncase "$*" in *isFork*) [ -n "${FAKE_IS_FORK:-}" ] && { echo "$FAKE_IS_FORK"; exit 0; } ;; esac\necho "gh: blocked (test)" >&2\nexit 1\n' > "$W/gh"; chmod +x "$W/gh"
resolve() { # remote attended pr_flag [policy] [is_fork] → "PATH_AXIS INTERACTION | REASON"
  local cfg=""
  if [ -n "${4:-}" ]; then cfg="$W/cfg.json"; printf '{"pr_policy":"%s"}' "$4" > "$cfg"; fi
  env -u CLAUDE_CODE_REMOTE -u CLAUDE_CODE_SESSION_ATTENDED ${1:+CLAUDE_CODE_REMOTE="$1"} ${2:+CLAUDE_CODE_SESSION_ATTENDED="$2"} \
    PATH="$W:$PATH" CLAUDE_PLUGIN_ROOT="$HERE/../../.." PR_FLAG="$3" IN_CHAIN="" CONFIG_PATH="$cfg" GITHUB_REPO=o/r \
    FAKE_IS_FORK="${5:-}" \
    bash -c 'abort() { echo "ABORT: $*"; exit 1; }
'"$RESOLVE"'
echo "$PATH_AXIS $INTERACTION | $REASON"' 2>/dev/null; }
assert_grep "cloud + attended, no flag → (PR, attended)"            "PR attended |"   "$(resolve true 1 "")"
assert_grep "cloud + attended, pr_policy=never → still (PR, attended)" "PR attended |" "$(resolve true 1 "" never)"
assert_grep "cloud, no attended signal → (PR, unattended)"          "PR unattended |" "$(resolve true "" "")"
OUT="$(resolve true 1 --no-pr)"
assert_grep "cloud + --no-pr → (PR, attended)"                      "PR attended |"   "$OUT"
assert_grep "…with the override reason"                             "flag=--no-pr overridden: cloud session" "$OUT"
assert_grep "cloud + --pr → (PR, unattended), unchanged"            "PR unattended | flag=--pr" "$(resolve true 1 --pr)"
assert_grep "local --no-pr → (direct-commit, attended), unchanged"  "direct-commit attended | flag=--no-pr" "$(resolve "" "" --no-pr)"
assert_grep "local pr_policy=never → (direct-commit, attended), unchanged" "direct-commit attended | pr_policy=never" "$(resolve "" "" "" never false)"
assert_grep "local, fork lookup fails → fail-closed (PR, unattended), unchanged" "PR unattended | fork detected" "$(resolve "" "" "")"

# executed: Phase 0.6 (ralph-loop gate) and Phase 5 (push + PR) in a real repo with a bare origin.
# A fake plugin root links the real libs and supplies a failing ralph-loop check, so the result does
# not depend on what the host has installed.
GIT_ENV=(-c user.name=t -c user.email=t@t -c init.defaultBranch=main)
FR="$W/root"; mkdir -p "$FR/scripts/lib"
for f in "$HERE/../../lib/"*; do ln -s "$f" "$FR/scripts/lib/$(basename "$f")"; done
printf '#!/usr/bin/env bash\nexit 1\n' > "$FR/scripts/check-ralph-loop.sh"; chmod +x "$FR/scripts/check-ralph-loop.sh"
mkdir -p "$W/gh2"; cat > "$W/gh2/gh" <<'STUB'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$GH2_LOG"
[ "$1" = "api" ] || { echo "unexpected porcelain gh $*" >&2; exit 1; }
case "$2" in
  repos/o/r)                 [ -n "${GH2_FAIL_REPO:-}" ] && { echo '{"message":"Not Found","status":"404"}'; echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
                             case " $* " in *" --jq .default_branch "*) echo main ;; *) echo '{"full_name":"o/r","default_branch":"main"}' ;; esac ;;
  repos/o/r/issues/5/comments) echo '[]' ;;
  repos/o/r/issues/19)       [ -n "${GH2_FAIL_TITLE:-}" ] && { echo '{"message":"Not Found","documentation_url":"https://docs.github.com/rest","status":"404"}'; echo "gh: Not Found (HTTP 404)" >&2; exit 1; }
                             echo "Some Title" ;;
  repos/o/r/pulls)           for a in "$@"; do case "$a" in body=@*) cp "${a#body=@}" "$GH2_PRBODY" ;; esac; done
                             echo "https://github.com/o/r/pull/77" ;;
  *) echo "unexpected api $2" >&2; exit 1 ;;
esac
STUB
chmod +x "$W/gh2/gh"; export GH2_LOG="$W/gh2.log" GH2_PRBODY="$W/prbody.md"
newrepo() { # → $W/repo-<name> on main with an idd/5-x branch checked out, bare origin
  local r="$W/repo-$1"
  git "${GIT_ENV[@]}" init -q --bare "$r.git"; git "${GIT_ENV[@]}" clone -q "$r.git" "$r" 2>/dev/null
  ( cd "$r" && git "${GIT_ENV[@]}" checkout -q -b main && git "${GIT_ENV[@]}" commit -q --allow-empty -m init \
    && git "${GIT_ENV[@]}" push -q origin main 2>/dev/null && git "${GIT_ENV[@]}" checkout -q -b idd/5-x ); }
P06="$(block_with "$ALL" 'check-ralph-loop.sh')"
P5="$(block_with "$ALL" 'VERIFY_LINE=')"
P05PR="$(block_with "$ALL" 'PR-mode-only preconditions')"
assert_true "idd-all: Phase 0.6 and Phase 5 blocks were found" '[ -n "$P06" ] && [ -n "$P5" ]'
run_block() { # remote block repo [extra env…] → combined output; returns the block's exit code
  local remote="$1" block="$2" repo="$3"; shift 3
  OUT="$(env -u CLAUDE_CODE_REMOTE -u CLAUDE_CODE_SESSION_ATTENDED ${remote:+CLAUDE_CODE_REMOTE="$remote"} \
    PATH="$W/gh2:$PATH" CLAUDE_PLUGIN_ROOT="$FR" CWD="$repo" GITHUB_REPO=o/r N=5 BRANCH=idd/5-x IN_CHAIN="" \
    PATH_AXIS=PR INTERACTION=unattended REASON=test PR_TITLE="T" COMMIT_COUNT=1 "$@" \
    bash -c "$block" 2>&1)"; local rc=$?; printf '%s' "$OUT"; return $rc; }
newrepo a; OUT="$(run_block true "$P06" "$W/repo-a")"; RC=$?
assert_exit "Phase 0.6 cloud + no ralph-loop → stops (exit 1), even without an abort helper" 1 "$RC"
assert_grep "…saying ralph-loop is required" "ralph-loop is required" "$OUT"
refute_grep "…never degrading to direct-commit" "Path: direct-commit" "$OUT"
refute "…and the new branch was removed" git -C "$W/repo-a" show-ref --verify --quiet refs/heads/idd/5-x
newrepo a2; mkdir -p "$W/repo-a2/.claude/.idd/state"; echo '{}' > "$W/repo-a2/.claude/.idd/state/unattended.json"
run_block true "$P06" "$W/repo-a2" >/dev/null
refute "…and clears the unattended flag Phase 0.5 set (abort duty, #123)" test -e "$W/repo-a2/.claude/.idd/state/unattended.json"
newrepo a3; OUT="$(run_block true "$P06" "$W/repo-a3" GH2_FAIL_REPO=1)"; RC=$?
assert_exit "Phase 0.6 cloud, default branch unreadable → still stops" 1 "$RC"
assert_grep "…saying the branch was left in place" "left checked out" "$OUT"
refute_grep "…never checking out the gh error text" "Not Found\"" "$(git -C "$W/repo-a3" branch --list)"
newrepo a4; OUT="$(run_block "" "$P06" "$W/repo-a4" GH2_FAIL_REPO=1)"; RC=$?
assert_exit "Phase 0.6 local, default branch unreadable → stops instead of degrading onto the feature branch" 1 "$RC"
refute_grep "…no degrade" "Path: direct-commit" "$OUT"
newrepo b; OUT="$(run_block "" "$P06" "$W/repo-b")"
assert_grep "Phase 0.6 local + no ralph-loop → degrades as before" "Path: direct-commit (attended)" "$OUT"
newrepo c; : > "$GH2_LOG"; OUT="$(run_block true "$P5" "$W/repo-c" VERIFY_STATE=PASS)"; RC=$?
assert_exit "Phase 5 cloud + PASS completes" 0 "$RC"
assert_grep "…pushes the branch" "idd/5-x" "$(git -C "$W/repo-c.git" branch --list)"
assert_grep "…opens the PR through REST" "api repos/o/r/pulls -X POST" "$(cat "$GH2_LOG")"
assert_grep "…from the branch onto the default branch" "head=idd/5-x -f base=main" "$(cat "$GH2_LOG")"
assert_output_grep "…and the PR body says the verify was Claude-only" "Claude-only verification PASS(cloud session" "$GH2_PRBODY"
newrepo d; : > "$GH2_LOG"; OUT="$(run_block true "$P5" "$W/repo-d" VERIFY_STATE=BLOCKING INTERACTION=attended)"
assert_grep "Phase 5 cloud + blocking findings: branch pushed" "idd/5-x" "$(git -C "$W/repo-d.git" branch --list)"
refute_grep "…but no PR opened" "repos/o/r/pulls" "$(cat "$GH2_LOG")"
newrepo f; : > "$GH2_LOG"; OUT="$(run_block true "$P5" "$W/repo-f")"; RC=$?
assert_exit "Phase 5 with VERIFY_STATE unset (shell state lost) → stops" 1 "$RC"
refute_grep "…pushing nothing" "idd/5-x" "$(git -C "$W/repo-f.git" branch --list)"
refute_grep "…and opening no PR" "repos/o/r/pulls" "$(cat "$GH2_LOG")"
newrepo g; rm -rf "$W/repo-g.git"; : > "$GH2_LOG"; OUT="$(run_block true "$P5" "$W/repo-g" VERIFY_STATE=PASS)"; RC=$?
assert_exit "Phase 5 push failure → stops" 1 "$RC"
assert_grep "…saying the push failed" "git push failed" "$OUT"
refute_grep "…before any PR is opened" "repos/o/r/pulls" "$(cat "$GH2_LOG")"
newrepo h; rm -rf "$W/repo-h.git"; OUT="$(run_block true "$P5" "$W/repo-h" VERIFY_STATE=BLOCKING)"; RC=$?
assert_exit "Phase 5 cloud + blocking + push failure → stops" 1 "$RC"
assert_grep "…warning the branch exists only in the container" "only in this container" "$OUT"
newrepo i; : > "$GH2_LOG"; OUT="$(run_block true "$P5" "$W/repo-i" VERIFY_STATE=PASS GH2_FAIL_REPO=1)"; RC=$?
assert_exit "Phase 5 default branch unreadable → stops" 1 "$RC"
refute_grep "…the gh error body never becomes the PR base" "repos/o/r/pulls" "$(cat "$GH2_LOG")"
# Phase 0.5 PR setup (N is the block's own example value, 19): every stop is a real exit — no block
# defines `abort`, so a stop that relied on it fell through into `git checkout -b` (verify round 3)
assert_true "idd-all: the Phase 0.5 PR setup block was found" '[ -n "$P05PR" ]'
p05() { newrepo "$1"; git -C "$W/repo-$1" checkout -q "${2:-main}" 2>/dev/null || git -C "$W/repo-$1" checkout -q -b "$2"; shift 2; }
p05 p1 main; OUT="$(run_block true "$P05PR" "$W/repo-p1")"; RC=$?
assert_exit "Phase 0.5 PR setup on a clean default branch succeeds" 0 "$RC"
assert_eq "…and checks out idd/19-some-title" "idd/19-some-title" "$(git -C "$W/repo-p1" branch --show-current)"
p05 p2 main; mkdir -p "$W/repo-p2/.claude/.idd/state"; echo '{}' > "$W/repo-p2/.claude/.idd/state/unattended.json"
printf '.claude/\n' >> "$W/repo-p2/.git/info/exclude"
OUT="$(run_block true "$P05PR" "$W/repo-p2" GH2_FAIL_TITLE=1)"; RC=$?
assert_exit "Phase 0.5: an unreadable issue title stops the run" 1 "$RC"
assert_grep "…saying why" "could not read the title" "$OUT"
assert_eq "…without creating a branch from the error text" "main" "$(git -C "$W/repo-p2" branch --show-current)"
refute "…and clears the unattended flag (abort duty, #123)" test -e "$W/repo-p2/.claude/.idd/state/unattended.json"
p05 p3 feature-x; OUT="$(run_block true "$P05PR" "$W/repo-p3" GH2_FAIL_REPO=1)"; RC=$?
assert_exit "Phase 0.5: an unreadable default branch stops the run" 1 "$RC"
assert_eq "…without branching off feature-x" "feature-x" "$(git -C "$W/repo-p3" branch --show-current)"
p05 p4 feature-x; OUT="$(run_block "" "$P05PR" "$W/repo-p4")"; RC=$?
assert_exit "Phase 0.5: off the default branch stops the run (local too)" 1 "$RC"
refute_grep "…never 'command not found'" "command not found" "$OUT"
newrepo e; : > "$GH2_LOG"; run_block "" "$P5" "$W/repo-e" VERIFY_STATE=PASS >/dev/null
assert_output_grep "Phase 5 local + PASS: PR body keeps the 6-AI line" "6-AI cross-model verification PASS" "$GH2_PRBODY"
refute_grep "Phase 5: no porcelain reaches gh" "unexpected porcelain" "$(cat "$GH2_LOG") $OUT"

assert_output_grep "idd-verify: resolves CODEX_ENABLED from the cloud signal" 'CODEX_ENABLED=false' "$VER"
assert_output_grep "idd-verify: workflow args pass the resolved flag" 'codexEnabled: $CODEX_ENABLED' "$VER"
assert_output_grep "idd-verify: report states the degraded leg" 'Codex leg not run — cloud session (degraded: Claude-only)' "$VER"

print_summary "cloud-session (#416)"
