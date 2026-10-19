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
- [x] 11.6 套用 Proposed Correction（#351 正文 `## Related` 中 #347 那一行），在主 repo 以本 branch 的 helper 執行，讓歸檔留在長期存在的 clone。驗證：#351 正文。
- [x] 11.7 11.6 的結果（#351 的留言 comment 6235380442）：2026-10-17 以本 branch（`6cc4f75`）的 `/idd-edit --correct` 從主 repo 照 SKILL 逐步執行，更正 #351 正文兩處，兩筆都先給使用者看差異與預覽、確認後寫入 —— `## Related` 的 #347 那一行（歸檔 `issue-351-body-20261017T145233Z`），與 `### 已定案` 的「只改你自己寫的內容」（歸檔 `issue-351-body-20261017T145544Z`）。兩筆都讀回一致、finish exit 0、歸檔權限 0000 且被 ignore、沒有殘留的工作目錄；`restore --target issue:351` 對真實 GitHub 列出兩個已檢查的 id、exit 2、什麼都沒寫（正文未變）。這是搬進 helper 之後第一次對真實 GitHub 執行。（8a78706 曾把這段寫進 11.6 的原文，第 12 輪還原 11.6、改記在這裡。）驗證：#351 正文與 comment 6235380442。

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
- [x] 16.4 Verify 第 10 輪，或改走驗收（11.6 實機套用）後合併 —— 由使用者決定。驗證：#351 的留言。
- [x] 16.5 Verify 第 10 輪；沒有 HIGH 以上就準備合併。驗證：#351 的 verify 留言。
- [x] 16.6 16.4 的決定：使用者 2026-10-17 選定先實機驗收（11.6，通過，結果見 11.7），再跑第 10 輪 verify（16.5）。（8a78706 曾把這段寫進 16.4 的原文，第 12 輪還原 16.4、改記在這裡。）驗證：#351 的留言。
- [x] 16.7 16.5 的結果：第 10 輪 FAIL，findings 50（MEDIUM 10／LOW 27／INFO 13），CRITICAL 0、HIGH 0；第一次執行時 5 個 agent 撞到每週額度，重置後以同一個 run 續跑完成。依「同一個 PR 修乾淨再合」，先做第 12 輪修正（§17），合併判定套用在修正後的 HEAD。報告在 #351 的 verify 留言（comment 6239594311）。

## 17. Verify 第 10 輪修正（第 12 輪）

