## Why

idd-* 產出的 comment 全部是 audit-facing（closing 五段式、verify master report、idd-comment 六型），沒有一型是 recipient-facing。當 comment 的讀者是人類 collaborator（指導教授、review 提出者），maintainer 只能每次口頭指揮 ad-hoc 重排（PsychQuant/issue-driven-development#269 的觸發案例：6 點 review 的逐點回覆分兩輪口頭指令才成形），且沒有「每句已修正都指到真實 diff」的機械保證，也沒有語氣／對象 calibration。

## What Changes

- `idd-comment` 新增第 7 型 `--type=reply`（human-facing 逐點回覆）：對方原文逐點 verbatim blockquote → 該點怎麼改、改在哪（file / theorem / section）→ 錨定 commit / PR / merge SHA → 該點狀態；結尾整體狀態（merged SHA、同步狀態、下一步）
- 新增必填 flag `--points-from`，三層解析：顯式 comment URL → 預設 issue body 的 Original text blockquote → fallback 使用者貼上原文；逐點內容一律 verbatim，禁止 paraphrase
- **verify-before-claim gate**：每一點在 draft 內宣稱「已修正」之前，先以 `git log --grep` / PR merge 狀態驗證證據存在；無證據的點必須誠實表述為 open / pending，不得含混帶過
- **perspective-writer soft integration（graceful degrade）**：`check-plugin-presence.sh perspective-writer perspective-writer` 命中 → draft 經 `Skill(perspective-writer:perspective-writer)` 做 voice / recipient calibration；缺席 → 印一行安裝指令（`claude plugin marketplace add PsychQuant/perspective-writer` + `claude plugin install perspective-writer@perspective-writer`）並照 post 未 calibrate 的 draft。不新增 install-time `dependencies` 條目
- **執行序不變量**：referent 錨定（SHA / 檔案 / 定理引用 / verbatim 引文）在 calibration 之前完成；calibration 不得改動任何錨定事實
- reply comment 是 closing summary 的加項，不取代任何 audit-facing 產出；egress 沿用 gh-egress choke-point（scrub + mention attestation 既有契約組合不變）
- 新增 drift-guard 測試 suite 鎖住上述 SKILL.md 契約元素（必填 flag、degrade 安裝指令 literal、執行序不變量）

## Non-Goals

- 不做 `--audience` 正交 flag（6 型 × audience 組合矩陣的 spec 面積不成比例）；不開新 skill（與 idd-comment 既有機制 70% 重疊）
- 不改動既有六型模板與其必填欄位驗證
- 不定義 perspective-writer 端的 EXTERNAL-CONSUMER CONTRACT（另案 PsychQuant/perspective-writer#1；本案只依賴 presence check + graceful degrade，契約收斂後可後續升級整合深度）
- 不涵蓋 PR description / GitHub Discussions 報告等其他 human-facing 輸出面（同 horizon、另案處理）

## Capabilities

### New Capabilities

- `idd-comment-reply`: idd-comment 的 human-facing `--type=reply` 逐點回覆型 — 逐點 verbatim 引文結構、verify-before-claim gate、perspective-writer soft integration 與 graceful degrade、referent 錨定先於 calibration 的執行序不變量

### Modified Capabilities

(none)

## Impact

- Affected specs: 新增 `idd-comment-reply`（既有 `superpowers-integration` 不修改 — 本案刻意走 soft 側，設計對比記於 design.md）
- Affected code:
  - New: plugins/issue-driven-dev/scripts/tests/idd-comment-reply/test.sh
  - Modified: plugins/issue-driven-dev/skills/idd-comment/SKILL.md, plugins/issue-driven-dev/README.md, docs/commands.md, docs/workflows.md, plugins/issue-driven-dev/CHANGELOG.md, plugins/issue-driven-dev/.claude-plugin/plugin.json, .claude-plugin/marketplace.json
  - Removed: (none)
