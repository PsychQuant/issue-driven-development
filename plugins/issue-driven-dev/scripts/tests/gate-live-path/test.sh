#!/usr/bin/env bash
# Test: the `--issue N` GATE, exercised on its LIVE path (#320 verify FAIL).
#
# WHY THIS SUITE EXISTS
#
# `--issue N` decides whether `/idd-close --retroactive` may post a second
# closing summary onto an issue. HISTORICAL, round 9-11: exit 0 was the
# authorisation and everything else
# must refuse.
#
# When the gate shipped, its only coverage went through `--json-file`, which
# skips the acquisition code entirely. The live branch — repo resolution,
# `gh issue view`, the paginated REST comment fetch — had NONE. A post-merge
# ensemble then found, from four independent lenses, that a FAILED comment
# fetch produced `class=missing, comments_complete=true, rc=0`: full
# authorisation to post a duplicate onto an issue that already had a summary.
# The suite was 51/51 green throughout, because the fixture path exercises a
# different branch than the one that runs in production.
#
# So: every case here stubs `gh` on PATH and goes through the live branch. A
# fixture can never satisfy these.
#
# PROBE DISCIPLINE (learned the hard way in the same round): the stub is
# written with a QUOTED heredoc and takes its mode from an env var. The first
# hand-written version of this probe used an unquoted heredoc, `\n` inside the
# JSON bodies collapsed to real newlines, jq rejected the payload, and a case
# returned the RIGHT exit code for entirely the WRONG reason. `success` is a
# control: it must come back rc=1, which is only possible if the stub's JSON
# actually parses.
set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$(cd "$HERE/../.." && pwd)/check-closed-without-summary.sh"
. "$(cd "$HERE/../../lib" && pwd)/assert-helpers.sh"

STUB=$(mktemp -d)
cat > "$STUB/gh" <<'STUBEOF'
#!/usr/bin/env bash
# $GATE_STUB selects the scenario. Anything unset behaves as a clean success.
case "$1" in
  issue)
    case "${GATE_STUB:-success}" in
      issue-view-fails) echo "gh: HTTP 502" >&2; exit 1 ;;
      open-issue) printf '%s\n' '{"number":42,"title":"still open","state":"OPEN"}' ;;
      *) printf '%s\n' '{"number":42,"title":"newest comment is a real closing summary","state":"CLOSED"}' ;;
    esac ;;
  api)
    case "${GATE_STUB:-success}" in
      total-failure)      echo "gh: HTTP 403: API rate limit exceeded" >&2; exit 1 ;;
      partial-pagination) printf '%s\n' '[{"body":"## Diagnosis"}]'; echo "gh: HTTP 502 on page 2" >&2; exit 1 ;;
      not-an-array)       printf '%s\n' '{"message":"Not Found"}' ;;
      genuinely-empty)    printf '%s\n' '[]' ;;
      *)                  printf '%s\n' '[{"body":"## Diagnosis"}]'
                          printf '%s\n' '[{"body":"## Closing Summary"},{"body":"real content"}]' ;;
    esac ;;
  repo)
    case "${GATE_STUB:-success}" in
      no-repo) exit 1 ;;
      *) printf '%s\n' 'o/r' ;;
    esac ;;
esac
STUBEOF
chmod +x "$STUB/gh"

