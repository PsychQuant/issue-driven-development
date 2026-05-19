# IDD Commands Reference

> Spec date: 2026-05-19 · `issue-driven-dev` **2.60.0** · `idd-route` **0.2.0** · `ralph-loop` **1.0.0**
>
> Single-page reference for all configured `idd-*` commands, the `idd-route-*` agent-routing helpers, and the `ralph-loop` integration used by `--loop` / unattended modes. Each command lists **Goal**, **Syntax**, every **Option / Flag** with what it actually does, **Decision points** (AskUserQuestion branches), **Workflow position**, and a link to the canonical `SKILL.md` (treat that as source of truth — this page is the index).

---

## Quick reference

| Command | One-liner | Args / flags |
|---------|-----------|-------------|
| [`/idd-config`](#idd-config) | Inspect / init / validate `.claude/issue-driven-dev.local.json` | `[show \| init \| validate \| which]` |
| [`/idd-list`](#idd-list) | List issues + IDD phase + suggested next action | `[--state ...] [--label ...] [--limit N] [--target ...]` |
| [`/idd-issue`](#idd-issue) | Create a well-documented GitHub issue | `[description \| path/to/.docx] [--target ...] [--parent N] [--blocked-by M,...] [--bundle-mode ordered\|unordered] [--mention login]` |
| [`/idd-comment`](#idd-comment) | Add template-guided comment (decision / note / question / correction / link / errata) | `#N [#N ...] --type=<type> [options]` |
| [`/idd-edit`](#idd-edit) | Edit existing comment (append / replace / prepend-note) | `comment:<id>[ ...] \| #N --last [--append \| --replace \| --prepend-note] [--body=...]` |
| [`/idd-diagnose`](#idd-diagnose) | RCA / requirements analysis + complexity verdict | `#N [#N ...] [--cwd ...]` |
| [`/idd-plan`](#idd-plan) | Plan-tier: EnterPlanMode approval gate before TDD | `#N [--pr \| --no-pr] [--cwd ...]` |
| [`/idd-implement`](#idd-implement) | TDD implementation with scope guard | `#N [#N ...] [--pr \| --no-pr] [--cwd ...] [--with-skill ...] [--extra '...']` |
| [`/idd-verify`](#idd-verify) | 6-AI cross verify (5 Claude reviewers + Codex) | `#N [#N ...] [engine] [--loop] [--pr N] [--commits N] [--branch X] [--since REF] [--cwd ...]` |
| [`/idd-close`](#idd-close) | Closing summary + close (refuses on unchecked items) | `#N [#N ...]` |
| [`/idd-update`](#idd-update) | Sync issue body Current Status block | `#N [#N ...]` |
| [`/idd-report`](#idd-report) | Aggregate progress report to GitHub Discussions | `#N ... \| source:file \| milestone:name [@tag ...]` |
| [`/idd-all`](#idd-all) | Run the whole pipeline (issue → verified) | `[#N \| 'desc'] [--pr \| --no-pr] [--cwd ...]` |
| [`/idd-all-chain`](#idd-all-chain) | `/idd-all` over root + auto-emergent spawned issues, 1 cluster PR | `[#N] [--cwd ...]` |
| [`/idd-route-recommend`](#idd-route-recommend) | Recommend an agent for an issue (data-driven) | `<repo-path> <complexity> <scope-loc> --signals s1,...` |
| [`/idd-route-stats`](#idd-route-stats) | Human-readable summary of `routing-stats.jsonl` | `<repo-path> [--decay-half-life-days N]` |
| [`/idd-route-backfill`](#idd-route-backfill) | Seed `routing-stats.jsonl` from historical verify comments | `<owner/repo> <repo-path> [--since DATE]` |
| [`/goal`](#goal) | Built-in: keep working across turns until a condition holds (Claude Code ≥ 2.1.139) | `[condition \| clear]` |
| [`/loop`](#loop) | Built-in: re-run a prompt on a schedule (bundled skill, Claude Code ≥ 2.1.72) | `[INTERVAL] [PROMPT]` |
| [`/ralph-loop`](#ralph-loop) | External (`claude-plugins-official`): legacy outer drive loop — superseded by `/goal` + `/loop` | `PROMPT [--max-iterations N] [--completion-promise TEXT]` |
| [`/cancel-ralph`](#cancel-ralph) | Cancel active Ralph Loop | — |

> **Slash-syntax note**: in Claude Code the canonical invocation prefix is `/`, not `:` — `/ralph-loop` not `/ralph:loop`. The `:` form is shorthand for plugin namespace, not the command syntax.
>
> **Native vs plugin autonomous loops**: `/goal` (condition-driven) and `/loop` (schedule-driven) are **Claude Code built-ins** and should be preferred over `ralph-loop` for new work. `ralph-loop` predates them; the IDD skills that previously documented `--loop` as a ralph-loop call now work equally well with `/goal` (e.g. `/goal idd-verify --pr 94 exits PASS`).

---

## Workflow position

```
              ┌──────────────────┐
              │  /idd-config     │   Set target repo (once per project tree)
              │  /idd-list       │   See what needs work
              └──────────────────┘
                       │
                       ▼
     ┌─────────────────────────────────────┐
     │  /idd-issue ─────────────────────►  │   Create issue
     │     │ (source: text / .docx / mail) │
     │     ▼                               │
     │  /idd-diagnose ──────────────────►  │   RCA + complexity verdict
     │     │                               │   ↳ Simple / Plan / Spectra
     │     ▼                               │
     │  ┌── Simple ──► /idd-implement ──┐  │
     │  │                               │  │   Pick path by complexity verdict
     │  ├── Plan ────► /idd-plan ───────┤  │
     │  │              (approval gate)  │  │
     │  │              ↓                │  │
     │  │              /idd-implement   │  │
     │  └── Spectra ─► /spectra-* …     │  │   (separate plugin chain)
     │     │                            │  │
     │     ▼                            │  │
     │  /idd-verify (6-AI) ─────────────┘  │   Cross verify, fix until clean
     │     │                               │
     │     ▼                               │
     │  /idd-close                         │   Closing summary + close
     └─────────────────────────────────────┘
              │
              ▼
     ┌──────────────────┐
     │  /idd-comment    │   Side-quest: add notes / decisions any time
     │  /idd-edit       │
     │  /idd-update     │   (mostly auto-called by other skills)
     │  /idd-report     │   Roll-up to Discussions
     └──────────────────┘

     Orchestration:                       Routing helpers (idd-route):
       /idd-all         ← full chain        /idd-route-recommend
       /idd-all-chain   ← root + spawns     /idd-route-stats
                                            /idd-route-backfill

     Autonomous loops (drive a session to a condition / on a schedule):
       /goal            ← Claude Code built-in (≥ 2.1.139); condition-driven
       /loop            ← Claude Code built-in (≥ 2.1.72); schedule-driven
       /ralph-loop      ← claude-plugins-official; legacy, superseded by /goal
       /cancel-ralph
```

---

## Phase 0 — Setup & triage

### `/idd-config`

**Goal**: Manage IDD's target-repo config (`.claude/issue-driven-dev.local.json`). No issues touched; no state mutated outside the config file.

**Syntax**: `/idd-config [show | init | validate | which]`

**Options**:

| Subcommand | Effect |
|---|---|
| `show` (default) | Print resolved config + which file the walk-up landed on |
| `init` | Interactive: pick `github_repo`, fork-aware menu (Upstream / Own fork / Both) when origin is a fork, write the file |
| `validate` | Schema-check current config (predicates well-formed, candidates resolvable) |
| `which` | Walk up from `$PWD` and print the first `.claude/issue-driven-dev.local.json` found, plus whether predicates would re-route the resolution |

**When**: first-run setup; debugging monorepo predicate routing; verifying schema before relying on it.

**Spec**: [`skills/idd-config/SKILL.md`](../plugins/issue-driven-dev/skills/idd-config/SKILL.md) · backing protocol: [`references/config-protocol.md`](../plugins/issue-driven-dev/references/config-protocol.md)

---

### `/idd-list`

**Goal**: List issues with their resolved IDD phase (`unprocessed` / `diagnosed` / `planning` / `implemented` / `verified` / `closed`) and the suggested next action for each.

**Syntax**: `/idd-list [--state open|closed|all] [--label <name>] [--limit N] [--target owner/repo]`

**Options**:

| Flag | Effect |
|---|---|
| `--state open` (default) / `closed` / `all` | GitHub state filter |
| `--label <name>` | Filter by label (single or comma list, as `gh issue list --label` accepts) |
| `--limit N` | Cap returned issues (`gh` default ≈ 30) |
| `--target owner/repo` | One-shot repo override; does not write to config |

**When**: opening a session, deciding what to work on, finding issues stuck mid-phase.

**Spec**: [`skills/idd-list/SKILL.md`](../plugins/issue-driven-dev/skills/idd-list/SKILL.md)

---

## Phase 1 — Issue creation

### `/idd-issue`

**Goal**: Create a well-documented GitHub issue. Issue is the human ↔ AI interface; this is the canonical entry point. Source can be a description, a `.docx`, a Telegram chat, an Apple Mail thread, an Apple Note, or any mix — the skill enforces the **attachment-preservation rule** (anything extractable is uploaded to the `attachments` release; manually-fallback-only when an MCP tool genuinely fails).

**Syntax**: `/idd-issue [description or path to .docx] [--target ...] [--parent N] [--blocked-by M,...] [--bundle-mode ordered|unordered] [--mention login[,...]]`

**Options**:

| Flag | Effect |
|---|---|
| _positional_ description / path | Raw text, file path (docx/pdf/md/txt), or chat reference; skill auto-detects type and routes to the matching reader (`che-word-mcp`, `che-pdf-mcp`, Telegram MCP, Apple Mail/Notes MCP). Missing MCP plugin → **fail-fast** with install instructions (per #27 / #32). |
| `--target <owner/repo \| group:label>` | Per-invocation target override; does **not** write to config |
| `--parent N` | Link the new issue under issue #N (idempotent PATCH of #N's body task-list, see [`bundle-flags.md`](../plugins/issue-driven-dev/references/bundle-flags.md)) |
| `--blocked-by M[,M2,...]` | Three-layer chain: body blockquote (unconditional) + `addBlockedByDependency` GraphQL (best-effort) + parent annotation (if `--parent` co-used) |
| `--bundle-mode ordered \| unordered` | Create an epic + N children; `ordered` also wires a Blocked-by chain. Mutually exclusive with group mode. |
| `--mention login[,login2,...]` | Force the 5-step collaborator-tagging protocol ([`rules/tagging-collaborators.md`](../plugins/issue-driven-dev/rules/tagging-collaborators.md)); cannot fail open. |

**Decision points (AskUserQuestion branches)**:

| Trigger | Question |
|---|---|
| Fork detected, no config yet | Upstream / Own fork / Both (cross-linked) |
| Content predicate matches a different candidate than the path-resolved one | "Title matches X better than Y — switch?" |
| `ask_each_time: true` + multiple candidates/groups | Pick which candidate or group |
| Step 4.7 linked-context sibling-concern markers in body draft | File all / file selected / skip (IC_R011 pattern) |
| Source is `.docx` / Telegram / Apple Mail / Apple Notes and the MCP plugin is missing | (no question — fail-fast with structured install message) |

**Workflow position**: Phase 1 entry. Issue must exist before any of diagnose / plan / implement.

**Spec**: [`skills/idd-issue/SKILL.md`](../plugins/issue-driven-dev/skills/idd-issue/SKILL.md) · [`references/bundle-flags.md`](../plugins/issue-driven-dev/references/bundle-flags.md) · [`rules/tagging-collaborators.md`](../plugins/issue-driven-dev/rules/tagging-collaborators.md)

---

### `/idd-comment`

**Goal**: Add a template-guided comment to a GitHub issue. Forces blockquote for quoted source text, timestamp, and a metadata marker so the comment is machine-recognisable later.

**Syntax**: `/idd-comment #N [#N ...] --type=<type> [options]`

**Options — `--type`** (mandatory, 6 types):

| Type | Use |
|---|---|
| `decision` | Record a user / team decision (with rationale) |
| `note` | Plain context / status note (no decision implied) |
| `question` | Open question for the issue author / others |
| `correction` | Mark a previous claim wrong + correction |
| `link` | External context (URL, related issue, gist) |
| `errata` | Errata about a prior comment in the same issue |

**Other options**:

| Flag | Effect |
|---|---|
| `--body '...'` | Free-text body; appended under the type-specific template heading |
| `--quote 'text'` | Source quote — forced into blockquote, marked as quoted text |
| `--quote-source 'where'` | Attribution for the quote |
| `#N #N #N` (batch mode, v2.34.0+) | Same comment goes to each issue (3 `gh issue comment` calls, one master report) |

**Workflow position**: Side-quest, any phase. Use when a real-time decision / context fact deserves the audit trail but doesn't merit a new issue.

**Spec**: [`skills/idd-comment/SKILL.md`](../plugins/issue-driven-dev/skills/idd-comment/SKILL.md)

---

### `/idd-edit`

**Goal**: Edit an existing GitHub comment. Always shows the original body + preview the new body for confirmation. Uses `gh api -F body=@file` to side-step the well-known backtick / `$()` escape bugs of inline `--body`.

**Syntax**: `/idd-edit comment:<id>[ comment:<id>...] | #issue --last [--append | --replace | --prepend-note] [--body="..."]`

**Options**:

| Flag | Effect |
|---|---|
| `comment:<id>` | Target the specific comment id (`gh api /repos/.../issues/comments/<id>`); multi-id form = batch (each gets per-confirm) |
| `#N --last` | Shortcut: target the most recent comment on issue #N |
| `--append` (default if `--body` given without explicit mode) | Append to existing body |
| `--replace` | Replace entire body — original is printed beforehand for confirmation |
| `--prepend-note` | Add a marked note block at the top (e.g., "Errata: see comment #M") |
| `--body "..."` | New body / appended chunk |

**Workflow position**: any phase. Common: explain figure under a comment, fix typo, mark a stale comment with an errata pointer.

**Spec**: [`skills/idd-edit/SKILL.md`](../plugins/issue-driven-dev/skills/idd-edit/SKILL.md)

---

## Phase 2 — Triage / planning

### `/idd-diagnose`

**Goal**: RCA for bugs, requirements decomposition for features, current-state analysis for refactors. Produces a Diagnosis comment posted on the issue, **with a Complexity verdict** that routes the next step (`Simple` → `/idd-implement`; `Plan` → `/idd-plan`; `Spectra` → `/spectra-discuss`). Includes Layer V (vagueness) pre-check and IC_R011 sister-concern surfacing.

**Syntax**: `/idd-diagnose #N [#N ...] [--cwd /path/to/clone]`

**Options**:

| Flag | Effect |
|---|---|
| `#N` (positional) | Issue to diagnose; multiple `#N` = batch mode (sequential, per-issue diagnosis comment + auto-update) |
| `--cwd /path/to/clone` | Run all `git` / `gh` against the given local clone (cross-repo support, v2.40.0+) |

**Decision points**:

| Stage | Question |
|---|---|
| Step 3.4 Layer V vagueness | `max(V1,V4)` axis-score ≥ 4 → 3-option Hybrid: `clarify now` / `proceed anyway` / `escalate to Plan` (default-option re-ordered by score) |
| Step 3.6 IC_R011 sister-concern surfacing | `file all` / `file selected` / `skip` |

**Complexity verdict (Step 3.5, written to `### Complexity` of the Diagnosis comment)**:

| Verdict | Next step | Why |
|---|---|---|
| `Simple` | `/idd-implement #N` | Clear root cause, single file, follow existing pattern, narrative / one-shot script |
| `Plan` (incl. `Plan via Layer V`) | `/idd-plan #N` | 2+ interdependent files / 5+ ordered steps / decision-heavy / risk-sensitive boundary, no published API contract |
| `Spectra` (alias `SDD-warranted`) | `/spectra-discuss` then `propose` → `apply` | Published API / protocol / skill / tool contract for future callers; needs frozen spec |

**Workflow position**: directly after `/idd-issue`, before `/idd-implement` / `/idd-plan`.

**Spec**: [`skills/idd-diagnose/SKILL.md`](../plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md) · [`rules/sdd-integration.md`](../plugins/issue-driven-dev/rules/sdd-integration.md) · [`references/ic-r011-checkpoint.md`](../plugins/issue-driven-dev/references/ic-r011-checkpoint.md)

---

### `/idd-plan`

**Goal**: Plan-tier deliberation. Drafts a richer Implementation Plan (files + reasoning + sequencing + risks + test plan + out-of-scope), posts it to the issue, then enters Claude Plan Mode (`EnterPlanMode`) so the user has a hard read-only approval gate before TDD. On approval, chains to `/idd-implement`.

**Syntax**: `/idd-plan #N [--pr | --no-pr] [--cwd ...]`

**Options**:

| Flag | Effect |
|---|---|
| `#N` | Issue (single — Plan tier is per-issue, no batch) |
| `--pr` / `--no-pr` | PR path override forwarded to `/idd-implement` after approval (same precedence chain as that skill) |
| `--cwd /path/to/clone` | Cross-repo |

**Decision points**:

| Stage | Question |
|---|---|
| `EnterPlanMode` review | Approve (→ TDD) / Revise (with feedback; plan is PATCHed and we re-enter plan mode) / Abort (→ `/idd-update` phase = `needs-fix`, stop) |
| Step 2.5 mid-plan tangential observations | `file all` / `file selected` / `skip` (IC_R011) |
| Complexity is `Simple` | Confirm "you really want the extra approval gate?" |
| Complexity is `Spectra` | Warn "you should be in `/spectra-discuss`" + confirm or abort |

**Workflow position**: between `/idd-diagnose` (Complexity = Plan) and `/idd-implement`. Skipped for Simple. Spectra changes go through `/spectra-*` instead.

**Spec**: [`skills/idd-plan/SKILL.md`](../plugins/issue-driven-dev/skills/idd-plan/SKILL.md)

---

### `/idd-route-recommend`

**Goal**: Ask the `idd-route` binary which agent (Codex GPT-5.5 xhigh / Claude Opus 4.7 / Sonnet 4.6 / Haiku 4.5) to use for an issue. Reads `routing-stats.jsonl`, buckets by `(complexity, scope_class)`. Falls back to static heuristic when bucket has < 5 data points (exit code 3).

**Syntax**: `/idd-route-recommend <repo-path> <complexity> <scope-loc-estimate> --signals s1,s2[,...] [--candidates c1,c2,...]`

**Options**:

| Arg | Effect |
|---|---|
| `<repo-path>` (positional) | Absolute path to repo; `realpath` is applied |
| `<complexity>` (positional) | `Simple` / `Plan` / `Spectra` (matches diagnose verdict tokens) |
| `<scope-loc-estimate>` (positional) | Integer LOC estimate (used to pick `scope_class` bucket) |
| `--signals s1,s2,...` | Signal tokens from [`signal-vocabulary.md`](../plugins/idd-route/references/signal-vocabulary.md) (e.g. `migration`, `cross-spec`, `refactor`) |
| `--candidates c1,c2,...` | Restrict candidates (default: all four agents) |

**Workflow position**: optional helper, run after `/idd-diagnose` if you want a data-driven agent pick rather than the default routing.

**Spec**: [`skills/idd-route-recommend/SKILL.md`](../plugins/idd-route/skills/idd-route-recommend/SKILL.md)

---

### `/idd-route-stats`

**Goal**: Human-readable markdown summary of `routing-stats.jsonl` — two tables, by-agent (totals) and by `(agent × complexity × scope_class)` bucket.

**Syntax**: `/idd-route-stats <repo-path> [--decay-half-life-days 30]`

**Options**:

| Arg | Effect |
|---|---|
| `<repo-path>` (positional) | Repo whose `.claude/idd-route/routing-stats.jsonl` to read |
| `--decay-half-life-days N` | Apply exponential decay so old outcomes weigh less (default = no decay) |

**Workflow position**: ad-hoc inspection — debug why a recommendation is what it is, sanity-check what got recorded.

**Spec**: [`skills/idd-route-stats/SKILL.md`](../plugins/idd-route/skills/idd-route-stats/SKILL.md)

---

### `/idd-route-backfill`

**Goal**: One-shot seed of `routing-stats.jsonl` from historical verify comments — parses `(agent, complexity, blocking findings, round_trips)` out of past GH verify comments and writes them as past outcomes. The cold-start cure.

**Syntax**: `/idd-route-backfill <owner/repo> <repo-path> [--since YYYY-MM-DD]`

**Options**:

| Arg | Effect |
|---|---|
| `<owner/repo>` | GitHub repo to scrape |
| `<repo-path>` | Local repo where stats file lives |
| `--since YYYY-MM-DD` | Lower bound on comment date (default = unbounded) |

**Workflow position**: run once after installing `idd-route` on a repo with existing verify history.

**Spec**: [`skills/idd-route-backfill/SKILL.md`](../plugins/idd-route/skills/idd-route-backfill/SKILL.md)

---

## Phase 3 — Implementation

### `/idd-implement`

**Goal**: TDD-disciplined implementation of the diagnosed strategy. Scope guard rejects unrelated drift. Every commit references `#NNN`. Strategy-level TaskList tracks each `- [ ]` from the Implementation Plan; `/idd-close` later refuses to close with unchecked items.

**Syntax**: `/idd-implement #N [#N ...] [--pr | --no-pr] [--cwd ...] [--with-skill <skill>] [--extra '<requirement>']`

**Options**:

| Flag | Effect |
|---|---|
| `#N` (positional, single or multi) | Single = standard mode. Multi (`#34 #36 #38`) = **cluster-PR mode**: 1 branch + 1 PR + per-issue `Refs #N` commits; **forces PR path** (does **not** accept `--no-pr`). See [#96](https://github.com/PsychQuant/issue-driven-development/issues/96) for the pending design question. |
| `--pr` | Force PR path: feature branch `idd/<N>-<slug>` (or `idd/cluster-<slug>` for clusters), push, `gh pr create` |
| `--no-pr` | Force direct-commit to current branch. **Ignored / rejected in cluster mode.** |
| `--cwd /path/to/clone` | Cross-repo (per [`cross-repo-cwd.md`](../plugins/issue-driven-dev/references/cross-repo-cwd.md)) |
| `--with-skill <skill>` | GREEN phase calls `Skill(skill=<skill>, args=...)` instead of direct Edit. Typical: `perspective-writer` for prose deliverables. Auto-detected from diagnosis "透過 X" / "via X" / "使用 X-skill" patterns. |
| `--extra '<text>'` | Free-text extra requirement appended to the Implementation Plan (e.g., `'500–800 字、避免 em dash'`) |

**PR-path resolution chain** (see [`references/pr-flow.md`](../plugins/issue-driven-dev/references/pr-flow.md)):

```
1. --pr flag                    → PR
2. --no-pr flag                 → direct-commit
3. gh repo view --json isFork   → fork ⇒ PR (forced; prints notice)
4. pr_policy = "always"         → PR
5. pr_policy = "never"          → direct-commit
6. pr_policy = "ask" / absent   → AskUserQuestion ("Open a PR for #N?")
```

(Cluster carve-out overrides 1–6 → PR; this is the documented-conflict from #96.)

**Decision points**:

| Stage | Question |
|---|---|
| Phase 0.5 + `pr_policy:ask` (or no flag, no fork) | `Open a PR for #N?` — PR path / Direct-commit |
| Step 2.5 Complexity routing | (read-only routing; no question — Plan tier should already have run via `/idd-plan`) |
| Step 5.7 sister-bug sweep (IC_R011) | `file all` / `file selected` / `skip` |

**Workflow position**: after diagnose (Simple) or after plan approval (Plan). Spectra changes don't come here — they go through `/spectra-apply`.

**Spec**: [`skills/idd-implement/SKILL.md`](../plugins/issue-driven-dev/skills/idd-implement/SKILL.md) · [`references/pr-flow.md`](../plugins/issue-driven-dev/references/pr-flow.md) · [`references/batch-and-cluster.md`](../plugins/issue-driven-dev/references/batch-and-cluster.md)

---

## Phase 4 — Verification

### `/idd-verify`

**Goal**: Cross-AI verification of code changes against the issue's stated requirements. **6 reviewers**: 5 parallel `Agent(subagent_type=general-purpose)` (Requirements / Logic / Security / Regression / Devil's Advocate) + 1 background Codex CLI (gpt-5.5 xhigh). They cannot see each other's findings. Master + pointer comment SOP.

**Syntax**: `/idd-verify [#N [#N ...]] [engine] [--loop] [--pr N] [--commits N] [--branch X] [--since REF] [--cwd ...]`

**Options — engine**:

| Engine | Effect |
|---|---|
| _(default)_ | 5 Claude reviewers + Codex (full ensemble) |
| `codex` | Codex CLI only |
| `team` (legacy alias) | 5 Claude reviewers only, no Codex |

**Options — input source** (mutually exclusive; auto-detect if all absent):

| Flag | Effect |
|---|---|
| `--pr <N>` | PR mode — `gh pr diff N` is the source, master comment lands on the PR, pointer comments on each ref'd issue. Step 0.7 enforces issue ↔ PR Refs correspondence. Step 0.8 also flags PR's own `closingIssuesReferences` (auto-close-trap gate). |
| `--commits <N>` | Local mode — `HEAD~N..HEAD` |
| `--since <ref>` | Local mode — `<ref>..HEAD` |
| `--branch <name>` | Branch mode — `origin/<default>...<name>` (committed but no PR yet) |
| _(none)_ | Auto-detect: count `Refs #N` commits since default; if 0, check open PRs and AskUserQuestion |

**Options — other**:

| Flag | Effect |
|---|---|
| `#N` (positional, single or multi) | Issues being verified. Multiple = **cluster verify mode** (v2.34.0+): findings rendered per-issue, aggregate verdict applies to PR overall. |
| `--loop` | Wrap verify-then-fix iteration in a ralph-loop driver (see [#ralph-loop](#ralph-loop)) |
| `--cwd /path/to/clone` | Cross-repo |

**Recovery protocol** (v2.59.0+, #52 / Step 2.5): if any of the 5 Claude reviewers fails to write `/tmp/verify_<N>_findings_<role>.md`:
1. **2.5a** file-existence check — Devil's Advocate sentinel `[STAGE 2.5 RECOVERY: DEVILS_ADVOCATE_TIMEOUT_<r>/4]` is deleted before re-evaluation.
2. **2.5b retry** — `SendMessage` retry with the **full prompt re-pasted** (assumes context lost across idle/wake).
3. **2.5c fallback** — coordinator self-review for that role, master report flags the process gap.

**Decision points**:

| Stage | Question |
|---|---|
| Step 0.5 auto-detect with 1 open PR | "Verify PR #X or local diff?" |
| Step 0.5 auto-detect with 2+ open PRs | Pick one |
| Step 0.7 PR has refs the user didn't pass | "Also verify those refs, or scope to your list?" |

**Workflow position**: after implement, before close. Required gate.

**Spec**: [`skills/idd-verify/SKILL.md`](../plugins/issue-driven-dev/skills/idd-verify/SKILL.md) · [`references/external-agent-delegation.md`](../plugins/issue-driven-dev/references/external-agent-delegation.md)

---

## Phase 5 — Closure

### `/idd-close`

**Goal**: Write the closing summary, then close the issue. Refuses to close if the Implementation Complete checklist has unticked `- [ ]` items. For cluster-PR closures, writes per-issue closing summaries (no merged superblob).

**Syntax**: `/idd-close #N [#N ...]`

**Options**:

| Flag | Effect |
|---|---|
| `#N` | Issue(s) to close. Multi-`#N` = cluster close: PR must be merged; each issue gets its own closing summary derived from `git log --grep "#N"` on the PR commit range. |

**Decision points**:

| Stage | Question |
|---|---|
| Step 1.6 — auto-close was honoured by GitHub on merge | "Should I still post the closing summary?" (default yes) |
| Unchecked `- [ ]` items remain | (no question — refuses with the list of unchecked items) |

**Workflow position**: last step in the standard IDD pipeline. Spectra changes additionally chain through `/spectra-archive`.

**Spec**: [`skills/idd-close/SKILL.md`](../plugins/issue-driven-dev/skills/idd-close/SKILL.md)

---

### `/idd-update`

**Goal**: Sync the `Current Status` block in the issue body to reflect actual phase (`unprocessed` / `diagnosed` / `planning` / `implemented` / `verified` / `closed`). Preserves the original `Problem` / `Type` / `Expected` / `Actual` body. Most other `idd-*` skills auto-call this; manual invocation is for re-sync after manual GH edits.

**Syntax**: `/idd-update #N [#N ...]`

**Options**:

| Flag | Effect |
|---|---|
| `#N` (single or multi) | Batch = sequential sync; idempotent. |

**Workflow position**: auto, end of each phase-changing skill. Manual when needed.

**Spec**: [`skills/idd-update/SKILL.md`](../plugins/issue-driven-dev/skills/idd-update/SKILL.md)

---

### `/idd-report`

**Goal**: Aggregate progress report to GitHub Discussions — pulls phase + key comments per issue in scope and renders a single roll-up post (milestone review, sprint summary, client / supervisor update).

**Syntax**: `/idd-report #N [#N ...] | source:<file> | milestone:<name> [@tag1 @tag2 ...]`

**Options**:

| Form | Effect |
|---|---|
| `#157 #158 ...` | Explicit issue list |
| `source:<file>` | All issues whose body cites the given source file path |
| `milestone:<name>` | All issues in the milestone |
| `@tag1 @tag2` | Discussion category tags |

**Workflow position**: not tied to any single issue lifecycle — fires at sprint / milestone boundaries.

**Spec**: [`skills/idd-report/SKILL.md`](../plugins/issue-driven-dev/skills/idd-report/SKILL.md)

---

## Orchestration

### `/idd-all`

**Goal**: Run the entire pipeline (issue → diagnose → plan-or-direct → implement → verify) in one call. Resolves a `(path, interaction)` tuple from `pr_policy` so the same `pr_policy:never` user gets `(direct-commit, attended)` (HITL — sub-skills are free to AskUserQuestion) and `pr_policy:always` user gets `(PR, unattended)` (automation-friendly; sub-skills suppress AskUserQuestion). Stops at `verified` — **never auto-closes**.

**Syntax**: `/idd-all [#N | 'issue description'] [--pr | --no-pr] [--cwd ...]`

**Options**:

| Flag | Effect |
|---|---|
| `#N` | Skip Phase 1 (issue already exists) and resume from diagnose |
| `'description'` | Phase 1 creates the issue from this description first |
| _(empty)_ | Interactive — prompt for what to work on |
| `--pr` | `(PR, unattended)` |
| `--no-pr` | `(direct-commit, attended)` |
| `--cwd /path/to/clone` | Cross-repo |

**Path × interaction tuple matrix** (see [`references/pr-flow.md`](../plugins/issue-driven-dev/references/pr-flow.md) §idd-all path resolution):

| Precedence | Outcome | Note |
|---|---|---|
| `--pr` | `(PR, unattended)` | Per-invocation flag |
| `--no-pr` | `(direct-commit, attended)` | Per-invocation flag |
| Fork detected | `(PR, unattended)` | Overrides `pr_policy:never` |
| `pr_policy: always` | `(PR, unattended)` | Config |
| `pr_policy: never` | `(direct-commit, attended)` | Config |
| `pr_policy: ask` (explicit) | first answer locks both axes | AskUserQuestion |
| `pr_policy` absent | `(PR, unattended)` | v2.40 default — `/loop` callers never hang |

**Workflow position**: replaces manually firing each of the 5 skills. Stops at `verified`; user runs `/idd-close` themselves.

**Spec**: [`skills/idd-all/SKILL.md`](../plugins/issue-driven-dev/skills/idd-all/SKILL.md)

---

### `/idd-all-chain`

**Goal**: Recursive `/idd-all` over a **root issue + all auto-emergent spawned issues** (sister bugs, follow-up findings, tangential observations, sister concerns surfaced by IC_R011 checkpoints). One cluster branch + one review PR. Spawn manifest tracks chain eligibility.

**Syntax**: `/idd-all-chain [#N] [--cwd ...]`

**Options**:

| Flag | Effect |
|---|---|
| `#N` | Root issue (chain seeded from here) |
| `--cwd /path/to/clone` | Cross-repo |

**Spawn sources tracked**:

| Source | Origin |
|---|---|
| `sister-bug` | `/idd-implement` Step 5.7 mid-implementation reproduction sweep |
| `follow-up-finding` | `/idd-verify` Step 5b post-verify triage |
| `tangential` | `/idd-plan` Step 2.5 mid-plan deliberation |
| `sister-concern` | `/idd-diagnose` Step 3.6 mid-diagnosis surfacing |

See [`references/spawn-manifest.md`](../plugins/issue-driven-dev/references/spawn-manifest.md) for the manifest contract.

**Workflow position**: alternative to `/idd-all` when the work is expected to ripple into adjacent issues. Stops at `verified` per child issue; per-issue `/idd-close` still required.

**Spec**: [`skills/idd-all-chain/SKILL.md`](../plugins/issue-driven-dev/skills/idd-all-chain/SKILL.md)

---

## Built-in autonomous loops (Claude Code native)

> These are **Claude Code built-ins** (require minimum versions noted below). Three approaches keep a session running between prompts; pick by **what should start the next turn**:

| Approach | Next turn starts when | Stops when |
|----------|---------------------|-----------|
| [`/goal`](#goal) | The previous turn finishes | A small fast model confirms the condition is met |
| [`/loop`](#loop) | A time interval elapses (or self-paced) | You press `Esc`, or Claude decides work is done (self-paced only) |
| Stop hook | The previous turn finishes | Your own script or prompt decides |
| [`ralph-loop`](#ralph-loop) (plugin) | The previous turn finishes | `--completion-promise` substring detected, or `--max-iterations` hit |

For IDD workflows specifically: `/idd-verify --loop` and `/idd-all` `(PR, unattended)` historically called `ralph-loop`. With native `/goal` available, you can do the same thing with `/goal idd-verify --pr 94 exits PASS` — no plugin needed.

---

### `/goal`

**Goal**: Set a completion condition; Claude keeps working across turns until a small fast model (defaults to Haiku) confirms the condition holds. Goal clears automatically once met. One goal per session.

**Requires**: Claude Code v2.1.139+. Workspace trust dialog accepted (because the evaluator is a Stop hook). Unavailable when `disableAllHooks` set or `allowManagedHooksOnly` set in managed settings.

**Syntax**: `/goal [condition | clear]`

**Options**:

| Form | Effect |
|---|---|
| `/goal <condition>` | Set the condition (up to 4,000 chars) and **immediately start a turn** with the condition as the directive. If a goal is already active, the new one replaces it. While active, a `◎ /goal active` indicator shows runtime. |
| `/goal` (no args) | Show current status — condition, runtime, turns evaluated, token spend, evaluator's most recent reason. If no goal active but one was achieved earlier in the session, shows that achieved entry. |
| `/goal clear` | Remove active goal early. Aliases: `stop`, `off`, `reset`, `none`, `cancel`. Running `/clear` (new conversation) also removes any active goal. |

**Writing an effective condition** — the evaluator judges against **what Claude has surfaced in the conversation** (it cannot call tools itself). A good condition has:
- One measurable end state (test result, build exit code, file count, empty queue)
- A stated check (how Claude should prove it — `npm test` exits 0, `git status` clean, etc.)
- Constraints that matter (e.g., "no other test file is modified")
- Optionally a turn / time bound (`or stop after 20 turns`)

**Resume behaviour**: a goal active when the session ended is restored on `--resume` / `--continue`. Condition carries over but turn count, timer, and token-spend baseline reset. Achieved or cleared goals are not restored.

**Non-interactive**:

```bash
claude -p "/goal CHANGELOG.md has an entry for every PR merged this week"
```

Runs the loop to completion in one invocation. Interrupt with `Ctrl+C`.

**IDD workflow integration**:

```text
/goal /idd-verify --pr 94 reports PASS and /idd-close #87 #74 has been executed
```

Conditions for typical IDD goals:
- `/goal /idd-verify #42 reports PASS` — drive verify-fix until clean
- `/goal cluster #87 #74 reaches verified phase` — drive a cluster through pipeline
- `/goal /idd-all-chain #28 stops at verified for all children` — drive chain mode

**Workflow position**: alternative to `ralph-loop` for any IDD `--loop` style integration. Use when there's a clear verifiable end state.

**Spec**: <https://code.claude.com/docs/en/goal>

---

### `/loop`

**Goal**: Re-run a prompt on a schedule (bundled skill). Both interval and prompt are optional — what you provide determines behaviour. Session-scoped; tasks fire only while Claude Code is running and idle. Recurring tasks expire 7 days after creation.

**Requires**: Claude Code v2.1.72+.

**Syntax**: `/loop [INTERVAL] [PROMPT]`

**Options — what you provide**:

| Input | Example | Behaviour |
|---|---|---|
| Interval + prompt | `/loop 5m check if the deploy finished` | Runs on a fixed cron schedule |
| Prompt only | `/loop check whether CI passed and address review comments` | **Self-paced** — Claude picks delay 1m–1h based on observed state; may use the `Monitor` tool to stream events instead of polling |
| Interval only, or nothing | `/loop` or `/loop 15m` | Runs the **built-in maintenance prompt**: continue unfinished work → tend current branch's PR → run cleanup passes (e.g., bug hunts) |
| Another command as prompt | `/loop 20m /review-pr 1234` | Re-runs a packaged workflow each iteration |

**Interval forms**:
- Bare token leading the prompt: `30m check ...`
- Trailing clause: `check ... every 2 hours`
- Units: `s` (rounded up to 1m), `m`, `h`, `d`
- Non-clean cron steps (`7m`, `90m`) are rounded to the nearest valid step; Claude reports what it picked

**Stopping**: press `Esc` while the loop waits for the next iteration. Self-paced loops can also self-terminate. Fixed-interval loops keep running until you stop them or 7 days elapse.

**`loop.md` customization** — replace the built-in maintenance prompt:
- `.claude/loop.md` (project, takes precedence)
- `~/.claude/loop.md` (user-level fallback)
- Plain Markdown, no required structure, applies to bare `/loop` (ignored when you supply a prompt). Max 25,000 bytes (truncated beyond).

**Underlying tools** (when you ask "what scheduled tasks do I have?" / "cancel job X"):

| Tool | Purpose |
|---|---|
| `CronCreate` | Schedule a task (5-field cron expression, prompt, recur/once) |
| `CronList` | List all scheduled tasks with IDs |
| `CronDelete` | Cancel a task by 8-char ID |

Session holds up to 50 scheduled tasks. Times are local timezone. Recurring tasks have jitter (up to 30min after scheduled, or up to half-interval for sub-hourly tasks); one-shot at `:00`/`:30` may fire up to 90s early. Pick `:03` instead of `:00` to skip jitter when timing matters.

**Disable**: `CLAUDE_CODE_DISABLE_CRON=1` env var disables the scheduler entirely.

**IDD workflow integration**:

```text
/loop 10m check if PR #94 CI passed
/loop 30m /idd-list --label needs-attention
```

**Workflow position**: useful for polling external state (CI, PRs, deploys) during a session. **For drive-to-condition (the classic IDD `--loop` use case), prefer `/goal`** — `/loop` polls on a clock, `/goal` polls on a condition.

**Spec**: <https://code.claude.com/docs/en/scheduled-tasks>

---

## External: `ralph-loop` (legacy)

> External plugin (`ralph-loop@claude-plugins-official`, v1.0.0). **Largely superseded by built-in `/goal` and `/loop`** as of Claude Code 2.1.x. Listed for completeness — older IDD docs reference it, and `idd-verify --loop` / `idd-all` `(PR, unattended)` still wire it up. New work should default to `/goal`.

### `/ralph-loop`

**Goal**: Spawn an outer loop that keeps re-issuing a prompt until either (a) the completion-promise is detected in the assistant output or (b) `--max-iterations` is hit. Survives idle / wake cycles. The state file is `.claude/ralph-loop.local.md`.

**Syntax**: `/ralph-loop PROMPT [--max-iterations N] [--completion-promise TEXT]`

**Options**:

| Flag | Effect |
|---|---|
| `PROMPT` (positional, required) | What the inner agent should attempt each iteration |
| `--max-iterations N` | Hard cap on iterations (default = generous; depends on plugin version) |
| `--completion-promise TEXT` | Stop when assistant output contains this substring — used by IDD as the `verified` sentinel for `--loop` |

**Workflow position**: invoked manually for arbitrary loop-driven workflows; auto-invoked by `/idd-verify --loop` and `/idd-all` when `(PR, unattended)`.

**Spec**: `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/ralph-loop/commands/ralph-loop.md`

---

### `/cancel-ralph`

**Goal**: Cancel the active Ralph Loop by deleting `.claude/ralph-loop.local.md`.

**Syntax**: `/cancel-ralph` (no args)

**Spec**: `~/.claude/plugins/marketplaces/claude-plugins-official/plugins/ralph-loop/commands/cancel-ralph.md`

---

### `/help` (within ralph-loop)

**Goal**: Inline help. (Mentioned for completeness; usually shadowed by Claude Code's own `/help`.)

---

## Cross-cutting references

| Topic | Reference |
|---|---|
| Target-repo resolution (6-mechanism algorithm) | [`references/config-protocol.md`](../plugins/issue-driven-dev/references/config-protocol.md) |
| Attachment handling rule (download / parse) | [`rules/process-attachments.md`](../plugins/issue-driven-dev/rules/process-attachments.md) |
| Collaborator tagging 5-step protocol | [`rules/tagging-collaborators.md`](../plugins/issue-driven-dev/rules/tagging-collaborators.md) |
| Cross-repo `--cwd` substitution rules | [`references/cross-repo-cwd.md`](../plugins/issue-driven-dev/references/cross-repo-cwd.md) |
| PR vs direct-commit path resolution | [`references/pr-flow.md`](../plugins/issue-driven-dev/references/pr-flow.md) |
| Batch vs cluster contract | [`references/batch-and-cluster.md`](../plugins/issue-driven-dev/references/batch-and-cluster.md) |
| `--parent` / `--blocked-by` / `--bundle-mode` flags | [`references/bundle-flags.md`](../plugins/issue-driven-dev/references/bundle-flags.md) |
| External-agent (PR-mode) verify contract | [`references/external-agent-delegation.md`](../plugins/issue-driven-dev/references/external-agent-delegation.md) |
| Spectra (`/spectra-*`) bridge into IDD | [`rules/spectra-bridge.md`](../plugins/issue-driven-dev/rules/spectra-bridge.md) |
| Complexity verdict gating (Simple / Plan / Spectra) | [`rules/sdd-integration.md`](../plugins/issue-driven-dev/rules/sdd-integration.md) |
| IC_R011 commercial low-bar checkpoint pattern | [`references/ic-r011-checkpoint.md`](../plugins/issue-driven-dev/references/ic-r011-checkpoint.md) |
| Spawn manifest (chain-mode enqueue contract) | [`references/spawn-manifest.md`](../plugins/issue-driven-dev/references/spawn-manifest.md) |
| Vagueness Likert scoring (Layer V anchors) | [`.claude/rules/attribute-assessment.md`](../.claude/rules/attribute-assessment.md) |
| GitHub markdown math format rule | [`rules/github-math-format.md`](../plugins/issue-driven-dev/rules/github-math-format.md) |
