## Context

idd-comment 現有六型（decision / note / question / correction / link / errata）全部 audit-facing：讀者是未來回來考古的 maintainer 或 AI。#269 的觸發案例顯示第七種讀者真實存在——review 提出者（人類 collaborator）要的是「我提的第 3 點你怎麼處理了」，而非聚合式 closing summary。

三個既有資產構成設計素材：

1. **suggestion-report skill**（ai_martech_principles，repo 外 prior art）：逐點「客戶反映（blockquote 原文）→ 問題原因 → 解決方式 → 目前狀態」模板，加上「寫報告前強制 verify completeness」紀律（per-issue commits check、實質性 spot-check）——與本案 R1 / R2 同構且已實戰驗證。
2. **perspective-writer plugin**：已抽成 standalone marketplace（`PsychQuant/perspective-writer`，v2.10.0，cache 座標 `perspective-writer/perspective-writer/<ver>`）。提供 voice / recipient calibration、T-Schema referent 紀律、per-recipient rules 學習迴圈（draft-learner / save-feedback → target repo `.claude/rules/correspondence-*.md`）。consumer-facing 契約另案（PsychQuant/perspective-writer#1）。
3. **superpowers-integration spec**（本 repo）：跨 plugin delegation 的 hard-dependency 前例——fail-fast、無 fallback，理由是「canonical process 替代、built-in 等價敘述已刪除、無物可退」。

## Goals / Non-Goals

**Goals:**

- `--type=reply`：recipient-facing 逐點回覆型，結構正確性（逐點 verbatim + 錨定 + 誠實狀態）由 IDD 自有紀律保證
- perspective-writer 缺席時功能完整可用（graceful degrade），命中時自動 calibration
- 契約元素被 drift-guard 測試鎖住（與 repo 既有 38 suites 同慣例）

**Non-Goals:**

- 不做 `--audience` 正交 flag、不開新 skill、不動既有六型
- 不定義 perspective-writer 端 EXTERNAL-CONSUMER CONTRACT（PsychQuant/perspective-writer#1）
- 不涵蓋 PR description / Discussions 報告等其他 human-facing 面

## Decisions

**D1 — 第 7 型，不是 audience flag、不是新 skill。** idd-comment 的架構是「per-type 模板 + per-type 必填欄位驗證」（decision 要 `--quote`、errata 要 `--target-comment`）；`reply` 帶必填 `--points-from` 完美嵌入。替代案 `--audience human` 需要定義 6 型 × audience 的組合矩陣（每型的 human 變體語意），spec 面積不成比例；新 skill 違反 70%-重疊反模式（target resolution、mention 協定、egress、body 同步全部要複製）。

**D2 — soft integration + graceful degrade，刻意走 superpowers 的另一側。** superpowers-integration 的 fail-fast 前提是「SHALL NOT fall back to built-in equivalent」——IDD 已刪除自有 process 敘述，缺 plugin 即無物可退。`reply` 相反：逐點結構與 verify-before-claim gate 是 IDD 自有紀律，缺 calibration 時輸出仍完整正確。故 presence check（`check-plugin-presence.sh perspective-writer perspective-writer`）命中 → calibration；缺席 → 印一行含兩步安裝指令的 notice 照 post。**不**新增 install-time `dependencies` 條目（soft = runtime-only，manifest 零改動）。替代案 hard fail-fast 會把 enhancement 綁架成 hard dependency，讓沒裝該 marketplace 的公共使用者連逐點 reply 都不能用。

**D3 — `--points-from` 三層解析 + verbatim 鐵律。** (1) 顯式 comment URL 或字面值 `issue-body`；(2) 未指定時預設抓 issue body 的 Original text blockquote（idd-issue 建案紀律保證其存在於多數 issue）；(3) 兩者皆無 → 要求使用者貼上原文（AskUserQuestion / 對話）。逐點內容一律 verbatim blockquote，禁止 paraphrase——收件人看到自己的話被改寫即失去信任（IC_R007 同源紀律）。

**D4 — recipient context 留在 target repo，IDD 只傳 pointer。** `--mention <login>` 走既有 tagging-collaborators 5-step 協定 resolve；calibration 階段把 resolved login 與 target repo `.claude/rules/correspondence-<person>.md`（若存在）的路徑交給 perspective-writer。關係語境不進 plugin、不跨專案共享。rules 檔缺席時由 perspective-writer 自行 fallback（其 6-phase 流程含 recipient interview），IDD 不複製該邏輯。

**D5 — 執行序不變量：錨定在前、calibration 在後。** draft 流程固定為：逐點 verbatim 引文組裝 → verify-before-claim（每點以 `git log --grep "#N"` / PR merge 狀態驗證證據；無證據的點寫 open / pending）→ referent 錨定完成（SHA、file / theorem 引用）→ 才進 calibration → egress。calibration 不得改動錨定事實（SHA、引用、verbatim 引文原文）；違反即為 bug。理由：先潤飾再錨定會讓句子找不到對應 diff，T-Schema 破功。

**D6 — verify-before-claim 是 prose 紀律 + drift-guard，不是新 script。** 檢查邏輯與 idd-close Step 1.6 semantic gate 同族（keyword → artifact 存在性），在 SKILL.md 以步驟陳述並由測試 suite 鎖關鍵字，不另寫 helper script——避免與既有 gate 形成兩份漂移的實作。

## Implementation Contract

- **Command shape**：`/idd-comment #N --type=reply --points-from=<comment-url|issue-body> [--mention <login>] [--body "<per-point 說明素材>"]`。`--points-from` 缺席 → Step 2 validation 拒絕（與 decision 缺 `--quote` 同機制）。
- **模板產出**（SKILL.md 新增 `#### Template: reply`）：每點一段 `> {verbatim 原文}` → 處理說明（哪裡改、怎麼改、cross-link commit / PR / label）→ 狀態（✅ 已解決（`<sha>`）/ ⏳ open）；結尾整體狀態行（merged SHA、同步狀態、下一步）；metadata marker `<!-- idd:comment type=reply date=... points-from=... calibrated=yes|no -->`。
- **Degrade notice literal**（缺 perspective-writer 時印出，內容進 SKILL.md 固定文字）：`claude plugin marketplace add PsychQuant/perspective-writer` + `claude plugin install perspective-writer@perspective-writer`。
- **Egress**：沿用 `gh-egress.sh comment` + `--scrub-attested` + （有 mention 時）`--mention-attested`——與既有六型同 choke-point，零新 egress 面。
- **驗證目標**：新 suite `plugins/issue-driven-dev/scripts/tests/idd-comment-reply/run.sh` 斷言 SKILL.md 含：(a) reply 型必填 `--points-from` 驗證列於 Step 2 表格；(b) degrade 安裝指令兩行 literal；(c) 執行序不變量字句（錨定在前 / calibration 不得改動錨定事實）；(d) presence-check 座標 `perspective-writer perspective-writer`。`run-all-tests.sh` 全綠（38 → 39 suites）。
- **文件同步**：docs/commands.md 型別清單、docs/workflows.md matrix 行、plugins README 型別摘要、CHANGELOG 版本段。
