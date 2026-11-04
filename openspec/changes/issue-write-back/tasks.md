## 1. 測試先行（RED）

- [x] 1.1 [P] 新增 `plugins/issue-driven-dev/scripts/tests/issue-write-back/test.sh`，鎖住 #424 的行為契約：規則檔 `plugins/issue-driven-dev/rules/issue-write-back.md` 存在，且寫明 Discussion changes SHALL be written back by kind 的三類分流（問題 → 正文段落、診斷 → Diagnosis 段落、新資訊與決定 → 新 comment，封閉列舉）、兩種觸發（session 討論、issue comment，封閉列舉，對應 D5 別人的 comment 在下一次讀取時觸發）、Only the invoking user's own content SHALL be rewritten 的作者邊界（`validate-target <id> <repo> false --correct`）、回報格式與 privacy 自審；`idd-edit` Step 3 對 `--correct` 不再要求確認、`--prepend-note` 引用嚴格作者檢查；`idd-diagnose` Stage 1 用 `--correct` 且不再寫「追加修正」。驗證：在實作前執行 `bash plugins/issue-driven-dev/scripts/tests/issue-write-back/test.sh`，結果為 FAIL（RED）。
- [x] 1.2 [P] 改寫 `plugins/issue-driven-dev/scripts/tests/in-place-correction/test.sh` 對三個偵測 skill 的斷言，鎖住 Skills that detect errors SHALL apply corrections and report them：`idd-verify`、`idd-diagnose`、`idd-reorganize` 各含 `### Applied Corrections` 與 `--correct`，並反向斷言不再含 `### Proposed Corrections` 與「只列不做」。驗證：實作前執行該測試，三個 skill 的新斷言 FAIL。
- [x] 1.3 [P] 在 `plugins/issue-driven-dev/scripts/tests/session-start-commit-rule/test.sh` 加斷言：hook 輸出含寫回提醒那一行、標題為「IDD 紀律」、總行數仍 ≤5（IDD SessionStart output SHALL carry the write-back reminder within five lines）。驗證：實作前執行該測試，新斷言 FAIL、既有的 ≤5 行斷言仍 PASS。

## 2. 規則與 SessionStart 注入（D3 規則放 plugin 層，SessionStart 加一行）

- [x] 2.1 撰寫 `plugins/issue-driven-dev/rules/issue-write-back.md`：三類分流表與例子、兩種觸發來源（Write-back SHALL be triggered by session discussion and by issue comments）、只改自己的內容（別人的 comment 用 `/idd-comment --type errata`、別人開的 issue 正文用 `--type correction`）、Write-back SHALL NOT ask for confirmation and SHALL be reported（每次一行：類別、目標、連結、backup id）、寫回前的 privacy 自審（`enforce` 命中就不寫）、A corrected diagnosis SHALL update the records that depend on it（Implementation Plan 用 `--correct`，verify 報告依 D2 verify 報告只加一行註記，用 `--prepend-note`）、`Original text` 不動。驗證：任務 1.1 中規則檔相關斷言全部 PASS。
- [x] 2.2 [P] 修改 `plugins/issue-driven-dev/hooks/session-start-commit-rule.sh`：標題改為「IDD 紀律」，第 5 行指向 `rules/issue-write-back.md` 並用一句話說明三類寫回、不確認、只改自己的內容。驗證：`bash plugins/issue-driven-dev/hooks/session-start-commit-rule.sh | wc -l` 為 5，任務 1.3 的測試 PASS。
- [x] 2.3 [P] 在 `plugins/issue-driven-dev/rules/append-vs-modify.md` 寫明討論寫回對應的分類：`--correct` 改段落屬 `in-place-correction`、verify 報告的 `--prepend-note` 註記屬 `audit-block-append`、新決定與資訊屬新增 comment（append），並連到 `issue-write-back.md`；`in-place-correction` 的定義不再要求明確確認（D1）、其他 skill 改為呼叫而非提議（D4）。驗證：`plugins/issue-driven-dev/scripts/tests/issue-write-back/test.sh` 的 append-vs-modify 斷言 PASS，且 `plugins/issue-driven-dev/scripts/tests/in-place-correction/test.sh`、`plugins/issue-driven-dev/scripts/tests/layerv-deferred/test.sh`、`plugins/issue-driven-dev/scripts/tests/authoritative-source-producer/test.sh` 仍 PASS。

