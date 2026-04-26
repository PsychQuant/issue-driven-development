# issue-driven-dev — CLAUDE.md

## Purpose

Issue-driven development：每個改動都從 issue 出發，每個 issue 都有驗證過的結案。

Issue 是人和 AI 的介面 — 人負責「什麼是對的」，AI 負責「怎麼做到」。

## 鐵律:Step 0 Bootstrap Stage Task List(v2.18.0+)

**每個 stage skill 的第一個動作必須是 `TaskCreate`**,把該 stage 的所有 execution sub-steps 建成 harness-level todo list。完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。

為什麼:
- Stage 內部的步驟(讀 issue / comment 到 GitHub / 建 milestone / 上傳圖片)容易漏做
- 歷史上看過:診斷完沒 comment / 建完 issue 沒建 milestone / verify findings 沒 post 到 issue
- TaskList 讓進度在 UI 可視化、中斷後可恢復、完成即打勾
- 與 `idd-implement` Step 2.5 的 Strategy-level TaskList 互補(Stage-level 追 skill sub-steps,Strategy-level 追改動 bullets)

## Skills

**流程 skills（主 workflow）**：
| Skill | 防止的失敗 | 用途 |
|-------|-----------|------|
| `idd-issue` | 改了東西卻沒有記錄「為什麼改」 | 建立 well-documented GitHub Issue |
| `idd-diagnose` | 修了表象，沒修根本原因 | 找 root cause / 分析需求 |
| `idd-implement` | Scope creep | 按 diagnosis 紀律實作 |
| `idd-verify` | 自以為修好了 | 用 Codex CLI 獨立驗證 |
| `idd-close` | 三個月後沒人知道做了什麼 | 寫 closing comment + 關 issue |

**輔助 skills（流程外與 comment 管理）**：
| Skill | 防止的失敗 | 用途 |
|-------|-----------|------|
| `idd-update` | Issue body 過時，要讀完所有 comments 才知道現狀 | 同步 body Current Status 區塊 |
| `idd-list` | 不知道有什麼要做、漏掉卡 verify 的 issue | 列出 open issues 含 IDD phase + 建議 next action |
| `idd-report` | 進度不透明，stakeholder 看不到現況 | 產出進度報告到 GitHub Discussions |
| `idd-comment` | 非流程性決定 / 外部 context 散落在 chat | Template-guided comment（decision/note/question/correction/link/errata）|
| `idd-edit` | 手動 `gh api PATCH` 容易字串 escape 誤覆蓋 | 編輯既有 comment（append/replace/prepend-note 三種 mode）|

**Orchestrator skill**：
| Skill | 防止的失敗 | 用途 |
|-------|-----------|------|
| `idd-all` | 手動跑 5 個 idd-* 太繁瑣、容易漏步驟、main 上 commit 沒 review checkpoint | 一鍵跑完 issue→diagnose→implement→verify，所有 commit 在 feature branch + 開 PR，停在 verified 等人 merge |

## Workflow

```
issue → diagnose ─┬→ implement → verify → close                          (Simple)
  ①        ②      │      ③         ④       ⑤
                   │
                   └→ spectra-discuss → spectra-propose → spectra-apply → verify → close + archive  (SDD)
                            ②b               ②c              ③b           ④       ⑤
                            ↑
                            default; opt-out to direct propose only when direction is crystal clear

每個 skill 都吃 #NNN，issue 貫穿全部。
diagnose 判斷 Complexity → Simple 走 implement，SDD-warranted 預設走 spectra-discuss 對齊方向。
```

### SDD 和 TDD 都是 IDD 的特例

業界通常把 TDD、SDD、issue tracking 當作三個獨立的方法論，團隊自行決定要用哪些、怎麼組合。IDD 的核心主張是：**它們不是平行的選擇，而是存在包含關係。**

#### 為什麼 TDD 和 SDD 天然需要 issue

- **TDD 脫離 issue 是不完整的**：TDD 回答「code 是否正確」，但不回答「為什麼要寫這個 code」。沒有 issue，測試只能驗證行為符合規格，卻無法追溯規格本身是否合理。Issue 是 TDD 的錨點 — 它定義了「正確」的標準。
- **SDD 脫離 issue 是不完整的**：SDD 回答「系統如何演進」，但不回答「為什麼要演進」。沒有 issue，spec 只是一份設計文件，缺少「什麼問題觸發了這個設計」的脈絡。Issue 是 SDD 的 motivation。
- **Issue 不需要 TDD 或 SDD 也能獨立存在**：一個 issue 可以只是一筆記錄（docs type）、一個不需要測試的配置改動、或一個需要人工處理的流程問題。Issue 的完整性不依賴於 TDD 或 SDD。

