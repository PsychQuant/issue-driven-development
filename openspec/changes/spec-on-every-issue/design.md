## Context

IDD 把 issue 依 Diagnosis 分成 Simple、Plan、Spectra 三個 tier。只有 Spectra tier 會經過 Spectra 的 propose、apply，留下 spec delta；它的封存目前沒有任何一步強制執行，所以有五個做完的 change 沒有封存（#482）。Simple 與 Plan 直接由 `idd-implement` 實作，不碰 `openspec/`。

現況的三個事實決定了這份設計：

- **verify 沒有固定的對象。** #405、#351 都在沒有 HIGH 的一輪之後又找到 HIGH。#423 的分析：後來的 HIGH 一部分來自先前的修正，那一類只能靠「每個找到的問題都變成規格裡的性質與一個會自己重跑的檢查」關掉。
- **Spectra 3.0.0 在 linked worktree 裡會寫進主工作樹。** 2026-11-10 在暫存 clone 上實測：在 linked worktree 裡建立 change，目錄出現在主工作樹。`idd-implement` 在主工作樹被別的 session 鎖住時會改用 linked worktree。
- **Spectra tier 現在不貼 Implementation Complete 留言。** 它的進度走 issue 正文的 `Current Status > Tasks`。

維護者的決定都記在 #480：每張 issue 都更新規格、Simple 也走 propose 與 apply 的快速形式、「不改變行為」要受審、每條 requirement 附可執行的檢查、沒有 Spectra 時自己的 repo 停下而第三方 clone 不寫、只管新增或改到的 requirement、保留 IDD 自己的 wrapper、接受每張 issue 一個 change 目錄。

實作的前提：#392 先合併進 main。這份 delta 是對 `dc64efa` 寫的；#392 會改 `idd-pr-hitl-modes` 與 `idd-all`、`idd-verify` 的 SKILL，合併後要重新 validate，並把封存檢查接到它的 close stage。

## Goals / Non-Goals

**Goals:**

- 每一張實作過的 issue 都在 `openspec/specs/` 留下改動，或留下一個受審的豁免宣告。
- 規格的寫入用 Spectra 原本的 change、delta、archive，IDD 不另外維護一份格式。
- 被 verify 審查的 commit 已經帶著套用後的規格。
- 新增或改到的 requirement 都有一個會自己重跑的檢查，或一行寫明為什麼沒有。
- verify 找到的 Blocking 問題，修正後留在規格裡。

**Non-Goals:**

- **verify 的停止條件**與「還沒找到的缺陷」的估計：在 #423。這份 change 提供的是機制，不是「之後不會再有 HIGH」的保證；規格沒寫到的性質仍然沒有檢查。
- **回頭補既有的 190 條 requirement**：只管之後新增或改到的。補齊另開一張，等這裡的連結寫法定案。
- **封存五個舊 change**：#482。
- **本 repo 自己的 `/spectra-archive` Step 7**（人手動封存時貼的 Implementation Complete）：那則留言沒有標記，照舊制處理，這次不改那支腳本。
- **讓 Spectra 在 linked worktree 裡寫對地方**：這次只停下並說明。把隔離工作樹改成獨立 clone 是另一張。
- **`sdd_bias` 與 tier 的判定**：tier 仍然決定實作前要不要討論、要不要核准，這次不動分流。

## Decisions

### 每張 issue 一個 change，名稱是 idd-N-slug

Simple 與 Plan 的 change 叫 `idd-<N>-<slug>`，verify 第 k 輪之後新增或修改 requirement 的修正叫 `idd-<N>-fix<k>`。Spectra tier 的名稱照舊由 propose 決定。名稱帶 issue 號，封存檢查與結案檢查就不必從文字裡猜它屬於哪一張 issue（#405 的七輪 verify 都在處理那個猜測）。

**Alternatives considered**：一張 issue 永遠只有一個 change，verify 之後的修正直接編輯 `openspec/specs/`。沒有採用：那是繞過 Spectra 的 delta 機制手改主規格，而且封存之後 change 已經不在了，沒有地方放新的 delta。

### Simple 用 spec-driven 的輕量形式，不 fork workflow

