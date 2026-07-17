# Dashboard Comment（#133, v2.97.0+）

**一個 issue、一則 human-facing dashboard comment**：給 reviewer / collaborator 的敘事快照（現在在哪、卡在哪、你該做什麼），與 body `## Current Status`（結構化、給 AI / parser 讀）分工。本檔是格式與更新時點的 canonical 契約；4 個 lifecycle SKILL 的接線點與 `idd-report --rollup`（#134）都引用本檔，不內嵌複本。drift-guard：`scripts/tests/dashboard-comment/test.sh`。

## 分工（為什麼不是 body 的一部分）

| Surface | 讀者 | 性質 |
|---------|------|------|
| body `## Current Status` | AI / parser（idd-list、idd-update） | 結構化欄位（`**Phase**:` 等），機器可靠解析 |
| dashboard comment | 人（reviewer / collaborator / 未來的自己） | **narrative for humans** — 一句話現況、blocker、行動呼籲；不要求機器可解析 |

body 頂部（Current Status 區塊內）放一行 link 指向 dashboard comment（可發現性）；dashboard 不重複 body 的結構化欄位。

## 格式模板

comment **第一行必須是 marker**（機器定位用，更新時以 **marker 定位**做 comment surgery）：

```markdown
<!-- idd:dashboard -->
## 📊 For Reviewer / Collaborator

**現在**：<一句話 current state，人話，不是 phase 名>
**Blocking**：<卡什麼 / 等誰；沒有就寫「無」>
**你該做什麼**：<具體行動呼籲，例：review PR #N 的 X 段 / 無需動作，等 verify>

_last-updated by <skill> at <phase transition>, <YYYY-MM-DD>_
```

- `<!-- idd:dashboard -->` 每個 issue 至多一則 comment 帶此 marker（found ≥ 2 → 取最早那則更新、警告）
- `last-updated by` 是 provenance 欄：哪個 skill 在哪個 phase 轉換時更新的 — dashboard 過期時人一眼看出斷在哪站

## 更新時點表（只綁 phase 轉換 — anti-fatigue 鐵律）

**唯一合法的更新時點是 phase 轉換**（≤ 5 次 / issue 生命週期）。中間進度（commit、finding、討論）一律不觸發 — 那正是 #116 的 notification fatigue class：訂閱者每次 comment 更新都收通知，高頻更新會讓人 mute 整個 issue，dashboard 就死了。

| Phase 轉換 | 負責 skill | Dashboard 更新內容 |
|-----------|-----------|------------------|
| → `diagnosed` | `idd-diagnose` | 現況 = root cause 一句話；你該做什麼 = 審 diagnosis / 等 implement |
| → `implemented` | `idd-implement` | 現況 = 改了什麼一句話 + PR ref；你該做什麼 = review PR |
| → `verified` / `needs-fix` | `idd-verify` | 現況 = verify verdict 一句話；你該做什麼 = merge（verified）/ 等修（needs-fix） |
| → `closed` | `idd-close` | 現況 = 結案一句話（root cause + solution）；你該做什麼 = 無 |

## 更新機制

1. **首發**（issue 尚無 marker comment）：經 `gh-egress.sh comment` 發（走 mention / privacy net）
2. **更新**：以 marker 定位既有 comment → `gh api PATCH /repos/:repo/issues/comments/:id` 整則替換（bounded-section-replace 語意 — dashboard 是快照不是 append log，舊快照不保留；歷史由 phase comments 本身承載）
3. 找不到 marker comment 且 phase ≥ diagnosed → 視為首發補建（self-healing）

## Scope 邊界

- **不 pin**（GitHub API 不支援 comment pin）；可發現性靠 body 頂部 link + marker
- **不推播**（無 @-mention 於 dashboard 內文 — 要 tag 人走 tagging-collaborators 協定，且只在行動呼籲真的指名時）
- 聚合視圖（跨 issue 的 rollup）屬 `idd-report --rollup`（#134），本檔只管單 issue 快照
