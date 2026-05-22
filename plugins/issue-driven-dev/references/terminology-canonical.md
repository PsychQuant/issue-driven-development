# Terminology Canonical Library

**Single source of truth** for `/idd-clarify` terminology mismatch detection。

> **Normative binding(per IDD MANIFESTO category — Authoring Dictionary)**:
> 本檔是 `idd-clarify` skill 的 input,heuristic match 依此 library。
> 修改本檔 SHALL 走 PR review;新 row 需 promotion-threshold 證據(per below)。
> Reload mode:`idd-clarify` 每次 invocation **fresh read**,無 cache。

## How `idd-clarify` uses this file

當 user 跑 `/idd-clarify #N`,skill 對 issue body 套用以下 detection table。每個 row 是一個「misuse pattern」:

- **Source term**:body 內可能出現的 domain term(可能是中文 / 英文 / 縮寫)
- **Context predicate**:額外條件 — 必須跟 source term 共現於同段 body 才 match(避免 generic 詞彙誤觸)
- **Suggested canonical**:領域 canonical 術語(以 `中文 / English` 雙語顯示)
- **Source citation**:本 row 的來源 case(出處 issue / commit / paper),audit trail 用

## Promotion threshold(rule-of-three)

新 row **SHOULD** 滿足:
- **同 misuse pattern 在不同 codebase 或 conversation 觀察到 ≥3 次**(rule of three),OR
- **單一 high-impact incident**(causing measurable rework / deploy issue / customer-facing bug)+ maintainer judgment

開 PR 加 row 時請 cite 證據(issue / commit / Slack / LINE 對話)。

## Open contribution

PR welcome at `https://github.com/PsychQuant/issue-driven-development`,加入新 row + 證據 + maintainer review。

## Future plugin-level extension

未來 domain-specific plugin(medical / legal / financial)可 ship own `references/terminology-canonical-{domain}.md`,`idd-clarify` 載入時 chain-merge。本 plugin base library 維持 statistics / ML / 商業分析 偏重。

詳細 future plan 待實際需求出現後 design(per design.md Open Question Q2)。

---

## Library rows

### Row 1: 特徵值 (eigenvalue/feature value) in K-means context

| Field | Value |
|---|---|
| Source term | `特徵值` |
| Context predicate | body 同時提及 `K-means` / `clustering` / `分群` |
| Common-misuse alert | 客戶可能誤稱「分群變數」(distinguishing variable)為「特徵值」 |
| Suggested canonical | `分群變數 / distinguishing variable` |
| Why mismatch | 「特徵值」嚴格指數學 eigenvalue(矩陣分解);K-means 沒有 eigenvalue 概念;客戶想說的是各 cluster 最具區辨力的變數 |
| Source citation | `kiki830621/ai_martech_global_scripts#804`(2026-05-21);LINE 對話老師 clarify「應該是說分群變數」 |

### Row 2: PCA + K-means 混用

| Field | Value |
|---|---|
| Source term | `PCA` 或 `主成分分析` |
| Context predicate | body 同時提及 `K-means` / `clustering` / `分群` 且未明示兩者順序或關係 |
| Common-misuse alert | 客戶可能搞混 dimensionality reduction(PCA)vs clustering(K-means);兩者**互補**不是同義 |
| Suggested canonical | 確認 user 要的是:(a) PCA 降維後跑 K-means;(b) 純 K-means;(c) 純 PCA 視覺化 |
| Why mismatch | PCA = unsupervised dimensionality reduction;K-means = unsupervised clustering。Tools 不同,output 不同 |
| Source citation | `kiki830621/ai_martech_global_scripts#135`(2026-05-22 spectra-discuss D4 row 2)+ 通用 misuse pattern |

### Row 3: 回歸 + ANOVA 用詞混用

| Field | Value |
|---|---|
| Source term | `回歸` / `regression` 跟 `ANOVA` / `變異數分析` 並列 |
| Context predicate | body 描述同一分析任務但混用兩種術語 |
| Common-misuse alert | Regression(連續自變數)跟 ANOVA(類別自變數)在 GLM framework 下都用 F-test,但 H0 跟報表不同;客戶混用可能不知差異 |
| Suggested canonical | 看 H0 / 自變數結構決定:連續 → regression coefficient + p;類別 → ANOVA effect size + post-hoc |
| Why mismatch | Linear model 框架包兩者,但顯示給 customer 的「coefficient」vs「main effect」是不同物件 |
| Source citation | `kiki830621/ai_martech_global_scripts#135`(2026-05-22 spectra-discuss D4 row 3)+ Layer V vagueness pre-check 通用 case |

