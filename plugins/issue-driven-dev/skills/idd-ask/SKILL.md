---
name: idd-ask
description: |
  對 issue 知識庫（issues + comments + linked PRs，open+closed）做 grounded 問答 — 鏡像 /spectra-ask。
  「當時為什麼這樣決定？」「X 是怎麼運作的？」→ 讀 top-N 命中全文、合成有引用的答案。
  Use when: 想還原 decision rationale、查歷史脈絡、不想自己翻 issue。
  防止的失敗：三個月後沒人記得當時為什麼；AI 憑記憶腦補歷史。
argument-hint: "<自然語言問題> [--repo owner/repo] [--limit N]"
allowed-tools:
  - Bash(gh search:*)
  - Bash(gh issue list:*)
  - Bash(gh issue view:*)
  - Bash(gh pr view:*)
  - Read
  - Grep
  - TaskCreate
  - TaskUpdate
---

# /idd-ask — issue 知識庫問答（surfacing-only）

自然語言問題 → 檢索 issue 語料 → 讀 top-N 命中**全文**（body + comments）→ **grounded 合成答案**（每個 claim 附引用）。回答「為什麼 / 怎麼運作」— 不是 lookup（那是 `idd-find`）、不是 triage（那是 `idd-list`）。

## 核心原則

> **語料裡沒有的不寫。** 答案只引用 issue / comment 內容，不腦補、不憑訓練記憶補歷史。查無就誠實說查無。
>
> **Surfacing-only 鐵律**：本 skill **不 mutate 任何 state** — 禁止 `gh issue create` / `edit` / `close` / `comment` / label 操作。family 共同契約見 [`references/surfacing-primitives.md`](../../references/surfacing-primitives.md)。

## 與 find 的分工（防定位稀釋）

| | `idd-find` | `idd-ask` |
|---|---|---|
| 問題 | 「有沒有處理過類似 X、在哪」 | 「當時為什麼這樣決定 / X 怎麼運作」 |
| 輸出 | ranked hits（人自己讀） | **合成答案**＋引用（AI 讀完答） |
| 讀取深度 | metadata + overlay | top-N 命中**全文** |
| Token 成本 | 低 | 高（有界：top-N 預設 5，`--limit` 上限 10） |

答案結尾必附 `### Referenced Issues` — 不滿意合成答案時人可 fall through 自行閱讀（ask → find 互補鏈）。

## Configuration

按 [config-protocol](../../references/config-protocol.md) 解析 target repo（`--repo` override → walk-up → git remote fallback）。read-only skill，只用 path / git predicates。group 搜尋（`--target group:<label>`）為 residue，v1 單 repo。

## Execution

### Step 0: Bootstrap Stage Task List（強制）

```
TaskCreate(name="parse_and_gate", description="解析問題 + --repo/--limit；decide-to-search gate（greeting/meta 不搜；無問題 → 從對話 context 推、推不出要求明確問題）")
TaskCreate(name="retrieve", description="idd-find backend 檢索（gh search issues 主 + gh issue list --search fallback，--state all 全語料）→ top-N 候選")
TaskCreate(name="read_full", description="對 top-N 命中 gh issue view --json body,comments 抓全文；linked PR 視需要 gh pr view")
TaskCreate(name="compose_answer", description="grounded 合成：blockquote 原問題 + claim 必附引用 + source priority + 分歧 surface + ### Referenced Issues")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。

### Step 1: Parse + decide-to-search gate

- 問題 = 去 flags 後的 free text；`--limit N`（top-N，預設 5、**上限 10** — 讀全文是 ask 的本質 token 成本，界限明文）
- **不是每個輸入都搜**：greeting / 純 meta 問題（「idd-ask 怎麼用」）→ 直接答，不檢索
- 無問題但對話 context 可推 → 向使用者確認推得的問題後搜；推不出 → 要求明確問題
- **問題長得像 bug report → 不觸發 `/idd-diagnose`、不建案** — 照常回答已知歷史，答案尾端至多附一行「要立案 → `/idd-issue`」
- Unattended mode：確認 gate 跳過、直接以推得的問題搜 + audit line（`[idd-ask: inferred question "<q>" under unattended mode]`）

### Step 2: Retrieval（delegate，不重造）

沿用 **`idd-find` 的 search backend** 契約（[`skills/idd-find/SKILL.md`](../idd-find/SKILL.md) Step 2：`gh search issues` relevance 主 + `gh issue list --search` fallback，`--state all` 全語料）— **引用該段，不內嵌分歧副本**。ask 疊加第二步：

```bash
# top-N 命中抓全文（這是 ask 與 find 的成本分界）
gh issue view "$N" --repo "$GITHUB_REPO" --json number,title,state,body,comments,url
```

跨措辭限制與 find 同界（詞法檢索）；輸出尾端同樣揭露。

### Step 3: Grounded 合成（spectra-ask 規矩移植）

1. **首行 blockquote 引用使用者原問題**
2. **claim 必附引用** — 每個論斷標 `#N`（必要時加 comment 錨點 / 區段名，如「#130 Diagnosis」）。**查無**或語料不足 → 誠實說明 + 建議換 phrasing 或 `/idd-find` 自行翻，不編造
3. **Source priority**：**closed-with-PR > open > orphaned comment** — 已關已 ship 是 ground truth；open 標注「進行中、可能會變」。同題衝突時取高優先源並 surface **分歧**（「#A（closed）採 X；#B（open）傾向 Y」），不靜默擇一
4. 結尾 **`### Referenced Issues`**：`#N (title) — URL`，**只列實際引用的**

### 輸出範例

```
> 為什麼 idd-verify 的 DA 改成 sequenced spawn？

#130（closed）記錄的根因是 polling window 的 socket-crash：DA 用 polling 等其他 4 份
findings 檔時 …（略）… 因此 v2.92 起 coordinator 在 4 檔就緒後才序列 spawn DA（#130 Closing Summary）。

### Referenced Issues
- #130 (idd-verify DA sequenced-spawn) — https://github.com/…/issues/130
```

## 鐵律

- **Read-only** — 問答結束於輸出；任何 state 變更走對應 lifecycle skill
- **不腦補** — 訓練記憶不是語料；只有 retrieval 讀到的才可引用
- **查無是合法輸出** — 語料沉默 ≠ 回答失敗
