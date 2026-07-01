# Codex Tool Compatibility

Codex support is a compatibility layer over the Claude-canonical IDD skill contract. Codex may load the shared `skills/` tree, but Claude Code remains the source of truth for workflow semantics.

When Codex cannot provide equivalent behavior, it must mark the behavior as degraded rather than silently weakening an IDD gate.

## AskUserQuestion

Codex-compatible handling:

- Prefer `request_user_input` when it is available and the interaction is a bounded user choice.
- If no structured input tool is available, ask a concise plain-text question and wait for the user's answer.
- In unattended contexts, use only defaults that the skill explicitly documents for unattended mode.

Degraded or unavailable:

- Do not silently choose for decisions that affect GitHub side effects, target repo, PR/direct-commit path, issue closure, or follow-up filing.
- If waiting for input is impossible, stop and report the blocker.

## EnterPlanMode

Codex-compatible handling:

- Treat `EnterPlanMode` as a required approval gate, not as a decorative planning section.
- Present the full implementation plan and wait for explicit approval before stateful work.
- Keep tooling read-only while waiting for approval when the local Codex mode supports that constraint.

Degraded or unavailable:

- Plain text approval is a degraded fallback because it cannot enforce read-only runtime behavior.
- If the skill depends on read-only enforcement for safety, stop or mark the run as degraded before continuing.

## TaskCreate / TaskUpdate / TaskList

Codex-compatible handling:

- Use Codex planning/status tools when available.
- For Spectra-driven work, the `tasks.md` checkbox state remains the source of truth.
- Keep stage progress visible in user updates when a task-list tool is unavailable.

Degraded or unavailable:

- Do not claim stage-task compliance if no visible task or equivalent progress tracking was maintained.
- Do not mark a Spectra task complete until its verification target passes.

## Agent / SendMessage

Codex-compatible handling:

- Prefer available multi-agent tools for independent review fan-out.
- If multi-agent tools are unavailable, run a single-agent fallback only when the skill allows degraded review.
- Preserve reviewer-role separation in prompts and report any missing lens as a process gap.

Degraded or unavailable:

- Do not collapse a required independent ensemble into one unlabelled self-review while still claiming full ensemble verification.
- Timeouts, crashes, or missing reviewer output must be surfaced.

## Skill(...)

Codex-compatible handling:

- Prefer native skill invocation or plugin namespacing when available.
- If native delegation is unavailable, load and follow the target skill instructions manually only when that does not bypass the target skill's gates.
- Preserve mode hints such as unattended behavior in the handoff.

Degraded or unavailable:

- Do not inline another skill casually if its preconditions, user gates, or side effects are unclear.
- Stop and ask for direction when delegation is required but the target skill is not available.

## Claude plugin commands

Codex-compatible handling:

- Use Codex plugin commands only for Codex marketplace operations.
- Keep Claude plugin commands in user-facing docs when they describe the canonical Claude install path.

Examples:

```bash
codex plugin marketplace add /path/to/issue-driven-development
codex plugin add issue-driven-dev@issue-driven-development
```

Degraded or unavailable:

- Installing a Codex compatibility shell does not prove Claude plugin dependencies such as source adapters or loop drivers are installed.
- Do not use Codex plugin installation as a substitute for Claude dependency detection unless the skill explicitly supports that runtime.

## .claude/.idd

Codex-compatible handling:

- Treat `.claude/.idd` as the canonical IDD state namespace even when Codex is executing the skill.
- Read and write documented IDD state paths exactly unless a migration spec says otherwise.
- Surface the path name as historical/canonical IDD state, not as evidence that the workflow is Claude-only.

Degraded or unavailable:

- Do not create a parallel `.codex/.idd` namespace for the same workflow without a migration plan.
- If a runtime policy blocks access to `.claude/.idd`, stop and report the compatibility issue.

## CLAUDE_PLUGIN_ROOT

Codex-compatible handling:

- Do not assume `CLAUDE_PLUGIN_ROOT` exists.
- Resolve bundled helper scripts relative to the installed plugin root or repository path when the Codex plugin shell exposes one.
- If no plugin-root signal exists, ask for the plugin root or stop before running helper-dependent logic.

Degraded or unavailable:

- Do not silently skip helper scripts because `CLAUDE_PLUGIN_ROOT` is absent.
- Do not substitute a different script unless the skill documents it as equivalent.
