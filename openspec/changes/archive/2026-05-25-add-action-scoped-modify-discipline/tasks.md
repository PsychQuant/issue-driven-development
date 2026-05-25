<!--
Tasks for add-action-scoped-modify-discipline.
Each task states behavior + verification target. File paths are locator
context only. Parallel tasks marked [P] when targeting different files
with no dependency on incomplete in-group tasks.

Substring anchors for analyzer cross-check:
- Spec Requirements: Every modify-action SHALL declare a scope category /
  Undeclared modify-actions SHALL be refused (default-refuse) /
  Canonical 7-category enumeration SHALL be normative /
  /idd-edit SHALL require --section flag /
  /idd-edit SHALL refuse modifications to verbatim-preserve zones /
  Gate logic SHALL resolve authoritative source /
  Gate SHALL fall back to legacy scan when no authoritative source exists /
  Action category labels SHALL be retroactively applied to existing skills
- Design Decisions:
  Decision 1: Action-scoped discipline 取代 actor-based exemption /
  Decision 2: 7-category action taxonomy /
  Decision 3: Path C gate-logic generalization(`only-look-at-latest`) /
  Decision 4: `/idd-edit` BREAKING 加 `--section` flag /
  Decision 5: Principle 落地獨立 rule file 不併 manifesto /
  Decision 6: Retroactive scope classification scope
-->

## 1. 建立 principle rule 文件(Decision 5: Principle 落地獨立 rule file 不併 manifesto)

- [x] 1.1 寫 `plugins/issue-driven-dev/rules/append-vs-modify.md` 內含 Canonical 7-category enumeration SHALL be normative table(Decision 2: 7-category action taxonomy)。 完成判準:檔案存在 + 含 7 個 category section,每 section 含 definition + scope boundary + ≥ 2 個 existing IDD action 範例;`grep -c "^### " plugins/issue-driven-dev/rules/append-vs-modify.md` 回傳 ≥ 7。
- [x] 1.2 在 rule file 內加 decision tree section 幫 plugin author classify 新 action,以及與 IC_R007 / IC_R010 / IC_R011 sister principles boundary discussion。 完成判準:rule 含「Decision tree for classifying new modify-actions」section + 「Boundary with IC sister principles」section;manual review 涵蓋每個 IC 的 cross-ref。
- [x] 1.3 在 rule file 結尾加 backward-compat fallback note 解釋 Path C gate-logic「only-look-at-latest」 pattern + legacy fallback behavior。 完成判準:rule 含 `## Backward-compat fallback` section 引用 `#515` precedent。

## 2. Spec normative requirements(Decision 1: Action-scoped discipline 取代 actor-based exemption)

- [x] 2.1 確認 spec `openspec/specs/append-vs-modify-discipline/spec.md`(本 change delta)passes `spectra analyze` 無 Critical / Warning findings,內含 「Every modify-action SHALL declare a scope category」 + 「Undeclared modify-actions SHALL be refused (default-refuse)」 + 「Canonical 7-category enumeration SHALL be normative」 三條 SHALL requirements 之 ADDED block。 完成判準:`spectra analyze add-action-scoped-modify-discipline --json` 對 spec 區段無 Critical / Warning。
- [x] 2.2 確認 spec 內 Decision 1: Action-scoped discipline 取代 actor-based exemption 是 root rationale 並於 design.md Decision 1 reference 一致。 完成判準:design Decision 1 段落 + spec ADDED block 「Every modify-action SHALL declare a scope category」 一致無 drift;manual cross-ref。

## 3. `/idd-edit` SHALL require --section flag(Decision 4: `/idd-edit` BREAKING 加 `--section` flag — scope clarification:comment-only;BREAKING 限縮在 `--replace` mode + verbatim-preserve user-authored comments guard)

- [x] 3.1 修改 `plugins/issue-driven-dev/skills/idd-edit/SKILL.md` 加 `--replace` scope flag 必填邏輯:`/idd-edit --replace` SHALL require `--scope whole-comment` OR `--section <heading-within-comment>`。 落實 Spec Requirement: 「/idd-edit --replace SHALL require scope flag」。 並加 inline category notes:`--append (category: audit-block-append, scope: trailing block)` / `--prepend-note (category: audit-block-append, scope: leading errata marker)` / `--replace (category: bounded-section-replace, scope: whole-comment OR <subsection>)`。 完成判準:SKILL.md 含 `--scope` / `--section` flag 規格段 + 至少 1 個 positive example(`--replace --scope whole-comment`)+ 至少 1 個 refuse example(`--replace` 不帶 scope flag);3 個 mode 各有 inline category note。
- [x] 3.2 在 idd-edit SKILL.md 加 verbatim-preserve user-authored comments refuse rule。 落實 Spec Requirement: 「/idd-edit SHALL refuse modifications to user-authored comments」。 完成判準:SKILL.md 含「verbatim-preserve guard」section 描述 `author_association ≠ OWNER` 且 non-bot 的 comment 對 3 個 mode 都 refuse;含 `--override-user-content` + `--reason="..."` escape hatch 規格;dogfood manual scenario:對 external collaborator comment invoke `/idd-edit --append` 應 refuse 引用 IC_R007 cross-ref。
- [x] 3.3 在 `plugins/issue-driven-dev/CHANGELOG.md` 加 `BREAKING` entry 對 `/idd-edit --replace` 必填 `--scope` 或 `--section`,以及 `--override-user-content` flag 對 user-authored comments,migration note(舊 invocation pattern `/idd-edit comment:NNN --replace --body "..."` → 加 `--scope whole-comment` 或 `--section "<subsection>"`)。 完成判準:CHANGELOG.md 最頂版本 entry 含 `BREAKING:` line 提到 `/idd-edit --replace` 跟 verbatim-preserve guard;migration guidance ≥ 3 行 含具體 invocation pattern 對照。

