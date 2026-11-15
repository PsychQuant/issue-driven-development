**GitHub-side tracker**: #548

## Problem

第六輪 verify（留言 6891008905）留下三列，三列都出在第五輪之後補進 requirement「Added and modified requirements carry an executable check」第 2 個條件的那一句：「主 repo 自己的 git 目錄，與它底下的一切，不屬於工作目錄」。那一句寫的是一個一般的說法，程式比對的是一個特定的目錄，兩者在三種配置下不一致。

- 第 1 列（HIGH）：在 linked worktree 裡執行 `links`，而這個 worktree 的頂層目錄裡放著主 repo 時，放在主 repo 的 `.git` 底下的 clone 仍然被搜尋，並在那裡執行 git。
- 第 2 列（HIGH）：外層 submodule 自己的 `.git` 是真目錄時，指進那個 `.git` 的路徑被搜尋；條文沒有說這種目錄算不算。
- 第 3 列（MEDIUM）：主 repo 的 git 目錄在頂層目錄之上時，照那一句的字面每個 submodule 都該被拒絕，程式照常搜尋；裁定是條文錯、程式對。

維護者的決定（留言 6891118023）：修；那一句改成封閉列舉；再審一輪。

## Root Cause

- 程式只問了 `git rev-parse --absolute-git-dir`。在 linked worktree 裡它印的是這個 worktree 私有的目錄，repository 的 git 目錄是 `git rev-parse --git-common-dir` 印的那個，沒有被比對。
- 條文用「工作目錄」與「git 目錄底下的一切」這兩個一般的說法來描述一個只比對特定目錄、而且只在頂層目錄以下比對的檢查。說法的字面範圍比檢查寬（第 3 列），也沒有說清楚其他 repository 的 git 目錄算不算（第 2 列）。

## Proposed Solution

- 程式：在主 repo 的頂層問 git 兩個目錄，`--absolute-git-dir` 印的與 `--git-common-dir` 印的；submodule 的目錄，或它與頂層目錄之間的任何一層目錄，是兩者之一時，原因是 path leaves the repository，不在那裡執行 git。往上比對仍然只到頂層目錄為止。
- 條文：第 2 個條件不再用「工作目錄」，改成只寫比對的內容：解析後的目錄是頂層目錄或在它底下；它自己與它到頂層目錄之間的每一層，都不是那兩個目錄之一。六個條件之後加一段，寫明這份兩個目錄的清單是封閉的，並點出三個邊界：submodule 自己的 git 目錄不在清單內；頂層目錄本身不拿來比對；解析後就是頂層目錄的路徑符合第 2 個條件。
- Example「markers in submodules」加四列（第 56 到 59 列），一句邊界一列。第 56 列的測試在改程式之前失敗；第 57 到 59 列描述的是現有的行為，改之前與之後都通過。
- `spec-change.py` 檔頭的說明、兩個函式的說明、`test.sh` 第 55 列的註解與 CHANGELOG 的 #548 條目，改成同樣的說法。

## Non-Goals

- 不排除 submodule 自己的 git 目錄。維護者若要排除，是另一個 change。
- 不改「頂層目錄本身也算」這個行為；它要不要算，仍在 #559。
- 第六輪第 4 到 7 列（#556、#559）不在這裡處理，包括 git 答不出 git 目錄位置時的原因文字。

## Success Criteria

- 第 56 列的檢查在改程式之前的 commit 上失敗（`status` 是 `ok`、在那個目錄有 git 呼叫），之後通過。
- 第 57、58、59 列回 `ok`；第 55 列仍回 `error`、沒有呼叫。
- 把新加的比對（common 目錄）拿掉時，只有第 56 列的檢查失敗。
- `bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 全部通過；`bash plugins/issue-driven-dev/scripts/run-all-tests.sh` 結束碼 0。
- `spec-change.py links` 從預設分支到這條分支的 HEAD 回 `ok`；`archived` 回 pass。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `spec-on-every-issue`: requirement「Added and modified requirements carry an executable check」的第 2 個條件改寫為封閉列舉，六個條件之後加一段；Example「markers in submodules」加第 56 到 59 列。

## Impact

- Affected specs: spec-on-every-issue（一個 MODIFIED requirement）
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/spec-change.py
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-change/test.sh
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
