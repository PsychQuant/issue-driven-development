# issue-driven-development

A Claude Code plugin marketplace for the [Issue-Driven Development (IDD)](https://github.com/PsychQuant/issue-driven-development/blob/main/plugins/issue-driven-dev/MANIFESTO.md) methodology.

> **TDD writes tests. SDD writes specs. IDD solves bugs.**

## Plugins

| Plugin | Version | Purpose |
|--------|---------|---------|
| [`issue-driven-dev`](./plugins/issue-driven-dev) | 2.56.0 | Core IDD workflow — issue → diagnose → implement → verify → close. 14 skills(含 `/idd-all-chain` chain-solve 與 `idd-issue` multi-finding source mode for batch routing across new + existing issues from a single source document) + 5 rules + 5 references. |
| `idd-route` (coming) | 0.1.0 | Data-driven agent routing: recommends Codex / Claude Opus / Sonnet / Haiku per IDD issue based on observed track record. Wraps the [PsychQuant/idd-route-swift](https://github.com/PsychQuant/idd-route-swift) binary. |

## Installation

```bash
claude plugin marketplace add PsychQuant/issue-driven-development
claude plugin install issue-driven-dev@issue-driven-development
```

## Requirements

IDD core 是零依賴的 — 純文字 issue / `/idd-issue` 直接貼描述、`/idd-diagnose` / `/idd-implement` / `/idd-close` 都不需要任何外部 plugin。

某些情境需要額外裝 plugin:

- **`.docx` / Telegram / Apple Mail / Apple Notes 來源** — `/idd-issue` 從這些來源讀文字 + 抽附件需對應 MCP plugin
- **`idd-verify --loop` / `idd-all` (PR, unattended) mode** — 需要 [`ralph-loop`](https://github.com/anthropics/claude-plugins-official) 作為 outer driver(#28 預計補完整文件)
- **`idd-verify` 6-AI ensemble** — 需要 [OpenAI Codex CLI](https://github.com/openai/codex) + ChatGPT Pro

完整 matrix 與 install 指令見 [`plugins/issue-driven-dev/README.md#requirements`](./plugins/issue-driven-dev/README.md#requirements)。

## Why a separate marketplace?

IDD is a methodology unto itself with its own [MANIFESTO](./plugins/issue-driven-dev/MANIFESTO.md) and steady release cadence (38+ versions). Pulling it out of `psychquant-claude-plugins` (which has ~36 unrelated plugins) gives:

- Cleaner discoverability for users adopting IDD without the rest of the PsychQuant ecosystem
- Independent release cycle
- Room to grow related sister plugins (`idd-route`, future `idd-bench` / `idd-stats` / `idd-codex-companion`)

## Migration from psychquant-claude-plugins

If you previously installed `issue-driven-dev` from `psychquant-claude-plugins`, you need to switch source:

```bash
claude plugin uninstall issue-driven-dev@psychquant-claude-plugins
claude plugin marketplace add PsychQuant/issue-driven-development
claude plugin install issue-driven-dev@issue-driven-development
```

Settings (`.claude/issue-driven-dev.local.json`, `.claude/.idd/`) and per-repo state are preserved — they live in your project repos, not in the plugin install.

## Workflow

```
issue → diagnose → implement → verify → close
  ①        ②           ③         ④       ⑤
```

Each step is one skill. See [the plugin README](./plugins/issue-driven-dev/README.md) for details.

## License

MIT
