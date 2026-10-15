## Why

使用者要能用一次呼叫把一張 issue 送去雲端跑完整個 IDD，不必本機開著（#400）。spike `cloud-idd-runtime-spike`（已封存）實測兩條路線後選定 Agent SDK 跑在 GitHub Actions：它真的載入 IDD 與依賴 plugin、保有 Skill／Agent／TaskCreate／Workflow，費用由 Max 附送額度支付。spike 的程式只在實驗 branch 上，入口也還是手打 API 請求；這個 change 把它變成正式功能，並一併處理 spike 留下的安全與相容缺口。

## What Changes

- `/idd-all --api #N`：idd-all 新增 `--api` 旗標。它不在本機跑 pipeline，只對 issue 所在 repo 的 caller workflow 送一個 `workflow_dispatch` 請求（帶 `return_run_details`），印出 run 的連結後結束。雲端那一端固定以 `--pr` 跑 idd-all，也就是 (PR, unattended)。
- 新增本機端的送出腳本：組請求、驗證參數、把 GitHub 的錯誤翻成部署說明裡對應的步驟。
- reusable workflow 與 Agent SDK runner 由實驗版轉為正式版：
  - **BREAKING**（對 spike 期間的部署者）：移除選填的 `IDD_GITHUB_TOKEN` secret，agent 只拿 job token；部署者 repo（或其 org）必須允許 GitHub Actions 開 PR。
  - 新增 `model` 輸入；`max_turns` 預設值提高到足以跑完整條 idd-all。
  - 安裝 gh-egress 需要的 `markdown-it-py` 與 `linkify-it-py`（鎖定 IDD 要求的版本）。
  - 雲端 run 關閉 commit 與 PR 的 Claude 署名。
- caller 範本只留 `workflow_dispatch` 一種觸發，輸入為 `prompt`、`model`、`max_turns`、`dry_run`；拿掉 `repository_dispatch`。
- 部署說明改寫成正式版：允許 Actions 開 PR 的設定、caller 範本、以 `/idd-all --api` 觸發、已知限制。
- **BREAKING**（對 spike）：移除 Managed Agents 的 launcher 及其測試；該路線未獲選，紀錄留在封存的 spike 裡。
- PsychQuant org 改成允許 GitHub Actions 開 PR（使用者 2026-10-15 的決定），sandbox 改用正式版 caller 做端到端驗收。

## Capabilities

### New Capabilities

- `cloud-idd-run`: 以 `/idd-all --api` 把一張 issue 送到部署者 repo 的 GitHub Actions，由 Agent SDK 載入 IDD 跑完 idd-all 並開 PR；涵蓋觸發、權限、憑證、caller 範本與雲端 verify 的降級聲明。

### Modified Capabilities

(none)

## Impact

- Affected specs: `cloud-idd-run`（新增）
- Affected code:
  - New: plugins/issue-driven-dev/cloud/dispatch.sh
  - Modified: .github/workflows/idd-cloud-run.yml, plugins/issue-driven-dev/cloud/sdk_run.py, plugins/issue-driven-dev/cloud/caller-example.yml, plugins/issue-driven-dev/cloud/README.md, plugins/issue-driven-dev/scripts/tests/cloud-runtime/test.sh, plugins/issue-driven-dev/skills/idd-all/SKILL.md, plugins/issue-driven-dev/CHANGELOG.md, plugins/issue-driven-dev/.claude-plugin/plugin.json, .claude-plugin/marketplace.json
  - Removed: plugins/issue-driven-dev/cloud/ma_run.sh
- 外部系統：PsychQuant org 的 Actions 設定（允許 workflow 開 PR）；private repo `PsychQuant/idd-cloud-sandbox` 的 caller workflow。
- 相關 issue：#400（錨點）；#401、#403、#404 與 #392 各自獨立處理，見 design 的 Non-Goals。
