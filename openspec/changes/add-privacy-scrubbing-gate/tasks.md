# Tasks — add-privacy-scrubbing-gate

> TDD enforced (`.spectra.yaml` tdd: true). For each behavioral task: write failing test → implement → green.
> **Phasing (APPROVED)**: spec covers ALL egress sites, but implementation lands **idd-issue FIRST** (Phase 1). The other 11 sites are Phase 2 follow-up — enumerated here as `- [ ]` under §5 but explicitly gated behind Phase 1.

## 1. Privacy-scrubbing policy rule (shared home)

- [ ] 1.1 Author `rules/privacy-scrubbing.md` (sibling to `rules/tagging-collaborators.md`): LLM-semantic-self-review detection contract, three-level strictness matrix (third-party ENFORCE / own-public WARN / private LIGHT), block-with-diff (refuse-not-strip) rule, and the explicit division of labor vs `sanitize_source_label` (#75).
- [ ] 1.2 State the anti-fixed-detection invariant in-rule: NO maintained pattern set / denylist / NLP name-detector for detection; personal-name judgment is LLM-semantic (cross-ref `.claude/rules/attribute-assessment.md`).

## 2. Egress choke-point wrapper (deterministic enforcement)

- [ ] 2.1 Write tests: dispatch refused when self-check attestation absent; dispatch proceeds when present → `scripts/tests/gh-egress/test.sh`.
- [ ] 2.2 Write tests for the mechanical last-resort net: literal `/Users/<name>` path caught; verbatim `~/.claude.json` content caught; a semantic-only private identifier is NOT caught by the wrapper (proves wrapper does not do semantic matching — that is the LLM's job).
- [ ] 2.3 Implement `scripts/gh-egress.sh` — single choke point for `create|comment|edit`; (a) enforce self-check attestation before dispatch (deterministic), (b) 2-3 mechanical zero-tolerance catches only. Placed under `plugins/issue-driven-dev/scripts/` alongside `git-ignore-block.sh`.
- [ ] 2.4 Decide + document the attestation format (Open Question Q1) at implementation time; encode the chosen handshake in the wrapper + rule.

## 3. Repo-visibility classification (reuse viewerPermission + add isPrivate)

- [ ] 3.1 Add `isPrivate` to the existing `gh repo view --json isFork,parent,viewerPermission` call (zero extra round-trip; same fold-in technique as #192).
- [ ] 3.2 Map visibility → gate level: third-party (viewerPermission ∉ {WRITE,MAINTAIN,ADMIN}) = ENFORCE; own + `isPrivate=false` = WARN; `isPrivate=true` = LIGHT. Reuse #192 third-party detection + fail-safe.
- [ ] 3.3 Patch `references/config-protocol.md` mechanism 5: document the `isPrivate` query addition and the visibility → gate-strictness mapping; note it resolves the push-permission proxy residue flagged at `add-third-party-clone-setup/design.md:145`.

## 4. idd-issue retrofit — PHASE 1 (lands first, highest-risk authoring path)

- [ ] 4.1 Write behavioral test: idd-issue in a third-party clone with a home-path-bearing draft → ENFORCE block-with-diff + confirm gate before dispatch.
- [ ] 4.2 Retrofit every `gh issue create/comment/edit` call site inside `idd-issue` to route through `bash scripts/gh-egress.sh …`.
- [ ] 4.3 Wire the LLM self-review step + attestation into idd-issue's dispatch path; reference `rules/privacy-scrubbing.md` in idd-issue Step 0 task list.
- [ ] 4.4 Confirm `sanitize_source_label` remains byte-for-byte unchanged (privacy scrubbing sits on top, does not replace).

## 5. Remaining egress-site retrofit — PHASE 2 (follow-up, gated behind Phase 1)

> Each site: swap raw `gh issue …` → `bash scripts/gh-egress.sh …` + wire self-review/attestation. Logic already lives in the wrapper (§2); these are call-site swaps.

- [ ] 5.1 `idd-comment`
- [ ] 5.2 `idd-edit`
- [ ] 5.3 `idd-diagnose`
- [ ] 5.4 `idd-implement`
- [ ] 5.5 `idd-plan`
- [ ] 5.6 `idd-update`
- [ ] 5.7 `idd-clarify`
- [ ] 5.8 `idd-close`
- [ ] 5.9 `idd-verify`
- [ ] 5.10 `idd-all-chain`
- [ ] 5.11 multi-finding Stage 4 dispatch (idd-issue-multi-finding-source) — route each create/comment/edit action through the wrapper (see §6.2 spec delta).

## 6. Spec + reference doc alignment

- [ ] 6.1 New capability spec `privacy-scrubbing-gate` (this change's `specs/privacy-scrubbing-gate/spec.md`).
- [ ] 6.2 MODIFIED delta on `idd-issue-multi-finding-source`: Stage 4 dispatch routes through `scripts/gh-egress.sh` (this change's `specs/idd-issue-multi-finding-source/spec.md`).
- [ ] 6.3 `references/config-protocol.md` cross-ref updated (done alongside §3.3).

## 7. Backward-compat regression

- [ ] 7.1 `sanitize_source_label` (#75) behavior unchanged — assert existing #75 fixtures stay green.
- [ ] 7.2 Non-retrofitted sites (before their Phase 2 turn) behave exactly as today.
- [ ] 7.3 own-private repo LIGHT level introduces no new friction for solo/private workflows (no block on ordinary identifiers).

## 8. Version + changelog

- [ ] 8.1 Bump `idd-issue` plugin minor version at Phase 1 release cut; other site skills bump as their Phase 2 lands.
- [ ] 8.2 CHANGELOG `[Unreleased]` entry referencing #202.
