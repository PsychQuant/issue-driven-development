**GitHub-side tracker**: #548

## Problem

這條分支開出之後，預設分支發布了 4.1.0（#547）。4.1.0 的 requirement「spec-change.py reads the repository that holds --cwd」與這條分支第三、四個 change 寫的「The repository's top directory is read as git prints it」說的是同一件事。把預設分支合併進來之後：

1. 規格裡有兩條 requirement 敘述同一個行為，用字不同。
2. 這條分支的那一句寫「帶 `--cwd` 的子命令（`links`、`archived`、`preflight`）」。合併之後帶 `--cwd` 的子命令是五個（4.1.0 加了 `archive-ref` 與 `link-base`），那一句不再完整。
3. CHANGELOG 的 #548 條目還把「`links`、`archived`、`preflight` 照 git 印出的讀頂層目錄」列為這次的改動，而 4.1.0 已經發布了這個行為。

## Root Cause

兩條分支各自修了同一個缺陷（頂層目錄名稱結尾的空白被 `strip()` 去掉），各自加了一條 requirement 與一張 Example 表。git 的合併只能把兩段文字都留下。

## Proposed Solution

- 移除這條分支的 requirement「The repository's top directory is read as git prints it」。已發布的那一條涵蓋它的全部敘述：五個子命令、只去掉 git 加的那一個行尾、名稱可以用空白或換行結尾。
- 這條分支的 Example「top directory names」的六列，改寫成已發布那一條的 Example「a top level whose name ends in whitespace」的三欄格式，接在那張表的後面。已發布的六列不動。
- `tests/spec-change/test.sh` 裡這一段的標記與標題改指向那個 Example。檢查本身不改，數目不變。
- CHANGELOG 的 #548 條目拿掉 4.1.0 已經發布的那一句，改寫成 Example 新增的列。
- `spec-change.py` 不在這個 change 裡改。合併時 `repo_top()` 與 `marker_files()` 讀 git 印出的路徑的兩處已改用 4.1.0 的 `one_line()`，先以 `os.fsdecode` 解碼；這個 change 確認兩處的回傳值與合併前相同。

## Non-Goals

- 不改任何子命令的行為。
- 不為名稱不是合法 UTF-8 的頂層目錄新增 requirement 的文字或列（#559 第 8 點）。
- 不改 4.1.0 的 `archive-ref` 與 `link-base`，也不改 4.1.0 那六列。

## Success Criteria

- 規格裡只有一條敘述頂層目錄讀法的 requirement，它的 Example 有十二列。
- `bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 799 項通過；`bash plugins/issue-driven-dev/scripts/tests/spec-archive-local/test.sh` 全部通過；整套測試通過。
- `spec-change.py links` 從預設分支到這條分支的 HEAD 回 `ok`；`archived` 回 pass。
- `repo_top()` 讀路徑的寫法，合併前後對同一組位元組輸入回傳相同的字串。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `spec-on-every-issue`: 移除 requirement「The repository's top directory is read as git prints it」；requirement「spec-change.py reads the repository that holds --cwd」的 Example 加六列。

## Impact

- Affected specs: spec-on-every-issue（一個 REMOVED requirement、一個 MODIFIED requirement）
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-change/test.sh
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
