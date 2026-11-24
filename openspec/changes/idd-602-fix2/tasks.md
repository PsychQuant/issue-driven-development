## 1. 實作

- [ ] 1.1 requirement「A configured stop mode decides when the fix loop stops and whether the run merges」：測試先寫（ledger、刪除即 replaced、reset 等鎖再刪、reset 與 init 的鎖），再改 `close-stage.py`。驗證：新測試改程式前失敗，改後 close-stage 套件全過。
- [ ] 1.2 [after: 1.1] requirement「Unattended fix loop covers in-scope findings with a two-round limit」：`idd-all-phase4-count` 的新情境，再改 SKILL.md Phase 4。驗證：對第 1 輪修正版的 SKILL 5 個斷言失敗，新的全過。

## 2. 回歸

- [ ] 2.1 [after: 1.1, 1.2] `run-all-tests.sh` 全過。
