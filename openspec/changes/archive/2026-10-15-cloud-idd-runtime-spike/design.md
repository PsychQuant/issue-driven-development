## Context

`/idd-all` 目前只能在本機的 Claude Code session 裡跑。#400 要的是用一次 API 呼叫送出 idd-all、在雲端跑完一張 IDD。2026-10-15 讀官方文件得到的現況：

- **Managed Agents**：一次 `POST /v1/sessions` 就能開跑，Max 附送的 API 額度明文涵蓋。沙箱有 bash、git、read／write／edit／glob／grep、web_fetch、web_search；skills 可上傳或從掛載 repo 的 `.claude/skills/<name>/SKILL.md` 探索。文件沒有提到 hooks、`$CLAUDE_PLUGIN_ROOT`、Skill／AskUserQuestion／TaskCreate 工具；`gh` 不在預裝清單；merge PR 沒有文件。
- **Agent SDK**：Python 版以 `plugins=[{"type": "local", "path": ...}]` 從本機路徑載入 plugin（含 skills、agents、hooks）。額度頁寫涵蓋 Agent SDK、不涵蓋 Claude Code，但沒說 SDK 請求如何與 Claude Code 請求區分。
- **Claude Code routines**：雲端 session 不安裝 plugin，`gh issue`／`gh pr`（GraphQL）回 403，計費走訂閱用量。

IDD 對 runtime 的既有政策：Claude Code 是 canonical runtime，其他 runtime 只能當相容層；無法等價保留的行為要明確標 degraded，不可靜默弱化 gate（plugin 的 CLAUDE.md〈Runtime Compatibility Policy〉、`references/codex-tools.md`）。IDD 另外依賴三個 plugin（`plugins/issue-driven-dev/.claude-plugin/plugin.json` 的 `dependencies`）：superpowers、parallel-ai-agents（`PsychQuant/parallel-ai-agents`）與 codex-pro（`PsychQuant/codex-pro`）；缺任何一個，IDD 本身就不會載入（第一次真實 run 實測到 `dependency-unsatisfied`）。superpowers 掛在 `anthropics/claude-plugins-official` 這個 marketplace 下，但它的程式碼不在該 repo 裡：marketplace 的條目指向 `obra/superpowers` 的一個固定 commit。三個來源 repo 都是 public。

使用者在 apply 開始時修正了部署形狀：流程要放在 IDD repo、讓其他使用者能部署到自己的 GitHub；API key 留在部署者自己的 private repo。private repo `PsychQuant/idd-cloud-sandbox` 已建立（seed issue #1、secret `ANTHROPIC_API_KEY`，key 來自 che830621 組織），作為第一個部署範例與測試目標。

## Goals / Non-Goals

**Goals:**

- 用同一組八項準則（C1–C8）實測 Managed Agents 與 Agent SDK＋GitHub Actions 兩條路線，每一格都附證據。
- 實測 Max API 額度在兩條路線上是否真的被扣。
- 讓流程從第一天就以「IDD repo 提供流程、部署者 repo 提供 key」的形狀存在，並實測別人能否照文件部署。
- 選定一條路線（或兩條都不選並寫明原因），作為正式 change 的依據。

**Non-Goals:**

- 不在本 change 交付 `/idd-all api`；觸發介面、正式文件與穩定版發佈留給後續 change。本 change 新增的流程標為實驗性。
- 不改動任何既有 skill，也不為 Managed Agents fork 一套 skills。
- 不評估 Claude Code routines（理由見 Decisions）。
- 不實作 #392 的自動 merge 與 close；spike 只量測 merge 在各路線上能不能做到。

## Decisions

### 先 spike 兩條路線再選定 runtime

使用者在 2026-10-15 選擇「先 spike 兩條再決定」。兩條的卡點性質不同：Managed Agents 的問題是功能缺口（要寫多少相容層），Agent SDK 的問題是計費歸屬（文件沒寫）。兩者都無法只靠讀文件判斷。

