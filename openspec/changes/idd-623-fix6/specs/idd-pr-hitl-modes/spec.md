## MODIFIED Requirements

### Requirement: A run with a stop mode leaves a record of how its verify loop ended

When `/idd-all` runs with a stop mode and `close-stage.py next` answers anything other than `fix`, the Phase 4 block that runs `next` SHALL append one JSON line to the stop-mode record through `scripts/stop-mode-log.py append`. The line SHALL carry the repository, the issue, the run's `created_at`, the mode, the decision, whether `next` answered merge (`next_merge`; not whether the run merged, because the close stage can still stop it), `decided`, the reason, and every recorded round with its status, Blocking count, In-scope count and report id. The record file SHALL be `~/.claude/.idd/stop-mode-runs.jsonl` unless `IDD_STOP_LOG` names another path, outside every repository. A run without a stop mode, a `fix` answer, a run with no readable run state, or a run another `/idd-all` replaced (`replaced` in `next`'s answer or in the gate's answer, which the Phase 4 gate block has `close-stage.py gate --write-answer yes` write to `.claude/.idd/state/idd-all-gate-<N>.json` and the `next` block passes to `append` with `--gate-file`, because the two blocks are separate Bash calls) SHALL write nothing, because a replaced run no longer owns the run state on disk. `gate --write-answer yes` SHALL write that file inside the state directory opened one component of its path at a time without following a symbolic link (with search permission only where the platform can open a directory for that, `O_PATH` on Linux or `O_SEARCH` on macOS; elsewhere every directory on the path has to be readable), doing every step relative to that directory: it SHALL refuse a symbolic link at the name or in the state directory's path instead of following it, SHALL write a temporary file created exclusively by a relative name in that directory, set to mode 0600 whatever the umask, and move it into place, and when the write fails it SHALL remove the previous answer if that is a regular file, or else empty it, but only after checking that the file it opened is a regular file with one link, and only warn, saying that the previous answer may still be there when it could be neither removed nor emptied, its state could not be read, or the state directory could not be opened or entered; the gate's answer on stdout and its exit code SHALL NOT change, and without `--write-answer` no file SHALL be written. When the gate refuses its arguments but was given `--write-answer yes` with a working directory and an issue number it can use, read as flag and value pairs (a value is never taken for a flag, and a flag given twice with the same value counts once), it SHALL write no answer and SHALL remove or empty the previous one the same way, so that the next block does not take it for this round's. The gate block SHALL NOT write the file itself. Only for an answer that would otherwise be written, `append` SHALL read the gate's answer; a `--gate-file` that is not this issue's gate file in its state directory (its directory part, resolved once by the system with every symbolic link in it followed, has to be the state directory itself, compared by device and inode with the directory opened as below, so that a `..` after a link counts where it leads, also when the state directory holds a valid answer; a directory part the system cannot resolve, such as one through a missing directory, is unreadable), that is a symbolic link, or that is not a regular file SHALL be treated as unreadable, and it SHALL be opened by its name inside the state directory, opened the same way, not through the path as given, without following a symbolic link and without blocking, so that a FIFO there is refused, not waited on; when that answer was asked for (`--gate` or `--gate-file`) and is missing, empty, not JSON, not a JSON object, or carries a `round` other than `next`'s, `append` SHALL write nothing and say why on stderr. A fix answer, a replaced `next` answer, a run with no readable run state and a run without a stop mode SHALL write nothing without reading the gate's answer and without a message. The `next` block SHALL say not to run it again for a record that was not written. Phase 6 SHALL delete the gate file together with the run state. A record whose last line has no newline SHALL get one before the next line is appended. A run replaced earlier, before its gate read the run state, cannot be told apart this way; telling it apart needs the run's identity from its own init (#618). The record file SHALL be created with mode 0600, and a symbolic link at its path SHALL NOT be followed (the append fails and only warns). A failed append SHALL print a warning and SHALL NOT change the run. `stop-mode-log.py summary` SHALL group the records by mode, taking the last line written for each (repository, issue, `created_at`), and SHALL count merge answers as such, not as merged runs. A line that parses as JSON but is not shaped like a line `append` writes (no string `mode`, `rounds` not a list of objects, a `reason` that is not text, or a key that cannot be compared), and a line that is not UTF-8, SHALL be counted as unreadable, not stop `summary`; the text output SHALL print the mode, each to-fix sequence and each reason with their control characters (C0 and C1) escaped.

#### Scenario: A stop answer of a run with a stop mode is recorded once per run

- **GIVEN** a run with stop mode `exhaustive-blocking` and one recorded round
- **WHEN** `next` answers stop, and is asked again with the same answer
- **THEN** the record has two lines for the run and `summary` counts the run once

##### Example: what append writes

