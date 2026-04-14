# issue-driven-dev — CLAUDE.md

## Purpose

Issue-driven development：每個改動都從 issue 出發，每個 issue 都有驗證過的結案。

Issue 是人和 AI 的介面 — 人負責「什麼是對的」，AI 負責「怎麼做到」。

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

首次使用時會建立 `.claude/issue-driven-dev.local.md`：

```yaml
---
github_repo: "owner/repo"
github_owner: "owner"
attachments_release: "attachments"
---
```

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
