# Findings: cloud-idd-runtime-spike

錨點：#400。部署範例與測試目標：private repo `PsychQuant/idd-cloud-sandbox`（seed issue #1）。API key：che830621 組織（Max 附送額度，17 日重置）。

## 矩陣

結果值：`pass`／`fail`／`partial`／`not measured`。沒有證據的格子一律 `not measured`。

| 準則 | Agent SDK on GitHub Actions | Managed Agents |
|---|---|---|
| C1 plugin 載入 | partial — IDD 與三個依賴 plugin 全部載入、無 plugin error，`idd-list` 跑完；但 superpowers 與 parallel-ai-agents 的 presence pre-flight 回報找不到（只查 `~/.claude/plugins/cache/`） | partial — 沒有 plugin 機制；agent 讀 SKILL.md 照做，`idd-list` 跑完（記下 4 個退化步驟）；`export CLAUDE_PLUGIN_ROOT` 可跨 bash 呼叫存活；superpowers 未掛載，presence 檢查 exit 1；掛載的 IDD repo 根目錄的 CLAUDE.md、AGENTS.md 被注入 context |
| C2 GitHub 寫入 | pass — 留言、push、開 PR、squash merge 都成功（PR #2）；開 PR 需要選填的 `IDD_GITHUB_TOKEN`，因為 PsychQuant org 禁止 Actions 開 PR | pass — 留言、push、開 PR #5、squash merge 都以 gh 完成；gh 接受 vault 代換的 placeholder token；沙箱內的 git 設定與檔案找不到任何像 token 的字串 |
| C3 API 觸發 | pass — 每次 run 都由一次 `POST /repos/PsychQuant/idd-cloud-sandbox/dispatches` 開跑（例：38685282630） | pass — `POST /v1/sessions` 開跑；launcher 另送 environment、agent、vault、credential 四個設定請求（environment 與 agent 可重用） |
| C4 Max API 額度 | pass — 只持有 Max 額度的組織接受 SDK 請求，promotional credit 由 US$139.83 降到 US$139.73（run 回報 US$0.097） | pass — US$133.42 → US$133.40，與 session 的 `list_cost` 2 美分一致 |
| C5 成本與時間 | 一張單行 docs 修正跑完整個 idd-all：US$3.37、329 秒、58 輪（Opus 5.5） | 一句 docs 新增跑完整個 idd-all：US$1.03、約 3.5 分鐘（active 190 秒）（Sonnet 5.5） |
| C6 工具可用性 | pass（有一項缺口）— Skill、Agent（Task）、TaskCreate、Workflow 都在；AskUserQuestion 不在，IDD 須走 unattended 預設；權限受 env scrub 強制為 default，靠 allowlist 放行 | fail — 只有 bash、edit、read、write、glob、grep、web_fetch、web_search；沒有 Skill、Agent、TaskCreate、AskUserQuestion、Workflow，IDD 的 Step 0 task list 與 verify 的平行 reviewer 都做不到 |
| C7 degraded verify | pass — verify 報告開頭寫「Codex leg did not run」，Process Gaps 說明原因並以 fail-closed 記為 INFO | pass（附條件）— 報告寫明「Manual sequential self-review (degraded)」與「Codex lens skipped … not a PASS」；但五個 lens 由同一個 agent 依序自審，沒有獨立 reviewer |
| C8 可部署性 | pass — 部署者 repo 只新增 caller workflow、IDD 設定檔與兩個 secret；照 README 即可。期間 README 補上 PAT 步驟；sandbox 為端到端另設 `max_turns: 400` | pass — 只需 keychain 裡的 API key 與 PAT，照 README 執行 launcher；PAT 以 `che-keychain set --stdin` 存入（README 寫的是 `security add-generic-password`，效果相同） |

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

### Agent SDK — C2（task 4.4，2026-10-15）

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

### Agent SDK — 端到端、C5、C7（task 4.5，2026-10-15）

