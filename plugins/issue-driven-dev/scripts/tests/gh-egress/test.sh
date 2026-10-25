#!/usr/bin/env bash
# test.sh — fixture tests for gh-egress.sh, the privacy-scrubbing choke-point
# wrapper (PsychQuant/issue-driven-development#202).
#
# Covers the two DETERMINISTIC halves of the gate (design D2) — the semantic
# breadth is the LLM self-review's job and is NOT tested here:
#   (a) attestation enforcement  — refuse when the self-review attestation is
#       absent/invalid; dispatch when present.
#   (b) mechanical last-resort net — catch the 2 zero-tolerance literal items
#       (absolute /Users/<name> home path, verbatim ~/.claude.json content),
#       and — critically — do NOT over-match legitimate or semantic-only content
#       (that would prove the wrapper is doing semantic matching, which it must
#       not; D1/D2).
#
# Self-contained: a stub `gh` (via IDD_GH_BIN) captures dispatched argv so the
# passthrough can be asserted without any live GitHub / network call. The
# ~/.claude.json probe is redirected to a fixture via IDD_CLAUDE_JSON so the
# real user config is never read.
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../gh-egress.sh"

. "$HERE/../../lib/assert-helpers.sh"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# --- stub gh: record argv (last call NUL-delimited + every call one line), save
# the stdin payload of `--input -` calls, answer the two lookups the REST
# transport makes (milestones, user), print a fake issue URL otherwise -------
STUB="$WORK/fake-gh"
cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
: > "$FAKE_GH_ARGV"
for a in "$@"; do printf '%s\0' "$a" >> "$FAKE_GH_ARGV"; done
printf '%s\n' "$*" >> "$FAKE_GH_CALLS"
n="$(wc -l < "$FAKE_GH_CALLS" | tr -d ' ')"
for a in "$@"; do [ "$a" = "--input" ] && { cat > "$FAKE_GH_STDIN.$n"; break; }; done
case "${2:-}" in
  */milestones*) echo '[{"title":"Sprint 1","number":4},{"title":"Sprint 10","number":5}]'; exit 0 ;;
  user)          echo '{"login":"me-login"}'; exit 0 ;;
esac
case " $* " in *" --silent "*) exit 0 ;; esac
echo "https://github.com/o/r/issues/123"
STUBEOF
chmod +x "$STUB"
export IDD_GH_BIN="$STUB"
export FAKE_GH_ARGV="$WORK/argv" FAKE_GH_CALLS="$WORK/calls" FAKE_GH_STDIN="$WORK/stdin"
: > "$FAKE_GH_CALLS"
calls_reset() { : > "$FAKE_GH_CALLS"; rm -f "$FAKE_GH_STDIN".*; }
call_n() { sed -n "${1}p" "$FAKE_GH_CALLS"; }          # the n-th gh call of the last dispatch, space-joined
ncalls() { wc -l < "$FAKE_GH_CALLS" | tr -d ' '; }
payload() { python3 -c 'import json,sys; print(json.dumps(json.load(open(sys.argv[1])), sort_keys=True))' "$FAKE_GH_STDIN.$1" 2>/dev/null; }

# --- fixture ~/.claude.json (redirect the probe away from the real one) -------
# One project key under /Users/ (also caught by the home-path net) and one under
# a non-/Users absolute path so the .claude.json content-overlap net can be
# proven to fire INDEPENDENTLY of the home-path net.
export IDD_CLAUDE_JSON="$WORK/fixture-claude.json"
printf '%s' '{"projects":{"/Users/fixtureuser/secret-lab":{"x":1},"/opt/priv/hidden-proj-xyz":{"y":2}},"mcpServers":{"tool":{"command":"/opt/homebrew/bin/uvx-tool","env":{"KEY_FILE":"/srv/secret-vault/che-key-abc"}}}}' \
  > "$IDD_CLAUDE_JSON"

ATT=(--scrub-attested warn)

# ── §2.1 attestation enforcement ────────────────────────────────────────────
bash "$SCRIPT" create --repo o/r --title T --body "fix parser in src/main.rs" >/dev/null 2>&1
assert_exit "attestation absent → refuse dispatch (exit 13)" 13 $?

OUT="$(bash "$SCRIPT" create --repo o/r --title T --body "fix parser in src/main.rs" "${ATT[@]}" 2>/dev/null)"
RC=$?
assert_exit "attestation present + clean → dispatch (exit 0)" 0 "$RC"
assert_grep "dispatch stdout is gh output, byte-preserved" "issues/123" "$OUT"

bash "$SCRIPT" create --repo o/r --title T --body "clean" --scrub-attested bogus >/dev/null 2>&1
assert_exit "invalid attestation level → refuse (exit 13)" 13 $?