替代方案：直接選 Agent SDK（plugin 原樣載入、最符合 deep-integration 規則），或直接選 Managed Agents（最貼近「用 Claude API 直接送」）。都沒採用，因為各自有一個未驗證的前提，選錯的成本是整個正式 change 重做。

### 排除 Claude Code routines

routines 的雲端 session 對 `gh issue`、`gh pr` 這類 GraphQL 子命令回 403；IDD 幾乎每個 skill 都用這兩個子命令讀寫 issue 與 PR。計費也走訂閱用量，不吃 API 額度。兩個條件都與 #400 的目標衝突，不納入 spike。

### 雲端 verify 只用 Claude 並標 degraded

使用者選擇不在雲端放 OpenAI key。雲端的 verify 只跑 Claude 的 lens，報告必須明寫「缺 Codex 跨模型那一條」。本 change 的 C7 量測這個 degraded verify 能否跑完、報告是否寫明缺口；正式 change 再把標示方式寫成規格。

替代方案：放 OpenAI key、安裝 codex CLI，維持 6-AI。被否決的理由是成本與憑證面積；代價是失去跨模型審查（過去的 blocking finding 多數來自跨模型），所以必須明示，不能靜默降級。

### 流程放在 IDD repo，key 留在部署者的 private repo

使用者在 apply 開始時定案：流程（reusable workflow、執行腳本、launcher、部署說明）放在 IDD repo，跟 plugin 一起維護；API key 與一份幾行的 caller workflow 放在部署者自己的 private repo。Agent SDK 路線用 GitHub 的 reusable workflow 實現這個分工：IDD repo 的 `.github/workflows/idd-cloud-run.yml` 宣告 `on: workflow_call` 並要求部署者傳入 `ANTHROPIC_API_KEY` secret，另接一個選填的 `IDD_GITHUB_TOKEN`（只授權部署者 repo 的 fine-grained PAT），供禁止 GitHub Actions 開 PR 的 org 使用；部署者 repo 的 caller workflow 以 `uses: PsychQuant/issue-driven-development/.github/workflows/idd-cloud-run.yml@<ref>` 呼叫它。IDD repo 不存放任何 API key，reusable workflow 也不讀取 IDD repo 自己的 secret。PsychQuant org 就禁止 Actions 開 PR（sandbox run 38685626718），使用者在 apply 時選擇以 sandbox 專用的 PAT 處理，不改 org 政策。

執行腳本與 launcher 放在 `plugins/issue-driven-dev/cloud/`，隨 plugin 發佈；部署說明 `plugins/issue-driven-dev/cloud/README.md` 標明實驗性。

替代方案：spike 工具放在只供 maintainer 用的開發目錄（原設計）。被使用者否決，因為其他使用者拿不到，也就無法部署自己的雲端 IDD。

### spike 只在專用 scratch repo 上執行

所有會寫入 GitHub 的測試動作（留言、push、開 PR、merge）只對 `PsychQuant/idd-cloud-sandbox` 做；使用者在 apply 時確認測試目標維持私人 sandbox。`PsychQuant/issue-driven-development` 只透過一般 commit 新增流程檔，spike run 不在上面開 issue、留言、push 或 merge。

### 憑證不進 repo 也不進 log

