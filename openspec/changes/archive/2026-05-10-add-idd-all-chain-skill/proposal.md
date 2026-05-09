## Why

跑 `/idd-all #N` 解 1 個 issue 過程中,sub-skill 會 spawn follow-up issue (idd-implement Step 5.7 sister bugs / idd-verify Phase 4 P3 follow-ups / idd-plan Step 2.5 tangentials / idd-diagnose Step 3.6 sister concerns)。目前這些 spawn 後 idd-all 就 stop,使用者要手動逐一跑 `/idd-all #M`,**且每個 issue 各自開 PR** — 形成 PR fragmentation,reviewer 失去 holistic view (本 session 真實案例:#28 root issue 衍生 #34 / #41 / #14 / #15 共 4 個 issue,被切成 4 個獨立 PR review)。

需要新 orchestrator skill 把「root + spawn 整鏈」自動接續解完,**單一 PR review** 整顆改動樹。

`/idd-all` 加 `--chain` flag 路線在 discuss 階段被 reject — 過 default-dilemma checklist 全 yes (`chain_policy: off / auto / ask` 三 default 各帶失敗模式;user binary 心智;90% pipeline 共用)。詳細討論見 `docs/design-patterns/default-dilemma.md`。

**GitHub-side tracker**:本 change 對應 GitHub Issue **#44** (`PsychQuant/issue-driven-development`)。Issue 是 change 已啟動後才補建的正式追蹤,因此 issue body 的「Expected」段仍反映**最初**提案 (`/idd-all --chain` flag + `chain_policy` config schema) — 兩者皆已在 discuss 階段 reject。實際採用方案以本 proposal + design.md 為準;#44 的 stale section 需 errata note (見 tasks 7.x)。

## What Changes

- **NEW skill `/idd-all-chain #N`** — thin orchestrator shell,**內部 recursive 呼叫** `/idd-all`,`/idd-all` 本身**不**改動。Phase 0 建 cluster branch (`idd/chain-N-<slug>`)、Phase 2 loop 處理 spawn queue 直到 depth / max-issues 上限、Phase 3 開 1 PR cover 所有 root + chained。停在 verified 等 user review (永不 auto-close,維持 IDD 紀律)。
- **NEW spawn manifest contract** — `.claude/.idd/state/chain-spawned-issues.json` schema 標準化。4 個 sub-skill (`idd-implement` / `idd-verify` / `idd-plan` / `idd-diagnose`) 皆 conformant write,讓 chain shell 機械讀取 spawn list (取代目前散在 prose 的 sister-concern audit trail)。
- **MODIFIED `idd-orchestrator-modes` spec** — 新增第 4 種 mode tuple `(direct-commit, unattended)`,專供 chain context 內 sub-`/idd-all` invocation 用 (chain shell 已建好 cluster branch,sub-`/idd-all` 不該再建自己的 feature branch + 不該開 PR + 不該 fire AskUserQuestion)。既有 3 種 tuple 行為不變。
- **MODIFIED `idd-all` skill** — 加 `--in-chain` flag 偵測 chain context,觸發 4th tuple semantics (skip Phase 0.5 PR mode branch creation + skip Phase 5.5 PR open + sub-skill receive UNATTENDED MODE directive)。其他 phase 完全不變。
- **MODIFIED 4 sub-skill** (`idd-implement` / `idd-verify` / `idd-plan` / `idd-diagnose`) — 在既有 sister-sweep / follow-up-finding / tangential-observation step 加 spawn manifest write logic。**既有 audit trail (Filed sibling issues / Sister Bugs Filed / 等) 不變**,只新增 machine-readable manifest 作 supplement。
- **NEW reference docs**:
  - `references/spawn-manifest.md` — 跨 4 sub-skill 的 manifest schema canonical contract
  - `references/chain-flow.md` — chain shell 的 phase algorithm + depth / max-issues / failure mode 規範

## Capabilities

### New Capabilities

- `idd-all-chain`: New orchestrator skill that drives root issue + auto-emergent spawned issues through one cluster branch and one review PR. Loop semantics, depth limits, failure handling, single-PR body schema.
- `idd-spawn-manifest`: Standardized cross-skill contract for `.claude/.idd/state/chain-spawned-issues.json`. Schema + write rules + 4 sub-skill conformance requirements.

### Modified Capabilities

- `idd-orchestrator-modes`: Add 4th `(direct-commit, unattended)` mode tuple for chain context. Both axes derived from `--in-chain` flag (single source of truth maintained).

## Impact

- Affected specs: 2 new (`idd-all-chain`, `idd-spawn-manifest`) + 1 modified (`idd-orchestrator-modes`)
- Affected code:
  - New:
    - plugins/issue-driven-dev/skills/idd-all-chain/SKILL.md
    - plugins/issue-driven-dev/references/spawn-manifest.md
    - plugins/issue-driven-dev/references/chain-flow.md
  - Modified:
    - plugins/issue-driven-dev/skills/idd-all/SKILL.md (Phase 0.5 + Phase 5.5 add `--in-chain` branch + flag passthrough to sub-skills)
    - plugins/issue-driven-dev/skills/idd-implement/SKILL.md (Step 5.7 add spawn manifest write)
    - plugins/issue-driven-dev/skills/idd-verify/SKILL.md (Phase 4 follow-up findings → spawn manifest)
    - plugins/issue-driven-dev/skills/idd-plan/SKILL.md (Step 2.5 tangentials → spawn manifest)
    - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md (Step 3.6 sister concerns → spawn manifest)
    - plugins/issue-driven-dev/CLAUDE.md (Skills table + Workflow section add chain-solve mode)
    - plugins/issue-driven-dev/.claude-plugin/plugin.json (version bump 2.53.0 → 2.55.0;chain skill is significant feature)
  - Removed: (none)
