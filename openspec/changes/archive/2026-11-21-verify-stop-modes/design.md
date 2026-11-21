## Context

`/idd-all` 的 Phase 4（`plugins/issue-driven-dev/skills/idd-all/SKILL.md`）用 `MAX_ROUND = 2 if INTERACTION == "unattended" else 1` 決定 verify 跑幾輪；attended 不自動修。會不會合併由 `plugins/issue-driven-dev/scripts/close-stage.py` 決定：`gate` 子指令把最新的 verify 報告交給 `verify-gate.py`，回傳 `status`、`blocking`、`in_scope`、`low_in_scope` 等計數；`run` 子指令經 `gate_stop()` 只放行 `clean`。run-state（`.claude/.idd/state/idd-all-run-<N>.json`）由 `cmd_init` 寫入，只有 path、interaction、branch、`--review`、`--in-chain` 等旗標與建立時間，沒有輪數；`load_state()` 拒絕超過 `STATE_TTL`（24 小時）的紀錄。

維護者 2026-11-21 在 #595 決定：停止條件做成三種可選模式，early stop 依收斂數、窮盡到沒有 Blocking、完全窮盡沒有上限；合併條件依模式；attended 也照設定。spectra-discuss 的五點建議都照原樣採用。

## Goals / Non-Goals

**Goals:**

- 三種停止模式，由 config 或 flag 選；沒有設定時行為逐字不變。
- 要不要再跑一輪、停下時要不要合併，由 `close-stage.py` 依 run-state 的紀錄判斷，不靠 model 記得。
- 沒有設定模式的 run，兩輪上限也由程式把關（#591）。
- 回報寫明停止的原因。

**Non-Goals:**

- 不改 verify 本身怎麼審（reviewer、席位、報告格式）。不重報已定的點是 #596。
- 不改 `/idd-all-chain` 的 cluster 流程；`--in-chain` 的 run 照舊不合併。
- 不處理沒有設定模式的 run 的 24 小時期限（#576 的其餘部分）。
- 不加時間或額度上限。

## Decisions

### 收斂數數的是要修的列

to-fix count = `blocking + in_scope - low_in_scope`，也就是這個迴圈本來就會去修的列。Follow-up 另開 issue、Rejected 直接停，都不在迴圈裡，所以不算。`--review`、`--in-chain` 的 run 只修 Blocking，to-fix count 就是 `blocking`。

替代方案：數全部的列（含 Follow-up），會把不在迴圈裡處理的列當成沒有收斂；依嚴重度加權，需要另外定權重，而 gate 只有三個計數。

### early stop 以嚴格下降判斷收斂

從第 2 輪起，to-fix count 沒有比上一輪少就停。列數是非負整數，嚴格下降的序列最多 `第一輪的數 + 1` 項，所以一定會停；這就是維護者要的「early stop 一定會停」。

替代方案：連續 k 輪不下降才停。k 是另一個要調的參數，而且失去「一定會停」的簡單上界。

### exhaustive-blocking 用連續兩輪不下降當保底

Blocking 為 0 就停；Blocking 連續兩輪沒有比前一輪少也停。給修正一次機會：修一個 Blocking 有時會暴露另一個。沒有保底的話，這一種和 exhaustive-all 一樣可能停不下來，差別只剩目標。

### exhaustive-all 沒有輪數上限

照維護者的決定。仍然會停的情況只有三種：歸零、遇到不自動修的 finding（安全漏洞）、使用者中斷。gate 讀不出報告或有 Rejected finding 時照舊停。

### 每輪的計數由 gate 寫進 run-state

`close-stage.py gate` 讀到一份這次 run 還沒讀過的報告時，在 run-state 的 `rounds` 陣列加一筆：`round`、`sha`、`blocking`、`in_scope`、`low_in_scope`、`at`（寫入時間）。用報告的 comment id 判斷是不是讀過，同一份報告重讀不加一輪。

另外每判一個新的 commit、或同一個 commit 上讀到新的報告，gate 在 `attempts` 加一筆（`sha`、`report_id`、`at`）；同一個 commit 重讀同一份報告不加。只看 commit 的話，修正沒有產生 commit 時輪數不會增加，迴圈沒有終點（修正輪複查指出）。沒有模式的 run 以 `attempts` 計輪數：報告沒貼出或讀不出的那一輪也算，和 #595 之前「迴圈跑了幾次」相同（spectra-verify W1 與 spectra-review #2 指出只數報告會讓這種輪次漏算、多跑一輪）。寫紀錄失敗時 gate 回 `unparseable`（exit 2），不讓一輪沒記到的結果被當成判過的一輪。寫在 gate 裡，因為每一輪本來就一定會呼叫 gate；另外加一個「記一輪」的指令，model 忘了呼叫就會少記。

### 要不要再跑一輪由 close-stage.py next 判斷

新子指令 `close-stage.py next --cwd --repo --issue`，讀 run-state 的模式與 `rounds`，印一行 JSON：`{"decision": "fix" | "stop", "merge": true | false, "reason": "...", "mode": "...", "rounds": [...]}`。Phase 4 的迴圈照 `decision` 走。判斷由 close-stage.py 提供，因為它已經擁有 run-state 與 gate；判定表本身是一個不讀 GitHub 的純函式，放在 `scripts/lib/stopmode.py`（close-stage.py 已超過 800 行，照 repo 的檔案大小慣例拆出；它和 `lib/workflows.py`、`lib/intent.py` 一樣只被 close-stage.py 使用）。

`next` 也處理沒有設定模式的 run：無人值守在第 2 輪後回 stop、attended 在第 1 輪後回 stop，與現在的 `MAX_ROUND` 相同。這樣 Phase 4 只有一條路，`MAX_ROUND` 只剩「沒有設定模式」那一列。