因此包含關係成立：TDD ⊂ IDD，SDD ⊂ IDD，但 IDD ⊄ TDD 且 IDD ⊄ SDD。

#### 在 IDD 中的具體位置

```
IDD (Issue-Driven Development)
 ├── TDD — 內嵌的實作紀律（RED → GREEN → commit）
 │         不管走哪條路，implement 都強制 TDD
 │
 └── SDD — 條件觸發的設計流程
           diagnose 判斷 complexity → SDD-warranted 才走 Spectra
```

| 機制 | 性質 | 觸發條件 | 在 IDD 的位置 |
|------|------|---------|--------------|
| **TDD** | 內嵌強制 | 每次 implement 都執行 | `idd-implement` Step 3 |
| **SDD** | 條件分支 | 跨 3+ 檔案、新抽象、架構決策 | `idd-diagnose` Step 3.5 判定 |

> 不是所有 issue 都需要 SDD，但所有 SDD 都值得有一個 issue。
> TDD 不是可選的 — 它是 `idd-implement` 的強制步驟。

- **Simple**（bug fix、小改動）→ 標準 IDD 流程（含 TDD）
- **SDD-warranted**（跨檔案設計、新抽象、架構決策）→ `idd-diagnose` 判定後銜接 Spectra（仍含 TDD）
- **進度追蹤**：SDD 用 `tasks.md`，issue 只掛一句 `→ see spectra change: <name>`
- **驗證**：統一用 `idd-verify #NNN`（6-AI 交叉驗證）
- **結案**：`idd-close #NNN` 同時觸發 `spectra-archive`

## Configuration

首次使用 `idd-issue` 時會建立 `.claude/issue-driven-dev.local.json`(注意:從 v2.25.0 起是 JSON,不是 YAML/markdown)。

最小設定:

```json
{
  "github_repo": "owner/repo",
  "github_owner": "owner",
  "attachments_release": "attachments"
}
```

完整 schema 和解析規則見 [references/config-protocol.md](references/config-protocol.md)。摘要:

### Six 機制(優先順序由高到低)

1. **per-invocation flag** — `idd-issue --target owner/repo` 或 `--target group:<label>`;sibling skills 用 `--repo owner/repo`
2. **Candidates menu** — config 有 `candidates` + `ask_each_time: true` → AskUserQuestion 選單
3. **Predicates** — `candidates[].when` / `groups[].when` 自動匹配(`path_contains` / `title_matches` / `label_in` 等)
4. **Cascading config** — 從 cwd 往上找 `.claude/issue-driven-dev.local.json`,first match wins(同 eslint/tsconfig 模式)
5. **git remote fallback** — 沒任何 config 時用 `git remote get-url origin`
6. **Groups**(orthogonal) — 一個邏輯 issue 跨多 repo,primary + tracking + cross-link comment

### 範例:Monorepo 路由

```json
{
  "github_repo": "owner/big-monorepo",
  "candidates": [
    {
      "label": "Music sub-package",
      "github_repo": "owner/music",
      "when": { "path_contains": "/packages/music" }
    },
    {
      "label": "Plugin marketplace (auto by title)",
      "github_repo": "PsychQuant/psychquant-claude-plugins",
      "when": { "title_matches": "(?i)\\b(plugin|skill|hook)\\b" }
    }
  ]
}
```

`cd ~/big-monorepo/packages/music && /idd-issue` → 自動路由 `owner/music`(path 預判)。
若使用者輸入 title 含「plugin」,Step 2.5 會問是否切到 plugin marketplace repo。

### 範例:跨 repo coordinated issue

```json
{
  "github_repo": "PsychQuant/foo",
  "groups": [
    {
      "label": "Cross-stack: foo+bar+glue",
      "repos": [
        {"github_repo": "PsychQuant/foo",  "role": "primary"},
        {"github_repo": "PsychQuant/bar",  "role": "tracking"},
        {"github_repo": "PsychQuant/glue", "role": "tracking"}
      ],
      "when": { "label_in": ["cross-package"] }
    }
  ]
}
```

