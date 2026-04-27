# issue-driven-dev

Human defines the problem, AI solves it.

## What is this?

A Claude Code plugin that enforces issue-driven development as a complete methodology:

1. **Every change starts with an issue** — the single source of truth
2. **Every issue is diagnosed before implementation** — no guessing
3. **Every implementation is scope-controlled** — no creep
4. **Every completion is independently verified** — no "looks good enough"
5. **Every closure is documented** — knowledge preserved

## Why?

Each skill guards against a specific failure mode:

| Failure | Without this plugin | With this plugin |
|---------|---------------------|-----------------|
| No documentation | Changes with no recorded reason | Every change traces to an issue |
| Surface-level fixes | Patch symptoms, root cause returns | Diagnosis required before implementation |
| Scope creep | Fix #42, refactor 3 unrelated files | Scope guardian flags unrelated changes |
| False confidence | "Should work" → ship broken code | Independent AI verification (Codex) |
| Lost knowledge | "What did we do?" 3 months later | Mandatory closing comment |

## Skills

```
idd-issue → idd-diagnose → idd-implement → idd-verify → idd-close
    ①            ②              ③              ④            ⑤
```

| Skill | Purpose |
|-------|---------|
| `idd-issue` | Create well-documented GitHub Issue with original quotes and images |
| `idd-diagnose` | Find root cause (bug) or analyze requirements (feature/refactor) |
| `idd-implement` | Scope-disciplined implementation with TDD |
| `idd-verify` | Independent verification using Codex CLI (gpt-5.5) |
| `idd-close` | Closing comment documenting problem, root cause, solution, verification |
| `idd-comment` / `idd-edit` | Add or amend issue comments with template guidance (decision / note / question) |
| `idd-list` / `idd-update` / `idd-report` | List open issues by phase, sync issue body, generate progress reports |
| `idd-config` | Manage `.claude/issue-driven-dev.local.json` lifecycle: `show` / `init` / `validate` / `which` (v2.31.0) |
| `idd-all` | Orchestrator that drives the full pipeline (issue → close) end-to-end (v2.26.0) |

### PR vs Direct-Commit Path Routing（v2.27.0）

`idd-implement` now explicitly resolves whether work flows through a **PR path** (feature branch + push + `gh pr create`) or a **direct-commit path** (current branch, no PR), instead of implicitly following whatever branch the user happens to be on.

Resolution priority (highest first):

1. `--pr` / `--no-pr` flag (per-invocation)
2. **Fork detection** (`gh repo view --json isFork`) → forced PR path (forks have no upstream push permission)
3. `pr_policy` config field: `"always"` / `"never"` / `"ask"` (default `"ask"`)

`idd-close` adds a Step 1.5 **PR Gate Check** that refuses to close an issue when its PR is unmerged. `idd-all` (orchestrator) explicitly enforces `--pr`.

Full contract in `references/pr-flow.md` (in-plugin).

### Multi-repo Support（v2.21.0+ / v2.25.0）

For monorepos and coordinated cross-repo issues, every IDD skill accepts `--target owner/repo` (or `--target group:<label>`) so a single workspace can drive issues across multiple GitHub repos:

- **Fork-aware** (v2.21.0) — `idd-issue` resolves the upstream repo from the fork's `origin`
- **JSON config** (v2.22.0, breaking) — per-repo settings move from `.local.md` to `.local.json`
- **Six-mechanism resolution** (v2.25.0) — flag → `ask_each_time` menu → predicates → cascading walk-up → git remote fallback → orthogonal groups; supports `candidates[]` with `when` predicates and `groups[]` for primary + tracking issue pairs

See `references/config-protocol.md` (in-plugin) for the full algorithm.

## Version History