# attestation flag is consumed by the wrapper, never forwarded to gh
calls_reset
bash "$SCRIPT" comment 5 --repo o/r --body "hello world" "${ATT[@]}" >/dev/null 2>&1
ARGV="$(tr '\0' '\n' < "$FAKE_GH_ARGV")"
refute_grep "wrapper strips --scrub-attested from gh argv" "--scrub-attested" "$ARGV"
assert_grep  "comment targets the issue's comments endpoint" "repos/o/r/issues/5/comments" "$ARGV"
assert_eq    "comment body rides stdin as JSON"  '{"body": "hello world"}' "$(payload 1)"
refute_grep  "body never appears in gh argv (#416: stdin only)" "hello world" "$ARGV"

# ── §2.2 mechanical last-resort net ─────────────────────────────────────────
# literal /Users/<name> caught even WITH a valid attestation (LLM missed it)
bash "$SCRIPT" create --repo o/r --title T \
  --body "the script at /Users/alice/proj/run.sh keeps failing" "${ATT[@]}" >/dev/null 2>&1
assert_exit "literal /Users/alice home path caught (exit 10)" 10 $?

# home path can also hide in the title
bash "$SCRIPT" create --repo o/r --title "crash in /Users/bob/tool" \
  --body "clean body" "${ATT[@]}" >/dev/null 2>&1
assert_exit "literal home path in --title caught (exit 10)" 10 $?

# bare ~/.claude.json filename mention is PUBLIC info (#203 item 1) — the private
# thing is its CONTENT (covered by the projects-key net below). Must dispatch.
bash "$SCRIPT" comment 5 --repo o/r \
  --body "the value comes from ~/.claude.json under projects" "${ATT[@]}" >/dev/null 2>&1
assert_exit "bare .claude.json filename mention NOT caught (#203 item 1) → dispatch (exit 0)" 0 $?

# verbatim CONTENT copied from ~/.claude.json (non-/Users project key) caught —
# proves the content-overlap net fires independently of the home-path net
bash "$SCRIPT" comment 5 --repo o/r \
  --body "reindex blew up on /opt/priv/hidden-proj-xyz this morning" "${ATT[@]}" >/dev/null 2>&1
assert_exit "verbatim .claude.json project-key content caught (exit 10)" 10 $?

# ── NOT over-matching (the wrapper must not do semantic matching) ────────────
# /Users/<name> PLACEHOLDER (angle-bracketed) is documentation, not a real path
OUT="$(bash "$SCRIPT" create --repo o/r --title T \
  --body "the home dir is /Users/<name>/foo by convention" "${ATT[@]}" 2>/dev/null)"
assert_exit "placeholder /Users/<name> NOT caught → dispatch (exit 0)" 0 $?

# ordinary legitimate technical prose passes untouched
bash "$SCRIPT" create --repo o/r --title T \
  --body "Fix the null check in parser.ts around line 42" "${ATT[@]}" >/dev/null 2>&1
assert_exit "legitimate body NOT caught → dispatch (exit 0)" 0 $?

# a semantic-only private identifier (unpublished codename) is the LLM's job,
# NOT the wrapper's — must pass the mechanical net
bash "$SCRIPT" create --repo o/r --title T \
  --body "Project Nightingale rollout slipped to Q3" "${ATT[@]}" >/dev/null 2>&1
assert_exit "semantic-only private id NOT caught by wrapper (exit 0)" 0 $?

# a metadata-only edit (no --body/--title) needs attestation but has nothing to
# scan — must dispatch cleanly (milestone title resolved to its number)
calls_reset
bash "$SCRIPT" edit 5 --repo o/r --milestone "Sprint 1" "${ATT[@]}" >/dev/null 2>&1
assert_exit "metadata-only edit dispatches with attestation (exit 0)" 0 $?
assert_eq "milestone title → number in the PATCH payload (exact title, not 'Sprint 10')" '{"milestone": 4}' "$(payload "$(ncalls)")"

# ── §7 REST transport (#416, change cloud-session-idd-all D2) ────────────────
# Porcelain `gh issue …` is GraphQL, which Claude Code cloud sessions block, so
# the wrapper dispatches through `gh api` REST in every environment. The
# contract that callers rely on is stdout = one URL line (URL=$(… create …)).
calls_reset
OUT="$(bash "$SCRIPT" create --repo o/r --title "T" --body "clean body" --label bug "${ATT[@]}" 2>/dev/null)"
EXPECT=$'api\nrepos/o/r/issues\n-X\nPOST\n--input\n-\n--jq\n.html_url'
GOT="$(tr '\0' '\n' < "$FAKE_GH_ARGV")"
assert_eq "create argv is the REST POST (attestation stripped)" "$EXPECT" "$GOT"
assert_eq "create payload carries title, body, labels" '{"body": "clean body", "labels": ["bug"], "title": "T"}' "$(payload 1)"
assert_eq "stdout is exactly the URL line gh printed" "https://github.com/o/r/issues/123" "$OUT"
assert_eq "one gh call for a plain create" "1" "$(ncalls)"

