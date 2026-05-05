# issue-driven-dev

Human defines the problem, AI solves it.

> **TDD 寫測試。SDD 寫規格。IDD 解 bug。** 前兩個是手段，IDD 是目的。
> 完整論述見 [`MANIFESTO.md`](./MANIFESTO.md)。

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
| `idd-plan` | Plan tier approval gate using `EnterPlanMode` — presents Implementation Plan for user approval before TDD execution; sits between `Simple` direct-implement and `Spectra` spec-contract path (v2.36.0+) |
| `idd-implement` | Scope-disciplined implementation with TDD |
| `idd-verify` | Independent verification using Codex CLI (gpt-5.5) |
| `idd-close` | Closing comment documenting problem, root cause, solution, verification |
| `idd-comment` / `idd-edit` | Add or amend issue comments with template guidance (decision / note / question) |
| `idd-list` / `idd-update` / `idd-report` | List open issues by phase, sync issue body, generate progress reports |
| `idd-config` | Manage `.claude/issue-driven-dev.local.json` lifecycle: `show` / `init` / `validate` / `which` (v2.31.0) |
| `idd-all` | Orchestrator that drives the full pipeline (issue → close) end-to-end (v2.26.0; v2.28.0 unattended SDD chain) |

### Use-Case Routing（v2.37.0）

Not sure which skill / flag to use for your situation? See [`references/usecase-routing.md`](references/usecase-routing.md) — a 24-row reference mapping common scenarios (single / batch / cluster-PR / external-agent / Plan / Spectra) to the exact skill chain + flags + contract docs.

### External-Agent Verify（v2.37.0）

When `implement` is delegated to an external agent (Codex, Copilot Workspace, remote claw on a sibling machine), `idd-verify` supports three input sources beyond the default local-diff:

- `idd-verify #98 --pr 123` — verify a PR opened by the external agent. PR is the master comment location; ref'd issues get pointer comments. Issue↔PR correspondence is gate-checked (PR body must `Refs #N` matching scope, else abort).
- `idd-verify #98 --commits 3` — when the external agent commits to your current working tree
- `idd-verify #98 --branch <name>` — when changes live on a branch but no PR yet
- `idd-verify --pr 123` (no issue) — auto-discover ref'd issues from PR body

Auto-detect: invoking `idd-verify #98` with no input flag counts unpushed commits ref'ing #98 and queries open PRs ref'ing #98, then `AskUserQuestion` to pick between local diff vs PR. Catches the common forgotten-flag case. Full contract: [`references/external-agent-delegation.md`](references/external-agent-delegation.md).

### Multi-issue Invocation（v2.34.0）

Seven skills accept multiple `#NNN` arguments and dispatch to one of two modes:

- **Batch mode** (`idd-diagnose` / `idd-update` / `idd-comment` / `idd-edit`) — independent per-issue ops looped sequentially. Each issue gets its own comment, its own auto-update phase, its own audit trail. Failure on one doesn't roll back the rest.
- **Cluster-PR mode** (`idd-implement` / `idd-verify` / `idd-close`) — multi-issue work sharing one feature branch + one PR. Branch `idd/cluster-{slug}`, commits tag `Refs #N` (multiple OK), verify report partitions per issue, close writes per-issue summary. Designed around the "7 issues → 2 themed PRs" workflow pattern.

Selector syntax in v1: explicit list (`#34 #36 #38`). `idd-issue` / `idd-list` / `idd-report` / `idd-config` / `idd-all` are out of scope. Single-issue invocation is unchanged. Full contract: `references/batch-and-cluster.md`.

### Tagging Collaborators（v2.32.0）

Any IDD skill that posts `@xxx` to GitHub follows a mandatory 5-step protocol so the wrong person never gets pinged:

1. **Detect intent** — `--mention <login>[,<login>...]` flag (on `idd-issue` / `idd-comment`) or natural-language ("tag X" / "ping X" / "通知 X")
2. **Fetch real list** — `gh api repos/$REPO/collaborators` (+ org members for org repos); training-data / chat-history / git-log handles are forbidden
3. **Resolve** — fuzzy match against `login` + `name` field; unique match → use, otherwise fallback
4. **AskUserQuestion fallback** — 0 or 2+ matches → menu populated from the real collaborator list, never guessed
5. **Verify pre-post** — grep `@\w+` from body, every token must be in the verified set, otherwise abort

