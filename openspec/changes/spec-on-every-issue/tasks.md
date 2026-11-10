## 1. 前置

- [x] 1.1 確認 #392 已經在 main，對 main 重新檢查這份 change：把 #392 改過的 `idd-pr-hitl-modes` 規格、`idd-all` 與 `idd-verify` 的 SKILL 跟這份 delta 對一次，有衝突先改 delta，並決定封存檢查接在 close stage 的哪一步。驗證：`spectra validate spec-on-every-issue` 通過；design 的 Risks「與 #392 的衝突」補上實際的差異。

## 2. scripts/spec-change.py（測試先寫）

- [x] 2.1 `declared` 子指令讀出宣告行：依 requirement「Every implemented issue leaves a spec change or a declared exemption」的 Example「reading the Spec line」先寫測試（測試檔帶標記 `spec-example: spec-on-every-issue / reading the Spec line`），確認失敗後再實作。驗證：`bash plugins/issue-driven-dev/scripts/tests/spec-change/test.sh` 裡 13 列各有一個檢查並通過；參數錯誤是 exit 64。
- [x] 2.2 `archived` 子指令回答宣告的 change 在某個 commit 上是否已封存：依 requirement「The change is archived on the branch before verify」的 Example「whether the declared changes are archived at a commit」先寫測試（帶對應標記），在暫存 repo 上建立與封存目錄後檢查。驗證：11 列各有一個檢查並通過；名稱只是另一個封存目錄的前綴時回 `refuse`；revision 不存在時回 `error`（exit 2）。
- [x] 2.3 `links` 子指令檢查新增與改到的 requirement：依 requirement「Added and modified requirements carry an executable check」的 Example「what the link check reports」先寫測試（帶對應標記）。驗證：15 列各有一個檢查並通過；不給 `--base` 是 exit 64；沒有改到的 requirement 不會被報。
- [x] 2.4 `preflight` 子指令決定能不能開始寫規格：依 requirement「A repository without Spectra stops and a third-party clone proceeds」的 Example「preflight by write access and Spectra state」先寫測試（帶對應標記）；linked worktree 用真的 `git worktree add` 建出來測（design「linked worktree 先停下」），`spectra` 是否在 PATH 用測試專用的 PATH 控制。驗證：8 列各有一個檢查並通過。
- [x] 2.5 四個子指令的共同行為（design「機械判定集中在 scripts/spec-change.py」）：非 git 目錄、解析不了的規格檔都回 `error`，不回 `ok` 或 `pass`；每個子指令只印一行 JSON。驗證：測試各一例；`python3 -m py_compile` 通過。

- [x] 2.6 規格目錄照 Spectra 的規則解析（requirement「The spec directory is resolved the way Spectra resolves it」；design「規格目錄照 Spectra 的規則解析」）：依 Example「spec directory by .spectra.yaml」先寫測試（帶對應標記），`archived`、`links`、`preflight` 都改用解析出的目錄。驗證：`scripts/tests/spec-change/test.sh` 的 7 列各有一個檢查並通過，原有的檢查不變；用真的 `spectra` 在暫存 repo 建立、封存一個 change，`links` 與 `archived` 讀得到 `docs/spectra/`。

## 3. wrapper

