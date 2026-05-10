## Why

處理 multi-finding source（transcript / docx / 老師回饋）時,當前 IDD 工具集要求使用者**預先**對每個 finding 做 triage(對應到既存 #N 還是新 issue?該 comment / edit / update?),才能呼叫對應 atomic skill。

實際 friction trace（PsychQuant/issue-driven-development#48,Lesley research 2026-05-09 case）：

| 時點 | 動作 | 痛點 |
|------|------|------|
| 09:48 | 04-14 transcript 11 個全新 finding → idd-issue | ✅ 順 |
| 10:05 | 05-03 transcript mix of new + amendment → 全當新建 | ⚠️ 沒法分流 |
| **15:32** | **手動 `gh api PATCH` 5 次** amend #6 #8 #12 #14 #17 | 🔴 **核心 friction** |

「對既存 #N 批次 amend」缺對應 IDD skill — 5 次 `gh api PATCH` 各 30 秒 = 2.5 min + 失去結構化 audit trail。隨 transcript 數量 amplify。

idd-issue 已有 prior art `--bundle-mode`(v2.52.0),從「create one」擴展為「create N + epic」。把「multi-finding source → mixed-routing batch dispatch」升格為 idd-issue 下一個 mode 是自然 fit:user 對 idd-issue 的 mental model 從「filing issues」直接擴成「filing **and amending** from source」,不需學新 skill。

## What Changes

- 新增 `idd-issue` 的 **Multi-finding source mode**:接受 source file 或 pasted text 含 ≥2 個 findings 時,跑 4-stage pipeline 取代現有 single-issue 流程
  - **Stage 1 Extract**: AI 從 source 抽 paragraph-level findings(每筆含原文 quote)
  - **Stage 2 Per-finding picker**: 對每個 finding,AI 先用 `gh issue list --search` 算 keyword overlap surface top-3 candidate issues;然後 AskUserQuestion 4-option 讓 user 選(top-1 / top-2 / top-3 / Other 展開 new/skip/merge/free-pick)
  - **Stage 3 Batch preview**: Stage 2 完成後印完整 dispatch table,單一 AskUserQuestion「execute all / edit row N / cancel」
  - **Stage 4 Dispatch**: warn-continue 跑 N 個 `gh issue create/comment/edit`,失敗紀錄在 jsonl 不 abort
- 新增 trigger 條件:source 偵測到 ≥2 findings 時自動進 multi-finding mode;單一 finding 走既有 single-issue 流程(backward compat)
- 新增 audit trail 雙軌:每個 dispatched action body footer `> Surfaced via /idd-issue multi-finding mode <run_id> from <source>` + `.claude/.idd/issue-runs/<run_id>.jsonl` 結構化紀錄(commit 進 git)
- 新增 merge 語意:Stage 2 picker 的「Merge with another finding」option 用 inline sub-prompt(pick partner → 共同 routing decision)combine 成單一 routing target,JSONL 紀錄 `merged_from: [...]`
- Cross-reference 更新:`idd-comment` / `idd-edit` / `idd-update` SKILL.md 在 multi-finding 場景指向 `idd-issue` multi-finding mode 而非各自獨立 invoke
- **NOT BREAKING**:既有 `idd-issue` invocation pattern 不變(single text / docx without multi-finding detection / `--bundle-mode` 等)全部 backward compatible;multi-finding mode 是 additive

## Non-Goals

- **不做 AI-route**:routing decision 完全由 user 主導(經過 spectra-discuss D1 拒絕 AI-route)。AI 只 surface candidates,不 decide。Confidence threshold / auto-dispatch 概念不存在
- **不整合 idd-all-chain**:Phase 1 ship standalone,multi-finding mode 結束後 user 自行決定 newly-created 的 issues 是否走 idd-all-chain 收尾。Q7 idd-all integration 留給 future enhancement(可能 issue #46 / #47 處理)
- **不做 three-way+ merge**:Stage 2 picker 的 merge option 限二方;三方+ merge 列為 future enhancement(95% 案例二方夠用)
- **不做 cross-repo dispatch**:multi-finding mode 限 single target repo(對齊既有 `--target` config),跨 repo 拆分由 user 多次 invoke
- **不修改 idd-list 露出 internal API**:不 add `--summary-only` flag 之類 cross-skill dependency(對齊 D3 — 用簡單 `gh issue list --search` 即可)
- **不做 mandatory dry-run flag**:`--dry-run` 概念被 Stage 3 batch preview cover,不需另起 flag

## Capabilities

### New Capabilities

- `idd-issue-multi-finding-source`: Define behavior contract for `idd-issue` 的 multi-finding source mode — source extraction trigger conditions / 4-stage pipeline / picker UX / batch preview / warn-continue dispatch / audit trail format(per-action footer + jsonl). Orthogonal to existing single-issue creation and the bundle capability(both extend idd-issue but with non-overlapping modes)

### Modified Capabilities

(none)

## Impact

- **Affected specs**:
  - NEW `openspec/specs/idd-issue-multi-finding-source/spec.md`
- **Affected code**:
  - `plugins/issue-driven-dev/skills/idd-issue/SKILL.md` — 新增 section "Multi-finding source mode" 含 trigger detection / 4-stage pipeline / examples;Step 0 Bootstrap Task List 新增 `extract_findings` / `per_finding_picker` / `batch_preview` / `dispatch_with_warn_continue` 條目(只在 multi-finding mode 觸發時 create)
  - `plugins/issue-driven-dev/skills/idd-comment/SKILL.md` — 在 「When to use」段新增 cross-reference「multi-finding 場景走 /idd-issue multi-finding mode」
  - `plugins/issue-driven-dev/skills/idd-edit/SKILL.md` — 同上 cross-reference
  - `plugins/issue-driven-dev/skills/idd-update/SKILL.md` — 同上 cross-reference
  - `plugins/issue-driven-dev/.claude-plugin/plugin.json` — version bump + description 加 multi-finding mode condensed summary
  - `plugins/issue-driven-dev/CHANGELOG.md` — 新版 entry
  - `plugins/issue-driven-dev/references/usecase-routing.md` — 加 row「multi-finding source → /idd-issue multi-finding mode」
  - `plugins/issue-driven-dev/README.md` — skill 列表更新提及 multi-finding mode
- **New file convention**:
  - `.claude/.idd/issue-runs/<YYYY-MM-DDTHH:MM:SS>.jsonl` — 每次 multi-finding mode invocation 一個 jsonl 檔,commit 進 git
- **Dependencies**:
  - 沿用既有 `idd-issue` Step 1 source-type adapter(che-word-mcp / che-pdf-mcp / Telegram MCP / Apple Mail / Apple Notes 等)— 不新增 plugin dependency
  - 沿用既有 `gh issue list --search` 做 candidate surfacing — 不新增 cross-skill API dependency
- **Backward compat**:
  - 既有 idd-issue invocation 全部行為不變(single text / docx without multi-finding detection / `--bundle-mode` / `--target` / `--mention` 等)
  - 既有 `idd-issue-bundle` capability 完全 orthogonal — bundle mode 跟 multi-finding mode 互斥(同時 set 拒絕,error message 引導 user 二選一)
- **Audit / archaeology**:
  - jsonl 進 git 確保 cross-machine continuity(Lesley project 跨 session 場景關鍵)
  - per-action footer 配 jsonl 雙保險,`grep "via /idd-issue multi-finding"` 跨 N 個 issue/comment 仍可重建 trace
