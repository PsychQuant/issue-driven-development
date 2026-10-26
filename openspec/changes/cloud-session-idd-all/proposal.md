## Why

**GitHub-side tracker**: #416

使用者人在 Claude Code 雲端 session（claude.ai/code、手機 app）時，本機沒開，`/idd-all #N` 跑不起來。#416 在雲端 container 內實測到三個阻斷點與兩個語意缺口：

1. plugin 沒載入（可由 setup script 在 session 啟動前安裝解決，已實測）
2. 雲端 proxy 封鎖 GitHub GraphQL：所有 `gh issue …` / `gh pr …` porcelain 回 403，連 `gh auth status` 都失敗；`gh api` REST 可用。`scripts/gh-egress.sh` 是所有 GitHub 寫入的唯一出口，它的 dispatch 是 `gh issue <verb>`，於是雲端所有寫入全斷
3. egress gate 依賴的 `markdown-it-py` 預設沒裝（可由 setup script 解決）
4. 模式缺口：雲端使用者在場，但 container 是暫時的、不 push 工作就消失 —— 需要 `(PR, attended)`，現有 tuple 沒有
5. verify 缺口：雲端沒有 Codex 認證與 executable，codex leg 失敗會被 fail-closed 合成 integrity finding

方向已在 #416 的 diagnose 與 spectra-discuss 定案（issuecomment-6257419682、issuecomment-6402000618）。

## What Changes

- **寫入 transport 改 REST**：`gh-egress.sh` 維持唯一寫入出口與所有 gate，dispatch 由 `gh issue create|comment|edit` 改為 `gh api` REST（本機雲端同一路徑）。stdout 契約由「與 `gh issue <verb>` byte-for-byte 相同」改為「成功時一行 issue／comment URL、失敗時空白」。REST 與 gh 語意不同處照 gh 的行為（label 必須已存在、milestone 忽略大小寫比對 open milestone）。issue URL 嚴格解析；wrapper 讀旗標值的方式改成與 gh 一致，掃描的就是送出的。
- **讀取 helper**：新增 `scripts/lib/gh-rest.sh`（入口）與 `scripts/lib/gh_rest.py`（實作）——把 REST 欄位正規化回 porcelain 名稱、一律分頁、雲端拒絕時 fail-loud 並說明原因。`check-existing-work.sh`、`check-diagnosis-readiness.sh`、`process-attachments.sh`、`idd-worktree.sh`、`check-closed-without-summary.sh` 改用它；`idd-list` 需要的 server 端排序、全量 comments、`mergeable` 也由它提供。
- **雲端偵測**：新增 `scripts/lib/cloud-session.sh`，`CLAUDE_CODE_REMOTE=true` 判定雲端，`CLAUDE_CODE_SESSION_ATTENDED=1` 判定有人在場，訊號缺席一律視為 unattended。
- **模式**：`idd-all` 在雲端強制 PR path，interaction 依 attended 訊號；新增 `(PR, attended)`；雲端下 `--no-pr` 被覆寫為 PR 並印出通知；雲端下 ralph-loop 缺席不降級成 direct-commit，改為 abort。本機的模式解析不變。只有 verify PASS 才開 PR；雲端有 blocking findings 時仍 push branch。`idd-all` 自己建 branch 與開 PR 的步驟直接走 REST。auth gate 為 `gh auth status || gh api user`。
- **Runtime reference**：新增 `references/claude-code-remote-tools.md`（porcelain→REST 對照、偵測訊號、不支援清單、setup script），在 13 個 skill 加一行指向它的 runtime note。
- **Verify**：雲端下 codex leg 不跑，Claude-only，master report 明寫 degraded。
- **不支援面明確失敗**：Discussions（`discussions_api.py` 雲端 guard）、`idd-find`、`idd-report`、`idd-discuss`、`idd-ask` 的 Discussions 語料、未 attach 的 repo。

## Non-Goals

- 不改寫 canonical SKILL.md 內的 porcelain 呼叫（依 plugin CLAUDE.md Runtime Compatibility Policy；SKILL.md 只加一行 runtime note）
- 不支援 `idd-close`、`idd-comment`、`idd-edit`、`idd-config`、`idd-reorganize`、`idd-all-chain` 在雲端的完整流程（它們經 `gh-egress.sh` 的寫入與 `check-*` script 的讀取可用，skill 本體的 porcelain 不改）
- 不做 Discussions、GitHub search、`--blocked-by` 原生關聯在雲端的替代方案（皆需 GraphQL 或 search API）
- 不處理 #400 的 API 觸發／GitHub Actions 路線
- 不在 container 內安裝 Spectra CLI（Spectra 路徑沿用既有 Phase 3b hard gate 的明確失敗）

