## Context

`idd-issue` Step 0.5.E（fork-aware detection）是 target-resolution 的最後一層（config-protocol mechanism 5，`git remote fallback`）。現有兩條 branch：E1（non-fork → 直接用 origin、不問）、E2（fork → 3-option）。

「clone 別人的 repo」（reference / 教學 / 研究素材，無 push 權）是 non-fork，落進 E1 → 靜默把 issue 導向原作者公開 repo + 把 `.claude/.idd/` config 寫進對方 working tree。GitHub 公開 repo 任何登入者都能開 issue，所以這是個**真會誤污染**的路徑，而非理論問題。

本 change 補上第三條 branch，並把「IDD config 不污染對方 repo」的機制（`.git/info/exclude`）內建為偵測到 third-party 時的預設建議。

## Goals / Non-Goals

### Goals

- Step 0.5.E 偵測 third-party clone 並主動給 routing + config-placement 建議。
- third-party 預設用 `.git/info/exclude`（per-clone、不 commit/push、不動對方 tracked 檔）擋 IDD config。
- 抽共用 ignore-block writer primitive，消除 #55 與本 feature 的重複邏輯。

### Non-Goals

- 自動建 tracking repo（保持零 outward action）。
- 改 E1 / E2 既有行為。
- 把兩種 ignore 操作併成單一 function。

## Decisions

### D1: 偵測判準 = hybrid（owner-mismatch pre-filter → push-permission probe）

```
owner_self  = gh api user --jq .login
origin_owner = <parsed from origin>
if origin_owner == owner_self:        → 你自己的 repo（E1 路徑，零額外 API）
else:
    push = gh api repos/{o}/{r} --jq .permissions.push   # 僅在不符時才打這支
    if push == true:   → 你有 push 權（org repo / collaborator）→ E1-like，不算 third-party
    else:              → third-party clone → 新 branch
```

**為什麼 hybrid 不是單一判準**：

- 純 owner-mismatch → false positive：你有 push 權的 org repo（owner=org≠你）會被誤判 third-party。
- 純 push-permission → 每次 first-run（含你自己的 repo common case）都多一支 API call + 需 auth scope。
- hybrid：common case（自己的 repo）零額外 API；只有 owner 不符才付一次 probe 成本，且精準回答「我能不能寫」。

> Fork（E2）必須**先於** third-party 判斷 —— fork 也是 owner-mismatch + 常無 push 權，但 fork 有自己的 upstream 語意（contributor / customization / divergent）。順序：E2 fork → 新 third-party branch → E1。

### D2: 偵測到時 = 3-option AskUserQuestion（不自動選）

| 選項 | target | 寫入 |
|---|---|---|
| Upstream（原作者 repo） | origin | config `github_repo=origin`；**警示公開可見** |
| 自己的 tracking repo | 使用者給的 `--target you/repo` | config `github_repo=you/repo` |
| Local-only | — | 不開 GitHub issue（degrade 提示） |

routing 是使用者意圖，猜會錯一半 → 強制問（與 fork E2 同構）。tracking repo **只接受既有 repo**（`--target` / 手填），不 `gh repo create`。

### D3: Config-placement × ignore-mechanism 矩陣

| 情境 | config 放哪 | ignore 機制 |
|---|---|---|
| 自己的 repo | `.claude/.idd/local.json`，可 commit 或全域忽略 | 視團隊慣例 |
| **third-party clone** | `.claude/.idd/local.json`（local） | **`.git/info/exclude`** 擋 `.claude/.idd/`（per-clone、不 commit/push） |
| monorepo / 巢狀 | walk-up config 放非 git 上層 | 同上 |

third-party 預設一併寫 `pr_policy: never`（無 push 權 → local direct-commit，避免 `idd-implement` push 失敗）。**絕不**改對方 tracked `.gitignore`（那等於在對方 history 疊 commit = 污染）。

### D4: 共用 helper = 共同 primitive，不是單一 function（CRITICAL）

#55（Stage 4.5）與本 feature 是**方向相反**的 ignore 操作：

| | #55 carve-out | 本 feature exclude |
|---|---|---|
| 目標檔 | **tracked `.gitignore`** | **untracked `.git/info/exclude`** |
| 方向 | **re-include**（把被 ignore 的 jsonl 拉回可 commit） | **exclude**（把 IDD config 擋掉） |
| 是否進 git | 是（要 commit `.gitignore` 變更） | 否（`.git/` 內，永不 commit/push） |

→ 抽出的 primitive 是 `write_idempotent_ignore_block(target_file, marker, lines)`：

- marker-delimited block（重跑 idempotent，靠 marker comment 偵測 + state-machine 替換 stale block，沿用 #55 已驗證的 awk 邏輯）。
- 處理 git「parent-dir-excluded」quirk（單行 `!` 例外在父目錄被 exclude 時無效 → 需 carve-out 鏈；#55 已踩過並驗證 5-line 解法）。
- **方向**（re-include vs exclude）與**目標檔**（`.gitignore` vs `.git/info/exclude`）由 caller 以參數帶入；primitive 不假設任一方向。

