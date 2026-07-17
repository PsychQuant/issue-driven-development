## 1. Tests first (RED)

- [x] 1.1 (Req: Surfacing-only semantic lookup across the full issue corpus; Req: Division of labor against idd-list is preserved) New drift-guard suite plugins/issue-driven-dev/scripts/tests/idd-find/test.sh: SKILL exists + surfacing-only 禁令 + open+closed 全語料 + relevance backend + phase/PR overlay + 誠實邊界（embedding residue）+ 分工表（導流 idd-list）+ CLAUDE.md 表列 + usecase-routing 情境列。Run: RED。

## 2. Implementation (GREEN)

- [x] 2.1 (Design D1 — surfacing-only 契約是硬邊界; D2 — v1 GitHub search relevance 誠實邊界; D3 — ranked hits + IDD overlay; D4 — family boilerplate conformance; D5 — 與 idd-list 的分工) New skills/idd-find/SKILL.md（frontmatter read-only allowed-tools、Step 0 bootstrap、search backend + fallback、輸出 shape、空結果誠實降級、unattended 行為、`--repo`/`--limit`、filter flags 拒收 + 導流 idd-list）。
- [x] 2.2 Plugin CLAUDE.md 輔助 skills 表加 idd-find 列；references/usecase-routing.md 加「找舊案」情境列。
- [x] 2.3 Verify: suite GREEN; full plugin sweep 0 fail; spectra validate clean。