- 第一次（workflow run 38706723482，`/issue-driven-dev:idd-all #1`）：動工前就停下。原因是 spike 自己造成的污染：C2 測試的 PR #2 寫了 `Refs #1` 且已 merge，existing-work 檢查判定 #1 已處理（E3），unattended 模式不開工。agent 另外預告三個阻擋：presence 檢查只認安裝快取、ralph-loop 沒載入（idd-all Step 0.6 會降級成 direct-commit＋attended）、沙箱佔位讓工作目錄不乾淨（PR 模式拒絕開工）。US$0.457。
- 修正（IDD commit `174c98e`）：載入 ralph-loop（`anthropics/claude-plugins-official` 的 `plugins/ralph-loop`，鎖 SHA）；workflow 設 `IDD_SKIP_PLUGIN_CHECK=1`，理由是 workflow 自己載入每個依賴（另開 #403 做正式修法）；佔位改為「checkout 時不存在才排除」，清單補上 `scripts`、`.idea`、`.vscode`。sandbox：#1 以 not planned 關閉並註明原因，同內容另開 #3；caller 為端到端設 `max_turns: 400`（偏離 README）。
- 第二次（workflow run 38707216442，`/issue-driven-dev:idd-all #3`）：完整跑完。
  - diagnose → implementation plan → implement（commit `e7ac0e9`，只改 `README.md` 第 3 行）→ verify PASS（0 輪修正）→ PR #4（`Refs #3`，作者為 PAT 擁有者）→ 停在 verified，提示 `merge … then run /idd-close #3`（#392 落地前的既定終點）。
  - 另打了 `idd-3-verified` tag 並 push。
  - `COST_USD: 3.370`、`DURATION_MS: 328573`、`NUM_TURNS: 58`、0 次 permission_denied。
  - verify 報告（https://github.com/PsychQuant/idd-cloud-sandbox/issues/3#issuecomment-6188138093）：「manual fan-out (4 lens Agents + sequenced DA, model: opus) + Codex … — **Codex leg did not run** (see Process Gaps)」；Process Gaps 說明 `codex-call` 是 macOS 專用 Swift script，在 Linux runner 編譯失敗、也沒有 Codex 認證，以 fail-closed 記為 INFO。
  - agent 回報的退化：`.claude/` 在沙箱內唯讀，unattended 狀態檔、附件資料夾、tree lock 都建不了（各自有文件化的 fallback）；verify reviewer 寫不了自己的 findings 檔，由主 agent 轉存；發 comment 的腳本缺 Python Markdown 套件，agent 自行裝到 `$TMPDIR`；`git push -u` 寫不了 upstream 設定。
  - https://github.com/PsychQuant/idd-cloud-sandbox/actions/runs/38707216442 、https://github.com/PsychQuant/idd-cloud-sandbox/pull/4

### Managed Agents — C3、C4、C8（task 5.1，2026-10-15）

- 基準：08:47Z 讀 che830621 的帳務頁：**US$133.42 promotional credit available**（SDK 路線的實測都已結束）。
- 照 README Route B 執行 `ma_run.sh`（prompt「Reply with the single word OK and nothing else.」、`--max-wait-minutes 15`），使用者在兩次 keychain 授權視窗按「允許」。
  - environment `env_01UW16BQbepRgin5sGTjXq72`、agent `agent_01SwmYE3J3TEQTsPZPRQDfUk`、vault `vlt_011Cg3jSGjzPZZjtkXEBKZ35`、session `sesn_01VfLMyoN3pfrNUvcsiBu6Zc`。
  - 08:47:36 running → 08:47:51 idle，`stop_reason=end_turn`，最後訊息 `OK`；usage：`input_tokens 4`、`output_tokens 4`、`cache_creation 5m 8458`、`active_seconds 1.786`、`list_cost 2`（美分）。模型 Sonnet 5.5。
  - 結束時封存 vault（存放的 PAT 已清除）。事件 9 筆：status_running、user.message、model_request、agent.message、usage、status_idle。
- 08:48Z 重讀：**US$133.40**，減少 US$0.02，與 `list_cost` 一致。
- 與 SDK 路線相比：同樣只回一個字，SDK（Opus 5.5、載入四個 plugin）US$0.097，Managed Agents（Sonnet 5.5、未載入 plugin）US$0.02；差距主要來自模型與 plugin 內容的固定成本。

### Managed Agents — C1、C2、C6（task 5.2，2026-10-15）

