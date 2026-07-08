## Context

IDD 的 Plan / pre-implementation tier 由三個 2026-07-07 使用者裁決收斂而來（issues #129 / #57 / #111，Cluster C 三決策）：

- **#129**：`/idd-diagnose` Step 3.5 的 Layer P（複雜度路由）目前是純建議性的 disjunctive any-match，大型多檔 / 動到共用抽象的改動可能靜默落 Simple 而被 under-plan。實證：#44 / #47 —— 同一 conceptual 改動散落三個量表，單次 Plan 未一次涵蓋，兩次 close 才補齊。
- **#57**：meeting / 審議型 issue 被迫走 code-centric pipeline（Strategy = Files & Changes、closing = TDD verify），與「使用者驅動的決策工作」形狀不符。
- **#111**：pre-implementation staging（brainstorm → written plan）在 IDD 沒有落點；而 #209 已把 superpowers 設為 install-time hard dependency，故正解是委派而非自建。

三者共通面：都重塑 Plan / pre-implementation tier，且 #129 與 #57 同碰 Step 3.5 routing，必須一起設計避免雙重判準。

## Goals / Non-Goals

**Goals:**

- 在 Layer P 之上疊一層 MUST-trigger 硬閘，讓 ≥ N 檔 / 共用抽象改動一定升級 Plan，同時保住其餘情況的 Simple 預設。
- 讓 `meeting` 成為 first-class issue type，有專屬的 diagnose Strategy 模板、meeting-adapted plan body（跳過對 `/idd-implement` 的 chain）、與 decision→action 的 closing 語意。
- 把 pre-implementation staging 委派給 superpowers（README 階段對照表 + diagnose/issue hand-off 指標），不自建對等 skill。
- 統一 Step 3.5 的 routing 順序，讓 #129 硬閘與 #57 type 分支在同一判定流程裡有明確先後、互不衝突。

**Non-Goals:**

- **不**反轉複雜度預設為 Default-Plan（#129 明確排除 —— 只升級、不改預設）。
- **不**自建 idd-brainstorm / idd-write-plan skill（#111：依 deep-integration-over-hardcode，自建 = 禁止的 vendored fork）。
- **不**對 meeting type 套用 `/idd-verify` TDD verify pass。
- **不**改動 Layer V（vagueness）的**評分邏輯 / anchors**；既有 non-meeting issue 的 Layer V 行為完全不變。但 `type=meeting` 因最優先分流而**不經過** Layer V（round-1 verify HIGH-8：這是刻意的 —— 審議 issue 的模糊性由 Phase A/B/C 議程釐清，非 V1/V4 Likert；meeting 是新增 type，過去不存在，故非「改動既有行為」）。
- **不**改動 `/idd-implement` 本身；meeting 分支只是在上游跳過對它的 chain。

## Decisions

### 硬閘疊加於 Layer P 之上，不反轉 Simple 預設

保留 Layer P 現行的 disjunctive any-match「may trigger」語意；在其上新增一層 MUST-trigger 硬閘。硬閘命中 → 強制 Plan；未命中 → 維持既有 Layer P + Simple 預設。**替代方案（反轉為 Default-Plan）已被使用者否決**：那會把大量小改也拖進 plan-mode approval gate，over-trigger 的成本高於 under-plan 的殘餘風險。硬閘是「加法」不是「換底」。

### 硬閘判準用 diagnose-time 的 AI scope 估計，門檻 N=5 檔 + shared-abstraction 述詞

`/idd-diagnose` 在 implementation 之前執行，**沒有實際 diff**可 grep，故硬閘的觸發是 AI 對「本 issue 預期改動範圍」的**估計**，而非 diff-time 機械比對。判準（OR，任一即命中）：