- Anthropic API key：Agent SDK 路線存成部署者 repo 的 repository secret，由 caller 明確傳給 reusable workflow（不用 `secrets: inherit`，只傳這一個）；Managed Agents 路線從 macOS keychain（service `anthropic-api`）即時讀，以 stdin 傳給 curl 的 header，不放進 argv。
- GitHub token：Agent SDK 路線預設用 workflow 的 `GITHUB_TOKEN`，權限由 caller 的 `permissions` 限定為 contents、issues、pull-requests 的 write，只作用在部署者 repo、job 結束即失效；部署者提供 `IDD_GITHUB_TOKEN` 時改用它（只授權部署者 repo 的 fine-grained PAT，效期越短越好）。Managed Agents 路線用一把只授權 sandbox repo 的 fine-grained PAT，由使用者建立並存進 keychain，經 vault 的 environment_variable credential 提供給 session。
- 使用者提供的 prompt 一律以環境變數傳進 shell，不以 `${{ }}` 直接插入 `run:` 指令，避免 workflow 指令注入。
- 兩支執行程式都有 `--dry-run`，只印出將要送出的請求，secret 一律以 `***` 遮蔽；測試確認 dry-run 輸出不含 secret。

### Agent SDK 路線以本機路徑載入 IDD 與三個依賴 plugin

reusable workflow 先 checkout 部署者 repo（工作目錄），再把 IDD（以 `idd_ref` 指定版本）、superpowers（`obra/superpowers`，鎖在官方 marketplace 當下指定的 commit）、parallel-ai-agents、codex-pro 四個 repo 以 git 抓到 runner 的暫存目錄（`actions/checkout` 不接受 workspace 以外的路徑，抓進 workspace 又會在部署者 repo 留下未追蹤檔案），執行腳本以 `plugins=[{"type": "local", "path": ...}]` 逐一載入。GitHub runner 預裝 gh，`GH_TOKEN` 取自 `GITHUB_TOKEN`。

### Managed Agents 路線以讀檔方式執行 IDD skill

Managed Agents 只從 repo 根目錄的 `.claude/skills/<name>/SKILL.md` 探索 skill，IDD 的 skills 在 `plugins/issue-driven-dev/skills/` 底下，無法被自動探索。launcher 把目標 repo 與 IDD repo 以 `github_repository` resource 掛進 session，agent 的 system prompt 指示它直接讀對應的 SKILL.md 並照做。environment 沒有文件記載的環境變數欄位，所以 `CLAUDE_PLUGIN_ROOT` 改由 system prompt 指示 agent 自行 `export` 為掛載路徑；它能否跨多次 bash 呼叫存活，由 spike 記錄。gh 以 environment 的 packages 安裝，裝不到就改下載官方 release binary。

替代方案：用 `POST /v1/skills` 上傳每個 idd-* skill。沒採用，因為 IDD 的 skill 共用 plugin 層的 `scripts/`，逐一上傳會把共用腳本切散；若讀檔方式失敗，再於 findings 記錄是否值得改用上傳。

### 雲端 run 的終點沿用 idd-all

spike 的端到端 run 以 unattended PR mode 跑 `/idd-all`。#392 落地前，idd-all 的終點是開 PR 並停在 verified；spike 另外以獨立步驟量測 merge 能不能做到（C2），不改 idd-all 本身。

### 正式入口命名為 /idd-all api

使用者在 2026-10-15 定名：正式的雲端入口是 `/idd-all api`，作為 idd-all 的一個 mode，不另開新 skill。語意是：呼叫端不在本地執行 pipeline，而是透過 API 把整個 run 送到 spike 選定的雲端 runtime，立即回報 session 或 workflow run 的連結；pipeline 的行為與 `/idd-all` 的 unattended PR mode 相同。本 change 不實作這個 mode，只確保流程的介面能直接被它包起來：

- Managed Agents 路線：`/idd-all api` 送出 `POST /v1/sessions`，等同 `ma_run.sh` 去掉輪詢的部分。
- Agent SDK 路線：`/idd-all api` 對部署者 repo 送出 GitHub 的 dispatches 請求，caller workflow 再呼叫 IDD 的 reusable workflow。

不另開 skill（例如 `/idd-cloud`）的理由：pipeline 本身不變，變的只是在哪裡執行；沿用 idd-all 的 mode 解析，只是多一個執行位置。

## Implementation Contract

**八項評估準則（每條路線每一項都要有結果與證據）：**