## Capabilities

### New Capabilities

- `cloud-session-runtime`: 雲端 session 的偵測、GitHub REST transport（寫入與讀取）、runtime reference、不支援面的明確失敗、Claude-only verify

### Modified Capabilities

- `idd-pr-hitl-modes`: mode 解析加入雲端規則與 `(PR, attended)`；PR path 的 unattended hint 改依 interaction 軸

## Impact

- Affected specs: cloud-session-runtime（new）、idd-pr-hitl-modes（modified）
- Affected code:
  - New:
    - plugins/issue-driven-dev/scripts/lib/cloud-session.sh
    - plugins/issue-driven-dev/scripts/lib/gh-rest.sh
    - plugins/issue-driven-dev/scripts/lib/gh_rest.py
    - plugins/issue-driven-dev/scripts/lib/gh_egress_rest.py
    - plugins/issue-driven-dev/references/claude-code-remote-tools.md
    - plugins/issue-driven-dev/scripts/tests/cloud-session/test.sh
    - plugins/issue-driven-dev/scripts/tests/gh-rest/test.sh
  - Modified:
    - plugins/issue-driven-dev/scripts/gh-egress.sh
    - plugins/issue-driven-dev/scripts/check-existing-work.sh
    - plugins/issue-driven-dev/scripts/check-diagnosis-readiness.sh
    - plugins/issue-driven-dev/scripts/process-attachments.sh
    - plugins/issue-driven-dev/scripts/idd-worktree.sh
    - plugins/issue-driven-dev/scripts/check-closed-without-summary.sh
    - plugins/issue-driven-dev/scripts/tests/check-closed-without-summary/test.sh
    - plugins/issue-driven-dev/scripts/lib/discussions_api.py
    - plugins/issue-driven-dev/scripts/tests/gh-egress/test.sh
    - plugins/issue-driven-dev/scripts/tests/check-existing-work/test.sh
    - plugins/issue-driven-dev/scripts/tests/check-diagnosis-readiness/test.sh
    - plugins/issue-driven-dev/scripts/tests/process-attachments/test.sh
    - plugins/issue-driven-dev/scripts/tests/idd-worktree/test.sh
    - plugins/issue-driven-dev/scripts/tests/discussion-reader/test_reader.py
    - plugins/issue-driven-dev/scripts/tests/correct-flow/fake-gh.py
    - plugins/issue-driven-dev/scripts/tests/correct-flow/test.sh
    - plugins/issue-driven-dev/scripts/tests/mention-markdown/test_mention_markdown.py
    - plugins/issue-driven-dev/skills/idd-close/SKILL.md
    - plugins/issue-driven-dev/skills/idd-all/SKILL.md
    - plugins/issue-driven-dev/skills/idd-verify/SKILL.md
    - plugins/issue-driven-dev/skills/idd-issue/SKILL.md
    - plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md
    - plugins/issue-driven-dev/skills/idd-plan/SKILL.md
    - plugins/issue-driven-dev/skills/idd-implement/SKILL.md
    - plugins/issue-driven-dev/skills/idd-update/SKILL.md
    - plugins/issue-driven-dev/skills/idd-clarify/SKILL.md
    - plugins/issue-driven-dev/skills/idd-list/SKILL.md
    - plugins/issue-driven-dev/skills/idd-find/SKILL.md
    - plugins/issue-driven-dev/skills/idd-report/SKILL.md
    - plugins/issue-driven-dev/skills/idd-discuss/SKILL.md
    - plugins/issue-driven-dev/skills/idd-ask/SKILL.md
    - plugins/issue-driven-dev/references/pr-flow.md
    - plugins/issue-driven-dev/references/claude-code-tools.md
    - plugins/issue-driven-dev/README.md
    - plugins/issue-driven-dev/CLAUDE.md
    - plugins/issue-driven-dev/CHANGELOG.md
    - plugins/issue-driven-dev/.claude-plugin/plugin.json
    - .claude-plugin/marketplace.json
    - README.md
  - Removed: (none)
