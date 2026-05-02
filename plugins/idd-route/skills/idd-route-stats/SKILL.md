---
name: idd-route-stats
description: |
  顯示 routing-stats.jsonl 的人讀 markdown 摘要 — 兩個表格：by agent（總體）+ by (agent × complexity × scope_class) bucket。
  Use when: 想看 Codex 跟 Claude 在你 marketplace 上的實際 track record；驗證 idd-verify / idd-close 有正確 record；偵錯為什麼推薦走某條路。
  防止的失敗：盲目相信推薦但不知道資料長相；jsonl 太大手動 grep 困難。
argument-hint: "<repo-path> [--decay-half-life-days 30]"
allowed-tools:
  - Bash(${CLAUDE_PLUGIN_ROOT}/bin/idd-route-wrapper.sh:*)
  - Bash(realpath:*)
  - Read
---

# /idd-route:stats — 看 routing 歷史

Thin skill — `idd-route-wrapper.sh stats ...` 直接 forward。

## 參數

- `repo_path`（必填）— 目標 repo
- `--decay-half-life-days N`（可選，預設 30）— 顯示時的 decay 設定（影響推薦時的 weight，不影響 stats 表的原始計數）

## Execution

```bash
STATS=$(realpath "$REPO_PATH")/.claude/.idd/routing-stats.jsonl

${CLAUDE_PLUGIN_ROOT}/bin/idd-route-wrapper.sh stats \
  --stats-file "$STATS" \
  --decay-half-life-days "${DECAY:-30}"
```

## 輸出

Markdown 兩個表：

```markdown
## By agent (un-decayed)

| Agent | N | Avg round trips | Avg blocking | Merge rate |
| codex-gpt-5.5-xhigh | 8 | 1.00 | 0.20 | 87% |
| claude-opus-4.7 | 4 | 2.50 | 1.50 | 100% |

## By (agent × complexity × scope) — for recommendation engine

| Agent | Complexity | Scope | N | Avg RT | Avg blocking | Merge% |
| codex-gpt-5.5-xhigh | Simple | small | 5 | 1.00 | 0.00 | 100% |
| codex-gpt-5.5-xhigh | Simple | medium | 3 | 1.33 | 0.33 | 67% |
| claude-opus-4.7 | Plan | large | 4 | 2.50 | 1.50 | 100% |
```

## 解讀

- **By agent**：粗略看哪個 agent 整體比較順 — 但混了不同 complexity，僅供 sanity check
- **By bucket**：推薦 engine 真正用的單位。bucket N >= 5 才會走 data-driven 推薦；< 5 走 static heuristic
- **Avg round trips**：1.0 代表 first-try pass；2.0 代表平均要 v1 → v2 才 land
- **Avg blocking**：每次 verify 平均的 blocking findings 數
- **Merge%**：在這 bucket 內最終 merge 比例（非 abandoned / reverted）

## 沒資料時

```
**Total records**: 0

_No data yet._ Cold start — recommendations will use static heuristic.
```

可以跑 `/idd-route:backfill` 從 GH 歷史 seed。

## 鐵律

- **stats 是純 read**，不會修改 jsonl
- **decay flag 只影響推薦 score**，不影響 stats 表（兩者獨立）
