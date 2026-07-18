# Design: codex-channel-dependency

## D1 — executable 歸 pai，前置區先解析（供兩用途）

現行 SKILL 的共通前置在 Tier 1 之前算 `CODEX_CALL=$CLAUDE_PLUGIN_ROOT/bin/codex-call`、Tier 1 才算 `PAI_DIR`。重排：**前置區先解析 `PAI_DIR`**（同一段 `sort -V` cache glob），再取 `PAI_CODEX_CALL="$PAI_DIR/bin/codex-call"` — 一次解析、engine 路徑與 codex-call 路徑兩用。`MIN_PAI="2.19.0"`（gate 理由更新：2.18.0 引擎會**靜默忽略** codexModel/codexEffort → canonical tier 治理斷鏈，寧 fail 不降級）。pai 缺席/過舊 → 既有 Tier 2 fail-fast 訊息路徑；此時 codex leg 無 executable → 沿用既有 fail-closed INFO finding（cross-model pass incomplete），不 abort 整個 verify。

## D2 — 治理歸 codex-pro：contract-pinned，非 value-pinned

```bash
CP_DIR=$(ls -d ~/.claude/plugins/cache/codex-pro/codex-pro/*/ 2>/dev/null | grep -E '/[0-9]+\.[0-9]+\.[0-9]+/$' | sort -V | tail -1)
MIN_CODEX_PRO="0.7.0"   # defaults.json + profile-contract.md 起點
# gate 失敗 → abort：claude plugin install codex-pro@codex-pro（superpowers 同款 fail-fast）
# 解析（per codex-pro references/profile-contract.md §2）：
#   defaults.json 起底（model/effort/max_time）→ ~/.codex-pro/profile.yaml → ./.codex-pro/profile.yaml（per-field 高層蓋低層）
```

IDD **pin 契約不 pin 值**（contract §4）：樹內不出現任何 model 字面。defaults.json 缺檔/parse 失敗 → **fail-fast**（#205 fail-loud 判準 — 靜默跑錯 model 比失敗糟）。profile.yaml 解析沿 contract 的扁平 YAML 假設（python3 單行，同 codex-pro 慣例、不依賴 PyYAML）。

## D3 — 依賴接線：superpowers 形狀逐項對齊

| #209 superpowers | 本案 codex-pro |
|---|---|
| `dependencies` @ claude-plugins-official | `dependencies` @ codex-pro（self-hosted marketplace）|
| root marketplace `allowCrossMarketplaceDependenciesOn` | 同 — 加 `codex-pro` |
| `check-plugin-presence.sh` 三參數 pre-flight | `check-plugin-presence.sh codex-pro codex-pro` 於 idd-verify Step 0.5 前 |
| 缺席 fail-fast + 一步安裝指令 | 同（無 soft fallback — 使用者裁決「要 hard，保證品質」）|

## D4 — canonical tier 傳參

Workflow args 增 `codexModel: $CODEX_MODEL, codexEffort: $CODEX_EFFORT`（pai 2.19.0 additive 契約）。`codexCallPath` 改傳 `$PAI_CODEX_CALL`。manual fan-out 的背景 codex 呼叫與 legacy 直呼段同步帶 `--model "$CODEX_MODEL" --effort "$CODEX_EFFORT" --max-time "$CODEX_MAX_TIME"`。

## D5 — drift-guard 重塑（single-pin 契約遷移）

`model-generation-sync` 的不變量從「pin 在 IDD codex-call」改為「**IDD 樹內零 pin，契約指向 codex-pro**」：

- assert `bin/codex-call` **不存在**（回歸 = 有人重新 vendor）
- assert SKILL 含 `MIN_CODEX_PRO="0.7.0"`、`defaults.json`、`codexModel`、`PAI_CODEX_CALL`、`MIN_PAI="2.19.0"`
- refute `--model gpt-5` / `gpt-5.5` hard-pin（維持）；世代中立 prose（`gpt-5.x`）維持
- idd-route / references 斷言維持不動

## Alternatives considered

- **依賴 codex-pro 也提供 executable**：否 — codex-pro design D3 明文 executable 歸 pai；跨 plugin 職責不重排
- **PATH 解析 `command -v codex-call`**（codex-pro setup 的做法）：否 — IDD 已有 PAI_DIR 精確解析，PATH 受安裝順序影響（本案動機之一就是 PATH 上撞到 IDD 自己的 vendored copy）
- **保留 vendored copy 當 fallback**：否 — 使用者裁決 superpowers 形狀；divergence audit 證明 fork 必然靜默落後
