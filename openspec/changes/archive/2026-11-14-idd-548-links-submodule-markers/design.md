## Context

`links` 是 `idd-implement`、`idd-all` 與 `idd-verify` 的規格包裝流程呼叫的檢查，行為寫在 capability `spec-on-every-issue`。它目前只看主 repo 自己追蹤的檔案。這個 script 的既有約定是：讀不到或無法判定的一律回 `error`，不回 `ok` 或 `missing`。

量測（臨時 repo，git 2.55.0）：`git grep --recurse-submodules <tree>` 讀 tree 記錄的 submodule commit、含巢狀，輸出路徑是 `<tree>:<submodule 路徑>/<檔案>`；submodule 沒取出時安靜略過（exit 1）；記錄的 commit 不在物件庫時 exit 128；在 submodule 的目錄裡對記錄的 commit 跑不帶旗標的 `git grep` 也找得到同一個檔案。

## Goals / Non-Goals

**Goals:**

- 標記在 submodule 的已追蹤檔案裡時找得到，讀的是 `<head>` 記錄的 commit。
- 沒看過的地方不被讀成「沒有標記」。
- 沒有 gitlink 的 repo 行為不變。

**Non-Goals:**

- 任何 gitlink 搜尋不了就一律 `error`（見 proposal 的 Non-Goals）。
- 搜尋 deinit 之後留在 `.git/modules/` 的 git 目錄。

## Decisions

### links 自己列出 gitlink 並逐一搜尋

對 `<head>` 跑 `git ls-tree -r -z`，取 mode 160000 的項目（路徑與 commit）。對每一個：目錄 `<repo>/<路徑>` 必須存在，而且在裡面跑 `git rev-parse --show-toplevel` 得到的就是它自己（實體路徑相同），否則記為「not checked out」；`git cat-file -e <commit>^{commit}` 失敗則記為「recorded commit <前 12 碼> is not in its object store」。兩項都過，就在那個目錄對那個 commit 跑現行的 `git grep -z -F -e <標記> <commit> -- .`，並對那個 commit 的 tree 以同樣方式處理它底下的 gitlink，路徑前面接上外層的 submodule 路徑。

目錄在工作樹裡是 symbolic link 時，也記為「not checked out」。

替代做法是加 `--recurse-submodules`。不採用：它略過沒取出與不是 active 的 submodule 時不留下任何訊息，仍然要另外列舉 gitlink 才知道哪些沒看；既然要列舉，就直接逐一搜尋，結果不依賴 git 對「active」的判定。

### 找不到而且有地方沒看過時回 error

`marker_files()` 回傳找到的檔案與沒辦法搜尋的 submodule 清單。`cmd_links()` 對一個 Example：有檔案就算有連結；沒有檔案、清單是空的，照舊加入 `missing`；沒有檔案、清單不是空的，丟出 `Fail`，原因是 `cannot decide whether the Example '<capability> / <title>' has a marker: submodule <路徑>: <原因>`（多個以分號分隔），指令回 `error`、exit 2。已找到標記的 Example 不因為別的 submodule 沒取出而失敗。無法判定的 Example 不只一個時，只點名檢查順序中遇到的第一個；原因裡列出每一個搜尋不了的 submodule。

### git 自己的遞迴一律關掉

每一次 `git grep` 都帶 `--no-recurse-submodules`。使用者的 git 設定若把 `submodule.recurse` 設成 true，`git grep` 給定 tree 時會自己進 submodule：沒取出的安靜略過，記錄的 commit 讀不到時以 128 結束，主 repo 已經有標記的 Example 也會因此被回報成 `error`。這一點由封存前的 `spectra-verify` 指出，在 git 2.55.0 上實測成立後補上；Example 的第 11、12 列檢查它。

### 排除規則套用在接上 submodule 路徑之後的名稱

`.md` 結尾與規格目錄底下這兩個排除，比對的是「submodule 路徑/檔案路徑」。submodule 自己的 `openspec/` 不另外排除：它底下的規格檔是 `.md`，已經被排除。