calls_reset
bash "$SCRIPT" create --repo o/r --title T --body x --label bug,ui --label x -a @me --milestone "Sprint 1" "${ATT[@]}" >/dev/null 2>&1
assert_eq "create resolves milestone + @me, comma-splits labels" \
  '{"assignees": ["me-login"], "body": "x", "labels": ["bug", "ui", "x"], "milestone": 4, "title": "T"}' "$(payload "$(ncalls)")"
assert_grep "the last call is the POST" "api repos/o/r/issues -X POST" "$(call_n "$(ncalls)")"

calls_reset
bash "$SCRIPT" comment https://github.com/o/r/issues/5 --body "done" "${ATT[@]}" >/dev/null 2>&1
assert_eq "comment on an issue URL → that repo's comments endpoint" "api repos/o/r/issues/5/comments -X POST --input - --jq .html_url" "$(call_n 1)"

calls_reset
bash "$SCRIPT" edit 7 --repo o/r --add-label triage --remove-label "needs review" --body "new body text here" "${ATT[@]}" >/dev/null 2>&1
assert_eq "edit call 1: add labels"          "api repos/o/r/issues/7/labels -X POST --input - --silent" "$(call_n 1)"
assert_eq "edit call 1 payload"              '{"labels": ["triage"]}' "$(payload 1)"
assert_eq "edit call 2: remove label (url-encoded)" "api repos/o/r/issues/7/labels/needs%20review -X DELETE --silent" "$(call_n 2)"
assert_eq "edit call 3: PATCH body last"     "api repos/o/r/issues/7 -X PATCH --input - --jq .html_url" "$(call_n 3)"
assert_eq "edit PATCH payload"               '{"body": "new body text here"}' "$(payload 3)"

calls_reset
bash "$SCRIPT" edit 7 --repo o/r --remove-milestone --add-assignee @me "${ATT[@]}" >/dev/null 2>&1
assert_eq "remove-assignee/add-assignee resolve @me" '{"assignees": ["me-login"]}' "$(payload 2)"
assert_eq "--remove-milestone → milestone null" '{"milestone": null}' "$(payload 3)"

calls_reset
bash "$SCRIPT" create --repo ghe.example.com/o/r --title T --body x "${ATT[@]}" >/dev/null 2>&1
assert_eq "HOST/OWNER/REPO → --hostname on the call" "api repos/o/r/issues -X POST --input - --jq .html_url --hostname ghe.example.com" "$(call_n 1)"

calls_reset
printf 'a body from a file, kept out of argv' > "$WORK/fbody.md"
bash "$SCRIPT" comment 5 --repo o/r --body-file "$WORK/fbody.md" "${ATT[@]}" >/dev/null 2>&1
assert_eq "body-file content rides stdin" '{"body": "a body from a file, kept out of argv"}' "$(payload 1)"

# translator refusals: exit 14, named cause, no gh call at all
calls_reset
bash "$SCRIPT" create --repo o/r --title T --body x --project Roadmap "${ATT[@]}" >/dev/null 2>"$WORK/err"
assert_exit "unsupported flag refused, not dropped (exit 14)" 14 $?
assert_grep "refusal names the flag" "--project" "$(cat "$WORK/err")"
assert_eq "no gh call for an unsupported flag" "0" "$(ncalls)"
bash "$SCRIPT" create --repo o/r --body "no title here" "${ATT[@]}" >/dev/null 2>&1
assert_exit "create without --title refused (exit 14)" 14 $?
bash "$SCRIPT" create --repo o/r --title T --body x stray "${ATT[@]}" >/dev/null 2>&1
assert_exit "create with a stray positional refused (exit 14)" 14 $?
bash "$SCRIPT" comment --repo o/r --body "no issue given" "${ATT[@]}" >/dev/null 2>&1
assert_exit "comment without an issue refused (exit 14)" 14 $?
calls_reset
bash "$SCRIPT" edit 5 --repo o/r --milestone "Nope" "${ATT[@]}" >/dev/null 2>"$WORK/err"
assert_exit "unknown milestone refused (exit 14)" 14 $?
refute_grep "no PATCH after a failed milestone lookup" "PATCH" "$(cat "$FAKE_GH_CALLS")"

# an earlier edit call failing stops the sequence and passes gh's code through
FAILLABEL="$WORK/fail-label-gh"
cat > "$FAILLABEL" <<'STUBEOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$FAKE_GH_CALLS"
case "$2" in */labels*) echo "gh: Validation Failed (HTTP 422)" >&2; exit 3 ;; esac
cat >/dev/null; echo "https://github.com/o/r/issues/7"
STUBEOF
chmod +x "$FAILLABEL"
calls_reset
IDD_GH_BIN="$FAILLABEL" bash "$SCRIPT" edit 7 --repo o/r --add-label x --body "body long enough here" "${ATT[@]}" >/dev/null 2>&1
assert_exit "failing label call → its exit code (3) passes through" 3 $?
refute_grep "the PATCH is not sent after a failed earlier call" "PATCH" "$(cat "$FAKE_GH_CALLS")"

