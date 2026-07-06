# Unattended contract — setter / detector / cleanup（#123, v2.92.0+）

> **Normative**：跨 skill（含跨 plugin）判定「本 session 是否處於 unattended orchestration」的唯一可靠契約。TTY heuristic（`[ ! -t 0 ]`）在 Claude Code harness 內恆真（Bash tool 永無 TTY，#222 實證），**不得**作為 attended/unattended 判別依據——只在 standalone CLI（真 terminal）場景可作輔助訊號。

## 訊號（優先序）

1. **State file** `.claude/.idd/state/unattended.json`（primary，harness 內跨 tool-call 持久）
   - Schema：`{"active":true,"by":"idd-all","started_at":"<UTC ISO8601>"}`
   - **TTL 24h**：`started_at` 超齡或檔案損毀 → 視為 stale，偵測方警告 + 自動清除 + 判 ATTENDED（crashed orchestrator 不得讓後續 attended session 永久誤判）
2. **Env var** `IDD_ALL_UNATTENDED=1`（compat layer — 給真 subprocess 的 hand-off，如 idd-all 內部啟動 plugin-tools `plugin-update` 時在命令列前綴）。Bash tool 的 fresh-shell 特性使它無法跨 tool call 存活——僅限單一命令列生命週期。

## 三方責任

| 角色 | 責任 | 載體 |
|------|------|------|
| **Setter** | `INTERACTION=unattended` 解析成立時 `mark_unattended`；對 subprocess 呼叫在命令列前綴 env var | `idd-all` Phase 0.5（chain 模式由 `idd-all-chain` Phase 0 代行）|
| **Detector** | 一律經 `scripts/lib/unattended-state.sh` 的 `is_unattended <repo_root>`（env var 先、file 次、TTL 防呆內建）；不得自行 grep 檔案或檢查 TTY | `idd-clarify` Step 4.8.A、`idd-issue` Stage 4.5、IC_R011 checkpoint、（跨 plugin）plugin-tools Phase 0.5 讀 env var 即可 |
| **Cleanup** | Phase 6 terminal report 前 + **每一條 abort path** `clear_unattended` | `idd-all` / `idd-all-chain` |

## Helper API（`scripts/lib/unattended-state.sh`）

```bash
. "$CLAUDE_PLUGIN_ROOT/scripts/lib/unattended-state.sh"
mark_unattended "$CWD" "idd-all"    # setter
is_unattended "$CWD" && echo un     # detector（exit 0 = unattended）
clear_unattended "$CWD"             # cleanup
```

測試：`scripts/tests/unattended-state/test.sh`（9 斷言：mark/clear/env-compat/stale-TTL/corrupt）。

## Cross-plugin 對接（plugin-tools #60 detector）

plugin-tools 的 `plugin-update` Phase 0.5 讀 **env var**——idd-all 呼叫它時以 `IDD_ALL_UNATTENDED=1 <cmd>` 前綴滿足（本契約第 2 訊號）。plugin-tools 側文件 cross-reference 的更新屬 psychquant-claude-plugins repo（#123 Residue）。
