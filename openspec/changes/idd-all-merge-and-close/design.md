## Context

`/idd-all` 現在的終點是 verified：PR mode 開了 PR 就停，direct-commit mode 留下本機 commit 就停，兩種都請使用者自己 merge、自己跑 `/idd-close`。這條規則寫在三個層級：

- published spec `idd-pr-hitl-modes`：Requirement「Verify is the terminal phase regardless of mode」規定 idd-all MUST NOT auto-invoke `idd-close`；Requirement「PR path preserves v2.40.0 behavior」保證 `/loop` caller 看不到行為變化；Requirement「Direct-commit path stays on current branch and skips PR」規定 direct-commit SHALL NOT push。`parallel-orchestration` 的 batch requirement 寫 SHALL stop at verified。
- `MANIFESTO.md`〈auto-merge 的合法性與限制〉：auto-merge 合法的理由寫明是「verify is the gate」而**不是**「merges are reversible」，並把 auto-merge→auto-close 交給 #37；#37 已以 not planned 結案。
- `skills/idd-all/SKILL.md`：description、Phase 4 到 Phase 6、鐵律、範例都寫死不 merge、不 close；Phase 0.5.1 把 close 說成不可逆。

#392 的使用者決定（Clarity Surface 五題、Diagnosis 確認的兩點、spectra-discuss 的四條結論）都已記在 issue 上，本 design 把它們落成實作契約。2026-11-02 實作前再確認一次 merge 這一步：使用者選「全部自動（照 10-14）」，所有 mode 都不在 merge 前停下（#392 comment 6562727408）。全域規則（`~/.claude/CLAUDE.md`）原本把 push／merge 列為要先確認、且優先於 skill 的「自動執行」，所以同一個變更也在那裡加上 `/idd-all #N` 算是確認的條目。`idd-verify` 已經把 findings 分成 Blocking、In-scope fix、Follow-up 三類，報告開頭有一行 `**PASS / FAIL** — N blocking, M follow-up`。

## Goals / Non-Goals

**Goals:**

- verify 乾淨時，idd-all 自己完成 merge（PR mode）或 push（direct-commit mode）與 close，不停下來問。
- 「乾淨」有明確、可機械判斷的定義，判斷不了時一律當成不乾淨。
- `/idd-close` 被 idd-all 呼叫時，每個會停下來問人的點都有明確的預設。
- 結尾回報讓人事後一眼看出做了什麼、怎麼復原。
- 三個層級的文件同時改，不留互相矛盾的段落。

**Non-Goals:**

- 不改 `/idd-all-chain`；chain 是否跟進由 #393 決定。
- 不改 `type=meeting` 的停點（diagnosed／planning）。
- 不改手動 `/idd-close` 的流程：沒有 `ORCHESTRATED BY /idd-all` 指示時每個問題照舊。手動 `/idd-verify` 只多了報告格式的規則（一行判定、`**Reviewed**` 一行、Action 欄只填三類），流程與「In-scope fix 修完不必重跑 verify」的既有規則不變。
- 不自動做 distribution sync 的不可逆部分（發版、推 marketplace）；無人在場時一律略過。
- 不做 Codex 以外的 verify 改動；雲端 runtime 是 #400 的範圍。

## Decisions

### verify 乾淨的定義與解析失敗即不乾淨

「乾淨」＝最新一輪 verify 的報告判定為 PASS、Blocking 為 0、In-scope fix 為 0。Follow-up 不擋 merge，照既有規則開 follow-up issue。

計數由一支新的 helper 從 verify master comment 的分類表解析，輸出 JSON。表格缺失、欄位對不上、判定行讀不到、或計數與判定行矛盾（判定 PASS 但有 Blocking）時，helper 回報 `unparseable`，idd-all 一律當成不乾淨、停在 verified。理由：這是唯一會把程式碼自動送進 main 的判斷，寧可漏 merge，不可誤 merge。

替代方案：讓 idd-all 的 LLM 直接讀報告判斷。沒採用，因為 merge 的觸發條件必須可重現、可測試；LLM 判斷錯了沒有可檢查的痕跡。

