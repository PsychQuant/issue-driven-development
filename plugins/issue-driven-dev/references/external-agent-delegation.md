# External Agent Delegation Reference

Single source of truth for **IDD ⇄ external agent** workflow — diagnose stays in IDD, implement may be delegated (Codex / openclaw-task / remote claw / Copilot Workspace), verify returns to IDD's 6-AI ensemble, close enforces IDD discipline regardless of who implemented.

Companion to [pr-flow.md](pr-flow.md) (PR vs direct-commit) and [batch-and-cluster.md](batch-and-cluster.md) (multi-issue invocation). This file covers the **agent boundary** dimension that the other two don't touch.

---

## When this applies

You're in scope for this contract when **any** of these hold:

- `idd-implement` was skipped — Claude diagnosed, then a different agent (Codex, Copilot, remote claw) wrote the code
- A PR was opened by a non-Claude author (`gh pr view --json author`)
- The change set lives on a branch Claude didn't create (`git log --author` shows different author)
- You're verifying work that landed via `gh pr checkout` from a fork

If Claude both diagnosed AND implemented in the same session, this contract is **inert** — the existing local-diff workflow applies.

---

## Four-phase delegation impact matrix

| Phase | Owner | Failure modes when delegated |
|-------|-------|------------------------------|
| **diagnose** | Always Claude (IDD) | None — diagnosis is high-leverage human-judgment work; never delegate |
| **implement** | External agent | Commit format drift (`Closes #N` trailer bypasses gate); no RED test (TDD discipline lost); attachment-blind (didn't read source-of-truth PDF/docx); scope creep (incidental refactor) |
| **verify** | Always Claude (IDD) | Diff source unreachable (work isn't in local tree); cross-post target ambiguous (PR? issue? both?); fix responsibility unclear (bounce back vs takeover) |
| **close** | Always Claude (IDD) | Closing summary empty (`git log --grep "#N"` finds nothing if external agent didn't tag); checklist gate fails (TDD bullet unticked because no RED test exists); authorship mis-attributed |

`verify` and `close` need protocol changes. `diagnose` and `implement` get a **soft contract** (a comment template Claude posts) but no enforcement — external agent compliance is opt-in by design (see "Hands-off principle" below).

---

## Hands-off principle

IDD does **not** babysit external agents. Reasons:

1. **Selection pressure** — if Claude auto-fixes external agent's commit format / missing RED tests, the external agent never improves
2. **Trust boundary** — if Claude rewrites external agent's commits, authorship becomes ambiguous and `git blame` lies
3. **Scope** — building a `idd-handoff` skill that pre-creates RED tests + branch for external agent ≈ building half of `idd-implement` twice

Instead: **strict verify, opt-in fix takeover**. External agent submits whatever they submit; verify finds drift; user decides whether to bounce back (default) or take over (`--takeover` escape hatch, deferred to v2).

---

## Verify input source modes (v2.37.0+)

`idd-verify` supports three explicit input sources plus auto-detect.

### Mode table

```bash
# Local commits — Case A: external agent commits to current working tree
idd-verify #98                          # auto: count Refs #98 commits since origin/<default>; fall back HEAD~1
idd-verify #98 --commits 3              # explicit: HEAD~3..HEAD
idd-verify #98 --since <ref>            # explicit: <ref>..HEAD

# PR — Case B: external agent opens PR (most common for delegated work)
idd-verify --pr 123                     # auto-discover issues from PR body Refs #N
idd-verify #98 --pr 123                 # explicit: assert #98 ∈ PR's Refs set
idd-verify #98 #105 --pr 123            # explicit cluster: assert {#98, #105} ⊆ PR's Refs set

# Branch — Case C: external agent commits to branch but no PR yet
idd-verify #98 --branch <name>          # diff against origin/<default>
```

### Resolution algorithm

```
1. --pr <N> set?           → PR mode (gh pr diff <N>)
2. --branch <name> set?    → branch mode (git diff origin/<default>...<name>)
3. --commits <N> set?      → local mode with explicit N (HEAD~N..HEAD)
4. --since <ref> set?      → local mode with ref (<ref>..HEAD)
5. None of the above       → auto-detect:
   a. Count commits ref'ing #N since origin/<default>
       N>0  → local mode HEAD~N..HEAD
       N=0  → continue
   b. Search open PRs ref'ing #N: gh pr list --search "#N in:body" --state open
       1 PR found  → AskUserQuestion "Verify PR #X or local diff?"
       2+ PRs      → AskUserQuestion list all
       0 PRs       → fall back HEAD~1 (preserves v2.36 behavior)
```

Auto-detect's job: catch the common forgotten-flag case ("I cloned this repo, Codex committed 3 things, I forgot `--commits 3`"). It does not silently switch modes — it always asks via `AskUserQuestion` when ambiguous.

---

## Issue ↔ PR correspondence (the iron rule)

> **Every PR verified by IDD must reference at least one issue. No exceptions.**

When `--pr <N>` is set, `idd-verify` runs this gate **before** invoking the 6-AI ensemble:

```bash
PR_BODY=$(gh pr view "$PR" --repo "$GITHUB_REPO" --json body -q .body)
DISCOVERED=$(echo "$PR_BODY" | grep -oE '#[0-9]+' | sort -u)
```

| User input | Discovered set | Behavior |
|------------|----------------|----------|
| `idd-verify --pr 123` (no issues) | non-empty | Use discovered set as cluster |
| `idd-verify --pr 123` (no issues) | **empty** | **Abort** with "PR #123 has no `Refs #N` — violates IDD discipline. Add `Refs #N` to PR body and retry." |
| `idd-verify #98 --pr 123` | contains #98 | Proceed with single-issue scope |
| `idd-verify #98 --pr 123` | does not contain #98 | **Abort** with "PR #123 does not ref #98 — correspondence broken. Add `Refs #98` to PR body or pick a different PR." |
| `idd-verify #98 #105 --pr 123` | superset of {#98, #105} | Proceed with cluster scope |
| `idd-verify #98 --pr 123` | contains {#98, #105} (PR refs more than user listed) | **AskUserQuestion**: "PR also refs #105 — verify that too, or scope to #98 only?" |

Why hard abort on empty discovery set: a PR without any issue ref is an untrackable change. IDD's audit value evaporates if the PR-issue link doesn't exist.

---

## Cross-post: PR is master, issues get pointers

When verify runs in PR mode, the **full report** (findings table, source attribution, scope check, action recommendations) is posted to **the PR**, and **each ref'd issue** gets a 1-line pointer comment back.

### Why PR is master

| Audience | Reads | Sees |
|----------|-------|------|
| External agent owner | PR (their workspace) | Full verify report — actionable |
| Issue subscribers | Issue (their notification source) | Pointer + PASS/FAIL — knows where to find detail |
| `idd-close` | Issue + PR | Both have audit trail; PR is canonical |

If verify report were posted only to issues, external agent owners working in PR view would never see findings. If posted only to PR, issue audit trail is broken.

### Master comment template (PR)

For cluster-scope verify, partition findings per-issue inside one master comment (mirrors `batch-and-cluster.md` cluster-PR mode):

```markdown
## Verify Report — PR #123

### Engine
Agent Team (5 Claude reviewers) + Codex (gpt-5.5)

### Aggregate
**FAIL** — 2 blocking findings, 1 follow-up. (Or **PASS** — no blocking findings.)

### Scope coverage
PR refs: #98, #105
Verified scope: #98, #105

---

### #98 — {issue 98 title}

**Requirements coverage**: 4/5 addressed (1 PARTIAL)

| # | Severity | Finding | Source | Action |
|---|----------|---------|--------|--------|
| 1 | P1 | ... | team:logic+codex | Blocking |
| 2 | P3 | ... | team:security | Follow-up |

---

### #105 — {issue 105 title}

**Requirements coverage**: 3/3 addressed

| # | Severity | Finding | Source | Action |
|---|----------|---------|--------|--------|
| 3 | P1 | ... | team:regression | Blocking |
```

### Pointer comment template (per issue)

```markdown
## Verify (via PR #123)
**Result**: FAIL — 2 blocking findings
**Full report**: https://github.com/owner/repo/pull/123#issuecomment-NNNNNNN

This issue's findings: see "#98" section in the linked report.
```

### Posting order (mandatory)

1. Post master comment to PR; capture the returned URL (`gh pr comment` output's last line)
2. For each ref'd issue: post pointer using the captured URL via templated body

The order matters because the pointer must contain the master URL. This pattern is already documented as SOP in `idd-verify` SKILL.md Step 4 — external delegation just changes the master location from issue→PR.

```bash
# Pseudocode mirroring the existing helper pattern
MASTER_URL=$(gh pr comment "$PR" --repo "$REPO" --body-file /tmp/master.md 2>&1 | tail -1)
for I in $REFD_ISSUES; do
  sed "s|__MASTER_URL__|$MASTER_URL|g" /tmp/pointer_template.md > /tmp/pointer.md
  gh issue comment "$I" --repo "$REPO" --body-file /tmp/pointer.md &
done
wait
```

---

## Working tree handling for PR mode

When `--pr <N>` is set, reviewer agents need actual file access for `Read` and `Grep` (the diff alone isn't enough — they need surrounding context).

```bash
# Save current branch for restore
ORIGINAL_BRANCH=$(git rev-parse --abbrev-ref HEAD)

# Checkout PR head
gh pr checkout "$PR" --repo "$GITHUB_REPO"

# Run 6-AI verify (reviewers see PR's tree state)
# ... existing verify execution ...

# Restore original branch
git checkout "$ORIGINAL_BRANCH"
```

Pre-conditions before checkout:
- Working tree clean (`git status --porcelain` empty) — abort otherwise
- No untracked files that would conflict with PR head — abort otherwise

If PR head is force-pushed mid-verify, the diff snapshot is stale. v1 doesn't detect this; user re-runs verify if they suspect drift. v2 may add `gh pr view --json headRefOid` snapshot + post-verify re-check.

---

## What's NOT in v1

Deferred to future versions; flagged here so they don't get reinvented:

| Feature | Reason for deferral |
|---------|---------------------|
| `--takeover` flag (Claude fixes blocking findings on PR head and pushes back) | Push permission unclear (forks have none); branch protection conflicts; bigger design |
| `idd-handoff #N --to <agent>` skill (Claude pre-creates RED test + Agent Contract comment) | Hands-off principle — opt-in compliance preferred |
| Auto-detect external authorship and switch verify mode | Authorship ≠ delegation (humans push commits to their own branches all the time); explicit flag is clearer |
| Force-push detection during verify | Race condition; rare in practice; user re-runs |
| Verify findings → fix attribution (who fixes what) | Out of scope; user-driven |

---

## Cross-references

- [pr-flow.md](pr-flow.md) — PR vs direct-commit. External delegation **always** uses PR path (the external agent can't push to your default branch).
- [batch-and-cluster.md](batch-and-cluster.md) — cluster-PR mode. PR-master cross-post here mirrors cluster verify's per-issue partitioning.
- [config-protocol.md](config-protocol.md) — target repo resolution applies; `--pr` does not affect target repo (PR's repo = target repo).
- `skills/idd-verify/SKILL.md` — execution steps that consume this contract.

## Versioning

- v2.37.0 introduces the three input modes (`--pr`, `--commits`, `--branch`), auto-detect, issue↔PR correspondence gate, and PR-as-master cross-post rules.
- `idd-implement` and `idd-close` external-delegation behavior is unchanged in v2.37.0 — they still assume Claude's local workflow. Future versions may add explicit support if real workflow patterns demand it.
