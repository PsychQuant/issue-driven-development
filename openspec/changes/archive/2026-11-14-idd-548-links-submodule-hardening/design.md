## Context

`idd-548-links-submodule-markers` 讓 `links` 走進 submodule 搜尋標記。第一輪 verify 指出這一步帶來三件先前沒有的事：`links` 第一次在主 repo 頂層以外的目錄跑 git；第一次把 tree 裡的路徑接到檔案系統上；第一次在已經有答案之後還繼續做會失敗的事。`links` 由 `idd-verify` 自動執行，輸入是別人送來的 commit，所以 tree 的內容與 submodule 工作樹裡的檔案都要當成不可信的資料。

量測（臨時 repo，git 2.55.0，協調者重跑）：

- gitlink 路徑是 `vendor/lib\xff`、標記在主 repo：這條分支的 script 印出 traceback、沒有 JSON、結束碼 1；分支之前的 script 回 `ok`。
- submodule 記錄的 commit 再記一個 gitlink `emb`，工作樹在較新的 commit 上、把 `emb/HEAD`、`emb/config`、`emb/objects/.keep`、`emb/refs/heads/.keep` 當一般檔案追蹤；`emb/config` 設了 `core.bare=false`、`core.worktree=.`、一個 promisor remote 與 `core.sshCommand`：`links` 回 `error`，而 `core.sshCommand` 指定的指令已經執行。

git 的規則裡這次用到的三條：git 不允許追蹤名為 `.git` 的路徑（大小寫不論），所以送來的 commit 無法在工作樹裡放出一個 `.git`；`safe.bareRepository=explicit` 讓 git 拒絕把沒有 `.git` 的目錄當成 repository；`GIT_NO_LAZY_FETCH=1` 讓 git 在物件不存在時直接失敗而不去抓。

## Goals / Non-Goals

**Goals:**

- `links` 不在 commit 內容可以擺佈的目錄裡跑 git，也不到主 repo 的工作樹之外跑 git。
- 主 repo 已經找到標記的 Example，結果與這條分支之前相同，不受任何 gitlink 影響。
- submodule 裡的任何失敗只會讓「這個 submodule 搜尋不了」，不會變成 traceback，也不會被讀成「沒有標記」。
- 輸出永遠是一行 JSON，結束碼 0、1 或 2。

**Non-Goals:**

- 改變「何時回 `error`」的讀法（見 proposal 的 Non-Goals）。
- 主 repo 這一層 git 呼叫的環境與設定。
- 讓 skill 自己取出 submodule。

## Decisions

### 找到就停，主 repo 先搜尋

`marker_files()` 先搜尋主 repo。只要有一個算數的檔案就立刻回傳，不列 gitlink、不碰任何 submodule。主 repo 沒找到才列 gitlink 並逐一搜尋，任何一層找到就回傳。

這同時解決四件事：主 repo 已有標記時不會在任何 submodule 目錄跑 git（第一輪確認過，原本連結果是 `ok` 的時候也會執行植入的指令）；找到的標記不會被之後的失敗蓋掉；標記都在主 repo 的 repository 完全不走新的程式路徑，行為與這條分支之前逐位元組相同；Example 多、submodule 多時少跑很多次 `git grep`。

替代做法是保留完整走訪、把每一種失敗都接住。不採用：要接的失敗種類是開放的，漏一種就是一次 regression；不走就不會失敗。

### 只在符合六個條件的目錄跑 git

對走訪中的目錄底下、路徑為 `<path>` 的 gitlink，依序檢查，第一個不成立的就決定原因：

1. `<path>` 是相對路徑，而且沒有空的、`.` 或 `..` 的段。不成立：`path leaves the repository`，而且完全不查檔案系統（原因文字不會透露那個位置上有什麼）。
2. `<目錄>/<path>` 解開 symbolic link 之後，位於主 repo 頂層目錄（同樣解開之後）之內。不成立：`path leaves the repository`。
3. 它是目錄、本身不是 symbolic link、底下有名為 `.git` 的項目。不成立：`not checked out`。到這一步為止沒有在裡面跑過任何 git 指令。
4. 在裡面跑 `git rev-parse --show-toplevel` 成功，而且回報的就是它自己（實體路徑相同）。指令失敗：`git refused to open it`（擁有者不同而被拒、gitfile 壞掉、不認得的 extension 都在這裡；要看原因，在那個目錄跑一次 `git status`）。指令成功但回報的是別的目錄：`not checked out`。
5. 在裡面跑 `git cat-file -e <commit>^{commit}` 成功。不成立：`recorded commit <前 12 碼> is not in its object store`。

規格把第 3 步拆成兩個條件（不是 symbolic link、有 `.git`），所以寫成六個；程式的順序如上。

