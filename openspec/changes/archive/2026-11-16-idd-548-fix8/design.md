## Context

第 50 列是第四個 change（`idd-548-links-unreadable-objects`）加的。它要守住的是 requirement 的這一句：搜尋 submodule 之前，先問 git 記錄的 commit 有哪些物件缺少或打不開；物件檔存在但打不開（例如空檔）算缺少。當時用的 git（2.55.0）在空的物件檔上會跳過那個檔案、讓 `git grep` 以 0 或 1 結束，所以只有「先問」那一步看得出檔案沒被讀到。fixture 把這個前提寫成檢查，前提不成立就停下整個測試檔。

git 2.56 起，同一個輸入讓 `git grep` 以 128 結束。第 49 列描述的正是「搜尋以 128 結束」的情形，答案相同（`error`，its recorded commit could not be read）。

## Goals / Non-Goals

Goals:

- 測試檔在 git 2.54.0、2.55.0、2.56.0 上都跑完，檢查項數相同。
- Example 第 50 列的第一欄對這三個版本都是真的。

Non-Goals:

- 不動 `spec-change.py`。
- 不動 requirement 的條文與其他各列。
- 不新增一列。

## Decisions

### 第 50 列的 fixture 記下結束碼，不停下

`git grep` 的結束碼存進變數。大於 1 時印一行，格式照測試檔其他說明行（開頭兩個空白與 `~`）：

`  ~ note: this git ends the search of an empty object with exit code <N>, row 50 takes the path of row 49`

之後的 `links_case` 與原因文字的檢查照樣執行。不在結束碼大於 1 時略過這一列：答案在兩種情形下相同，略過會讓 git 2.56 起的版本少一組檢查，各版本的項數也會不同。

「git 把那個物件列為存在」的前提檢查（`rev-list --objects --missing=print` 不把它印成缺少）保留，不成立時仍然停下：那是這一列與「物件不在」各列的差別，三個版本都成立。

### Example 第一欄寫兩種情形，不寫版本號

第一欄現在的後半句是「so the search skips the file and ends with exit code 0 or 1」。改成：

「depending on its version, git either skips the file and ends the search with exit code 0 or 1, or ends the search with exit code 128」

不寫「2.56 之前／之後」：量到的只有四個版本，其中一個（CI 的 2.56.1）只知道結束碼大於 1。版本與結束碼的對照記在 proposal 與測試檔的註解，那裡寫的是量到的版本。

### 測試檔的註解寫量到的版本

第 50 列上方的註解改成：git 2.54.0 與 2.55.0 跳過那個檔案、以 0 或 1 結束，只有打開物件才看得出檔案沒被讀到；git 2.56.0 讓搜尋自己以 128 結束，這一列就走第 49 列的路。兩種情形答案相同，都檢查。

## Implementation Contract

- `plugins/issue-driven-dev/scripts/tests/spec-change/test.sh`：只動第 50 列。註解兩行換成上面的說法；`[ "$?" -le 1 ] || setup_failed …` 那一行換成「記下結束碼，大於 1 時印說明行」。其他各列與 helper 不動。
- `openspec/specs/spec-on-every-issue/spec.md`（由封存套用）：requirement「Added and modified requirements carry an executable check」的 Example「markers in submodules」第 50 列第一欄換掉後半句。這條 requirement 的其他文字、這一列的第二、三欄、其他各列都不變。
- `plugins/issue-driven-dev/scripts/spec-change.py`：不動；`git diff` 對這個檔案沒有輸出。
- 驗證：測試檔在 git 2.54.0、2.55.0、2.56.0 上都是 878 項通過、0 項失敗；改之前的測試檔在 git 2.56.0 上停在第 50 列；`run-all-tests.sh` 結束碼 0；`links --base origin/main` 回 `ok`；`archived` 回 pass。

## Risks / Trade-offs

- git 2.56 起，空的物件檔讓搜尋自己失敗。「搜尋前先問 git 哪些物件打不開」那一步，在這些版本上沒有只有它才抓得到的測試輸入：把那一步拿掉的變異，在 git 2.55 以下會讓第 50 列失敗，在 2.56 上不會。那一步仍然留著，requirement 也仍然要求它；CI 用的是新版 git，所以 CI 守不住它，要靠在舊版 git 上跑測試。有沒有別的輸入能在新版 git 上分辨，沒有查過。
- 第 50 列以後的檢查還沒有在 Linux 上執行過。這個 change 推上去之後 CI 才會跑到；那裡再有失敗，不在這個 change 的範圍內處理，先回報。
- 這個 change 沒有獨立讀者，也不開 verify 輪（維護者的決定）。它不改程式；證據是三個 git 版本上的測試結果與推上去之後的 CI。

## Migration Plan

沒有。測試檔與 Example 的一列，使用者的 repository 不受影響。

## Open Questions

沒有。
