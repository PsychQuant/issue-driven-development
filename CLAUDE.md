<!-- SPECTRA:START v1.0.2 -->

# Spectra Instructions

This project uses Spectra for Spec-Driven Development(SDD). Specs live in `openspec/specs/`, change proposals in `openspec/changes/`.

## Use `/spectra-*` skills when:

- A discussion needs structure before coding → `/spectra-discuss`
- User wants to plan, propose, or design a change → `/spectra-propose`
- Tasks are ready to implement → `/spectra-apply`
- There's an in-progress change to continue → `/spectra-ingest`
- User asks about specs or how something works → `/spectra-ask`
- Implementation is done → `/spectra-archive`
- Commit only files related to a specific change → `/spectra-commit`

## Workflow

discuss? → propose → apply ⇄ ingest → archive

- `discuss` is optional — skip if requirements are clear
- Requirements change mid-work? Plan mode → `ingest` → resume `apply`

## Parked Changes

Changes can be parked（暫存）— temporarily moved out of `openspec/changes/`. Parked changes won't appear in `spectra list` but can be found with `spectra list --parked`. To restore: `spectra unpark <name>`. The `/spectra-apply` and `/spectra-ingest` skills handle parked changes automatically.

<!-- SPECTRA:END -->

## Reference Projects

### NSQL — Human-AI Confirmation Protocol (https://github.com/kiki830621/NSQL)

NSQL formalizes the human-AI confirmation loop: *AI detects ambiguity → shows structured understanding → human confirms or corrects **intent** → then execute*. Core principle: **"clarify before execute, never guess."**

IDD's human-in-the-loop is an instance of this protocol — not a separate model. The mapping:

- NSQL's confirmation loop = IDD's `issue` + `idd-diagnose` (Layer V / Plan / Spectra are the ambiguity detector).
- The human confirms *intent* **before** execution — not output **after**.
- `idd-verify` is an execution-fidelity check, **not** a confirmation loop — the loop already closed upstream.

When reasoning about where a human belongs in the IDD pipeline (acceptance, review, "human-in-the-loop"), treat NSQL as the canonical protocol IDD conforms to.

## Project Rules

@.claude/rules/attribute-assessment.md
@.claude/rules/deep-integration-over-hardcode.md
