## Context

IDD plugin skills currently use Claude Code as their native execution language. The skill bodies name Claude runtime primitives such as AskUserQuestion, EnterPlanMode, TaskCreate, Agent, SendMessage, Skill(...), Claude plugin install commands, and `.claude/.idd` state paths. That language is intentional: it encodes the workflow discipline IDD relies on.

At the same time, the same Markdown skill tree can be exposed to Codex or other agent runtimes through platform-specific plugin shells. The goal is not to make Claude and Codex identical. The goal is to preserve the Claude-defined workflow semantics as the canonical contract and give non-Claude runtimes an explicit compatibility map.

## Goals / Non-Goals

**Goals:**

- State that Claude Code is the canonical runtime for IDD skills.
- State that `skills/` remains the canonical source tree for IDD behavior.
- Add `references/claude-code-tools.md` documenting the native Claude contracts used by the skills.
- Add `references/codex-tools.md` documenting Codex interpretation, fallback limits, and degraded behavior rules.
- Update README and CLAUDE.md so maintainers know non-Claude runtimes are compatibility shells, not equal sources of truth.

**Non-Goals:**

- Do not fork `skills-codex/`.
- Do not rewrite existing SKILL.md files into runtime-neutral language.
- Do not implement a Codex plugin shell in this change.
- Do not change `.claude/.idd` state namespace or migration behavior.
- Do not promise full Codex runtime parity for Claude-only constructs.

## Decisions

### Claude Code remains the canonical runtime

IDD skill semantics SHALL be defined first by Claude Code behavior. Other runtimes may load the same skills, but their adapters must preserve the Claude-defined workflow semantics or explicitly mark degraded fallback behavior.

Alternative considered: declare a platform-neutral abstract runtime as the canonical contract. Rejected because current IDD discipline depends on concrete Claude runtime affordances such as plan-mode locking and stage-level task harnesses.

### Keep the shared skills tree canonical

The repository SHALL keep `plugins/issue-driven-dev/skills/` as the single canonical skill source. Compatibility guidance belongs in references and platform shells, not copied skill trees.

Alternative considered: create `skills-codex/`. Rejected until a specific skill proves impossible to express through compatibility guidance without breaking Claude-native behavior.

### Runtime mapping is reference documentation, not behavior rewrite

`claude-code-tools.md` SHALL describe native Claude contracts. `codex-tools.md` SHALL map those contracts to Codex-compatible handling, including when a fallback is degraded or unavailable. Existing skill bodies may continue to name Claude-native tools.

Alternative considered: edit every SKILL.md to include Codex-specific branches. Rejected because it would add noise to the canonical skill instructions and increase maintenance cost before actual runtime gaps are measured.

## Implementation Contract

Observable behavior: maintainers reading the plugin documentation can tell that Claude Code is the canonical runtime, `skills/` is the canonical source tree, and Codex or other runtimes are compatibility consumers. A Codex runner reading `references/codex-tools.md` gets a concrete mapping for common Claude-native primitives and can identify when behavior is degraded.

Data shape:

- `plugins/issue-driven-dev/references/claude-code-tools.md` exists and documents native semantics for AskUserQuestion, EnterPlanMode, TaskCreate/TaskUpdate/TaskList, Agent/SendMessage, Skill(...), Claude plugin commands, `.claude/.idd`, and CLAUDE_PLUGIN_ROOT.
- `plugins/issue-driven-dev/references/codex-tools.md` exists and maps those same primitives to Codex behavior or explicit degraded fallback.
- `plugins/issue-driven-dev/README.md` states the canonical-runtime policy and references both mapping files.
- `plugins/issue-driven-dev/CLAUDE.md` states the maintainer policy: keep Claude-native SKILL.md instructions canonical and add non-Claude compatibility through references/adapters before forking skill trees.

Acceptance criteria:

- The two new reference files contain matching sections for the same tool-contract vocabulary.
- Documentation does not claim Codex has full runtime parity.
- Documentation does not require a `skills-codex/` fork.
- `spectra validate codify-claude-canonical-runtime` succeeds.
- `spectra analyze codify-claude-canonical-runtime --json` reports no Critical or Warning findings.

Scope boundaries:

- In scope: documentation and Spectra artifacts.
- Out of scope: plugin shell manifests, runtime code, hooks, state migrations, and edits to individual skill execution steps.

## Risks / Trade-offs

- [Risk] Codex support may look weaker because degraded fallbacks are explicit. -> Mitigation: explicit boundaries are safer than silent semantic drift.
- [Risk] Maintainers may still copy skills for convenience. -> Mitigation: document that forks are last resort and require a concrete incompatibility.
- [Risk] Reference mappings can drift from skill bodies. -> Mitigation: keep the mapping vocabulary focused on stable runtime primitives rather than every individual step.
