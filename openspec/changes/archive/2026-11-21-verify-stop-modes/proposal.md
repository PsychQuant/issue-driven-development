**GitHub-side tracker**: #595

## Why

`/idd-all` 的 verify 什麼時候停只有一條寫死的規則：無人值守最多 2 輪（中間修一次）、attended 1 輪就交回使用者，而且只有 verify 判定乾淨才自動合併。還在收斂的 issue 因此被提早停下，要人回來接手；不收斂的 issue 則只能靠維護者每一批在對話裡另訂規則（#595）。這條上限也只寫在 SKILL.md，沒有程式把關，compaction 之後會被超過（#591）。

## What Changes

- 新增可設定的停止模式：repo config 的 `verify_stop.mode` 設預設，`/idd-all --stop <mode>` 覆蓋這一次。三種模式：
  - `early`：依收斂數停。每一輪「要修的列」（Blocking 加上非 LOW／INFO／P3 的 In-scope fix）沒有比上一輪少就停。
  - `exhaustive-blocking`：修到 Blocking 為 0；Blocking 連續兩輪沒有下降時停。
  - `exhaustive-all`：修到 Blocking 與 In-scope fix（含 LOW）都是 0，沒有輪數上限。
- 沒有設定時，行為與現在逐字相同（無人值守 2 輪、attended 1 輪、乾淨才合併）。
- run-state 記錄每一輪 verify 的計數（輪次、`blocking`、`in_scope`、`low_in_scope`、審過的 commit），由 `close-stage.py gate` 在每一輪寫入。這同時做到 #591 要的程式把關：要不要再跑一輪由 `close-stage.py next` 依模式與這份紀錄回答，不靠 model 記得上限。
- 合併條件依模式：`early` 與 `exhaustive-blocking` 停在 Blocking 為 0 時，合併最後一輪審過的 commit，沒修的列合成一張 follow-up issue；`exhaustive-all` 只在兩種列都歸零時合併。**BREAKING**（只對設了模式的 run）：verify 不乾淨的 commit 也可能自動合併。
- 設了模式的 attended run 也自動修、自動再驗；只有安全漏洞這類不自動修的 finding 才停下交回。沒設模式的 attended run 不變。
- 設了模式的 run，run-state 的 24 小時期限從最後一輪 verify 算起，而不是從 run 開始（#576 的一部分）。
- Phase 6 的回報寫明停止的原因：模式、輪數、每一輪要修的列數。

## Non-Goals (optional)

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `idd-pr-hitl-modes`：新增「停止模式決定修正迴圈何時停、停下後是否合併」；修改「Clean verify leads to merge and close」（依模式的合併條件、run-state 期限從最後一輪算起）與「Unattended fix loop covers in-scope findings with a two-round limit」（兩輪上限與 attended 不自動修只在沒有設定模式時成立）。

## Impact

- Affected specs: `idd-pr-hitl-modes`
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/close-stage.py, plugins/issue-driven-dev/skills/idd-all/SKILL.md, plugins/issue-driven-dev/references/config-protocol.md, plugins/issue-driven-dev/scripts/tests/close-stage/scenarios.sh
  - New: test fixtures under plugins/issue-driven-dev/scripts/tests/close-stage/fixtures/ for the round record, `close-stage.py next` and the merge conditions
  - Removed: none
- 相關 issue：#595（本 change）、#591（輪數由程式把關，本 change 一併做到）、#576（期限只改設了模式的 run）、#596（不重報已定的點，讓收斂數更可信；不在本 change）。
