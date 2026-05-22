# IDD Manifesto

**TDD 寫測試。SDD 寫規格。IDD 解 bug。**

前兩個是手段，IDD 是目的。

---

## 三個 methodology 各自回答的問題

| Methodology | 問的問題 | Audit unit |
|---|---|---|
| **TDD** (Test-Driven Development) | 「這個 function 對嗎？」 | per-test (commit-level) |
| **SDD** (Spec-Driven Development) | 「這個 design 站得住嗎？」 | per-change (rollout-level) |
| **IDD** (Issue-Driven Development) | **「這個 project 結束了嗎？」** | per-issue (lifecycle-level) |

TDD 跟 SDD 強在 **verification** — 給定一個 unit 能驗證對錯。但它們**沒有定義「DONE」**：

- TDD 沒有 DONE — 只有「N 個 test pass」per-snapshot
- SDD 沒有 DONE — 只有「spec 跟 code conform」per-change
- IDD 有 DONE — 「open issues 全 close 且每個都有 verified resolution + closing summary」

「DONE」是 software project completeness 的**唯一可量化定義**。沒這個東西，TDD/SDD 驗證的真實全部會 leak 進「使用者三個月後再踩到」的黑洞。

---

## 為什麼說 IDD 解 bug 比 TDD/SDD 強

「解 bug 的能力」不是一個 binary 屬性，是 6 個 sub-capability 的聯集（v2.50.0+ 新增第 6 軸 Alignment quality）。對照三個 methodology 的覆蓋：

| Sub-capability | TDD | SDD | IDD |
|---|---|---|---|
| **1. Diagnosis 品質**（症狀 vs root cause） | ❌ TDD 不討論 root cause — 它說「寫個 test 證明 bug 存在」 | ❌ SDD scope 不含 bug | ✅ `idd-diagnose` 強制輸出 root cause |
| **2. Fix completeness**（修一顆還是修整 cluster） | 🟡 部分 — 你可以為 cluster 寫多個 test，但 TDD 沒告訴你 cluster 在哪 | ❌ | ✅ Strategy checklist + verify cross-check |
| **3. Verification independence**（誰驗 implementer 漏的） | ❌ TDD 是 implementer 自己寫 test 自己 pass — 同一人知道 + 同一人 verify | ❌ | ✅ `idd-verify` 6-AI cross-model — implementer 沒參與 |
| **4. Regression prevention**（同一坑不會再踩） | 🟡 test 留下了，但沒人記錄為什麼這個 test 存在 | ❌ | ✅ closing summary 含 root cause + 「為什麼當時這樣修」 |
| **5. Audit traceability**（三個月後知道做了什麼） | ❌ TDD 不管 issue tracker；commit message 看 developer 自律 | ❌ | ✅ `(#NNN)` ref convention + structural + semantic gate |
| **6. Alignment quality**（問題本身的清晰度，v2.50.0+） | ❌ TDD 假設 spec 已給;不檢查 issue body 是否模糊 | ❌ SDD spec 已 framed,通常已過 alignment 階段 | ✅ `idd-diagnose` Step 3.4 Layer V Vagueness Pre-check — 6-point Likert 評 V1/V4,trigger 跳 3-option 對齊 |

**TDD 在 6 格裡 1 全 + 2 半 + 3 缺**（只覆蓋 fix 那一段，且不獨立 verify，也不檢查 issue 是否清楚）。
**SDD 6 格全缺**（不解 bug，scope 不同）。
**IDD 6 格全綠**。

Software engineering 的 ROI 是按解 bug 計的，不是按 test 跑得多綠或 spec 寫得多漂亮計的。**TDD/SDD 是 IDD 解 bug 過程裡的內嵌工具，不是同層級的對手。**

> **第 6 軸的意義**:Alignment quality 不只是「issue 寫得好」 — 它是「**AI 對 issue 的理解和 user intent 對齊**」。Layer V 把這個檢查機制化:scope 小但需求模糊的 issue(quadrant A)會被偵測 → user 表態(澄清 / 照做 / 升級 Plan)→ AI 不會 pattern-match 一個錯方向就動手。詳細 routing 邏輯見 [`rules/sdd-integration.md`](rules/sdd-integration.md) Layer V section,屬性評分原則見 [`.claude/rules/attribute-assessment.md`](../../.claude/rules/attribute-assessment.md)。