## 3. Skill 行為（D1、D1b、D4）

- [x] 3.1 修改 `plugins/issue-driven-dev/skills/idd-edit/SKILL.md`，落實 D1 `--correct` 不再確認，其餘安全步驟保留，即 /idd-edit --correct SHALL replace a bounded region after reporting the preview：Step 3 對 `--correct` 顯示 diff 與完整預覽後直接 apply；privacy 自審命中 `enforce`、或 #272 題答否時 discard，`finish` 以 9 結束。同時落實 D1b `--prepend-note` 只在自己的內容上不確認，即 /idd-edit --prepend-note SHALL skip confirmation only for the invoking user's own content：先跑 `validate-target <id> <repo> false --correct`，exit 0 才略過確認，否則照舊確認。`--append`、`--replace` 照舊確認。frontmatter description 改成與新行為一致；`plugins/issue-driven-dev/skills/idd-comment/SKILL.md` errata 路徑中描述委派 idd-edit 確認的文字同步改為回報。驗證：任務 1.1 的 idd-edit 斷言 PASS；`plugins/issue-driven-dev/scripts/tests/edit-run/test.sh` 與 `plugins/issue-driven-dev/scripts/tests/correct-flow/test.sh` 仍 PASS；`plugins/issue-driven-dev/scripts/tests/skill-description-contract/test.sh` 仍 PASS。
- [x] 3.2 修改 `plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md`，落實 idd-diagnose SHALL correct its own Diagnosis instead of appending a correction：Step 4 Stage 1 要調整診斷時，以 `/idd-edit comment:<Diagnosis id> --correct --section <heading>` 改寫 Diagnosis，再依規則更新 Implementation Plan 與 verify 報告；Step 3.8 依 D4 偵測到錯誤的 skill 直接套用，改為 `### Applied Corrections`（attended 與 unattended 一致、不先問），TaskCreate 的 `propose_corrections` 改名 `apply_corrections` 並更新說明。驗證：任務 1.1 的 idd-diagnose 斷言與任務 1.2 的 idd-diagnose 斷言 PASS。
- [x] 3.3 [P] 修改 `plugins/issue-driven-dev/skills/idd-verify/SKILL.md` Step 3.5：由 Proposed 改為 `### Applied Corrections`，自己的內容呼叫 `/idd-edit ... --correct`、別人的內容貼 errata 或 correction comment，每項列目標、段落、錯在哪、結果（backup id、comment 連結或拒絕原因）；unattended 也直接套用；TaskCreate 同步改名。驗證：任務 1.2 的 idd-verify 斷言 PASS。
- [x] 3.4 [P] 修改 `plugins/issue-driven-dev/skills/idd-reorganize/SKILL.md` Step 3.5，比照任務 3.3 改為 `### Applied Corrections`，TaskCreate 同步改名。驗證：任務 1.2 的 idd-reorganize 斷言 PASS。

## 4. 版本、文件與整體驗證

- [x] 4.1 plugin 版本升到 3.7.0：`plugins/issue-driven-dev/.claude-plugin/plugin.json` 與根目錄 `.claude-plugin/marketplace.json` 一致；`plugins/issue-driven-dev/CHANGELOG.md` 新增 3.7.0 條目（Added：寫回規則與 SessionStart 第 5 行；Changed：`--correct` 不再確認、偵測到錯誤直接套用、idd-diagnose 改寫自己的 Diagnosis），`plugins/issue-driven-dev/README.md` 與根目錄 `README.md` 的說明同步。驗證：`plugins/issue-driven-dev/scripts/tests/doc-sync-sweep/test.sh` 與 `plugins/issue-driven-dev/scripts/tests/docs-catalog-sync/test.sh` PASS，兩個 JSON 以 `python3 -m json.tool` 解析成功且版本皆為 3.7.0。
- [x] 4.2 執行 `bash plugins/issue-driven-dev/scripts/run-all-tests.sh`，全部 suite PASS（GREEN），並執行 `spectra validate issue-write-back` 通過。驗證：兩個指令的輸出與 exit code 0 記錄在 Implementation Complete comment。

