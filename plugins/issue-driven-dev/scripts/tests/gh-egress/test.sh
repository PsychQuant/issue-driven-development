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
FIFO="$WORK/fifo"; mkfifo "$FIFO"
( printf 'x' > "$FIFO" & ) 2>/dev/null
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

print_summary "gh-egress"
