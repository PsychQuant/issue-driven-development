## Context

`/idd-all` 現在有三種入口：指名一張 issue、指名多張 issue 的批次模式、從一段描述或檔案新開 issue。不帶參數時它用 AskUserQuestion 問「建新 issue 還是用既有 issue」。#478 的兩則 Decision 決定：不帶參數就是跑剩下的全部，`rest` 同義；需要人的 issue 跳過、其他繼續；途中新開的 issue 同一次解掉；不設張數上限；開始前印出清單。

現有、可以直接用的東西：

- 批次模式的外圈規則（`parallel-orchestration` 規格的批次那一條）：依序跑，PR mode 每張之間回到預設 branch 並 pull，失敗就停整批。
- 可動性判定只有一份實作：scripts/lib/actionability.sh。
- 「意圖有沒有確認過」是程式：scripts/lib/intent.py 的 open_clarity_row 與 check_issue_authors，讀 GitHub 渲染後的正文。
- GitHub 讀取的共用層：scripts/lib/ghread.py（gh_json、can_write、latest_diagnosis、rendered 的 HTML 解析）。
- 每張的 merge 與 close 由 close-stage.py 把關，run-state 放在工作樹的 .claude/.idd/state 底下。

缺的是：一份機器可讀的「剩下哪些、各屬哪一類、下一張是誰」，以及能撐過 context 壓縮的「每張只試一次」。

Diagnosis 在無人值守下取了六個預設（不等 #457 與 #423、衍生 issue 各自一個 PR、最後的決策點就是 close stage 的閘門、連續有 HIGH 就停那一張、維持兩輪 verify 上限、已經 verified 的不重跑）。這份設計照那六個預設寫；維護者之後若改其中一項，受影響的是下面標出的決定。

## Goals / Non-Goals

**Goals:**

- `/idd-all` 沒有位置參數或只有 `rest` 時，不提問，直接跑剩下的全部。
- 每張 open issue 由一張有順序的判定表放進恰好一類；判定可以重現、可以窮舉檢查。
- 每張 issue 在一次 run 裡只試一次；途中新開的 issue 會被接住；run 的狀態撐得過 context 壓縮與重複呼叫。
- 單張停下不影響其他張；整個 run 的停止條件是封閉列舉。
- 開始前有清單、結束時有一份總報告。

**Non-Goals:**

- chain 成為預設、衍生 issue 併進同一個 PR（#457）。
- verify 的停止規則與輪數上限（#423）。單張流程的 verify 迴圈不動。
- 未診斷 issue 的分波平行診斷（#456）與任何平行執行（#466）。外圈是依序的。
- 判斷一張舊 issue 的前提還成不成立。rest 不做這個判斷。
- 版本號與 CHANGELOG 的 release 條目。發布由維護者決定。
- 改動既有 capability 的 requirement。

## Decisions

### One helper owns selection and run state

新增 scripts/rest-queue.py，子命令 args、list、start、next、record、stop、report。挑選（讀 GitHub、分類、排序）與 run 的狀態（試過哪些、結果、整個 run 是否停了）放在同一支程式，因為 next 的答案同時取決於兩者。狀態檔是工作樹裡的 .claude/.idd/state/idd-all-rest.json，與 close stage 的 run-state 同目錄、同樣拒絕經過 symlink 的路徑。

替代方案：把迴圈與「試過哪些」寫成 SKILL.md 的文字，由模型記。不採用：一次 run 會跨很多張 issue 與多次 context 壓縮，模型記不住，重跑同一張的代價是一輪 verify。

### Decision table is data, checked exhaustively

分類規則寫成一張有順序的表（資料，不是散在程式裡的 if），先中者為準：

1. author：開 issue 的帳號或正文最後編輯者沒有寫入權（帳號讀不到也算）
2. tracker：有 north-star 或 epic label
3. needs-person：正文有還沒回答的釐清問題
4. parked：actionability gate 的 parked 一組
5. blocked：gate 的 blocked 一組
6. meeting：最新受信任 Diagnosis 的 type 是 meeting
7. verified：正文 Current Status 的 Phase 是 verified
8. candidate：其餘

測試對七個輸入的所有組合（六個布林與四值的 gate 分組，共 256 種）檢查：每一種都落在恰好一類，而且符合表的先後順序。表先寫、檢查先寫，再寫讀 GitHub 的部分。

第 1 類放在最前面的理由：指名一張 issue 時是人選了它；rest 沒有人選。close stage 的同一道作者檢查只擋 merge，擋不到 implement、push 與開 PR。

第 7 類是 Diagnosis 的第六個預設：已經停在 verified 的 issue 不重跑。維護者若改成重跑，拿掉這一列即可，它們會落到 candidate。

### Judgement is reused, not copied

