# Findings: cloud-idd-runtime-spike（草稿，實測進行中）

錨點：#400。部署範例與測試目標：private repo `PsychQuant/idd-cloud-sandbox`（seed issue #1）。API key：che830621 組織（Max 附送額度，17 日重置）。

## 矩陣

結果值：`pass`／`fail`／`partial`／`not measured`。沒有證據的格子一律 `not measured`。

| 準則 | Agent SDK on GitHub Actions | Managed Agents |
|---|---|---|
| C1 plugin 載入 | not measured | not measured |
| C2 GitHub 寫入 | not measured | not measured |
| C3 API 觸發 | partial — dispatches API 觸發 dry run 成功（見 C8 證據）；尚未以真實 run 量測 | not measured |
| C4 Max API 額度 | not measured | not measured |
| C5 成本與時間 | not measured | not measured |
| C6 工具可用性 | not measured | not measured |
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

## 待記錄的觀察

- 背景安全審查（2026-10-15）：prompt injection 可能讀到 agent 環境變數中的 key、未鎖版本的程式碼與 key 同 job → 已以 `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1` 與全面鎖 SHA 處理（IDD commit `f54ef3e`）。Managed Agents 的 repo resource token 是否在沙箱內可讀，待 task 5.2 量測。
- IDD 的 `check-plugin-presence.sh` 只在 `~/.claude/plugins/cache/` 找依賴 plugin；以本機路徑載入時預期 C1 的 pre-flight 失敗，待 task 4.3 確認。