- [x] 17.1 先寫會失敗的測試：in-place-correction R10.1（CRLF 引文經 LF 取代後以原位元組寫回，段落與整則兩種）、R10.2（標記被移進 `<script>`／`<div>` 時照樣補上獨立的標記，已獨立的標記不重複）；correct-flow R10.1（CRLF 引文經 prepare、apply、讀回比對）。驗證：新斷言在 8a78706 的 helper 上失敗（in-place 4 條、correct-flow 1 條）。
- [x] 17.2 helper：`_verbatim_spans`（`_verbatim_runs` 共用同一個引文定義）、`_region_text`（取代區內與原文相符的引文用原位元組）、`_compose` 只把仍是獨立 HTML block 的標記算成已保留，並在組好的正文裡檢查它們。驗證：in-place-correction、correct-flow 全綠。
- [x] 17.3 文件：spec（標記保留條款、組好後的檢查、引文換行情境）、CHANGELOG 第 12 輪。驗證：`spectra validate`。
- [x] 17.4 先寫會失敗的測試（其餘 MEDIUM 與 LOW）：edit-run A10（閒置的 run 不被自己的 prepare 清掉、各 mode 的 `--scope` 在 start 檢查、private repo 的 user-pasted reply 以 warn 檢查與寫入（`--append` 與 `--correct`）、讀不到的 PICK comment 是 fetch-failed 且可重試、`#007`、diff 只在換行處斷行、`--correct` 標記用本地日期、大小寫變體與 `GH_CONFIG_DIR`／`XDG_CONFIG_HOME` 的憑證路徑）、所有區塊的 placeholder 不在雙引號裡、PICK 列表用 `@json`、偽造的 TARGET 貼進 prepare 區塊不執行；correct-flow（`restore --target` 只查不寫、git 工作樹外 exit 7）；correction-archive（heredoc 訊息被擋時說明替代寫法）。驗證：新斷言在 8a78706 上失敗（edit-run 25 條、correct-flow 4 條）。
- [x] 17.5 helper：`_gh_config_dirs`／`_under_folded`（不分大小寫、gh 的 token 目錄在 escape hatch 之前）、`--scope` 在每個 mode 檢查、`_floor`（#272 下限，prepare 的檢查與兩種 apply 的寫入）、`_remove_stale_work_dirs(keep=)` 與 `_record` 更新 run 的 mtime、`_comment_issue` 分開讀取失敗、PICK 數字正規化、`_write_diff` 只在 `\n` 斷行、`_correct_marker` 用本地日期（#406）、`restore --target` 改為只查（工作樹外 exit 7）、`--help`；hook 的拒絕訊息。驗證：edit-run、correct-flow、correction-archive 全綠。
- [x] 17.6 SKILL 與文件：idd-edit 的區塊一律單引號、PICK 列表 `@json` 與貼值前的形狀檢查、Step 2 的 `merged`／`not-in-pick`／PICK 的 fetch-failed、STATE 重抄仍不符與中止時的處置、#272 下限、restore 兩步、路徑安全清單、frontmatter 的「只改自己的內容」、`--correct` 不發布 `--reason`；兩份 spec（read guard 封閉列舉補 `--reason`／`python`、restore 只查、run 的下限／清理／PICK／`--scope`、跨暫存目錄的 work dir、run-start 的 exit 1、標記日期、憑證路徑、四個情境）；usecase-routing、design 契約表與 Context、tasks 11.6／16.4 還原原文並追加 11.7／16.6、CHANGELOG（Security、Changed 補列、實機驗收、exit 9 更正、第 12 輪）、plugin 與 marketplace 描述、plugin CLAUDE.md、README、三個提議 skill 的指令格、idd-comment 的委派；gh-egress-rollout 兩條字串契約。驗證：`spectra validate`、`run-all-tests.sh`。
- [x] 17.7 Verify 第 11 輪（只審 `8a78706..026bc5c`）：FAIL，findings 46（MEDIUM 5／LOW 23／INFO 18），CRITICAL 0、HIGH 0；Codex 的「跨午夜被判 differs-from-preview」是誤報（placeholder 標記不帶日期）。第 12 輪造成兩個退步：#272 下限由 helper 代為升級（fail-open）、只有 CR 的引文吃掉空行。報告在 #351 的 verify 留言（comment 6240562880）。

## 18. Verify 第 11 輪修正（第 13 輪）

- [x] 18.1 先寫會失敗的測試：edit-run（A5c／A7n 的 `not-applied` 改為 exit 9；A10c 的 #272：prepare 印 `FLOOR=272`、apply 以 light 被拒、以 warn 才寫入，`--append` 與 `--correct`；A11：PICK 在 issue 讀到之後才讀取失敗仍可重試、`²`、HOME 改掉時帳號家目錄的憑證路徑、symlink 的 `hosts.yml`、`/PRIVATE/ETC`、diff 在單獨 `\r` 斷行、sweep 保留 run 自己的 `--correct` 工作副本、`--correct` 的 `--reason` 提示；SKILL 的 U+2028 與 `FLOOR=272`）；in-place-correction（E6 本地日期、只有 CR 的引文）；correct-flow（標記不在時仍列出歸檔版本）；correction-archive（`git diff -m <archive>` 被擋、拒絕訊息；單一 token 的 `-m` 改為拒絕）；fake gh 的 `fail-body-read`。驗證：新斷言在 026bc5c 上失敗（edit-run 21 條、in-place 2 條、correct-flow 2 條、correction-archive 2 條）。
- [x] 18.2 helper：`_print_floor` 與 apply 的 #272 檢查（不再代為升級）、`_region_text` 的 CR 退路、`_archived_versions`（以本機歸檔與 sidecar 為準）、`not-applied` 記為 declined、PICK 的 ASCII 數字與不記錄讀取失敗、`_edit_prepare` 清掉未記錄的嘗試、`keep` 含工作副本、`_homes` 與 named／resolved 兩種路徑、系統路徑不分大小寫、diff 在 `\r\n`／`\r`／`\n` 斷行、`emit-audit-marker` 本地日期、run-start 的 `--reason` 提示、`--help`；hook 的 `-m` 只在有空白時視為訊息、拒絕訊息。驗證：四個 suite 全綠。
- [x] 18.3 SKILL 與文件：idd-edit（#272 專門詢問與 `FLOOR=272`、PICK 列表的 U+2028、TARGET 先於 PICK、引號只包一次、STATE 重抄仍不符的批次處置、`not-applied`、restore 查詢的版本與結束碼、mode 表、範例的 `--reason`、frontmatter 的 issue 正文路由）；三個提議 skill 與 idd-comment 的引號；兩份 spec（#272、`not-applied`、PICK、sweep、憑證路徑、diff、引文位元組的 SHALL、標記日期、提議指令要重組、errata 情境的旗標、restore 查詢、read guard 的空白規則）；design、CHANGELOG（第 13 輪、Security 的範圍、Changed 補列）、plugin 與 marketplace 描述、plugin CLAUDE.md、README。驗證：`spectra validate`、`run-all-tests.sh`。
- [x] 18.4 Verify 第 12 輪（只審第 13 輪的差異）；沒有 HIGH 以上就合併。驗證：#351 的 verify 留言。
- [x] 18.5 18.4 的結果：第 12 輪 FAIL，findings 48（MEDIUM 6／LOW 25／INFO 17），CRITICAL 0、HIGH 0；DA 照 SKILL 實跑全部符合文件，建議依同一個 PR 修乾淨先處理 #272 的兩則 MEDIUM。報告在 #351 的 verify 留言（comment 6241513472）。

