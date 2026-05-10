## Context

`idd-issue` 既有支援:
1. **Single-issue creation** — `idd-issue "text"` 或 source file 單筆 finding(常見)
2. **Source from doc adapter** — Step 1 Source Type Adapter 支援 docx / pdf / Telegram / Apple Mail / Apple Notes,**但**對「source 含多 findings」案例只把全部當一個 issue body 餵進去
3. **Bundle mode**(`idd-issue-bundle` capability,v2.52.0) — `--parent` / `--blocked-by` / `--bundle-mode` 處理多 issue 創建 + 依賴
4. **Cross-repo group mode** — `groups` config + `--target group:<label>` 處理跨 repo

**Gap**:當 source 含 N 個 findings 且部分對應到**既存** issues(該 amend 而非建新),沒有 IDD-native 解法。Lesley research 2026-05-09 案例:

- 09:48 04-14 transcript 11 個 finding 全新 → idd-issue 順
- 10:05 05-03 transcript mix → idd-issue 全當新建(損失 routing)
- 15:32 amend 5 個既存 #N → 手動 `gh api PATCH` 5 次 + 失去 audit trail

「對既存 #N 批次 amend from source」沒有 first-class 工具,user 退化成手敲 GitHub API。

Per spectra-discuss(2026-05-10 session,#48),5 個 architectural decisions converged:

- **D1 user-route**:AI extract → user route → AI dispatch(rejected AI-route)
- **D2 hybrid audit + commit jsonl**:per-action body footer + `.claude/.idd/issue-runs/*.jsonl` 進 git
- **D3 AI surface top-3 candidates**:per-finding picker 4-option 含 top-3 既存 issue 候選 + Other 展開 new/skip/merge/free-pick
- **D4 batch preview + warn-continue**:Stage 3 final preview + Stage 4 失敗紀錄不 abort
- **D5 merge = combine routing target**:Stage 2 inline sub-prompt;二方 merge MVP

User correction(realignment after spectra-discuss converge):**這是 idd-issue 的擴展 mode,不是 sibling skill**。Issue #48 title 已對齊(「**idd-issue**: 加入 multi-finding source...」);只是 issue body 早期推 Strategy A(新 skill)是 over-abstraction。

## Goals / Non-Goals

**Goals**:

- 把「multi-finding source → mixed-routing batch dispatch」升格為 idd-issue 的 first-class mode,parallel `--bundle-mode` 的 prior art pattern
- 對既存 #N 批次 amend(comment / edit)的 friction 從「N × `gh api PATCH`」降到「single user invoke + N × user pick + 1 batch confirm」
- 維持 IDD 紀律:audit trail 完整(per-action footer + jsonl)/ user-confirmed routing(無 AI 自動 dispatch)/ scope-bounded(single repo)/ idempotent(jsonl run-id 唯一)
- Backward compatible:既有 idd-issue invocation 不受影響;multi-finding mode 是 additive trigger
- Cross-machine continuity:jsonl commit 進 git,跨 session 跨 machine 場景可 replay audit trail

**Non-Goals**:

- AI-route(已 rejected per D1)
- idd-all-chain integration(Phase 1 standalone;留 future enhancement)
- Three-way+ merge(MVP 限二方)
- Cross-repo dispatch(對齊既有 `--target` config single repo 假設)
- `idd-list` 露出 internal API(用簡單 `gh issue list --search` 即可,per D3 design)
- Mandatory `--dry-run` flag(被 Stage 3 batch preview cover)
- 修改 idd-comment / idd-edit / idd-update 的 atomic skill 行為(只加 cross-reference)

## Decisions

### D1: User-route over AI-route

AI 從 source 抽 findings 並 surface candidates,**but routing decision 完全由 user 主導**。

**Rationale**:Lesley case 真實 friction 是 dispatch 不是 routing — user 看完 finding 自己最知道對應 #N。AI-route 的最大失敗模式是高估 keyword match confidence 把 finding 推到錯 issue,recovery 成本(close + 重新 file)遠大於 user 一次 click 確認。

**Trade-off**:user 仍要 N 次 click。Mitigation:Stage 3 batch preview 讓 user 在一個畫面看完整 plan,實際 click cost 攤分到 surface candidate 已 narrow 的 picker。

### D2: Hybrid audit trail (footer + commit jsonl)

每個 dispatched action body 加 footer:

```markdown
> Surfaced via /idd-issue multi-finding mode 2026-05-10T17:00:00 from `communications/recordings/0509-research.srt`
> Run log: `.claude/.idd/issue-runs/2026-05-10T17:00:00.jsonl`
```

`.claude/.idd/issue-runs/<ISO-8601-run-id>.jsonl` 一檔/run,commit 進 git。Schema:

```jsonl
{"run_id": "2026-05-10T17:00:00", "source": "<path or 'pasted-text'>", "actions": [
  {"finding_id": 1, "finding_quote": "...", "action": "create", "issue_url": "...", "issue_number": 50, "duration_ms": 1234},
  {"finding_id": 2, "finding_quote": "...", "action": "comment", "issue_number": 14, "comment_url": "...", "duration_ms": 890},
  {"finding_id": 3, "finding_quote": "...", "action": "edit", "issue_number": 17, "duration_ms": 1100, "merged_from": [4]},
  {"finding_id": 5, "action": "skip", "reason": "user-decision"},
  {"finding_id": 6, "action": "create", "error": "GraphQL rate limit", "retry_hint": "manual gh issue create"}
]}
```

**Rationale**:雙保險。Footer 讓 GitHub 端 archaeology 可 grep `via /idd-issue multi-finding`;jsonl 讓本地 audit 一檔到位 + cross-machine continuity(commit)。

**Trade-off**:`.claude/.idd/` 目錄會多出 jsonl 檔。Mitigation:per-run 一檔(非 append-only single file),單檔小,易刪。

### D3: AI surface top-3 candidates per-finding picker

**Stage 2 per-finding picker 流程**:

```
For each finding:
  1. AI compute keyword overlap score:
     - Source: gh issue list --state open --search "<noun_phrases from finding>" --limit 30
     - Score: title overlap × 2 + body[:300] overlap × 1, normalize
  2. Pick top-3 by score
  3. AskUserQuestion 4-option:
     [#X (score 0.85)] [#Y (score 0.72)] [#Z (score 0.41)] [Other]
  4. If user picks #X/Y/Z → routing = comment OR edit (sub-prompt to disambiguate intent)
     If user picks Other → second AskUserQuestion: [New issue] [Skip] [Merge] [Pick free-text #N]
```

**Routing intent disambiguation**(picked existing #X):

```
AskUserQuestion: "Finding goes to #X. What action?"
  [comment] — append to #X as new comment (additive context)
  [edit body] — modify #X body (replace stale content / add to existing section)
  [update Current Status] — only update Current Status block (calls idd-update)
  [skip — change my mind] — back to picker
```

**Rationale**:user-route 不等於 AI 不能 surface candidates。Surface top-3 是 information layer,不是 decision layer。AI keyword scoring 透明可審視(score 寫進 picker),user 仍主導決定。

### D4: Batch preview + warn-continue

**Stage 3 batch preview** 用 single AskUserQuestion + table format:

```
=== Multi-Finding Plan (10 findings → 8 actions, 2 skipped) ===
 1. [NEW]      "Schultz scale 12 items"               → /idd-issue
 2. [COMMENT]  "Lesley reputation 變 core IV"         → #14
 3. [EDIT]     "刪 H4-H6 cue hypotheses"              → #14
 4. [COMMENT]  "Conjoint paired-choice 重要性"         → #17
 5. [SKIP]     "(老師閒聊不相關)"                       —
 6. [NEW]      "問卷 §5b Schultz 加 12 題"             → /idd-issue
 7. [COMMENT]  "Prolific N=200-400 確認"               → #8
 8. [EDIT]     "JCP 1-study → 2-study budget"         → #6
 9. [MERGED:8] (combined into row 8)                   → #6
10. [COMMENT]  "Phase 4 dogfood 紀錄"                 → #48

[Execute all] [Edit row N] [Cancel]
```

**Stage 4 dispatch** 跑 N 個 gh API call(順序執行避免 rate limit hit):

- 成功:寫 footer + 寫 jsonl `actions[i]`
- 失敗:寫 jsonl `actions[i].error`,**continue** to next
- 全部完成:print summary `8 succeeded, 2 failed (see jsonl), 2 skipped`,user 自行手動 retry failed actions

**Rationale**:rollback semantically 不適用(每個 action 是 user-confirmed 意圖,不是 AI 推論);halt 浪費已 confirmed 的 K-1 個 work;warn-continue 配 jsonl audit 是最小驚奇 + 最低 cognitive overhead。

### D5: Merge = combine routing target (二方,inline sub-prompt)

**Stage 2 picker 選 [Merge with another finding]**:

```
1. AskUserQuestion: "Merge finding 5 with which?"
   [finding 3] [finding 7] [finding 9] [Other]
2. User picks finding 3
3. AskUserQuestion: "Merged 3+5 should go to..."
   [#X] [#Y] [New issue] [Skip]
4. User picks #X → routing = single combined comment/edit on #X
   JSONL: {"finding_id": 3, "action": "comment", "issue_number": X, "merged_from": [5]}
   Finding 5 marked as merged-into-3, no separate dispatch
```

**Rationale**:declarative — user 在當下決定 merge partner + final routing,no deferred state;JSONL 紀錄 `merged_from` array 保留 audit trail(B 的原文 quote 仍在 finding_id 5 entry 但無 dispatch action)。

**MVP scope**:只支援二方 merge(`merged_from: [N]` 單一 element)。三方+ 未來 enhancement(`merged_from: [N, M]`)。

### D6: Trigger detection — auto-detect by finding count

**Trigger logic**:

```
extract findings from source (Stage 1)
if len(findings) >= 2:
  enter multi-finding mode (Stage 2-4)
else:
  fall back to existing single-issue flow (current idd-issue behavior)
```

**Override flags**(config):

- `--multi-finding` — explicit force multi-finding mode even if Stage 1 only extracts 1 finding(罕見場景:user 知道 source 有多 finding 但 AI 沒抽到全)
- `--no-multi-finding` — explicit disable,把整個 source 當一個 issue body(現有 docx-based idd-issue 行為)

**Rationale**:auto-detect 對 95% 案例正確 + zero learning curve;explicit flags 處理 edge case + future debugging。

### D7: Bundle mode 與 multi-finding mode 互斥

**Pre-flight gate**:

```
if --bundle-mode set AND multi-finding mode triggered:
  abort with: "—bundle-mode 和 multi-finding 模式互斥。Bundle 是 explicit ordered/unordered 多 issue creation;multi-finding 是 source-driven mixed routing(包含 amend existing)。請選一個。"
```

**Rationale**:兩個 mode 的 mental model 不同 — bundle 預期 user 已知道要建 N issue + 依賴關係;multi-finding 預期 source 含未分流 findings。同時 set 語意混淆。

## Implementation Contract

### Behavior(end user observable)

| Invocation | Behavior |
|-----------|----------|
| `idd-issue "text"` | Single-issue mode(unchanged)|
| `idd-issue source.docx` 且 docx 1 finding | Single-issue mode(unchanged)|
| `idd-issue source.docx` 且 docx ≥2 findings | **Auto-trigger multi-finding mode** |
| `idd-issue --multi-finding "text-with-multiple-findings"` | **Explicit multi-finding mode** |
| `idd-issue --no-multi-finding source.docx` | Force single-issue,把 source 當一個 issue body |
| `idd-issue --bundle-mode ordered "..." source.docx` | **Refuse — mutual exclusive error** |

### Interface

**Flags**:
- `--multi-finding` — force multi-finding mode
- `--no-multi-finding` — disable multi-finding auto-trigger

**Output paths**:
- `.claude/.idd/issue-runs/<ISO-8601-run-id>.jsonl` — audit log per run

**Audit trail formats**:

Per-action body footer(appended to created issue body or comment body):

```markdown

---
> **Surfaced via**: /idd-issue multi-finding mode <run_id> from `<source-path-or-pasted-text>`
> **Run log**: `.claude/.idd/issue-runs/<run_id>.jsonl`
```

JSONL schema(per run file):

```typescript
type RunLog = {
  run_id: string;        // ISO-8601 timestamp, e.g. "2026-05-10T17:00:00"
  source: string;        // "<path>" or "pasted-text:<first-30-chars>"
  source_type: "docx" | "pdf" | "telegram" | "apple-mail" | "apple-notes" | "pasted-text" | "md";
  total_findings: number;
  actions: Action[];
  started_at: string;    // ISO-8601
  completed_at: string;  // ISO-8601
  succeeded: number;     // count
  failed: number;        // count
  skipped: number;       // count
};

type Action = {
  finding_id: number;        // 1-indexed
  finding_quote: string;     // original text quoted from source
  action: "create" | "comment" | "edit" | "skip";
  issue_number?: number;     // null if action=skip or action=create-failed
  issue_url?: string;
  comment_url?: string;      // for action=comment
  duration_ms?: number;
  merged_from?: number[];    // 二方 merge: [partner_finding_id]
  error?: string;            // failure message
  retry_hint?: string;       // suggested manual recovery command
  reason?: string;           // for action=skip
};
```

### Failure modes

- **Stage 1 (extract) fails**:abort + error message;source 可能損毀 / 不支援 source-type
- **Stage 2 (per-finding picker) interrupt**:已 routed 的 N 個 decisions 不丟,寫 partial jsonl(`completed_at: null`),user 可重啟跑相同 source 從 partial jsonl resume(P1 enhancement,P0 不做 resume)
- **Stage 3 (preview) cancel**:不寫 jsonl,no GitHub side effect
- **Stage 4 (dispatch) per-action fail**:warn-continue,jsonl `actions[i].error` 紀錄,結束印 summary
- **Bundle mode + multi-finding 同時 set**:Pre-flight gate refuse,error message 引導二選一

### Acceptance criteria

| 驗證 | 方法 |
|------|------|
| Single-issue mode 完全 backward compat | 既有 single-text / single-docx / bundle-mode invocation 行為 unchanged。Manual:跑舊 invocation pattern(`idd-issue "test"`) 確認 1 issue 建立 |
| Multi-finding auto-trigger | source 含 ≥2 findings 時自動進新 flow。Manual:用 Lesley 0509 transcript 跑,觀察 Stage 2 picker 啟動 |
| Top-3 candidate accuracy | AI surface 的 top-3 對 ≥80% findings 包含正確 routing target(Lesley dogfood 實測)|
| Audit trail 雙軌 | 跑完一次 invocation 後:GitHub 端每個 dispatched comment/issue 有 footer;本地 `.claude/.idd/issue-runs/<run>.jsonl` 存在且 schema 正確 |
| Warn-continue 在失敗時 | 模擬 Stage 4 第 K 次 gh call 失敗(stub gh 回 error),驗證 K+1..N 仍跑完,jsonl error 欄位寫對 |
| Mutual exclusion gate | `idd-issue --bundle-mode ordered source.docx` (source 含多 findings)→ refuse with error message 引導二選一 |
| Cross-reference updates | idd-comment / idd-edit / idd-update SKILL.md "When to use" 段含 cross-reference 到 idd-issue multi-finding mode |

### Scope boundaries

**In scope**:
- idd-issue SKILL.md 新 section + flag handler
- jsonl schema + per-action footer format
- 4-stage pipeline 完整實作
- 二方 merge
- Bundle mode mutual exclusion gate
- Cross-reference 4 個既有 skill 的 SKILL.md
- CHANGELOG / plugin.json / README.md / usecase-routing.md 更新

**Out of scope**(future enhancement issues 可建):
- Three-way+ merge
- Stage 2 interrupt resume from partial jsonl
- AI-route 模式(已 rejected per D1)
- idd-all-chain integration
- Cross-repo dispatch
- `idd-list --summary-only` flag

## Risks / Trade-offs

| Risk | Severity | Mitigation |
|------|----------|------------|
| AI 抽 finding 漏抓 / 切錯 granularity | 🔴 high — 影響 mode usability | Stage 2 picker 每筆都有 [Merge] [Skip] option;Stage 3 preview 讓 user 看完整圖再 execute;dogfood phase 用 Lesley 0509 transcript 真實測 |
| Top-3 surface 不夠準導致 user 常選 [Other] | 🟠 medium — UX 退化到 free-pick | keyword scoring 透明(score 寫進 picker),user 可 calibrate;若 [Other] rate >50%,後續 enhancement issue tune scoring |
| Trigger auto-detect 過鬆/過緊 | 🟠 medium — 誤進 / 漏進 mode | `--multi-finding` / `--no-multi-finding` flag override;auto-detect threshold(≥2 findings) 後續可調 |
| jsonl 進 git 增加 repo size | 🟡 low | jsonl 純文字小檔(<10KB/run),可接受;若 repo size 成問題,後續 enhancement 加 `.gitignore` 配 explicit `--commit-runlog` flag |
| Stage 2 picker 對 100+ open issues repo 體驗差 | 🟡 low — top-3 配 free-pick fallback 應該夠 | dogfood 確認;若不夠,後續 enhancement 加 label-filter / repo-section 篩選 |
| Bundle mode mutual exclusion gate 觸發頻率 | 🟢 very low | 兩個 mode 使用情境天然不同(bundle = ordered creation;multi-finding = source-driven mixed),user 不太會同時 set;gate 是 safety net |
| Cross-reference updates lock-in 4 個 skill 的 cross-skill dependency | 🟡 low | 只是文件 cross-link,不是 code-level 依賴;後續移除 multi-finding mode 時也只需移除 link 段落 |
| AI extraction 把同一 finding 切成 2 個 → user merge 處理 | 🟢 expected | merge mechanism 設計就是 cover 此 case;dogfood 觀察是否 merge 頻率高(>20%),若是 後續 enhancement tune extraction granularity |
