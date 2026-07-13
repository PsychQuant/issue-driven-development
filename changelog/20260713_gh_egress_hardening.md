# 2026-07-13 — gh-egress 硬化 cluster + idd-edit batch 語意（v2.96.0）

## 已 merge 至 main（PR #256 cluster + PR #257）

- **#227 exit-code band ≥10**（`ed0b738`）：wrapper-origin 碼全遷專屬帶（10 privacy / 11 mention / 12 unscannable / 13 attestation / 14 usage）；不變式「wrapper 絕不自行 exit <10」→ `$?` 可分流 gate-refusal vs gh-failure。
- **#225 python3 統一掃描**（`82c948f`）：消滅 jq/no-jq 雙路徑分歧；taxonomy = projects keys ∪ sensitive-key path values；fail-closed 寬網。
- **#226 Phase 2 rollout**（`8c01d13`）：6 skill comment/edit egress 全接線 gh-egress（attestation + mention net 機械生效）；rollout drift-guard 24 assertions。
- **#158 idd-edit batch × R5**（`dda0cfc`）：per-comment refuse + 繼續、Step 7.5 outcome report、exit 4 iff any refused；fixture 14。

四 issue 均已 close（獨立 closing summaries）。**v2.96.0** 同日發版。

CLAUDE.md：無需更新 — 皆 plugin 內部變更。