1. **單一概念散佈 ≥ N 檔**，預設 **N = 5**。**判準是「同一 conceptual 改動散佈到 ≥ N 檔」，不是純檔數**：genuinely 各自獨立、無共享概念的多檔由 Layer 1「Multi-file but each file independent」保持 Simple、**不**觸發硬閘（round-1 verify HIGH-7：消解硬閘 vs Layer 1 對 5-independent-file 的矛盾）。取 5 而非 3/4 是為保護 Simple 預設：impl + test + doc 這類合法小改常觸及 3 檔，門檻設 3 會過度觸發；5 檔才是「單一概念散佈多處」的可靠訊號（對齊 #44/#47 的 failure class —— CR/PTSR/PCQ 三量表共用一 scoring helper 即散佈的單一概念）。N 是本設計唯一真正可調的旋鈕（見 Open Questions）。
2. **動到 shared abstraction**：被多個 caller 使用的 data structure / helper interface / constants set。diagnose 以「issue 描述 + 對現有程式碼的引用查找」估計某個待改符號是否有 ≥ 2 個跨檔 caller；有 → 命中。

估計必須依 `attribute-assessment` 紀律揭露：在 Diagnosis comment 寫一行 `Hard-gate: <triggered|not> — <reason + 具體錨點（檔名/符號名）>`，與 Layer V 同等的 audit trail。認識論地位與 Layer P/V 的 AI 判斷一致 —— 是有理由、有錨點的估計，不是黑箱。

### 硬閘觸發後，Plan 必涵蓋 family-wide 影響

硬閘因 shared-abstraction 命中時，產出的 Plan **必須列舉該抽象的所有已知 call site / family 成員為 in-scope**，而非只覆蓋觸發當下那個檔案的最小修改。這正是 #44 的教訓：miss 不在於沒開 Plan，而在於 Plan 只覆蓋一個量表、沒涵蓋同 family 的 sibling（CR + PTSR + PCQ）。family-wide enumeration 是硬閘的產出契約的一部分。

### meeting 作為 first-class type：diagnose Strategy 模板 + plan skip-chain + closing 語意

`meeting` 加入 type taxonomy（與 bug / feature / refactor / docs 並列）。三段行為改變：

- **diagnose**：對 `type=meeting` emit **Phase A/B/C Strategy 模板**（審議 deliverables：議程 / 決策點 / 行動項），取代 code-centric 的 Files & Changes。
- **plan**：偵測 `type=meeting` → 用 meeting-adapted Plan body schema，且**跳過** Step 6 對 `/idd-implement` 的 chain（meeting 是 user-driven deliberation，不是 TDD loop）。
- **closing**：無 `/idd-verify` TDD pass；closing summary = decision → action mapping。

**替代方案（issue 自身推薦的 Option C：doc-only 漸進過渡）已被使用者否決** —— 那把 adaptation 複雜度推遲進每個 agent 的臨場判斷，非本質正確形式；explicit 邊界 > implicit 判斷。過渡期沿用 `ai_martech_global_scripts` #615 的 Plan body 範本。

### Step 3.5 統一 routing 順序（消解 #129×#57 耦合）

Step 3.5 內明定判定順序，讓兩個新機件不衝突（**忠實 7-step，含 Spectra，不省略任何 gate**）：**(1) type=meeting 分支（走 meeting Strategy，最優先 —— type 是確定性欄位，先於任何內容啟發式）→ (2) Layer 1 disqualifier（narrative/ad-hoc → 強制 Simple）→ (3) Layer V vagueness（Step 3.4 既有）→ (4) Spectra（Layer 2+3；published API contract）→ (5) #129 硬閘（MUST-trigger）→ (6) Layer P any-match → (7) Simple 預設**。**meeting 最優先分流**（round-1 verify HIGH-2 修正：原設計把 Layer 1 放最前，會讓 meeting 的 Phase A/B/C 審議內容被 Layer 1 的 narrative disqualifier 攔成 Simple、永遠到不了 meeting 分支）。硬閘只作用於非 meeting 的 code-centric issue，兩者不會對同一 issue 同時給出衝突 verdict。（round-3 verify HIGH 修正：本段原為漏列 Spectra 的 5-step，與同檔 Acceptance Criteria + Risks 自我矛盾。）

### pre-implementation staging 委派 superpowers，不自建

