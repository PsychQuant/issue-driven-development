**GitHub-side tracker**: #548

## Problem

`idd-548-links-submodule-hardening` 修好了第一輪 verify 的十二列。第二輪 verify（issue 留言 6878222878）確認了這一點，另外找到七項，其中三項由協調者重現：

1. requirement 寫了兩次主 repo 這一層「checked exactly as before」，但有兩種罕見的輸入結果變了，而且都是從錯的變成對的：頂層目錄名稱以空白結尾的 repo（先前回不實的 `error`，現在回正確的答案）；規格目錄底下有路徑不是合法 UTF-8 的 capability（先前以 traceback 結束，現在回 `error`，原因是例外的原文）。`archived` 與 `preflight` 仍用舊的讀法，三個子命令對同一個 repo 的判斷不一致。
2. submodule 的搜尋失敗時，它底下的 submodule 不再被搜尋：標記在一個取出而且完整的巢狀 submodule 裡時回 `error`。
3. 「找到的標記不被別處的失敗蓋掉」在 submodule 這一層沒有測試擋住：兩個把這個性質改壞的變異，測試全部通過。
4. submodule 的搜尋只要有任何錯誤輸出、又沒找到算數的檔案，就算「讀不到」：`GIT_TRACE=1`、名稱有歧義的警告、已淘汰設定的提示，都會把 `missing` 變成 `error`，而原因說的是程式沒有檢查過的事。
5. `links` 依賴 `GIT_NO_LAZY_FETCH`（git 2.45 起）而沒有檢查版本：較舊的 git 上，「不向遠端抓任何東西」不成立。
6. Example 第 11、12 列的 fixture 設定 `submodule.recurse` 的那一步沒有失敗檢查，也沒有確認設定生效。
7. `references/spec-wrapper.md` 叫人先取出 submodule，沒有提醒這個指令會向那條分支的 `.gitmodules` 指定的位址抓東西。

維護者 2026-11-14 的決定（issue 留言 6878497822）：這七項修完再審一輪；第 1 項改規格那句話、保留現在的行為，並讓三個子命令用同一種讀法；submodule 搜尋不了時，維持「標記到處都找不到才回 `error`」。

## Root Cause

- 第 1 項：requirement 用一句總括的話（exactly as before）描述主 repo 這一層，而程式在兩個邊界上其實變了；驗收時比對用的 repo 沒有這類名稱，所以量不出來。`links` 另抄了一份讀頂層目錄的程式，沒有改共用的 `repo_top()`。
- 第 2 項：`marker_files()` 在記下「搜尋不了」之後立刻跳到下一個 submodule，還沒列出它的 gitlink。
- 第 4 項：用「git 有沒有錯誤輸出」代替「有沒有物件讀不到」。前者不等於後者。
- 第 3、5、6、7 項：缺測試、缺版本檢查、缺一個失敗檢查、缺一句提醒。

## Proposed Solution

- 改 requirement 的兩句話：主 repo 找到標記時，不列任何 gitlink、不檢查任何 submodule；head 沒有記錄 submodule 的 repo 只搜尋自己追蹤的檔案，submodule 的規則不改變它的答案。規格目錄底下不是合法 UTF-8 的路徑寫成 `error` 的一種，原因用固定文字。
- 新增一條 requirement：`links`、`archived`、`preflight` 以同一種方式讀頂層目錄，照 git 印出的內容、只去掉結尾的換行。`links` 改回呼叫 `repo_top()`，改的是 `repo_top()` 本身。
- 搜尋失敗的 submodule 仍然列出它的 gitlink 並往下走；只有它的 tree 列不出來時，裡面的 submodule 才無從得知。
- 不再看 git 的錯誤輸出。搜尋 submodule 之前，先用 `git rev-list --objects --no-walk --missing=print <commit>` 問 git 記錄的 commit 缺哪些物件（量測：不抓取，部分 clone 也不抓；三千個檔案約 0.1 秒）。缺物件的 submodule 照樣搜尋，找到算數的檔案就確定；沒找到時才算搜尋不了。
- git 比 2.45 舊時，不在任何 submodule 目錄跑 git，那些 submodule 算搜尋不了，原因寫明 git 的版本。
- 測試：Example「markers in submodules」加第 42 到 49 列；「what the link check reports」加兩列；新 requirement 的 Example「top directory names」三列；第 11、12 列的 fixture 補檢查；第 22 列的 git 呼叫紀錄另外確認沒有列 gitlink 的呼叫（`ls-tree -r -z <commit>`）。
- 文件：`spec-change.py` 檔頭、`references/spec-wrapper.md`（最低的 git 版本；取出 submodule 會連到 `.gitmodules` 指定的位址）、CHANGELOG 的 #548 條目。

## Non-Goals

- 主 repo 這一層的三個既有缺口（顏色設定、檔名含換行、讀不到的檔案內容回 `missing`）：#556。
- `idd-verify` 與 worktree 的說明：#554。
- 改變「何時回 `error`」的讀法：維護者已確認維持現在的讀法。
- ASSUMPTION: 不升版號；CHANGELOG 改寫這條分支自己加的 #548 那一條。
- ASSUMPTION: 封存的兩個 change 的文字（例如 design 寫的「逐位元組相同」）是當時的紀錄，不改。

## Success Criteria

- 第二輪的三個重現在改動後：頂層目錄名稱以空白結尾的 repo，`links`、`archived`、`preflight` 的答案與同一個 repo 放在沒有結尾空白的路徑時相同；標記在完整的巢狀 submodule、外層少一個無關的檔案內容 → `ok`；完整的 submodule、沒有標記、`GIT_TRACE=1` → `missing`。
- 新的檢查在改 `spec-change.py` 之前各自失敗（第 44、45、48 列檢查的是已經做對的行為，以變異測試確認它們分辨得出來）；改完後全部通過，既有檢查數只增不減。
- 變異測試包含把性質改壞的變異，不只拿掉防護：找到的標記被別處的失敗蓋掉、缺物件的 submodule 裡找到的檔案不算、搜尋失敗的 submodule 的子項不看、錯誤輸出又被算進去、拿掉版本檢查。每一種都要有檢查失敗。
- 沒有 gitlink 的 repo，以及有 gitlink 而標記都在主 repo 的 repo，`links` 的輸出與結束碼和這條分支之前的 script（`6ed8dec`）逐位元組相同（比對用的 repo 路徑與檔名都是一般的名稱；邊界上的差異由新的 Example 列說明）。
- `scripts/run-all-tests.sh` 的全部 suite 與 `.claude/scripts/tests/spectra-archive-post-ic/test.sh` 通過；對這條分支的範圍跑 `links` 回 `ok`。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `spec-on-every-issue`: requirement「Added and modified requirements carry an executable check」改寫主 repo 那兩句、搜尋失敗的定義、巢狀 submodule、git 版本與原因的列舉；新增 requirement「The repository's top directory is read as git prints it」。

## Impact

- Affected specs: spec-on-every-issue（MODIFIED requirement「Added and modified requirements carry an executable check」；ADDED requirement「The repository's top directory is read as git prints it」）
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/spec-change.py
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-change/test.sh
  - Modified: plugins/issue-driven-dev/references/spec-wrapper.md
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
