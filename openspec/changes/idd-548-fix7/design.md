## Context

第七輪 verify（留言 6893428419）確認 `idd-548-fix6` 解決了第六輪的三列，另外找到一個更早就有的缺陷，落在兩行：`marker_files()` 用解析後的路徑字串判斷 submodule 的目錄在不在頂層目錄底下（第 2 個條件的前半），也用字串相等判斷 git 回報的頂層是不是那個目錄（第 5 個條件）。同一個目錄有兩種拼法時，兩行都答錯，方向都是保守的（回 `error`）。同一輪還有兩項條文字面的問題（第 3、4 列）。

維護者決定（留言 6894347661）：改程式，再審一輪。

協調者在動手之前重現了兩項（第七輪報告已記）：

- 上游把放 submodule 的目錄只改大小寫，本機在不分大小寫的磁碟上 `git pull --recurse-submodules` 之後，`links` 回 `error`，原因是 not checked out；git 在那個目錄回報的頂層是磁碟上的名稱（`Tests/sub`），樹裡記的是 `tests/sub`。
- link 的目標把頂層目錄寫成另一種大小寫，或寫成 macOS 上同一個磁碟的另一種絕對路徑（前面加 `/System/Volumes/Data`）時，`links` 回 `error`，原因是 path leaves the repository；link 用 git 的拼法時回 `ok`。

## Goals / Non-Goals

**Goals**

- 第 2 個條件與第 5 個條件都比對目錄，不比對名稱。
- 條文對「在頂層目錄底下」與「同一個目錄」各給一個可以對著程式核對的說法。
- 兩種拼法指同一個目錄的輸入，有 Example 的列與測試。
- 修掉第七輪第 3、4 列的兩句字面。

**Non-Goals**

- 不改主 repo 自己的搜尋，不改其他 subcommand。
- 不改規格目錄與 `.md` 的排除（照樹裡記的名稱比對），見下面「照名稱比對而這次不動的地方」。
- 不新增被排除的目錄種類，不改「解析後等於頂層目錄的路徑照樣接受」。
- 不處理 #556、#559 的其他項目。

## Decisions

### 「在頂層目錄底下」的意思是往上走會遇到頂層目錄

`os.path.realpath` 解析 symbolic link，但留下路徑原本的拼法；`os.path.commonpath` 比的是字串。新的做法從解析後的目錄開始，逐層取上一層目錄，每一層用 `os.stat` 與頂層目錄比對裝置與 inode（`os.path.samestat`）。遇到頂層目錄就停，條件的前半成立；走到檔案系統的根還沒遇到，原因是 path leaves the repository。

條文照這個做法寫：「going from the resolved directory to its parent directory, to the parent of that one, and so on, the top directory is met」。這句話的每一個詞都對得上一行程式，沒有另外的「在底下」的定義。

### 往上走經過的目錄，就是與那兩個 git 目錄比對的清單

`under_git_directory()` 原本自己往上走，用字串長度決定何時停（`len(current) > len(real_top)`）；解析後的路徑與頂層目錄拼法不同時，這個停止條件沒有意義。新的做法只走一次：`directories_below_top()` 回傳遇到頂層目錄之前經過的每一個目錄（解析後的目錄自己，除非它就是頂層目錄；以及兩者之間的每一層），`under_git_directory()` 只比對這份清單。頂層目錄不在清單裡，所以永遠不會被拿去比對，與 `idd-548-fix6` 的決定相同。

git 的兩個問題（`--absolute-git-dir`、`--git-common-dir`）仍然只在頂層目錄被遇到之後才問，次序與呼叫次數不變。

### 第 5 個條件用同一種比對

git 在 submodule 的目錄回報的頂層，與那個目錄，用 `os.path.samefile` 比對。git 印的是磁碟上的名稱；樹裡記的路徑、或 link 的目標，可以是同一個目錄的另一種拼法。

### 檢查不到的目錄略過

往上走時，`os.stat` 失敗的那一層（例如不存在）不是頂層目錄，也不是那兩個目錄之一，繼續往上。沒有取出的 submodule（目錄不存在）因此仍然通過第 2 個條件，由第 3、4 個條件回報 not checked out，與修改前相同。條文加一句說明這一點。第 5 個條件比對時，任一邊檢查不到就當作不是同一個目錄（not checked out）。

### 條文的三句（第七輪第 3、4 列）

- 第 2 個條件的子句改成「解析後的目錄自己，除非它就是頂層目錄，以及兩者之間的每一層」，不再與「解析後等於頂層目錄的路徑符合第 2 個條件」那一句相反。
- 「submodule 的 git 目錄不在清單上，所以裡面的目錄會被搜尋」改成：不另外把任何 submodule 的 git 目錄加進清單；它正好是那兩個目錄之一、或在其中之一底下時，第 2 個條件照寫的適用，否則裡面的目錄在六個條件成立時會被搜尋。
- 「頂層目錄不與那兩個目錄比對，所以頂層目錄在其中之一裡面時」補上「就是其中之一」的情形。

### 四列 Example，只在不分大小寫的磁碟上執行

| 列 | 輸入 | 答案 | 修改前 |
| --- | --- | --- | --- |
| 60 | link 的目標把頂層目錄寫成另一種大小寫，submodule 在工作目錄裡 | `ok` | `error`，path leaves the repository |
| 61 | 樹裡記 `tests/sub`，磁碟上的目錄是 `Tests/sub` | `ok` | `error`，not checked out |
| 62 | link 指到頂層目錄之外，目標用另一種大小寫 | `error`，path leaves the repository | 相同 |
| 63 | link 指進主 repo 的 git 目錄，目標把頂層目錄寫成另一種大小寫 | `error`，path leaves the repository | 相同的答案，但原因是字串比對：沒有問 git 那兩個目錄 |

