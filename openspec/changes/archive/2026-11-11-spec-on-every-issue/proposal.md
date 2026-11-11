## Why

IDD 目前只有 Spectra tier 的 issue 會留下規格。Simple 與 Plan 的設計決定留在 issue 留言、程式與測試裡，之後的改動沒有東西可以對照。verify 也因此沒有固定的對象：#405 與 #351 都出現過某一輪沒有 HIGH、之後幾輪又找到 HIGH 的情況，後來的 HIGH 有一部分出在先前的修正上。維護者在 2026-11-10 決定：每一張 issue 不論 tier 都要更新規格，而且每一條新增或改到的 requirement 都要附一個可執行的檢查（#480 的 Diagnosis 與五則 Decision comment）。

## What Changes

- **BREAKING**：Simple 與 Plan 的 issue 也會產生一個 Spectra change（proposal、spec delta、tasks），並在 branch 上封存。現在這兩個 tier 的流程完全不碰規格目錄。
- Simple 走輕量形式：不做 discuss、不寫 design，只寫短的 proposal、spec delta 與 tasks，接著 apply。
- Plan 保留 IDD 自己的入口（plan skill）：attended 時計畫的核准留在 IDD 這一層，核准的對象是同一套包裝產生的 proposal 與 tasks。
- 規格的產生一律經過 IDD 的包裝（實作 skill 與 plan skill，加上一份共用的契約文件），其他 skill 不直接依賴 Spectra 的 skill 介面。
- 封存改在 branch 上、verify 之前做，三個 tier 都一樣。被審查的 commit 就帶著套用後的規格，合併後不再補封存 commit。
- 每一張實作過的 issue，Implementation Complete 留言都有一行宣告：寫了哪些 change，或「不改變行為」，或「第三方的 clone」。Spectra tier 現在不貼這則留言，之後也會貼。
- 「不改變行為」只在四種情況成立（封閉列舉）：只改沒有東西會執行的文件、一次性分析、只改測試或 CI 設定、行為完全不變的重構。宣告由 verify 審。
- 新增一支腳本，集中四個機械判定：能不能開始寫規格（含沒有 Spectra、linked worktree、第三方 clone）、讀宣告行、宣告的 change 在某個 commit 上是否已封存、新增或改到的 requirement 是否都有 Example 與指名它的測試。
- verify 的 Regression lens 拿規格當對照：範圍內的行為改動沒有任何 requirement 寫到，是 HIGH；宣告「不改變行為」而有行為改動，也是 HIGH。連結檢查與封存檢查的失敗列為 Blocking。
- verify 之後的修正走同一個包裝：新增或修改 requirement 的修正，是這張 issue 的另一個 change；Blocking 的修正要留下一條寫出該性質的 requirement、Example 與修正前會失敗的測試。
- 自己的 repo 沒有 Spectra（沒有 CLI 或沒有規格目錄）或工作樹是 linked worktree 時停下並說明；第三方的 clone 不寫規格，照現在的方式跑。
- 結案前檢查這張 issue 宣告的 change 在預設 branch 上已經封存。

## Capabilities

### New Capabilities

- `spec-on-every-issue`: 每一張實作過的 issue 都留下規格改動或一個宣告過的豁免；規格改動經由 IDD 的包裝走 Spectra；在 branch 上、verify 之前封存；新增或改到的 requirement 有可執行的檢查；verify 之後的修正走同一條路；沒有 Spectra 時的行為；結案前的封存檢查。

### Modified Capabilities

- `idd-verify`: 新增一條 requirement，reviewer 拿規格檢查範圍內的行為改動，並把連結檢查與封存檢查的結果列入報告。

## Impact

- Affected specs: `spec-on-every-issue`（新增）、`idd-verify`（新增一條 requirement）
- Affected code:
  - New:
    - plugins/issue-driven-dev/scripts/spec-change.py
    - plugins/issue-driven-dev/scripts/tests/spec-change/test.sh
    - plugins/issue-driven-dev/references/spec-wrapper.md
  - Modified:
    - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
    - plugins/issue-driven-dev/skills/idd-plan/SKILL.md
    - plugins/issue-driven-dev/skills/idd-all/SKILL.md
    - plugins/issue-driven-dev/skills/idd-verify/SKILL.md
    - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
    - plugins/issue-driven-dev/skills/idd-close/SKILL.md
    - plugins/issue-driven-dev/rules/sdd-integration.md
    - plugins/issue-driven-dev/references/verify-profiles.md
    - plugins/issue-driven-dev/references/usecase-routing.md
    - plugins/issue-driven-dev/README.md
    - plugins/issue-driven-dev/CHANGELOG.md
  - Removed: (none)
- Dependencies: Spectra 的 CLI 與它在 repo 裡產生的 propose、apply、verify skill，從只有 Spectra tier 用到，變成每一張實作的 issue 都用到。
