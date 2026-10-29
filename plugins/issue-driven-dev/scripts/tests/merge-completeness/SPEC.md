# Merge-completeness gate: specification (#399)

`check-merge-completeness.sh` answers one question for `idd-close` Step 1.55:

> For every commit on the issue branch that `git cherry` cannot match in the baseline,
> did its content land in the baseline?

The maintainer's decision A (#399, verify round 2) fixes the scope: what the baseline did
**after** the branch landed (a follow-up edit, a revert) is the baseline's own history and
is out of scope.

This file defines the right answer, lists the shapes it decides, and enumerates the places
where the helper is allowed to differ. `bounded.py` checks the helper against the definition
in a small world; `test.sh` pins the shapes below with fixtures.

## Definition

The definition assumes the history's story is known: which branch commits main received,
and when. The helper sees only the trees and has to infer the same answer.

- **B** is the merge-base, **H** the branch head, and c₁ … cₙ the branch commits in order.
- **S** is the set of branch commits main received when the branch landed, in one step:
  one squash, one merge, or one run of cherry-picks.
- **R** is main right after that step. If main never received any branch commit, R is
  main's tip.
- An **effect of c that the head still shows** is one of these two:
  1. a line or path that c added, and that H still has;
  2. a line or path that c removed, and that H still lacks.
- c is an **orphan** when c is not in S and at least one of its effects is not in R:
  the added line or path is missing from R, or the removed one is still in R.
