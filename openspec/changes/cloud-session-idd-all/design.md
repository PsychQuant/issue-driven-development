## Context

#416：在 Claude Code 雲端 session 裡跑 `/idd-all #N`。diagnose（issuecomment-6257195406）實測了雲端 container 的限制，spectra-discuss（issuecomment-6402000618）定案了方向，使用者確認全部 assumptions。

雲端 container 的實測事實（2026-10-19／25）：

| 項目 | 結果 |
|---|---|
| `gh issue view|list|comment|create|edit`、`gh pr list|view|create`、`gh label list`、`gh repo view` | 403：`GitHub GraphQL is not available from Claude Code sessions; use the REST API` |
| `gh auth status` | 失敗（`GH_TOKEN` 是佔位值，proxy 注入真正的憑證） |
| `gh api repos/{owner}/{repo}/...`、`gh api user` | 可用 |
| `gh api search/issues`、未 attach 的 repo | 403（session 綁定 attach 的 repo） |
| 環境變數 | `CLAUDE_CODE_REMOTE=true`、`CLAUDE_CODE_SESSION_ATTENDED=1`（網頁 session） |
| plugin | session 啟動前裝進 user scope 即載入（worker 重啟後觀察到） |
| `codex`、Spectra CLI | 不存在 |

## Goals / Non-Goals

**Goals**

- 雲端 session 內 `/idd-all #N` 走完 issue → diagnose → plan → implement → verify → push + PR，所有 GitHub 讀寫成功
- 做不到的環節明確報錯，不靜默失敗
- 本機行為不變（transport 換成 REST 之外，輸出與 gate 不變）

**Non-Goals**：見 proposal。

**範圍**

- In scope：`idd-all` 路徑上的 skill（`idd-issue`、`idd-diagnose`、`idd-plan`、`idd-implement`、`idd-verify`、`idd-update`、`idd-clarify`）＋ `idd-list`；`gh-egress.sh` 與 4 支讀取 script
- Out of scope：`idd-close`、`idd-comment`、`idd-edit`、`idd-config`、`idd-reorganize`、`idd-all-chain`、`check-closed-without-summary.sh`；Discussions、search、`--blocked-by` 原生關聯；#400 的 Actions 路線

## Decisions

### D1 — 雲端偵測：`scripts/lib/cloud-session.sh`

可 source 的 shell lib，兩個函式：

- `idd_is_cloud_session`：`CLAUDE_CODE_REMOTE` 的值**恰好**是 `true` 時回 0，其餘（未設、空字串、`1`、`TRUE`）回 1
- `idd_cloud_interaction`：`CLAUDE_CODE_SESSION_ATTENDED` 恰好是 `1` 時印 `attended`，其餘一律印 `unattended`

訊號缺席時判 unattended，因為 attended 模式下 sub-skill 的 `AskUserQuestion` 沒有逾時（spec `idd-pr-hitl-modes`「No silent timeout」）：沒人在場的雲端 session 若判成 attended 會永遠等。判錯方向的代價：有人在場卻判成 unattended，只是少問問題，工作仍以 PR 交付。

Python 端（`gh_rest.py`、`discussions_api.py`）以同一判準讀 `os.environ`，不另訂規則。

### D2 — 寫入 transport：`gh-egress.sh` → `scripts/lib/gh_egress_rest.py`

`gh-egress.sh` 的參數解析、attestation、四道 net、empty-body guard 全部不動；只把最後一行 `exec gh issue "$VERB" …` 換成 `exec python3 lib/gh_egress_rest.py "$VERB" …`（`edit-comment` 本來就是 REST，不動）。transport **無條件** REST——REST 在本機也能用，單一路徑、不依環境分支。

`gh_egress_rest.py` 只由 `gh-egress.sh` 呼叫（header 註明：直接呼叫會繞過 gate）。它把 `gh issue <verb>` 參數翻成 `gh api` 呼叫：

| verb | 呼叫（`<R>` = repo，`<N>` = issue 號） | stdin JSON |
|---|---|---|
| `create` | `gh api repos/<R>/issues -X POST --input - --jq .html_url` | `title`（必填）、`body`、`labels[]`、`assignees[]`、`milestone`（號碼） |
| `comment` | `gh api repos/<R>/issues/<N>/comments -X POST --input - --jq .html_url` | `body` |
| `edit` | 先做 label／assignee 增刪（各自一個 `--silent` 呼叫），最後 `gh api repos/<R>/issues/<N> -X PATCH --input - --jq .html_url`；沒有 PATCH 欄位時改 `gh api repos/<R>/issues/<N> --jq .html_url` 取 URL | `title`、`body`、`milestone`（號碼或 `null`） |