# ── verb / usage validation ─────────────────────────────────────────────────
bash "$SCRIPT" delete 5 "${ATT[@]}" >/dev/null 2>&1
assert_exit "unknown verb → usage error (exit 14)" 14 $?
bash "$SCRIPT" >/dev/null 2>&1
assert_exit "missing verb → usage error (exit 14)" 14 $?


# ── #203 mechanical-net precision + edge-case hardening ─────────────────────
# item 2: public tool path from mcpServers must NOT be treated as a leak
# (content net scoped to the projects object when jq is available)
bash "$SCRIPT" comment 5 --repo o/r \
  --body "run it via /opt/homebrew/bin/uvx-tool instead" "${ATT[@]}" >/dev/null 2>&1
assert_exit "public mcpServers tool path NOT caught (#203 item 2 / #225 unified) → dispatch (exit 0)" 0 $?
# item 2 regression: projects key still caught (both jq and fallback paths)
bash "$SCRIPT" comment 5 --repo o/r \
  --body "reindex blew up on /opt/priv/hidden-proj-xyz again" "${ATT[@]}" >/dev/null 2>&1
assert_exit "projects key still caught after item-2 scoping (exit 10)" 10 $?

# item 3: non-regular body-file (stdin dash / FIFO / process-sub) → refuse exit 5
bash "$SCRIPT" create --repo o/r --title T --body-file - "${ATT[@]}" >/dev/null 2>&1
assert_exit "body-file '-' (stdin) refused — unscannable (#203 item 3, exit 12)" 12 $?
# No writer process needed: the gate refuses on the not-a-regular-file check
# WITHOUT opening the FIFO (a background writer would block forever on open()
# and hold the test's stdout pipe hostage).
FIFO="$WORK/fifo"; mkfifo "$FIFO"
bash "$SCRIPT" create --repo o/r --title T --body-file "$FIFO" "${ATT[@]}" >/dev/null 2>&1
assert_exit "body-file FIFO refused — unscannable (#203 item 3, exit 12)" 12 $?
# regular body-file still scanned + dispatched
printf 'a clean body from file' > "$WORK/body.txt"
bash "$SCRIPT" create --repo o/r --title T --body-file "$WORK/body.txt" "${ATT[@]}" >/dev/null 2>&1
assert_exit "regular body-file still dispatches (exit 0)" 0 $?
# regular body-file with a leak is still caught (scan path intact)
printf 'log at /Users/carol/x.log' > "$WORK/leak.txt"
bash "$SCRIPT" create --repo o/r --title T --body-file "$WORK/leak.txt" "${ATT[@]}" >/dev/null 2>&1
assert_exit "regular body-file leak still caught (exit 10)" 10 $?

# item 4: HOME + IDD_CLAUDE_JSON both unset → no set -u crash, clean body dispatches
env -u HOME -u IDD_CLAUDE_JSON IDD_GH_BIN="$STUB" FAKE_GH_ARGV="$FAKE_GH_ARGV" \
  bash "$SCRIPT" create --repo o/r --title T --body "clean prose" "${ATT[@]}" >/dev/null 2>&1
assert_exit "HOME+IDD_CLAUDE_JSON unset → no crash, dispatch (#203 item 4, exit 0)" 0 $?

# item 5: minimal forwarded args → no phantom '' positional reaches the
# transport (a phantom would be refused as a stray positional, exit 14) and the
# REST argv is exactly 8 NUL-terminated fields. Field count via NUL bytes —
# command substitution strips trailing newlines so a string compare is blind
# to the phantom. No --repo → gh's {owner}/{repo} placeholder (#416).
bash "$SCRIPT" create --title T "${ATT[@]}" >/dev/null 2>&1
assert_exit "minimal create dispatches (no phantom positional, #203 item 5)" 0 $?
NFIELDS="$(tr -cd '\0' < "$FAKE_GH_ARGV" | wc -c | tr -d ' ')"
assert_eq "minimal create argv has exactly 8 fields (#203 item 5)" "8" "$NFIELDS"
assert_grep "no --repo → {owner}/{repo} placeholder" "repos/{owner}/{repo}/issues" "$(tr '\0' '\n' < "$FAKE_GH_ARGV")"

# item 6: --scrub-attested where a --body value is expected → malformed, usage refuse
bash "$SCRIPT" create --repo o/r --body --scrub-attested warn >/dev/null 2>&1
assert_exit "split-token attestation refused (#203 item 6, exit 14)" 14 $?


# ── #117 unattested @-mention net ────────────────────────────────────────────
# raw @login token without attestation → refuse (GitHub notification is irreversible)
bash "$SCRIPT" comment 5 --repo o/r \
  --body "ping @nonexistentuser123 for a second look" "${ATT[@]}" >/dev/null 2>&1
