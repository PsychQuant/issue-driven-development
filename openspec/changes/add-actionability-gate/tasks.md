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
