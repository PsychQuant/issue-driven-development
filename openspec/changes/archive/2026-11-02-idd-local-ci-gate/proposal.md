## Why

IDD 沒有本機 CI 路徑。#392 規劃的 close stage 要求 CI 全過，若只看遠端 CI，每張 issue 都要等遠端 runner（實測：一批 8 個 PR 的 Linux job 每輪約 30 分鐘）。維護者決定所有 repo 預設用本機檢查的結果，GitHub CI 有問題再另外處理（#465）。

## What Changes

- 新增 script `plugins/issue-driven-dev/scripts/idd-ci-gate.sh`：對指定 commit 建乾淨 checkout、跑本機 CI 指令、以結束碼回報通過或失敗，並產出一份紀錄。
- walk-up config（`.claude/.idd/local.json`）新增 `ci` 欄位：`mode`（`local` 預設、`remote`）、`command`、`timeout_seconds`（預設 3600）。
- 指令只來自這個 repo 本機未追蹤、屬於自己的 config；不往上層目錄找、不讀 repo 內其他檔案、不自動偵測。沒設定時 attended 停下來問（可列候選，確認後才寫入），unattended 停下回報。
- `idd-all` 在 verify 之後、開 PR 或收尾之前跑這個閘門，紀錄寫到 PR 或 issue comment。
- 遠端 CI 紅燈時回報但不擋合併；`idd-close` 的 distribution sync 在發版前仍要求遠端 CI 綠燈。

## Non-Goals

- 不重現遠端環境（舊版 Xcode、容器權限）：這類問題由發版前的遠端綠燈兜底。
- 不把 #392 的 close stage 併進這個 change；它之後呼叫本 script。
- 不跑 repo 內宣告的指令、不提供容器或 sandbox 隔離。
- 不處理 submodule 或依賴安裝，由使用者設定的指令自行處理。

## Capabilities

### New Capabilities

- `local-ci-gate`: 本機 CI 閘門的設定來源、執行、結果判定與紀錄，以及它與遠端 CI、發版的關係

### Modified Capabilities

（無）

## Impact

- 新增 `plugins/issue-driven-dev/scripts/idd-ci-gate.sh` 與 `plugins/issue-driven-dev/scripts/tests/idd-ci-gate/`
- 修改 `plugins/issue-driven-dev/references/config-protocol.md`、`plugins/issue-driven-dev/skills/idd-all/SKILL.md`、`plugins/issue-driven-dev/skills/idd-close/SKILL.md`
- 預設行為改變：沒設定 `ci.command` 的 repo，`idd-all` 跑到閘門會停下來
