## Why

IDD 的 target-resolution（`idd-issue` Step 0.5.E）目前只有兩條 branch：

| Branch | 條件 | 行為 |
|---|---|---|
| **E1** | `IS_FORK=false` | 直接用 origin、寫 config、**不詢問** |
| **E2** | `IS_FORK=true` + upstream | 3-option AskUserQuestion（upstream / own fork / both） |

「**clone 別人的 repo 當參考 / 教學 / 研究素材**」（origin owner ≠ 你、不是你的 fork、無 push 權）是 non-fork → 落進 **E1** → issue 預設導向**原作者的公開 repo**（GitHub 公開 repo 任何登入者都能開 issue），且 IDD config 被寫進對方 working tree，**零** non-pollution guidance。使用者得自己想到用 `.git/info/exclude` 才不會把工具檔留在對方 repo。

**Concrete incident**（本 change 起源，2026-06-26）：使用者 clone `kaochenlong/spectra-app` + `sherly-app`（HTTPS、無 push 權）當參考。手動設了 `.claude/.idd/local.json`（`pr_policy: never`）+ 在 `.git/info/exclude` 擋 `.claude/.idd/`，才避免污染原作者 repo。這套手動推導應內建為 IDD guidance。

**GitHub-side tracker**: #192

## What Changes

新增 Step 0.5.E 第三條 branch（third-party clone）+ 抽共用 ignore-block helper：

1. **Patch `idd-issue` Step 0.5.E** — 加 third-party detection（hybrid：owner-mismatch pre-filter → push-permission probe），偵測到 → 3-option routing（upstream / tracking repo / local-only），**排在 fork E2 之後、E1 之前**。
2. **Patch `references/config-protocol.md`** — mechanism 5 加 third-party 偵測條款 + 文件化「config-placement × ignore」決策矩陣。
3. **Patch `idd-config` init** — `/idd-config init` 提供同款 third-party setup。
4. **Patch `idd-all` Phase 0.5** — third-party clone → `pr_policy: never` 預設（無 push 權 → local direct-commit）。
5. **Extract shared `git-ignore-block-writer` helper** — idempotent marker-delimited block writer primitive，供 Stage 4.5 #55 carve-out（在 tracked `.gitignore` **re-include**）與本 feature 的 exclude writer（在 untracked `.git/info/exclude` **exclude**）共用；#55 既有行為**不退化**。

## Non-Goals

- **不自動建 tracking repo**（無 `gh repo create`）— 使用者用 `--target` / config 指定既有 repo。
- **不改變 fork（E2）行為** — third-party 排在 fork 之後，fork 邏輯原封不動。
- **不改 E1（你自己的新 repo）的 silent-write** — backward compat，common case 零退化。
- **不把 #55 與 third-party 的 ignore 操作併成單一 function** — 兩者方向相反（re-include vs exclude），只抽共同 primitive。
- **不解「co-maintained / vendored read-only」的灰色地帶** — 偵測用機械 proxy（push permission），灰色情境列為 residue（見 design Open Questions）。

## Capabilities

### New Capabilities

- `idd-third-party-clone-detection`: `idd-issue` Step 0.5.E 新增 third-party clone branch — hybrid 偵測（owner-mismatch cheap pre-filter → push-permission probe），偵測到時走 3-option routing（upstream / 自己的 tracking repo via `--target`+config / local-only），排序在 fork E2 之後、E1 之前；`/idd-config init` parity；backward compat 保證 E1 與 fork 路徑不變。
- `idd-third-party-config-placement`: 文件化並實作 config-placement × ignore-mechanism 矩陣 — third-party clone 預設 `.git/info/exclude` 擋 `.claude/.idd/` + `pr_policy: never`；`idd-all` Phase 0.5 對 third-party 套用 `pr_policy: never` 預設；config-protocol mechanism 5 收錄偵測條款。
- `git-ignore-block-writer-helper`: 抽出一個 idempotent、marker-delimited 的 git ignore-block writer primitive，以參數區分目標檔（`.gitignore` vs `.git/info/exclude`）與方向（re-include vs exclude）+ 處理 git「parent-dir-excluded」quirk；Stage 4.5 #55 carve-out 重構為呼叫此 primitive，行為位元等價。