### 停止模式的合併也要求覆蓋率行與 reviewers 行完整

verify-gate.py 原本只在 PASS 時檢查覆蓋率行（`X / X requirements addressed`）與 reviewers 行；FAIL 的報告在那之前就回 `not_clean`。停止模式會合併 FAIL 的一輪，所以 verify-gate 對每種判定都輸出 `coverage_complete` 與 `reviewers_complete`，close-stage.py 的停止模式合併要求兩者都是 `true`（spectra-verify C1、spectra-review #1）。乾淨的合併照舊由 verify-gate 自己擋。

### 停下時合併的是最後一輪審過的 commit

`next` 回 `merge: true` 時，`close-stage.py run` 放行那個結果，但仍要求 HEAD 就是最後一輪審過的 commit（gate 本來就以 `--sha` 綁定）。剩下的列合成一張 follow-up issue，做法與現在的 `low_in_scope` 相同。停下之後不再加修正，否則那些修正沒有人審過。

### 設了模式的 attended run 也自動修

照維護者的決定。attended 的差別只剩 sub-skill 照常可以問問題；不自動修的 finding（安全漏洞）停下交回。沒設模式的 attended run 不變。

### 設了模式的 run，期限從最後一輪算

`load_state()` 對有 `verify_stop` 模式的紀錄，以 `rounds` 最後一筆的 `at` 計算年齡；沒有 `rounds` 時用建立時間。沒有設定模式的 run 不變。

### config 值寫錯時當成沒有模式

`verify_stop.mode` 不是三個值之一時，當成沒有設定並印一行。沒有設定的行為比任何模式都保守（較少自動合併），所以寫錯不會放寬。`--stop` 是使用者這一次明確給的值，寫錯就在 Phase 1 之前停下，免得使用者以為照他說的模式在跑。

## Implementation Contract

**行為**

- `idd-all` 在模式解析時印出停止模式（或「沒有停止模式」），寫進 run-state 的 `verify_stop` 欄位（`null` 或三個值之一）。
- 每一輪 verify 之後，Phase 4 跑 gate，再跑 `close-stage.py next`，照它的 `decision` 修或停。停下時 Phase 6 的回報有一行：模式、輪數、每輪的 to-fix count、`next` 的 `reason`。
- `close-stage.py run` 合併的條件：沒有模式時與現在相同（`clean`，且沒有模式的無人值守 run 的 `rounds` 不超過 2 筆）；有模式時是 `next` 對最後一輪回 `merge: true`，其餘 guardrail 照舊。

**資料形狀**

- run-state 新欄位：`"verify_stop": null | "early" | "exhaustive-blocking" | "exhaustive-all"`、`"rounds": [{"round": 1, "sha": "<40 hex>", "status": "clean|not_clean|unparseable", "blocking": 0, "in_scope": 0, "low_in_scope": 0, "rejected": 0, "report_id": <int>, "at": "<ISO-8601>"}]`、`"last_gate": {"status", "report_id", "sha", "reason", "at"}`（每次 gate 都更新，`next` 用它判斷最新的結果是不是最新的那一輪）。
- `cmd_init` 多一個必填引數 `--stop <none|early|exhaustive-blocking|exhaustive-all>`，與其他引數一樣不接受預設值。
- config：`"verify_stop": {"mode": "early"}`，寫在 `references/config-protocol.md` 的新節。

**失敗模式**

- `next` 讀不到 run-state、或 `rounds` 是空的：回 `stop`、`merge: false`，`reason` 寫明，結束碼非 0。不會因為讀不到而回 `fix`。
- gate 結果是 `unparseable`：找到了報告（被編輯過、被隱藏、沒有 HTML、verify-gate 沒有輸出 JSON）時仍記一筆，計數為 `null`；找不到報告時不記一輪，但 `last_gate` 記下這次的結果。兩種情況 `next` 都回 `stop`、`merge: false`。

**驗收**

- `plugins/issue-driven-dev/scripts/tests/close-stage/scenarios.sh` 對 spec 裡每一個 Scenario 有一個情境，用假的 run-state 與 gate 結果驗 `next` 的輸出與 `run` 是否放行。
- 沒有設定模式時，現有 close-stage 測試全部通過、輸出不變。
- `idd-all` 的 SKILL.md Phase 4 只剩一條由 `next` 驅動的迴圈；`MAX_ROUND` 這個名字不再出現。

**範圍**

- 在範圍內：close-stage.py 的 `init`、`gate`、`next`、`run`、`load_state`；idd-all SKILL.md 的 Step 0.2、Step 0.7、Phase 4、Phase 5c 的表、Phase 6；config-protocol.md 的新欄位；close-stage 測試。
- 不在範圍內：idd-verify、verify-gate.py 的判定、idd-all-chain、沒有模式的 run 的期限。

## Risks / Trade-offs

- [設了模式的 run 會自動合併 verify 不乾淨的 commit] → 只合併最後一輪審過的 commit；剩下的列一定開成 follow-up issue；模式要明確設定才生效，預設不變。
- [exhaustive-all 沒有上限，成本與時間沒有界線] → 回報每輪的數字，讓使用者看得出是否在空轉；使用者隨時可中斷。這是維護者接受的取捨。
- [重報的列讓收斂數看起來沒下降，early 提早停] → #596 解決重報；在那之前，early 的行為偏保守（提早停），不會偏向多合併。
- [自動修正越多輪，越容易為了消掉某一列改壞別處] → 每一輪仍經完整 verify；合併前的 guardrail 照舊。
- [一份報告被編輯後重讀] → 以 comment id 判斷讀過與否，編輯過的報告不算新的一輪；gate 本來就不讀發出後才編輯的判定。
