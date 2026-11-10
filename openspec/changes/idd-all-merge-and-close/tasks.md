## 1. 開工前提

- [x] 1.1 確認 #383 已 merge 進 main，並從最新的 main 開實作 branch。完成時：實作 branch 的起點包含 #383 的 commit，`plugins/issue-driven-dev/skills/idd-all/SKILL.md` 已含 #383 的 meeting 停點。驗證：`gh issue view 383 --json state` 為 CLOSED 或其 PR 為 MERGED；`git log --oneline origin/main` 看得到 #383 的 commit。

## 2. verify gate helper（TDD）

- [x] 2.1 [P] 依 requirement「Verify gate parsing fails closed」與「verify 乾淨的定義與解析失敗即不乾淨」，先寫 `plugins/issue-driven-dev/scripts/tests/verify-gate/test.sh` 與 fixture：乾淨（PASS、0／0）、只剩 Follow-up（判定 clean）、有 Blocking、有 In-scope fix、判定 FAIL、缺分類表、分類欄出現第四種值、判定 PASS 卻有 Blocking、檔案不存在、缺參數。每個 case 斷言 JSON 的 `status` 與結束碼（0／1／2／64）。完成時：測試存在且因 helper 尚未存在而失敗（RED）。驗證：`bash plugins/issue-driven-dev/scripts/tests/verify-gate/test.sh` 以非零結束並列出全部 case 失敗。
- [x] 2.2 依 design 的 Implementation Contract 實作 `plugins/issue-driven-dev/scripts/verify-gate.py`：讀 `--comment-file`，解析判定行與 Step 5a 分類表，輸出一行 JSON，結束碼照契約；任何讀不出、對不上或互相矛盾的情況都回報 `unparseable` 並在 `reason` 寫明。完成時：2.1 的測試全數通過。驗證：`bash plugins/issue-driven-dev/scripts/tests/verify-gate/test.sh` 以 0 結束。

## 3. 文字契約測試（TDD）

  - ASSUMPTION（apply 時加，2026-11-02）：拿 5 份真實的 verify 留言（#383 round 5、6，PR #418 round 17–19）跑 helper，全部是 `unparseable`：Action 欄實際出現 `No action`、`In-scope`、`Blocking（證據缺口）` 這類三類以外或帶註解的值，粗體標籤（`**更正**`）也會被誤認成判定行。helper 照契約維持嚴格（判定行限粗體大寫英文字；Action 只收三個值，只剝掉外圍的 `*`、`_`、反引號）。為了讓 gate 在實務上會通過，另在 `skills/idd-verify/SKILL.md` Step 5a 補上報告格式的 producer 規則（恰好一行判定、Action 只填三個值、不成立的意見另列、零筆時保留表頭），並把本地模式的報告範本補上 `### Aggregate` 與 `Action` 欄。這個檔案不在 proposal 的 Affected code 清單內，verify 時請一併審。

- [x] 3.1 [P] 寫 `plugins/issue-driven-dev/scripts/tests/merge-and-close-contract/test.sh`，鎖住三層文件一致：idd-all 的 SKILL.md 有 close stage、四道 guardrail、`ORCHESTRATED BY /idd-all` 指示、回報的 `Done:`／`Undo:`／`Stopped:`；idd-close 的 SKILL.md 有停點的預設表（apply 時加到六個，見 5.1 的 ASSUMPTION）；MANIFESTO 的 auto-merge 段同時寫出兩個理由、不再把 auto-merge 交給 #37；idd-all 的 SKILL.md、MANIFESTO 與 `references/parallel-orchestration.md` 不再出現「永不 auto-close」「永遠不 auto-merge」「Stop at verified」這類舊句；idd-all 的 description 含 meeting 例外。完成時：測試存在且在現行文件上失敗（RED）。驗證：`bash plugins/issue-driven-dev/scripts/tests/merge-and-close-contract/test.sh` 以非零結束，失敗訊息逐項列出。

## 4. idd-all

