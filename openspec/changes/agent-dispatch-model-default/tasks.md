## 1. ensemble-workflow.js — dispatch model 解析與注入

- [x] 1.1 頂部（args 解析區）加 `AGENT_MODEL`：`['sonnet','opus','haiku','fable'].includes(args.agentModel) ? args.agentModel : 'opus'`（兜底層，D1）
- [x] 1.2 三個 agent() 站點（reviewers / codex-runner / devil's-advocate）opts 加 `model: AGENT_MODEL`
- [x] 1.3 workflow 回傳物件帶 `dispatchModel: AGENT_MODEL`（供 master report Engine 行揭露，D3）
- [x] 1.4 `node --check ensemble-workflow.js` 通過

## 2. idd-verify SKILL.md — env 解析、args 傳遞、手動模板

- [x] 2.1 Step 2（engine 選擇）前加 `IDD_AGENT_MODEL` 解析段：未設 → `opus`；非法值 → abort with usage error（fail-loud，D1 第一層）
- [x] 2.2 Workflow 呼叫 args 加 `agentModel: $RESOLVED_MODEL`
- [x] 2.3 5 個手動 fan-out `Agent({...})` 模板各加 `model: "<resolved model (default opus)>"`
- [x] 2.4 Step 2.5b retry 模板（fresh Agent spawn）與 light-mode 段落同步加 model 註記
- [x] 2.5 master report Engine 行格式加 dispatch model 揭露（例 `6-AI (model: opus) + Codex`）

## 3. spectra-archive reference — 委派 model 註記

- [x] 3.1 `references/spectra-skills/spectra-archive/SKILL.md` 的 Task(general-purpose) 委派處加同一解析規則註記

## 4. 收尾

- [x] 4.1 plugin.json 2.87.0 → 2.88.0 + CHANGELOG.md 條目
- [x] 4.2 盤點 grep（`Agent({|agent(`）確認零未指定站點；`spectra validate` 通過