## 5. verify 第 1 輪之後（四項決定與 findings）

- [x] 5.1 先寫失敗的測試：`scripts/tests/writeback-candidates/test.sh`（信任分類、自己的不列、日期截止、關閉的 issue、抓取失敗）；`scripts/tests/edit-run/test.sh`（`--note` 與可見文字、其他 mode 給 `--note` 回 2、`discard --reason` 的 finish 報告、exit 9）；`scripts/tests/issue-write-back/test.sh`（定案門檻、信任邊界、寫入權、隱私任何等級都停、idd-close 把可見文字與標記當空白、三個 skill 接上候選清單）；`scripts/tests/in-place-correction/test.sh`（封閉段落、親自查證、別人的內容只列、Outcome 五種）。驗證：實作前跑這四個 suite 都有 FAIL。
- [x] 5.2 落實 A corrected section SHALL carry a visible line 與 /idd-edit SHALL NOT ask questions in unattended mode 的 helper 部分。helper：`--note`、`discard --reason`、路徑閘清單；新增 `scripts/writeback-candidates.py`。驗證：`edit-run`、`writeback-candidates`、`idd-edit` suite 通過。
- [x] 5.3 落實 Decided discussion changes SHALL be written back by kind 與 Write-back SHALL be triggered by session discussion and by trusted comments。改寫 `rules/issue-write-back.md` 與 SessionStart 那一行（定案門檻、信任邊界、寫入權、隱私、被拒時的去處、復原路徑、實作後走 `idd-reorganize`、限自己的報告）。驗證：`issue-write-back`、`session-start-commit-rule` suite 通過。
- [x] 5.4 落實 The target SHALL be re-read before the write、idd-comment errata SHALL route by comment author、Correction targets SHALL be resolved one per iteration、One /idd-edit run SHALL keep its state in the helper 的文字。`idd-edit`：Step 3 依序判斷、unattended 分支、SCRUB=enforce 走確認；`idd-comment` 殘留的確認文字；`idd-close` Residue 判斷忽略可見文字與標記。驗證：`edit-run`、`idd-edit-contract`、`correct-flow`、`issue-write-back` suite 通過。
- [x] 5.5 `idd-verify`、`idd-diagnose`、`idd-reorganize`：封閉段落、親自查證、別人的內容只列、Outcome 五種、獨立的暫存更正檔；`idd-diagnose` attended 在 Stage 1 之後套用；`idd-verify` 的 `EW_SECTIONS` 加 `Applied Corrections`、Step 2.9 比對 issue 的 `updated_at`；`allowed-tools` 補齊。驗證：`in-place-correction`、`verify-external-writes`、`verify-scratch-paths` suite 通過。
- [x] 5.6 落實 in-place-correction SHALL replace errors only after archiving the prior version。`idd-diagnose`、`idd-plan`、`idd-update` 接上 `writeback-candidates.py`；`archive-read-guard.py` 的理由、`append-vs-modify`、`rules-layering` 對照表、README、CHANGELOG 3.7.0、plugin.json 與 marketplace 的說明同步。驗證：`run-all-tests.sh` 全部通過、`spectra validate issue-write-back` 通過。

## 6. verify 第 2 輪之後（觸發移出 idd-update、verify 只列、自動更正限 bug）

