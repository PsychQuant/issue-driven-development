## 1. 兩條 requirement 的檢查

- [x] 1.1 `scripts/tests/rest-queue/test.sh`：capability `idd-all-chain` 的 Example `DFS vs BFS queue order with a single spawn`（requirement「idd-all-chain skill SHALL drive root issue plus auto-emergent spawn through one cluster branch and one PR」）——取出 chain skill 的 pop 與 push 原文，用 Example 的數值執行，比對兩列。完成時：把 skill 的 push-front 改成 push-back 會讓這個測試失敗。
- [x] 1.2 `scripts/tests/rest-queue/test.sh`：capability `idd-pr-hitl-modes` 的 Example `the skill asks once in rest mode and offers only the PR path`（requirement「Mode resolution from pr_policy and flags」）。完成時：`scripts/spec-change.py links` 對這個 branch 回報 `ok`。
