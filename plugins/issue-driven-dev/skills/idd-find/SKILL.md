---
name: idd-find
description: |
  對 open+closed 全語料做語意查找：「之前是不是處理過類似的問題？」
  GitHub search relevance 排序 + IDD phase / PR overlay。surfacing-only（read-only）。
  Use when: 建新 issue 前查重、找舊案考古、想引用過往結案紀錄。
  防止的失敗：重複 diagnose 已解過的問題；忘記三個月前的同類 fix 在哪。
argument-hint: "<free-text query> [--repo owner/repo] [--limit N]"
allowed-tools:
  - Bash(gh search:*)
  - Bash(gh issue list:*)
  - Bash(gh issue view:*)
  - Bash(gh pr list:*)
  - Read
  - Grep
  - TaskCreate
  - TaskUpdate
---

# /idd-find — 語意查找（surfacing-only）

對目標 repo 的 **open+closed** 全語料跑 GitHub search relevance，輸出 ranked hits 並疊加 IDD 資訊。回答「有沒有處理過類似 X」— 不是 triage（那是 `idd-list`）、不是 lifecycle step。

## 核心原則

> **Surfacing-only 鐵律**：本 skill **不 mutate 任何 state** — 禁止 `gh issue create` / `gh issue edit` / `gh issue close` / `gh issue comment` / label 操作。查到之後要動什麼，交還使用者或對應 lifecycle skill。surfacing-only primitive family（idd-list / idd-clarify / idd-find）的共同契約見 [`references/surfacing-primitives.md`](../../references/surfacing-primitives.md)。

## 與 idd-list 的分工（防定位稀釋）

| | `idd-list` | `idd-find` |
|---|---|---|
| 問題 | 「現在有什麼、在哪個 phase」 | 「有沒有處理過類似 X」 |
| 輸入 | filters（state / label / limit） | 自然語言 query |
| 語料 | open（預設） | **open+closed 全語料** |
| 排序 | updatedAt | GitHub relevance |

**Filter flags 拒收**：`--state` / `--label` / phase filter 一律 abort 並導流 `idd-list`（usage 訊息明示）。要完整 cluster / triage 視圖 → `idd-list`。

## v1 誠實邊界

搜尋 backend 是 **GitHub search relevance**（詞面比對 + 排序）。**跨措辭**同義查找（「白畫面」vs「blank screen」）查不到 — 每次輸出尾端印一行邊界提示。embedding 語意搜尋是 #139 的明確 residue，v1 不做、也不假裝有。

## Configuration

按 [config-protocol](../../references/config-protocol.md) 解析 target repo（`--repo` per-invocation override → walk-up config → git remote fallback）。read-only skill，只用 path / git 類 predicate。

## Execution

### Step 0: Bootstrap Stage Task List（強制）

```
TaskCreate(name="parse_args", description="free-text query + --repo/--limit；偵測 filter flags（--state/--label 等）→ abort 導流 idd-list")
TaskCreate(name="search_corpus", description="gh search issues 主查詢（--state all 全語料，relevance 排序）；失敗/rate-limit → fallback gh issue list --search")
TaskCreate(name="overlay_idd", description="open hits 解析 body **Phase**: + open-PR ref（→ PR #M）；closed hits 標 Closing Summary 有無")
TaskCreate(name="render_results", description="ranked 列表 + 邊界提示行；空結果誠實降級（建議放寬 query）")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。

### Step 1: Parse arguments

- Query = 去掉 flags 後的全部 free text（必填；空 → usage）
- `--repo owner/repo`（optional override）、`--limit N`（預設 15，上限 50）
- **拒收** `--state` / `--label` / `--phase` 等 filter flags → abort：`filtering is idd-list's surface — /idd-list --state ... --label ...`

### Step 2: Search（主 + fallback）

```bash
# 主查詢：GitHub search relevance，open+closed 全語料
gh search issues "$QUERY" --repo "$GITHUB_REPO" --state all --limit "$LIMIT" \
  --json number,title,state,updatedAt,url

# fallback（gh search 不可用 / 403 rate-limit）：
gh issue list --search "$QUERY in:title,body" --repo "$GITHUB_REPO" \
  --state all --limit "$LIMIT" --json number,title,state,updatedAt,url
```

fallback 啟用時印一行 notice（排序品質可能較差）。

### Step 3: IDD overlay

- **Open hit**：`gh issue view N --json body` 解析 `**Phase**:` 行（同 idd-list Step 3 規則；無 → `(no phase)`）；`gh pr list --state open` body scan `#N` → 有 → 標 `→ PR #M`（精簡版 — 不做 cluster leader 邏輯，要完整視圖導流 idd-list）
- **Closed hit**：comments 掃 `## Closing Summary` 開頭 → 有 → 標 `📜 closing summary`（可考古的結案紀錄）；無 → 標 `(closed, no summary)`

### Step 4: Render

```
Find: "comment surgery escape"  (repo: owner/repo, 15 hits max)

 1. #150 [closed 📜 closing summary] fix: idd-edit body wipe on bad sed — updated 2mo ago
 2. #158 [implemented → PR #257]     idd-edit batch × R5 refuse semantics  — updated 4d ago
 3. ...

⚠ v1 邊界：GitHub relevance 是詞面比對 — 跨措辭同義（例：白畫面 vs blank screen）可能漏；換個關鍵詞再試。
```

**空結果誠實降級**：`(0 hits — 試著放寬 query：拆關鍵詞、去修飾語、換同義詞)` — 不編造相近結果。

### Unattended mode

不跳任何 AskUserQuestion（本 skill 本來就無互動 gate）；空結果照 Step 4 降級輸出。delegate 呼叫方（如 idd-issue 查重）自行消費輸出。

## 鐵律

- **Read-only** — 查到該做什麼是人的決定；本 skill 結束於輸出
- **不假裝語意** — relevance 邊界每次都印，embedding 是 residue 不是隱藏功能
- **空結果是合法輸出** — 查無 ≠ 失敗
