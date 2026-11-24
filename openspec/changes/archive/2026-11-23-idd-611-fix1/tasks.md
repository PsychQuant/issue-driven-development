## 1. 測試（先寫）

- [x] 1.1 requirement「Change metadata carries no author address」的 Example「the wrapper's two calls」：在 plugins/issue-driven-dev/scripts/tests/spec-change/test.sh 加檢查。第 4 節要有呼叫，位置在 `spectra unpark` 那一行之後、呼叫 `spectra-apply` 那一行之前。驗證：ba49f74f 上失敗，2.1 之後通過。
- [x] 1.2 同一個 requirement 的 Example「the close-out order restated by idd-implement and idd-all」：加兩項檢查。idd-all Step 3b.4 的呼叫要在 `Skill(skill="spectra-apply"` 之前；idd-implement 同時寫到 `spectra unpark` 與 `spectra-apply` 的那一行，要在兩者之間寫 `scrub-authors`。驗證：ba49f74f 上失敗，2.2 之後通過。

## 2. 實作

- [x] 2.1 plugins/issue-driven-dev/references/spec-wrapper.md 第 4 步：在 unpark 的 bash 區塊之後、呼叫 `spectra-apply` 之前，寫一句跑 scrub-authors，並寫明原因：park 會把 change 移到工作樹之外。不新增 bash 區塊。驗證：1.1 通過，spec-wrapper-contract 套件通過。
- [x] 2.2 plugins/issue-driven-dev/skills/idd-implement/SKILL.md 重述第 4 步的那一行，以及 plugins/issue-driven-dev/skills/idd-all/SKILL.md 的 Step 3b.4：加上這次呼叫。驗證：1.2 通過。

## 3. 全部測試

- [x] 3.1 spec-change、spec-wrapper-contract、spec-archive-local 三個套件通過，run-all-tests.sh 也通過。