## 19. Verify 第 12 輪修正（第 14 輪）

- [x] 19.1 先寫會失敗的測試：edit-run A12（warn 等級也印 `FLOOR=272`、prepare 不印 `SCRUB=`、作者讀取失敗的 PICK 可重試、超長的 issue 號碼）、Step 0 的 `reply_272_gate`、PICK 列表的 null body、diff 的單獨 `\r`；correct-flow（同一秒的版本依寫入順序、追蹤歸檔的 repo 被查詢拒絕、獨立 correct-apply 在 light 先擋再歸檔）；correction-archive（含空白的路徑接在 `git diff -m` 後、黏住的 `&&`／`||`、換行、`git -C`、多行訊息、`gh pr create`、單一 token 的 commit 訊息恢復放行）；fake gh 的 `fail-author-read`。驗證：新斷言在 45273ec 上失敗。
- [x] 19.2 helper：`_reply_272` 與 `_print_floor`（不論等級、不印 `SCRUB=`）、獨立 `_correct_apply` 的 #272 檢查、PICK 的 `author-unknown` 不記錄、一到十八位數、diff 的單獨 `\r`、`not-applied` 的報告措辭、restore 查詢的路徑與追蹤檢查、sidecar 必須是一般檔案、同一秒版本的排序；hook 以子命令判斷訊息旗標、換行與黏住的分隔符、拒絕訊息。驗證：edit-run、correct-flow、correction-archive 全綠。
- [x] 19.3 SKILL 與文件：idd-edit（`reply_272_gate`、`FLOOR=272` 不論等級、只有 `--replace` 能遮蔽、重跑的收尾、`apply_or_discard` 的說明、PICK 列表的 null body）；三個提議 skill 與 idd-comment 恢復單引號內的跳脫寫法、idd-comment 的 exit 9 列；兩份 spec（#272、PICK、diff、read guard 的子命令清單與分隔符、restore 查詢）；design；CHANGELOG（第 14 輪、Changed 的 #272 與路徑閘門）。驗證：`spectra validate`、`run-all-tests.sh`。
- [x] 19.4 Verify 第 13 輪（只審第 14 輪的差異）；沒有 HIGH 以上就合併。驗證：#351 的 verify 留言。
- [x] 19.5 19.4 的結果：第 13 輪 FAIL，findings 43（HIGH 6／MEDIUM 2／LOW 23／INFO 12）。六則 HIGH 同一個根因，是第 14 輪造成的退步：read guard 改用 `shlex.shlex` 時保留了預設的 `#` 註解字元，一個未加引號的 `#` 之後的指令（含 `chmod -R`）都不再檢查。報告在 #351 的 verify 留言（comment 6242229710）。

