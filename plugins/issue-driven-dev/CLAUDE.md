# issue-driven-dev — CLAUDE.md

## Purpose

Issue-driven development：每個改動都從 issue 出發，每個 issue 都有驗證過的結案。

Issue 是人和 AI 的介面 — 人負責「什麼是對的」，AI 負責「怎麼做到」。

## Skills

| Skill | 防止的失敗 | 用途 |
|-------|-----------|------|
| `idd-issue` | 改了東西卻沒有記錄「為什麼改」 | 建立 well-documented GitHub Issue |
| `idd-diagnose` | 修了表象，沒修根本原因 | 找 root cause / 分析需求 |
| `idd-implement` | Scope creep | 按 diagnosis 紀律實作 |
| `idd-verify` | 自以為修好了 | 用 Codex CLI 獨立驗證 |
| `idd-close` | 三個月後沒人知道做了什麼 | 寫 closing comment + 關 issue |

## Workflow

```
issue → diagnose → implement → verify → close
  ①        ②          ③         ④       ⑤

每個 skill 都吃 #NNN，issue 貫穿全部。
```

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

### 參考

- **superpowers** (claude-plugins-official) — 小粒度 skill 設計、verification 獨立化
- 本 plugin 的優勢：per-project config (`.local.md`)、具體 CLI 指令

## Development

- Update after changes: `/plugin-tools:plugin-update issue-driven-dev`
- Health check: `/plugin-tools:plugin-health`
