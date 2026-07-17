# Proposal: verify-profiles

## Why

`idd-verify` 的 4 個 ensemble lens（requirements / logic / security / regression）與輸入源（git diff / `--pr` / `--commits` / `--branch`）在 skill 層被寫死成 code review + git repo。非 code deliverable（學術 / 臨床 prose、信件、報告）或非 git workspace 上使用時，操作者只能臨場手動重映射 lens 並繞過 diff 機制 — 不可複現、不可稽核、且可能靜默失去「獨立交叉驗證」保證（#258）。而 composability primitive 其實已存在於 engine 層（pai-ensemble 接受 `profile: 'custom'` + `customLenses` + `daFocus` + `diffFile`），只是沒有在 skill 層暴露。

## What Changes

1. **`--profile <name>` flag**（`code` 預設 / `prose` / `academic`）：同時切換 lens 組合與輸入源 adapter。`code` = 今日行為，逐 byte 不變（backward compatible）。
2. **輸入源抽象 `--file <path>` / `--dir <path>`**：與既有 `--pr` / `--commits` / `--branch` 平行的新輸入源；git repo 變 optional（GitHub posting target 仍照 config-protocol 解析）。
3. **File-based freshness gate**：#228 diff-freshness gate 的檔案輸入等價物 — ensemble 啟動時 snapshot 輸入檔 SHA-256，aggregate/post 前重算，mismatch → refuse stale verdict。**不得靜默豁免**。
4. **Repo-local 自訂 profile**：config（`.claude/.idd/local.json`）新 `verify_profiles` 欄位，讓專案註冊自己的 lens 軸。
5. **新 canonical reference `references/verify-profiles.md`**：profile 定義（lens 文本、DA focus、輸入源、freshness）的 single source of truth；SKILL 引用不內嵌複本。

## Non-Goals

- diagnose / implement 的 profile 化（#258 Residue — verify 先行，成功後再議）
- 內建 `data` profile（v1 先 code/prose/academic；其他軸走自訂 profile 機制）
- 動 pai-ensemble engine（`customLenses` primitive 已存在；本案只在 skill 層組裝參數）
- 改變 `code` profile 的任何行為（lens 文本、輸入源 auto-detect、#228 git freshness gate 全部不動）

## Impact

- Affected specs: `idd-verify`（ADDED requirements）
- Affected code: `skills/idd-verify/SKILL.md`、新 `references/verify-profiles.md`、`references/config-protocol.md`、新 drift-guard suite `scripts/tests/verify-profiles/`
- 使用者可見：`idd-verify --profile prose --file <path>` 成為 first-class 可稽核路徑

## Refs

Issue #258（Spectra opt-out → propose；方向 / flag 名 / profile 集 / backward-compat / config 機制由 issue 自書定案）
