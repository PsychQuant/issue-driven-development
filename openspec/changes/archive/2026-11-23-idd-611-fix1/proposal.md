**GitHub-side tracker**: #611

## Problem

`spectra-propose` 結束時會 park change，而 `spectra park` 會把 change 移出工作樹，放到 `.git/spectra-app/changes/<名稱>/`。所以第 3 步呼叫 `scrub-authors` 時什麼都找不到。到了第 4 步，unpark 把 change 移回 `<spec dir>/changes/`，地址還在裡面。apply 期間如果有 commit，就可能在第 5 步拿掉地址之前把它帶進 repo。這個問題是 verify 之後，實際 park 一個臨時 change 才發現的。

## Root Cause

wrapper 假設 change 從 propose 到 apply 一直留在 `<spec dir>/changes/`。

## Proposed Solution

- wrapper 第 4 步在 unpark 之後、`spectra-apply` 之前跑 `scrub-authors`。呼叫寫成一句文字，不另加 bash 區塊，因為其他套件會照原文執行第 4 步的第一個 bash 區塊。
- `idd-implement` 重述第 4 步的地方寫明同一件事。
- `idd-all` 的 Step 3b.4 在 `spectra-apply` 之前跑它。

## Non-Goals

- 改變 Spectra park change 的位置。

## Success Criteria

- 第 4 步、`idd-implement` 與 `idd-all` 的順序檢查在 ba49f74f 上失敗，修正後通過。

## Impact

- Affected specs: spec-on-every-issue（一條 MODIFIED requirement）
- Affected code:
  - Modified: plugins/issue-driven-dev/references/spec-wrapper.md
  - Modified: plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - Modified: plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-change/test.sh