- [x] 4.1 依 requirement「Unattended fix loop covers in-scope findings with a two-round limit」、「無人在場時 In-scope fix 也要修完並重跑 verify」與「有人在場時照舊不自動修」，改寫 Phase 4：unattended 時每輪 verify 後呼叫 `verify-gate.py`，`not_clean` 就修 Blocking 與 In-scope fix 並重跑，最多 2 輪；滿 2 輪仍不乾淨或 `unparseable` 就停在 verified；attended 時照舊交回使用者。完成時：Phase 4 的流程與 design 的終點行為表一致。驗證：3.1 測試中 Phase 4 的斷言通過；人工比對 Phase 4 與終點行為表的對應列。
- [x] 4.2 依 requirement「Clean verify leads to merge and close」與「Merge guardrails gate every automatic merge」、design「merge 前的四道 guardrail」、「close 停下時 PR 已經 merge」與「--review 照舊停在 verified」，在 PR mode 新增 close stage：依序檢查 gate、`gh pr checks`（pending 最多等 15 分鐘、無 check 視為通過）、Step 0.8 掃描、idd-all 自組的 squash subject 與 body；全過才 `gh pr merge --squash`、`git fetch`、呼叫 `/idd-close` 並帶 `ORCHESTRATED BY /idd-all`；`--review`、`--in-chain`、`type=meeting` 不進入 close stage；close 停下時回報「PR 已 merge、issue 仍開」與 `/idd-close #N`。完成時：close stage 寫進 SKILL.md，Step 0 的 TaskCreate 清單有對應 task。驗證：3.1 測試中 close stage 與 guardrail 的斷言通過。
- [x] 4.3 依 requirement「Direct-commit path stays on current branch and skips PR」與「direct-commit 先 push 再 close」，在 direct-commit mode 的 close stage：在預設 branch 上 `git push origin HEAD` 成功後才呼叫 `/idd-close`；不在預設 branch 或 push 被拒就停在 verified 並寫明原因；Phase 5 的 log 改為 `→ direct-commit path: skipping PR`。同時依 requirement「PR path preserves v2.40.0 behavior」更新 PR path 的敘述，寫明 PR 建立後接著進入 close stage。完成時：兩條 path 的敘述與 spec delta 一致。驗證：3.1 測試對應斷言通過；人工比對 spec delta 的 scenario。
- [x] 4.4 依 requirement「Run report states what was done and how to undo it」與「結尾回報照 Foresay 的 operation 格式」改寫 Phase 6：成功時以 `Done:` 開頭，列 merge commit 或 push 的 commit、closed issue 與 closing summary 連結、改動檔數與增刪行數、follow-up、residue、distribution sync 結果、跑了與缺少的 verify reviewer，最後 `Undo:` 列 `gh issue reopen <N>` 與 `git revert <sha>`；停下時只列實際做到的步驟並加 `Stopped:`。完成時：Phase 6 的兩種輸出範例寫進 SKILL.md。驗證：3.1 測試對應斷言通過；範例中的欄位與 spec scenario「Successful run report」逐項對得上。
- [x] 4.5 依 requirement「idd-all multi-issue batch mode (conflict-class-ordered, sequential)」與「吸收 #387 的 meeting 例外」，改寫 batch mode：每張各自 merge 並 close，merge 後 `git pull --ff-only` 再處理下一張、失敗就停止批次；meeting issue 停在 diagnosed 或 planning；`references/parallel-orchestration.md` 的「Stop at verified」改成相同敘述。完成時：batch mode 敘述與 spec delta 三個 scenario 一致。驗證：3.1 測試的舊句斷言通過；人工比對 scenario。
- [x] 4.6 依 removed requirement「Verify is the terminal phase regardless of mode」與「文件三層一起改」，清理 idd-all 的 SKILL.md 其餘舊說法：frontmatter description（寫明 verify 乾淨即 merge 並 close、meeting 例外）、開頭摘要、Verify is the terminal phase 段、鐵律、範例的 `Next:` 行、Phase 0.5.1 把 close 說成不可逆的句子。完成時：SKILL.md 不再出現與 close stage 矛盾的段落。驗證：3.1 測試全數通過；`bash plugins/issue-driven-dev/scripts/tests/skill-description-contract/test.sh` 維持通過。

## 5. idd-close

