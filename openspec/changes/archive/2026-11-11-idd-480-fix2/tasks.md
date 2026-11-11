## 1. spec-change.py

- [x] 1.1 `links`：fence 照 CommonMark 判斷（同一種字元、長度不短於開頭、後面只有空白才關），fence 內的 `##### Example:` 與 `No executable check:` 不算；同一個 capability 裡同名的 requirement 回 `error`（requirement「Added and modified requirements carry an executable check」）。驗證：Example「what the link check reports」新增的四列各一個檢查，先看到失敗。
- [x] 1.2 `preflight`：`.spectra.yaml` 讀不到回 `error`（exit 2，一行 JSON）；`spec_dir` 以 `-` 開頭回 `error`，`git ls-tree` 加 `--`；不用 `--path-format=absolute`（git 2.31 以前沒有）（requirement「A repository without Spectra stops and a third-party clone proceeds」）。驗證：Example「preflight by write access and Spectra state」新增的那一列有檢查，先看到失敗。
- [x] 1.3 `ic`：marker 前有空白時也選得到（requirement「One way to choose the Implementation Complete comment」）。驗證：Example「choosing the Implementation Complete comment」新增的那一列有檢查，先看到失敗。

## 2. skills、契約與文件

- [x] 2.1 preflight 呼叫：契約第 1 步與 `idd-all` Step 3b.0 對沒有輸出、不是 JSON、未知狀態一律停下；兩份從權限到 `--can-write` 的對應一致（requirement「Spec changes go through Spectra behind IDD wrappers」）。驗證：`spec-wrapper-contract` 用假的 `gh` 與不含 `spectra` 的 PATH 實跑兩份區塊，Example「the preflight call routes by permission and Spectra」六列各一個檢查，兩份結果相同。
- [x] 2.2 `idd-close` Step 1.57：`gh repo view` 或 `git fetch` 失敗回 `error`；`--retroactive` 的對照表把 Step 1.57 列為略過（requirement「Close requires the issue's change to be archived」）。驗證：`spec-close-gate` 實跑 Step 1.57 區塊，`gh repo view` 失敗與 fetch 失敗兩種都停下，先看到失敗。
- [x] 2.3 `idd-verify`：只在有 git 範圍時組規格對照；資料包在每次產生的 nonce fence 裡，fence 外是審查規則；DA 的後綴只在組了規格對照時加；`verify-profiles.md` 寫明不變的是 lens 組合與輸入偵測（`idd-verify` 的 requirement「Reviewers check behaviour against the specs」）。驗證：實跑規格對照那段：SHA 空時 `SPEC_BLOCK` 為空、DA 後綴不變；資料裡的 nonce 被中和。
- [x] 2.4 手動的 Spectra 路徑：`idd-diagnose` 的 hand-off 與 `rules/sdd-integration.md` 在 `/spectra-discuss` 之前跑 preflight；checklist 來源的規則寫進 wrapper 那條 requirement；`docs/commands.md` 不再說 close 之後才封存。驗證：`spec-wrapper-contract` 檢查這幾處文字。
