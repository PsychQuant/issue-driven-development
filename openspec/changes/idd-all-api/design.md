## Context

spike `cloud-idd-runtime-spike`（2026-10-15 封存，錨點 #400）選定 Agent SDK 跑在 GitHub Actions 作為雲端 IDD 的 runtime。spike 留下的狀態：

- reusable workflow、Agent SDK runner、caller 範本、部署說明都在 IDD repo 的實驗 branch 上，可以從 sandbox 端到端跑出 verified PR（sandbox PR #4）。
- 觸發方式是手送 `repository_dispatch`，它回 204、不回 run，呼叫方拿不到 run 連結。
- PsychQuant org 禁止 Actions 開 PR，spike 以一把只授權 sandbox 的 PAT（`IDD_GITHUB_TOKEN`）繞過。背景安全審查指出兩點：agent 的 shell 讀得到 PAT；PAT 有 Contents 寫入權，能送 `repository_dispatch` 連鎖開新的 run。
- 雲端 run 會在 commit 與 PR 加上 Claude 署名；gh-egress 的 mention 檢查缺 `markdown-it-py`；`max_turns` 預設 80 跑不完整條 idd-all（sandbox 改成 400 才跑完）。

使用者 2026-10-15 的兩個決定：PR 權限改由 org 設定給、不用 PAT；入口寫成 `/idd-all --api #N`。

## Goals / Non-Goals

**Goals:**

- 本機一個指令 `/idd-all --api #N` 就能讓那張 issue 在部署者 repo 的 Actions 跑完 idd-all、停在 verified PR，並立刻拿到 run 的連結。
- agent 手上只有 job token；caller 不留任何讓 agent 再觸發一次自己的入口。
- 部署者只需要：一份 caller workflow、一個 `ANTHROPIC_API_KEY` secret、允許 Actions 開 PR 的設定。
- 雲端 run 不加 Claude 署名、能跑 gh-egress、可選模型與輪數。

**Non-Goals:**

- 自動 merge 與結案：屬於 #392（`idd-all-merge-and-close`），雲端 run 仍停在 verified PR。
- presence 檢查認得路徑載入的 plugin（#403）：`IDD_SKIP_PLUGIN_CHECK` 暫時保留。
- `${CLAUDE_PLUGIN_ROOT}` 加大括號（#401）、IDD 狀態檔不弄髒部署者 repo（#404）：各自獨立處理，部署說明列為已知限制。
- 從自由文字建 issue 再上雲（from-scratch）：`--api` 只收已存在的 issue。
- Managed Agents 路線、GitHub Enterprise Server、Codex reviewer 上雲。
- 撤銷 spike 的 PAT：使用者決定留到 2026-10-17 到期；之後刪 keychain 與 sandbox secret 兩份，不在本 change 的 task 內。

## Decisions

### 入口是 idd-all 的 --api 旗標

**Supersedes**: cloud-idd-runtime-spike / 正式入口命名為 /idd-all api

idd-all 現有參數全是旗標（`--pr`、`--no-pr`、`--review`、`--cwd`、`--in-chain`），沒加旗標的自由文字是 from-scratch 的 issue 描述。用 `api` 當保留字會讓以 api 開頭的描述被誤判，所以採 `--api`（使用者 2026-10-15 確認）。

`--api` 只接受 from-issue（`#N`），與 `--no-pr`、`--in-chain`、`--review`、`--cwd` 互斥：前兩者要求 direct-commit，雲端只跑 PR；`--review` 要人在 terminal 接手，雲端沒有人；`--cwd` 指本機 clone，與雲端無關。`--pr` 可並用，等於沒加。

### 以 workflow_dispatch 送出並直接取回 run 連結

替代方案：`repository_dispatch`（spike 用的）回 204、不回 run；事後查 runs 列表在並發時會抓錯。

`workflow_dispatch` 端點帶 `return_run_details: true` 時回 200 與 `workflow_run_id`、`run_url`、`html_url`；不帶時回 204。2026-10-15 對 sandbox 實測兩次都符合（不帶：run 38711152595 回 204；帶：run 38711228550 回 200 與三個欄位；兩個 run 都在安裝 SDK 前取消）。依據是 GitHub REST OpenAPI 描述中該端點的 `return_run_details` 參數。

送出時用本機 `gh` 的登入身分；目標 repo 是 idd-all 解析出的 issue 所在 repo（也就是部署了 caller 的 repo），workflow 檔名固定為 `idd-cloud.yml`，ref 是該 repo 的預設 branch。

### agent 只拿 job token，PR 權限由部署者的 Actions 設定給

替代方案一：PAT 留在 session，靠 caller 只留 `workflow_dispatch` 擋連鎖觸發。被拒：agent 的 shell 仍讀得到 PAT，被 prompt injection 讀走後，PAT 效期內 repo 都能被寫。
替代方案二：PAT 不進 session，PR 由 agent 結束後的 workflow 步驟開。被拒：idd-all 要多一個「沒有 PR 也能跑 verify」的雲端分支，#392 的 merge 與結案也得拆成兩段。

