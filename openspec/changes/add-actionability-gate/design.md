## Context

`/idd-list` 與 `/idd-all` 的 routing 需要回答一個問題：**這個 issue 現在可不可以動？** 目前四個候選訊號中只有一個有 routing consumer：

| 訊號 | 位置 | 生命週期 | 現況 |
|---|---|---|---|
| `### Complexity` 的限定詞 | Diagnosis comment（append-only）| 凍結 | 被三個 consumer 各自窄化，互不相容 |
| `parking-lot` label | Issue labels | 可變 | 無 producer、無 consumer |
| `### Blocking` 區塊 | Issue body（`idd-update` 維護）| 可變 | 有 consumer（#84）|
| Strategy `[~] 暫緩` | Diagnosis comment | 凍結 | 有 consumer，但屬 `idd-close` 的 close-time disposition |

2026-08-10 實測：22-issue backlog、11 個 diagnosed，routing 判對 1 個、判錯 8 個。`#131` 與 `#200` 帶有使用者親自下的 defer 裁決，routing 仍建議執行。

實測另一項數據推翻了「限定詞與 label 資訊重複」的假設：11 個 issue 中兩者**一致的只有 5 個**。`#37` 是 bare `Spectra` 加 `parking-lot` label（人事後 park）；`#131` 與 `#200` 是有限定詞、無 label（diagnose 判 parked 但無人貼 label）；`#136` 的 comment 與 body 甚至彼此分岔。兩者不是同一資訊的兩種寫法，而是**兩個會分岔的訊號**。

約束：`rules/append-vs-modify.md` 規定 Diagnosis comment 是 append-only 審計軌跡。既有的 `### Conflict Class` 契約（openspec/specs/parallel-orchestration/spec.md）已示範了正確形狀 —— 封閉值域、absent 或 unparseable 時保守預設、且必須 surface —— 本設計以之為對照模型。

## Goals / Non-Goals

**Goals:**

- 讓 routing 能區分「diagnosed 且現在可動」與「diagnosed 但在等 trigger」
- 把 parked 這個**會變的狀態**從不可變的 artifact 遷到可變的 metadata
- 消除三個 consumer 各自窄化 `### Complexity` 的分岔
- 保留 #84 既有的 Blocked 分組輸出行為，不退化
- 建立可被未來新欄位繼承的通則：被 routing 消費的欄位必須宣告封閉值域與 unparseable 契約

**Non-Goals:**

- **不 parse diagnosis 散文抽取 trigger 條件**。trigger 是關於未來世界狀態的散文命題（「等 ≥3 instances」「首次 trace-stale 實害事故」），其成立與否需要人對世界的觀察，不在 repo 內。這是認識論邊界，非本設計的遺漏。
- **不新增 `### Park Trigger` 結構化欄位**。
- **不讓 producer 自動貼 `parking-lot` label**（理由見決策「parked label 維持人工裁決」）。
- **不把 Strategy `[~] 暫緩` 納入 gate**（理由見決策「gate 採三訊號」）。
- **不做 parked issue 的回訪／staleness 機制** —— 已獨立為 #310。本變更會把 parked 藏得更乾淨、放大該問題，但兩者範圍分離。
- **不改寫既有 Diagnosis comment 的歷史內容**（理由見決策「migration 只貼 label」）。
- **不退役 `SDD-warranted`** —— 它是 `Spectra` 的既有 backward-compat alias，留在封閉值域內。

## Decisions

### Complexity 回歸純封閉值域，parked 遷出至 label

`### Complexity` 的合法值僅四個 tier（`Simple` / `Plan` / `Spectra` / `SDD-warranted`），各自可帶既有的 ` via <來源>` 後綴慣例。parked 狀態改由 `parking-lot` label 單獨承載。

理由：根因不是 parser 太窄，而是**把會變的狀態存進不可變的 artifact**。Diagnosis comment 是 append-only，parked 卻會變（trigger 成立就該 unpark）。`#136` 的 comment 與 body 分岔，正是狀態被凍住後自行漂移的自然實驗。IDD 已經知道正確做法 —— `### Blocking` 正因為會變才放在 body 由 `idd-update` 維護。

替代方案：(a) 讓 `when triggered` 成為合法後綴，兩訊號並存 —— 但實測已證明兩者會分岔，並存就必須定義優先序，而該優先序沒有非任意的答案；(b) 只加寬三個 parser —— 會讓三個 consumer 一致地讀到一個會分岔的訊號，一致地錯比不一致地錯更難發現。

### gate 採三訊號，Strategy 暫緩標記排除在外

actionability gate 的輸入是三個訊號：`### Complexity` 非合法值、`parking-lot` label 存在、`### Blocking` 區塊非空。放行需三者皆不成立。Strategy 的 `[~] 暫緩` **不納入**。

