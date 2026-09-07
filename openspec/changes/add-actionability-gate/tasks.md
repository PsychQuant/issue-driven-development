## 1. 共用 helper（TDD）

- [x] 1.1 建立 fixture 與失敗測試（RED）。fixture 為靜態對照表，記錄 issue 號、`### Complexity` 原始值、labels、期望 verdict 與期望 reason，覆蓋 2026-08-10 快照的 9 筆 diagnosed 路由，並額外含兩個合法後綴值（`Plan via Layer V`、`Spectra via hard-gate (sdd_bias)`）與缺少 `### Complexity` 區段的案例。fixture 不查詢 live GitHub。行為契約：測試斷言 9 筆中只有 `#37` 為 actionable。驗證：執行 plugins/issue-driven-dev/scripts/tests/actionability-gate/test.sh 全部案例失敗且訊息指出 helper 尚未存在。檔案：`plugins/issue-driven-dev/scripts/tests/actionability-gate/fixtures/parked-routing.json`、`plugins/issue-driven-dev/scripts/tests/actionability-gate/test.sh` 涵蓋需求：Closed value domain for the Complexity field、Actionability gate evaluates three signals disjunctively、Conservative verdict and mandatory surfacing on non-domain Complexity。

- [x] 1.2 實作共用 helper 至測試通過（GREEN），落實決策「解析與判定抽為共用 helper」、「unparseable 的保守處置為 not-actionable 並強制 surface」與「gate 採三訊號，Strategy 暫緩標記排除在外」。行為契約：`idd_parse_complexity` 對 bare tier 與帶 ` via <來源>` 後綴回 exit 0 並輸出 canonical tier；對域外值回 exit 3 並於 stderr 輸出原值；對缺區段回 exit 4。`idd_actionability_verdict` 依三訊號回 `actionable` 或 `not-actionable: <reason>`，reason 限於四個封閉值。驗證：1.1 的測試全數轉綠。檔案：`plugins/issue-driven-dev/scripts/lib/actionability.sh` 涵蓋需求：Single shared implementation of parsing and verdict。

- [x] 1.3 確認新測試被 test runner 納入。行為契約：全套測試執行時涵蓋 actionability-gate 套件。**runner 以 glob 自動探索 `scripts/tests/*/test.sh`，無需手動登錄** —— 本項為驗證而非編輯，`run-all-tests.sh` 不應被修改。驗證：執行 plugins/issue-driven-dev/scripts/run-all-tests.sh 的輸出包含 actionability-gate 套件且回報通過，且該檔在本 change 中維持未修改。

## 2. 契約文件

- [x] 2.1 撰寫 actionability gate 的 canonical reference，內容涵蓋封閉值域、三訊號 gate、reason 封閉值域、unparseable 的保守處置與強制 surface，並明記與 `### Conflict Class` 契約的對稱關係。行為契約：四個 consumer skill 引用此檔而非各自敘述規則。驗證：內容審查確認四項規則皆有明文，且封閉性以「僅此四值、不得類推」形式書寫。檔案：`plugins/issue-driven-dev/references/actionability-gate.md`

## 3. Consumer 改寫

- [x] 3.1 消除 `idd-list` 內部矛盾：Step 5 的 Complexity 解析改為引用共用 helper，落實決策「顯示分兩組以保留 #84 既有輸出」。**背景（2026-08-14 re-scope）**：#298 的修正已由 PR #309 merge 進 Step 3.7，但同檔 Step 5 仍文載會截斷的 regex `([A-Za-z-]+)` —— 與 Step 3.7 明文禁止的截斷直接衝突。本 task **不重做 Step 3.7 的行為**，只讓 Step 5 停止規定一個矛盾的解析。行為契約：Step 5 不再出現任何私有 Complexity regex，改為引用 `references/actionability-gate.md` 與共用 helper；Step 3.7 既有的 Blocked 分組輸出不變。驗證：grep 確認該截斷 regex 在 `skills/idd-list/SKILL.md` 內**不再有 prescriptive 用法**（僅得出現在 `>` rationale blockquote 內作為反例引用 —— 把失敗史留在文件裡是刻意的，否則後人會覺得這條規則囉嗦而改回去）；且 `git diff` 確認 Step 3.7 段落零刪除行。檔案：`plugins/issue-driven-dev/skills/idd-list/SKILL.md` 涵蓋需求：Blocked-state output is preserved as a distinct display group。

