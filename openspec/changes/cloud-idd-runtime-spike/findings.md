# Findings: cloud-idd-runtime-spike（草稿，實測進行中）

錨點：#400。部署範例與測試目標：private repo `PsychQuant/idd-cloud-sandbox`（seed issue #1）。API key：che830621 組織（Max 附送額度，17 日重置）。

## 矩陣

結果值：`pass`／`fail`／`partial`／`not measured`。沒有證據的格子一律 `not measured`。

| 準則 | Agent SDK on GitHub Actions | Managed Agents |
|---|---|---|
| C1 plugin 載入 | partial — IDD 與三個依賴 plugin 全部載入、無 plugin error，`idd-list` 跑完；但 superpowers 與 parallel-ai-agents 的 presence pre-flight 回報找不到（只查 `~/.claude/plugins/cache/`） | not measured |
| C2 GitHub 寫入 | pass — 留言、push、開 PR、squash merge 都成功（PR #2）；開 PR 需要選填的 `IDD_GITHUB_TOKEN`，因為 PsychQuant org 禁止 Actions 開 PR | not measured |
| C3 API 觸發 | pass — 每次 run 都由一次 `POST /repos/PsychQuant/idd-cloud-sandbox/dispatches` 開跑（例：38685282630） | not measured |
| C4 Max API 額度 | pass — 只持有 Max 額度的組織接受 SDK 請求，promotional credit 由 US$139.83 降到 US$139.73（run 回報 US$0.097） | not measured |
| C5 成本與時間 | not measured | not measured |
| C6 工具可用性 | pass（有一項缺口）— Skill、Agent（Task）、TaskCreate、Workflow 都在；AskUserQuestion 不在，IDD 須走 unattended 預設；權限受 env scrub 強制為 default，靠 allowlist 放行 | not measured |
| C7 degraded verify | not measured | not measured |
| C8 可部署性 | partial — 部署與 dry run 通過；定義要求的 C1 尚待真實 run | not measured |

## 證據

### Agent SDK — C8 部署（task 4.1，2026-10-15）

- 照 `plugins/issue-driven-dev/cloud/README.md` Route A 部署到 sandbox，caller 鎖 IDD commit `f54ef3e3a9dabb0e99d46629c2df396b25cea199`（`uses:` 與 `idd_ref` 相同）。
- sandbox 新增的檔案：
  - `.github/workflows/idd-cloud.yml`（65 行，由 `caller-example.yml` 只改兩處 ref 而來；sandbox commit `66be280`）
  - `.claude/issue-driven-dev.local.json`（5 行，內容與 README 步驟 3 相同）
  - repository secret `ANTHROPIC_API_KEY`
  - 沒有複製任何其他 IDD 檔案，沒有 fork。
- 偏離文件之處：
  - secret 與 IDD 設定檔在 README 寫成之前就建立（task 1.1、1.2），所用指令與內容與 README 步驟 1、3 相同。
  - 等待 run 用的是 `gh run view` 輪詢，不是 README 寫的 `gh run watch`（後者需要互動選擇 run）。
- dry run：`POST /repos/PsychQuant/idd-cloud-sandbox/dispatches`（`event_type=idd-run`、`client_payload.dry_run=true`）→ workflow run 38683706991，`completed success`。
  - 三個 plugin 依鎖定版本抓取：IDD `f54ef3e…`、`obra/superpowers` `5bf4e78…`、`PsychQuant/parallel-ai-agents` `d6c6cea…`。
  - runner 輸出 `MODE: dry-run`、三個 `PLUGIN_DIR`、`PERMISSION_MODE: bypassPermissions`、`SETTING_SOURCES: project`、`ANTHROPIC_API_KEY: *** (set)`；log 中 key 一律為 `***`。
  - https://github.com/PsychQuant/idd-cloud-sandbox/actions/runs/38683706991

### Agent SDK — C4 計費（task 4.2，2026-10-15）

