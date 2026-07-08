<!-- 本 change 全部落在單一 issue-driven-dev plugin 的 skill/rule/README，屬同一內聚子系統（Plan / pre-implementation tier）。任務按依賴排序：hard gate 與 meeting type 各自的檔案先就位，最後 Step 3.5 統一 routing 收斂耦合。`[P]` 只標記與其他 pending task 檔案互斥且無未完成依賴者。 -->

## 1. 硬閘（#129，complexity-hard-gate）

- [x] 1.1 為 **MUST-trigger complexity hard gate layered above Layer P** 先寫 drift-guard fixture（TDD RED）：給定「估計 ≥5 檔」與「動到 shared abstraction」兩組 diagnose 輸入，斷言 Complexity verdict = `Plan`；給定「1 檔、無 shared abstraction、無 Layer P 訊號」斷言 verdict = `Simple`。落實 design 決策 **硬閘疊加於 Layer P 之上，不反轉 Simple 預設**。驗證：新增 fixture 在實作前執行為 RED（斷言失敗）。
- [x] 1.2 在 `plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md` Step 3.5 與 `plugins/issue-driven-dev/rules/sdd-integration.md` Layer P 段落實作硬閘：`Plan` 只升級不反轉，門檻 N=5、shared-abstraction 述詞 =「符號跨檔 caller 數 ≥ 2」。落實 design 決策 **硬閘判準用 diagnose-time 的 AI scope 估計，門檻 N=5 檔 + shared-abstraction 述詞**。驗證：1.1 fixture 由 RED 轉 GREEN，且 Simple-default fixture 仍 GREEN。
- [x] 1.3 實作 **Hard-gate estimate is disclosed in the audit trail**：diagnose 於 Diagnosis comment 印出單行 `Hard-gate: <triggered|not triggered> — <reason with anchors>`，訊號不足時印 `insufficient signal` 且不觸發（fail-open 回 Layer P）。驗證：新增 fixture 斷言三種情境（triggered／not triggered／insufficient signal）各自輸出對應 audit line 字串。
- [x] 1.4 實作 **Shared-abstraction trigger forces family-wide Plan scope**：shared-abstraction 觸發時，產出的 Plan 列舉該抽象的所有已知 call site / family member 為 in-scope。落實 design 決策 **硬閘觸發後，Plan 必涵蓋 family-wide 影響**。驗證：fixture 給定「scoring helper 被三個 sibling 量表共用」，斷言 Plan 列出三個 sibling（非僅 issue 標題點名的單檔）。

## 2. meeting 型別（#57，meeting-issue-type）

- [x] 2.1 [P] 實作 **meeting is a first-class issue type**：在 `plugins/issue-driven-dev/skills/idd-issue/SKILL.md` 的 type taxonomy 加入 `meeting`（與 `bug` / `feature` / `refactor` / `docs` 並列），idd-issue 接受 `meeting` 為合法 type 值。驗證：drift-guard 斷言 taxonomy 行含 `meeting`；以 `meeting` 建 issue 不 fallback 成 `feature`、不被拒。
- [x] 2.2 實作 **Diagnose emits a deliberation Strategy for meeting issues**：`type=meeting` 時 idd-diagnose emit Phase A/B/C 審議 Strategy 模板（agenda / decision points / action items），不 emit code-centric 的 Files & Changes。驗證：fixture 斷言 meeting issue 的 Strategy 含 Phase A/B/C 段、且不含 Files & Changes 段。
- [x] 2.3 實作 **Plan for meeting issues skips the implement chain**：`plugins/issue-driven-dev/skills/idd-plan/SKILL.md` 對 `type=meeting` 用 meeting-adapted Plan body schema，且不 chain 到 `/idd-implement`。驗證：fixture 斷言 meeting plan 用 meeting schema 且輸出不含對 `/idd-implement` 的邀請/呼叫。
- [x] 2.4 實作 **Meeting closing maps decisions to actions without a TDD verify pass**：closing meeting issue 以 decision→action mapping 作 closing summary，不要求 `/idd-verify` TDD pass 為前置。落實 design 決策 **meeting 作為 first-class type：diagnose Strategy 模板 + plan skip-chain + closing 語意**。驗證：fixture 斷言 meeting close 路徑產出 decision→action 對照且不 gate 於 idd-verify。

## 3. 耦合收斂（#129 × #57）

- [x] 3.1 於 idd-diagnose Step 3.5 建立統一 **meeting-first** routing 順序：(1) `type=meeting` 分支 →(2) Layer 1 disqualifier →(3) Layer V vagueness →(4) Spectra（Layer 2+3）→(5) #129 hard gate →(6) Layer P →(7) Simple default，確保 meeting issue 最優先分流（先於 Layer 1 / Layer V，含 Step 3.4 short-circuit）、不被硬閘或 Layer P 雙重判定。落實 design 決策 **Step 3.5 統一 routing 順序（消解 #129×#57 耦合）**。驗證：fixture 斷言 meeting issue 走 meeting 分支（無 Simple/Plan complexity verdict）、非 meeting 的 code issue 才進硬閘與 Layer P。（round-2 verify CRITICAL fix：此 task 文字原本仍是 disproven 的 Layer-1-first 序，與 SKILL/rule/design 全部矛盾。）

## 4. superpowers 委派（#111，superpowers-integration）

- [x] 4.1 [P] 實作 **Pre-implementation staging hand-off to superpowers**：在 `plugins/issue-driven-dev/README.md` 加 IDD↔superpowers 階段對照表（標明 verify ensemble 與 close audit trail 為 IDD 獨有、無 superpowers 對應），並於 idd-issue 建立摘要步驟與 idd-diagnose 對 design-heavy issue 印非綁定 hand-off pointer 指向 `superpowers:brainstorming`；不新增 `idd-brainstorm` / `idd-write-plan`。落實 design 決策 **pre-implementation staging 委派 superpowers，不自建**。驗證：README 表格內容審查通過；fixture 斷言 design-heavy diagnose 輸出含 `superpowers:brainstorming` pointer 字串；`ls plugins/issue-driven-dev/skills/` 不含 `idd-brainstorm` / `idd-write-plan`。
- [x] 4.2 更新 **Kept disciplines are excluded from delegation**：在 superpowers-integration 契約區分「delegation（IDD flow 內部呼叫，仍禁止）」與「hand-off pointer（idd-issue/idd-diagnose 對使用者的非綁定建議，允許）」，並保留 idd-plan 無 superpowers 呼叫的機械檢查。驗證：`grep -rn 'superpowers:' plugins/issue-driven-dev/skills/idd-plan/` 回傳零命中；契約文字明述 pointer ≠ delegation。

## 5. 迴歸防護與驗證

- [x] 5.1 彙整三條決策的 drift-guard 覆蓋並跑全套 plugin 測試 + `spectra validate "reshape-plan-preimpl-tier"`：確保硬閘 fixtures、meeting fixtures、superpowers pointer/grep 檢查全 GREEN，Simple 預設未回歸。驗證：plugin test suite 全綠、spectra validate 通過。
