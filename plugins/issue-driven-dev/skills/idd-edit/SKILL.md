---
name: idd-edit
description: |
  編輯既有 GitHub issue comment。支援 append/replace/prepend-note/correct 四種 mode；`--correct` 也能更正 issue 正文（`issue:<N>`，#351）。
  必 show 原 body + preview 新 body 讓 user confirm。用 `gh api -F body=@file` 避免 backtick escape bug。
  支援 batch mode（v2.34.0+）：多個 comment 套同一段 edit（如 `comment:NNN comment:MMM --replace --body '...'`），每個 comment 仍 per-confirm。
  Use when: 補既有 comment 說明（如圖片下方解釋）；內容有錯（打錯字、事實錯誤、被推翻的結論都算）→ `--correct` 就地取代（舊版歸檔、AI 讀不到）。
  防止的失敗：手動 `gh api PATCH` 字串 escape 錯誤、誤覆蓋未 backup 的原內容。
argument-hint: "comment:<id>[ comment:<id>...]|#issue --last|issue:<N> (--append|--replace [--scope whole-comment|--section <heading>]|--prepend-note|--correct (--scope whole-comment|--section <heading>)) [--body=... | --body-file=...] [--reason=...] [--override-user-content --reason='...']"
allowed-tools:
  - Bash(gh:*)
  - Read
  - Write
---

# /idd-edit — Edit existing issue comment

解決手動 `gh api PATCH` 的痛點：字串 escape（backtick 常炸）、容易誤覆蓋、沒 audit trail。

## 核心原則

> Edit 是破壞性動作。**原 body 必 backup，新 body 必 preview，修改必留 metadata**。

## Batch mode（v2.34.0+）

`idd-edit comment:NNN comment:MMM --replace --scope whole-comment --body '...'` 把同一段內容套到多個 comment。Edit 是破壞性動作，batch 把破壞範圍放大 N 倍 — preview + per-comment confirm 仍照舊（不允許 `--yes-to-all`），但每個 confirm 後就推進，不需要 N 次重打命令。

**v2.81.0+ R4/R5 在 batch mode 下 per-target 評估**:
- R4 (`--replace` 必要 scope) 一次套用全 batch
- R5 (author check) **per-target**:mixed OWNER + non-OWNER 批次採**語意 (i) per-comment refuse + 繼續**（#158 拍板 2026-07-11）— OWNER 的照做、non-OWNER 的 prepare 記為 refused 後換下一個 target,絕不因單一 refuse 殺整批（不中斷 batch（#158 語意 (i)））;`--override-user-content` 語意為 **all-targets + reason 共用**（全 batch 啟用 override,一個 reason 進所有 audit markers）
- 批次結束由 Step 5 `finish` 輸出 outcome report（`edited / refused` + 顯著標記）;exit contract 依序比對、先中者為準:任一 refused 或寫入失敗 → exit 4（M>0 → exit 4,單 target 退化等價 — 契約鎖於 tests/edit-run）;已寫入但讀回失敗或不符 → 7;使用者拒絕任一預覽 → 9;其餘 → 0

完整契約見 [batch-and-cluster.md](../../references/batch-and-cluster.md)。罕見場景：跨 issue 的 typo 統一修、補同一段 errata note、把多個 stale comment 統一標 deprecated。

## When to use `idd-issue` multi-finding mode instead（v2.55.0+）

> **例外（#351）**：內容**確定是錯的**（打錯字、事實錯誤、被推翻的結論）一律走 `--correct`，不走 multi-finding 的 `edit body` —— 後者不歸檔、不檢查 Original text，錯的舊版會留在 AI 讀得到的地方。

如果你要做的是「**從一個 source 文件抽多個 findings,部分 edit 既存 issue body**」(典型場景:transcript 含 5 個對既存 issues body 的修正,e.g. 「H4 hypothesis 重新表述」「reputation 變 core IV 改 framing」),**不要**手動跑 `idd-edit` 多次,改用 `idd-issue` multi-finding mode:

