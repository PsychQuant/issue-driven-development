## Why

`idd-verify` 的兩條 agent 派發路徑（dynamic-workflow 的 `agent()`、manual fan-out 的 `Agent()`）均未指定 model → agents 繼承主迴圈模型。高階模型 session 下每輪 verify 實測燒 563k–1,092k subagent tokens；實證（2026-07-02, PsychQuant/bestASR#14 verify 輪）devil's advocate 逐字死因 `You've hit your session limit`——quota 耗盡把 6-AI 降級 4-AI，直接侵蝕對抗深度。使用者裁決（#205）：預設 `opus` + 覆蓋機制，範圍全部 fan-out 盤點。

## What Changes

1. `ensemble-workflow.js`：args 增 `agentModel`（預設 `'opus'`）；reviewers / codex-runner / devil's-advocate 三個 `agent()` 站點帶 `model: A.agentModel`。
2. `skills/idd-verify/SKILL.md`：workflow 呼叫段解析 `IDD_AGENT_MODEL`（env var；缺省 `opus`；非法值 fail-loud）傳入 args；manual fan-out 的 5 個 `Agent()` 模板 + Step 2.5 retry 加 `model` 參數；文件化覆蓋機制。
3. `references/spectra-skills/spectra-archive/SKILL.md`：sync 委派（Task general-purpose）加 model 註記。
4. Spec `idd-verify`：MODIFIED——dispatch model requirement（default opus、`IDD_AGENT_MODEL` 覆蓋、Codex 例外聲明——它經 codex-call 跨模型，本就不吃 Claude model 參數，但其 runner agent 吃）。

## Non-Goals

- 不改 parallel-ai-agents plugin（tracking PsychQuant/parallel-ai-agents#20 另行處理）
- 不改 Codex lens 的跨模型契約（gpt-5.5 via codex-call 不變）
- 不加 per-lens 分級模型（如 DA 用高階、reviewer 用低階）——v1 單一預設，分級留未來
- 不動 spectra-archive 委派以外的非 verify 派發（盤點確認無其他站點）

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `idd-verify`: agent dispatch model requirement（default opus + env 覆蓋）

## Impact

- Affected specs: `idd-verify`（MODIFIED）
- Affected code:
  - Modified: plugins/issue-driven-dev/skills/idd-verify/ensemble-workflow.js, plugins/issue-driven-dev/skills/idd-verify/SKILL.md, plugins/issue-driven-dev/references/spectra-skills/spectra-archive/SKILL.md, plugins/issue-driven-dev/CHANGELOG.md（若有）
  - New: (none)
  - Removed: (none)