Simple 用 Spectra 內建的 `spec-driven`，只是不做 discuss、不產生 design（design 本來就是選用的 artifact）。proposal 寫到能說明為什麼與改什麼就好，tasks 的每一項仍然要有行為與驗證方式。

**Alternatives considered**：fork 一個 IDD 專用的 schema。沒有採用：多一份要跟著 Spectra 升級的 schema，而現有的 schema 已經允許跳過 design。Spectra 的 `no-spec` schema 也不適用，它正好沒有這次要的 spec delta。

### wrapper 是 idd-implement 與 idd-plan，契約放在 references/spec-wrapper.md

維護者要保留 IDD 自己的 wrapper，理由是以後可能會調整。所以：

- `idd-implement` 是 Simple 的 wrapper：輕量 propose、apply、收尾。
- `idd-plan` 是 Plan 的 wrapper：propose 之後在 plan mode 請人核准 proposal 與 tasks，核准後交給 `idd-implement` 做 apply 與收尾。unattended 的 Plan 照現在的做法直接走 `idd-implement`。
- 共用的步驟（preflight、建立 change、apply 時測試先寫、收尾）寫在一份 `references/spec-wrapper.md`，兩個 skill 引用它，不各寫一份。
- `idd-all` 的 dispatch table 仍然是「哪個 phase 呼叫哪個 skill」唯一寫明的地方，這次不在規格裡重述。

`idd-implement` 的 TDD 仍然先載入 superpowers 的 test-driven-development（既有的 `superpowers-integration` 規格不變），task 的逐項執行交給 Spectra 的 apply。

### 封存在 branch 上、verify 之前

收尾的順序：Spectra 的 verify（規格 → 程式）→ `spectra archive` → 確認封存落在要 commit 的工作樹 → commit → 連結檢查 → 貼 Implementation Complete。之後才是 `idd-verify`。

理由是 #392 的原則：合併的就是審查過的那個 commit。封存若放在 verify 之後，合併前還要多一個沒審過的 commit；放在合併之後，就是現在沒有人做的那一步。

`rules/sdd-integration.md` 的「Close triggers archive」與流程圖的「close + archive」要改成這個順序。

**Alternatives considered**：verify 通過後才封存、封存 commit 不再審。沒有採用：封存會套用 delta，那個 commit 改的正是主規格。

### 宣告寫在 Implementation Complete 留言的 Spec 行

宣告放在留言而不是 issue 正文：留言由有寫入權的帳號貼出後，issue 的作者改不了；正文可以被外部作者改。標記 `<!-- idd:comment type=implementation-complete -->` 用來分辨新舊：沒有標記也沒有 Spec 行的是舊制留言，不追溯。

Spectra tier 之後也貼這則留言（由 `idd-all` 的收尾貼），內容是 Spec 行、change 名稱與 commit；它的 checklist 仍然留在 `Current Status > Tasks`，所以這則留言沒有 `### Checklist` 小節。`append-vs-modify-discipline` 的 authoritative source 第一順位是那個小節，沒有小節時照既有規則落到第二順位；實作時要用 `authoritative-source-producer` 的測試確認這一點。

### 機械判定集中在 scripts/spec-change.py

四個子指令，各有 Example 表與測試：`preflight`、`declared`、`archived`、`links`。SKILL 的敘述只負責呼叫它們並照結果行動。這是 #351、#392 得到的做法：判定寫成有判定表的程式，才測得到邊界。

- `links` 的範圍由呼叫端給（`--base` 必填）。不給預設值，是因為在預設 branch 上直接 commit 的 run 沒有「跟預設 branch 的分岔點」，預設值會讓檢查永遠通過。
- 測試的標記是 `spec-example: <capability> / <Example title>`，所以 Example 的標題在一個 capability 內要唯一。標記只證明有一個測試指名這個 Example；測試是否真的檢查了 Example 寫的事，由 verify 的 reviewer 判斷。
- 搜尋字串的測試不能當成 requirement 的檢查（#480 的決定）。由模型照 SKILL 執行、寫不出檢查的 requirement，寫一行 `No executable check:` 與理由，由 verify 審。

### 規格目錄照 Spectra 的規則解析

