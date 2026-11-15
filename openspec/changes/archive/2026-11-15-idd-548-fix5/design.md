## Context

第五輪 verify 第一次從頭審整條分支（預設分支到 `8003a7b`）。結論是 1 項 blocking、4 項要在分支上修、8 項後續（留言 6889821186）。

blocking 的那一項：head 記錄一個 gitlink `dir/sub`；工作目錄裡 `dir` 是指向 `.git/planted` 的 symbolic link，`.git/planted/sub` 是人工放進去、持有記錄的 commit 與標記的 clone。`links` 回 `ok`，並在那個目錄執行五次 git；4.1.0 回 `missing`。requirement 的第 2 個條件是「its directory, after symbolic links are resolved, lies inside the working tree of the main repository」。git 自己在 `.git/planted` 裡回報：不在工作目錄內、在 git 目錄內。security 一席評為 LOW；devil's advocate 補審後依審查規則裁定 HIGH（範圍內改變了、而 requirement 沒有寫明的行為）。兩席都確認後果小：讀的是記錄的 commit（依 id），不會替沒有標記的 commit 回 `ok`；commit、clone、checkout 都產生不出這個狀態。

量測（協調者，git 2.55.0，macOS；三個 fixture，各用 4.1.0 與 `8003a7b` 的 script 跑一次，並記錄 git 呼叫）：

| link 指向 | 4.1.0 | `8003a7b` | 在 `dir/sub` 的 git 呼叫 |
| --- | --- | --- | --- |
| 主 repo 的 `.git/planted` | `missing` | `ok` | 5 |
| 工作目錄內的另一個目錄 | `missing` | `ok` | 5 |
| 頂層目錄之外 | `missing` | `error`（path leaves the repository） | 0 |

## Goals / Non-Goals

Goals：

- 第 2 個條件的程式與條文一致：主 repo 的 git 目錄與它底下的東西不算在工作目錄內。
- 這個行為有一列 Example，而且它的測試在修正之前失敗。
- 第五輪第 2 到 5 列在同一輪補齊，不改任何行為。

Non-Goals：

- 不改 link 指向工作目錄內另一個 clone 時的答案。
- 不排除主 repo 以外的 git 目錄；不處理第五輪第 6 到 13 列（#559）。

## Decisions

### 照條文改程式，不改條文去配合程式

兩種修法：(a) 程式照條文，把落在主 repo git 目錄裡的目錄算成不符合第 2 個條件；(b) 把條文改成「頂層目錄內」，並寫明 git 目錄也算在內。選 (a)。理由：「不符合前四個條件的目錄裡不得執行 git」這一句的用意，是不在工作目錄以外的地方執行 git；(a) 讓答案變成 `error`，方向是少讀、不是多讀，與這條分支先前的取捨一致（讀不到或不該讀時回 `error`，不把沒檢查到的說成檢查過）。(b) 是在審查者指出不一致之後改條文去配合程式，而且會把「在 git 目錄裡執行 git」寫成規格。

### git 目錄的位置問 git，用目錄的身分比，不比名稱

主 repo 的 git 目錄不一定叫 `.git`（`--separate-git-dir` 可以放在任何地方、取任何名字），在會折疊大小寫的檔案系統上，link 的目標也可以寫成 `.GIT`。所以不比路徑字串：在主 repo 的頂層執行 `git rev-parse --absolute-git-dir` 取得位置，從解析後的目錄一層一層往上走到頂層目錄為止，每一層用 `os.stat` 的裝置與 inode 與 git 目錄比。任一層相同，就是 git 目錄本身或在它底下。某一層 stat 不到（目錄不存在）就跳過那一層：不存在的東西不會是 git 目錄，而目錄不存在的 submodule 之後會被第 3、4 個條件判成 not checked out。git 目錄本身 stat 不到時回 `error`。

主 repo 是 linked worktree，或它自己是別人的 submodule 時，git 目錄在頂層目錄之外，這個檢查不會命中任何東西；那種位置原本就被「在頂層目錄之外」擋下。

### 只排除主 repo 自己的 git 目錄

條文講的是主 repo 的工作目錄，所以排除的是主 repo 的 git 目錄。照一般做法取出的 submodule，git 目錄在主 repo 的 `.git/modules/` 底下，因此也在排除的範圍內。沒有涵蓋的只有一種：外層 submodule 的 `.git` 是放在它自己目錄裡的真目錄（不是由 `git submodule` 取出）時，link 指進那個 `.git`。照條文那個位置在主 repo 的工作目錄內。要不要一律排除任何 git 目錄，是另一個決定，記在 #559。

