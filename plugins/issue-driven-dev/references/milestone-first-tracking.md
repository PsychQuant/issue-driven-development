# Milestone-first cross-cluster tracking (#83)

**用 GitHub 原生的 milestone 追蹤跨 cluster 的工作，不要用 Epic issue。**

## 由來

2026-05-12 的 dogfood session（`PsychQuantHsu/psychophysical_representations`），使用者一句話切開了一個卡住的 pattern：

> 「還是你可以創 milestone 來追蹤」

當時的處境是：有一組互相關聯的 issue 要一起追，直覺做法是開一張 Epic issue 當母票。但 Epic 跑 IDD lifecycle **不合適** —— 它沒有可診斷的 root cause、沒有可實作的 scope、沒有可驗證的完成條件，於是每一個 IDD phase 套在它身上都是空轉。

## 為什麼 Epic issue 是 anti-pattern

IDD 的每個 artifact 都預設它的 issue 有一個**單一可交付物**：

| Phase | 對 Epic 的意義 |
|---|---|
| `diagnose` | 沒有單一 root cause 可查 —— 診斷會退化成「列出子票」 |
| `implement` | 沒有東西可實作，scope guard 無從判斷越界 |
| `verify` | 沒有 diff 可驗；6-AI ensemble 對它是 dead weight |
| `close` | closing summary 的五段式（Problem / Root Cause / Solution / Verification / Changes）全部填不出實質內容 |

結果是 Epic 卡在 `diagnosed` 或被迫寫一份空洞的 lifecycle 紀錄，而它真正的功能（「這幾張要一起完成」）根本不需要 lifecycle。

## SOP

1. **建 milestone，不建 Epic issue。** 標題就是那組工作的名字，description 寫「完成條件」（不是子票清單 —— 清單由 GitHub 自動維護）。
2. **子票照常各自跑完整 IDD lifecycle。** 它們是真的 issue，有 root cause、有 diff、有 verify。
3. **`gh issue edit <N> --milestone "<name>"`** 把子票掛上去。新建時用 `gh issue create --milestone`。
4. **進度用 GitHub 自己的計數**（`gh api repos/{o}/{r}/milestones` 的 `open_issues` / `closed_issues`），不要人工維護一份會過期的 checklist。
5. **milestone 關閉 = 那組工作完成**，不需要也不應該有一份「Epic 的 closing summary」—— 每張子票已經各自留了自己的。

## 什麼時候仍該用 issue 而非 milestone

- **cluster PR**：多張 issue 共用一個 PR 時走 `idd-implement #A #B #C --pr`，那是 PR 層的分組，與 milestone 正交（兩者可以並用）。
- **north-star / tracker**：需要敘述性脈絡（為什麼這條線存在、目前的假設是什麼）而不只是計數時，`tracking` phase 的 issue 仍是對的工具（v2.82.0+ #179）。milestone 只有標題與描述，承載不了論述。

判準：**要計數就用 milestone，要論述就用 tracker issue。** 兩者都不該跑 implement / verify。
