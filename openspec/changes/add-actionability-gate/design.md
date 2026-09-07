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

約束：`rules/append-vs-modify.md` 規定 Diagnosis comment 是 append-only 審計軌跡。既有的 `### Conflict Class` 契約（openspec/specs/parallel-orchestration/spec.md）示範了**保守預設 + 強制 surface**這一半的正確形狀，本設計沿用；但它的**封閉值域**那一半不可照搬 —— Conflict Class 由 `idd-diagnose` 以五個固定 key 寫入，`### Complexity` 的實際產出卻是自由散文（159 筆語料中 93% 帶理由或裝飾）。同一個 producer、兩種欄位紀律，這正是前版誤植的來源。

## Goals / Non-Goals

**Goals:**

- 讓 routing 能區分「diagnosed 且現在可動」與「diagnosed 但在等 trigger」
- 把 parked 這個**會變的狀態**從不可變的 artifact 遷到可變的 metadata
- 消除三個 consumer 各自窄化 `### Complexity` 的分岔
- 保留 #84 既有的 Blocked 分組輸出行為，不退化
- 建立可被未來新欄位繼承的通則：**被 routing 消費的欄位，其判準必須以真實語料驗證**，不得從有偏樣本推導

**Non-Goals:**

- **不 parse diagnosis 散文抽取 trigger 條件**。trigger 是關於未來世界狀態的散文命題（「等 ≥3 instances」「首次 trace-stale 實害事故」），其成立與否需要人對世界的觀察，不在 repo 內。這是認識論邊界，非本設計的遺漏。
- **不新增 `### Park Trigger` 結構化欄位**。
- **不讓 producer 自動貼 `parking-lot` label**（理由見決策「parked label 維持人工裁決」）。
- **不把 Strategy `[~] 暫緩` 納入 gate**（理由見決策「gate 採三訊號」）。
- **不做 parked issue 的回訪／staleness 機制** —— 已獨立為 #310。本變更會把 parked 藏得更乾淨、放大該問題，但兩者範圍分離。
- **不改寫既有 Diagnosis comment 的歷史內容**（理由見決策「零 migration」）。
- **不退役 `SDD-warranted`** —— 它是 `Spectra` 的既有 backward-compat alias，仍是合法 tier。
- **不把延期語彙清單當成封閉列舉**。它是高精度的經驗規則，不是定義；漏抓由 `parking-lot` label 兜底。

## Decisions

### tier 以 prefix 抽取，延期以語彙偵測，parked 主訊號在 label

> **本決策於 2026-08-15 重寫**（前版：「Complexity 回歸純封閉值域」）。前版把「tier 後接文字」等同於「延期修飾語」，被 `/idd-verify --pr 318` CRITICAL-2 以真實語料證偽。原文保留於 git history。

`idd_parse_complexity` 依序：**(1)** 剝除前後 markdown 裝飾 → **(2)** 值須**以** `Simple` / `Plan` / `Spectra` / `SDD-warranted` 之一**開頭**（最長匹配優先），該開頭即為 tier；其後的一切 —— 理由、括號、` via <來源>` —— 皆不參與 tier 判定→ **(3)** 對**整個值**掃延期語彙，命中則不路由。

tier 之後的其餘文字（同行理由、括號說明）**是合法的**，不影響 tier 抽取。

**理由（159 筆 corpus 實證）**：本 repo 全部 225 個 issue 中 159 筆有 Diagnosis。形狀分佈：

| 形狀 | 數量 | 佔比 |
|---|---|---|
| tier + 同行理由 | 66 | 41.5% |
| bare tier | 45 | 28.3% |
| bare tier + markdown 裝飾 | 37 | 23.3% |
| tier + ` via <來源>` | 1 | 0.6% |
| **tier + 延期語彙** | **9** | **5.7%** |
| 無區段 | 1 | 0.6% |

**分界不在「後面有沒有字」，而在「那些字是否表達延期」。** 前版的分界把 93.1% 的正常寫法與 5.7% 的延期寫法切在同一邊，導致 66 筆本該路由的 issue 變成 hard abort。

本規則在完整 corpus 上：**149 筆正確路由 + 9 筆正確擋下 + 1 筆正確報缺區段 = 159/159，0 false positive。**