| Run | `next` answer | Lines appended |
| --- | --- | --- |
| stop mode `early`, one round | stop, merge true | 1 |
| stop mode `exhaustive-blocking`, two rounds | stop, merge false | 1 |
| stop mode `exhaustive-blocking` | fix | 0 |
| no stop mode | stop | 0 |
| no run state | stop, undecided | 0 |
| stop mode `early`, `next` answered `replaced` | stop, undecided | 0 |
| stop mode `early`, the gate answered `replaced`, `next` answered without the flag | stop, undecided | 0 |
| stop mode `early`, the gate's answer empty, not JSON or not an object | stop, undecided | 0 |
| stop mode `early`, the gate's answer from another round | stop, merge true | 0 |
| stop mode `exhaustive-blocking`, the gate's answer empty | fix | 0, and no message |

#### Scenario: A failed append does not change the run

- **GIVEN** a record path that cannot be written
- **WHEN** the Phase 4 `next` block runs
- **THEN** it prints a warning, `NEXT_JSON` and `NEXT_RC` are the answer of `next`, and the block's own result is unchanged

#### Scenario: The summary does not claim a merge

- **GIVEN** a record whose `next` answered stop with merge true
- **WHEN** `summary` is run
- **THEN** it counts one merge answer for the mode, says `next answered merge`, and has no `merged` count

#### Scenario: The gate's answer file is written and read through the state guards

- **WHEN** the Phase 4 gate block runs and the `next` block reads the gate's answer
- **THEN** the file is written only by `close-stage.py gate --write-answer yes` through the run state's guards, and `append` reads only this issue's regular gate file, never through a symbolic link

##### Example: the gate writes its answer without following a symbolic link

- **GIVEN** a run state for issue 7
- **WHEN** `gate` runs without `--write-answer`, then with `--write-answer yes`, then with a symbolic link at `idd-all-gate-7.json` to another file, then with the move into place failing over an earlier answer, then with that move failing and the earlier answer not removable, then with the state directory itself a symbolic link, then with that move failing over an earlier answer that can be neither removed nor emptied, then over one that is hard-linked to another path and cannot be removed, then with arguments it refuses (an empty `--base`) over an earlier answer, then with `--repo --write-answer yes` (a value that reads like the flag), then with `--write-answer yes` given twice and an empty `--base`, then under an ancestor directory that can be searched but not listed, then under umask 477
- **THEN** the first leaves no gate file; the second writes the gate's answer as printed, mode 600; the third leaves the other file unchanged, warns, and prints the same answer with the same exit code as the first; the fourth warns, prints the same answer with the same exit code, removes the earlier answer and leaves no temporary file; the fifth prints the same answer with the same exit code, leaves the earlier answer empty and does not say it may still be there; the sixth prints the same answer with the same exit code as without the flag in that directory, writes nothing through the link and warns that the previous answer may still be there; the case where the earlier answer can be neither removed nor emptied and the case where it is hard-linked to another path and cannot be removed print the same answer with the same exit code and warn that the previous answer may still be there, the hard-linked one leaving the other path's content unchanged; the refused arguments print what they print without the flag, with the same exit code, and leave no earlier answer; the value that reads like the flag leaves the earlier answer as it was, the flag given twice clears the earlier answer, under the search-only ancestor the gate file is written where the platform can open a directory for search only, and otherwise no gate file is written and the gate warns (an account that can list the directory anyway does not test it), and under umask 477 it is mode 600

##### Example: append reads only this issue's gate file and never through a symbolic link

- **GIVEN** a run state for issue 41 with a stop mode and a `stop` answer from `next`
- **WHEN** `--gate-file` is a symbolic link to a readable answer, a file named `idd-all-gate-41.json` in a directory outside the state directory, a path in the state directory whose `..` after a symbolic link leads outside it, while the state directory holds a valid answer, issue 42's gate file, a directory, a FIFO with no writer, a path through a missing directory (`missing/..`) while the state directory holds a valid answer, a file of that name in a directory elsewhere that a second path lookup would report as the state directory, and then issue 41's regular gate file
- **THEN** the first eight write no record and say why (the seventh that it cannot be read, the eighth that it is not this issue's gate file) (the first that it cannot be read, the second, the third and the fourth that it is not this issue's gate file, the fifth and the sixth that it is not a regular file, without waiting on the FIFO), and the last writes one, also under an ancestor of the state directory that can be searched but not listed where the platform can open a directory for search only (`O_PATH`, `O_SEARCH`); without such an open no record is written there, and an account that can list the directory anyway does not test it

##### Example: the gate block has the gate write its answer

- **GIVEN** the Phase 4 gate block of `idd-all`
- **WHEN** its text is read
- **THEN** it calls `close-stage.py gate` with `--write-answer yes` and has no redirect into the gate file