## 20. Verify 第 13 輪修正（第 15 輪）

- [x] 20.1 先寫會失敗的測試（correction-archive）：註解行之後的讀取、行尾註解後換行、字中的 `#`、`--grep=#351`、註解行之後的 `chmod -R`、`git commit -- -m <歸檔>`、`|&` 之後含空白的路徑；放行：`git commit -am`、反斜線續行、`env A=1 python3 <helper>`、`hg --repository`；單一 token 的 `-m` 值改回拒絕。驗證：12 條在 116aead 上失敗。
- [x] 20.2 hook：`lex.commenters = ""`；訊息值須同時是多字詞的文字、在收訊息的子命令裡、在 `--` 之前（`--` 只對 git／gh／hg／jj／svn）；`|&`／`&|` 分隔符；反斜線續行；git 的 `-am` 類合併旗標；更多的子命令前選項與收訊息的子命令；`env` 鏈；docstring 與拒絕訊息。驗證：correction-archive 194 條全綠，各輪 reviewer 列過的繞法逐一實跑。
- [x] 20.3 文件：idd-edit SKILL（#272 那一題問這次新加的文字、四種 mode 都能遮蔽、Step 0 順序、PICK 的 `author-unknown`、restore 查詢的 exit 2）；兩份 spec（not-applied 措辭、路徑閘門、#272 遮蔽、read guard 的規則清單）；`--help` 與獨立 correct-apply 的訊息；CHANGELOG（第 15 輪、兩處被推翻的條目加註、3.4.0 的 #272 說法）。驗證：`spectra validate`、`run-all-tests.sh`。
- [x] 20.4 Verify 第 14 輪（只審第 15 輪的差異）；沒有 HIGH 以上，就請使用者確認合併（合併即發佈 3.5.0）。驗證：#351 的 verify 留言。
- [x] 20.5 20.4 的結果：第 14 輪 FAIL，findings 29（HIGH 3／MEDIUM 4／LOW 9／INFO 13）。HIGH：第 15 輪的 `-am` 合併旗標把 `-Fm` 當成 `-m`（第 15 輪造成）；註解裡的撇號開出引號、吞掉下一行的 `chmod -R`（DA：45273ec 就有，不是退步）。MEDIUM：`--replace` 拿掉 reply 標記就不問 #272。DA 的原型修法以 shell 比對語料驗證。報告在 #351 的 verify 留言。

## 21. Verify 第 14 輪修正（第 16 輪）

- [x] 21.1 先寫會失敗的測試：correction-archive（`-Fm` 後含空白的路徑、`-am` 改回掃描、註解撇號後的 `chmod -R` 四種、註解裡的引號吞掉下一行兩種、IDD 的單引號跳脫寫法；放行：`2>&1`、`${#arr[@]}`）；edit-run A13（`--replace` 拿掉 reply 標記仍印 `FLOOR=272`、light 被拒）。驗證：11 條在 caf9791 上失敗。
- [x] 21.2 hook：詞首的 `#` 起註解到行尾、引號在註解裡是文字；反斜線只在 PowerShell 改成 `/`；`&` 只在重導向運算子之後不算分隔符；引號不平衡時的退路拿掉引號、切開黏住的分隔符；拿掉 `-am` 合併旗標；`chmod -R` 檢查帶 PowerShell 旗標。helper：`_reply_272`／`_floor` 同時看新內文與目前內文。驗證：correction-archive 216 條、edit-run 203 條全綠；DA 的已知繞法 47 條全擋、shell 比對語料只剩 1 條比對誤判（續行把 `sort` 接成參數）。
- [x] 21.3 文件：兩份 spec、hook docstring 與拒絕訊息、idd-edit SKILL 的 `FLOOR=272`、CHANGELOG（第 16 輪、兩處被推翻的條目加註、3.4.0 的 #272 說法）。驗證：`spectra validate`、`run-all-tests.sh`。
- [x] 21.4 Verify 第 15 輪（只審第 16 輪的差異）；沒有 HIGH 以上，就請使用者確認合併。驗證：#351 的 verify 留言。
- [x] 21.5 21.4 的結果：第 15 輪 FAIL，findings 35（HIGH 1／MEDIUM 5／LOW 15／INFO 14）。HIGH：`$(true)# x; chmod -R` 的 `#` 被當成註解跳過，藏住 `chmod -R`（第 16 輪造成）；MEDIUM：跳脫字元後的 `#`、heredoc 本文裡的 `#`（含 `#351`）、PowerShell 結尾反斜線，同一根因。DA：相對 caf9791 是淨改善、沒有其他 HIGH。

