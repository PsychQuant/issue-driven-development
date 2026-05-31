#!/usr/bin/env bash
# Guard: PR-body templates must not emit a GitHub auto-close trap (#173).
#
# GitHub's auto-close parser (the authoritative `closingIssuesReferences` that
# idd-verify Step 0.8 Source 1 reads) hyphen-splits tokens, so a PR body line
# rendering to `... close #170 ...` — including from `/idd-close #${NUMBER}` or
# `/idd-close $REFS_LIST` — links the PR to auto-close that issue on merge,
# bypassing /idd-close's checklist gate + closing summary. (#173)
#
# This guard scans the PR-body-generating template lines for a close/fix/resolve
# keyword immediately followed by a rendered issue reference:
#   - `#${VAR}`        (literal '#' + brace-var, e.g. `#${NUMBER}`)
#   - `#<digit>`       (hardcoded number)
#   - `$ALLCAPS_VAR`   (e.g. `$REFS_LIST`, which expands to `#34 #36 ...`)
#
# Scope = PR-body checklist lines, identified by the `Verify-gated` label or the
# `REVIEW_CHECKLIST_LINE` assignment. Console "next steps" hints (which SHOULD
# show the literal `/idd-close #34 #36` command to the user) are NOT PR bodies
# and are intentionally out of scope.
#
# Usage: bash test.sh   (exit 0 = no trap, 1 = trap found)

set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
P="$(cd "$HERE/../../.." && pwd)"   # plugin dir (tests/<name>/ → tests → scripts → plugin)
ROOT="$(cd "$P/../.." && pwd)"       # repo root (plugin → plugins → repo)

FILES=(
  "$P/skills/idd-implement/SKILL.md"
  "$P/skills/idd-all/SKILL.md"
  "$P/skills/idd-all-chain/SKILL.md"
  "$P/references/pr-flow.md"
  "$P/references/chain-flow.md"   # chain cluster PR-body schema doc (#173 verify)
)

# PR-body template line markers.
SCOPE='Verify-gated|REVIEW_CHECKLIST_LINE'
# Trap: a close keyword + optional colon + whitespace + an issue-ref form.
#
# The inter-token pattern `[[:space:]]*:?[[:space:]]+` MIRRORS the runtime Step 0.8
# Source 2 detector — so this static guard is NOT weaker than the detector it
# backstops. GitHub auto-closes the COLON form too (`Closes: #N`), which an
# earlier `[[:space:]]+`-only regex missed (#173 verify: DA-1 + Codex HIGH).
# Issue-ref forms covered: `#$VAR` / `#${VAR}` (→ `#\$`), `#<digit>`,
# and an ALLCAPS var that expands to refs `$REFS_LIST` / `${REFS_LIST}`
# (→ `\$\{?[A-Z_]`).
TRAP='(close[sd]?|fix(e[sd])?|resolve[sd]?)[[:space:]]*:?[[:space:]]+(#\$|#[0-9]|\$\{?[A-Z_])'

hits=0
missing=0
for f in "${FILES[@]}"; do
  if [ ! -f "$f" ]; then
    # Fail CLOSED: a stale FILES entry means the guard is no longer checking what
    # it claims — a renamed / moved template would slip through GREEN. (#173 Codex)
    echo "  ✗ expected template file missing (stale FILES list?): ${f#"$ROOT"/}"
    missing=$((missing + 1))
    continue
  fi
  while IFS= read -r line; do
    [ -z "$line" ] && continue
    hits=$((hits + 1))
    printf '  ✗ %s: %s\n' "${f#"$ROOT"/}" "$line"
  done < <(grep -hE "$SCOPE" "$f" 2>/dev/null | grep -iE "$TRAP")
done

if [ "$hits" -gt 0 ] || [ "$missing" -gt 0 ]; then
  echo ""
  if [ "$missing" -gt 0 ]; then
    echo "FAIL: $missing expected template file(s) missing — guard cannot verify them."
    echo "      Update the FILES list (a template was renamed / moved / deleted)."
  fi
  if [ "$hits" -gt 0 ]; then
    echo "FAIL: $hits PR-body template line(s) contain an auto-close trap"
    echo "      (a close/fix/resolve keyword — incl. colon form 'Closes: #N' —"
    echo "       immediately before an issue reference)."
    echo "      Rephrase so no such keyword is adjacent to #<issue> / \$REFS — e.g."
    echo "      'after merge, run /idd-close to finalize this issue'."
  fi
  exit 1
fi

echo "PASS: no auto-close trap in PR-body templates."
exit 0