assert_exit "raw unattested @-mention refused (#117, exit 11)" 11 $?

# backtick-escaped token is inert on GitHub → dispatch
bash "$SCRIPT" comment 5 --repo o/r \
  --body "the reviewer codename \`@codex\` wrote this" "${ATT[@]}" >/dev/null 2>&1
assert_exit "backtick-escaped @token NOT caught (#117) → dispatch (exit 0)" 0 $?

# fenced code block containing @token is inert → dispatch
BODY_FENCED=$'usage example:\n```\ncc @somebody\n```\ndone'
bash "$SCRIPT" comment 5 --repo o/r --body "$BODY_FENCED" "${ATT[@]}" >/dev/null 2>&1
assert_exit "fenced @token NOT caught (#117) → dispatch (exit 0)" 0 $?

# email-like user@host must not trip the net (char before @ is alnum)
bash "$SCRIPT" comment 5 --repo o/r \
  --body "reach me at demo@example.com about this" "${ATT[@]}" >/dev/null 2>&1
assert_exit "email-like token NOT caught (#117) → dispatch (exit 0)" 0 $?

# attested mention dispatches AND the flag is stripped from forwarded argv
bash "$SCRIPT" comment 5 --repo o/r \
  --body "cc @kiki830621 please review" "${ATT[@]}" --mention-attested kiki830621 >/dev/null 2>&1
assert_exit "attested @-mention dispatches (#117, exit 0)" 0 $?
ARGV="$(tr '\0' '\n' < "$FAKE_GH_ARGV")"
refute_grep "wrapper strips --mention-attested from gh argv (#117)" "--mention-attested" "$ARGV"

# attestation must cover EVERY token — partial coverage still refuses
bash "$SCRIPT" comment 5 --repo o/r \
  --body "cc @kiki830621 and also @stranger99" "${ATT[@]}" --mention-attested kiki830621 >/dev/null 2>&1
assert_exit "partially-attested mentions refused (#117, exit 11)" 11 $?

# split-token guard extends to --mention-attested
bash "$SCRIPT" create --repo o/r --body --mention-attested kiki830621 "${ATT[@]}" >/dev/null 2>&1
assert_exit "split-token --mention-attested refused (#117, exit 14)" 14 $?


# ── cluster verify in-scope fixes (R1 findings) ──────────────────────────────
# fix 1 (sec 203-2 / logic LOW): jq PRESENT but ~/.claude.json malformed →
# content net must fail CLOSED to the grep fallback, not silently disable
export IDD_CLAUDE_JSON="$WORK/malformed-claude.json"
printf '%s' '{"projects":{"/opt/priv/hidden-mal-xyz":{"x":1},}' > "$IDD_CLAUDE_JSON"   # trailing comma = invalid JSON
bash "$SCRIPT" comment 5 --repo o/r \
  --body "crash traced to /opt/priv/hidden-mal-xyz build" "${ATT[@]}" >/dev/null 2>&1
assert_exit "malformed claude.json → parse-failure falls CLOSED to wide net (fix1/#225, exit 10)" 10 $?
export IDD_CLAUDE_JSON="$WORK/fixture-claude.json"

# fix 2 (sec 117-1): entity-encoded @ forms refused (decode-side notification risk)
bash "$SCRIPT" comment 5 --repo o/r \
  --body "ping &#64;realuser about this" "${ATT[@]}" >/dev/null 2>&1
assert_exit "entity-encoded &#64;login refused (fix2, exit 11)" 11 $?
bash "$SCRIPT" comment 5 --repo o/r \
  --body "or &#x40;realuser even" "${ATT[@]}" >/dev/null 2>&1
assert_exit "entity-encoded &#x40;login refused (fix2, exit 11)" 11 $?

# fix 3 (logic 117-1): attached short-form values are scanned like their spaced forms
bash "$SCRIPT" create --repo o/r --title T "-blog at /Users/alice/secret.sh" "${ATT[@]}" >/dev/null 2>&1
assert_exit "attached -b<body> home-path leak caught (fix3, exit 10)" 10 $?
bash "$SCRIPT" create --repo o/r --title T "-bcc @sneakymention" "${ATT[@]}" >/dev/null 2>&1
assert_exit "attached -b<body> raw mention caught (fix3, exit 11)" 11 $?
printf 'leak at /Users/dave/y.log' > "$WORK/att.txt"
bash "$SCRIPT" create --repo o/r --title T "-F$WORK/att.txt" "${ATT[@]}" >/dev/null 2>&1
assert_exit "attached -F<file> content scanned (fix3, exit 10)" 10 $?

# fix 4 (logic 117-2): mention net is BODY-only — title @tokens neither notify nor can be escaped
bash "$SCRIPT" create --repo o/r --title "responsive @media breakpoints" \
  --body "clean prose" "${ATT[@]}" >/dev/null 2>&1
