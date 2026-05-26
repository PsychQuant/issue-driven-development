# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.75.0] - 2026-05-25

### Added

- **`plugins/issue-driven-dev/scripts/idd-edit-helper.sh`** ([#154](https://github.com/PsychQuant/issue-driven-development/issues/154)): NEW extracted runtime helper with 3 subcommands. `parse-args` does positional shift over 7 space-form flags with explicit missing-value guards (`[ -z "${2:-}" ]` + `[[ "$2" == --* ]]`) + eq-form support + body-file readability pre-check + emits eval-friendly KEY=quoted-value via printf %q (preserves newlines). `validate-target` enforces R5 via single gh API call (author_association + login fetch) with `*[bot]` allowlist + OWNER passthrough + override pathway. `section-replace` uses awk-getline pattern (BSD/gnu safe — closes R3 C3 BSD awk -v multi-line newline reject). 5 distinct exit codes (0/1/2/3/4/5).

- **`plugins/issue-driven-dev/scripts/tests/idd-edit/{test.sh,fixtures/01-19/}`** ([#154](https://github.com/PsychQuant/issue-driven-development/issues/154)): NEW test infrastructure per `.claude/scripts/tests/spectra-archive-post-ic/` precedent. **19 fixtures** cover R1/R2/R3 regression set + Round 1 verify finding additions: parser robustness (eq form / space form / missing value / next-flag-eats-value / unreadable file / multi-line body / single-line body / subsections / no-closing-heading), R4 gate (no scope/section refuse + invalid scope value refuse), R5 override pair guard (default=false / requires --reason / succeeds with both), validate-target via IDD_EDIT_HELPER_GH_MOCK env var (OWNER passthrough / bot allowlist / non-OWNER refuse / non-OWNER with override), section-replace CRLF input handling. All 19 GREEN.

- **`emit-audit-marker` helper subcommand** ([#154](https://github.com/PsychQuant/issue-driven-development/issues/154) Round 1 fix C3+M1): centralizes HTML-comment-escape so attacker-controlled `$REASON` / `$SECTION_FLAG` cannot forge audit trail. Strips `-->` tokens (→ `-\>`), newlines, control chars. Used by all 3 modes for both `edit` markers and `override` markers. Closes R5 forensic gap where override marker only emitted in `--replace` branch.

- **`IDD_EDIT_HELPER_GH_MOCK` env var** ([#154](https://github.com/PsychQuant/issue-driven-development/issues/154) Round 1 fix H3): test hook for `validate-target` subcommand. When set, reads mock JSON `{"login": ..., "assoc": ...}` instead of calling `gh api`. Unblocks unit-test coverage of bot allowlist / OWNER passthrough / refuse paths without live API. Used by fixtures 15-18.

- **`comment_id` numeric validation** ([#154](https://github.com/PsychQuant/issue-driven-development/issues/154) Round 1 fix C2): SKILL.md Step 1 enforces `[[ "$COMMENT_ID" =~ ^[0-9]+$ ]]` before substitution into `gh api repos/.../comments/$comment_id` URL or `/tmp/idd-edit-repl-$COMMENT_ID.md` filename. Closes Round 1 verify finding C2 path traversal via Step 0.7 PR↔issue correspondence input.

- **`--body-file` path-traversal documentation** ([#154](https://github.com/PsychQuant/issue-driven-development/issues/154) Round 1 fix H5): SKILL.md 鐵律 section explicitly notes `--body-file=/etc/passwd` would be read + pushed to public PATCH; user/caller validates path; restrict-to-subtree is future enhancement.

- **`/idd-edit` R4 runtime gate** ([#154](https://github.com/PsychQuant/issue-driven-development/issues/154)): `--replace` without `--scope whole-comment` OR `--section <heading>` → refuse with exit 3 + actionable error message + spec Requirement 4 citation. Closes #150 Requirement 4 runtime enforcement deferral. Tested by fixture 10.

- **`/idd-edit` R5 runtime gate** ([#154](https://github.com/PsychQuant/issue-driven-development/issues/154)): non-OWNER non-bot comment without `--override-user-content --reason="..."` → refuse with exit 4 + helpful manual-invocation message + spec Requirement 5 citation. Bot allowlist matches `*[bot]` glob (github-actions[bot], dependabot[bot], etc.). Override appends `<!-- idd:edit override-user-content date=... reason="..." -->` audit marker to comment body. Closes #150 Requirement 5 runtime enforcement deferral.

- **`/idd-comment` errata flow R5 integration** ([#154](https://github.com/PsychQuant/issue-driven-development/issues/154)): errata Template SPECIAL BEHAVIOUR sets `IDD_CALLER=idd-comment-errata` env var when auto-calling `/idd-edit --prepend-note`. On R5 refuse (exit 4), displays helpful message with exact manual invocation pattern (`--override-user-content --reason='errata clarification per IDD discipline'`). Per D2 decision (refuse-with-message > auto-override, aligns with IC_R007 user-authored-intent spirit).

### Refactored

- **`/idd-edit` SKILL.md Step 1** ([#154](https://github.com/PsychQuant/issue-driven-development/issues/154)): replaced inline `if [[ "$ARG" == comment:* ]]; then ... elif [[ "$ARG" == \#* ]]; then ...` pseudocode with `bash $CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.sh parse-args "$@"` invocation + eval-import. AI no longer generates parser bash inline — uses tested helper. Closes R1/R2/R3 root cause: AI bash generation inconsistency.

- **`/idd-edit` SKILL.md Step 4 `--replace` mode** ([#154](https://github.com/PsychQuant/issue-driven-development/issues/154)): replaced inline `awk -v new_content="$BODY"` (R3 C3 BSD-broken) with `bash ... section-replace` invocation that uses awk-getline reading from file. Whole-comment path stays inline (no awk needed). Override audit marker appended when applicable.

- **`/idd-edit` SKILL.md frontmatter `argument-hint`** ([#154](https://github.com/PsychQuant/issue-driven-development/issues/154)): updated to show new flag syntax — mode flags grouped with R4-required `--scope`/`--section` for `--replace` + new `--body-file`/`--reason`/`--override-user-content` flags.

- **`/idd-edit` SKILL.md `## 使用範例`** ([#154](https://github.com/PsychQuant/issue-driven-development/issues/154)): 3 existing examples updated with new flag syntax; 2 new examples added (section-replace + errata override flow).

- **`/idd-edit` SKILL.md `## Batch mode`** ([#154](https://github.com/PsychQuant/issue-driven-development/issues/154)): added per-target R4/R5 enforcement note + cross-link to [#158](https://github.com/PsychQuant/issue-driven-development/issues/158) for full batch+R5 semantics design.

- **`openspec/specs/append-vs-modify-discipline/spec.md`** ([#154](https://github.com/PsychQuant/issue-driven-development/issues/154)): Purpose / Requirement 4 / Requirement 5 preambles updated from "deferred to #154" to "landed via #154" + specific helper subcommand + tested-by fixture references. Removed "Re-verify for runtime conformance when #154 closes" cleanup tags.

### BREAKING (runtime)

- **`/idd-edit --replace` without `--scope`/`--section` now refuses** ([#154](https://github.com/PsychQuant/issue-driven-development/issues/154)): existing AI invocations of `/idd-edit comment:NNN --replace --body "..."` will get exit 3 + R4 message. Must add `--scope whole-comment` (full overwrite) or `--section "### Heading"` (named subsection). Discipline already declared in v2.73.0/v2.74.0 spec; v2.75.0 makes it runtime-enforced.

- **`/idd-edit` modifying non-OWNER non-bot comment now refuses** ([#154](https://github.com/PsychQuant/issue-driven-development/issues/154)): existing AI invocations targeting external collaborator / non-OWNER comments will get exit 4 + R5 message. Must add `--override-user-content --reason="..."` for explicit consent. `/idd-comment` errata flow auto-call gracefully handles this with helpful message.

### Round 1 verify fixes (all 11 pre-merge findings addressed)

- **C1**: Helper + test fixtures moved from `.claude/scripts/` to `plugins/issue-driven-dev/scripts/` — matches `process-attachments.sh` / `manifest-append.sh` precedent. `$CLAUDE_PLUGIN_ROOT/scripts/idd-edit-helper.sh` now resolves correctly in production install.
- **C2**: `comment_id` numeric validation (described above under Added).
- **C3+M1**: `emit-audit-marker` helper subcommand (described above under Added) — centralized HTML-escape, marker emission in all 3 modes.
- **B1**: SKILL.md Step 4 `--append` mode uses `$BODY_INPUT` (helper-exported) instead of undefined `$APPEND_BODY`.
- **B2**: SKILL.md Step 6 PATCH + Step 7 verify use `$REPO` (helper-exported, currently respects `--repo` flag only; walk-up config resolution deferred to future enhancement) instead of undefined `$GITHUB_REPO`.
- **H1**: helper `parse-args` R4 gate validates `--scope` value MUST be `whole-comment` (no other valid scopes today). Invalid value → exit 3 with hint.
- **H2**: SKILL.md Step 1 splits `parse-args` stdout/stderr via temp file. `eval` only sees `printf %q` quoted assignments; stderr never reaches eval (closes shell-injection via `cat`-on-directory `$()` POC).
- **H3**: `validate-target` test coverage via `IDD_EDIT_HELPER_GH_MOCK` env var (described above under Added) — 4 new fixtures.
- **H4**: `section-replace` heading-level counter rewritten via awk char-by-char (no `wc -c` trailing-newline off-by-one). CRLF input strip via `tr -d '\r'` on both input + replacement. Fixture 08 strengthened with exact-stdout match. New fixture 19 verifies CRLF.
- **H5**: `--body-file` path-traversal risk documented in SKILL.md 鐵律.
- **D1**: PR body + commit body Closes/auto-close trailer cleaned per `CLAUDE.md` Commit Conventions §「引用 trap pattern 作反例的寫作紀律」(#97).
- **M3**: Bot allowlist dead-code redundant patterns cleaned up.
- **M6**: `validate-target` guards against null `login`/`assoc` from malformed gh API response.

### Filed during implementation

- **[#155](https://github.com/PsychQuant/issue-driven-development/issues/155)** — sister concern: bash vs alternative layer for strict flag parsing (parking-lot P3; helper extraction proves bash + thin SKILL.md orchestration works)
- **[#156](https://github.com/PsychQuant/issue-driven-development/issues/156)** — sister concern: IDD plugin test framework (P2; partially pre-empted by reusing `.claude/scripts/tests/` fixture-dir precedent for #154 — same pattern now applies to 2 sites)
- **[#157](https://github.com/PsychQuant/issue-driven-development/issues/157)** — tangential: spec.md `<!-- @trace -->` blocks lack auto-updater (parking-lot P3)
- **[#158](https://github.com/PsychQuant/issue-driven-development/issues/158)** — tangential: `/idd-edit` batch mode + R5 interaction semantics decision (P2; single-target enforcement shipped, batch interaction follow-up)
- **[#160](https://github.com/PsychQuant/issue-driven-development/issues/160)** — sister bug: spectra-archive-post-ic/test.sh likely has same `grep -qF --` bug (parking-lot P3)
- **[#161](https://github.com/PsychQuant/issue-driven-development/issues/161)** — sister concern: IDD_CALLER env var registry codification (parking-lot P3)

### Round 2 verify fixes (R2 found 5 NEW HIGH + 4 MEDIUM introduced by R1 fix loop; R3 addresses all)

R2 findings + R3 fixes:

- **H6 (quote injection in `emit-audit-marker`)** — 4-way confluence (Logic + Security + DA + Codex independently surfaced). `--reason='ok" date="1970-01-01" forged="yes'` was forging audit attributes by breaking out of value's double-quote scope. R3 fix: `${val//\"/\&quot;}` (note bash `&`-as-backref gotcha required `\&` escape). Also closes latent key-injection (H7 defense in depth). Fixture 20 GREEN.
- **H7 (batch mode broken)** — SKILL.md Step 1 for-loop closed BEFORE Steps 1.5-7, silently processing only LAST target. R3 fix: restructured to accumulate `RESOLVED_COMMENT_IDS` array; added explicit "Per-target outer loop" subsection wrapping Steps 1.5-7.
- **H8 (`IDD_EDIT_HELPER_GH_MOCK` ungated)** — R5 author check bypassable via attacker-crafted env (classic LD_PRELOAD pattern). R3 fix: helper now requires `IDD_EDIT_HELPER_TEST_MODE=1` paired with the mock var, refuses with explicit error otherwise. Fixture 21 GREEN.
- **H9 (CHANGELOG false claim)** — Line 58 claimed `$REPO` "respects walk-up config" but walk-up never implemented. R3 fix: corrected entry to acknowledge --repo flag only + defer walk-up to future enhancement.
- **H10 (`--body-file` path traversal)** — R1 doc-only fix insufficient; `/etc/passwd` still readable. R3 fix: helper `validate_body_file_path()` refuses `/etc/* /var/* /sys/* /proc/* /private/etc|var/* $HOME/.ssh|.aws|.gnupg|.kube|.docker/*` unless `IDD_EDIT_HELPER_ALLOW_UNSAFE_BODY_FILE=1` escape hatch set. Fixtures 22 (refuse) + 23 (safe path) GREEN.
- **M-R2-1 (null guard incomplete)** — Only caught `<null>` literal, not empty string from jq parse failure. R3 fix: extended to `[ -z "$author_login" ]` + `2>/dev/null` on jq calls.
- **M-R2-2 (`tr` range excluded TAB/CR)** — R3 fix: range now `\000-\037` (full ctrl chars); comment corrected.
- **M-R2-3 (marker format change unannounced)** — Marker values now double-quoted (e.g. `mode="replace"` not `mode=replace`). Downstream parsers should accept either form; this entry documents the change.
- **M-R2-4 (fixtures don't cover SKILL.md↔helper integration)** — Architectural gap acknowledged; not addressed in R3 to avoid scope inflation. Filed as follow-up [#163](https://github.com/PsychQuant/issue-driven-development/issues/163).
- **N1-3 doc drift** — Stale `.claude/scripts/` refs in spec.md / SKILL.md / test.sh + PR body "13 fixtures" outdated → R3 sed pass over 5 sites; PR body updated to "23 fixtures" (current count post-R3).

### Filed during R3 fix loop

- **[#163](https://github.com/PsychQuant/issue-driven-development/issues/163)** — sister: SKILL.md↔helper integration test layer (M-R2-4) — pragmatic test layer that exercises SKILL.md orchestration end-to-end with mock gh, not just helper standalone

## [2.74.0] - 2026-05-25

### Added

- **`/idd-clarify` Step 4.8.A unattended-mode auto-defer** ([#137](https://github.com/PsychQuant/issue-driven-development/issues/137)): under `[ ! -t 0 ] || [ -n "$IDD_ALL_UNATTENDED" ]` detection, scan mode emits `deferred` rows with registry-cited reason literal `unattended-auto-Step-4.6-deferred` (instead of `surfaced`)。 5-column table schema(Type / Source / Suggested canonical / Status / Reason)used in unattended variant;attended mode preserves 4-column legacy schema unchanged。 Closes #137 design space收斂 Option D(per /spectra-discuss + user explicit pick post #150 reframe)— reuse existing `deferred` enum 取代 new `unattended_review_pending` enum 提案;preserve audit visibility per #148 file-by-default discipline。

- **Reason pattern registry in `rules/append-vs-modify.md`** ([#137](https://github.com/PsychQuant/issue-driven-development/issues/137)): new `### Reason pattern registry` section as single source of truth for gate-recognized reason literals。 First registered:`unattended-auto-Step-4.6-deferred`(`/idd-clarify` Step 4.8.A → `/idd-diagnose` Step 0.5 gate)。 3+ SKILL.md sites SHALL cite by reference,not inline duplication — prevents typo drift HIGH risk surface across coordinating gates。 Registry规範 dot-escape + anchored case-sensitive regex convention for new literals。

- **`openspec/specs/idd-clarify/spec.md`** ([#137](https://github.com/PsychQuant/issue-driven-development/issues/137)): NEW greenfield spec — 7 SHALL requirements covering scan/update mode dispatch, three-class detection (terminology / ambiguity / missing-context), Step 4.8.A unattended detection, registry citation, IC_R007 source preservation, mandatory `/idd-issue` Step 4.6 auto-delegation, scan-mode source guard。 Retroactive #135 codification + #137 unattended branch。

- **`openspec/specs/idd-diagnose-clarity-gate/spec.md`** ([#137](https://github.com/PsychQuant/issue-driven-development/issues/137)): NEW greenfield spec — 7 SHALL requirements covering hard-refuse baseline (#135), reason-pattern accept for registry-cited unattended-auto-deferred rows (#137), legacy `deferred` row refusal preservation, dot-escaped anchored regex convention, legacy backward-compat silent proceed, all-resolved silent proceed, cross-site literal alignment guarantee。

### Refactored

- **`/idd-diagnose` Step 0.5 gate per-row reason scan** ([#137](https://github.com/PsychQuant/issue-driven-development/issues/137)): gate logic 改 `deferred` row blanket REFUSE 為 per-row reason regex 分流(dot-escaped `^unattended-auto-Step-4\.6-deferred$`)— registry-cited literal → PROCEED-with-warn(emit audit line to stderr 標示 count + 引導 user 看 /idd-all Phase 6 Action items),non-match → preserve legacy REFUSE。 `surfaced` rows unchanged(仍 REFUSE)。 `(category: state-field-update, scope: gate condition relaxation per #150 Path C pattern + #137 reason-pattern accept)` per `rules/append-vs-modify.md`。

- **`/idd-all` Phase 6 final report Action items surface** ([#137](https://github.com/PsychQuant/issue-driven-development/issues/137)): Phase 6 終端 report 之後 scan invoked sub-issues' bodies(root + spawn manifest 衍生 issues if any)for `### Clarity Surface` rows with registry-cited reason literal;found rows append 到「## Action items (require human review)」section with cite to Reason pattern registry + 引導 user `/idd-clarify resolved=<idx>,<reason>` 解決路徑。 Non-noisy:無 auto-deferred rows → section 不 emit。 `(category: audit-block-append, scope: "## Action items" final report section)`。

### Notes

- Plugin v2.74.0 是 **minor** bump(activate #150 `state-field-update` category for `/idd-clarify` Step 4.8.A;non-BREAKING 因 legacy `deferred` rows 行為不變)。
- 本 change 是 `#150`(action-scoped modify discipline,shipped v2.73.0)落地的第一個下游 design — activates 4 `#150` mechanisms:`state-field-update` category extension、`audit-block-append` category(Phase 6 Action items)、Path C `authoritative_source` pattern(gate condition-based dispatch deterministic)、strict reason literal naming(prevent drift)。
- Cluster PR with #150:branch `idd/137-150-action-scoped-cluster` 含兩 issue's implementation,cluster close via `/idd-close #137 #150`(per-issue closing summary required per IDD discipline)。
- Sister `#152` filed for git hygiene tangential(3 pre-existing dirty items pollute cluster PRs — surfaced via #137 tangential sweep,routing TBD)。

## [2.73.0] - 2026-05-25

### Spec discipline (declared, runtime enforcement deferred to follow-up issue)

- **`/idd-edit --replace` SHALL declare scope** ([#150](https://github.com/PsychQuant/issue-driven-development/issues/150), [spec](../../openspec/specs/append-vs-modify-discipline/spec.md) Requirement 4): action-scoped modify discipline 規範 `/idd-edit --replace` 屬 `bounded-section-replace` category — invocations SHALL be made with explicit `--scope whole-comment` (full-comment overwrite acknowledgment) OR `--section <heading-within-comment>` (named subsection scope). `--append` 跟 `--prepend-note` 屬 `audit-block-append` category (scope inherent in mode semantics) — no flag required.

  **Status**: Spec-documented + AI / user invocation discipline (Claude orchestrator reads the spec + applies). **Bash-runtime enforcement deferred to [#154](https://github.com/PsychQuant/issue-driven-development/issues/154)** after 3 verify iterations (R1/R2/R3) each surfaced new bugs in incremental bash patching attempts — implementation needs proper standalone proposal with multi-line body handling + parser pattern + errata flow integration designed upfront.

  **Recommended invocation pattern (AI / user discipline)**:
  ```bash
  /idd-edit comment:NNN --replace --scope whole-comment --body "..."
  /idd-edit comment:NNN --replace --section "### Sister Concerns Filed" --body "..."
  ```

- **`/idd-edit` verbatim-preserve guard for user-authored comments** ([#150](https://github.com/PsychQuant/issue-driven-development/issues/150), [spec](../../openspec/specs/append-vs-modify-discipline/spec.md) Requirement 5): all 3 modes SHALL refuse modifications to comments where `author_association ≠ OWNER` and author is not in known-bot allowlist. Aligns IC_R007 verbatim source preservation discipline at comment layer. Override via `--override-user-content` + `--reason="<rationale>"`.

  **Status**: Same as above — spec discipline + AI/user invocation guideline; runtime enforcement deferred to [#154](https://github.com/PsychQuant/issue-driven-development/issues/154).

  **Recommended override pattern**:
  ```bash
  /idd-edit comment:<external-user-id> --append --body "..." \
    --override-user-content --reason="Reformatted at original author's email request 2026-05-25"
  ```

### Added

- **`plugins/issue-driven-dev/rules/append-vs-modify.md`** ([#150](https://github.com/PsychQuant/issue-driven-development/issues/150)): new plugin-level rule codifying action-scoped modify discipline. 7-category taxonomy(`state-field-update` / `bounded-section-replace` / `audit-block-append` / `inline-replace-before-publish` / `verbatim-preserve` / `append-only` / `free-rewrite`)+ decision tree for new modify-actions + boundary with IC_R007 / IC_R010 / IC_R011 sister principles + Path C gate-logic generalization pattern + backward-compat fallback note。 Parallel to existing IC rule file pattern。

- **`openspec/specs/append-vs-modify-discipline/spec.md`**: normative spec with 8 SHALL requirements + 16+ scenarios。 Sourced from change `add-action-scoped-modify-discipline`(see `openspec/changes/archive/<date>-add-action-scoped-modify-discipline/`)。

### Refactored

- **Path C gate-logic generalization across 4 sites** ([#150](https://github.com/PsychQuant/issue-driven-development/issues/150)): `idd-close` Step 0 / `idd-verify` checklist scan / `idd-update` body sync gate / `idd-implement` Step 5 Checklist Sync 統一採用 `authoritative_source` resolution(`## Implementation Complete > ### Checklist` → `## Current Status > ### Tasks` → `## Todo`/`## Tasks`/`## Checklist` priority order)。 `#515` supersession bridge 邏輯升格為通用 pattern;legacy fallback(無 authoritative_source → scan all sources)保留 backward compat。 Strategy / Implementation Plan checkboxes 在 implementation 後一律視為 superseded snapshot,不再 gate-block。

- **Retroactive action category labels** ([#150](https://github.com/PsychQuant/issue-driven-development/issues/150)): existing modify-actions retroactively 在 SKILL.md inline note 標 category — `/idd-update`(`bounded-section-replace`)/ `/idd-clarify`(`state-field-update`)/ `/idd-close` Step 3.5 inline replace(`inline-replace-before-publish`)/ IC_R011 audit PATCH in 5 skills(`audit-block-append`)。 `/idd-edit` labels deferred to [#154](https://github.com/PsychQuant/issue-driven-development/issues/154) along with runtime enforcement (3 verify iterations exposed that bash-level enforcement needs a proper proposal, not incremental patches)。 未來新 modify-action 應在 SKILL.md 描述加 `(category: <name>)` inline note per spec discipline。

### Notes

- Plugin v2.73.0 是 minor bump(spec discipline declaration for `/idd-edit` — not runtime BREAKING since enforcement deferred to follow-up [#154](https://github.com/PsychQuant/issue-driven-development/issues/154))。
- 本 change ship 後 sister `#137`(unattended-mode Clarity Surface contract)+ `#151`(commit-body auto-close trap remediation)的 design 必須 align 新 principle。
- Dogfood paradox:本 change 在 spec-driven 流程內 ship,但 spec-driven flow 本身 pre-existing 不 compliant — `proposal.md` / `design.md` / `tasks.md` 屬 `free-rewrite`(docs),`spec.md` ship 後落 `verbatim-preserve`(spec frozen)。

## [2.72.0] - 2026-05-25

### BREAKING (behavioral)

- **IC_R011 follow-up filing default flipped from "ask 3-option" to "file by default + 3-category skip taxonomy"** ([#148](https://github.com/PsychQuant/issue-driven-development/issues/148)): user feedback after 3 consecutive `file all`-variant choices in one session ("預設要開起 issue,不然過去的問題就會消失了吧,除非是無法解決的問題") triggered systematic default-flip across 5 SHALL-tier IC_R011 sites. `idd-diagnose` Step 3.6 / `idd-plan` Step 2.5 / `idd-implement` Step 5.7 / `idd-issue` Step 4.7 / `idd-verify` Step 5b now file by default without `AskUserQuestion`. Skip requires explicit 3-category taxonomy: **(a) unactionable observation** (real skip, no issue), **(b) infeasible but understood** (auto-file P3 with `blocker:infeasible` label), **(c) blocked on external state** (auto-file P3 with `blocker:waiting` label). Only (a) avoids filing — (b) and (c) preserve the parking lot.

- **`idd-close` Step 3.5 SHOULD-tier preserved** — closing summary follow-up scan retains legacy `[file all] / [file selected] / [skip]` 3-option ask (closure is wrap-up moment, not deliberation per canonical Section 6).

- **Escape hatch semantic shift** — `AI_LOW_BAR_ISSUE_FILING=false` env var + `# Disable IC_R011` repo CLAUDE.md flag preserve their names but shift semantics from "silent skip checkpoint" to "revert to pre-default-flip 3-option ask". No new env var introduced. CI / unattended (no TTY) environments with `=false` set fall back to implicit (a) skip + audit trail (no AskUserQuestion possible).

- **Audit trail format change** — `Skipped per user choice (...)` superseded by categorized `Skipped: (a)|(b)|(c) ...` lines for SHALL-tier sites. `idd-close` SHOULD-tier preserves legacy string. Downstream telemetry / log analysis tools matching the legacy string need to extend regex:
  ```bash
  # v2.72.0+ migration hint
  grep -E "Skipped(:| per user choice)" .claude/.idd/
  ```

### Refactored

- **Canonical reference `references/ic-r011-checkpoint.md` now holds the normative procedure body** (Decision 4 from #148 design): grew from 301 → 397 lines absorbing file-by-default behavior, 3-category skip taxonomy, audit trail format table (6 literal strings), Source footer normative format, Skill citation template (Section 8). 6 implementing skill SKILL.md files refactored from inline procedure duplication (~50 lines each) to cite-only form (~15-20 lines per site) per Section 8 citation template. Net effect: future IC_R011 spec changes only edit 1 file (canonical ref) instead of syncing 7 places. Maintainer grep `grep -L 'per IC_R011' plugins/issue-driven-dev/skills/idd-*/SKILL.md` returns empty (all 6 sites cite).

### Fixed

- **`idd-verify` Step 5b lacks canonical "Rule (SHALL/SHOULD)" framing** ([#149](https://github.com/PsychQuant/issue-driven-development/issues/149)): closed as side effect of #148 refactor. `idd-verify` Step 5b now opens with explicit `**Rule (SHALL)**` framing line consistent with other IC_R011 sites. Spec consistency gap eliminated.

### Notes

- Plugin v2.72.0 is a **minor** bump (over v2.70.0) covering BREAKING behavioral change. Marketplace.json sync deferred to `/idd-close` Step 6.5 chain (per repo precedent).
- Skipping 2.71.0 — intentional (BREAKING tier change deserves visible minor gap).
- Dogfood: this CHANGELOG entry itself was authored under the OLD default (3-option ask); first invocation under the NEW default is the post-apply `/idd-diagnose` test per task 5.1 acceptance.

## [2.70.0] - 2026-05-20

### Fixed

- **`idd-issue` Step 1 pasted-image immediate-persistence** ([#112](https://github.com/PsychQuant/issue-driven-development/issues/112)): Claude Code's `~/.claude/image-cache/<session-id>/` is per-session + cleared by context compaction / session lifecycle / session-id rollover. Step 1 → Step 4 separation (read annotation in Step 1, upload in Step 4) spans `AskUserQuestion` + Step 2.5/2.6 + Step 3 `gh issue create` + Step 4 upload — easily long enough for cache eviction. 2026-05-20 downstream incident (`kiki830621/ai_martech_global_scripts#788`) hit exactly this failure mode. NEW immediate-persistence rule: when Step 1 encounters `[Image: source: <path>]` annotation, `cp` to `/tmp/idd-issue-attachments/issue_pending_<ts>_<rand>.png` in the **same tool turn** that reads the annotation; Step 4 references the staged path, not the original cache path. Anonymous `/tmp` staging (POSIX-safe, system-cleanup-friendly, no repo pollution) per `feedback_lead_minimal`. Fallback for already-evicted source: warn + continue without that attachment.

### Refactored

- **`spectra-archive` skill `.agents/` ↔ `.claude/` sync** ([#93](https://github.com/PsychQuant/issue-driven-development/issues/93)): #93 surfaced 3-copy divergence between `.claude/skills/`, `.agents/skills/`, and `plugins/.../references/spectra-skills/`. Investigation refuted the diagnose-time recommendation to delete `.agents/` — 4 openspec specs reference `.agents/skills/spectra-*/SKILL.md` as Spectra-tier dependencies (the path is LIVE, not legacy). Revised disposition: sync `.agents/skills/spectra-archive/SKILL.md` from `.claude/` so both LIVE load paths carry the v1.3+ Implementation Complete auto-post feature (#56). `plugins/.../references/spectra-skills/spectra-archive/` left as historical snapshot (no markdown cross-refs found; low cleanup ROI per `lead-minimal`). **Sister-skill divergences out of scope**: 7 other spectra-* skills (audit / discuss / propose / apply / ingest / debug / commit) also diverge between `.claude/` and `.agents/` — audit comment on #93 documents the drift matrix. **Sister issues NOT auto-filed in this PR** per `feedback_lead_minimal` — drift documented as observation, separate issues will be filed if specific divergence causes user-visible friction. (Original wording "filed for separate follow-up as needed" was misleading per #115 DA finding DA-1 — no issues actually filed.) Drift-prevention CI hook deferred until drift recurs naturally.

- **`idd-implement` cluster detection glob hardening + Option A-final doc** ([#100](https://github.com/PsychQuant/issue-driven-development/issues/100)): two non-blocking findings from PR #99 (#96) verify rounds.
  - **Finding 1 (design)** — Option A (cluster mode unconditionally forces PR regardless of branch context) confirmed final. NEW `### Feature-branch + cluster + direct-commit — rejected case` subsection in `references/pr-flow.md` § Cluster mode override documenting the rejected Option B (branch-context-gated cluster direct-commit) with comparison table + rationale. Contract simplicity wins; feature-branch direct-commit workflow remains viable for single-issue `--no-pr` invocations.
  - **Finding 2 (refactor)** — `idd-implement` Step 0.5 cluster detection bash hardened. Previous glob `\#[0-9]*` over-matched (`#42abc` counted, `#34 #34` over-counted as 2). Replaced with strict integer check (`[[ "$arg_num" =~ ^[0-9]+$ ]]`) + associative-array dedup matching the documented `^#\d+$` form in `batch-and-cluster.md`. 0 behavior change for well-formed distinct invocations. **Quiet behavior change for malformed tokens** (per #115 DA finding DA-2): pre-v2.70.0, `#42abc` was counted as a cluster member (causing later failures when used as issue number); post-v2.70.0 it's silently skipped from the count. Users invoking with typo'd tokens get cluster-mode evaluation based on well-formed tokens only — failure modes shifted from "fail mid-loop on bad number" to "treat as if token not present".

### Notes

- Plugin v2.70.0 is a **minor** bump (over v2.69.0) covering 3 issues across `idd-issue` + `idd-implement` + `pr-flow.md` + `.agents/skills/spectra-archive/SKILL.md`. All changes additive (#112 immediate-persistence + #93 sync + #100 glob hardening + Option A-final documentation). Cluster PR for review surface — verify ensemble runs over the cumulative diff.
- Marketplace.json sync deferred to `/idd-close` Step 6.5 chain (per repo precedent).

## [2.69.0] - 2026-05-20

### Fixed

- **`idd-verify` DA timeout sentinel detection broadening + write-side discipline** ([#88](https://github.com/PsychQuant/issue-driven-development/issues/88)): `/idd-verify --pr 82` in downstream `PsychQuantHsu/psychophysical_representations` exposed that DA agent wrote a VARIANT sentinel string that didn't match the exact-prefix regex at Step 2.5a line 558 → coordinator missed timeout → silent N-1 engine degradation. Two-track fix per #88 diagnosis: (a) read-side regex broadened to `grep -qiE '^\[[[:space:]]*stage[[:space:]]*2\.5[[:space:]]*recovery[[:space:]]*:[[:space:]]*devils?[[:space:]_-]*advocate[[:space:]_-]*timeout'` tolerating case drift / internal whitespace / separator drift (underscore vs hyphen vs space) / apostrophe variants; (b) write-side Step 2 DA spawn block gains canonical-sentinel-string discipline comment block specifying exact required form. Defense in depth.

### Refactored

- **CRLF → LF normalization across 4 idd-* SKILL.md files** ([#95](https://github.com/PsychQuant/issue-driven-development/issues/95)): #95 surfaced CRLF line terminators in `skills/idd-implement/SKILL.md`. Audit during fix revealed 3 SISTER files with the same issue: `skills/idd-close/SKILL.md` (912 CR chars), `skills/idd-diagnose/SKILL.md` (689), `skills/idd-issue/SKILL.md` (2007). Total 4259 CR characters stripped. Pure whitespace diff (`git diff --check` clean post-fix). 0 semantic change — Claude Code reads file content as text, normalizes whitespace internally. Pre-fix: `git diff --check` flagged touched lines as 'trailing whitespace' on every edit. Direct-commit `9a7244e` (no PR — pure whitespace + 4259-line balanced diff would be review-noise-dominated).

### Notes

- Plugin v2.69.0 is a **minor** bump (over v2.68.0) covering 2 fixes shipped via direct-commit (no PR). Direct-commit defensible for: (a) line-ending normalization (#95) where PR diff would be review-noise-dominated and `git diff --check` is sufficient verification; (b) DA sentinel regex broadening (#88) where the change is a localized regex tightening with clear rollback path and no cross-skill interactions.
- Marketplace.json sync deferred to manual cycle (this release didn't go through `/idd-close` Step 6.5 chain because both issues closed via direct-commit + audit comment paths).

## [2.68.0] - 2026-05-20

### Changed

- **Phase 0.4 diagnosis-detection precision sweep** ([#59](https://github.com/PsychQuant/issue-driven-development/issues/59), [#64](https://github.com/PsychQuant/issue-driven-development/issues/64), [#65](https://github.com/PsychQuant/issue-driven-development/issues/65)): 3 sister fixes from [#53](https://github.com/PsychQuant/issue-driven-development/issues/53)'s verify follow-up family.
  - **#59** — `idd-all` 2 substring sites (line 450 complexity readback + line 533 Spectra context capture) swapped from `'## Diagnosis' in c['body']` to line-anchored `re.search(r'(?m)^## Diagnosis', c['body'])`, matching `check-diagnosis-readiness.sh` canonical convention shipped in #53 / PR #58. Cited `idd-list:115` / `idd-update:120` sites are prose, not code; `idd-close:416` uses `startswith()` (already line-1-anchored).
  - **#64** — `scripts/check-diagnosis-readiness.sh` regex widened from `^## Diagnosis` to `^[ ]{0,3}## Diagnosis` for CommonMark spec's 1-3 space leading indent tolerance on ATX headings. 0 behavior change for canonical IDD comments (col-0 = `[ ]{0}`).
  - **#65** — NEW comment block in `scripts/check-diagnosis-readiness.sh` documenting line-based detection's fenced-code false-positive limitation (Approach A from diagnosis decision point). Mitigation is the chain Phase 0.4 AskUserQuestion user override.

### Notes

- Plugin v2.68.0 is a **minor** bump (over v2.67.0): 3 same-family precision fixes from #53 verify follow-up. All additive.
- **Not in scope this PR**: [#61](https://github.com/PsychQuant/issue-driven-development/issues/61) (shell test fixture infra) — Plan-tier with framework-choice surface deferred per `feedback_lead_minimal`. Stays diagnosed.
- Marketplace.json sync deferred to `/idd-close` Step 6.5 chain (per repo precedent).

## [2.67.0] - 2026-05-20

### Changed

- **`idd-issue` multi-finding mode — 5-issue spec hardening family from #48 verify** ([#75](https://github.com/PsychQuant/issue-driven-development/issues/75), [#76](https://github.com/PsychQuant/issue-driven-development/issues/76), [#77](https://github.com/PsychQuant/issue-driven-development/issues/77), [#79](https://github.com/PsychQuant/issue-driven-development/issues/79), [#80](https://github.com/PsychQuant/issue-driven-development/issues/80)): 5 sister issues from #48's 6-AI verify, all same-file (`skills/idd-issue/SKILL.md`), shipped as one chain.

  - **#75 — Content sanitization contract** (security). NEW `### Content sanitization contract (v2.67.0+, #75)` subsection: dual-track contract (jsonl `finding_quote` verbatim per IC_R007 line 1007 + GitHub body `finding_quote_display` sanitized — strip C0/C1 control chars, warn-and-strip bidi-override U+202A-U+202E + U+2066-U+2069, normalize CRLF); `sanitize_source_label()` bash helper that strips control chars + escapes backticks + **refuses** (not silently strips) embedded `@[A-Za-z0-9_-]+` mention tokens (cross-references `rules/tagging-collaborators.md` 5-step protocol); mandate `jq --arg` / `--argjson` parameter binding (refuses string-interpolation anti-pattern vulnerable to JSON injection). `finding_quote` CAUTION banner above schema makes the untrusted-content invariant readable from the file itself.

  - **#76 — `run_id` collision + symlink overwrite hardening** (bug). `run_id` format: ISO-8601 second precision → millisecond precision + UTC Z suffix + nonce-retry on collision. Pre-v2.67.0 second-precision collided under parallel `/loop` / CI batch / concurrent terminals → silent audit-trail overwrite (the **irreversible-side-effect** failure mode added to Layer P vocabulary in v2.64.0 #103 F4). TOCTOU symlink check before jsonl write (`[ -L "$JSONL_PATH" ] && abort`) closes the predictable-path + truncate-write hardening gap (attacker with local FS write access could pre-create the audit path as a symlink at e.g. `~/.ssh/authorized_keys`). Noclobber retry helper (`JSONL_WRITE_GUARD`) on hostile concurrency.

  - **#77 — 7 corner-case spec contract gaps** (enhancement). Gap 1 — flag-conflict refusal layering table (explicit flag pairs at Step 0 arg-parse vs auto-trigger conflicts post-Stage 1). Gap 2 — `partner_eligible_set` formal definition consolidating rules previously 18 lines apart. Gap 3 — Stage 3 `[Edit row N]` soft cap at >5 cumulative edits. Gap 4 — `[Back to top-3]` added as 5th option in Stage 2 Other second-level picker. Gap 5 — Stage 1 entry MUST canonicalize source paths + refuse paths outside repo work tree. Gap 6 — agent-crash recovery documented as known gap with trade-off rationale. Gap 7 — Stage 4.5 unattended-mode fallback (no TTY + `IDD_ALL_UNATTENDED` / `CI` → auto-default to `skip-commit`).

  - **#79 — Audit trail completeness** (enhancement). Gap 1 — abort-path now writes minimal `aborted: true` jsonl with `actions[]` already dispatched + partial timestamps; footer link no longer 404s after abort. Gap 2 — footer template adds `> **Action**: {create|comment|edit|update}` line. Gap 3 — schema `source_type` enum adds `"srt"` as first-class adapter.

  - **#80 — Stage 1 reproducibility + Stage 2 scoring + N<3 picker** (enhancement). Gap 1 — Stage 1 anchor heuristics for "AI MAY merge / MAY split" clauses. Gap 2 — `max_possible_score` denominator explicitly defined as `title_token_count × 2 + min(body_token_count, 300) × 1`. Gap 3 — degenerate-case picker shape table (N=0 → skip to Other; N=1 → 1+Other; N=2 → 2+Other; N≥3 → unchanged).

  Schema additions: `aborted?: boolean` (#79 Gap 1), `"srt"` enum value (#79 Gap 3), CAUTION banner above schema (#75 F1). Audit footer additions: action type line (#79 Gap 2), validity caveat (#79 Gap 1). All changes additive.

### Notes

- Plugin v2.67.0 is a **minor** bump (over v2.66.0): 5 same-file spec hardening additions to `idd-issue` multi-finding mode. No behavior change for inputs that already worked correctly under the looser pre-v2.67.0 contracts; user-visible changes for inputs that exercised the corner-case gaps (hostile concurrency, abort path, srt sources, etc.).
- Marketplace.json sync deferred to `/idd-close` Step 6.5 chain (per repo precedent, same path used by #103 / #102 / #110).

## [2.66.0] - 2026-05-20

### Added

- **`idd-close` Step 3.6 — Residue Acknowledgement** ([#105](https://github.com/PsychQuant/issue-driven-development/issues/105)): closes the `### Residue` write-only loop from #103. v2.64.0 added `### Residue` to the Diagnosis template (NSQL §4.6 — non-operationalizable intent) but no downstream skill consumed it. Per #103 PR #104 Devil's Advocate finding D2: "latent capacity for the section to drift into ritual filler with no consumer pressure to keep it honest." Step 3.6 gives Residue its first consumer at close time. Reads latest `## Diagnosis` comment's `### Residue` section (mirrors Step 0 supersession). Silent skip when section missing, content is `(none)`, or pre-v2.64.0 format. When non-empty, AskUserQuestion 3-option (`still residue — acknowledge` / `file as follow-up issue(s)` / `skip — audit trail only`). Audit trail PATCH appends `### Residue Acknowledgement` to the in-memory closing summary draft before publish. Filed follow-ups get spawn manifest entries when chain context active. SHOULD-tier (non-blocking) per closure-tier IC_R011 eligibility. Step 0.5 Bootstrap adds `residue_acknowledgement` task. Placement mirrors Step 3.5's drafted-summary-scan pattern; must run before Step 4 publish so audit PATCH operates on same draft.

- **`idd-issue` Step 5 — CI/loop hard-parse warning** ([#107](https://github.com/PsychQuant/issue-driven-development/issues/107)): #103 PR #104 expanded `idd-issue` Step 5 from metadata-only to also echo AI-rendered `## Type` / `## Expected` / `## Actual` + plain-language interpretation. Strictly better for human readers (misparse catchable from terminal) but a silent surface change for CI / `/loop` scripts that hard-parse Step 5 stdout. Adds one ⚠ paragraph mirroring the v2.55.0 `--no-multi-finding` CI warning precedent. Wording is near-verbatim from the issue body's `## Expected`, with two skill-internal additions: the `#107` self-reference suffix on the `v2.64.0+` marker, and a parenthetical pointer to the parallel precedent (no line number — paths rot). No behavior change — purely defensive documentation.

### Changed

- **PR-body checklist wording aligned across the IDD documentation family** ([#108](https://github.com/PsychQuant/issue-driven-development/issues/108)): #102 shipped the NSQL doctrine that `verify-gated PASS` is the terminal default disposition but only updated `idd-all-chain` Phase 5; the parallel templates were intentionally deferred. #108 closes the 5-template + 3-satellite consistency family.
  - **4 PR-body templates** (`skills/idd-implement/SKILL.md:503` + `skills/idd-all/SKILL.md:755` + `references/pr-flow.md:135` + `references/chain-flow.md:254`) drop legacy `Pending: human review of this PR + /idd-close after merge` framing; default wording becomes `- [x] **Verify-gated**: PR verify PASS — ready to merge → /idd-close #${NUMBER} after merge` (or cluster variant for `chain-flow.md`). Per Option A from #108 diagnosis: `idd-implement` does NOT accept `--review` flag (remains `idd-all` + `idd-all-chain` only); direct `idd-implement` invocations get the default wording without conditional.
  - **F3 satellite** — `idd-all-chain` Phase 4 final stdout report dispatches on `$REVIEW_FLAG`: default emits `Verify: verify-gated PASS across cluster — cluster ready to merge` + `Next: Merge → /idd-close`; with `--review` emits `awaiting human acceptance (re-opened confirmation loop per --review)` + `Next: Review PR → Merge after acceptance → /idd-close`. Built via explicit `if/else` before the heredoc to avoid the `${VAR:-word}` mutex pitfall hardcoded into the doctrine after PR #109 F1.
  - **Trace 1 example refresh** — `idd-all/SKILL.md` Trace 1 example block (lines 893-901) shows the v2.65.0+ wording: default `Verify: verify-gated PASS` + `Next: merge`, with a parallel `--review` variant block showing `awaiting human acceptance` + `merge after acceptance`. Aligns documentation with actual Phase 6 output.
  - **DA3 wording precision** — `--review` flag is now described as **orchestrator-scope messaging-only** (was just `messaging-only`) in 3 sites (`idd-all` Phase 0 args parsing comment, `idd-all-chain` Phase 0 args parsing comment, `MANIFESTO.md` Human-in-the-loop `--review` paragraph). The qualifier prevents the misreading: the flag is messaging-only AT THE ORCHESTRATOR (doesn't change skill behavior, doesn't make orchestrator wait), but humans + CI parsers downstream can react to the changed text differently — so the flag is not messaging-only end-to-end.

### Notes

- Plugin v2.66.0 is a **minor** bump (over v2.65.0): new `idd-close` step (additive behavior at close time) + 4 default PR-body wording strings change (user-visible diff in every PR opened by IDD orchestrators) + new conditional in `idd-all-chain` Phase 4 stdout. Patch would have under-claimed.
- Marketplace.json sync deferred to `/idd-close` Step 6.5 chain (per repo precedent, same path used by #103 / #102).

## [2.65.0] - 2026-05-20

### Added

- **`MANIFESTO.md` — Human-in-the-loop: IDD 即 NSQL Confirmation Protocol section** ([#102](https://github.com/PsychQuant/issue-driven-development/issues/102)): formalizes the doctrine that IDD's human-in-the-loop **is** an instance of the NSQL Confirmation Protocol ([kiki830621/NSQL](https://github.com/kiki830621/NSQL) v4.1.0, already registered as a reference project in CLAUDE.md via #103's `fd2f21c`). Doctrine elements: (1) NSQL confirmation loop ⇆ IDD pipeline mapping table — human's confirmation loop closes **before** execution (at `issue` + `idd-diagnose`); `idd-verify` is an execution-fidelity check, not a confirmation loop. (2) **`verify-gated` is the named, sanctioned terminal default disposition** — one clean 6/6 verify PASS is sufficient to merge; issue was the acceptance contract, verify confirmed delivery. (3) Verify-as-review reframe — 5 specialized adversarial agents + an independent model (Codex) on correctness exceed a single human merge reviewer's thoroughness; "AI verify PASS = no review" is a backwards read. (4) **`--review` flag — opt-in to re-open the confirmation loop**, NOT a quality gate, per-invocation flag (NOT a standing config field — exceptions don't warrant standing policy). (5) auto-merge legitimacy under verify-gated PASS, justified by "verify is the gate" (not "merges are reversible"); guardrails mandatory; `auto-merge ≠ auto-close`; autopilot mechanics belong to [#37](https://github.com/PsychQuant/issue-driven-development/issues/37) — `idd-all` default behavior unchanged (鐵律 `永遠不 auto-merge PR` stays).

- **`--review` flag on `idd-all` + `idd-all-chain`** ([#102](https://github.com/PsychQuant/issue-driven-development/issues/102)): per-invocation messaging-only flag implementing the MANIFESTO doctrine above. Default Phase 6 report on `idd-all`: `Verify: verify-gated PASS` + `Next: merge <PR>, then /idd-close #N` (drops the legacy `Pending: human review` framing that implied a default second gate). With `--review`: `Verify: verify-gated PASS — awaiting human acceptance (re-opened confirmation loop per --review)` + `Next: review PR, merge after acceptance, then /idd-close #N`. `idd-all-chain` mirrors the same pattern: Phase 0 args parsing recognizes `--review`, Phase 2 chain loop propagates the flag to each chained `/idd-all #M --in-chain` invocation (so per-issue Phase 6 reports also reflect), Phase 4 cluster PR body checklist dispatches conditionally — default `- [x] Verify-gated: per-issue verify PASS — cluster ready to merge`, `--review` → `- [ ] Pending: human acceptance review of cluster PR (per --review flag)`. Flag is orthogonal to `--pr`/`--no-pr`/`--in-chain`/`--bfs`/`--cwd` (no mutex). Effect is messaging-only — does NOT make the orchestrator wait, does NOT change `idd-implement`/`idd-verify`/`idd-close` internals.

### Notes

- Discuss-conclusion-aligned scope: `idd-implement` Step 5.5 + `idd-all` Phase 5 + `references/pr-flow.md` + `references/chain-flow.md` PR-body checklist wording **intentionally left at old wording** in this release. Sister consistency follow-up tracked as [#108](https://github.com/PsychQuant/issue-driven-development/issues/108) — "Sync PR-body checklist wording to match #102 NSQL doctrine" — to land in a separate PR. (Originally 4 templates; surfaced as 5-template family during /idd-implement #102 Step 5.7 sister sweep — `chain-flow.md:254` is the canonical chain-shell contract doc that mirrors the same `Pending: human review of cluster PR` wording the orchestrator skills used to emit.)

## [2.64.0] - 2026-05-20

### Changed

- **IDD human-in-the-loop reconciled to the NSQL confirmation protocol** ([#103](https://github.com/PsychQuant/issue-driven-development/issues/103)): NSQL ([kiki830621/NSQL](https://github.com/kiki830621/NSQL) v4.1.0) is registered as a reference project in the repo `CLAUDE.md`; this change aligns IDD's front-half human touchpoints to it. **F1** — `idd-issue` Step 5 report now echoes the AI-rendered interpretation (`## Type` / `## Expected` / `## Actual` + plain-language interpretation), so a misparse is catchable without opening the issue (NSQL `run → report` — creating an issue is reversible, so no confirm gate, but the report must state *what was done*). **F2** — `idd-diagnose` Layer V `clarify now` now renders candidate interpretations for the user to pick (NSQL P1, Read-Only for Humans), with free-text as the named fallback for un-enumerable questions. **F3** — the Diagnosis report template gains a `### Residue` section (NSQL §4.6 — non-operationalizable intent / horizon is marked, not silently dropped; distinct from Layer V vagueness: Layer V = the issue is unclear, residue = the issue is clear but part of its intent is non-operationalizable). **F4** — the Layer P "risk-sensitive boundary" signal (`rules/sdd-integration.md` + the `idd-diagnose` Step 3.5 inline copy) adds "irreversible side effects" to its enumerated list. Diagnosed Spectra → `/spectra-discuss` re-evaluated the 4 audit findings under NSQL v4.1.0's traceability gate (F1 dissolved from "add a confirm gate" to "echo the report"; F4 downgraded from a new mechanism to wording) → re-routed to Plan. The IDD↔NSQL doctrine in `MANIFESTO.md` is #102's deliverable, not #103's.

## [2.63.0] - 2026-05-19

### Added

- **`## Cluster-PR eligibility` section in `references/batch-and-cluster.md`** ([#60](https://github.com/PsychQuant/issue-driven-development/issues/60)): criteria table (same-file / same-skill / same-root-issue / same-label / same-review-timing) + >50-line review-surface heuristic for the bundle-vs-split decision; cross-ref from `idd-implement` Cluster-PR mode.
- **`openspec/CONVENTIONS.md`** ([#90](https://github.com/PsychQuant/issue-driven-development/issues/90)): documents the `**GitHub-side tracker**: #NN` canonical Spectra-proposal → GitHub-issue linking convention. (R1 placed it at `openspec/LANGUAGE.md`; 6-AI verify caught that as a reserved spectra-discuss vocabulary filename → R2 relocated to `CONVENTIONS.md`.)
- **`Step 0: Bootstrap Stage Task List` in `.claude/skills/spectra-archive/SKILL.md`** ([#91](https://github.com/PsychQuant/issue-driven-development/issues/91)): 8 `TaskCreate` entries matching the idd-* Bootstrap pattern. The tool-managed command-file surface was intentionally left untouched — its gap is folded into #93.

### Changed

- **`references/usecase-routing.md`** — decision-tree bulk-solve note pointing to row 27 ([#62](https://github.com/PsychQuant/issue-driven-development/issues/62)); `#44 chain-solve` given an explicit URL link in row 27 ([#63](https://github.com/PsychQuant/issue-driven-development/issues/63)).
- **Retroactive notice — v2.55.0 multi-finding behavioral change for CI callers** ([#78](https://github.com/PsychQuant/issue-driven-development/issues/78)): from v2.55.0, `idd-issue source.docx` auto-enters multi-finding mode when the source contains ≥2 findings — changed from the pre-v2.55.0 always-single-issue behavior. Automated / CI / `/loop` callers expecting the legacy single-issue output **must pass `--no-multi-finding` explicitly**. `idd-issue/SKILL.md` now carries this notice inline at the multi-finding override-flags section. (No standalone `## [2.55.0]` entry exists in this CHANGELOG; this is the retroactive record.)

> The 6 issues above are the Simple-tier subset of an 18-issue `/idd-diagnose` batch (6 Simple / 12 Plan) from the #96-backlog cleanup, shipped via cluster-PR #101 (squash `0eb419c`), 6-AI verified R1 CONDITIONAL → R2 PASS.

## [2.62.0] - 2026-05-19

### Added

- **Cluster mode override — `pr-flow.md` canonical doc + `idd-implement` Step 0.5 bash** ([#96](https://github.com/PsychQuant/issue-driven-development/issues/96)): resolves a 3-file contradiction in IDD's PR-vs-direct-commit path resolution. `pr-flow.md`'s resolution-algorithm table had no cluster carve-out while `idd-implement/SKILL.md:49` + `batch-and-cluster.md:133` independently asserted cluster forces PR; `--no-pr` + cluster collision behavior was undefined.

  - **`pr-flow.md` `### Cluster mode override`** — cluster mode (≥2 `#N` args) is an `idd-implement` path-resolution precondition that pre-empts the algorithm table and forces PR path. `idd-verify` / `idd-close` are cluster-aware but consume the path, don't resolve it. Explicit override notice mirrors fork detection; fork+cluster co-occurrence prints both notices.
  - **`idd-implement` Step 0.5 bash** — cluster detection wired: parse `#N` token count → `CLUSTER_MODE` → pre-empt block → `OVERRIDE_SRC` accumulation prints `→ cluster mode (N issues) → PR path enforced (overriding --no-pr / pr_policy=never)`. Local algorithm summary gains row 0.
  - **`batch-and-cluster.md:133`** — rule statement demoted to a pointer at the new canonical section.

  Option A (user-selected from 3 diagnosis candidates). Verified 6-AI × 2 rounds (R1 CONDITIONAL doc/code gap → R2 6/6 PASS with bash impl) + R3 doc fix. Backward compat: single-issue invocation byte-equivalent — cluster carve-out only fires on ≥2 `#N`. Follow-up [#100](https://github.com/PsychQuant/issue-driven-development/issues/100) tracks 2 non-blocking items (feature-branch cluster tension, glob looseness). PR #99 squashed as `b7f72ff`.

## [2.60.0] - 2026-05-18

### Added

- **`/idd-all-chain` multi-root + DFS/BFS traversal + per-root halt** ([#46](https://github.com/PsychQuant/issue-driven-development/issues/46), `multi-root-traversal-idd-all-chain` Spectra change):chain-solve mode 從 single-root 擴成 multi-root forest orchestrator。N=1 行為 byte-equivalent backward compat;N>1 開新能力。

  - **Multi-root invocation**:`/idd-all-chain #A #B #C [--bfs] [--cwd <path>]` 接受 ≥1 root issue。N>1 開 cluster branch `idd/chain-multi-<hash8>-<root1-slug>`(hash8 = first 8 hex of sha256 over sorted-asc roots joined by `-`;collision fallback hash16,double-collision abort)。
  - **NEW `--bfs` flag**:BFS traversal mode(spawn push-back queue,level-by-level across roots,fairness 優先)。Default DFS(spawn push-front,rich subtree first per root)。
  - **Cap redesign for multi-root**:per-root `chain_max_depth` 2→3、global `chain_max_issues` 5→10。兩 cap 獨立 apply,whichever triggers first 勝。每 root subtree 獨立 depth=0 起算。
  - **Verify FAIL = per-root halt**(D4 Option C):failing issue 的 `root_id` 加入 `FAIL_ROOTS`,同 root_id 從 QUEUE 清出,其他 root subtree 繼續(不是 global halt),commits preserved;Phase 4 per-root PASS/FAIL summary 顯示。
  - **PR title dispatches**:N=1 `chain: <root title>`(backward compat);N>1 `chain (multi-root): N issues — <root#1 title>`。Cluster overview table 加 `root_id` 欄位。
  - **Phase 4 forest tree printout**:per-root subtree 含 status icons(`✓` PASS / `✗` FAIL / `⊘` filed-but-not-chained)+ depth + spawn source attribution;per-root PASS/FAIL summary block;filed-only-not-chained list。

### Changed (BREAKING)

- **Spawn manifest schema v1 → v2**:top-level `root_issue: int` 改為 `root_issues: [int]`,加 `traversal: "dfs"|"bfs"`,每個 spawn entry 加 `root_id: int`(必為 `root_issues` 元素之一)。
  - Helper `scripts/manifest-append.sh` bumps `EXPECTED_SCHEMA_VERSION` 1→2,接受 9th positional arg `root_id`,validates `root_id ∈ root_issues`,fail-fast on v1 manifest detection(no silent migration)。
  - 4 sub-skills(`idd-implement` / `idd-verify` / `idd-plan` / `idd-diagnose`)透過 `IDD_CHAIN_CURRENT_ROOT_ID` env var(Phase 2 chain loop export)傳第 9 個 arg。Defensive `[ -n "$ROOT_ID_FOR_MANIFEST" ]` guard 預防 unset 變數造成 silent skip。
  - **無 v1 callers in the wild**:manifest 是 per-chain-session transient state(每次 Phase 0 重建,無 cross-session 持久化 client),hard-break 安全。

### Fixed

- **`idd-all-chain/SKILL.md` `allowed-tools` frontmatter 補齊**:新增 11 個 Bash tools(`shasum / sed / tr / cut / sort / seq / grep / awk / printf / date / head` 等)for Phase 0.5 branch naming + Phase 4 forest rendering。修復 first N>1 chain invocation 撞 permission gate 的 P1。
- **Sub-skill `ROOT_ID_FOR_MANIFEST` 防禦性 guard**:`${IDD_CHAIN_CURRENT_ROOT_ID:-${NNN:-}}` + `if [ -n ]` 包裹,避免 fallback chain 同時 unset 時 silent skip(`|| true` 吞錯誤的歷史 trap)。

### Documentation

- **Modified specs**:`idd-all-chain`(3 MODIFIED + 1 ADDED Requirement)+ `idd-spawn-manifest`(3 MODIFIED)。Spec deltas in `openspec/changes/multi-root-traversal-idd-all-chain/`,將在 `/spectra-archive` 階段 merge 進 main specs。
- **Updated reference docs**:`references/spawn-manifest.md` v2 schema + multi-root example;`references/chain-flow.md` DFS/BFS algorithm + per-root halt scope + cap interaction + branch naming hash rule + PR title/body dispatch。
- **Cap docs sync**:`CLAUDE.md` skills table + Chain-Solve Mode section、`README.md` skills table、`references/usecase-routing.md` row 25 全部 reference v2.60.0+ caps。

### Testing

- **Smoke tests 7.1+7.2** 標 `[~]` first-real-use validation track per `## Checklist Conventions` IDD discipline:orchestration tests cannot mock GitHub API + git operations without significant fixture infrastructure(mirroring [#52](https://github.com/PsychQuant/issue-driven-development/issues/52) idd-verify validation pattern)。Manifest helper 4 unit tests pass(8-args→exit 2 / 9-args→exit 0+root_id written / v1-manifest→exit 1 / bad root_id→exit 2);branch naming deterministic smoke validated。

## [2.59.0]

### Added

- **`/idd-all-chain` skill — chain-solve mode** ([#44](https://github.com/PsychQuant/issue-driven-development/issues/44), `add-idd-all-chain-skill` Spectra change):root issue + auto-emergent spawned issues 自動接續解,**單一 cluster branch + 單一 review PR**。Reviewer 拿回 holistic view,使用者不必手動逐一跑 `/idd-all #M`。

  - **NEW skill `/idd-all-chain #N`**:thin shell over `/idd-all`,內部 recursive 呼叫 `/idd-all #M --in-chain`。Phase 0 建 cluster branch `idd/chain-<N>-<slug>` from default branch、Phase 2 main loop pop queue + invoke sub-`/idd-all` + read manifest delta + enqueue eligible spawns、Phase 3 開 cluster PR(title prefix `chain:`、collapsed `<details>` per issue)、Phase 4 final report STOP at verified(永不 auto-close,維持 IDD 紀律)
  - **NEW `--in-chain` flag on `/idd-all`**:single source for chain context,推導 4th mode tuple `(direct-commit, unattended)`。Sub-`/idd-all` skip Phase 0.5 PR-mode branch creation + skip Phase 5.5 PR open + sub-skill 收 `UNATTENDED MODE` directive。與 `--pr` / `--no-pr` 互斥 abort
  - **NEW spawn manifest contract**:`.claude/.idd/state/chain-spawned-issues.json` schema_version=1,4 個 sub-skill(`idd-implement` / `idd-verify` / `idd-plan` / `idd-diagnose`)在既有 sister-sweep / follow-up-finding / tangential / sister-concern step append entry。Manifest writes atomic via temp-file rename。Schema mismatch abort。Helper script `scripts/manifest-append.sh`
  - **Chain caps(hard-coded)**:`chain_max_depth = 2`、`chain_max_issues = 5`(含 root)。超過 cap 仍 file 為 follow-up issue 但不 enqueue
  - **Chain-eligible heuristic**:`same_file_as_root OR same_skill_as_root OR spawn_kind="sister-bug"`。不 eligible 仍 file 但不 chain solve
  - **Failure mode**:任一 chained verify FAIL → halt queue + preserve partial commits(無 rebase / revert)+ 印 abort report 含 4 條 recovery paths
  - **NEW reference docs**:`references/spawn-manifest.md`(schema canonical contract)、`references/chain-flow.md`(chain shell algorithm canonical contract)
  - **MODIFIED capability `idd-orchestrator-modes`**:加第 4 種 mode tuple `(direct-commit, unattended)` for chain context;既有 3 tuples 行為不變
  - Backward compat:`/idd-all #N`(不帶 `--in-chain`)行為與 v2.53.0 baseline byte-equivalent

- **`idd-issue` multi-finding source mode** ([#48](https://github.com/PsychQuant/issue-driven-development/issues/48), `add-multi-finding-source-mode-to-idd-issue` Spectra change):從 multi-finding source(transcript / docx / pasted text 等)分流 N 個 findings 到 mixed routing(部分 new issue、部分 amend 既存 #N comment / edit body / update Current Status),解決 5/9 真實 friction(5 次手敲 `gh api PATCH` 浪費 2.5 min + 失 audit trail)。

  - **Auto-trigger when ≥2 findings extracted**:Step 1 source extraction 後 detect `len(findings) >= 2` 進 mode;1 finding 時 fall through single-issue。Override flags `--multi-finding`(force in)/ `--no-multi-finding`(force out),同時 set 兩個 flag refuse;與 `--bundle-mode` 互斥 refuse(不同 mental model:bundle = explicit ordered/unordered creation,multi-finding = source-driven mixed routing)
  - **4-stage pipeline**:Stage 1 Extract paragraph-level findings 含 verbatim quote + AI summary(no rewording per IC_R007 source-preservation);Stage 2 Per-finding picker — AI compute keyword overlap score `(title × 2 + body[:300] × 1)` 從 `gh issue list --state open --search "<noun phrases>"` candidates 取 top-3,4-option AskUserQuestion `[#X(score)] [#Y(score)] [#Z(score)] [Other]`,picked existing 觸發 intent disambiguation `[comment] [edit body] [update status] [skip]`;Stage 3 Batch preview single AskUserQuestion `[Execute all] [Edit row N] [Cancel]`,`Edit row N` re-invokes Stage 2 picker for that finding only;Stage 4 Dispatch warn-continue,失敗 log to jsonl `actions[i].error` + `retry_hint` 不 abort 不 rollback,結束 print summary
  - **Audit trail dual-track**:per-action body footer `> Surfaced via /idd-issue multi-finding mode <run_id> from <source>` + structured JSONL at `.claude/.idd/issue-runs/<ISO-8601-run-id>.jsonl` **committed to git**(non-gitignored,for cross-machine continuity)。JSONL schema: `run_id` / `source` / `source_type` / `total_findings` / `actions[]` (含 `finding_id` / `finding_quote` / `action` / `issue_number` / `issue_url` / `comment_url` / `duration_ms` / `merged_from` / `merged_into` / `error` / `retry_hint` / `reason`) / `started_at` / `completed_at` / `succeeded` / `failed` / `skipped`
  - **Two-way merge**:Stage 2 picker `[Merge with another finding]` 觸發 inline sub-prompt:partner picker(4-option from remaining unprocessed findings)→ combined target picker → intent disambiguation;single combined dispatch on primary entry,partner entry `action: "merged-into"` 無 issue_url。JSONL `merged_from: [<partner_id>]` in primary,`merged_into: <primary_id>` in partner — bidirectional traceability。Three-way+ merge **refused**(已 merged 的 finding 不能再被選 partner)
  - **NEW capability `idd-issue-multi-finding-source`**(parallel to existing `idd-issue-bundle`):both extend idd-issue with non-overlapping modes orthogonal to single-issue creation。SKILL.md 新增 `## Multi-finding source mode` section 含 trigger detection / 4-stage pipeline / Stage 0 Bootstrap conditional TaskCreate(`extract_findings` / `per_finding_picker` / `batch_preview` / `dispatch_with_warn_continue` / `merge_handler`)/ examples
  - **Cross-reference updates**:`idd-comment` / `idd-edit` / `idd-update` SKILL.md 各加「When to use idd-issue multi-finding mode instead」段落,redirect batch source workflows from manually invoking N times → 一次 idd-issue invocation
  - **5 architectural decisions** D1-D5 from spectra-discuss session 2026-05-10:D1 user-route(rejected AI-route — AI surface candidates 不 decide)/ D2 hybrid audit trail(footer + commit jsonl)/ D3 AI surface top-3 candidates picker UX / D4 batch preview + warn-continue / D5 merge = combine routing target inline sub-prompt 二方。+ 2 derived D6 trigger detection auto-detect + D7 mutual exclusion gate
  - **Backward compat**:既有 `idd-issue` invocation byte-equivalent — single-text / single-finding source / `--bundle-mode ordered/unordered` / `--target group:<label>` / `--mention <login>` / `--parent <N>` / `--blocked-by <M>` 全部不變。Multi-finding mode 是 additive trigger,既有 invocation pattern 不會誤進 mode

## [2.52.0] - 2026-05-05

### Added

- **`idd-issue` ordered/unordered bundle flags** ([#21](https://github.com/PsychQuant/issue-driven-development/issues/21), `add-bundle-flags-to-idd-issue` Spectra change):IDD 第三軸正交支援上線 — milestone(分組)、group(跨 repo)、bundle(同 repo parent-child + dependency)。

  - **NEW `--parent <N>`**:child 建完後 PATCH parent #N body 加 task list entry。Idempotent via `#N` reference scan;parent 沒 task list 時 fallback 建 `## Children` anchor 段落
  - **NEW `--blocked-by <M>[,<M2>...]`**:三層 fallback chain 全部執行 — Layer 1 GraphQL `addBlockedByDependency` 嘗試(失敗 → warning + continue,不 abort)、Layer 2 child body 加 `> Blocked by #M` blockquote(無條件,markdown 永遠可讀)、Layer 3 parent task list entry 加 `(blocked by #M)` 註解(僅 `--parent` co-used 時)
  - **NEW `--bundle-mode <ordered|unordered>`**:單次 invocation 建 1 個 epic + N 個 children。`ordered` 加嚴格 `child[i] blocked by child[i-1]` 鏈、`unordered` 純 task list 無 dependency
  - **Pre-flight gates**:cross-repo refuse(parent 在不同 repo → abort + 指引 `groups` 機制)、bundle-mode 與 group-mode 互斥(refuse if both)
  - **Step 3.B** 插在 3.A(single repo)和 3.G(group)之間,reuse 3.A 作 primitive
  - **Step 0 TaskCreate** 加 `resolve_parent_link` / `apply_blocked_by` / `orchestrate_bundle_mode` 三個 entry
  - **正交保證**:Step 4.5 milestone(bundle children 仍 assign 到 milestone)、Step 4.7 sister sweep(epic parent 仍跑 sweep,sibling issues 不加進 bundle task list)、`groups` 機制(互斥但可漸進組合)

- **NEW canonical reference doc** `plugins/issue-driven-dev/references/bundle-flags.md`:flag spec、edit algorithm、fallback chain、partial failure handling、idempotency contract

- **NEW `## Ordered Bundle Pattern` section** in `idd-issue` SKILL.md(放在 Step 5 之後 / `## 來源文件規則` 之前):3-mode 對照表(parent + task list / native dependency / milestone)、3 種使用情境(單 child 加進既存 parent / 從零建完整 ordered bundle / retrofit 既存散落 issue)、設計理由(為什麼不另開 `/idd-bundle` skill)、反模式

- **NEW capability** `idd-issue-bundle` in `openspec/specs/`(由本 change archive 後生成)

### Spectra change

`add-bundle-flags-to-idd-issue` — Feature change covering 3-flag interface + reference doc + SKILL.md sections。Decision-heavy with multiple valid approaches(mega flag vs three flags;hard refuse vs degrade;separate skill vs flag),適合走 Spectra path 凍 spec contract 給未來 caller 參考。

### Backward compatibility

- 全部 flag 都是 **additive**:既有 `idd-issue` invocation(無 flag)行為**完全不變**
- Step 4.5 auto-milestone 對 bundle 透明(children + epic 都 assign milestone)
- Step 4.7 sister sweep 對 epic parent 仍跑(orthogonal concern,不污染 bundle task list)
- `groups` 機制完全保留作為 cross-repo 機制(bundle 偵測到跨 repo → refuse + 指引 groups)
- 無 flag deprecation、無 config schema 改動

## [2.51.0] - 2026-05-04

### Added

- **`idd-list` shows open PR info + cluster detection** ([PsychQuant/issue-driven-development#13](https://github.com/PsychQuant/issue-driven-development/issues/13)): `idd-list` 從「列 issue phase + next action」升級為「列 issue + 對應 open PR + cluster 結構 + PR-aware actionable next」。

  - **NEW Step 2.5**: batch fetch all open PRs once via `gh pr list --state open --limit 100 --json number,title,body,isDraft,mergeable,headRefName,createdAt,url`. 一次 query,不是 per-issue N+1(後者無法偵測 cluster)
  - **NEW Step 3.5**: client-side regex `#(\d+)\b` scan PR body 反向建 `issue→PR` index + cluster map(同 PR ref ≥ 2 issue)。Cluster leader = `min(refs)` deterministic
  - **Step 4 Format Output 擴充**:每個 issue 有 PR ref 時加 `└─ PR #N (draft|ready, MERGEABLE|CONFLICTING)` 子行;cluster leader 加 `— cluster: #X #Y #Z`;cluster member 顯示 `→ see PR #N (cluster member)`。Direct-commit issue **不加** 子行(完全 backward compatible)
  - **Footer 擴充**:第二行加 `N issues bundled in M cluster(s); P solo PR(s); Q direct-commit` 統計(無 open PR 時 footer 維持 v2.50 格式)
  - **Step 5 Suggest Next 擴充**:phase × PR state matrix(10+ rows)。`implemented + draft` → `gh pr ready N → /idd-verify --pr N`;`implemented + ready MERGEABLE` → `/idd-verify --pr N`;`verified + ready MERGEABLE` → `gh pr review N → gh pr merge N → /idd-close #N`;`verified + merged` (catch-up) → `/idd-close #N`;`CONFLICTING` → `gh pr checkout N → resolve`;cluster member → `see leader's next action`

- **Step 0 TaskCreate 清單**:加 `fetch_open_prs` + `build_issue_pr_index` 兩個 task,讓 PR fetch + index 步驟有 stage-level audit trail

### Spectra change

`add-pr-aware-idd-list` (informal — 走 IDD lifecycle 而非 Spectra,因為 idd-list output 是視覺 surface 不是 frozen API contract)。Diagnosis verdict = `Plan` (Layer P:decision-heavy with 3 valid approaches + 5+ ordered steps)。

### Sister issues filed (per IC_R011 sister concern surfacing)

- **#14** [refactor] markdown-aware PR body parser:ignore `#N` inside fenced code blocks (R1 follow-up;v2.51 accepts false positive)
- **#15** [enhancement] `cluster_leader: lowest | primary` config option (R3 follow-up;v2.51 hardcodes lowest)

### Backward compatibility

- Direct-commit issue(無 open PR ref)顯示**完全與 v2.50 一致**,no behavior change
- Footer 第二行只在有 open PR 時出現,無 PR 時維持 v2.50 格式
- Step 5 phase-only fallback 邏輯保留,作為 PR state 推不出時的 default
- Performance:`--limit 100` 對 dogfood repo 足夠;100+ open PR repo 後續若有需求加 `--pr-limit` flag(目前 out-of-scope)

## [2.50.0] - 2026-05-04

### Added

- **Layer V Vagueness Pre-check** ([PsychQuant/issue-driven-development#12](https://github.com/PsychQuant/issue-driven-development/issues/12)): NEW Step 3.4 in `idd-diagnose` between Layer 1 disqualifier and Layer 2 Spectra evaluation. Closes the routing gap where scope-small + request-vague issues (quadrant A: "menu feels off, fix it") were forced to `Simple` verdict, AI pattern-matched a wrong direction, then needed rework.

  - **Heuristic**: AI scores V1 (vague WHAT) + V4 (vague ACCEPTANCE) on Likert 6-point scale (no neutral midpoint); trigger threshold `max(V1, V4) ≥ 4` (per-axis OR semantics)
  - **Hybrid 3-option AskUserQuestion** when triggered: `clarify now` / `proceed anyway` / `escalate to Plan`. Default option score-driven: V=4 → proceed, V=5 → clarify, V=6 → escalate
  - **Choice effects**: clarify appends Q/A pairs to issue body via `gh issue edit` then re-runs Layer V; proceed continues to Layer 2/3/P with audit trail; escalate force-sets verdict = `Plan via Layer V` and skips Layer 2/3/P
  - **5-layer evaluation order**: Layer 1 → V → 2+3 → P → Simple
  - **V2 (vague HOW) and V3 (vague SCOPE) intentionally excluded**: V2 already covered by Layer P "decision-heavy"; V3 overlaps with IC_R011 sister sweep (idd-diagnose Step 3.6)

- **`.claude/rules/attribute-assessment.md` project rule** (NEW file): codifies meta-principle "**attribute scoring SHALL use Likert scale, not keyword matching**". Applies repo-wide via root `CLAUDE.md` `@import`. Scope intentionally beyond Layer V — any future attribute scoring need (confidence, priority, risk) follows the same rule. Includes V1 + V4 6-point anchors with concrete examples per Likert level.

- **MANIFESTO 6-axis bug-fix model** (was 5-axis): NEW axis 6 "Alignment quality (問題本身的清晰度)". Coverage: TDD ❌ / SDD ❌ / IDD ✅. Evidence: Layer V Vagueness Pre-check.

- **`vagueness_precheck` TaskCreate entry** in `idd-diagnose` Step 0 Bootstrap Stage Task List.

### Changed

- **`rules/sdd-integration.md`**: 4-layer evaluation order → 5-layer (Layer V inserted between Layer 1 and Layer 2). NEW "Layer V: Vagueness Pre-check" section documenting heuristic, threshold, 3-option, audit trail, unattended mode, backward compat. NEW "Retrospective dry-run" table with 5 sample closed issues (#7-#11) — all V≤3, none triggered (expected: IDD-self-improvement issues are inherently high-clarity since they originate from verify findings).

- **`idd-implement` Step 2.5 routing parser**: NEW logic strips ` via X` suffix to extract canonical tier. `Plan via Layer V` → `Plan` (routes identically to bare `Plan`). Bare verdicts unchanged (backward compat).

- **`idd-all` Phase 3 routing parser**: same suffix-stripping logic as `idd-implement`. NEW `Plan via Layer V` row in Complexity-to-action table.

- **`idd-all` unattended mode**: Layer V auto-applies `proceed anyway` + audit trail `[Layer V: V1=N V4=M, clarify-default skipped under unattended mode, defaulting to proceed]`. Same pattern as Plan tier under unattended mode (no user in current loop to review prompt).

- **`idd-diagnose` Step 3.5**: 4-layer evaluation order updated to 5-layer; Layer V handling added (escalate short-circuits Layer 2/3/P).

### Backward compatibility

- Pre-v2.50 diagnoses **NOT** retroactively re-evaluated. Existing `Simple` / `Plan` / `Spectra` / `SDD-warranted` verdicts remain valid.
- No `--ignore-vagueness` flag introduced. The 3-option `proceed anyway` choice covers the "user knows what they want, just didn't write it down" case. Adding a flag would invite habitual bypass.
- Plugin trade-off acknowledged: `.claude/rules/attribute-assessment.md` lives in this repo, not in the plugin. Other repos installing `issue-driven-dev` won't have the file. Step 3.4 has a fallback that uses built-in anchors and prints a warning. If/when the rule proves stable, promote to plugin internal or to global `~/.claude/CLAUDE.md`.

### Spectra change

`add-vagueness-layer-routing` in `openspec/changes/` (this repo). Capability `routing-vagueness-layer` documents the 9 normative requirements with scenarios and example tables.

## [2.49.0] - 2026-05-03

### Added
- **`references/ic-r011-checkpoint.md` v1.1.0 — Third-Party Skill Alignment section** ([kiki830621/ai_martech_global_scripts#530](https://github.com/kiki830621/ai_martech_global_scripts/issues/530), sub-issue E of [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) systematic plugin alignment, **last sub-issue closing the parent epic**): adds documentation guidance for applying IC_R011 checkpoint to third-party spectra-* skills.

  - `/spectra-discuss` (deliberation moment): SHALL apply manual checkpoint at discussion convergence — review log, AskUserQuestion 3-option, file via `gh issue create`, note in conclusion artifact under `### Tangential Observations (post-discuss)` heading.
  - `/spectra-propose` (deliberation moment): SHALL apply manual checkpoint at proposal drafting completion — re-read drafted artifact, AskUserQuestion 3-option, file via `gh issue create`, note in proposal under `### Tangential Observations (post-propose)` heading.
  - Eligible-skills inventory: explicitly N/A for `/spectra-apply` / `/spectra-archive` / `/spectra-ask` / `/spectra-ingest` / `/spectra-commit` / `/spectra-debug` (all mechanical execution, no deliberation moment).

### Why documentation-only (no SKILL.md modification)
spectra-* skills are published by third-party `kaochenlong/spectra-app` repo. Direct upstream SKILL.md modification would require:
- Cross-plugin coordination governance (different commit cycle)
- Upstream PR review by third-party maintainer

Documentation-side alignment delivers immediate value: agents/users reading this canonical doc when invoking `/spectra-*` know to apply the pattern manually at the equivalent lifecycle moments.

If spectra-app upstream adopts native IC_R011 checkpoint in their SKILL.md files, the new "Third-Party Skill Alignment" section becomes redundant and can be removed. Until then, the canonical doc is the single source of truth that bridges the gap.

### #523 parent epic closing
This is **sub-issue E**, the **last** of 6 sub-issues filed under #523 systematic plugin alignment. With #530 closed, the parent epic [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) is fully resolved across the IDD lifecycle:

| Sub-issue | Skill | Released | Strength |
|---|---|---|---|
| F #525 | canonical reference doc | v2.43.0 | (foundation) |
| A #526 | `/idd-implement` Step 5.7 Sister Bug Sweep | v2.44.0 | SHALL |
| B #527 | `/idd-close` Step 3.5 Closing Summary Scan | v2.45.0 | SHOULD |
| C #528 | `/idd-diagnose` Step 3.6 Sister Concern Surfacing | v2.47.0 | SHALL |
| D #529 | `/idd-issue` Step 4.7 Linked-Context Sister Sweep | v2.48.0 | SHOULD |
| **E #530** | `/spectra-discuss` + `/spectra-propose` (docs-only) | **v2.49.0** | SHALL |

Pre-existing alignment retained:
- `/idd-verify` Step 5b follow-up triage (pre-existing in plugin)
- `/idd-plan` Step 2.5 Tangential Observations Sweep ([#524](https://github.com/kiki830621/ai_martech_global_scripts/issues/524), v2.42.0)
- `/idd-close` Step 0 supersession ([#515](https://github.com/kiki830621/ai_martech_global_scripts/issues/515), v2.41.0 — gate logic, distinct from #527 IC_R011 checkpoint)

### Backward compatibility
Documentation-only addition. No SKILL.md behavioral change. spectra-* invocations continue to work exactly as before; the alignment is opt-in guidance for agents/users who want IC_R011-spirit follow-up filing during spectra deliberation moments.

### Related issues
- Parent: [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) (parent epic — fully resolved with this release)
- Canonical reference doc: [#525](https://github.com/kiki830621/ai_martech_global_scripts/issues/525) (v2.43.0, doc bumped to v1.1.0 in this release)
- Sibling sub-issues (all closed): [#526](https://github.com/kiki830621/ai_martech_global_scripts/issues/526), [#527](https://github.com/kiki830621/ai_martech_global_scripts/issues/527), [#528](https://github.com/kiki830621/ai_martech_global_scripts/issues/528), [#529](https://github.com/kiki830621/ai_martech_global_scripts/issues/529)
- IC_R011 codification: [#516](https://github.com/kiki830621/ai_martech_global_scripts/issues/516)

## [2.48.0] - 2026-05-03

### Added
- **`idd-issue` Step 4.7: Linked-Context Sister Sweep** ([kiki830621/ai_martech_global_scripts#529](https://github.com/kiki830621/ai_martech_global_scripts/issues/529), sub-issue D of [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) systematic plugin alignment): new advisory step between Step 4.5 (auto-milestone) and Step 5 (回報並停止). Scans 3 sources for sibling-concern markers:
  - Issue body draft (`also` / `additionally` / `related` / 「另外」 / 「順便」 / `BTW`)
  - Linked attachments (per IC_R007 attachments policy)
  - Recent session conversation (~20 turns before `/idd-issue` invocation)

  - If any source hits, AskUserQuestion three-option (`file as sibling issues now` / `file selected` / `skip`) per canonical [`references/ic-r011-checkpoint.md`](plugins/issue-driven-dev/references/ic-r011-checkpoint.md).
  - `file as sibling issues now`/`file selected` filing pipeline: `gh issue create` per orphan mention (parallel issues — **NOT** cross-linked into the just-created issue body), each with `confidence:confirmed` + `priority:P3` labels and source link `surfaced during /idd-issue #NEW linked-context sister sweep (Step 4.7)`.
  - PATCHes the just-created issue body via `gh issue edit` to append `### Linked-Context Siblings Filed (v2.48.0+ #529)` audit-trail line per canonical heading conventions.
  - Strength: **SHOULD (advisory, non-blocking)** per canonical eligibility criteria §6 — issue creation is light-touch (user is already in filing-active mode, double-prompt risks friction). Empty list = silent no-op default for clean single-issue invocations.
  - `AI_LOW_BAR_ISSUE_FILING=false` env var (per IC_R011 rollback hatch) silences AskUserQuestion silently with audit-trail line.

### Changed
- **Step 0 Bootstrap Task List**: added `linked_context_sister_sweep` TaskCreate entry between `create_milestone` and `report_and_stop`.

### Why
When user invokes `/idd-issue` from a session with scout history / attached document / linked source material, the session log + attachments often contain references to **sibling concerns** that are tangentially relevant but not the user's primary issue. Without checkpoint, those mentions stay in conversation; the user files one issue + walks away with N orphan mentions still un-tracked.

Sibling issues are **filed in parallel** (not as children of the just-created issue), preserving primary-concern focus. The just-created issue body simply tracks the audit trail of which siblings got filed alongside.

### Backward compatibility
- Empty surface list = silent no-op: existing single-issue invocations unchanged for clean filing without scout context.
- `AI_LOW_BAR_ISSUE_FILING=false` env var (per IC_R011 rollback hatch) skips AskUserQuestion silently.
- Existing issue creation flows without the new section: continue to work; section only appears when Step 4.7 surfaces a hit.

No flag deprecations. No breaking changes for any existing issue creation workflow.

### Related issues
- Parent: [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) (closed as parent tracker)
- Blocking dependency landed: [#525](https://github.com/kiki830621/ai_martech_global_scripts/issues/525) (canonical reference doc v2.43.0)
- Sibling shipped: [#526](https://github.com/kiki830621/ai_martech_global_scripts/issues/526) (idd-implement Step 5.7 v2.44.0), [#527](https://github.com/kiki830621/ai_martech_global_scripts/issues/527) (idd-close Step 3.5 v2.45.0), [#528](https://github.com/kiki830621/ai_martech_global_scripts/issues/528) (idd-diagnose Step 3.6 v2.47.0)
- IC_R011 codification: [#516](https://github.com/kiki830621/ai_martech_global_scripts/issues/516)

## [2.47.0] - 2026-05-03

### Added
- **`idd-diagnose` Step 3.6: Sister Concern Surfacing** ([kiki830621/ai_martech_global_scripts#528](https://github.com/kiki830621/ai_martech_global_scripts/issues/528), sub-issue C of [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) systematic plugin alignment): new mandatory step between Step 3.5 (Complexity Assessment) and Step 3.7 (Agent Routing). Surfaces sister-concern markers in the just-posted Diagnosis content + scout session log.

  - Trigger phrases: 「也有」 / 「same pattern」 / 「related」 / 「另外」 / 「sister」 / 「likewise affects」 — references to other files where the same root cause might apply, plus "this won't solve X" disclaimers in Strategy section.
  - Agent re-reads posted Diagnosis content after `complexity_assessment`, lists candidates per canonical [`references/ic-r011-checkpoint.md`](plugins/issue-driven-dev/references/ic-r011-checkpoint.md) heuristic, then AskUserQuestion three-option (`file all` / `file selected` / `skip`).
  - Files via `gh issue create` with `confidence:confirmed` + `priority:P3` + source link `surfaced during /idd-diagnose #NNN sister concern surfacing (Step 3.6)` for traceability.
  - PATCHes the Step 3 Diagnosis comment to add `### Sister Concerns Filed (mid-diagnose, v2.47.0+ #528)` audit-trail line per canonical heading conventions.
  - Strength: **SHALL** (mandatory step) per canonical eligibility criteria — diagnosis is a deliberation moment where sister concerns naturally surface during Strategy authoring. Empty surface list is a legitimate result.
  - `AI_LOW_BAR_ISSUE_FILING=false` env var (per IC_R011 rollback hatch) silences AskUserQuestion silently with audit-trail line.

### Changed
- **Step 0 Bootstrap Task List**: added `sister_concern_surfacing` TaskCreate entry between `complexity_assessment` and `confirm_and_route`.

### Why
Diagnosis Strategy section is **prime authoring territory** for sister concerns — the AI agent thinks about root cause, identifies the failing pattern, then naturally observes "this same pattern likely affects X / Y / Z elsewhere." Without mechanical checkpoint, those observations live only in conversation + Diagnosis comment text, never tracked as proper follow-up issues.

This is the **earliest** lifecycle moment in the IDD chain where sister concerns surface organically. Catching them here prevents downstream cascading manual reminders during implement / verify / close (the previously-observed `#510 → #518 → #520` cluster pattern).

### Backward compatibility
- Empty surface list = no-op: existing diagnose flow unchanged for issues with no sister concerns.
- `AI_LOW_BAR_ISSUE_FILING=false` env var (per IC_R011 rollback hatch) skips AskUserQuestion silently.
- Existing Diagnosis comments without the new section: continue to work; section only appears when Step 3.6 runs.

No flag deprecations. No breaking changes for any existing diagnose workflow.

### Related issues
- Parent: [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) (closed as parent tracker)
- Blocking dependency landed: [#525](https://github.com/kiki830621/ai_martech_global_scripts/issues/525) (canonical reference doc v2.43.0)
- Sibling shipped: [#526](https://github.com/kiki830621/ai_martech_global_scripts/issues/526) (idd-implement Step 5.7 v2.44.0), [#527](https://github.com/kiki830621/ai_martech_global_scripts/issues/527) (idd-close Step 3.5 v2.45.0)
- IC_R011 codification: [#516](https://github.com/kiki830621/ai_martech_global_scripts/issues/516)
- Reference impl pattern: [#524](https://github.com/kiki830621/ai_martech_global_scripts/issues/524) (idd-plan Step 2.5 v2.42.0)

## [2.46.0] - 2026-05-03

### Added
- **`idd-all` HITL mode** ([PsychQuant/issue-driven-development#1](https://github.com/PsychQuant/issue-driven-development/issues/1)): Phase 0.5 now resolves a `(path, interaction)` tuple from existing `pr_policy` config field + new `--pr` / `--no-pr` flags, replacing the hardcoded `--pr` enforcement.
  - Resolution precedence: `--pr` → `--no-pr` → fork detect → `pr_policy: always|never|ask`. Fork detection always overrides config to PR mode (no push to upstream).
  - **`(PR, unattended)`**: feature branch `idd/<N>-<slug>` from default branch + push + PR + sub-skill args carry `UNATTENDED MODE` directive (suppress `AskUserQuestion`/`EnterPlanMode`). v2.40.0 regression — `/loop` automation observes zero behavioral drift.
  - **`(direct-commit, attended)`**: stays on user's current checkout + no push + no PR + sub-skill args **omit** unattended hint. Native attended-by-default behavior fires: `idd-implement` Plan tier `EnterPlanMode` approval, `spectra-discuss` multi-turn pacing, `spectra-propose` Step 10 Park/Apply, `spectra-apply` Step 4 continue-confirmation. HITL scenario for solo/personal repos where PR is ceremony.
  - Mandatory resolved-tuple notice line printed before any state-mutating action: `→ Path: direct-commit (attended) — pr_policy=never`.
  - Phase 6 next-step copy is mode-aware: PR mode → `Next: review PR <url>, merge, then run /idd-close #N`; direct-commit mode → `Next: review last <N> commits, then run /idd-close #N`. **Verify is the terminal phase regardless of mode** — `idd-all` never auto-invokes `idd-close`.
  - **No silent timeout in attended mode**: documentation explicit that attended mode assumes a user is in session; `idd-all` imposes no timeout on sub-skill prompts.
- **`references/pr-flow.md`**: new `idd-all path resolution` section documenting that `idd-all` consumes `pr_policy` per the same algorithm as `idd-implement` (no behavioral divergence). Captures the "two axes from one source" architectural decision so future maintainers don't reintroduce duplicate config surfaces.

### Migration
Pure additive — no breaking change. Existing callers (`/loop`, `/idd-all #N`, `/idd-all #N --pr`, `/idd-all #N --cwd /path`) all continue to resolve to `(PR, unattended)`. Opt into HITL via `--no-pr` flag or `pr_policy: never` config.

### Spec
New capability `idd-orchestrator-modes` (`openspec/changes/idd-all-hitl-mode/specs/idd-orchestrator-modes/spec.md`) with 7 ADDED Requirements covering mode resolution, PR-path regression guarantee, direct-commit branch behavior, attended-interaction permits sub-skill questions, terminal-verify-regardless-of-mode, no-silent-timeout, and documentation contract.

## [2.45.0] - 2026-05-03

### Added
- **`idd-close` Step 3.5: Closing Summary Follow-up Keyword Scan** ([kiki830621/ai_martech_global_scripts#527](https://github.com/kiki830621/ai_martech_global_scripts/issues/527), sub-issue B of [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) systematic plugin alignment): new advisory step between Step 3 (review with user) and Step 4 (gh issue close). Scans drafted closing summary for trigger phrases (`follow-up` / `follow up` / `deferred` / `future` / `TODO` / `later` / `之後` / `未來` / `待` / `待 follow` / `順便` / `我之前觀察到` / `之後再` / `改天`).

  - Each match checked against existing `#NNN` cross-links via `gh issue view` — orphan mentions (no link or stale link to wrong-scope issue) trigger AskUserQuestion three-option (`file all` / `file selected` / `skip`) per canonical [`references/ic-r011-checkpoint.md`](plugins/issue-driven-dev/references/ic-r011-checkpoint.md).
  - `file all`/`file selected` filing pipeline: `gh issue create` with `confidence:confirmed` + `priority:P3` labels + source link `surfaced during /idd-close #NNN closing summary scan (Step 3.5)`, then **PATCHes the closing summary inline** to replace each filed mention with `(see #NEW)` cross-link.
  - `skip` keeps closing summary as-is, appends `### Closing Follow-ups Filed (v2.45.0+ #527)` audit trail with `Skipped per user choice (kept inline mentions without cross-links: ...)`.
  - Strength: **SHOULD (advisory, non-blocking)** per canonical eligibility criteria §6 — closure is mostly mechanical action with text artifact;hard-blocking on every "future" keyword would create user-friction. Empty-list and skip-with-reason are both legitimate outcomes. The value is making orphan-mention pattern visible at decision moment, not enforcing filing.
  - `AI_LOW_BAR_ISSUE_FILING=false` env var (per IC_R011 rollback hatch) silences AskUserQuestion silently with audit-trail line.

### Changed
- **Step 0.5 Bootstrap Task List**: added `closing_followup_keyword_scan` TaskCreate entry between `review_with_user` and `publish_and_close`.

### Disambiguation
A note added to Step 3.5 explicitly disambiguates this from Step 0 supersession check (#515 v2.41.0):
- **Step 0 supersession** is **gate logic** (recognize Implementation Complete > Checklist as canonical when supersession active) — operates on pre-implementation Strategy/Plan checkboxes
- **Step 3.5 closing summary scan** is the **IC_R011 checkpoint** (orphan mentions in drafted summary)

The two are orthogonal concerns. Step 0 runs at gate time;Step 3.5 runs after summary draft + before final close.

### Why
Closing summaries often contain phrases like "will follow up later" / "之後再做" / "deferred to next sprint" — but if the mention isn't linked to an actual issue, it vanishes into the closing comment never to be tracked. By scan time, the user has just typed the summary, the matched phrase is fresh in context — best moment to prompt for filing.

This step closes a gap in the IDD lifecycle: **closure** is the final discipline checkpoint where audit trail completeness matters most, since after close the issue artifact is frozen and orphan mentions become unrecoverable without manual archaeology.

### Backward compatibility
- Empty match list = no-op: closing flow unchanged for clean summaries (most common case).
- Existing closing summaries unaffected: Step 3.5 only runs on the **draft** before `gh issue close`.
- `AI_LOW_BAR_ISSUE_FILING=false` env var skips AskUserQuestion silently, only writes the skip-reason to closing summary audit trail.

No flag deprecations. No breaking changes for any existing close workflow.

### Related issues
- Parent: [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) (closed as parent tracker)
- Blocking dependency landed: [#525](https://github.com/kiki830621/ai_martech_global_scripts/issues/525) (canonical reference doc v2.43.0)
- Sibling already shipped: [#526](https://github.com/kiki830621/ai_martech_global_scripts/issues/526) (idd-implement Step 5.7 v2.44.0)
- IC_R011 codification: [#516](https://github.com/kiki830621/ai_martech_global_scripts/issues/516)
- Disambiguates from: [#515](https://github.com/kiki830621/ai_martech_global_scripts/issues/515) (idd-close Step 0 supersession v2.41.0 — gate logic, not IC_R011 checkpoint)

## [2.44.0] - 2026-05-03

### Added
- **`idd-implement` Step 5.7: Sister Bug Sweep** ([kiki830621/ai_martech_global_scripts#526](https://github.com/kiki830621/ai_martech_global_scripts/issues/526), sub-issue A of [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) systematic plugin alignment): new mandatory step between Step 5.5 (Open PR, if PR path) and chain to `/idd-verify`. Surfaces sister bugs discovered during TDD reproduction (Step 3 manual reproduction often reveals same-root-cause sibling files in adjacent paths).

  - Agent reviews session log + grep paths + reproduction trace, identifies candidates per canonical [`references/ic-r011-checkpoint.md`](plugins/issue-driven-dev/references/ic-r011-checkpoint.md) heuristic (same root cause manifesting in different file / unrelated quality issue from manual reproduction / TODO-FIXME hits / refactor opportunities adjacent to fix path), surfaces numbered list, then AskUserQuestion three-option (`file all` / `file selected` / `skip`).
  - Files via `gh issue create` with `confidence:confirmed` + `priority:P3` labels and source link `surfaced during /idd-implement #NNN reproduction (Step 5.7)` for traceability.
  - PATCHes the Step 5 Implementation Complete comment to add `### Sister Bugs Filed (mid-impl, v2.44.0+ #526)` audit-trail line per canonical heading conventions table: `Filed: #NNN, #MMM, #PPP` / `none surfaced` / `Skipped per user choice (...)` / `skipped (AI_LOW_BAR_ISSUE_FILING=false)`.
  - Strength: **SHALL** (mandatory step), but empty surface list is a legitimate result. `AI_LOW_BAR_ISSUE_FILING=false` env var (per IC_R011 rollback hatch) silences the AskUserQuestion prompt while preserving audit trail.

### Changed
- **Step 0 Bootstrap Task List**: added `sister_bug_sweep` TaskCreate entry between `open_pr_if_pr_path` and chain-to-verify.

### Why
2026-05-03 cluster `#510 → #518 → #520` proves the inconsistency: 3 separate same-pattern bugs (`gen_product_attribute_*` / `fix_wiser_poisson_tables.R` / `_build.R`) — each manual reminder was needed despite same root-cause pattern. Without mechanical checkpoint at this lifecycle moment, AI spirit-alignment drifts. Implementation is the **prime moment** for sister bugs to surface (manual reproduction is when they're most visible);30-second filing × N items vs. 30+ min reconstructing the cluster pattern weeks later (per IC_R011 cost calibration).

### Backward compatibility
- Empty observation list = no-op: existing implement flow unchanged for focused fixes with no sister observations.
- `AI_LOW_BAR_ISSUE_FILING=false` env var (per IC_R011) skips AskUserQuestion silently, only writes the skip-reason to Implementation Complete audit trail.
- Existing Implementation Complete comments without the new section: continue to work; section only appears when Step 5.7 runs.

No flag deprecations. No breaking changes for any existing implement workflow.

### Related issues
- Parent: [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) (closed 2026-05-03 as parent tracker, decomposed into 6 sub-issues)
- Blocking dependency landed: [#525](https://github.com/kiki830621/ai_martech_global_scripts/issues/525) (sub-issue F, canonical reference doc v2.43.0)
- IC_R011 codification: [#516](https://github.com/kiki830621/ai_martech_global_scripts/issues/516)
- Reference impl pattern: [#524](https://github.com/kiki830621/ai_martech_global_scripts/issues/524) (idd-plan Step 2.5 v2.42.0 — direct sibling at deliberation moment;Step 5.7 is the execution-moment counterpart)

## [2.43.0] - 2026-05-03

### Added
- **NEW canonical reference doc**: [`references/ic-r011-checkpoint.md`](plugins/issue-driven-dev/references/ic-r011-checkpoint.md) ([kiki830621/ai_martech_global_scripts#525](https://github.com/kiki830621/ai_martech_global_scripts/issues/525), sub-issue F of [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) systematic plugin alignment). Standardizes the IC_R011 ([#516](https://github.com/kiki830621/ai_martech_global_scripts/issues/516)) checkpoint pattern across all eligible IDD + Spectra skills:
  - **The 3-option AskUserQuestion structure** — exact labels (`file all` / `file selected` / `skip`), filing command template, sub-prompt structure for cherry-pick
  - **Heuristic triggers** — what counts as "concern worth surfacing" with 7 categories + trigger phrase regex
  - **Default-off exemptions** — narrow list (pure exploration / existing issue / hallucinated / CONSTRAINT / mechanical execution stages)
  - **Audit trail format** — uniform contents + per-skill heading conventions table
  - **Rollback escape hatch** — env var (`AI_LOW_BAR_ISSUE_FILING=false`) + repo CLAUDE.md flag (`# Disable IC_R011`); both layers honored additively
  - **Eligibility criteria** — SHALL (deliberation moments + manual reproduction) / SHOULD (closure + issue creation) / N/A (mechanical execution)
  - **Citation pattern** — exact Markdown for skills to back-reference the canonical doc

### Changed
- **`skills/idd-plan/SKILL.md` Step 2.5** now back-references the canonical doc: link added to `references/ic-r011-checkpoint.md`, and skill-specific sections marked as "this skill's specific application of that pattern". Step 2.5's own normative content unchanged (3-option AskUserQuestion + audit trail format already match canonical).
- **`skills/idd-close/SKILL.md` Step 0 supersession check** now disambiguates itself from IC_R011 checkpoint: a sentinel note marks supersession as "gate logic, NOT IC_R011 checkpoint", and points to [#527](https://github.com/kiki830621/ai_martech_global_scripts/issues/527) as the proper IC_R011 closing summary keyword scan tracker.

### Why
Sub-issues [#526–#530](https://github.com/kiki830621/ai_martech_global_scripts/issues/526) (sibling sub-issues of [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523)) all need the IC_R011 checkpoint pattern in their respective skills. Without a canonical reference, each implementation drifts in option labels, heuristic phrasing, audit format, and rollback semantics. This doc is the **mechanical anchor** that makes cross-skill consistency a verification artifact rather than a code-review aspiration.

Filing this as a separate sub-issue (F) before A-E (per [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) phasing rationale) means:
- A-E start by citing F → no per-skill drift
- Future skill alignments (whatever's added beyond #530's scope) follow the same pattern

### Backward compatibility
- No behavioral change to existing skills. `idd-plan` Step 2.5 + `idd-close` Step 0 supersession both keep their existing logic;only added doc back-references.
- `references/ic-r011-checkpoint.md` is a new file, no existing code references it (yet). Sub-issues #526–#530 will introduce citations as their Plan tier lands.

### Related issues
- Parent: [#523](https://github.com/kiki830621/ai_martech_global_scripts/issues/523) (closed 2026-05-03 as parent tracker, decomposed into 6 sub-issues F + A-E)
- Sibling sub-issues (open): [#526](https://github.com/kiki830621/ai_martech_global_scripts/issues/526) [#527](https://github.com/kiki830621/ai_martech_global_scripts/issues/527) [#528](https://github.com/kiki830621/ai_martech_global_scripts/issues/528) [#529](https://github.com/kiki830621/ai_martech_global_scripts/issues/529) [#530](https://github.com/kiki830621/ai_martech_global_scripts/issues/530) (all blocked on this doc)
- Source principle: [#516](https://github.com/kiki830621/ai_martech_global_scripts/issues/516) (IC_R011 codification)
- Reference impl back-link: [#524](https://github.com/kiki830621/ai_martech_global_scripts/issues/524) (idd-plan Step 2.5 v2.42.0) + [#515](https://github.com/kiki830621/ai_martech_global_scripts/issues/515) (idd-close Step 0 supersession v2.41.0)

## [2.42.0] - 2026-05-03

### Added
- **`idd-plan` Step 2.5: Tangential Observations Sweep** ([kiki830621/ai_martech_global_scripts#524](https://github.com/kiki830621/ai_martech_global_scripts/issues/524)): new mandatory step between Step 2 (Draft Plan) and Step 3 (Confirm post) that surfaces mid-plan tangential discoveries — Phase 1 Explore agents' pass-by sister bugs, Phase 2 grep-discovered drift, Phase 3 user-mentioned sub-concerns — previously falling into the gap between In-scope and Out-of-scope categorization, vanishing into conversation.
  - Agent self-reviews session log from Step 1 to current point, identifies candidates per IC_R011 (#516) default-on heuristic (verifiable behavior gap / sister bug / out-of-scope user-mentioned), surfaces numbered list, then AskUserQuestion three-option (`file all` / `file selected` / `skip`).
  - Files via `gh issue create` with `confidence:confirmed` + `priority:P3` labels and source link `surfaced during /idd-plan #NNN tangential sweep (Step 2.5)` for traceability.
  - PATCHes the Step 2 plan comment to add `### Tangential Observations (filed mid-plan, v2.42.0+ #524)` audit trail line: `filed #NNN, #MMM, #PPP` / `none surfaced` / `skipped per user choice` / `skipped (AI_LOW_BAR_ISSUE_FILING=false)`.
  - Strength: **SHALL** (mandatory step), but empty surface list is a legitimate result. `AI_LOW_BAR_ISSUE_FILING=false` env var (per IC_R011 rollback hatch) silences the AskUserQuestion prompt while preserving audit trail.

### Changed
- **`skills/idd-plan/SKILL.md` Implementation Plan template**: added `### Tangential Observations` section after `### Out-of-scope` (filled by Step 2.5).
- **Step 0 Bootstrap Task List**: added `tangential_sweep` TaskCreate entry between `draft_implementation_plan` and `enter_plan_mode_for_approval`.

### Why
The original `idd-plan` flow had Out-of-scope as the only categorization for non-implemented items, but **Out-of-scope is a categorized exclusion** (diagnosis-mentioned items deliberately deferred). Mid-plan **tangential discoveries** are different — they emerge during scouting/design without a categorization channel, so they vanish into conversation. The plan structure itself didn't have a slot for them, leading to recurring audit-trail loss observed in #524-trigger session.

This step is the plugin-side enforcement of IC_R011 (#516) "when in doubt, file the issue" applied specifically to the mid-plan deliberation window. Finer-grained than #523 broader systematic alignment, which covers Out-of-scope items + manual reproduction sister concerns + verify Step 5b + closing summary mentions but does NOT cover the mid-plan-without-categorization gap.

### Backward compatibility
- Empty observation list = no-op: existing plan flow unchanged for focused-scout cases.
- `AI_LOW_BAR_ISSUE_FILING=false` env var (per IC_R011) skips AskUserQuestion silently, only writes the skip-reason to plan body.
- Existing plan bodies without the new section: continue to work; section only appears when Step 2.5 runs.

No flag deprecations. No breaking changes for any existing plan workflow.

### Related issues
- #516 (IC_R011 Commercial Project Low-Bar Issue Filing — codifies the spirit being mechanically enforced here)
- #523 (broader plugin systematic alignment — sibling, but #524 is finer gap)
- #515 (idd-close skill design gap — sibling, different layer)

## [2.41.0] - 2026-05-03

### Fixed
- **`idd-close` Step 0 false-positive on pre-implementation Strategy/Plan checkboxes** ([kiki830621/ai_martech_global_scripts#515](https://github.com/kiki830621/ai_martech_global_scripts/issues/515)): `idd-close`'s gate scanned `Strategy` + `Implementation Plan` + `Implementation Complete > Checklist` as equal sources, but `idd-implement` Step 5 only writes back to its own `## Implementation Complete > ### Checklist` subsection — never PATCHes the pre-implementation Strategy/Plan comments. Result: complete IDD-lifecycle issues (work done, Implementation Complete fully `- [x]`) still showed 8+ stale `- [ ]` in Strategy/Plan, refusing close until user manually `gh api PATCH`ed both comments. Observed in #455 + #510 close, 2026-05-03.

### Added
- **Pre-implementation supersession check** in `idd-close` Step 0 (`skills/idd-close/SKILL.md`): when `## Implementation Complete > ### Checklist` exists and **all** its items are `- [x]`, that subsection is recognized as the canonical state of truth and `Strategy` / `Implementation Plan` `- [ ]` items are auto-superseded (skipped from gate). Logged as `(superseded by Implementation Complete > Checklist)` for audit trail.

### Why
The original Step 0 spec implicitly assumed `idd-implement` Step 5 syncs all checkbox sources, but the actual implementation only writes the canonical `## Implementation Complete > ### Checklist`. Strategy/Plan are pre-implementation **snapshots** — they record design intent at diagnose/plan time, and shouldn't function as a ship gate after the canonical implementation record exists. Strategy A from #515 diagnosis (header-based supersession) was chosen over B (sync-at-write — adds idd-implement Step 5 complexity, error-prone PATCH fan-out) and C (narrow gate — too aggressive, loses Strategy/Plan defensive coverage when Implementation Complete is missing/partial).

### Backward compatibility
- Legacy issues without `## Implementation Complete` (idd-implement never ran): unchanged, full spec table still scanned.
- Issues with `## Implementation Complete` but containing any `- [ ]`: supersession **not** triggered; falls back to full spec scan (defensive — catches both pre-impl AND post-impl unchecked items).
- Issues already manually `PATCH`ed via the workaround: continue to pass (Strategy/Plan items already `- [x]`; gate succeeds via either the supersession path or the legacy path).

No flag deprecations. No breaking changes for any existing close workflow.

### Spec table update
The `Step 0 > 掃描範圍` table in `skills/idd-close/SKILL.md` now documents the supersession rule explicitly: Strategy and Implementation Plan rows note `**Superseded** when Implementation Complete > Checklist 全 [x]`; Implementation Complete > Checklist row notes that triggering supersession requires all items to be `- [x]`.

## [2.40.0] - 2026-05-03

### Added
- **`--cwd` flag propagated to all cwd-aware sub-skills**: `idd-diagnose`, `idd-implement`, and `idd-verify` now accept `--cwd /path/to/local/clone` with the same semantics as `idd-all` v2.39.0. Each sub-skill's Step 0 parses `--cwd`, derives `$CWD` and `$GITHUB_REPO` from origin remote, and applies a substitution rule to all subsequent `git`/`gh` calls.
- **`references/cross-repo-cwd.md`**: Single source of truth for the `--cwd` convention — resolution algorithm (BSD-sed-compatible), substitution table (`git X` → `git -C "$CWD" X`, `gh issue/pr/repo X` → `gh ... -R "$GITHUB_REPO"`), failure modes, sibling-flag interaction (`--target` for read-only vs `--cwd` for git-writing skills).
- **`idd-all` Phase 1/2/3a/4 forwarding**: When `idd-all` invokes a sub-skill, it now appends `--cwd "$CWD"` (for git-writing skills) or `--target "$GITHUB_REPO"` (for read-only skills like `idd-issue`) to the args string. Without this, sub-skills would inherit Claude Code's session-level cwd and operate on the wrong repo — silently committing to repo A while user expected repo B.

### Changed
- **`idd-diagnose` argument-hint** advertises `--cwd /path/to/clone`.
- **`idd-implement` argument-hint** advertises `--cwd /path/to/clone` alongside `--pr` / `--no-pr`.
- **`idd-verify` argument-hint** advertises `--cwd /path/to/clone` alongside `--pr` / `--commits` / `--branch` / `--since`.
- **`idd-all` Phase 2 / 3a / 4 / Phase 4 follow-up creation**: explicit `--cwd "$CWD"` / `--target "$GITHUB_REPO"` propagation (was: implicit cwd inheritance via Skill tool).

### Why
v2.39.0 introduced `--cwd` only on `idd-all`, but the orchestrator's primary job is to invoke sub-skills via the Skill tool. Skill calls inherit Claude Code's session-level cwd, not anything `idd-all` resolved internally — so sub-skills would still operate on the wrong repo. This release closes that gap by extending the convention to every sub-skill that does local git ops, plus updating `idd-all` to forward the flag explicitly.

### Backward compatibility
Omitting `--cwd` reads from session `pwd` — identical to v2.39.0 behavior. No flag deprecations. Single-repo workflows (the common case) are unchanged.

## [2.39.0] - 2026-05-03

### Added
- **`idd-all --cwd /path/to/clone` flag**: Per-invocation override that decouples the orchestrator from Claude Code's session-level working directory. Previously, running `idd-all` on a repo other than the one your session started in required exiting Claude Code and re-launching with `cd <path>` first — because Skill tool calls inherit session cwd and don't follow mid-session `cd`. New `--cwd` flag breaks that friction; cross-repo orchestration (e.g. thesis work in repo A, want pipeline on dependency repo B) now works without session restart.
- **Step 0.2 "Resolve Working Tree"**: Explicit phase that derives `$CWD` from `--cwd` flag (or falls back to session `pwd`) and `$GITHUB_REPO` from `git -C $CWD remote get-url origin`. All subsequent phases reference these variables instead of relying on cwd defaults.
- **Improved abort messages**: Phase 0.2/0.3 abort guidance now includes `--cwd /path/to/clone` as an explicit alternative to `cd $path && claude`. Failure Modes table grew 3 new rows for `--cwd` validation errors.
- **Cross-repo invocation example** in Examples section: `/idd-all #43 --cwd /Users/che/Developer/macdoc/packages/ooxml-swift`.

### Changed
- All `git` calls in idd-all use `git -C "$CWD" ...` (was: implicit cwd)
- All `gh` calls in idd-all use `gh -R "$GITHUB_REPO" ...` (was: implicit cwd repo detect)
- `argument-hint` updated to advertise the new flag

### Backward compatibility
- Omitting `--cwd` reads from session `pwd` — identical to v2.38.0 behavior. No flag deprecations.

## [2.38.0] - 2026-05-02

### Added
- **`idd-diagnose` Step 3.7**: Calls `~/bin/idd-route recommend` after Complexity Assessment. Injects "Recommended Agent" section into diagnosis comment with confidence + expected metrics + per-candidate stats + reasoning. Powered by data-driven recommendation against `<repo>/.claude/.idd/routing-stats.jsonl` + global mirror at `~/.cache/idd-route/stats.jsonl`. Falls back to static heuristic on cold start.
- **`idd-verify` Step 5d**: Calls `~/bin/idd-route record` after findings post + triage. Captures (issue, agent, complexity, scope_files, scope_loc, signals, round_trips, blocking, medium, low, followups) + initial outcome=in_review. Append-only JSONL.
- **`idd-close` Step 4.5**: Calls `~/bin/idd-route update-outcome` after issue close. Appends a follow-up record with outcome=merged or outcome=abandoned (auto-detected from `gh pr view --json merged`). Original in_review record from idd-verify Step 5d stays for audit. Requires `idd-route-swift` v0.3.0 (P2 of plan); gracefully no-ops on `command not found`.
- **`references/agent-routing.md`**: Canonical contract for IDD ⇄ idd-route boundary. Lifecycle integration (diagnose recommends, verify records, close finalizes), graceful-skip semantics when binary missing, signal extraction conventions, opt-out mechanisms (kill-switch flag / per-project / per-machine config / uninstall).

### Changed
- All three new step blocks gracefully no-op via `command -v idd-route` check — IDD flow is unchanged for users who don't install the companion `idd-route` plugin.
- Marketplace migration: this is the first issue-driven-dev release shipping in `PsychQuant/issue-driven-development` (the new dedicated marketplace). Full 63-commit history preserved via `git filter-repo` from the previous home (`PsychQuant/psychquant-claude-plugins`). `git log -- plugins/issue-driven-dev/` shows complete evolution since v1.0.0.

## [2.37.0] - 2026-05-02
### NEW: External-agent / PR mode for `idd-verify` + use-case routing reference

Closes a structural gap: `idd-verify` previously assumed Claude was always the implementer (operating on `git diff` / `HEAD~1`). When implement is delegated to another agent (Codex via `codex exec`, Copilot Workspace, remote claw on PsychQuantClaw), the change set lives in a PR or remote branch — current verify couldn't reach it.

#### `idd-verify` new input source flags

| Flag | Mode | Diff source |
|------|------|------------|
| `--pr <N>` | PR mode | `gh pr diff <N>` (with `gh pr checkout` so reviewer agents see file context); auto-restore original branch after verify |
| `--commits <N>` | Local mode | `HEAD~N..HEAD` |
| `--since <ref>` | Local mode | `<ref>..HEAD` |
| `--branch <name>` | Branch mode | `git diff origin/<default>...<name>` |
| (no flag) | **Auto-detect** | Count `Refs #N` commits since `origin/<default>` → if N>0 use HEAD~N; else `gh pr list --search "#N in:body" --state open` → AskUserQuestion to pick |

Auto-detect catches the common "I cloned this repo, Codex committed 3 things, I forgot `--commits 3`" scenario without silently switching modes.

#### Issue ↔ PR correspondence gate (PR mode iron rule)

`--pr <N>` runs a hard gate before invoking the 6-AI ensemble:

- `gh pr view --json body` → grep `Refs #N` patterns into **discovered set**
- PR body has zero `Refs #N` → **ABORT** with "violates IDD discipline; add `Refs #N` and retry"
- User passed `#98` but PR doesn't ref #98 → **ABORT** with "correspondence broken"
- PR refs `{#98, #105}` but user only passed `#98` → **AskUserQuestion** to confirm scope

A PR without any issue ref is an untrackable change. IDD's audit value evaporates if the PR-issue link doesn't exist.

#### PR-as-master cross-post

PR mode flips master comment location from issue → PR (external agent owners work in PR view; never see issue comments). Each ref'd issue receives a 1-line pointer comment back:

```markdown
## Verify (via PR #123)
**Result**: PASS — no blocking findings
**Full report**: https://github.com/owner/repo/pull/123#issuecomment-NNN

This issue's findings: see "#98" section in the linked report.
```

Capture-master-URL-then-write-pointer SOP enforced (preventing the recurring bug class where pointer URLs accidentally referenced earlier diagnosis / implementation comments instead of the actual verify report).

#### NEW reference: `references/external-agent-delegation.md`

Single source of truth for IDD ⇄ external agent contract. Covers:

- 4-phase delegation impact matrix (diagnose / implement / verify / close)
- Hands-off principle (no babysitting external agents; strict verify + opt-in fix takeover)
- Three input modes + auto-detect resolution algorithm
- Issue↔PR correspondence gate
- PR-as-master cross-post + working tree handling
- Out-of-scope items deferred to v2 (`--takeover`, `idd-handoff`, force-push detection)

#### NEW reference: `references/usecase-routing.md`

Discoverability gap fix: 24-row table mapping common scenarios → exact skill chain + flags + contract doc. Covers single-issue, batch, cluster-PR, external-agent (PR/commits/branch/auto), Plan tier, Spectra-warranted, bundle close, Spectra-bridge, multi-repo monorepo. Plus a top-of-doc decision tree ("你正要做什麼？") for users who don't know which entry point to start from.

Linked from CLAUDE.md (Claude-facing) and README.md (human-facing) so both audiences find it.

#### Touched files

- `skills/idd-verify/SKILL.md` — argument-hint, description, allowed-tools, Cluster-PR mode section, External-agent / PR mode section (new), 參數 section, Step 0 TaskCreate list (+ resolve_input_source / gate_pr_correspondence / post_master_and_pointers / restore_working_tree), Step 0.5 (new), Step 0.7 (new), Step 1 multi-source, Step 4 master-pointer rules per mode, report format examples
- `references/external-agent-delegation.md` — new
- `references/usecase-routing.md` — new
- `CLAUDE.md` — Use-Case Routing section (new) before Multi-issue Invocation
- `README.md` — Use-Case Routing + External-Agent Verify sections (new) before Multi-issue Invocation

#### Backward compatibility

Single-issue invocation `idd-verify #42` without flags still works exactly as v2.36 in the common case (no Refs commits, no open PRs → falls back to `HEAD~1`). Auto-detect only activates AskUserQuestion when ambiguous; never silently switches modes. Cluster-PR mode (`#34 #36 #38`) unchanged. No flag deprecations.

## [2.35.0] - 2026-04-30
### NEW: `scripts/process-attachments.sh` + `rules/process-attachments.md` — attachment 上下游處理協定

Closes a recurring gap: `gh issue view --json` 抓不到 issue body 含的 user-attachments docx/pdf 內容,IDD skills 過去全程沒處理 → diagnosis 漏關鍵 source-of-truth(歷史案例:kiki830621/collaboration_liu-thesis-analysis#21 摘要 docx 結尾段落「mismatch / SP 作為機制 / construct mapping」三條 narrative bridge 因 idd-diagnose 沒讀附件被遺漏,後續 spectra-propose 重建 design/spec/tasks 全部要回頭補)。

**設計選擇**:把機械工作(detection / curl / sha256 / manifest write / diff check / disk verify)放進 `scripts/process-attachments.sh` helper,**不**依賴 SKILL.md 文檔 link 讓 Claude follow — shell call 一定執行,文檔 link Claude 不一定 follow。SKILL.md 只 call `bash $CLAUDE_PLUGIN_ROOT/scripts/process-attachments.sh {download|check|verify} <NUMBER>`,parse 部分(docx → text)由 Claude 用 MCP tool(che-word-mcp / che-pdf-mcp / Read)處理,因為 parse 本來就需要 LLM 介入。

### Helper script: 3 個 commands

| Command | 用途 | 主要 caller | Exit code 0 / 1 |
|---------|------|-------------|-----------------|
| `download <N>` | 偵測 issue body/comments 的 attachment URL,curl 下載到 `.claude/.idd/attachments/issue-N/`,寫 `_manifest.json` | idd-diagnose Step 1.5 / idd-issue | 0=完成或無 attachment;1=部分下載失敗(error 條目寫進 manifest) |
| `check <N>` | 確認 manifest 涵蓋當下 issue attachment list;偵測 diagnose 後新增 | idd-implement Step 1.2 / idd-verify Step 1.5 / idd-report | 0=up-to-date;1=manifest missing 或有新增(警告但不 auto-repair) |
| `verify <N>` | 確認 manifest 列出的檔案在 disk 上還在 | idd-close Step 1.4 | 0=all present;1=部分被搬走/刪掉(警告但不 abort close) |

Repo 自動從 walk-up config 解析(支援新 `.claude/.idd/local.json` / 舊 `.claude/issue-driven-dev.local.json` / 更舊 `.claude/issue-driven-dev.local.md` YAML frontmatter);可用 `--repo owner/repo` 顯式 override。`IDD_CALLER` 環境變數記錄到 manifest `fetched_by` 欄位作 audit。

### Changed

<!-- (formerly: 上下游責任分工) -->

- **上游下載(`idd-issue`, `idd-diagnose`)** — call `download` 機械抓取 + manifest;Claude 後續用 MCP-first parser 讀內容(`.docx` → che-word-mcp、`.pdf` → che-pdf-mcp、圖片 → Read tool;fallback pandoc / pdftotext)
- **下游檢查(`idd-implement`, `idd-verify`, `idd-close`, `idd-report`)** — call `check` 或 `verify`,缺漏輸出警告引導使用者重跑 idd-diagnose,**不 auto-fetch**(避免 mask 上游 skill bug)
- **不適用** — idd-list / idd-config(不分析 issue 內容)

### Manifest schema(`_manifest.json`)

```json
{
  "issue": 21,
  "fetched_at": "2026-04-30T03:13:02Z",
  "fetched_by": "idd-diagnose",
  "files": [
    {"filename": "1.docx", "url": "https://...", "sha256": "2ae0...", "size_bytes": 16363}
  ]
}
```

下載失敗的條目改為 `{filename, url, error: "download_failed"}`。

### Namespace 重組:`.claude/.idd/`

統一所有 idd 工作流檔案到 `.claude/.idd/`:

```
.claude/.idd/
  ├── local.md         # was .claude/issue-driven-dev.local.md
  ├── local.json       # was .claude/issue-driven-dev.local.json
  ├── state/
  │   └── bridge.json  # was .claude/state/idd-bridge.json
  └── attachments/
      └── issue-NNN/   # 新功能
```

理由:idd config + state + attachments 屬於 issue 工作流,不該散在 `.claude/` root 跟 `.claude/state/` 兩處;統一到 `.claude/.idd/` 子目錄讓 namespace 收斂,協作者一看就知道「這些是 IDD 的東西」。

### Backward compat

Walk-up search 同時找新舊路徑,**新路徑優先**;偵測到 legacy(`.claude/issue-driven-dev.local.json` / `.claude/state/idd-bridge.json`)印一行 migration hint 但 skill 仍正常運作。新 install 一律寫新路徑(config-protocol.md `When skills should write back to config` 段落更新)。

Migration 命令:

```bash
cd <repo-root>
mkdir -p .claude/.idd .claude/.idd/state
[ -f .claude/issue-driven-dev.local.json ] && mv .claude/issue-driven-dev.local.json .claude/.idd/local.json
[ -f .claude/issue-driven-dev.local.md ] && mv .claude/issue-driven-dev.local.md .claude/.idd/local.md
[ -f .claude/state/idd-bridge.json ] && mv .claude/state/idd-bridge.json .claude/.idd/state/bridge.json
```

### Changed
- **NEW** `plugins/issue-driven-dev/scripts/process-attachments.sh`(150 行 bash + python3 inline,3 個 commands;支援 walk-up config 含 .md frontmatter fallback)
- **NEW** `plugins/issue-driven-dev/rules/process-attachments.md`(薄薄的:scope / storage / manifest schema doc / parser strategy / reference convention / .gitignore guidance / 6 條 iron rules;機械邏輯不重複,引用 helper script)
- `skills/idd-diagnose/SKILL.md` — Bootstrap Task List 加 `download_attachments`;Step 1.5 改為 `bash $CLAUDE_PLUGIN_ROOT/scripts/process-attachments.sh download $NUMBER` + Claude 後續 parse
- `skills/idd-implement/SKILL.md` — Bootstrap Task List 加 `check_attachments`;Step 1.2 改為 `bash ... check $NUMBER`,exit 1 警告不 abort
- `skills/idd-verify/SKILL.md` — Bootstrap Task List 加 `check_attachments`;Step 1.5 改為 `bash ... check $NUMBER`,把 attachment path 塞進 reviewer agent prompt 作 source-of-truth
- `skills/idd-close/SKILL.md` — Bootstrap Task List 加 `check_attachments`;Step 1.4 改為 `bash ... verify $NUMBER`,disk integrity check
- `references/config-protocol.md` — Walk-up algorithm 雙路徑;first-run write 寫新路徑;新增 Migration command
- `rules/spectra-bridge.md` — bookmark path 全面換新;Hard rule #6 加 backward compat 條款
- `CLAUDE.md` — 新增「Attachments」「Namespace Migration」段

### Iron rules added

- 下載 = mandatory for upstream(idd-diagnose 偵測到 attachment URL 必須下載,不可跳過)
- Reference by path, never by URL(comment / report 一律用 repo 相對 path)
- Failure must be visible(下載 / parse 失敗一律輸出警告,禁止靜默)
- Downstream never auto-repairs upstream(下游發現 manifest 缺漏 → 警告 + 引導,不偷偷補抓)
- Storage location is fixed(`.claude/.idd/attachments/issue-{NNN}/`,skill 不允許各自選位置)
- Script is source of truth(機械工作由 helper script 處理,SKILL.md 不得 inline 重新實作)

### Out of scope (留下次)

- `idd-issue` 處理「下載別人 issue 的 attachment」(目前只處理「上傳本地素材」,反方向)
- `idd-report` / `idd-all` 的 attachment check
- `idd-config` 的 auto-migrate 命令(目前只在 walk-up 印 hint,沒主動搬)
- `.gitignore` template 自動生成

## [2.33.0] - 2026-04-28
### NEW: `MANIFESTO.md` — methodology thesis

Formalizes the IDD methodology argument as a standalone document, separating "what the plugin does" (README) from "why this is a methodology not a workflow tool" (MANIFESTO).

### Changed

<!-- (formerly: Thesis) -->

> **TDD writes tests. SDD writes specs. IDD solves bugs.**
> 前兩個是手段，IDD 是目的。

### Document structure

- **三 methodology 各自回答的問題** — TDD/SDD/IDD 對應 verification unit；只有 IDD 給出 DONE definition
- **5-axis 解 bug 能力拆解** — diagnosis quality / fix completeness / verification independence / regression prevention / audit traceability。TDD 覆蓋 1.5/5，SDD 覆蓋 0/5，IDD 覆蓋 5/5
- **Verification × Closure 兩個正交軸** — TDD/SDD 在 verification axis 高，但在 closure axis 是 0；IDD 兩軸都正
- **Falsifiability strict superset** — formal proof: IDD ⊋ TDD ∪ SDD via Step 3 RED→GREEN inheritance + spectra-apply conformance inheritance + Step 1.6 semantic gate
- **TDD/SDD ⊂ IDD 的包含關係** — TDD/SDD 是 IDD 的 special case，不是並列方法論
- **Case study: che-word-mcp #56 cluster** — empirical proof. 30 findings via 6-AI verify, 5 sub-stack rounds, v3.13.0-v3.13.5 共 6 個 patch release, zero zombie issues. 對照假想 TDD-only 路徑會 leak 29/30 findings 成為使用者後續半年才陸續報的獨立 bug。
- **5 個 Skill = 5 個 Checkpoint** — 人決定，AI 執行
- **這個 plugin 不是什麼** — disclaimer (不是 issue tracker、不是 GitHub workflow automation、不是 ceremony for ceremony 的 process)
- **一句話總結** — 「TDD 跟 SDD 都驗證『對』，只有 IDD 驗證『完』」

### Changed
- **NEW** `plugins/issue-driven-dev/MANIFESTO.md` (~1100 字)
- **README.md** — opening 加 thesis blockquote + link 到 MANIFESTO.md
- **CLAUDE.md** — 「設計哲學」段加 link 到 MANIFESTO.md，標明本段是濃縮版

### Changed
No code changes. New artifact, opt-in reading. Plugin behavior identical to v2.32.0.

### Why now

`che-word-mcp` 是第一個用 IDD 從 v3.0 一路打到 v3.15 的大專案，#56 cluster 是 IDD 解 bug 能力的 empirical demo。把抽象論述跟具體 case study 一起寫進 MANIFESTO，讓 IDD 從「個人 plugin 的 README 描述」升級為「可被引用的 methodology 論述」。

## [2.32.0] - 2026-04-28
### NEW two protocols closing real-world workflow gaps

Two recurring failure modes observed in real IDD usage now have explicit, mandatory protocols.

#### Feature 1: `rules/tagging-collaborators.md` — collaborator-list-driven `@`-mention

Any IDD skill that posts `@xxx` to GitHub must follow a 5-step protocol:

1. **Detect intent** — `--mention <login>` flag or natural-language ("tag X" / "ping X" / "通知 X")
2. **Fetch real list** — `gh api repos/$REPO/collaborators` (+ org members for org repos); training-data / chat-history / git-log handles are forbidden
3. **Resolve** — fuzzy match against `login` + `name` field; unique match → use, otherwise fallback
4. **AskUserQuestion fallback** — 0 or 2+ matches → menu populated from the real collaborator list, not guessed
5. **Verify pre-post** — grep `@\w+` from body, every token must be in the verified set, otherwise abort

Skills with explicit `--mention <login>[,<login>...]` flag: `idd-issue`, `idd-comment`. Other skills (`idd-diagnose`, `idd-implement`, `idd-verify`, `idd-close`) reference the rule from their Step 0 task list — the protocol applies whenever prose contains `@xxx` regardless of how it got there.

Why now: in PsychQuant/contact-book#96 the AI happened to resolve "Hardy" → `@Hardy1Yang` correctly via `gh api`, but only because of careful prompting — without the protocol formalized, the next call could pick a hallucinated handle, ping the wrong person, and the notification can't be undone. GitHub mentions are an irreversible side effect; the rule is mandatory not advisory.

#### Feature 2: `rules/spectra-bridge.md` — preserve and resume spectra context across IDD detours

When `spectra-discuss` is interrupted mid-flow to invoke an IDD skill (e.g. "let me capture this finding to the issue"), the user previously had to re-explain the topic and assumptions on return. New bridge protocol:

- **Step 0.7 Detect** in IDD skills: trigger `SPECTRA_BRIDGE_ACTIVE=1` if any signal fires — `--resume-spectra="<topic>"` flag, `--source` contains `spectra-discuss`, `spectra list --json` shows in-flight changes, or `.claude/state/idd-bridge.json` already exists
- **Step N-1 Bookmark**: write `.claude/state/idd-bridge.json` with `spectra_topic` (verbatim), `issue_number`, `idd_action`, `idd_action_url`, `open_questions[]`, `next_step_hint`
- **Step N Resume Prompt**: emit a clearly-delimited `↩ Resume spectra-discuss` block with a copy-pasteable `/spectra-discuss <topic>...` prompt the user can paste back

`idd-comment` is the first skill to implement the bridge end-to-end (Step 0.7 detect, Step 7 bookmark + resume prompt). `idd-issue` and `idd-edit` will gain it in subsequent versions; the rule defines the contract for all skills.

Hard rules: never auto-invoke `/spectra-discuss` (user controls pacing); never paraphrase `spectra_topic` (user's wording carries assumptions); resume prompt is the actual recovery — bookmark file is convenience.

### Changed
- **NEW `rules/tagging-collaborators.md`** — 5-step protocol with examples, hard rules, implementation contract for skill authors
- **NEW `rules/spectra-bridge.md`** — detection signals, bookmark schema, resume prompt format, future-compat with spectra-side complement
- **`skills/idd-comment/SKILL.md`** — Step 0 task list expanded (added `detect_spectra_context`, `resolve_mentions`, `verify_mentions`, `spectra_bridge_resume`); new Step 0.7 (Detect Spectra Context), Step 2.5 (Resolve Mentions), Step 3.5 (Verify mentions), Step 7 (Spectra Bridge Resume Prompt); two new flags `--mention <login>[,<login>...]` and `--resume-spectra="<topic>"`; two new examples (`Note with mention`, `Spectra-bridge resume`); two new 鐵律 entries
- **`skills/idd-issue/SKILL.md`** — Step 0 task list adds `resolve_mentions`; Step 2 gathers `Stakeholders` (point 5); new Step 2.6 (Resolve Mentions); rule reference in 鐵律
- **`skills/idd-diagnose/SKILL.md`** — Step 0 footnote: tagging in diagnosis comment must follow `rules/tagging-collaborators.md`
- **`skills/idd-implement/SKILL.md`** — same footnote for Implementation Plan / Complete comments
- **`skills/idd-verify/SKILL.md`** — same footnote for Verify findings comments
- **`skills/idd-close/SKILL.md`** — same footnote for Closing Summary comments
- **`CLAUDE.md`** — new top-level sections "Tagging Collaborators (v2.32.0+)" and "Spectra ↔ IDD Bridge (v2.32.0+)"
- **No breaking changes**. Existing skills work as before; the new flags are opt-in. Skills without `--mention` flag still scan body for `@xxx` tokens and route through the protocol — but only when tokens are present, so empty-mention flows are unaffected.

### Why now

Two failure modes observed in PsychQuant/contact-book#96 (the ContactBook cloud-data-layer architecture decision):

1. The AI was asked to "tag Hardy" — happened to resolve correctly only because the human had reflexes to verify; the protocol formalizes what was previously ad-hoc luck.
2. The conversation pivoted: spectra-discuss → idd-comment (to capture findings + tag Hardy) → user wanted to resume spectra-discuss but the session state was lost. The bridge fixes this for the next person running the same flow.

Both gaps are skill-level (every IDD skill that posts to GitHub needs them), so they live as rules and are referenced from each skill's Step 0 — same pattern as `sdd-integration.md` for the spectra escalation protocol.

## [2.31.0] - 2026-04-27
### NEW `idd-config` skill — independent entry for config lifecycle

Filling a long-standing gap where `.claude/issue-driven-dev.local.json` setup, inspection, and predicate debugging were only available as side effects of `idd-issue` Step 0.5.

### Changed
- **NEW `skills/idd-config/SKILL.md`** with four subcommands:
  - `show` (default, no args) — prints resolved target + cwd-aware predicate trace from current `.claude/issue-driven-dev.local.json`. Walks up filesystem to find config (eslint/tsconfig pattern). Reports candidates / groups / `ask_each_time` if present.
  - `init` — interactive first-time setup. Equivalent to `idd-issue` Step 0.5.E fork-aware detection, but as a standalone command so users can configure before creating any issue. Detects fork via `gh repo view --json isFork,parent`; for forks, presents three-option AskUserQuestion (Upstream / Own fork / Both). Writes `github_repo` + optional `tracking_upstream`; "Both" mode writes an ad-hoc `groups[]` with primary + tracking entries.
  - `validate` — JSON schema check + `gh repo view` existence verification + predicate-key sanity (warns on unknown `when.*` keys). Validates groups (exactly one primary), `github_repo` regex, etc.
  - `which` — dry-run resolution at current cwd. Shows step-by-step trace of Phase 0.5 (path-class predicates) and optionally Phase 2.5 (with `--title <T>` / `--label <L>` to evaluate content predicates). Helps debug "why did `idd-issue` route to repo X instead of Y?"

- **No breaking changes**. `idd-issue` Step 0.5.E fork-detection is retained for users who prefer creating their first issue immediately. A future v3.0 may delegate to `idd-config init`, but v2.31.0 keeps both entry points functional.

### Why now

The IDD plugin's monorepo + multi-repo support has grown sophisticated since v2.25.0 (six-mechanism resolution, candidates with predicates, groups with cross-link tracking), but config management remained tied to `idd-issue`. Real-world use cases:

- Setting up a new project where you want to verify config before filing the first issue
- Debugging "this issue went to the wrong repo" by replaying the resolution at cwd
- Validating a hand-edited config file
- Inspecting which candidate matches at the current cwd

These all required either side-effect-creating `idd-issue` runs or manual JSON editing. `idd-config` is the missing read/inspect/init layer.

## [2.30.0] - 2026-04-26
### Data preservation hard rule in `idd-issue` + extra-requirements channel in `idd-implement`

Two long-standing gaps surfaced during real-world IDD use on the gukai spondylodiscitis project (`kiki830621/collaboration_gukai#4` and `#5`). Both were fixed as additive changes — existing flows are untouched.

### Changed
- **`idd-issue` — 資料保留鐵律 (HARD RULE)**

  - Step 1 renamed `讀取來源（如果是 .docx）` → `讀取來源並保留所有原始資料` with explicit hardline: "all source attachments uploaded to attachments release by default, without asking; only fall back to manual when MCP extraction is technically impossible".
  - New **Source Type Adapter** table covers `.docx` / `.pdf` / Telegram / Apple Mail / Apple Notes / pasted text / mixed.
  - New **Telegram source 專屬流程**: when chat_id / Telegram URL is referenced, enumerate all attachments via MCP `get_chat_history`, attempt download (or fallback to a specific manual-save prompt listing timestamp + sender + caption + suggested filename — never silently skip).
  - Step 4 renamed `附加圖片（如果有）` → `附加所有原始素材（鐵律：預設全保留）` with mandatory **violation checklist** at the end.
  - **Closes a recurring gap**: SNQ issue (`#5`) PDF + 2 timeline images were originally dropped because skill default was "ask first" — should have been "preserve first".

- **`idd-implement` — `--with-skill` + `--extra` flags**

  - `argument-hint` extended: `[--with-skill <skill>] [--extra '<requirement>']` (e.g., `'#42 --with-skill perspective-writer --extra ''500-800 chars'''`).
  - New **Step 1.5: Resolve Extra Requirements** merges three sources: explicit `--with-skill` flag, `--extra "<text>"` free-text constraint, and auto-detected `透過 X` / `via X` patterns from diagnosis Strategy.
  - Step 2 Implementation Plan template gains optional `### Extra Requirements` section listing the resolved with-skill + extra-text.
  - Step 3 GREEN phase: when `with_skill` set, calls `Skill(skill=...)` instead of direct Edit/Write; sub-skill completes the file write, then idd-implement resumes commit + checklist update.
  - Spectra-warranted complexity (SDD path) ignores `--with-skill` — `spectra-apply` already has sub-skill orchestration; no double-layering.
  - **First-class formalization** of the idd-implement × perspective-writer integration pattern that emerged in `#4` — previously hacked via free-form Implementation Plan bullet, now skill-supported.

### Why these changes

| Gap before 2.30.0 | Failure mode | Fix |
|-------------------|--------------|-----|
| Skill default = "ask before attaching" | Easy to skip when AI plays safe — preservation duty silently shifted to user | Default flipped to "preserve all" with explicit violation checklist |
| No documented way to inject "use skill X for execution" | Each prose deliverable hacks Implementation Plan bullets to mention X-skill — no checklist-level verification that X actually ran | First-class flag + Step 1.5 resolution + Step 5 sync verifies sub-skill invocation |

### Backwards compatibility

- All changes additive. Existing flows without Telegram sources / without `--with-skill` flag behave identically to 2.29.0.
- Configs not touched. `pr_policy`, `candidates`, `groups` semantics unchanged.

---

## [2.29.0] - 2026-04-26
### Two-tier checklist gate in `idd-close`

The structural gate (v2.17.0) catches **honest forgetting** — you can't close an issue with unticked `- [ ]` items. But it can't catch **motivated cheating** — ticking `- [x]` without doing the work. v2.29.0 adds a semantic gate to address the second failure mode.

### Changed
- **`idd-close` Step 1.6 — Semantic Checklist Gate** — for each `- [x]` bullet that passed the structural gate, classify against three keyword patterns and verify the underlying artifact exists:

  | Pattern | Check |
  |---------|-------|
  | Contains test/regression/coverage keywords | `git log --grep="#${N}" -- '**/*test*' ...` must return ≥1 commit |
  | References `openspec/changes/<name>/{proposal,design,tasks,spec}.md` | File must exist |
  | Contains backtick-wrapped file path with extension | Path must appear in `git log --grep="#${N}" --name-only` |
  | No recognized pattern | Skip (counted as "unchecked") |

- **Warn-only behavior** — semantic gate doesn't hard-refuse like the structural gate. Keyword extraction has false positives (e.g. test commit landed in earlier PR), so warnings are presented with AskUserQuestion three-way choice: proceed / investigate / edit checklist.

- **`idd-close` Step 0.5 task list** — added `semantic_gate_check` entry.

- **`idd-close` 鐵律 section** — added "打勾沒做要 warn" rule alongside "沒打勾就不關".

- **`CLAUDE.md` Two-Tier Gate section** — new section comparing structural vs semantic gate, and explicit falsifiability claim that IDD is now strict superset of TDD ∪ SDD on the falsifiability surface (outcome verification inherited from inner methodologies + IDD-only audit-level semantic check).

### Why warn-only and not hard-refuse

The structural gate can hard-refuse because false positives are impossible — either a `- [ ]` exists or it doesn't. The semantic gate works on heuristics: a test commit might legitimately live in a prior PR not referencing #NNN, an external file might be modified by tooling, etc. A hard-refuse on heuristic check would block legitimate closes. The warn + AskUserQuestion approach surfaces the suspicious signal, makes the user explicitly acknowledge it, and lets them either proceed (confirming the heuristic was wrong) or investigate (treating the heuristic as right).

### Changed
No breaking changes. Issues that previously closed cleanly under v2.28.0 still close cleanly under v2.29.0 — the semantic gate adds a warning step but doesn't refuse anything. Issues with semantic mismatches now surface them at close time instead of staying hidden.

## [2.28.0] - 2026-04-26
### `idd-all` SDD path is now unattended

`idd-all` is a fire-and-forget orchestrator — it assumes nobody is watching. Previously the SDD path called `spectra-discuss` and `spectra-apply` directly, with two problems:

1. The middle step `spectra-propose` was missing from the chain.
2. Each spectra skill's built-in `AskUserQuestion` checkpoints would stall the pipeline — `spectra-discuss` paces conversation one question at a time; `spectra-propose` Step 10 asks "Park or Apply?" defaulting to Park; `spectra-apply` Step 4 asks for continue-confirmation.

This release makes the SDD path a true unattended chain.

### Changed
- **`idd-all` Phase 3b** — rewrote as four sub-steps: capture issue context, then call `spectra-discuss` / `spectra-propose` / `spectra-apply` in sequence. Each call passes a long `args` string with explicit instructions to suppress `AskUserQuestion` checkpoints and produce a structured marker line (`Conclusion: ...` / `Change: ...`) that the next step parses.
- **`spectra-propose` chaining** — `idd-all` calls `spectra-apply` itself rather than letting `spectra-propose` chain. This respects the architectural `NEVER invoke /spectra-apply` guardrail in spectra-propose (L267) while still achieving end-to-end automation.
- **New core principle: "Unattended assumption"** — added to idd-all's core principles. Sub-skills' attended-by-default behavior is correct for solo use; idd-all is the one promising "unattended", so it's idd-all's responsibility to override via args, not by modifying sub-skill plugins.
- **Failure modes table** — added entries for spectra-discuss / propose / apply specific failure modes (missing marker line, unrecoverable validation, unfinished tasks).
- **Complexity table footnote** — clarifies that users wanting attended SDD discussion should run `/spectra-discuss` etc. manually, not `idd-all`.
- **CLAUDE.md workflow diagram** — annotated to show idd-all's SDD path is unattended chain; manual SDD path remains attended.

### Changed
No breaking changes for users running `idd-all` from scratch — the SDD path now finishes more reliably (no longer stalls on `Park or Apply` prompt). If you were relying on the prior "abort on user input needed" escape hatch, you now need to run the SDD skills manually instead of `idd-all`. The trade-off matches the orchestrator's stated promise: pick `idd-all` for fire-and-forget, pick manual `/spectra-*` for attended alignment.

## [2.27.0] - 2026-04-26
### PR vs Direct-commit path routing

`idd-implement` now explicitly resolves between two execution paths instead of implicitly following whatever branch the user happens to be on:

- **PR path** — feature branch `idd/<N>-<slug>` + push + `gh pr create`
- **Direct-commit path** — current branch, no push, no PR

Resolution priority (highest first):

1. `--pr` / `--no-pr` flag (per-invocation)
2. Fork detection (`gh repo view --json isFork` true → forced PR path)
3. `pr_policy` config field (`always` / `never` / `ask`, default `ask`)

### Changed
- **`idd-implement`** — added Phase 0.5 PR Decision step; added Phase 5.5 PR creation (idempotent — skips if PR for branch already open). New `--pr` / `--no-pr` flags. argument-hint updated.
- **`idd-close`** — added Step 1.5 PR Gate Check. Refuses close when an open PR references the issue, instructing the user to merge first. Mirrors the "no `--force`" philosophy of the checklist gate.
- **`idd-all`** — explicitly enforces `--pr` when calling `idd-implement` (orchestrator path always = PR path, overriding `pr_policy`). Phase 3a doc clarifies this. Phase 5.5 idempotency means orchestrator's Phase 5 PR creation no longer collides with idd-implement's.
- **Config schema** — new optional `pr_policy` field in `.claude/issue-driven-dev.local.json`. Backward compatible (absent = `ask`).
- **`references/pr-flow.md`** — new canonical contract document. Branch naming, PR body template, decision matrix, all in one place. Three SKILLs link here instead of duplicating.
- **`references/config-protocol.md`** — added `pr_policy` documentation to schema and field reference.
- **`CLAUDE.md`** — new "PR vs Direct-commit Path" section describing the routing.

### Changed
No breaking changes. Existing configs without `pr_policy` default to `ask` (prompts on first `idd-implement`). Existing `idd-all` users see no behavior change — it always was PR-only; this release just makes that contract explicit and consistent with the new flag system.

If you want to opt out of the prompt on a solo / personal repo:

```json
{
  "github_repo": "owner/repo",
  "pr_policy": "never"
}
```

If you want to enforce PR for a team repo:

```json
{
  "github_repo": "owner/repo",
  "pr_policy": "always"
}
```

## [2.26.0] - 2026-04-25
(prior history not migrated to CHANGELOG; see git log)
