# idd-route

Data-driven agent routing for [IDD methodology](../issue-driven-dev). Wraps the [`PsychQuant/idd-route-swift`](https://github.com/PsychQuant/idd-route-swift) Swift binary.

## What does this do?

Given a new GitHub issue diagnosed by `idd-diagnose`, recommends the best agent to delegate implementation to:

- `codex-xhigh` — OpenAI Codex CLI with GPT-5.5 at xhigh reasoning effort
- `claude-opus-4.7` — Anthropic Claude Opus 4.7
- `claude-sonnet-4.6` — Anthropic Claude Sonnet 4.6
- `claude-haiku-4.5` — Anthropic Claude Haiku 4.5

Recommendation is based on **observed track record** per `(complexity, scope_class)` bucket with exponential decay (recent decisions weight more, half-life 30 days). Falls back to a static heuristic rubric when fewer than 5 data points exist for a candidate (cold start).

## Skills

| Skill | Purpose |
|-------|---------|
| `/idd-route:recommend <repo> <complexity> <loc>` | Get agent recommendation for a hypothetical or real issue |
| `/idd-route:stats <repo>` | Markdown summary of routing-stats.jsonl |
| `/idd-route:backfill <gh-repo> <repo>` | Seed initial data from past GH verify comments (requires binary v0.3.0) |

## Auto-integration with issue-driven-dev

Once both plugins are installed, the IDD skills call `~/bin/idd-route` directly:

- `idd-verify` records each verify outcome
- `idd-close` finalizes outcome (merged / abandoned)
- `idd-diagnose` shows recommendation in diagnosis comment

You don't need to manually invoke this plugin's skills — it works automatically. The 3 skills here are for ad-hoc lookup / debugging.

## Install

```bash
claude plugin marketplace add PsychQuant/issue-driven-development
claude plugin install idd-route@issue-driven-development
```

The wrapper auto-downloads the universal binary from [`PsychQuant/idd-route-swift`](https://github.com/PsychQuant/idd-route-swift) releases on first use.

## Config

```bash
# Disable entirely
touch ~/.cache/idd-route/disabled

# Per-project disable
echo '{"enabled": false}' > .claude/idd-route.json

# Tune decay half-life
echo '{"decay_half_life_days": 60}' > ~/.cache/idd-route/config.json
```

See [`CLAUDE.md`](CLAUDE.md) for full config schema + three-tier injection logic.

## License

MIT
