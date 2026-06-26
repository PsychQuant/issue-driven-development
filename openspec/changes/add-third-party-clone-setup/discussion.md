# Discussion — add-third-party-clone-setup

Audit trail of the alignment that produced this change (per IDD MANIFESTO). Source: `/idd-diagnose #192` → spectra-discuss, 2026-06-26.

## Origin

GitHub issue #192 (`PsychQuant/issue-driven-development`). Filed after a live incident: user cloned `kaochenlong/spectra-app` + `sherly-app` (HTTPS, no push permission) as reference material, and had to manually figure out `.claude/.idd/local.json` (`pr_policy: never`) + `.git/info/exclude` to avoid polluting the original author's repo. The manual derivation should be built into IDD.

## Diagnosis verdict (idd-diagnose #192)

- Type: feature
- Complexity: **Spectra** — modifies `config-protocol.md` (normative SSOT for all idd-* target resolution) + `idd-issue` Step 0.5.E documented behavior contract (Layer 2 met); modifies normative spec behavior + affects 2+ skills + architectural decision future engineers inherit (Layer 3 met).
- Conflict Class: `C_shared_module_coord` (shared `config-protocol.md` + `idd-issue` Step 0.5.E).
- Layer V vagueness: not triggered (V1=2, V4=3).

## Aligned decisions (spectra-discuss)

The 3 open questions from diagnosis were resolved via choice-first AskUserQuestion:

1. **Detection criterion** → **hybrid** (owner-mismatch cheap pre-filter → push-permission probe only on mismatch). Rejected: pure owner-mismatch (false-positives org repos you can push to), pure push-probe (API cost on every own-repo first-run).
2. **Tracking repo** → **`--target` / config only, no auto-create** (zero outward action).
3. **Scope** → **full**: includes extracting a shared `.git/info/exclude` / `.gitignore` ignore-block writer primitive shared with Stage 4.5 #55.

## Key design subtlety surfaced

#55 (Stage 4.5) and this feature are **opposite-direction** ignore operations:

- #55: re-include a path in **tracked `.gitignore`** (so the jsonl run-log can be committed).
- #192: exclude a path in **untracked `.git/info/exclude`** (so IDD config never pollutes upstream).

→ The shared helper must be a **common primitive** (idempotent marker-delimited block writer + git parent-dir-excluded handling), parameterized by target file + direction — NOT forced into a single function. design.md D4 captures this with a byte-equivalence regression guarantee for #55.

## Residue (NSQL §4.6)

"What counts as a third-party clone worth special-casing" is partly a values judgment that push-permission cannot fully capture (e.g. a repo you co-maintain but did not create, or a read-only vendored dependency). The spec picks a mechanical proxy (push permission); the broader intent ("don't pollute repos that aren't really yours") is flagged in design.md Open Questions Q2, not silently dropped.

## Provenance

- Discuss + propose conducted manually (not via `spectra` CLI slash command) because the driving session's cwd was outside the dev clone. Artifacts authored directly into `openspec/changes/`; `.spectra/spectra.db` change-state NOT updated by this manual pass — run `spectra` CLI sync if DB consistency is required before apply.