- **P0.** If, on every path a candidate touched, main's tip has exactly what H has (the same
  file, or no file on either side), no candidate is an orphan: nothing is left to land,
  however main got there (a squash resolved to the branch's tree, a later commit of main's
  own). This is #399's own first test ("no orphan when the branch head's content is in the
  baseline") and it comes before the rule above, which would list a commit main never
  received even when the tip already holds everything it did (#399 verify round 12).
- The helper exits 3 when some candidate is an orphan, and lists exactly the orphans.
  It exits 0 when no candidate is an orphan. A commit that `git cherry` matches in the
  baseline is never a candidate, so it is never listed.

Lines are compared by their whole text, ignoring blank lines, over the files the commit
touched. "Has" and "lacks" count copies: when the same text appears twice, removing one
copy is an effect too.

## Decision table

| # | History | S | Expected | Fixtures |
|---|---------|---|----------|----------|
| 1 | Branch adds x = 1, then changes it to x = 2; main squashes the branch | all | 0: x = 1 is not an effect H still shows | 8 |
| 2 | Row 1, then main edits the same line again | all | 0: after landing, out of scope | 9, 13, 16 |
| 3 | Branch not rebased; main changed the same file meanwhile; squash | all | 0 | 10, 46 |
| 4 | Squash of the first k commits; the rest dropped | prefix | 3: the dropped commits with an effect H shows | 11, 29, 43, 53, 60 |
| 5 | Branch adds a debug line, then removes it; only the adding commit reached the squash | all but the removal | 3: the removal (fixture 19's mirror) | 79 |
| 6 | The same, and neither reached main | none of the two | 0 for both: neither has an effect H shows | 55b |
| 7 | Branch deletes a file or a line; nothing landed | ∅ | 3: the deleting commit | 55, 55b, 63, 67, 68, 72 |
| 8 | Branch deletes a line; main had added a copy elsewhere before the squash | all | 0: the copy is main's | 76, 77 |
| 9 | Branch creates and deletes a scratch file; main created its own file at that path (also when the name has a space or non-ASCII characters) | all | 0 | 78, 109, 110 |
| 10 | Branch moves a line, or deletes one of two equal lines it keeps | all | 0 | 64, 65 |
| 11 | Branch renames a file; squash / nothing landed | all / ∅ | 0 / 3 | 71, 71b |
| 12 | Branch adds an empty file; dropped | all but it | 3 | 80 |
| 13 | Branch removes a submodule; nothing landed | ∅ | 3 | 68 |
| 14 | Squash, then main reverts it | all | 0: out of scope | 13, 57 |
| 15 | Branch has no net change; one of its commits was cherry-picked, the one undoing it was not | the first | 3: the undoing commit | 51, 106 |
| 16 | Branch changes a value, then restores it; only the change reached the squash (also when the restored line appears elsewhere in the file) | all but the restore | 3: the restore | 19, 82 |
| 17 | Branch adds a line; main had removed its own copy elsewhere before the squash | all | 0: the copy count is main's plus the branch's | 81 |
| 18 | Squash resolved by hand; main removed a line of its own that the branch also adds (a shared `}`) | all | 0 | 65, 83 |
| 19 | Branch adds a second copy of a line, then deletes it; main removed its own copy before the squash of the earlier commits | all but the deletion | 3: the deletion | 84 |
| 20 | Squash kept the branch's line over main's own edit of it (resolved by hand); another commit dropped | all but it | 3: the dropped commit | 85 |
| 21 | Branch drops a line, adds another, then puts the first back; main had turned a line of its own into the same text; squash of the first two | all but the last | 3: the last commit (its copy is missing although the text is elsewhere) | 86 |
| 22 | Two commits landed as one squash; a later commit adds a second copy of their line plus a line of its own, and never landed | the first two | 3: the later commit only | 87 |
| 23 | A commit adds a line the branch later drops again; main had the same text and the landing commit dropped it too | all | 0 | 88 |
| 24 | Squash edited by hand: the branch moves a line, and the squash also turns one of main's lines into the same text | all | 0: the moved line is in place in the landing commit | 89 |
| 25 | Release merge: the squash lands on a side branch next to another PR that adds the same text as a line the branch dropped; main merges the side branch | all | 0 | 90 |
| 26 | Branch has no net change; its first commits were squashed, the commits that undid them were not | the first ones | 3: the undoing commits | 91, 92 |
| 27 | Row 16, while another PR inserts a line right next to the restored one (before landing, or in the squash itself) | all but the restore | 3: the restore | 94, 95 |
| 28 | A commit with two effects, one of which a squash edited by hand left out | — (the squash is not a set of commits) | 3: that commit | 96 |
| 29 | Main changed the branch's line first; the squash was resolved by hand to the branch's side (its tree is the head's); a follow-up edited the branch's line | all | 0 | 97 |
| 30 | Row 26 through a release merge whose side branch also edits the next line | the first ones | 3: the undoing commit | 98 |
| 31 | Squash, then a later PR moves the change's files into an archive directory and edits one | all | 0: after landing, out of scope | 99 |
| 32 | Dropped commits that only remove a blank line or change a file mode | all but them | 0: neither is an effect | 100 |
| 33 | Branch's whole net change is a line and an empty file it adds (or deletes); another PR put the same line in main first; the squash carries a file of its own | all | 0: the other PR's commit has the wrong files, so the branch landed at the squash | 102, 102b |
| 34 | The squash leaves out a final newline or a blank line the branch added, or keeps a blank line it deleted; main later edits another of the branch's lines | all but those | 0: none of them is an effect, so the squash holds the net change and main's edit came after landing | 103, 104, 108 |
| 35 | A commit renames a file and edits it; squash; a follow-up edits the file | all | 0 | 105 |
| 36 | Row 1, but nothing landed | ∅ | 3: only the commit that wrote x = 2 | 107 |
| 37 | Rows 2 and 16 under the user's diff settings: `diff.interHunkContext`, `GIT_DIFF_OPTS`, no prefixes, no rename detection, raw names, color, another algorithm, a submodule log format | all / all but the restore | the same answers: 0 / 3 | 112, 113, 128 |
| 38 | Row 2 with a git that has no `--no-relative` (before 2.28) | all | 0 | 114 |
| 39 | A last line without a final newline, re-added with it after lines another PR appended, or written without it by the squash | all | 0 | 115, 115b |
| 40 | Row 9 with a name holding a space and a character git quotes | all | 0 | 116 |
| 41 | A commit deletes a line and adds an empty file x; main adds files under a directory x/, one of them named so that it decodes to a newline and a forged record | all but that commit | 3: that commit | 117 |
| 42 | A commit with more paths than go on one command line | all | 0 | 119 |
| 43 | A file moved, or renamed and edited, while main edited it before the squash | all | 0 | 120, 121 |
| 44 | Row 43, but the rename never landed | the other commit | 3: the rename | 122 |
| 45 | The tip has the head's content on every path the branch touched: the squash was resolved to the branch's tree after another PR set the same line, or main set the head's value later | all | 0 (P0) | 123 |
| 46 | A copied function or a duplicated block; main edited the original before the squash, and git put the edit on the branch's copy | all | 0 (R1) | 124, 125 |
| 47 | A branch with no net change whose landed prefix is older than the newest 20 earlier commits | the first two | 3: the last commit, at the tip | 127 |
| 48 | The branch adds an empty file x and a line; another PR adds the line and a directory x/; no squash | ∅ | 3: a directory is not the file | 130 |
| 49 | A restore of a line that is in the file twice, left out of the squash (its change and the change it undid cancel out in the net change) | all but the restore | 3: the restore (R1 confirms it) | 131 |
| 50 | Rows 49 and 19 when a later commit, after the landed part, added or deleted another copy of the same text | the landed part | 3: the commit in the landed part (copies are counted against what landed, not the head) | 132, 133 |

## The small world (`bounded.py`)

- **Units.** f.txt has three slots, each one line from {A, B, C} or empty, separated by fixed
  lines. g.txt (one line) and e.txt (empty) each exist or not. The same text in two slots is
  "the same line elsewhere in the file". The helper sees only text, so it has to tell these
  collisions apart.
- `--adjacent` puts the slots on consecutive lines, so edits of two slots touch; `--distinct`
  gives each slot its own texts (A0, A1, …). Together they test adjacency alone. Adjacent
  slots holding the same text are left out of the results: then even the positions are
  ambiguous in the text (main's C in slot 1 and the branch's C in slot 0 can be the same line
  of the file), and no check that reads text can tell which is which.
- `--pairs` lets a commit edit two units at once (a commit with several effects).
- `--touch` lets main's own edits, before landing and in the landing step, edit units the
  branch edits too; a squash that conflicts with them is resolved by hand, taking the branch
  side.
- **Merge-base.** Two states: slots (A, –, B) without g.txt and e.txt, and the same with both.
- **Branch.** Every sequence of 1 to N single-unit edits.
- **Main.** An unrelated commit. Optionally one edit of its own to a unit the branch does not
  touch; its text can collide with the branch's. Then, unless S is empty, one squash of S, for
  every subset S of the branch whose commits apply in order from the merge-base: the units S
  changes take S's value, the rest keep main's.
- `--landing own` makes that squash also carry one edit of main's own (a squash edited by
  hand), to a unit neither the branch nor main's earlier edit touched. `--landing merge` puts
  the squash on a side branch, optionally followed there by another PR's edit of such a unit,
  while main gets one more unrelated commit; main then merges the side branch (a release merge,
  or a `git pull` merge). In both modes S is never empty.
- `--after` adds one more main edit after the squash, to a unit the branch touched. This is
  out of scope by decision A.
- **What the world cannot build.** The slots are separated by distinct lines, so in this world
  a position always says which line it is. Where it does not — the same lines repeated, so
  that git may pair the copies one way when it builds the landing commit and another way in
  the helper's diffs, and renames — the fixtures (103–125) and fuzz runs on real
  `git merge --squash` histories cover it (Results). The world has one file with lines and no
  merge commits on the branch.

Every case is run with the real helper on a real repository. In every case, not only when
the answers differ, the helper's route must match the model: it stops at P0 exactly when the
model says so, and otherwise checks each commit where the model of the landing step does.
Exit 0 means every disagreement belongs to a class below.

## Known deviations (only these)

`bounded.py` decides each class from the model, never from the helper's own answer. Where
each commit is checked (the landing commit or the tip) comes from a model of the landing step
written from the helper's header; the helper also writes where it checked each commit to a
trace file (only when the test sets `CHECK_MERGE_COMPLETENESS_TRACE`), and a trace that differs
from the model is a bug in the landing step, whatever the list says. Round 10 took the sides
from the trace itself, so a helper with the landing step switched off still came out with
nothing unexplained.

- **D1, tip fallback.** Some commits have no landing commit to be checked at, and are
  checked at the tip: nothing of a branch with a net change landed (S = ∅); the landed
  commits are not a prefix of the branch; a squash resolved by hand left one of the branch's
  own lines out of place, so no commit holds its net change; or a branch with no net change
  reached main through cherry-picks. At the tip main's own edits, before or after landing,
  are part of the target. The helper cannot tell "nothing landed" from "landed, then main
  changed it" there, so only presence is compared (D2), and the deviation is documented
  instead of fixed.
- **D2, presence at the tip.** At the tip only presence is compared: a commit is listed when
  a line or path it adds is in the head and not in the tip, or one it deletes is not in the
  head and is in the tip. A text that is elsewhere in the tip or the head can therefore hide
  a commit or list one.
- **D3, its place, not its value.** At the landing commit each effect is checked in its own
  place. The check sees where a change is, not which commit made it: a commit that landed and
  was undone by a later commit that landed too, then changed again by a commit that did not
  land, is listed along with that last commit; so is a commit that did not land and added a
  line that a later commit, which did not land either, rewrote. Only over-listing, and only
  with the right verdict (exit 3), since the later commit that did not land is listed too.
- **D4, main's own edit of the commit's line.** When main itself edited a line a branch
  commit edited, before landing or in the landing step, the landing commit can hold the value
  from before that commit, or a third value, although the commit landed: the commit is
  listed, and the verdict can be wrong (exit 3 instead of 0). Example: the branch sets a
  version to 1.1 and back to 1.0, main releases 1.1 itself and then squashes the branch. The
  trees are exactly those of a history in which the commit was dropped, so no check that reads
  trees can tell; cherry-picking the listed commit would undo main's edit. For a line whose
  text repeats in the file, the copy count (R1) can read the same history as landed instead.
- **R1, repeated lines.** A position identifies a line only while its text is unique in the
  file. When a line found missing at the landing commit has a text that occurs more than once
  (at the commit or its parent, the head or the landing commit), the helper keeps the finding
  only when the copies agree: the landing commit, less the copies main added or removed before
  it, has fewer copies of an added line than what landed there (the landed prefix, or the
  head), or more of a deleted one. This removes
  the false findings of a clean squash whose main edit git put on the branch's copy (#399
  verify round 12). The count only ever removes a finding, never adds one, and it cannot see an
  edit main made in the landing step itself (a squash edited by hand, another PR in a release
  merge): when such an edit changes another copy of the same text, a copy that never landed, or
  a deletion that did not, reads as landed. `bounded.py` finds these in `--landing own` and
  `--landing merge` and decides them from the model: the commit is checked at the landing
  commit and missed, the model finds its effect missing there, the text occurs at least twice,
  and the helper's count computed on the model's states reads it as landed. Separately, where
  the copies sit next to each other, or another PR inserts an identical line next to one, the
  positions themselves can read a missing copy as in place, and a branch can look landed where
  only part of it did; the small world does not build that, and the fuzz runs in Results count
  it. Either way the verdict can be wrong (exit 0).
- **B1, a listed blind spot.** A commit that set its line back to the merge-base value in a
  branch with no net change, when no prefix of the branch landed later: the branch "lands" at
  the merge-base, where the line has that value, so the commit is not listed. This covers a
  branch of which nothing landed while main changed the line itself (fixture 34b pins that
  answer: by decision A the branch landed, trivially, and main's edit came after), and a
  branch whose earlier commits reached main in a form no earlier state of it matches (a
  squash of them edited by hand). Its verdict is wrong (exit 0). 3.5.0, which compared the
  tip, listed some of these.
- **B2, main's own commit holds the net change.** When main made a commit of its own —
  before it received S, or after — that holds the branch's net change (it made the same
  edit, or replaced a line the branch deleted), and no earlier commit holds it, that commit
  is where the branch landed, and what it holds counts as landed. A deletion counts as
  landed wherever the line is no longer in place, replaced or not: requiring a pure
  deletion would read an insertion next to it as a replacement and bring back round 11's
  adjacency misses. The helper's header lists this as a blind spot. Its verdict is wrong
  (exit 0); the commit it misses had nothing left to do (the line is gone from main).

A disagreement is known when every commit the two answers differ on falls in one of these,
each decided from the model: checked at the tip, and the tip rule (D2) computed on the
model's head and tip gives the helper's answer (D1+D2); checked at the landing commit and
listed with the right verdict (D3); listed with the wrong verdict while main's own edit, before
landing or in the landing step, touched a unit the commit edits (D4); checked at the landing
commit and missed, when the model's landing commit is one main made itself, not the one that
brought S in (B2),
or when B1 holds in the model, including that no prefix lands after the merge-base. At the
landing commit the model also decides the helper's answer: for a one-unit edit, an added value
is missing when the head holds it and the landing commit does not, and a removed value is
missing when the head no longer holds it and the landing commit still does. A commit checked
there whose listing differs from that is a bug, and so is a landing commit the trace reports
differently from the model. R1 is not built by the small world, so a disagreement only R1
would explain counts as unexplained there.

## Results

Runs of 2026-10-28 and 2026-10-29 against the round-13 helper, with `python3 bounded.py
--max-len N [--sample K --seed S] [mode]`. The table's runs used blob `05b66eb` (the default
runs and `--landing own` length 2 a copy before its last comment edit). The final helper,
blob `66dab7f`, checks a landing commit's files with one `diff-tree` instead of one lookup per
path; the default length-2 run, `--landing own` length 3 and `--touch --landing own` were run
again on it (blob `62a48f8`; the final blob differs only in comments) and gave exactly the
same counts. "Known" lists
the cases by class ("tip" is D1+D2 alone); "Wrong verdict" counts the known cases whose exit
code differs from the definition's; "Landing" counts cases in which at least one commit was
checked at a landing commit (a run that never gets there says nothing about the landing step;
round 13's P0 settles many cases before it, so these counts are lower than round 12's).