| 代號 | 準則 | 通過的定義 | 證據 |
|---|---|---|---|
| C1 | plugin 載入 | IDD 與三個依賴 plugin 都載入且沒有 plugin error；`/issue-driven-dev:idd-list` 跑完；skill 能解析出 plugin 路徑並執行其腳本；SessionStart hook 有輸出；superpowers 與 parallel-ai-agents 的 presence pre-flight 通過（原定「`$CLAUDE_PLUGIN_ROOT` 有值」已刪除：Bash 在任何環境都拿不到這個變數，見 #401） | 執行紀錄原文 |
| C2 | GitHub 寫入 | 在 sandbox repo 依序完成：issue 留言、push branch、開 PR、merge PR | 每一步的成功輸出或錯誤原文、PR URL |
| C3 | API 觸發 | 一次 HTTP 呼叫即開跑：Managed Agents 為 `POST /v1/sessions`；Agent SDK 為對部署者 repo 的 `POST /repos/{owner}/{repo}/dispatches` | 請求與回應（secret 遮蔽） |
| C4 | Max API 額度 | 以只持有 Max API 額度的組織的 key 跑極小 prompt：額度餘額減少、且沒有出現「Credit balance too low」 | 執行前後的額度、錯誤原文 |
| C5 | 成本與時間 | 一次端到端 run 的 token 費用、sandbox 或 runner 時間、總耗時 | session usage 或 SDK 回傳的 cost、workflow run 時間 |
| C6 | 工具可用性 | 逐一記錄 Skill、Agent、TaskCreate、AskUserQuestion、Workflow 是否存在；不存在者寫明 IDD 的哪一步會退化、怎麼退化 | 工具清單原文 |
| C7 | degraded verify | Claude-only 的 verify 能跑完，報告寫明缺 Codex | verify 報告連結 |
| C8 | 可部署性 | 只照 `plugins/issue-driven-dev/cloud/README.md` 的步驟，在 sandbox 完成部署並跑通 C1 與 C3；部署者 repo 只新增 key 與 caller 設定，不複製 IDD 的其他程式碼、不 fork IDD | 部署者 repo 新增的檔案清單與行數、照做時偏離文件之處 |

**reusable workflow（`.github/workflows/idd-cloud-run.yml`）的介面：**

- 觸發：只有 `on: workflow_call`；不因 IDD repo 自己的 push 或 PR 而執行。
- inputs：`prompt`（string，必填）、`idd_ref`（string，預設 `main`，指定要 checkout 的 IDD 版本）、`max_turns`（number，預設 80）、`dry_run`（boolean，預設 false）。
- secrets：`ANTHROPIC_API_KEY`（必填）、`IDD_GITHUB_TOKEN`（選填；有則作為 `GH_TOKEN`，無則用 `github.token`）。不宣告、不讀取其他 secret。
- 行為：checkout 部署者 repo；把 IDD、superpowers（`obra/superpowers` 的固定 commit）、parallel-ai-agents、codex-pro 抓到 `$RUNNER_TEMP`，`idd_ref` 先驗證只含分支或 commit 允許的字元；安裝 Python 與 `claude-agent-sdk`（版本在實作時鎖定並記進 findings）；以環境變數傳入 prompt 後呼叫 `sdk_run.py`；`timeout-minutes: 60`。
- 權限：不自行提升權限；實際權限由 caller 的 `permissions` 決定。

**caller workflow 範本（`plugins/issue-driven-dev/cloud/caller-example.yml`）：**

- 觸發：`workflow_dispatch`（輸入 `prompt`）與 `repository_dispatch`（type `idd-run`，`client_payload.prompt`）。
- `permissions`：contents、issues、pull-requests 為 write，其餘不給。
- 只把 `ANTHROPIC_API_KEY` 與 `IDD_GITHUB_TOKEN` 明確傳給 reusable workflow，不用 `secrets: inherit`。

