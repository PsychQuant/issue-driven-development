#!/usr/bin/env bash
# resolve-submodule-route.sh — submodule boundary detection for IDD config
# resolution (#162; config-protocol.md "Mechanism 3.5").
#
# Problem shape: cwd inside a git submodule → walk-up finds the PARENT repo's
# config → its github_repo silently targets the parent, not the submodule.
#
# Contract:
#   resolve_submodule_route <submodules_key_value>
#     $1  the config's `submodules` value ("auto" when key absent)
#   stdout: "owner/repo" of the SUBMODULE's origin when the boundary should
#           override the parent config's github_repo; EMPTY otherwise
#   stderr: a surface line whenever cwd IS inside a submodule (both routings) —
#           the silent-wrong-repo failure is the bug class being closed, so
#           the boundary is never crossed silently.
#   exit:   always 0 (advisory resolver; caller falls through on empty stdout)
#
# Priority (per #162 diagnosis): explicit candidates (mechanism 3) already won
# before this runs; this only overrides the bare parent `github_repo` default.
resolve_submodule_route() {
  local mode="${1:-auto}"
  local super sub_url sub_repo
  super="$(git rev-parse --show-superproject-working-tree 2>/dev/null || true)"
  [ -z "$super" ] && return 0   # not inside a submodule — silent no-op

  if [ "$mode" = "off" ]; then
    echo "→ submodule detected (superproject: $super) — 'submodules: off' set; routing stays with the parent config's github_repo" >&2
    return 0
  fi

  sub_url="$(git remote get-url origin 2>/dev/null || true)"
  if [ -z "$sub_url" ]; then
    echo "⚠ submodule detected but it has no 'origin' remote — falling back to the parent config's github_repo" >&2
    return 0
  fi
  sub_repo="$(printf '%s' "$sub_url" | sed -E 's#(\.git)?$##; s#.*[:/]([^/]+/[^/]+)$#\1#')"
  if ! printf '%s' "$sub_repo" | grep -qE '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$'; then
    echo "⚠ submodule origin URL did not yield owner/repo shape ('$sub_repo') — falling back to parent config" >&2
    return 0
  fi
  echo "→ submodule detected: routing to $sub_repo (submodule origin). Parent config would target its own github_repo; set \"submodules\": \"off\" to keep parent routing." >&2
  printf '%s\n' "$sub_repo"
}