```bash
idd-issue source.docx       # auto-trigger when source contains ≥2 findings
```

差別:

| 情境 | 用 idd-edit | 用 idd-issue multi-finding mode |
|------|------------|-------------------------------|
| 已知 N 個 comment 套同一段 edit | ✅ batch mode | overkill |
| 從 source 文件分流多 finding,部分 edit body / 部分 comment / 部分 new | 5+ 次 invoke + 失 audit trail | ✅ 一次 invoke + Stage 2 picker 對每筆選 routing intent(`comment` / `edit body` / `update status`) |
| 需要 per-action footer 連結回 source | 手動加 | ✅ 自動加 |

完整 multi-finding mode 契約見 `idd-issue` SKILL.md `## Multi-finding source mode` 段落。

## 四種 Edit Mode

| Mode | 動作 | 原 body | 適用 | 強制 flags |
|------|------|--------|------|-----------|
| `--append` | 在末尾加 `---\n**Edit YYYY-MM-DD**: {reason}\n\n{body}` | 保留 | 補充 / 更正（保留歷史） | `--reason` |
| `--replace` | 完全替換 body 或指定 section | 寫入 backup 檔 | 大幅改寫（如補圖說明） | `--reason` + **`--scope whole-comment` OR `--section <heading>`**（R4 enforced）|
| `--prepend-note` | 在最上方加 `> ⚠️ {reason}\n\n---\n\n` | 保留 | 標示「此 comment 已過時」 | `--reason` |
| `--correct` | 就地取代確定錯誤的整則 comment 或指定 section，區段末尾加帶 `backup-id` 的標記 | 歸檔到 correction archive（不進 git、權限 0000、hook 擋 AI 讀取） | 內容確定是錯的、使用者已確認（#351） | `--scope whole-comment` OR `--section <heading>`；`issue:<N>` 只接受 `--section`；不接受 `--override-user-content` |

## 動作分類 (per [`#150` action-scoped modify discipline](../../rules/append-vs-modify.md))

