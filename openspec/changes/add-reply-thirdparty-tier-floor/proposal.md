## Why

reply 型（v2.100.0，#269）是唯一逐字重製第三方原文的 comment 型別，但 `SCRUB_LEVEL` 是 repo-visibility-keyed——reply 的典型情境（第三方逐字內容貼到使用者自己的 repo）落在 WARN / LIGHT、永不 ENFORCE；layer-3（使用者貼上的外部原文）是新第三方內容首次進 remote 的唯一通道，目前只靠 prose「heightened 自審」（#269 verify DA-3 判為必要不充分）。

## What Changes

- `rules/privacy-scrubbing.md` 新增 normative 段「Reply layer-3 payload tier floor」：`points-from=user-pasted` 的 reply egress 不適用 LIGHT——最低 WARN＋顯式使用者確認（不論 repo visibility）；unattended context 下不 post（refuse＋說明，留待 attended）
- `skills/idd-comment/SKILL.md` R1/R4：layer-3 source 時 attended → AskUserQuestion 顯式確認第三方逐字內容可進 remote；unattended → refuse post。取代 v2.100.0 的「heightened 自審」prose
- `scripts/gh-egress.sh` 機械 net item 4（3→4，本案即 rules 要求的 separate change）：SCAN 含 `type=reply` 且 `points-from=user-pasted` 且 attested=`light` → exit 13 band refuse。僅偵測 IDD 自產 metadata marker token，零 semantic matching——net 邊界紀律不變
- 測試：gh-egress suite 新斷言（refuse / pass 兩向）＋ idd-comment-reply suite 新斷言（SKILL 手續字句）
- **比例原則邊界**：layer 1（comment URL）/ layer 2（issue-body）內容本已在 repo remote、無新增暴露 → 維持 repo-tier 預設，不受本案影響

## Non-Goals

- 不把 reply 全部 payload（layer 1/2）拉 tier——過度（無新增暴露）
- 不做 unattended draft 持久化檔案（YAGNI；refuse＋說明即可）
- 不擴 mechanical net 為 semantic 偵測（rules 檔明文禁止；item 4 限自產 marker token）
- 不動 in-flight `add-privacy-scrubbing-gate` 的未完成 tasks（rules 檔僅 append 新段）
- 不涵蓋 PR body / Discussions 等其他 human-facing 輸出面的同類問題（horizon 另案）

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `idd-comment-reply`: MODIFIED Points-source resolution（layer-3 綁 tier floor）＋ ADDED requirement「Layer-3 third-party payload tier floor」（rules 段、SKILL 手續、gh-egress 機械 backstop 三件套的 normative 契約）

## Impact

- Affected specs: `idd-comment-reply`（delta：1 MODIFIED + 1 ADDED requirement）
- Affected code:
  - New: (none)
  - Modified: plugins/issue-driven-dev/rules/privacy-scrubbing.md, plugins/issue-driven-dev/scripts/gh-egress.sh, plugins/issue-driven-dev/skills/idd-comment/SKILL.md, plugins/issue-driven-dev/scripts/tests/gh-egress/test.sh, plugins/issue-driven-dev/scripts/tests/idd-comment-reply/test.sh, plugins/issue-driven-dev/CHANGELOG.md, plugins/issue-driven-dev/.claude-plugin/plugin.json, .claude-plugin/marketplace.json
  - Removed: (none)
