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
issue → diagnose → implement → verify → close
  ①        ②          ③         ④       ⑤
```

| Skill | Purpose |
|-------|---------|
| `issue` | Create well-documented GitHub Issue with original quotes and images |
| `diagnose` | Find root cause (bug) or analyze requirements (feature/refactor) |
| `implement` | Scope-disciplined implementation with TDD |
| `verify` | Independent verification using Codex CLI (gpt-5.4) |
| `close` | Closing comment documenting problem, root cause, solution, verification |

## Quick Start

```bash
# Install
/plugin marketplace add https://github.com/PsychQuant/psychquant-claude-plugins
/plugin install issue-driven-dev

# Use
/issue-driven-dev:issue "upload button doesn't work on mobile"
/issue-driven-dev:diagnose #42
/issue-driven-dev:implement #42
/issue-driven-dev:verify #42
/issue-driven-dev:close #42
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
- [OpenAI Codex CLI](https://github.com/openai/codex) installed (for `verify`)
- ChatGPT Pro account (for Codex gpt-5.4)
