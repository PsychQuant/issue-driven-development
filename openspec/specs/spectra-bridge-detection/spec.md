# spectra-bridge-detection Specification

## Purpose

Defines which signals tell an IDD skill that it was called in the middle of a spectra-discuss session, so that it saves a bookmark and prints a resume prompt (the bridge of `rules/spectra-bridge.md`), and which facts are not such a signal. It exists so that the state of the repository is not read as where a call came from.

## Requirements

### Requirement: Open Spectra changes do not turn the spectra bridge on

The detection block of `skills/idd-comment/SKILL.md` Step 0.7 SHALL set `SPECTRA_BRIDGE_ACTIVE=1` when at least one of these holds, and SHALL leave it `0` otherwise: the `--resume-spectra` value is not empty; the `--source` value contains `spectra-discuss`, in any letter case; a bridge file whose `active_spectra_session` is `true` exists at `.claude/.idd/state/bridge.json`, or at the legacy path `.claude/state/idd-bridge.json` when the new path has no file. When both files exist, the block SHALL read only the one at the new path. Open Spectra changes in the repository SHALL NOT be a signal, and the block SHALL NOT run the `spectra` command. The places that list the signals for a reader SHALL NOT list open or in-flight Spectra changes, whether the sentence is in English or in Chinese: the detection table of `rules/spectra-bridge.md`, the Step 0 task description of `idd-comment`, and the sentence of the plugin's `CLAUDE.md` and of its `README.md` that lists them. A remark in one of those places that open changes do not count is not a listing. A row of the detection table SHALL NOT mention Spectra changes at all; for the three sentences, the wording rule of the Example "which wordings list open changes as a signal" tells a listing from a remark, and a wording outside that rule is not recognised. Those two sentences SHALL name `active_spectra_session` for the bridge file. Step 7 of the skill, which writes the bookmark and prints the resume prompt, SHALL be headed as applying only when `SPECTRA_BRIDGE_ACTIVE=1`.

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

The wording rule, in four steps:

1. The sentence is cut into clauses at every bracket (`(`, `)`, `（`, `）`), comma (`,`, `，`, `、`), semicolon (`;`, `；`), ideographic full stop (`。`) and full stop followed by a space.
2. A clause mentions Spectra changes when it holds a word that starts with `change` or `Change`, or one of `變更`, `提案`, `spectra list`, `in-flight`, `In-flight`.
3. A clause that mentions them is a remark when one of these comes after the mention in the same clause: `不算`, `不是訊號`, `not a signal`, `not signals`, `do not count`, `does not count`, `don't count`, `not counted`.
4. The sentence lists open changes as a signal when at least one clause mentions them and is not a remark.

The suite reads the rows of this table and runs the rule on each sentence.

