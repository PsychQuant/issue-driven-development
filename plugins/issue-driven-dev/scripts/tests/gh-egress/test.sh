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

# --- stub gh: record NUL-delimited argv, print a fake issue URL, exit 0 -------
STUB="$WORK/fake-gh"
cat > "$STUB" <<'STUBEOF'
#!/usr/bin/env bash
: > "$FAKE_GH_ARGV"
for a in "$@"; do printf '%s\0' "$a" >> "$FAKE_GH_ARGV"; done
echo "https://github.com/o/r/issues/123"
STUBEOF
chmod +x "$STUB"
export IDD_GH_BIN="$STUB"
export FAKE_GH_ARGV="$WORK/argv"

# --- fixture ~/.claude.json (redirect the probe away from the real one) -------
# One project key under /Users/ (also caught by the home-path net) and one under
# a non-/Users absolute path so the .claude.json content-overlap net can be
# proven to fire INDEPENDENTLY of the home-path net.
export IDD_CLAUDE_JSON="$WORK/fixture-claude.json"
printf '%s' '{"projects":{"/Users/fixtureuser/secret-lab":{"x":1},"/opt/priv/hidden-proj-xyz":{"y":2}},"mcpServers":{"tool":{"command":"/opt/homebrew/bin/uvx-tool"}}}' \
  > "$IDD_CLAUDE_JSON"

ATT=(--scrub-attested warn)

# ── §2.1 attestation enforcement ────────────────────────────────────────────
bash "$SCRIPT" create --repo o/r --title T --body "fix parser in src/main.rs" >/dev/null 2>&1
assert_exit "attestation absent → refuse dispatch (exit 3)" 3 $?

OUT="$(bash "$SCRIPT" create --repo o/r --title T --body "fix parser in src/main.rs" "${ATT[@]}" 2>/dev/null)"
RC=$?
assert_exit "attestation present + clean → dispatch (exit 0)" 0 "$RC"
assert_grep "dispatch stdout is gh output, byte-preserved" "issues/123" "$OUT"

bash "$SCRIPT" create --repo o/r --title T --body "clean" --scrub-attested bogus >/dev/null 2>&1
assert_exit "invalid attestation level → refuse (exit 3)" 3 $?

# attestation flag is consumed by the wrapper, never forwarded to gh
bash "$SCRIPT" comment 5 --repo o/r --body "hello world" "${ATT[@]}" >/dev/null 2>&1
ARGV="$(tr '\0' '\n' < "$FAKE_GH_ARGV")"
refute_grep "wrapper strips --scrub-attested from gh argv" "--scrub-attested" "$ARGV"
assert_grep  "gh argv keeps the verb"            "comment" "$ARGV"
assert_grep  "gh argv keeps the issue number"    "5"       "$ARGV"
assert_grep  "gh argv keeps the body value"      "hello world" "$ARGV"

# ── §2.2 mechanical last-resort net ─────────────────────────────────────────
# literal /Users/<name> caught even WITH a valid attestation (LLM missed it)
bash "$SCRIPT" create --repo o/r --title T \
  --body "the script at /Users/alice/proj/run.sh keeps failing" "${ATT[@]}" >/dev/null 2>&1
assert_exit "literal /Users/alice home path caught (exit 4)" 4 $?

# home path can also hide in the title
bash "$SCRIPT" create --repo o/r --title "crash in /Users/bob/tool" \
  --body "clean body" "${ATT[@]}" >/dev/null 2>&1
assert_exit "literal home path in --title caught (exit 4)" 4 $?

# bare ~/.claude.json filename mention is PUBLIC info (#203 item 1) — the private
# thing is its CONTENT (covered by the projects-key net below). Must dispatch.
bash "$SCRIPT" comment 5 --repo o/r \
  --body "the value comes from ~/.claude.json under projects" "${ATT[@]}" >/dev/null 2>&1
assert_exit "bare .claude.json filename mention NOT caught (#203 item 1) → dispatch (exit 0)" 0 $?

# verbatim CONTENT copied from ~/.claude.json (non-/Users project key) caught —
# proves the content-overlap net fires independently of the home-path net
bash "$SCRIPT" comment 5 --repo o/r \
  --body "reindex blew up on /opt/priv/hidden-proj-xyz this morning" "${ATT[@]}" >/dev/null 2>&1
assert_exit "verbatim .claude.json project-key content caught (exit 4)" 4 $?

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
# scan — must dispatch cleanly (byte-preserved milestone assignment path)
bash "$SCRIPT" edit 5 --repo o/r --milestone "Sprint 1" "${ATT[@]}" >/dev/null 2>&1
assert_exit "metadata-only edit dispatches with attestation (exit 0)" 0 $?

