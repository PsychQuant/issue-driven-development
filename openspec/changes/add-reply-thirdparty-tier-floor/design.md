## Context

privacy-scrubbing 契約（v2.87–2.96 已 ship）的 tier 由 repo visibility 決定；gh-egress.sh 的 mechanical net 限 3 個 zero-tolerance items 且 rules 檔明文「不得長成 semantic pattern set、增長需 separate change」。reply 型（v2.100.0）逐字重製第三方原文，marker `<!-- idd:comment type=reply ... points-from={comment-url|issue-body|user-pasted} calibrated={yes|no} -->` 是 IDD 自產結構化 token。#269 verify DA-3：own-repo 情境永不 ENFORCE，layer-3 只有 prose 自審，必要不充分。in-flight change `add-privacy-scrubbing-gate` 尚有 11 open tasks、標的同兩檔。

## Goals / Non-Goals

**Goals:**

- layer-3（user-pasted）reply payload 的 tier floor：機械可執行、不論 repo visibility
- net 邊界紀律不破：新 item 僅 token matching（自產 marker），零 semantic
- 與 in-flight change 疊層不衝突（rules 檔 append-only）

**Non-Goals:**

- layer 1/2 tier 變更、unattended draft 持久化、semantic 偵測、其他 human-facing 輸出面

## Decisions

**D1 — floor 只綁 layer 3，不綁整個 reply。** layer 1/2 的內容本已在同 repo remote（issue body / comment），重引零新增暴露；全 reply 拉 tier 會把日常 advisor 回覆全部拖進 confirm 流程（比例原則違反、user 明示要評估的軸）。替代案「全 reply enforce」被否。

**D2 — 機械 backstop 檢測『自產 marker token』，不是內容。** gh-egress 新 item 4 的判準：SCAN 同時含字串 `type=reply` 與 `points-from=user-pasted`（兩 token 同在 metadata marker 慣例內）且 `$ATTESTED = light` → exit 13（attestation band：這是「attested level 對此 payload 無效」，不是 content leak 的 exit 10）。為何 13 不是 10：net_refuse(10) 語意是 zero-tolerance content leak；本案是 tier-floor violation——attested level 不足，重派時帶 `warn`＋完成確認即可，body 本身不必改。marker 可被不寫 marker 繞過 → backstop 定位是 belt-and-suspenders（與既有 net 哲學一致），主 gate 在 SKILL 端手續。

**D3 — SKILL 端主 gate：attended 顯式確認、unattended refuse。** layer-3 時 attended → AskUserQuestion「此段第三方逐字內容確認可進 remote？」（帶 redact 選項）；unattended（`is_unattended` / directive）→ 不 post、印 refuse 說明＋改跑 attended 的指示。理由：reply 本質是 correspondence（人在場的工作），unattended 貼第三方逐字內容無人把關 = CLAUDE.md「raw 第三方逐字內容不進 remote」鐵律的直接風險面。

**D4 — rules 檔以 append 為主。** 「Reply layer-3 payload tier floor」段落 append 在 Related rules 之前；既有段落僅允許兩處最小 in-place 校正（net count 句 3→4、growth 歷史句補 3→4），其餘段落（tier 表、ENFORCE 語意、division of labor、implementation contract）零改動——與 in-flight change 的疊層紀律（C_shared_module_coord）以此為界。

## Implementation Contract

- **gh-egress.sh net item 4**：`printf '%s' "$SCAN" | grep -q 'type=reply'` 且 `grep -q 'points-from=user-pasted'` 且 `[ "$ATTESTED" = "light" ]` → stderr 訊息（指示以 `--scrub-attested warn` 重派並先完成使用者確認）＋ `exit 13`。attested=warn/enforce 或 marker 不全 → 不觸發、行為不變。位置：既有 3-item net 之後、mention net 之前或之後皆可（獨立判斷）。
- **SKILL R1 增訂**（R4 僅在 R1 的 floor 條目中被引用、不改動）：layer-3 手續字句（attended confirm / unattended refuse）、marker `points-from=user-pasted` 值與 tier floor 的對應、引用 rules 段名。
- **rules 新段**：normative 三句——LIGHT 不適用於 user-pasted reply payload；最低 WARN＋顯式確認；unattended 不 post。net item 4 的邊界聲明（token-only）。
- **驗證目標**：gh-egress suite 斷言（light+雙 token → exit 13＋stderr 含 warn 重派指示；warn+雙 token → 照派；light+單 token（各向）→ 照派；fenced 討論體 → refuse 的 accepted-friction 鎖定；template↔wrapper token binding）；idd-comment-reply suite 斷言 SKILL 新字句與 rules 段名；`run-all-tests.sh` 40 suites 全綠；版本 2.100.0 → 2.101.0 三處同步。
