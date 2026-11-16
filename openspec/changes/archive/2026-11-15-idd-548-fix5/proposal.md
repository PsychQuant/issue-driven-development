**GitHub-side tracker**: #548

## Problem

第五輪 verify（留言 6889821186）第 1 列。submodule 路徑的上層目錄是 symbolic link，指向主 repo 自己的 git 目錄裡一個人工放進去的 clone 時，`links` 在那裡執行 git（五次）並回 `ok`。requirement「Added and modified requirements carry an executable check」的第 2 個條件寫的是「解析 symbolic link 之後，位於主 repo 的工作目錄內」；git 目錄不屬於工作目錄，所以照條文這個 submodule 不該被搜尋，答案是 `error`（path leaves the repository），而且「不符合前四個條件的目錄裡不得執行 git」。

同一輪的第 2 到 5 列是測試檔與 CHANGELOG 的缺口，不改行為，在同一輪修。

## Root Cause

`marker_files()` 用「解析後的路徑是不是在頂層目錄的實際路徑底下」判斷第 2 個條件。主 repo 的 git 目錄通常就在頂層目錄底下（`.git`），所以也被算成在裡面。第二個 change 的 design 寫的是「頂層目錄」，requirement 寫的是「工作目錄」；兩個詞只在 git 目錄這一塊不同，而 Example 沒有任何一列建這個輸入，所以五輪之前沒有被發現。

## Proposed Solution

- 程式照條文走。解析後的目錄是主 repo 的 git 目錄，或在它底下時，算不符合第 2 個條件：原因是 path leaves the repository，不在那個目錄執行 git。
- git 目錄的位置問 git（`git rev-parse --absolute-git-dir`，在主 repo 的頂層執行），再用「是不是同一個目錄」逐層往上比，不比名稱。只在第一次要檢查某個 submodule 的目錄時問一次；標記在主 repo 就找到的情況不多任何 git 呼叫。
- requirement 的第 2 個條件補一句，寫明主 repo 自己的 git 目錄與它底下的東西不算在工作目錄內。
- Example「markers in submodules」補第 55 列；它的測試在這次修正之前的 commit 上失敗。
- 第五輪第 2 到 5 列：第 29 列的 fixture 改成列裡寫的輸入；建不出暫存目錄時測試不往下跑；第 7 到 12 列的標籤改用現在的 Example 標題；CHANGELOG 補一句 `submodule.recurse` 打開時答案會變的情況。

## Non-Goals

- 不處理 link 指向工作目錄內另一個 clone 的情況：照條文那是寫明的行為（第五輪兩席讀法相同）。
- 不排除其他 repository 的 git 目錄（例如外層 submodule 自己的 `.git` 目錄）。條文講的是主 repo 的工作目錄；要不要一律排除任何 git 目錄，留在 #559。
- 第五輪第 6 到 13 列留在 #559，不在這條分支處理。

## Success Criteria

- 第 55 列的測試在 `8003a7b`（這次修正之前）失敗，在修正之後通過；它確認答案是 `error`、原因點名路徑與 path leaves the repository，而且記錄 git 呼叫的程式沒有看到任何一次在那個目錄的呼叫。
- link 指向工作目錄內另一個 clone 時仍回 `ok`；link 指到頂層目錄之外時仍回 `error`。
- `bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 全部通過；`bash plugins/issue-driven-dev/scripts/run-all-tests.sh` 結束碼 0。
- `spec-change.py links` 從預設分支到這條分支的 HEAD 回 `ok`；`archived` 回 pass。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `spec-on-every-issue`: requirement「Added and modified requirements carry an executable check」的第 2 個條件補一句；Example「markers in submodules」加第 55 列。

## Impact

- Affected specs: spec-on-every-issue（一個 MODIFIED requirement）
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/spec-change.py
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-change/test.sh
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
