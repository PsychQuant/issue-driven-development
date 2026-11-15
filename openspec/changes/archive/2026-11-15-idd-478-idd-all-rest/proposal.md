## Why

維護者要一個指令，把 repo 裡剩下的 open issue 一次跑完整條 IDD 流程並結案，只在必須由人決定的地方停下（#478）。現在 `/idd-all` 不帶參數只會問一個二選一的問題，要批次處理就得自己列出每一個 issue 號；2026-11-15 這個 repo 有 192 張 open issue，沒有任何程式能回答「剩下哪些、各屬哪一類、下一張是誰」。

## What Changes

- **BREAKING** `/idd-all` 沒有位置參數時不再提問，改為跑剩下的全部（rest）；唯一的位置參數是 `rest` 時同義。`rest` 加上其他位置參數、或 `--in-chain` 而沒有 issue 號，會被拒絕並印出用法。其餘輸入的行為不變。
- 新增清單程式 rest-queue：一次分頁的 GraphQL 讀取取回所有 open issue，依一張有順序的判定表把每一張放進恰好一類（作者沒有寫入權、tracker、有未回答的釐清問題、parked、blocked、meeting、已經 verified、候選），並輸出候選的順序。讀取失敗或不完整時整個失敗，不輸出部分清單。
- rest-queue 同時記錄一次 run 的狀態：每張 issue 在一次 run 裡只試一次；每跑完一張就重讀清單，途中新開的 issue 會被接住；24 小時內沒有結束的 run 會被接續而不是重置。
- 一張 issue 停下或 abort 不會停下整個 run。整個 run 只在四種情況停下：回不到預設 branch、rest-queue 失敗、gh 認證失效、使用者中斷。
- run 開始前印出清單（每一類有哪些、候選的順序），結束時印一份總報告：結案的、停下的與原因、等人回答的問題、沒跑的與類別。
- intent 模組新增回傳所有未回答釐清問題的函式；close stage 原本用的單筆函式改成取其中第一筆，行為不變。
- idd-all skill 加上參數判定與 rest 的流程；批次與平行的兩份 reference、README、MANIFESTO 同步改寫。

## Capabilities

### New Capabilities

- `idd-all-rest`: `/idd-all` 不帶 issue 時的挑選、順序、每張只試一次、整個 run 的停止條件與總報告。

### Modified Capabilities

(none)

## Impact

- Affected specs: `idd-all-rest`（新增）。既有 capability 的 requirement 不變；`parallel-orchestration` 的批次模式那一條被引用，不被修改。
- Affected code:
  - New:
    - plugins/issue-driven-dev/scripts/rest-queue.py
    - plugins/issue-driven-dev/scripts/tests/rest-queue/test.sh
    - plugins/issue-driven-dev/scripts/tests/rest-queue/fake-gh.py
  - Modified:
    - plugins/issue-driven-dev/scripts/lib/intent.py
    - plugins/issue-driven-dev/skills/idd-all/SKILL.md
    - plugins/issue-driven-dev/references/parallel-orchestration.md
    - plugins/issue-driven-dev/references/batch-and-cluster.md
    - plugins/issue-driven-dev/README.md
    - plugins/issue-driven-dev/MANIFESTO.md
    - plugins/issue-driven-dev/CHANGELOG.md
  - Removed: (none)