assert_exit "title @token NOT fed to mention net (fix4) → dispatch (exit 0)" 0 $?
# privacy nets still scan titles (regression guard)
bash "$SCRIPT" create --repo o/r --title "crash in /Users/eve/tool" \
  --body "clean" "${ATT[@]}" >/dev/null 2>&1
assert_exit "title home-path still caught by privacy net (exit 10)" 10 $?

# fix 5 (logic 117-3): 4-space-indented ``` is GFM literal code, NOT a fence —
# must not toggle fence state and swallow a later real mention
BODY_IND=$'see:\n    ```\ncc @realafteripseudofence' 
bash "$SCRIPT" comment 5 --repo o/r --body "$BODY_IND" "${ATT[@]}" >/dev/null 2>&1
assert_exit "indented pseudo-fence does not hide later mention (fix5, exit 11)" 11 $?


# ── R2 fixes (DA-r2 findings on 4d2e87b) ─────────────────────────────────────
# DA-117-B: @handle inside a URL never notifies on GitHub — must NOT refuse,
# and backtick-escaping would break the link
bash "$SCRIPT" comment 5 --repo o/r \
  --body "docs at https://unpkg.com/@angular/core and https://mastodon.social/@dev profile" "${ATT[@]}" >/dev/null 2>&1
assert_exit "@handle inside URLs NOT caught (DA-117-B) → dispatch (exit 0)" 0 $?
# markdown link target with /@handle also exempt
bash "$SCRIPT" comment 5 --repo o/r \
  --body "see [pkg docs](https://cdn.jsdelivr.net/npm/@scope/pkg) for details" "${ATT[@]}" >/dev/null 2>&1
assert_exit "markdown link target @handle NOT caught (DA-117-B) → dispatch (exit 0)" 0 $?
# regression guard: raw mention NEXT TO a URL still caught
bash "$SCRIPT" comment 5 --repo o/r \
  --body "see https://example.com/docs and ping @realperson about it" "${ATT[@]}" >/dev/null 2>&1
assert_exit "raw mention adjacent to URL still caught (exit 11)" 11 $?


# ── R3 fixes (R2-round findings) ─────────────────────────────────────────────
# 117-A: URL-strip must only exempt autolink-eligible hosts (dot required);
# no-dot/malformed hosts render as literal text where /@name IS a live mention
bash "$SCRIPT" comment 5 --repo o/r --body "see https://@realuser now" "${ATT[@]}" >/dev/null 2>&1
assert_exit "no-host URL @mention still caught (117-A, exit 11)" 11 $?
bash "$SCRIPT" comment 5 --repo o/r --body "at http://localhost/@realuser today" "${ATT[@]}" >/dev/null 2>&1
assert_exit "no-dot-host URL @mention still caught (117-A, exit 11)" 11 $?
# regression: dotted-host URLs stay exempt
bash "$SCRIPT" comment 5 --repo o/r --body "docs https://unpkg.com/@angular/core here" "${ATT[@]}" >/dev/null 2>&1
assert_exit "dotted-host URL @handle stays exempt (exit 0)" 0 $?

# 117-B: fully-encoded username (&#64;&#114;ealuser) must also refuse
bash "$SCRIPT" comment 5 --repo o/r --body "try &#64;&#114;ealuser form" "${ATT[@]}" >/dev/null 2>&1
assert_exit "double-encoded entity mention refused (117-B, exit 11)" 11 $?

# 117-C: template expansion under zsh — the =-form must reach the wrapper as
# ONE recognizable arg and dispatch a vetted mention (end-to-end)
if command -v zsh >/dev/null 2>&1; then
  MA_OUT="$WORK/zsh-ma-argv"
  zsh -c '
    MENTION_ATTESTED="kiki830621"
    exec bash "$1" comment 5 --repo o/r --body "cc @kiki830621 ok" --scrub-attested warn ${MENTION_ATTESTED:+--mention-attested="$MENTION_ATTESTED"}
  ' zsh "$SCRIPT" >/dev/null 2>&1
  assert_exit "zsh template =-form expansion dispatches vetted mention (117-C, exit 0)" 0 $?
fi

# 203-C: attached short-form must reset pending next_is (parser hygiene) —
# `--body -bX Y` : -bX consumes as attached body, Y must NOT be eaten as body
bash "$SCRIPT" create --repo o/r --body "-binline body" --title T "${ATT[@]}" >/dev/null 2>&1
assert_exit "attached form after pending --body keeps parser state sane (exit 0)" 0 $?


# ── #227 exit-code band: wrapper-origin ≥10; gh native codes pass through <10 ──
# stub gh exiting 4 (e.g. auth failure) must surface as 4 — NOT be confused with
# a gate refusal (which now lives at ≥10). This is the caller-disambiguation
# contract: rc<10 ⇒ gh's own; rc≥10 ⇒ wrapper refusal.
FAILGH="$WORK/fail-gh"
printf '#!/usr/bin/env bash\nexit 4\n' > "$FAILGH"; chmod +x "$FAILGH"
IDD_GH_BIN="$FAILGH" bash "$SCRIPT" comment 5 --repo o/r --body "clean prose" "${ATT[@]}" >/dev/null 2>&1
assert_exit "gh native exit 4 passes through UNCHANGED (#227 band disambiguation)" 4 $?