| Sentence | Lists open changes as a signal |
| --- | --- |
| --source 含 spectra-discuss、repo 裡有開著的 Spectra change — 任一觸發 | yes |
| --source contains spectra-discuss, or the repository has open Spectra changes → on | yes |
| --source contains spectra-discuss, or spectra list shows one → on | yes |
| --source contains spectra-discuss, or an in-flight proposal → on | yes |
| In-flight proposals turn it on | yes |
| Changes left open turn it on | yes |
| --source 含 spectra-discuss、repo 裡有進行中的變更 — 任一觸發 | yes |
| --source 含 spectra-discuss、repo 裡有尚未封存的提案 — 任一觸發 | yes |
| --source 含 spectra-discuss — 任一觸發（repo 裡有開著的 Spectra change 不算，#502） | no |
| --source contains spectra-discuss → on. Open Spectra changes in the repository are not a signal (#502) | no |
| --source contains spectra-discuss → on. Open Spectra changes do not count (#502) | no |
| 開著的 change 不是訊號 | no |
| Open changes are not signals | no |
| An open change does not count | no |
| Open changes don't count | no |
| Open changes are not counted | no |
| --source contains spectra-discuss and the default is unchanged → on | no |
| --source 含 spectra-discuss、repo 裡有開著的 change — 任一觸發（repo 裡有開著的 Spectra change 不算，#502） | yes |
| --source contains spectra-discuss, or open Spectra changes → on;Open Spectra changes are not a signal | yes |
| --source 含 spectra-discuss、repo 裡有開著的 change — 任一觸發，對話脈絡不算 | yes |
| --source 含 spectra-discuss、repo 裡有開著的 change 也算、舊路徑不算 | yes |
| --source 含 spectra-discuss。repo 裡有開著的 change 算。其他不算 | yes |
| --source 含 spectra-discuss — 任一觸發；repo 裡有開著的 change 算；其他不算 | yes |
| --source contains spectra-discuss, or open Spectra changes → on, and a false bridge file is not a signal | yes |
| Open Spectra changes turn it on. The legacy path does not count | yes |
| --source contains spectra-discuss, or open Spectra changes (a false bridge file is not a signal) → on | yes |
| --source 含 spectra-discuss、repo 裡有開著的 change 算（舊路徑不算） | yes |
| --source 含 spectra-discuss — 任一觸發；其他不算但 repo 裡有開著的 change 算 | yes |
| --source 含 spectra-discuss — 任一觸發；repo 裡有開著的 Spectra change（#502）不算 | yes |

Rows 18 to 27 each hold a listing next to a remark that sits in another clause. In row 28 the remark comes before the mention. In row 29 a bracket ends the clause before the remark, so the sentence counts as a listing: a remark has to follow the mention inside one clause.

##### Example: Step 7 applies only when the bridge is on

| Place | Says |
| --- | --- |
| the heading of Step 7 in `skills/idd-comment/SKILL.md` | `僅當 SPECTRA_BRIDGE_ACTIVE=1` (only when it is 1) |

---
### Requirement: Conversation context does not turn the spectra bridge on

What the model that runs a skill knows from the conversation SHALL NOT be a signal: the three signals read by the detection block are the only ones. The detection table of `rules/spectra-bridge.md` SHALL have exactly three signal rows, for the `--resume-spectra` flag, the `--source` argument and the bridge file, and SHALL NOT have a row for conversation context. Below the table, the Detection section of the rule SHALL say that conversation context is not a signal and that a call made in the middle of a spectra-discuss session passes `--resume-spectra`. Below its block, Step 0.7 of `skills/idd-comment/SKILL.md` SHALL say the same in one line that names `--resume-spectra`. The skill's rule that a spectra context must not be ignored silently SHALL tie the resume prompt to `SPECTRA_BRIDGE_ACTIVE=1` and SHALL say that this is not inferred from the conversation.

#### Scenario: A comment posted in the middle of a spectra-discuss session

- **GIVEN** a spectra-discuss session in which `/idd-comment` is called without `--resume-spectra`, with a `--source` that does not mention spectra-discuss, and no bridge file exists
- **WHEN** Step 0.7 runs
- **THEN** `SPECTRA_BRIDGE_ACTIVE` stays `0`
- **AND** the same call with `--resume-spectra="<topic>"` turns the bridge on

##### Example: what the rule and the skill say about conversation context

| Place | What it holds |
| --- | --- |
| the signal rows of the detection table in `rules/spectra-bridge.md` | three: the `--resume-spectra` flag, the `--source` argument, the bridge file |
| every row of that table | no mention of conversation context, in English or as `對話脈絡` |
| the text below that table, inside the Detection section | one line that says conversation context is not a signal and that a call from a spectra-discuss session passes `--resume-spectra` |
| the text below the block of Step 0.7 in `skills/idd-comment/SKILL.md` | one line that says `對話脈絡` is not a signal (`不是訊號`) and names `--resume-spectra` |
| the rule `Spectra context 不可靜默忽略` in the same file | names `SPECTRA_BRIDGE_ACTIVE=1` and says `不從對話推斷` (not inferred from the conversation) |
