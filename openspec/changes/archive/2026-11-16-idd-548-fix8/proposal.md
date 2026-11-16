**GitHub-side tracker**: #548

## Problem

draft PR #572 的第一次 CI（ubuntu-26.04、git 2.56.1）裡，`spec-change` 這個 suite 停在 Example「markers in submodules」第 50 列的 fixture（留言 6909882017）：

`FATAL: spec-change suite: fixture setup failed: the search of a submodule with an empty object must end with 0 or 1`

停下之後的檢查都沒有執行。PR 因此是紅燈，第 50 列以後的檢查也從來沒有在 Linux 上跑到。

## Root Cause

第 50 列描述的輸入是：標記所在檔案的物件檔存在，但長度為零。fixture 在執行 `links` 之前先確認兩件事：git 把那個物件列為存在；`git grep` 以 0 或 1 結束（它跳過讀不到的檔案）。第二件事取決於 git 的版本。同一個輸入實跑的結果：

| git | `git grep` 的結束碼 | git 印的訊息 |
|---|---|---|
| 2.54.0（macOS 內附） | 1 | `error: … unable to read …` |
| 2.55.0 | 1 | `error: … unable to read …` |
| 2.56.0 | 128 | `fatal: loose object … is corrupt` |
| 2.56.1（CI） | 大於 1：fixture 的前提檢查失敗，結束碼沒有印出來 | 沒有紀錄 |

壞掉的是 fixture 的前提檢查，以及 requirement 的 Example 那一列第一欄的一句：「so the search skips the file and ends with exit code 0 or 1」。`links` 的答案沒有錯：在 macOS 上用 git 2.56.0，在一份副本裡拿掉那一行前提檢查之後，測試檔 878 項通過，第 50 列的答案仍是 `error`（its recorded commit could not be read）。

維護者的決定（留言 6910032608）：修測試，不再審。

## Proposed Solution

- 測試檔第 50 列：前提檢查改成記下 `git grep` 的結束碼。結束碼是 0 或 1 時與現在相同；大於 1 時印一行說明（這個 git 讓搜尋自己失敗，這一列走的是第 49 列的路），不停下。答案的檢查（`status`、列出的項數、結束碼、原因文字）兩種情形都執行。「git 把那個物件列為存在」的前提檢查不動。
- Requirement 的 Example 第 50 列第一欄：那一句改成兩種情形並列，不寫版本號。第三欄不變。
- `spec-change.py` 不動。

## Non-Goals

- 不改 `links` 的任何行為，不改 requirement 的條文；只動 Example 的一列。
- 不處理第八輪的後續項（留在 #559）。
- 不處理 `edit-run` 的不穩定檢查（#534）。
- 不為 git 2.56 起的版本另找一個「搜尋不失敗、但物件打不開」的輸入。有沒有這種輸入沒有查過；後果記在 design 的 Risks。

## Success Criteria

- `bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 在 git 2.54.0、2.55.0、2.56.0 三個版本上都是 878 項通過、0 項失敗。前兩個版本不印那一行說明，2.56.0 印。
- 改之前的測試檔在 git 2.56.0 上停在第 50 列（559 項通過之後 FATAL）；改之後不停。
- `bash plugins/issue-driven-dev/scripts/run-all-tests.sh` 結束碼 0。
- `spec-change.py links` 從預設分支到這條分支的 HEAD 回 `ok`；`archived` 回 pass。
- PR #572 的 CI 裡 `spec-change` 通過。這一項要推上去之後才知道：第 50 列以後的檢查是第一次在 Linux 上執行。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `spec-on-every-issue`: Example「markers in submodules」第 50 列第一欄的敘述。

## Impact

- `plugins/issue-driven-dev/scripts/tests/spec-change/test.sh`：第 50 列的 fixture 與它的註解。
- `openspec/specs/spec-on-every-issue/spec.md`：Example 的一列，封存時套用。