- 基準：04:53Z 讀 Console 帳務頁（che830621’s Individual Org）：Purchased US$0.00、**US$139.83 promotional credit available**。
- 第一次真實 run（workflow run 38683885702）在 CLI 啟動時失敗：`bubblewrap is required for subprocess env scrubbing and isolation`。失敗在送出 API 請求之前，額度未變。修正：workflow 在不持有 key 的步驟安裝 bubblewrap（IDD commit `cb48707`）。
- 第二次 run（workflow run 38684015025，prompt「Reply with the single word OK and nothing else.」）：`RESULT: OK`、`RESULT_SUBTYPE: success`、`COST_USD: 0.0974`、`DURATION_MS: 2573`、`NUM_TURNS: 1`、`MODEL: claude-opus-5-5`、`API_KEY_SOURCE: ANTHROPIC_API_KEY`、`CLAUDE_CODE_VERSION: 2.1.300`、`SDK_VERSION: 0.2.167`。沒有出現「Credit balance too low」。
- 之後 04:56Z 重讀：**US$139.73 promotional credit available**，減少 US$0.10，與 run 回報一致。結論：Agent SDK 的請求由 Max 附送額度支付，不被當成 Claude Code。
- 同一次 run 的附帶觀察（C1、C6 尚未正式量測）：
  - `PLUGIN_ERRORS`：`issue-driven-dev@inline` 為 `dependency-unsatisfied`（缺 `codex-pro@codex-pro`），IDD 沒有載入；superpowers、parallel-ai-agents 有載入。已補上 codex-pro（IDD commit `2cf02d9`）。
  - `WATCHED_TOOLS: Skill=present Agent=present(as Task) TaskCreate=present AskUserQuestion=absent Workflow=present`。
  - 預設模型為 Opus 5.5；只回一個字就要 US$0.097，多半是系統提示與 plugin 內容的固定成本。
  - https://github.com/PsychQuant/idd-cloud-sandbox/actions/runs/38684015025

### Agent SDK — C1、C3、C6（task 4.3，2026-10-15）

到 idd-list 真正跑通之前，修了四個 runner 層的問題；每一個都是前一次 run 揭露的：

| run | 現象 | 原因 | 修正（IDD commit） |
|---|---|---|---|
| 38684015025 | `issue-driven-dev@inline` dependency-unsatisfied | IDD 的 plugin.json 還依賴 codex-pro | 抓 `PsychQuant/codex-pro` 並載入（`2cf02d9`） |
| 38684230150、38684468139 | `SESSION_PERMISSION_MODE: default`，每個 Bash 與 Skill 呼叫都 permission_denied | `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB` 會強制 default 模式，只在 stderr 說明（本機以無效 key 重現，CLI 2.1.300）；中間一次改 managed settings 是錯誤推論，已撤回 | runner 改用 default＋工具 allowlist，並印出 CLI stderr（`b954b03`） |
| 38684924067 | Bash 全部失敗：`socat not installed` | scrub 啟用的 Bash 沙箱需要 socat | 與 bubblewrap 一起安裝（`0f63873`） |
| 38685072135 | Bash 全部失敗：bwrap 無法在 plugin 目錄建立 `.mcp.json`（唯讀） | `add_dirs` 把 `$RUNNER_TEMP` 的 plugin 目錄設成工作目錄 | plugin 改匯出到 workspace 的 `.idd-cloud/plugins/`，並寫進 `.git/info/exclude`（`f89ccd8`） |

最後一次（workflow run 38685282630，prompt：印 `CLAUDE_PLUGIN_ROOT`、跑兩個 presence 檢查、跑 `/issue-driven-dev:idd-list`）：