## 22. Verify 第 15 輪修正（第 17 輪）

- [x] 22.1 先寫會失敗的測試（correction-archive，以 `json.dumps` 產生）：`$(true)#`、`foo\ #x`、`a\;#b`、heredoc 本文裡的 `#351 $(cat …)`、`# Summary: $(cat …)`、`PR_BODY=$(cat <<EOF`、heredoc 撇號奇偶藏住 `chmod -R` 兩種、PowerShell 結尾反斜線、`x=( a b )\` 續行接 `chmod`、`>|`；放行：`# step` 註解行之後的 commit、`gh pr create --body "$(cat <<'EOF' …)"`。驗證：11 條在 4c5a0e4 上失敗。
- [x] 22.2 hook：`_normalize`（註解文字與 heredoc 本文保留並掃描、只空白掉引號與反斜線；PowerShell 先換反斜線）；`(`、`)` 分隔；`>|` 是重導向；退路的切分含括號。helper：apply 的 #272 檢查看存在的內文。驗證：correction-archive 242 條全綠；第 14 輪已知繞法 47 條全擋；第 15 輪 DA 的 12,000 筆網格以真實 bash／zsh 比對，放行且真的會讀到的是 0 筆。
- [x] 22.3 文件：correction-archive spec 的 read guard 規則、CHANGELOG（第 17 輪、兩處加註）、hook docstring。驗證：`spectra validate`、`run-all-tests.sh`。
- [x] 22.4 Verify 第 16 輪（只審第 17 輪的差異）；沒有 HIGH 以上，就請使用者確認合併。驗證：#351 的 verify 留言。
- [x] 22.5 22.4 的結果：第 16 輪 FAIL，findings 37（HIGH 6／MEDIUM 12／LOW 9／INFO 10），全部在 read guard，都是第 17 輪改寫造成：第 2 行以後的 `#` 註解認不出、heredoc 本文的跳脫被換成空白而拆開路徑、heredoc 誤判、括號 token、`>|`。報告在 #351 的 verify 留言（comment 6243761496）。
- [x] 22.6 使用者 2026-10-18 決定：read guard 改成 fail-closed——拿掉訊息例外，指令文字只要提到歸檔路徑就擋（訊息改用檔案傳）。

## 23. read guard 改為 fail-closed（第 18 輪）

- [x] 23.1 測試：correction-archive 中訊息提到路徑的放行案例改為拒絕（16 條）、拒絕訊息改指向訊息檔；新增 `arch\ive`／`arch""ive`／`'arch'ive`、第 2 行以後註解藏 `chmod -R`、heredoc 之後的註解、here-string、`find -exec chmod`、黏住的括號；放行：沒提到路徑的註解與 commit、`--body "$(cat <<'EOF' …)"`、`chmod -R u+x scripts`。
- [x] 23.2 hook：`_flat`（去掉引號、解開跳脫，PowerShell 的反斜線當路徑分隔）＋路徑片段比對；`_recursive_permission_change` 看整段指令的每個詞，`find`／`xargs`／`fd` 視同遞迴；移除訊息例外、斷詞模型、註解與 heredoc 處理。驗證：correction-archive 264 條全綠；47 個已知繞法、12,000 筆網格、第 2 行以後註解的 400 筆網格以真實 bash／zsh 比對全擋。
- [x] 23.3 文件：correction-archive spec（需求改寫、兩個 scenario 改為拒絕、新增註解 scenario）、hook docstring 與拒絕訊息、CHANGELOG（第 18 輪、Changed、舊條目加註）。驗證：`spectra validate`、`run-all-tests.sh`。
- [x] 23.4 Verify 第 17 輪（只審第 18 輪的差異）；沒有 HIGH 以上，就請使用者確認合併。驗證：#351 的 verify 留言。
- [x] 23.5 23.4 的結果：第 17 輪 FAIL，findings 52（HIGH 3／MEDIUM 6／LOW 23／INFO 20）。HIGH：反斜線續行把路徑或指令名稱切開（另由背景安全審查回報）；`chmod -R` 的目標去掉引號後被空白拆開（第 18 輪造成）。DA：fail-closed 的前提成立，剩下的是字元層級；沒有 IDD skill 無路可走。

