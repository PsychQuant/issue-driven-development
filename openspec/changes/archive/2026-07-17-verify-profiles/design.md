# Design: verify-profiles

## D1 — Profile 是四元組，reference 檔是 single source

一個 profile = `(lens set, DA focus, 輸入源預設, freshness 機制)` 四元組，全部定義在新 canonical reference `references/verify-profiles.md`。SKILL.md 引用該檔、不內嵌 lens 文本複本（同 #137 registry 的反 typo-drift 紀律：多 site 引用同一文本時，單一 source + 引用，drift-guard 鎖逐字）。內建三個 profile：

| Profile | Lenses | 輸入源預設 | Freshness |
|---------|--------|-----------|-----------|
| `code`（預設） | requirements / logic / security / regression（今日文本，逐字不動） | git auto-detect（diff / PR / commits / branch） | #228 FROZEN_SHA vs HEAD（不動） |
| `prose` | factual-accuracy-vs-source / requirements-format-compliance / pii-phi-leak / citation-support | `--file` / `--dir`（必填其一） | file SHA-256 snapshot |
| `academic` | prose 四軸 + reviewer-defense 強化（DA focus 改學術審稿人姿態） | 同 prose | 同 prose |

prose / academic 的 lens 文本以 #258 Provenance 中使用者已驗證的即興映射為底稿（Logic→事實正確性、Security→PII、Requirements→範本合規、Regression→引用佐證）。

## D2 — 輸入源抽象掛在既有 Step 0.5 resolution algorithm

`--file <path>` / `--dir <path>` 加入 Step 0.5 的 input-source resolution，與 `--pr` / `--commits` / `--branch` / `--since` **互斥**（同時給 → abort with usage）。規則：

- `--profile prose|academic` 且無輸入源 flag → **abort** 要求 `--file` / `--dir`（不 fallback git — 非 code deliverable 對 git diff 無意義）
- `--profile code`（或缺省）→ 既有 auto-detect 鏈逐 byte 不變
- `--file` / `--dir` 模式下不做 `git checkout` / branch restore（無 git 假設）；GitHub posting target（master comment 落點 issue）仍照 config-protocol 解析 — 「git repo optional」指工作樹，不指 issue tracker

ensemble 的 `diffFile` 參數在 file 模式下裝的是**檔案內容 bundle**（單檔直接放、`--dir` 遞迴串接並以 `=== FILE: <relpath> ===` 分隔），agents 用 file-read tool 讀，與 diff 路徑同管道。

## D3 — File-based freshness gate（#228 等價物，不豁免）

#228 的 gate 語意是「verdict 必須對應 verify 當下的 snapshot」。git 模式錨點是 FROZEN_SHA vs HEAD；file 模式的等價物：

1. ensemble 啟動前：對每個輸入檔算 SHA-256，記 `FROZEN_HASHES`（含檔案清單）
2. aggregate / post master comment 前：重算比對；任何 mismatch（含檔案增刪）→ **refuse** post verdict，印 stale-snapshot 訊息 + 重跑指令
3. 這是 MUST gate，與 git 模式同級 — 不因「檔案不在 git」而靜默豁免（#258 Risks 第一條）

## D4 — Repo-local 自訂 profile：內建名不可 shadow

config `verify_profiles`（`.claude/.idd/local.json`）schema：

```json
{
  "verify_profiles": {
    "clinical": {
      "lenses": [{"key": "phi-leak", "focus": "..."}, {"key": "fact-vs-chart", "focus": "..."}],
      "da_focus": "...",
      "input": "file"
    }
  }
}
```

- 自訂名與內建（`code` / `prose` / `academic`）**碰撞 → 內建勝 + 印 warning**（fail-safe：內建是行為契約，config 不得靜默改寫；特別是 `code` 的 backward-compat 保證）
- `lenses` 至少 1 個、`da_focus` 必填、`input` ∈ {`file`,`git`}；schema 不合 → 該 profile 忽略 + warning（absent-safe，不 abort）
- 未知 `--profile` 名（內建與 config 都查無）→ abort with 可用 profile 清單（fail-loud — 與 `sdd_bias` 的靜默降級不同：`--profile` 是顯式 per-invocation 意圖，typo 靜默跑錯 profile 比失敗更糟，同 IDD_AGENT_MODEL 的 fail-loud 判準）

## D5 — 兩個 backend 同時支援

profile dispatch 在 Step 2 backend 解析鏈**之前**組裝：pai canonical tier 把 lens 四元組填進 `customLenses` + `daFocus`（primitive 已支援）；manual fan-out tier 把同一組 lens 文本填進 4 個 Agent prompt + DA prompt。兩 backend 消費同一 reference 檔的文本 → findings contract / master report 結構不變，Step 3 之後完全 backend-agnostic + profile-agnostic。

## Alternatives considered

- **每個 deliverable type 各開一個新 skill**（`idd-verify-prose` …）：拒絕 — skill 數爆炸、共用機制（gates、posting、triage）全複製，違反 deep-integration 反複製判準。
- **讓操作者繼續手動重映射**：拒絕 — 即是 #258 要消除的不可複現性。
- **自訂 profile 可 override 內建**：拒絕 — `code` 是既有 caller 的行為契約；config 靜默改寫 = 不可預期品質。
