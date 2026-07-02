## Why

idd-verify vendor 一份 305 行窄化 ensemble fork，與 parallel-ai-agents（pai）的 513 行 canonical 引擎重複維護同構機件；#205/pai#20 證實同一 bug 要修兩次。使用者裁決（pai#20 decision comment 逐字在案）：「idd不是應該要依賴 parallel-ai-agents嗎…需要官方就直接依賴」。pai 2.18.0 已官方化 EXTERNAL-CONSUMER CONTRACT（args surface + return shape 為 STABLE API），依賴接口就緒。

## What Changes

1. `skills/idd-verify/SKILL.md`：backend 解析鏈改三層——(1) 已安裝 pai canonical 引擎（plugin cache `sort -V` 最高版，版本閘門 ≥ 2.18.0）→ (2) vendored fallback（凍結）→ (3) manual fan-out；args 映射（profile:'custom' + customLenses ×4 + daFocus + DATA_GUARD contextBlock + diffFile + codexCallPath + agentModel）；Engine 行揭露實際 backend + 版本
2. `skills/idd-verify/ensemble-workflow.js`：凍結 banner（fallback-only；新功能一律上游 pai）
3. spec delta：idd-verify MODIFIED（backend resolution 條款 + version-gate degrade scenario）
4. CHANGELOG + plugin.json 2.88.0 → 2.89.0

**時序解耦**：現裝 pai 2.17.0 < 閘門 → 解析鏈自然落 vendored fallback；pai 2.18.0 shipped 後 canonical 路徑零改動點亮。本 change 可先於 pai#21 merge 安全出貨。

## Impact

- Affected specs: idd-verify (MODIFIED)
- Affected code: plugins/issue-driven-dev/skills/idd-verify/SKILL.md, plugins/issue-driven-dev/skills/idd-verify/ensemble-workflow.js, plugins/issue-driven-dev/CHANGELOG.md, plugins/issue-driven-dev/.claude-plugin/plugin.json, .claude-plugin/marketplace.json（close 時 dist-sync）
- Non-goals：pai 端任何改動（契約已在 pai#20 凍結）；manual fan-out 路徑不動；vendored copy 的物理刪除（等 canonical 跑過數輪真 verify 後另議，見 issue Residue）