- [x] 5.1 依 requirement「idd-close honors the orchestrated directive from idd-all」與「idd-close 的 idd-all 呼叫指示」，在 `plugins/issue-driven-dev/skills/idd-close/SKILL.md` 加入 `ORCHESTRATED BY /idd-all` 指示的偵測與五個停點的預設：Step 1.55 與 Step 1.6 的警告停下不 close、Step 3.5 照 IC_R011 預設開 follow-up、Step 3.6 的 Residue 記為殘留、Step 6.5 在 attended 照問而 unattended 略過並列出命令；沒有指示時行為不變。完成時：預設表與各 Step 內的分支都寫進 SKILL.md，Step 0 的 TaskCreate 描述提到指示。驗證：3.1 測試中 idd-close 的斷言通過；人工確認無指示時每個 AskUserQuestion 都還在。

  - ASSUMPTION（apply 時加，2026-11-02）：idd-close 的 Step 6.3 doc-sync 在 PR 已 merge 後會直接 commit 到預設 branch，那個 commit 沒有經過 verify。orchestrated 模式下改成不 commit、列進 closing summary 的 `### Doc-sync 檢查`（第六個預設），spec delta 的 idd-close requirement 與 design 的停點表一併補上。direct-commit 的 push 前加掃 close 類關鍵字（4.3 的範圍），理由見 design。fix 輪數：spec 原寫「at most 2 fix rounds」與 scenario（第 2 輪 verify 仍不乾淨即停）不一致，改成「at most 2 verify rounds（one fix pass between them）」，與 spectra-discuss 結論一致。

## 6. 文件

- [x] 6.1 [P] 依「文件三層一起改」改寫 `plugins/issue-driven-dev/MANIFESTO.md`：〈auto-merge 的合法性與限制〉改成兩個理由並列（verify 保證改得對；可逆讓它免事前確認但必須事後回報），revert 不對稱段改用來說明 distribution sync 為何仍要確認，指向 #37 的句子改指 #392；〈verify-gated 是 terminal 預設 disposition〉改寫成 verify 乾淨即 merge 並 close；自動化 caller 那段改寫。完成時：MANIFESTO 與 close stage 不矛盾。驗證：3.1 測試的 MANIFESTO 斷言通過。
- [x] 6.2 [P] 同步其餘文件的 idd-all 終點敘述：`plugins/issue-driven-dev/CLAUDE.md` 的 idd-all 列與 PR vs Direct-commit 段、`plugins/issue-driven-dev/README.md`、`plugins/issue-driven-dev/references/usecase-routing.md`、`plugins/issue-driven-dev/references/pr-flow.md`、`docs/commands.md`。完成時：這些檔案不再寫 idd-all 停在 verified（`--review`、chain、meeting 的例外除外）。驗證：`grep -rn "停在 verified" plugins/issue-driven-dev docs` 的剩餘結果都屬於上述例外，逐筆人工確認。

- [x] 6.3 依 2026-11-02 的決定（#392 comment 6562727408）同步本 repo 以外的兩份規則，避免規則與實作互相矛盾：使用者的全域 `CLAUDE.md`加一節「`/idd-all #N` 本身就是確認」（在 verify 乾淨時的 merge／push 與 close），〈GitHub 紀錄不用問〉裡「關閉 issue（照 IDD，close 由維護者決定）」改為除外 `/idd-all`；dev 層 `.claude/rules/human-vs-claude-skills.md` 把「結案只有人能決定」改成「人可以手動結案；`/idd-all` verify 乾淨時自己結案」。完成時：兩份規則不再說 close 一律由人決定。驗證：`grep -n "close 由.*決定\|只有人能決定" ~/.claude/CLAUDE.md .claude/rules/human-vs-claude-skills.md` 沒有與 close stage 矛盾的結果；全域規則所在的設定 repo 有本機 commit。

## 7. 收尾

- [x] 7.1 CHANGELOG 以 BREAKING 記錄 idd-all 終點改變並寫明 `--review` 可取回舊行為；以 minor 版號同步 `plugins/issue-driven-dev/.claude-plugin/plugin.json` 與 `.claude-plugin/marketplace.json`；在 #387 留言標明已併入本 change。完成時：版本號一致、全部測試通過。驗證：`bash plugins/issue-driven-dev/scripts/run-all-tests.sh` 除既知與本 change 無關的失敗外全數通過；`jq` 讀出兩個檔案的版本號相同；#387 有留言。
  - ASSUMPTION（apply 時加，2026-11-02）：main 的 CHANGELOG 已改成「Version number left to the merge, as in PR #442」——同時有 #418（3.5.1）、#426（3.6.0）在飛，先寫死版本號只會撞號。所以本 change 把條目寫在 `[Unreleased]`（BREAKING 標在 Changed 第一條），`plugin.json`／`marketplace.json` 的版本號留給 merge 時決定；文件裡也不寫版本號，只寫 #392。7.1 的「版本號一致」在 merge 時驗。

