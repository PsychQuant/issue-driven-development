# What the plugin writes into a repository, and what rest mode does with it

`/idd-all` in rest mode (`skills/idd-all/SKILL.md`, `## Rest mode`) runs one issue after another in the same working tree. Between two issues `scripts/rest-queue.py settle` decides, for everything the last issue left uncommitted, whether it is discarded, never committed, or committed on that issue's branch. The lists in the requirement "Between two issues one helper settles the working tree" (capability `idd-all-rest`) come from this inventory.

A check in `scripts/tests/rest-queue/test.sh` fails when a skill or a script of the plugin names a location under `.claude/` that this file does not name. Adding a writer therefore means adding a row here, and deciding its class.

## Classes

| Class | What `settle` does with an uncommitted path of this kind |
| --- | --- |
| regenerated | Discarded when the conditions of the requirement hold: the manifest alone; or, on a branch without a commit of its own and without an upstream, the manifest with the files it vouches for (listed with the SHA-256 they have, or listed as a download that failed). Otherwise it is `kept with the issue` |
| never committed | `settle` stops with exit 3 when such a path is not ignored: its writer keeps it out of git |
| kept with the issue | Committed on the issue's own branch, locally, and listed in the report |
| shared log | As `kept with the issue`, and the report says that the path is a log shared by all issues |
| not in the working tree | Outside the repository, or inside the git directory: `git status` does not show it and `settle` does not see it |
| stashed | Put into one stash entry after the checkout of the default branch and before the fetch; nothing is deleted |
| stops | `settle` exits 3 and leaves the file as it is |
| read only | The plugin reads this location and does not write it |

## Locations under `.claude/` that skills and scripts name

Paths are relative to the directory the skill runs in (`--cwd`) unless the row says otherwise.

