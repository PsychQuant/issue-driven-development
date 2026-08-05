## Context

`authoritative_source` 是 gate logic 的核心解析：決定「哪一份 checklist 才算數」。它由 `rules/append-vs-modify.md` 定義，被三個 skill 消費（`idd-close` Step 0 硬 gate、`idd-verify` checklist scan、`idd-update` phase 推斷 fallback），由一個 skill 生產（`idd-implement` Step 5a 寫回 `## Implementation Complete > ### Checklist`）。

三層優先序中，**第二層（`## Current Status > ### Tasks`）沒有任何 producer**——`idd-update` 的 Current Status 模板不含該小節。第三層只有人手寫。

約束條件：

- **repo 無 CI**；測試靠 `plugins/issue-driven-dev/scripts/tests/<name>/test.sh` ＋ runner 手動執行。既有 pattern 是「fixture 驗機制 ＋ drift-lock 斷言 SKILL.md 含必要文字」。
- 這些 skill 是 **markdown prose**，「實作」＝改 SKILL.md 的規範敘述；正確性靠 fixture 測試與 drift-lock 守住。
- 產生 checklist 的外部工具（Spectra）是**獨立 plugin**，本 repo 不得依賴其內部佈局。

## Goals / Non-Goals

**Goals:**

- 讓第二層有 producer，使「有 checklist 檔案可指」的路徑不再 fallback 掃 pre-implementation snapshot。
- 定義 `exists` 判準，使三個 consumer 一致。
- 修正 producer/consumer 的角色描述。
- 不因此引入「不該過卻過」的假陽性。

**Non-Goals:**

- 覆蓋所有繞過 `idd-implement` 的路徑（見 proposal 的 Non-Goals）。
- 改變第一層的既有行為。
- 讓外部工具產生 IDD 格式的 comment。
- 新增 CI。

## Decisions

### 決策 1：`exists` ＝ heading 在**且**至少一個可解析項目

canonical rule 目前只寫 `first_exists([...])`，未定義何謂 exists。三個 consumer 中只有 `idd-close` Step 0 寫出這個條件（其 edge-case 表明列「存在但 0 items → 視同不存在 → legacy fallback」），另兩個無條件。

採用 `idd-close` 的定義並寫進 canonical rule。**這是文件追上程式碼，不是新決定**——它是唯一的既有實作，且另兩個 consumer 不執行硬 gate，統一後零 backward-compat 破壞。

副效果：空的 section 不會 resolve，自然退回現行行為。這讓決策 4 的「不 emit vs emit 空節」在 gate 層等價。

### 決策 2：producer 是 `--tasks-file <path>`，不是 change name

原本三個候選都預設「IDD 要**找到**外部工具的目錄」：

| 候選 | 為什麼不採 |
|---|---|
| 取「唯一 active change」 | 實測本 repo 當下有 6 個 active change，第一天就會挑錯 |
| 掃 proposal 找 issue 編號 | 依賴人有寫 ref，格式無保證 |
| 收 change name | 較穩，但 IDD 仍須知道 `<外部工具目錄>/<name>/tasks.md` 的佈局 |

改為**收路徑**：IDD 只是「讀一個含 checkbox 的 markdown 檔」。樹內不出現外部工具的目錄名，對方改佈局不會靜默失效。並重用既有的 checkbox regex（`idd-close` Step 0 已有），不新增解析器。

### 決策 3：路徑由呼叫端**查詢**取得，不由任何一方組出

決策 2 只是把「誰知道佈局」的問題往上推。若 `idd-all` 用 change name 組出路徑，佈局知識只是換個位置。

**第三條路**：向外部工具的 CLI 查。實測 `spectra instructions apply --change <name> --json` 回傳 `contextFiles.tasks` 的絕對路徑。於是**沒有任何一方硬編佈局**——orchestrator 問、對方答、IDD 讀。

**誠實修正**：先前把決策 2 描述為「IDD 對外部工具零知識」，那是自欺——`idd-all` 仍須知道要問誰、問什麼。正確說法是**沒有任何一方硬編佈局**，且佈局知識集中在已經與該工具耦合的 orchestrator（`idd-all` 的 Spectra 分支本來就按名字呼叫那三個 skill），而**不擴散到通用的 `idd-update`**。

### 決策 4：flag 缺席時不 emit `### Tasks`

在決策 1 的定義下，「不 emit」與「emit 空節」在 gate 層等價（兩者都不 resolve）。選前者的理由**不是可讀性偏好**：一個空的 `### Tasks` heading 出現在 issue 上，讀的人會問「這是壞了還是本來就沒有」——那是需要解釋的雜訊。不製造它。

### 決策 5（本次新增）：路徑必須落在當前 git toplevel 內，否則拒絕

**這條是實測逼出來的，不是防禦性過度。**

在某個工作目錄執行 spectra 查詢，回傳的 `contextFiles.tasks` 指向**同一 repo 的另一個 git worktree**——該工具的 change registry 不是 cwd-scoped。