### 無人在場時 In-scope fix 也要修完並重跑 verify

unattended 時，Blocking 與 In-scope fix 一起在同一個 PR 修，修完重跑 verify；修正最多 2 輪（沿用 Phase 4 既有的 `MAX_ROUND`）。2 輪後仍不乾淨就停在 verified。

這與 `idd-verify` 既有的「In-scope fix 修完不必重跑 verify」不同，差異只適用於 idd-all 的自動 merge 路徑：AI 自動修的程式碼若沒被 verify 看過就自動進 main，等於沒有人審過。手動流程維持原規則。

取捨：verify 幾乎每輪都會再找到新的小問題，嚴門檻會讓一部分 run 停在 verified；選擇嚴門檻＋2 輪上限，而不是帶著已知缺陷 merge。

### 有人在場時照舊不自動修

attended 時，verify 有任何 Blocking 或 In-scope fix 就交回使用者（沿用 Phase 4 既有行為）；只有某一輪乾淨時才 merge 並 close，不再另外詢問。理由：使用者在場時看得到回報，事後確認符合 Foresay 的 traceable 分支。

### merge 前的四道 guardrail（最初版本；verify round 1–3 之後的完整清單見下方各輪修正與 SKILL.md Phase 5c）

PR mode 在 merge 前依序檢查，任一不過就停在 verified、在回報寫明是哪一道：

1. verify 乾淨（上一個決策）。
2. CI checks：`gh pr checks` 全部成功；有 pending 時等待（上限 15 分鐘），有失敗就停。沒有任何 check 的 repo 視為通過。
3. Step 0.8 的 auto-close trap 掃描（PR body 與每個 commit body）乾淨。
4. squash commit 的 subject 與 body 由 idd-all 自己組，用 `gh pr merge --squash --subject --body` 明確傳入，內容只用 `Refs #N` 引用 issue；組好後再掃一次 close 類關鍵字緊鄰 `#數字` 的寫法。

squash 而不是 merge commit：commit message 由 idd-all 控制，guardrail 4 才有意義；也與 MANIFESTO 既有的「squash commit message 必須 clean」一致。merge 後 `git fetch` 讓本機看到新的預設 branch，再呼叫 `/idd-close`。

### direct-commit 先 push 再 close

direct-commit mode 驗證乾淨後：

- 目前在預設 branch：先掃要推出去的 commit 有沒有 close 類關鍵字緊鄰 `#數字`（有就停在 verified：direct-commit 沒有 PR，GitHub 會從這種 commit 直接關掉 issue、繞過 `/idd-close`；apply 時加），再 `git push origin HEAD`，成功後呼叫 `/idd-close`；push 被拒（例如 non-fast-forward）就停在 verified，不自動 rebase。
- 目前不在預設 branch：停在 verified，回報「修正尚未落到預設 branch」。

理由：issue 關了而修正只在本機，其他人看到的是一張已關、卻找不到修正的 issue。push 與 PR mode 的 merge 同性質（可 revert）。

### idd-close 的 idd-all 呼叫指示

`/idd-all` 呼叫 `/idd-close` 時在 args 加一段 `ORCHESTRATED BY /idd-all` 指示，形狀與既有的 `UNATTENDED MODE` 指示相同，兩者獨立：前者決定「誰在呼叫」，後者決定「有沒有人在場」。`/idd-close` 收到指示時：

| 停點 | 預設 |
|---|---|
| Step 1.55 merge-completeness 回報有 commit 未落到預設 branch | 停下、不 close，寫進回報 |
| Step 1.6 semantic check 警告（打勾項目找不到對應 commit） | 停下、不 close，寫進回報 |
| Step 3.5 closing summary 裡的 follow-up 關鍵字 | 照 IC_R011 預設開 issue，列進回報 |
| Step 3.6 Diagnosis 的 Residue | 記為殘留（不開 issue），列進回報。這與手動流程的預設（#304：開 follow-up issue）不同，依 Clarity Surface 第 4 列的決定；residue 原文出現在回報裡 |
| Step 6.3 doc-sync 判定文件過時 | 不 commit，列在 closing summary 的 `### Doc-sync 檢查` 與回報（apply 時加：merge 之後的 commit 沒有經過 verify） |
| Step 6.5 distribution sync | 有人在場時照常詢問；無人在場時略過，回報裡列出要跑的命令 |

