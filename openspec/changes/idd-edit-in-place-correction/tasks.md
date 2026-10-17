## 1. 先寫會失敗的測試（TDD RED）

- [x] 1.1 建立 `plugins/issue-driven-dev/scripts/tests/in-place-correction/test.sh`，涵蓋：`parse-args` 接受 `--correct` 與 `issue:<N>`、正文用 whole scope 回 exit 3、`--correct` 併用 `--override-user-content` 回 exit 2（Requirement: /idd-edit --correct SHALL replace a bounded region after explicit confirmation；Requirement: /idd-edit SHALL refuse modifications to user-authored comments）；`check-correction` 對 design 四列範例的結果、受管區（含目標段落包含 `### Clarity Surface` 的情形）exit 6 並指名 `idd-update`／`idd-clarify`（Requirement: Protected regions SHALL NOT be corrected）；標記格式不含 `/`、`emit-audit-marker` 對不合格 `backup-id` 回 exit 2、標記位於被取代區段最後一行（Requirement: Correction marker SHALL carry only the backup id and sit at the end of the replaced region）；規則檔恰有 8 個類別、`in-place-correction` 段落含至少 2 個範例、`verbatim-preserve` 只列兩種內容（Requirement: Canonical category enumeration SHALL be normative；Requirement: verbatim-preserve SHALL cover only original-source quotations and third-party content）；`idd-edit` SKILL.md 含 `(category: in-place-correction)`；`idd-comment` errata 段落依作者分流；`idd-verify`、`idd-diagnose`、`idd-reorganize` 各含 `### Proposed Corrections` 且 unattended 只列不做。驗證：執行該 suite，每個斷言都以「尚未實作」的理由失敗，並記下失敗數。
- [x] 1.2 建立 `plugins/issue-driven-dev/scripts/tests/correction-archive/test.sh`，在暫存 git repo 中涵蓋：`archive` 的命名、同秒碰撞加 `-2`、既有檔 byte 不變、stdout 只有 backup-id（Requirement: Archive entries SHALL be written once under a fixed local path）；`.git/info/exclude` 寫入、`!` re-include 時 exit 7、非 git 目錄 exit 7（Requirement: Archive entries SHALL never be tracked by git）；檔案權限 `0000` 且 `grep -r` 讀不到內容（Requirement: Archive files SHALL be unreadable at rest）；`restore` 的路徑穿越 exit 2、檔案不存在 exit 5、以 PATH 上的 stub `gh` 驗證 stdin 內容正確且 stdout 不含歸檔文字、失敗後權限回到 `0000`（Requirement: Restore SHALL return a target to its archived version without displaying the content）；hook 對 Read／Grep／Glob（`path` 與 `pattern`）／Edit／Write／NotebookEdit／Bash／PowerShell 的 deny、大小寫與 `./` 變體的 deny、對 helper 指令與無關檔案的 allow、輸入無法解析時 allow；`idd-edit` SKILL.md 的 fenced bash 不含歸檔路徑字面值（Requirement: A PreToolUse hook SHALL deny Claude tool access to the archive）。驗證：執行該 suite，斷言以「尚未實作」失敗。

## 2. 規則檔

- [x] 2.1 [P] 在 `plugins/issue-driven-dev/rules/append-vs-modify.md` 新增第 8 類 `in-place-correction`（定義、範圍邊界、至少 2 個範例：`idd-edit --correct` 更正 Diagnosis 段落、更正正文 `## Expected`），把 `verbatim-preserve` 縮成 `Original text` 引用區塊與非 OWNER 非 bot comment，decision tree 加上「內容確定錯誤且已確認 → in-place-correction」分支，文中「7 類」改為「8 類」（設計：新增第 8 類 in-place-correction，不放寬既有類別；Requirement: Every modify-action SHALL declare a scope category；Requirement: Undeclared modify-actions SHALL be refused (default-refuse)；Requirement: in-place-correction SHALL replace confirmed errors only after archiving the prior version）。驗證：1.1 中規則檔相關斷言轉綠。

## 3. helper（`plugins/issue-driven-dev/scripts/idd-edit-helper.py`）