**#55 regression 保證（amended — apply 時發現 byte-equivalence 不可行）**：byte-equivalence 證實**不可能** —— helper 用 BEGIN/END sentinel，舊 #55 block 是 single-marker + rationale-comments 格式；要 byte-equivalent 就得讓 generic helper 複製 #55 的特定格式，抹殺抽取意義。改採 **behavior-equivalence**：refactor 後 `git check-ignore` 結果與 refactor 前**完全一致**（run-log 變 trackable、sibling 仍 ignored、bare `.claude/` 移除、gate options/summary/`JSONL_GITIGNORE_DECISION` 不變），外加**一次性遷移**舊格式 block（偵測舊 marker → strip → helper 寫新 sentinel，不重複）。gate options 不變、user 內容保留。由 `scripts/tests/stage45-carveout-migration/test.sh`（13 assertions）驗證。

### D5: idd-config init / idd-all 對齊

- `/idd-config init` 偵測 third-party 時，呈現同 D2 的 3-option，並依 D3 寫 config + `.git/info/exclude`。
- `idd-all` Phase 0.5 mode resolution：偵測到 third-party（且 config 未顯式設 pr_policy）→ 套用 `pr_policy: never` 預設（位階同 fork → PR override，但方向相反）。

## Implementation Contract

### Observable Behavior

1. 在 third-party clone（owner 不符 + 無 push 權）首跑 `/idd-issue` → 出現 3-option AskUserQuestion；選 tracking repo → issue 開到該 repo，`.claude/.idd/` 進 `.git/info/exclude`，`git status` 乾淨。
2. 在自己的 repo / 有 push 權的 org repo 首跑 `/idd-issue` → 行為與今日 E1 完全相同（無新 prompt、無額外 API 在 owner 相符時）。
3. fork 首跑 → 行為與今日 E2 完全相同。
4. Stage 4.5 #55 carve-out → 輸出與 refactor 前位元等價。

### Acceptance Criteria

- [ ] third-party 偵測：owner-mismatch + push=false → 觸發新 branch；owner 相符 OR push=true → 不觸發。
- [ ] fork 優先於 third-party（fork repo 不被誤判為 third-party）。
- [ ] 3-option routing 寫對 config + `.git/info/exclude` + `pr_policy: never`。
- [ ] E1 / E2 backward compat：既有測試全綠。
- [ ] #55 carve-out refactor：位元等價（fixture 對拍）。
- [ ] `idd-config init` + `idd-all` Phase 0.5 對齊。

### Out of Scope

- tracking repo 自動建立。
- 「co-maintained / vendored read-only」灰色情境的精細分流。

## Risks / Trade-offs

| Risk | Mitigation |
|---|---|
| push-permission probe 多一支 API + 需 auth scope | hybrid pre-filter：只有 owner 不符才打；owner 相符（common case）零額外 API |
| 與 fork E2 double-prompt | 嚴格排序 E2 → third-party → E1；third-party 判斷在 `IS_FORK=false` 分支內 |
| #55 refactor 改壞既有行為 | 位元等價對拍 + 既有 fixtures；primitive 為純抽取 |
| `.git/info/exclude` re-clone 後消失 | 文件化此性質（per-clone 本質）；偵測在每次 first-run 都會重跑，re-clone 後重設 |
| git parent-dir-excluded quirk | 沿用 #55 已驗證 5-line carve-out 邏輯，不重新推導 |

## Migration Plan

### Deploy

純 additive：新 branch 在 `IS_FORK=false` 內插入 third-party 判斷；helper 抽取為 refactor。無 schema migration。Bump `idd-issue` / `idd-config` / `idd-all` plugin minor version。

### Rollback

移除 third-party branch → 回到 E1/E2 兩分支行為；helper 抽取可獨立 revert（#55 改回 inline）。已寫入使用者 repo 的 `.git/info/exclude` 規則無害（per-clone、不影響對方），rollback 不需清理。

### Backward Compat

- E1（你自己的新 repo）silent-write 不變。
- E2（fork）3-option 不變。
- 既有已寫好的 config（含本 session 在 kaochenlong repo 的手動 setup）被偵測為「config 已存在」→ 走 mechanism 4，不重跑偵測。

## Open Questions

### Q1: push-permission probe 的 auth scope 失敗如何處理？

若 `gh api repos/{o}/{r}` 因 scope / rate-limit 失敗 → fail-open（當作 third-party、給建議）還是 fail-closed（當作非 third-party、走 E1）？傾向 **fail-safe = 當 third-party 並提示**（寧可多問一次，不要靜默污染）。propose review 時定。

### Q2: 「co-maintained / vendored read-only」灰色地帶（residue）

push permission 是機械 proxy，但「不真正屬於你的 repo」意圖更廣 —— 你共同維護但非建立的 repo（有 push 權卻可能不想污染）、只讀 clone 的 vendored dependency。本 change 用 push permission 一刀切，灰色情境留給 future signal（如顯式 `--third-party` flag）。**標記為 residue，不靜默吞掉。**

### Q3: tracking repo 是否接 config-protocol `candidates` 機制？

「自己的 tracking repo」選項可否記住跨多個 third-party clone 共用一個預設 tracking repo（接既有 `candidates`）？本 change 先做單次 `--target`/config；candidates 整合列為 follow-up。