沒有收到指示時，`/idd-close` 的行為完全不變。

替代方案：直接沿用 unattended contract。沒採用，因為「有人在場、但 residue 與 follow-up 仍取預設」這個組合用單一軸表達不了。

### close 停下時 PR 已經 merge

PR mode 的順序是 merge 後才 close；若 `/idd-close` 因上表的停點停下，結果是 PR 已 merge、issue 仍開著。回報必須寫明這個狀態與原因，並給出 `/idd-close #N` 讓人處理。不在 merge 前先跑 close 的 gate，因為 Step 1.55 要讀已 merge 的 PR 才能判斷。

### --review 照舊停在 verified

`--review` 的語意是使用者想自己再看一次；帶這個旗標時 idd-all 不 merge、不 close，Phase 6 沿用既有的「awaiting human acceptance」措辭。

### 結尾回報照 Foresay 的 operation 格式

Phase 6 回報寫出實際發生的事，不寫預估：

```
Done:
  merged PR #<P> into <default> as <sha>   （direct-commit：pushed <n> commits to <default>）
  closed #<N> — closing summary: <url>
  changed: <files> files, +<adds>/-<dels>
  follow-ups filed: #<a>, #<b>   （沒有則 none）
  residue recorded: <text>   （沒有則 none）
  distribution sync: <done | asked: <answer> | skipped — run <command>>
  verify: <reviewers that ran>，degraded: <missing reviewers or none>
Undo:
  gh issue reopen <N>
  git revert <sha>
```

停在 verified 時，`Done` 只列實際做到的步驟，另起一行 `Stopped: <哪一道 guardrail 或停點>，<原因原文>`。

### 文件三層一起改

MANIFESTO〈auto-merge 的合法性與限制〉改成兩個理由並列：verify 保證改得對；可逆讓它免事前確認、但必須事後回報（Foresay traceable）。revert 不對稱那段保留，改用來說明 distribution sync 為何仍要確認。指向 #37 的句子改指 #392。〈verify-gated 是 terminal 預設 disposition〉改寫成 verify 乾淨即進入 merge 與 close。idd-all 的 description、鐵律、Phase 0.5.1 對 close 可逆性的說法一併修正；新增文字契約測試，鎖住三層不再出現「永不 auto-close」一類的舊說法。

### 吸收 #387 的 meeting 例外

`parallel-orchestration` batch requirement 改寫時，一併寫明 `type=meeting` 停在 diagnosed 或 planning、不 verify、不開 PR；idd-all 的 description 同樣寫明。#387 標為被本 change 取代。

### verify round 1 之後的修正（2026-11-02）

第 1 輪 verify（#392 comment 6563410294）指出把 close stage 寫成 skill 裡的 bash 區塊本身就不安全，改成下面幾點：