第 3 步的 `.git` 是關鍵：commit 的內容無法在工作樹裡產生 `.git`，所以形狀像 git 目錄的一般資料夾過不了這一步。第 4、5 步再加兩層（見下一個決定），讓舊版 git 或其他形狀的資料夾也不會被當成 repository。第一輪另有一個建議是再確認 `rev-parse --git-dir` 指向該目錄的 `.git` 或 superproject 的 modules；不採用：`.git` 無法由 commit 的內容產生，是使用者自己建立的，再查它指向哪裡沒有多擋住什麼。

封存的 `idd-548-links-submodule-markers` 在 tasks 3.2 記了一個判斷：內容由 commit 的雜湊決定，所以不必檢查路徑。那個判斷只管「讀到的內容是不是記錄的那一版」，沒有管「git 在哪裡執行、讀誰的設定」。這次補上後者。

### 在 submodule 目錄跑 git 的方式

submodule 目錄裡的每一次 git 呼叫（上一個決定的第 4、5 步、`grep`、`ls-tree`）都經過同一個包裝：`git()` 原有的選項，加上 `-c safe.bareRepository=explicit`；環境變數設 `GIT_NO_LAZY_FETCH=1`，並拿掉 `GIT_DIR`、`GIT_WORK_TREE`、`GIT_INDEX_FILE`、`GIT_OBJECT_DIRECTORY`、`GIT_ALTERNATE_OBJECT_DIRECTORIES`、`GIT_COMMON_DIR`。

拿掉這六個變數的原因：它們會讓 `git -C <submodule>` 改看別的 repository，判定出來的原因就是錯的（實測：`GIT_DIR` 指向主 repo 時，取出的 submodule 被回報成缺 commit；`GIT_ALTERNATE_OBJECT_DIRECTORIES` 指向另一個物件庫時，submodule 自己沒有的 commit 會被當成有，結果由不屬於這個 submodule 的物件決定）。六個變數裡五個各有測試擋住（Example 第 28、40、41 列）；`GIT_INDEX_FILE` 是唯一的例外：這裡只讀記錄的 commit，不讀 index，留著它不會改變任何輸出，所以寫不出會失敗的測試。把它一起拿掉，是因為 submodule 的指令沒有理由看主 repo 的 index。主 repo 的呼叫維持 `git()`，不加這些限制：部分 clone 的主 repo 可能需要 lazy fetch 才讀得到規格檔，那是既有行為。

### submodule 裡的失敗算搜尋不了

在 submodule 目錄：`git grep` 的結束碼不是 0 或 1，或沒有找到算數的檔案而錯誤輸出有內容（有物件讀不到），或 `git ls-tree` 失敗，原因都是 `its recorded commit could not be read`。「沒有找到算數的檔案」包含結束碼是 0 的情況：`git grep` 只要有一行符合就回 0，而符合的可以全是不算數的檔案（`.md`、標題更長的另一個 Example）。這一點由封存前的 `spectra-verify` 指出，重現後補上（Example 第 36 列）。`ls-tree` 不另立原因：`git grep` 乾淨結束時已經讀過 `ls-tree -r` 需要的每一個 tree，所以它在這之後失敗幾乎不會發生，另立一種原因就會有一條測不到的規則。原因用固定文字，不放 git 的錯誤訊息：那段訊息裡可以有本機路徑（第一輪實測），而且內容由送 commit 的人影響。

主 repo 這一層不變：`git grep` 的結束碼不是 0 或 1 照舊丟出 `Fail`（`git grep failed: ...`），結束碼 1 照舊是沒找到。主 repo 的 gitlink 清單現在只在主 repo 沒找到標記時才列，列不出來時丟出 `Fail`。

關掉 lazy fetch 之後，部分 clone 的 submodule 裡從沒抓過的物件會讓 `git grep` 以 128 結束（第一輪實測），落在這裡的第一種情況，不會被悄悄算成「搜尋過、沒有標記」。

沒找到加上錯誤輸出就算搜尋不了，是往保守的方向取：寧可在罕見情況回 `error`，也不把沒讀完的 submodule 說成沒有標記。

### 路徑照位元組處理

gitlink 的路徑與 `rev-parse --show-toplevel` 的輸出用 `os.fsdecode` 解碼（無法解碼的位元組保留成代理字元，檔案系統呼叫時還原）。`rev-parse` 的輸出只去掉結尾的一個換行，不用 `.strip()`：路徑結尾可以是空白。放進原因文字時，把無法解碼的位元組換成替代字元，確保 JSON 印得出來。

### 規格目錄底下的 gitlink 略過

完整名稱（外層路徑加自己的路徑）在規格目錄底下的 gitlink 不搜尋，也不記為搜尋不了。它的每一個檔案名稱都以規格目錄開頭，本來就不算；把它記為搜尋不了，會讓找不到標記的 Example 回 `error`，而實際上所有可能算數的檔案都讀過了。

### 原因文字有上限

搜尋不了的 submodule 依路徑排序，列出前五個（`submodule <path>: <reason>`，以 `; ` 相連），超過時加上 `; and <N> more`；超過 200 個字元的路徑只留前 200 個、後面接 `...`。原因的開頭維持 `cannot decide whether the Example '<capability> / <title>' has a marker: `。

