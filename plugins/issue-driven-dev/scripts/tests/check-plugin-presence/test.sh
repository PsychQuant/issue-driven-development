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

run() { # home [args...] — runs script with fake HOME, captures stderr to $ERR
  local home="$1"; shift
  ERR=$(HOME="$home" IDD_SKIP_PLUGIN_CHECK= bash "$SCRIPT" "$@" 2>&1 >/dev/null)
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

print_summary "check-plugin-presence"