- [x] 7.2 手動驗收：在一個拋棄式 repo（可沿用 #400 的 scratch repo）以 `claude -p --plugin-dir plugins/issue-driven-dev` 跑兩張 trivial issue：一張 unattended PR mode，確認 PR 被 squash merge、issue 被 close、回報有 `Done:` 與 `Undo:`；一張帶 `--review`，確認停在 verified、沒有 merge。完成時：兩張的結果與 spec scenario 一致。驗證：把兩次的 PR URL、issue 狀態與回報原文貼在 #392 的驗收留言。（2026-11-10 在 sandbox 跑兩張，head `3fc3d41`：PR mode 那張 `close-stage.py run` 回 `merged` 並結案；`--review` 那張回 `stopped`、PR 留著。紀錄在 #392 的 Acceptance comment。第三張在 `d38d132` 上跑（sandbox #18）：Phase 5 的 `pr-check` 回 `open`，run 沒有停下來問就開了 PR，紀錄在 comment 6763687583。）
  - 進度（2026-11-02）：做了 scripted 驗收，沒做 `claude -p` 的完整端到端。把 SKILL.md 裡 Phase 5c.1–5c.3 的 bash 原文抽出來，在 `PsychQuant/idd-cloud-sandbox` 對真的 PR 跑：trap commit 停在 guardrail 3（PR #9）、乾淨 PR 被 squash merge 且 issue 沒被 GitHub 自動關（PR #10）、direct-commit 的 trap 不推、乾淨的推上 main、不在預設 branch 時停下。第一次跑抓到一個 bug：verify 報告的選擇式用 `([ \t]|$)`，jq 的 `$` 只比對字串結尾，標題後接換行就選不到，close stage 讀到空報告（已修，合約測試改成直接執行 SKILL.md 裡的 jq 程式）。還沒驗的：模型照著 SKILL 走完整條 pipeline、`/idd-close` 收到 ORCHESTRATED 指示時的行為、`--review`。`claude -p` 需要另外設定權限（不用 `--dangerously-skip-permissions`），留到 verify 之後由維護者決定要不要跑。**更正（verify round 2，#25）**：這次 sandbox 跑的是 round 1 之前、寫在 SKILL.md 裡的 bash，那段已在 round 1 整段換成 `scripts/close-stage.py`；現行 helper 的 merge 與 push 只在假的 gh 下測過（`tests/close-stage/`），還沒碰過真的 GitHub。

## 8. verify round 1 修正（#392 comment 6563410294）

- [x] 8.1 `verify-gate.py`：fence 依字元與長度配對、未關閉即 unparseable；GFM 表格（無前導 `|` 的列、一個 `-` 的分隔列）；表格外寫著三類之一的列與加了裝飾的 `Action` 表頭即 unparseable；FAIL 卻沒有 Blocking 與 In-scope fix 即 unparseable；`--expect-sha` 要求恰好一行 `**Reviewed**` 且是該 commit。完成時：`tests/verify-gate/` 全數通過，含新增的 13 個情境。
- [x] 8.2 `scripts/close-stage.py`（init／gate／run）與 `tests/close-stage/`：run-state、本帳號的報告、SHA 綁定、CI 寬限、strict trap regex、PR 對應、`--match-head-commit`、merge 後確認 `MERGED`、direct-commit 推出範圍。完成時：`tests/close-stage/` 全數通過，每一道停下時都斷言沒有 merge 或 push。
- [x] 8.3 idd-all：Step 0.7 寫 run-state；Phase 4 改用 `close-stage.py gate --sha`，`--review`／`--in-chain` 不修 In-scope fix；Phase 5 的 PR body 照 gate 結果寫、不寫死 issue 號；Phase 5c 改成一次 helper 呼叫（背景執行）、`/idd-close` 帶 `--repo`、指示不含 `#數字`、結案要有 closing summary；batch 每張結束都回到預設 branch。idd-verify Step 4 樣板加 `**Reviewed**` 與格式規則。idd-close 記下 1.55 的已知代價、只認 args 裡的指示、Step 3.5 照 `AI_LOW_BAR_ISSUE_FILING`。完成時：合約測試通過。
- [x] 8.4 規格與文件：IC_R011 spec delta 與 reference、attended requirement、guardrail 與 gate 條款；docs/workflows.md、pr-flow.md、idd-all-chain、MANIFESTO（分 mode 的 guardrail）、usecase-routing。完成時：`spectra validate` 通過，`grep` 找不到舊 doctrine。
- [x] 8.5 全域規則：〈誰來執行〉的「唯一的例外」改成兩個例外；觸發條件從 `/idd-all #N` 改成任何 `/idd-all` 呼叫。完成時：全域規則所在的設定 repo 有本機 commit。

