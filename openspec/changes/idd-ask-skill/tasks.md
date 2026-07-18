## 1. Tests first (RED)

- [x] 1.1 (Req: Grounded question-answering over the issue corpus; Req: Surfacing-only fourth member obligations) New drift-guard suite plugins/issue-driven-dev/scripts/tests/idd-ask/test.sh: SKILL 存在 + read-only 禁令 + blockquote 原問題 + claim 必附引用 + source priority + `### Referenced Issues` + top-N/limit 界限 + delegate idd-find backend 引用 + 不觸發 diagnose + family 文件成員表含 idd-ask + CLAUDE.md / usecase-routing 可發現性。Run: RED。

## 2. Implementation (GREEN)

- [x] 2.1 (Design D1 — 與 find 的分工; D2 — retrieval delegate idd-find backend; D3 — grounded 回答契約; D4 — decide-to-search gate; D5 — #140 boilerplate checklist 逐項) New skills/idd-ask/SKILL.md（frontmatter read-only allowed-tools、Step 0 bootstrap、gate、retrieval delegate、全文讀取 top-N、回答契約、source priority、unattended 行為、`--repo`/`--limit`、分工表）。
- [x] 2.2 references/surfacing-primitives.md 成員表 +1（第 3 題弱命中註記）；plugin CLAUDE.md 輔助表加 idd-ask 列；references/usecase-routing.md 加情境列。
- [x] 2.3 Verify: suite GREEN; full plugin sweep 0 fail; spectra validate clean。