### gitlink 的清單與可搜尋性在一次執行內只算一次

以 (repo 目錄, commit) 為鍵快取 gitlink 清單與每個 submodule 的檢查結果，Example 多時不重複跑 `ls-tree` 與 `cat-file`。每個 Example 仍然各跑一次 `git grep`。

### 在 submodule 目錄裡只跑唯讀的 git 指令

只用 `ls-tree`、`rev-parse`、`cat-file`、給定 commit 的 `grep`，都經過 script 既有的 `git()` 包裝（`core.quotePath=false`、`GIT_LITERAL_PATHSPECS=1`）。這些指令不執行 hook、不讀工作樹的內容。

## Implementation Contract

呼叫端看到的行為：repo 的 `<head>` 沒有 gitlink 時，`links` 的輸出與結束碼與現在相同。有 gitlink 時，標記在已取出的 submodule（含巢狀）於記錄的 commit 的已追蹤檔案裡，該 Example 算有連結；標記找不到而每個 gitlink 都搜尋過，回報 `missing`，`why` 是現行文字；標記找不到而至少一個 gitlink 搜尋不了，指令印 `{"status": "error", "missing": [], "reason": "cannot decide whether the Example ... has a marker: submodule <path>: <reason>"}`，exit 2。

介面：`links --base <rev> [--head <rev>] [--cwd <dir>]` 不變；輸出仍是一行 JSON，欄位不變。

失敗情況：submodule 目錄不存在或不是自己工作樹的頂層（not checked out）；記錄的 commit 不在物件庫；在 submodule 裡的 git 指令以 0、1 以外的結束碼結束（照現行的 `git grep failed` 處理）。

驗收條件：

- Example「markers in submodules」的十列在 `tests/spec-change/test.sh` 各有一個檢查，測試檔帶標記 `spec-example: spec-on-every-issue / markers in submodules`。
- 改 `spec-change.py` 之前，十個檢查裡六個失敗（第 1、2、3、4 列應為 `ok`，第 8、10 列應為 `error`），第 5、6、7、9 列通過。
- 改完後 `bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 全部通過，既有檢查數不減；`python3 -m py_compile` 通過。
- `bash plugins/issue-driven-dev/scripts/run-all-tests.sh` 與 `bash .claude/scripts/tests/spectra-archive-post-ic/test.sh` 結束碼為 0。

範圍內：`spec-change.py` 的 `marker_files()`、`cmd_links()`、檔頭說明；`tests/spec-change/test.sh`；`references/spec-wrapper.md`；`CHANGELOG.md`。範圍外：其他 subcommand、其他 skill 的文字、版號。

## Risks / Trade-offs

- [CI 的 checkout 預設不取出 submodule，找不到標記的 Example 會從 `missing` 變成 `error`] → 這是要的結果：沒看過不算沒有。`references/spec-wrapper.md` 寫明檢查時 submodule 要已經取出。
- [submodule 多、Example 多時 git 指令變多] → 清單與可搜尋性快取；每個 Example 對每個 submodule 一次 `git grep`。
- [submodule 的路徑含空白或非 ASCII 字元] → `-z` 輸出與 `core.quotePath=false`；Example 有一列是含空白的路徑。
- [#547 的修正也改 `spec-change.py`] → 改動限在 `marker_files()`、`cmd_links()` 與檔頭的 `links` 段；先後合併時解一般的衝突。

## Migration Plan

沒有資料要搬。沒有 gitlink 的 repo 不受影響；有 gitlink 的 repo 在升級後，`links` 會多看 submodule，原本回報 `missing` 的 Example 可能變成 `ok` 或 `error`。

## Open Questions

- submodule 搜尋不了時要不要一律回 `error`（不論標記是否已在別處找到）。這次取「找不到才回 `error`」，等維護者確認（issue 的 Diagnosis，Choice Default Record）。
