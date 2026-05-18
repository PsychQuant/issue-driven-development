## Context

`/idd-all-chain` (v2.55.0+, archived from `add-idd-all-chain-skill` change) 目前是 single-root chain orchestrator:接受 1 個 root issue,recursive 呼叫 `/idd-all #M --in-chain` 處理 root + auto-emergent spawn,共開 1 個 cluster branch + 1 個 review PR。Hard caps `chain_max_depth=2` 與 `chain_max_issues=5` 寫死。Spawn manifest schema v1 在 `.claude/.idd/state/chain-spawned-issues.json`,4 個 sub-skill(`idd-implement`/`idd-verify`/`idd-plan`/`idd-diagnose`)透過 `scripts/manifest-append.sh` helper 寫入 spawn entry。

**問題**:當 user 同時有 N 個獨立 root issue 要共開一個 review PR(transcript 分流出 3 個 root concern、cross-cutting refactor 撞到 multi-root 場景),只能跑 N 次獨立 chain → N 個 PR,reviewer 失去 holistic view。manifest schema 的 `root_issue: int`(singular)無法描述 multi-root 場景下「某個 spawn 屬於哪個 root subtree」,因此需要 schema 升級。同步地,既有 cap 對 multi-root 過緊(3 roots × 1.5 spawn avg ≈ 7.5 issues 已超過 max=5),需 cap redesign 配套放寬。

**Stakeholders**:`/idd-all-chain` 直接 caller(個人 dogfood + IDD 維護者),`/idd-all` chain context 的 4 個 sub-skill(間接 — manifest schema 是它們的 write contract)。

**Constraints**:
- IDD discipline:**不**自動 close、**不**自動 merge,Phase 4 停在 verified 等 user
- Single-root invocation(N=1)行為**byte-equivalent**,backward compat 不可破
- Schema v1→v2 是 BREAKING,但因 manifest 是 per-chain-session transient state(每次 `idd-all-chain` Phase 0 重建,無 cross-session client),hard-break 安全

## Goals / Non-Goals

**Goals:**

- Accept N≥1 root issues via `/idd-all-chain #A #B #C`;N=1 行為與 v2.55.0+ 完全相同
- 兩種 traversal strategy:default DFS(rich subtree first),opt-in `--bfs`(fairness across roots)
- Cap redesign 配套 multi-root:`max_depth=3` 為主 cap,`max_issues=10` 為 safety net
- 失敗隔離:per-root verify FAIL halt,其他 root subtree 繼續(不是 global halt)
- 跨 sub-skill consistency:helper + 4 sub-skill 的 manifest write 同 PR ship,schema v1 vs v2 mismatch fail-fast
- Audit truth:spawn entry 顯式記錄 `root_id`,後續分析能追每個 spawn 屬於哪 root subtree

**Non-Goals:**

- Dual-accept schema(v1+v2 同時支援)— 沒有 v1 client in the wild,額外 conditional logic 無收益
- N>1 仍開 N 個 cluster branch / N 個 PR(那是 `/idd-all #N #M --pr` cluster-PR mode 的 use case,本 change 統一在 1 PR 內)
- Cluster-PR mode 的整合(`idd-implement #N #M --pr` 已存在,multi-root chain 與其互補但**不重疊**)
- Auto-close / auto-merge(維持 IDD discipline,user 永遠是 close/merge 的最終 gate)
- `references/chain-flow.md` 之外的 reference doc 新增(現有 doc 補章節即可,不另開檔)

## Decisions

### D1: Schema v2 hard-break,不 dual-accept

**Decision**: `EXPECTED_SCHEMA_VERSION` 在 `scripts/manifest-append.sh` 與 `idd-all-chain/SKILL.md` 同 PR 從 1 升到 2。manifest top-level `root_issue: int` 改為 `root_issues: [int]`,加 `traversal: "dfs" | "bfs"` 欄位;每 spawn entry 加 `root_id: int`(必填,值必為 `root_issues` 內某一元素)。

**Rationale**: Manifest 是 per-chain-session transient state(Phase 0 寫入、chain 結束就不再讀);沒有 cross-session 持久化 client。Dual-accept(v1+v2 同時支援)會在 helper write path 與 4 sub-skill read path 加 ~80 行 conditional logic,對應零個真實 backward-compat 需求。Hard-break + 同 PR atomic upgrade 是 net simpler。

