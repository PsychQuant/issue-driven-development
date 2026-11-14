## Context

第三輪 verify 找到的十六列裡，第 1 到 10 列與第 14 列在這張 issue 修；第 11 列的清單已補在 issue 的留言；第 12、13、15、16 列是分支之前就有的事，開在 #558。維護者選定了第 1 列與第 3 列的做法（issue 留言 6885330621）。這份 design 只寫這次要決定的事；六個條件、submodule 用的 git 包裝、版本檢查、原因的列舉都不變。

量測。標「協調者」的是這次自己在臨時 repo 上跑的（git 2.55.0，macOS）；標「審查者」的是第三輪的 devil's advocate 與 logic 兩席量到的（git 2.55.0 與 Apple 的 git 2.54.0，macOS），協調者沒有重做：

- 物件檔長度為零（協調者；第 50 列的 fixture 每次執行都確認前兩點）：`git rev-list --objects --no-walk --missing=print` 回 0、沒有 `?` 行；`git grep` 印一行 error、結束碼 0 或 1；把物件 id 交給 `git cat-file --batch-check`，回報 `<id> missing`。沒有讀取權限的物件檔也是這三個結果（審查者）。
- 物件檔不是壓縮資料：`git grep` 以 128 結束（協調者）。夠大的檔案內容在最後一個位元組損壞時，`--batch-check` 回報「在」、`git grep` 以 128 結束（協調者；第 54 列的 fixture 每次執行都確認），所以搜尋的結束碼仍然要看。只有十幾個位元組的內容做同樣的損壞時，`--batch-check` 回報的是 missing（協調者，第一版 fixture 因此不能用）。
- `--batch-check` 在部分 clone 裡會抓取，除非設了 `GIT_NO_LAZY_FETCH=1`；`rev-list --missing=print` 不設也不抓。五萬個檔案的 commit，`--batch-check` 約 0.07 秒（都是審查者的量測）。
- 把 `rev-list` 的整行（id 加檔名）交給 `--batch-check`，每個有檔名的物件都會被回報成 missing，所以只能送 id（審查者；這次的變異 P16 得到同樣的結果）。
- 搜尋中途中止時，`git grep` 有時已經印出標記那一行、有時沒有；兩千個檔案的 submodule 上，上一輪的 script 30 次裡 6 次回 `ok`（協調者）。

## Goals / Non-Goals

**Goals**

- 「在、但打不開」的物件與缺少的物件同樣算讀不完。
- 同一個 repo 的同一個狀態，每次執行的答案相同。
- requirement 的每一句都與程式一致，每一列 Example 的檢查都執行它寫的情況。
- 測試檔不受呼叫者的 git 環境影響。

**Non-Goals**

- 主 repo 這一層的行為（#556、#558）。
- 抓出「物件 id 底下放的是另一個合法物件」：git 讀取時不核對雜湊，任何做法都看不出來，第二輪的 script 也看不出來。

## Decisions

### 用 cat-file --batch-check 確認物件打得開

`submodule_lacks_objects(directory, rev)` 取代原來在 `marker_files()` 裡的那兩行：

1. `rev-list --objects --no-walk --missing=print <rev>`。結束碼不是 0 → 缺。
2. 輸出只在 `\n` 切開。整行是 `?` 加十六進位字元的 → 缺。其餘每一行取第一個空白之前的 id。
3. 所有 id 以換行分隔交給 `cat-file --batch-check` 的標準輸入。結束碼不是 0、回答的行數與 id 數不同、或任何一行以 ` missing` 結尾 → 缺。

第 3 步經過 `submodule_git()`，所以有 `GIT_NO_LAZY_FETCH=1`、`safe.bareRepository=explicit`，而且只在版本檢查通過之後才會走到。`submodule_git()` 多一個 `stdin` 參數。

替代做法是重新讀錯誤輸出、只認 `error:` 與 `fatal:` 開頭的行。不採用：devil's advocate 找到兩個完整的 submodule 仍會被誤判的例子（`.gitattributes` 的一行、指向不存在目錄的 alternates）。

### 搜尋中途中止時不採用它印出的內容

submodule 的 `git grep` 以 0、1 以外的結束碼結束時，`marker_files()` 不逐行讀它的輸出，直接把這個 submodule 記為搜尋不了，然後照舊列它的 gitlink。這是第二輪 script 的答案（一律 `error`），差別只在第二輪之後仍然會往下走到它底下的 submodule。主 repo 的搜尋中止時照舊是 `error`。

替代做法是讓 submodule 的搜尋只用一個執行緒（`--threads=1`）。不採用：答案仍然取決於損壞的物件排在標記之前還是之後，只是變成固定的；而且 requirement 要多寫一條關於讀取順序的規則。

requirement 因此改成「搜尋跑完時（結束碼 0 或 1）找到的檔案才確定這個 Example」。缺一個檔案內容時 `git grep` 不會中止，所以第 42、45 列不變。

### 句子與測試各自收窄到做得到的範圍