Spectra 3 的 `spectra init` 預設把規格放在 `docs/spectra/`，`.spectra.yaml` 寫 `spec_dir: docs/spectra`；設定檔沒有這一欄時是 `openspec`（設定檔裡的說明原文：New projects initialize at docs/spectra; configurations without this field resolve to openspec）。本 repo 屬於後者。所以 `spec-change.py` 不寫死 `openspec/`，照同一條規則解析；`archived` 與 `links` 讀被檢查的那個 revision 的設定檔，`preflight` 讀工作樹的。解析出的路徑是絕對路徑、空的、或跑出 repo 時回 `error`，不退回 `openspec`。實作 task 2.1 時在暫存 repo 跑 `spectra init` 才發現這件事。

### verify 之後的修正走同一個 wrapper

修正若新增或修改 requirement，就是這張 issue 的另一個 change（`idd-<N>-fix<k>`），同樣在下一輪 verify 之前封存，新的 Implementation Complete 留言列出這張 issue 的所有 change。requirement 與 Example 已經存在、只是測試沒寫對的，補測試即可。

Blocking 的修正要留下一條寫出該性質的 requirement、Example 與修正前會失敗的測試。這是 #423 留言裡「改動帶進來的 HIGH」的對策落在這張的部分。

### linked worktree 先停下

`preflight` 偵測到 linked worktree 就停下，不呼叫任何會寫入的 Spectra 指令。代價是 `idd-implement` 在主工作樹被鎖住時改用 linked worktree 的那條路，對要寫規格的 issue 走不通，要等隔離工作樹改成獨立 clone，或 Spectra 自己修正。這條限制要寫進 `idd-implement` 的 tree-lock 那一步與 README。

## Implementation Contract

**行為**

- 任何 tier 的 issue 實作完，Implementation Complete 留言都有標記與一行 `**Spec**:`；宣告了 change 的，審查的 commit 上已經封存。
- `idd-verify` 的報告多出三種來源的 finding：連結檢查缺漏（Blocking）、宣告的 change 沒封存（Blocking）、Regression lens 對照規格找到的行為改動（HIGH）。
- `idd-close` 在宣告的 change 還沒出現在預設 branch 的封存目錄時不關 issue。
- 自己的 repo 缺 Spectra、缺規格目錄、或在 linked worktree 裡時，wrapper 在建立任何東西之前停下。

**介面**

- `spec-change.py preflight --cwd <dir> --can-write <yes|no>` → `{"status": "ready" | "third-party" | "linked-worktree" | "install-spectra" | "init-openspec", "message": …}`，exit 0（前兩種）或 1。
- `spec-change.py declared --file <comment>` → `{"form": "change" | "no-behaviour-change" | "third-party-clone" | "legacy" | "invalid", "changes": […], "reason": …}`，exit 0、1（invalid）或 2（讀不到檔）。
- `spec-change.py archived --file <comment> --cwd <dir> --ref <rev>` → `{"status": "pass" | "refuse" | "error", "not_archived": […], "reason": …}`，exit 0、1、2。
- `spec-change.py links --base <rev> [--head <rev>] [--cwd <dir>]` → `{"status": "ok" | "missing" | "error", "missing": [{"capability", "requirement", "example", "why"}]}`，exit 0、1、2。
- 四個子指令的參數錯誤都是 exit 64，不印 JSON。
- 留言的標記與宣告行：`<!-- idd:comment type=implementation-complete -->`、`**Spec**: change <name>[, <name>…]`、`**Spec**: no behaviour change`、`**Spec**: third-party clone`。change 名稱只接受小寫字母、數字與連字號。
- 測試檔裡的標記：`spec-example: <capability> / <Example title>`。

**失敗時**

- 四個子指令遇到讀不到的 revision、不是 git repo 的目錄、解析不了的規格檔，一律回 `error`（exit 2），不回 `ok` 或 `pass`。
- wrapper 在 Spectra 的 verify 回報 critical、`links` 回 `missing`、封存沒有落在目前的工作樹時停下，不貼 Implementation Complete。
- 第三方 clone 不停下，照舊實作，宣告 `third-party clone`。

**驗收**