**Alternatives considered**:
- Dual-accept v1+v2 — rejected:no v1 clients in the wild
- 只升 manifest schema 不升 helper — rejected:`scripts/manifest-append.sh:20` 的 `EXPECTED_SCHEMA_VERSION=1` check 會 fail-fast 拒寫,sub-skill 全部 abort

### D2: DFS = push-front 真的改 queue 順序,不是只標 label

**Decision**: 當前 Phase 2 是 `QUEUE=("${QUEUE[@]:1}")` 配 `QUEUE+=("$SPAWN_NUM")` = FIFO = BFS。新 implementation:default DFS mode 把 spawn push 到 queue 前端(`QUEUE=("$SPAWN_NUM" "${QUEUE[@]}")`),BFS mode 保留 push-back。Traversal mode 由 `/idd-all-chain` 接受 `--bfs` flag 決定;default DFS。

**Rationale**: 把 default 標為「DFS」卻用 BFS queue 是 mislabelled spec — 任何 user 看到「rich subtree first」描述,實際看到「level-by-level across roots」行為時會 surprised。Single-root 場景 DFS/BFS 在 traversal order 相等(無分支),所以 backward compat 不破。

**Alternatives considered**:
- Default BFS — rejected:diagnosis 給的「rich subtree first」是 DFS 語意,user clarification 明示 DFS 為 default
- Per-root 自己選 traversal — rejected:整 chain 共一個 traversal mode 才有單一可預測語意

### D3: Cap = max-depth=3 primary + max-issues=10 safety net,獨立 apply

**Decision**: 兩個 cap 同時存在,擇先觸發。`CHAIN_MAX_DEPTH=3` 對每 root subtree 獨立(每 root depth=0);`CHAIN_MAX_ISSUES=10` 是整個 chain(所有 root 合計)的 total budget。Phase 2 main loop check 兩者皆通過才 enqueue。

**Rationale**: max_issues=5 對 multi-root 過緊(3 roots × 平均 1.5 spawn ≈ 7.5 issues > 5);全砍掉 max_issues 失去 unbounded-explosion 的 safety floor;max_depth=3 為主 cap 給 user 直觀控制(我願意看到 depth 多深的 ripple),max_issues=10 為 safety net 防止 max_depth 允許範圍內 fan-out 太大(假設 max_depth=3 + branching=4 → 1+4+16+64=85 issues 是病態)。

**Alternatives considered**:
- 只保留 max_depth(去掉 max_issues)— rejected:depth=3 + 高 fan-out 仍可爆炸
- max_depth=2 max_issues=10 — rejected:depth=2 太緊,multi-root 場景下 root spawns 的 spawns 是常態,depth=2 限制是 single-root v2.55.0 default,multi-root 應該放寬到 3

### D4: Verify FAIL = per-root continue (Q4 Option C)

**Decision**: Phase 2 main loop 偵測 verify FAIL 時,將該 issue 屬於的 root_id 加入 `FAIL_ROOTS[]` set,把該 root 的 subtree 標 FAIL 並停(從 QUEUE 移除所有 `root_id == failed_root` 的 issue);其他 root 的 subtree 繼續處理。所有 commits preserved。Phase 4 final report 印 per-root PASS/FAIL 表。

**Rationale**: Option A(global halt)是 single-root 時代的保守 default,multi-root 場景下 root #1 失敗就放棄 root #2/#3 抹掉 multi-root 的收益。Option C 是「失敗隔離 per root」semantics,類似 BFS-tree 中砍 subtree 不砍 forest。Commits preserved 因為 cluster PR 必須由 user review,user 可選擇 partial revert / partial merge。

**Alternatives considered**:
- Option A global halt — rejected:抹掉 multi-root 收益
- Option B halt 該 subtree 但允許在另一 root subtree spawn 出同檔的修復 — rejected:語意太複雜,implementer 容易誤判 spawn ownership

### D5: Branch naming hash8 for N>1,N=1 保留現行

