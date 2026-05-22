# discussion: add-idd-clarify-skill

Audit trail for the multi-round design iteration that produced `idd-clarify` v4 composable primitive design。Per IDD MANIFESTO audit-trail discipline,本檔保留完整對話 chain 讓 future maintainer 看到設計過程 + critique。

## Triggering case

**`kiki830621/ai_martech_global_scripts#804`(2026-05-21)— K-means 特徵值 incident**

客戶 docx `向創_20260520.docx` 要點 10 原文:

> 「(1)下圖有兩個區隔沒有特徵值出現,可否 prompt 跟他說各群要有至少一個最高得分的**特徵值**出現,並根據**特徵值**意涵來命名」

老師事後跟 user 於 LINE 對話(2026-05-21 21:25-21:29)clarify:

> 「我以為你懂」
> 「應該是說**分群變數**」
> 「很多都沒有分群變數」
> 「我知道」「太忙了」「只能麻煩妳了」「事情太多」「每天都在打戰」

換句話說客戶寫「特徵值」(eigenvalue / feature value)實際**意思是「分群變數 / distinguishing variable」**(K-means 各群最具區辨力的變數)。

### What happened in the issue chain

| Stage | 行為 | Term used |
|---|---|---|
| `/idd-issue` Step 1 source read | 抓 docx verbatim,無 terminology check | 原文「特徵值」 |
| Issue #804 body | blockquote 原文 + AI 摘要「客戶要求 prompt 強制各群至少一個最高得分的特徵值」 | 「特徵值」(propagated) |
| `/idd-diagnose` | 沒重新檢視術語,只 routing / complexity | 「特徵值」(propagated) |
| `/spectra-propose` qef-market-segmentation-redesign spec.md | AI 寫 spec 時自動翻成 `distinguishing variable`(正確語意) | **意外修對了** — AI 獨立知道 K-means context canonical term |
| `fn_D06_01_market_segmentation_kmeans_core.R` / component file | 變數名 `cluster_top_var` / `distinguishing_variables` | **正確語意** |

### 為什麼這次運氣好

K-means「各群最有區辨力的變數」是領域 canonical concept,AI 看到 source 講「最高得分的 X 用來命名」就能自動 map 到 distinguishing variable,所以 spec / code 沒繼承錯誤。

### 為什麼下次未必運氣好

若 source 用的錯誤 term 跟正確 term 有**語意衝突**(不是純命名問題),AI 沒有獨立 domain knowledge 校正,錯誤會繼承下去。例如:

- 客戶寫「PCA 分析」實際做 K-means → AI 可能真的去寫 PCA 分析
- 客戶寫「回歸係數」實際指 ANOVA effect size → AI 寫 lm() 而不是 anova()
- 客戶寫「分群」實際指「分類」(有 ground truth labels)→ AI 寫 unsupervised K-means 而不是 supervised classifier

## Design iteration chain

User user在 Claude Code session 2026-05-21 ~ 2026-05-22 連 4 輪推 design 到更精確,每次 push back 抓 AI over-abstract:

| Iteration | Frame | Critique 抓到的洞 |
|---|---|---|
| v0(my初版)| 獨立 skill `/idd-clarify` with `AskUserQuestion` + `PATCH body` resolution flow | **失職 gatekeeper 問失職 gatekeeper** paradox — 沒 oracle 時 user 就是 over-worked filter,問他等於問空氣 |
| v1(my retry)| 塞進 `idd-diagnose` 當 sub-step,surfacing-only no resolution | **diagnose 預設 issue 對** — 把 State 1(問題是否 framed correctly)塞進 State 2(怎麼解)= category error / paradox |
| v2(my retry)| `idd-issue` Step 4.8 Clarity Surface,跟 4.4 / 4.7 並列 advisory | **lose retroactive case** + clarify logic 跟 idd-issue 耦合 → 未來 reuse 困難 |
| **v3 / v4(final)** | **`/idd-clarify` primitive + `idd-issue` Step 4.6 auto-invokes**(composable orchestrator pattern,Step 4.6 不 4.8 因為後者已被 Split Umbrella SOP 佔用)| **這個對了** |

User 對話 quote(2026-05-22):

> 「我其實覺得還是可以建立:/idd-clarify,只是 idd-issue 最後會直接呼叫」

直接定義 composable primitive 跟 orchestrator 的 boundary。

### Skill graph framing(三軸)

