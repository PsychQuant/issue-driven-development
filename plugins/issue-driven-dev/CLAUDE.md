# issue-driven-dev — CLAUDE.md

## Purpose

Issue-driven development：人定義問題，AI 解決問題。

Issue 是人和 AI 的介面 — 人負責「什麼是對的」，AI 負責「怎麼做到」。

## Skills

| Skill | 用途 |
|-------|------|
| `/issue-driven-dev:issue` | 建立 well-documented GitHub Issue（原文引用、圖片附件、closing comment） |
| `/issue-driven-dev:codex-review` | 用 Codex CLI 驗證 uncommitted code 是否滿足 issue 要求 |

## Workflow

```
issue → implement → codex-review → fix → codex-review → commit → closing comment → close
```

## Configuration

首次使用時會建立 `.claude/issue-driven-dev.local.md`：

```yaml
---
github_repo: "owner/repo"
github_owner: "owner"
attachments_release: "attachments"
---
```

## Development

- Update after changes: `/plugin-tools:plugin-update issue-driven-dev`
- Health check: `/plugin-tools:plugin-health`
