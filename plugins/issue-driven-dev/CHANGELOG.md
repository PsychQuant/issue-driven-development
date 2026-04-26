# Changelog

## 2.29.0 — 2026-04-26

### Two-tier checklist gate in `idd-close`

The structural gate (v2.17.0) catches **honest forgetting** — you can't close an issue with unticked `- [ ]` items. But it can't catch **motivated cheating** — ticking `- [x]` without doing the work. v2.29.0 adds a semantic gate to address the second failure mode.

### Changes

- **`idd-close` Step 1.6 — Semantic Checklist Gate** — for each `- [x]` bullet that passed the structural gate, classify against three keyword patterns and verify the underlying artifact exists:

  | Pattern | Check |
  |---------|-------|
  | Contains test/regression/coverage keywords | `git log --grep="#${N}" -- '**/*test*' ...` must return ≥1 commit |
  | References `openspec/changes/<name>/{proposal,design,tasks,spec}.md` | File must exist |
  | Contains backtick-wrapped file path with extension | Path must appear in `git log --grep="#${N}" --name-only` |
  | No recognized pattern | Skip (counted as "unchecked") |

- **Warn-only behavior** — semantic gate doesn't hard-refuse like the structural gate. Keyword extraction has false positives (e.g. test commit landed in earlier PR), so warnings are presented with AskUserQuestion three-way choice: proceed / investigate / edit checklist.

- **`idd-close` Step 0.5 task list** — added `semantic_gate_check` entry.

- **`idd-close` 鐵律 section** — added "打勾沒做要 warn" rule alongside "沒打勾就不關".

- **`CLAUDE.md` Two-Tier Gate section** — new section comparing structural vs semantic gate, and explicit falsifiability claim that IDD is now strict superset of TDD ∪ SDD on the falsifiability surface (outcome verification inherited from inner methodologies + IDD-only audit-level semantic check).

### Why warn-only and not hard-refuse

The structural gate can hard-refuse because false positives are impossible — either a `- [ ]` exists or it doesn't. The semantic gate works on heuristics: a test commit might legitimately live in a prior PR not referencing #NNN, an external file might be modified by tooling, etc. A hard-refuse on heuristic check would block legitimate closes. The warn + AskUserQuestion approach surfaces the suspicious signal, makes the user explicitly acknowledge it, and lets them either proceed (confirming the heuristic was wrong) or investigate (treating the heuristic as right).

### Migration

No breaking changes. Issues that previously closed cleanly under v2.28.0 still close cleanly under v2.29.0 — the semantic gate adds a warning step but doesn't refuse anything. Issues with semantic mismatches now surface them at close time instead of staying hidden.

## 2.28.0 — 2026-04-26

### `idd-all` SDD path is now unattended

`idd-all` is a fire-and-forget orchestrator — it assumes nobody is watching. Previously the SDD path called `spectra-discuss` and `spectra-apply` directly, with two problems:

1. The middle step `spectra-propose` was missing from the chain.
2. Each spectra skill's built-in `AskUserQuestion` checkpoints would stall the pipeline — `spectra-discuss` paces conversation one question at a time; `spectra-propose` Step 10 asks "Park or Apply?" defaulting to Park; `spectra-apply` Step 4 asks for continue-confirmation.

This release makes the SDD path a true unattended chain.

### Changes

- **`idd-all` Phase 3b** — rewrote as four sub-steps: capture issue context, then call `spectra-discuss` / `spectra-propose` / `spectra-apply` in sequence. Each call passes a long `args` string with explicit instructions to suppress `AskUserQuestion` checkpoints and produce a structured marker line (`Conclusion: ...` / `Change: ...`) that the next step parses.
- **`spectra-propose` chaining** — `idd-all` calls `spectra-apply` itself rather than letting `spectra-propose` chain. This respects the architectural `NEVER invoke /spectra-apply` guardrail in spectra-propose (L267) while still achieving end-to-end automation.
- **New core principle: "Unattended assumption"** — added to idd-all's core principles. Sub-skills' attended-by-default behavior is correct for solo use; idd-all is the one promising "unattended", so it's idd-all's responsibility to override via args, not by modifying sub-skill plugins.
- **Failure modes table** — added entries for spectra-discuss / propose / apply specific failure modes (missing marker line, unrecoverable validation, unfinished tasks).
- **Complexity table footnote** — clarifies that users wanting attended SDD discussion should run `/spectra-discuss` etc. manually, not `idd-all`.
- **CLAUDE.md workflow diagram** — annotated to show idd-all's SDD path is unattended chain; manual SDD path remains attended.

### Migration

No breaking changes for users running `idd-all` from scratch — the SDD path now finishes more reliably (no longer stalls on `Park or Apply` prompt). If you were relying on the prior "abort on user input needed" escape hatch, you now need to run the SDD skills manually instead of `idd-all`. The trade-off matches the orchestrator's stated promise: pick `idd-all` for fire-and-forget, pick manual `/spectra-*` for attended alignment.

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