### 只在第一次要檢查 submodule 的目錄時問一次

requirement 的「Order of the search」寫明：標記在主 repo 就找到時，不列出 gitlink、不檢查任何 submodule。所以 git 目錄的位置不在一開始就問，而是在第一次有 submodule 的目錄通過「在頂層目錄內」之後才問，並存起來給同一次執行的其他 submodule 與其他 Example 用。標記都在主 repo 的 repo，git 呼叫的次數不變。

### 原因沿用 path leaves the repository

requirement 把第 1、2 個條件的原因定為同一句。這個情況是第 2 個條件不成立，所以用同一句，不新增第七種原因。

### 第 29 列：改 fixture，不改列

第五輪第 2 列指出第 29 列寫「標記只在七個 submodule 記錄的 commit 裡」，fixture 卻是七個指向不存在的 commit 的 gitlink。兩種修法：把列的第一欄改成 nowhere，或把 fixture 建成列裡寫的。選後者：列裡寫的輸入（標記真的在 submodule 裡、但都沒有 checkout）才是這個功能要回答的情況，而且程式對它的答案已經由兩席實測確認。fixture 另外確認每個 submodule 都停在記錄的 commit、那個 commit 有標記，再 deinit。斷言不改。

### 第 7 到 12 列的標籤改名

第五個 change 的 design 決定不改這些斷言的名稱，理由是它們只是訊息。第五輪第 5 列指出：檢查失敗時印出的標題在規格裡已經找不到。所以這次改成現在的 Example 標題的用詞。只改名稱，比對的內容不變。

### 建不出暫存目錄就停

測試檔的 fixture 都建在 `$WORK` 底下，也會刪除它底下的路徑。`mktemp` 失敗時 `$WORK` 是空的，那些路徑就落在檔案系統的根目錄。所以 `mktemp` 失敗、或結果不是目錄時，測試印出原因並以 1 結束，不往下跑。

## Implementation Contract

- `openspec/specs/spec-on-every-issue/spec.md`（由封存套用）：requirement「Added and modified requirements carry an executable check」的第 2 個條件多一句；Example「markers in submodules」在第 54 列之後多第 55 列。其他句子與列逐字不變。
- `plugins/issue-driven-dev/scripts/spec-change.py`：`marker_files()` 在「解析後的目錄在頂層目錄內」之後、檢查目錄本身之前，多一個判斷；新增一個函式做逐層比對。除此之外不改。這個判斷成立時，不呼叫 `submodule_git()`。
- `plugins/issue-driven-dev/scripts/tests/spec-change/test.sh`：新增第 55 列的 fixture 與 7 個檢查；第 29 列的 fixture 重建，斷言不變；`mktemp` 的守衛；28 處標籤與標題改名。
- `plugins/issue-driven-dev/CHANGELOG.md`：只動 `[Unreleased]` 裡 #548 那一條，兩處。
- 驗證：第 55 列的檢查在 `8003a7b` 的 script 上失敗、在改過的 script 上通過；`tests/spec-change/test.sh` 全部通過；`run-all-tests.sh` 結束碼 0；`links --base origin/main` 回 `ok`；`archived` 回 pass。

## Risks / Trade-offs

- 有 submodule 要檢查的執行多一次 git 呼叫（在主 repo 的頂層）。
- 在主 repo 的 git 目錄裡放 clone、再用 link 接出來的人，答案從 `ok` 變成 `error`。這個狀態只能手動造出來；`git submodule update --init` 取出的 submodule 不受影響。
- 外層 submodule 自己的 `.git` 真目錄不在排除範圍內（見上面的決定）。
- 協調者在做這個 change 時另外試出一種同類的情況，這個 change 不處理：記錄的路徑經過上層的 symbolic link 離開頂層目錄、再回到頂層目錄本身（例如 `out` 指向 `..`，記錄的路徑是 `out/<頂層目錄的名字>`），而且 head 為它記錄的是主 repo 自己較早的一個 commit。六個條件照字面都成立（git 在頂層目錄回報它在工作目錄內），`links` 會讀那個較早的 commit；那個 commit 有標記時回 `ok`，即使 head 自己的檔案沒有標記。修改前後的 script 答案相同，4.1.0 回 `missing`。這個狀態同樣要手動放 link 才造得出來。記在 #559。
- 這個 change 的條文、測試與程式都由協調者撰寫，沒有實作者模型，也沒有獨立讀者；第六輪 verify 是第一次獨立審查。

## Migration Plan

不需要。沒有設定或資料要搬。

## Open Questions

沒有。要不要排除任何 git 目錄（不只主 repo 的），在 #559。