延期語彙目前為 `when triggered` / `parking lot` / `deferred` / `暫緩`。偵測必須掃**整個值**而非只掃 tier 之後 —— `#136` 的 tier 是 bare `Spectra`，延期語彙藏在括號理由內。

替代方案：(a) 前版的純封閉值域 —— 已被 corpus 證偽（42% 誤判率）；(b) 維持舊的 `([A-Za-z-]+)` 截斷 —— 對裝飾值（37 筆）完全不匹配、對延期值（9 筆）誤判可動，錯誤率 29%；(c) 只認 tier prefix 不做延期偵測 —— 那 9 筆延期會被誤判可動，等同回到 #298 的原始 bug。

### 風險姿態：label 為主、語彙為輔

延期語彙是**開放列舉**（新措辭隨時可能出現），因此失敗方向必須明確界定：

| 失敗 | 後果 | 兜底 | 可見性 |
|---|---|---|---|
| **漏抓**延期 | 退回 pre-#298 行為（以 tier 路由）| `parking-lot` label | label 在 |
| **誤抓**延期 | 正常 issue 被擋下 | 無 | 原值有 surface，人一眼可辨 |

因此：**`parking-lot` label 是 parked 的主要訊號**（人為裁決、可變、無歧義）；Complexity 的延期語彙是**次要安全網**，覆蓋 legacy 與未貼 label 的情形。語彙清單取**高精度、容忍低召回** —— 漏抓有 label 兜底，誤抓會擋住正常工作。

這與前版的姿態相反：前版讓 Complexity 欄位做主要判定，於是任何解析不確定都變成硬停。

### gate 採三訊號，Strategy 暫緩標記排除在外

actionability gate 的輸入是三個訊號：`### Complexity` 非合法值、`parking-lot` label 存在、`### Blocking` 區塊非空。放行需三者皆不成立。Strategy 的 `[~] 暫緩` **不納入**。

理由：`[~]` 的既有 consumer 是 `idd-close` 的 checklist gate，語意是「close 時這個 checklist item 刻意跳過」—— 那是 per-item 的 close-time disposition，不是 per-issue 的「現在可不可以動」。把它拉進 routing gate 等於用回答 A 問題的訊號去回答 B 問題，且會與 `idd-close` 的既有語意衝突。

### 三種不可路由狀態各有獨立 reason 並一律 surface

> **本決策於 2026-08-15 重寫**（前版：「unparseable 的保守處置」）。「不得靜默截斷 / 不得降級 / 不得中斷 listing」三條**未被推翻、原樣保留**；被推翻的是「什麼算不可路由」的定義。

`idd_parse_complexity` 的非零出口分成**三種**，各有獨立 reason：

| 狀況 | exit | reason | stderr |
|---|---|---|---|
| tier prefix 不是四值之一 | 3 | `complexity-unparseable` | `unparseable-complexity: <原值>` |
| 缺 `### Complexity` 區段 | 4 | `complexity-missing` | `missing-complexity` |
| **tier 合法但值含延期語彙** | **5** | **`complexity-deferral-marker`** | **`deferral-marker: <原值>`** |

三者一律**顯示原始值**供人判讀。

**為何延期要獨立於 unparseable**：兩者的**人工處置完全不同**。`complexity-unparseable` 是**資料錯誤**（diagnosis 寫壞了，該修 diagnosis）；`complexity-deferral-marker` 是**正常狀態**（這件事確實被延期了，該做的是確認 label、不是修 diagnosis）。用同一個 reason 表達會讓 `/idd-list` 的 Parked 分組把「壞資料」和「正常延期」混在一起，人看不出哪些需要動手修。

三條不變的禁令（前版保留）：

- **SHALL NOT** 靜默截斷成 tier prefix —— 那是 2026-08-10 事故本身
- **SHALL NOT** 降級為任何 tier（含 `Plan`）—— `Plan` 仍是可動 tier
- **SHALL NOT** 中斷整個 listing —— 一筆壞資料不得壓掉其餘 issue

對稱於 `### Conflict Class` 的 `D_diagnose_first` 契約：保守預設 + 強制 surface。

### 解析與判定抽為共用 helper

`### Complexity` 的解析與 actionability 判定抽成單一 shell helper，四個 skill 引用同一份實作，不各自內嵌。