| Mode | Length | Cases | Agree | Known | Wrong verdict | Landing | Unexplained |
|------|--------|-------|-------|-------|---------------|---------|-------------|
| default | ≤ 2 | 7,058 (all) | 5,938 | tip 1,120 | 716 (3 → 0) | 1,260 | 0 |
| default | ≤ 3 | 6,000 of 109,788, seed 399 | 4,392 | tip 1,602, D3 3, tip+D3 3 | 542 (3 → 0) | 1,972 | 0 |
| default | ≤ 3 | 6,000 of 109,788, seed 4242 | 4,365 | tip 1,631, D3 3, tip+D3 1 | 569 (3 → 0) | 1,888 | 0 |
| `--landing own` | ≤ 2 | 22,440 (all) | 19,588 | tip 2,780, R1 72 | 2,228 (3 → 0) | 15,772 | 0 |
| `--landing own` | ≤ 3 | 3,000 of 300,448, seed 399 | 2,278 | tip 690, R1 18, D3 6, tip+D3 4, tip+R1 4 | 252 (3 → 0) | 1,961 | 0 |
| `--landing merge` | ≤ 2 | 27,498 (all) | 24,662 | tip 2,764, R1 72 | 2,836 (3 → 0) | 8,372 | 0 |
| `--landing merge` | ≤ 3 | 3,000 of 392,358, seed 399 | 2,282 | tip 696, R1 14, D3 5, tip+D3 3 | 244 (3 → 0) | 1,295 | 0 |
| `--after` | ≤ 2 | 3,000 of 22,350, seed 399 | 2,454 | tip 428, B2 118 | 517 (3 → 0), 29 (0 → 3) | 1,171 | 0 |
| `--adjacent --distinct` | ≤ 2 | 3,000 of 7,058, seed 12 | 3,000 | — | — | 875 | 0 |
| `--adjacent --distinct --landing own` | ≤ 2 | 3,000 of 22,440, seed 12 | 3,000 | — | — | 2,098 | 0 |
| `--adjacent --distinct --landing merge` | ≤ 2 | 3,000 of 27,498, seed 12 | 3,000 | — | — | 1,404 | 0 |
| `--touch` | ≤ 2 | 3,000 of 11,448, seed 12 | 2,475 | tip 506, B2 14, B1 5 | 369 (3 → 0), 7 (0 → 3) | 508 | 0 |
| `--touch --landing own` | ≤ 2 | 3,000 of 71,070, seed 12 | 2,128 | tip 847, B2 14, B1 4, D4 5, R1 2 | 319 (3 → 0), 296 (0 → 3) | 1,533 | 0 |
| `--touch --landing merge` | ≤ 2 | 3,000 of 79,350, seed 12 | 2,379 | tip 600, B2 16, D4 2, R1 3 | 375 (3 → 0), 232 (0 → 3) | 832 | 0 |
| `--pairs` | ≤ 2 | 3,000 of 103,986, seed 12 | 2,589 | tip 411 | 167 (3 → 0) | 523 | 0 |

