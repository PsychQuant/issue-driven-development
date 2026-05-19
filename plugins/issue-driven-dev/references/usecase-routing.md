# Use-Case Routing Reference

「我現在的情況是 X，該跑哪個 skill 帶哪個 flag？」的 single-source-of-truth。

掃這張表先找到你的情境，再跳到對應的 SKILL / contract 文件看細節。

---

## Decision tree（先選 path，再選 mode）

```
你正要做什麼？
├── 紀錄一個改動的「為什麼」                                  → idd-issue
├── 釐清根本原因 / 評估方案 / 判定 Complexity                  → idd-diagnose
├── 看 Implementation Plan 給人 approve（Plan tier）          → idd-plan
├── 寫 code（你是 Claude 自己做）                            → idd-implement
├── 看 code 對不對                                          → idd-verify  ← 本表後半段重點
├── 結案 + closing summary                                   → idd-close
├── 一氣呵成跑完整個流程                                     → idd-all
├── 同步 issue body 的 Current Status                       → idd-update
├── 列 open issues 看下一步                                  → idd-list
├── 寫進度報告到 GitHub Discussions                         → idd-report
├── 補一條決策 / 筆記 / 問題到既有 issue                     → idd-comment
├── 編輯既有 comment（不 append 新的）                      → idd-edit
└── 看 / 修 .claude/.idd/local.json config                   → idd-config
```

> **Note**: the decision tree above only covers atomic skill picking. For backlog
> bulk-solve scenarios (N unrelated open issues), there is **no built-in zero-arg
> bulk-solve** — see row 27 below: use per-issue `/idd-all #N`, or `/idd-all-chain`
> if hot-emergent ripple is expected.

---

## Master use-case routing table

