**GitHub-side tracker**: #595

## Why

`/idd-verify #595` 第 1 輪找到七處：停止模式的合併在 close stage 自己不擋還沒修的嚴重 In-scope fix；一輪若沒有新 commit 也沒有新報告，`next` 會一直重複上一輪的 fix，early 的「一定會停」與兩輪上限都失效；round 紀錄是空的時，close stage 會合併 Phase 4 沒判過的報告；本輪 gate 寫紀錄失敗時沿用上一輪的答案；config 的 `"early\n"` 被當成 `early`；沒有 run-state 時，沒有模式的 run 少修一輪；`exhaustive-all` 對 `--review`／`--in-chain` 只看 Blocking，規格沒有寫。

## What Changes

- `verify-gate.py` 回報還沒修的 CRITICAL／HIGH／P0／P1 In-scope fix 列數（`high_in_scope`）；停止模式的合併要求它是 0，由 close stage 自己擋。
- `next` 回答過 fix 的結果記在 run-state；同一個 commit 上的同一份報告（或同樣沒有報告）再被問到時，回 stop、不合併。適用於有模式與沒有模式的 run。
- 沒有模式的合併：最新報告必須在 round 紀錄裡，空紀錄也一樣。
- idd-all Step 0.2 在 `jq` 裡比對三個值；空字串、不是三個值之一的字串都印警告。
- 沒有 run-state 時，沒有模式的 run 照以前自己數輪數。
- 規格寫明 `--review`／`--in-chain` 在 `exhaustive-all` 只看 Blocking。

## Non-Goals

- 不辨識報告裡哪一列是安全漏洞：close stage 以 Severity 擋（CRITICAL／HIGH／P0／P1 的 In-scope fix），安全漏洞照 verify 的分級通常落在這裡；Phase 4 對安全漏洞照舊 abort。
- 不改 zsh 下 Step 0.2 讀不到最後一個參數的問題（#598）。

## Capabilities

### New Capabilities

（無）

### Modified Capabilities

- `idd-pr-hitl-modes`：修改「A configured stop mode decides when the fix loop stops and whether the run merges」與「Unattended fix loop covers in-scope findings with a two-round limit」。

## Impact

- Affected specs: `idd-pr-hitl-modes`
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/close-stage.py, plugins/issue-driven-dev/scripts/lib/stopmode.py, plugins/issue-driven-dev/scripts/verify-gate.py, plugins/issue-driven-dev/skills/idd-all/SKILL.md, plugins/issue-driven-dev/scripts/tests/close-stage/scenarios.sh
  - New: none
  - Removed: none