- [x] 3.1 `parse-args` 新增 `--correct` 模式與 `issue:<N>` target，輸出 `MODE=correct`、`TARGET_KIND`；新增 `check-correction <old-file> <section|-> <new-file>` 子命令，實作受管區拒絕（含包含關係）與 verbatim 區塊逐 byte 比對；`emit-audit-marker` 對 `backup-id` 做格式驗證（設計：--correct 是獨立模式，不是 --replace 加旗標；設計：正文目標只接受 --section，並拒絕保護區）。驗證：1.1 的 parse-args 與 check-correction 斷言轉綠，既有 `scripts/tests/idd-edit/test.sh` 維持全綠。
- [x] 3.2 新增 `archive <comment|issue> <id> --from-file <path>` 子命令（原文檔不可讀 exit 5）：以 `scripts/git-ignore-block.sh --direction exclude` 寫入 `.git/info/exclude`、以 `git check-ignore` 驗證、exclusive create 與碰撞後綴、寫入後 `chmod 0000`、stdout 只印 backup-id（設計：歸檔寫進 .git/info/exclude，不改 tracked 的 .gitignore；設計：雙層擋讀：hook 加上檔案權限 0000）。驗證：1.2 的 archive 相關斷言轉綠。
- [x] 3.3 新增 `restore <backup-id> --repo R` 子命令：id 格式驗證、從 id 推出目標、暫時 `chmod u+r` 後經 stdin 交給 `gh api -X PATCH -F body=@-`、`finally` 設回 `0000`、stdout 只印目標 URL 與 byte 數（設計：還原整個目標，內容不經 stdout）。驗證：1.2 的 restore 斷言轉綠。

## 4. 擋讀 hook

- [x] 4.1 [P] 新增 `plugins/issue-driven-dev/hooks/archive-read-guard.py`（stdlib `json`，命中時輸出 `permissionDecision: "deny"` 與說明還原方式的理由、exit 0；無法解析時放行並寫一行 stderr），並在 `plugins/issue-driven-dev/hooks/hooks.json` 以 matcher `Read|Grep|Glob|Edit|Write|NotebookEdit|Bash|PowerShell` 註冊 PreToolUse，保留既有 SessionStart（設計：hook 以 Python 實作，輸入無法解析時放行）。驗證：1.2 的 hook 斷言轉綠；`python3 -m json.tool` 解析 hooks.json 成功；`scripts/tests/session-start-commit-rule/test.sh` 維持全綠。

## 5. Skill 文件

- [x] 5.1 [P] 改寫 `plugins/issue-driven-dev/skills/idd-edit/SKILL.md`：新增 `--correct` 模式列與 `(category: in-place-correction)`、`issue:<N>` target 說明、Task 清單加入 `check_correction` 與 `archive_before_patch`、執行順序為預覽 → 確認（預設 NO）→ `archive --from-file` → PATCH → 刪除 `/tmp` 工作副本、標記以 `emit-audit-marker edit mode=correct backup-id=...` 產生並接在取代內容末尾、「Backup 管理」改為 `restore` 用法與人工 `chmod u+r` 說明，執行的 bash 不出現歸檔路徑字面值（設計：確認後才歸檔，歸檔成功才 PATCH；設計：標記只留 backup-id，放在被取代區段末端）。驗證：1.1、1.2 中 idd-edit 相關斷言轉綠；`scripts/tests/idd-edit-contract/test.sh` 全綠（新變數皆有出處）。
- [x] 5.2 [P] 改寫 `plugins/issue-driven-dev/skills/idd-comment/SKILL.md` 的 errata 流程：解析 target 作者，OWNER／bot 轉給 `idd-edit --correct` 且不另貼 comment，其他作者只貼 errata comment、不呼叫 `idd-edit`、不印 override 提示（設計：idd-comment errata 依作者分流；Requirement: idd-comment errata SHALL route by comment author）。驗證：1.1 的 errata 斷言轉綠。
- [x] 5.3 [P] 在 `idd-verify`、`idd-diagnose`、`idd-reorganize` 的 SKILL.md 各加一個步驟：發現 issue 既有內容有錯時於報告加 `### Proposed Corrections`（目標、段落、錯在哪、完整 `/idd-edit ... --correct` 指令），attended 逐項以 AskUserQuestion 詢問是否執行，unattended 只列不做，且不呼叫 helper 的 `archive`（設計：偵測錯誤的 skill 只提議；Requirement: Skills that detect errors SHALL propose corrections, not apply them）。驗證：1.1 的三個 skill 斷言轉綠；三個 skill 的 Task 清單都含對應項目。

## 6. 收尾與驗收