當 issue 加 `cross-package` label,Step 2.5 會切到 group 模式:在 `foo` 建 primary issue,`bar` / `glue` 建 tracking issues(body 首行 `> Tracking primary: foo#N`),最後在 primary issue 留 comment 列出所有 tracking refs。

### Backward compatibility

舊有的單一 `github_repo` config 完全不受影響 — 沒有 `candidates` / `groups` / `when` 就走原本的單一 repo 行為。所有新欄位都是 additive。

## Checklist Conventions

IDD 把 checkbox 當成**契約**，不是願望清單。`idd-implement` 會 bootstrap TaskList 追蹤進度，`idd-close` 會 refuse 關任何還有未勾項的 issue。

### 標記語意

| 標記 | 意義 | 阻擋 close? | 需附 reason? |
|------|------|-------------|-------------|
| `- [ ]` | Open todo，還沒做 | 🔴 是 | — |
| `- [x]` / `- [X]` | 完成，測試通過 | ✅ 否 | — |
| `- [~]` | Skipped（刻意跳過，可能回來做）| ✅ 否 | **必須**附原因 |
| `- [-]` | Won't fix / out of scope（決定不做）| ✅ 否 | **必須**附原因 |
| `- [?]` | Unknown / need input | 🟡 是（同 open）| — |

**Reason 格式**：寫在同一行 dash 後，或下一個縮排 bullet：

```markdown
- [~] Add Redis cache layer — deferred: waiting on infra team's Redis rollout (ETA 2026-05)
- [-] Support Windows paths
  - Won't fix: MCP server is macOS-only; Windows would need a separate binary
```

### 哪些區段會被掃描

`idd-close` 的 Gate Check 只掃**結構化的 checklist 區段**，避免誤判 `## Repro` 或 `## Steps to reproduce` 裡的情境 checkbox：

| 標題 (`## ` 或 `### `) | 掃描 |
|------------------------|------|
| `Strategy` | ✅ |
| `Implementation Plan` | ✅ |
| `Implementation Complete` → `Checklist` | ✅（`idd-implement` Step 5 寫回的 source of truth）|
| `Todo` / `Tasks` / `Checklist` | ✅ |
| `Current Status` → `Tasks` | ✅ |
| `Problem` / `Repro` / `Workaround` / `Expected` / `Actual` | ❌ |
| _其他未列出的標題_ | ❌（保守：只掃白名單）|

### 去重規則

同一個 issue 可能有多個 comments 含相同 source 標題（例如 re-run `idd-implement` 後發了兩個 `## Implementation Complete`）。Gate check **只看最後一個**（按 comment `createdAt` desc），那是最新的 source of truth。

### 為什麼這麼嚴格？

「Strategy 上列了 5 個 bullet，實作了 3 個就 close issue」是最常見的隱形 scope creep：
- 沒做的 2 個被遺忘，3 個月後變成新 bug 報告
- 或者其實根本不打算做，但沒人記錄「為什麼不做」
- 下一次類似需求再次走一遍 diagnose → 討論 → 決定不做 → 忘記 → …

強制 `- [~]` / `- [-]` + reason 的代價是多打 30 秒字，換來的是「這個決定有紀錄」。這在 issue-driven dev 裡比 velocity 重要。

## Commit Conventions

IDD 的 close 流程是由 `idd-close` skill 執行的——它會跑 gate check、post Closing Summary、再實際關閉 issue。**不能**讓 GitHub 繞過這條流程 auto-close issue。

### 規則：一律走 skill，不用 auto-close trailer

| Trailer | 行為 | 在 IDD 裡 |
|---------|------|----------|
| `(#NNN)` / `Refs #NNN` | Cross-reference，不 auto-close | ✅ 推薦 |
| `Closes #NNN` | GitHub 立即 auto-close | ❌ 禁止 |
| `Fixes #NNN` | GitHub 立即 auto-close | ❌ 禁止 |
| `Resolves #NNN` | GitHub 立即 auto-close | ❌ 禁止 |

Commit message 只要用 `(#NNN)` 或 `Refs #NNN` 產生 cross-link 就好。Close 動作由 `/idd-close` 負責。

### 為什麼