GitHub mentions are an irreversible side effect; the rule is mandatory not advisory. See `rules/tagging-collaborators.md` (in-plugin) for the full protocol with examples.

### Spectra ↔ IDD Bridge（v2.32.0）

When `spectra-discuss` is interrupted mid-flow to invoke an IDD skill (e.g. "let me capture this finding to the issue"), the bridge protocol preserves and resumes context:

- **Step 0.7 Detect** — `--resume-spectra="<topic>"` flag, `--source` contains `spectra-discuss`, `spectra list --json` shows in-flight changes, or `.claude/state/idd-bridge.json` exists → `SPECTRA_BRIDGE_ACTIVE=1`
- **Step N-1 Bookmark** — `.claude/state/idd-bridge.json` written with verbatim `spectra_topic` + `issue_url` + `open_questions[]` + `idd_action_url` + `next_step_hint`
- **Step N Resume Prompt** — final output prints a clearly-delimited `↩ Resume spectra-discuss` block with a copy-pasteable `/spectra-discuss <topic>...` prompt

Hard rules: never auto-invoke `/spectra-discuss` (user controls pacing); never paraphrase `spectra_topic`; resume prompt is the actual recovery — bookmark file is convenience.

`idd-comment` is the first skill with full implementation. `idd-issue` and `idd-edit` will gain it next; the rule defines the contract for all skills. See `rules/spectra-bridge.md` (in-plugin) for the full schema.

### Implementation Composability（v2.30.0）

`idd-implement` accepts two flags that turn it from a single-purpose TDD loop into a **dispatcher** for other skills:

- `--with-skill <name>` — GREEN phase calls `Skill(skill=<name>)` instead of direct `Edit` (e.g., `--with-skill perspective-writer` for prose deliverables, `--with-skill spectra-apply` for SDD-warranted)
- `--extra '<text>'` — free-text additional constraint, written into Implementation Plan's `### Extra Requirements` section so checklist semantic gate can verify it