## 9. verify round 2 修正（#392 comment 6564044471）

- [x] 9.1 `verify-gate.py`：判定行的 blocking 數必填且與表格一致（in-scope、follow-up 有寫也要一致）；Action 不是最後一欄的表、表格外寫著三類之一的列判 unparseable；`--expect-base`；`**Reviewed**` 要完整 40 字元。完成時：`tests/verify-gate/` 全數通過。
- [x] 9.2 `close-stage.py`：init 的每個值必填（`--review`／`--in-chain` 為 yes／no、`--requested-path`）；run-state 24 小時失效、結果檔每次 run 先刪；降級即停；issue 作者與最後編輯者的寫入權限；`origin` 必須是這個 repo；發佈型 workflow 即停；fork PR 不算；merge queue 即停；CI 寬限期與 `pull_request` check；CI 後再判 gate；merge 後重讀確認、仍 OPEN 就關 auto-merge；direct-commit 推 verified sha、推前再確認；任何例外都輸出 stopped／unparseable；新增 `confirm-close`。完成時：`tests/close-stage/` 全數通過，含 7 個突變中 6 個被抓到（推 HEAD 的突變被推前的再確認擋下，屬預期）。
- [x] 9.3 idd-all：Step 0.2 的 yes／no 旗標、Phase 0.5 印出 requested path；Phase 4 以 `--branch` 呼叫 verify、gate 帶 `--base`、gate 讀不出來時照舊處理 Blocking；Phase 5 只寫 gate 狀態、`--review` 的措辭、沿用已開的 PR；Phase 5c 的排除表與 guardrail 表、`/idd-close` 只在 merged／pushed 後呼叫並指定 clone、`confirm-close`；Phase 6 的 Undo 完整步驟、Spectra archive 提醒、follow-up 合併、清理；batch 只在 PR mode 切回預設 branch。idd-verify 的 `**Reviewed**` 寫範圍與 `BASE_SHA` 的定義。完成時：合約測試通過。
- [x] 9.4 文件與規格：plugin CLAUDE.md、config-protocol.md 的 direct-commit 不再寫「不 push」；idd-close 的「結案不可逆」句改寫；parallel-orchestration 的 spec delta 與 reference 改成 PR mode 才切回；hitl-modes delta 補上 run-state 必填、降級、作者權限、範圍、merge queue、CI、gate 條款。完成時：`spectra validate` 通過。

## 10. verify round 3 修正（#392 comment 6566486203；範圍決定 comment 6566557673）

