## Context

#207（使用者依賴裁決）。pai 2.18.0 契約：args `profile|file|diffFile|contextBlock|customLenses|daFocus|codexEnabled|codexCallPath|agentModel|maxAgents…`；return `{findings[{lens,severity,title,file,body}], verdict, stats.dispatchModel}`——與 IDD 現引擎同構（血緣 fork）。

## Goals / Non-Goals

Goals：canonical 依賴為主路徑、版本閘門防契約前引擎、三層 graceful degrade、fork 凍結。Non-goals 見 proposal。

## Decisions

### D1 — 三層解析鏈 + 版本閘門

```
PAI_ENGINE=$(ls -d ~/.claude/plugins/cache/parallel-ai-agents/parallel-ai-agents/*/ 2>/dev/null | sort -V | tail -1)
PAI_VER=$(basename "$PAI_ENGINE")   # cache 目錄名即版本
MIN_PAI=2.18.0                      # agentModel + STABLE 契約起點
若 PAI_ENGINE 存在且 sort -V 判 PAI_VER ≥ MIN_PAI 且 workflows/ensemble-workflow.js 存在
    → backend = pai-ensemble（canonical）
否則若 dynamic-workflow primitive 可用 → backend = vendored fallback（凍結 fork）
否則 → manual fan-out
```

每層印 notice：`→ verify backend: pai-ensemble 2.18.0 (canonical)` / `vendored fallback (pai absent or < 2.18.0)` / `manual fan-out`。**閘門理由**：2.17.0 引擎會靜默忽略 `agentModel`（無此參數）→ 派發回退繼承 session model（#205 根因復發且審計行造假）——寧可用自家已修的 fork 也不用契約前的 canonical。

### D2 — args 映射（IDD lens 語意以 custom profile 表達）

`profile:'custom'`；`customLenses` = requirements / logic / security / regression 四鍵（focus 文本自 vendored 引擎 LENSES port，字面不變）；`daFocus` = 現 daPrompt 之反駁指令精髓；`contextBlock` = `DATA_GUARD 前言 + ISSUE #N: <title>\n<body>（各 issue）+ Source-of-truth attachments: <清單>`（pai 端 `dataBlock()` 對整個 contextBlock 再包 PAI_ENSEMBLE sentinel + 偽造 marker 剝除——雙層防injection）；`diffFile` 直傳；`codexCallPath` = IDD 自己 vendored 的 codex-call 絕對路徑（不依賴 pai 的 bin 佈局）；`agentModel` = 既有 Step 2 前 `IDD_AGENT_MODEL` 解析值。

### D3 — 揭露與消費

pai return 與 IDD 同構 → Step 3 normalization 原樣消費；Engine 行：`pai-ensemble <ver> — 6/6 (model: <stats.dispatchModel>)`。lens 鍵沿用 IDD 命名（customLenses 自帶鍵，harness 強制 attribution），master report 的 Source 欄零改動。

### D4 — fork 凍結

vendored `ensemble-workflow.js` header 加 FROZEN banner：fallback-only、新功能/修復一律上游 pai（canonical single source），本檔僅接受「與 pai 契約同步的必要對齊」。

## Implementation Contract

- SKILL.md 有三層解析鏈 + `MIN_PAI` 常數 + 三種 notice line；`agentModel` 傳遞至 pai args
- customLenses 四鍵 focus 與 vendored LENSES 字面一致（grep 可驗）
- vendored 引擎首屏可見 FROZEN banner
- `spectra validate` 綠；雙軌掃尾：解析鏈變更未觸碰 manual fan-out 與 dispatch-model 規則（#205 不回歸）