**Decision**: 
- N=1: `idd/chain-<N>-<slug>`(現行,不動)
- N>1: `idd/chain-multi-<hash8>-<root1-slug>`,其中 `hash8 = sha256sum("$ROOT_ISSUES_JOINED") | cut -c1-8`(`ROOT_ISSUES_JOINED` 是 sorted asc 的 root numbers 用 `-` join),`root1-slug` 是最小 root 號碼的 title slug(deterministic)
- Collision 偵測:若 `gh api repos/.../branches/$BRANCH` 回 200(branch 已存在),fallback 用 `hash16`(`cut -c1-16`)。雙重 collision(極罕見)則 Phase 0 abort 並印手動清理 hint

**Rationale**: 列出所有 N 個 root number(`idd/chain-44-45-46-50-55-...-<slug>`)在 N≥5 時 branch name 失控且難辨識;hash 是固定長度且 deterministic(同 root set 永遠對應同 hash)。`root1-slug` 提供「這 chain 大致關於什麼」的人類可讀提示。

**Alternatives considered**:
- List all root numbers — rejected:N=5+ 長度失控
- 純 hash(無 slug)— rejected:branch name 失去人類可讀性
- timestamp suffix — rejected:無 determinism,同一組 root 第二次跑會得到不同 branch name,違反 idempotency

### D6: PR title format(Q6 deferred from discuss)

**Decision**: 
- N=1: `chain: <root title>`(現行,不動)
- N>1: `chain (multi-root): N issues — <root#1 title>`,其中 `<root#1 title>` 是最小 root 號碼的 issue title

**Rationale**: Title 第一段給 GitHub reviewer 立刻看到「這是 chain 模式 + 是 multi-root」;`N issues` 給規模感;`<root#1 title>` 給語意 anchor(reviewer 點開 PR 前能猜大致主題)。

### D7: Phase 4 TaskList visualization(Q7 deferred from discuss)

**Decision**: Phase 4 final report 印 forest tree printout,每個 root 為一棵樹的根。格式:

```
Forest summary (traversal: DFS):

  ✓ root #44 (depth 0)
    └─ ✓ #34 (depth 1, spawned by idd-implement Step 5.7 sister-bug)
        └─ ✓ #41 (depth 2, spawned by idd-verify Phase 4 follow-up-finding)
  ✗ root #45 (depth 0) — FAIL at #48
    └─ ✗ #48 (depth 1, spawned by idd-plan Step 2.5 tangential)
  ⊘ root #50 (depth 0) — filed but unprocessed (max-issues=10 reached)

Per-root PASS/FAIL:
  #44: PASS (2 spawn processed)
  #45: FAIL (verify FAIL at #48 — subtree halted)
  #50: SKIPPED (max-issues cap)
```

**Rationale**: Single-line aggregate(現行 `Processed: #28 #34 #41`)在 multi-root 時無法回答「每 root 走多深」「FAIL 出在哪」「哪 root 被 cap 切掉」三個常見 review question。Tree printout 一眼可見 fan-out 形狀。

## Implementation Contract

**Observable behavior after this change ships**:

1. `/idd-all-chain #44`(N=1,backward compat)— 行為與 v2.55.0+ **byte-equivalent**:cluster branch `idd/chain-44-<slug>`、manifest schema v2 但只有 1 個 `root_issues` 元素、PR title `chain: <title>`、Phase 4 single-tree printout。
2. `/idd-all-chain #44 #45 #50`(N=3 multi-root,default DFS)— 在 lowest root issue 上記錄 chain comment、cluster branch `idd/chain-multi-<hash8>-<root-44-slug>`、manifest 含 `root_issues: [44,45,50]` 與 `traversal: "dfs"`、每個 spawn entry 帶 `root_id: <which root>`、DFS 依序處理 root #44 整 subtree → root #45 → root #50、PR title `chain (multi-root): 3 issues — <root #44 title>`、Phase 4 forest tree printout。
3. `/idd-all-chain #44 #45 #50 --bfs` — manifest `traversal: "bfs"`,Phase 2 改 push-back semantics,level-by-level 處理。
4. Verify FAIL 在 root #45 的 subtree(任一 issue)— `FAIL_ROOTS[]` 加 45、QUEUE 移除所有 `root_id=45` 的 pending issue、其他 root subtree 繼續、Phase 4 report 印 per-root PASS/FAIL/SKIPPED。
5. Hit `max_depth=3` 或 `max_issues=10` cap — 該 spawn filed only(不入 QUEUE)、Phase 4 標 `(depth/issues cap reached)`、chain 不 abort。
6. v1 manifest 在 disk 上(沒新到 v2 的環境)— helper 與 chain skill 都 `schema_version` mismatch fail-fast,印 migration hint。