- session `sesn_01HZT4M4XbQZMnhUEvV1Y5Ny`：idle、`end_turn`；usage `active_seconds 74.5`、`cache_read 476417`、`cache_creation 5m 59876`、`output_tokens 6651`、`list_cost 27`（美分）。結束時 vault 已封存。
- 工具：`bash, edit, read, write, glob, grep, web_fetch, web_search`。
- presence 檢查：`exit=1`，「superpowers plugin not found」。agent 沒有繞過。
- idd-list：讀 SKILL.md 執行成功，輸出 `#3 [verified] → gh pr review 4 → gh pr merge 4 → /idd-close #3`。退化：Step 0 的 TaskCreate／TaskUpdate 不存在、Step 3.7 改以 `set -uo pipefail` 內聯執行、Step 4 未算相對時間。
- gh：`gh version 2.45.0`（apt 套件），`gh auth status` 顯示以 GH_TOKEN 登入 kiki830621，token 欄位是 placeholder；寫入成功，代表代換在出口完成。
- clone token：`git remote -v`、git config 的 url／extraheader／credential、`~/.git-credentials`、credential helper、`~/.gitconfig`、`~/.netrc`、gh hosts 檔都沒有像 token 的字串；remote 為一般 URL，push 仍成功，憑證由網路層注入。design 中「repo resource token 可能可讀」的風險此次未觀察到。
- 寫入：留言 https://github.com/PsychQuant/idd-cloud-sandbox/issues/3#issuecomment-6188232400 ；commit `d643778` push 到 `spike/ma-c2-probe`；PR https://github.com/PsychQuant/idd-cloud-sandbox/pull/5 ；squash merge `mergedAt 2026-10-15T08:50:24Z`。
- 附帶：掛載的 IDD repo 根目錄的 CLAUDE.md、AGENTS.md 與 `.claude/skills` 清單被注入 agent 的 context（IDD 開發用的 Spectra 規則）。正式版若走這條路線，應只掛載 plugin 目錄或改用上傳的 skills。

### Managed Agents — 端到端、C5、C7（task 5.3，2026-10-15）

- sandbox 開新 issue #6（README 加一句說明 `spike/` 目錄）。prompt：讀 idd-all 的 SKILL.md 與其呼叫的子 skill 照做，UNATTENDED、PR 模式，缺的工具以最接近的方式代替並記為退化。`--budget-cents 800`。
- session `sesn_01KQt5Gds4Bs9i8afzJS42Z4`：08:51:47 → 08:55:13，idle、`end_turn`；usage `active_seconds 190`、`cache_read 4085761`、`cache_creation 5m 172348`、`output_tokens 18796`、`list_cost 103`（美分）。
- 走完：existing-work clear → Diagnosis（docs、Simple、A_parallel_safe、Layer V 未觸發）→ Implementation Plan → 實作（`3918c5f` 改 README；`08e778b` 加入空的附件 manifest）→ verify PASS（0 blocking、1 LOW）→ `idd-6-verified` tag → PR https://github.com/PsychQuant/idd-cloud-sandbox/pull/7 → Phase 6 停在 verified。
- **關卡被 agent 自行越過**：idd-all Step 0.35 superpowers 檢查失敗（skill 規定中止），agent 以「prompt 要求 unattended PR 模式」為由繼續；Step 0.6 ralph-loop 檢查失敗（skill 規定降級成 direct-commit＋attended），agent 也沒有降級。agent 自己寫明「This was safe only because #6 is a prose-only change」。這違反 IDD 的 runtime 政策：無法等價保留的行為要明確標 degraded，不可靜默弱化 gate。
- **verify 不獨立**：沒有 Agent、Workflow、Codex，五個 lens 由同一個 agent 依序自審。報告（https://github.com/PsychQuant/idd-cloud-sandbox/issues/6#issuecomment-6188302238）寫明「Manual sequential self-review (degraded)」「Reviewers were sequential self-reviews by one model, not 5 independent agents」「Codex lens skipped … not a PASS」。
- 揭露的 IDD 本身問題（兩條路線都會碰到）：idd-all Phase 0.5 的 `mark_unattended` 在「工作目錄必須乾淨」檢查之前寫入 `.claude/.idd/state/unattended.json`；`idd-tree-lock.sh` 留下未追蹤的 `.gitignore`；附件 manifest `.claude/.idd/attachments/issue-6/_manifest.json` 被 commit 進 PR #7。另開 issue。

## 決策

**選定 Agent SDK 跑在 GitHub Actions，作為 `/idd-all api` 的 runtime。**

依據（引用矩陣）：

- **C4**：兩條都由 Max 附送額度支付（SDK：US$139.83 → 139.73；Managed Agents：US$133.42 → 133.40）。spike 開始時最大的未知已排除，兩條在計費上沒有差別。
- **C6**：決定性的差異。SDK 路線有 Skill、Agent、TaskCreate、Workflow（只缺 AskUserQuestion，由 unattended 預設處理）；Managed Agents 只有八個基本工具。
- **C1、C7**：SDK 路線以真正的 plugin 載入 IDD 與依賴，verify 以獨立的 Agent reviewer 執行；Managed Agents 只能讀 SKILL.md 模仿，agent 自行越過了兩道關卡，verify 由同一個 agent 自審。前者保留 IDD 的語意，後者在 skill 的關卡與審查獨立性上都打了折。
- **C2、C3、C8**：兩條都通過。SDK 路線需要部署者 repo 有 secret 與 caller workflow，PsychQuant 這類禁止 Actions 開 PR 的 org 還要一把 PAT；Managed Agents 只要 keychain 裡的 key 與 PAT，部署較輕。
- **C5**：同樣的單行 docs 修正，SDK US$3.37（Opus 5.5、獨立 reviewer）、Managed Agents US$1.03（Sonnet 5.5、自審）。差距主要來自模型與 reviewer 數量，不是 runtime 本身；正式版應讓部署者選模型。