- [x] 6.1 本 repo 的 `.gitignore` 加入 `.claude/.idd/archive/`，執行 `plugins/issue-driven-dev/scripts/run-all-tests.sh` 全部 suite 通過，並以 `git status` 確認沒有歸檔檔被追蹤。驗證：run-all-tests 輸出全綠的 suite 數與 0 失敗。
- [x] 6.2 手動驗收一次：在本 repo 建一則測試 comment，跑完整 `/idd-edit comment:<id> --correct --scope whole-comment` 流程，確認 GitHub 上只剩更正版與標記、標記不含路徑、`git status` 乾淨、Claude 以 `Read` 與 `Grep` 讀歸檔都被 hook 拒絕、`restore` 能還原且輸出不含內容；把結果記在 #351。驗證：#351 上的驗收紀錄 comment。
- [x] 6.3 bump plugin 版本、更新 `plugins/issue-driven-dev/CHANGELOG.md`（標明 errata 行為面 BREAKING）與 `plugins/issue-driven-dev/.claude-plugin/plugin.json` 描述，並記下封存後要把 `append-vs-modify-discipline` spec 的 Purpose 由 7 類改為 8 類。驗證：`scripts/tests/model-generation-sync` 與 `docs-catalog-sync` 等版本相關 suite 通過；CHANGELOG 有對應版本段落。

## 7. Verify 第 1 輪修正

- [x] 7.1 先寫會失敗的測試：多行 `--body-file` 經 `eval` 後 `BODY_INPUT` 與檔案一致且不執行任何內容；`issue:` 混合或多個時 exit 2；`--scope` 與 `--section` 併用 exit 3；作者閘門接受「login 等於目前 gh 使用者」、拒絕外部開的 issue；`---` 為段落邊界；替換內容帶入受管標題 exit 6；verbatim 多重集合比對（尾端改字、追加引用行、拿掉 `>`）與 `**Original**` 標籤；archive 根目錄在主 worktree、撞名檔也檢查 ignore、`--from-file` 敏感路徑 exit 5、sidecar 寫入；restore 拒絕 symlink、tracked、repo 不符；hook 的 token 比對、`..` 變體、`archive-foo` 不誤擋、解鎖旗標；`idd-update` 與三個提議 skill 的文件契約（Requirement: Correction targets SHALL be resolved one per iteration；Requirement: Only the invoking user's own content SHALL be correctable；Requirement: The target SHALL be re-read after confirmation；Requirement: Corrected sections SHALL stop at a thematic break or a managed heading；Requirement: idd-update SHALL rebuild Key Decisions from current comments；Requirement: Restore SHALL refuse entries it did not write；Requirement: The read guard SHALL match path tokens and honour an unlock flag）。驗證：兩個 suite 新增斷言以「尚未實作」失敗。
- [x] 7.2 helper：`emit_assignment` 多行值改用 `$'...'` 安全引號；`parse-args` 目標與旗標檢查；`validate-target` 接受自己的 login、新增 issue 作者檢查；`check-correction` 的 `---` 邊界、受管標題、verbatim 多重集合與雙標籤；`section-replace` 加 `--stop-at-rule`；`archive` 主 worktree 根目錄、逐檔 ignore 檢查、`--from-file` 路徑閘門、sidecar；`restore` 的 symlink／tracked／repo 檢查；`emit-audit-marker` 先清理再驗證、date 取 backup-id 的 UTC 日。驗證：7.1 的 helper 斷言轉綠，`idd-edit` 與 `idd-edit-contract` suite 全綠。
- [x] 7.3 hook：shell word 比對、路徑段比對、解鎖旗標。驗證：7.1 的 hook 斷言轉綠。
- [x] 7.4 `idd-edit` SKILL.md：每個目標一個 iteration（不用全域旗標）、確認後重抓比對、PATCH 前檢查 `section-replace` 結束碼、拒絕原因分桶、失敗路徑清除工作副本、`mktemp` 工作副本、正文的 Step 3／7；說明與範例把 typo 導到 `--correct`；multi-finding 指引改為更正走 `--correct`。驗證：`idd-edit-contract` 全綠、7.1 文件斷言轉綠。
- [x] 7.5 其他文件：`idd-update` Key Decisions 改為每次重建；三個提議 skill 的替換檔放 `$HOME/.cache/idd/corrections/`、「錯在哪」欄不重述錯誤值；`idd-comment` errata 本人路徑改用 `--correction-file`、移除類別宣告；`idd-reorganize` 鐵律；規則檔 decision tree、IC_R007 列、spec 檔歸類、override 說法；MANIFESTO 8 類；CHANGELOG 標 BREAKING、修正「唯一保留的舊版」說法；design 同步。驗證：7.1 文件斷言轉綠，全部 suite 跑過。
- [x] 7.6 6.2 手動驗收加入正文路徑（`issue:<N> --correct --section`），並在 #351 驗收後套用 verify 報告的兩項 Proposed Corrections。驗證：#351 驗收紀錄。

## 8. Verify 第 2 輪修正

