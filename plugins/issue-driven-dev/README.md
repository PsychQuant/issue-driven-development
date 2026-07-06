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
| `idd-clarify` | **Terminology / Semantic accuracy axis** (v2.72.0+, [#135](https://github.com/PsychQuant/issue-driven-development/issues/135)) — surfacing-only primitive that scans issue body for terminology mismatches / ambiguity / missing-context gaps, annotates via `### Clarity Surface` block. Standalone runnable for retroactive audit; delegated by `idd-issue` Step 4.6; gated by `idd-diagnose` Step 0.5. Third axis alongside IC_R010 Confidence + IC_R007 Verbatim. |
| `idd-comment` / `idd-edit` | Add or amend issue comments with template guidance (decision / note / question) |
| `idd-list` / `idd-update` / `idd-report` | List open issues by phase, sync issue body, generate progress reports |
| `idd-config` | Manage `.claude/issue-driven-dev.local.json` lifecycle: `show` / `init` / `validate` / `which` (v2.31.0) |
| `idd-all` | Orchestrator that drives the full pipeline (issue → close) end-to-end (v2.26.0; v2.28.0 unattended SDD chain) |
| `idd-all-chain` | **Chain-solve mode** (v2.55.0+ single-root, v2.60.0+ multi-root + DFS/BFS) — root issue(s) + auto-emergent spawned issues (sister bug / verify follow-up / mid-plan tangential / sister concern) through ONE cluster branch + ONE review PR. Thin recursive shell over `idd-all` using `--in-chain` flag (4th mode tuple `(direct-commit, unattended)`). Multi-root invocation `#A #B #C` with `--bfs` opt-in (default DFS). Hard caps: per-root depth=3, global max-issues=10 (v2.60.0+, was 2/5). Eligibility: same-file OR same-skill OR sister-bug. Verify FAIL = per-root halt (other root subtrees continue). STOPs at verified — never auto-close |

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
| v2.72.0 | 2026-05-22 | **`/idd-clarify` skill — Terminology / Semantic accuracy quality axis** ([#135](https://github.com/PsychQuant/issue-driven-development/issues/135), `add-idd-clarify-skill` Spectra change). NEW composable primitive surfacing-only that scans existing issue body for terminology mismatches (per `references/terminology-canonical.md` library) / ambiguity / missing-context gaps; annotates via `### Clarity Surface` block with status (surfaced / dismissed / resolved). Standalone runnable for retroactive audit + delegated by `idd-issue` Step 4.6 (between Step 4.5 Milestone and Step 4.7 Sister Sweep, skip in `--multi-finding` mode) + gated by `idd-diagnose` Step 0.5 (hard refuse on unresolved rows, per `idd-close` PR Gate Check + `idd-all-chain` #119 fail-fast precedents). Library initial seed 6 rows (K-means 特徵值→分群變數 / PCA-K-means / regression-ANOVA / accuracy-RMSE / Bayesian-frequentist / unsupervised-classification) per #804 incident + 通用 ML/統計 misuse patterns. Rule-of-three promotion threshold for new rows + open PR contribution. Triggering case: QEF #804 K-means「特徵值」(eigenvalue) source term actually meant「分群變數 / distinguishing variable」(老師 LINE clarify);AI 沿用 source verbatim, spec 階段意外修對是運氣不是 systematic safeguard。Recursive evidence: 本 session AI 連 4 次 under-verification (D06 collision #815 / Step 4.8 collision / customer_attributes 來源未指定 / 三輪 design over-abstract) — codify 後 surface 給 user dismiss/resolve 不繼續犯。Sister concerns filed: [#136](https://github.com/PsychQuant/issue-driven-development/issues/136) idd-edit/idd-update symmetry P3 / [#137](https://github.com/PsychQuant/issue-driven-development/issues/137) unattended Clarity Surface contract P2 / [#138](https://github.com/PsychQuant/issue-driven-development/issues/138) ralph-loop → /goal substitution P3. |
| v2.56.0 – v2.71.0 | 2026-05-10 – 2026-05-21 | Multi-finding source mode, chain-solve hardening, auto-close-trap defence, cluster mode override, Simple-cluster docs batch, NSQL conformance, acceptance-review doctrine, NSQL doctrine follow-up family, multi-finding spec hardening from #48 verify, Phase 0.4 detection precision sweep from #53 verify, DA sentinel regex + CRLF normalization, spectra-archive sync + cluster glob + pasted-image cache. **v2.56.0**: `idd-issue` multi-finding source mode — auto-trigger on ≥2 paragraph-level findings from docx/pdf/Telegram/Mail/Notes adapters, 4-stage extract→pick→preview→dispatch pipeline. **v2.57.0**: `idd-close` Step 6.5 Distribution Sync chain — detection-driven 3-option AskUserQuestion chaining to `plugin-update` / `mcp-deploy` / `cli-deploy` at close moment. **v2.58.0**: `idd-issue` Stage 4.5 jsonl gitignore pre-flight gate. **v2.59.0**: `idd-verify` orchestration playbook — Step 2 switches TeamCreate → 5 parallel `Agent` calls + Codex background; NEW Step 2.5 Recovery Protocol. **v2.60.0**: `idd-all-chain` multi-root + DFS/BFS traversal + per-root halt + spawn-manifest schema v2 ([#46](https://github.com/PsychQuant/issue-driven-development/issues/46)). **v2.60.1**: cluster fix — PR-body auto-close trap ([#87](https://github.com/PsychQuant/issue-driven-development/issues/87) + [#74](https://github.com/PsychQuant/issue-driven-development/issues/74)); 4 PR-body templates reworded digit-free + NEW `idd-verify` Step 0.8 preventive gate. **v2.61.0**: `idd-verify` Step 0.8 squash-commit-body auto-close trap fix ([#97](https://github.com/PsychQuant/issue-driven-development/issues/97)) — 2-source scan (PR body `closingIssuesReferences` + per-commit headline/body trap regex) + `### 引用 trap pattern 作反例的寫作紀律` writing discipline in CLAUDE.md. **v2.62.0**: cluster mode override ([#96](https://github.com/PsychQuant/issue-driven-development/issues/96)) — NEW `pr-flow.md` `### Cluster mode override` (cluster mode = `idd-implement` path-resolution precondition, forces PR; verify/close are cluster-aware but consume the path) + `idd-implement` Step 0.5 bash cluster detection with explicit override notice mirroring fork detection; resolves a 3-file doc contradiction. **v2.63.0**: #96-backlog Simple cluster — 6 docs/reference follow-ups shipped via cluster-PR [#101](https://github.com/PsychQuant/issue-driven-development/pull/101) ([#60](https://github.com/PsychQuant/issue-driven-development/issues/60) [#62](https://github.com/PsychQuant/issue-driven-development/issues/62) [#63](https://github.com/PsychQuant/issue-driven-development/issues/63) [#78](https://github.com/PsychQuant/issue-driven-development/issues/78) [#90](https://github.com/PsychQuant/issue-driven-development/issues/90) [#91](https://github.com/PsychQuant/issue-driven-development/issues/91)); Simple-tier subset of an 18-issue `/idd-diagnose` batch over the #96-backlog cleanup. **v2.64.0**: IDD human-in-the-loop reconciled to the NSQL confirmation protocol ([#103](https://github.com/PsychQuant/issue-driven-development/issues/103), PR [#104](https://github.com/PsychQuant/issue-driven-development/pull/104)). NSQL ([kiki830621/NSQL](https://github.com/kiki830621/NSQL) v4.1.0) is the Human-AI Confirmation Protocol registered as a reference project in `CLAUDE.md`. F1 — `idd-issue` Step 5 echoes the AI-rendered `## Type` / `## Expected` / `## Actual` + plain-language interpretation (NSQL `run → report`, not a confirm gate; creating an issue is reversible per v4.1.0). F2 — `idd-diagnose` Layer V `clarify now` renders candidate interpretations for the user to pick (NSQL P1 Read-Only for Humans), free-text named as fallback. F3 — Diagnosis report template gains `### Residue` section + explanatory paragraph (NSQL §4.6: non-operationalizable intent, distinct from Layer V vagueness; `(none)` empty-state required). F4 — Layer P `risk-sensitive boundary` adds `irreversible side effects` to its enumerated vocabulary (catches Telegram-send / Stripe-charge / webhook-fire / file-delete cases). Plan tier: Spectra → `/spectra-discuss` re-evaluated under v4.1.0 traceability gate, re-routed Plan via EnterPlanMode. 6-AI verify PASS (0 blocking, in-PR polish merged). 3 follow-ups filed: [#105](https://github.com/PsychQuant/issue-driven-development/issues/105) idd-close Residue acknowledgement, [#106](https://github.com/PsychQuant/issue-driven-development/issues/106) plugin.json description chain via plugin-update, [#107](https://github.com/PsychQuant/issue-driven-development/issues/107) idd-issue Step 5 echo CI/loop warning. **v2.65.0**: IDD acceptance-review reconciled as a **MANIFESTO doctrine + thin `--review` flag**, NOT a new mode-tuple axis ([#102](https://github.com/PsychQuant/issue-driven-development/issues/102), PR [#109](https://github.com/PsychQuant/issue-driven-development/pull/109)). `/spectra-discuss` killed Direction A (3-tuple `(path, interaction, acceptance)`) and most of Direction B (merge-time gate); re-routed Spectra → Plan. NEW MANIFESTO section `## Human-in-the-loop: IDD 即 NSQL Confirmation Protocol` formalises that IDD's human-in-the-loop is an NSQL Confirmation Protocol instance — human confirmation loop closes BEFORE execution (at `issue` + `idd-diagnose`); `idd-verify` is execution-fidelity, NOT a confirmation loop; **`verify-gated` is the named, sanctioned terminal default disposition** (one clean 6/6 verify PASS is sufficient). Verify-as-review reframe: 5 specialized adversarial agents + Codex on correctness exceed a single human merge reviewer's thoroughness; "AI verify PASS = no review" is a backwards read. `--review` is opt-in to re-open the confirmation loop (NOT a quality gate; per-invocation flag, NOT a standing config field). auto-merge legitimate under verify-gated PASS, justified by "verify is the gate" (not "merges are reversible"); guardrails mandatory; `auto-merge ≠ auto-close`; autopilot mechanics belong to [#37](https://github.com/PsychQuant/issue-driven-development/issues/37); doctrine explicitly forbids `/loop` / external CI callers from interpreting Phase 6 `verify-gated PASS` as `gh pr merge` authorization. **idd-all + idd-all-chain** Phase 6/4 terminal messaging dispatches on `$REVIEW_FLAG`: default `Verify: verify-gated PASS` + `Next: merge, then /idd-close`; `--review` `Verify: verify-gated PASS — awaiting human acceptance (re-opened confirmation loop per --review)`. Cluster PR body checklist conditional. `--review` orthogonal to `--pr`/`--no-pr`/`--in-chain`/`--bfs`/`--cwd`, messaging-only at orchestrator scope. **6-AI verify on PR #109** caught a HIGH blocking bug: `idd-all-chain` PR-body checklist initially used `${REVIEW_FLAG:+A}${REVIEW_FLAG:-B}` thinking it was a mutex — it is NOT (`${var:-word}` returns `$var` when set, not the alternative branch). 3 of 6 reviewers convergent (regression / DA / Codex); 3 missed it including logic which claimed bash-correct without empirically testing. Fixed in-PR (`dc61ffb`) with explicit `if/else` building `$REVIEW_CHECKLIST_LINE` before the heredoc. The catch itself dogfoods the doctrine being shipped: the adversarial + cross-model ensemble is the falsifiable check. Sister consistency family follow-up [#108](https://github.com/PsychQuant/issue-driven-development/issues/108) extended to 5-template + 3 satellite items (PR-body wording sync across `idd-implement` Step 5.5 + `idd-all` Phase 5 + `pr-flow.md` + `chain-flow.md` + Phase 4 stdout + `Trace 1` example + DA3 wording). **v2.66.0**: NSQL doctrine follow-up family from #102 / #103 close ([#105](https://github.com/PsychQuant/issue-driven-development/issues/105), [#107](https://github.com/PsychQuant/issue-driven-development/issues/107), [#108](https://github.com/PsychQuant/issue-driven-development/issues/108), PR [#110](https://github.com/PsychQuant/issue-driven-development/pull/110)). **#105** — `idd-close` Step 3.6 Residue Acknowledgement closes the `### Residue` write-only loop from v2.64.0 (#103 PR #104 DA finding D2 "latent capacity to drift into ritual filler with no consumer pressure"). NEW step reads latest Diagnosis comment's `### Residue` section, silent-skips on `(none)` / missing / pre-v2.64.0; non-empty fires 3-option AskUserQuestion (acknowledge / file follow-up / skip); audit-trail PATCH appends `### Residue Acknowledgement` to in-memory closing summary draft BEFORE Step 4 publish; SHOULD-tier non-blocking; `IDD_LOW_BAR_RESIDUE_ACK=false` rollback. **#107** — `idd-issue` Step 5 NEW ⚠ paragraph warns CI / `/loop` callers about the v2.64.0 echo expansion (metadata-only → rendered `## Type` / `## Expected` / `## Actual` + plain-language interpretation); near-verbatim per issue body with skill-internal `#107` self-reference + precedent parenthetical. **#108** — 5-template + 3-satellite consistency family closed. 4 PR-body templates synced to `Verify-gated` default wording across `idd-implement` Step 5.5:503 + `idd-all` Phase 5:755 + `pr-flow.md`:135 + `chain-flow.md`:254 (cluster variant); section heading `## Pending review` → `## Review status`. F3 satellite — `idd-all-chain` Phase 4 stdout dispatches via explicit `if/else` before heredoc (avoids `${VAR:-word}` mutex from PR #109 F1). Trace 1 example refresh with parallel `--review` variant. DA3 wording precision `messaging-only` → `orchestrator-scope messaging-only` in 3 sites (`idd-all` + `idd-all-chain` Phase 0 + MANIFESTO `--review` paragraph). Per Option A: `idd-implement` does NOT accept `--review`. Live spec `openspec/specs/idd-all-chain/spec.md:161` updated to match emission. 6-AI verify ensemble PASS post-fix (regression H1 spec drift + L1 off-by-2 line-number + L3 heading dissonance + Codex CHANGELOG accuracy nit all addressed in fix commit `6bae8e6`). Master verify: [PR #110 #issuecomment-4494037985](https://github.com/PsychQuant/issue-driven-development/pull/110#issuecomment-4494037985). Squash-merged as `cb19802`. **v2.67.0**: multi-finding spec hardening family from [#48](https://github.com/PsychQuant/issue-driven-development/issues/48)'s 6-AI verify ([#75](https://github.com/PsychQuant/issue-driven-development/issues/75) [#76](https://github.com/PsychQuant/issue-driven-development/issues/76) [#77](https://github.com/PsychQuant/issue-driven-development/issues/77) [#79](https://github.com/PsychQuant/issue-driven-development/issues/79) [#80](https://github.com/PsychQuant/issue-driven-development/issues/80), PR [#113](https://github.com/PsychQuant/issue-driven-development/pull/113)). 5 sister bugs all same-file (`skills/idd-issue/SKILL.md`), shipped as one chain. **#75** security — NEW `### Content sanitization contract` (dual-track jsonl-verbatim-per-IC_R007 + GitHub-body-sanitized via Python Unicode-aware filter covering C0/DEL/C1 + bidi-override U+202A-U+202E + U+2066-U+2069 Trojan-Source CVE-2021-42574; `sanitize_source_label()` refuse-on-`@token` cross-references `rules/tagging-collaborators.md`; jq `--arg`/`--argjson` mandate; CAUTION banner above schema). **#76** bug — run_id second→ms-precision via dispatch chain handling macOS BSD date hazard (GNU `%3N` → Python datetime fallback → `.000Z`); TOCTOU symlink check fail-closed; `JSONL_WRITE_GUARD` 15-bit nonce-retry invoked at **run-start** (not materialize) to lock canonical path before Stage 4 footer composition. Pre-v2.67.0 second-precision was the irreversible-side-effect failure mode added to Layer P vocabulary in v2.64.0 #103 F4. **#77** enhancement — 7 corner-case spec contract gaps (flag-conflict layering, `partner_eligible_set` formal definition, Stage 3 Edit-row soft cap >5, `[Back to top-3]` in Stage 2 Other, Stage 1 path canonicalization, agent-crash known gap, Stage 4.5 unattended fallback). **#79** enhancement — abort-path writes minimal `aborted: true` jsonl with partial timestamps (footer URLs in already-dispatched bodies remain valid); footer `> **Action**` line; `"srt"` `source_type` enum. **#80** enhancement — Stage 1 anchor heuristics for MAY merge/split clauses (default preserve / split if ≥3 distinct topics / merge if <200 chars same-topic); `max_possible_score` formula explicit; N<3 degenerate-case picker shape table. **5/6-AI verify PASS post-fix** caught 4 HIGH blocking dispatched in-PR per `feedback_verify_fix_same_pr` (F75-1 CJK UTF-8 byte-level corruption / F76-1 BSD date `%3N` silent literal / F76-2 `JSONL_WRITE_GUARD` dead code + RANDOM 15-bit drift / #79 abort spec/impl contradiction). Codex 6th reviewer hung at 12+ min — process gap recorded per v2.59.0+ convention. Squash-merged as `14bc930`. **v2.68.0**: Phase 0.4 diagnosis-detection precision sweep from [#53](https://github.com/PsychQuant/issue-driven-development/issues/53)'s verify follow-up family ([#59](https://github.com/PsychQuant/issue-driven-development/issues/59) [#64](https://github.com/PsychQuant/issue-driven-development/issues/64) [#65](https://github.com/PsychQuant/issue-driven-development/issues/65), PR [#114](https://github.com/PsychQuant/issue-driven-development/pull/114)). 3 sister fixes. **#59** — `idd-all` 2 Python substring sites (line 450 + 533) swapped to line-anchored `re.search(r'(?m)^## Diagnosis', c['body'])` matching `check-diagnosis-readiness.sh` canonical convention from #53 / PR #58. Scope narrowed during implementation: cited `idd-list` / `idd-update` sites are narrative prose; `idd-close` uses `startswith()` (already line-1-anchored). **#64** — helper script regex widened from `^## Diagnosis` to `^[ ]{0,3}## Diagnosis` for CommonMark 1-3 space ATX heading indent. Col-0 still matches; 4+ space / tab / Unicode whitespace stay excluded (verified by DA's 31-fixture battery). **#65** Approach A — NEW comment block documenting line-based detection's fenced-code false-positive limitation. Approach B (full markdown parser) deferred per `feedback_lead_minimal`. Mitigation: chain Phase 0.4 AskUserQuestion user override. **3-AI verify PASS** (lean ensemble for 108-line diff). 0 blocking; 3 FYI observations. **Not in scope**: [#61](https://github.com/PsychQuant/issue-driven-development/issues/61) test fixture infra — Plan-tier with framework-choice surface deferred. Squash-merged as `a15a6a5`. **v2.71.0**: `/idd-all-chain` Phase 0.4.5 fail-fast cap-exceeded preflight + anti-pattern A3 cite ([#119](https://github.com/PsychQuant/issue-driven-development/issues/119), commits `cb96579` + `7aa11ea`). Pre-v2.71 silent-truncate ("filed only, not chained") behavior — when user passed N>cap roots, Phase 2 loop processed first cap then broke; remaining roots silently dropped — replaced with **fail-fast refuse at Phase 0.4.5** before any cluster branch / manifest creation. Refuse message cites `docs/workflows.md` Anti-pattern A3 (P-chain-from-root 多 root 用 batch 跑) + suggests batch `/idd-diagnose #N #M ...` + (P-atomic / P-cluster-pr) per cluster. Existing Phase 2 silent-truncate warnings (line 368, 468) get `(per docs/workflows.md anti-pattern A3)` cite suffix for defense-in-depth (Phase 2 fires on spawn-driven overflow, orthogonal to Phase 0.4.5 input-cap). Configuration cap doc reframed "global cap" → "**hard cap** as ripple-chain guardrail" — cap is ripple subtree safety bound NOT batch knob; multi-root batch should use `/idd-all #N #M ... --pr` cluster-pr path. Failure mode table adds new row distinguishing Phase 0 root-count refuse from Phase 2 spawn-driven truncate. **Ship dogfood**: Round 1 verify (`cb96579`) FAIL — 3 independent reviewers (Logic + Regression + Codex) + DA reinforcement caught Phase 0.4.5 was placebo gate: F1 (`${ROOTS[@]}` undefined; Phase 0.1 uses `ROOT_ISSUES_SORTED` / `N_ROOTS`) + F2 (`$CHAIN_MAX_ISSUES` set at line 377 Phase 1, hoist needed for line 267 Phase 0.4.5) + F3 (`exit 1` vs `abort` convention). Fix commit `7aa11ea` resolves all 3; Round 2 verify 5 independent voices + 1 coordinator self-review (DA Agent crashed 2x with `API socket closed` — process gap surfaced [#130](https://github.com/PsychQuant/issue-driven-development/issues/130)) = 6 PASS, 0 BLOCKING. Spectra→Plan tier reframing per `docs/workflows.md` path-catalog approach (commit `92e82c2`): skill behavior change collapsed from architectural Spectra (cap config-driven / new semantic detection) to Plan minimal MVP (fail-fast + cite A3 + doc-level cover). Companion docs introduce `docs/workflows.md` (8 sanctioned path categories + 6 anti-patterns) + `docs/skill-dimensions.md` (D1-D11 design axes) for IDD plugin architecture navigation. 6 IDD design issues migrated from `psychquant-claude-plugins` marketplace to architectural home (commit `e827bc7`): `#89→#122` (strict-separation proposal, supersede by reframing), `#69→#123`, `#29→#124`, `#27→#125`, `#33→#126`, `#7→#127`. Follow-ups filed: [#130](https://github.com/PsychQuant/issue-driven-development/issues/130) DA Agent socket crash, [#131](https://github.com/PsychQuant/issue-driven-development/issues/131) cognitive-load proxy metric (residue), [#132](https://github.com/PsychQuant/issue-driven-development/issues/132) Phase 2 truncate backward-compat policy (residue, likely moot). |
| v2.55.0 | 2026-05-10 | **`/idd-all-chain` skill — chain-solve mode** ([#44](https://github.com/PsychQuant/issue-driven-development/issues/44), `add-idd-all-chain-skill` Spectra change). NEW thin recursive shell over `/idd-all` that drives root issue + auto-emergent spawn (sub-skill sister sweep / verify follow-up / mid-plan tangential / sister concern) through ONE cluster branch (`idd/chain-<N>-<slug>`) + ONE review PR (title prefix `chain:`, collapsed `<details>` per issue). NEW `--in-chain` flag on `/idd-all` derives 4th mode tuple `(direct-commit, unattended)` — sub-`/idd-all` skips Phase 0.5 PR-mode branch + Phase 5.5 PR open + sub-skill UNATTENDED MODE; mutex with `--pr`/`--no-pr`. NEW spawn manifest cross-skill contract at `.claude/.idd/state/chain-spawned-issues.json` (schema_version=1, atomic temp-file rename); 4 sub-skills (`idd-implement` / `idd-verify` / `idd-plan` / `idd-diagnose`) all conformantly write entries with `spawn_kind` + `same_file_as_root` + `same_skill_as_root`. Helper `scripts/manifest-append.sh`. Hard caps: depth=2, max-issues=5; over-cap spawns still file as follow-up issues but NOT enqueued. Chain-eligible heuristic: `same_file OR same_skill OR sister-bug`; ineligible spawns stay filed-only. Failure mode: chained verify FAIL halts queue + preserves partial commits (no rebase / revert) + abort report cites 4 recovery paths. Stops at verified — never auto-close, never auto-merge (per IDD discipline). MODIFIED capability `idd-orchestrator-modes` adds 4th tuple `(direct-commit, unattended)` for chain context; existing 3 tuples unchanged. NEW reference docs: `references/spawn-manifest.md` (schema canonical contract) + `references/chain-flow.md` (chain shell algorithm canonical contract). Backward compat: `/idd-all #N` (no flag) is byte-equivalent to v2.53.0 baseline. |
| v2.53.0 | 2026-05-07 | **ralph-loop dependency declaration + runtime detect** ([#28](https://github.com/PsychQuant/issue-driven-development/issues/28), `add-ralph-loop-dependency` Spectra change). README `### Required for specific modes` matrix declares ralph-loop optional dependency for `idd-verify --loop`. NEW `scripts/check-ralph-loop.sh` detector (version-glob path lookup with HOME-spaces tolerance via nullglob array; escape hatch: `IDD_SKIP_RALPH_LOOP_CHECK=1`). NEW `idd-verify --loop` Step 0a fail-fast gate (abort if ralph-loop missing, point user to install). NEW `idd-all` Phase 0.6 graceful-degrade gate (when `--loop` style is requested but ralph-loop missing, unwind feature branch + fall back to single-shot verify with audit trail; Trace 4 example added). Forward-compat `plugins[].dependencies` field experimentally added then removed per F1 verify finding (schema validate-fail). Address F1-F5 verify findings before merge. |
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

## Deep Integrations（深度整合套件總覽）

IDD 遵循「**深度整合 >> hard-coded**」原則（#209/#214）：生態系已有 canonical 套件時依賴它、不在內部複製等價邏輯。每個整合的綁定形狀與缺席行為：

| Package | 綁定形狀 | 角色 | 缺席行為 |
| ------- | ------- | ---- | ------- |
| `parallel-ai-agents`（`psychquant-claude-plugins`） | **Hard dependency** — `plugin.json` `dependencies` 安裝時自動安裝（#219；cross-marketplace，root marketplace 需 `allowCrossMarketplaceDependenciesOn` 增列） | `idd-verify` 的 canonical ensemble 引擎（4 lens + DA + Codex；≥2.18.0 STABLE contract） | 缺席/過舊 → 印一步安裝指令 + fall back **manual fan-out**（品質等價、較慢）；vendored fork 已刪（#207 Residue 成熟） |
| `superpowers`（`claude-plugins-official`） | **Hard dependency** — `plugin.json` `dependencies` 安裝時自動安裝（#209） | TDD 執行（`idd-implement`）、系統性除錯（`idd-diagnose` bug RCA）、完成前驗證的 canonical process 紀律 | Delegation 點 **fail-fast abort** + 一步安裝指令；絕不 silent degrade |
| `parallel-ai-agents`（pai） | **Canonical engine + 版本閘門 ≥ 2.18.0**（#207，STABLE external-consumer contract） | `idd-verify` 的 6-AI ensemble 引擎（4 lenses + Devil's Advocate + Codex 編排） | 三層 graceful degrade：canonical → frozen vendored fork → manual fan-out（每層印 notice） |
| `ralph-loop`（`claude-plugins-official`） | Optional mode 依賴（#28） | `idd-verify --loop` / `idd-all (PR, unattended)` 的 verify-fix loop driver | `--loop` fail-fast + 安裝指引；`idd-all` graceful degrade 到 (direct-commit, attended) |
| OpenAI Codex CLI（gpt-5.5） | Vendored `codex-call` HTTP wrapper（#147，非 subprocess） | Verify 的跨模型盲驗 lens | Fail-closed INFO finding「cross-model pass incomplete」，不靜默當 PASS |
| `che-word-mcp` / `che-telegram-mcp` / `che-apple-mail-mcp` / `che-apple-notes-mcp` | Optional per source type（#27） | `idd-issue` 來源 adapter（docx / Telegram / Mail / Notes） | 該 source type **fail-fast** + 結構化安裝指引（見下方 Optional 表） |

## Requirements

### Required (always)

- `gh` CLI authenticated with GitHub
- [OpenAI Codex CLI](https://github.com/openai/codex) installed (for `idd-verify`)
- ChatGPT Pro account (for Codex gpt-5.5)
- `superpowers` plugin（`claude-plugins-official`）— **hard dependency（v2.90.0+ #209）**。安裝本 plugin 時 Claude Code 會經 `plugin.json` `dependencies` 自動安裝（需 Claude Code v2.1.110+；遞移 enable 需 v2.1.143+）。`idd-implement` 的 TDD 執行與完成前驗證、`idd-diagnose` 的 bug RCA 執行框架 delegate 給它；缺席時該路徑 **fail-fast abort** + 一步安裝指令，不做 fallback
- **SessionStart hook（v2.91.0+ #214）**：plugin 啟用後每次 SessionStart 事件（startup / resume / clear / compact — 刻意含 compact，讓規則在 context 壓縮後存活）注入 ≤5 行 commit issue-reference 紀律（canonical：`rules/commit-issue-reference.md`）— 防 GitHub auto-close trap 於 skill 外的手動 commit

### Optional (per source type)

`/idd-issue` 支援多種來源類型。文字直接貼進 prompt 不需要任何 plugin;若要從以下來源讀取,需另裝對應 MCP plugin:

| Source type | MCP plugin | Why | Install |
|-------------|------------|-----|---------|
| `.docx` / `.doc` | `che-word-mcp` | `idd-issue` Step 1 用 `mcp__che-word-mcp__get_document_text` / `list_images` / `export_image` 讀文字 + 抽圖 | `claude plugin install che-word-mcp@<your-marketplace>` |
| Telegram chat range | `che-telegram-mcp` (telegram-all server) | 讀 chat history (`get_chat_history`) | `claude plugin install che-telegram-mcp@<your-marketplace>` |
| Apple Mail message | `che-apple-mail-mcp` | `get_email` + `list_attachments` + `save_attachment` | `claude plugin install che-apple-mail-mcp@<your-marketplace>` |
| Apple Notes | `che-apple-notes-mcp` | `get_note` + 抽 inline 圖 | `claude plugin install che-apple-notes-mcp@<your-marketplace>` |

替換 `<your-marketplace>` 為實際的 marketplace 名稱。沒裝對應 plugin 不會壞 IDD 核心流程,但該 source type 會被迫 fallback 到「使用者手動處理」模式 (#27 追蹤改為明確 fail-fast 報錯)。

> **不知道 `<your-marketplace>` 該填什麼?**
>
> 1. 查已加的 marketplaces:`claude plugin marketplace list`
> 2. 加新 marketplace:`claude plugin marketplace add <owner>/<repo>`
> 3. 常見對照(以 PsychQuant 維護的 plugins 為例,如有變動以 `claude plugin marketplace list` 為準):
>
>    | Plugin pattern | Marketplace | Add command |
>    |----------------|-------------|-------------|
>    | `che-*` (incl. `che-word-mcp` / `che-telegram-mcp` / `che-apple-mail-mcp` / `che-apple-notes-mcp`) | `psychquant-claude-plugins` | `claude plugin marketplace add PsychQuant/psychquant-claude-plugins` |
>    | `idd-*` (本 plugin / `idd-route`) | `issue-driven-development` | `claude plugin marketplace add PsychQuant/issue-driven-development` |
>    | `ralph-loop` (Anthropic 官方) | `claude-plugins-official` | `claude plugin marketplace add anthropics/claude-plugins-official` |

### Required for specific modes

某些 mode / flag 需要額外 plugin。**未裝對應 plugin 時的行為**見最右欄:

| Mode | Required plugin | Marketplace | Why | Behavior if missing |
|------|-----------------|-------------|-----|---------------------|
| `idd-implement`（TDD / 完成前驗證）+ `idd-diagnose`（bug RCA） | `superpowers` | `claude-plugins-official` | process-discipline delegation（#209 hard dependency；正常情況由 `dependencies` 自動安裝，不會缺席） | **fail-fast abort** + install hint |
| `idd-verify --loop` | `ralph-loop` | `claude-plugins-official` | outer driver for verify-fix loop | **fail-fast abort** + install hint |
| `idd-all` (PR, unattended) (default) | `ralph-loop` | 同上 | unattended 在 verify findings 後需 driver 觸發下一輪 | **graceful degrade** to `(direct-commit, attended)` + warning(保護 v2.40.0 caller backward compat) |
| `idd-all --no-pr` (direct-commit, attended) | (none) | n/a | user 在 keyboard 自然推進 | n/a |
| Single-skill calls (no `--loop`) | (none) | n/a | atomic skill 自完成 | n/a |

Install:`claude plugin marketplace add anthropics/claude-plugins-official` 然後 `claude plugin install ralph-loop@claude-plugins-official`。

> **Native alternative — `/goal`（v2.1.139+，#138）**：以上「outer driver for verify-fix loop」的角色，也可改用 Claude Code **內建**的 [`/goal`](https://code.claude.com/docs/en/goal.md) —— 設一個 completion condition（例如「verify 通過、blocking findings = 0」），它每個 turn 後用 small fast model 檢查、未達成就自動再跑下一個 turn，直到條件滿足。`/goal` 是 native（無需安裝第三方 plugin），`ralph-loop` 是 `claude-plugins-official` 的 plugin —— 兩者都能驅動 loop，擇一即可。**目前 `idd-all` / `idd-verify --loop` 的 gate 偵測的是 `ralph-loop` plugin**；若偏好 native，可手動以 `/goal` 驅動（是否把 gate 改為支援 `/goal` 為更大設計題，見 #138 residue）。

### Sister plugins

- [`idd-route`](../idd-route) — Data-driven agent routing (Codex / Claude Opus / Sonnet / Haiku) per IDD issue。`idd-diagnose` Step 3.7 偵測到 `idd-route` 已裝就會自動呼叫做 enrichment;沒裝則 silently skip。**非必要**,純粹增強 routing 建議品質。Install: `claude plugin install idd-route@issue-driven-development`

### Security model (v2.54+, #41)

`scripts/check-plugin-presence.sh` (#34) 用「filesystem 存在」作為 plugin 安裝判準 — 檢查 `~/.claude/plugins/cache/<marketplace>/<plugin>/<version>/.claude-plugin/plugin.json` 即視為 installed,**無 signature / hash / integrity 驗證**。

| Environment | Trust model fit |
|-------------|-----------------|
| Single-user macOS / Linux local dev | ✅ 設計預設場景,trust model 適用 |
| Shared dev container / CI runner with shared `$HOME` | ⚠️ Hostile party 可在 cache path 植入空 `plugin.json` 騙過 detect → IDD 跑 `--loop` / source-type adapter as if plugin present。**Caller 自負其責** |
| Multi-user shared workstation | ⚠️ 同上 |

**Hardening path** (若部署到 untrusted 環境):
1. Pre-validate plugin install via `claude plugin list` (source-of-truth from Claude Code itself, not filesystem)
2. 設 `IDD_SKIP_PLUGIN_CHECK=1` env var 跳過 detect,接受 bypass cost (`--loop` 跑了但無真實 driver = silent fail)
3. 部署時 lock `~/.claude/plugins/cache/` permissions (chmod 700) 防 hostile write

**Future hardening** (#41 reopen criteria): 若 multi-user / CI deployment 真實成本上升,evaluate hash verification step against marketplace-published plugin manifest。
