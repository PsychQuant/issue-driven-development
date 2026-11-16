## Problem

verify 第 3 輪（#478）判定 FAIL。4 項 Blocking 都在「一張 issue 結束之後、下一張開始之前」：一張 issue 的一般 abort 會在工作樹留下檔案（附件 manifest、spectra artifacts、沒 commit 的改動），rest 第 5 步看到工作樹不乾淨就停下整個 run，之後每次 rest 都停在第一張；只在本機的 `idd/N-*` branch 會讓單張流程在 run 中途提問；direct-commit 下一張停下留下的沒推的 commit，讓之後每一張都推不出去；另一份規格 `idd-existing-work-lookup` 要求 idd-all 接手既有工作，與 rest 的不接手相反。這 4 項在第 1 輪審的版本就已經存在。

## Root Cause

兩張之間只有一段 skill 散文（切回預設 branch、快轉、確認乾淨），沒有程式執行它，也沒有測試在 git repo 裡跑過它；它沒有處理單張流程各種結束方式留下的東西。

## Proposed Solution

- 新的子命令 `rest-queue.py settle`：照一張封閉的表處理工作樹（PR mode 下，這張自己的 branch 上的留下物 commit 在那個 branch；預設 branch 上或別的 branch 上的就停下整個 run；`.claude/.idd/` 底下除了這張的附件一律不 commit；direct-commit 下不乾淨或有沒推的 commit 就停），之後快轉預設 branch。在臨時 git repo 裡測。
- `next` 遇到本機已有 `idd/N-*` branch 的 issue，記為 existing work，不交出。
- `start` 先確認 git 會忽略 run 的狀態檔，不會就停下。
- `idd-existing-work-lookup` 的 requirement 加上 rest mode 的例外；in flight 的處理寫進規格。
- 停止表簡化；狀態檔的驗證、讀渲染的例外、existing work 的報告文字、文件與訊息的小項。

## Non-Goals

- rest 接手既有的工作（#566）。
- 自動把 `.claude/.idd/state/` 加進目標 repo 的 ignore 規則（#564）；這裡只在 `start` 檢查並說明。
- 在交出之後重新分類 in flight 的 issue（列為已知限制）；triage 帳號改 label（#571）。

## Success Criteria

- 臨時 git repo 裡：這張自己的 branch 上的留下物被 commit 在那個 branch、工作樹回到快轉後的預設 branch 且乾淨；預設 branch 上的未追蹤檔讓 `settle` 以 3 結束、不 commit；`.claude/.idd/` 底下不屬於這張附件、也沒被忽略的檔讓 `settle` 以 3 結束、不 commit；direct-commit 下有沒推的 commit 讓 `settle` 以 3 結束。
- 本機有 `idd/5-old` 時，`next` 交出下一張，#5 記為 `existing work: local branch idd/5-old`。
- git 不會忽略 `.claude/.idd/state/` 時，`start` 以 3 結束、不寫任何檔。
- `scripts/tests/rest-queue/test.sh`、`scripts/tests/close-stage/test.sh` 與 `scripts/run-all-tests.sh` 全部通過；每個 Example 都有帶標記的測試。

## Impact

- Affected specs: `idd-all-rest`（修改六條 requirement，新增一條）、`idd-existing-work-lookup`（修改一條）
- Affected code:
  - Modified: plugins/issue-driven-dev/scripts/rest-queue.py
  - Modified: plugins/issue-driven-dev/scripts/close-stage.py
  - Modified: plugins/issue-driven-dev/scripts/tests/rest-queue/test.sh
  - Modified: plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
  - Modified: plugins/issue-driven-dev/CLAUDE.md
  - Modified: plugins/issue-driven-dev/references/usecase-routing.md
  - Modified: docs/commands.md