- **一個 helper、一個 process**：`scripts/close-stage.py run` 做完所有檢查與 merge／push。skill 的每個 bash 區塊是一次獨立的 tool call，一個區塊判了 `Stopped` 擋不住下一個區塊的 merge（#383 r2 #12 同型），CI 等待也不能拆成好幾次呼叫。helper 用 `run_in_background` 執行。
- **run-state 檔**：Step 0.7 用 `close-stage.py init` 把 `--review`、`--in-chain`、path、interaction、branch 寫進 `.claude/.idd/state/idd-all-run-<N>.json`。helper 從這裡讀，不靠 shell 變數或模型記得；沒有這個檔就不 merge。
- **verify 報告綁定 commit**：idd-verify 的報告寫一行 `**Reviewed**: <sha>`；gate 用 `--expect-sha` 要求它等於要 merge（PR head）或要 push（本機 HEAD）的 commit。舊報告、這一輪沒貼出報告、verify 之後 branch 又多了 commit，都讀成 `unparseable`，取代原本「記住上一份報告 id」的做法（跨不過 tool call）。merge 帶 `--match-head-commit`。
- **只認本帳號的報告**：`author_association` 的 MEMBER／COLLABORATOR 包含只有讀取權限的人，而這份報告決定 merge。
- **CI 寬限**：PR 剛開時 `gh pr checks` 可能還沒有任何 check。repo 有對 `pull_request` 觸發的 workflow 就等 check 出現；沒有才在 90 秒寬限期後視為通過。
- **trap regex 不豁免連字號**，並涵蓋 `owner/repo#N` 與 issue／PR 網址（GitHub 會把 `/idd-close #N` 拆開並關掉 issue，#173）。
- **direct-commit 只推這次 run 的 commit**：`origin/<default>..HEAD` 的每個 commit 都要引用 `#N`，HEAD 要是 verify 報告的 commit。
- **merge 之後確認 `MERGED`**：merge queue 會讓 `gh pr merge` 回 0 而 PR 仍是 OPEN。
- **結案要有 closing summary**：只看 issue state 會把「被 GitHub 或別人關掉」誤報成已結案。
- **PR body 照 gate 結果寫**，停在 verified 的 run 不宣稱 PASS。
- **`--review`／`--in-chain` 的 run 不修 In-scope fix**：它們不會 merge，維持原本只修 Blocking 的範圍。

### verify round 2 之後的修正（2026-11-02）

第 2 輪（#392 comment 6564044471）指出 round 1 的修法本身還有幾個缺口，改成：

- **run-state 的值一律必填**：`--review yes|no`、`--in-chain yes|no`、`--requested-path`。shell 變數遺失時 init 報 usage error，不再悄悄記成「沒有 `--review`」。
- **降級不推**：Step 0.6 因為沒有 ralph-loop 把 PR mode 降成 direct-commit 時，使用者要的是 PR review；close stage 停在 verified。
- **issue 的作者與最後編輯者要有寫入權限**：issue 正文是 implement 照做、verify 照驗的規格；沒有人 merge 時，它必須出自本來就能推這個改動的人。
- **verify 的範圍綁定**：idd-all 以 `--branch` 呼叫 verify，報告寫 `**Reviewed**: <base>..<head>`；gate 要求 base 是 `merge-base(origin/<default>, head)`。只綁 head 時，沒提到 `#N` 的 commit 會讓 verify 的範圍比實際 merge 的短。
- **direct-commit 推 verified sha 本身**，推前再確認 HEAD 與 branch 沒變；`origin` 必須就是這個 repo。
- **merge queue**：merge 前查，有就停（由人經 queue merge）；merge 後仍是 OPEN 就關掉 auto-merge 並停下；讀不到確認時回報「可能已 merge」並保留 PR 號。
- **CI**：一律先等 90 秒寬限期；有對每個 `pull_request` 都會跑的 workflow 時，要等到 `pull_request` 事件的 check 出現；gate 在 CI 等完後再判一次。
- **發佈即 merge 的 repo**：預設 branch 上有 workflow 在 push 時發佈（`gh release`、`npm publish`……）就停下，要人帶 `--review`。這是啟發式偵測，只往「停下」的方向錯；repo 層級的開關仍是 #460。
- **結案確認改成正面確認**：本帳號在 merge／push 之後貼出、第一行是 `## Closing Summary` 的 comment。plugin 的分類器只能否決，不能拿來放行。
- **gate 讀不出來時**仍照 #392 之前的方式處理 Blocking（模型讀報告、修、最後一輪仍有就 abort），只是不 merge。
- **verify-gate**：判定行的 blocking 數要與表格一致；Action 不是最後一欄的表、表格外寫著三類之一的列都判 unparseable；`**Reviewed**` 要完整 40 字元。

### verify round 3 之後的修正（2026-11-02，範圍縮小：comment 6566557673）

