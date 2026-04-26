# Changelog

## 2.27.0 — 2026-04-26

### PR vs Direct-commit path routing

`idd-implement` now explicitly resolves between two execution paths instead of implicitly following whatever branch the user happens to be on:

- **PR path** — feature branch `idd/<N>-<slug>` + push + `gh pr create`
- **Direct-commit path** — current branch, no push, no PR

Resolution priority (highest first):

1. `--pr` / `--no-pr` flag (per-invocation)
2. Fork detection (`gh repo view --json isFork` true → forced PR path)
3. `pr_policy` config field (`always` / `never` / `ask`, default `ask`)

### Changes

- **`idd-implement`** — added Phase 0.5 PR Decision step; added Phase 5.5 PR creation (idempotent — skips if PR for branch already open). New `--pr` / `--no-pr` flags. argument-hint updated.
- **`idd-close`** — added Step 1.5 PR Gate Check. Refuses close when an open PR references the issue, instructing the user to merge first. Mirrors the "no `--force`" philosophy of the checklist gate.
- **`idd-all`** — explicitly enforces `--pr` when calling `idd-implement` (orchestrator path always = PR path, overriding `pr_policy`). Phase 3a doc clarifies this. Phase 5.5 idempotency means orchestrator's Phase 5 PR creation no longer collides with idd-implement's.
- **Config schema** — new optional `pr_policy` field in `.claude/issue-driven-dev.local.json`. Backward compatible (absent = `ask`).
- **`references/pr-flow.md`** — new canonical contract document. Branch naming, PR body template, decision matrix, all in one place. Three SKILLs link here instead of duplicating.
- **`references/config-protocol.md`** — added `pr_policy` documentation to schema and field reference.
- **`CLAUDE.md`** — new "PR vs Direct-commit Path" section describing the routing.

### Migration

No breaking changes. Existing configs without `pr_policy` default to `ask` (prompts on first `idd-implement`). Existing `idd-all` users see no behavior change — it always was PR-only; this release just makes that contract explicit and consistent with the new flag system.

If you want to opt out of the prompt on a solo / personal repo:

```json
{
  "github_repo": "owner/repo",
  "pr_policy": "never"
}
```

If you want to enforce PR for a team repo:

```json
{
  "github_repo": "owner/repo",
  "pr_policy": "always"
}
```

## 2.26.0 — 2026-04-25

(prior history not migrated to CHANGELOG; see git log)