採用：reusable workflow 不再宣告 `IDD_GITHUB_TOKEN`，`GH_TOKEN` 只取 job token。job token 在 job 結束時失效、權限由 caller 的 `permissions` 決定。部署者 repo 必須允許 GitHub Actions 開 PR；個人帳號的 repo 在 repo 設定開，org 的 repo 要在 org 設定開（spike 時 repo 層無法覆寫 org 的禁止，API 回 409）。PsychQuant 依使用者決定改 org 設定。

### caller 只留 workflow_dispatch 觸發

GitHub 的規則：job token 產生的事件不會開新的 workflow run，例外正是 `workflow_dispatch` 與 `repository_dispatch`。送 `repository_dispatch` 只需要 Contents 寫入權，caller 給 agent 的 job token 正好有；送 `workflow_dispatch` 需要 Actions 寫入權，caller 不給。所以 caller 拿掉 `repository_dispatch`、`permissions` 不含 `actions`，agent 就無法再開一個自己。

### 雲端 run 一律以 --pr 跑 idd-all

送出的 prompt 固定為 `/issue-driven-dev:idd-all #N --pr`。不加 `--pr` 時，部署者 repo 的 `pr_policy` 若是 direct-commit，雲端 run 會直接 commit 到預設 branch。`--pr` 解析為 (PR, unattended)，與雲端沒有人回答問題的事實一致。

### 送出邏輯放在獨立的 dispatch 腳本

idd-all 的 SKILL.md 只負責解析旗標與呼叫腳本；組請求、驗證、錯誤翻譯放在 `plugins/issue-driven-dev/cloud/dispatch.sh`，可以用 `--dry-run` 在沒有網路與 token 的 CI 測試。

### 模型與輪數由 caller 決定

caller 的 `workflow_dispatch` 輸入 `model`（預設空字串，即 SDK 預設模型）與 `max_turns`（預設 400），由部署者在 caller 檔裡改預設值。`/idd-all --api` 只送 `prompt`，不另開 `--model` 旗標。reusable workflow 的 `max_turns` 預設也改為 400：spike 的端到端在 sandbox 設 400 才跑完；`timeout-minutes: 60` 仍是上限。

### 雲端 run 關閉 Claude 署名

Claude Code 的 `attribution.commit` 與 `attribution.pr` 設為空字串即不加署名（官方 settings reference）。runner 以 SDK 的 `settings` 選項傳入 `{"attribution": {"commit": "", "pr": ""}}`，不依賴部署者 repo 的 `.claude/settings.json`。

### gh-egress 的 Python 依賴裝在無 key 的步驟

`mention_scan_text.py` 只接受 `markdown-it-py` 4.0.0 與 `linkify-it-py` 2.0.3（版本不符即拒絕）。兩者與 SDK 一起在「安裝」步驟以固定版本安裝；那個步驟不持有 API key。

### 移除 Managed Agents launcher

該路線未獲選；留著等於維護一份不會被用到、又持有憑證處理邏輯的程式。紀錄與程式碼留在封存的 spike change 與 git 歷史。

## Implementation Contract

**`plugins/issue-driven-dev/cloud/dispatch.sh`**

- 介面：`dispatch.sh --repo OWNER/REPO --issue N [--ref REF] [--dry-run]`。
- 驗證：`--repo` 須符合 `^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$`；`--issue` 須為正整數；`--ref` 不得以 `-` 開頭、只含字母數字與 `._/-`。不符即 exit 2，stderr 說明哪個參數錯。
- `--dry-run`：不連網、不讀 token。stdout 印出 `POST /repos/OWNER/REPO/actions/workflows/idd-cloud.yml/dispatches` 與 JSON body：`ref`（未給 `--ref` 時印 `(default branch)`）、`inputs.prompt` 為 `/issue-driven-dev:idd-all #N --pr`、`return_run_details: true`；exit 0。
- 正式送出：先確認 issue 存在且為 OPEN（否則 exit 1，不送出）；未給 `--ref` 時讀 repo 的預設 branch；以 `gh api` 送出。成功時 stdout 只有一行 `html_url`，exit 0。
- 錯誤（都不送第二次、不印 token）：`gh` 不存在 → exit 64；HTTP 404 → 說明 `.github/workflows/idd-cloud.yml` 不存在於該 repo、指向部署說明；HTTP 403 → 說明本機 gh 身分缺該 repo 的 Actions 寫入權；HTTP 422 → 說明 caller 的輸入與預期不符（caller 過舊）；其他 → 原樣轉印 gh 的錯誤；以上皆 exit 1。

**idd-all `--api`**

- Phase 0 解析 `--api`。與 `--no-pr`、`--in-chain`、`--review`、`--cwd` 並用即 abort，訊息點名衝突的旗標；from-scratch（自由文字）或沒有 issue 編號即 abort，提示先建 issue。
- target repo 解析照舊；之後若有 `--api`，呼叫 `dispatch.sh --repo "$GITHUB_REPO" --issue N`，印出 run 連結與「雲端 run 會停在 verified PR」，然後結束。不建立 Phase 1 之後的 task、不切 branch、不動本機工作目錄。
- argument-hint 與使用表加上 `--api`。

