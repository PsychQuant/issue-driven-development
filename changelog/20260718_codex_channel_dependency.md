# 2026-07-18 — codex 通道完全依賴化（v2.98.0，跨三 repo）

## 已 merge 至 main（PR #265）

- **#264 codex channel full-dependency**（`228763d`，Spectra `codex-channel-dependency`）：使用者裁決「完全依賴，跟 superpowers 一樣」。vendored `bin/codex-call` **刪除** — divergence audit 證實它落後 pai 2.18.0 四個安全/正確性修正（token-exp NSNumber parse、OAuth 檔 umask 0o077、form-encoding escape、flock 後 re-read），切換即淨升級。executable 歸 pai（`PAI_CODEX_CALL`，`MIN_PAI` → 2.19.0）；治理歸 codex-pro（`MIN_CODEX_PRO=0.7.0`：`defaults.json` 起底 + profile.yaml 兩層，fail-fast 無 soft fallback）；三處呼叫帶顯式治理值；IDD 樹內**零 model pin**。dependencies + `allowCrossMarketplaceDependenciesOn` + pre-flight 逐項對齊 superpowers 形狀（#209）。

## 上游先行（皆已 ship + 結案）

- **codex-pro 0.7.0**（their issue 7，`98c1b59`）：EXTERNAL-CONSUMER CONTRACT 官方化 — `profile-contract.md` + 機器可讀 `defaults.json`；5 個 skill prose 表加鏡像註記
- **pai 2.19.0**（their issue 22）：`codexModel`/`codexEffort` additive 契約 args；未傳參 caller 逐 byte 不變

#264 已依 close ritual 結案（summary + body sync + dashboard）；Spectra change 已 archive（idd-verify spec +1 requirement）。`model-generation-sync` 重塑 v2 契約（RED 17/8 → GREEN 25/0）；全 sweep **36 suites 0 fail**。**v2.98.0** 同日發版，三個 marketplace（issue-driven-development / codex-pro / parallel-ai-agents）皆已同步。

CLAUDE.md：無需更新 — 皆 plugin 內部與依賴接線變更。