- [x] 3.1 `references/spec-wrapper.md` 寫出共用的契約：preflight、建立 change（design「每張 issue 一個 change，名稱是 idd-N-slug」）、輕量形式不做 discuss 與 design（design「Simple 用 spec-driven 的輕量形式，不 fork workflow」）、apply 時 Example 的測試先寫、收尾的順序（design「封存在 branch 上、verify 之前」）。驗證：內容審閱，契約的每一步都對得到一個 `spec-change.py` 子指令或一個 Spectra 指令，沒有留給執行者自行判斷的總括判準。
- [ ] 3.2 `idd-implement` 成為 Simple 的 wrapper（requirement「Spec changes go through Spectra behind IDD wrappers」；design「wrapper 是 idd-implement 與 idd-plan，契約放在 references/spec-wrapper.md」）：先跑 preflight，照契約 propose、apply、收尾；Implementation Complete 的模板加上標記與 `**Spec**:` 行（design「宣告寫在 Implementation Complete 留言的 Spec 行」）；tree-lock 那一步寫明 linked worktree 會被 preflight 擋下。驗證：在暫存 repo 跑一張 Simple issue，branch 上有封存目錄與 `openspec/specs/` 的改動，`spec-change.py declared` 讀留言得到 `change`，`spec-change.py archived --ref HEAD` 印 `pass`。
- [ ] 3.3 `idd-plan` 成為 Plan 的 wrapper：attended 時 propose 之後在 plan mode 請人核准 proposal 與 tasks，核准後把 change 交給 `idd-implement` 做 apply 與收尾，`idd-implement` 不再 propose 一次。驗證：在暫存 repo 跑一張 attended 的 Plan issue，核准之前沒有任何程式檔被改，核准之後的結果與 3.2 相同。
- [ ] 3.4 `idd-all` 替 Spectra tier 做收尾：apply 之後跑 Spectra 的 verify、封存、commit、`links`，並貼出帶標記與 `**Spec**:` 行、沒有 `### Checklist` 小節的 Implementation Complete。驗證：`authoritative-source-producer` 的測試加一例，確認有這種留言時 checklist 的來源仍是 `Current Status > Tasks`；在暫存 repo 跑一張 Spectra issue，`archived --ref HEAD` 印 `pass`。
- [ ] 3.5 兩種豁免的宣告：`idd-implement` 只在規格列的四種情況宣告 `no behaviour change`；第三方 clone 宣告 `third-party clone`，不建立 `openspec/`。驗證：在暫存 repo 跑一張只改 README 錯字的 issue，沒有 change 目錄，留言宣告 `no behaviour change`；`preflight --can-write no` 時 wrapper 照舊實作並宣告 `third-party clone`。

## 4. verify 與 close

- [ ] [P] 4.1 `idd-verify` 拿規格對照行為（requirement「Reviewers check behaviour against the specs」）：把 `**Spec**:` 行與範圍內改到的規格檔交給每個 reviewer，跑 `links` 與 `archived`，把缺漏列為 Blocking；Regression lens 的提示加上兩條 HIGH 的規則。驗證：在 3.2 的暫存 repo 上拿掉一個 Example 的測試標記後跑 verify，報告有一項 Blocking 指名那個 Example；把留言的宣告換成 `no behaviour change` 後再跑，報告有一項 HIGH。
- [ ] [P] 4.2 verify 之後的修正留下規格（requirement「A fix after a verify round goes through the same wrapper」；design「verify 之後的修正走同一個 wrapper」）：`idd-all` 的修正迴圈與 `idd-implement` 在修正新增或修改 requirement 時建立 `idd-<N>-fix<k>`，並在新的留言列出這張 issue 的所有 change。驗證：在暫存 repo 讓一輪 verify 回報一項 Blocking，修正後 branch 多一個已封存的 `idd-<N>-fix<k>`，新留言的 `**Spec**:` 行有兩個名稱，`archived --ref HEAD` 印 `pass`。
- [x] [P] 4.3 `idd-close` 在關閉前檢查封存（requirement「Close requires the issue's change to be archived」）：依 Example「the close gate reads the default branch」先寫測試（帶對應標記），再把檢查接進 `idd-close` 的 gate。驗證：5 列各有一個檢查並通過；在暫存 repo 上，合併前跑 close 會停下並指名 change，合併後通過。

## 5. 文件與收尾

- [ ] [P] 5.1 文件與這份 change 一致：`rules/sdd-integration.md` 的流程與「Close triggers archive」改成 branch 上、verify 之前封存；`idd-diagnose` 的下一步說明、`references/verify-profiles.md`、`references/usecase-routing.md`、README、CHANGELOG（標明 BREAKING、linked worktree 的限制、在暫存 repo 量到的一張 Simple 多花的時間）。驗證：內容審閱，這幾份文件沒有任何一處還寫 Simple 不碰規格，或封存在 close 時做。
- [ ] 5.2 這份 change 自己符合新規則：五個 Example 都有帶標記的測試，其餘 requirement 有 `No executable check:` 行。驗證：`spec-change.py links --base <開始實作的 commit>` 印 `ok`；照新的收尾順序封存後 `spec-change.py archived --ref HEAD` 印 `pass`。
- [x] [P] 5.3 開兩張後續的 issue（#487 補齊既有 requirement、#488 獨立 clone 隔離）：補齊既有 requirement 的 Example 與檢查；把隔離用的工作樹改成獨立 clone，讓要寫規格的 issue 在主工作樹被鎖住時也能跑。驗證：兩張 issue 的號碼寫進 #480 的 closing summary。