## 24. Verify 第 17 輪修正（第 19 輪）

- [x] 24.1 先寫會失敗的測試（correction-archive）：續行切開路徑與指令名稱、含空白的 `chmod -R` 目標（加引號、跳脫、相對）、巢狀反斜線、`$'…'`、PowerShell 反引號、`$PWD`／`$(git rev-parse --show-toplevel)` 目標、`--recurs`、Monitor 工具；放行：`grep -R chmod .`、非遞迴的 chmod；權限規則的拒絕訊息。驗證：11 條在 9e784fc 上失敗。
- [x] 24.2 hook：`_variants`（續行接起與當成換行兩種讀法都查、跳脫成對掃描）、`_flat`（去掉所有跳脫字元、`$'…'`、PowerShell 反引號）、`_shell_words`（shlex 的完整詞與平面詞取聯集）、`_permission_change_in`（旗標與目標在權限指令之後、樹走訪器例外、無法解析的目標拒絕、不分大小寫）、`PERMISSION_REASON`、Monitor 納入 matcher。驗證：correction-archive 292 條全綠；47 個已知繞法、12,000 筆網格、400 筆註解網格以真實 bash／zsh 比對全擋。
- [x] 24.3 文件：correction-archive spec、hook docstring、design（fail-closed 決定與代價）、README、idd-edit SKILL（`--reason`／`--body` 不寫出路徑）、CHANGELOG（第 19 輪、Changed、舊條目加註）、測試註解。驗證：`spectra validate`、`run-all-tests.sh`。
- [x] 24.4 Verify 第 18 輪（只審第 19 輪的差異）；沒有 HIGH 以上，就請使用者確認合併。驗證：#351 的 verify 留言。
- [x] 24.5 24.4 的結果：第 18 輪 FAIL，findings 40（HIGH 5／MEDIUM 3／LOW 18／INFO 14）。HIGH 全在遞迴改權限：黏住的 `;`、註解裡的撇號讓 shlex 放棄、`cd` 之後的相對目標（第 19 輪「旗標與目標須在權限指令之後」造成）；另一則是 `$` 在任何 repo 都擋（DA 校正為過度拒絕，非安全退步）。

## 25. Verify 第 18 輪修正（第 20 輪）

- [x] 25.1 先寫會失敗的測試（correction-archive）：黏住的 `;`／`&&`、註解撇號、`cd`／`pushd` 後的相對目標、`.*`、PowerShell `-Recurse | ForEach-Object`、repo 外的含空白目標與變數目標、兄弟 repo 的 `..`、裝 repo 的資料夾的 `.`；放行：repo 外的 `chmod -R u+x scripts` 與 `grep -R chmod .`、repo 內的非遞迴 chmod 與 `ls -lrt`；`chmod-ok`、`grep-chmod` 改為拒絕。驗證：12 條在 71df95b 上失敗（apos-cmt 在 repo 內，測的是 repo 內規則）。
- [x] 25.2 hook：`_permission_change_in` 不再把詞歸給指令——含歸檔的 repo 內一律拒絕；別處每個詞都當目標，含 `$`、反引號、萬用字元或 shlex 無法配對的引號就拒絕；`_archive_below` 加查直接子目錄；`_RECURSIVE` 只有大寫 `R` 算短旗標；PowerShell `-Recurse`／`ForEach-Object`、`gchmod` 等、反引號＋CRLF；檢查出錯時拒絕該次呼叫。驗證：correction-archive 322 條全綠；47 個已知繞法、12,000 筆網格、400 筆註解網格、360 筆 chmod 網格以真實 bash／zsh 比對全擋。
- [x] 25.3 文件：correction-archive spec（新規則與兩個 scenario、matcher 含 Monitor）、hook docstring（接受的落差、輸入錯誤的處理）、design（新增 fail-closed 決定、Risks、延遲 40–45 ms）、README、idd-edit SKILL（`--reason` 含路徑時先問使用者）、CHANGELOG（第 20 輪、Changed、Added 的工具清單與延遲、舊條目加註）、測試標題。驗證：`spectra validate`、`run-all-tests.sh`。
- [x] 25.4 Verify 第 19 輪（只審第 20 輪的差異）；沒有 HIGH 以上，就請使用者確認合併。驗證：#351 的 verify 留言。
- [x] 25.5 25.4 的結果：第 19 輪 FAIL，findings 43（HIGH 7／MEDIUM 9／LOW 16／INFO 11）。HIGH 全在「工作目錄在 repo 外」時的目標解析（黏住的運算子、括號路徑被 `strip` 剝掉的 regression、`cd` 後的相對目標、無法列出的目錄放行）；DA 以使用者真實紀錄量到無歸檔 repo 的誤擋從 1 筆增為 237 筆。使用者決定（2026-10-18）：遞迴改權限只在歸檔附近檢查。

