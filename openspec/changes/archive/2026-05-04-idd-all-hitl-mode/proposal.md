## Why

`idd-all` v2.40.0 強制走 PR path 且強制 unattended（所有 sub-skill `AskUserQuestion` 一律 suppress）。這個設計對 fire-and-forget orchestration 合適，但對「user 就在 keyboard、想被 sub-skill 諮詢」的常見場景反而是 friction：

1. **PR 對 solo / personal repo 是純 ceremony** — 沒有 review 流程的 repo，每個 issue 強制 feature branch + PR 是 noise
2. **Sub-skill attended 預設被一律 override** — `spectra-discuss` 多輪對話、`spectra-propose` Park/Apply 抉擇、`idd-implement` plan-tier `EnterPlanMode` approval gate 全被靜默跳過。當 user 就在現場時，這些 checkpoint 反而是它們存在的意義

關鍵發現：`references/pr-flow.md` 已有 `pr_policy` config (`always|never|ask`) 服務 `idd-implement`，但 `idd-all` **完全不讀** — 硬覆蓋成 PR path。本 change 把 `idd-all` 改成消費 `pr_policy`，從同一個 source 推導 path + interaction 兩軸。

Tracks PsychQuant/issue-driven-development#1.

## What Changes

- **`idd-all` Phase 0.5 path resolution**: 不再硬覆蓋 PR path，按 `references/pr-flow.md` 既有 `pr_policy` resolution algorithm 解析（`--pr / --no-pr` flag → fork detection → `pr_policy` config → ask）
- **Phase 3a/3b sub-skill args**: direct-commit + attended 模式下，**完全不傳 unattended hint** 給 sub-skills；PR + unattended 模式下沿用現行 hint。讓每個 sub-skill 的 attended 預設在 attended mode 自然生效
- **Phase 5 conditional PR creation**: direct-commit path 跳過 `git push -u` 與 `gh pr create`，直接到 Phase 6 report
- **Phase 6 report**: 對兩 mode 顯示對應的下一步指引（PR mode → review + merge + close；direct-commit mode → review last N commits + close）
- **核心原則段重寫**: "Always PR path" / "Unattended assumption" 改成「依 `pr_policy` 解析 path 與 interaction 兩軸」
- **`references/pr-flow.md`**: 加段「`idd-all` 也消費 `pr_policy`」(目前該文件只記 `idd-implement`)
- **Skill frontmatter**: `description` + `argument-hint` 加註 `--no-pr` 觸發 HITL direct-commit + attended

## Non-Goals

- **不**新增 `--hitl` flag — 與 `idd-implement` 既有 `--pr/--no-pr` vocabulary 對齊，避免引入新 mental model
- **不**新增 orthogonal `--attended/--unattended` flag — path 與 interaction 兩軸從 `pr_policy` 同源推導；混合 mode (e.g. `pr_policy: never` + unattended) 罕見，留待 v2.41+ 再評估真實需求
- **不**自動 close issue after verify — closing summary 含 root-cause/solution narrative，由人寫才有審計價值。HITL 不等於 auto-close-everything
- **不**加 silent timeout for attended mode — 文件明示「attended assumes user in session」。timeout 設多久都會踩雷；放棄 attended-mode 遠端執行情境是合理 trade-off
- **不**翻轉預設 — `pr_policy: ask`（或 config 缺）的第一次呼叫仍預設 PR path。零 backward incompatibility，現有 `/loop` 等顯式帶 `--pr` 的 caller 不受影響
- **不**切細 sub-skill question taxonomy（哪些 question 算「重要」 vs 「節奏細節」可繼續 suppress）— attended mode 全開全關，user 想要更細粒度時開新 issue

## Capabilities

### New Capabilities

- `idd-orchestrator-modes`: defines the path × interaction matrix consumed by `idd-all` (and any future orchestrator skill). Specifies how `pr_policy` config + `--pr/--no-pr` flag jointly resolve into `(path, interaction)` tuples and how each tuple shapes sub-skill invocation args. Captures the "two axes derived from one source" architectural decision so future maintainers don't reintroduce duplicate config surfaces.

### Modified Capabilities

(none — the spec directory is empty pre-this-change; this is the first capability for the IDD plugin codebase)

## Impact

**Code**:
- `plugins/issue-driven-dev/skills/idd-all/SKILL.md` — substantial rewrite of Phase 0.5, Phase 3a/3b, Phase 5; core principles section; frontmatter
- `plugins/issue-driven-dev/references/pr-flow.md` — additive section documenting `idd-all` as a `pr_policy` consumer

**API surface**:
- `idd-all` is a published Claude Code skill consumed by users + by `/loop` automation. Its `--pr/--no-pr/--cwd` flag set + `pr_policy` config field form the public contract. This change extends contract surface (`--no-pr` on `idd-all`, was previously force-overridden) without removing any. Backward-compatible.

**Downstream skills** (idd-implement, idd-verify, spectra-discuss/propose/apply): no source change required. They already have correct attended defaults; this change just stops `idd-all` from overriding them in attended mode.

**Dependencies**: none added.

**Tests / sample runs** (per acceptance criteria in tasks.md): at least 2 trace examples — one PR+unattended (regression of v2.40.0 behavior), one direct-commit+attended (new behavior).