- `LOADED_PLUGINS`：issue-driven-dev、superpowers、parallel-ai-agents、codex-pro，`PLUGIN_ERRORS: (none reported)`，19 個 `issue-driven-dev:*` skill。
- 0 次 permission_denied；`RESULT_SUBTYPE: success`、`COST_USD: 0.609`、`DURATION_MS: 67699`、`NUM_TURNS: 31`。
- `CLAUDE_PLUGIN_ROOT=<unset>`：本機 Bash 同樣 unset。官方文件寫明 skill 內文只代換 `${CLAUDE_PLUGIN_ROOT}`，Bash 不會拿到這個環境變數；IDD 有 92 處寫成無大括號的 `$CLAUDE_PLUGIN_ROOT`，靠 agent 自行推路徑，另開 #401。C1 的定義因此修正（見 design）。
- presence pre-flight：兩個都 `exit=1`，訊息為「plugin not found. Searched: ~/.claude/plugins/cache/...」。plugin 實際已載入，是檢查方式只認安裝快取。
- idd-list 輸出：`Repo: PsychQuant/idd-cloud-sandbox`、`#1 [(no phase)] docs: README 把 sandbox 拼成 sandbx`、`Needs diagnosis (1): #1 → /idd-diagnose #1`。agent 為了讓 Step 3.7 的 helper 載得到，自行把 `$CLAUDE_PLUGIN_ROOT` 代成實際路徑。
- https://github.com/PsychQuant/idd-cloud-sandbox/actions/runs/38685282630

### Agent SDK — C2（task 4.4，進行中）

- workflow run 38685626718（`GITHUB_TOKEN`，無 PAT）：
  - `gh issue comment 1` 成功：https://github.com/PsychQuant/idd-cloud-sandbox/issues/1#issuecomment-6184965200
  - `git push` 成功（branch `spike/c2-probe`，commit `28f843d`）；`-u` 寫 upstream 設定失敗：`could not lock config file .../.git/config: File exists`（沙箱保護 `.git/config`），不影響 push。
  - `gh pr create` 失敗：`GitHub Actions is not permitted to create or approve pull requests (createPullRequest)`；PsychQuant org 設定 `can_approve_pull_request_reviews: false`，repo 層無法覆寫（API 回 409）。`gh pr merge` 因此也失敗。
  - `git status --porcelain` 顯示沙箱留下的未追蹤佔位：`.bash_profile .bashrc .gitconfig .idea .mcp.json .profile .ripgreprc .vscode .zprofile .zshrc scripts`。
  - agent 自動在 commit 加 `Co-Authored-By: Claude Opus 5.5`、在 PR body 加「Generated with Claude Code」：雲端沒有關閉 attribution 的設定。
- 處理（IDD commit `4fc8dd5`）：reusable workflow 接選填的 `IDD_GITHUB_TOKEN`（使用者選擇以 sandbox 專用 PAT 處理，不改 org 政策）；不可能是專案內容的佔位 dotfile 寫進 `.git/info/exclude`，`scripts`、`.idea`、`.vscode` 刻意不排除。
- 背景安全審查（commit `4fc8dd5`）：PAT 在 agent 的 shell 可見，且以 PAT 產生的事件會觸發 workflow、可被用來連鎖 dispatch。spike 期間接受（理由與正式版修法見 design 的 Risks）。
- 使用者建立 fine-grained PAT（只授權 sandbox、Contents／Issues／Pull requests 讀寫、2026-10-17 到期），存成 keychain `github-pat`／`idd-cloud-sandbox` 與 sandbox secret `IDD_GITHUB_TOKEN`。
- workflow run 38706501387（有 PAT）：`gh pr create` → https://github.com/PsychQuant/idd-cloud-sandbox/pull/2；`gh pr merge --squash` 成功，merge commit `16245559`，`mergedAt 2026-10-15T08:34:10Z`；PR 作者為 PAT 擁有者 kiki830621；issue #1 仍為 OPEN。`COST_USD: 0.186`，0 次 permission_denied。

## 待記錄的觀察

- 背景安全審查（2026-10-15）：prompt injection 可能讀到 agent 環境變數中的 key、未鎖版本的程式碼與 key 同 job → 已以 `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` 與全面鎖 SHA 處理（IDD commit `f54ef3e`）。Managed Agents 的 repo resource token 是否在沙箱內可讀，待 task 5.2 量測。
- IDD 的 `check-plugin-presence.sh` 只在 `~/.claude/plugins/cache/` 找依賴 plugin；以本機路徑載入時預期 C1 的 pre-flight 失敗，待 task 4.3 確認。