第 61 列的 fixture 直接把 clone 放在 `Tests/sub`、把 gitlink 記在 `tests/sub`，沒有重演上游改名與 pull；那個過程由協調者的重現（上面 Context）涵蓋，列的文字只寫 fixture 建出來的狀態。第 62 列確認新的往上比對仍然拒絕頂層目錄之外的目錄；第 63 列確認原本因為字串不同而被拒絕的輸入，現在由 git 目錄的比對拒絕，測試從 git 呼叫紀錄確認問過那兩個目錄。

這四列需要同一個目錄的兩種拼法。在區分大小寫的磁碟上沒有不需要管理者權限的做法，測試偵測到之後印出一行說明並略過這四列；所以「測試先寫、在修改之前失敗」只在不分大小寫的磁碟上看得到。macOS 上另外用 `/System/Volumes/Data` 的拼法重跑第 60 列的輸入（那個路徑指得到 fixture 時）。

### 照名稱比對而這次不動的地方

`links` 走得到的路徑比對一共六處。這次改三處（第 2 個條件的前半、往上比對的停止條件、第 5 個條件）；其餘三處不動，各自在修改前後用兩種拼法量測過（不分大小寫的磁碟，git 2.55.0）：

1. **`--cwd`**：只交給 git 找頂層目錄，沒有任何比對。`--cwd` 把頂層目錄或它底下的目錄寫成另一種大小寫，答案與原本相同（`ok`）。
2. **「同一個目錄、同一個 commit 只搜尋一次」的鍵**（解析後的路徑字串與 commit）。同一個目錄以兩種拼法各記一次（`Tests/sub` 與 `tests/sub`）時，修改後兩個都通過條件，各被搜尋一次，答案相同（都沒有標記時是 `missing`）。修改前第二個被第 5 個條件回報為 not checked out（`error`）。重複搜尋不改變答案；拼法的個數有限，所以防止循環的作用不受影響。
3. **規格目錄與 `.md` 的排除**。條文寫明這兩個排除看的是名稱（「apply to that name」），名稱是樹裡記的路徑。樹裡記在 `OPENSPEC/specs/sub`、磁碟上落在規格目錄 `openspec/` 裡的 submodule：修改前回 `error`（not checked out，原因就是第 5 個條件比對名稱），修改後回 `ok`，因為這個名稱不在 `openspec/` 底下。主 repo 自己的檔案從這條分支之前就是這樣（樹裡記在 `OPENSPEC/specs/cap/check.sh` 的檔案帶標記時回 `ok`，修改前後相同）。這是這次修改唯一讓答案從 `error` 變成 `ok`、而又不是第 60、61 列的輸入；它照條文是對的，但規格目錄的排除在不分大小寫的磁碟上要不要忽略大小寫，是另一個問題（也牽涉主 repo 的檔案），記在 #559，這個 change 不決定。

## Implementation Contract

- `openspec/specs/spec-on-every-issue/spec.md`（由封存套用）：requirement「Added and modified requirements carry an executable check」的第 2、5 個條件換掉；「(6) its object store holds the recorded commit.」之後加兩句（比對的是目錄；檢查不到的目錄略過）；其後「The git directory of a submodule …」與「The top directory is not compared …」兩句換掉；Example「markers in submodules」在第 59 列之後多第 60 到 63 列。其他句子與列逐字不變。
- `plugins/issue-driven-dev/scripts/spec-change.py`：新增 `directories_below_top()`、`leaves_repository()`、`same_directory()`；`under_git_directory()` 改成比對一份清單；`marker_files()` 裡第 2 個條件的兩個分支合成一個、第 5 個條件改用 `same_directory()`，不再計算 `real_top`；檔頭 `links` 的說明改寫。除此之外不改。
- `plugins/issue-driven-dev/scripts/tests/spec-change/test.sh`：第 59 列之後新增第 60 到 63 列的 fixture 與檢查，以及偵測磁碟是否區分大小寫的一段；第 57 列的註解改成新的說法（不另外把 submodule 的 git 目錄加進清單）。其他不動。
- `plugins/issue-driven-dev/CHANGELOG.md`：只動 `[Unreleased]` 裡 #548 那一條講這兩個條件的那一句。
- 驗證：在不分大小寫的磁碟上，第 60、61 列的檢查與第 63 列「問過那兩個目錄」的檢查在改程式之前的 commit 上失敗、之後通過；第 62 列與第 63 列的其他檢查前後都通過；`tests/spec-change/test.sh` 全部通過；`run-all-tests.sh` 結束碼 0；`links --base origin/main` 回 `ok`；`archived` 回 pass。

## Risks / Trade-offs

- 比對裝置與 inode 是作業系統對「同一個目錄」的說法。同一個目錄經由兩個掛載點出現時（例如 Linux 的 bind mount），兩邊會被當成同一個目錄；這與條文一致。反過來，子目錄另外掛載到別處、而上層沒有一起掛載時，往上走遇不到頂層目錄，答案是 path leaves the repository（保守的方向）。
- 第 60 到 63 列在區分大小寫的磁碟上不執行，所以 Linux 上的 CI 看不到它們。這個缺陷在那種磁碟上不靠管理者權限也造不出來。
- 上面「照名稱比對而這次不動的地方」第 3 點：一個輸入的答案從 `error` 變成 `ok`。

## Migration Plan

沒有資料要搬。答案改變的輸入：第 60、61 列的形狀（`error` 變 `ok`），同一個目錄以兩種拼法各記一次（`error` 變成依搜尋結果），以及上面第 3 點。其他輸入的答案不變。

## Open Questions

- 規格目錄的排除在不分大小寫的磁碟上要不要忽略大小寫（#559）。