# ── §7 backward-compat: transparent pass-through (byte-preserved forwarding) ──
# With attestation present and no mechanical hit, the argv reaching gh MUST be
# EXACTLY `issue <verb> <original args>` — the attestation flag removed, nothing
# else added/reordered. This is what keeps existing idd-issue capture sites
# (URL=$(gh issue create ...)), the JSONL audit and the footer byte-identical.
bash "$SCRIPT" create --repo o/r --title "T" --body "clean body" --label bug "${ATT[@]}" >/dev/null 2>&1
EXPECT=$'issue\ncreate\n--repo\no/r\n--title\nT\n--body\nclean body\n--label\nbug'
GOT="$(tr '\0' '\n' < "$FAKE_GH_ARGV")"
assert_eq "pass-through argv is byte-identical to raw gh (attestation stripped, order kept)" "$EXPECT" "$GOT"

# ── verb / usage validation ─────────────────────────────────────────────────
bash "$SCRIPT" delete 5 "${ATT[@]}" >/dev/null 2>&1
assert_exit "unknown verb → usage error (exit 2)" 2 $?
bash "$SCRIPT" >/dev/null 2>&1
assert_exit "missing verb → usage error (exit 2)" 2 $?


# ── #203 mechanical-net precision + edge-case hardening ─────────────────────
# item 2: public tool path from mcpServers must NOT be treated as a leak
# (content net scoped to the projects object when jq is available)
if command -v jq >/dev/null 2>&1; then
  bash "$SCRIPT" comment 5 --repo o/r \
    --body "run it via /opt/homebrew/bin/uvx-tool instead" "${ATT[@]}" >/dev/null 2>&1
  assert_exit "public mcpServers tool path NOT caught (#203 item 2, jq path) → dispatch (exit 0)" 0 $?
fi
# item 2 regression: projects key still caught (both jq and fallback paths)
bash "$SCRIPT" comment 5 --repo o/r \
  --body "reindex blew up on /opt/priv/hidden-proj-xyz again" "${ATT[@]}" >/dev/null 2>&1
assert_exit "projects key still caught after item-2 scoping (exit 4)" 4 $?

# item 3: non-regular body-file (stdin dash / FIFO / process-sub) → refuse exit 5
bash "$SCRIPT" create --repo o/r --title T --body-file - "${ATT[@]}" >/dev/null 2>&1
assert_exit "body-file '-' (stdin) refused — unscannable (#203 item 3, exit 5)" 5 $?
# No writer process needed: the gate refuses on the not-a-regular-file check
# WITHOUT opening the FIFO (a background writer would block forever on open()
# and hold the test's stdout pipe hostage).
FIFO="$WORK/fifo"; mkfifo "$FIFO"
bash "$SCRIPT" create --repo o/r --title T --body-file "$FIFO" "${ATT[@]}" >/dev/null 2>&1
assert_exit "body-file FIFO refused — unscannable (#203 item 3, exit 5)" 5 $?
# regular body-file still scanned + dispatched
printf 'a clean body from file' > "$WORK/body.txt"
bash "$SCRIPT" create --repo o/r --title T --body-file "$WORK/body.txt" "${ATT[@]}" >/dev/null 2>&1
assert_exit "regular body-file still dispatches (exit 0)" 0 $?
# regular body-file with a leak is still caught (scan path intact)
printf 'log at /Users/carol/x.log' > "$WORK/leak.txt"
bash "$SCRIPT" create --repo o/r --title T --body-file "$WORK/leak.txt" "${ATT[@]}" >/dev/null 2>&1
assert_exit "regular body-file leak still caught (exit 4)" 4 $?

# item 4: HOME + IDD_CLAUDE_JSON both unset → no set -u crash, clean body dispatches
env -u HOME -u IDD_CLAUDE_JSON IDD_GH_BIN="$STUB" FAKE_GH_ARGV="$FAKE_GH_ARGV" \
  bash "$SCRIPT" create --repo o/r --title T --body "clean prose" "${ATT[@]}" >/dev/null 2>&1
assert_exit "HOME+IDD_CLAUDE_JSON unset → no crash, dispatch (#203 item 4, exit 0)" 0 $?

# item 5: zero forwarded args → argv is exactly 2 NUL-terminated fields
# (issue, create) with NO phantom '' third field. Field count via NUL bytes —
# command substitution strips trailing newlines so a string compare is blind
# to the phantom.
bash "$SCRIPT" create "${ATT[@]}" >/dev/null 2>&1
NFIELDS="$(tr -cd '\0' < "$FAKE_GH_ARGV" | wc -c | tr -d ' ')"
assert_eq "zero-arg dispatch has no phantom empty positional (#203 item 5, argv fields)" "2" "$NFIELDS"

# item 6: --scrub-attested where a --body value is expected → malformed, usage refuse
bash "$SCRIPT" create --repo o/r --body --scrub-attested warn >/dev/null 2>&1
assert_exit "split-token attestation refused (#203 item 6, exit 2)" 2 $?


# ── #117 unattested @-mention net ────────────────────────────────────────────
# raw @login token without attestation → refuse (GitHub notification is irreversible)
bash "$SCRIPT" comment 5 --repo o/r \
  --body "ping @nonexistentuser123 for a second look" "${ATT[@]}" >/dev/null 2>&1
assert_exit "raw unattested @-mention refused (#117, exit 4)" 4 $?

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
assert_exit "partially-attested mentions refused (#117, exit 4)" 4 $?