- [x] 3.2 [P] 改寫 `idd-all` 使用共用 helper，補上域外值的 dispatch 處置。行為契約：Complexity 值域外時停止 routing 並回報原值，不再落入既有 dispatch table 無匹配 row 的未定義行為；既有的缺區段 abort 行為以 `complexity-missing` reason 表達。驗證：測試以 `Simple when triggered` 為輸入，斷言回報原值且未解析出任何 canonical tier。檔案：`plugins/issue-driven-dev/skills/idd-all/SKILL.md`

- [x] 3.3 [P] 改寫 `idd-implement` 使用共用 helper。行為契約：Complexity 值域外時停止並回報原值，不再自行以字串切割推導 tier。驗證：測試斷言該 skill 的解析路徑呼叫共用 helper 且對域外值不產生 canonical tier。檔案：`plugins/issue-driven-dev/skills/idd-implement/SKILL.md`

- [x] 3.4 [P] 改寫 `idd-plan` 的 tier 確認步驟使用共用 helper。行為契約：確認 Complexity 為 `Plan` 的步驟改以共用 helper 的 canonical tier 判定，域外值時停止並回報原值。驗證：測試斷言帶 ` via Layer V` 後綴的值仍被認定為 `Plan`，而域外值不被認定為任何 tier。檔案：`plugins/issue-driven-dev/skills/idd-plan/SKILL.md`

## 4. Producer 與既有文件

- [x] 4.1 於 `idd-diagnose` 的 verdict 寫入段宣告封閉值域，並落實決策「Complexity 回歸純封閉值域，parked 遷出至 label」與「parked label 維持人工裁決，producer 不自動貼」。行為契約：該 skill 明文規定 `### Complexity` 僅得寫四個 tier（可帶 ` via <來源>` 後綴）、限定詞改以 `parking-lot` label 表達，且該 skill 不得貼除既有 type label 以外的 `parking-lot` label。驗證：內容審查確認封閉宣告與「producer 不貼 label」兩條皆成文；並確認既有的 Layer V 與硬閘出口所產生的後綴值在新宣告下仍為合法。檔案：`plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md` 涵蓋需求：Parked label is authored by a human and never derived by the producer。

- [x] 4.2 [P] 收斂 parking 慣例敘述，落實決策「parking 慣例收斂為 parking-lot」。行為契約：該檔不再宣稱以 `blocker:infeasible` 或 `blocker:waiting` 進行 parking 標記，改為 `parking-lot`，或明記兩者分工；同時移除對不存在的 periodic backlog grooming 機制的宣稱，改為誠實敘述並指向 #310。驗證：逐行分類檔內每個 `blocker:*` 出現處，確認**全部位於 `>` blockquote**（歷史引用／收斂理由），無任何 prescriptive 用法；且 grooming 敘述與現實一致。檔案：`plugins/issue-driven-dev/references/ic-r011-checkpoint.md`

## 5. Migration

- [~] 5.1 對既有 parked issue 補齊 `parking-lot` label —— **moot（2026-08-14）**：migration 目標 `#131` / `#200` / `#128` 在 2026-08-10 之後全部被 close（backlog 已清，非 park）。決策「migration 只貼 label，不改寫歷史」仍然成立且已由 helper 的 unparseable 路徑承接 —— legacy 值判為 not-actionable 並 surface 原值，無需回填。驗證（2026-08-14 實測）：載入共用 helper，對**當前全部 open issue** 逐一跑 `idd_parse_complexity` —— **域外值（exit 3）數量為 0**，需補 `parking-lot` label 的 open issue 數為 0。整個 migration 類別在 live backlog 中為空集合，非僅原列三筆已 close。同時這也是 helper 對真實資料的 end-to-end 驗證。 涵蓋需求：Legacy Diagnosis values are handled without rewriting history。

- [~] 5.2 由人重新判斷 `#128` 的處置 —— **moot（2026-08-14）**：`#128` 已 CLOSED，處置已由 backlog 清理決定，無待判事項。原內容：行為契約：`#128` 的 `### Complexity` 值為散文（tier 後接未決 UX 軸敘述），需由人決定該 issue 為 parked 或可動，並據以決定是否貼 `parking-lot` label。驗證：`#128` 的裁決結果以 `/idd-comment --type decision` 記錄於該 issue，且 label 狀態與裁決一致。

