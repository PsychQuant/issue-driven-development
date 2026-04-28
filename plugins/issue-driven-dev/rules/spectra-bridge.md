---
name: spectra-bridge
description: Contract for IDD skills called mid-spectra session — preserve and resume context
---

# Spectra ↔ IDD Bridge Rule

**The protocol for keeping a `spectra-discuss` (or other spectra) session resumable when an IDD skill is invoked mid-flow.**

## Why this rule exists

`spectra-discuss` is a long-running, conversational skill that converges toward a decision. Real-world flow often looks like:

```
/spectra-discuss → ... thinking ...
                  → "let me capture this finding to the issue"
                  → /idd-comment ...
                  → "ok, back to the discussion"   ← context lost!
```

Without a bridge, the user has to re-explain the topic, the assumptions list, and where the discussion left off. The IDD skill has no way to signal "you should resume spectra-discuss after this" because each skill invocation is stateless from spectra's perspective.

This rule defines a lightweight, file-based bridge so any IDD skill can:

1. Detect it was called from a spectra session
2. Save enough context that spectra-discuss can pick up where it left off
3. Emit a copy-pasteable resume prompt at the end

## Detection (Step 0.7 in any IDD skill)

An IDD skill is "in a spectra context" if **any** of these signals are true:

| Signal | Source | Confidence |
|--------|--------|------------|
| `--resume-spectra="<topic>"` flag | explicit | 100% |
| `--source` argument contains `spectra-discuss` | explicit-ish | 95% |
| `spectra list --json` returns in-flight changes | environmental | 60% (could be unrelated) |
| `.claude/state/idd-bridge.json` exists with `active_spectra_session: true` | written by spectra (future contract) | 100% |
| Conversation context (skill caller knows it was launched from spectra) | implicit | varies |

If at least one signal fires → set `SPECTRA_BRIDGE_ACTIVE=1`. Otherwise, no bridge action.

## Bookmark file (Step N before exit)

When `SPECTRA_BRIDGE_ACTIVE=1`, before the skill exits, write `.claude/state/idd-bridge.json`:

```json
{
  "version": 1,
  "created_at": "2026-04-28T07:30:00+0800",
  "spectra_topic": "ContactBook 雲端資料層架構決策 — CloudKit vs Supabase vs Hybrid",
  "issue_number": 96,
  "issue_url": "https://github.com/PsychQuant/contact-book/issues/96",
  "idd_action": "idd-comment",
  "idd_action_url": "https://github.com/PsychQuant/contact-book/issues/96#issuecomment-4331333658",
  "open_questions": [
    "App 是「平台」還是「工具」？",
    "Web Admin 是否必要？"
  ],
  "next_step_hint": "/spectra-discuss 接續討論，等 @Hardy1Yang 對方向回應後收斂"
}
```

Fields:

- `version` — bump if schema changes
- `spectra_topic` — preserved verbatim from spectra-discuss args
- `issue_number` / `issue_url` — anchor for future cross-references
- `idd_action` — which IDD skill was invoked (`idd-comment` / `idd-issue` / etc.)
- `idd_action_url` — link to the comment / issue / PR just produced
- `open_questions` — list of unresolved items the discussion was tracking
- `next_step_hint` — verbatim text the user can paste back into spectra-discuss

The file is **append-aware**: if it already exists, the skill should merge (preserving older `open_questions`, updating `idd_action` to the latest).

## Resume Prompt (final output)

After the skill's normal Step N (Report), emit a clearly-delimited resume block:

```
↩ Resume spectra-discuss
═══════════════════════════════════════════════════════════
Paste the following prompt back into the spectra-discuss session
to continue with full context preserved:

  /spectra-discuss 接續 ContactBook 雲端資料層架構決策的討論。
  上輪結論已 comment 到 issue #96
  (https://github.com/PsychQuant/contact-book/issues/96#issuecomment-4331333658)
  並 tag @Hardy1Yang。等他回應方向後再收斂。
  待解問題:
    - App 是「平台」還是「工具」？
    - Web Admin 是否必要？

State saved to: .claude/state/idd-bridge.json
═══════════════════════════════════════════════════════════
```

The block is **printable text** — not a tool call, not auto-invoked. The user controls when to resume.

## Skill responsibilities

| Skill | Responsibility |
|-------|----------------|
| `idd-comment` | Detect (Step 0.7) + write bookmark + emit resume prompt (Step 7) |
| `idd-issue` | Detect (Step 0.7) + write bookmark + emit resume prompt (Step 6) |
| `idd-edit` | Same pattern, lower priority (rare to call mid-spectra) |
| `idd-diagnose`, `idd-implement`, `idd-verify`, `idd-close` | Generally NOT called mid-spectra (those are full IDD flow). No bridge needed unless user explicitly passes `--resume-spectra`. |

## Hard rules

1. **Never auto-invoke spectra-discuss.** The user controls pacing. The skill only emits a resume prompt.
2. **Bookmark is best-effort.** If `.claude/state/` doesn't exist or is read-only, log a warning and emit the resume prompt anyway (the prompt is the actual recovery mechanism; bookmark is convenience).
3. **Don't bridge silently.** Always tell the user the bridge fired ("Detected spectra context. Resume prompt below.") so they know to look for it.
4. **Verbatim topic preservation.** Don't paraphrase `spectra_topic` — the user's original wording carries assumptions that paraphrasing can lose.
5. **Stateless from spectra's side.** This rule only governs what IDD skills do. Spectra plugin authors may opt to read `idd-bridge.json` but are not required to.

## Future: spectra-side complement

If/when spectra-discuss adds bridge support, the contract is:

- spectra-discuss writes `.claude/state/idd-bridge.json` on entry with `active_spectra_session: true`, `topic`, `started_at`
- IDD skills detect the file, read its `topic`, and produce richer resume prompts
- spectra-discuss on resume reads the file's `idd_action_url` and surfaces it: "Last interruption: idd-comment at <url> — continuing from there"

This rule is forward-compatible: writing the bookmark today doesn't break anything if spectra never reads it.
