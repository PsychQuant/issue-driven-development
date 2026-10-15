## Why

使用者要能用一次 API 呼叫送出一張新的 `/idd-all`，在雲端跑完整個 IDD（issue → diagnose → implement → verify → PR → merge → close），不需要本機開著（#400）。官方文件顯示沒有一條路線能原樣跑 IDD plugin、同時又由 Max 附送的 API 額度付費：Managed Agents 吃額度但不載入 plugin，Agent SDK 能載入 plugin 但計費歸屬沒有文件。兩條的卡點都只能實測，所以先 spike，再開正式 change。

部署形狀在 spike 開始時就定下：流程放在 IDD repo、跟 plugin 一起維護；API key 與幾行呼叫設定留在部署者自己的 private repo。這樣其他使用者也能把雲端 IDD 部署到自己的 GitHub，key 不會離開他們的 repo。

## What Changes

- 在 IDD repo 新增雲端執行流程（實驗性，隨 plugin 發佈）：
  - Agent SDK 路線：一份 reusable workflow（`on: workflow_call`），由部署者 repo 的 caller workflow 呼叫；一支 Python 執行腳本，從本機路徑載入 IDD 與它的三個依賴 plugin（superpowers、parallel-ai-agents、codex-pro）。
  - Managed Agents 路線：一支 shell launcher，以 Claude API 建立 environment、agent、session，掛載目標 repo 與 IDD repo，並讀取 session 事件。
  - 一份部署說明與一份 caller workflow 範本，讓部署者只需提供自己的 key 與 repo。
  - 一支測試，確認腳本的 dry-run 輸出不含任何 secret，且 reusable workflow 不讀取 IDD repo 自己的 secret。
- 以 private repo `PsychQuant/idd-cloud-sandbox` 當第一個部署範例與測試目標：key 存在它的 secret，spike 的測試 issue、PR、merge 只做在它上面。
- 依固定的八項準則（C1–C8）實測兩條路線，含 Max API 額度是否被扣、GitHub 寫入能做到哪一步、每次 run 的費用與時間，以及別人能否只靠自己的 key 與 repo 完成部署。
- 產出 findings 與決策紀錄，選定一條路線（或兩條都不選並說明原因），並把摘要貼回 #400。
- 記錄已定案的方針：雲端 verify 只用 Claude，報告必須明寫少了 Codex 那一條；正式入口名稱為 `/idd-all api`（正式 change 才實作，本 change 的流程是它背後要呼叫的那一層）。

## Capabilities

### New Capabilities

- `cloud-runtime-spike`: 雲端 runtime 候選的評估準則、流程與 secret 的分工、spike 執行的隔離與憑證規則，以及決策紀錄的必要內容。

### Modified Capabilities

(none)

## Impact

- Affected specs: `cloud-runtime-spike`（新增）
- Affected code:
  - New: .github/workflows/idd-cloud-run.yml
  - New: plugins/issue-driven-dev/cloud/sdk_run.py
  - New: plugins/issue-driven-dev/cloud/ma_run.sh
  - New: plugins/issue-driven-dev/cloud/caller-example.yml
  - New: plugins/issue-driven-dev/cloud/README.md
  - New: plugins/issue-driven-dev/scripts/tests/cloud-runtime/test.sh
  - New: openspec/changes/cloud-idd-runtime-spike/findings.md
- 外部系統：private repo `PsychQuant/idd-cloud-sandbox`（已建立，含 seed issue #1 與 `ANTHROPIC_API_KEY` secret）、只持有 Max API 額度的 Console 組織（che830621）、GitHub Actions minutes。
- IDD repo 只透過一般的 commit 新增上述流程檔；spike run 不在 `PsychQuant/issue-driven-development` 開 issue、留言、push 或 merge，IDD repo 也不存放任何 API key。
- 相關 issue：#400（本張的錨點）、#392（idd-all 自動 merge 與 close；雲端 run 的終點沿用它）。