# split-token guard extends to --mention-attested
bash "$SCRIPT" create --repo o/r --body --mention-attested kiki830621 "${ATT[@]}" >/dev/null 2>&1
assert_exit "split-token --mention-attested refused (#117, exit 2)" 2 $?


# ── cluster verify in-scope fixes (R1 findings) ──────────────────────────────
# fix 1 (sec 203-2 / logic LOW): jq PRESENT but ~/.claude.json malformed →
# content net must fail CLOSED to the grep fallback, not silently disable
if command -v jq >/dev/null 2>&1; then
  export IDD_CLAUDE_JSON="$WORK/malformed-claude.json"
  printf '%s' '{"projects":{"/opt/priv/hidden-mal-xyz":{"x":1},}' > "$IDD_CLAUDE_JSON"   # trailing comma = invalid JSON
  bash "$SCRIPT" comment 5 --repo o/r \
    --body "crash traced to /opt/priv/hidden-mal-xyz build" "${ATT[@]}" >/dev/null 2>&1
  assert_exit "malformed claude.json + jq present → fallback net still catches (fix1, exit 4)" 4 $?
  export IDD_CLAUDE_JSON="$WORK/fixture-claude.json"
fi

# fix 2 (sec 117-1): entity-encoded @ forms refused (decode-side notification risk)
bash "$SCRIPT" comment 5 --repo o/r \
  --body "ping &#64;realuser about this" "${ATT[@]}" >/dev/null 2>&1
assert_exit "entity-encoded &#64;login refused (fix2, exit 4)" 4 $?
bash "$SCRIPT" comment 5 --repo o/r \
  --body "or &#x40;realuser even" "${ATT[@]}" >/dev/null 2>&1
assert_exit "entity-encoded &#x40;login refused (fix2, exit 4)" 4 $?

# fix 3 (logic 117-1): attached short-form values are scanned like their spaced forms
bash "$SCRIPT" create --repo o/r --title T "-blog at /Users/alice/secret.sh" "${ATT[@]}" >/dev/null 2>&1
assert_exit "attached -b<body> home-path leak caught (fix3, exit 4)" 4 $?
bash "$SCRIPT" create --repo o/r --title T "-bcc @sneakymention" "${ATT[@]}" >/dev/null 2>&1
assert_exit "attached -b<body> raw mention caught (fix3, exit 4)" 4 $?
printf 'leak at /Users/dave/y.log' > "$WORK/att.txt"
bash "$SCRIPT" create --repo o/r --title T "-F$WORK/att.txt" "${ATT[@]}" >/dev/null 2>&1
assert_exit "attached -F<file> content scanned (fix3, exit 4)" 4 $?

# fix 4 (logic 117-2): mention net is BODY-only — title @tokens neither notify nor can be escaped
bash "$SCRIPT" create --repo o/r --title "responsive @media breakpoints" \
  --body "clean prose" "${ATT[@]}" >/dev/null 2>&1
assert_exit "title @token NOT fed to mention net (fix4) → dispatch (exit 0)" 0 $?
# privacy nets still scan titles (regression guard)
bash "$SCRIPT" create --repo o/r --title "crash in /Users/eve/tool" \
  --body "clean" "${ATT[@]}" >/dev/null 2>&1
assert_exit "title home-path still caught by privacy net (exit 4)" 4 $?

# fix 5 (logic 117-3): 4-space-indented ``` is GFM literal code, NOT a fence —
# must not toggle fence state and swallow a later real mention
BODY_IND=$'see:\n    ```\ncc @realafteripseudofence' 
bash "$SCRIPT" comment 5 --repo o/r --body "$BODY_IND" "${ATT[@]}" >/dev/null 2>&1
assert_exit "indented pseudo-fence does not hide later mention (fix5, exit 4)" 4 $?


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
assert_exit "raw mention adjacent to URL still caught (exit 4)" 4 $?


# ── R3 fixes (R2-round findings) ─────────────────────────────────────────────
# 117-A: URL-strip must only exempt autolink-eligible hosts (dot required);
# no-dot/malformed hosts render as literal text where /@name IS a live mention
bash "$SCRIPT" comment 5 --repo o/r --body "see https://@realuser now" "${ATT[@]}" >/dev/null 2>&1
assert_exit "no-host URL @mention still caught (117-A, exit 4)" 4 $?
bash "$SCRIPT" comment 5 --repo o/r --body "at http://localhost/@realuser today" "${ATT[@]}" >/dev/null 2>&1
assert_exit "no-dot-host URL @mention still caught (117-A, exit 4)" 4 $?
# regression: dotted-host URLs stay exempt
bash "$SCRIPT" comment 5 --repo o/r --body "docs https://unpkg.com/@angular/core here" "${ATT[@]}" >/dev/null 2>&1
assert_exit "dotted-host URL @handle stays exempt (exit 0)" 0 $?

# 117-B: fully-encoded username (&#64;&#114;ealuser) must also refuse
bash "$SCRIPT" comment 5 --repo o/r --body "try &#64;&#114;ealuser form" "${ATT[@]}" >/dev/null 2>&1
assert_exit "double-encoded entity mention refused (117-B, exit 4)" 4 $?

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

print_summary "gh-egress"