# ── #225 unified scan (python3) — non-projects sensitive paths, same everywhere ─
# The motivating divergence: a secret-file path under mcpServers[].env dispatched
# on jq machines (projects-only scope) but refused on no-jq machines (wide net).
# The unified python3 parser scans projects keys ∪ path-shaped values under
# sensitive key names — SAME result on every machine.
bash "$SCRIPT" comment 5 --repo o/r \
  --body "loader reads /srv/secret-vault/che-key-abc at boot" "${ATT[@]}" >/dev/null 2>&1
assert_exit "mcpServers env secret path caught (#225 unified taxonomy, exit 10)" 10 $?
# non-sensitive prose sharing no config path still dispatches (no over-match)
bash "$SCRIPT" comment 5 --repo o/r \
  --body "we store vault material under /srv/other-vault/keyring generally" "${ATT[@]}" >/dev/null 2>&1
assert_exit "similar-but-absent path NOT caught (#225 no fuzzy matching) → dispatch (exit 0)" 0 $?

# ── #272 reply layer-3 tier floor — marker-token backstop (net item 4) ────────
# Body carrying BOTH IDD-own marker tokens (`type=reply` + `points-from=user-pasted`)
# at attested level `light` → refuse in the ATTESTATION band (13, not content 10):
# the attested level is invalid for this payload; re-dispatch at warn after the
# explicit user confirmation. Token matching on IDD's own metadata marker only —
# NOT semantic content matching (net boundary discipline preserved).
REPLY_L3_BODY='## 🧑‍🏫 Reply
> 「third-party pasted words」
done. <!-- idd:comment type=reply date=2026-07-19 points-from=user-pasted calibrated=no -->'
bash "$SCRIPT" comment 5 --repo o/r --body "$REPLY_L3_BODY" --scrub-attested light >/dev/null 2>&1
assert_exit "reply user-pasted marker at light → tier-floor refuse (#272, exit 13)" 13 $?
# same body at warn (user confirmed) → dispatches normally
bash "$SCRIPT" comment 5 --repo o/r --body "$REPLY_L3_BODY" --scrub-attested warn >/dev/null 2>&1
assert_exit "reply user-pasted marker at warn → dispatch (#272 floor satisfied, exit 0)" 0 $?
# reply WITHOUT user-pasted (layer 1/2) at light → unaffected (floor binds layer 3 only)
REPLY_L2_BODY='## 🧑‍🏫 Reply
> 「quoted from issue body」
done. <!-- idd:comment type=reply date=2026-07-19 points-from=issue-body calibrated=yes -->'
bash "$SCRIPT" comment 5 --repo o/r --body "$REPLY_L2_BODY" --scrub-attested light >/dev/null 2>&1
assert_exit "reply issue-body marker at light → dispatch (#272 layer-1/2 unaffected, exit 0)" 0 $?
# conjunction pin: user-pasted token ALONE (no type=reply) at light → dispatch
# (kills the single-token mis-implementation that would pass the other fixtures)
bash "$SCRIPT" comment 5 --repo o/r --body "note: source resolution recorded points-from=user-pasted here" --scrub-attested light >/dev/null 2>&1
assert_exit "user-pasted token without type=reply at light → dispatch (#272 conjunction pinned, exit 0)" 0 $?
# refusal stderr carries the remediation instruction (re-dispatch at warn)
ERR="$(bash "$SCRIPT" comment 5 --repo o/r --body "$REPLY_L3_BODY" --scrub-attested light 2>&1 >/dev/null)"
printf '%s' "$ERR" | grep -Fq -- '--scrub-attested warn'
assert_exit "tier-floor stderr instructs re-dispatch at warn (#272)" 0 $?
# accepted-friction LOCK: a body merely DISCUSSING both tokens (in a code fence)
# at light IS refused — raw-substring semantics are deliberate (fenced content
# still reaches the remote; stripping fences would be a trivial bypass).
DISCUSS_BODY='documenting the marker vocabulary:
```
type=reply
points-from=user-pasted
```
this body quotes both tokens without being a reply.'
bash "$SCRIPT" comment 5 --repo o/r --body "$DISCUSS_BODY" --scrub-attested light >/dev/null 2>&1
assert_exit "fenced discussion of both tokens at light → refuse (#272 accepted friction locked, exit 13)" 13 $?