**Interface / data shape**:

- CLI:`/idd-all-chain #N [#M ...] [--bfs] [--cwd <path>]` — 接受多個 `#NNN` token(positional)、optional `--bfs` flag(presence = BFS mode,absence = DFS mode)、optional `--cwd <abs path>`(現有 cross-repo flag,行為不變)
- Manifest schema v2(JSON):
  ```json
  {
    "schema_version": 2,
    "session_id": "<uuid v4>",
    "root_issues": [<int>, ...],
    "traversal": "dfs" | "bfs",
    "spawned": [
      {
        "issue_number": <int>,
        "spawned_by": "<sub-skill>",
        "spawn_step": "<str>",
        "spawn_kind": "<enum>",
        "same_file_as_root": <bool>,
        "same_skill_as_root": <bool>,
        "root_id": <int>,
        "filed_at": "<ISO-8601>",
        "title": "<str>"
      }
    ]
  }
  ```
- Helper:`manifest-append.sh <repo-root> <issue> <spawned-by> <spawn-step> <spawn-kind> <same-file> <same-skill> <title> <root-id>` — 第 9 個位置參數 `root-id` 必填(整數 > 0)
- Branch:N=1 `idd/chain-<N>-<slug>`;N>1 `idd/chain-multi-<hash8>-<root1-slug>`(collision → hash16)
- PR title:N=1 `chain: <title>`;N>1 `chain (multi-root): N issues — <root#1 title>`

**Failure modes**:

- 0 root token → Phase 0 abort `Usage: /idd-all-chain #NNN [#MMM ...] [--bfs] [--cwd <path>]`
- 任一 root state ≠ OPEN → Phase 0 abort,列出非 OPEN 的 root number 與 state
- 任一 root 缺 diagnosis comment → Phase 0.4 3-option AskUserQuestion 套到第一個缺 diagnosis 的 root(現有單 root 邏輯擴展)
- Manifest schema_version 不是 2 → helper exit 1,印 expected vs actual + migration hint
- Branch collision(hash8 與 hash16 都已存在)→ Phase 0.5 abort 並印手動清理 hint
- Sub-skill manifest-append 缺第 9 個位置參數(root_id)→ helper exit 2(usage error)
- Verify FAIL 在某 root subtree → 該 root 標 FAIL、QUEUE 清該 root_id pending、Phase 4 per-root report 印 FAIL + 失敗 issue 號碼

**Acceptance criteria**:

- Smoke test 1:`/idd-all-chain #X`(N=1,X 是現實 issue)→ branch name = `idd/chain-X-<slug>`,manifest `root_issues=[X]` + `traversal="dfs"` + 0 spawn 入 chain(假設無 spawn)→ 行為與 v2.55.0+ 觀察一致(diff Phase 4 report 應有 forest tree 但只有 1 棵)
- Smoke test 2:`/idd-all-chain #A #B #C`(N=3,A<B<C,設 sub-skill 不 spawn 任何 issue)→ branch = `idd/chain-multi-<hash8>-<A-slug>`,manifest `root_issues=[A,B,C]`,Phase 2 依序 process A → B → C,Phase 4 forest 3 棵單獨節點
- Smoke test 3:`/idd-all-chain #A #B #C --bfs`(同上 N=3 but BFS)→ manifest `traversal="bfs"`,Phase 2 順序仍 A → B → C(無 spawn 時 BFS/DFS 等效),測試在於 manifest 有正確 traversal 標記
- Smoke test 4:`/idd-all-chain #A #B`(N=2)且 root A 在 idd-implement 階段 spawn 出 #X → DFS mode 應 process 順序為 `A → X → B`(spawn pushed to front),BFS 應為 `A → B → X`
- Smoke test 5:verify FAIL 在 root A 的 spawn #X → FAIL_ROOTS=[A]、QUEUE 清空 root_id=A,繼續 process root B 整 subtree、Phase 4 report A=FAIL B=PASS
- Smoke test 6:depth 4 spawn 被 enqueue → 該 spawn 被 helper 寫入 manifest(audit 仍 file)但 chain 不 process(`⊘ #X depth>max — filed only, not chained`)
- Smoke test 7:total issues 達到 11 個 → 第 11 個 spawn 被 helper 寫入 manifest 但 chain 不 process,印 `⚠ chain_max_issues=10 reached`
- Helper unit test:`manifest-append.sh ... <8 args>` exit code = 2(usage);`... <9 args>` exit code = 0 並寫入含 `root_id`
- Spec analyzer:`spectra analyze multi-root-traversal-idd-all-chain` 0 Critical / 0 Warning
- 4 sub-skill conformance:grep `manifest-append.sh` in `idd-implement/SKILL.md` `idd-verify/SKILL.md` `idd-plan/SKILL.md` `idd-diagnose/SKILL.md` — 每處應傳 9 個位置參數(含 root_id 計算)

