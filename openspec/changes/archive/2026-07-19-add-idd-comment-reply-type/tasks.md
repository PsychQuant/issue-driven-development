## 1. SKILL.md — reply 型契約落地

- [x] 1.1 在 plugins/issue-driven-dev/skills/idd-comment/SKILL.md 的型別總表加入第 7 型 `reply`（用途「human-facing 逐點回覆」、必填 `--points-from`、emoji header 🧑‍🏫 或等價），並在 Step 2 validation 表加入「reply → `--points-from` 必存在」列（spec requirement: Reply comment type with per-point structure）。完成判準：缺 `--points-from` 的 reply invocation 依表被拒；新 suite 斷言 (a) 命中。
- [x] 1.2 新增 `#### Template: reply` 模板段：每點「verbatim blockquote → 處理說明（哪裡改、怎麼改、cross-link）→ 錨定（commit / PR / merge SHA）→ 狀態（✅ / ⏳ open）」、結尾整體狀態行、metadata marker `<!-- idd:comment type=reply date=... points-from=... calibrated=yes|no -->`（spec requirement: Reply comment type with per-point structure）。完成判準：模板含全部四個 per-point 元素與 marker 欄位，內容審查對照 design.md Implementation Contract。
- [x] 1.3 新增「Points-source 三層解析」步驟：顯式 comment URL / `issue-body` → 預設 issue body Original text blockquote → fallback 要求使用者貼原文；明文 verbatim 鐵律（禁止 paraphrase 對方原文）。完成判準：三層順序與 verbatim 禁令逐字可 grep；spec `Points-source resolution` 兩個 scenario 對得上。
- [x] 1.4 新增「verify-before-claim gate」步驟：每點宣稱已解決前以 `git log --grep "#N"` / PR merge 狀態驗證證據，無證據的點必須寫 open / pending；註明與 idd-close Step 1.6 semantic gate 同族、prose 紀律不另立 helper script（design D6）。完成判準：gate 字句可 grep，含「無證據不得宣稱完成」的禁令。
- [x] 1.5 新增「perspective-writer soft integration」步驟：`check-plugin-presence.sh perspective-writer perspective-writer` 命中 → `Skill(perspective-writer:perspective-writer)` calibration（轉交 resolved `--mention` login 與 target repo `.claude/rules/correspondence-<person>.md` 路徑，若存在）；缺席 → 印兩行安裝指令 literal（`claude plugin marketplace add PsychQuant/perspective-writer`、`claude plugin install perspective-writer@perspective-writer`）並照 post。明文「不新增 install-time dependencies 條目」（spec requirement: Perspective-writer soft integration with graceful degrade）。完成判準：座標、兩行 literal、degrade 行為三者可 grep；新 suite 斷言 (b)(d) 命中。
- [x] 1.6 新增執行序不變量段：referent 錨定（verbatim 引文、verify-before-claim、SHA / 引用固定）完成後才進 calibration；calibration 不得改動錨定事實（SHA、file / theorem 引用、verbatim 引文），違反即 bug（spec requirement: Anchoring precedes calibration）。完成判準：不變量字句可 grep；新 suite 斷言 (c) 命中。
- [x] 1.7 在 SKILL.md Step 0 bootstrap TaskCreate 清單補 reply 型專屬 stage tasks（points 解析 / verify-before-claim / calibration or degrade），並於「與其他 idd-* skill 的關係」表與鐵律段補 reply 是 closing summary 加項、egress 沿用 gh-egress `--scrub-attested`（有 mention 時 `--mention-attested`）（spec requirement: Additive audit posture and egress discipline）。完成判準：bootstrap 清單含新 stage tasks；additive 語意與 egress 紀律可 grep。

## 2. Drift-guard 測試

- [x] 2.1 [P] 新增 plugins/issue-driven-dev/scripts/tests/idd-comment-reply/test.sh（跟隨既有 suite 慣例與 assert-helpers）：斷言 SKILL.md 含 (a) Step 2 表的 reply 必填 `--points-from` 列、(b) 兩行 degrade 安裝指令 literal、(c) 執行序不變量字句、(d) presence-check 座標 `perspective-writer perspective-writer`。完成判準：單跑 `bash plugins/issue-driven-dev/scripts/tests/idd-comment-reply/test.sh` 綠燈；故意刪 SKILL.md 任一元素時紅燈（RED 驗證後還原）。
- [x] 2.2 跑 `bash plugins/issue-driven-dev/scripts/run-all-tests.sh` 全綠（38 → 39 suites），特別確認 docs-catalog-sync 與 idd-caller-registry 未因文件改動翻紅。完成判準：aggregator 輸出 0 fail。

## 3. 文件同步

- [x] 3.1 [P] docs/commands.md：`/idd-comment` 摘要行的型別列舉補 `reply`，並在 `### /idd-comment` 段補 `--points-from` 語法與一句 reply 用途。完成判準：兩處可 grep；型別列舉與 SKILL.md 總表一致。
- [x] 3.2 [P] docs/workflows.md 與 plugins/issue-driven-dev/README.md：matrix 行與型別摘要（decision / note / question …）補 reply。完成判準：兩檔的型別列舉與 SKILL.md 一致（docs-catalog-sync 慣例的人工對照）。
- [x] 3.3 plugins/issue-driven-dev/CHANGELOG.md 加版本段（feature：`--type=reply`、soft perspective-writer integration、graceful degrade、drift-guard suite），版本號依 repo 慣例 minor bump；.claude-plugin 兩個 manifest（plugin.json 與 root marketplace.json entry）同步同一版本字串。完成判準：三處版本字串一致；changelog 段涵蓋四個要點。

## 4. 驗證與收尾

- [x] 4.1 Dogfood：在測試 issue（或 #269 本身）以 `--points-from=issue-body` 走一次 reply 流程之乾跑（draft 產出、不實際 post 到無關 issue），核對 per-point 四元素、degrade / calibration 分支各一次（透過暫時 rename cache 目錄模擬缺席，事後還原）。完成判準：兩分支的 draft 皆符合模板、缺席分支印出兩行安裝指令。
- [x] 4.2 spectra validate 通過 + `spectra analyze` 無 Critical/Warning，PR 依 repo 慣例 Refs #269。完成判準：validate exit 0；PR body 含 spec delta 摘要。
