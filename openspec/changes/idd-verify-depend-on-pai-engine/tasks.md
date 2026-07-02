## 1. SKILL.md — 三層 backend 解析鏈

- [x] 1.1 「Capability detection + fallback」段改三層：pai canonical（cache `sort -V` 最高版 + `MIN_PAI=2.18.0` 閘門）→ vendored fallback → manual fan-out；三種 notice line
- [x] 1.2 pai 路徑的 args 映射：profile:'custom'、customLenses ×4（focus 字面 port 自 vendored LENSES）、daFocus、contextBlock（DATA_GUARD + issues + attachments）、diffFile、codexCallPath（IDD 自有）、agentModel
- [x] 1.3 Engine 行揭露格式：canonical 帶 `pai-ensemble <ver>` + `stats.dispatchModel`

## 2. vendored 引擎凍結

- [x] 2.1 ensemble-workflow.js header 首屏 FROZEN banner（fallback-only；新功能一律上游 pai）

## 3. 收尾

- [x] 3.1 plugin.json 2.88.0 → 2.89.0 + CHANGELOG 條目
- [x] 3.2 `spectra validate` 綠；雙軌掃尾（manual fan-out 與 #205 dispatch-model 規則零回歸；customLenses focus 與 LENSES 字面一致 grep 驗證）
