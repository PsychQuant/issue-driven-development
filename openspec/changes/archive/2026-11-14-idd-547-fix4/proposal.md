## Why

第 4 輪 verify（#547 comment 6879033245）判定 PASS、0 Blocking，但有 4 列 MEDIUM 的 In-scope fix：`remotes_of()` 用去掉空白後的值判斷 remote 是否存在（url 設成空白或空字串時漏算）、`repo_top()` 去掉所有結尾換行而不是只去 git 加的那一個、幾列 Example 的測試只驗 status、spec-wrapper 第 5 步的 remote 路徑沒有測試。另有 7 列 LOW／INFO：規格兩處對 `has_remote` 的說法不一致、主工作樹的規則沒有寫出 `.git` 命名與 submodule 的情況、bare 主 repo 沒有寫明、第 5 步 fetch 失敗時丟掉 `link-base` 的原因，以及 docstring 與 issue 文字。

## What Changes

- `has_remote` 正好是 true 才 fetch，close 與 archive-ref 兩條 requirement 說法一致。
- remote 是否存在看 `url`、`pushurl`、`vcs` 是否設定，不看值。
- 主工作樹：照實寫出 git 不記錄主工作樹的兩種情況（其他名稱的 separate git dir、submodule），以及 `.git` 命名時 git 回報的路徑；bare 主 repo 的 linked worktree 以自己的路徑為 key。
- 讀 git 印出的路徑只去一個結尾換行；Example 補換行結尾與 `preflight` 的列。
- 第 5 步 fetch 失敗時附上 `link-base` 的原因。

## Impact

- `plugins/issue-driven-dev/scripts/spec-change.py`、`references/spec-wrapper.md`、`references/config-protocol.md`、`CHANGELOG.md`
- 測試：`scripts/tests/spec-archive-local`、`spec-close-gate`、`check-existing-work`
