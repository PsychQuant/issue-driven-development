## Context

#205（clarity 已裁決：預設 opus + 覆蓋、全 fan-out 盤點）。實證：高階模型 session 下每輪 verify 563k–1,092k subagent tokens；bestASR#14 verify 輪 DA 死於 session limit → 6-AI 降級 4-AI。盤點結果：派發面集中三處——ensemble-workflow.js（agent() ×3 站點）、idd-verify SKILL.md（manual fan-out Agent() ×5 + retry）、spectra-archive reference（Task 委派 ×1）。

## Goals / Non-Goals

Goals：所有派發站點帶顯式 model；預設 `opus`；`IDD_AGENT_MODEL` env var 覆蓋（值域 `sonnet|opus|haiku|fable`，非法值 fail-loud）；spec 對齊。Non-goals 見 proposal（parallel-ai-agents 另 repo、per-lens 分級、Codex 跨模型契約不動）。

## Decisions

### D1 — 雙層預設（skill 端解析 + workflow 端兜底）

Skill 在組 workflow args 時解析 `IDD_AGENT_MODEL`：未設 → `'opus'`；設了但非法 → **abort with usage error**（不靜默回退——使用者顯式設定錯值時安靜換模型比失敗更糟）。workflow 端兜底改為**同樣 fail-loud**（verify F4 對齊 spec「invalid SHALL fail loudly at dispatch time」）：顯式非法值 `throw` 於任何派發前；只有 **absent**（legacy caller 未傳 `agentModel`）才回退 `'opus'`。兩層一致，程式化 caller 繞過 skill 也擋得住。

**方向性 caveat**（verify F6/F10）：預設 opus 的降負載效益只在 session tier 高於 opus 時成立（#205 事故 session 為 Fable 級——live run wf_6c1d8ee6-5f3 證實 pin 後 6 agent 全跑 claude-opus-4-8，真降級）；session 本身低於 opus 時預設是升級，要省 quota 需顯式降級覆蓋。此非缺陷（#205 明確要求預設 opus），但文件如實揭露。

### D2 — 站點覆蓋

ensemble：reviewers、codex-runner（跑 codex-call 的 Bash-agent 本身）、devil's-advocate 三站點 `{ ..., model: AGENT_MODEL }`。manual fan-out：5 個 `Agent({...})` 模板 + Step 2.5b retry 的**具體** fresh-spawn 模板都帶 `model: "${AGENT_MODEL}"`。**verify 抓出的補齊面**（首輪字面 grep 對 prose 派發盲視）：idd-diagnose #182 fan-out（investigator/synthesis/skeptic）、parallel-orchestration.md 契約條款、spectra-audit 3-agent、spectra-apply `[P]` 平行、spectra-archive sync 委派——vendored spectra-* 為 doc-only 對齊（該樹是第三方 reference copy，不在本 plugin 執行週期；canonical 規則住在 idd-verify）。

### D3 — 揭露

master report 的 Engine 行加註 dispatch model（例：`5 general-purpose Agents (model: opus) + Codex`）——審計軌跡可見「這輪 verify 用什麼模型跑的」，成本異常時可追。

## Implementation Contract

- `grep -n "model" ensemble-workflow.js`：三個 `agent(` 站點皆含 `model: AGENT_MODEL`；`AGENT_MODEL` 由 `args.agentModel` 解析、預設 `'opus'`
- SKILL.md：`IDD_AGENT_MODEL` 解析段存在（含值域驗證 + 可執行的 fail-loud——`exit 64`，不用未定義 helper）；workflow args 傳遞 `agentModel`；5 個 Agent 模板 + retry 具體模板含 model；Engine 行揭露以 workflow 回傳的 `dispatchModel` 為準（degraded args 時與 skill 端變數可能不同）
- spectra-archive SKILL.md 委派處含 model 註記
- spec delta validate 通過；盤點 grep（`Agent({|agent(`）零未指定站點（Codex 之 gpt-5.5 端例外——不經 Claude model 參數）
