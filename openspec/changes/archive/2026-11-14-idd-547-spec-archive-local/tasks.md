## 1. 測試先行

- [x] 1.1 `spec_archive` 的解析：依 requirement「A repository without a remote can opt into its local default branch」的 Example「how a spec_archive entry resolves」，新 suite spec-archive-local 對 `spec-change.py archive-ref` 跑 Example 十一列，測試檔帶標記 spec-example: spec-on-every-issue / how a spec_archive entry resolves。驗證：改 spec-change.py 之前失敗（子命令不存在）。
- [x] 1.2 本機模式的連結檢查起點：依同一條 requirement 的 Example「where the local link check starts」，spec-archive-local 對 `spec-change.py link-base` 跑 Example 五列，帶標記 spec-example: spec-on-every-issue / where the local link check starts。驗證：改之前失敗。
- [x] 1.3 封存檢查的本機模式：依 requirement「Close requires the issue's change to be archived」的 Example「the close gate reads the default branch」新增的三列，spec-close-gate 照 SKILL.md 原文執行 Step 1.57 的區塊（有設定、沒有 remote 的 repo），帶既有標記。驗證：改 SKILL.md 之前，新的三列失敗；原有各列照舊通過。
- [x] 1.4 略過 branch 查詢：依 requirement「The helper can skip the branch lookup」的 Example「the branch lookup can be skipped」，check-existing-work suite 跑三列，並檢查 idd-close Step 1.5 在本機模式帶 `--skip-branches`，帶標記 spec-example: idd-existing-work-lookup / the branch lookup can be skipped。驗證：改之前失敗。

## 2. 程式

- [x] 2.1 `spec-change.py` 加 `archive-ref` 與 `link-base` 子命令（docstring 一併更新）。驗證：1.1、1.2 通過；spec-change suite 照舊通過。
- [x] 2.2 `check-existing-work.sh` 加 `--skip-branches`。驗證：1.4 的 helper 部分通過；check-existing-work 原有各項照舊通過。

## 3. skill 與文件

- [x] 3.1 idd-close Step 1.57：宣告了 change 時先問 `archive-ref`，`local` 用回傳的 commit 並印出本機 ref，`remote` 照舊 fetch，`error` 停下。驗證：1.3 通過；spec-close-gate 原有的文字檢查照舊通過。
- [x] 3.2 idd-close Step 1.5：`archive-ref` 回 `local` 時帶 `--skip-branches` 並印出說明。驗證：1.4 的 skill 部分通過。
- [x] 3.3 spec-wrapper.md 第 5 步：先問 `link-base`，`ok` 用它的起點、`remote` 照舊、`error` 停下。驗證：spec-wrapper-contract suite 照舊通過。
- [x] 3.4 config-protocol.md 加 `spec_archive` 欄位一節（key 的算法、只在沒有 remote 時接受的理由、找不到設定時照舊）。驗證：git diff 只有新增。

## 4. 收尾

- [x] 4.1 CHANGELOG 的 Unreleased 加 Added 條目（#547）。驗證：已發布版本的條目沒有改動。
- [x] 4.2 跑 run-all-tests.sh 與連結檢查。驗證：結束碼都是 0，links 回 ok。
