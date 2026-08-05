## 0. 追溯對照（Traceability）

spec 依規定為英文、tasks 依 locale 為繁中，故以逐字名稱建立對應。

| Spec requirement（逐字） | Tasks |
| --- | --- |
| Gate logic SHALL resolve authoritative source | 1.1, 1.2, 3.1, 3.2, 4.1 |
| A checklist file outside the current work tree SHALL be refused as a task source | 1.3, 2.1, 2.2, 2.3 |
| The layout of an external checklist source SHALL NOT be hardcoded | 2.4, 3.3, 4.2 |

| Design 決策（逐字標題） | Tasks |
| --- | --- |
| 決策 1：`exists` ＝ heading 在**且**至少一個可解析項目 | 1.1, 3.1 |
| 決策 2：producer 是 `--tasks-file <path>`，不是 change name | 2.1, 3.2 |
| 決策 3：路徑由呼叫端**查詢**取得，不由任何一方組出 | 2.4, 3.3 |
| 決策 4：flag 缺席時不 emit `### Tasks` | 2.3, 3.2 |
| 決策 5（本次新增）：路徑必須落在當前 git toplevel 內，否則拒絕 | 1.3, 2.2 |

| Implementation Contract 小節 | Tasks |
| --- | --- |
| behavior | 2.1, 2.2, 2.3 |
| interface / data shape | 2.1, 2.4, 3.2 |
| failure modes | 1.3, 2.2, 2.3 |
| acceptance criteria | 4.1, 4.2, 4.3 |
| scope boundaries | 4.3 |

## 1. 測試先行（TDD：先紅後綠）

- [x] 1.1 寫出**會失敗**的 fixture 測試（`plugins/issue-driven-dev/scripts/tests/authoritative-source-producer/test.sh`，比照 `doc-sync-sweep/test.sh` 的形狀 ＋ `lib/assert-helpers.sh`）：對「heading ＋ 0 項」「heading ＋ 1 項未勾」「heading ＋ 3 項已勾」三種 fixture 斷言 resolve 與否符合 spec 的 Example 表。驗證目標：跑該 test.sh 出現 fail（判準尚未寫進任何文件）。（Requirement: Gate logic SHALL resolve authoritative source）
- [x] 1.2 同檔加 drift-lock：斷言 `rules/append-vs-modify.md` 含 `exists` 的判準文字與「1 producer ＋ 3 consumer」的具名描述。驗證目標：紅燈。
- [x] 1.3 同檔加**圍籬測試**：用 `git worktree add` 建**真的**第二個工作樹（不是只換字串的假 fixture——實際遇到的情形正是同 repo 跨 worktree），斷言指向該工作樹的路徑被拒絕、且訊息含「給定路徑」與「當前 toplevel」兩者。驗證目標：紅燈。（Requirement: A checklist file outside the current work tree SHALL be refused as a task source）

## 2. 規範敘述（producer 端）

- [x] 2.1 `idd-update/SKILL.md` 新增 `--tasks-file <path>` 的參數說明與 Step 4 模板的 `### Tasks` 小節：內容為來源檔的 checkbox 行，保留 `[ ]` / `[x]` / `[~]` / `[-]` 標記與原文。驗證目標：1.1 的 drift-lock 部分轉綠。
- [x] 2.2 同檔寫入圍籬規範：路徑解析為絕對路徑後必須以 `git -C "$CWD" rev-parse --show-toplevel` 為前綴，否則**拒絕**、印出兩個路徑、不 emit、**不中止** `idd-update` 其餘工作。附上「為何是必要而非防禦性過度」的理由（實測跨 worktree ＋ 假陽性比假陰性嚴重）。驗證目標：1.3 轉綠。
- [x] 2.3 同檔寫明三種不 emit 的情形：flag 缺席、檔案不存在（警告不中止）、檔案零個 checkbox 行。並說明「不 emit」而非「emit 空節」的理由（不製造需要解釋的雜訊）。驗證目標：內容審查。
- [x] 2.4 `idd-all/SKILL.md` 的 Spectra 分支在收尾呼叫 `idd-update` 時附上 `--tasks-file`，路徑取自對外部工具 CLI 的**查詢**結果而非由 change name 組出；查詢失敗或工具未安裝時不附 flag、不 abort。驗證目標：內容審查——該檔不得出現外部工具的目錄名字面值。（Requirement: The layout of an external checklist source SHALL NOT be hardcoded）

## 3. 契約文件（consumer 端一致化）

- [x] 3.1 `rules/append-vs-modify.md` 的 resolution 段落定義 `exists` ＝ heading 在**且**至少一個可解析項目，並註明此定義三個 consumer 一致適用、consumer 不得自訂 emptiness 規則。驗證目標：1.1、1.2 全綠。
- [x] 3.2 同檔把「4 個 gate site」改為具名的「1 producer（`idd-implement` Step 5a）＋ 3 consumer（`idd-close` Step 0 / `idd-verify` checklist scan / `idd-update` body sync）」，並指名第二層的 producer 是 `idd-update` 的 `--tasks-file`。驗證目標：1.2 轉綠。
- [x] 3.3 同檔新增不變式：**優先序的每一層都必須指名 producer**；沒有 producer 的層無法 resolve，會讓優先序靜默塌縮。註明本不變式無法被測試強制（它約束的是未來新增的層），靠 review 維持。驗證目標：內容審查。
- [x] 3.4 `idd-close/SKILL.md` Step 0 的 `exists` 敘述與新的 canonical 定義對齊（它原本只對第一層寫 `len(items) > 0`）。驗證目標：內容審查 ＋ 以 diff 確認其 gate 行為敘述未被放寬。

## 4. 收尾驗證

- [x] 4.1 確認第一層行為**逐字未變**：以 `git diff` 確認 `idd-implement/SKILL.md` 的 Step 5a 敘述未被修改，且 `rules/append-vs-modify.md` 中第一層的優先權描述未動。驗證目標：兩處 diff 為空或僅含角色措辭更動。
- [x] 4.2 確認**未硬編外部佈局**：`grep -rn 'openspec/changes' plugins/issue-driven-dev/skills/ plugins/issue-driven-dev/rules/` 在本次新增的敘述中零命中（既有無關引用不計）。驗證目標：命中清單經人工確認皆非本次新增。
- [x] 4.3 跑既有測試 runner，全數通過；記錄變更前後的測試數量。驗證目標：runner 全綠，新測試出現在清單中。