理由：`[~]` 的既有 consumer 是 `idd-close` 的 checklist gate，語意是「close 時這個 checklist item 刻意跳過」—— 那是 per-item 的 close-time disposition，不是 per-issue 的「現在可不可以動」。把它拉進 routing gate 等於用回答 A 問題的訊號去回答 B 問題，且會與 `idd-close` 的既有語意衝突。

### unparseable 的保守處置為 not-actionable 並強制 surface

`### Complexity` 值不在封閉值域內時，gate 判定 not-actionable，且**必須顯示原始值**供人判讀，絕不靜默截斷。完全缺少 `### Complexity` 區段時同樣 not-actionable，理由標為 missing。

理由：完全對稱於 `### Conflict Class` 的 `D_diagnose_first` 契約 —— 保守預設加強制 surface。既有 `idd-all` 的 `UNKNOWN` 安全網只覆蓋「regex 完全沒 match」，結構上接不住「match 到但值非法」，本決策把兩種失敗都納入。

替代方案：降級為 `Plan` —— 否決，`Plan` 仍是可動 tier，仍會把 parked issue 送進 `/idd-plan`；中斷整個 `idd-list` —— 否決，對 surfacing-only 工具過重，一筆壞資料會堵死全部輸出。

### 解析與判定抽為共用 helper

`### Complexity` 的解析與 actionability 判定抽成單一 shell helper，四個 skill 引用同一份實作，不各自內嵌。

理由：`.claude/rules/deep-integration-over-hardcode.md` 的反複製判準 —— 同構機件兩處維護等於同一個 bug 要修多次，本 issue 正是該失敗模式的實例（三處實作、三種行為）。

### migration 只貼 label，不改寫歷史

既有 9 筆帶限定詞的 Diagnosis comment **維持原狀不改寫**。migration 的動作只有兩種：對應 issue 補上 `parking-lot` label（若缺），以及 `#128` 由人重新判斷。

理由：改寫既有 Diagnosis comment 的 `### Complexity` 是 modify-in-place 一個 append-only 審計 artifact，違反 `rules/append-vs-modify.md`。而且**不需要改寫** —— legacy 限定詞值在新契約下落入 unparseable 路徑，判定為 not-actionable 並顯示原值，對那 8 個 parked issue 而言正是正確結果。封閉值域約束的是**新產出的** diagnosis；歷史值由 unparseable 路徑正確承接。

替代方案：回填改寫 —— 否決，違反 append-only 且無必要；永久放寬值域容忍 legacy —— 否決，會讓封閉值域名存實亡。

### parked label 維持人工裁決，producer 不自動貼

`idd-diagnose` **不**自動貼 `parking-lot` label。

理由：限定詞是 diagnose 當下的 AI 判斷，label 是人的裁決，兩者語意不同。`#37` 是 bare `Spectra` 加 label —— diagnose 當時（2026-05-19）判的是可動，label 是 2026-08-10 由人 re-park 時貼上。若讓 producer 從限定詞推導 label，就等於宣告 parked 只能在 diagnose 當下決定，這條事後裁決路徑會消失。

### 顯示分兩組以保留 #84 既有輸出

gate 產出 verdict 加 reason 清單；顯示層依 reason 分兩組 —— reason 為 blocking 者維持 #84 既有的 Blocked 分組與其 banner、footer 計數逐字不變；reason 為 parking label 或 complexity 相關者進新的 Parked 分組。

理由：gate 統一不等於顯示統一。把兩者合併成單一分組會構成 #84 的輸出退化，而 #84 的 anti-anxiety surface 是使用者依賴的既有行為。分組拆分讓「統一判定」與「不退化」同時成立。

### parking 慣例收斂為 parking-lot

`references/ic-r011-checkpoint.md` 中 `blocker:infeasible` 與 `blocker:waiting` 的敘述改為 `parking-lot`，或明記兩者分工。

理由：vocabulary drift —— 文件寫的兩個 label 目前各 0 個 issue 在用，實際在用的 `parking-lot` 有 6 個。該檔同時宣稱存在一個「periodic backlog grooming」機制去 grep 那兩個 label；該機制不存在且會掃到空集合（已獨立為 #310）。本變更只收斂 label 名稱，不實作 grooming。

## Implementation Contract

**Behavior** — 跑 `/idd-list` 時，被 gate 判為 not-actionable 的 issue 不再出現在 Suggested next 的可動清單，改列於 Blocked 或 Parked 分組並附判定理由；`### Complexity` 值非法時，該值原文顯示於輸出中。`/idd-all`、`/idd-implement`、`/idd-plan` 拿到非法 Complexity 值時停止 routing 並回報原值，不再落入未定義行為。

**Interface** — 共用 helper 提供兩個函式：

- `idd_parse_complexity`：輸入為 Diagnosis comment 全文，stdout 為 canonical tier（四個合法值之一）。exit 0 表示合法（bare tier 或帶 ` via <來源>` 後綴）；exit 3 表示區段存在但值不在封閉值域，stderr 輸出 `unparseable-complexity: <原始值>`；exit 4 表示缺少 `### Complexity` 區段，stderr 輸出 `missing-complexity`。
- `idd_actionability_verdict`：輸入為前一函式的 exit code、是否帶 `parking-lot` label、`### Blocking` 是否非空。stdout 為 `actionable`，或 `not-actionable: <reason>[; <reason>...]`；exit 0 為 actionable、exit 1 為 not-actionable。

