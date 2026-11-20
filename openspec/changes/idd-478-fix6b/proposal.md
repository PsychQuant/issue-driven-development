## Problem

修正輪 6（change `idd-478-fix6`）為了讓另外兩份規格指向 `idd-all-rest`，各改了一句：capability `idd-all-chain` 的「idd-all-chain skill SHALL drive root issue plus auto-emergent spawn through one cluster branch and one PR」與 capability `idd-pr-hitl-modes` 的「Mode resolution from pr_policy and flags」。`scripts/spec-change.py links` 對這個 branch 回報這兩條各缺一個檢查：前者的 Example「DFS vs BFS queue order with a single spawn」沒有任何測試帶它的標記；後者沒有 Example。

## Root Cause

這兩條 requirement 早於「每個 Example 都要有檢查」的規則（#480），之前沒有被任何 branch 動到，所以一直沒有補。

## Proposed Solution

- `idd-all-chain`：加一個測試，從 `skills/idd-all-chain/SKILL.md` 取出佇列的 pop 與 push 那幾行原文，用 Example 表裡的數值執行（佇列 `[44, 45, 50]`，取出 #44 後加入一個 spawn），比對 DFS 與 BFS 兩列的結果。規格不改。
- `idd-pr-hitl-modes`：在那條 requirement 加一個 Example（rest 模式下 `pr_policy: ask` 只問一次、只提供 PR path），測試讀 `skills/idd-all/SKILL.md` 的對應兩處。這是 skill 的散文、由模型執行，測試檢查的是 skill 有沒有這樣寫。

## Non-Goals

- 不改這兩條 requirement 的其他內容，也不替它們其餘的 Scenario 補測試。

## Success Criteria

- `scripts/spec-change.py links --base <merge base>` 對這個 branch 回報 `ok`。
- `scripts/tests/rest-queue/test.sh` 全部通過。

## Impact

- Affected specs: `idd-pr-hitl-modes`（修改 1 條 requirement：加一個 Example）
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/tests/rest-queue/test.sh
