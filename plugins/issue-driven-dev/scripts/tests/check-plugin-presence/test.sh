#!/usr/bin/env bash
# test.sh — fixture tests for check-plugin-presence.sh, incl. skill-level
# pre-flight extension (PsychQuant/issue-driven-development#209, spec
# superpowers-integration "Dual pre-flight at delegation sites").
#
# Each test builds a fake plugin cache under a throwaway $HOME and asserts
# exit codes + stderr contract. Self-contained — no live network.
#
# Usage: bash test.sh   (exit 0 = all pass, 1 = any fail)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$HERE/../../check-plugin-presence.sh"

. "$HERE/../../lib/assert-helpers.sh"

TMPDIRS=()
cleanup() { for d in "${TMPDIRS[@]:-}"; do [ -n "${d:-}" ] && rm -rf "$d"; done; }
trap cleanup EXIT

mk_home() { local d; d="$(mktemp -d)"; TMPDIRS+=("$d"); printf '%s' "$d"; }

mk_plugin() { # home marketplace plugin version [skill...]
  local home="$1" mp="$2" pl="$3" ver="$4"; shift 4
  local base="$home/.claude/plugins/cache/$mp/$pl/$ver"
  mkdir -p "$base/.claude-plugin"
  printf '{"name":"%s"}\n' "$pl" > "$base/.claude-plugin/plugin.json"
  local s
  for s in "$@"; do
    mkdir -p "$base/skills/$s"
    printf -- '---\ndescription: t\n---\nbody\n' > "$base/skills/$s/SKILL.md"
  done
}

mk_claude_shim() { # home json — installs a fake `claude` CLI printing $json for `plugin list --json`
  local home="$1" json="$2"
  mkdir -p "$home/bin"
  cat > "$home/bin/claude" <<SHIM
#!/usr/bin/env bash
if [ "\$1" = "plugin" ] && [ "\$2" = "list" ]; then printf '%s' '$json'; exit 0; fi
exit 2
SHIM
  chmod +x "$home/bin/claude"
}

run() { # home [args...] — fake HOME + hermetic claude shim (default: empty list)
  local home="$1"; shift
  [ -x "$home/bin/claude" ] || mk_claude_shim "$home" "[]"
  ERR=$(HOME="$home" PATH="$home/bin:$PATH" IDD_SKIP_PLUGIN_CHECK= bash "$SCRIPT" "$@" 2>&1 >/dev/null)
  return $?
}

run_noclaude() { # home [args...] — PATH without any claude CLI
  local home="$1"; shift
  ERR=$(HOME="$home" PATH="/usr/bin:/bin" IDD_SKIP_PLUGIN_CHECK= bash "$SCRIPT" "$@" 2>&1 >/dev/null)
  return $?
}

# --- 2-arg backward compat --------------------------------------------------
H="$(mk_home)"; mk_plugin "$H" claude-plugins-official superpowers 4.1.0 test-driven-development
run "$H" claude-plugins-official superpowers
assert_exit "2-arg: plugin present → 0" 0 $?

H="$(mk_home)"
run "$H" claude-plugins-official superpowers
assert_exit "2-arg: plugin missing → 1" 1 $?
assert_grep "2-arg missing: stderr has install cmd" "claude plugin install superpowers@claude-plugins-official" "$ERR"

# --- 3-arg skill-level check -------------------------------------------------
H="$(mk_home)"; mk_plugin "$H" claude-plugins-official superpowers 4.1.0 test-driven-development systematic-debugging
run "$H" claude-plugins-official superpowers test-driven-development
assert_exit "3-arg: plugin+skill present → 0" 0 $?

H="$(mk_home)"; mk_plugin "$H" claude-plugins-official superpowers 4.1.0 test-driven-development
run "$H" claude-plugins-official superpowers verification-before-completion
assert_exit "3-arg: skill missing → 1" 1 $?
assert_grep "3-arg skill missing: stderr names the skill" "verification-before-completion" "$ERR"
assert_grep "3-arg skill missing: stderr has install cmd" "claude plugin install superpowers@claude-plugins-official" "$ERR"

H="$(mk_home)"
run "$H" claude-plugins-official superpowers test-driven-development
assert_exit "3-arg: plugin missing → 1" 1 $?
assert_grep "3-arg plugin missing: stderr has install cmd" "claude plugin install superpowers@claude-plugins-official" "$ERR"

# --- highest-version resolution (sort -V, pai D1 precedent) -------------------
H="$(mk_home)"
mk_plugin "$H" claude-plugins-official superpowers 4.9.0
mk_plugin "$H" claude-plugins-official superpowers 4.10.0 test-driven-development
run "$H" claude-plugins-official superpowers test-driven-development
assert_exit "version: skill only in sort -V highest (4.10.0 > 4.9.0) → 0" 0 $?

H="$(mk_home)"
mk_plugin "$H" claude-plugins-official superpowers 4.9.0 test-driven-development
mk_plugin "$H" claude-plugins-official superpowers 4.10.0
run "$H" claude-plugins-official superpowers test-driven-development
assert_exit "version: skill only in stale lower version → 1" 1 $?

# --- input hardening (audit: Scoundrel lens) ----------------------------------
H="$(mk_home)"; mk_plugin "$H" claude-plugins-official superpowers 4.1.0 test-driven-development
run "$H" claude-plugins-official superpowers "../../../etc/passwd"
assert_exit "hardening: path-traversal skill name → 2" 2 $?

run "$H" claude-plugins-official superpowers ""
assert_exit "hardening: empty skill name → 2" 2 $?

