## Context

第五輪之後的 change `idd-548-fix5` 讓 `links` 不搜尋落在主 repo git 目錄裡的 submodule 目錄，並在第 2 個條件補了一句。第六輪（留言 6891008905）的六席裡有四席各自找到那一句與程式不一致的配置，裁定為 2 項 blocking、1 項要在分支上修。共同的原因是那一句用一般的說法描述一個特定的比對。

維護者決定（留言 6891118023）：修，條文改封閉列舉，再審一輪。

## Goals / Non-Goals

**Goals**

- 第 2 個條件只寫程式比對的內容，讓每一句都能對著程式逐字核對。
- linked worktree 的配置下，repository 的 git 目錄也被比對。
- 每一句邊界有一列 Example。

**Non-Goals**

- 不新增被排除的目錄種類（submodule 自己的 git 目錄不排除）。
- 不改頂層目錄本身也算的行為。
- 不處理 #556 與 #559 裡的項目。

## Decisions

### 條文寫比對的內容，不寫「工作目錄」

第五輪與第六輪的爭議都落在「工作目錄」這個詞：它可以讀成 git 的回報，也可以讀成頂層目錄底下的範圍，兩種讀法在邊界上答案不同。新的第 2 個條件不用這個詞，改寫兩件可以直接核對的事：解析後的目錄是頂層目錄或在它底下；它自己與它到頂層目錄之間的每一層，都不是清單上的兩個目錄之一。

### 清單只有兩個目錄，而且寫明是封閉的

兩個目錄是在主 repo 的頂層問 git 得到的：`git rev-parse --absolute-git-dir` 印的，與 `git rev-parse --git-common-dir` 印的。一般的 repository 兩者是同一個目錄；linked worktree 裡前者是這個 worktree 私有的目錄，後者是 repository 的 git 目錄。條文加一句「這份清單是封閉的」，避免之後有人依性質相似再推出第三類目錄。

替代做法：把「任何 repository 的 git 目錄」都排除（對每個外層 submodule 再問一次它的 git 目錄）。沒有採用：多一類目錄就多一段程式與一批邊界；這種目錄裡的 clone 要能寫這台機器上的 repository 才放得進去，而在那裡的 git 呼叫與在任何已取出的 submodule 裡的呼叫用的是同一層防護。這是協調者依維護者「照你的建議修」所做的選擇，寫在留言 6891118023，維護者可以推翻。

### 兩個目錄分兩次問，相對路徑接在頂層目錄後面

`--git-common-dir` 在一般的 repository 印的是相對路徑（`.git`），相對於執行 git 的目錄；程式是以 `-C <頂層目錄>` 執行，所以不是絕對路徑時接在頂層目錄後面。不用 `--path-format=absolute`：它在 git 2.31 之前不存在，而這兩次呼叫發生在 git 版本檢查之前。不把兩個選項放在同一次呼叫：輸出會是兩行，目錄名稱含換行時分不開；現有讀單一路徑的寫法（只去掉 git 加的那一個換行）對一次一個路徑才成立。

代價：要檢查 submodule 目錄的那次執行，在頂層多兩次 git 呼叫（上一個 change 是多一次）。標記都在主 repo 時一次都不多。

### 往上比對只到頂層目錄為止

比對從解析後的目錄開始，逐層往上，到頂層目錄的下一層為止；頂層目錄本身不比對。所以 git 目錄在頂層目錄之上（或就是頂層目錄）時，頂層目錄底下的目錄不因此被拒絕。這是第六輪第 3 列的裁定：那種配置下 git 把頂層目錄底下的目錄當成工作目錄，拒絕它們會讓那種 repository 的每個 submodule 都搜尋不了。條文把這一點寫成一句，並有一列。

### 解析後就是頂層目錄的路徑符合第 2 個條件

程式比的是「頂層目錄是不是共同的上層」，解析後等於頂層目錄也成立，而且這時沒有任何一層要比對。第五、六輪建了這種輸入的席位都讀成寫明的行為。封閉列舉必須說清楚頂層目錄本身算不算，所以條文寫明它算，並有一列。它要不要算，是 #559 的問題；這個 change 不改行為。

### 原因沿用 path leaves the repository

與第 55 列相同，不新增原因文字。

## Implementation Contract

- `openspec/specs/spec-on-every-issue/spec.md`（由封存套用）：requirement「Added and modified requirements carry an executable check」的第 2 個條件整句換掉；「(6) its object store holds the recorded commit.」之後加一段三句；Example「markers in submodules」在第 55 列之後多第 56 到 59 列。其他句子與列逐字不變。
- `plugins/issue-driven-dev/scripts/spec-change.py`：`main_git_directory()` 改成回傳兩個目錄（改名 `main_git_directories()`），`under_git_directory()` 改成比對兩個；`marker_files()` 裡那個判斷的呼叫與註解跟著改；檔頭 `links` 的說明兩行改寫。除此之外不改。
- `plugins/issue-driven-dev/scripts/tests/spec-change/test.sh`：第 55 列之後新增第 56 到 59 列的 fixture 與檢查；第 55 列的註解改成新的說法。其他不動。
- `plugins/issue-driven-dev/CHANGELOG.md`：只動 `[Unreleased]` 裡 #548 那一條講這個條件的那一句。
- 驗證：第 56 列的檢查在改程式之前的 commit 上失敗、之後通過；第 57 到 59 列前後都通過；`tests/spec-change/test.sh` 全部通過；`run-all-tests.sh` 結束碼 0；`links --base origin/main` 回 `ok`；`archived` 回 pass。

## Risks / Trade-offs

- 要檢查 submodule 目錄的執行在頂層多兩次 git 呼叫。
- 這個 change 把兩個現有的行為寫成明文並各加一列：submodule 自己的 git 目錄裡的 clone 會被搜尋；記錄的路徑解析後是頂層目錄本身時，讀的是主 repo 自己的 commit。兩者要不要改，維護者之後可以另外決定；改的時候要連條文與那一列一起改。
- git 答不出這兩個目錄，或印出讀不到的路徑時，整次執行以 `error` 結束，原因文字不在 requirement 裡（第六輪第 6 列，#559 第 18 點）。這個 change 多問一個目錄，這條路徑多一個入口，行為相同。
- 呼叫端的環境帶著 `GIT_DIR` 或 `GIT_COMMON_DIR` 時，這兩次呼叫印的是那些變數指的目錄（第六輪第 7 列，#559 第 19 點）。這是主 repo 的呼叫本來就有的行為。
- 測試只在 macOS 上跑過；第 56 與 58 列的 fixture 有守衛，配置建不出來時整個測試會停下並說明原因。
- 這個 change 的條文、測試與程式都由協調者撰寫，沒有實作者模型，也沒有獨立讀者；第七輪 verify 是第一次獨立審查。

## Migration Plan

不需要。沒有設定或資料要搬。

## Open Questions

沒有。
