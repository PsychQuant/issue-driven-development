## Context

第二輪 verify 找到的七項裡，四項在程式（頂層目錄的讀法、巢狀 submodule、錯誤輸出、git 版本），三項在測試與文件。這份 design 只寫要決定的事；第二個 change 的六個條件、submodule 用的 git 包裝、原因的上限都不變。

量測（臨時 repo，git 2.55.0，協調者執行）：

- `git rev-list --objects --no-walk --missing=print <commit>` 列出那個 commit 的 tree 與檔案內容，缺的以 `?` 開頭，結束碼 0。完整的 repo：沒有 `?`。少一個檔案內容或一個子目錄的 tree：各一行 `?`。tree 裡的 gitlink 不會被當成缺的物件。只在較舊的 commit 裡出現的物件不算。部分 clone（`--filter=blob:none`、沒有 checkout）：列出缺的內容，執行前後物件庫的物件數相同，沒有抓取；沒有設 `GIT_NO_LAZY_FETCH` 時也一樣。三千個檔案的 tree 約 0.1 秒。
- 完整而沒有標記的 submodule，`GIT_TRACE=1` 之下，現行 script 回 `error`；不設時回 `missing`。
- 外層 submodule 少一個無關的檔案內容、標記在完整的巢狀 submodule：現行 script 回 `error`、只點名外層；外層完整時回 `ok`。
- 頂層目錄名稱以空白結尾的 repo：`links` 回 `ok`，分支之前的 script 回 `error`（revision does not exist）。

## Goals / Non-Goals

**Goals:**

- requirement 不再有與程式不一致的總括句。
- 「這個 submodule 讀不完」由一次明確的檢查決定，不由 git 有沒有錯誤輸出決定。
- 一個可以搜尋的巢狀 submodule 不因為外層讀不完而被略過。
- 在任何版本的 git 上，檢查都不向遠端抓東西。
- 第一輪第 2 列那一類缺陷（找到的標記被別處的失敗蓋掉）在 submodule 這一層有測試擋住。

**Non-Goals:**

- 主 repo 這一層的三個既有缺口（#556）。
- 讓 skill 自己取出 submodule（#554）。

## Decisions

### 改的是 requirement 的句子，不是把程式改回去

維護者的決定。兩處「exactly as before」改成可以檢查的話：主 repo 找到標記時不列 gitlink、不檢查 submodule；head 沒有記錄 submodule 的 repo 只搜尋自己追蹤的檔案，submodule 的規則不改變它的答案。兩個邊界上的行為各有一句與一列 Example：頂層目錄照 git 印出的讀（新 requirement）；規格目錄底下不是合法 UTF-8 的路徑回 `error`，原因是固定文字 `a path under the spec directory is not valid UTF-8`，不帶例外的原文。

### 頂層目錄的讀法放在 repo_top()

`repo_top()` 改成以 `os.fsdecode` 解碼、只去掉結尾的一個換行；`cmd_links()` 改回呼叫它，刪掉自己那一份。`archived` 與 `preflight` 本來就呼叫 `repo_top()`，所以三個子命令的讀法相同。這是一條新的 requirement，因為它管的不只是 `links`。

### 以 rev-list 的 --missing=print 決定讀不讀得完

進入一個 submodule（六個條件都成立）之後，先跑一次 `git rev-list --objects --no-walk --missing=print <commit>`：結束碼不是 0，或有任何一行以 `?` 開頭，這個 submodule 就是「缺物件」。結果與 gitlink 清單一樣，每個（目錄, commit）在一次執行內只算一次。

接著照常搜尋。找到算數的檔案就回傳（找到的標記確定這個 Example，不論這個 submodule 缺不缺物件）。沒找到時，下列任一成立就記為搜尋不了，原因是 `its recorded commit could not be read`：缺物件；`git grep` 的結束碼不是 0 或 1；tree 列不出來。submodule 的 `git grep` 的錯誤輸出不再讀。主 repo 不變：搜尋以 0、1 以外的結束碼結束時回 `error`，原因是 `git grep failed: ` 加上 git 錯誤輸出的前 200 個字元，和這條分支之前一樣（所以設了 `GIT_TRACE=1` 時，主 repo 這種錯誤的原因文字會跟著變；requirement 的句子只說 submodule 算不算搜尋過、它的原因不受錯誤輸出影響）。