run "$H" claude-plugins-official superpowers a b
assert_exit "usage: 4 args → 2" 2 $?

# --- escape hatch consistency --------------------------------------------------
H="$(mk_home)"
ERR=$(HOME="$H" IDD_SKIP_PLUGIN_CHECK=1 bash "$SCRIPT" claude-plugins-official superpowers test-driven-development 2>&1 >/dev/null)
assert_exit "bypass: IDD_SKIP_PLUGIN_CHECK=1 covers 3-arg → 0" 0 $?


# --- R1 verify fixes (#209 verify round 1) ------------------------------------
# F3: partial version dir (no plugin.json) must NOT win highest-version resolution
H="$(mk_home)"
mk_plugin "$H" claude-plugins-official superpowers 4.9.0 test-driven-development
mkdir -p "$H/.claude/plugins/cache/claude-plugins-official/superpowers/4.10.0"   # broken leftover: no plugin.json, no skills
run "$H" claude-plugins-official superpowers test-driven-development
assert_exit "F3: broken higher version dir ignored → 0" 0 $?

# F7: multiline skill name must be rejected (whole-string match, not per-line grep)
H="$(mk_home)"; mk_plugin "$H" claude-plugins-official superpowers 4.1.0 test-driven-development
run "$H" claude-plugins-official superpowers "$(printf 'test-driven-development\n../../../etc/passwd')"
assert_exit "F7: multiline skill name → 2" 2 $?

# F9: marketplace / plugin args validated symmetrically
H="$(mk_home)"
run "$H" "../escape" superpowers
assert_exit "F9: traversal marketplace arg → 2" 2 $?
run "$H" claude-plugins-official "../escape"
assert_exit "F9: traversal plugin arg → 2" 2 $?

# F6: plugin-missing message leads with the one-step install command (no broken
# unconditional "marketplace add <owner>/..." as the first instruction)
H="$(mk_home)"
run "$H" claude-plugins-official superpowers
assert_grep "F6: one-step install line present" "Install (one step):" "$ERR"


# --- R2 verify: bare dot components rejected (R2 findings 1/3/4/6, DA PoC) ----
H="$(mk_home)"; mk_plugin "$H" claude-plugins-official superpowers 4.1.0 test-driven-development
run "$H" ".." superpowers
assert_exit "R2: bare .. marketplace → 2" 2 $?
run "$H" "." superpowers
assert_exit "R2: bare . marketplace → 2" 2 $?
run "$H" claude-plugins-official ".."
assert_exit "R2: bare .. plugin → 2" 2 $?
run "$H" claude-plugins-official "..."
assert_exit "R2: dot-only plugin (...) → 2" 2 $?


# --- #212 enabled-state detection --------------------------------------------
# enabled=true → pass
H="$(mk_home)"; mk_plugin "$H" claude-plugins-official superpowers 4.1.0
mk_claude_shim "$H" '[{"id":"superpowers@claude-plugins-official","enabled":true,"installPath":"'"$H"'/.claude/plugins/cache/claude-plugins-official/superpowers/4.1.0"}]'
run "$H" claude-plugins-official superpowers
assert_exit "#212: installed + enabled → 0" 0 $?

# enabled=false → exit 3 + enable hint
H="$(mk_home)"; mk_plugin "$H" claude-plugins-official superpowers 4.1.0
mk_claude_shim "$H" '[{"id":"superpowers@claude-plugins-official","enabled":false,"installPath":"x"}]'
run "$H" claude-plugins-official superpowers
assert_exit "#212: installed but DISABLED → 3" 3 $?
assert_grep "#212 disabled: stderr has enable cmd" "claude plugin enable superpowers@claude-plugins-official" "$ERR"

# claude CLI absent → graceful degrade (disk evidence), exit 0 + warning
H="$(mk_home)"; mk_plugin "$H" claude-plugins-official superpowers 4.1.0
run_noclaude "$H" claude-plugins-official superpowers
assert_exit "#212: claude CLI absent → degrade to disk check (0)" 0 $?
assert_grep "#212 degrade: warning surfaced" "enabled-state check skipped" "$ERR"

# list --json errors → degrade, exit 0 + warning
H="$(mk_home)"; mk_plugin "$H" claude-plugins-official superpowers 4.1.0
mkdir -p "$H/bin"; printf '#!/usr/bin/env bash\nexit 1\n' > "$H/bin/claude"; chmod +x "$H/bin/claude"
run "$H" claude-plugins-official superpowers
assert_exit "#212: plugin list --json fails → degrade (0)" 0 $?
assert_grep "#212 cli-fail: warning surfaced" "enabled-state check skipped" "$ERR"

# plugin on disk but absent from list → warn + proceed (fail-open floor)
H="$(mk_home)"; mk_plugin "$H" claude-plugins-official superpowers 4.1.0
mk_claude_shim "$H" '[]'
run "$H" claude-plugins-official superpowers
assert_exit "#212: on disk but absent from list → proceed (0)" 0 $?
assert_grep "#212 absent: inconclusive warning" "inconclusive" "$ERR"

# disabled check still respects skill-level pre-flight ordering (missing skill wins with 1)
H="$(mk_home)"; mk_plugin "$H" claude-plugins-official superpowers 4.1.0
mk_claude_shim "$H" '[{"id":"superpowers@claude-plugins-official","enabled":false}]'
run "$H" claude-plugins-official superpowers no-such-skill
assert_exit "#212: missing skill (1) precedes disabled (3)" 1 $?

print_summary "check-plugin-presence"
