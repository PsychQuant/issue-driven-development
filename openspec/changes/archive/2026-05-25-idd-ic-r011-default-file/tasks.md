## 1. Pre-flight verification

- [x] 1.1 Verify `idd-all-chain` IC_R011 reference 是 spawn-manifest pass-through(非 standalone AskUserQuestion checkpoint),確認本 change scope 維持 6 site(5 SHALL + 1 close)。若 verify 失敗(找到 standalone checkpoint)則新開 follow-up change,本 change 仍 ship 原 6 site scope。確立 **scope boundaries** 在後續任務中不漂移。**Verification**:`grep -A 20 'IC_R011' plugins/issue-driven-dev/skills/idd-all-chain/SKILL.md` 結果不含 `AskUserQuestion 3-option`,只含 spawn-manifest helper invocation

## 2. Canonical reference centralization (Decision 4: Centralize procedure body 到 canonical reference)

- [x] 2.1 Implement Requirement「**Canonical reference SHALL hold the normative procedure body; skill SKILL.md files SHALL cite, not duplicate**」:centralize 完整 normative IC_R011 procedure body 到 `plugins/issue-driven-dev/references/ic-r011-checkpoint.md`,包含 Decision 1: Pick Option B file-by-default behavior、Decision 2: 3-category skip taxonomy(a)(b)(c) 規則 + every category 含 2-3 個 example、updated audit trail format table — **observable behaviors** 部分(file / skip-(a) / skip-(b) / skip-(c) / unattended bypass 各 literal string)。**Verification**:`wc -l plugins/issue-driven-dev/references/ic-r011-checkpoint.md` ≥ 350 lines(從 301 增長);grep 確認 6 個 audit string literal 全存在

- [x] 2.2 Implement Requirement「**Issue body `Source` footer SHALL identify the surfacing skill and step**」:在 canonical reference 規範 `**Source**: surfaced during /<skill-name> #<source-issue-or-pr> <description> (Step <N.M>)` 為 normative footer format,涵蓋 6 個 IC_R011 checkpoint site 的 issue body footer。屬於 Implementation Contract 的 **interface / data shape** 規範。**Verification**:`grep -c '\*\*Source\*\*: surfaced during /' plugins/issue-driven-dev/references/ic-r011-checkpoint.md` ≥ 1(canonical ref normative line);新 file 出的 issue body 含 literal 此 footer pattern

## 3. Skill SKILL.md refactor (Decision 3: SHALL skills 翻 default;idd-close 保留 3-option ask)

- [x] 3.1 [P] Refactor `idd-diagnose` Step 3.6 「Sister Concern Surfacing」 為 cite-only 形式 + 採新 file-by-default 行為,**delete inline procedure body 大段** 改為 1-line invoke `**Per IC_R011 follow-up filing checkpoint** (see [references/ic-r011-checkpoint.md](../../references/ic-r011-checkpoint.md))` + step-specific deviation。對應 Requirement「SHALL-tier sites SHALL default to filing surfaced candidates, not asking」。**Verification**:`grep 'per IC_R011' plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md` ≥ 1 hit;Step 3.6 段落不含 `AskUserQuestion 3-option`

- [x] 3.2 [P] Refactor `idd-plan` Step 2.5 「Tangential Observations Sweep」 為 cite-only 形式 + 新 file-by-default 行為(同 3.1 pattern)。**Verification**:`grep 'per IC_R011' plugins/issue-driven-dev/skills/idd-plan/SKILL.md` ≥ 1 hit;inline procedure body 大段消失

- [x] 3.3 [P] Refactor `idd-implement` Step 5.7 「Sister Bug Sweep」 為 cite-only + 新 file-by-default 行為。**Verification**:`grep 'per IC_R011' plugins/issue-driven-dev/skills/idd-implement/SKILL.md` ≥ 1 hit;inline procedure body 大段消失

- [x] 3.4 [P] Refactor `idd-issue` Step 4.7 「Linked-Context Sister Sweep」 為 cite-only + 新 file-by-default 行為。**Verification**:`grep 'per IC_R011' plugins/issue-driven-dev/skills/idd-issue/SKILL.md` ≥ 1 hit

- [x] 3.5 [P] Refactor `idd-verify` Step 5b 「Follow-up Issue Triage」 為 cite-only + 新 file-by-default 行為;**同時補上 canonical「Rule (SHALL)」framing 解決 #149**。對應 Requirement「Skip path SHALL require explicit 3-category taxonomy disambiguation」(verify 階段 follow-up findings 也走相同 skip taxonomy)。**Verification**:`grep '\*\*Rule (SHALL)\*\*' plugins/issue-driven-dev/skills/idd-verify/SKILL.md` ≥ 1 hit(Step 5b 段落);`gh issue close 149` 可執行

