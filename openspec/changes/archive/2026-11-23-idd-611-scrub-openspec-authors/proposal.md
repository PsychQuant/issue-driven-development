**GitHub-side tracker**: #611

## Problem

`spectra new change` 與 `spectra archive` 會把 git 作者的 email 寫進 `<spec dir>/changes/<名稱>/.openspec.yaml`，寫法是 `created_by: <名字> <<email>>` 與 `archived_by: <名字> <<email>>`。spec wrapper 在第 3 步與第 5 步 commit 這些檔，中間沒有任何一步看過它們（#611）。repo 沒有自己的檢查時，email 就會進到 tree 裡。

## Root Cause

wrapper 把 Spectra 的 metadata 當成不透明的檔案：從 Spectra 寫出它，到 commit 帶走它，中間沒有一步。

## Proposed Solution

- 新增 `spec-change.py scrub-authors --cwd <dir>`：在 `<spec dir>/changes/` 底下，對每一個未追蹤或與 HEAD 不同的 `.openspec.yaml`，把行尾帶角括號 email 的 `created_by`、`archived_by` 改成只剩欄位與名字；其他位元組不動；用一行 JSON 回報改了哪些檔。
- wrapper 在兩處跑它，都在 commit 之前：
  - 第 3 步：change 建立之後、任何 commit 之前；
  - 第 5 步：`spectra archive` 之後、封存 commit 之前。
  兩處都印出拿掉了哪些檔，回報不是 `ok` 就停下。
- 維護者 2026-11-23 的兩個決定：每個 repo 都跑，不看公開或私有；自己拿掉並回報，不停下來請人處理。

## Non-Goals

- 改寫已經 commit 的 metadata（封存的歷史）。
- `created_by`、`archived_by` 以外的欄位。
- 改 Spectra 本身。

## Success Criteria

- 新 requirement 的四個 Example 在 spec-change suite 裡各有測試，實作之前會失敗，實作之後通過。
- wrapper 第 3 步（含沿用開著的 change）與第 5 步在 commit 之前呼叫這個子命令；idd-implement 與 idd-all 重述收尾順序的地方、idd-all 自己的 propose 之後也都呼叫它。

## Impact

- Affected specs: spec-on-every-issue（新增 requirement）
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/spec-change.py
  - Modified: plugins/issue-driven-dev/references/spec-wrapper.md
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-change/test.sh
  - Modified: plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - Modified: plugins/issue-driven-dev/skills/idd-all/SKILL.md