---

## 三個 IDD Quality Axes — issue body 在進 diagnose 之前的健全性檢查

IDD 對「issue 是否 ready to diagnose」有三個正交品質軸:

| Axis | 問題 | Existing safeguard | Skill / Step |
|---|---|---|---|
| **Confidence**(IC_R010)| 客戶是否真的反映?| Source confidence triage | `idd-issue` Step 4.4 + `idd-diagnose` Step 3.4 |
| **Verbatim**(IC_R007)| 原文是否被改寫?| Source preservation discipline | `idd-issue` Step 1 |
| **Terminology / Semantic accuracy** | source 用詞是否正確?隱含 missing context?| Surfacing-only annotation | `idd-clarify`(v2.72.0+,delegated by `idd-issue` Step 4.6,gated by `idd-diagnose` Step 0.5) |

三軸 orthogonal:每軸獨立 surface 不同類 issue body 品質問題。Source 可能 high-confidence、verbatim 完整保留,但**用詞錯誤**(QEF #804「特徵值」實際是「分群變數」case)。這時 confidence + verbatim safeguard 都 PASS,terminology axis 才能 catch。

**Recursive evidence**(本 plugin 自身 design 階段觀察):AI 對 #135 v3 design 提案三輪過抽象 — 獨立 skill → diagnose sub-step → idd-issue inline,直到 user 連三次 push back 才落到 composable primitive。**AI 在 design 階段也會 over-abstract**,需要 third-party surfacing 機制把「這個 abstraction 真的對嗎?」帶到 review surface。Codify 三軸後 IDD plugin 自己未來的 design iteration 也受惠。

**Composability pattern**:

```
/idd-clarify <#N>                  ← standalone primitive(retroactive audit)
    ↑ delegated by
idd-issue (Step 4.6 auto-invoke)   ← orchestrator(zero UX burden, called at end of filing)
    ↑ gated by
idd-diagnose (Step 0.5 PR Gate)    ← refuses to run if Clarity Surface has unresolved rows
```

Sister concerns(open at #135 ship time):
- [#136](https://github.com/PsychQuant/issue-driven-development/issues/136) — `idd-edit` / `idd-update` 是否也應整合 `/idd-clarify` primitive(symmetry expansion P3)
- [#137](https://github.com/PsychQuant/issue-driven-development/issues/137) — Clarity Surface 在 `/idd-all` PR mode unattended caller 下的 interaction contract(P2)

詳細 design history 見 `openspec/changes/add-idd-clarify-skill/discussion.md`。

## 兩個正交的維度：Verification 與 Closure

```
              Verification axis
              (falsifiability)
                    ▲
                    │
      TDD ●─────────┤
                    │            ● IDD
      SDD ●─────────┤            (有 closure 機制)
                    │
                    │
                    ●────────────────► Closure axis
                                       (DONE definition)
                       TDD/SDD on this axis: 0
                       IDD on this axis: enforced via idd-close
```

**Verification axis** — 能驗證 unit 對錯。TDD/SDD 強，IDD ⊋ TDD ∪ SDD（嚴格大於，見下節）。

**Closure axis** — 能宣告 project 完成。TDD/SDD 沒有定義這個東西。IDD 用 `idd-close` 強制 enforce。

把 closure 跟 falsifiability 放一起看，IDD 不是「比 TDD/SDD 多一點點」，是**打開了第二個維度**。

### Falsifiability：IDD 嚴格大於 TDD ∪ SDD

```
falsifiability(IDD) = falsifiability(TDD)         ← idd-implement Step 3 RED→GREEN→commit (繼承)
                    ∪ falsifiability(SDD)         ← spectra-apply spec/code conformance (繼承)
                    ∪ semantic_check              ← idd-close Step 1.6 keyword → commit/file 驗證
                    ∪ process_compliance          ← issue why、closing summary root cause
                    ⊋ falsifiability(TDD ∪ SDD)
```

`idd-close` 的 two-tier gate（structural + semantic, v2.17.0 + v2.29.0）是讓這個包含關係從 lower bound（"⊇"）變成 strict superset（"⊋"）的關鍵：

| Layer | Check what | 防什麼失敗 |
|------|-----------|-----------|
| **Structural** (v2.17.0) | 有沒有 `- [ ]` 未勾 | Honest forgetting（忘了打勾）|
| **Semantic** (v2.29.0) | 打勾的 bullet 是否有對應 commit/artifact | Motivated cheating（打勾了但沒做）|

兩層加總後，close 不再是 button click，是 **ceremonial declaration** —「我做完了 + 有 audit trail 證明 + verifier 跑過 + closing summary 寫了 root cause」。這時候 closure 才是真的可信的 DONE definition。

---

## Human-in-the-loop: IDD 即 NSQL Confirmation Protocol

IDD 的 human-in-the-loop 不是隨意散落在 pipeline 各處的 ad-hoc 確認 —— 它是 [NSQL](https://github.com/kiki830621/NSQL)（Human-AI Confirmation Protocol）的一個 instance。NSQL 的核心契約：**AI detect ambiguity → 對 user render structured understanding → user confirm/correct intent → execute**。一句話：**clarify before execute, never guess**。

| NSQL confirmation loop | IDD pipeline |
|---|---|
| AI parses & identifies ambiguity | `idd-diagnose` + Layer V / Plan / Spectra（ambiguity detector） |
| AI shows structured understanding | Diagnosis comment / `EnterPlanMode` plan |
| Human confirms 對 / 不對改成… | issue authored / clarified / plan approved |
| Execute | `idd-implement` |
| —（loop closed） | `idd-verify` = **execution-fidelity check**, not a confirmation loop |

關鍵不對稱：**人的 confirmation loop 在 execution 之前就關閉了**。`idd-verify` 檢查的是「執行結果是否忠於已 confirmed intent」，不是再開一次 confirmation loop。Post-execution 沒有東西可以給人 confirm —— issue（已 confirm 的 intent）+ verify（fidelity check）就夠了。

### `verify-gated` 是 terminal 預設 disposition

一次乾淨的 6/6 verify PASS 足以 merge —— issue 是 acceptance contract，verify 確認 delivery。`idd-all` / `idd-all-chain` Phase 6/4 報告的 `verify-gated PASS, ready to merge` 是這個 doctrine 的具體表達。

把 `idd-verify` 的 6-AI ensemble 通過當成「沒 review」是反向誤讀 —— **AI verify PASS 本身就是 review**：5 個 specialized adversarial agents（requirements / logic / security / regression / devil's advocate）+ 一個獨立 model（Codex），cross-lens、falsifiable，在 correctness 維度上**超過**一個人類 merge reviewer 的 thoroughness。Verify 本身是 acceptance 的 falsifiable 部分。

### `--review` flag：opt-in 重開 confirmation loop

罕見情境裡，user 想對自己 issue 起疑（"我可能 issue 寫錯了"），可以用 `--review` flag 重開 confirmation loop。Phase 6 報告會從 `verify-gated PASS, ready to merge` 切成 `verify-gated PASS — awaiting human acceptance (re-opened confirmation loop per --review)`。

`--review` **不是 quality gate** —— 它是 **orchestrator-scope** opt-in 重開 confirmation loop (per #108 DA3)。Verify 的 falsifiability 不受影響；改變的只是「user 還想自己再過一次」的 explicit 表態。`--review` 是 per-invocation flag，**不是** standing config field —— 一個 exception 不該升格成 standing policy。

### auto-merge 的合法性與限制

在 `verify-gated PASS` 的 doctrine 下，clean 6/6 verify PASS 之上 auto-merge **是合法的** —— 證成理由是 "verify is the gate"（獨立 ensemble 已抓 catch），**不是** "merges are reversible"（revert 不對稱：一個 reviewed change + 兩個 history scars + distribution 已 ship）。

Guardrails 是 mandatory，不是 skipped：

- Clean 6/6 PASS only（never CONDITIONAL / FAIL）
- Step 0.8 auto-close-trap scan 必須 clean
- Squash commit message 必須 clean

**auto-merge ≠ auto-close** —— `idd-close` 仍要跑（closing summary 是 audit artifact，不可省）。

`idd-all` / `idd-all-chain` 預設**不**做 auto-merge（鐵律保留 `永遠不 auto-merge PR`）—— 那是 **#37** bulk-solve autopilot 的 mechanic，由 #37 處理 auto-merge → auto-close 序列細節，**不**在 #102 scope。本 section 只把 `verify-gated` 升格成 named, sanctioned terminal disposition —— 讓 #37 之後接手 autopilot 時有 doctrine 可依。

同樣的約束適用於 `/loop` / `ralph-loop` / 外部 CI 等自動化 caller：把 Phase 6 「verify-gated PASS, ready to merge」當作「請 `gh pr merge`」的 trigger 是**讀錯了**。Doctrine 只 sanction 那個 disposition 為合法 terminal state，**沒有**授權任何 caller 自動 merge。Auto-merge 路徑統一由 **#37** 用 guardrail-aware mechanic 接手；在 #37 ship 前，自動化 caller 仍須停在 Phase 6 report 並由 user / `idd-close` 接手實際 merge。

---

## TDD/SDD 是 IDD 的 special case

業界通常把 TDD、SDD、issue tracking 當作三個獨立的方法論，團隊自行決定要用哪些、怎麼組合。IDD 的核心主張是：**它們不是平行的選擇，而是存在包含關係。**

- **TDD 脫離 issue 是不完整的** — TDD 回答「code 是否正確」，但不回答「為什麼要寫這個 code」。沒有 issue，測試只能驗證行為符合規格，卻無法追溯規格本身是否合理。Issue 是 TDD 的錨點。
- **SDD 脫離 issue 是不完整的** — SDD 回答「系統如何演進」，但不回答「為什麼要演進」。沒有 issue，spec 只是一份設計文件，缺少「什麼問題觸發了這個設計」的脈絡。
- **Issue 不需要 TDD 或 SDD 也能獨立存在** — 一個 issue 可以是一筆紀錄（docs）、一個不需要測試的配置改動、或一個流程問題。

因此包含關係：**TDD ⊂ IDD，SDD ⊂ IDD，但 IDD ⊄ TDD 且 IDD ⊄ SDD**。

| 機制 | 性質 | 觸發條件 | 在 IDD 的位置 |
|------|------|---------|--------------|
| **TDD** | 內嵌強制 | 每次 implement 都執行 | `idd-implement` Step 3 |
| **SDD** | 條件分支 | 跨 3+ 檔案、新抽象、架構決策 | `idd-diagnose` 判定後接 spectra-* |

---

## 設計：5 個 Skill = 5 個 Checkpoint

每個 skill 是一個強制停頓點 — **人決定，AI 執行**：

| Checkpoint | 確認什麼 | 防的失敗 |
|-----------|---------|---------|
| `idd-issue` 之後 | 我們同意問題是什麼了嗎？ | 改了東西卻沒紀錄「為什麼改」 |
| `idd-diagnose` 之後 | 我們理解為什麼了嗎？ | 修了表象，沒修根本原因 |
| `idd-implement` 之後 | 我們只改了該改的嗎？ | Scope creep |
| `idd-verify` 之後 | 真的修好了嗎？ | 自以為修好了 |
| `idd-close` 之後 | 紀錄完整嗎？ | 三個月後沒人知道做了什麼 |

Issue 是人和 AI 的介面 — 人負責「什麼是對的」，AI 負責「怎麼做到」。

---

## Case Study: `che-word-mcp` #56 Cluster

`che-word-mcp` 是用 IDD 開發的 233-tool Swift OOXML server。2026-04 期間，issue #56 暴露了一個 P0 critical bug：`save_document` 在 round-trip 時 lossy re-serialization，會 strip 32/34 個 OOXML element。這顆 bug 的處理過程是 IDD 解 bug 能力的具體 demo。

### IDD 路徑（實際發生）

```
v3.13.0  closes #56 P0          ← 主 fix
         └─ idd-verify 跑完 6-AI cross-model verify
            └─ 抓出 round 2 verify findings: 8 P0 + 3 P1（"無 source 變更" 的修法）
v3.13.1  fix round 1 hot-fix (F1-F4)
v3.13.2  fix round 1 hot-fix (pPr double-emission)
v3.13.3  fix round 2 batches A/B/C/D — 8 P0 + 3 must-fix P1
v3.13.4  ...
v3.13.5  closes #56 round 5     ← 30 findings 全部清完
```

5 sub-stack rounds、30 findings、6 個 patch release、所有 follow-up issue（#57 #58 #59 #60 #65 #66）以 `(#NNN)` 引用 #56 cross-link。

### 純 TDD 假想路徑

```
v3.13.0  closes #56 — fix + 1 round-trip test pass
         └─ developer 認為 done
2026-05  使用者報 #57「lang attribute 在 round-trip 後消失」
2026-05  使用者報 #58「TOC 的 bookmark 偶爾消失」
2026-06  使用者報 #59「whitespace 在 run boundary 被吃掉」
2026-08  使用者報 #60「rFonts 74% 場景丟失」
...
```

純 TDD 路徑會 leak 30 - 1 = 29 個 finding，因為 TDD 不獨立 verify、不會主動找 cluster — 它假設 implementer 寫的 test 就是完整 spec。30 個 finding 用「使用者三個月後踩到再報」的形式，會散落 6 個月以上才修完，而且每個都是獨立 bug report，沒互相 link。

### 關鍵差異不在 fix 速度

兩條路徑修完的最終 source code 可能類似。差別在：

1. **時間軸壓縮** — IDD 在 2 週內處理完 30 個 finding，TDD 路徑會被使用者拉到 6+ 個月
2. **Audit trail 完整** — IDD 有 #56 → #57 → ... 的 cluster 鍊；TDD 路徑是 30 個獨立 bug report，沒人看出 cluster 存在
3. **Regression prevention** — IDD closing summary 紀錄 root cause，下次有類似 PR 時 reviewer 看到 #56 的 closing comment 知道要查什麼；TDD 路徑沒留 audit trail，下次同樣 cluster 又重來一遍

> "30 findings via 6-AI verify, 5 sub-stack rounds" 這種 metadata 在一般 plugin CHANGELOG 裡看不到，因為一般 fix workflow 沒有「verify 自己有 round」這個概念。這是 IDD 解 bug 能力的指紋。

---

## Anti-pattern: SDD escalation 過度敏感（2026-04-30 修訂）

SDD ⊂ IDD 的包含關係不代表「複雜的 issue 都該升級 SDD」。實務上 IDD → SDD 升級**最常見的 failure mode 是 over-trigger** — 把 cross-file research analysis、多步驟 narrative work、multi-doc edits 等「scope 大但無 spec contract 需求」的 issue 強行升級成 spectra change,結果 spec/design/tasks artifacts 變成 fluid wording 的 freeze 嘗試,反覆 ingest 修訂卻 converge 不了。

### Case study: `kiki830621/collaboration_liu-thesis-analysis#21`

**Issue 性質**: research analysis(Exp2 SP-stratified contrasts vs Exp3 Human/Speaker + 摘要 v22 改寫)。Deliverable 是 R script outputs + abstract wording + cross-issue comments,**沒有任何 caller 會依賴的 reusable abstraction**。

**前版 OR-trigger logic 命中**:
- ✓ 改動跨 3+ 檔案(R script + outputs/ + docs/ + 摘要)
- ✓ Strategy 5+ 步驟(setup + partition + contrasts + sensitivity + narrative)
- ✗ 新可重用抽象、新 protocol、modify normative spec — 全 No

兩個 false-positive(scope hint)讓 issue 升級 SDD。

**實際 outcome**:
- Spectra change 經三輪 framing 修訂(over-claim「SP 之外 affordance」 → HsuanYuLiuuu Q2 push-back 撤回 → over-claim「重要因素 vs 重要基礎」 → 第三輪撤回到老師原版 wording)
- 真正的 surgical work(加 Low-SP × Human contrast + 撤 over-claim wording)在第二輪 follow-up 走 Simple path 才精準完成
- HsuanYuLiuuu 的 Q1+Q2 collaborator pushback 比 6-AI verify 更有效;這類 review 用 IDD comments 已足夠
- 過度生產的 narrative artifacts(`sp_stratified_narrative.md` / `sp_construct_mapping.md` / `mismatch_hypothesis_predictions.md`)是 spec 思維的副產品,實際**不一定進論文**

### 為什麼 narrative work 不適合 SDD

Spec 是 contract — 給 caller 用來驗證 conformance。Narrative wording(摘要、論文段落、報告)**by design 是 fluid 的**:它隨 reviewer feedback、advisor pushback、journal style guide 演化。試圖 spec 化 narrative 會產出每次都要 rewrite 的脆弱文件,而不是穩定的 contract。

Ad-hoc analysis script 同理:當 question 答完,script 進 archive,不會被 future caller 呼叫,沒 contract 需要 verify。

### 修正後的 logic(v2.36.0+)

`rules/sdd-integration.md` 改為 **4-layer 評估產出 3-tier verdict**:

**4-layer evaluation**:

1. **Layer 1 disqualifiers**(任一命中 → 強制 Simple): narrative deliverable / ad-hoc analysis / no-caller code / multi-file independent
2. **Layer 2 + Layer 3 (Spectra)**: Layer 2 必要條件(published API/protocol/skill/tool 給 future callers + documented contract) + Layer 3 至少一個(modify normative spec / cross-spec impact / architectural decision)
3. **Layer P (Plan)**: 至少一個 — 2+ 互依檔案 / 5+ ordered steps / decision-heavy with 2+ valid approaches / risk-sensitive boundary / cross-file refactor without external contract change
4. 否則 → Simple(default)

**3-tier verdict**:

| Verdict | Path | 場景 |
|---------|------|------|
| `Simple` | `/idd-implement #N` | clear root cause、單檔、follow existing pattern |
| `Plan` (新) | `/idd-plan #N` | think before leap，但無 published API contract |
| `Spectra` (rename from `SDD-warranted`) | `/spectra-discuss → spectra-propose → spectra-apply` | 有 published API contract 給 future callers |

`SDD-warranted` 保留為 backward-compat alias(parse as `Spectra`),既有 issue 的 diagnosis comment 不需重寫。

**跨檔案** 跟 **多步驟** 從 SDD trigger 降為 Plan signal — 它們表示「需要 deliberation」,不表示「需要 spec contract」。default = Simple,Plan/Spectra 都需 explicit escalation。

> **教訓**: 「scope 大」、「需要先想清楚」、「需要 spec contract」是 **三件**事，不是兩件。前者用 IDD checklist + sequential sub-tasks 處理；中者用 Plan tier 的 EnterPlanMode approval gate；後者才需要 Spectra 的 spec/proposal/tasks artifacts。三層都是工具，工具錯用比工具不用更貴。
>
> **為什麼新增 Plan tier**: che-word-mcp#104 是 motivating example — 被判 Simple 直接 implement，6-AI verify 才抓到 P1 sub-bug(Run.toXML rawXML short-circuit 默默蓋掉 Run.text 寫入)。Implementation Plan 在 EnterPlanMode 給 user review 30 秒就能抓到的 case，省下後續補 commit 的迴圈。Plan tier 對「已知 risky boundary 的單筆改動」是 sweet spot。

---

## 這個 plugin 不是什麼

- **不是另一個 issue tracker**。GitHub Issues 已經夠用。IDD 不取代 issue tracker，是定義「以 issue 為中心的開發紀律」。
- **不是 GitHub workflow automation**。IDD 不自動化 issue triage / labels / projects。它定義 issue 從 open 到 close 的**人類 decision points**。
- **不是 process for process 的 ceremony**。每個 skill 都防一種具體的歷史失敗（zombie issue、scope creep、symptom-fix-without-root-cause、用過的 trailer 又繞過 gate）。Ceremony 是有理由的 — `CLAUDE.md` 跟各 skill 文件都記了 lesson chain。

---

## 一句話總結

> **TDD 跟 SDD 都驗證「對」，只有 IDD 驗證「完」。**
>
> 一個 project 可以同時用三個：TDD 管 commit，SDD 管 design rollout，IDD 管 issue lifecycle。三層 audit 加總起來才是「真的完成」。少哪一個都會 leak — TDD 缺 → 不知道單元對不對；SDD 缺 → 不知道 design 站不站得住；IDD 缺 → **不知道整個 project 完了沒**。

---

維護者：Che Cheng
首次版本：2026-04-28（針對 issue-driven-dev v2.32.0 的方法論論述）