- [x] 3.6 [P] Refactor `idd-close` Step 3.5 「Closing Summary Follow-up Keyword Scan」 為 cite-only 形式,但 **preserve 3-option ask behavior**(對應 Requirement「idd-close Step 3.5 SHALL preserve 3-option ask behavior unchanged」)。Canonical ref 必須有對應「SHOULD-tier site with legacy 3-option ask」 section 讓 cite 有對象。**Verification**:`grep '\[file all\]' plugins/issue-driven-dev/skills/idd-close/SKILL.md` ≥ 1 hit(Step 3.5 段落確認 3-option 仍存在);`grep 'per IC_R011' plugins/issue-driven-dev/skills/idd-close/SKILL.md` ≥ 1 hit

## 4. Backward-compat shift + failure modes documentation (Decision 5: Escape hatch semantic shift)

- [x] 4.1 Implement Requirement「**Existing escape hatches SHALL preserve names but shift to new semantics**」+ Requirement「**Unattended mode SHALL fall back to implicit (a) skip with audit trail**」:shift `AI_LOW_BAR_ISSUE_FILING=false` env var docstring + `# Disable IC_R011` flag wording across all 8 reference sites,semantic 從「silently skip checkpoint」到「revert to pre-default-flip 3-option ask」;同時在 canonical reference 記錄 unattended mode + `=false` combined fallback 邏輯,屬於 **failure modes** documentation。範圍:`plugins/issue-driven-dev/references/ic-r011-checkpoint.md` § 5、`plugins/issue-driven-dev/CHANGELOG.md`、`plugins/issue-driven-dev/.claude-plugin/plugin.json` metadata、6 skill SKILL.md(若有 inline docstring 重複)、`plugins/issue-driven-dev/references/distribution-detection.md`。**Verification**:`grep -l 'silently skip checkpoint' plugins/issue-driven-dev/` 返回 empty(舊 wording 全清);`grep -c 'revert to pre-default-flip' plugins/issue-driven-dev/references/ic-r011-checkpoint.md` ≥ 1;`grep -c 'implicit (a) skip' plugins/issue-driven-dev/references/ic-r011-checkpoint.md` ≥ 1

- [x] 4.2 Update `plugins/issue-driven-dev/CHANGELOG.md` with prominent BREAKING entry 紀錄 default-flip + escape hatch 語意 shift + audit trail format change;provide grep migration hint(`grep -E 'Skipped(:| per user choice)' .claude/.idd/`)for downstream telemetry tools。Bump `plugins/issue-driven-dev/.claude-plugin/plugin.json` version minor(non-patch per BREAKING)。**Verification**:`grep -E '^## \[?[0-9]+\.[0-9]+\.[0-9]+\]?' plugins/issue-driven-dev/CHANGELOG.md | head -1` 顯示新 minor version;`grep BREAKING plugins/issue-driven-dev/CHANGELOG.md` 含本 change entry;`jq -r .version plugins/issue-driven-dev/.claude-plugin/plugin.json` 反映 bump

## 5. Acceptance criteria verification

- [x] 5.1 Dogfood acceptance:apply 完成後立刻在新 default 下跑一次 `/idd-diagnose` 試 invocation(per design Risks R6 dogfood-paradox mitigation):選一個既有 OPEN issue,跑 `/idd-diagnose #N`,確認 Step 3.6 IC_R011 checkpoint 採新 file-by-default 行為(無 AskUserQuestion 3-option 阻擋)。對應 design **acceptance criteria** section item 8(dogfood gate)。**Verification**:gh issue comments on the test diagnose target 含 Sister Concerns Filed block 用新 format,**沒**含舊 `[file all] / [file selected] / [skip]` AskUserQuestion 對話痕跡

- [x] 5.2 Run automated structural check 對應 design **acceptance criteria** items 1-5:6 SKILL.md cite canonical reference + 5 SHALL site 翻 default + idd-close preserved + #149 framing fixed + canonical ref 增長到 ≥350 行。**Verification**:`bash -c 'grep -L "per IC_R011" plugins/issue-driven-dev/skills/idd-{diagnose,plan,implement,issue,verify,close}/SKILL.md'` 返回 empty;`bash -c 'grep -c "\[file all\]" plugins/issue-driven-dev/skills/idd-close/SKILL.md'` ≥ 1(close 仍 3-option);5 SHALL site 加總 `\[file all\]` 命中 = 0;`wc -l plugins/issue-driven-dev/references/ic-r011-checkpoint.md` ≥ 350

- [x] 5.3 Run `spectra validate idd-ic-r011-default-file` PASS as final gate before close(design **acceptance criteria** item 7)。**Verification**:`spectra validate idd-ic-r011-default-file` exit code 0,no Critical/Warning findings
