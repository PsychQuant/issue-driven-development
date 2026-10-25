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
assert_output_grep "idd-all: auth gate uses gh api user" 'gh api user --jq .login > /dev/null 2>&1 || abort' "$ALL"
refute_output_grep "idd-all: no gh auth status gate" 'gh auth status > /dev/null' "$ALL"
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

assert_output_grep "idd-verify: resolves CODEX_ENABLED from the cloud signal" 'CODEX_ENABLED=false' "$VER"
assert_output_grep "idd-verify: workflow args pass the resolved flag" 'codexEnabled: $CODEX_ENABLED' "$VER"
assert_output_grep "idd-verify: report states the degraded leg" 'Codex leg not run — cloud session (degraded: Claude-only)' "$VER"

print_summary "cloud-session (#416)"