```
| Axis                    | Existing safeguard | Skill                                              |
|-------------------------|--------------------|----------------------------------------------------|
| Confidence              | IC_R010            | idd-issue Step 4.4 + idd-diagnose Step 3.4         |
| Verbatim                | IC_R007            | idd-issue Step 1 source preservation               |
| Terminology/Semantic    | MISSING            | /idd-clarify (新增) ← 本 change                     |
```

User 對話 quote:

> 「diagnose 是承認 issue 的情況下去做的事情」

直接定義 clarify 跟 diagnose 的 boundary — clarify 在 State 1(問題是否正確 framed),diagnose 在 State 2(怎麼解)。

## Recursive evidence

本 session AI 連 4 次 under-verification / over-abstraction,每次 user 抓到都 surface 一個 case-for-`/idd-clarify`:

| # | Incident | Self-evidence type |
|---|---|---|
| 1 | D06 group registry collision(#815)| 跨檔案 step number 推薦無 grep 既存 |
| 2 | v3 design Step 4.8 collision(propose 階段 scout 抓到 Split Umbrella 已佔)| Step number 推薦無 scout 既存 SKILL.md |
| 3 | `df_qef_customer_attributes` 來源未指定(spec / issue 都沒寫)| Missing-context 假設未驗證 |
| 4 | Design 三輪過抽象(v0 → v1 → v2 → v3 才對)| Over-abstraction 不檢查 boundary case |

**Codify 後 AI 不會繼續犯這四種 — 而是 surface 給 user dismiss / resolve**。

User 對話 quote(2026-05-22)on recursive evidence:

> 「連我自己這個 session 都是 case study」

## Open questions resolution(4 條)

Per #135 final design comment 列的 4 open questions,本 spectra change resolution:

### Q1: Auto-trigger scope on idd-issue Step 4.6

**Resolved (per design D3)**:
- doc source(.docx / .pdf):auto-run
- pasted-text:auto-run
- `--multi-finding` mode:**SKIP**(per-finding sub-invocation 跑成本太高)
- Telegram / Apple Mail / Apple Notes: auto-run

### Q2: /idd-clarify vs /spectra-discuss boundary

**Resolved (per design D5)**:
- `/idd-clarify` = text-level audit(既有 issue body terminology / ambiguity / missing-context)
- `/spectra-discuss` = concept-level design alignment(assumption listing / decision exploration / future-shape)
- Cross-link rule:clarify 發現 missing-context 需要 design discussion → annotation 標 「Recommend /spectra-discuss」,**不**自動 chain 進 spectra workflow

### Q3: Terminology heuristic library 維護權

**Resolved (per design D4)**:
- Initial seed 6 rows(K-means / PCA / regression / Bayesian / classification / unsupervised)
- Rule-of-three promotion threshold(同 misuse 出現 3 次升格進 canonical)
- Open PR contribution
- Future plugin-level extension(待實際需求出現後 design)

### Q4: idd-diagnose Step 0.5 gate 強度

**Resolved (per design D2)**:**hard refuse**(類比 PR Gate Check / idd-all-chain #119 fail-fast),refuse + easy-dismiss 等價於 explicit choice。

## Sister concerns filed

本 PR 期間額外 surface 並 file 為 sister issues(不阻塞本 PR):

- **#136**:`/idd-edit` / `/idd-update` 是否也應整合 `/idd-clarify` primitive(symmetry expansion)— P3,待 #135 ship 後評估
- **#137**:Clarity Surface 在 `/idd-all` PR mode unattended caller 下的 interaction contract — P2,須在本 PR implementation 期間 parallel design,本 PR 暫定 fail-fast policy
- **#138**:`/ralph-loop` → `/goal` substitution scope question(orthogonal,user 「順便改」request)— P3

## Cross-references

- Original meta-issue:`PsychQuant/issue-driven-development#135`
- Sister concerns:`#136`, `#137`, `#138`
- Triggering incident:`kiki830621/ai_martech_global_scripts#804`(K-means 特徵值)+ `#815`(D06 group registry collision — same root cause class:AI under-verification before recommending)
- Companion principles:**IC_R007** GitHub Issue Attachments(verbatim preservation — sister axis)/ **IC_R010** Issue Source Confidence Triage(confidence axis — orthogonal)/ **IC_R011** Commercial Project Low-Bar Issue Filing(本 issue file 是 IC_R011 default-on triggers 中「skill plugin design ambiguity」一條的具體 instance)
- Internal precedents:`idd-close` Step 1.5 PR Gate Check(hard-refuse pattern)/ `idd-all-chain` #119 fail-fast precedent / `idd-close` Step 3.5 IC_R011 closing-followup keyword scan(advisory pattern — clarify chose hard-refuse 是 stronger variant)