| Mode | Category | Scope contract |
|------|----------|---------------|
| `--append` | `audit-block-append` | trailing block,inherently bounded — no `--scope` needed |
| `--replace --scope whole-comment` | `bounded-section-replace` | scope = whole comment(explicit acknowledgment of full overwrite）|
| `--replace --section <heading>` | `bounded-section-replace` | scope = named markdown subsection only |
| `--prepend-note` | `audit-block-append` | leading errata marker,inherently bounded — no `--scope` needed |
| `--correct` | `in-place-correction` | 一個 bounded region（整則 comment 或一個 section）；歸檔後才寫入 — `(category: in-place-correction)` |

## Runtime gates (#154, v2.81.0+)

`/idd-edit` enforces 2 SHALL requirements at runtime via the **Python helper** `plugins/issue-driven-dev/scripts/idd-edit-helper.py` (#155 — replaces inline bash that was non-convergent over 3 verify rounds; the Python layer eliminates the R1/R2/R3 bug classes by-construction). Call `python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" <subcmd> ...` and branch on its exit code:

| Requirement | Gate | Refuse code |
|-------------|------|-------------|
| **R4** (spec) | `--replace` without `--scope`/`--section` → refuse | exit 3 |
| **R5** (spec) | 作者不是 OWNER、bot 或你自己（目前的 gh 使用者），且沒有 `--override-user-content --reason="..."` → refuse；`--correct` 只放行你自己寫的（OWNER 由別人執行時也拒絕、bot 也拒絕、沒有 override；查不到 gh 使用者 → exit 1） | exit 4 |
| `--correct` scope | 缺 `--scope`/`--section`，或 `issue:<N>` 用 whole scope → refuse | exit 3 |
| `--correct` override | `--correct` 併用 `--override-user-content` → refuse（協作者 comment 只提議、不改） | exit 2 |
| Protected regions | `check-correction`：目標是或包含 `## Current Status`／`### Clarity Surface`（含其下的子標題，逐行比對、與 idd-update 相同）、替換內容帶入這些標題、`Original text`／`**Original**` 引用被改或後面緊接文字、整則更正拿掉開頭的型別標題 → refuse。`compose-correction`：替換內容留下沒關閉的 fence 或 HTML 註解 → refuse。段落邊界取自 Markdown parser（頂層 ATX 標題、分隔線；code 與 HTML 區塊裡的行不算）；`--correct` 範圍內有 setext 標題、或替換內容新增 setext 標題 → refuse（`REASON=setext`） | exit 6 |
| Markdown parser | `section-replace`／`check-correction`／`compose-correction` 需要 `markdown-it-py` 4.0.0（`scripts/requirements-egress.txt`）；缺或版本不符 → refuse、不改任何東西 | exit 8 |
| Ambiguous section | `--section` 的標題在原文出現不只一次 → refuse（不選第一個） | exit 9 |
| Archive | `archive` 子命令：不在 git work tree、歸檔路徑沒被 ignore、寫入失敗 → refuse，不 PATCH。`--correct` 在 prepare（預覽之前）就檢查，記為 `REASON=archive` | exit 7 |

> 上表是 helper 各子命令的結束碼；一次 `/idd-edit` 執行的結束碼是 Step 5 `finish` 的（4、7、9 在那裡的意思不同：prepare 或 apply 的拒絕一律算 4）。

Override pathway:`--override-user-content --reason="<rationale>"` 顯式同意修改 user content。 Audit marker `<!-- idd:edit override-user-content date=... reason="..." -->` 自動 append。

## Configuration

按 [config-protocol](../../references/config-protocol.md) 解析 target repo:

- `--repo owner/repo` flag → per-invocation override
- Walk-up `.claude/issue-driven-dev.local.json`(從 cwd 往上找)
- Path / git predicates 自動匹配

**Group/predicate 行為**:`idd-edit` 操作既存 comment,只用 path/git 類 predicate。Group config 會 fall through 到 primary repo。

## Target Comment 指定方式

兩種都支援（方便 AI 編輯）：

| 語法 | 意義 |
|------|------|
| `comment:<numeric-id>` | 直接用 GitHub comment ID（從 URL 尾部 `#issuecomment-<id>` 取） |
| `#NNN --last` | issue #NNN 的**最後一個** comment |
| `#NNN` | issue #NNN → 列出所有 comments 讓使用者選（AskUserQuestion） |
| `issue:<N>` | issue #N 的**正文**（只限 `--correct --section`；其他模式見 #347） |

## Execution

一次 `/idd-edit` 分成五步，每一步是**一次** Bash 呼叫、**一行** helper 指令。使用者確認前後是不同的 Bash 呼叫，shell 變數、陣列、迴圈都不會留下（#351 verify 第 6、7 輪：舊版把整次執行寫成橫跨確認的一段 bash，確認後的區塊讀不到 `MODE`、`TARGET`、結果陣列，被拒的更正還會回報 0）。所以：

- 一次執行的狀態（解析好的引數、每個 target 的進度與結果）存在 helper 的 run 目錄裡，不在 shell 變數裡。
- 每一步只帶**前一步印出的字面值**：`<REPO>`、`<ARGS>`、`<RUN>`、`<TARGET>`、`<SCRUB>`、`<STATE>`。照抄上一步的輸出填進角括號，不要自己組、不要重跑前一步。
- 整次執行的結束碼是 Step 5 `finish` 的結束碼（idd-comment 的 errata 路徑依它分流）。

`scripts/tests/edit-run/` 把下面每個區塊抽出來，一個區塊開一個空環境的 shell（zsh 與 bash）執行，只代入這些字面值。

### Step 0: Bootstrap Stage Task List（強制)

**在動任何事之前**先用 `TaskCreate` 為這個 stage 建 todo list,確保每個 sub-step 都被追蹤:

```
TaskCreate(name="start_run", description="Step 1：依 config-protocol 解析 repo（<REPO>），run-start 解析引數（R4 等閘門）、解析 target 與隱私等級；記下 RUN= / SCRUB= / 每個 TARGET=；PICK=#N 時列出 comments 讓使用者選")
TaskCreate(name="prepare_targets", description="Step 2：每個 target 一次 prepare —— 作者閘門、讀原文、備份、組新內文、egress 預檢；RESULT=refused 就換下一個 target")
TaskCreate(name="privacy_scrub_gate", description="Step 3：依 SCRUB 等級對 PREVIEW 做 rules/privacy-scrubbing.md 的語意自審；enforce 命中 → 顯示 redaction diff、使用者確認前不 apply")
TaskCreate(name="preview_and_confirm", description="Step 3：顯示 DIFF 與 PREVIEW（--correct 顯示完整全文），AskUserQuestion 確認，預設 NO")
TaskCreate(name="apply_or_discard", description="Step 4：確認 → apply（照抄 RUN / TARGET / SCRUB，--correct 另帶 STATE）；拒絕 → discard")
TaskCreate(name="finish_run", description="Step 5：finish —— 印 outcome report，其結束碼就是這次 /idd-edit 的結束碼（0／4／7／9）")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。**TaskCreate 清單 = 真實的步驟清單；任何寫在 skill 裡但沒列進 TaskCreate 的步驟，都視為 skill 的 bug，必須補進 Task 清單。**

特別提醒：**idd-edit 是破壞性動作**，每一步都必須在 task list 留痕。`prepare_targets` 跳過 = 沒有 backup；`preview_and_confirm` 跳過 = 跳過使用者把關；`finish_run` 跳過 = 沒有結束碼，呼叫端（idd-comment）無從分流。

---

### Step 1: Start the run

`<REPO>` 依下方 Configuration（config-protocol）解析；`<ARGS>` 是使用者給 `/idd-edit` 的引數原樣，每個引數用單引號包起來（引數本身含單引號時寫成 `'\''`）。

```bash
# step: start — one call; prints RUN=, REPO=, SCRUB=, then TARGET= / PICK= lines
python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" run-start --default-repo "<REPO>" -- <ARGS>
```

- 結束碼 2、3、5：引數錯誤（R4 → 3、`--body-file` 讀不到或被路徑閘門擋 → 5），stderr 有說明。**這就是整次執行的結束碼**，不必再跑後面的步驟。
- `PICK=#N`：使用者寫了 `#N` 但沒有 `--last`。列出 #N 的 comments（`gh api "repos/<REPO>/issues/N/comments" --jq '.[] | "\(.id) | \(.created_at) | \(.body | .[0:80])"'`），用 AskUserQuestion 選一則，把 `comment:<選中的 id>` 當成一個 TARGET。
- `SCRUB=` 是這個 repo 的隱私等級（third-party → `enforce`、自己的 public → `warn`、private → `light`，見 [`rules/privacy-scrubbing.md`](../../rules/privacy-scrubbing.md)）。

### Step 2: Prepare one target

每個 TARGET 依序做 Step 2–4，一次一個（batch mode 也是逐一確認，#158）。

```bash
# step: prepare — one call per target
python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" prepare --run "<RUN>" --target "<TARGET>"
```

- `RESULT=refused` 與 `REASON=`：這個 target 不改（R5、fetch-failed、egress、protected、setext、section-not-found、section-ambiguous、archive …，stderr 有原因），直接換下一個 TARGET。拒絕已記在 run 裡，`finish` 會列出。
- 成功時印出 `PREVIEW=`（新內文全文）與 `DIFF=`（目前內容 → 新內文的差異）；`--append`／`--replace`／`--prepend-note` 另印 `BACKUP=`（原內文的備份），`--correct` 另印 `WORK=` 與 `STATE=`。

`--correct`（`(category: in-place-correction)`）在 prepare 這一步跑完讀原文、作者閘門（只放行你自己寫的）、受管區與引文檢查、組出要寫入的全文、egress 預檢；確認後的 apply 會再重抓比對、重組比對預覽、歸檔、寫入、讀回。helper 自己算歸檔路徑；**本 skill 執行的 bash 不寫出歸檔路徑**，否則會被 archive-read-guard hook 擋下。

### Step 3: Preview, privacy review, confirm

1. 用 Read 工具讀 `DIFF=` 那一行的路徑並完整顯示：使用者要看得出哪些內容被刪掉或改寫（#351 verify 第 7 輪：只給新全文時看不出來）。
2. 用 Read 工具讀 `PREVIEW=` 那一行的路徑：`--correct` **完整**顯示（`(assigned after confirmation)` 在確認後換成實際的 backup id）；其他 mode 至少顯示前 40 行。
3. 隱私自審（`privacy_scrub_gate`）：依 `SCRUB` 等級，對 PREVIEW 做 [`rules/privacy-scrubbing.md`](../../rules/privacy-scrubbing.md) 的語意檢查（本機路徑、未公開的協作者真名、未發表的內容）。`enforce` 命中 → 顯示 redaction diff，使用者確認前不進 Step 4；`warn` 命中 → 印一行提醒。
4. AskUserQuestion 確認，預設 NO（破壞性動作）。

### Step 4: Apply or discard

使用者確認：

```bash
# step: apply — after the user confirmed; <STATE> is the STATE= value for --correct, empty ("") otherwise
python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" apply --run "<RUN>" --target "<TARGET>" --scrub-attested "<SCRUB>" --state "<STATE>"
```

`--scrub-attested` 填 Step 1 印出的 `SCRUB`，表示 Step 3 的隱私自審做過了；與這個 run 的等級不符 → exit 2。印出 `RESULT=`：`edited`（另有 `URL=`）、`refused`（`REASON=`）、`write-failed`（gh 自身錯誤，重讀確認未寫入）、`unverified`（已寫入但讀回不符，請手動檢查）；`--correct` 有歸檔時另印 `BACKUP_ID=`。不要重跑 prepare、也不要自己算 STATE —— 那會讓 apply 比對的不再是使用者看過的預覽。

使用者拒絕：

```bash
# step: discard — the user declined
python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" discard --run "<RUN>" --target "<TARGET>"
```

### Step 5: Finish（outcome report 與結束碼，#158）

所有 TARGET 都處理完（或使用者中止）後一定要跑：

```bash
# step: finish — after every target; prints the outcome report and exits 0 / 4 / 7 / 9
python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" finish --run "<RUN>"
```

部分成功絕不偽裝成全成功：report 逐一列出 EDITED／REFUSED(<reason>)／REFUSED(egress)／DECLINED／FAILED(write)／UNVERIFIED。結束碼依序比對、先中者為準：

| 結束碼 | 意思 |
|---|---|
| 4 | 有 target 被拒（含 egress 拒絕、prepare 後沒有 apply 或 discard 的 `not-applied`），或寫入失敗 —— 它沒有被改 |
| 7 | 已寫入，但讀回失敗或不符 —— 請手動檢查 |
| 9 | 沒有拒絕或失敗，但使用者拒絕了至少一個預覽 |
| 0 | 全部完成 |

2、3、5 只來自 Step 1（引數錯誤），不會與上表重疊。這張表就是 batch 的 exit contract（單 target 退化等價），由 `scripts/tests/edit-run/` 的行為測試鎖定。

## Metadata Marker

每次 edit 在 body 加 HTML comment：

```html
<!-- idd:edit mode=<mode> date=<date> [backup=<path>] -->
```

`--correct` 的標記只帶 backup id、不帶路徑，放在被取代區段的最後一行：

```html
<!-- idd:edit mode="correct" backup-id="comment-5805214375-20261009T100000Z" date="2026-10-09" -->
```

多次 edit 會 **append 多個 marker**（不覆蓋前次），形成 edit history。

## 使用範例

### 補既有 comment 的圖片說明（自己發的 comment,whole-comment scope）

```
/idd-edit comment:4241327867 --replace \
  --scope whole-comment \
  --body-file=~/notes/new-implementation-summary.md \
  --reason="依新 skill 規則補圖下方資料/統計/結論說明"
```

### 修錯的數字或錯字（`--correct`，單 section）

錯的值直接換掉，不在後面追加「修正：…」（#351：追加的更正會讓錯的原文繼續被讀到）。

```
/idd-edit #18 --last --correct --section "### Results" \
  --body-file=~/notes/fixed-results.md \
  --reason="p-value 計算誤差，重跑後為 56.3%"
```

### 修 Diagnosis comment 內某 ### 區段（自己發的 comment）

```
/idd-edit comment:4530594011 --replace \
  --section="### Strategy" \
  --body-file=~/notes/new-strategy.md \
  --reason="重新拆 Block A → B 依賴順序"
```

### 更正確定錯誤的內容（`--correct`，#351）

```
/idd-edit comment:4241327867 --correct --section "### Strategy" \
  --body-file=~/notes/fixed-strategy.md \
  --reason="備份位置寫錯，實際不進 git"

/idd-edit issue:351 --correct --section "## Expected" \
  --body-file=~/notes/fixed-expected.md \
  --reason="誤讀了需求"
```

別人發的 comment（含 OWNER 由你以外的人執行時、bot）不用 `--correct`：改用 `/idd-comment --type errata` 另貼更正（`--correct` 沒有 override）；是你用另一個 GitHub 帳號寫的，就 `gh auth switch` 切過去再跑。issue 正文以開 issue 的人為作者，別人開的 issue 正文裡的錯誤改用 `/idd-comment --type correction`。

**改不到的地方（已知限制，2026-10-17 使用者決定）**：不屬於任何標題的文字 —— issue 正文最後一條 `---` 之下（例如 IC_R011 的 `**Source**` 註腳）、或第一個標題之前 —— `--section` 搆不到，issue 正文也沒有整則範圍。這類錯誤用 `/idd-comment --type correction` 追加更正。

## 鐵律

- **原 body 必 backup**：`--append`/`--replace`/`--prepend-note` 由 prepare 存到使用者暫存目錄下的 `idd-edit-backup/comment-<id>-<unix time>.md`（Step 2 印出 `BACKUP=`，run 結束後仍保留）；`--correct` 確認後歸檔到 correction archive（永久、不進 git、AI 讀不到）；它的工作副本在使用者暫存目錄的 `idd-correct-*`，由 apply／discard／finish 刪除，未完成的一天後由下一次 prepare 清掉
- **Preview 必 show**：即使是 `--append` 也要 show 最終 body 讓使用者確認
- **`-F body=@file` 不是 `-f body=""`**：避免 backtick escape（`gh api` 會把 heredoc 裡的 backtick escape 成 `\`）
- **Metadata marker 不覆蓋**：每次 edit 加新 marker，保留 history
- **`--replace` 預設 confirm = NO**：破壞性動作不自動 yes
- **Log 每次 edit**：顯示 URL 讓使用者能立即 verify
- **`--body-file` path safety（#155）**：helper **canonicalize（`os.path.realpath`）後拒絕** sensitive system paths（`/etc` `/var` `/sys` `/proc` `/private/etc|var`）+ credential dirs（`.ssh` `.aws` `.gnupg` `.kube` `.docker`），含 `//etc` / `/tmp/../etc` / symlink / relative-traversal bypass vectors → exit 5 refuse。Escape hatch：`IDD_EDIT_HELPER_ALLOW_UNSAFE_BODY_FILE=1`（須自審 reason）。合法 repo / `/tmp` / `$HOME/Developer` 路徑照常讀；使用者自己的暫存目錄底下（macOS 在 `/var/folders/…`）也放行（#351）。Preview gate 仍是最後一道防線。

## 與 idd-comment 的配合

**errata flow**（#351 起依 target 作者分流，由 `/idd-comment --type errata` 決定）：

```
/idd-comment #NNN --type=errata --target-comment=XXX ...
  ├─ XXX 是你本人寫的        → /idd-edit comment:XXX --correct ...（不另貼 comment）
  │                              └─ 更正被拒或寫入失敗（exit 4）→ 改貼 errata，再提議 --prepend-note 指向它
  │                                 （原 comment 的第一個非空行是 ATX 標題或 IDD 標記時不加）
  └─ 其他作者（含 OWNER、bot）→ 只貼 errata comment，不呼叫 idd-edit
```

## Backup 管理

**`--append` / `--replace` / `--prepend-note`**：備份在使用者暫存目錄下的 `idd-edit-backup/`（目錄權限 0700），檔名 `comment-<id>-<unix time>.md`，同一秒再有一份就加 `-2`；Step 2 印出完整路徑（`BACKUP=`）。3.4.0 以前在 `/tmp/idd-edit-backup/`；macOS 的使用者暫存目錄在 `/var/folders/…` 底下。

```bash
ls -la "${TMPDIR:-/tmp}/idd-edit-backup/"
# 回復（災難復原刻意走 raw gh api、不經 egress 網 — 還原的是先前已公開發佈的內容）
gh api "repos/<REPO>/issues/comments/<id>" \
    -X PATCH \
    -F body=@"<Step 2 印出的 BACKUP= 路徑>"
```

**`--correct`**：舊版在 correction archive，用 backup id（標記裡那個）還原。內容直接送給 GitHub、不顯示；還原的是**整個**目標，更正之後的修改（例如 `idd-update` 重建的 Current Status）會一起被蓋掉，執行前用 AskUserQuestion 說明這點並確認。

```bash
python3 "$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.py" restore "<the backup-id in the comment's correction marker>" --repo "<REPO>"
```

歸檔檔不經過 Claude 讀取（hook 會擋、檔案權限 0000）。人要看舊版時，在自己的終端機 `chmod u+r` 該檔後用編輯器開，不要透過 Claude；看完 `chmod 000` 改回，否則 `grep -r` 這類不寫出路徑的遞迴讀取會讀到它。

歸檔是被 git ignore 的檔案：`git clean -X`（或 `-x`）會把它刪掉，而它是更正前內容在本機唯一能還原的一份 —— 在有歸檔的 clone 裡不要跑這兩個指令（移到更安全位置的討論在 #407）。

歸檔只存在**執行 `--correct` 的那份 clone**（它的主 worktree）。同一個 repo 在別處的 clone 沒有這份歸檔，`restore` 會回報找不到；要還原就回到原本那份 clone 執行。

## Next Step

Edit 後通常不需要後續 skill。如果是修 diagnosis comment，可能要重跑 `/idd-verify`。
如果是 errata flow，由 `/idd-comment` 統一 orchestrate。

## SKILL↔helper Contract（#163）

本 SKILL 的每個步驟區塊只讀 `$CLAUDE_PLUGIN_ROOT`，其餘都是前一步印出的字面值（`<RUN>` 等）；`scripts/tests/edit-run/` 實際執行這些區塊。舊的變數契約由 **`scripts/tests/idd-edit-contract/`** 靜態鎖定：SKILL fenced bash 內消費的每個大寫 `$VAR` 必有出處 —（a）SKILL block 內賦值、（b）helper `emit_assignment` / `TARGETS` emit（**helper 源碼即 source of truth**，本節不重列變數清單）、（c）環境 allowlist（`CLAUDE_PLUGIN_ROOT`、`IDD_CALLER` #161 等，明文列於 checker）。此層封殺 #154 R1 B1（`$APPEND_BODY`）/ B2（`$GITHUB_REPO`）的「fixtures 全綠、production 壞掉」class。

**掃描邊界**：只掃 fenced bash blocks（heredoc 在內 — B1 就住在 heredoc）；single-quote 不展開造成的 false positive 由 allowlist 消化；loop 結構 class（R2 H7）不在此層 — 由 `scripts/tests/idd-edit/` fixture 14 的 prose 契約覆蓋。編輯本 SKILL 引入新變數時：在 block 內賦值、或經 helper emit、或（僅環境變數）進 checker allowlist — 三者皆非會被 suite 擋下。