edit 的增刪呼叫：加 label `POST repos/<R>/issues/<N>/labels {"labels":[…]}`；移除 label 每個一次 `DELETE repos/<R>/issues/<N>/labels/<url-encoded name>`；加 assignee `POST …/assignees {"assignees":[…]}`；移除 assignee `DELETE …/assignees {"assignees":[…]}`。

支援的旗標（其餘一律以 exit 14 拒絕並點名該旗標，不靜默丟棄）：

- create：`--repo/-R`、`--title/-t`、`--body/-b`、`--body-file/-F`、`--label/-l`、`--assignee/-a`、`--milestone/-m`
- comment：issue（號碼或 URL）、`--repo/-R`、`--body/-b`、`--body-file/-F`
- edit：issue（號碼或 URL）、`--repo/-R`、`--title/-t`、`--body/-b`、`--body-file/-F`、`--add-label`、`--remove-label`、`--add-assignee`、`--remove-assignee`、`--milestone/-m`、`--remove-milestone`

旗標值接受 `--flag value`、`--flag=value`、以及 `gh-egress.sh` 已支援的短旗標黏著形式（`-bX`、`-tX`、`-FX`）。label／assignee 值依 gh 的慣例以逗號分隔且可重複。

repo 解析順序：`--repo` 值（`OWNER/REPO`；`HOST/OWNER/REPO` 時加 `--hostname HOST`，`github.com` 不加）→ issue 參數是 URL 時取 URL 的 owner/repo → 字面 `{owner}/{repo}`（由 gh 依目前目錄的 git remote 解析，與 `gh issue` 省略 `--repo` 的行為一致）。

查詢：milestone 名稱以 `gh api repos/<R>/milestones?state=all&per_page=100&page=K` 分頁比對**完全相同**的 title，找不到 → exit 14；`@me` assignee 以 `gh api user --jq .login` 解析。

**Exit band 維持 #227 不變式**：翻譯器自己的拒絕（缺 title、缺 issue、不支援的旗標、未知 milestone、多餘的 positional）一律 exit 14；任何 `gh` 呼叫失敗 → 以該呼叫的 exit code 結束（gh 的 code 都 < 10），其 stderr 原樣轉出。edit 的前置增刪呼叫失敗時，不再送出後續呼叫。

**stdout 契約**：成功時 stdout 只有一行 URL（create／edit 是 issue URL，comment 是 comment URL）。既有 `URL=$(bash gh-egress.sh create …)` 的 caller 不受影響；header 由「byte-for-byte 等同 `gh issue <verb>`」改寫成這個契約。

payload 經 stdin 傳給 gh：先寫入暫存檔、開成 fd、刪檔，再以該 fd 當 stdin 執行 gh（不留檔、不經 argv，body 不出現在 process list）。

### D3 — 讀取 helper：`scripts/lib/gh-rest.sh` + `scripts/lib/gh_rest.py`

`gh-rest.sh` 是給 shell 與 SKILL.md 用的穩定入口（`exec python3 gh_rest.py "$@"`），邏輯全在 `gh_rest.py`。只讀，沒有寫入子命令。

| 子命令 | REST | 可用欄位（`--json` 必填，逗號分隔） |
|---|---|---|
| `issue-view <N\|URL> [--repo R]` | `repos/R/issues/N`（`comments` 欄位另分頁讀 `…/comments`） | `number,title,state,body,url,createdAt,updatedAt,closedAt,author,labels,assignees,milestone,comments` |
| `issue-list [--repo R] [--state open\|closed\|all] [--label L]… [--limit N]` | `repos/R/issues`，濾掉 `pull_request` | 同上，但不含 `comments` |
| `pr-list [--repo R] [--state open\|closed\|merged\|all] [--limit N]` | `repos/R/pulls`（`merged` = closed 且 `merged_at` 非空） | `number,title,body,state,url,createdAt,updatedAt,closedAt,mergedAt,headRefName,headRefOid,baseRefName,isDraft,author` |
| `repo-view [--repo R]` | `repos/R` | `nameWithOwner,defaultBranchRef,isFork,visibility,url,viewerPermission` |

