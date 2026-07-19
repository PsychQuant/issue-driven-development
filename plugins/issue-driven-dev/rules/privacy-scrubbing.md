---
name: privacy-scrubbing
description: Mandatory repo-aware privacy-scrubbing gate every IDD skill MUST run before any GitHub issue egress (create / comment / edit)
---

# Privacy-Scrubbing Gate Rule

**The gate every IDD skill MUST pass a drafted body through BEFORE it dispatches to
GitHub via `gh issue create` / `gh issue comment` / `gh issue edit`.**

Sibling to [`tagging-collaborators.md`](tagging-collaborators.md): both guard an
*irreversible* GitHub side effect. Tagging guards `@`-mentions; this rule guards
the leak of **local / private identifiers** into a public or third-party tracker.

## Why this rule exists

Every IDD skill ends by pushing an AI-drafted body over the **egress boundary** —
past that line the content is public, the notification is sent, the archive is
permanent, and none of it can be recalled. On a third-party clone (#192) or any
public repo, a drafted body easily carries:

- an absolute local home path (`/Users/<name>/...`)
- a `~/.claude.json` project basename (leaks your local folder structure)
- a collaborator's real name (not public / not their consented context)
- unpublished research or internal context

This is the same privacy boundary as the global CLAUDE.md rule "third-party
verbatim content does not go to remote" — only here the leak path is the
**AI-drafted issue/comment body**, not a raw file.

## The two halves: LLM detects, a deterministic checkpoint enforces

The core tension: detection needs **semantic breadth** (private identifiers are
unbounded in form, cross-language, and personal-name-ness is contextual) — an LLM
strength and a regex dead-end. But "did the gate actually run?" cannot be left to
the AI remembering, across ~12 egress sites, long context, and unattended
`/loop`. So the two concerns are split:

| Concern | Owner | Mechanism |
|---|---|---|
| **Detection** (what is private?) | the **LLM**, semantically | this rule's self-review contract |
| **Enforcement** (did the gate run? did a literal leak slip?) | a **deterministic checkpoint** | `scripts/gh-egress.sh` wrapper |

### Detection is LLM semantic self-review — NOT a fixed pattern set (invariant)

At egress time the skill SHALL semantically inspect the drafted body and decide,
**by judgment**, whether it carries private identifiers. There is **no maintained
regex denylist, keyword catalogue, or NLP name-detector** as the detection
mechanism, and personal-name detection is LLM-semantic (understand from context
who is private) — **never** a fixed list or name-detection library.

Why not fixed detection:

- Private identifiers are unbounded and cross-language (home paths, internal
  codenames, unpublished project names, real name vs public handle…). A fixed
  regex/denylist necessarily both misses (false negative) and over-fires (flags
  the public `Tarski` as private).
- This mirrors this repo's [`.claude/rules/attribute-assessment.md`](../../.claude/rules/attribute-assessment.md):
  **"Deterministic match on a wrong feature is worse than honest AI judgment
  because it hides its mistake behind a rule."** "Is this content private?" is an
  attribute-assessment task — use AI judgment + disclosed reasoning, not keyword
  matching.
- The owner has explicitly rejected fixed detection. This rule MUST NOT introduce
  a maintained pattern set as the **primary** detector. (The wrapper's 2-item
  mechanical net below is an explicitly-bounded last-resort backstop, not the
  detector — and must not be grown into a semantic pattern set without a separate
  change.)

## Repo-visibility classification → three strictness levels

Classify the target repo's visibility, reusing the existing viewerPermission
own-vs-third-party detection (`references/config-protocol.md` §third-party
detection, #192) plus the `isPrivate` field folded into the same `gh repo view`
call (no extra round-trip):

| Level | Trigger | Gate behavior |
|---|---|---|
| **ENFORCE** | third-party — `viewerPermission ∉ {WRITE, MAINTAIN, ADMIN}` (incl. probe-fail fail-safe, #192) | **block-with-diff** — show a redaction diff, refuse dispatch until the user confirms |
| **WARN** | own + `isPrivate=false` (you have write access, repo is public) | **flag** — print a one-line concern, default **proceed** without blocking |
| **LIGHT** | `isPrivate=true` | do **not** block ordinary identifiers; still honor the CLAUDE.md "raw third-party verbatim content does not go to remote" rule |

Adding `isPrivate` resolves the residue flagged at
`add-third-party-clone-setup/design.md:145` — push-permission alone was a proxy
that conflated own-public with own-private; the gate can now give them different
strictness. (The *semantic* residue — "is this specific name/content private?" —
does not disappear; it is the acknowledged consequence of LLM-semantic detection,
tracked in the change's Open Question Q2.)

## ENFORCE = block-with-diff, never silent auto-redact

At ENFORCE, when a private identifier is detected:

1. show a **redaction diff** (original vs suggested redaction),
2. **refuse dispatch** until the user explicitly confirms,
3. dispatch the **confirmed** body only after confirmation.

The gate SHALL NOT silently rewrite (auto-redact) the body at any level. This
mirrors `sanitize_source_label`'s (#75) **refuse-not-strip** philosophy: a silent
body rewrite would break the audit trail, hide the AI's judgment, and rob the
user of a veto. WARN is the inverse: flag + one line, default proceed — on an
own-public repo most identifiers are acceptable and over-blocking is noise.

## Deterministic enforcement — the `scripts/gh-egress.sh` choke point

All egress routes through `bash "$CLAUDE_PLUGIN_ROOT/scripts/gh-egress.sh"
<create|comment|edit> …` instead of raw `gh issue …`. The wrapper does two
things and **only** these:

1. **Enforce the self-review attestation.** After running the self-review above
   and resolving the strictness level, the skill passes
   `--scrub-attested <enforce|warn|light>` (the resolved level, which cannot be
   produced without having run the classification). Missing / invalid
   attestation → the wrapper **refuses dispatch** (non-zero exit). This makes the
   *existence* of the gate deterministic even though its *content* is the LLM's.
   (Q1 resolution: mechanism (a), a required per-call flag — not an env var,
   which could be left globally set and silently satisfy every dispatch.)
2. **A mechanical last-resort net** catching **only 4 zero-tolerance mechanical
   items** — an absolute `/Users/<name>` home path, verbatim `~/.claude.json`
   content, and an unattested raw `@login` mention token (#117) — as
   belt-and-suspenders if the LLM misses one. It is **level-independent**
   (fires even at LIGHT: these are absolute leaks / irreversible notifications,
   not "ordinary identifiers"). It performs **no semantic pattern matching**; a
   semantically-private identifier that is not one of these mechanical items
   (e.g. an unpublished project codename) is deliberately **not** caught by the
   wrapper — that breadth is the LLM self-review's job.

The wrapper MUST NOT grow a semantic check; the #202 D1/D2 boundary is
"mechanical token matching only". The 2→3 growth (#117 mention net) and the
3→4 growth (#272 reply tier-floor backstop — matching IDD's own metadata
marker tokens, not content) both stayed on the mechanical side of that line;
any future semantic expansion requires a separate openspec change (spec: "net
does not grow into semantic matching").

## Division of labor vs `sanitize_source_label` (#75)

Both run before egress; they do **not** overlap:

| | `sanitize_source_label` (#75) | privacy-scrubbing gate (this rule) |
|---|---|---|
| Layer | character / mention hygiene | semantic private-identifier review |
| Scope | the `<source>` **label** (footer filename / paste excerpt) | the **whole drafted body**, repo-aware |
| Does | strip C0/C1/DEL/bidi control chars; refuse `@`-mention tokens | LLM semantic self-review + strictness by repo visibility |
| Style | mechanical, deterministic | AI judgment + block-with-diff |

`sanitize_source_label` is **unchanged** — it keeps doing its control-char strip
and `@`-mention refuse on source labels. Privacy scrubbing is a **new semantic
layer on top**, not a replacement.

## Implementation contract for skill authors (no skipping)

Every IDD egress skill (`idd-issue`, `idd-comment`, `idd-edit`, `idd-diagnose`,
`idd-implement`, `idd-plan`, `idd-update`, `idd-clarify`, `idd-close`,
`idd-verify`, `idd-all-chain`, and the multi-finding Stage 4 dispatch) MUST:

1. **Reference this rule in its Step 0 Bootstrap Stage task list** (a
   `privacy_scrub_gate` task) so the self-review is a tracked, non-silent step.
2. **Resolve the strictness level once** from repo visibility (§classification),
   reusing the `gh repo view --json isFork,parent,viewerPermission,isPrivate`
   fold-in.
3. **Run the LLM semantic self-review** on the drafted body before dispatch; at
   ENFORCE, block-with-diff and get user confirmation; at WARN, flag + proceed.
4. **Route every `gh issue create/comment/edit` through
   `scripts/gh-egress.sh <verb> … --scrub-attested <level>`** — never raw
   `gh issue …`. A wrapper refusal (exit 3 attestation / exit 4 mechanical net)
   is a hard error for a single dispatch; in warn-continue batch dispatch
   (multi-finding Stage 4) it is recorded as a non-dispatched action and does
   NOT abort the remaining actions.

**Phasing (APPROVED):** the spec covers all sites; implementation lands
`idd-issue` first (Phase 1, highest-risk authoring path). The other sites are
Phase 2 follow-up call-site substitutions (the logic already lives in the
wrapper).

## Reply layer-3 payload tier floor (#272)

`idd-comment --type=reply` is the only comment type that mandates verbatim
reproduction of a third party's words. Its three points-source layers carry
unequal risk: layers 1–2 (an existing comment / the issue body) re-quote
content **already on this repository's remote** — zero new exposure — while
layer 3 (**user-pasted external text**: an email, a DM, meeting notes) is the
one channel where NEW third-party verbatim content first reaches the remote.
Because the strictness level is repo-visibility-keyed, the characteristic reply
case (third-party words posted to the user's OWN repo) resolves to WARN/LIGHT
and never ENFORCE — so for layer-3 payloads the tier default is not enough:

1. **LIGHT does not apply** to a reply whose points source is user-pasted
   (marker `points-from=user-pasted`), regardless of repository visibility.
   The minimum is **WARN plus an explicit user confirmation** that the quoted
   third-party content may be pushed to the remote.
2. **Unattended contexts SHALL NOT post** such a reply: refuse with an
   explanatory notice and defer to an attended session (no human is present to
   give the confirmation the floor requires).
3. Layers 1–2 remain governed by the repository-visibility default (the floor
   binds layer 3 only — proportionality).

Deterministic backstop: `gh-egress.sh` net item 4 refuses (attestation band,
exit 13) when the drafted body carries both the `type=reply` and
`points-from=user-pasted` marker tokens while the attested level is `light`.
This matches IDD's **own structured metadata marker tokens only** — it is not,
and must not grow into, semantic content matching. A marker-less body bypasses
the backstop by construction: the SKILL-side confirmation step is the primary
gate; the wrapper is belt-and-suspenders (same philosophy as the other three
net items). Anchor: the CLAUDE.md "raw third-party verbatim content does not go
to remote" iron rule — this floor is its mechanical enforcement for the one
channel reply opened.

## Related rules

- [`tagging-collaborators.md`](tagging-collaborators.md) — the sibling
  irreversible-GitHub-side-effect guard (`@`-mentions).
- [`.claude/rules/attribute-assessment.md`](../../.claude/rules/attribute-assessment.md)
  — why "is this private?" is AI judgment, not keyword matching.
- `references/config-protocol.md` §third-party detection — the viewerPermission +
  `isPrivate` classification this gate reuses.