- [x] 8.1 先寫會失敗的測試（`in-place-correction` F 節、`correction-archive` G 節）：整則 `--correct` 拿掉受管區 exit 6；fence 內的 `# 註解` 與 `---` 不結束段落、fence 內的 `## Current Status` 不算受管標題；`compose-correction` 組出全文、重複標題只出現一次、再次更正保留舊標記且新標記在最後；`--section` 不是標題 exit 2；`--correct` 對 bot 與他人 exit 4 且不提 override；test mode 不呼叫 `gh`；`=` 開頭的值在 zsh `eval` 後不變；`restore`／`archive` 遇到父目錄 symlink 拒絕；SKILL 的 `fetch-failed`／`section-not-found`／`declined`／`compose-correction`／mode 參數契約；文件契約（idd-comment 以 `--correct` 分流、歸檔只在原 clone、`chmod 000`、idd-issue 導流、README hook、idd-update 排除 errata 推翻的決定、idd-reorganize 分界）。驗證：新斷言以「尚未實作」失敗。
- [x] 8.2 helper：`_code_line_set`（markdown-it-py 4.0.0，缺或版本不符 exit 1）用於 `section-replace`、`_section_range`、`_managed_owner`；`check-correction` 整則也檢查受管區；新增 `compose-correction`；`parse-args` 要求 `--section` 為標題；`validate-target` 第 4 參數 mode，`--correct` 拒絕 bot、拒絕訊息不提 override；test mode 不跑 `gh api user`；`bash_quote` 跳脫開頭的 `=`；`_archive_path_problem` 供 `archive`（exit 7）與 `restore`（exit 2）。驗證：8.1 的 helper 斷言轉綠，`idd-edit`、`idd-edit-contract` 全綠。
- [x] 8.3 `idd-edit` SKILL.md：兩次 `gh api` 檢查結束碼（`fetch-failed`）；check-correction 結果分桶；預覽與寫入都用 `compose-correction`、預覽顯示全文；拒絕時刪工作副本並記 `declined`；validate-target 傳 `$MODE`；備份檔名、`chmod 000`、歸檔只在原 clone。驗證：8.1 的 skill 契約斷言轉綠。
- [x] 8.4 其他文件與 spec：作者閘門改為「OWNER 或你自己」（idd-comment、idd-verify、idd-diagnose、idd-reorganize、規則檔、design、兩份 spec），idd-comment 分流傳 `--correct`；idd-reorganize 分開「判斷被推翻」與「敘述錯誤」；idd-update 排除 errata 推翻的決定；idd-issue multi-finding 導流；README 列出 read guard；三份 spec 補上本輪行為與 scenario；CHANGELOG 3.5.0（rebase 到 main 後版本由 3.4.0 改為 3.5.0）。驗證：`spectra validate idd-edit-in-place-correction`、`run-all-tests.sh` 全綠。
- [x] 8.5 Verify 第 3 輪：FAIL，2 項 blocking 與 in-scope 修正（[report](https://github.com/PsychQuant/issue-driven-development/issues/351#issuecomment-6197369179)），follow-up #406、#407。Proposed Correction 移到 9.5。

## 9. Verify 第 3 輪修正

- [x] 9.1 先寫會失敗的測試（`in-place-correction` G 節、`correction-archive` H 節）：未封閉的 fence 吞掉 `## Current Status` exit 6、替換內容留下開著的 fence exit 6、HTML 註解內的標題不結束段落且不留下 `-->`、setext 標題結束段落；NUL 的 body file exit 5、控制字元走 ANSI-C、`a:=ls` 在 zsh 不變；Clarity Surface 子標題受保護；引文後緊接文字 exit 6；`--correct` 無內文 exit 2；整則更正保留開頭標題與 `idd:comment` 標記；標記不重複、`idd:edit` 標記保留；parser 版本不符 exit 8；`--correct` 不吃 override、查不到 gh 使用者 exit 1；`existing-mentions`；sidecar 獨佔建立（孤兒、symlink）；巢狀 repo 與大小寫變體的追蹤檢查；hook 擋遞迴 chmod、`sort -m`；SKILL 契約（egress check、existing-mentions、--replace 結束碼、stage-failed、私有工作目錄、與預覽比對、exit 5、eval 失敗即停）；idd-comment 的 errata 退路。驗證：新斷言以「尚未實作」失敗。
- [x] 9.2 helper：`_Blocks`（parser 的不透明區塊、頂層標題、分隔線）取代逐行判斷；受管區改為逐行比對（含 Clarity Surface 子標題）；`check-correction` 整則保留開頭標題、lazy continuation；`compose-correction` 保留全部 IDD 標記並做不變量檢查；引號與 NUL；`--correct` 需要內文；`validate-target` 的 mode 判斷順序與 exit 1；`existing-mentions`；sidecar 獨佔；巢狀 repo 與大小寫檢查；parser exit 8。hook：遞迴 chmod、`-m` 只對訊息指令。驗證：9.1 的 helper 與 hook 斷言轉綠，`idd-edit`、`idd-edit-contract` 全綠。
- [x] 9.3 SKILL 與其他文件：私有工作目錄、stage-failed、egress 預檢與 mention、與預覽比對、讀回確認、exit 5、`--replace` 結束碼、eval 檢查、Step 1.5 的 exit 1；idd-comment 退路；規則檔、兩份 spec、design、proposal、CHANGELOG 的 bot 殘留與過頭宣稱；`git clean -X` 警告；idd-issue 措辭。驗證：`spectra validate`、`run-all-tests.sh` 全綠。
- [x] 9.4 Verify 第 4 輪：FAIL，CRITICAL 為第 4 輪的工作目錄回歸（[report](https://github.com/PsychQuant/issue-driven-development/issues/351#issuecomment-6198383293)），follow-up #409、#410。

## 10. Verify 第 4 輪修正

- [x] 10.1 先寫會失敗的測試（`in-place-correction` H 節、`correction-archive` I 節）：以 `TMPDIR=/var/tmp` 執行 SKILL 自己的工作目錄那一行再 archive（exit 0），路徑閘門對使用者暫存目錄放行、`/etc/hosts` 照擋；write-failed 桶與 exit 4、unverified exit 7、declined exit 9、idd-comment 的對應；`--last` 讀全部分頁；fence 內的範例標記不搬、不頂替；dashboard 第一行標記；GFM 表格；引文移進 HTML 註解或 fence；非 ASCII 的位元組跳脫；`## Current Status` 管到結尾；只有空白的內文、沒有 target；替換內容加入同級標題、分隔線、Current Status 變體；Step 1.5 的 exit 1 只限 `--correct`；idd-comment 作者無法判定改貼 errata；hook 的 repo 根目錄以上、gh-egress 與環境變數前綴、訊息值的重導向；archive 的追蹤檢查。驗證：新斷言以「尚未實作」失敗。
- [x] 10.2 實作：helper（位元組跳脫、空白內文、沒有 target、表格規則、Current Status 範圍、`_verbatim_runs` 的隱藏判定、`_opening_line`、替換內容的結構檢查、compose 的開頭標記與 code 內標記、`_tracks_archive`、sidecar 錯誤）、hook（`INTERPRETERS`、環境變數前綴、`<`／`>`、`_archives_around`）、helper 路徑閘門放行使用者自己的暫存目錄（`/tmp` 固定前綴會被 verify-scratch-paths 擋，`$HOME` 會讓標記帶出使用者名稱）；SKILL（`WRITE_FAILED_TARGETS`、exit 7／9、Step 1.5、`--paginate`）、idd-comment 分流表。驗證：四個相關 suite 全綠。
- [x] 10.3 spec 與文件：受管區條件依序編號並加入 (5)(6)、作者 requirement 改名並寫 exit 1、errata 退路、標記與 exit code、表格規則、引數的非 ASCII 與 target、archive 追蹤檢查、hook 的新規則；規則檔的 issue 作者；CHANGELOG 第 5 輪段落並修正第 4 輪段落的 exit code。驗證：`spectra validate`、`run-all-tests.sh` 全綠。
- [x] 10.4 決定下一步：使用者 2026-10-16 選定先把 `--correct` 的流程搬進 helper（第 11 節），正文更正等流程定案後再套用。

## 11. `--correct` 的流程搬進 helper

- [x] 11.1 先寫會失敗的端到端測試 `plugins/issue-driven-dev/scripts/tests/correct-flow/`（假的 gh、`TMPDIR=/var/tmp`）：comment section 確認後更正並歸檔、拒絕後不留檔、預覽後目標變了、既有 mention 放行而新 mention 在 prepare 就被擋、寫入失敗、讀回不符 exit 7、抓不到原文、issue 正文經 `gh issue edit`、bot 作者、工作目錄被動過、受管區、不是 prepare 建的目錄。驗證：新 suite 以「尚未實作」失敗。
- [x] 11.2 helper：拆出 `_archive_write`、`_compose`、`_existing_mentions`、`_correct_marker`；新增 `correct-prepare`、`correct-apply`、`correct-discard`（工作目錄驗證、sha256 狀態、行程內歸檔、gh-egress 寫入、讀回）。驗證：`correct-flow` 全綠，既有 suite 仍全綠。
- [x] 11.3 SKILL：新增 Step 1.6，`--correct` 只呼叫三個子命令；刪除 Step 5.5 與 Steps 2–7 裡的 `--correct` 分支；task 清單改名；restore 範例的 `BACKUP_ID`。契約測試改指向 helper。驗證：`idd-edit`、`idd-edit-contract`、`in-place-correction` 全綠。
- [x] 11.4 spec、design（新增 decision 與三個子命令的契約）、CHANGELOG。驗證：`spectra validate`。
- [x] 11.5 Verify 第 5 輪：FAIL，findings 40（第 2–4 輪 42、52、63），CRITICAL 0；DA 因額度未跑完。報告在 #351 的 verify 留言（comment 6229416722）。
- [ ] 11.6 套用 Proposed Correction（#351 正文 `## Related` 中 #347 那一行），在主 repo 以本 branch 的 helper 執行，讓歸檔留在長期存在的 clone。驗證：#351 正文。

## 12. Verify 第 5 輪修正

- [x] 12.1 先寫會失敗的測試：`correct-flow` R6 節（state 雜湊、欄位格式、apply 重跑作者閘門與受管區、JSON 原樣抓取、寫入報錯後重讀分流、歸檔前置檢查、先抓原文再判作者、殘留工作目錄清理、整則更正不重複開頭標記）；`in-place-correction`（setext 標題被拒、`--replace` 照舊取代、標題重複 exit 9、Step 1.5 對 `--correct` 跳過）。驗證：新斷言以「尚未實作」失敗。
- [x] 12.2 helper：`_section_end` 只認 ATX、`_heading_count`、`EXIT_AMBIGUOUS`、`_archive_preflight`、`_remove_stale_work_dirs`、`_state_problem`、`_fetch_body` 改取 JSON、apply 的 `--state` 與重跑閘門、寫入報錯後重讀、`_compose` 去重開頭標記。驗證：`correct-flow` 全綠。
- [x] 12.3 SKILL：Step 1.5 對 `--correct` 跳過；Step 1.6 保存並傳回 `STATE`、兩個區塊包在 mode 判斷裡、印 backup id；`--replace` 對應 exit 9；Step 0、鐵律、閘門表。idd-comment 貼 errata 後提議 `--prepend-note`；規則檔、idd-diagnose／idd-reorganize 的暫存目錄理由。驗證：`idd-edit`、`idd-edit-contract`、`in-place-correction` 全綠。
- [x] 12.4 spec、design、CHANGELOG。驗證：`spectra validate`。
- [x] 12.5 Verify 第 6 輪（含 DA）：FAIL，findings 52（HIGH 1／MEDIUM 10／LOW 30／INFO 11），CRITICAL 0；DA 完成。報告在 #351 的 verify 留言（comment 6229867499）。

## 13. Verify 第 6 輪修正

- [x] 13.1 先寫會失敗的測試（`correct-flow` R8 節；在 `fec3c07` 上 17 條失敗）：把 SKILL 的 Step 1.6 三個區塊抽出來、分兩個 shell 執行；apply 端重跑作者閘門與受管區、state 欄位、寫入生效後才報錯、殘留目錄、另一個 repo、CRLF 與無結尾換行、讀回多一個換行、dashboard 標記被移到結尾、null body、只有標題、新增 setext、歸檔目錄被檔案擋住、缺 `--scrub-attested`、OWNER 不是自己。fake gh 依 owner/repo 路由、新增 `fail-after-patch`／`pad-read`；暫存目錄改為每次執行私有。驗證：DA 的五個突變（拿掉 apply 端作者閘門、受管區重跑、state 欄位檢查、殘留清理、寫入報錯一律算 write-failed）各自都有測試失敗。
- [x] 13.2 helper：`_raw_lines` 與逐位元組保留的 `_compose`、頂端標記固定、`_check_correction` 回傳拒絕原因（`setext` 獨立）、`_adds_setext`、`_fetch_body` 對缺欄位與 null 的處理、`--scrub-attested` 必填、去掉標題後為空的檢查、歸檔前置檢查加目錄可建立、`_correct_apply` 單次讀 state 與閘門前移、`_correct_write` 的例外處理、讀回逐位元組比對；`--correct` 只放行本人（使用者 2026-10-17 決定）。驗證：`correct-flow` 全綠。
- [x] 13.3 SKILL 與文件：Step 1.6 印出並照抄 WORK／PREVIEW／STATE、scrub 分級解析；閘門表、批次 exit 契約、REASON 清單、help；idd-comment 的 exit 2／3／5 不貼、指標只在自己的 comment 更正失敗後且開頭不是 IDD 標題時提議、errata_pointer task；OWNER 規則與無標題文字限制同步到 idd-edit、idd-comment、idd-diagnose、idd-verify、idd-reorganize、規則檔；spec、design、CHANGELOG 第 8 輪與第 6、7 輪說得過頭處的註記。開 #413（idd-update Branch B）。驗證：`spectra validate`、`run-all-tests.sh`。
- [x] 13.4 Verify 第 7 輪：FAIL，findings 52（HIGH 2／MEDIUM 15／LOW 27／INFO 8），CRITICAL 0；趨勢 66 → 42 → 52 → 63 → 40 → 52 → 52 未收斂。兩個 HIGH 與第 6 輪同源：確認後的區塊仍依賴新呼叫裡沒有的 `MODE`、`TARGET`、結果陣列與迴圈。報告在 #351 的 verify 留言（comment 6231476603）。使用者 2026-10-17 決定：整次執行的狀態搬進 helper；issue 正文維持以開 issue 的人判定歸屬並寫明；拒絕訊息提示切換帳號。

## 14. 整次執行的狀態搬進 helper（第 9 輪）

- [x] 14.1 先寫會失敗的測試 `plugins/issue-driven-dev/scripts/tests/edit-run/`：Part A 測 helper 的 `run-start`／`prepare`／`apply`／`discard`／`finish`（四種 mode、R5 與 override、拒絕／拒絕預覽／沒 apply／寫入失敗／寫入後才報錯／egress／隱私等級、`--correct` 經 run 的各種結局）；Part B 把 SKILL 每個步驟區塊抽出來，一個區塊一個空環境的 zsh 與 bash，只代入前一步印出的值。驗證：新 suite 以「尚未實作」失敗（63 條）。
- [x] 14.2 helper：`_parse_args`、`_audit_marker` 拆出；新增 run 子命令、`_scrub_tier`、`_edit_prepare`／`_edit_compose`／`_edit_apply`、`_edit_backup`（使用者暫存目錄的 `idd-edit-backup/`）、`_write_diff`；correct-prepare 印 `DIFF=`。另修第 7 輪 helper 項目：`**Point` 引文、setext 整組比對、整則更正先去掉頂端標記、只剩標記為空、`unclosed-block`、作者閘門後才做歸檔前置、例外處理、state 的 sha 欄位、殘留 run 目錄、validate-target 驗 repo、拒絕訊息提示 `gh auth switch`、R5 列的 override 提示。驗證：`edit-run`、`correct-flow`（R9 節）全綠。
- [x] 14.3 SKILL：Execution 改為五個單行步驟（start／prepare／apply／discard／finish）與預覽、差異、隱私自審；批次說明、閘門表註、Backup 管理、restore 範例、契約段。CI 安裝 zsh。舊的字串契約（in-place-correction、idd-edit fixture 14／15、gh-egress-rollout）改指向 helper；correct-flow 的 R8.1 由 edit-run 取代。驗證：`run-all-tests.sh` 全綠。
- [x] 14.4 文件：決定 1、3 與正文歸屬的近似同步到規則檔、兩份 spec、design（新增兩個 decision 與五個子命令的契約列）、proposal、idd-edit、idd-comment（`--repo`、egress 不轉述、correction-file、指標條件的統一寫法）、idd-issue、idd-verify／idd-diagnose／idd-reorganize（`--type correction`）；CHANGELOG 第 9 輪、既有 mode 的結束碼與備份位置、Key Decisions 重建的副作用、被取代句子的註記。驗證：`spectra validate`。
- [x] 14.5 Verify 第 8 輪：FAIL，findings 52（CRITICAL 2／HIGH 4／MEDIUM 14／LOW 23／INFO 9）。CRITICAL：SKILL 的 apply 對非 `--correct` 傳 `--state ""`，helper 當成缺值，三個既有 mode 確認後都沒寫入（fail-closed）；HIGH：不帶大括號的 `$CLAUDE_PLUGIN_ROOT` 不會被代換、3.4.0 的 0755 備份目錄。報告在 #351 的 verify 留言（comment 6233768167）。

## 15. Verify 第 8 輪修正（第 10 輪）

- [x] 15.1 先寫會失敗的測試：edit-run Part B 改為照 Claude Code 代換 `${CLAUDE_PLUGIN_ROOT}`、環境不帶任何 IDD 變數，四種 mode 都經 SKILL 區塊確認並寫入，另有含單引號的引數、`~` 與 `$HOME` 的 body file、兩個 target 的批次、只做一半的批次、PICK、拒絕預覽、被拒；Part A 新增 0755 備份目錄、較嚴的等級、STATE 抄錯重試、缺 mode、重複 target、沒有 comment 的 `--last`、只有標題、別人 issue 正文的拒絕訊息。驗證：新斷言以「尚未實作」失敗。
- [x] 15.2 helper：`_take_flag` 接受明確的空值；`_home_path`；run-start 的 mode、只有標題、去重、`--last` 沒有 comment、清殘留 run；`_own_run_dir`／`_own_work_dir` 不綁當次呼叫的暫存目錄；apply 的等級（可更嚴）、STATE 先比對再套用、例外改 unverified；`_backup_dir`（收緊 3.4.0 的 0755、他人的目錄改用 `-<uid>`）、`_backup_ref`（標記不帶本機路徑）；finish 的 `not-prepared`／`not-picked`；只剩標記為 `empty`；issue 正文的拒絕訊息指向 `--type correction`。驗證：edit-run、correct-flow 全綠。
- [x] 15.3 SKILL 與文件：idd-edit 的區塊改用 `${CLAUDE_PLUGIN_ROOT}`、Step 1 的結束碼與 `~`／`$HOME`、REASON 清單、ENFORCE 的遮蔽做法、等級與 STATE 重試、finish 的拒絕類別、restore 用單引號與無引號的 placeholder、PICK 分頁、GitHub 內容是資料；idd-comment 的作者分流改為一行字面值指令、`correction` 列的用途；`**Point` 標籤補到 idd-verify／idd-diagnose／idd-reorganize、規則檔決策樹、design；spec（run 需求、parse-args 需求改寫、untitled 限制只限正文、(2) 與 in-place-correction 的關係）；design 過時的列；CHANGELOG 第 10 輪與漏寫的介面變化、被取代句子的註記。驗證：`spectra validate`、`run-all-tests.sh` 全綠。
- [x] 15.4 Verify 第 9 輪：FAIL，findings 44（HIGH 1／MEDIUM 9／LOW 25／INFO 9），CRITICAL 0；DA 照字面逐段執行 SKILL，四種 mode、批次、PICK、拒絕預覽、被拒與 idd-comment 委派都跑通。報告在 #351 的 verify 留言（comment 6234222016）。另一個 session 的結構審查建議以 run.json 為唯一事實來源、靜態檢查所有區塊、restore 不貼 GitHub 的值。

## 16. Verify 第 9 輪修正（第 11 輪）

- [x] 16.1 先寫會失敗的測試：edit-run A9（`--correct` 以較嚴等級寫入、沒列出的 target、PICK 的逐一對帳與不屬於該 issue 的 comment、PICK 指向已有的 target、跨 TMPDIR 的 `--correct`、外來 run 目錄、diff 的結尾換行、`$HOME//`、gh token 目錄、bot 開的 issue 正文）與所有區塊不讀變數的靜態檢查；correct-flow R9.9（restore --target、偽造標記）、E4 實際數工作目錄；correction-archive 的 `--reason` 提到歸檔路徑。驗證：新斷言以「尚未實作」失敗。
- [x] 16.2 helper：`_correct_prepare_text`（run 傳文字不傳路徑）、`_correct_apply` 的 scrub、SCRUB= 輸出、`_run_meta_problem` 與 body.md 檢查、`_comment_issue` 與 PICK 紀錄、prepare 的 target 閘門、`_latest` 沿用 pick、apply 的例外分段、`_write_diff` 的結尾換行、`_home_path`、bot 正文訊息、PICK 去重、備份目錄的第三個退路、gh token 目錄、`restore --target`；hook 的 `--reason`。驗證：edit-run、correct-flow、correction-archive 全綠。
- [x] 16.3 SKILL 與文件：prepare 的 `--pick`、restore 改用 `--target`、`<REPO>` 單引號與格式、備份找回、STATE 重抄仍不符的處置、untitled 限制只限正文（idd-edit 與三個提議 skill）；spec（STATE、等級、untitled、備份退路、PICK、run 內容、跨暫存目錄、parse-args、restore --target）；design 四處過時描述；proposal 的 run 決定與兩個 BREAKING；plugin 與 marketplace 描述；CHANGELOG 第 11 輪與 3.4.0 讀不到目標的基準。驗證：`spectra validate`、`run-all-tests.sh`。
- [ ] 16.4 Verify 第 10 輪，或改走驗收（11.6 實機套用）後合併 —— 由使用者決定。驗證：#351 的留言。