README 加 IDD ↔ superpowers 階段對照表（idd-issue / brainstorming / writing-plans / idd-implement / idd-verify / idd-close），明標 verify ensemble 與 close audit trail 為 IDD 獨有；design-heavy issue 在 `/idd-issue` Step 5 與 `/idd-diagnose` 加一行指向 `superpowers:brainstorming` 的 hand-off hint。**不**新增任何 staging skill。依 deep-integration-over-hardcode：superpowers 既是 hard dependency，hand-off 指標必然可解析，自建即 vendored fork。這是三個 requirement 中最輕的一塊，可在本 change 內先落地。

## Implementation Contract

**Behavior（可觀察行為）:**

- diagnose 對「估計 ≥5 檔 或 動到 shared abstraction」的非 meeting issue → Complexity 欄輸出 `Plan`，且 Diagnosis comment 含一行 `Hard-gate: triggered — <reason + 錨點>`；未命中則輸出 `Hard-gate: not triggered — <reason>` 並回落既有 Layer P 判定。
- diagnose 對 `type=meeting` → 輸出 Phase A/B/C Strategy 模板（非 Files & Changes）。
- plan 對 `type=meeting` → 產出 meeting-adapted Plan body，且不 chain 到 `/idd-implement`。
- idd-issue 接受 `meeting` 為合法 type 值；Step 5 與 diagnose 對 design-heavy issue 印出 `superpowers:brainstorming` hand-off hint。
- plugin README 含 IDD ↔ superpowers 階段對照表。

**Interface / data shape:**

- type taxonomy 值集由 `{bug, feature, refactor, docs}` 擴為 `{bug, feature, refactor, docs, meeting}`。
- Diagnosis audit line 格式：`Hard-gate: <triggered|not triggered> — <reason>`（單行，PATCH 進 Diagnosis comment，與 Layer V 的 audit line 並列）。
- 硬閘 shared-abstraction 命中時，Plan body 含一個 `Family-wide scope` 小節，列舉所有已知 call site。

**Failure modes:**

- diagnose 無法估計檔數 / caller 數（issue 描述過稀）→ 硬閘**不**命中（fail-open 到 Layer P + Simple 預設），並在 audit line 註明 `insufficient signal`。理由：硬閘是「加保護」，訊號不足時不應誤升級；漏升級由既有 Layer P 兜底。
- superpowers 未安裝 → 已由 #209 hard dependency + pre-flight gate 處理，本 change 不新增 failure mode。

**Acceptance criteria:**

- 新增 test.sh 案例：餵一個「issue 描述明示改 ≥5 檔」的 fixture → 斷言 diagnose 輸出 Complexity=Plan + `Hard-gate: triggered`。
- 新增 test.sh 案例：餵 `type=meeting` fixture → 斷言 diagnose emit Phase A/B/C 模板、plan 不 chain 到 implement。
- drift-guard / analyzer：斷言 type taxonomy 值集含 `meeting`；README 含階段對照表；Step 3.5 routing 順序文字含 **meeting-first 忠實 7-step 序列**（不省略 Spectra）；Step 3.4 對 `type=meeting` short-circuit；tasks.md / spec.md 的 routing 順序與硬閘 qualifier 與 SKILL 一致（round-2 verify：normative artifact 亦納入 drift-guard）。
- 以上皆以可觀察輸出斷言，不綁定 source line number。

**Scope boundaries:**

- **In scope**：7 個 SKILL/rule/README/CLAUDE.md 編輯（idd-diagnose、idd-plan、idd-issue、**idd-close**、sdd-integration、README、**plugin CLAUDE.md**）+ 2 個新 spec（complexity-hard-gate、meeting-issue-type）+ 1 個 modified spec（superpowers-integration delta）+ 對應 test 案例。（idd-close 承載 meeting 的 decision→action closing + meeting-specific gate；CLAUDE.md 的 Checklist Conventions 加 meeting 例外註記 —— round-1/round-4 verify regression finding：原 Impact 漏列 idd-close 與 CLAUDE.md。）
- **Out of scope**：N 門檻在預設值 5 之外的進一步 calibration（見 Open Questions）、**既有 non-meeting issue 的 Layer V 評分邏輯/anchors**（meeting 因最優先分流而短路跳過 Layer V，屬本 change 範圍；改動的是 non-meeting 行為才 out of scope）、任何新 skill、`/idd-implement` 內部。