## 6. 值域規則重寫（第 2 輪 — post re-baseline）

> 前 5 組的 `[x]` 為第 1 輪成果，**不回退**：helper 骨架、契約文件、四個 consumer 的引用點與 fail-loud guard、producer 段落位置、`blocker:*` 收斂皆仍有效。本組修的是**判準本身**與第 1 輪漏掉的接線。

- [ ] 6.1 重寫 `idd_parse_complexity` 的 tier 判定，落實決策「tier 以 prefix 抽取，延期以語彙偵測，parked 主訊號在 label」。行為契約：剝裝飾 → 取 ` via ` 前的 tier prefix → 對**整個值**掃延期語彙。exit 0 = 可路由；exit 3 = tier prefix 非四值之一；exit 4 = 缺區段；**exit 5 = tier 合法但含延期語彙**，stderr `deferral-marker: <原值>`。驗證：三個代表性正常值（`Spectra（opt-out → 直接 propose）` / `Plan（Layer P：…）` / `Simple — 單檔、2 個 1-token 補丁…`）回 exit 0 且 tier 正確；三個代表性延期值（`Simple when triggered` / `Spectra when triggered (parking lot)` / `**Spectra**(Layer 2 + Layer 3 if/when triggered)`）回 exit 5。檔案：`plugins/issue-driven-dev/scripts/lib/actionability.sh` 涵蓋需求：Complexity tier extraction tolerates trailing rationale、Deferral vocabulary withholds routing under its own reason。

- [ ] 6.2 reason 值域擴為五值，新增 `complexity-deferral-marker`，落實決策「三種不可路由狀態各有獨立 reason 並一律 surface」。行為契約：`idd_actionability_verdict` 接受 `--complexity-exit 0|3|4|5`；exit 5 → reason `complexity-deferral-marker`。`idd_actionability_group` 對該 reason 回 `parked`。驗證：測試斷言 `Plan when triggered` 得 `complexity-deferral-marker` 而 `移入 discussion list` 得 `complexity-unparseable`，兩者 reason 不同。檔案：`plugins/issue-driven-dev/scripts/lib/actionability.sh` 涵蓋需求：Conservative verdict and mandatory surfacing on non-routable Complexity。

- [ ] 6.3 [P] 修 verify #318 的 HIGH findings（helper 側）。行為契約：(a) option 缺 value 時回 exit 2 具名錯誤，不再因 `shift 2` 失敗而無限迴圈；(b) awk 追蹤 ``` 與 ~~~ code fence 並忽略其內 heading，且在同級或更高級 heading 結束；(c) ` via <source>` 後綴內的延期語彙同樣被偵測（不得成為逃生孔）。驗證：三類各補負向測試（value-less flag ×3、fenced-example body、`Simple via when triggered`）。檔案：`plugins/issue-driven-dev/scripts/lib/actionability.sh`

- [ ] 6.4 [P] 修 verify #318 的 HIGH finding（consumer 側 `set -e` 相容）。行為契約：contract 範例與四個 SKILL.md 的呼叫形狀改為條件位置捕捉（`if TIER=$(...); then CEXIT=0; else CEXIT=$?; fi`），使 exit 3/4/5 與 verdict 的 exit 1 不會在 `set -euo pipefail` 下終止 caller。驗證：新增 `set -euo pipefail` 的整合測試，斷言一筆不可路由的 issue 不會中斷整個 listing。檔案：`plugins/issue-driven-dev/references/actionability-gate.md`、四個 consumer SKILL.md

## 7. 接上三訊號 gate（verify CRITICAL-1）

