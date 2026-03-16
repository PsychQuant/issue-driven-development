# issue-driven-dev

Human defines the problem, AI solves it.

## What is this?

A Claude Code plugin that enforces issue-driven development discipline:

1. **Every change starts with an issue** — with the customer's exact words quoted
2. **Every implementation is verified** — Codex CLI checks code against issue requirements
3. **Every closure is documented** — mandatory closing comment before close

## Why?

Most teams use GitHub Issues casually. This plugin makes discipline automatic:

| Without this plugin | With this plugin |
|---------------------|-----------------|
| Issues have vague descriptions | Issues quote customer's exact words |
| "Looks good enough" before commit | Codex verifies every requirement is met |
| Issues closed with no explanation | Mandatory closing comment documenting what was done |
| AI summaries lose precision | Original text preserved verbatim |

## Skills

| Skill | Purpose |
|-------|---------|
| `issue` | Create well-documented GitHub Issues with original quotes, images, closing comments |
| `codex-review` | Verify uncommitted changes against issue requirements using Codex CLI (gpt-5.4) |

## Workflow

```
/issue-driven-dev:issue "description"
    → implement changes
    → /issue-driven-dev:codex-review #42
    → findings? fix and re-verify
    → all passed? commit with #42 reference
    → closing comment → close
```

## Install

```bash
/plugin marketplace add https://github.com/PsychQuant/psychquant-claude-plugins
/plugin install issue-driven-dev
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

- [OpenAI Codex CLI](https://github.com/openai/codex) installed and authenticated
- `gh` CLI authenticated with GitHub
- ChatGPT Pro account (for Codex gpt-5.4)
