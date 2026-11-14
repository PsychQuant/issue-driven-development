**GitHub-side tracker**: #548

## Problem

`idd-548-links-submodule-markers` 讓 `scripts/spec-change.py links` 讀得到 submodule 裡的標記。這條分支的第一輪 verify 找到三類問題，其中兩項由協調者在臨時 repo 上重現：

- 送出 commit 的人可以讓 `links` 執行他指定的指令。submodule 記錄的 commit 裡再記一個 gitlink，而 submodule 的工作樹在那個路徑上放一組一般的已追蹤檔案（`HEAD`、`config`、`objects/`、`refs/`），形狀像一個 git 目錄。`links` 在那個目錄跑 `git rev-parse` 與 `git cat-file -e`，git 讀了裡面的 `config`，為了找不存在的 commit 發動 lazy fetch，執行 `config` 指定的 `core.sshCommand`。改動之前，`links` 只在主 repo 的頂層跑 git。
- 主 repo 已經找到標記的 Example，會被 submodule 裡的失敗蓋掉。找到之後仍然走完每一個 gitlink：路徑不是合法 UTF-8 的 gitlink 讓 script 以 Python 的 traceback 結束（沒有 JSON，結束碼 1，也就是 `missing` 的結束碼）；記錄的 commit 在、它的 tree 讀不到時回 `error`。改動之前這兩種情況都回 `ok`。
- devil's advocate 另外確認第一項的範圍更大：主 repo 已經找到標記、結果是 `ok` 時，那個指令照樣執行。
- 邊界上的錯誤：gitlink 的路徑沒有檢查是否留在 repo 之內（含 `..`，或經過工作樹裡指向外面的 symbolic link），`links` 會到 repo 外面跑 git，原因文字還透露那個路徑上有沒有工作樹；路徑結尾是空白的 submodule 被判成沒取出；掛在規格目錄底下、沒取出的 submodule 讓找不到標記的 Example 變成 `error`，雖然它的檔案本來就不算；繼承到的 `GIT_DIR` 讓判定失準；`rev-parse` 的每一種失敗（含 git 因擁有者不同而拒絕開啟）都被報成沒取出；submodule 裡有檔案內容讀不到時仍被當成「搜尋過、沒有標記」；原因文字沒有長度上限。

## Root Cause

`marker_files()` 把「目錄存在、`git rev-parse --show-toplevel` 回報它自己」當成「這是取出的 submodule」。git 會把形狀像 git 目錄的一般資料夾認成 repository，並讀它的設定；設定可以指定要執行的指令。走訪也沒有在找到標記時停下，所以與結果無關的 gitlink 仍然被解碼、被搜尋，其中任何一步失敗都變成整個指令的失敗。路徑以嚴格的 UTF-8 解碼，並直接接在目錄後面，沒有檢查範圍。

## Proposed Solution

- 找到就停。每個 Example 先搜尋主 repo；找到標記就不看任何 submodule。主 repo 找不到才走 submodule，並在第一個找到的檔案停下。標記都在主 repo 的 repository，結果與沒有 submodule 的 repository 相同。
- 只在符合六個條件的目錄跑 git：路徑是相對路徑、沒有空的、`.` 或 `..` 的段；解開 symbolic link 之後仍在主 repo 的工作樹之內；目錄本身不是 symbolic link；目錄底下有自己的 `.git`；git 回報它是自己工作樹的頂層；物件庫裡有記錄的 commit。前四個條件不成立時不在那裡跑任何 git 指令。
- 在 submodule 目錄跑 git 時，一律加 `safe.bareRepository=explicit`、關掉 lazy fetch（`GIT_NO_LAZY_FETCH=1`），並拿掉繼承來的 `GIT_DIR`、`GIT_WORK_TREE`、`GIT_INDEX_FILE`、`GIT_OBJECT_DIRECTORY`、`GIT_ALTERNATE_OBJECT_DIRECTORIES`、`GIT_COMMON_DIR`。
- submodule 開始搜尋之後才失敗（`git grep` 的結束碼不是 0 或 1、沒找到算數的檔案而錯誤輸出有內容、tree 列不出來），算「搜尋不了」，不讓整個指令失敗。主 repo 這一層不變：搜尋的結束碼不是 0 或 1 照舊是 `error`。
- 檢查不抓任何東西：部分 clone 的 submodule 缺記錄的 commit 的物件時，算搜尋不了，不向遠端抓。
- 路徑照 git 儲存的位元組處理；`rev-parse` 的輸出只去掉結尾的一個換行。不是合法 UTF-8 的路徑照常處理，輸出仍是一行 JSON。
- 掛在規格目錄底下的 submodule 不搜尋，也不算搜尋不了。
- 原因文字：搜尋不了的 submodule 依路徑排序，最多列五個，其餘只報數量；超過 200 個字元的路徑截斷；原因是五種固定文字之一，不放 git 的錯誤訊息（裡面可以有本機路徑）。git 拒絕開啟的 submodule（例如擁有者不同、gitfile 壞掉）有自己的原因，不再併入「沒取出」。
- 修改 requirement「Added and modified requirements carry an executable check」的 Submodules 段，Example「markers in submodules」加二十六列（第 16 到 41 列）；`tests/spec-change/test.sh` 每列一個檢查，並補上第 4、5 列 fixture 的失敗檢查。
- 文件：`spec-change.py` 檔頭的 `links` 段、`references/spec-wrapper.md`（檢查前先取出 submodule；樹裡記成 submodule 但 `.gitmodules` 沒有對應項目的路徑無法取出）、CHANGELOG 裡 #548 那一條。

