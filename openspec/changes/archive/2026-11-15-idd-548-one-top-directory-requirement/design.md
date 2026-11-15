## Context

這條分支從 `6ed8dec` 分岔。之後預設分支多了兩個 commit：#547 的功能與 4.1.0 的發布。把預設分支合併進這條分支時有兩處衝突，合併 commit 這樣處理：

- 規格：兩邊各在檔案結尾加了 requirement。合併 commit 把兩段都留下（4.1.0 的兩條在前，這條分支的一條在後），沒有改任何一句。
- `spec-change.py`：兩邊都改了 `repo_top()` 的回傳。4.1.0 寫成 `one_line(p.stdout.decode("utf-8"))`，這條分支寫成先在位元組上去掉一個行尾、再 `os.fsdecode`。合併 commit 寫成 `one_line(os.fsdecode(p.stdout))`，`marker_files()` 裡同樣的一處也改用 `one_line()`。
- CHANGELOG：git 把 #548 的條目自動併進了 4.1.0 的段落。合併 commit 把它移到新的 `[Unreleased]` 段落，4.1.0 的段落與預設分支逐字相同。

合併 commit 之後，規格裡有兩條 requirement 說同一件事。這個 change 處理的是這一點。

量測（協調者，git 2.55.0，macOS，Python 的檔案系統編碼是 utf-8 加 surrogateescape）：十組位元組輸入（結尾一個換行、空白加換行、兩個換行、沒有換行、空的、只有換行、不合法的 UTF-8 位元組、中文、CR 加 LF、不合法位元組加兩個換行），「先在位元組上去掉一個行尾再 `os.fsdecode`」與「`one_line(os.fsdecode(...))`」回傳相同的字串。

## Goals / Non-Goals

Goals：

- 規格對頂層目錄的讀法只說一次，而且說的是合併後的五個子命令。
- 這條分支為這個行為寫的檢查全部留下，並且仍然連到一個 Example。

Non-Goals：

- 不改行為、不改 4.1.0 已發布的文字與六列。
- 不處理名稱不是合法 UTF-8 的頂層目錄的規格文字（#559）。

## Decisions

### 留已發布的那一條，移除這條分支的那一條

4.1.0 的那一條已經發布，涵蓋五個子命令；這條分支的那一條只列三個，而且每一句都被前者涵蓋（只去掉 git 加的那一個行尾；名稱可以用空白或換行結尾；三個子命令讀法相同，是「每個子命令都照 git 印出的讀」的特例）。所以移除的是這條分支的那一條。反過來做（留這條分支的、改 4.1.0 的）會改寫已經發布的句子，沒有必要。

### 六列搬過去，一列一列寫，不合併

這條分支的六列比 4.1.0 的六列多固定了三件事：`links` 在名稱以空白結尾時回 `ok`（4.1.0 的列是 `missing`）、`links` 與 `preflight` 在名稱以換行結尾時的答案、以及答案與「同一個 repo 放在一般名稱底下」逐字相同。六列各自對應測試檔裡既有的檢查，所以一列一列寫，不併成較少的列。每一列的 Result 只寫測試實際比對的東西：`preflight` 在換行那一列比對的是 `status` 與結束碼相同，不另外斷言 `ready`。

### 標記改指向已發布的 Example，不讓兩個 Example 並存

移除 requirement 之後，Example「top directory names」不存在了，`tests/spec-change/test.sh` 檔頭的標記與這一段的標題改成 Example「a top level whose name ends in whitespace」。同一個 Example 因此在兩個測試檔各有一個標記（另一個在 `tests/spec-archive-local/test.sh`），連結檢查只要求至少一個。斷言的名稱（`top directory names: ...`）不改，它們只是訊息。

### 讀 git 印出的路徑只用一個 helper

合併後 `spec-change.py` 裡去掉 git 行尾的函式只有 4.1.0 的 `one_line()`。這條分支原本在兩處各寫一次同樣的運算式，合併 commit 把它們改成呼叫 `one_line()`。解碼仍用 `os.fsdecode`：這是這條分支第三個 change 的行為（名稱不是合法 UTF-8 時不以 traceback 結束），4.1.0 的寫法在這種輸入上會丟出解碼錯誤。這個 change 不改這兩處，只記錄並確認回傳值相同（見 Context 的量測）。

## Implementation Contract

- `openspec/specs/spec-on-every-issue/spec.md`（由封存套用）：requirement「The repository's top directory is read as git prints it」連同它的 Scenario 與 Example 不再存在；requirement「spec-change.py reads the repository that holds --cwd」的敘述與 Scenario 逐字不變，Example「a top level whose name ends in whitespace」在原有六列之後多六列。
- `plugins/issue-driven-dev/scripts/tests/spec-change/test.sh`：檔頭的 `spec-example:` 那一行與這一段的 `echo` 標題改名；不新增、不移除、不改任何斷言。
- `plugins/issue-driven-dev/CHANGELOG.md`：只動 `[Unreleased]` 裡 #548 那一條的最後一句。
- 驗證：`tests/spec-change/test.sh` 799 項通過；`tests/spec-archive-local/test.sh` 通過；`run-all-tests.sh` 結束碼 0；`links --base origin/main` 回 `ok`；`archived` 回 pass。

## Risks / Trade-offs

- 被移除的 requirement 是這條分支第三、四個 change 的 delta 寫的。那兩個封存的 change 不改；這個 change 的 delta 記錄它被移除與原因。
- 兩個測試檔標記同一個 Example：其中一個被刪掉時，連結檢查不會發現另一半的列少了檢查。這是連結檢查既有的粒度（每個 Example 至少一個標記），不是這次造成的。

## Migration Plan

不需要。沒有行為改變，沒有設定或資料要搬。

## Open Questions

沒有。名稱不是合法 UTF-8 的頂層目錄要不要寫進 requirement，在 #559。