理由：`.claude/rules/deep-integration-over-hardcode.md` 的反複製判準 —— 同構機件兩處維護等於同一個 bug 要修多次，本 issue 正是該失敗模式的實例（三處實作、三種行為）。

### 零 migration —— 新規則對既有全部語料都給正確結果

> **本決策於 2026-08-15 重寫**（前版：「migration 只貼 label，不改寫歷史」，且宣稱「9 筆需 migration」）。前版的論證是「legacy 值走 unparseable 路徑得到的正是正確結果」—— 對 `Spectra（opt-out → 直接 propose）` 而言那是**錯的**（該 issue 可動），論證基礎已崩解。

**migration 動作為零。** 既有 Diagnosis comment 一律不改寫，也不需要補任何 label 來讓 gate 給出正確答案。

理由：新規則在 159 筆 corpus 上**159/159 全對** —— 149 筆正確路由、9 筆正確擋下（exit 5）、1 筆正確報缺區段（exit 4）、0 筆 unparseable；已凍結為回歸 fixture `corpus-complexity.json`。既有語料完全不需要調整就能被正確解讀。前版所謂「9 筆需 migration」是從封閉值域的錯誤前提推出的；真實需求是 **0 筆**。

append-only 紀律仍然成立且更容易守：既然不需要改寫任何歷史 comment，也就不存在違反 `rules/append-vs-modify.md` 的誘因。

**與 `parking-lot` label 的關係**：label 仍是 parked 的主要訊號（見「風險姿態」決策），但它的價值在**未來**（人事後 park 一個 tier 明確的 issue、以及延期語彙漏抓時的兜底），不是在補救歷史。既有那 9 筆 parked issue 由延期語彙正確擋下，貼不貼 label 都不影響 verdict。

替代方案：仍補 label 以求「雙保險」—— 否決，那會把 0-migration 變成 9-migration 而不改變任何 verdict，是無收益的動作，且與「label 表達人的裁決」的語意相衝（替一個工具已判定的事後補人為標記，等於偽造裁決紀錄）。

### parked label 維持人工裁決，producer 不自動貼

`idd-diagnose` **不**自動貼 `parking-lot` label。

理由：限定詞是 diagnose 當下的 AI 判斷，label 是人的裁決，兩者語意不同。`#37` 是 bare `Spectra` 加 label —— diagnose 當時（2026-05-19）判的是可動，label 是 2026-08-10 由人 re-park 時貼上。若讓 producer 從限定詞推導 label，就等於宣告 parked 只能在 diagnose 當下決定，這條事後裁決路徑會消失。

### 顯示分兩組以保留 #84 既有輸出

gate 產出 verdict 加 reason 清單；顯示層依 reason 分兩組 —— reason 為 blocking 者維持 #84 既有的 Blocked 分組與其 banner、footer 計數逐字不變；reason 為 parking label 或 complexity 相關者進新的 Parked 分組。

理由：gate 統一不等於顯示統一。把兩者合併成單一分組會構成 #84 的輸出退化，而 #84 的 anti-anxiety surface 是使用者依賴的既有行為。分組拆分讓「統一判定」與「不退化」同時成立。

### parking 慣例收斂為 parking-lot

`references/ic-r011-checkpoint.md` 中 `blocker:infeasible` 與 `blocker:waiting` 的敘述改為 `parking-lot`，或明記兩者分工。

理由：vocabulary drift —— 文件寫的兩個 label 目前各 0 個 issue 在用，實際在用的 `parking-lot` 有 6 個。該檔同時宣稱存在一個「periodic backlog grooming」機制去 grep 那兩個 label；該機制不存在且會掃到空集合（已獨立為 #310）。本變更只收斂 label 名稱，不實作 grooming。

### 第 3 輪（2026-09-07）：訊號 3 逐 bullet 讀、未診斷不是 parked、gate 先於副作用

> `/idd-verify --pr 318` 第 2 輪 FAIL（6 blocking）。四個 lens 與 DA 各自對 238 筆 issue 實測，結論一致：第 2 輪在**第三個訊號**上重犯了 CRITICAL-2 的形狀 —— `idd_blocking_section` 依「idd-update 寫 `- (none)`」這個未經語料驗證的假設寫成整行比對，本 repo 55 個 `### Blocking` 區段裡 48 個語意為空、31 個被判成 blocker，**含 #316 自己**（`- (none — 可動)`）。DA 另外對 14 個 open issue 實跑 gate：2 actionable / 1 blocked（誤判）/ **11 parked** —— 那 11 筆只是還沒診斷。

