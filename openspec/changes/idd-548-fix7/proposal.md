**GitHub-side tracker**: #548

## Problem

第七輪 verify（留言 6893428419）確認第七個 change 解決了第六輪的三列，但整輪不乾淨：有兩行程式比對的是解析後的路徑字串，而 requirement「Added and modified requirements carry an executable check」說的是目錄。這兩行在第六輪之前就有，前六輪都沒有人看到。

- 第 1 列（HIGH，blocking）：第 5 個條件。上游把放 submodule 的目錄只改大小寫（`Tests/sub` 改成 `tests/sub`），本機在不分大小寫的磁碟上照常 pull 之後，git 把那個目錄回報為它自己工作樹的頂層，`git submodule status` 也列出它；`links` 卻回 `error`，原因是 not checked out。只用 git 指令就走得到。
- 第 2 列（HIGH，blocking）：第 2 個條件的前半。link 的目標把頂層目錄寫成另一種拼法（另一種大小寫，或 macOS 上同一個磁碟的另一種絕對路徑）時，repository 裡的 submodule 被回 `error`，原因是 path leaves the repository；link 用實際的拼法時回 `ok`。
- 第 3 列（LOW）：「submodule 的 git 目錄不在清單上」在 submodule 的 git 目錄正好是清單上的目錄時，照字面不對。
- 第 4 列（LOW）：頂層目錄本身就是那兩個目錄之一時，第 2 個條件的子句與條件 6 之後的第四句說的相反。

兩項 HIGH 的方向都是保守的：答案是 `error`，不會把沒有檢查的 Example 說成 `ok`。

維護者的決定（留言 6894347661）：改程式，再審一輪。

## Root Cause

`os.path.realpath` 解析 symbolic link，但不會把同一個目錄的兩種拼法變成同一個字串。程式有兩處拿解析後的字串來判斷「是不是同一個目錄」或「在不在某個目錄底下」：

- `marker_files()` 用 `os.path.commonpath` 判斷 submodule 的目錄在不在頂層目錄底下（第 2 個條件的前半）。
- `marker_files()` 用字串相等判斷 git 回報的頂層是不是那個目錄（第 5 個條件）。

同一個函式裡，與那兩個 git 目錄的比對（第 2 個條件的後半）用的是 `os.stat`，不受拼法影響；`under_git_directory()` 往上走的迴圈卻用字串長度決定何時停。條文在第 2 個條件裡寫了「比對的是目錄，不是名稱」，前半沒有照做。

## Proposed Solution

- 程式：
  - 第 2 個條件：從解析後的目錄往上走，每一層用 `os.stat` 與頂層目錄比對，遇到頂層目錄就停；走到檔案系統的根還沒遇到，原因是 path leaves the repository。沿路經過的每一層（不含頂層目錄）就是拿來與那兩個 git 目錄比對的清單，`under_git_directory()` 不再自己往上走。
  - 第 5 個條件：git 回報的頂層與那個目錄用 `os.path.samefile` 比對。
- 條文：
  - 第 2 個條件寫明整個條件都比對目錄，並說「在頂層目錄底下」是什麼意思（往上走會遇到頂層目錄）；子句加上「除非它就是頂層目錄」。
  - 第 5 個條件寫明 git 回報的是同一個目錄，不論路徑怎麼拼。
  - 「submodule 的 git 目錄不在清單上」改成「不另外加進清單」，並說它正好是那兩個目錄之一或在其中之一底下時，第 2 個條件照寫的適用。
- Example「markers in submodules」加四列（第 60 到 63 列）。這四列需要同一個目錄的兩種拼法，測試只在不分大小寫的磁碟上建得出來；在區分大小寫的磁碟上，測試印出一行說明並略過這四列。
- `spec-change.py` 檔頭的說明、函式的說明與 CHANGELOG 的 #548 條目，改成同樣的說法。

## Non-Goals

- 不改主 repo 自己的搜尋，也不改 `archived`、`preflight`、`declared`、`ic`。
- 不改「同一個目錄、同一個 commit 只搜尋一次」所用的鍵（仍是解析後的路徑字串）：同一個目錄經由兩種拼法被搜尋兩次時答案相同。記在 #559。
- 不改規格目錄與 `.md` 的排除：條文寫明它們看的是樹裡記的名稱。量測結果與一個因此改變答案的輸入寫在 design「照名稱比對而這次不動的地方」。
- 不處理 #556、#559 裡的其他項目，包括繼承的 `GIT_DIR`、`GIT_COMMON_DIR`，以及 git 答不出目錄時的原因文字。
- 不排除 submodule 自己的 git 目錄，也不改「解析後等於頂層目錄的路徑照樣接受」。

## Success Criteria

- 在不分大小寫的磁碟上，第 60、61 列的檢查在改程式之前的 commit 上失敗（`status` 是 `error`），之後通過。第 62 列改之前與之後都通過。第 63 列的答案改之前與之後相同，但改之前是字串比對拒絕的、沒有問 git 那兩個目錄，所以它「問過那兩個目錄」的檢查在改之前失敗、之後通過。
- 逐一把程式的每一處修改改回去或改壞時，每一種都讓至少一列的檢查失敗。哪一種讓哪些列失敗以量到的為準，記在 tasks.md 的驗收紀錄；動手之前已知的一點是，第 60 列的輸入要第 2 個條件與第 5 個條件兩處都改了才回 `ok`，所以把其中任何一處改回去，第 60 列都會失敗。
- 第 1 到 59 列的答案不變。
- `bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 全部通過；`bash plugins/issue-driven-dev/scripts/run-all-tests.sh` 結束碼 0。
- `spec-change.py links` 從預設分支到這條分支的 HEAD 回 `ok`；`archived` 回 pass。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `spec-on-every-issue`: requirement「Added and modified requirements carry an executable check」的第 2、5 個條件與條件之後的一段改寫；Example「markers in submodules」加第 60 到 63 列。

## Impact

- Affected specs: spec-on-every-issue（一個 MODIFIED requirement）
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/spec-change.py
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-change/test.sh
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