替代做法是只認錯誤輸出裡以 `error:`、`fatal:` 開頭的行。不採用：git 的訊息前綴會隨語系翻譯，而且「有一行 error」仍然不等於「有物件讀不到」。

### 搜尋失敗之後仍然列 gitlink

記下「搜尋不了」之後不跳走，繼續對同一個 commit 跑 `ls-tree`，把它的 gitlink 放進待走訪清單。`ls-tree` 失敗時，這個 submodule 記為搜尋不了（已經記過就不重複），它裡面的 submodule 無從得知，走訪在這裡停。同一個 submodule 在原因裡只出現一次。

### git 比 2.45 舊時不在 submodule 目錄跑 git

`GIT_NO_LAZY_FETCH` 是 git 2.45 的功能；較舊的 git 會忽略它，部分 clone 的 submodule 會在搜尋時向遠端抓物件。第一次要在某個 submodule 目錄跑 git 之前（它的前四個條件已經成立），先跑一次 `git version` 並取出主版號與次版號，結果在一次執行內只算一次。比 2.45 舊、或讀不出版號時，這個 submodule 記為搜尋不了，原因是 `git is older than 2.45`，不在它的目錄跑任何 git 指令（Example 第 47 列兩種都測）。前四個條件不成立的 submodule 仍然回報它自己的原因。

替代做法是只在文件寫最低版本。不採用：那樣 Example 第 32、33 列的「沒有抓取」在舊 git 上就是假的。只對部分 clone 設限也考慮過；不採用，因為要先在那個目錄讀設定才知道它是不是部分 clone，規則也變成兩層。

主 repo 找到標記的 Example 不受影響：那時根本不檢查 submodule，也不讀版號。

### 把性質改壞的變異也要有檢查擋住

第二個 change 的變異表只拿掉防護。這次的驗收加上把性質改壞的變異，每一種都要有檢查失敗：

- 找到檔案但有 submodule 搜尋不了時不算找到（第 44 列）。
- 缺物件的 submodule 裡找到的檔案不算（第 45 列）。
- 搜尋失敗的 submodule 不列 gitlink（第 42 列）。
- 錯誤輸出又被算成讀不到（第 46 列）。
- 拿掉版本檢查（第 47 列）。
- `repo_top()` 改回 `.strip()`（Example「top directory names」）。
- 拿掉缺物件的檢查（第 20、36 列）。
- submodule 的搜尋以 0、1 以外的結束碼結束時不算失敗（第 49 列：物件在、但已損壞，缺物件的檢查看不出來，量測 `rev-list` 回 0、沒有 `?`，`git grep` 回 128）。
- 讀不出的版號當成夠新（第 47 列）。
- 主 repo 的搜尋失敗時原因不帶 git 的訊息（「what the link check reports」新增的第二列）。
- 主 repo 的搜尋失敗時原因不截到 200 個字元（同一列）。

兩種變異沒有任何輸入能分辨，記為明文例外，不算缺口：留著 `GIT_INDEX_FILE`（這裡只讀 commit、不讀 index）；submodule 的 tree 列不出來時不另外記原因（列 tree 要讀的物件，缺物件的檢查與搜尋都已經讀過，所以這時它一定已經被記為搜尋不了；程式裡那一句留著當防護）。主 repo 也一樣：列 gitlink 失敗時共用的 git 包裝會以 `error` 停下，但搜尋成功就表示每個 tree 都讀得到，所以這條路到不了，requirement 不另外寫它。

## Implementation Contract

呼叫端看到的行為（第二個 change 的契約沒有提到的部分不變）：