## 26. Verify 第 19 輪修正（第 21 輪）

- [x] 26.1 先寫會失敗的測試（correction-archive）：repo 外的 out-*、sibling-up 改為放行（已知限制）；新增無歸檔 repo 的 join 誤擋（fp-join）、 `.claude/.idd` 內的相對讀取與 chmod、同一行 `cd` 後的相對讀取、無法列出的工作目錄、PowerShell `-r`／`%`、`gfind`／`gxargs`、檢查出錯時拒絕且不提解除開關；放行：無歸檔 repo 裡寫 script 的 heredoc、`cd .claude/.idd && ls attachments`。
- [x] 26.2 hook：`_permission_change_in` 只看工作目錄是否在歸檔附近（`_near_archive`：歸檔在其上、其直接子目錄是含歸檔的 repo、或無法列出），不再解析目標，刪掉 `_archive_below`、`_shell_words`、`$`／萬用字元規則與 shlex；`_candidates` 把每個片段也以工作目錄與指令中存在的目錄解析（只在含 `archive` 時 join）；`_decide` 抽出；拒絕訊息補上分開執行、Write 工具、請使用者執行；檢查出錯的訊息不再叫 agent 建立解除開關。join 只在所指的歸檔確實存在時才算（無歸檔 repo 的 `.claude/.idd` 加上無關的 `archive/` 資料夾不再誤擋）。驗證：correction-archive 347 條全綠；歸檔附近 68,040 筆網格以真實 bash／zsh 比對全擋，7 個相對路徑情境全擋；使用者真實紀錄中無歸檔目錄的誤擋為 0（9394aaf 為 198），歸檔附近 59 筆（多為本 repo 的 verify 腳本）；`run-all-tests.sh` 63 個 suite 全綠。
- [x] 26.3 文件：spec（新規則、兩個 scenario、Monitor 欄位）、docstring、design（決定改寫、Risks、輪次）、README、CHANGELOG（第 21 輪、Changed、第 19／20 輪加註）。驗證：`spectra validate`、`run-all-tests.sh`。
- [x] 26.4 Verify 第 20 輪（只審第 21 輪的差異）；沒有 HIGH 以上，就請使用者確認合併。驗證：#351 的 verify 留言（6256335129）。
- [x] 26.5 26.4 的結果：第 20 輪 FAIL，findings 43（HIGH 3／MEDIUM 9／LOW 18／INFO 13）。HIGH：第 21 輪對每個指令片段 `isdir`，卡住的掛載點讓呼叫卡到 hook 逾時（逾時即放行）；`cd` 到含空白／括號的目錄後的相對路徑不被解析。DA：使用者接受的限制沒有藏住別的東西。背景安全審查另報「repo 外不檢查」為 fail-open——即使用者選定的限制，不改。

## 27. Verify 第 20 輪修正（第 22 輪）