**Scope boundaries (in scope / out of scope)**:

In scope:
- `idd-all-chain/SKILL.md` Phase 0/1/2/3/4 logic for multi-root + traversal + new caps + per-root halt + new branch/PR naming + forest report
- `manifest-append.sh` schema_version bump + 第 9 位置參數
- `references/spawn-manifest.md` v2 spec text + example
- `references/chain-flow.md` DFS/BFS algorithm + halt scope + cap interaction
- 4 sub-skill 的 manifest-append.sh 呼叫加 root_id 引數(每處只是 1-line 改動,語意:從 manifest 自己讀 spawn parent 的 root_id)
- 兩個 spec delta:`idd-all-chain`(MODIFIED 5 Requirements)、`idd-spawn-manifest`(MODIFIED schema + new EXPECTED_SCHEMA_VERSION)

Out of scope:
- `/idd-all-chain` 的 dual-mode merge(N=1 用 single-root 路徑,N>1 用 multi-root 路徑)— 統一 multi-root code path,N=1 是退化情況
- Auto-restart on cluster-PR conflict — chain 失敗仍依現有 recovery 流程(commits preserved + user 手動接手)
- Per-root branch + cherry-pick to cluster — 維持 single cluster branch,所有 commit 直接 land
- Cross-chain session persistence — manifest 仍是 per-session transient
- `idd-route` integration 變更 — routing-stats 寫入維持單 root summary(post-Phase 4 報表)

## Risks / Trade-offs

- **[Risk] Schema migration mismatch across env(helper 升級 vs sub-skill 在不同 PR ship)**→ Mitigation: 強制同 PR ship + 同 commit;helper 的 `schema_version` check 是 fail-fast 兜底,mismatched env 直接 abort 而非 silent corruption
- **[Risk] DFS budget exhaustion fairness(第 1 root subtree 用完 10 budget,root #2/#3 完全沒跑)**→ Mitigation: Phase 2 entry log 印 `DFS strategy: root #X subtree explored first` 提醒;user 若需 fairness 可用 `--bfs`;Phase 4 report 顯示 `⊘ root #Y not processed (max-issues cap)` 透明 surface
- **[Risk] Branch hash8 collision**→ Mitigation: hash8 衝突 fallback hash16(碰撞機率 2^32 vs 2^64);雙重碰撞(極罕見)Phase 0 明示 abort + 手動清理 hint
- **[Risk] PR body 過長(N=5 roots × 平均 2 spawn × subtree details)撞 GitHub 256KB body limit**→ Mitigation: 維持現行 collapsed `<details>` per issue;若仍超限,Phase 3 印 warning 並引導 user 看 individual issue
- **[Risk] DFS vs BFS default 爭議**→ Mitigation: design.md 明示 trade-off,DFS = rich subtree first(reviewer cognitive load 低,一個 root 一個 root 看完),BFS = fairness(每 root 都至少跑到);default DFS 是因為 chain 的典型用途是 root-centric review,fairness 用 opt-in 即可
- **[Trade-off] Hard-break schema vs dual-accept**:選 hard-break 簡化 helper + 4 sub-skill 的 code,代價是若 user 在 env 升級時跑到一半的 chain 會 abort(可接受 — chain session 是 transient,重跑沒成本)
- **[Trade-off] Single cluster PR(N>1)vs N 個 PR**:選 single cluster PR 給 reviewer holistic view,代價是 user 無法只 merge 部分 root subtree(需 partial revert)— 接受,因 IDD discipline 本來就要求 user 是最終 review 與 merge gate