正規化（輸出與 `gh … --json` 同名同形）：`created_at`→`createdAt` 等 camelCase；`state` 大寫（`OPEN`／`CLOSED`／`MERGED`）；`author` 為 `{login}`；`labels` 為 `[{name}]`；`assignees` 為 `[{login}]`；`milestone` 為 `{title,number}` 或 `null`；`headRefName`／`headRefOid`／`baseRefName` 取自 `head.ref`／`head.sha`／`base.ref`；`isDraft`←`draft`；`defaultBranchRef` 為 `{name}`；`isFork`←`fork`；`visibility` 大寫；`viewerPermission` 由 `permissions` 推導為 `ADMIN`／`MAINTAIN`／`WRITE`／`TRIAGE`／`READ`。comment 物件為 `{id, databaseId, author:{login}, authorAssociation, body, createdAt, url}`。

分頁：`per_page=100&page=K` 逐頁讀到短頁或達到 `--limit`（`--limit` 預設 30，同 gh）。用逐頁呼叫而非 `--paginate`，避免多頁陣列串接的解析問題，也能在達到上限時提早停。

錯誤：exit 0 成功、1 GitHub／gh 失敗、2 用法錯誤（未知子命令、未知欄位、缺 `--json`）。失敗時 stderr 第一行 `gh-rest: <動作> failed: <gh stderr 第一行>`，並依訊息加一行 `hint:`——含 `not enabled for this session` → 提示這個雲端 session 沒有 attach 該 repo（attach 後重試）；含 `GraphQL is not available` → 提示該操作需要 GraphQL、雲端不支援；HTTP 404 → 提示 repo／issue 不存在或沒有權限。

### D4 — 讀取 script 改用 helper

| script | 原本 | 改為 |
|---|---|---|
| `check-existing-work.sh` | `gh pr list --state open/merged`、`gh repo view --json defaultBranchRef`、`gh issue view --json createdAt,state` | `gh-rest.sh pr-list`／`repo-view`／`issue-view`，欄位名不變，所以比對邏輯不動 |
| `check-diagnosis-readiness.sh` | `gh issue view --json comments` | `gh-rest.sh issue-view --json comments` |
| `process-attachments.sh` | `gh issue view --json body,comments` | `gh-rest.sh issue-view --json body,comments` |
| `idd-worktree.sh` | `gh issue view --json title -q .title` | `gh-rest.sh issue-view --json title` + `jq -r .title`（失敗時沿用既有的「無 slug」fallback） |

既有測試以 PATH shim 假造 `gh`；shim 改為回應對應的 `gh api` REST 路徑（回 REST 形狀的 JSON），證明正規化後 script 行為不變。

### D5 — `idd-all` 模式解析（spec `idd-pr-hitl-modes` MODIFIED）

```
1. --in-chain                → (direct-commit, unattended)               不變
2. --pr                      → (PR, unattended)                          不變
3. --no-pr                   → 本機：(direct-commit, attended)            不變
                               雲端：(PR, idd_cloud_interaction) + 覆寫通知
4. 雲端 session（新）         → (PR, idd_cloud_interaction)
5. fork                      → (PR, unattended)                          不變
6-8. pr_policy …             →                                           不變
```

雲端規則放在 fork／pr_policy 之前：`gh repo view --json isFork` 在雲端必定 403（fail-closed 成 fork），`pr_policy: never` 在雲端會讓工作隨 container 消失。雲端 `--no-pr` 的 interaction 也取自訊號而非固定 attended，理由同 D1。

Phase 0.6（ralph-loop gate）：本機行為不變。雲端下 `(PR, unattended)` 缺 ralph-loop 時**不得**降級成 direct-commit（會遺失工作），改為 unwind 剛建的 branch 後 abort，印出一步安裝指令。`(PR, attended)` 不經此 gate（使用者在場，不需要 loop driver）。

Phase 0.3 auth gate：`gh auth status` 改為 `gh api user --jq .login`（本機與雲端皆可用；`gh auth status` 在任一 host 憑證壞掉時也會失敗，`gh api user` 只檢查實際要用的 API）。

PR path 的 unattended hint 依 interaction 軸決定（`(PR, attended)` 不傳 `UNATTENDED MODE`），spec「PR path preserves v2.40.0 behavior」同步修訂；`(PR, unattended)` 的行為逐字不變。

### D6 — Runtime reference 與 skill 指標

