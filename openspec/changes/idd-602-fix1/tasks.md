## 1. 實作

- [ ] 1.1 requirement「A configured stop mode decides when the fix loop stops and whether the run merges」：測試先寫（替換的標記、`reset` 拿鎖、init 與 `next` 拿鎖、等鎖、非法 `verify_stop`），再改 `close-stage.py`。驗證：新測試改程式前失敗，改後 close-stage 套件全過。
- [ ] 1.2 [after: 1.1] requirement「Unattended fix loop covers in-scope findings with a two-round limit」：新套件 `idd-all-phase4-count` 執行 Phase 4 標記內的兩段，再改 SKILL.md。驗證：對舊的兩段 5 個斷言失敗，新的全過。

## 2. 回歸

- [ ] 2.1 [after: 1.1, 1.2] `run-all-tests.sh` 全過。
