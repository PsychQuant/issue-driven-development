## Purpose

Defines which signals tell an IDD skill that it was called in the middle of a spectra-discuss session, so that it saves a bookmark and prints a resume prompt (the bridge of `rules/spectra-bridge.md`), and which facts are not such a signal. It exists so that the state of the repository is not read as where a call came from.

## ADDED Requirements

### Requirement: Open Spectra changes do not turn the spectra bridge on

The detection block of `skills/idd-comment/SKILL.md` Step 0.7 SHALL set `SPECTRA_BRIDGE_ACTIVE=1` when at least one of these holds, and SHALL leave it `0` otherwise: the `--resume-spectra` value is not empty; the `--source` value contains `spectra-discuss`, in any letter case; a bridge file whose `active_spectra_session` is `true` exists at `.claude/.idd/state/bridge.json`, or at the legacy path `.claude/state/idd-bridge.json` when the new path has no file. Open Spectra changes in the repository SHALL NOT be a signal, and the block SHALL NOT run the `spectra` command. The places that list the signals for a reader SHALL NOT list open or in-flight Spectra changes: the detection table of `rules/spectra-bridge.md`, the Step 0 task description of `idd-comment`, and the sentence of the plugin's `CLAUDE.md` and of its `README.md` that lists them. Those two sentences SHALL name `active_spectra_session` for the bridge file.

No executable check: the row "Conversation context" of the rule's table is judged by the model that runs the skill and is not part of the block; what the skill does once the bridge is on (Step 7) is carried out by that model too.

#### Scenario: A comment in a repository that has open changes

- **GIVEN** a repository with eight open Spectra changes, none of them about the comment being posted
- **AND** `/idd-comment` is called without `--resume-spectra`, with a `--source` that does not mention spectra-discuss, and no bridge file exists
- **WHEN** Step 0.7 runs
- **THEN** `SPECTRA_BRIDGE_ACTIVE` stays `0`, no bookmark is written and no resume prompt is printed

##### Example: what turns the spectra bridge on

In every row the block does not run `spectra`.

| `--resume-spectra` | `--source` | Bridge file | Open Spectra changes | `SPECTRA_BRIDGE_ACTIVE` |
| --- | --- | --- | --- | --- |
| empty | empty | none | 8 | `0` |
| empty | empty | none | none | `0` |
| `my topic` | empty | none | none | `1` |
| empty | `Spectra-Discuss session` | none | none | `1` |
| empty | empty | new path, `active_spectra_session: true` | none | `1` |
| empty | empty | legacy path only, `active_spectra_session: true` | none | `1` |
| empty | empty | new path, `active_spectra_session: false` | 8 | `0` |

##### Example: where the bridge signals are listed

| Place | Lists open or in-flight Spectra changes | Names `active_spectra_session` for the bridge file |
| --- | --- | --- |
| the rows of the detection table in `rules/spectra-bridge.md` | no | yes |
| the `detect_spectra_context` task description in `skills/idd-comment/SKILL.md` | no | not checked |
| the "Step 0.7 Detect" sentence of the plugin's `CLAUDE.md` | no | yes |
| the "Step 0.7 Detect" sentence of the plugin's `README.md` | no | yes |
