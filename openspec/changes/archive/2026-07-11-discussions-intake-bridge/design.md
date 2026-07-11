## Context

Two prose SKILLs (idd-list, idd-issue) gain Discussions awareness through GraphQL (Discussions have no REST API). The direction was fully settled by the issue author's own design constraints in #221's body plus the 2026-07-06 diagnosis; this design records the operational decisions the implementer needs.

## Goals / Non-Goals

**Goals**: opt-in surfacing in idd-list; Discussion-seeded filing in idd-issue; one shared normative contract + GraphQL templates in a reference doc; drift-guard test.

**Non-Goals**: sentiment-based resolution detection; auto-filing; always-on fetch; any Discussions write beyond the single back-reference reply. (See proposal Non-Goals.)

## Decisions

### D1 — One shared reference doc owns the contract and the GraphQL

Both skills cite `references/discussions-intake.md` instead of each embedding its own query text. The doc carries: (a) the three normative constraints — **no-auto-file** (surface + human judge), **dedup** (a Discussion referenced by any existing issue, open or closed, is not re-flagged), **resolution-detection** (`answerChosenAt != null` → not actionable; sentiment reading is out of scope); (b) the `hasDiscussionsEnabled` probe query; (c) the discussions list query (first 50, fields: number, title, url, category name, answerChosenAt, updatedAt, author login); (d) the single-discussion fetch query (title, body, url, author, category, answerChosenAt) for idd-issue seeding. Rationale: two copies of a GraphQL string is the drift the plugin's own deep-integration rule forbids.

### D2 — idd-list surfacing is a new Step 2.7 (opt-in, after PR fetch, before phase extraction)

`--discussions` flag only (no config key in v1). Flow: probe `hasDiscussionsEnabled` → false prints one line `(discussions disabled on this repo — skip)` and continues; true → fetch → filter category ∈ {Q&A, Ideas} AND `answerChosenAt == null` → dedup by searching issue bodies for the discussion URL (`gh search issues` / `gh issue list --search` with the URL, both states) → render a dedicated `Discussions (actionable)` block after the issues table with per-row `→ /idd-issue --from-discussion <url>` as the suggested next, and a footer count. Zero actionable → one-line note, not silence (surfacing tools must not silently swallow an empty channel).

### D3 — idd-issue seeding records provenance verbatim; the reply is draft-and-confirm with a hard unattended boundary

`--from-discussion <url|number>`: fetch the Discussion, seed the issue body with a `## Provenance` section (Discussion URL + author + a verbatim blockquote of the opening post — blockquote per the plugin's 原文引用 discipline), then continue the normal idd-issue flow (type/priority gathering, privacy gate, egress). After the issue exists: draft the back-reference reply (`Filed as <issue-url> — follow-up there`) and (attended) AskUserQuestion confirm before `gh api graphql` addDiscussionComment; (unattended) **never post** — print the draft in the Step 5 report as "suggested reply (not posted)". This mirrors the #141 surface-only contract for outward-facing writes.

### D4 — Drift-guard tests mock nothing live

`scripts/tests/discussions-intake/test.sh` asserts the prose contract (flags documented, constraints named, reference doc sections present, unattended draft-only boundary stated, no-auto-file literal) — the falsifiable form for prose SKILLs, consistent with every sibling suite. No live GraphQL in tests.

## Risks / Trade-offs

- **GraphQL schema drift** (Discussions API is younger than REST): the reference doc records the schema assumption (field names + query date); a query failure in the wild degrades to the same one-line skip as discussions-disabled, never a hard abort of idd-list.
- **Dedup search cost**: one search per actionable discussion, bounded by the ≤50 fetch window and the category/answered filters that run first.
- **Opt-in invisibility**: users who never pass `--discussions` keep the blind spot. Accepted for v1 (latency + noise trade-off, per issue body); revisit a config key if the flag proves sticky.

## Migration Plan

Additive flags only; no existing invocation changes behavior. No migration.

## Open Questions

(none — direction settled in #221 body + diagnosis; Spectra opt-out conditions were met)