- [ ] 7.1 四個 consumer 實際呼叫 `idd_actionability_verdict`。行為契約：每個 consumer 讀該 issue 的 labels 與 body 的 `### Blocking` 區塊，連同 `idd_parse_complexity` 的 exit code 一併送進 verdict，並依其 exit 0/1/2 分支（2 = API 誤用，不得與 not-actionable 混同）。**只換 parser 不呼叫 verdict 等於沒修** —— 第 1 輪即是如此：gate 完整實作、66 測試全綠、零 consumer 呼叫。**另（2026-09-07 rebase 後補記）**：四個 consumer 抓 latest Diagnosis 時**不得**用 `gh issue view --json comments` —— 它把巢狀 connection 解成 `comments(first: 100)`，硬截成**最舊** 100 則；超過 100 則 comment 的 issue，最新 Diagnosis 正是被丟掉的那則，helper 會誤回 exit 4 `complexity-missing`。改用 `gh api repos/:o/:r/issues/N/comments --paginate --jq '[.[]|{body}]' | jq -s add`（main `idd-list` Step 2 於 2026-08-15 post-merge audit 已規定同款修法，且明寫「不得只在其中一個 consumer 修」；`scripts/check-closed-without-summary.sh` 已有現成實作可抄）。驗證：測試對四個引用點各驗一次「verdict 被呼叫且 labels/Blocking 有被讀取」，而非只驗 helper 自身行為；另 grep 四份 SKILL.md 確認抓 comments 的路徑皆為 `--paginate`，無殘留 `--json comments`。檔案：`plugins/issue-driven-dev/skills/idd-list/SKILL.md`、`skills/idd-all/SKILL.md`、`skills/idd-implement/SKILL.md`、`skills/idd-plan/SKILL.md` 涵蓋需求：Actionability gate evaluates three signals disjunctively、Single shared implementation of parsing and verdict。

- [ ] 7.2 `idd-list` 顯示層依 reason 分兩組。行為契約：reason 僅 `blocking-nonempty` → 維持 #84 既有 Blocked 分組；其餘（含 `complexity-deferral-marker`）→ Parked 分組並顯示原值。驗證：測試斷言 #84 的分組標題、全 blocked banner 文案、footer 計數與變更前逐字相同。檔案：`plugins/issue-driven-dev/skills/idd-list/SKILL.md` 涵蓋需求：Blocked-state output is preserved as a distinct display group。

## 8. 測試重建

- [ ] 8.1 fixture 重建為 corpus 抽樣。行為契約：四種真實形狀各至少 3 筆（bare tier / tier + 同行理由 / markdown 裝飾 / 延期語彙），逐字取自真實 diagnosis，不得只收錄為驗證假設而挑的樣本。驗證：內容審查確認四類數量達標且每筆標註來源 issue 號。檔案：`plugins/issue-driven-dev/scripts/tests/actionability-gate/fixtures/parked-routing.json` 涵蓋需求：Existing diagnoses require no migration。落實決策「零 migration —— 新規則對既有全部語料都給正確結果」——fixture 的存在意義正是把這個宣稱變成可回歸的斷言，而非一次性檢查。

- [ ] 8.2 新增全 corpus 回歸測試。行為契約：對 159 筆真實 diagnosis 跑 `idd_parse_complexity`，斷言 149 筆 exit 0 且 tier 正確、9 筆 exit 5、1 筆 exit 4、**0 筆 exit 3**。corpus 快照存為 fixture，不查詢 live GitHub。驗證：執行 plugins/issue-driven-dev/scripts/tests/actionability-gate/test.sh 該項通過。檔案：`plugins/issue-driven-dev/scripts/tests/actionability-gate/`

## 9. 文件同步（第 2 輪）

- [ ] 9.1 `references/actionability-gate.md` 依新規則重寫。行為契約：封閉值域段改為「tier prefix 抽取 + 延期語彙」；reason 值域 4 → 5；新增「風險姿態：label 為主、語彙為輔」段並說明漏抓/誤抓的不對稱處置。驗證：內容審查確認不再出現「合法值域為封閉四值」的宣稱，且 corpus 數據（159 筆 / 158-158）有明文引用。檔案：`plugins/issue-driven-dev/references/actionability-gate.md`

- [ ] 9.2 [P] `idd-diagnose` producer 宣告改寫。行為契約：移除封閉值域宣告，改為「tier 寫清楚；延期意圖貼 `parking-lot` label，不要寫進 `### Complexity`」，並保留「producer 不自動貼 label」一條。驗證：內容審查確認不再宣告封閉值域，且 159 筆語料的常態寫法（tier + 同行理由）未被規定為違規。檔案：`plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md`