- [x] 6.1 先寫失敗的測試，鎖住 Write-back SHALL be triggered by session discussion and by trusted comments、A correction left for a person SHALL block until answered、Skills that detect errors SHALL report them and apply only bounded diagnosis corrections、A corrected section SHALL carry a visible line：`writeback-candidates`（截止點改用自己的 IDD comment、比 `updated_at`、bot 一律 UNTRUSTED、偽造的 Last updated 無效）；`edit-run`（只有標記的替換內容仍回 empty、舊的可見文字被換掉、`--note` 拒絕 `<`、控制字元與行分隔、私人路徑）；`issue-write-back`（`idd-update` 不跑候選、`idd-implement` 跑、`而且`、定案的封閉列舉、被拒的封閉列舉、隱私只看加入的文字）；`in-place-correction`（verify 只列、diagnose 與 reorganize 限 bug、Plan 列出、`--repo`）。驗證：實作前這四個 suite 都有 FAIL。
- [x] 6.2 helper 與 `scripts/writeback-candidates.py`。驗證：`edit-run`、`writeback-candidates`、`correct-flow`、`idd-edit` suite 通過。
- [x] 6.3 落實 SessionStart rule injection is minimal and canonical-aligned 與 idd-update SHALL rebuild Key Decisions from current comments，並照 D6（不問的路徑上，隱私命中一律停；只限有寫入權的 repo）、D7（信任邊界、驗收條件、定案門檻、可見文字）、D8（實作後的更正走 idd-reorganize）、D10 改規則。規則、SessionStart 那一行、`idd-update`（移除 Step 1.1、Step 3 只採受信任作者、`listed` 進 Blocking）、`idd-implement`、`idd-plan`、`idd-diagnose` 的 Step 1.1。驗證：`issue-write-back`、`session-start-commit-rule` suite 通過。
- [x] 6.4 `idd-verify`（Step 3.5 只列、Step 1 記錄需求端基準）、`idd-diagnose` 與 `idd-reorganize`（限 bug、Plan 列出、`--repo`、Stage 1 流程）、`idd-edit`（隱私只看加入的文字、unattended 偵測帶 `--cwd`）、`idd-comment`（errata 帶 `--note`）。驗證：`in-place-correction`、`verify-external-writes`、`edit-run` suite 通過。
- [x] 6.5 CHANGELOG、README、plugin.json 與 marketplace、`append-vs-modify`，`run-all-tests.sh` 全部通過、`spectra validate issue-write-back` 通過。

## 7. verify 第 3 輪之後（拿掉截止點、listed 不擋）

- [x] 7.1 先寫失敗的測試，鎖住 idd-update SHALL read only trusted comments 與更新後的 Write-back SHALL be triggered by session discussion and by trusted comments、Skills that detect errors SHALL report them and apply only bounded diagnosis corrections：`writeback-candidates`（不論日期全部列出）；`edit-run`（替換內容尾端的舊可見行與舊標記都換掉、home 前綴大小寫不同仍拒絕）；`issue-write-back`（`idd-update` 不再把 listed 放進 Blocking、跳過 Comments Not Taken、Comments Not Taken 只寫連結與帳號）；`in-place-correction`（verify 的 Action 是 listed、diagnose 也看 issue 正文、`req_state` 移除）。驗證：實作前這四個 suite 都有 FAIL。
- [x] 7.2 helper、腳本、規則、skill 與文件依 D5、D9 更新。驗證：`run-all-tests.sh` 全部通過、`spectra validate issue-write-back` 通過。

## 8. verify 第 4 輪之後（D11 只留核心）

8.2 撤回了前幾組裡的兩塊，下列項目的內容已不成立，只留作紀錄：1.1 的 comment 觸發、1.2、2.1 的兩種觸發、2.3 的「其他 skill 改為呼叫」、3.3、3.4、5.1 的 `writeback-candidates`、5.3、5.5、5.6 的候選清單接線，以及 6.1 到 7.2 裡關於信任、候選清單、`listed` 與自動更正的部分。