#### 失敗模式 A：用 `Closes` trailer → gate bypass

1. Commit message 寫 `Closes #42`
2. Push 觸發 GitHub auto-close
3. `idd-close` 從未執行 → Step 0 Checklist Gate Check 從未跑
4. Strategy 的 `- [ ]` 可能還沒勾完——沒人攔
5. 沒有 Closing Summary——3 個月後回來看 issue 只剩 diagnosis，沒有 Solution / Root Cause 的最終紀錄

→ IDD 的核心契約「沒打勾就不關」+「結案必留 summary」被 silent 繞過。

#### 失敗模式 B：完全不 reference issue → zombie

1. Commit message 完全不寫 `#NNN`
2. Fix 沒 link 到 issue
3. Issue 保持 open，沒人回來 close
4. 堆積成 zombie（#1/#2/#6 都是這個模式，closed 前放 26 天）

→ Issue 被遺忘，類似 bug 再度報告時要重走 diagnose。

### 正確做法

**Both fix at once**: commit message 用 `(#NNN)` 或 `Refs #NNN` reference issue（防 zombie），close 時跑 `/idd-close` skill（enforce gate + post summary + 關 issue）。兩邊責任清楚：

- **Commit** 負責「留 cross-reference 痕跡」
- **Skill** 負責「驗收 + 記錄 + 關閉」

這樣 commit 是 fix 的紀錄、issue 是 workflow 的紀錄，不會互相 bypass。

### 歷史脈絡

- **#1 / #2 / #6** (2026-03)：commit message 用了 `(#1)` 但**沒有** `Closes` trailer，結果 GitHub 不 auto-close，issue 堆積 26 天變 zombie。當時學到的 lesson 是「用 `Closes` trailer」。
- **#11 / #13** (2026-04-14)：套用上面那個 lesson 在 commit message 寫 `Closes #11` 和 `Closes #13`，push 後 GitHub 立即 auto-close——但 v2.17.0 剛加的 `idd-close` gate check **從未跑過**，Closing Summary 也沒 post。之後補 retroactive comments 做補救。

兩個 lesson 綜合後的正確合成：**用 skill 做 close，用 cross-reference 做 commit link**。`Closes` trailer 本身沒有錯，只是對 IDD 的 close 流程有害——我們選擇讓 skill 成為唯一的 close pathway，換回可預期、可驗收的 close 契約。

### 補救：commit 已 push 且 trailer 已觸發 auto-close

1. 不要 reopen → re-close，那是 noise。
2. 補一個 retroactive Closing Summary comment，標題加 `(retroactive — auto-closed via Closes trailer)`，內容照 `idd-close` 的模板：Problem / Root Cause / Solution / Verification / Changes。
3. 在 comment 裡標記 Strategy checklist 的最終狀態（本來 gate 會驗收的東西），確保 audit trail 完整。
4. 記得在日後的 commit message 裡不要再犯。

## 設計哲學

### 五個 Skill = 五個 Checkpoint

每個 skill 是一個強制停頓點：

| Checkpoint | 確認什麼 |
|-----------|---------|
| `idd-issue` 之後 | 我們同意問題是什麼了嗎？ |
| `idd-diagnose` 之後 | 我們理解為什麼了嗎？ |
| `idd-implement` 之後 | 我們只改了該改的嗎？ |
| `idd-verify` 之後 | 真的修好了嗎？ |
| `idd-close` 之後 | 記錄完整嗎？ |

### 與其他方法論的差異

本 plugin 是 **issue-driven**（問題驅動），不是 process-driven（流程驅動）。
所有決策都圍繞 `#NNN`，不是圍繞流程步驟。

IDD 不是把 TDD + SDD + issue tracking 拼在一起的 combo —
而是指出 issue 是更基本的單位，TDD 和 SDD 是從 issue 自然衍生的特化流程。
這解釋了為什麼單獨使用 TDD 或 SDD 時總覺得「少了什麼」：少的就是 issue 提供的 why。

### 參考

- **superpowers** (claude-plugins-official) — 小粒度 skill 設計、verification 獨立化
- 本 plugin 的優勢：per-project config (`.local.md`)、具體 CLI 指令

## Development

- Update after changes: `/plugin-tools:plugin-update issue-driven-dev`
- Health check: `/plugin-tools:plugin-health`