- [x] 10.1 `close-stage.py`：意圖確認的閘門（comment 作者、Clarity Surface、deferred 紀錄、Plan tier）；只認這次 run 開始之後、有寫入權限的帳號貼的最新報告；`reset` 子指令；origin 的 host 與 push URL、推完向 GitHub 確認；PR commit 從本機 git 讀；branch 落後即停；改到 CI 即停；發佈型 workflow 掃預設 branch、略過 tag-only；`pull_request` 觸發的判定看 trigger 區塊；CI 集合穩定 90 秒；merge 失敗後重讀狀態；GraphQL 字串用 `-f`；run-state 不經過 symlink。完成時：`tests/close-stage/` 全數通過（205）。
- [x] 10.2 `verify-gate.py`：HTML 區塊與重複計數判 unparseable。完成時：`tests/verify-gate/` 全數通過（150）。
- [x] 10.3 idd-all：Phase 0.4 `reset`、Step 0.7 拿不到 N 報錯且 init 失敗只警告、chain 與 `--review` 維持原本的 verify 範圍、attended 續跑、Phase 5c 兩張表、續跑只沿用自己開的 PR、前景執行的 timeout、abort 時 `reset`、`--review` 報告寫 gate 狀態。idd-verify 三類計數與 HTML 規則；idd-close 的 orchestrated Step 3.5 也照 `# Disable IC_R011`。完成時：合約測試通過（77）。
- [x] 10.4 規格與文件：hitl-modes 新增「意圖確認過才收尾」requirement 並更新 guardrail 與 push scenario；existing-work-lookup 的「結案不可逆」改寫；MANIFESTO 加意圖確認；proposal、design 的「四道」改成指向完整清單；全域規則改成指向 skill 的封閉列舉。完成時：`spectra validate` 通過。

## 11. verify round 4 修正（#392 comment 6567217569；決定 comment 6567272352：保留 unattended 自動收尾）

- [x] 11.1 `verify-gate.py` 改讀 GitHub 渲染後的 HTML（`--html-file`）：判定行與 Reviewed 行要自成一段、表格照 GitHub 畫出的算（含 `<details>` 裡的）、第四個 Action 值 `Rejected` 與判定行的 rejected 數、PASS 的覆蓋率行要滿、表格外帶 pipe 的 findings 列判 unparseable；fixture 由 `render-fixtures.sh` 以 GitHub 渲染器產生並 commit。完成時：`tests/verify-gate/` 全數通過（244），第 4 輪的五個重現（HTML 第 4 型、清單裡的 fence、單行註解包住的 table、延續列、details 裡的 Blocking）都是 unparseable。
- [x] 11.2 `close-stage.py`：comment 帶 `body_html`；報告只認本帳號、最新一則 verify comment 必須是 `## Verify: #N`、時間窗不放寬；run 開始後別人插手即停（issue comment 新增或編輯、正文編輯、comment 被刪、PR 的 comment／review／draft／changes requested）；意圖檢查改看 tier＋interaction、最新 Diagnosis 的 `- **Reason**:` 記錄行、unattended 的 Proposed Corrections、所有 Clarity block 的 surfaced／deferred 格；`Rejected` 即停；CI 等完重查預設 branch、gate 與 PR 上的人；origin 的每個 URL、空 userinfo；`--cwd` realpath；merge／push 前先寫「可能已發生」的結果；仍 OPEN 時記 `refused`。完成時：`tests/close-stage/` 全數通過（279）。
- [x] 11.3 skills：idd-verify 的格式規則（渲染後 HTML、`<details>` 可用、Rejected 留在表內、覆蓋率）；idd-diagnose 的 Choice Default Record 與 registry literal `unattended-auto-Step-4-choice-default`；idd-all 的 Step 0.4／0.7（reset 移到 init 失敗分支）、Phase 4 的 gate（`--review`／`--in-chain` 只比對 head）、Phase 5 的 PR body（Rejected 不承諾 merge）、Phase 5c 兩張表與已知限制、Phase 6 的 Undo（`refused` 不列）與 Action items。完成時：合約測試通過。
- [x] 11.4 規格與文件：hitl-modes 的意圖 requirement 改寫、新增「別人插手」requirement 與 scenario、guardrail 與 gate 條款；IC_R011 spec 與 reference 補 `# Disable IC_R011`；design 第 4 輪一節與 Implementation Contract；proposal 的範圍；MANIFESTO 與 CHANGELOG。完成時：`spectra validate` 通過。

## 12. verify round 5 修正（#392 comment 6568097813；決定 comment 6568180861：威脅模型、Stage 1）

