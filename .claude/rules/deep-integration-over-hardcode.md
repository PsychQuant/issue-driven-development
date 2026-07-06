# Deep Integration over Hard-Coding（深度整合 >> hard-coded）

> **Scope**：本 rule 適用於 `issue-driven-development` repo 的任何 Claude session，當 IDD 需要一種能力、而生態系已有對應套件（plugin / skill / engine）時的取捨。dev-only 專案 rule — 不隨 plugin 發佈（per #209 Clarity row 3 裁決：「不用一起上傳，是我開發要用的而已」）。

## 核心原則

**生態系有 canonical 套件時，依賴它；不在 IDD 內部複製一份等價邏輯。**

Hard-code（vendor 一份 fork、內嵌等價流程敘述、重造 resolver）的代價是同構機件兩處維護 — 同一個 bug 要修兩次（實證：#205 / pai#20，idd-verify 的 305 行 vendored ensemble fork 與 pai 的 513 行 canonical 引擎）。

## 判準鏈（依序評估）

1. **生態系有 canonical 套件嗎？** 沒有 → hard-code 是唯一選項，不適用本 rule。
2. **上游接口穩定嗎？** 判定依據（任一即可）：上游已官方化 EXTERNAL-CONSUMER CONTRACT（如 pai 2.18.0 的 STABLE args/return surface）；或套件位於官方 marketplace（`claude-plugins-official`，有 review pipeline）。都不成立 → 先推動上游凍結契約（如 pai#20 → pai 2.18.0），或落入例外 1。
3. **選擇深度整合的形狀**：
   - **依賴宣告**：plugin 對 plugin 用 `plugin.json` `dependencies`（native 機制有遞移 enable / prune / doctor 整合，自建 resolver = hard-code）；cross-marketplace 需 root marketplace `allowCrossMarketplaceDependenciesOn`
   - **存在／版本閘門**：runtime pre-flight（plugin 存在 + 接口存在；有版本契約時加 `sort -V` 版本閘門）
   - **缺席行為，二選一並記錄理由**：
     - **fail-fast**（預設）：缺席即 abort + 一步安裝指令。適用：上游內容 vendor 即複製（如 process-discipline prompt），或品質不容降級
     - **frozen-fork degrade**：僅當 fork 本來就在手上、品質等價、且有時序解耦需要（如 pai 案例等上游 ship）；fork 必須掛 FROZEN banner、新功能一律上游

## 具名例外（允許 hard-code，各須記錄）

| 例外 | 條件 | 記錄格式 |
|------|------|---------|
| **上游無穩定契約** | 上游拒絕或無法凍結接口，且推動無果 | 在引入處註記 `hard-code exception: unstable upstream（<issue/link>）` + 開 tracking issue 監看上游 |
| **隱私／安全邊界** | 整合會把第三方逐字內容或 secrets 送出信任邊界 | 在引入處註記 `hard-code exception: privacy boundary` + 引用對應 privacy rule |
| **時序解耦** | 上游修正已承諾未 ship，IDD 需先出貨 | 走 frozen-fork degrade（見上），並在 design.md 記「canonical 路徑何時點亮」 |

## Exemplars

- **pai（parallel-ai-agents）**：`openspec/changes/idd-verify-depend-on-pai-engine/` — 先推動上游官方化 STABLE contract（pai#20），再以三層解析鏈依賴（canonical + `MIN_PAI` 版本閘門 → frozen fork → manual fan-out）。時序解耦例外的標準用法。
- **superpowers（#209，change `idd-depend-on-superpowers`）**：install-time hard dependency（`dependencies` @ `claude-plugins-official`）+ 雙重 pre-flight（`check-plugin-presence.sh` 三參數）+ 缺席 fail-fast、無 fork。process-discipline 內容 vendor 即複製，故 fail-fast 是正確形狀。

## 反例（rule 反對的形狀）

- 為「保險」vendor 一份上游 skill/engine 又不掛 FROZEN banner → 兩處維護、靜默漂移
- 用 SessionStart hook 自寫 dependency 安裝邏輯，而 native `dependencies` 機制可用 → 重造 resolver
- soft fallback 到內建等價敘述 → silent degrade，品質不可預期（#209 使用者裁決：「要hard，保證品質」）