Auto-detection: `idd-implement` Step 1.5 also scans the diagnosis Strategy for `透過 X` / `via X` patterns and resolves the with_skill target without requiring explicit flags. Compose order: explicit flag > diagnosis hint > none.

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
| v2.52.0 | 2026-05-05 | **`idd-issue` ordered/unordered bundle flags** ([#21](https://github.com/PsychQuant/issue-driven-development/issues/21)). NEW `--parent <N>` flag PATCHes parent body task list with new child entry, idempotent via `#N` reference scan + fallback `## Children` anchor when no list exists. NEW `--blocked-by <M>[,<M2>...]` flag applies three-layer fallback chain: Layer 1 GraphQL `addBlockedByDependency` mutation attempt (graceful failure → warning + continue, no abort) + Layer 2 unconditional body blockquote `> Blocked by #M` (always readable in any markdown viewer) + Layer 3 parent task list annotation `(blocked by #M)` when `--parent` co-used. NEW `--bundle-mode <ordered\|unordered>` flag orchestrates bundle creation in single invocation: builds 1 epic parent + N children with auto-applied `--parent <epic>`, `ordered` mode adds strict `child[i] blocked by child[i-1]` chain, `unordered` keeps task list only. Pre-flight gates: cross-repo refuse (parent in different repo → abort + redirect to `groups`), bundle-mode and group-mode mutual exclusion. Step 3.B inserted between 3.A (single repo) and 3.G (group), reusing 3.A flow. Orthogonal with Step 4.5 milestone, Step 4.7 sister sweep. NEW canonical reference doc `references/bundle-flags.md`. NEW `## Ordered Bundle Pattern` section after Step 5 in `idd-issue` SKILL.md (3-mode comparison + 3 usage scenarios + design rationale for not creating separate `/idd-bundle` skill). NEW capability spec `idd-issue-bundle` (4 Requirements, frozen). Spectra change `add-bundle-flags-to-idd-issue` archived. No breaking changes — all flags additive. |
| v2.51.0 | 2026-05-04 | **`idd-list` shows open PR info per issue + cluster detection** ([#13](https://github.com/PsychQuant/issue-driven-development/issues/13)). NEW Step 2.5 batch fetches all open PRs once (`gh pr list --state open --limit 100`); NEW Step 3.5 client-side regex `#(\d+)\b` scans PR bodies and builds reverse `issue→PR` index plus cluster map (PRs ref'ing 2+ issues). Step 4 Format Output adds `└─ PR #N (status, mergeable)` sub-line per issue with PR ref; cluster leaders (lowest issue number) show `— cluster: #X #Y #Z` listing all members; cluster members show `→ see PR #N (cluster member)` redirect. Direct-commit issues (no PR refs) display unchanged from v2.50 — fully backward compatible. Footer adds second line summarizing `N issues bundled in M cluster(s); P solo PR(s); Q direct-commit`. Step 5 Suggest Next extended to phase × PR state matrix (10+ rows): `implemented + draft` → `gh pr ready N → /idd-verify --pr N`; `implemented + ready MERGEABLE` → `/idd-verify --pr N`; `verified + ready MERGEABLE` → `gh pr review N → gh pr merge N → /idd-close #N`; `verified + merged` catch-up → `/idd-close #N`; `CONFLICTING` → `gh pr checkout N → resolve`; cluster member → `see leader's next action`. Sister concerns filed as P3 follow-ups: [#14](https://github.com/PsychQuant/issue-driven-development/issues/14) (markdown-aware PR body parser) + [#15](https://github.com/PsychQuant/issue-driven-development/issues/15) (`cluster_leader` config option). |
| v2.50.0 | 2026-05-04 | **Layer V Vagueness Pre-check** for complexity routing ([#12](https://github.com/PsychQuant/issue-driven-development/issues/12)). NEW Step 3.4 in `idd-diagnose` between Layer 1 disqualifier and Layer 2 Spectra evaluation. AI scores V1 (vague WHAT) + V4 (vague ACCEPTANCE) on Likert 6-point scale (no neutral midpoint), trigger threshold per-axis ≥ 4. Triggered cases fire Hybrid 3-option AskUserQuestion (`clarify now` / `proceed anyway` / `escalate to Plan`) with default option score-driven (V=4 → proceed, V=5 → clarify, V=6 → escalate). `escalate` force-sets verdict = `Plan via Layer V` and skips Layer 2/3/P. Routing parsers in `idd-implement` Step 2.5 + `idd-all` Phase 3 strip ` via X` suffix to extract canonical tier (backward compat: bare verdicts unchanged). NEW project rule [`.claude/rules/attribute-assessment.md`](https://github.com/PsychQuant/issue-driven-development/blob/main/.claude/rules/attribute-assessment.md) codifies meta-principle "**attribute scoring SHALL use Likert scale, not keyword matching**" — applies session-wide via root `CLAUDE.md` `@import`, scope beyond Layer V. [`MANIFESTO.md`](./MANIFESTO.md) 5-axis bug-fix model expanded to 6-axis adding "Alignment quality" (TDD ❌ / SDD ❌ / IDD ✅), evidence = Layer V. `idd-all` unattended mode auto-applies `proceed anyway` + audit trail (same pattern as Plan tier under unattended). Backward compat: pre-v2.50 diagnoses **NOT** retroactively re-evaluated; existing `Simple` / `Plan` / `Spectra` / `SDD-warranted` verdicts remain valid. No `--ignore-vagueness` flag (option B `proceed anyway` covers it). Spectra change `add-vagueness-layer-routing` archived. New main spec `openspec/specs/routing-vagueness-layer/spec.md` (9 normative requirements with scenarios + example tables). |
| v2.36.0 – v2.49.0 | 2026-04-30 – 2026-05-03 | Spectra rename + Plan tier + cross-skill IC_R011 alignment. **v2.36.0**: 3-tier Complexity routing (Simple / Plan / Spectra; SDD-warranted alias preserved); NEW `idd-plan` skill with EnterPlanMode approval gate. **v2.37.0**: External-agent / PR mode for `idd-verify` (`--pr <N>` / `--commits N` / `--branch <name>` flags + auto-detect); `references/external-agent-delegation.md` + `references/usecase-routing.md`. **v2.38.0**: `idd-route` integration (data-driven agent routing recommendation; binary at PsychQuant/idd-route-swift); marketplace migration to `PsychQuant/issue-driven-development`. **v2.39.0 / v2.40.0**: `--cwd` flag for cross-repo orchestration (sub-skills inherit). **v2.41.0**: `idd-close` Step 0 supersession (Implementation Complete > Checklist treated as canonical when all `[x]`). **v2.42.0 – v2.48.0**: IC_R011 systematic alignment — canonical `references/ic-r011-checkpoint.md` + 5 sub-issues across `idd-plan` / `idd-implement` / `idd-close` / `idd-diagnose` / `idd-issue` (each gets a 3-option AskUserQuestion + audit trail at its deliberation moment). **v2.49.0**: IC_R011 Third-Party Skill Alignment for `/spectra-discuss` + `/spectra-propose`. |
| v2.34.0 | 2026-04-29 | Multi-issue invocation across 7 skills via two distinct modes. **Batch mode** (`idd-diagnose` / `idd-update` / `idd-comment` / `idd-edit`) — sequential per-issue ops, each issue gets its own comment / auto-update phase / audit trail; failure on one doesn't stop the rest; pure idempotent. **Cluster-PR mode** (`idd-implement` / `idd-verify` / `idd-close`) — multi-issue work shares one feature branch + one PR; commits tag `Refs #N` (multiple OK); branch named `idd/cluster-{slug}`; verify report partitions per-issue; close enforces per-issue checklist gate + writes per-issue summary (no batched fake summary). Designed around the "7 issues → 2 themed PRs" workflow pattern (e.g., 04/27 Docs+Sanitizer split). Selector syntax in v1: explicit list (`#34 #36 #38`) only; `--label` / `--milestone` selectors deferred. Out of scope: `idd-issue` (input phase), `idd-list` / `idd-report` (already multi by design), `idd-config` (N/A), `idd-all` (single-issue orchestrator). Single-issue invocation unchanged — backward compatible. New canonical contract: `references/batch-and-cluster.md`. |
| v2.33.0 | 2026-04-28 | NEW [`MANIFESTO.md`](./MANIFESTO.md) — formalizes the methodology thesis. Decomposes "bug-solving capability" into 5 sub-capabilities (TDD covers 1.5/5, SDD 0/5, IDD 5/5). Adds two formal claims: (1) IDD opens a second axis orthogonal to TDD/SDD's verification axis (closure / DONE definition); (2) IDD ⊋ TDD ∪ SDD on falsifiability surface. Empirical case study: che-word-mcp #56 cluster — 30 findings, 5 sub-stack rounds, 6 patch releases, zero zombies. README + CLAUDE.md link to MANIFESTO. No code change. |
| v2.32.0 | 2026-04-28 | TWO new rules closing real-world workflow gaps observed in PsychQuant/contact-book#96. (1) NEW `rules/tagging-collaborators.md` — mandatory 5-step protocol when any IDD skill posts `@`-mention to GitHub: detect intent (`--mention <login>` flag or natural-language) → fetch real list (`gh api repos/$REPO/collaborators` + org members; training-memory / chat-history / git-log handles forbidden) → fuzzy match → AskUserQuestion fallback for 0/2+ matches → grep + verify pre-post (abort on unverified token). `idd-issue` + `idd-comment` gain `--mention <login>[,<login>...]` flag; `idd-diagnose` / `idd-implement` / `idd-verify` / `idd-close` enforce via prose detection. (2) NEW `rules/spectra-bridge.md` — bridge contract for IDD skills called mid-`spectra-discuss`: detection signals trigger `SPECTRA_BRIDGE_ACTIVE`, bookmark schema preserves verbatim `spectra_topic` + `issue_url` + `open_questions[]` + `next_step_hint`, final `↩ Resume spectra-discuss` prompt block printed at skill exit. `idd-comment` is first skill with full implementation (Step 0.7 detect, Step 7 bookmark + resume); `idd-issue` / `idd-edit` will gain it next. No breaking changes — new flags opt-in. |
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
# Install (v2.38.0+ marketplace)
/plugin marketplace add https://github.com/PsychQuant/issue-driven-development
/plugin install issue-driven-dev@issue-driven-development

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