- 規格裡五個 Example 表（讀宣告行、是否已封存、連結檢查、preflight、結案檢查）在 `scripts/tests/spec-change/test.sh` 各有測試，測試帶著對應的 `spec-example:` 標記；這份 change 自己要通過 `links`。
- 在一個暫存 repo 上各跑一張 Simple 與一張 attended Plan：branch 上出現封存目錄與主規格的改動，留言有 Spec 行，`idd-verify` 的報告列出連結檢查與封存檢查的結果。
- 一張只改 README 錯字的 issue：沒有 change，留言宣告 `no behaviour change`，verify 沒有相關 finding。

**範圍**

- In scope：`scripts/spec-change.py` 與測試、`references/spec-wrapper.md`、`idd-implement`、`idd-plan`、`idd-all`（Spectra tier 的收尾與留言）、`idd-verify`（Regression lens、兩個檢查）、`idd-close`（封存檢查）、`idd-diagnose`（下一步的說明）、`rules/sdd-integration.md`、README、CHANGELOG。
- Out of scope：Non-Goals 列的六項；Spectra 自己的 skill 與 CLI；`idd-all-chain`（併入 `idd-all` 是 #478 與另一張的事）。

## Risks / Trade-offs

- **每張 issue 變慢、變貴**：Simple 多了 propose、Spectra 的 verify、封存與一個 change 目錄。→ 輕量形式不做 discuss 與 design；實作後在暫存 repo 量一張 Simple 多花的時間，寫進 CHANGELOG。
- **依賴擴大**：Spectra 的 CLI 或 skill 介面一變，每一張 issue 都受影響。→ 介面的使用集中在兩個 wrapper 與一份契約；`preflight` 在開始前就檢查 CLI 與目錄。
- **linked worktree 這條路對要寫規格的 issue 走不通**。→ `preflight` 明確停下並說明；另開 issue 處理隔離方式。
- **標記可以指向一個不檢查任何事的測試**。→ 規格寫明標記只是名稱上的連結；reviewer 要看測試內容，名不副實是 MEDIUM 以上的 finding。
- **「不改變行為」的第四種情況（重構）靠 reviewer 判斷**。→ 宣告本身進報告；範圍內有任何行為改動就是 HIGH，方向是寧可多報。
- **這份 change 自己會經過很多輪 verify**：它改的是分流、驗證與結案。→ 先寫 `spec-change.py` 的 Example 表與測試再實作；verify 找到的 Blocking 先補進規格。
- **與 #392 的衝突**：兩邊都改 `idd-all`、`idd-verify` 的 SKILL。→ #392 先合併；這份 change 在那之後才 apply，apply 前重新 validate。2026-11-11 對 3.7.0（`03f5559`）重新核對（task 1.1）：`spectra validate` 與 `spectra analyze` 都沒有問題；delta 碰到的規格在 main 上沒有被 #392、#424 改過。實作時要接上的三處：
  - `idd-close` 的封存檢查要比照 Step 1.55、1.6 寫出 `ORCHESTRATED BY /idd-all` 時的行為：不問，`refuse` 或 `error` 就停下、不 close，原因寫進輸出。
  - `idd-verify` 新增的兩種 Blocking（`links` 缺漏、`archived` 拒絕）要寫成 Findings 表的列、Action 欄是 `Blocking`，否則 #392 的 verify gate 讀不出來。
  - 封存 commit 是 run 自己的 branch 上的本機 commit，不是新的對外動作，idd-all 的〈權限〉表不用改。現有的留言都沒有用 `type=implementation-complete` 這個標記，新標記不會撞到。

## Migration Plan

1. #392 合併並發布後，重新對 main validate 這份 change，補上 close stage 需要的封存檢查接點。
2. 先做 `spec-change.py` 與測試（不改任何 skill 的行為），再改 wrapper，最後改 verify 與 close。
3. 發布後，既有 issue 的舊制留言（沒有標記）不受影響；進行中的 issue 下一次貼 Implementation Complete 時才開始適用。
4. 退回的做法：回復 skill 的改動即可。已經封存的 change 與主規格的改動是正常的 Spectra 產物，不需要清除。

## Open Questions

- Spectra tier 的收尾由 `idd-all` 做；人手動跑 `/spectra-apply` 之後的收尾由誰做，這次沒有定（目前靠本 repo 自己的 `/spectra-archive`）。
- 補齊既有 requirement 的 Example 時，是否沿用同一種標記，等這份 change 用過一輪再決定。