| Location | Writer | Class | Notes |
| --- | --- | --- | --- |
| `.claude/.idd/attachments` | `scripts/process-attachments.sh download`, called by `idd-diagnose` (every run of an issue, also when it has no attachment) | regenerated | One folder per issue, `issue-<N>/`, with `_manifest.json`. The script writes relative to the shell's current directory, not to `--cwd` (#586). `rules/process-attachments.md` says the folder is committed by default. One step stages it by name: the meeting unwind of `idd-all` (`git add -- <folder>`), which commits it on the issue's branch |
| `.claude/.idd/state` | `scripts/close-stage.py` (the run of one issue and its result), `scripts/rest-queue.py` (the rest run), `scripts/lib/unattended-state.sh` (the unattended marker), `scripts/manifest-append.sh` (the chain's spawned issues), `scripts/idd-discuss.py` (`discussions/`), `idd-comment` (`bridge.json`) | never committed | `rest-queue.py start` refuses to begin when git would not ignore this folder |
| `.claude/.idd/archive` | `scripts/idd-edit-helper.py` (`edits/`: earlier versions of corrected GitHub text) | never committed | Written in the main working tree of the repository (not in a linked worktree), at its top, whatever `--cwd` is. The writer adds its own ignore rule and refuses to write without it. The files hold other people's words and are not to be read |
| `.claude/.idd/tree-lock` | `scripts/idd-tree-lock.sh`, called by `idd-implement`; also `tree-lock.reclaim/` | never committed | The writer adds an ignore rule through `scripts/lib/runtime-ignore.sh`, anchored at the top of the repository: it does not cover a `--cwd` below the top |
| `.claude/worktrees` | `scripts/idd-worktree.sh`, called by `idd-implement` when the tree lock is held by another session | never committed | Written at the top of the main working tree whatever `--cwd` is. Ignored through `scripts/lib/runtime-ignore.sh` |
| `.claude/.idd/routing-stats.jsonl` | The `idd-route` program, called by `idd-verify` (every round) and `idd-close` | shared log | Written at the top of the working tree the shell is in (`git rev-parse --show-toplevel`), not below `--cwd`. Not determined: whether a round writes it before or after the last commit of the issue. The plugin does not say whether the file is tracked. Not written when `idd-route` is not installed |
| `.claude/.idd/issue-runs` | `idd-issue` in multi-finding mode (one `.jsonl` per run) | shared log | Written relative to the shell's current directory. Not determined: whether an unattended run commits it |
| `.claude/.idd/local.json` | `idd-issue`, `idd-verify` and `idd-config` when no configuration exists; `idd-all` after the user confirms a CI command; `scripts/migrate-idd-config.sh` | kept with the issue | A user's configuration. In a third-party clone its writer excludes it from git |
| `.claude/issue-driven-dev.local.json` | Earlier versions of the plugin; `scripts/migrate-idd-config.sh` moves it | kept with the issue | The legacy path of the configuration. Read as a fallback |
| `.claude/issue-driven-dev.local.md` | Earlier versions of the plugin | kept with the issue | A legacy configuration path. Read as a fallback |
| `.claude/local` | — | read only | Named only in a comment of `scripts/migrate-idd-config.sh` about a path it must not follow |
| `.claude/state` | — | read only | `.claude/state/idd-bridge.json`, the legacy place of the bridge bookmark; `idd-comment` reads it as a fallback |
| `.claude/rules` | — | read only | Rules of the target repository, read by `idd-diagnose` and `idd-issue` |
| `.claude/.idd/issue-pending` | — | not in the working tree | Named in `idd-issue` as a place that was considered and rejected; pasted images go to the system's temporary folder |
| `.claude/.idd/global.json` | `scripts/idd-repo-map.sh` | not in the working tree | In the user's home folder (`~/.claude/.idd/global.json`) |
| `.claude/issue-driven-dev.global.json` | — | not in the working tree | In the user's home folder; named in `idd-config` as a configuration that is not used |
| `.claude/image-cache` | Claude Code | not in the working tree | In the user's home folder; `idd-issue` copies pasted images out of it |
| `.claude/plugins` | Claude Code | not in the working tree | In the user's home folder; scripts look there for other plugins |

## Other things an issue leaves

| What | Writer | Class | Notes |
| --- | --- | --- | --- |
| Uncommitted edits of tracked files, new files of the implementation | `idd-implement`, the spec steps | kept with the issue | |
| `openspec/changes/<change>/` (the folder name comes from the repository's Spectra configuration) | The Spectra CLI, driven by `references/spec-wrapper.md` | kept with the issue | No step commits a proposal by name; the archive commit carries what is left |
| `.spectra/` | The Spectra CLI | kept with the issue | The plugin does not say whether it is ignored. Not determined: which Spectra commands write `touched/` and `archive-recovery/` |
| `<git dir>/spectra-app/` (parked changes, its database) | The Spectra CLI | not in the working tree | |
| `<git dir>/info/exclude` | `scripts/lib/runtime-ignore.sh`, `scripts/idd-edit-helper.py`, `scripts/git-ignore-block.sh` | not in the working tree | |
| `.gitignore` at the top | `idd-issue` (the carve-out for run logs, after the user chose it) | kept with the issue | |
| Files that an ignore rule of the issue's own branch covers | The issue's own commands (a build, a test run) | stashed | Ignored on the branch, untracked on the default branch. The report says how to bring them back, also when the branch held no commit and was deleted |
| A file that the issue's branch ignores and the default branch tracks | The issue's own commands, after a commit of the issue stopped tracking the file | stops | A plain checkout would overwrite it without a word; `settle` checks out with `--no-overwrite-ignore` and stops. The fast-forward of the default branch is done the same way |
| The branch `idd/<N>-<slug>` | `idd-all` Step 0.5, before diagnose, from `origin/<default>` | — | `settle` deletes it when it has no commit that `origin/<default>` lacks and no upstream; otherwise it is kept |
| The tags `idd-<N>-baseline` and `idd-<N>-verified` | `idd-issue`, `idd-verify` | not in the working tree | |

## What this inventory and its check cannot see

- Programs outside the plugin: the Spectra CLI, `idd-route`, and the hooks of the target repository. What they write is handled as `kept with the issue`; a commit hook that rejects the commit, and a hook that fails after a checkout, are handled by the requirement itself.
- A writer that builds its path from pieces, so that no skill or script holds the path as text.
- Locations outside `.claude/`. The table "Other things an issue leaves" is kept by hand.