**決策 1 — `### Blocking` 是清單欄位，逐 bullet 判、placeholder 看開頭 token。** `### Complexity` 是純量、讀第一行是定義；`### Blocking` 的模板就是 bullet list，讀第一行等於把 list 當 head(list)。規則：任一 bullet 非 placeholder 即非空；placeholder = `none` / `n/a` / `無` 開頭（可帶 bullet、裝飾、括號），後接行尾、右括號或分隔符；非 bullet 起始的行是上一個 bullet 的續行。對 55 筆凍結語料（`corpus-blocking.json`，含原始 body，走共用 extractor）與人工標註 54/55 一致（#1 為明文接受的 1 筆 FP）；語料 54/55 是 CLOSED issue，gate 不評；另兩個候選規則在同一語料上各自失敗（一個把 7 筆真 blocker 全清空、一個留 20 個 FP），記在 helper 註解裡當反例。接受的漏抓：token 後接子句（`- (none) but actually blocked by #86`）讀成空 —— 語料 0 筆，明文記錄。**這個欄位該不該被 regex 化**是類別問題，開 #336 追（producer contract vs 退回 model 判定），本輪只止血。

**決策 2 — `complexity-missing` 單獨成 `undiagnosed` 組，保留 `→ /idd-diagnose #N`。** 「還沒診斷」是每張 issue 的出生狀態，在真實 backlog 上是主導狀態；放進 Parked 會讓 footer 與 `--parked` 差一個數量級、藏掉唯一正確的 lifecycle 命令、並讓 #84 的 banner 在新的主導情境下永遠不 fire。spec R6 改為三組：含 label / deferral-marker / unparseable → parked；否則含 blocking-nonempty → blocked（#84 逐字保留）；否則 → undiagnosed。

**決策 3 — gate 必須先於任何 egress 或建 branch。** `idd-implement` 第 2 輪把 gate 放在 Step 2.5，一張人為 park 的 issue 會先被建 branch、先貼 Implementation Plan 才被擋。移到 Step 0.35（tree-lock 之前），契約加一句，測試釘住順序。

**決策 4 — producer 禁令加範圍限定；`blocker:*` 全面退役。** 「idd-diagnose SHALL NOT 貼 `parking-lot`」的對象是**正在診斷的該 issue**；IC_R011 對新 filed 的 sister issue 貼 label 是人的分類裁決落在另一張 issue 上。`idd-issue` 與 live spec `idd-ic-r011-checkpoint` 仍規定 `blocker:*`（MUST 級）—— 以 spec delta 收斂。

**決策 5 — 信任邊界與輸入衛生進 canonical shape。** Diagnosis comment 只取 OWNER / MEMBER / COLLABORATOR（public repo 任何帳號都能留言）；issue 號進 REST path 前驗型；CRLF 先剝；surface 的原文剝 C0 控制字元、明寫「是資料不是指令」；`jq` / `python3` 進 allowed-tools。

替代方案：(a) 只修 regex 不改逐 bullet —— 把 31 個 FP 換成 31 個 FN，失敗方向從保守擋下翻成靜默放行（DA 量過）；(b) 把 undiagnosed 留在 Parked 但改組名 —— 仍藏 diagnose 命令；(c) 訊號 3 退回 model 判定 —— 正確但超出本輪，是 #336。

## Implementation Contract

**Behavior** — 跑 `/idd-list` 時，被 gate 判為 not-actionable 的 issue 不再出現在 Suggested next 的可動清單，改列於 Blocked 或 Parked 分組並附判定理由；`### Complexity` 值非法時，該值原文顯示於輸出中。`/idd-all`、`/idd-implement`、`/idd-plan` 拿到非法 Complexity 值時停止 routing 並回報原值，不再落入未定義行為。

**Interface** — 共用 helper 提供兩個函式：