若原樣採用，gate 會讀另一個工作樹的 tasks.md：

```
cwd:  <repo>/                      ← 正在 close 的分支
path: <repo>-other-worktree/openspec/changes/X/tasks.md   ← 完全不相干的完成狀態
```

方向是最壞的：另一工作樹的清單若全部完成，**一個沒做完的 issue 會通過 close gate**。

修一個假陰性（該過不過）卻引入假陽性（不該過卻過）——**後者嚴重得多**，因為前者會被人擋下（人被擋住會抱怨），後者不會（沒人會發現 gate 放行了不該放的）。

**判準**：`--tasks-file` 解析為絕對路徑後，必須以 `git -C "$CWD" rev-parse --show-toplevel` 的結果為前綴。worktree 共用 `.git` 但 toplevel 不同，故此檢查抓得到。**拒絕時必須印出兩個路徑**——否則使用者看到「拒絕」卻不知道為什麼。

## Implementation Contract

### Behavior

- `idd-update` 收到合法的 `--tasks-file <path>` 時，在 `## Current Status` 內 emit `### Tasks` 小節，內容為該檔案的 checkbox 行。
- 未收到該 flag 時，**不** emit `### Tasks`，其餘行為逐字不變。
- 收到落在當前 git toplevel 之外的路徑時，**拒絕**並印出「給定路徑」與「當前 toplevel」兩者；不 emit `### Tasks`；不中止 `idd-update` 的其餘工作。
- 三個 consumer 判定某來源是否 resolve 時，一致採「heading 存在**且**至少一個可解析的 checkbox 項目」。
- 第一層（`## Implementation Complete > ### Checklist`）的解析與優先權**逐字不變**。

### Interface / data shape

- `idd-update` 新增選填 flag `--tasks-file <path>`。可為相對或絕對路徑；相對路徑相對於當前工作目錄解析。
- emit 的小節位於 `## Current Status` 之下，heading 為 `### Tasks`，其下逐行複製來源檔的 checkbox 行（保留 `[ ]` / `[x]` / `[~]` / `[-]` 標記與原文）。
- `idd-all` 的 Spectra 分支在收尾呼叫 `idd-update` 時附上該 flag；路徑取自對外部工具 CLI 的查詢結果，**不由 change name 組出**。
- canonical rule 的角色描述改為「1 producer ＋ 3 consumer」，並具名各自是誰。

### Failure modes

- 路徑不存在 → 警告並跳過 emit，不中止。
- 路徑在 toplevel 之外 → **拒絕** ＋ 印出兩個路徑，不 emit。
- 檔案存在但零個 checkbox 行 → 不 emit（等同無來源；避免產生一個不會 resolve 的空節）。
- 外部工具查詢失敗 / 未安裝 → `idd-all` 不附 flag，行為退回現行 fallback。**不 abort**。

### Acceptance criteria

- fixture 測試證明：heading ＋ 0 項 **不** resolve；heading ＋ ≥1 項 resolve。
- fixture 測試證明：toplevel 之外的路徑被拒絕，且錯誤訊息含兩個路徑。
- fixture 測試以**另一個 git worktree** 重現實際遇到的情形，證明圍籬攔得住。
- drift-lock：`idd-update/SKILL.md` 含 `--tasks-file`；`rules/append-vs-modify.md` 含 producer/consumer 的具名表與 `exists` 定義。
- 既有測試全數通過（runner 執行）。
- `idd-implement` 的 Step 5a 敘述**未被修改**（以 diff 確認）。

### Scope boundaries

**In scope**：`rules/append-vs-modify.md` 的 resolution 敘述、`idd-update` 的 flag 與 emit、`idd-all` Spectra 分支的 flag 傳遞、`idd-close` 的 `exists` 敘述對齊、新測試、spec delta。

**Out of scope**：其餘兩條未覆蓋路徑（外部 agent 委派、手動 direct-commit）、以 PR/CI 狀態取代 checklist、外部工具端的任何改動、CI 建置。

## Risks / Trade-offs

- **最大風險是圍籬沒做或做錯** → 引入假陽性（不該過卻過）。這比原本的假陰性嚴重，因為它不會被任何人發現。測試必須用真的第二個 worktree 重現，不能只用「路徑字串不同」的假 fixture。
- **markdown prose 的「實作」沒有編譯器**：正確性完全靠 fixture 測試與 drift-lock。drift-lock 只證明「字串在檔案裡」，不證明行為——與被修的那個缺口同型（那正是為什麼要有 fixture 測試）。
- **第二層一旦有 producer，第三層仍然沒有**。本變更不解決它；若日後有人依賴第三層，同樣的缺口會重演。契約層應加一條「每一層都必須指名 producer」的不變式，但那條無法被測試強制（它約束的是未來新增的層），只能寫進文件靠 review 維持。
- **repo 無 CI**：新測試要有人記得跑。這是既有狀況，本變更不改變它，但也因此不能宣稱「測試會擋住回歸」——只能說「測試存在且可跑」。
