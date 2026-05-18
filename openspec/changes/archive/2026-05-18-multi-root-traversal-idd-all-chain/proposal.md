## Why

`/idd-all-chain` 目前只接受**單一 root issue**,當 user 同時有多個獨立 root issue 要共開一個 review PR(例如 multi-source dogfood、cross-cutting refactor 撞到 3 個 root concern)時,只能跑 N 次獨立 chain → N 個 cluster branch → N 個 PR,reviewer 失去 holistic view。同時,既有的 `chain_max_depth=2 / chain_max_issues=5` hard cap 對 multi-root 場景太緊(3 roots × 平均 1.5 spawn 已 = 7.5 > 5),需 cap redesign 配套放寬。Spawn manifest schema v1 的 `root_issue: int` 在 multi-root 場景下無法區分某個 spawn 屬於哪個 root subtree,需 hard-break 到 v2。

## What Changes

- **Multi-root invocation**:`/idd-all-chain #44 #45 #50` 接受 ≥2 個 root issue(N=1 行為不變,backward compat)
- **Traversal mode**:default DFS(rich subtree first)+ opt-in `--bfs` flag(fairness — level-by-level across roots)
- **BREAKING**: spawn manifest schema v1 → v2 — `root_issue: int` 改 `root_issues: [int]`、top-level 加 `traversal: "dfs" | "bfs"`、每個 spawn entry 加 `root_id: int` 標明所屬 root subtree
- **Cap redesign**:`chain_max_depth` 2 → 3(primary cap),`chain_max_issues` 5 → 10(safety net);兩 cap 獨立 apply,whichever triggers first 勝
- **Verify FAIL halt scope**(Q4 Option C):per-root continue(非 global halt)— root #N 的 subtree 中 verify FAIL → 記入 `FAIL_ROOTS[]`,該 subtree 標 FAIL 並停,但其他 root 的 subtree 繼續;commits preserved;Phase 4 final report 印 per-root PASS/FAIL
- **Branch naming**:N=1 仍用 `idd/chain-<N>-<slug>`(backward compat);N>1 用 `idd/chain-multi-<hash8>-<root1-slug>`(hash = first 8 chars of `sha256sum` over joined root numbers,collision fallback to hash16)
- **DFS implementation**:current `QUEUE` 是 FIFO(pop-front + push-back = BFS)— DFS mode 改 push-spawns-to-front(`QUEUE=("$SPAWN_NUM" "${QUEUE[@]}")`);BFS mode 保留現行 push-back
- **Per-root depth counting**:每個 root 獨立 depth=0,`DEPTH_MAP[spawn] = DEPTH_MAP[parent] + 1`;`max_depth=3` 對每 root subtree 獨立 apply
- **PR title format**:N=1 維持 `chain: <root title>`;N>1 用 `chain (multi-root): N issues — <root#1 title>`
- **Phase 4 TaskList visualization**:forest tree printout — 每 root 印該 subtree 的 PROCESSED issues 縮排樹狀
- **Helper update**:`scripts/manifest-append.sh` 同步 bump `EXPECTED_SCHEMA_VERSION=2`,新增 `root_id` 參數位
- **4 sub-skill manifest writes**:`idd-implement`/`idd-verify`/`idd-plan`/`idd-diagnose` 的 manifest-append 呼叫需傳入 `root_id`(從讀 manifest 自己的 spawn parent 算出)

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `idd-all-chain`: 接受多 root + 加 traversal mode + 新 cap 值 + 新 verify FAIL halt 語意 + 新 branch naming + 新 PR title
- `idd-spawn-manifest`: schema v1 → v2(BREAKING)— `root_issues: [int]`、top-level `traversal`、spawn entry `root_id`

## Impact

- Affected specs:
  - Modified: `openspec/specs/idd-all-chain/spec.md`(multi-root + traversal + cap + halt + branch + PR title 五個 Requirements 更新)
  - Modified: `openspec/specs/idd-spawn-manifest/spec.md`(schema v2 BREAKING,新欄位 + EXPECTED_SCHEMA_VERSION bump)
- Affected code:
  - Modified: `plugins/issue-driven-dev/skills/idd-all-chain/SKILL.md`(Phase 0.1 多 root 解析、Phase 0.4 cluster branch 命名分支、Phase 1 init QUEUE/DEPTH_MAP 多 root、Phase 2 DFS/BFS 雙模式 + per-root halt、Phase 3 PR title + body、Phase 4 forest tree + per-root PASS/FAIL report)
  - Modified: `plugins/issue-driven-dev/scripts/manifest-append.sh`(EXPECTED_SCHEMA_VERSION=2、新增 root_id 第 9 個位置參數)
  - Modified: `plugins/issue-driven-dev/references/spawn-manifest.md`(schema v2 spec 描述 + example 更新)
  - Modified: `plugins/issue-driven-dev/references/chain-flow.md`(DFS/BFS algorithm + per-root halt scope + cap interaction)
  - Modified: `plugins/issue-driven-dev/skills/idd-implement/SKILL.md`(Step 5.7 manifest-append.sh 呼叫加 root_id 引數)
  - Modified: `plugins/issue-driven-dev/skills/idd-verify/SKILL.md`(Phase 4 manifest-append.sh 呼叫加 root_id)
  - Modified: `plugins/issue-driven-dev/skills/idd-plan/SKILL.md`(Step 2.5 manifest-append.sh 呼叫加 root_id)
  - Modified: `plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md`(Step 3.6 manifest-append.sh 呼叫加 root_id)