**Agent SDK 執行腳本（`plugins/issue-driven-dev/cloud/sdk_run.py`）的介面：**

- 參數：`--prompt <text>`（必填）、`--plugin-dir <path>`（可重複，至少一個）、`--cwd <path>`、`--max-turns <n>`、`--dry-run`。
- 行為：以給定的 plugin 目錄啟動 SDK，先印出實際載入的 plugin 與可用工具清單，再印出每則訊息摘要，最後印出結果與 SDK 回報的費用。
- `--dry-run`：不呼叫 API，只印出將使用的選項；API key 只顯示是否存在。
- 失敗：缺 `ANTHROPIC_API_KEY`、plugin 目錄不存在、SDK 回報錯誤時以非零狀態結束，錯誤原文寫到 stderr。

**Managed Agents launcher（`plugins/issue-driven-dev/cloud/ma_run.sh`）的介面：**

- 參數：`--prompt-file <path>`（必填）、`--target-repo <owner/repo>`（必填）、`--keychain-account <name>`（必填，API key 所在的 keychain account）、`--github-token-keychain <service>:<account>`（必填，fine-grained PAT 所在處）、`--dry-run`。
- 行為：依序送出五個請求：建立 environment、agent、vault、vault 裡的 PAT credential、session（掛載目標 repo 與 IDD repo，設 session budget）；輪詢 session 狀態直到 idle 或 terminated；印出 session ID、停止原因與 usage；結束時（含失敗）封存 vault，清掉存放的 PAT。
- `--dry-run`：只印出五個請求的 body，token 與 key 一律顯示為 `***`，不讀 keychain、不送請求。
- 失敗：缺 key 或 token 時非零結束並點名缺少的 keychain entry；任何 HTTP 非 2xx 時印出狀態碼與回應 body（遮蔽後）並以非零狀態結束。

**部署說明（`plugins/issue-driven-dev/cloud/README.md`）：** 兩條路線各自的部署步驟、需要的 key 與權限、觸發方式、實驗性聲明與已知限制；C8 只照這份文件做。

**findings 的必要內容（`findings.md`）：** 兩條路線 × C1 到 C8 的矩陣、每格的證據或連結、一次端到端 run 的費用與時間、最後的決策與理由。

**範圍：**

- In scope：上述 reusable workflow、caller 範本、兩支執行程式、部署說明、測試、sandbox 上的部署與實測、findings、決策紀錄、在 #400 貼摘要。
- Out of scope：修改既有 skill、`/idd-all api` 的實作、Codex 跨模型 verify、Claude Code routines、spike run 對 `PsychQuant/issue-driven-development` 的任何寫入。

## Risks / Trade-offs