- [x] 12.1 共用模組：`lib/rendered.py`（gate 與 close stage 讀 GitHub 的渲染結果）、`lib/workflows.py`（發佈偵測，讀不懂即當成會發佈）；close-stage.py 拆出 `lib/ghread.py`、`lib/intent.py`，主檔 800 行以內。完成時：各 suite 全數通過。
- [x] 12.2 `verify-gate.py`：所有可見文字行（判定、表格外 findings 列）、表格儲存格不算判定、乾淨報告必須有完整覆蓋率行、回報 `high_follow_up` 與 `process_gaps`、崩潰時 unparseable。完成時：`tests/verify-gate/` 全數通過（272），第 5 輪的重現（tight list、details 原文、清單裡的第二個判定）都是 unparseable。
- [x] 12.3 `close-stage.py`：報告貼出後被編輯或被藏起來即 unparseable；Rejected、嚴重 Follow-up、Process Gaps 即停；意圖檢查讀渲染結果，紀錄與 Proposed Corrections 掃所有 comment、Decision comment 回應；Diagnosis 選取與 Phase 2 一致；bot 豁免；issue 的 state／label／標題／關閉與 PR 的作者、label、標題、描述；GraphQL 讀不完即停；PR commit 都要引用 #N；發佈偵測改用 workflows 模組。完成時：`tests/close-stage/` 全數通過（350）。
- [x] 12.4 skills 與文件：idd-all 的 description、Phase 0.5 從 `origin/<default>` 開 branch、reset 移到 Step 0.5.1 之後、Phase 5c 兩張表、威脅模型與已知限制、Action items；idd-verify 的格式規則；idd-diagnose 的紀錄位置；spec delta、design、proposal 的 Impact、MANIFESTO、CHANGELOG。完成時：`spectra validate` 通過、合約測試通過。

## 13. verify round 6 修正（#392 comment 6568962908）

- [x] 13.1 close-stage 的 `gate_stop`、`lib/workflows.py` 遞迴與 merge 事件、intent 的格式走樣與 Decision 認定、verify-gate 的 Severity 與表格外標籤、`--no-track`。close-stage suite 改平行（`scenarios.sh`＋`run_parallel.py`）。完成時：`tests/close-stage/` 378、`tests/verify-gate/` 278 全數通過。

## 14. verify round 7 修正與 2026-11-10 的決定（#392 comment 6573633253；決定 6761657951、6761899504）

- [x] 14.1 spec delta 先寫：時間軸計數、合併門檻與 `low_in_scope`、Proposed Corrections、tier、CI 這一道、發佈偵測的具名限制、run report 的三個欄位。完成時：`spectra validate` 通過，每一項有 Example。
- [x] 14.2 時間軸計數：`lib/ghread.py`、`lib/intent.py` 改比 `filteredCount`，沒有這個欄位就停；假 `gh` 在 query 沒要 `filteredCount` 時不回它；加兩個由 sandbox 真實回應錄下的 fixture。完成時：新情境先在 `c853975` 上失敗、修正後通過；對 sandbox PR #12 與 issue #11 唯讀實測不再停。
- [x] 14.3 `verify-gate.py`：輸出 `low_in_scope`；`clean` 的 reason 改成符合門檻；補 `83d62f9`、`c853975` 沒有的測試（LOW／INFO／P3 的 In-scope fix 是 clean、MEDIUM 以上是 not_clean、Severity 欄取最嚴重的字）。完成時：`tests/verify-gate/` 全數通過。
- [x] 14.4 `lib/intent.py`、`close-stage.py`：拿掉 tier 與 Proposed Corrections 的停點；結果帶 `proposed_corrections`、`low_in_scope`。完成時：`corrections`、`corrections-verify`、tier 的情境改成 merged 並斷言計數。
- [x] 14.5 `close-stage.py` 的 CI 這一道呼叫 `idd-ci-gate.sh`（PR 與 direct-commit），結果帶 `remote_ci_failed`。完成時：spec Example 表的每一列有一個情境。
- [x] 14.6 第 7 輪 finding 2、3、11、12、14、15、16：finding 2 → 釐清問題不看標題、在任何位置都讀（`open_clarity_row`）；3、12 → 第二個判定與表格外的分類以「行的開頭」判定，有 Severity 欄而沒有 Action 欄的表也拒讀，句子中間的字不讀（具名限制）；11、14 → 降級標記不分大小寫、在可見文字的任何位置都算，PASS 的報告必須有 `R / T reviewers completed`；15 → 較深的小標題不結束一節；16 → 補上 `release`、`workflow_call` 的情境。每一項先有失敗的測試（16 是 `83d62f9` 已修、補測試）。完成時：`tests/verify-gate/` 431、`tests/close-stage/` 481、`tests/merge-and-close-contract/` 全數通過。
- [x] 14.7 idd-all 的 SKILL.md（Phase 4 的 `low_in_scope`、Phase 4.5 與 close stage 的關係、Phase 5c 兩張表、已知限制、Run report）、idd-verify 的 SKILL.md（樣板的 reviewers 行與格式規則）、MANIFESTO、CHANGELOG（合併 main 時 Unreleased 的條目被併進 3.6.0，已移回）。全域規則不必改：它只指向 skill 的封閉列舉。完成時：合約測試通過。
- [x] 14.8 第 7 輪的 LOW 合成一張 follow-up issue（#481，20 項未處理、3 項已在 `7a4c3d1` 處理）；#392 正文的 Blocking 改成現況。
- [ ] 14.9 重跑 7.2 的端到端（兩張），再跑第 8 輪 verify。