- 釐清問題：intent.py 新增 open_clarity_rows(issue)，回傳所有未回答的列；原本的 open_clarity_row 改成回傳其中第一筆。close stage 的行為不變。不另外移植 idd-diagnose Step 0.5 的 bash。
- 可動性：呼叫 actionability.sh 的 idd_blocking_section、idd_diagnosis_type、idd_parse_complexity、idd_actionability_verdict、idd_actionability_group。issue 正文與 Diagnosis 經暫存檔交給 bash，不走命令列參數（Linux 單一參數上限 128 KB，中文正文會超過）。
- 寫入權：ghread.can_write，每個帳號查一次。GitHub 回 404（不是 collaborator，或是 app 的 bot 帳號）算沒有寫入權；其他失敗讓整個命令失敗。
- 受信任的 Diagnosis：ghread.latest_diagnosis。
- Phase：從 GitHub 渲染後的正文讀第一行以 Phase 開頭的文字，code block 裡的不算。這是新的讀法，因為 repo 裡沒有現成的 phase 解析程式；只認 verified 這一個值。

### Fail closed on an incomplete read

所有 open issue 用一次分頁的 GraphQL 查詢取回（編號、作者、最後編輯者、label、正文與它的渲染、最新 100 則 comment）。comment 超過 100 則的 issue 改用 REST 分頁讀完整。任何一頁失敗、回傳缺欄位、或 actionability.sh 回報誤用，整個命令以非 0 結束，不輸出部分清單。理由：少讀一頁會讓 run 以為 backlog 已經空了而提早結束，少讀 comment 會把已診斷的 issue 當成未診斷。

### Candidate order ignores Conflict Class

候選的順序：gate 判定為 actionable（已診斷）的在前，undiagnosed 的在後，各自依 issue 號由小到大。不解析 Diagnosis 的 Conflict Class：批次模式的 conflict class 排序是模型讀文字做的，沒有共用的解析程式，而規格自己寫明依序執行時順序不影響正確性。已診斷的先跑，是因為它們的意圖已經確認過、比較可能直接結案。這一點與 Diagnosis 寫的「照批次模式的 conflict class 規則」不同。

### Attempt-once is recorded when an issue is handed out

next 把一張 issue 交出去的當下就寫進狀態檔（in flight）；record 再補上結果。有一張還在 in flight 時，next 不會交出第二張，而是重複同一張並標明它還沒有結果。這樣模型在一張跑到一半時遇到 context 壓縮、又呼叫 next，不會靜悄悄跳到下一張，也不會把同一張重新跑一遍而不自知。

start 遇到最後一次活動（start、交出、record、stop）在 24 小時內、還沒 report 的 run 就接續，不重置，記下的 stop 也保留；超過 24 小時或已經 report 過的才重新開始。效期從最後一次活動算起，不從開始算起：跑完整個 backlog 會超過一天。理由相同：模型壓縮後從頭讀 skill 再呼叫一次 start，不能把試過的清單清掉。24 小時與 close stage 的 run-state、unattended 狀態的效期一致。

### record reads the outcome from GitHub

record 只收 issue 號與一段原因文字。結果由它自己向 GitHub 讀：issue 是 CLOSED 記 closed，否則記 stopped 加上原因。模型不能報「已結案」。record 只接受目前 in flight 的那一張。

### Unknown flags are refused

args 把參數分成旗標與位置參數。認得的旗標是 --pr、--no-pr、--review、--in-chain、--cwd（含 --cwd=）。以 -- 開頭而不認得的參數一律拒絕，不當成位置參數。理由：不帶位置參數現在會開始一個無人值守的 run，打錯的旗標（例如把 --review 打錯）不能被靜悄悄忽略。

### Listings print issue numbers, not titles

start 與 report 的清單只印 issue 號。標題是 issue 作者寫的文字，印 192 個標題既佔篇幅，也把別人寫的文字送到模型面前。report 會印等人回答的問題原文，但 author 那一類排在最前面，所以被印出的問題都來自有寫入權的帳號開的 issue。已經 verified 的 issue 也只列號碼，不另外查它的 PR：PR 與 issue 的對應只有一份實作（check-existing-work.sh），在這個 repo 它對每張都回 unknown（#471）；issue 自己的 dashboard 留言已經有 PR 連結。這一點比 Diagnosis 寫的「附它的 PR」少。

## Implementation Contract

**行為**

- `/idd-all` 開始時先跑 args。結果是 rest 時不提問，進入 rest 流程；refuse 時印出原因與用法後結束，不做任何事；other 時照現有流程。
- rest 流程：start（印出清單）→ 反覆 next、跑那一張的單張流程（Phase 0.4 起，旗標沿用這次呼叫的）、record、PR mode 下回到預設 branch 並 pull → next 回 done 或 stopped 後 report。
- 單張停下、abort 或被 gate 判為不可動，都只記在那一張，下一張照跑。
- 整個 run 停下只有四種：回不到預設 branch、rest-queue.py 以結束碼 3 結束（GitHub 或判定程式讀不到）、gh 認證失效、使用者中斷。結束碼 1 與 2 是呼叫寫錯，改正後重跑，不算停下。前三種由 skill 呼叫 stop 記下原因後 report；使用者中斷時狀態檔留著，24 小時內再跑會接續。

