**GitHub-side tracker**: #547（設計決定見 issue comment 6869531838；症狀見 #546）

## Problem

`/idd-close` Step 1.57 對宣告了 change 的 issue 一律 `git fetch origin -- <default>`，對 fetch 回來的 commit 跑 `spec-change.py archived`；fetch 失敗就是 `error`、硬性停下。issue 開在 repo A（有 GitHub remote）、程式與規格在 A 底下另一個**刻意沒有 remote** 的本機 git repo B 時，fetch 永遠失敗，這種佈局裡宣告了 change 的 issue 都無法結案，即使 change 已經封存在 B 的預設 branch 上。同一件事也讓 `spec-wrapper.md` 第 5 步的連結檢查找不到起點，`check-existing-work.sh` 在 Step 1.5 多記一筆 `git fetch failed`。

## Root Cause

這三處都假設程式所在的 repo 有一個 remote，預設 branch「以遠端為準」。對沒有 remote 的 repo，這個假設沒有替代：沒有任何方式說「這個 repo 的預設 branch 就是本機的這一條」。

## Proposed Solution

維護者已決定（2026-11-14，issue comment 6869531838）：放寬只能靠設定明確打開，不做自動判斷。

- IDD 設定加欄位 `spec_archive`：一個以「程式 repo 相對於設定檔所在目錄的路徑」為 key 的物件，值是 `{"ref": "local", "branch": "<本機 branch>"}`。設定寫在 issue 所在 repo 的設定檔；從程式 repo 的 top level 往上找第一份 IDD 設定。
- 只在程式 repo **沒有任何 remote** 時接受；有 remote 卻設了，回 `error`。沒有條目時行為完全不變。
- `spec-change.py` 加兩個子命令：`archive-ref`（這個 repo 要用哪個 ref 判定封存：`remote`、`local` 或 `error`）與 `link-base`（本機模式的連結檢查起點：baseline tag → HEAD 歷史中第一個引用 `#N` 的 commit 的父 commit → `error`）。三處共用這兩個子命令，不各寫一份 bash。
- Step 1.57：本機模式用本機 branch 的 commit 跑 `archived`，輸出寫明用的是本機 ref。
- Step 1.5：本機模式呼叫 `check-existing-work.sh --skip-branches`，略過程式 repo 的 fetch 與 branch 列舉、只查 issue repo 的 PR，輸出寫明略過了。
- `spec-wrapper.md` 第 5 步：本機模式用 `link-base` 的起點。
- `config-protocol.md` 記這個欄位。

## Non-Goals

- 自動偵測「沒有 remote」並放寬：維護者選了明確設定。
- `idd-all` direct-commit 的推送、`close-stage.py` 的檢查：推送本來就需要 remote。
- `idd-all` Step 0.5.1、`idd-implement` Step 0.37 呼叫 `check-existing-work.sh` 時的 `unknown`：不擋，只是多一行雜訊。
- 程式 repo 不在 issue repo 底下的佈局：找不到設定，照舊 `error`。
- ASSUMPTION: 不升版號，CHANGELOG 加在既有的 Unreleased 區塊（版號留給 release）。

## Success Criteria

- 新增的測試在改程式之前失敗，改之後通過。
- spec-close-gate、check-existing-work 原有的檢查照舊通過；run-all-tests 的全部 suite 通過。
- 連結檢查對新增與修改的 requirement 回 ok。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `spec-on-every-issue`: 封存檢查的 requirement 加本機模式；新增 requirement 寫明 `spec_archive` 怎麼解析、本機模式的連結檢查起點。
- `idd-existing-work-lookup`: 新增 requirement：helper 可以略過 branch 查詢；idd-close 在本機模式這樣呼叫它。

## Impact

- Affected specs: spec-on-every-issue（MODIFIED「Close requires the issue's change to be archived」；ADDED「A repository without a remote can opt into its local default branch」）、idd-existing-work-lookup（ADDED「The helper can skip the branch lookup」）
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/spec-change.py
  - Modified: plugins/issue-driven-dev/scripts/check-existing-work.sh
  - Modified: plugins/issue-driven-dev/skills/idd-close/SKILL.md
  - Modified: plugins/issue-driven-dev/references/spec-wrapper.md
  - Modified: plugins/issue-driven-dev/references/config-protocol.md
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-close-gate/test.sh
  - Modified: plugins/issue-driven-dev/scripts/tests/check-existing-work/test.sh
  - New: plugins/issue-driven-dev/scripts/tests/spec-archive-local/test.sh
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
