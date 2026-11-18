**GitHub-side tracker**: #548

## Problem

`scripts/spec-change.py links` 檢查每個新增或改到的 requirement 底下的 Example 有沒有帶標記的已追蹤檔案。它用 `git grep -z -F -e <標記> <head> -- .` 找檔案，而 `git grep` 在給定 tree 時不進 submodule。規格在主 repo、測試在 submodule 的 repo，每一個 Example 都回報 `missing`，不論測試檔有沒有標記；讀報告的人分不出是工具沒看到還是真的沒有。

## Root Cause

`marker_files()` 只搜尋主 repo 自己追蹤的檔案。在一個三層的臨時 repo（主 repo、submodule、巢狀 submodule，git 2.55.0）上量到：不加旗標時 submodule 裡的標記找不到；加 `--recurse-submodules` 找得到，讀的是 tree 記錄的那個 submodule commit，巢狀的也讀；但 submodule 沒取出時它安靜略過，結束碼與「沒有標記」相同，git 的說明也寫它只搜尋 active 且已取出的 submodule；tree 記錄的 commit 不在 submodule 的物件庫時以 128 結束。

## Proposed Solution

- `links` 自己列出 `<head>` 的 gitlink（`git ls-tree -r` 裡 mode 160000 的項目），逐一確認該目錄是自己工作樹的頂層、而且物件庫裡有記錄的 commit，然後在那個 commit 上搜尋；submodule 的 gitlink 照同樣方式往下走。不用 `git grep --recurse-submodules`。
- 一個 Example 有三種結果：找到標記就算有連結；沒找到而且每個 gitlink 都搜尋過，照舊回報缺少連結（`why` 文字不變）；沒找到而且至少一個 gitlink 沒辦法搜尋，整個指令回 `error`，原因寫出 Example、submodule 路徑與是沒取出還是缺 commit。
- submodule 裡的檔案以「submodule 路徑/檔案路徑」套用既有的兩個排除（規格目錄底下、`.md` 結尾）。
- 沒有 gitlink 的 repo 結果與現在相同。
- 修改 requirement「Added and modified requirements carry an executable check」，加一段 Submodules 與 Example「markers in submodules」（十列）；`tests/spec-change/test.sh` 每列一個檢查。
- 文件：`spec-change.py` 檔頭的 `links` 說明、`references/spec-wrapper.md` 一句（標記可以在 submodule 的已追蹤檔案裡，檢查時 submodule 要已經取出）、CHANGELOG 的 Unreleased。

## Non-Goals

- 只要有任何 gitlink 搜尋不了就一律回 `error`（不論標記是否已在別處找到）：比較嚴格的另一種讀法。這次取的是上面第二點的讀法，記在 issue 的 Diagnosis（Choice Default Record），等維護者確認；要改只需放寬一個條件。
- 搜尋已經 deinit、只剩 `.git/modules/` 的 submodule：視為沒取出。
- `idd-ci-gate` 在本身是 submodule checkout 的 repo 回 error（#535）：另一個問題。
- `idd-implement` 與 `idd-all` 的文字：它們只說測試檔帶標記，沒有規定檔案在哪裡，不改。
- ASSUMPTION: 不升版號，CHANGELOG 加在既有的 Unreleased 區塊。

## Success Criteria

- 新的十個檢查在改 `spec-change.py` 之前有六個失敗（四個標記在 submodule 裡而應為 `ok` 的列、兩個應為 `error` 的列），其餘四個通過；改完後十個都通過。
- `tests/spec-change/test.sh` 既有的檢查全部照舊通過，檢查數只增不減。
- `scripts/run-all-tests.sh` 的全部 suite 與 `.claude/scripts/tests/spectra-archive-post-ic/test.sh` 通過。
- 對這個 change 的範圍跑 `links` 回 `ok`。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `spec-on-every-issue`: requirement「Added and modified requirements carry an executable check」寫明標記可以在 submodule 的已追蹤檔案裡、讀哪個 commit、submodule 搜尋不了時的結果。

## Impact

- Affected specs: spec-on-every-issue（MODIFIED requirement「Added and modified requirements carry an executable check」）
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/spec-change.py
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-change/test.sh
  - Modified: plugins/issue-driven-dev/references/spec-wrapper.md
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
