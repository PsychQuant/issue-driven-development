## Context

`/idd-all` (v2.46.0+) 是 single-issue orchestrator,跑 `/idd-all #N` lifecycle (issue → diagnose → implement → verify),Phase 6 停在 verified 等使用者親自 close。Sub-skill (idd-implement / idd-verify / idd-plan / idd-diagnose) 在 verify findings / sister sweep / mid-plan tangentials 等 deliberation moment 會 spawn follow-up issues,但 spawn 後 idd-all 就 stop。

當前缺陷:
- 使用者必須手動逐一跑 `/idd-all #M` 處理每個 spawn (cognitive load)
- 每個 spawned issue 各自開 PR (PR fragmentation,reviewer 失去 holistic view)
- 跨 issue 但同主題的 refactor (e.g. 本 session #28 → #34 → #41) 被切成多 PR,review effort × N

`/idd-all-chain` 解決 chain solve 場景:單一 root issue + auto-emergent 衍生鏈 → 1 個 cluster branch + 1 個 review PR。語意是 IDD orchestrator 從 single-issue lifecycle 演化到 emergent multi-issue lifecycle,**不替代** `/idd-all` (兩個 skill 共存)。

Discuss 階段已 converge:
- `/idd-all-chain` 是 separate skill (不是 `/idd-all --chain` flag,過 default-dilemma checklist 全 yes — 詳見 `docs/design-patterns/default-dilemma.md`)
- 實作策略採「thin shell pattern」— 內部 recursive 呼叫既有 `/idd-all`,`/idd-all` 本身**幾乎不變**

本 design.md 拍板 3 個 implementation 層級 open questions + 6 個 #44 diagnose 階段提到的 design questions。

## Goals / Non-Goals

**Goals:**

- 提供 `/idd-all-chain #N` skill,**單一 cluster branch + 單一 review PR** 解掉 root + auto-emergent spawn 整鏈
- Sub-skill spawn pattern (sister sweep / follow-up findings / tangentials / sister concerns) 取得 machine-readable manifest,讓 chain shell deterministic 偵測 spawned issues
- 維持既有 IDD 紀律:per-issue verify、停在 verified 等 user close、commit 引用 `Refs #N`
- `/idd-all` 行為**不變** (backward compat 對既有 `/loop` automation caller)

**Non-Goals:**

- **不做** `/idd-all-chain` 的「`chain_policy: auto`」自動偵測 — chain 是 explicit user invocation,不從 backlog cold-start (那是 #37 parked bulk-solve mode 的範圍)
- **不做** chain 跨 repo 串接 (groups mechanism 已 cover 跨 repo 場景,跟 chain 互斥)
- **不改** sub-skill 既有 audit trail 格式 (Filed sibling issues / Sister Bugs Filed 等) — manifest 是 supplement,不是 replacement
- **不做** chain 中途某 issue verify FAIL 後自動 retry — failure halts chain,user 接手
- **不做** chain depth 超過 limit 時的「降級為 file-only」異常處理 — 簡單 hard cap,超過直接 stop chain solve (file 為 follow-up issue 等下次 user explicit 跑)

## Decisions

### Decision 1: Chain shell 用 recursive `/idd-all --in-chain` 而非 inline phase logic

**Decision**: `/idd-all-chain` skill 內部用 `Skill(skill="issue-driven-dev:idd-all", args="#N --in-chain")` 遞迴呼叫既有 `/idd-all`,**不**在 chain shell 重新實作 idd-all 的 Phase 0-6 logic。

**Rationale**: User-confirmed simplification (discuss 階段)。Pros:
- `/idd-all` 完全不變 (backward compat 完整保留)
- chain shell ~150 行 vs inline 重做 ~400 行
- bug isolation:chain 邏輯改動不破壞 single-issue path

Cons:
- 需要 `/idd-all` 加 `--in-chain` flag 偵測 chain context (見 Decision 3)
- Sub `/idd-all` 跑時要 deterministic skip Phase 0.5 PR mode branch creation + Phase 5.5 PR open

**Alternative considered**: Phase 4.5/4.6 inline in idd-all — rejected because 90% phase 共用,inline 等於兩條 path 在同個 file 容易污染 single-issue lifecycle。

### Decision 2: Branch coordination 用 cluster branch + 4th mode tuple

**Decision**: `/idd-all-chain` Phase 0 建 cluster branch `idd/chain-N-<slug>`,sub `/idd-all --in-chain` 跑時:
- **不**建 `idd/N-<slug>` per-issue feature branch (skip Phase 0.5 PR mode branch setup)
- **不**開 PR (skip Phase 5.5 PR creation)
- 所有 commits 落在 `idd/chain-N-<slug>` cluster branch
- Sub-skill 收 `UNATTENDED MODE` directive (skip AskUserQuestion)

這對應**新的第 4 種 mode tuple `(direct-commit, unattended)`**,延伸 `idd-orchestrator-modes` spec 的既有 3 tuples。Tuple 解析仍維持「two axes from one source」原則:`--in-chain` flag 是 single source 同時推導 `path=direct-commit` + `interaction=unattended`。

**Rationale**: 既有 2 tuple 不夠 cover chain context (`(PR, unattended)` 會建 per-issue branch + 開 PR;`(direct-commit, attended)` 會 fire AskUserQuestion 讓 chain hang)。需要第 4 種 tuple 才能正確支援 chain 內 sub-skill 行為。

**Alternative considered**: 加 `--branch-override <name>` flag — rejected because 不夠 atomic,使用者可能搞混 branch 與 mode (e.g. `--branch-override foo` 同時 `--pr` 是矛盾語意)。`--in-chain` 一個 flag 推 4-axis 行為,clean。

### Decision 3: `--in-chain` flag 是 chain context 的 single source

**Decision**: `/idd-all` 加 1 個新 flag `--in-chain`:
- 不帶 flag → 既有 3 tuple 行為 (完全 backward compat)
- 帶 flag → 自動 resolve 為 `(direct-commit, unattended)` tuple,且 skip branch creation + PR open

`--in-chain` 不可與 `--pr` / `--no-pr` 共用 (conflict abort,類似既有 `--pr`/`--no-pr` 互斥)。flag 不寫入 config (per-invocation only,避免 default ambiguity)。

**Rationale**: 簡單、explicit、不需新 config schema。Sub `/idd-all --in-chain` 行為 deterministic,chain shell 透過 args 完全控制 sub-skill。

### Decision 4: Spawn manifest schema + 4 sub-skill conformant write

**Decision**: `.claude/.idd/state/chain-spawned-issues.json` schema:

```json
{
  "schema_version": 1,
  "session_id": "<uuid>",
  "root_issue": 28,
  "spawned": [
    {
      "issue_number": 34,
      "spawned_by": "idd-implement",
      "spawn_step": "Step 5.7 sister bug sweep",
      "spawn_kind": "sister-bug",
      "same_file_as_root": false,
      "same_skill_as_root": true,
      "filed_at": "2026-05-08T03:14:22Z",
      "title": "..."
    }
  ]
}
```

4 sub-skills 在既有 sister-sweep / follow-up / tangential step 的 issue create loop 內,append 一個 entry 到 `spawned[]` array (read-modify-write,要 file lock 避免 race)。

**Rationale**: 取代目前散在 prose 的 audit trail。Manifest is machine-readable,chain shell 用 jq 讀 spawned[] 決定 chain queue。

**Alternative considered**: GraphQL `gh issue` API 反查 sister-issue cross-link — rejected because 慢 (N+1 query per chain iteration) + 不可靠 (sister cross-link 不一定都用標準 markdown format)。

### Decision 5: PR body schema 用 collapsed sections per chained issue

**Decision**: `/idd-all-chain` Phase 3 開 1 PR,body schema:

```markdown
chain: <root issue title>

Refs #<root> #<chained_1> #<chained_2> ...

## Summary

Cluster of <N> issues solved as one chain (root + auto-emergent spawn).

## Cluster overview

| # | Spawn source | Phase | PR commit |
|---|-------------|-------|-----------|
| #28 (root) | — | verified | abc123 |
| #34 | idd-implement Step 5.7 | verified | def456 |
| #41 | idd-verify P3 follow-up | verified | ghi789 |

## Per-issue details

<details>
<summary>#28 root — <title></summary>

(diagnose link / verify link / commit list)

</details>

<details>
<summary>#34 — <title></summary>

...

</details>

## Pending review

- [x] Diagnose ✓ for all <N> issues
- [x] Implement ✓
- [x] Verify ✓ (per-issue 6-AI ensemble)
- [ ] **Pending: human review of cluster PR + /idd-close #ROOT #M #K after merge**
```

**Rationale**: GitHub renders `<details>` collapsed by default,reviewer 看 cluster overview table 即可掌握全貌,深入 issue details 才展開。Solves Q3 (PR body wall of text concern) from #44 diagnose。

### Decision 6: Failure mode = halt chain + preserve partial commits (no rebase/revert)

**Decision**: chained issue verify FAIL → halt chain (停止 process queue 中後續 issue),已成功 chain 的 commit **保留**在 cluster branch。chain shell 印 abort report:
- 哪 N 個 issues 已成功 chain (commits / verify URL)
- 哪 1 個 fail 在哪 phase
- 哪 K 個還在 queue 沒跑

User 接手選擇:
- `/idd-verify --pr <chain-PR>` 看 FAIL 細節並修
- 或 `/idd-implement #failing-issue --branch-override idd/chain-...-slug` 在 cluster branch 內接續修
- 或 `gh pr close` + 從 main 重起

**Rationale**: IDD 紀律「不 swallow + recoverable」。Rebase / revert 會破壞 audit trail (chain 過程的 verify findings 會消失)。Partial commits 保留是 explicit state — user 看到 git log 就知道 chain 跑到哪。

### Decision 7: chain depth + max-issues hard cap

**Decision**:
- `chain_max_depth=2` (hard-coded constant in skill v1)
- `chain_max_issues=5` (含 root,所以 root + 4 chained)
- 達 limit 後 spawn 仍 file 為 follow-up issue (既有 audit trail behavior),但**不** chain solve (skip 加進 queue)

**Rationale**: Real-world chain rarely > 2 layers (本 session 實證 #28 → #34 都 stop at depth 1)。限制是 v1 conservative cap,未來若有 evidence 需要更深可改 config。Hard cap 在 skill 內,不靠 config 避免 default ambiguity。

### Decision 8: Cross-cutting heuristic = same-file OR same-skill

**Decision**: 不是所有 spawned issue 都 chain solve。Chain queue 加入規則:

```
chain_eligible(spawned, root) =
    spawned.same_file_as_root == true
    OR spawned.same_skill_as_root == true
    OR spawned.spawn_kind == "sister-bug"     # implies high coupling
```

不 eligible 的 spawn 仍 file 為 follow-up issue (既有 audit trail),但 chain shell **不**加進 queue。

**Rationale**: 防止 chain 跨無關 file / 跨 skill (e.g. #28 idd-all spawn 出 #29 是 upstream tracking,跟 idd-all code 無關 — 不該 chain)。同 file 或 sister-bug kind 是高耦合訊號,自然該 chain 一起解。

**Alternative considered**: ML / heuristic based on title similarity — rejected because 過度工程,deterministic 規則更可預測。

## Risks / Trade-offs

- **Risk: Chain 雪崩** (depth=2 + max=5 = 5 issues × full pipeline = 30+ AI invocations) → Mitigation: hard cap 不可繞過 + per-issue verify 紀律保留 + failure halt chain
- **Risk: Spawn manifest race condition** (4 sub-skills concurrent write 同 file) → Mitigation: file lock via `flock` (POSIX) 或 atomic mv pattern (write to `.tmp` 然後 `mv`);實際上 4 sub-skills 不會 concurrent 跑,sub-skill 都是 sequential 在 chain 內
- **Risk: `--in-chain` 被外部 caller 誤用** (e.g. `/loop` 直接帶 `--in-chain` 但沒 cluster branch context) → Mitigation: `/idd-all --in-chain` Phase 0.3 加 sanity check (cluster branch 命名 pattern `^idd/chain-`,不符 abort)
- **Risk: PR body 過大** (5 issues × details section) → Mitigation: max=5 cap + collapsed `<details>`,GitHub UI 已 handle
- **Trade-off: Manifest contract drift** — 4 sub-skill 都要 conformant write,任一忘記寫 chain 偵測會 silent miss → Mitigation: 把 manifest write 寫進 4 sub-skill 既有 audit trail step (Step 5.7 / Step 3.6 等),作為該 step 的 atomic 動作之一

## Open Questions

(none — all 8 decisions are settled in this design.md based on discuss conclusion + diagnose recommendations + IDD precedent)