| # | 情境 | Skill | 帶 flag | Contract 文件 |
|---|------|-------|---------|---------------|
| **1** | 單 issue，Claude 全程自己做（最常見） | `idd-issue` → `idd-diagnose` → `idd-implement` → `idd-verify` → `idd-close` | （無） | — |
| **2** | 同一輪 diagnose 涵蓋多個 independent issue | `idd-diagnose #34 #36 #38` | （無 — batch mode 自動觸發） | [batch-and-cluster.md](batch-and-cluster.md) |
| **3** | 多個 issue 共用一個 PR（一次改完）| `idd-implement #34 #36 #38 --pr` → `idd-verify #34 #36 #38` → `idd-close #34 #36 #38` | `--pr` 強制 PR path | [batch-and-cluster.md](batch-and-cluster.md), [pr-flow.md](pr-flow.md) |
| **4** | Implement 委派給 Codex（你跑 `codex exec`，commit 到當前 tree）| Claude `idd-diagnose` → 自己跑 codex → Claude `idd-verify #98 --commits N` | `--commits N`（N = codex commit 數）| [external-agent-delegation.md](external-agent-delegation.md) |
| **5** | Implement 委派給 Codex，Codex 開 PR 回來（最完整 case）| Claude `idd-diagnose` → 自己 / 別處跑 codex → Claude `idd-verify #98 --pr 123` | `--pr 123`（PR 號碼）| [external-agent-delegation.md](external-agent-delegation.md) |
| **6** | Implement 委派給遠端 agent（PsychQuantClaw / Copilot Workspace），開 PR | 同 #5 | 同 #5 | [external-agent-delegation.md](external-agent-delegation.md) |
| **7** | Implement 在某個 branch 但還沒開 PR | Claude `idd-verify #98 --branch <name>` | `--branch <name>` | [external-agent-delegation.md](external-agent-delegation.md) |
| **8** | 一個 PR 涵蓋 2+ issues（不確定有哪些）| `idd-verify --pr 123` | 不帶 issue → auto-discover 從 PR body Refs #N | [external-agent-delegation.md](external-agent-delegation.md) |
| **9** | Plan tier — 改動跨 5+ 檔且 sequence-dependent，動手前要 approval | `idd-diagnose` 判 Plan → `idd-plan` → `idd-implement` | （`idd-plan` 自動接 `idd-implement`）| `skills/idd-plan/SKILL.md` |
| **10** | Spectra-warranted — 公開 API / protocol，有 spec contract | `idd-diagnose` 判 Spectra → `spectra-discuss` → `spectra-propose` → `spectra-apply` → `idd-verify` → `idd-close` + `spectra-archive` | （chain 由 spectra skills 接力）| `rules/sdd-integration.md` |
| **11** | 一氣呵成跑完整個流程（unattended） | `idd-all #98 --pr`（或 `pr_policy: always`） | v2.46.0+：`idd-all` 從 `pr_policy` + `--pr/--no-pr` 解析 `(path, interaction)` tuple;不帶 flag 且 config 缺則默認 `(PR, unattended)`（v2.40.0 backward compat）| [pr-flow.md](pr-flow.md) |
| **11b** | 一氣呵成跑完,HITL（attended,sub-skill 可問問題）| `idd-all #98 --no-pr`（或 `pr_policy: never`）| v2.46.0+:解析為 `(direct-commit, attended)`,留在當前 branch、不開 PR | [pr-flow.md](pr-flow.md) |
| **12** | Verify 後有 blocking findings，要進入修復迴圈 | `idd-verify #98 --loop` | `--loop`（ralph-loop 自動驗-修迴圈，每輪用完整 6-AI）| `skills/idd-verify/SKILL.md` |
| **13** | 只想要快速 Codex review（不開 5-Claude team）| `idd-verify #98 codex` | `codex`（engine 切換）| `skills/idd-verify/SKILL.md` |
| **14** | 只想要 5-Claude team review（不跑 Codex）| `idd-verify #98 team` | `team`（engine 切換）| `skills/idd-verify/SKILL.md` |
| **15** | 通用 code review（無對應 issue）| `idd-verify` | （無 issue 號碼）| `skills/idd-verify/SKILL.md` |
| **16** | Bundle close — 一個 PR 在 main merge 後，要關 N 個 issues | `idd-close #98 #105 #107` | （cluster-PR mode 自動觸發；要求 PR 已 merged）| [batch-and-cluster.md](batch-and-cluster.md), [pr-flow.md](pr-flow.md) |
| **17** | Issue body 過時，要把 N 條 comments 收斂到 Current Status | `idd-update #98` 或 batch `idd-update #34 #36 #38` | （無）| `skills/idd-update/SKILL.md` |
| **18** | 補一條決策 / 補述到既有 issue（不是 verify findings）| `idd-comment #98 --type decision --body '...'` | `--type` decision/note/question/correction/link/errata | `skills/idd-comment/SKILL.md` |
| **19** | 編輯既有 comment（typo / 結論翻盤）| `idd-edit <comment-url> --mode replace` | `--mode` append/replace/prepend-note | `skills/idd-edit/SKILL.md` |
| **20** | Spectra-discuss 中途要 comment 回 issue（保留 round-trip context）| `idd-comment #98 --resume-spectra="topic"` | `--resume-spectra="<topic>"` | `rules/spectra-bridge.md` |
| **21** | 第一次跑 IDD，要設 config | `idd-config init` | `init`（first-time setup）| `skills/idd-config/SKILL.md` |
| **22** | 想知道 cwd 落在哪個 candidate / group repo | `idd-config which` | `which`（dry-run resolution）| [config-protocol.md](config-protocol.md) |
| **23** | Monorepo / multi-repo，要把 issue 開到特定 repo | `idd-issue --target owner/repo` 或 `--target group:<label>` | `--target` | [config-protocol.md](config-protocol.md) |
| **24** | 要把 issue tag 給 collaborator | `idd-issue --mention <login>[,<login>...]` | `--mention`（自動 fuzzy match + AskUserQuestion fallback）| `rules/tagging-collaborators.md` |
| **25** | Emergent multi-issue solve from one root — root issue 解到一半 spawn 出 sister bug / follow-up,想全鏈在 1 個 PR review(v2.55.0+ single-root, v2.60.0+ multi-root + DFS/BFS) | `idd-all-chain #N` 或 `idd-all-chain #A #B #C [--bfs]` | （無 — 內部用 `--in-chain` 自動推導 4th mode tuple `(direct-commit, unattended)`）；hard caps per-root depth=3 / global max-issues=10 (v2.60.0+, was 2/5)；eligibility = same-file OR same-skill OR sister-bug；multi-root 時 verify FAIL = per-root halt（其他 root subtree 繼續）| [chain-flow.md](chain-flow.md), [spawn-manifest.md](spawn-manifest.md) |
| **26** | Multi-finding source(transcript / docx / 老師回饋)— 一個 source 含 ≥2 findings 要分流到 mixed routing(部分 new issue、部分 amend 既存 #N comment / edit / update),用一次 invocation 取代手敲 N 次 atomic skill(v2.56.0+)| `idd-issue source.docx`(auto-trigger when ≥2 findings)或 `idd-issue --multi-finding "text"`(force in)| `--multi-finding` / `--no-multi-finding`(override auto-detect);**互斥**`--bundle-mode`;Stage 2 picker AI surface top-3 candidates 不 decide;Stage 3 batch preview confirm;Stage 4 warn-continue dispatch + per-action footer + jsonl run log at `.claude/.idd/issue-runs/<run_id>.jsonl`(commit 進 git)| `skills/idd-issue/SKILL.md` `## Multi-finding source mode` 段落 |
| **27** | N 個 unrelated open issues 想一次解(無 emergent 關係) | **目前無內建 bulk-solve** — 手動 `idd-diagnose #N #M ...`(batch)→ per-issue `/idd-all #N` 或 `/idd-all-chain #N`;parked feature [#37](https://github.com/PsychQuant/issue-driven-development/issues/37) | (none — 用既有 atomic skills 組合)| #37 closing summary(parked,not superseded by #44 chain-solve)|

> **Chain-solve vs bulk-solve semantic 差異**(per #49 cross-link):
> - **`/idd-all-chain #N`**(v2.55.0+, row 25, single-root):**hot-chain from active work** — 1 root + auto-emergent spawn(sister bug / verify follow-up / mid-plan tangential / sister concern detected via spawn manifest)。Bounded by hard caps per-root depth=3、global max-issues=10 (v2.60.0+, was 2/5)。Reviewer mental model:「this thread is complete」。
> - **`/idd-all-chain #A #B #C [--bfs]`**(v2.60.0+ multi-root, [#46](https://github.com/PsychQuant/issue-driven-development/issues/46)):**multi-root forest** — N roots + per-root subtrees。DFS default (rich subtree first) / BFS opt-in (fairness across roots)。Verify FAIL = per-root halt(其他 root subtree 繼續)。Cluster branch `idd/chain-multi-<hash8>-<root1-slug>` for N>1。**部分 cover** #37 use case 若 user 願意手動 list roots,但仍非 zero-arg auto-sequence。
> - **#37 bulk-solve**(parked):**cold-start from backlog** — zero-arg auto-sequence all open issues。Unbounded scope。Reviewer mental model:「all my issues fixed in one go」。
> - **`/idd-all-chain` 不**滿足 #37 reopen criteria 的「一次解所有 open issue」— chain 不是 bulk,user 仍需手動挑 root(N=1 或 N>1)。#37 reopen 條件繼續成立(尚未 trigger)。

---

## External-agent verify auto-detect 行為（不帶 input flag 時）

`idd-verify #98`（什麼 input flag 都沒帶）跑這個流程找 diff 來源：

```
1. 數本地 unpushed commits ref'ing #98:
   N=$(git log --grep "#98" origin/<default>..HEAD --oneline | wc -l)
   N>0 → 用 HEAD~N..HEAD（fall through，下一步不跑）

2. N=0 → 查 open PRs ref'ing #98:
   gh pr list --search "#98 in:body" --state open
   找到 1 PR  → AskUserQuestion「Verify PR #X 還是本地 diff？」
   找到 2+ PR → AskUserQuestion 列全部
   找不到     → fall back HEAD~1（保留 v2.36 行為）
```

避免你忘記加 `--commits N` 或 `--pr N` 結果 verify 空 diff。

完整算法見 [external-agent-delegation.md](external-agent-delegation.md#verify-input-source-modes-v2370)。

---

## Issue ↔ PR 對應強制（PR mode iron rule）

`--pr <N>` 一定先檢查 issue↔PR 對應，**不通過直接 abort 不跑 6-AI**：

| 你打的 | PR body 含 | 結果 |
|-------|-----------|------|
| `idd-verify --pr 123`（無 issue） | 沒任何 `Refs #N` | ABORT — PR 沒 ref 任何 issue |
| `idd-verify --pr 123` | 有 Refs，例如 #98 #105 | 用 discovered set 當 cluster |
| `idd-verify #98 --pr 123` | Refs 含 #98 | 進 6-AI |
| `idd-verify #98 --pr 123` | Refs 不含 #98 | ABORT — correspondence broken |
| `idd-verify #98 --pr 123` | Refs 含 #98 #105（多）| AskUserQuestion 確認 scope |

理由：PR 沒有 issue ref = 不可追蹤的改動，IDD 的審計價值就消失了。詳見 [external-agent-delegation.md](external-agent-delegation.md#issue--pr-correspondence-the-iron-rule)。

---

## 哪些 case 還沒支援（v2.37.0 範圍外）

| 想做的事 | 現況 | 替代 / 何時會做 |
|---------|------|----------------|
| Verify 找到 blocking findings → Claude 自己 push fix 回 PR | 不支援 | v1 走 bounce-back（comment 到 PR 等外部 agent 修）；`--takeover` flag 在 v2 規劃 |
| `idd-handoff #N --to codex` 自動建 RED test + post Agent Contract | 不支援 | 設計上 hands-off — 外部 agent 合規是 opt-in |
| Force-push 中途 detection | 不支援 | 罕見；user 重跑即可 |
| 跨 repo 的 cluster（一次 verify 多 repo 的 PR）| 不支援 | 一個 cluster 必須同 target repo |
| Auto-detect 從 git author 推「這是外部 agent 寫的」 | 不支援 | Authorship ≠ delegation；明確 flag 較清楚 |

---

## 看到不知道走哪條時的 fallback

1. 跑 `idd-list` 看 issue 在 IDD 裡的 phase（diagnosed / implementing / verified / closed）
2. 跑 `idd-config which` 看 cwd 落在哪個 repo
3. 找這張表第一欄關鍵字
4. 都不對 → 開 issue 描述情境，貼到 [psychquant-claude-plugins](https://github.com/PsychQuant/psychquant-claude-plugins/issues)

---

## Versioning

- v2.37.0 — 首次發行（external-agent / PR mode 上線時順便整理）
- 表格按 IDD 版本演進補；新增 use case 時直接加 row + 帶上 contract 文件 link