- **意圖確認過才收尾**（範圍決定）：所有 comment 的作者都有寫入權限；Clarity Surface 沒有 surfaced／deferred 的列；沒有 Layer V 或 Clarity 的 deferred 紀錄；Plan tier 有 `## Implementation Plan`。不符合就停在 verified、PR 照開。（Plan tier 的判斷在第 4 輪改成看 tier 與 interaction，見下面兩節。）這把 10-14「所有 mode 都適用」縮成「意圖確認過的 run 都適用」。
- **報告綁定這次 run**：只認 run-state 建立之後貼的報告；有寫入權限的帳號後貼的 FAIL 也算數（不只本帳號）。Phase 0.4 先 `reset` 上一次的 run-state，Step 0.7 拿不到 N 就報錯，abort 時也 `reset`。（第 4 輪之後改回只認本帳號，別人的 comment 由「別人插手」停下；reset 移到 Step 0.7，見下一節。）
- **origin**：fetch 與 push URL 都必須是 `github.com/<repo>`；推完向 GitHub 確認預設 branch 指向 verified commit。
- **PR commit 從本機 git 的完整範圍讀**，不受 `gh pr view --json commits` 的筆數上限影響。
- **chain 與 `--review` 不改 verify 的範圍**：只有能走到 close stage 的 run 才以 `--branch` 呼叫 verify。
- **branch 落後預設 branch 就停**（merge 的結果沒被審過）；**改到 CI 的改動不自動 merge**。
- **發佈型 workflow 改掃預設 branch 最新的 tree**，只由 tag 觸發的不算，`workflow_run` 與本地 reusable workflow 也看；**`pull_request` 觸發的判定看 trigger 區塊**，有 path 篩選的不算。
- **CI 要 check 集合連續 90 秒不變**才接受（`needs:` 之後才出現的 check）。
- **verify-gate**：HTML 區塊判讀不出來（單行 `<!-- -->` 可以）；判定行同一類計數寫兩次也判讀不出來；idd-verify 樣板改成三類計數。（第 4 輪之後 gate 改讀渲染後的 HTML，這條規則取消，見下一節。）
- **attended**：使用者處理完 findings、說要繼續時，同一個 session 再跑一輪 verify，乾淨了照常收尾。

兩個沒有改、記錄理由的決定：

- **idd-close Step 1.55 仍然停下**（Diagnosis Decisions）。代價是 #399 的誤報：unattended 修正輪產生「後面的 commit 改寫前面加的行」的 branch，squash 之後 1.55 會報 orphan，PR mode 的自動 close 在 PR #418 merge 前常停在「已 merge、issue 仍開」。把 1.55 改成照樣 close 會讓一張可能沒做完的 issue 在沒有人判斷時被關掉，比停下更糟。
- **workflow 以外的發佈管道**：push 到預設 branch 時發版的 workflow 由 helper 偵測（round 2 起，見上）；不經 workflow 的發佈管道不偵測——plugin marketplace 直接服務預設 branch（本 repo 就是：`.claude-plugin/marketplace.json` 的 source 是 `./plugins/...`）、GitHub Pages 從 branch 部署、Vercel／Netlify 的 Git 整合。這類 repo 的 merge 就是把改動交給下一個安裝或部署的人；要不要偵測、怎麼偵測（repo 層級開關或掃 marketplace.json）留在 #460 由維護者決定，在那之前這類 repo 用 `--review`。closing summary 與自動開的 follow-up issue 會發通知、收不回，這是 close 的一部分，依 #392 的決定歸在「做完回報」這一側。

### verify round 4 之後的修正（2026-11-02，comment 6567272352：保留 unattended 自動收尾）

第 4 輪的 HIGH 幾乎都是「unattended run 自己確認了意圖，close stage 看不出來」，以及 gate 的 markdown 解析又漏了幾種 GitHub 會畫成表格的寫法。使用者選擇保留 unattended 自動收尾、把檢查補齊。

