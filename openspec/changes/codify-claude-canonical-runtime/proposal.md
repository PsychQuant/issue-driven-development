## Why

IDD skills were designed around Claude Code runtime semantics, but the repository is starting to expose the same skill tree to other agent runtimes such as Codex. Without an explicit compatibility policy, maintainers may either over-neutralize the canonical Claude workflow language or accidentally let non-Claude runtimes reinterpret critical workflow gates.

## What Changes

- Document Claude Code as the canonical runtime for IDD skills.
- Add runtime compatibility references that map Claude-native tool contracts to Codex-compatible interpretations and fallback limits.
- Update plugin documentation so other runtimes are described as compatibility shells that must preserve Claude-defined workflow semantics or explicitly mark degraded behavior.
- Keep the shared `skills/` tree as the canonical source; do not fork `skills-codex/` or rewrite existing skill bodies into runtime-neutral language in this change.

## Capabilities

### New Capabilities

- `runtime-compatibility-guidance`: Defines IDD's canonical-runtime policy and runtime tool mapping references for Claude Code and Codex.

### Modified Capabilities

(none)

## Impact

- Affected specs: runtime-compatibility-guidance
- Affected code:
  - New: plugins/issue-driven-dev/references/claude-code-tools.md
  - New: plugins/issue-driven-dev/references/codex-tools.md
  - New: openspec/changes/codify-claude-canonical-runtime/specs/runtime-compatibility-guidance/spec.md
  - Modified: plugins/issue-driven-dev/README.md
  - Modified: plugins/issue-driven-dev/CLAUDE.md
  - Modified: openspec/changes/codify-claude-canonical-runtime/proposal.md
  - Modified: openspec/changes/codify-claude-canonical-runtime/design.md
  - Modified: openspec/changes/codify-claude-canonical-runtime/tasks.md
  - Removed: none
