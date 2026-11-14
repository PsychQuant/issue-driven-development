## 1. 測試先行

- [x] 1.1 requirement「A repository without a remote can opt into its local default branch」— spec-archive-local：Example「how a spec_archive entry resolves」改動與新增的列（讀不了的設定回 remote、BOM、重複 key、revision 語法、空白 key、沒有 URL 的全域 remote 區段、linked worktree、新檔先於舊檔、HOME 以上不讀），帶標記 spec-example: spec-on-every-issue / how a spec_archive entry resolves。驗證：改之前新的列失敗。
- [x] 1.2 spec-archive-local：Example「where the local link check starts」新增的列（remote 時不讀 `--issue`、左邊界、baseline 不是祖先時的退路、`baseline_format`、0x1e），並檢查 spec-wrapper 第 5 步呼叫 `link-base`，帶標記 spec-example: spec-on-every-issue / where the local link check starts。驗證：改之前新的列失敗。
- [x] 1.3 requirement「Close requires the issue's change to be archived」— spec-close-gate：Example「the close gate reads the default branch」新增的兩列（HEAD 在 issue branch、沒有條目），測試設 HOME；remote 而 fetch 失敗時原因帶出 archive-ref 的說明；本機模式訊息不含設定檔路徑。驗證：改之前 HEAD 那一列與原因那一項失敗。
- [x] 1.4 check-existing-work：Step 1.5 在本機模式真的把 `--skip-branches` 傳給 helper（`EW_JSON` 有 notes），open PR 仍被算到；重複 `--cwd` 回 2。驗證：拿掉旗標的變異會失敗。

## 2. 程式

- [x] 2.1 `spec-change.py` 照 requirement 改 `archive-ref` 與 `link-base`。驗證：1.1、1.2 通過；spec-change suite 照舊。
- [x] 2.2 `check-existing-work.sh` 拒絕重複的 `--cwd`。驗證：1.4 通過。

## 3. skill 與文件

- [x] 3.1 idd-close Step 1.57 的原因與本機訊息。驗證：1.3 通過。
- [x] 3.2 spec-wrapper 第 5 步（`${NUMBER:-${N:-}}`、錯誤訊息）、idd-all Step 3b.6 補一句。驗證：spec-wrapper-contract 照舊。
- [x] 3.3 config-protocol 與 CHANGELOG。驗證：git diff 只改這一節與 Unreleased。

## 4. 收尾

- [x] 4.1 跑 run-all-tests.sh 與連結檢查。驗證：結束碼 0，links 回 ok。