In `--landing own` length 2 one case first exited 4: under a load of over 100 the system
killed one of the helper's `git diff` processes. Run again on its own it agrees, and it is
counted under Agree. The first `--landing own` length-3 run overlapped an edit of the helper
(bash reads a script while it runs it) and was run again; the table shows the second run.

Most wrong verdicts are at the tip (D1+D2): presence cannot tell main's own copy of a line from
the branch's, and three slots holding three texts make such copies common. At the landing
commit the wrong verdicts are the inherent classes D4, B1 and B2, where main edits the
branch's own units (`--touch`) or edits after landing (`--after`), and R1, where main's own
edit in the landing step itself changes another copy of a text. With adjacent slots and
distinct texts every answer agrees with the definition.

The world above separates its slots with distinct lines. Repeated lines, where git can pair
the copies one way when it builds the squash and another way in the helper's diffs, are run
on real histories by `fuzz13.py` (kept with the #399 work, not in the repository; the
devil's-advocate reviewer of round 12 wrote the first version): a base of 3–7 lines drawn from
five repetition-prone code lines, a branch of 2–3 commits that only insert lines, one edit of
main's own, then `git merge --squash` of the whole branch (full: nothing may be listed) or of
its first commits (prefix: every later commit is an orphan). Cases whose squash conflicts are
skipped.

| Run | Cases | Round 13 | Round 12 | 3.5.0 | Round 11 |
|-----|-------|----------|----------|-------|----------|
| full, seed 1 | 154 | 154 exact, 0 false | 152 exact, 2 false | 154 exact | 154 exact |
| full, seed 3 | 157 | 157 exact, 0 false | 156 exact, 1 false | 157 exact | 157 exact |
| prefix, seed 2 | 200 | 127 exact, 78 missed | 127, 78 missed | 0, 272 missed | 122, 83 missed |
| prefix, seed 4 | 194 | 127 exact, 70 missed | 127, 70 missed | 0, 240 missed | 124, 73 missed |

Of round 13's 148 misses, 3 are at the landing commit (R1's adjacent copies) and the rest at
the tip (D1+D2: the inserted lines are elsewhere in the file). None of the four lists a commit
that landed in the prefix runs.

