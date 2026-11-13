# spectra-bridge-detection Specification

## Purpose

Defines which signals tell an IDD skill that it was called in the middle of a spectra-discuss session, so that it saves a bookmark and prints a resume prompt (the bridge of `rules/spectra-bridge.md`), and which facts are not such a signal. It exists so that the state of the repository is not read as where a call came from.

## Requirements

### Requirement: Open Spectra changes do not turn the spectra bridge on

The detection block of `skills/idd-comment/SKILL.md` Step 0.7 SHALL set `SPECTRA_BRIDGE_ACTIVE=1` when at least one of these holds, and SHALL leave it `0` otherwise: the `--resume-spectra` value is not empty; the `--source` value contains `spectra-discuss`, in any letter case; a bridge file whose `active_spectra_session` is `true` exists at `.claude/.idd/state/bridge.json`, or at the legacy path `.claude/state/idd-bridge.json` when the new path has no file. When both files exist, the block SHALL read only the one at the new path. Open Spectra changes in the repository SHALL NOT be a signal, and the block SHALL NOT run the `spectra` command. The places that list the signals for a reader SHALL NOT list open or in-flight Spectra changes, in whatever language they are written: the detection table of `rules/spectra-bridge.md`, the Step 0 task description of `idd-comment`, and the sentence of the plugin's `CLAUDE.md` and of its `README.md` that lists them. A remark in one of those places that open changes do not count is not a listing. Those two sentences SHALL name `active_spectra_session` for the bridge file. Step 7 of the skill, which writes the bookmark and prints the resume prompt, SHALL be headed as applying only when `SPECTRA_BRIDGE_ACTIVE=1`.

#### Scenario: A comment in a repository that has open changes

- **GIVEN** a repository with eight open Spectra changes, none of them about the comment being posted
- **AND** `/idd-comment` is called without `--resume-spectra`, with a `--source` that does not mention spectra-discuss, and no bridge file exists
- **WHEN** Step 0.7 runs
- **THEN** `SPECTRA_BRIDGE_ACTIVE` stays `0`, so Step 7 does not apply: no bookmark is written and no resume prompt is printed

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
| empty | empty | new path, `active_spectra_session: false`, and legacy path, `active_spectra_session: true` | none | `0` |

##### Example: where the bridge signals are listed

| Place | Lists open or in-flight Spectra changes | Names `active_spectra_session` for the bridge file |
| --- | --- | --- |
| the rows of the detection table in `rules/spectra-bridge.md` | no | yes |
| the `detect_spectra_context` task description in `skills/idd-comment/SKILL.md` | no | not checked |
| the "Step 0.7 Detect" sentence of the plugin's `CLAUDE.md` | no | yes |
| the "Step 0.7 Detect" sentence of the plugin's `README.md` | no | yes |

##### Example: which wordings list open changes as a signal

A sentence is cut into clauses at brackets, full stops and semicolons, in either script. It lists open changes when a clause mentions them and that clause does not say they do not count.

| Sentence | Lists open changes as a signal |
| --- | --- |
| --source 含 spectra-discuss、repo 裡有開著的 Spectra change — 任一觸發 | yes |
| --source contains spectra-discuss, or the repository has open Spectra changes → on | yes |
| --source contains spectra-discuss, or spectra list shows a change → on | yes |
| --source contains spectra-discuss, or an in-flight Spectra change → on | yes |
| --source 含 spectra-discuss — 任一觸發（repo 裡有開著的 Spectra change 不算，#502） | no |
| --source contains spectra-discuss → on. Open Spectra changes in the repository are not a signal (#502) | no |
| --source 含 spectra-discuss、repo 裡有開著的 change — 任一觸發（repo 裡有開著的 Spectra change 不算，#502） | yes |

##### Example: Step 7 applies only when the bridge is on

| Place | Says |
| --- | --- |
| the heading of Step 7 in `skills/idd-comment/SKILL.md` | the step applies only when `SPECTRA_BRIDGE_ACTIVE=1` |

---
### Requirement: Conversation context does not turn the spectra bridge on

What the model that runs a skill knows from the conversation SHALL NOT be a signal: the three signals read by the detection block are the only ones. The detection table of `rules/spectra-bridge.md` SHALL have exactly three signal rows, for the `--resume-spectra` flag, the `--source` argument and the bridge file, and SHALL NOT have a row for conversation context. Below the table, the Detection section of the rule SHALL say that conversation context is not a signal and that a call made in the middle of a spectra-discuss session passes `--resume-spectra`.

#### Scenario: A comment posted in the middle of a spectra-discuss session

- **GIVEN** a spectra-discuss session in which `/idd-comment` is called without `--resume-spectra`, with a `--source` that does not mention spectra-discuss, and no bridge file exists
- **WHEN** Step 0.7 runs
- **THEN** `SPECTRA_BRIDGE_ACTIVE` stays `0`
- **AND** the same call with `--resume-spectra="<topic>"` turns the bridge on

##### Example: what the rule says about conversation context

| Part of the Detection section of `rules/spectra-bridge.md` | What it holds |
| --- | --- |
| the signal rows of the table | three: the `--resume-spectra` flag, the `--source` argument, the bridge file |
| every row of the table | no mention of conversation context |
| the text below the table | one line that says conversation context is not a signal and that a call from a spectra-discuss session passes `--resume-spectra` |