### Row 4: 「準確率」+ regression context

| Field | Value |
|---|---|
| Source term | `準確率` / `accuracy` |
| Context predicate | body 描述 regression model / 連續 target 預測 |
| Common-misuse alert | 「準確率」是 classification metric(TP+TN / total)— regression 沒有「對 / 錯」二元判定 |
| Suggested canonical | 看 regression 目標決定:`RMSE` / `MAE`(absolute error)/ `R²`(explained variance)/ `MAPE`(relative error) |
| Why mismatch | Customer 用「準確率達 80%」這類 phrase 暗示 classification metric,但其實 regression 應該講 error |
| Source citation | `kiki830621/ai_martech_global_scripts#135`(2026-05-22 spectra-discuss D4 row 4)+ 通用 ML beginner misuse |

### Row 5: 「P 值」 + Bayesian context

| Field | Value |
|---|---|
| Source term | `P 值` / `p-value` |
| Context predicate | body 描述 Bayesian model / `posterior` / `prior` / `credible interval` |
| Common-misuse alert | P-value 是 frequentist statistic;Bayesian 框架報 posterior / credible interval,沒有 p-value |
| Suggested canonical | `posterior probability` / `credible interval` / `Bayes factor`(視 question 而定) |
| Why mismatch | Conceptually 不同 framework — Bayesian 不假設 null hypothesis sampling distribution |
| Source citation | `kiki830621/ai_martech_global_scripts#135`(2026-05-22 spectra-discuss D4 row 5)+ 學術論文 frequentist/Bayesian 混淆通用 case |

### Row 6: 「分群」+ 有 ground truth label

| Field | Value |
|---|---|
| Source term | `分群` / `clustering` |
| Context predicate | body 同時提及 `已知 label` / `ground truth` / `已分類` / `customer 已 segment` |
| Common-misuse alert | Customer 說「分群」但實際有已知 label = supervised classification task,不是 unsupervised clustering |
| Suggested canonical | `分類 / classification`(supervised);用 logistic regression / decision tree / random forest 等 |
| Why mismatch | Unsupervised clustering 不用 label;若 customer 已有 label 還跑 K-means 等於浪費資訊。可能客戶 mental model 是「把 customer 分群顯示」(顯示已知 segment),不是「找出未知 segment」 |
| Source citation | `kiki830621/ai_martech_global_scripts#135`(2026-05-22 spectra-discuss D4 row 6)+ ML 教學常見 misuse |

---

## Row schema(for new contributions)

每個 row 加入時 SHALL 提供以上 6 個 fields。Source citation **必要**(rule-of-three audit trail)。

Optional fields(若有 evidence):
- **Frequency observed**:本 misuse 在 codebase 觀察到的具體次數(per rule-of-three)
- **Detection regex**(advanced):若 source term 有 stable surface pattern,可加 regex 供 `idd-clarify` 機械匹配
- **Resolution example**:典型對話如何 clarify(供 user reference)

## Heuristic match contract(for skill implementers)

`idd-clarify` Step 5a Scan mode 對 body 套以下 match logic:

1. **Lexical pass**:body contains source term(case-sensitive for ASCII abbreviations,case-insensitive for Chinese)
2. **Context predicate pass**:context predicate phrase 在 same body 出現(任何位置 OK,not necessarily same paragraph — heuristic allows broad match,user 可 dismiss false positive)
3. **De-dupe**:同一 source phrase 觸發多個 rows 時,選 highest-specificity row(最 specific context predicate)
4. **Emit**:per match row,produce `### Clarity Surface` table row with Type=`terminology`,Source=quoted body excerpt(含周圍 sentence),Suggested canonical=本檔 row 的 suggested canonical value

## Versioning

Library version follows IDD plugin version。Library content changes get changelog row in `README.md`。

Library file backward compat:row 刪除是 breaking(會讓 既有 issue 的 surfaced row 失參考)— SHALL 走 spectra change with `MODIFIED Requirement` workflow,不是 ad-hoc edit。新增 row 是 additive,可直接 PR。
