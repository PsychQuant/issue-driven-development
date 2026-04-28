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

「解 bug 的能力」不是一個 binary 屬性，是 5 個 sub-capability 的聯集。對照三個 methodology 的覆蓋：

| Sub-capability | TDD | SDD | IDD |
|---|---|---|---|
| **1. Diagnosis 品質**（症狀 vs root cause） | ❌ TDD 不討論 root cause — 它說「寫個 test 證明 bug 存在」 | ❌ SDD scope 不含 bug | ✅ `idd-diagnose` 強制輸出 root cause |
| **2. Fix completeness**（修一顆還是修整 cluster） | 🟡 部分 — 你可以為 cluster 寫多個 test，但 TDD 沒告訴你 cluster 在哪 | ❌ | ✅ Strategy checklist + verify cross-check |
| **3. Verification independence**（誰驗 implementer 漏的） | ❌ TDD 是 implementer 自己寫 test 自己 pass — 同一人知道 + 同一人 verify | ❌ | ✅ `idd-verify` 6-AI cross-model — implementer 沒參與 |
| **4. Regression prevention**（同一坑不會再踩） | 🟡 test 留下了，但沒人記錄為什麼這個 test 存在 | ❌ | ✅ closing summary 含 root cause + 「為什麼當時這樣修」 |
| **5. Audit traceability**（三個月後知道做了什麼） | ❌ TDD 不管 issue tracker；commit message 看 developer 自律 | ❌ | ✅ `(#NNN)` ref convention + structural + semantic gate |

**TDD 在 5 格裡 1 全 + 2 半 + 2 缺**（只覆蓋 fix 那一段，且不獨立 verify）。
**SDD 5 格全缺**（不解 bug，scope 不同）。
**IDD 5 格全綠**。

Software engineering 的 ROI 是按解 bug 計的，不是按 test 跑得多綠或 spec 寫得多漂亮計的。**TDD/SDD 是 IDD 解 bug 過程裡的內嵌工具，不是同層級的對手。**

---

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
