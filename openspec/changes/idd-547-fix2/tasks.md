## 1. 測試先行

- [x] 1.1 requirement「A repository without a remote can opt into its local default branch」— spec-archive-local：Example「how a spec_archive entry resolves」與「where the local link check starts」新增的各列（`.` 不再是退路、字面重複的 key、只有 pushurl、舊式 remotes 檔、separate-git-dir、`github_repo` 的 `owner/repo#N`、tag 在 HEAD、簽章、名為 HEAD 的檔），帶兩個既有標記。驗證：改之前新的列失敗。
- [x] 1.2 check-existing-work：`--skip-branches` 不跑 fetch、不讀 tracking ref（git shim 記錄呼叫，tracking ref 不產生 E4）；既有 Step 1.5 列設 HOME；Step 1.5 在 archive-ref 回 error 時不帶旗標；拿掉永遠不會失敗的斷言。驗證：帶旗標仍 fetch 的變異會失敗。
- [x] 1.3 spec-close-gate：「沒有條目」列驗原因含「default branch could not be read」；與設定無關的錯誤標 `archive-ref:`；原因不含設定檔的絕對路徑。

## 2. 程式與文件

- [x] 2.1 `spec-change.py` 照 requirement 改。驗證：1.1 通過；spec-change suite 照舊。
- [x] 2.2 idd-close Step 1.5／1.57（`python3 -I`、原因標籤、error 表說明）、spec-wrapper 第 5 步（`python3 -I`、說明文字）。驗證：1.2、1.3 通過；spec-wrapper-contract 照舊。
- [x] 2.3 config-protocol 的矛盾句與新規則、CHANGELOG。

## 3. 收尾

- [ ] 3.1 run-all-tests.sh 與連結檢查。驗證：結束碼 0，links 回 ok。