| Version | Date | Changes |
|---------|------|---------|
| v2.31.0 | 2026-04-27 | NEW `idd-config` skill — independent entry for `.claude/issue-driven-dev.local.json` lifecycle. Four subcommands: `show` (default; resolved target + cwd-aware predicate trace), `init` (interactive first-time setup, equivalent to `idd-issue` Step 0.5.E fork-aware detection without forcing an issue creation), `validate` (JSON schema + repo existence + predicate-key sanity), `which` (dry-run resolution at cwd, optional `--title` / `--label` to evaluate content predicates). Closes the gap where setup / inspection / monorepo predicate debugging was only available as a side effect of `idd-issue`. |
| v2.30.0 | 2026-04-26 | (1) `idd-issue` 資料保留鐵律 — all source attachments uploaded to attachments release by default without asking. New Source Type Adapter table covers `.docx` / `.pdf` / Telegram / Apple Mail / Notes / pasted text + Telegram fallback flow. Step 4 renamed `附加圖片（如果有）` → `附加所有原始素材（鐵律：預設全保留）` with violation checklist. (2) `idd-implement` `--with-skill <name>` + `--extra '<text>'` flags + new Step 1.5 Resolve Extra Requirements; GREEN phase calls Skill(skill=…) instead of Edit when with_skill set. First-class formalization of idd-implement × perspective-writer integration. |
| v2.29.0 | 2026-04-26 | Two-tier checklist gate in `idd-close` — Step 0 structural gate (existing) refuses close on unticked `- [ ]`; new Step 1.6 semantic gate does keyword extraction on each `- [x]` and verifies test/spec/file mentions correspond to real artifacts. Warn-only with three-way AskUserQuestion (proceed / investigate / edit). |
| v2.28.0 | 2026-04-26 | `idd-all` SDD path is now an unattended chain — spectra-discuss → spectra-propose → spectra-apply with explicit unattended hints in args. Orchestrator overrides sub-skill attended-by-default contracts via args, not by modifying sub-skills. |
| v2.27.0 | 2026-04-26 | PR vs direct-commit path routing in `idd-implement` (`--pr` / `--no-pr` flag, fork-aware default, new `pr_policy` config field). `idd-close` Step 1.5 PR Gate Check refuses close on unmerged PR. `idd-all` explicitly enforces PR path. New `references/pr-flow.md` as canonical contract. |
| v2.26.0 | 2026-04-26 | Add `idd-all` orchestrator skill that drives the full pipeline (issue → diagnose → implement → verify → close) end-to-end. |
| v2.25.0 | 2026-04-26 | Monorepo + multi-repo support via config-protocol — six-mechanism resolution. New `candidates[]` (path/git predicates), `groups[]` (primary + tracking with bidirectional cross-link comments), `ask_each_time`. |
| v2.22.x | 2026-04-22 | JSON config (breaking — `.local.md` → `.local.json`); fork-aware target repo selection; codex pinning. |
| v2.18.0 – v2.20.0 | 2026-04-14 – 2026-04-16 | Mandatory Step 0 Bootstrap Stage Task List for every IDD stage skill; `idd-verify` auto-triages follow-up findings into new issues. |
| v2.12.0 – v2.17.x | 2026-04-07 – 2026-04-14 | SDD as special case of IDD; checklist gate on close; `idd-list` / `idd-comment` / `idd-edit` skills; ban `Closes`/`Fixes`/`Resolves` trailers (they bypass `idd-close` gate). |

## Quick Start

```bash
# Install
/plugin marketplace add https://github.com/PsychQuant/psychquant-claude-plugins
/plugin install issue-driven-dev

# Use (auto-completion: type "idd-" to see all skills)
/idd-issue "upload button doesn't work on mobile"
/idd-diagnose #42
/idd-implement #42
/idd-verify #42
/idd-close #42
```

## Configuration

On first use, creates `.claude/issue-driven-dev.local.md`:

```yaml
---
github_repo: "owner/repo"
github_owner: "owner"
attachments_release: "attachments"
---
```

## Requirements

- `gh` CLI authenticated with GitHub
- [OpenAI Codex CLI](https://github.com/openai/codex) installed (for `idd-verify`)
- ChatGPT Pro account (for Codex gpt-5.5)
