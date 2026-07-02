## Context

#205（clarity 已裁決：預設 opus + 覆蓋、全 fan-out 盤點）。實證：高階模型 session 下每輪 verify 563k–1,092k subagent tokens；bestASR#14 verify 輪 DA 死於 session limit → 6-AI 降級 4-AI。盤點結果：派發面集中三處——ensemble-workflow.js（agent() ×3 站點）、idd-verify SKILL.md（manual fan-out Agent() ×5 + retry）、spectra-archive reference（Task 委派 ×1）。

## Goals / Non-Goals

Goals：所有派發站點帶顯式 model；預設 `opus`；`IDD_AGENT_MODEL` env var 覆蓋（值域 `sonnet|opus|haiku|fable`，非法值 fail-loud）；spec 對齊。Non-goals 見 proposal（parallel-ai-agents 另 repo、per-lens 分級、Codex 跨模型契約不動）。

## Decisions

### D1 — 雙層預設（skill 端解析 + workflow 端兜底）

Skill 在組 workflow args 時解析 `IDD_AGENT_MODEL`：未設 → `'opus'`；設了但非法 → **abort with usage error**（不靜默回退——使用者顯式設定錯值時安靜換模型比失敗更糟）。workflow 端 `const AGENT_MODEL = ['sonnet','opus','haiku','fable'].includes(args.agentModel) ? args.agentModel : 'opus'` 兜底（舊 caller 未傳 args 時仍得到 opus，非法值在 workflow 層靜默正規化為 opus 是可接受的第二層——第一層已擋掉互動路徑）。

### D2 — 站點覆蓋

ensemble：reviewers、codex-runner（跑 codex-call 的 Bash-agent 本身）、devil's-advocate 三站點 `{ ..., model: AGENT_MODEL }`。manual fan-out：5 個 `Agent({...})` 模板 + Step 2.5b retry 模板加 `model: "<resolved>"`（SKILL.md 為 prose 模板，寫明「以 Step 2 解析的 $IDD_AGENT_MODEL（預設 opus）填入」）。spectra-archive 委派：Task 呼叫註記同規則。

### D3 — 揭露

master report 的 Engine 行加註 dispatch model（例：`5 general-purpose Agents (model: opus) + Codex`）——審計軌跡可見「這輪 verify 用什麼模型跑的」，成本異常時可追。

## Implementation Contract

- `grep -n "model" ensemble-workflow.js`：三個 `agent(` 站點皆含 `model: AGENT_MODEL`；`AGENT_MODEL` 由 `args.agentModel` 解析、預設 `'opus'`
- SKILL.md：`IDD_AGENT_MODEL` 解析段存在（含值域驗證 + fail-loud）；workflow args 傳遞 `agentModel`；5 個 Agent 模板 + retry 模板含 model；Engine 行揭露格式更新
- spectra-archive SKILL.md 委派處含 model 註記
- spec delta validate 通過；盤點 grep（`Agent({|agent(`）零未指定站點（Codex 之 gpt-5.5 端例外——不經 Claude model 參數）