**介面**

- `rest-queue.py args -- <argv…>`：stdout 一行 JSON，`{"mode": "rest"}`、`{"mode": "other"}` 或 `{"mode": "refuse", "reason": "…"}`；rest 與 other 結束碼 0，refuse 結束碼 1。
- `rest-queue.py list --repo O/R [--json]`：只讀，不建立 run。JSON 形狀：`{"repo", "open", "classes": {"candidate": [n…], "needs-person": […], "author": […], "tracker": […], "parked": […], "blocked": […], "meeting": […], "verified": […]}, "order": [n…], "diagnosed": [n…], "questions": {"<n>": ["…"]}}`（diagnosed 是候選裡已經有可動 Diagnosis 的那些）。
- `rest-queue.py start --cwd C --repo O/R`：建立或接續 run，印清單（文字），結束碼 0。
- `rest-queue.py next --cwd C --repo O/R`：stdout 一行 JSON，`{"next": n, "in_flight": false}`、`{"next": n, "in_flight": true}`、`{"next": null, "done": true}` 或 `{"next": null, "stopped": "…"}`。
- `rest-queue.py record --cwd C --repo O/R --issue N [--reason TEXT]`：stdout 一行 JSON `{"issue": n, "outcome": "closed"|"stopped", "reason": "…"}`。N 不是 in flight 的那一張時結束碼 1、狀態不變。
- `rest-queue.py stop --cwd C [--repo O/R] --reason TEXT`：記下整個 run 停止的原因；之後 next 回 stopped。第一個原因保留，再呼叫一次不會覆蓋。
- `rest-queue.py report --cwd C --repo O/R`：印總報告（結案的、停下的與原因、等人回答的問題、沒跑的與類別、整個 run 停下的原因），然後刪除狀態檔。清單重讀失敗時仍印出狀態檔裡有的部分，並說明清單讀不到。
- 狀態檔：`{"version": 1, "repo", "started_at", "updated_at", "attempts": [{"issue", "handed_at", "outcome", "reason", "recorded_at"}], "stop": null | {"reason", "at"}}`。
- intent.open_clarity_rows(issue) 回傳字串 list；open_clarity_row(issue) 回傳第一筆或 None。

**失敗時**

- 讀取失敗、清單不完整、helper 誤用：結束碼 3，stderr 一行原因，stdout 不印清單。
- 沒有 run 時呼叫 next、record、stop：結束碼 1。
- 用法錯誤：結束碼 2。

**驗收**

- scripts/tests/rest-queue/test.sh 全過：參數表每一列、判定表的 256 種組合、排序、讀取失敗、comment 超過 100 則、只試一次與 in flight、record 讀 GitHub、stop、接續、report。
- close-stage 既有的測試全過（open_clarity_row 的行為不變）。
- scripts/run-all-tests.sh 全過。
- skills/idd-all/SKILL.md 的參數表與 rest 一節有文字檢查釘住。

**範圍**

- 在範圍內：rest-queue.py 與測試、intent.py 的一個新函式、idd-all 的 SKILL.md、兩份 reference、README 與 MANIFESTO 的對應段落。
- 不在範圍內：單張流程 Phase 1 到 Phase 6 的任何行為、close-stage.py、idd-all-chain、idd-list、idd-diagnose、版本號。

## Risks / Trade-offs

- [不帶參數從提問變成開跑，誤觸會開始一個無人值守的 run] → 清單先印出來；第一張的第一個動作是建 branch 與貼 Diagnosis，都可以復原；不認得的旗標被拒絕。
- [第一次跑有 166 張候選，成本很高] → 不設上限是維護者的決定；start 印出張數，run 可以中斷後接續。
- [多數未診斷的 issue 會停在 PR 而不是結案，開著的 PR 彼此可能衝突] → 每張的原因進總報告；衝突由之後處理那個 PR 的人解。這是依序加上「停下不擋別張」的代價。
- [新 issue 開得比解得快時 run 跑不完] → 每張只試一次保證不重複；沒有上限是決定。
- [另一個 session 同時在同一個工作樹跑 rest] → 狀態檔一個工作樹一份；不處理兩個 session 共用一個工作樹的情況，單張流程本來也不處理。
- [Phase 的讀法是新的] → 只用來把 verified 的 issue 排除在外；讀錯的方向是多跑一張已經 verified 的 issue，單張流程會接到既有的 PR。
- [GraphQL 的 bodyHTML 與 REST 的 body_html 渲染略有不同] → open_clarity_rows 對兩者都吃的是 HTML 表格；測試用 GraphQL 取回的真實渲染當 fixture。