## 4. Path C gate logic generalization(Decision 3: Path C gate-logic generalization(`only-look-at-latest`))

- [x] 4.1 修改 `plugins/issue-driven-dev/skills/idd-close/SKILL.md` Step 0 supersession,把現有 `#515` 邏輯 generalize 為 spec Requirement「Gate logic SHALL resolve authoritative source」(authoritative_source priority order)。 完成判準:SKILL.md Step 0 含 `authoritative_source resolution` 段落 + priority list 3 個 source;backward-compat fallback note 引用 `#515`。
- [x] 4.2 修改 `plugins/issue-driven-dev/skills/idd-verify/SKILL.md` checklist scan 階段對齊 authoritative_source pattern。 完成判準:SKILL.md verify gate 段落含「authoritative_source」 用詞 + 至少 1 個 worked example(legacy issue fallback)。
- [x] 4.3 修改 `plugins/issue-driven-dev/skills/idd-update/SKILL.md` body sync gate 對齊 pattern。 完成判準:SKILL.md gate 段落含 authoritative_source 處理 + fallback note。
- [x] 4.4 修改 `plugins/issue-driven-dev/skills/idd-implement/SKILL.md` Step 5 Checklist Sync 對齊 pattern,寫 Implementation Complete > Checklist 是 authoritative_source winner。 完成判準:SKILL.md Step 5 含「Implementation Complete > ### Checklist 是 authoritative_source」 explicit note。
- [x] 4.5 落實 Spec Requirement「Gate SHALL fall back to legacy scan when no authoritative source exists」:在每個改過的 SKILL.md 加 fallback bullet。 完成判準:4 個 SKILL.md 各含「無 authoritative_source → fall back legacy scan」 fallback bullet;dogfood manual:用 legacy issue body(無 Implementation Complete)觸發 close,確認 fallback 動。

## 5. Retroactive scope classification(Decision 6: Retroactive scope classification scope)

- [x] 5.1 [P] 落實 Spec Requirement「Action category labels SHALL be retroactively applied to existing skills」: 在 `plugins/issue-driven-dev/skills/idd-update/SKILL.md` modify-action 描述加 inline note `(category: bounded-section-replace, scope: "## Current Status")`。 完成判準:grep `category: bounded-section-replace` 在該 SKILL.md 有 hit;manual review confirm 位置在「替換 --- 以下內容」 action 段落。
- [x] 5.2 [P] 在 `plugins/issue-driven-dev/skills/idd-clarify/SKILL.md` status field 操作加 inline note `(category: state-field-update)`。 完成判準:grep `category: state-field-update` 在該 SKILL.md 有 hit;manual review confirm 在 `--status resolved/dismissed` 段落。
- [x] 5.3 [P] 在 `plugins/issue-driven-dev/skills/idd-close/SKILL.md` Step 3.5 inline replace 加 inline note `(category: inline-replace-before-publish)`。 完成判準:grep 在 Step 3.5 段落有 hit。
- [x] 5.4 [P] 在 `idd-diagnose` / `idd-issue` / `idd-close` SKILL.md 各 IC_R011 audit PATCH 操作加 inline note `(category: audit-block-append, scope: <named section>)`(`### Sister Concerns Filed` / `### Linked-Context Siblings Filed` / `### Closing Follow-ups Filed`)。 完成判準:3 個 SKILL.md 各至少 1 個 inline note hit;每 scope 對應 named section 名稱正確。

## 6. Manifesto pointer + dogfood verification

- [x] 6.1 若 `plugins/issue-driven-dev/manifesto.md` 存在,加 one-section overview 指向新 rule(`See rules/append-vs-modify.md for action-scoped modify discipline`);若不存在則跳過 task。 完成判準:manifesto.md 含 pointer section 或本 task 明確 skip(commit message 或 tasks.md note 記)。
- [x] 6.2 Dogfood verification:本 plugin 自己用新 principle 操作 comment。 invoke `/idd-edit comment:<id> --replace --body "..."` 不帶 `--scope`/`--section` 驗證 refuse;帶 `--scope whole-comment` 驗證 work;對 user-authored comment 不帶 `--override-user-content` 驗證 refuse 引用 IC_R007。 完成判準:3 個 invocation 結果(2 refuse + 1 work)在 plugin author log 或 PR description 截圖記錄。
