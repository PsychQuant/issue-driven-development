---
name: idd-route-recommend
description: |
  問 idd-route 給某個 issue 推薦 agent（Codex GPT-5.5 xhigh / Claude Opus 4.7 / Sonnet 4.6 / Haiku 4.5）。
  讀 routing-stats.jsonl 的歷史資料、按 (complexity, scope_class) bucket 計算，曲線資料 < 5 筆時 fall back 到 static heuristic（exit code 3）。
  Use when: 已有 idd-diagnose comment 但要重新查推薦；ad-hoc 評估某個 issue 該找誰；測 idd-route binary 是否 work。
  防止的失敗：選 agent 靠感覺、漏看 track record；首次 install 後 binary 沒 download。
argument-hint: "<repo-path> <complexity> <scope-loc-estimate> --signals s1,s2 [--candidates c1,c2,...]"
allowed-tools:
  - Bash(${CLAUDE_PLUGIN_ROOT}/bin/idd-route-wrapper.sh:*)
  - Bash(realpath:*)
  - Read
---

# /idd-route:recommend — 查 agent 推薦

Thin skill — 把參數 forward 給 `idd-route-wrapper.sh recommend ...`，wrapper 自動下載 binary（如果還沒）然後 exec。

## 參數

- `repo_path`（必填）— 目標 repo 根目錄。stats.jsonl 路徑會 derive 為 `<repo>/.claude/.idd/routing-stats.jsonl`
- `complexity`（必填）— `Simple` / `Plan` / `Spectra`
- `scope_loc_estimate`（必填）— 整數，估計 implementation 會改幾行（diagnosis 的 file:line 摘要可以推估）
- `--signals s1,s2`（可選）— 來自 issue body 的 signal classification，見 [signal-vocabulary.md](../../references/signal-vocabulary.md)
- `--candidates c1,c2,...`（可選）— 預設 `codex-gpt-5.5-xhigh,claude-opus-4.7,claude-sonnet-4.6,claude-haiku-4.5`

## Execution

```bash
STATS=$(realpath "$REPO_PATH")/.claude/.idd/routing-stats.jsonl
GLOBAL=$HOME/.cache/idd-route/stats.jsonl

${CLAUDE_PLUGIN_ROOT}/bin/idd-route-wrapper.sh recommend \
  --stats-file "$STATS" \
  --global-stats-file "$GLOBAL" \
  --complexity "$COMPLEXITY" \
  --scope-loc-estimate "$SCOPE_LOC" \
  --signals "$SIGNALS" \
  --candidates "$CANDIDATES"
```

## 解讀輸出

stdout 是 pretty-printed JSON。重點欄位：

- **`recommended`**: 推薦的 agent ID
- **`confidence`**: 0.0–1.0（warm 路徑：分數佔比；cold 路徑：固定 0.5）
- **`data_source`**: `per_repo` / `global` / `static_heuristic`
- **`expected.{round_trips, blocking, merge_rate}`**: 推薦 agent 的歷史平均（warm only）
- **`reasoning`**: 一行人讀解釋
- **`fallback_used`**: true → exit code 3（呼叫者可 branch 此處決定要不要顯示「低信心」標記）

## 範例

```bash
# Warm 場景（per-repo 有資料）
/idd-route:recommend ~/Developer/macdoc/mcp/che-word-mcp Simple 200 --signals explicit_acceptance,single_handler

# Cold 場景（新 repo / 新 bucket）
/idd-route:recommend ~/Developer/new-project Spectra 2000 --signals redesign,cross_repo
# → static heuristic fallback、recommend Claude Opus、exit 3
```

## 鐵律

- **Stats jsonl 路徑由 repo 推導**，不要傳絕對路徑（保持一致性）
- **Cold start 不是錯誤**，只是低信心；exit code 3 是 informational signal
- **Recommendation 是建議，不是命令** — user 永遠可以 override 走另一個 agent