排序讓輸出不依賴走訪的順序。上限是因為這段文字會被 `idd-verify` 放進報告與審查者的說明，而 gitlink 的路徑與數量由送 commit 的人決定。

## Implementation Contract

呼叫端看到的行為：

- 標記在主 repo 的已追蹤檔案裡：`links` 的輸出與結束碼和這條分支之前的 script 相同，不論 `<head>` 記錄了什麼 gitlink。
- 標記只在取出的 submodule（含巢狀）於記錄的 commit 的已追蹤檔案裡：該 Example 算有連結。
- 標記找不到、每個 gitlink 都搜尋過（規格目錄底下的不計）：`missing`，`why` 是現行文字。
- 標記找不到、至少一個 gitlink 搜尋不了：`{"status": "error", "missing": [], "reason": "cannot decide whether the Example '<capability> / <title>' has a marker: submodule <path>: <reason>[; ...][; and <N> more]"}`，結束碼 2。

原因的固定文字（封閉列舉，只有這五種）：`path leaves the repository`、`not checked out`、`git refused to open it`、`recorded commit <前 12 碼> is not in its object store`、`its recorded commit could not be read`。

介面：`links --base <rev> [--head <rev>] [--cwd <dir>]` 不變；輸出仍是一行 JSON，欄位不變。任何輸入都不會讓 script 以 traceback 結束。

驗收條件：

- Example「markers in submodules」的第 16 到 41 列在 `tests/spec-change/test.sh` 各有一個檢查；第 21、22、31 列另外確認 `config` 指定的指令沒有執行；第 23 列確認外面有沒有 repository 不影響結果；第 19、20 列確認原因裡沒有 git 的錯誤訊息；第 32、33 列確認沒有東西被抓進 submodule。
- 改 `spec-change.py` 之前，新的檢查除了第 27、35 列可能已通過，其餘每一列至少一項失敗；改完後全部通過，既有檢查數不減。
- 沒有 gitlink 的 repo，以及有 gitlink 而標記都在主 repo 的 repo，改動前後（對照這條分支之前的 script）輸出與結束碼逐位元組相同。
- 協調者的兩個重現在改動後：第一個回 `ok`；第二個回 `error` 而標記檔不存在。在只套用新測試檔、script 維持 `afd0021` 的複本上，第 21 列的標記檔確實被建立（證明這個測試分辨得出來）。
- `python3 -m py_compile` 通過；`bash plugins/issue-driven-dev/scripts/run-all-tests.sh` 與 `bash .claude/scripts/tests/spectra-archive-post-ic/test.sh` 結束碼為 0。

範圍內：`spec-change.py` 的 `marker_files()`、`cmd_links()`、submodule 用的 git 包裝、檔頭說明；`tests/spec-change/test.sh`；`references/spec-wrapper.md`；`CHANGELOG.md` 的 #548 條目。範圍外：其他 subcommand、主 repo 層的 `git()`、skill 的文字、版號。

## Risks / Trade-offs

- [第 3 步要求 `.git`：以 `git worktree` 或其他方式掛進來、沒有 `.git` 項目的目錄會被判成沒取出] → git 的每一種取出方式（submodule、worktree、一般 clone）都會在目錄裡留下 `.git` 檔或目錄，所以實際上不會誤判；真的沒有 `.git` 的目錄不該在裡面跑 git。
- [`GIT_NO_LAZY_FETCH` 在較舊的 git 沒有作用] → 不執行植入指令的防線不靠它：第 3 步在 Python 裡擋，`safe.bareRepository` 是第二層，這個變數是第三層。受影響的只有「不抓取」這一項：忽略這個變數的 git 仍會向部分 clone 的 submodule 自己設定的遠端抓物件，那時 Example 第 32、33 列的檢查會失敗，這是正確的訊號。測試判斷物件在不在時只列出本機有的物件（`cat-file --batch-all-objects`），不依賴這個變數。
- [結束碼 1 加錯誤輸出就算搜尋不了，可能把只是警告的情況也算進去] → 只在標記到處都找不到時才有影響，結果是 `error` 而不是 `missing`，方向保守；原因文字會點名那個 submodule。
- [部分 clone 的 submodule 在關掉 lazy fetch 之後讀不到物件] → 回報成搜尋不了，並點名 submodule；先把 submodule 的物件抓齊再跑檢查。
- [原因只列前五個 submodule] → 其餘的數量有寫；全部取出之後再跑一次就會看到下一批。

## Migration Plan

沒有資料要搬。這條分支還沒有合併，所以沒有已發布的行為要相容；對照的基準是分支之前的 script。

## Open Questions

- submodule 搜尋不了時要不要一律回 `error`：仍然等維護者確認，這次沒有改讀法。
- `idd-verify` 在另外的 clone 或 worktree 跑時要不要自己取出 submodule，或只在說明裡提醒：不在這次範圍。