**Reason 值域**（封閉列舉，四個）：`complexity-unparseable`、`complexity-missing`、`parking-lot-label`、`blocking-nonempty`。

**Failure modes** — 非法 Complexity 值一律 surface，絕不靜默截斷或降級為合法 tier。helper 本身不可用（檔案缺失）時，呼叫端 fail-loud 並指出缺失路徑，不 silent degrade 回舊行為。gate 不對「trigger 條件是否已成立」做任何判斷，該問題明確在範圍外。

**Acceptance criteria**

- 新增測試以既有慣例落在 `plugins/issue-driven-dev/scripts/tests/actionability-gate/test.sh`，並登錄進 `plugins/issue-driven-dev/scripts/run-all-tests.sh`。
- fixture 為靜態對照表，記錄 issue 號、Complexity 原始值、labels、期望 verdict，覆蓋 2026-08-10 快照的 9 筆 diagnosed 路由，斷言其中只有 `#37` 為 actionable。fixture 不查詢 live GitHub。
- 三個代表性 legacy 值（`Simple when triggered`、`Spectra when triggered (parking lot)`、`#128` 的散文值）經 `idd_parse_complexity` 皆回 exit 3 並在 stderr 顯示原值。
- 兩個既有的合法後綴值（`Plan via Layer V`、`Spectra via hard-gate (sdd_bias)`）經 `idd_parse_complexity` 回 exit 0 且 canonical tier 分別為 `Plan` 與 `Spectra`。
- #84 既有行為回歸測試：帶非空 `### Blocking` 的 issue 仍列於 Blocked 分組，該分組標題、全 blocked banner 文案、footer 計數與變更前逐字相同。

**Scope boundaries**

- 範圍內：Complexity 值域契約、三訊號 gate、共用 helper、四個 skill 的引用改寫、`ic-r011-checkpoint.md` 的 label 名稱收斂、測試與 fixture、9 筆 issue 的 label migration。
- 範圍外：parked 回訪／staleness 機制（#310）、`--limit` 排序缺陷（#299）、trigger 條件的機械判定、`idd-close` 對 Strategy `[~]` 的既有處理、grooming 機制的實作。

## Risks / Trade-offs

- **#84 行為退化** → 顯示層分兩組而非合併，Blocked 分組的標題、banner、footer 計數列入回歸測試逐字比對。
- **四個 skill 改寫不同步，只修一處等於沒修** → 抽共用 helper，並在測試中對四個引用點各驗一次；只修 `idd-list` 會讓 `idd-all` 的未定義行為留存。
- **與 #299 同檔衝突** → 兩者都修改 `plugins/issue-driven-dev/skills/idd-list/SKILL.md`，需序列化或合併為同一 PR；conflict class 已判為需序列化。
- **legacy 值走 unparseable 路徑，verdict 對但 reason 不精確** → reason 會標為 `complexity-unparseable`（資料問題）而非 parked。緩解：surface 原始值，人看到 `Simple when triggered` 即可理解實情。這是不改寫歷史所付的已知代價。
- **本變更讓 parked 藏得更乾淨，放大無回訪機制的問題** → 已獨立為 #310 並在 Non-Goals 明記；本變更不因此擴大範圍。

## Migration Plan

1. helper 與新 reference 落地，四個 skill 改為引用共用實作。
2. 測試與 fixture 落地並登錄進 test runner。
3. 對 8 個既有 parked issue 補齊 `parking-lot` label（`#131`、`#200` 目前有限定詞但缺 label；其餘已有）。**不改寫任何 Diagnosis comment。**
4. `#128` 交由人重新判斷 —— 其 Complexity 值為散文（tier 後接未決 UX 軸的敘述），需決定該 issue 是 parked 或可動，再決定是否貼 label。
5. `ic-r011-checkpoint.md` 的 label 名稱收斂。

Rollback：本變更為 skill 文件、helper script 與 label 的變更，無資料遷移。回退方式為 revert commit 加撕除步驟 3 補上的 label；既有 Diagnosis comment 全程未被修改，無不可逆狀態。

## Open Questions

- `#128` 的正確處置需人判斷，migration 步驟 4 才能完成。其值為「tier 後接未決 UX 軸」的散文，無法機械判定該 issue 是 parked 還是可動。
- `ic-r011-checkpoint.md` 的兩個 `blocker:*` label 是「退役」還是「與 parking-lot 分工」，需在該檔改寫時定案。目前 0 使用，傾向退役，但若原設計意圖是區分 infeasible 與 waiting 兩種 parked 成因，則應保留並明記與 `parking-lot` 的關係。