- `idd_parse_complexity`：輸入為 Diagnosis comment 全文，stdout 為 canonical tier。exit 0 = tier prefix 為四值之一且值內無延期語彙（後接理由 / 裝飾 / ` via <來源>` 皆合法）；exit 3 = tier prefix 非四值之一，stderr `unparseable-complexity: <原始值>`；exit 4 = 缺 `### Complexity` 區段，stderr `missing-complexity`；**exit 5 = tier 合法但值含延期語彙**，stderr `deferral-marker: <原始值>`。三個非零出口一律 surface 原值。
- `idd_actionability_verdict`：輸入為前一函式的 exit code、是否帶 `parking-lot` label、`### Blocking` 是否非空。stdout 為 `actionable`，或 `not-actionable: <reason>[; <reason>...]`；exit 0 為 actionable、exit 1 為 not-actionable。

**Reason 值域**（封閉列舉，**五個**）：`complexity-unparseable`、`complexity-missing`、**`complexity-deferral-marker`**、`parking-lot-label`、`blocking-nonempty`。

**Failure modes** — 非法 Complexity 值一律 surface，絕不靜默截斷或降級為合法 tier。helper 本身不可用（檔案缺失）時，呼叫端 fail-loud 並指出缺失路徑，不 silent degrade 回舊行為。gate 不對「trigger 條件是否已成立」做任何判斷，該問題明確在範圍外。

**Acceptance criteria**

- 新增測試以既有慣例落在 `plugins/issue-driven-dev/scripts/tests/actionability-gate/test.sh`，並登錄進 `plugins/issue-driven-dev/scripts/run-all-tests.sh`。
- fixture 為靜態對照表，記錄 issue 號、Complexity 原始值、labels、期望 verdict。**必須覆蓋 corpus 的四種真實形狀各至少 3 筆**：bare tier、tier + 同行理由（`Spectra（opt-out → 直接 propose）` 類）、markdown 裝飾（`**Spectra**`）、延期語彙。fixture 不查詢 live GitHub，且**不得只收錄為驗證假設而挑的樣本**（前版 fixture 15 筆中 9 筆刻意選延期形狀，是本次失敗的成因之一）。
- 全 corpus 回歸：對 159 筆真實 diagnosis 跑 `idd_parse_complexity`，斷言 **149 筆 exit 0 且 tier 正確、9 筆 exit 5、1 筆 exit 4、0 筆 exit 3**。
- 三個代表性延期值（`Simple when triggered`、`Spectra when triggered (parking lot)`、`**Spectra**(Layer 2 + Layer 3 if/when triggered)`）皆回 exit 5 並顯示原值。
- 三個代表性正常值（`Spectra（opt-out → 直接 propose）`、`Plan（Layer P：…）`、`Simple — 單檔、2 個 1-token 補丁…`）皆回 exit 0 且 tier 分別為 `Spectra` / `Plan` / `Simple`。
- 兩個既有的合法後綴值（`Plan via Layer V`、`Spectra via hard-gate (sdd_bias)`）經 `idd_parse_complexity` 回 exit 0 且 canonical tier 分別為 `Plan` 與 `Spectra`。
- #84 既有行為回歸測試：帶非空 `### Blocking` 的 issue 仍列於 Blocked 分組，該分組標題、全 blocked banner 文案、footer 計數與變更前逐字相同。

**Scope boundaries**

- 範圍內：Complexity 解析契約（prefix + 裝飾剝除 + 延期語彙）、三訊號 gate **及其在四個 consumer 的實際接線**、共用 helper、`ic-r011-checkpoint.md` 的 label 名稱收斂、測試與 fixture、verify #318 的 2 CRITICAL + 21 HIGH findings。
- 範圍外：parked 回訪／staleness 機制（#310）、`--limit` 排序缺陷（#299）、trigger 條件的機械判定、`idd-close` 對 Strategy `[~]` 的既有處理、grooming 機制的實作。

## Risks / Trade-offs