- **gate 改讀 GitHub 渲染後的 HTML**（`body_html`），不再自己解析 markdown。第 3、4 輪各有好幾項是同一類：GitHub 畫成表格、gate 的 parser 沒看到（HTML 區塊第 3–5 型、清單裡的 fence、單行註解包住的 raw table、延續列）。補一條漏一條，改讀渲染結果之後，人看到的表格就是 gate 讀到的表格。`<details>` 因此可以用（Proposed Corrections 的替換內容，r4 #17）；收在 `<details>` 裡的 findings 表照樣計數。測試的輸入是 GitHub 渲染器的真實輸出（`render-fixtures.sh` 產生、commit 進 repo）。
- **被駁回的意見留在表內**：第四個 Action 值 `Rejected`，判定行寫出筆數；close stage 遇到 `Rejected` 就停，由人決定它是否成立（r4 #7）。判定意見不成立的，就是寫這份程式碼的 orchestrator。
- **意圖檢查改看 run 自己的狀態與最新 Diagnosis**：
  - tier：unattended 的 Plan、Spectra、SDD-warranted 一律停（r4 #2、#13）。不再找 `## Implementation Plan` comment：idd-implement 自己也會貼這個標題，找到它不代表有人核准。attended 的 Plan 經過 `/idd-plan` 的核准才會走到 merge，所以不擋。這比使用者選項裡的「補 Plan 降級標記」更直接：降級標記要靠寫入端記得寫，tier 與 interaction 本來就在 Diagnosis 與 run-state 裡。
  - 紀錄：只讀最新 Diagnosis 裡 `- **Reason**: <literal>` 形式的記錄行（code fence 外），literal 是 Layer V 延後或新登記的 choice-first 預設 `unattended-auto-Step-4-choice-default`（r4 #20）。只讀最新一則，attended 重新診斷就清掉舊紀錄（r4 #31）；只認記錄行，提到 literal 的說明文字不算。
  - Proposed Corrections：unattended run 只列不做，issue 正文可能寫錯，停（r4 #20）。
  - Clarity Surface：讀正文裡所有 block（fence 外），看每列有沒有格子仍是 `surfaced` 或 `deferred`；resolved 的列保留 Reason 也不再擋（r4 #18、#27、#30）。
  - 沒有算進來的：unattended 的 diagnosis 策略確認（Stage 1）。每個 unattended run 都會略過它，算進來就只剩 attended 能自動收尾，與這次的決定相反。
- **run 開始之後有別人插手就停**（r4 #4、#15、#48）：issue 上別的帳號（非 bot）新增或改了 comment、改了正文、任何不是本帳號的 comment 被刪；PR 上有非 bot 的 comment 或 review、是 draft、或 changes requested。PR 的部分在 CI 等完之後、merge 之前讀。因此報告只認本帳號的（同事的 FAIL 由這一條停下），規格、MANIFESTO 與 docstring 的說法回到一致（r4 #9、#42）。
- **報告選取**：本帳號在 run 開始之後的最新一則 verify comment（任何 `## Verify` 標題）必須是 `## Verify: #N` 報告，PR mode 的報告與指標不會被跳過（r4 #22）；時間窗不再往前放寬 60 秒（r4 #8）。
- **CI 等完再查一次**：重新 fetch 預設 branch，落後、發佈 workflow、改 CI、merge queue、gate 全部重判（r4 #1、#32、#38、#45）。
- **其他**：origin 的每個 fetch 與 push URL 都要對（r4 #33），userinfo 可以是空的（`https://@github.com/...`，r4 #19）；`--cwd` 先 realpath（r4 #43）；merge／push 之前先寫一份「可能已發生」的結果，被中斷也留得下紀錄；`"refused"` 不列 Undo（r4 #23、#34）；reset 移到 Step 0.7 的 init 失敗分支，排在 Step 0.5.1 之後（r4 #47）；`--review`／`--in-chain` 的 gate 只比對 head（r4 #44）；IC_R011 的 spec 與 reference 補上 `# Disable IC_R011`（r4 #24）。

### verify round 5 之後的修正（2026-11-02，comment 6568180861：定威脅模型）

