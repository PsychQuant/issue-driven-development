## Why

`authoritative_source` 的三層優先序被三個 gate consumer 讀，但**第二層沒有任何 producer**：

```
authoritative_source = first_exists([
  "## Implementation Complete > ### Checklist",   ← producer: idd-implement Step 5a
  "## Current Status > ### Tasks",                ← producer: 無
  "## Todo" | "## Tasks" | "## Checklist"         ← producer: 無（僅人手寫）
])
```

`idd-update` 的 Current Status 模板只 emit Key Decisions / Scope Changes / Blocking / Commits。全 repo 搜 `### Tasks` 只剩讀取端那一行——**這個來源被三個 gate 讀，卻沒有任何 skill 寫它**。

於是 chain 實務上退化成「只有第一層」，而它只有 `idd-implement` 產生。**任何繞過 `idd-implement` 的路徑都沒有 authoritative source** → fallback 掃 Strategy → 撞上那些「沒有任何一步會勾」的 pre-implementation checkbox。

`idd-implement` Step 5a 自己就把這個情形寫成已知行為（「Strategy/Plan checkbox 會被視為未完成可能 refuse close」），只是框成 backward compat 而非缺口。

下游實證：一個走完 19/19 tasks、跨模型驗證 0 blocking、PR 已開的 issue，被 diagnosis 當初寫的 7 個 `- [ ]` 擋在 close 門外，唯一解法是人工 PATCH diagnosis comment。**一個每次都得繞過的 gate，會養成它想防止的那種肌肉記憶。**

第二個缺口：`first_exists` 的 **`exists` 判準未定義**。canonical rule 零次提及 non-empty；三個 consumer 只有 `idd-close` 寫出 `len(items) > 0`，且只對第一層。

## What Changes

**補上第二層的 producer，並釘死 `exists` 判準。**

1. `idd-update` 接受 `--tasks-file <path>`，據以 emit `## Current Status > ### Tasks`。缺席時不 emit（行為退回現行 fallback）。
2. 路徑**由呼叫端查詢取得**，不由任何一方硬編佈局。`idd-all` 的 Spectra 分支向 spectra CLI 查 `contextFiles.tasks`。
3. **強制圍籬**：`--tasks-file` 必須落在當前工作目錄的 git toplevel 之內，否則拒絕並印出兩個路徑。
4. canonical rule 與 spec 定義 `exists` ＝ heading 在**且**至少一個可解析項目。
5. canonical rule 的「4 個 gate site」改為「1 producer ＋ 3 consumer」。

### 為什麼圍籬是必要而非防禦性過度

實測：在某個工作目錄執行 spectra 查詢，回傳的路徑指向**同一 repo 的另一個 git worktree**（registry 不是 cwd-scoped）。若原樣採用，gate 會讀另一個工作樹的完成狀態。

方向是最壞的那種：另一工作樹的清單若全部完成，**一個沒做完的 issue 會通過 close gate**。修一個假陰性卻引入假陽性，後者嚴重得多。

## Non-Goals

- **不覆蓋所有繞過 `idd-implement` 的路徑。** 本變更修的是「有 checklist 檔案可指」的路徑。**未覆蓋**：standalone spectra apply（無 orchestrator 傳 flag）、外部 agent 委派（工作在別處，無檔案）、手動 direct-commit 修復（根本沒有 checklist）。要全覆蓋需外部工具主動告知，屬 protocol 耦合，成本高於收益。
- **不改用「merged PR ＋ CI 綠」當 authoritative source。** 那是**整合狀態**不是**工作完成度**——merge 了但只做一半的 PR 會讓 issue 通過。且 close 流程已另有 PR gate，兩者互補非替代。採納它等於拆掉「沒打勾就不關」。
- **不讓外部工具產生 IDD 格式的 comment。** 那是 protocol 耦合；本變更只讀一個含 checkbox 的 markdown 檔。
- **不改第一層的既有行為。** `idd-implement` 產生的 checklist 仍是最高優先，逐 byte 不變。
- **不新增 CI**（repo 目前無 CI；測試靠 runner 手動執行）。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `append-vs-modify-discipline`: gate logic 的 authoritative-source resolution —— 定義 `exists` 判準、修正 producer/consumer 的角色描述、指名第二層的 producer

## Impact

- Affected specs: `append-vs-modify-discipline`（modified）
- Affected code:
  - New:
    - `plugins/issue-driven-dev/scripts/tests/authoritative-source-producer/test.sh`
  - Modified:
    - `plugins/issue-driven-dev/rules/append-vs-modify.md`
    - `plugins/issue-driven-dev/skills/idd-update/SKILL.md`
    - `plugins/issue-driven-dev/skills/idd-all/SKILL.md`
    - `plugins/issue-driven-dev/skills/idd-close/SKILL.md`
  - Removed: (none)