**reusable workflow `.github/workflows/idd-cloud-run.yml`**

- 觸發仍只有 `workflow_call`。inputs：`prompt`（必填）、`idd_ref`（預設 `main`）、`model`（字串，預設空）、`max_turns`（預設 400）、`dry_run`（預設 false）。secrets：只有 `ANTHROPIC_API_KEY`。
- `GH_TOKEN` 只取 `github.token`。
- 安裝步驟以固定版本裝 `claude-agent-sdk`、`markdown-it-py==4.0.0`、`linkify-it-py==2.0.3`。
- `model` 經環境變數傳給 runner；所有 input 都經 `env:` 進 shell，`run:` 內不出現 `${{ }}`。
- 標頭註解拿掉 EXPERIMENTAL，改指向部署說明的「已知限制」。

**runner `plugins/issue-driven-dev/cloud/sdk_run.py`**

- 新增 `--model`（空字串或未給 = 不傳 model）。
- 一律以 `settings` 傳入 attribution 為空字串的設定。
- `--dry-run` 的輸出列出 `MODEL:` 與 `SETTINGS:`，其餘行為不變。

**caller 範本 `plugins/issue-driven-dev/cloud/caller-example.yml`**

- 只有 `workflow_dispatch`，輸入 `prompt`（必填）、`model`、`max_turns`、`dry_run`；沒有 `repository_dispatch`。
- `permissions` 只有 contents、issues、pull-requests 的 write；沒有 `actions`。
- secrets 只明確傳 `ANTHROPIC_API_KEY`；沒有 `secrets: inherit`、沒有 `IDD_GITHUB_TOKEN`。
- `uses:` 與 `idd_ref` 鎖同一個 tag 或 commit。

**驗收**

- `plugins/issue-driven-dev/scripts/tests/cloud-runtime/test.sh` 全數通過，至少涵蓋：dispatch 的 dry-run 輸出與參數拒絕；workflow 不含 `IDD_GITHUB_TOKEN`、含 `model` 輸入、安裝兩個 Markdown 套件且版本正確、`run:` 內無 `${{ }}`；caller 無 `repository_dispatch`、無 `actions` 權限；runner dry-run 印出 attribution 為空的設定；`ma_run.sh` 不存在。
- 端到端：在 sandbox 對一張新 issue 執行 `/idd-all --api #N`，本機印出 run 連結；該 run 開出的 PR 作者是 `github-actions[bot]`；commit 與 PR 沒有 Claude 署名；verify 報告寫明 Codex reviewer 沒跑；記錄費用與耗時。

**範圍**

- In：上列五個檔案、idd-all SKILL.md、部署說明、測試、CHANGELOG 與版本號、PsychQuant org 的 Actions 設定、sandbox 的 caller。
- Out：Non-Goals 所列各項；idd-all 在本機的其他 mode 行為不變。

## Risks / Trade-offs

- [PsychQuant 放寬後，org 內每個 workflow 都能開 PR 與 approve PR；org 的 `default_workflow_permissions` 目前是 write，沒寫 `permissions` 的 workflow 也拿得到寫入權] → 這是使用者接受的取捨；task 執行前再確認一次，並在部署說明建議 org 把預設權限改成 read、需要寫入的 workflow 自己宣告。改預設權限不在本 change 範圍。
- [agent 的 shell 讀得到 job token] → token 在 job 結束時失效、權限只有 caller 給的三項；caller 不留讓它觸發自己的入口。
- [部署者 repo 裡其他監聽 `repository_dispatch` 的 workflow 仍可被 agent 觸發] → 部署說明寫明此風險，建議那類 workflow 改用 `workflow_dispatch`。
- [presence 檢查仍被略過、狀態檔仍會留在工作目錄（#403、#404）] → 部署說明列為已知限制並附 issue 編號。
- [spike 期間的 sandbox caller 仍傳 `IDD_GITHUB_TOKEN`] → sandbox caller 在 task 中改成正式版；reusable workflow 不再宣告該 secret 後，舊 caller 傳入它會讓 workflow 驗證失敗，所以更新 caller 與鎖新版本要同一步完成。

## Migration Plan

1. 合併前：在 sandbox 以實作 branch 的 commit 鎖定 caller，完成端到端驗收。
2. 改 PsychQuant org 設定：讀出目前的 `default_workflow_permissions`，只把 `can_approve_pull_request_reviews` 改成 true，其餘照舊。
3. 合併後：sandbox caller 改鎖合併後的 tag 或 commit。
4. 回退：org 設定改回 false；caller 改回舊的鎖定版本。sandbox 的 PAT secret 在 2026-10-17 前仍在，必要時可回到 spike 版 caller。

## Open Questions

（無。版本號在合併時依 main 當下的版本決定。）