## Non-Goals

- 改變「submodule 搜尋不了時何時回 `error`」的讀法：仍然是只有標記到處都找不到時才回 `error`，等維護者確認（issue 的 Diagnosis，Choice Default Record）。這次的「找到就停」是把這個讀法做徹底，不是換讀法。
- 讓 IDD 的 skill 自己取出 submodule（在另外的 clone 或 worktree 跑 verify 時）：`idd-verify` 與 worktree 的說明不在這次範圍，記為後續。
- 為沒有 `.gitmodules` 項目的 gitlink 另立一種原因文字：只在 `references/spec-wrapper.md` 加一句。
- 主 repo 這一層的 git 呼叫：環境變數與設定照舊，不加這次的限制。
- ASSUMPTION: 不升版號；CHANGELOG 改寫這條分支自己加的 #548 那一條，不動其他條目。
- ASSUMPTION: 封存的 `idd-548-links-submodule-markers` 的 design 與 proposal 寫的「十列」是補強之前的數字，封存檔不改。

## Success Criteria

- 兩個重現在改動後的結果：路徑不是合法 UTF-8 的 gitlink、標記在主 repo → `ok`，結束碼 0；形狀像 git 目錄的資料夾 → 標記找不到時 `error`、點名那個路徑為 not checked out，標記在主 repo 時 `ok`，兩種情況 `config` 指定的指令都沒有執行（測試用一個標記檔確認）。
- 第 16 到 35 列的檢查在改 `spec-change.py` 之前，除了第 27、35 列可能已經通過，其餘每一列都有至少一項失敗；改完後全部通過。第 36 到 41 列是封存前補的（tasks 4.1）：第 36 列在補上對應的修正之前失敗，第 37 到 41 列檢查的是已經做對、先前沒有測試的行為，以變異測試確認它們分辨得出來（各拿掉對應的一處程式，該列失敗）。
- `tests/spec-change/test.sh` 既有的檢查全部照舊通過，檢查數只增不減。
- 沒有 gitlink 的 repo，以及有 gitlink 而標記都在主 repo 的 repo，`links` 的輸出與結束碼和這條分支之前的 script 逐位元組相同。
- `scripts/run-all-tests.sh` 的全部 suite 與 `.claude/scripts/tests/spectra-archive-post-ic/test.sh` 通過。
- 對這條分支的範圍跑 `links` 回 `ok`。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `spec-on-every-issue`: requirement「Added and modified requirements carry an executable check」寫明搜尋的順序、哪些 submodule 可以搜尋、在 submodule 目錄怎麼跑 git、submodule 裡的失敗怎麼算、原因文字的格式。

## Impact

- Affected specs: spec-on-every-issue（MODIFIED requirement「Added and modified requirements carry an executable check」）
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/spec-change.py
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-change/test.sh
  - Modified: plugins/issue-driven-dev/references/spec-wrapper.md
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
