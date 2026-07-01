# Claude Code Tool Contracts

Claude Code is the canonical runtime for IDD skills. This reference records the native tool semantics that existing `SKILL.md` files may rely on.

Non-Claude runtimes can load or interpret the same skills, but they must preserve these workflow semantics or explicitly mark a degraded fallback.

## AskUserQuestion

`AskUserQuestion` is the native attended-decision primitive. IDD uses it when a decision changes workflow state, repository targeting, issue scope, follow-up filing, or PR/direct-commit path.

Required semantics:

- Present bounded options to the user.
- Wait for a user answer unless the enclosing skill explicitly declares unattended mode.
- Treat the selected option as an audit-relevant decision.
- Never replace an irreversible GitHub side-effect decision with a silent default.

## EnterPlanMode

`EnterPlanMode` is a Claude Code runtime gate that locks the session into read-only planning semantics until the user exits or approves the plan.

Required semantics:

- No state-mutating tools run while plan mode is active.
- The implementation plan is shown before execution.
- User approval or revision controls whether execution continues.
- Plain text confirmation is not equivalent when read-only enforcement matters.

## TaskCreate / TaskUpdate / TaskList

`TaskCreate`, `TaskUpdate`, and `TaskList` provide the stage-level harness for IDD skills.

Required semantics:

- Each stage skill creates a visible task list before doing stage work.
- Each sub-step is marked complete immediately after it is actually complete.
- Silent completion is a process bug.
- The stage task list complements, but does not replace, issue checklist contracts.

## Agent / SendMessage

`Agent` and `SendMessage` are Claude-native fan-out and recovery primitives used by review, verification, and orchestration flows.

Required semantics:

- Reviewer prompts remain isolated unless a later merge step intentionally combines findings.
- Recovery prompts must restate enough context for an idle or restarted agent.
- Missing reviewer output is reported as a process gap, not silently ignored.

## Skill(...)

`Skill(...)` delegates to another installed skill while preserving that skill's own contract.

Required semantics:

- Delegation is explicit and named.
- The receiving skill controls its own preconditions, gates, and side effects.
- Orchestrators pass mode hints such as unattended behavior through arguments or context, not by editing the callee contract.

## Claude plugin commands

Claude plugin commands are the canonical install and dependency-management surface for this package.

Examples:

```bash
claude plugin marketplace add PsychQuant/issue-driven-development
claude plugin install issue-driven-dev@issue-driven-development
```

Detection helpers may inspect Claude plugin cache paths only where the relevant skill documents that trust model.

## .claude/.idd

`.claude/.idd` is the canonical IDD state namespace for per-repo config, state, and attachments.

Required semantics:

- Runtime state and audit artifacts stay under `.claude/.idd` unless a migration is explicitly specified.
- Walk-up config resolution treats existing `.claude` paths as durable compatibility surface.
- Non-Claude runtimes must not silently invent a different state namespace for the same IDD workflow.

## CLAUDE_PLUGIN_ROOT

`CLAUDE_PLUGIN_ROOT` is the Claude-side way to locate plugin-bundled scripts or assets from inside installed plugin execution.

Required semantics:

- Script resolution should prefer plugin-bundled paths when the skill depends on shipped helper scripts.
- If a helper is not on `PATH`, the skill should resolve it relative to the plugin root.
- A missing plugin root is a runtime compatibility issue, not permission to silently skip helper-backed behavior.
