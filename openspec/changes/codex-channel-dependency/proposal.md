# Proposal: codex-channel-dependency

## Why

IDD vendor 一份 `bin/codex-call`（#147 時代 — 當時 pai 還不是依賴）。前提已被 #207/#219 推翻（pai 是 install-time hard dependency、vendored ensemble fork 已刪，codex-call 卻留下）。實證兩則：divergence audit（#264 comment）顯示 vendored copy 落後 pai 2.18.0 四個安全/正確性修正（exp NSNumber parse、umask 0o077、form-encoding、flock re-read）；#251 在 vendored copy 重做了 codex-pro#3 五天前已做過的 model bump。使用者裁決（2026-07-18）：「完全依賴，跟 superpowers 一樣」。

## What Changes

1. **刪除** `plugins/issue-driven-dev/bin/codex-call`（不留 fork — superpowers 形狀，#209 exemplar）
2. **executable 歸 pai**：codex-call 一律解析 `$PAI_DIR/bin/codex-call`（沿用既有 cache `sort -V` 解析）；`MIN_PAI` 2.18.0 → **2.19.0**（codexModel/codexEffort args 起點，pai#22）
3. **治理歸 codex-pro**：新 governance 解析 — `MIN_CODEX_PRO=0.7.0` gate、讀 `references/defaults.json` 起底、疊 profile.yaml 兩層（per codex-pro `profile-contract.md` §2）；解析失敗 fail-fast（不靜默 fallback）
4. **canonical tier 傳參**：Workflow args 加 `codexModel`/`codexEffort`（pai 2.19.0 契約）；manual fan-out 與 SKILL 直呼處帶顯式 `--model`/`--effort`
5. **依賴接線**：`plugin.json` dependencies 加 `codex-pro@codex-pro`；root marketplace `allowCrossMarketplaceDependenciesOn` 加 `codex-pro`；Step 0.5 前 pre-flight `check-plugin-presence.sh codex-pro codex-pro`（缺席 fail-fast + 一步安裝指令）
6. **drift-guard 重塑**：`model-generation-sync` 的 single-pin 契約改指 codex-pro `defaults.json` — IDD 樹內零 model pin；`bin/codex-call` 不存在成為 assertion

## Non-Goals

- pai `bin/codex-call` 自身 default 的 bump（顯式傳參後無關；pai 另案）
- codex-pro producer skills 的 resolver 讀檔化（codex-pro#7 Residue）
- IDD_AGENT_MODEL（Claude dispatch model）機制 — 與 codex 治理正交，不動

## Impact

- Affected specs: `idd-verify`（ADDED requirement）
- Affected code: `skills/idd-verify/SKILL.md`、刪 `bin/codex-call`、`scripts/tests/model-generation-sync/test.sh`、`.claude-plugin/plugin.json`、root `marketplace.json`

## Refs

Issue #264（diagnosis + divergence audit）；上游 codex-pro#7（0.7.0，已結案）、pai#22（2.19.0，已結案）