- [x] 8.1 先改測試，鎖住 Decided discussion changes SHALL be written back by kind（別人的 comment 不自動觸發）與 in-place-correction 的 Skills that detect errors SHALL propose corrections, not apply them（選執行後不再問第二次）：刪掉 `scripts/tests/writeback-candidates`；`issue-write-back` 拿掉候選清單、信任表、Comments Not Taken、idd-update 的斷言；`in-place-correction` 的偵測 skill 斷言回到 3.6.0（`### Proposed Corrections`、只列不做），加上「不再寫仍走自己的 preview + confirm」。驗證：改完程式前，`in-place-correction` 對「仍走自己的 preview + confirm」的斷言 FAIL。
- [x] 8.2 照 D11 只留核心（verify 第 4 輪，2026-11-04 維護者決定，comment 6616229678），撤回兩塊：刪掉 `scripts/writeback-candidates.py`；`idd-verify`、`idd-diagnose`、`idd-reorganize`、`idd-plan`、`idd-implement`、`idd-update` 的 SKILL.md 回到 main，只重新套用 `idd-diagnose` Stage 1 的就地改寫與三個偵測 skill 選執行後的那一句；規則、spec、design、proposal、CHANGELOG、README、plugin.json 與 marketplace 同步。驗證：`run-all-tests.sh` 全部通過、`spectra validate issue-write-back` 通過。

## 9. verify 第 5 輪之後（D12 再拿掉三樣、實作後同 PR 就地寫回）

- [x] 9.1 先改測試，鎖住 A corrected diagnosis SHALL update the records that depend on it（verify 報告不動、同 PR 跟著改就就地寫回）與 in-place-correction 的 Skills that detect errors SHALL propose corrections, not apply them（run-now 問句附替換全文、引數帶 `--repo`）：`issue-write-back` 拿掉 verify 註記、`--prepend-note` 不問、unattended 的斷言，改成反向斷言；`edit-run` 拿掉私人路徑與 `discard --reason` 的區塊；`append-vs-modify` §8 的斷言改回 main 的提議寫法。驗證：把新測試放到 353f686 上跑，這些斷言 FAIL；改完後通過。
- [x] 9.2 照 D12（verify 第 5 輪，2026-11-04 維護者決定，comment 6617788666）撤回 D1b、D2（第 5 輪撤回，見 D12）：helper 拿掉私人路徑閘與 `discard --reason`、`finish` 的 HELD；`idd-edit` Step 3 拿掉 unattended 偵測與 `--prepend-note` 的不問分支；`idd-comment` 的 errata 指標回到 main；規則、spec、design、proposal、`append-vs-modify`、CHANGELOG、README、plugin.json 與 marketplace 同步。驗證：`run-all-tests.sh` 全部通過、`spectra validate issue-write-back` 通過。
- [x] 9.3 第 5 輪的 LOW：先在 `edit-run` 加測試（替換文字中間的舊可見文字、只有別的 mode 標記的替換內容），再改 helper（每一行舊可見文字都移除，只有 IDD 標記的替換內容算空）；規則指明 Diagnosis 是最新一則你自己寫的、Spectra tier 用 `/spectra-ingest`；`idd-diagnose` Stage 1 只改剛貼出的那一則、allowed-tools 補上 Skill、Write、mktemp；CHANGELOG 補上 `idd-issue` 的 edit body。驗證：`edit-run`、`issue-write-back` 通過。

## 10. verify 第 6 輪之後（D13 兩處都寫、可見文字拿掉「AI 判斷」）

- [x] 10.1 先改測試，鎖住 Decided discussion changes SHALL be written back by kind（改了診斷的決定兩處都寫）與 A corrected section SHALL carry a visible line（新格式、結尾以外的舊行拒絕、code fence 裡的同形文字保留）：`edit-run` 改可見文字的斷言並加 fail-closed 與 code fence 的案例；`issue-write-back` 加兩處都寫、Diagnosis 目標、實作之後沒有 PR 承載、依編號採納、寫回目錄的斷言。驗證：把新測試放到 f9a7322 上跑，這些斷言 FAIL；改完後通過。
- [x] 10.2 照 D13（verify 第 6 輪，2026-11-04 維護者決定，comment 6619279709）改 helper、規則、spec、`append-vs-modify`、`idd-edit`、三個偵測 skill、`idd-reorganize`、`idd-issue`、hook、CHANGELOG 與文件。驗證：`run-all-tests.sh` 全部通過、`spectra validate issue-write-back` 通過。

