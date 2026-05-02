# issue-driven-development

A Claude Code plugin marketplace for the [Issue-Driven Development (IDD)](https://github.com/PsychQuant/issue-driven-development/blob/main/plugins/issue-driven-dev/MANIFESTO.md) methodology.

> **TDD writes tests. SDD writes specs. IDD solves bugs.**

## Plugins

| Plugin | Version | Purpose |
|--------|---------|---------|
| [`issue-driven-dev`](./plugins/issue-driven-dev) | 2.37.0 | Core IDD workflow — issue → diagnose → implement → verify → close. 13 skills + 5 rules + 5 references. |
| `idd-route` (coming) | 0.1.0 | Data-driven agent routing: recommends Codex / Claude Opus / Sonnet / Haiku per IDD issue based on observed track record. Wraps the [PsychQuant/idd-route-swift](https://github.com/PsychQuant/idd-route-swift) binary. |

## Installation

```bash
claude plugin marketplace add PsychQuant/issue-driven-development
claude plugin install issue-driven-dev@issue-driven-development
```

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