不選 Managed Agents 的理由：IDD 的價值在關卡與獨立驗證，這條路線兩者都無法等價保留；要補齊需要大量相容層（上傳 skills、以 multiagent 重建 reviewer、改寫 presence 檢查），等同 fork 一套 skills，違反 runtime 相容政策與 deep-integration 規則。

### 正式 change（`/idd-all api`）的待辦

1. **PR 改在 agent session 之外開**（安全審查）：agent 只 push branch，開 PR 與 merge 由 agent 結束後、不持有 API key 的 workflow 步驟以 PAT 執行，讓 PAT 不進 session。
2. **presence 檢查認得以路徑載入的 plugin**（#403），拿掉 `IDD_SKIP_PLUGIN_CHECK`。
3. **`${CLAUDE_PLUGIN_ROOT}` 加大括號**（#401）。
4. **IDD 的狀態檔不弄髒部署者 repo**：`.claude/` 在 Bash 沙箱內唯讀，unattended 狀態檔、tree lock、附件資料夾都建不了；另一條路線則把它們留在工作目錄甚至 commit 進 PR（#404）。
5. **workflow 補依賴**：發 comment 用的 Python Markdown 套件；`gh pr create` 等寫入在 PR 移出 session 後重新驗證。
6. **關閉 attribution**：雲端 run 在 commit 與 PR 自動加上 Co-Authored-By／Generated with Claude Code，與維護者本機設定不同。
7. **模型與輪數可設定**：caller 傳入 `model` 與 `max_turns`；完整 idd-all 需要遠超 80 輪（實測 58 輪，含子 skill）。
8. **自動 merge 與 close**：依賴 #392。

### `/idd-all api` 要送出的請求（選定路線）

呼叫端（本機 session 或任何 caller）不在本地執行 pipeline，只送出一個請求、回報連結：

```
POST https://api.github.com/repos/{owner}/{repo}/dispatches
Authorization: Bearer <部署者自己的 GitHub token>
{"event_type": "idd-run",
 "client_payload": {"prompt": "/issue-driven-dev:idd-all #<N>", "dry_run": false}}
```

- `{owner}/{repo}` 是部署了 caller workflow 的 repo，也是 IDD 要處理的 repo。spike 中每次 run 都是這樣啟動的（例：38707216442）。
- 這個端點回 204、不回 run 的 ID。要立即回報連結，得在送出後查 `GET /repos/{owner}/{repo}/actions/runs?event=repository_dispatch&per_page=1`，但並發時可能抓錯；或改用 `workflow_dispatch` 端點，看它能否直接回傳 run。正式 change 要選一種並寫測試。
- caller 應能多收 `model` 與 `max_turns`（見待辦 7），由 `client_payload` 帶入。

**參數解析的待決點**：idd-all 的 from-scratch mode 收自由文字，描述若以「api」開頭會被誤判成這個 mode。兩個選項：`api` 當保留字（自由文字以 api 開頭時必須加引號），或改成 `--api` 旗標。名稱維持使用者定的 `/idd-all api`。

## PAT 處置

spike 用的 fine-grained PAT（只授權 sandbox，Contents、Issues、Pull requests 讀寫）依使用者 2026-10-15 的決定**不提前撤銷**，2026-10-17 到期。用途是讓 #392 的手動驗收沿用 sandbox。這兩天內，design〈Risks〉第二條的風險仍在：agent 的 shell 看得到這把 PAT，PAT 送出的事件也能觸發 workflow。限制它的條件不變：sandbox 為 private、issue 作者只有使用者本人、PAT 只授權 sandbox。存放位置是 keychain 與 sandbox secret `IDD_GITHUB_TOKEN`；到期後兩處都要刪。

## 待記錄的觀察

- 背景安全審查（2026-10-15）：prompt injection 可能讀到 agent 環境變數中的 key、未鎖版本的程式碼與 key 同 job → 已以 `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` 與全面鎖 SHA 處理（IDD commit `f54ef3e`）。Managed Agents 的 repo resource token 是否在沙箱內可讀：task 5.2 量測，沙箱內找不到（見上）。
- IDD 的 `check-plugin-presence.sh` 只在 `~/.claude/plugins/cache/` 找依賴 plugin；以本機路徑載入時 C1 的 pre-flight 失敗，task 4.3 已確認（#403）。