# $1=name $2=GATE_STUB $3=expected-rc $4...=extra args (default: --issue 42 --repo o/r)
#
# The verdict JSON goes into $GATE_OUT, NOT stdout. That is not a style choice:
# if this function printed the JSON, every caller would have to capture it with
# $(...) — and command substitution runs in a SUBSHELL, so the assert_eq below
# would increment PASS/FAIL in a child process and the counts would vanish.
# The first version of this file did exactly that and silently lost four
# assertions. Same class as the bugs this suite exists to catch: a probe that
# looks like it ran.
GATE_OUT=$(mktemp); trap 'rm -rf "$STUB"; rm -f "$GATE_OUT"' EXIT
gate_case() {
  local name="$1" mode="$2" want="$3"; shift 3
  local args=("$@"); [ ${#args[@]} -eq 0 ] && args=(--issue 42 --repo o/r)
  GATE_STUB="$mode" PATH="$STUB:$PATH" bash "$SCRIPT" "${args[@]}" >"$GATE_OUT" 2>/dev/null
  assert_eq "$name" "$want" "$?"
}

echo "── live gate: the veto-clear direction ──"
# CONTROL. Proves the stub emits parseable JSON; without it every other row
# below could be passing because jq choked, not because the guard worked.
gate_case "control: a real summary in the newest comment REFUSES (rc=1)" success 1
# The one path that clears the veto over the LIVE fetch: it SUCCEEDED and there
# really are no comments. rc=10, and 10 is not permission -- idd-close still has
# to read the comment set (there is none here) and get a human to say yes.
gate_case "a genuinely empty comment set clears the veto (rc=10, not 0)" genuinely-empty 10
assert_grep "...and reports class=unrecognised, not missing" \
  '"class": "unrecognised"' "$(cat "$GATE_OUT")"
assert_grep "...and says on the wire that it authorises nothing" \
  '"authorises": false' "$(cat "$GATE_OUT")"

echo "── live gate: every failure must refuse ──"
# THE #320 CRITICAL. `gh api ... | jq -s 'add // []'` — without pipefail the
# `if !` reads JQ's status, and jq exits 0 on empty stdin printing `[]`. A 403
# therefore looked exactly like "this issue has no comments".
gate_case "a failed comment fetch refuses (rc=2), NOT rc=0" total-failure 2
TOTAL=$(cat "$GATE_OUT")
refute_grep "a failed fetch never claims class=missing" '"class": "missing"' "$TOTAL"
refute_grep "a failed fetch never claims the comment set is complete" '"comments_complete": true' "$TOTAL"

# Worse than total failure and not exotic: --paginate streams OLDEST first, so
# a mid-pagination failure keeps the old comments and loses the newest — which
# is by construction where a closing summary is.
gate_case "a partially-paginated fetch refuses (rc=2)" partial-pagination 2
refute_grep "a partial fetch never claims class=missing" '"class": "missing"' "$(cat "$GATE_OUT")"

gate_case "an unreachable issue-view refuses (rc=2)"     issue-view-fails 2
gate_case "a non-array comments response refuses (rc=2)" not-an-array     2
gate_case "an OPEN issue refuses (rc=2)"                 open-issue       2
# HERMETIC. Repo resolution walks UP from $PWD and then consults $HOME's global
# layer, so running this case from inside a configured repo resolves a repo and
# the assertion silently tests something else. It passed when run standalone and
# failed inside the suite runner for exactly that reason — a cwd-dependent test
# is a test that reports on its own working directory.
EMPTY_CWD=$(mktemp -d); EMPTY_HOME=$(mktemp -d)
( cd "$EMPTY_CWD" && HOME="$EMPTY_HOME" GATE_STUB=no-repo PATH="$STUB:$PATH" \
    bash "$SCRIPT" --issue 42 >"$GATE_OUT" 2>/dev/null )
assert_eq "an unresolvable repo refuses (rc=2)" "2" "$?"
rm -rf "$EMPTY_CWD" "$EMPTY_HOME"

echo "── live gate: the flag itself ──"
# An empty value made `[ -n "$GATE_ISSUE" ]` false, so the whole gate block was
# skipped and the run fell through to AUDIT mode — whose contract is to always
# exit 0. A caller writing `--issue "$NUMBER"` with NUMBER unset read that 0 as
# "go ahead and post". The validator's `''` arm was dead code.
gate_case "an EMPTY --issue value refuses (rc=2), does not fall through to audit mode" \
  success 2 --issue "" --repo o/r
gate_case "a bare trailing --issue refuses (rc=2)" success 2 --repo o/r --issue
gate_case "a non-numeric --issue refuses (rc=2)"   success 2 --issue abc --repo o/r

# Whatever happens, gate mode emits ONE JSON object — a caller that has to tell
# JSON from a sentence will eventually get it wrong.
for m in success genuinely-empty total-failure partial-pagination not-an-array open-issue; do
  require "gate: $m emits one parseable JSON object" \
    bash -c 'GATE_STUB="$2" PATH="$3:$PATH" bash "$0" --issue 42 --repo o/r 2>/dev/null | jq -e "type == \"object\"" >/dev/null' \
    "$SCRIPT" "" "$m" "$STUB"
done

# And the advisory contract must survive untouched: audit mode still exits 0.
AUDIT_RC=$(GATE_STUB=total-failure PATH="$STUB:$PATH" bash "$SCRIPT" --repo o/r >/dev/null 2>&1; echo $?)
assert_eq "audit mode still always exits 0, even when gh fails" "0" "$AUDIT_RC"

print_summary "gate-live-path"
exit $?
