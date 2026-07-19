## 1. Normative 契約落地

- [x] 1.1 plugins/issue-driven-dev/rules/privacy-scrubbing.md append 新段「Reply layer-3 payload tier floor」：LIGHT 不適用於 `points-from=user-pasted` reply payload、最低 WARN＋顯式使用者確認（不論 repo visibility）、unattended 不 post；net item 4 的 token-only 邊界聲明（spec requirement: Layer-3 third-party payload tier floor）。append 為主（design D4）：新段可 grep；既有段僅 net-count 句與 growth 歷史句兩處最小校正，其餘零改動。
- [x] 1.2 plugins/issue-driven-dev/scripts/gh-egress.sh 加 net item 4：SCAN 同時含 `type=reply` 與 `points-from=user-pasted` 且 `$ATTESTED = light` → stderr 指示（以 `--scrub-attested warn` 重派、先完成使用者確認）＋ exit 13（design D2：attestation band 非 content band）。完成判準：task 2.1 兩向測試綠。
- [x] 1.3 plugins/issue-driven-dev/skills/idd-comment/SKILL.md R1/R4 增訂 layer-3 手續：attended → AskUserQuestion 顯式確認第三方逐字內容可進 remote（帶 redact 選項）；unattended → refuse post＋說明；marker 記 `points-from=user-pasted`；引用 rules 新段名；移除/改寫 v2.100.0 的「heightened 自審」句為指向新 normative 段（spec requirement: Layer-3 third-party payload tier floor + MODIFIED Points-source resolution）。完成判準：新字句可 grep、舊 prose 不殘留矛盾表述。

## 2. 測試

- [x] 2.1 plugins/issue-driven-dev/scripts/tests/gh-egress/test.sh 加三向斷言：(a) light＋雙 marker → exit 13；(b) warn＋雙 marker → 照派（mock gh 或既有測試手法）；(c) light＋僅 `type=reply`（無 user-pasted）→ 照派。跟隨該 suite 既有 mock/fixture 慣例。完成判準：單跑 suite 綠；暫時移除 item 4 時 (a) 紅（RED 驗證後還原）。
- [x] 2.2 plugins/issue-driven-dev/scripts/tests/idd-comment-reply/test.sh 加斷言：SKILL 的 layer-3 attended-confirm 與 unattended-refuse 字句、rules 新段名引用、marker `points-from=user-pasted` tier-floor 對應。完成判準：suite 綠（27 → 31±）。
- [x] 2.3 bash plugins/issue-driven-dev/scripts/run-all-tests.sh 全綠（40 suites 0 fail）。完成判準：aggregator 輸出 0 fail。

## 3. 文件與版本

- [x] 3.1 plugins/issue-driven-dev/CHANGELOG.md 加 2.101.0 段（tier floor 三件套、net 3→4 的 separate-change 依據、#272 / #269 DA-3 出處）；plugin.json 與 root marketplace.json entry 同步 2.101.0。完成判準：三處版本字串一致。
- [x] 3.2 spectra validate + analyze 無 Critical/Warning；PR 以 Refs #272 開出。完成判準：validate exit 0。