How the numbers got here:

- **Round 9, length ≤ 2.** The first run left 32 cases unexplained: nothing had landed, main
  had made an edit of its own, and that edit shared text with the branch. That is the tip
  fallback (D1), whose definition then covered only `--old-git` and `--after`. D1 was widened
  to every commit checked at the tip; the helper did not change.
- **Round 9, length ≤ 3 (seed 399).** 19 exit-code misses (3 → 0): the landing commit was
  compared with the head's count of a line and with main's state just before it plus the
  branch's net change. Fixtures 84 and 86 are two of them.
- **Round 10.** The landing commit was compared with the clean merge of the landed part onto
  main just before it. Both length-3 samples: 0 unexplained, with 93 and 119 cases of
  over-listing (D3) and 16 and 13 misses of B1.
- **Round 10 verify.** The world could not build a landing step that carries main's own edits,
  and the classifier took where each commit was checked from the helper's own trace. Round 11
  added `--landing own` and `--landing merge` and decided the sides from a model.
- **Round 11.** Each commit was undone on the landing commit with `merge-tree --merge-base`.
  Its runs showed 0 unexplained, but the world had no adjacent edits; round 11's verify found
  that a three-way merge conflicts on adjacent lines and that the conflict was read as
  "landed". Against the round-11 helper, `--adjacent --distinct` leaves 18 (plain) and 35
  (merge) of 1,500 cases unexplained; the landing step itself (`holds`, also a merge-tree)
  failed the same way.
