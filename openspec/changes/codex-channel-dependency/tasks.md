## 1. Tests first (RED)

- [x] 1.1 (Req: Codex channel is fully dependency-resolved) Reshape scripts/tests/model-generation-sync/test.sh: single-pin 契約遷移 — assert `bin/codex-call` 不存在、SKILL 含 `MIN_CODEX_PRO="0.7.0"` / `defaults.json` / `codexModel` / `PAI_CODEX_CALL` / `MIN_PAI="2.19.0"` / 安裝指令 `claude plugin install codex-pro@codex-pro`；refute `--model gpt-5` hard-pin 維持；idd-route 斷言維持。Run: RED。

## 2. Implementation (GREEN)

- [x] 2.1 (Design D1 — executable 歸 pai，前置區先解析; D2 — 治理歸 codex-pro：contract-pinned; D4 — canonical tier 傳參) skills/idd-verify/SKILL.md: 前置區重排（PAI_DIR 先解析 + PAI_CODEX_CALL + codex-pro governance 解析 block + fail-fast）；MIN_PAI 2.19.0 + gate 理由；Workflow args 加 codexModel/codexEffort、codexCallPath 改 PAI_CODEX_CALL；manual fan-out 與 legacy 直呼段帶顯式 --model/--effort/--max-time；Step 0 TaskCreate 清單補 governance pre-flight。
- [x] 2.2 (Design D3 — 依賴接線 superpowers 形狀) 刪 plugins/issue-driven-dev/bin/codex-call；plugin.json dependencies 加 codex-pro@codex-pro；root marketplace.json allowCrossMarketplaceDependenciesOn 加 codex-pro。
- [x] 2.3 (Design D5 — drift-guard 重塑) Verify: model-generation-sync GREEN；全 plugin sweep 0 fail；spectra validate clean。