## Risks / Trade-offs

- [N 設太低把 impl+test+doc 三件組拖進 Plan（over-trigger）] → 預設 N=5 保守；shared-abstraction 述詞作為更精準的 OR 條件補位；N 作為唯一旋鈕外顯供 calibrate。
- [diagnose 無 diff，scope 估計可能失準] → 依 attribute-assessment 揭露估計 + 理由 + 錨點；認識論地位等同 Layer P/V 判斷；訊號不足時 fail-open 不誤升級。
- [#129 硬閘與 #57 meeting 分支在 Step 3.5 給出雙重 verdict] → 統一 routing 順序決策把 meeting 分流置於複雜度評估之前，硬閘只作用於 code-centric issue，precedence 明確。
- [meeting type 無 TDD verify，品質保證減弱] → 這是刻意的：meeting 是審議非 code，closing 的 decision→action mapping + 人工 review 是其對應的品質閘，非 TDD。
- [Layer 1 narrative disqualifier 攔截 meeting（round-1 verify HIGH-2）] → meeting 分支移到**最優先**（step 1，先於 Layer 1）；type 是確定性欄位，先分流即免疫於內容啟發式。
- [硬閘 ≥5 檔 vs Layer 1「獨立多檔→Simple」矛盾（round-1 verify HIGH-7）] → 硬閘判準改為「單一概念散佈 ≥5 檔」；獨立多檔留給 Layer 1，兩機制不對同輸入給衝突 verdict。
- [meeting 永久豁免 Layer V vagueness（round-1 verify HIGH-8）] → 接受為刻意設計：meeting 的模糊性由 Phase A/B/C 議程釐清；已在 Non-Goals 明述、非「改動既有 Layer V 行為」。
- [string-only drift-guard = false assurance（round-1 verify HIGH-6）] → drift-guard 補強：新增 sdd-integration 內部一致性斷言（meeting 分支存在、無 stale「5-layer」、truth table 有 Hard-gate 欄）、Step 1 type recognition、Next Step meeting row、idd-close TaskCreate 分支 —— 讓「executor 與 canonical rule 漂移」這類可被機械斷言的內部矛盾被鎖住。
- [meeting-first 排序在 Step 3.5 內，但 Step 3.4 Layer V 更早跑，形同虛設（round-2 verify HIGH）] → 於 Step 3.4 頂端加 `type=meeting` short-circuit（跳過整個 Layer V），並在 meeting spec 加對應 Scenario；drift-guard 斷言「跳過整個 Layer V」token。
- [meeting Phase C 行動項無 downstream 打勾者，checklist gate 永久 deadlock close（round-2 verify HIGH）] → idd-close meeting 段改為 close 時經 decision→action mapping 為每個行動項標 `- [x]`/`- [~] tracked in #N`/`- [-]` disposition（依 Checklist Conventions 三者皆不擋）；bare `- [ ]` 無 disposition 仍擋。
- [normative artifact（tasks.md / 兩份 spec.md）仍載 disproven 舊規，且 archive 後成 canonical（round-2 verify CRITICAL + HIGH）] → 修正三檔至 meeting-first + interdependent qualifier + full bypass；drift-guard 擴至 change dir artifact（present 才斷言，downstream/archive 後 graceful skip），把「executor 修了但 spec 沒修」鎖住。
- [5-stage 摘要漏列 Spectra，與 7-step operational list 歧義，且被 design acceptance criterion 鎖死（round-2 verify HIGH）] → 摘要改為忠實 7-step 序列（含 Spectra）與 list 一一對應；acceptance criterion 同步改「7-step 序列」。
- [Spectra-omission 復發於 siblings：design.md Decisions 段、meeting spec Requirement/Scenario 仍是漏 Spectra 的短序（round-3 verify HIGH ×3）] → 全類掃除：design.md line 59 + meeting spec bypass 清單 + test 註解全部補上 Spectra；drift-guard 擴至讀 design.md 並斷言 Spectra 在 routing seq / bypass 清單（點修改成類修）。
- [checklist gate 白名單不認得 meeting 標題 → Phase C 掃不到（round-3 verify HIGH ×2）；且 round-3 的 whitelist bolt-on 其實是 prose-only —— `authoritative_source` resolution 無 meeting 分支、supersession 宣稱未實作，pure-meeting issue 會 deadlock 或完全不 gate（round-4 verify CRITICAL ×2）] → **改採 meeting-specific gate**（使用者裁決，取代 whitelist bolt-on）：`type=meeting` 於 idd-close Step 0 分流、**不走** generic checklist gate / authoritative_source，改跑自足 meeting gate —— 掃 authoritative meeting deliverable（approved Meeting Plan Phase C，退回 diagnose Strategy deliberation Phase C；兩者並存只掃 Meeting Plan），precedence 就地判定、disposition 三態（`[x]`/`[~]`/`[-]`）、bare `- [ ]` 擋 close。revert round-3 加的 whitelist rows；plugin CLAUDE.md 副本改為 meeting 例外註記（兩處同步）；meeting spec 加 gate Requirement + Scenario；drift-guard 斷言 meeting gate 分支存在（機制而非字串）。
- [diagnose_by_type bootstrap TaskCreate 漏 docs/meeting（round-3 verify MEDIUM）] → 補齊 docs/meeting；drift-guard 斷言 meeting 在該行。
- [meeting gate 的「approved Meeting Plan」是 prose 裝飾，真正條件是 existence 非 approval；且 no-deliverable / disposition 時序 / heading 前綴未定義（round-5 verify HIGH ×多）] → source resolution 改為可機械判定：**最新 `## Meeting Plan` comment（prefix 比對）→ 最新 `### Strategy (meeting deliberation)` → 兩者皆無則擋 close（不 vacuous pass）**；明訂執行順序（先 PATCH disposition 再跑 blocking check）；掃 `- [ ]` 行不論 Phase C 是 heading 或粗體。drift-guard 鎖 no-deliverable block + 順序 + 移除「approved」誤導語。
- [`type=meeting` 判定的「type 是確定性欄位」前提無解析程序（round-5 verify HIGH）] → idd-diagnose Step 1 補 type 解析序：GitHub label > body `## Type` heading > 衝突取 label > 皆無則預設非 meeting。drift-guard 斷言解析序存在。
- [Pile B：hard gate「interdependent concept」、shared-abstraction lookup、Layer V prompt 時序、meeting clarity gate、mixed-mode detection 要求把 AI-judgment predicate 完全 deterministic（round-5 verify）] → 判定為 **by-design**：IDD 全部 complexity routing（Layer 1/V/P + 硬閘）皆 AI estimate + audit-trail 揭露（N=5 為使用者裁決）；操作化到完全 deterministic 等於重設計已定案決策 + 大幅擴 scope。以 audit line 揭露為既有解；如需 operational checklist 留作 follow-up issue，不阻擋本 change。

## Migration Plan

純加法，無 breaking change。既有非 meeting issue 不受影響；Layer P 既有 advisory 行為保留（硬閘是疊加層）；meeting close 走**自足 meeting gate**，不改動 code-issue 的 generic checklist gate / `authoritative_source` resolution。type taxonomy 擴充向後相容（舊 issue 無 type=meeting）。Rollback = revert 7 個 SKILL/rule/README/CLAUDE.md 編輯（idd-diagnose、idd-plan、idd-issue、idd-close、sdd-integration、README、plugin CLAUDE.md）+ 移除 3 個新 test suite（complexity-hard-gate / meeting-issue-type / superpowers-staging）+ 移除整個 openspec change dir（proposal / design / tasks / specs，含 complexity-hard-gate、meeting-issue-type 新 spec 與 superpowers-integration delta）；無資料遷移。

## Open Questions

- **N 門檻最終值**：預設 5，於 apply 階段請使用者確認 / 微調（可調旋鈕；3 = 激進、5 = 保守）。
- **shared-abstraction 偵測的機械形式**：diagnose-time 以「符號跨檔 caller 數 ≥ 2」為估計啟發式；實際啟發式細節（如何 grep、要不要限定 helper/constants 目錄）於 apply 階段細化。此為估計非精確判定，接受一定誤差。