# template↔wrapper binding (#272 DA N-4): the SKILL template must emit the exact
# vocabulary the wrapper greps — if either side's spelling drifts, the net is
# silently disabled. Bind both ends to the shared literals.
SKILL_MD="$HERE/../../../skills/idd-comment/SKILL.md"
assert_output_grep "binding: SKILL template enumerates user-pasted"  "points-from={comment-url|issue-body|user-pasted}" "$SKILL_MD"
assert_output_grep "binding: wrapper greps the same reply token"     "grep -Fq -- 'type=reply'"                          "$SCRIPT"
assert_output_grep "binding: wrapper greps the same user-pasted token" "grep -Fq -- 'points-from=user-pasted'"           "$SCRIPT"

# ── §2.6 empty-body guard (#275) — presence check, not content check ─────────
# Upstream `"$(cat file)"` + silent composition failure dispatches an empty
# body; on `edit` (overwrite semantics) that WIPES the issue body. Wrapper-
# origin refusal code 15 (band >=10 per #227 — the issue's suggested exit 5
# would break the rc<10-is-gh invariant).

bash "$SCRIPT" edit 7 --repo o/r --body "" "${ATT[@]}" >/dev/null 2>&1
assert_exit "edit with empty body → refuse (exit 15)" 15 $?

bash "$SCRIPT" edit 7 --repo o/r --body "hi" "${ATT[@]}" >/dev/null 2>&1
assert_exit "edit with <10-char body → refuse (overwrite floor, exit 15)" 15 $?

OUT="$(bash "$SCRIPT" edit 7 --repo o/r --body "" --allow-empty-body "${ATT[@]}" 2>/dev/null)"
assert_exit "edit empty + --allow-empty-body → dispatch (exit 0)" 0 $?
ARGV="$(tr '\0' '\n' < "$FAKE_GH_ARGV")"
refute_grep "wrapper strips --allow-empty-body from gh argv" "--allow-empty-body" "$ARGV"

bash "$SCRIPT" comment 7 --repo o/r --body "   " "${ATT[@]}" >/dev/null 2>&1
assert_exit "comment with whitespace-only body → refuse (exit 15)" 15 $?

bash "$SCRIPT" comment 7 --repo o/r --body "done" "${ATT[@]}" >/dev/null 2>&1
assert_exit "comment with short-but-real body → dispatch (no floor on comment)" 0 $?

printf '' > "$WORK/empty-body.md"
bash "$SCRIPT" create --repo o/r --title T --body-file "$WORK/empty-body.md" "${ATT[@]}" >/dev/null 2>&1
assert_exit "create with empty body-file → refuse (exit 15)" 15 $?

bash "$SCRIPT" edit 7 --repo o/r --add-label bug "${ATT[@]}" >/dev/null 2>&1
assert_exit "edit with NO body channel (label-only) → guard silent, dispatch" 0 $?

assert_output_grep "header documents refusal code 15" "15  empty/near-empty body" "$SCRIPT"

# ── §2.7 edit-comment verb (#273) — comment-PATCH surgery enters the nets ────
# The #226 rollout whitelisted `gh api ... PATCH comments` as "tracked
# separately"; that debt is retired here: a dedicated verb dispatches the
# PATCH so every net (privacy / mention / attestation / tier-floor / #275
# empty-body) applies to comment surgery too.

printf '%s' "reasonable replacement body for the comment surgery path" > "$WORK/patch-body.md"
bash "$SCRIPT" edit-comment 9 --repo o/r --body-file "$WORK/patch-body.md" "${ATT[@]}" >/dev/null 2>&1
assert_exit "edit-comment happy path → dispatch (exit 0)" 0 $?
ARGV="$(tr '\0' '\n' < "$FAKE_GH_ARGV")"
assert_grep "edit-comment dispatch is gh api"              "api"                          "$ARGV"
assert_grep "edit-comment targets the comment endpoint"    "repos/o/r/issues/comments/9" "$ARGV"
assert_grep "edit-comment method is PATCH"                 "PATCH"                        "$ARGV"
assert_grep "edit-comment body rides -F body=@file"        "body=@$WORK/patch-body.md"    "$ARGV"

printf '%s' "leak /Users/fixtureuser/secret-lab inside surgery body padded long" > "$WORK/leaky-body.md"
bash "$SCRIPT" edit-comment 9 --repo o/r --body-file "$WORK/leaky-body.md" "${ATT[@]}" >/dev/null 2>&1
assert_exit "edit-comment privacy net applies (exit 10)" 10 $?

bash "$SCRIPT" edit-comment 9 --repo o/r --body-file "$WORK/empty-body.md" "${ATT[@]}" >/dev/null 2>&1
assert_exit "edit-comment empty body → overwrite floor (exit 15)" 15 $?

bash "$SCRIPT" edit-comment 9 --repo o/r --body-file "$WORK/patch-body.md" >/dev/null 2>&1
assert_exit "edit-comment without attestation → refuse (exit 13)" 13 $?

bash "$SCRIPT" edit-comment 9 --repo o/r "${ATT[@]}" >/dev/null 2>&1
assert_exit "edit-comment without --body-file → usage (exit 14)" 14 $?

print_summary "gh-egress"