- [Agent SDK 的請求被當成 Claude Code，額度不給用] → C4 第一個跑；出現「Credit balance too low」就停止 SDK 路線其餘 probe，直接記為不通過。
- [reusable workflow 被用來注入指令] → prompt 只經環境變數進 shell；caller 範本限定權限；`repository_dispatch` 本來就只有持有部署者 repo 寫入權限的 token 能觸發。
- [issue 內文的 prompt injection 讓 agent 外洩 secret] → Agent SDK 路線設 `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`，Bash、hooks、MCP 子程序拿不到 `ANTHROPIC_API_KEY`；`GH_TOKEN` 依官方設計保留，風險由 caller 的最小權限與 job 生命週期限制。Managed Agents 路線的 API key 不進沙箱，`GH_TOKEN` 經 vault 在出口代換。部署說明寫明只在 issue 作者可信任的 repo 部署。
- [Managed Agents 的 repo resource token 在沙箱內可讀] → 該 token 不經 vault，可能出現在沙箱的 git 設定裡；task 5.2 量測是否可讀（只回報有無，不印值）；部署說明要求最短效期並在結束後撤銷。
- [選填的 PAT 比 GITHUB_TOKEN 活得久，而且以它產生的事件會觸發 workflow] → 背景安全審查（2026-10-15）指出兩點：agent 的 shell 看得到 `GH_TOKEN`（scrub 依設計保留），且持有 Contents 寫入權的 PAT 可以被 prompt injection 用來再送 dispatch、連鎖開新的 run。spike 期間接受此風險（sandbox 為 private、issue 作者只有使用者本人、PAT 只授權 sandbox 且 2026-10-17 到期；使用者決定不提前撤銷，見 findings〈PAT 處置〉）。正式 change 必須改成 PAT 不進 agent 的 session：agent 只 push branch，開 PR 與 merge 由 agent 結束後、不持有 API key 的 workflow 步驟以 PAT 執行。
- [Bash 沙箱在工作目錄留下佔位檔] → workflow 把不可能是專案內容的佔位 dotfile 寫進 `.git/info/exclude`；名稱像專案路徑的佔位（如 `scripts`）刻意不排除，記在 findings。
- [抓進 job 的程式碼被上游改動] → actions 與 superpowers、parallel-ai-agents 一律鎖 commit SHA，測試檢查；`claude-agent-sdk` 鎖版本但未鎖 hash，列為殘餘風險；`idd_ref` 由部署者在 caller 裡鎖定。
- [部署者的 caller 指向 `@main`，IDD 改版會直接影響他們] → caller 範本與文件建議鎖定 tag 或 commit；`idd_ref` 預設與文件說明一致。
- [gh 拒絕 vault 替換後的 token 格式] → 改以 `github_repository` resource 的 token 做 push，以 curl 帶 header 呼叫 REST API 開 PR 與 merge；兩種結果都記錄。
- [spike 花費失控] → Managed Agents 設 session budget；SDK 設 `--max-turns`；workflow 設 `timeout-minutes: 60`。每次端到端 run 前先跑最小 probe。
- [IDD 的 pre-flight 在 Managed Agents 上必然失敗] → 這本身就是 C1 要量測的結果；記錄失敗點，不為了通過而改 pre-flight。
- [IDD 的 presence pre-flight 在 Agent SDK 路線上失敗] → `check-plugin-presence.sh` 與 `check-ralph-loop.sh` 只在 `~/.claude/plugins/cache/` 找依賴，以本機路徑載入的 plugin 不在那裡（task 4.3 實測）。C1 已記錄這個失敗；為了量測後面的階段（C5、C7），workflow 設 `IDD_SKIP_PLUGIN_CHECK=1`，理由是 workflow 自己載入了每個依賴，每次 run 的 `LOADED_PLUGINS` 可證。正式修法是讓檢查認得以路徑載入的 plugin（另開 issue）。
- [superpowers 的固定 commit 會過時] → workflow 寫明它取自官方 marketplace 的條目；正式 change 再決定要不要在執行時讀 marketplace 取最新指定值。
- [Claude-only verify 漏掉只有跨模型才抓得到的問題] → 已接受的取捨；C7 只量測能否跑完與是否明示缺口。
- [實驗性流程隨 plugin 發佈到其他使用者手上] → 檔案只在被主動部署時才會執行；README 開頭標明實驗性與可能變動。

## Migration Plan

沒有資料遷移。spike 用的 fine-grained PAT 依使用者 2026-10-15 的決定不提前撤銷，2026-10-17 到期；sandbox repo 與其中的 `ANTHROPIC_API_KEY` secret 作為部署範例保留，是否移除由使用者決定。

## Open Questions

- Managed Agents 的 environment packages 能否直接裝到 gh，或必須下載 release binary。
- `/idd-all api` 的參數解析：idd-all 的 from-scratch mode 收自由文字，描述若剛好以「api」開頭會被誤判成 mode。正式 change 要決定以 `api` 為保留字（自由文字需加引號），或改成 `--api` 旗標；名稱維持使用者定的 `/idd-all api`。