第 5 輪仍有 4 個 HIGH，Blocking 分兩類：判定不完整而放行的機械漏洞，以及自我認證（寫程式碼的 orchestrator 同時產生 gate 讀的每一份材料）。維護者決定：

- **威脅模型**：close stage 防的是 orchestrator 出錯，不是刻意欺騙。讀不準的一律停；自我認證那一類加便宜的擋法，其餘列為已知限制。
- **Stage 1 不算略過**：「ai的attention也算attention，只是人類的更稀少」。unattended diagnose 自己做的策略確認是一次注意；人的注意力留給偵測器觸發的地方。

照這個威脅模型的修正：

- **共用模組**：`scripts/lib/rendered.py`（讀 GitHub 渲染後的 HTML，gate 與 close stage 共用）、`lib/workflows.py`（workflow 會不會在 push 到預設 branch 時發佈）、`lib/ghread.py`、`lib/intent.py`（從 close-stage.py 拆出，它超過 800 行）。
- **gate 讀所有可見的文字行**：段落、清單項目、標題、summary、details 裡的原文都算，code block 不算（r5 #3、#10、#15）；表格儲存格不算判定行（粗體的 **HIGH** 不是判定）。乾淨的報告一定要有完整的覆蓋率行（r5 #41）。
- **自我認證的便宜擋法**：Severity 是 CRITICAL／HIGH／P0／P1 的 Follow-up 停（r5 #4）；報告貼出後被編輯或被藏起來就讀不出來（r5 #14、#16）；報告有 `Process Gaps` 一節就停（verify 降級跑，r5 #22）。
- **意圖檢查讀 GitHub 的渲染結果**（r5 #12）：略過紀錄與 Proposed Corrections 讀所有 comment，不只最新 Diagnosis（r5 #5、#7、#18、#20）；之後有 Decision comment 才算回應，這也是 r4 #31「紀錄永遠清不掉」的出口。Diagnosis 的選取改成 Phase 2 分派用的那一則（r5 #11）。bot 在意圖檢查裡也豁免（r5 #19、#28、#30）。
- **別人插手**補上 issue 被關閉、加或拿掉 label、改標題、重開，以及 PR 不是本帳號開的、PR 的 label／標題／描述被別人改（r5 #6、#13、#16、#33）；GraphQL 一次讀不完時停（r5 #2）。
- **PR 的 commit 都要引用 #N**（r5 #23），PR mode 從剛 fetch 的 `origin/<default>` 開 branch（r5 #21）。
- **發佈偵測改用 `lib/workflows.py`**：加引號的事件鍵、list 寫法、inline map、否定或方括號的 branch pattern、tag 加 branches-ignore、別的 repo 的 reusable workflow、composite action、`run:` 呼叫的本機 script；讀不懂就當成會發佈（r5 #1、#9、#17、#29）。
- **reset** 移到 Step 0.5.1 放行之後（r5 #36）；verify-gate 崩潰時輸出 unparseable，不再以 exit 1 結束（r5 #46）。

列為已知限制（SKILL.md Phase 5c）：orchestrator 刻意改分類、不寫紀錄或自己貼 Decision；attended 由 path 推出（r5 #42）；Decision comment 不檢查回應的是哪一則；direct-commit 不受 branch protection 擋（r5 #32）與測試用的環境變數 seam（r5 #47），兩者開在 #464。

仍留著的限制（SKILL.md Phase 5c〈已知限制〉）：同一帳號分不出 run 與人、最後檢查到 squash 之間的幾秒、direct-commit 不等 CI、workflow 以外的發佈管道（#460）、idd-all 仍可被模型呼叫（#457）、close 的 Step 0 與 1.5 排在 merge 之後、task 7.2 尚未在真的 GitHub 上跑過。

## Implementation Contract

**verify gate helper（`scripts/verify-gate.py`）：**