- **Round 12.** No merge anywhere: landing and the check at the landing commit compare by
  two-way diffs, position by position. Its runs: 0 unexplained in every mode.
- **Round 12 verify.** A position is not a line's identity: the user's diff settings
  (`diff.interHunkContext`, `GIT_DIFF_OPTS`) shift every position; with repeated lines the
  squash's merge and the helper's diffs pair the copies differently (the fuzz above lists 3 of
  311 clean squashes; round 12's verify found the class); a moved file reads as all new lines.
  The helper also listed commits when the tip had the head's tree, which the issue's Expected
  rules out. The world could build none of these.
- **Round 13.** P0, pinned diffs with rename detection, and R1. bounded.py now checks every
  case's route (P0, where each commit is checked), not only the cases whose answers differ.
  The first R1 rule counted copies against the head; the length-3 sample found two cases where
  a later commit that never landed cancelled a dropped deletion, and it now counts against what
  landed (fixtures 132 and 133). The first `--landing own` run then showed 73 unexplained
  cases: 72 were R1 missing a copy because main's edit inside the landing step changed another
  copy, now a class decided from the model, and 1 was the killed process.
- `--after` needs length 2: a single-commit squash is matched by `git cherry`, so no length-1
  case reaches the landing step. Round 13 ran no `--old-git` mode: the helper has not called
  merge-tree since round 12, and the suite runs once under the shim.
- Not covered by the world: branches longer than 3 (and length 3 only by sampling), more than
  one file with lines, merge commits on the branch, renames and repeated blocks (fixtures
  103–133 and the fuzz runs above), and the 200-check and 20-commit limits (fixtures 12, 60 and
  127). Adjacent slots holding the same text are not in the results: there even the positions
  are ambiguous in the text, and no check that reads text can tell which slot a line belongs
  to. The model tracks each line by its slot; the helper sees text and positions, so equal
  texts at the tip are where most disagreements come from.