新增 `references/claude-code-remote-tools.md`：偵測訊號、porcelain→REST 對照表（含 `gh-rest.sh` 子命令、`gh pr create`→`POST repos/R/pulls`、`gh auth status`→`gh api user`、CCR 的 PR routes）、寫入一律經 `gh-egress.sh`、不支援清單與各自的錯誤訊息、setup script 範本。

SKILL.md 不改寫 porcelain，只在開頭加一行 runtime note，兩種措辭：

- 支援（`idd-all`、`idd-issue`、`idd-diagnose`、`idd-plan`、`idd-implement`、`idd-verify`、`idd-update`、`idd-clarify`、`idd-list`）：雲端時 porcelain 依 reference 改走 REST，寫入仍經 `gh-egress.sh`
- 不支援（`idd-find`、`idd-report`、`idd-discuss`、`idd-ask`）：雲端時停下，印出原因與「改在本機 session 執行」

兩種措辭各有固定標記字串，由 drift-guard 測試鎖定每個 skill 帶有正確的那一種。

### D7 — 雲端 verify：Claude-only（沿用 #400 的判定）

`idd-verify` 在 engine 選擇前：`idd_is_cloud_session` 成立 → `CODEX_ENABLED=false`，跳過 codex-pro 治理解析（不需要也拿不到 Codex 憑證），workflow args 帶 `codexEnabled: false`，manual fan-out 不啟動 Codex 呼叫。master report 的 Engine 行與 Process Gaps 明寫 `Codex leg not run — cloud session (degraded: Claude-only)`。缺 Codex 本身不是 blocking finding。本機行為不變。

### D8 — 不支援面的明確失敗

- Discussions：`discussions_api.GitHub.graphql()` 在雲端直接 raise `DiscussionError`，訊息點明「Discussions 需要 GraphQL，雲端 session 封鎖；請在本機 session 執行」，不送出請求
- `idd-find`／`idd-report`／`idd-discuss`／`idd-ask`：D6 的不支援 runtime note
- `idd-issue --blocked-by`：既有行為已把 GraphQL 錯誤原樣印出並繼續（body blockquote 照寫），雲端 proxy 的 403 訊息本身就點明原因；reference 記錄此限制
- 未 attach 的 repo：D3 的 `hint:`
- Spectra CLI：沿用 `idd-all` Step 0.35 警告與 Phase 3b hard gate

## Risks / Trade-offs

- **本機 transport 改變**：所有寫入改走 REST。緩解：gate 與 stdout 契約不變；翻譯器對不支援的旗標 fail-loud；測試鎖定每個 verb 的 argv 與 payload
- **欄位正規化漏欄**：REST 與 porcelain 欄位語意不完全一致（例如 comment 的 `id`）。緩解：helper 只提供表列欄位，其他欄位以 exit 2 拒絕，不靜默回空值
- **平台訊號漂移**：`CLAUDE_CODE_REMOTE`、`CLAUDE_CODE_SESSION_ATTENDED` 是平台行為。緩解：判準嚴格（只認 `true`／`1`），缺席方向安全（判成本機 → 撞到帶說明的 403；判成 unattended → 少問問題）
- **`CLAUDE_CODE_SESSION_ATTENDED` 在排程／API 起的 session 中的值未實測**：D1 的缺席判 unattended 已涵蓋未設定的情況
- **SKILL.md porcelain 靠 agent 依 reference 翻譯**：非確定性。緩解：確定性要求最高的寫入與 script 讀取已由 D2／D3 承擔；reference 對照表逐條列出

## Implementation Contract

- `bash plugins/issue-driven-dev/scripts/tests/cloud-session/test.sh`：lib 判準（`true`／`1` 之外皆否）、13 個 skill 的 runtime note 標記、reference 涵蓋對照表條目
- `bash plugins/issue-driven-dev/scripts/tests/gh-rest/test.sh`：四個子命令的 REST 路徑、正規化欄位、分頁與 limit、`merged` 過濾、未知欄位 exit 2、雲端拒絕的 `hint:`
- `bash plugins/issue-driven-dev/scripts/tests/gh-egress/test.sh`：既有 gate 斷言全數保留；dispatch 斷言改為 REST argv 與 stdin payload；不支援旗標 exit 14；未知 milestone exit 14；gh 失敗 code 原樣傳出
- 四支讀取 script 的既有測試在 REST shim 下全數通過
- `bash plugins/issue-driven-dev/scripts/run-all-tests.sh`：除兩個以 root 執行時必定失敗的權限測試（`idd-repo-map`、`idd-tree-lock`，基準即失敗）外全數通過
