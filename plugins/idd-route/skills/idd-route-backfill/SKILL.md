---
name: idd-route-backfill
description: |
  一次性 seed routing-stats.jsonl — 從 GH 歷史 verify comments 解析 (agent, complexity, blocking findings, round_trips) 寫成過去資料。
  Cold start 救星：新 marketplace 跑 idd-diagnose 馬上有資料推薦、不只 static heuristic。
  Use when: 新 repo 第一次裝 idd-route；已有歷史 verify comments 但都在 GH issue 上沒寫進 stats.jsonl；想補做之前手動 verify 的記錄。
  防止的失敗：永遠在 cold start fallback；過去手動 verify 的 30 個 outcome 都浪費掉。
argument-hint: "<owner/repo> <repo-path> [--since 2026-04-01]"
allowed-tools:
  - Bash(${CLAUDE_PLUGIN_ROOT}/bin/idd-route-wrapper.sh:*)
  - Bash(realpath:*)
  - Bash(gh:*)
  - Read
  - AskUserQuestion
---

# /idd-route:backfill — Seed routing-stats from GH history

> **NOTE — v0.1.0 status**: `backfill` command ships in `idd-route-swift` v0.3.0 (P2 of the plan).
> 在 binary v0.3.0 之前這個 skill 會回 "command not found"。
> 解法：等 P2 ship 後再跑，或先靠 `/idd-route:recommend` 的 static heuristic fallback 過渡。

Thin skill — `idd-route-wrapper.sh backfill ...` 直接 forward。

## 參數

- `gh_repo`（必填）— 例如 `PsychQuant/che-word-mcp`，要掃哪個 repo 的 verify comments
- `repo_path`（必填）— 對應的 local repo 根目錄（決定 stats.jsonl 寫到哪裡）
- `--since YYYY-MM-DD`（可選）— 限制掃描時間範圍

## Execution

```bash
STATS=$(realpath "$REPO_PATH")/.claude/.idd/routing-stats.jsonl

${CLAUDE_PLUGIN_ROOT}/bin/idd-route-wrapper.sh backfill \
  --repo "$GH_REPO" \
  --stats-file "$STATS" \
  --since "${SINCE:-2026-01-01}" \
  --gh-token "$(gh auth token)"
```

## 輸出

```json
{
  "backfilled": 23,
  "skipped_existing": 5,
  "skipped_unparseable": 2,
  "stats_file": "/path/to/routing-stats.jsonl"
}
```

## 解讀

- **backfilled**: 新加的 records
- **skipped_existing**: 已在 jsonl（idempotent — 重跑不重複）
- **skipped_unparseable**: verify comment 無法解析（過舊格式 / 手寫亂寫 / non-IDD comment）

跑完建議跟 `/idd-route:stats` 確認 bucket 看起來合理。

## 解析規則

binary 用 regex 從 verify comment 抓：

- **Agent**: 從 commit author 推斷（codex-* prefix → codex-xhigh；其他 → claude-opus-4.7 預設）
- **Complexity**: 從 diagnosis comment 的 `### Complexity` 區段（v2.36.0+）；找不到 fall back Simple
- **Round trips**: 數 verify comments 跟 implementation commits 的 interleave
- **Blocking / Medium / Low**: 解 verify report 的 findings 表
- **Outcome**: PR merged → `merged`；issue closed without merge → `abandoned`

詳細 regex 見 `Sources/IDDRoute/Logic/BackfillParser.swift` in `PsychQuant/idd-route-swift`。

## 鐵律

- **Idempotent**：重跑不會 duplicate；可安全多次執行
- **One-shot**：通常跑一次就夠；後續新 verify 會自動 record，不需再 backfill
- **不修改 GH issues**：只讀，不寫 GitHub
