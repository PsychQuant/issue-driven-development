## 1. Runtime Reference Documents

- [x] 1.1 Deliver Runtime tool mappings are explicit, Claude Code is the canonical IDD runtime, and Claude Code remains the canonical runtime by adding `plugins/issue-driven-dev/references/claude-code-tools.md` with native semantics for AskUserQuestion, EnterPlanMode, TaskCreate/TaskUpdate/TaskList, Agent/SendMessage, Skill(...), Claude plugin commands, `.claude/.idd`, and CLAUDE_PLUGIN_ROOT; verify by content review that every listed primitive has a concrete Claude-native contract.
- [x] 1.2 Deliver Runtime tool mappings are explicit for Codex by adding `plugins/issue-driven-dev/references/codex-tools.md` with the same section vocabulary as `claude-code-tools.md`, mapping each primitive to Codex handling or an explicit degraded/unavailable fallback; verify by comparing headings between the two reference files and checking Codex limitations are named.

## 2. Plugin Documentation

- [x] 2.1 Deliver Documentation avoids full-parity claims by updating `plugins/issue-driven-dev/README.md` to state Claude Code is the canonical runtime, other runtimes are compatibility consumers, and full runtime parity is not implied by shared skill loading; verify the README links to both runtime mapping references and does not require a `skills-codex/` fork.
- [x] 2.2 Deliver Shared skills tree remains canonical, Keep the shared skills tree canonical, and Runtime mapping is reference documentation, not behavior rewrite by updating `plugins/issue-driven-dev/CLAUDE.md` with maintainer policy that existing SKILL.md files stay Claude-native, non-Claude compatibility belongs in references/adapters first, and forked skill trees require a documented incompatibility; verify content review confirms the policy names the shared `skills/` tree.

## 3. Verification

- [x] 3.1 Verify the runtime-compatibility-guidance contract by checking matching reference headings, running `spectra validate codify-claude-canonical-runtime`, and running `spectra analyze codify-claude-canonical-runtime --json`; completion requires no Critical or Warning findings.
