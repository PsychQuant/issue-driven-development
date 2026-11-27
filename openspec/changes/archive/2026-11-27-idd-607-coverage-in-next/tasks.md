## 1. 實作

- [x] 1.1 requirement「A configured stop mode decides when the fix loop stops and whether the run merges」：Example「an incomplete coverage line counts as one Blocking finding」與「an incomplete reviewers line stops without a merge」的測試先寫（`scripts/tests/close-stage/scenarios.sh`，帶 `spec-example: idd-pr-hitl-modes / <標題>`），再改 `close-stage.py` 的 round 紀錄與 `stopmode.py` 的 `decide()`。驗證：新檢查在舊程式上失敗，close-stage 套件全過。

## 2. 回歸

- [x] 2.1 [after: 1.1] 整套測試通過（`bash plugins/issue-driven-dev/scripts/run-all-tests.sh`）。