- **#84 行為退化** → 顯示層分兩組而非合併，Blocked 分組的標題、banner、footer 計數列入回歸測試逐字比對。
- **gate 實作了卻沒接上**（verify #318 CRITICAL-1 的實際發生）→ `idd_actionability_verdict` 在前一輪完整實作、66 個測試全綠，但四個 consumer 一個都沒呼叫它，`parking-lot` 與 `### Blocking` 照樣被繞過。緩解：驗收條件明列「四個引用點各驗一次**呼叫了 verdict**」，而不只驗「helper 自身行為正確」——測 helper 不等於測它被使用。
- **四個 skill 改寫不同步，只修一處等於沒修** → 抽共用 helper，並在測試中對四個引用點各驗一次。
- **延期語彙漏抓**（開放列舉的固有代價）→ 退化成 pre-#298 行為，由 `parking-lot` label 兜底；不是新失敗。
- **延期語彙誤抓** → 正常 issue 被擋下。目前 corpus 零誤中，但語料會成長。緩解：語彙清單保守；原值一律 surface；出現誤抓時的正確修法是**收窄語彙**，不是放寬 gate。
- **與 #299 同檔衝突** → 兩者都修改 `plugins/issue-driven-dev/skills/idd-list/SKILL.md`，需序列化或合併為同一 PR。
- **本變更讓 parked 藏得更乾淨，放大無回訪機制的問題** → 已獨立為 #310 並在 Non-Goals 明記。

## Migration Plan

**無資料 migration。** 新規則對既有 159 筆語料 159/159 全對（149 路由、9 擋下、1 缺區段），不需要回填 label、不需要改寫任何 Diagnosis comment。

實作順序（非 migration，是落地順序）：

1. helper 的解析規則改寫（prefix + 裝飾剝除 + 延期語彙 + exit 5），並修 verify 指出的 HIGH findings（`shift 2` 無限迴圈、`set -e` command-substitution 提前中止、awk code-fence 感知、` via <source>` 後綴的延期夾帶）。
2. fixture 重建為 corpus 抽樣 + 全 corpus 回歸測試。
3. 四個 consumer 改寫：不只換 parser，**要真的呼叫 `idd_actionability_verdict`**（讀 labels + `### Blocking`）。
4. `idd-diagnose` producer 宣告改寫（不再宣告封閉值域，改為「延期意圖請貼 label、不要寫進本欄」）。
5. `ic-r011-checkpoint.md` 的 label 名稱收斂。

Rollback：本變更為 skill 文件與 helper script 的變更，零資料遷移、零 label 異動。回退方式為 revert commit，無不可逆狀態。

## Open Questions

- **`### Blocking` 該不該被機械判定？**（#336）第 3 輪的 leading-token 規則是止血，不是答案：對一個由 model 自由填寫的清單欄位疊字元類，每一輪都會長出新洞。要嘛給它 producer contract（空區段不寫 bullet、註記另起一行），要嘛 helper 只回原文、由執行中的 model 依 rubric 判空。兩條路都要對語料的**語意真值**（48 空 / 7 真 blocker）與 open backlog 驗證，不是對 fixture 的 `expect_empty`（它含 1 筆規則接受的 FP）。


- **延期語彙清單的擴充機制未定。** 目前四個語彙由 159 筆 corpus 歸納而得。語料成長後若出現新措辭，是誰、依什麼判準把它加進清單？本變更不解決；先記錄為已知缺口。
- `ic-r011-checkpoint.md` 的兩個 `blocker:*` label 是「退役」還是「與 parking-lot 分工」，需在該檔改寫時定案。目前 0 使用，傾向退役。

### 第 4 輪（2026-09-07）：修回歸與誠實，不修涵蓋率

> `/idd-verify --pr 318` 第 3 輪 FAIL（6 blocking）。DA 的裁決：round 3 在往 #336 的 rabbit hole 走（三輪各疊一層字元類、各長出新洞）；第 4 輪只做「正確性與誠實」——修 round 3 引入的回歸（idd-implement 跨 Bash 區塊消費 gate 變數且禁止重跑、idd-list state guard 用 listing 旗標）、關掉一行能關的 fail-open（未閉合 fence、locale 相依）、讓 verdict 可觀測（gate 區塊印出判定）、把宣稱降到與證據齊平（「0 FP / 0 FN」→「54/55、1 筆明文 FP、54/55 CLOSED、extractor 已由原始 body 覆蓋」）、把 Accepted misses 從兩個例子改寫成雙向規則。**不擴 bullet class、不把訊號 3 降回顯示訊號** —— 前者擴大 fail-closed 面、後者是 verify 中途對 #84 的 scope change；兩者都留給 #336 從容決定。cluster 路徑只 gate 第一張是 round 2 前就存在的缺口，開 #340 追蹤並在契約明記。