- 輸入：`--html-file <path>`（GitHub 渲染 verify master comment 得到的 HTML，即 comment 的 `body_html`），可加 `--expect-sha`、`--expect-base`（各 40 個 hex）。
- 輸出（stdout，一行 JSON）：`{"status": "clean" | "not_clean" | "unparseable", "verdict": "PASS" | "FAIL" | null, "blocking": <int|null>, "in_scope": <int|null>, "follow_up": <int|null>, "rejected": <int|null>, "reason": <string>}`。
- `clean`：判定行為 PASS，分類表可解析，Blocking＝0 且 In-scope fix＝0（`Rejected` 不影響 status，由 close stage 停下）。
- `not_clean`：可解析但有 Blocking 或 In-scope fix，或判定為 FAIL。
- `unparseable`：找不到判定行或分類表、分類欄出現四類以外的值、判定與表格或覆蓋率行矛盾等（完整清單見 spec〈Verify gate parsing fails closed〉）；`reason` 寫明是哪一種。
- 結束碼：`clean` 為 0，`not_clean` 為 1，`unparseable` 為 2，用法錯誤為 64。檔案讀不到時以 2 結束。

**idd-all 的終點行為：**

| 情況 | 結果 |
|---|---|
| PR mode，gate `clean`，Phase 5c 的檢查全過 | squash merge，fetch，呼叫 `/idd-close`（帶 ORCHESTRATED 指示），回報 Done |
| PR mode，任一 guardrail 不過 | 不 merge，停在 verified，回報 Stopped |
| direct-commit，在預設 branch，gate `clean` | push，呼叫 `/idd-close`，回報 Done |
| direct-commit，不在預設 branch，或 push 被拒 | 停在 verified，回報 Stopped |
| unattended，gate `not_clean` 且未滿 2 輪 | 修 Blocking 與 In-scope fix，重跑 verify |
| unattended，滿 2 輪仍 `not_clean` | 停在 verified |
| attended，gate `not_clean` | 交回使用者（既有行為） |
| gate `unparseable` | 停在 verified，回報解析失敗的原因 |
| `--review`、`--in-chain`、`type=meeting` | 終點不變 |
| 意圖沒有確認過，或 run 開始之後有別人插手 | 停在 verified、PR 照開，回報 Stopped（spec 的兩條對應 requirement） |
| verify 報告有 `Rejected` 的 finding | 停在 verified，由人決定那則意見是否成立 |

**範圍：**

- In scope：上述 helper 與測試、idd-all Phase 4 到 Phase 6、idd-close 的 ORCHESTRATED 指示、MANIFESTO 與文件、兩份 spec、CHANGELOG 與版本號。
- Out of scope：`/idd-all-chain`、meeting 停點、手動 `/idd-verify` 與 `/idd-close` 的行為、distribution sync 的自動執行、雲端 runtime。

## Risks / Trade-offs

- [自動 merge 了一個錯的改動] → Phase 5c 的 guardrail；回報附 `git revert` 命令。revert 會在 history 留痕跡，這是使用者接受的取捨。
- [嚴門檻讓多數 run 停在 verified] → 回報寫明停在哪一輪、還剩哪些 In-scope fix；2 輪上限避免無限迴圈。
- [PR 已 merge、close 卻停下] → 回報寫明狀態並給出 `/idd-close #N`；不嘗試回滾 merge。
- [`/loop` 等 caller 依賴舊的停點] → CHANGELOG 標 BREAKING；需要舊行為的 caller 改帶 `--review`。
- [批次模式下一張 issue 從過時的預設 branch 開 branch] → 每張 merge 後先 `git pull --ff-only` 再處理下一張；失敗就停止批次並回報。
- [與 #383 同檔衝突] → 實作等 #383 merge 後才開始；spec 改動只引用 meeting 停點，不複製其內容。

## Migration Plan

沒有資料遷移。發佈為 minor 版本，CHANGELOG 以 BREAKING 標註 idd-all 終點改變，並寫明 `--review` 可取回舊行為。回滾：revert 本 change 的 commit 並發佈新版本。

## Open Questions

(none) — 使用者的決定已記在 #392（Clarity Surface、Diagnosis Decisions、spectra-discuss 結論）。
