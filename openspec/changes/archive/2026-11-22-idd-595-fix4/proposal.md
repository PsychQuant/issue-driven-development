**GitHub-side tracker**: #595

## Why

`/idd-verify #595` 第 2 到第 4 輪修正時加了幾個行為，程式與測試都有，規格還沒寫：Phase 5 以唯讀方式讀 gate 與 `next`、gate 不把讀給被取代的 run 的結果寫進新 run、停止模式的合併要求重讀報告的計數與紀錄一致、紀錄的 attempt 比 round 少時不合併、`--stop` 重複或後面接著別的旗標時中止。

## What Changes

- 規格寫明上面五個行為；程式不改（已在 `132238f`..HEAD 實作並有測試）。

## Non-Goals

- 不改行為、不加新功能。

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `idd-pr-hitl-modes`：修改「A configured stop mode decides when the fix loop stops and whether the run merges」與「Unattended fix loop covers in-scope findings with a two-round limit」。

## Impact

- Affected specs: `idd-pr-hitl-modes`
- Affected code:
  - Modified: none
  - New: none
  - Removed: none