- 非 UTF-8 路徑：只有規格目錄的 `specs/` 底下（base 或 head）才回 `error`；其他位置不影響答案，補一列固定。
- 巢狀 submodule：清單來自 `ls-tree -r`，也就是每一個 tree 的列表；任何一個 tree 讀不到，清單就拿不到。不改成逐層列出：那會讓缺 subtree 的 submodule 多一種答案，而方向只是少回一個 `error`。補第 53 列固定現在的行為。
- 第 49 列的文字改成它的 fixture 造出來的情況（不是壓縮資料、搜尋以 128 結束）。「在、但打不開」由新的第 50 列負責。第 49 列的物件現在也會被 `--batch-check` 回報成缺，所以「只有搜尋的結束碼看得出來」改由新的第 54 列固定：物件的內容在最後一個位元組損壞，git 列得出它、也打得開，搜尋仍以 128 結束。
- 主 repo 的原因：行為不變。檢查改用一個假的 git，它的搜尋以 128 結束並寫出 300 個字元、每四個一組都不同的訊息；原因必須等於前綴加上前 200 個字元。

### 測試檔自己的環境

- 開頭讀一次 `git version`，比 2.45 舊就以一句話停下。
- 設定隔離的那一行之後，unset 會改變 git 讀哪個 repo 或寫多少訊息的變數。需要這些變數的列自己在那一次呼叫設定。
- `setup_failed` 在子 shell 裡（`BASH_SUBSHELL` 大於 0）時，另外對主 shell 送 TERM；主 shell 的 TERM trap 以 1 結束。bash 3.2 也有 `BASH_SUBSHELL`。

### 每一處改動各有一種變異

驗收時在上一個 change 的 34 種之外加上這些，每一種都要有檢查失敗：

- 不呼叫 `--batch-check`（第 50 列）。
- `rev-list` 的輸出改回用 `splitlines()` 切（第 51 列）。
- 搜尋中止時仍然讀它印出的內容（第 52 列）。
- 主 repo 的原因改留後 200 個字元（「what the link check reports」的那一列）。
- `repo_top()` 去掉所有結尾的換行（「top directory names」名稱以換行結尾的三列）。
- 搜尋的結束碼不再讓 submodule 算搜尋不了，只看缺不缺物件（第 54 列）。
- 把 `rev-list` 的整行而不是 id 交給 `--batch-check`（多數 submodule 的列）。

上一個 change 的兩種明文例外不變：留著 `GIT_INDEX_FILE`；submodule 的 tree 列不出來時不另外記原因。第 53 列走到的正是後一種的那個分支，但那時這個 submodule 已經因為缺物件被記為搜尋不了，所以拿掉那一句答案不變。

## Implementation Contract

呼叫端看到的行為（前三個 change 的契約沒有提到的部分不變）：

- submodule 裡帶標記的檔案，它的物件檔是空的：`error`，點名那個 submodule，原因是 `its recorded commit could not be read`。上一輪是 `missing`。
- 完整的 submodule 裡有檔名含 CR 緊接問號、哪裡都沒有標記：`missing`。上一輪是 `error`。
- 標記所在的 submodule 搜尋到一半就中止（結束碼 128）：每次都是 `error`。上一輪有時是 `ok`。
- 規格目錄底下、`specs/` 以外的非 UTF-8 路徑：答案不受影響（三輪以來都是這樣，現在 requirement 這樣寫）。
- 名稱以換行結尾的頂層目錄：`links`、`archived`、`preflight` 的答案與放在一般名稱的同一個 repo 相同（上一個 change 起就是這樣，現在有列固定）。
- 其餘輸入的輸出與結束碼不變。沒有 gitlink 的 repo 與標記都在主 repo 的 repo，輸出與 `6ed8dec` 逐位元組相同。

驗收條件：

- Example 新增與改寫的每一列各有檢查；第 50、51、52 列的檢查在 `726050b` 的 script 上失敗。
- 上一節列的七種變異各自至少一項檢查失敗；34 種舊變異的結果不比上一次差。
- `726050b`、`7ad9152`、`afd0021`、`6ed8dec` 的測試檔配新 script 全部通過。
- 整套測試通過。

範圍：

- In scope：`spec-change.py` 的 `submodule_git()`、`marker_files()` 與新函式；測試檔；requirement 的兩條；`references/spec-wrapper.md`；CHANGELOG 的 #548 條目。
- Out of scope：主 repo 的搜尋與原因文字；`archived`、`preflight` 的邏輯；時間上限；封存的檔案。

## Risks / Trade-offs

- `--batch-check` 多開一個行程、多讀一次每個物件的檔頭。量測的成本很小，而且每個 submodule 的每個 commit 只做一次。
- 搜尋中止時一律 `error`，會讓「標記其實讀得到、但別的檔案損壞到讓搜尋中止」的 repo 得到 `error` 而不是 `ok`。這是保守的方向，也是第二輪的答案。
- 測試檔在 git 比 2.45 舊的機器上整個不跑。先前是 55 項失敗而沒有說明。
- 第 50、52、54 列的 fixture 各自先確認 git 的行為與上面的量測相同，不同就讓整個測試停下。這些量測都在 macOS 上；這個 repo 的 CI 在 Linux 上跑，而這條分支沒有 PR，CI 還沒有跑過。
- 名稱不是合法 UTF-8 的頂層目錄沒有測試。

## Migration Plan

沒有資料或設定要遷移。合併並發布之後，使用者更新 plugin 即可。

## Open Questions

- 主 repo 的原因文字要留錯誤輸出的哪一端（#558 第 1 點）。決定之後，這次加的檢查要跟著改。