- [x] 27.1 先寫會失敗的測試（correction-archive）：`cd` 到含空白、括號的目錄與 `$(git rev-parse …)` 之後的相對讀取、`cd .claude/.idd/attachments` 後的 `../archive/…`、Glob 的相對 path、子 repo 無搜尋權限（EACCES）時的遞迴改權限；放行：只提到 `archive` 這個字的三種指令、Bash 的 `%` 算術；一般指令不碰檔案系統（patch `os.stat`／`listdir`／`isdir` 為拋例外）。驗證：10 條在 30afcec 上失敗。
- [x] 27.2 hook：刪掉逐詞 `isdir` 與 `_names_existing_archive`；新增 `_relative_archive_reference`（純文字：接上工作目錄落在 `archive/` 之下，或 `archive/…`／`.idd/archive/…` 配上工作目錄或指令裡的 `.claude`／`.claude/.idd`），歸檔附近才擋；`_isdir_or_unknown`（stat 錯誤非「不存在」即視為有）；`_near_archive` 也查 realpath；`%`／`foreach` 只限 PowerShell，加 `bfs`、PowerShell `-Depth`；`_norm_path` 用 posixpath；拒絕訊息補上相對路徑、unlistable 目錄與訊息改由檔案傳；hooks.json 設 10 秒逾時。驗證：correction-archive 368 條全綠；歸檔附近 68,040 筆網格與 12 個相對路徑情境以真實 bash／zsh 比對全擋；使用者真實紀錄中無歸檔目錄的誤擋 0、歸檔附近 55（與 9394aaf 相同）；`run-all-tests.sh` 63 個 suite 全綠。
- [x] 27.3 文件：spec（相對路徑規則、純文字、symlink／EACCES、PowerShell 標記、10 秒逾時、scenario）、docstring、design（第 22 輪、Windows、Risks 的檔案系統存取與逾時）、README、idd-edit SKILL（權限規則對 `--body`／`--reason` 的影響）、CHANGELOG（第 22 輪、第 21 輪加註、Changed）。驗證：`spectra validate`。
- [x] 27.4 Verify 第 21 輪（只審第 22 輪的差異）；沒有 HIGH 以上，就把 PR #408 標為 ready，合併留給使用者。驗證：#351 的 verify 留言（6257481651）。
- [x] 27.5 27.4 的結果：第 21 輪 FAIL，findings 37（HIGH 3／MEDIUM 12／LOW 11／INFO 11）。HIGH：相對路徑片段未正規化（`archive//`、`.claude/./.idd`、中間的 `..`）；DA 因 session 額度未完成。MEDIUM：第 22 輪丟掉 repo 外指名 `.claude/.idd` 的情況、`.claude/` 下的 worktree 誤觸發、`cd archive`、逾時即放行、量測 fixture 在 `~/.claude/` 下。

## 28. Verify 第 21 輪修正（第 23 輪）

- [x] 28.1 先寫會失敗的測試（correction-archive）：`archive//`、`.claude//.idd`、`attachments/../archive`、`.idd/./archive`、兄弟目錄的相對與絕對 `cd`、`cd archive`、`pwsh -c` 從 Bash、檢查卡住時拒絕；放行：`.claude/worktrees/wt` 下的 `archive/…`。驗證：10 條在 cd81099 上失敗。
- [x] 28.2 hook：片段先 POSIX 正規化；`_relative_archive_reference` 回傳指名的 `.claude` 目錄，`_names_archive_holder` 只在文字符合後 stat 它們；`cd archive`；工作目錄須是 `.claude/.idd` 或 `.claude` 本身；`_near_archive` 加 lru_cache；`pwsh`／`powershell` 觸發 PowerShell 標記；5 秒 watchdog（不採用 `onFailure: "block"`）。驗證：correction-archive 387 條全綠；`~/.claude` 以外的 fixture 上，歸檔附近 68,040 筆網格與 21 個相對路徑情境以真實 bash／zsh 比對全擋；使用者真實紀錄中無歸檔目錄的誤擋 0、歸檔附近 55；`run-all-tests.sh` 63 個 suite 全綠。
- [x] 28.3 文件：spec（正規化、指名的 `.claude/.idd`、`cd archive`、worktree、5 秒 watchdog、POSIX normpath）、docstring（規則、接受清單、walker 清單）、design（第 23 輪、`onFailure` 不採用的理由、Risks）、README、idd-edit SKILL、CHANGELOG。驗證：`spectra validate`。
- [ ] 28.4 Verify 第 22 輪（只審第 23 輪的差異，DA 重跑）；沒有 HIGH 以上，就把 PR #408 標為 ready，合併留給使用者。驗證：#351 的 verify 留言。