## 15. 權限寫進 skill（維護者 2026-11-10 的決定，#392 comment 6763147692）

- [x] 15.1 spec delta 新增 requirement「idd-all states which outward actions it runs without asking」，含兩張 Example 表；`spectra validate` 通過。
- [x] 15.2 `close-stage.py pr-check`：標題或內文提到帳號、close 關鍵字緊鄰 issue 號、預設 branch 有 `CODEOWNERS`、預設 branch 讀不到，四種都回 `ask`（exit 3）；其餘回 `open`。驗證：`tests/close-stage` 的 pr-check 情境先在沒有這個子指令時失敗，實作後通過。
- [x] 15.3 `skills/idd-all/SKILL.md` 新增〈權限〉一節（兩張封閉的表），Phase 5 開 PR 前呼叫 `pr-check`，開了就印 `Undo:`。驗證：`tests/merge-and-close-contract` 的權限檢查。
- [x] 15.4 第 8 輪 verify 在含這一節的 head 上跑（`d38d132`，報告是 #392 comment 6763800725：沒有 HIGH，2 項 MEDIUM 要先修）。

## 16. 第 8 輪 verify 之後的修正（報告：#392 comment 6763800725）

- [x] 16.1 direct-commit 路徑在本機 CI 閘門之後、push 之前，重讀 verify gate 與 run 開始後有沒有別人插手（finding 1）。驗證：`tests/close-stage` 的三個情境（CI 期間沒事、teammate 留言、新的 FAIL 報告），後兩個在修正前會 push。
- [x] 16.2 續跑時更新既有 PR 的正文也先過 `pr-check`；回 `ask` 就不開也不改（finding 2）。〈權限〉兩張表補上「更新 PR 正文」與「開到別人的 repo」。驗證：`tests/merge-and-close-contract` 檢查 Phase 5 的 `pr-check` 在 `gh pr edit` 之前。
- [x] 16.3 idd-all 的 description 與 proposal 不再寫 unattended 的 Plan／Spectra 要停（finding 3）。驗證：contract 測試檢查 frontmatter。
- [x] 16.4 `pr-check`：`@` 前面只要不是字母或數字就算提到帳號，用 character reference 寫的 `@` 也算；空標題回 `ask`；找 `CODEOWNERS` 之前先 fetch 預設 branch（finding 5、7、8）。Phase 5 在同一個 block 設定標題、`git push` 失敗就停（finding 4、8）。驗證：`tests/close-stage` 的 pr-check 情境。
- [x] 16.5 `gh pr checks` 以 1 結束（有失敗的 check）時照樣讀出清單：本機 CI 通過時回報寫出失敗的 check 名稱，remote mode 的停止理由寫出是哪個 check（finding 12）。驗證：`tests/close-stage` 的兩個情境。
- [x] 16.6 文件：`--ci-timeout` 只管等遠端 check 的時間，本機 CI 閘門有自己的時限（finding 11）；〈權限〉寫明 follow-up issue 的建立還沒走 `gh-egress.sh`（finding 13）、PR path 一律 unattended（finding 14）、watcher 與 workflow 的通知是已知限制（finding 17）；task 7.2 補上第三張 sandbox 的結果（finding 10）。
- [x] 16.7 沒有在這個 PR 處理的 finding（6、9、16）開成 follow-up issue #484。finding 15（第 7 輪的發佈偵測改列為已知限制，issue 上沒有 Decision comment）留給維護者確認。

