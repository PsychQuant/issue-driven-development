# 2026-07-17 — 9-issue drain：5 cluster PR 全 merge（v2.97.0 + idd-route v0.2.1）

## 已 merge 至 main（PR #259–#263，皆 merge-commit 保留 per-issue commits）

- **Line A / PR #259 — #122 path catalog**（`3e2be78`）：docs/workflows.md 補 P-meeting / P-batch-drain / P-discussions-intake / P-clarify-audit 四路徑 + 決策樹 Q1.5 meeting 分流；兩矩陣補 idd-clarify 列；D12 slot 於 merge 後由 `040e39a` 指向 canonical。
- **Line B / PR #260 — #252 sdd_bias 開關**（`8e45053`，Spectra `sdd-bias-switch`）：硬閘命中 `sdd_bias: high` 升 `Spectra via hard-gate (sdd_bias)`；default/absent/invalid 逐 byte 維持 Plan。**#120 Layer V deferred-record**（`5340781`）：registry literal `unattended-auto-Step-3.4-layerV-deferred` 三處鎖定；unattended 觸發寫結構化回補記錄，idd-all Phase 6 聚合。
- **Line C / PR #261 — #258 verify profiles**（`d227568`，Spectra `verify-profiles`）：`--profile code/prose/academic` 四元組 + `--file`/`--dir` 輸入源 + file SHA-256 freshness gate（#228 等價物）+ config `verify_profiles`。**#251 model 世代同步**（`ede816e`）：live probe `gpt-5.6-sol` 成功 → codex-call default 為全樹唯一 pin；散文世代中立（`gpt-5.x`）；idd-route candidate 更名 `codex-xhigh`（idd-route v0.2.1）。
- **Line D / PR #262 — #133 dashboard comment 契約**（`1307af7`）：`<!-- idd:dashboard -->` marker + 只綁 phase 轉換（anti-#116）；4 lifecycle SKILL 接線。**#134 idd-report --rollup**（`583e505`）：四分組 attention 視圖、pull-only invariant。
- **Line E / PR #263 — #139 /idd-find**（`e0375cf`，Spectra `idd-find-skill`）：open+closed 全語料 relevance 查找、surfacing-only、v1 誠實邊界。**#140 family 文件**（`f151c81`）：`references/surfacing-primitives.md` D12 軸 + 增員判準。

9 issue 均已依 close ritual 結案（各自獨立 closing summary + body sync + dashboard 首發 — 後者是 #133 契約當日 dogfood）。3 個 Spectra change 已 archive（specs：complexity-hard-gate modified；idd-verify +3；idd-find +2 新 capability）。

測試：5 新 drift-guard suites，聚合器 **36 suites 0 fail**。**v2.97.0 + idd-route v0.2.1** 同日發版，marketplace 已同步。

CLAUDE.md：plugin CLAUDE.md 已於 PR #263 加 idd-find 列；專案 CLAUDE.md 無需更新。
