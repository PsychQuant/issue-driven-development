## 1. Reference document — `references/bundle-flags.md`

- [x] 1.1 Create skeleton `plugins/issue-driven-dev/references/bundle-flags.md` with sections: Overview / Flag Spec / Edit Algorithm / Fallback Chain / Partial Failure / Idempotency Contract
- [x] 1.2 Document `--parent` flag spec covering Requirement: `idd-issue SHALL accept --parent flag to register child in parent task list`. Include the idempotent task list edit algorithm per Decision: Parent body task list 編輯演算法 idempotent (find first contiguous `- [ ]`/`- [x]` section → scan for existing `#child` reference → append only if absent → fallback to `## Children` anchor when no list exists)
- [x] 1.3 Document `--blocked-by` flag spec covering Requirement: `idd-issue SHALL accept --blocked-by flag with three-layer fallback`. Detail Decision: Blocked-by 三層 fallback chain (Layer 1 GraphQL `addBlockedByDependency` mutation attempt + Layer 2 unconditional body blockquote + Layer 3 parent annotation when `--parent` co-used). Specify GraphQL failure → warning + continue, no abort
- [x] 1.4 Document `--bundle-mode` flag spec covering Requirement: `idd-issue SHALL accept --bundle-mode flag for batch bundle creation`. Justify Decision: Flag 介面拆三層而非單一 mega flag (three independent flags compose to full bundle; mega flag would prevent incremental child addition). Cover ordered chain semantics (strict child[i] blocked by child[i-1]) and unordered (task list only, no Blocked-by)
- [x] 1.5 Document Decision: Cross-repo bundle 直接 refuse 而非降級 in references/bundle-flags.md — refuse rule when `--parent <N>` parent issue lives in different repo than resolved target;suggest `groups` mechanism. Document orthogonality covering Requirement: `Bundle mechanism SHALL coexist orthogonally with milestone, group, and sister sweep` — no interaction with Step 4.5 milestone, Step 4.7 sister sweep, or `groups` cross-repo

## 2. SKILL.md — flag handling implementation

- [x] 2.1 Update Step 0 Bootstrap Task List in `plugins/issue-driven-dev/skills/idd-issue/SKILL.md` to add bundle-related TaskCreate entries (`resolve_parent_link`, `apply_blocked_by`, `orchestrate_bundle_mode`)
- [x] 2.2 Implement `--parent <N>` handling in SKILL.md Step 3 covering Requirement: `idd-issue SHALL accept --parent flag to register child in parent task list`. Code path: after `gh issue create` for child, run idempotent body PATCH algorithm per Decision: Parent body task list 編輯演算法 idempotent
- [x] 2.3 Implement `--blocked-by <M>[,<M2>...]` handling in SKILL.md Step 3 covering Requirement: `idd-issue SHALL accept --blocked-by flag with three-layer fallback`. Apply Decision: Blocked-by 三層 fallback chain — prepend body blockquote unconditionally, attempt GraphQL mutation per target with try/catch + warning on failure, annotate parent task list entry when `--parent` co-used
- [x] 2.4 Implement `--bundle-mode <ordered|unordered>` handling in SKILL.md Step 3 covering Requirement: `idd-issue SHALL accept --bundle-mode flag for batch bundle creation`. Orchestration: create epic → loop N children with auto-applied `--parent` → on `ordered` apply `--blocked-by <prev>` to each child after first
- [x] 2.5 Implement cross-repo refuse logic per Decision: Cross-repo bundle 直接 refuse 而非降級. Hook after Step 0.5/Step 2.5 target resolution: if `--parent <N>` and `gh issue view <N> --repo $TARGET` returns 404 or wrong repo metadata, abort with error naming both repos and pointing at `groups` mechanism
- [x] 2.6 Audit Step 4.5 (auto-milestone) + Step 4.7 (sister sweep) + group mode (Step 3.G) integration covering Requirement: `Bundle mechanism SHALL coexist orthogonally with milestone, group, and sister sweep`. Confirm bundle children get milestone assignment;confirm parent epic still subject to sister sweep;confirm group mode and `--bundle-mode` are mutually exclusive (refuse if both)

## 3. SKILL.md — `## Ordered Bundle Pattern` documentation section

- [x] 3.1 Add `## Ordered Bundle Pattern` section to SKILL.md placed after Step 5 / before `## 來源文件規則` per Decision: SKILL.md 段落放在 Step 5 之後而非散落各 Step. Open with three-mode comparison table (parent + task list / GitHub native dependency / milestone) including columns: ordering enforced / GitHub UI support / idd-issue automation / suitable for
- [x] 3.2 In `## Ordered Bundle Pattern` section, add three flag-combination usage examples: (a) single child added to existing parent via `--parent`, (b) full ordered bundle from scratch via `--bundle-mode ordered`, (c) retrofit existing scattered issues by manually editing parent body + invoking `--blocked-by` per child
- [x] 3.3 In `## Ordered Bundle Pattern` section, document design rationale for why no separate `/idd-bundle` skill (target resolution / attachment / mention validation 70% overlap with `idd-issue`;flag composition is lower-cost integration)

## 4. Plugin metadata + integration

- [x] 4.1 [P] Update `plugins/issue-driven-dev/CLAUDE.md` skills table `idd-issue` row description to mention bundle flag support (single line addition, references `## Ordered Bundle Pattern` section)
- [x] 4.2 Bump `plugins/issue-driven-dev/.claude-plugin/plugin.json` version 2.51.0 → 2.52.0 and prepend changelog entry to description summarizing flags + new reference doc
- [x] 4.3 [P] Add v2.52.0 entry to `plugins/issue-driven-dev/CHANGELOG.md` with structured summary: new flags, new reference doc, no breaking changes, related capability `idd-issue-bundle`

## 5. Dogfood verification on real GitHub

- [x] 5.1 Create test ordered bundle in this repo:invoke `idd-issue --bundle-mode ordered` with three test items, verify epic + three children created, parent task list contains all three, child2/child3 have `> Blocked by` blockquote
- [x] 5.2 Verify GitHub UI rendering:open epic in browser, confirm sub-issue progress bar appears (0/3), confirm GraphQL native Blocked-by warning visible on child2 when GraphQL succeeded
- [x] 5.3 Simulate GraphQL native dep failure (e.g., target repo without enabled feature):confirm child body blockquote persists, confirm warning emitted to user, confirm child issue creation succeeded (no abort)
- [x] 5.4 Verify idempotency:invoke `idd-issue --parent <epic>` twice for same child issue (simulating retry after partial failure), confirm parent body task list still contains exactly one entry for that child
- [x] 5.5 Verify cross-repo refuse:attempt `idd-issue --parent <N>` where `<N>` is an issue number in a different repo than resolved target, confirm error message names both repos and suggests `groups` mechanism, confirm child issue NOT created
- [x] 5.6 Verify orthogonality with milestone:invoke `idd-issue --bundle-mode ordered` from a `.docx` source with three items, confirm Step 4.5 creates milestone, confirm parent epic + all three children assigned to that milestone, confirm bundle behavior unchanged

## 6. Marketplace sync

- [x] 6.1 Run `/plugin-tools:plugin-update issue-driven-dev` to sync marketplace.json + bump cache after merge
- [x] 6.2 Smoke-test post-sync:after marketplace update, invoke `idd-issue --parent` flag once and confirm flag is recognized (not "unknown flag" error), confirm new SKILL.md content reflects in cache
