**GitHub-side tracker**: #548

## Problem

`idd-548-links-search-completeness` 修了第二輪 verify 的七列。第三輪 verify（issue 留言 6881182720）確認其中五列修好了，但那次修正本身引入了新的問題，協調者重現了其中四項：

1. submodule 裡一個檔案內容的物件「在、但打不開」時（物件檔長度是零，或沒有讀取權限），`links` 回 `missing`；第二輪的 script 回 `error`。那個檔案正好帶標記時，也被說成沒有標記。
2. submodule 記錄的 commit 裡有檔名含 CR 緊接問號時，完整的 submodule 被算成缺物件，`links` 多回一個 `error`。
3. submodule 的搜尋中途以 128 結束、而標記就在那個 submodule 裡時，同一個 repo 重複執行，有時回 `ok`、有時回 `error`。
4. requirement 說規格目錄底下任何不是合法 UTF-8 的路徑都回 `error`，程式只看 `specs/` 底下。
5. 主 repo 搜尋失敗的那一列寫「前 200 個字元」，沒有檢查分辨得出前 200 與後 200。
6. 另有六項 LOW 與 INFO：一句關於巢狀 submodule 的話比程式寬；測試檔沒有清掉繼承的 git 環境變數；測試檔沒有寫明需要 git 2.45；`commit` 的失敗檢查在命令替換裡只結束子 shell；頂層目錄的 requirement 少一個邊界的列；`references/spec-wrapper.md` 的提醒少說兩件事。

## Root Cause

- 第 1 項與第 3 項是同一個修正的兩個副作用。上一個 change 為了不把任何錯誤輸出都當成讀不到，改成完全不讀 submodule 搜尋的錯誤輸出、改問 `git rev-list --missing=print` 缺哪些物件，並且先讀搜尋印出的內容、沒找到才看結束碼。`rev-list` 只看物件存不存在；物件檔在而打不開時，`git grep` 只印一行 error、跳過那個檔案、結束碼仍是 0 或 1，所以沒有訊號留下來。`git grep` 中途中止之前印出了多少，取決於它的工作執行緒。
- 第 2 項：用 `splitlines()` 切 `rev-list` 的輸出，它在單獨的 CR 也會斷行。
- 第 4、5 項與巢狀 submodule 那一句：句子寫得比程式或測試寬。這與第二輪的第 1 列是同一類問題。
- 測試檔的三項：隔離了 git 的設定，沒有隔離 git 的環境變數；失敗時停下的檢查沒有考慮命令替換。

## Proposed Solution

維護者 2026-11-15 的決定（issue 留言 6885330621）：修完再審一輪；第 1 項用 `git cat-file --batch-check`；第 3 項改成搜尋中途中止時不採用它印出的內容。

- 新函式 `submodule_lacks_objects()`：`rev-list` 的輸出只在換行切開，缺物件的行比對成問號加物件 id；再把列出的物件 id 交給 `git cat-file --batch-check`（經過關掉 lazy fetch 的同一個包裝），回報 missing 的算成缺物件。
- submodule 的搜尋以 0、1 以外的結束碼結束時，不讀它印出的內容；這個 submodule 算搜尋不了。主 repo 不變。
- requirement 的四處文字改成與程式一致：非 UTF-8 路徑限定在 `specs/` 底下；巢狀 submodule 的清單來自「每一個 tree 的列表」；缺物件的定義加上打不開的物件；找到的檔案在搜尋跑完時才確定 Example。第 49 列改寫成它的 fixture 實際造出來的情況。
- Example「markers in submodules」加第 50 到 54 列；「what the link check reports」加一列；「top directory names」加三列（名稱以換行結尾）。
- 主 repo 那一列的檢查改用一個回報已知 300 個字元訊息的 git，逐字比對前 200 個字元。行為不變；要不要改留結尾，留在 #558 決定。
- 測試檔：開頭確認 git 版本、清掉繼承的 git 環境變數；`setup_failed` 在命令替換裡也讓整個測試停下。
- 文件：`references/spec-wrapper.md` 的提醒補上兩件事；CHANGELOG 的 #548 條目與 `spec-change.py` 檔頭改成最後的行為。

## Non-Goals

- 不改主 repo 這一層的行為（#556、#558）：讀不到的檔案內容回什麼、原因文字留哪一端、lazy fetch、時間上限，都不在這次。
- 不處理名稱不是合法 UTF-8 的頂層目錄：這台機器的檔案系統不接受這種名稱，寫了測試也跑不到，所以不新增列，只在實作摘要裡說明這個輸入的答案也變了。
- 不重寫封存的檔案：上一個 change 的 design 與 tasks 不改，更正寫在這個 change 與 issue 的留言。

## Success Criteria

- 第三輪第 1、2、3 列的重現在新 script 上回 `error`、`missing`、每次都 `error`；新測試在上一輪的 script 上，第 50、51、52 列各有檢查失敗。
- `bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 全部通過；`726050b`、`7ad9152`、`afd0021`、`6ed8dec` 的測試檔配新 script 也全部通過。
- 沒有 gitlink 的 repo 與標記都在主 repo 的 repo，新 script 與 `6ed8dec` 的 script 輸出逐位元組相同。
- 變異測試：這次改的每一處各有一種變異，都有檢查失敗；逐項結果寫進 tasks 的驗收紀錄。
- 整套測試通過。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `spec-on-every-issue`: requirement「Added and modified requirements carry an executable check」改寫非 UTF-8 路徑、巢狀 submodule、缺物件與搜尋中止的四處，Example 加列；requirement「The repository's top directory is read as git prints it」加上名稱以換行結尾的情況。

## Impact

- Affected specs: spec-on-every-issue（兩個 MODIFIED requirement）
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/spec-change.py
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-change/test.sh
  - Modified: plugins/issue-driven-dev/references/spec-wrapper.md
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