- 頂層目錄名稱以空白結尾的 repo：`links`、`archived`、`preflight` 的輸出與結束碼，和同一個 repo 放在沒有結尾空白的路徑時相同。
- 規格目錄底下有不是合法 UTF-8 的路徑：`links` 印 `{"status": "error", "missing": [], "reason": "a path under the spec directory is not valid UTF-8"}`，結束碼 2。
- 標記只在完整的巢狀 submodule、外層缺一個無關的檔案內容：`ok`。同樣的兩層而標記哪裡都沒有：`error`，只點名外層，原因是 `its recorded commit could not be read`。
- 標記在 submodule 的算數檔案、同一個 commit 另一個檔案內容不在：`ok`。
- 兩個 submodule，路徑順序在前的那個沒取出，標記在後面那個：`ok`。
- 完整而沒有標記的 submodule，`GIT_TRACE=1`：`missing`。
- git 回報的版本比 2.45 舊：標記只在 submodule → `error`，原因是 `submodule <path>: git is older than 2.45`，沒有任何 git 指令在 submodule 目錄執行；標記在主 repo → `ok`。

原因的固定文字（封閉列舉，只有這六種）：`path leaves the repository`、`not checked out`、`git is older than 2.45`、`git refused to open it`、`recorded commit <前 12 碼> is not in its object store`、`its recorded commit could not be read`。

介面：三個子命令的參數與輸出欄位都不變。

驗收條件：

- Example「markers in submodules」第 42 到 49 列、「what the link check reports」新增的兩列、「top directory names」的三列，在 `tests/spec-change/test.sh` 各有一個檢查；測試檔的標記清單加上 `spec-example: spec-on-every-issue / top directory names`。
- 第 47 列以一個會記錄、而且把 `git version` 的答案換成舊版號的 git 包裝執行，確認紀錄裡沒有任何在 submodule 目錄的呼叫。
- 改 `spec-change.py` 之前：第 42、43、46、47 列、「top directory names」的 `archived` 與 `preflight` 兩列、非 UTF-8 那一列的原因，各至少一項失敗；第 44、45、48 列與「top directory names」的 `links` 那一列通過。
- 改完後 `bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 全部通過，既有檢查數不減、沒有既有檢查被改寬；`python3 -m py_compile` 通過。
- 上一節列的十一種變異，各自至少一項檢查失敗（協調者在實作者寫不到的目錄執行）。
- 沒有 gitlink 的 repo，以及有 gitlink 而標記都在主 repo 的 repo，新 script 與 `6ed8dec` 的 script 輸出與結束碼逐位元組相同（一般的路徑與檔名）。
- `bash plugins/issue-driven-dev/scripts/run-all-tests.sh` 與 `bash .claude/scripts/tests/spectra-archive-post-ic/test.sh` 結束碼為 0。

範圍內：`spec-change.py` 的 `repo_top()`、`marker_files()`、`cmd_links()`、submodule 用的 git 包裝、檔頭說明；`tests/spec-change/test.sh`；`references/spec-wrapper.md`；`CHANGELOG.md` 的 #548 條目。範圍外：其他 subcommand 的邏輯（`archived` 與 `preflight` 只因為 `repo_top()` 而改變）、主 repo 這一層的搜尋（#556）、skill 的文字、版號。

## Risks / Trade-offs

- [git 比 2.45 舊的使用者不能把標記放在 submodule 裡] → 這個功能是這條分支才加的，沒有既有的使用者受影響；原因文字寫明版本，升級 git 就能用。主 repo 裡的標記不受影響。
- [每個 submodule 多跑一次 `rev-list`] → 一次執行內每個（目錄, commit）只跑一次；量測三千個檔案約 0.1 秒。
- [缺物件的 submodule 仍然搜尋，`git grep` 可能在中途以 128 結束] → 結束之前印出的符合行是那個 commit 的真實內容，找到算數的檔案就算；沒找到時這個 submodule 記為搜尋不了。關掉 lazy fetch 之後不會抓取。
- [`repo_top()` 的改動影響 `archived` 與 `preflight`] → 只有頂層目錄名稱以空白字元結尾時答案才不同，而且是從錯的變成對的；新 requirement 寫明，Example 三列各測一個子命令。

## Migration Plan

沒有資料要搬。這條分支還沒有合併。

## Open Questions

(none)
