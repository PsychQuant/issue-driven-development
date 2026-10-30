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
  main's tip. When the branch reached main in several steps (an earlier PR of the branch,
  then the PR that completes it), it landed at the first of them after which main holds the
  head's net change: S is what main received up to that step, R is main right after it, and a
  later step is main's history after landing (decision A).
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
| 37 | Rows 2 and 16 under the user's diff settings: `diff.interHunkContext`, `GIT_DIFF_OPTS`, no prefixes, no rename detection, raw names, color, another algorithm | all / all but the restore | the same answers: 0 / 3 | 112, 113, 128 |
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
| 51 | A file whose name the tree stores in NFD, on a git that precomposes paths (`core.precomposeUnicode`, macOS's default): a partial squash, or a commit left out | all but the last / all but it | 3: that commit | 134, 134b |
| 52 | A submodule pointer set again after the landed prefix, never landed | the prefix | 3: that commit (not exit 4) | 135 |
| 53 | A deletion that never landed, in a file the same commit renamed (also in a moved file with repeated text) | all but it | 3: that commit (not exit 4) | 136, 138 |
| 54 | The branch landed in two squashes (or a cherry-pick, then a squash, also of a later commit first); a restore of a repeated line never landed, also when main's own edit and the first squash's copy cancel out | the landed commits | 3: the restore | 137, 137b, 147, 149 |
| 55 | More than 64 KB of paths: main moved a file the wide commit touched; a squash, then main's edit; a wide commit that never landed | all / all / ∅ | 0 / 0 / 3 | 139, 140, 141 |
| 56 | One of two equal adjacent lines deleted next to a line main edited; clean squash; follow-up (also when the branch moved the file), when no other commit of the branch touches that text | all | 0 | 142, 146, 163 |
| 56b | Row 56 when another commit of the branch adds or deletes a copy of the same text, or the branch landed in several steps (Rebase and merge, a squash into another branch that is then merged) | all | 0 in the definition; the helper finds no landing commit and checks at the tip (D1+D2), where the follow-up lists the commit | — (fuzz runs in Results) |
| 57 | Row 56 with a restore elsewhere that never landed | all but the restore | 3: the restore only | 142b |
| 58 | A copy one commit added and the next took away, another copy added; two squashes | all | 0 | 148 |
| 58b | Only a prefix could have landed, and a later commit brings a copy of its line in the same squash | the later commits | 3 in the definition; the helper checks the prefix at the tip (D1+D2), where the copy hides it | 150 (pins the route) |
| 58c | A commit moves a line of repeated text (the copies stay as many) and was dropped; another commit adds a copy and landed | the other commit | 3 in the definition; the helper checks the move at the tip (D1+D2), where the copies hide it | 155 (pins the route) |
| 58d | A release merge brings the squash and another PR that adds a copy of a line a dropped commit also added | the other commit | 3 in the definition; the helper checks the dropped commit at the tip (D1+D2), where the other copy hides it | 156 (pins the route) |
| 58e | The branch adds a copy of a line and never landed; main's own commit adds the same text elsewhere | ∅ | 3 in the definition; the helper checks the commit at the tip (D1+D2), where main's copy hides it | 157 (pins the route) |
| 59 | A moved file, main's edit before the squash, checked at the tip | all | 0 | 143 |
| 60 | Row 2 under a `diff.orderFile` that does not exist, and under `diff.submodule=log` with a submodule bump | all | 0 | 144, 145 |
| 61 | A commit dropped from a squash while another commit moved a file main had edited; everything checked at the tip | all but the dropped one | 3: the dropped commit only, not the move | 151 |
| 62 | A file turned into a submodule, or back, checked where the branch landed (undone by a later landed commit, redone by one that never landed) | all but the last | 3 (D3: listed with the last), not exit 4 | 152, 152b |
| 63 | Row 54 when the part in L^1 is neither a prefix of the branch nor a patch `git cherry` finds (two of its commits squashed together, before the first commit) | the landed commits | 3: the restore | 153 |
| 64 | Row 46 after the branch first moved the file: main's edit of a copy is in the file under its old name | all | 0 (R1, the copies read under each revision's name) | 154 |
| 65 | A commit adds a line, and a later commit moves its file (with or without an edit); main gets only the move, by a pick or a squash edited by hand | the move | 3: the first commit, its line looked for under the file's name in the head | 158, 158b, 159 |
| 66 | Row 46 with the function copied twice; or a unique line next to the copies, which the diffs pair with another function's | all | 0 (R1, unique lines counted too) | 160, 161 |
| 67 | Row 46 or 56 after a commit of the branch (another file) was picked to main early, or after an earlier PR of the branch's unrelated commits | all | 0: a part of the branch in L^1 that changes no copy of the text does not stop R1 | 162, 163 |
| 68 | Row 54 when the first PR is older than the 20 earlier commits searched for a part in L^1 | the landed commits | 3: the restore (the first PR's commit is in place in L^1) | 164 |
| 69 | A squash edited by hand dropped a commit adding a copy, or moving one; later main's own commit adds the same text | the other commits | 3 in the definition; the landing is the squash of what landed, not main's commit, and the dropped commit is checked at the tip (D1+D2), where the copies hide it | 165, 166 (pin the route) |
| 69b | A unique line restored by a commit that never landed, after the commit that moved it landed | all but the restore | 3: the restore (a move is judged by position) | 169 |
| 69c | A file whose name has a backslash; main's own commit already had the branch's line in another file; squash; follow-up | all | 0 | 170 |
| 70 | More than 64 KB of paths: a path `update-index` refuses (an NTFS form of `.git`), changed only on the branch; a repository whose path has `:`, with `core.splitIndex` on | ∅ there / all | 3 / 0, and nothing written into the repository's `.git` | 167, 168 |
| 71 | A restore of a unique line never landed; main had replaced that line itself before the branch landed | the first commit | 3: the restore (the line is not in the landing commit; main's replacement does not count as main removing the branch's copy) | 171 |
| 72 | A commit dropped after picks of the commits around it, the first pick replacing the line the branch's net change deletes | the picks | 3: the dropped commit | 172 |
| 73 | Row 71 for a deletion: a commit deleting a unique line never landed, and main had put the same line in the same place itself | all but it | 3: that commit (the line is still in the landing commit) | 173 |

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
- `--landing two` lands S in two squashes: a nonempty part S1 of S, then the rest on top of it
  (a squash of S1's state to S's). If the first squash already holds the head's net change,
  the branch landed there: S is S1 and R is main after it; else R is main after the second
  (Definition). Single-commit squashes are matched
  by `git cherry`, so this mode needs branches of length 3.
- `--after` adds one more main edit after the squash, to a unit the branch touched. This is
  out of scope by decision A.
- **What the world cannot build.** The slots are separated by distinct lines, so in this world
  a position always says which line it is. Where it does not — the same lines repeated, so
  that git may pair the copies one way when it builds the landing commit and another way in
  the helper's diffs, and renames — the fixtures (103–157) and fuzz runs on real
  `git merge --squash` histories cover it (Results). The world has one file with lines and no
  merge commits on the branch. It does have repeated texts across slots (three slots, three
  texts), which is where the copy rule and R1 act.

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
  checked at the tip: nothing of a branch with a net change landed (S = ∅, or commits that
  cancel each other out, so no tree shows that they landed); the landed
  commits are not a prefix of the branch; a squash resolved by hand left one of the branch's
  own lines out of place, so no commit holds its net change; main moved or renamed a file
  the branch edited before the branch landed, so no commit has the branch's paths (3.5.0 listed
  these too); a commit that fails by position only on a repeated text that more than one
  commit of the branch touches, or that the net change only moves, is not counted as holding
  it (round 14's verify: one commit deletes one of two equal lines, another adds one); a
  landing in several steps (Rebase and merge, a squash into another branch that is then
  merged) whose last step fails on repeated text, since only that step's copies are counted
  and never at a merge commit; or a branch with no net change: it lands at the merge-base,
  and when a prefix of it landed later (a squash of its first commits, or a commit of main's
  own that holds the prefix's net change, B2), the commits after that prefix are checked at
  the tip, as they are when some of its commits reached main through cherry-picks. `bounded.py` requires one of these causes, read from how the case was built,
  for every disagreement at the tip (round 15; before it, the class followed the routing model,
  which follows the helper's own landing rules). At the tip main's own edits, before or after landing,
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
- **R1, the copies.** A position identifies a line only while the lines around it say which one
  it is. When a line's text occurs more than once, git may pair the copies one way when it
  builds the landing commit and another way in the helper's diffs; next to a block of repeated
  lines it can pair even a unique line with another (round 14's verify: a function copied
  twice). So every finding at the landing commit stands only when the copies agree too: the
  landing commit, less the copies main added or removed before it, has fewer copies of an
  added line than what landed there (the landed prefix, or the head), or more of a deleted
  one. A unique line has one copy, so main's edit cannot have been put on the branch's copy of
  it: it must also be in the landing commit as often as in what landed, before main's own
  copies are counted (otherwise main's own replacement of the line before landing let a
  restore of it that never landed read as landed, found by `--landing two --touch` in round
  15); and a unique line the commit moved (its step leaves the number of copies alone) is
  judged by its position alone. Copies are counted only in a file the commit edited, each
  revision's file under the name it has there, never for a submodule pointer. What L^1 gained
  or lost since the merge-base is main's, unless another commit of the branch that changes the
  copies has its own change all in place in L^1: the finding then stands. That covers every way
  a part of the branch reaches main before the landing commit: a squash of its first commits
  (round 13 read its copy as main's and cleared the commit that undid it), a pick, later
  commits squashed before an earlier one, a squash older than any search would try. Round 14
  kept the finding whenever another commit changed the copies, or any earlier part of the
  branch was in L^1, whatever file it touched: a function copied twice, a hotfix picked early,
  or an earlier PR of the branch then listed a clean squash. Round 15 first subtracted the
  copies of the newest earlier prefix L^1 holds; `--landing two` showed L^1 can hold a prefix
  only because a deletion counts as landed once its line is replaced, so the prefix's state is
  not what L^1 has, and a dropped commit was missed. The same count
  decides a landing commit that positions alone reject: a commit that fails only on lines
  whose text repeats holds the net change when its own step changes the copies of each such
  text as the net change does, for a text at most one commit of the whole branch touches
  (adds or deletes a line of it: a move leaves the count alone) and whose copies the net
  change changes (a move has no count to compare: round 14 took a squash that dropped one
  for the landing commit), when some other line of the net change is in place in that commit
  that its own step brought (a commit of main's own that adds the same text elsewhere carries
  none of the branch's change, even when an earlier squash put the branch's other lines in
  place), and never at a merge commit (its step brings the other commits of the side
  it merges; with the count there, `--landing merge` gave 8 more wrong verdicts than round 13
  over all 27,498 cases).
  This removes the false findings of a clean squash whose main edit git put on the branch's
  copy (#399 verify round 12) and the missed landing of a squash that deletes one of two equal
  lines (round 13). The count only ever removes a finding, never adds one, and it cannot see an
  edit main made in the landing step itself (a squash edited by hand, another PR in a release
  merge): when such an edit puts the same text elsewhere, a line that never landed, or a
  deletion that did not, reads as landed, at the landing commit or in choosing it; and a part of
  the branch that reached L^1 in a form that leaves a line of its commits out of place reads as
  main's.
  `bounded.py` finds these in `--landing own`, `--landing merge` and `--landing two` and decides
  them from the model, not from the helper's count alone: the commit is checked at the landing
  commit and missed, the model finds its effect missing there (a unique line not one the
  commit moved), the helper's count computed on the model's states reads it as landed, and in
  the model's
  landing step main itself changed another copy of that text: an edit of its own in that
  commit, another PR in the merge, a conflict resolved over an edit of main's own, or every
  change when the landing commit is main's own (B2). The branch's own changes in the step
  never count, whether or not they are part of what landed. Without that cause the case is
  unexplained (round 13's class used the count alone, which could never expose a wrong
  count; round 14's first version compared the step with the head, which let the branch's
  dropped commits pass as main's edits).
  Separately, where
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
differently from the model. The model of the landing step includes the copy rule and the
check for an earlier part of the branch in L^1, as the helper's header states them.

## Results

Runs of 2026-10-30 against the round-15 helper (blob `f8b4759`, the one committed)
and `bounded.py`, with `python3 bounded.py --max-len N [--sample K --seed S] [mode]`. The machine
carried other work at a load of 20 to 190 through the morning, so apart from `plain` length 2
(every case) the samples are smaller than round 14's (600 to 1,000 cases a mode, against 3,000
to 6,000). "Known" lists the cases by class ("tip" is D1+D2 alone); "Wrong verdict" counts the
known cases whose exit code differs from the definition's; "Landing" counts cases in which at
least one commit was checked at a landing commit.

| Mode | Length | Cases | Agree | Known | Wrong verdict | Landing | Unexplained |
|------|--------|-------|-------|-------|---------------|---------|-------------|
| default | ≤ 2 | 7,058 (all) | 5,938 | tip 1,120 | 716 (3 → 0) | 1,260 | 0 |
| default | ≤ 3 | 1,000 of 109,788, seed 399 | 723 | tip 277 | 105 (3 → 0) | 293 | 0 |
| default | ≤ 3 | 1,000 of 109,788, seed 4242 | 740 | tip 259, tip+D3 1 | 97 (3 → 0) | 302 | 0 |
| `--landing own` | ≤ 2 | 800 of 22,440, seed 399 | 692 | tip 100, R1 8 | 84 (3 → 0) | 553 | 0 |
| `--landing own` | ≤ 3 | 600 of 300,448, seed 399 | 459 | tip 133, R1 7, tip+D3 1 | 42 (3 → 0) | 393 | 0 |
| `--landing merge` | ≤ 2 | 800 of 27,498, seed 399 | 723 | tip 71, R1 6 | 77 (3 → 0) | 250 | 0 |
| `--landing merge` | ≤ 3 | 600 of 392,358, seed 399 | 454 | tip 141, R1 4, tip+D3 1 | 50 (3 → 0) | 248 | 0 |
| `--landing two` | ≤ 3 | 600, seed 399 | 552 | tip 48 | 48 (3 → 0) | 200 | 0 |
| `--landing two` | ≤ 3 | 600, seed 4242 | 565 | tip 35 | 35 (3 → 0) | 210 | 0 |
| `--landing two --touch` | ≤ 3 | 600, seed 12 | 548 | tip 44, B2 5, D4 3 | 46 (3 → 0), 4 (0 → 3) | 163 | 0 |
| `--after` | ≤ 2 | 600 of 22,350, seed 399 | 480 | tip 91, B2 29 | 117 (3 → 0), 3 (0 → 3) | 229 | 0 |
| `--adjacent --distinct` | ≤ 2 | 600 of 7,058, seed 12 | 600 | — | — | 155 | 0 |
| `--adjacent --distinct --landing own` | ≤ 2 | 600 of 22,440, seed 12 | 600 | — | — | 424 | 0 |
| `--adjacent --distinct --landing merge` | ≤ 2 | 600 of 27,498, seed 12 | 600 | — | — | 283 | 0 |
| `--touch` | ≤ 2 | 600 of 11,448, seed 12 | 498 | tip 100, B2 2 | 77 (3 → 0), 1 (0 → 3) | 103 | 0 |
| `--touch --landing own` | ≤ 2 | 600 of 71,070, seed 12 | 428 | tip 165, R1 3, B1 2, B2 1, D4 1 | 70 (3 → 0), 52 (0 → 3) | 310 | 0 |
| `--touch --landing merge` | ≤ 2 | 600 of 79,350, seed 12 | 492 | tip 103, B2 5 | 71 (3 → 0), 36 (0 → 3) | 178 | 0 |
| `--pairs` | ≤ 2 | 800 of 103,986, seed 12 | 681 | tip 119 | 47 (3 → 0) | 155 | 0 |

`plain` length 2 gives exactly round 13's and round 14's answers on all 7,058 cases (5,938 agree,
716 wrong verdicts at the tip, all 3 → 0). In every mode the tip class now also needs a cause D1
names, read from how the case was built; the first runs found three causes the class had
taken for granted (a branch with no net change whose prefix main's own commit holds, B2; commits
in S that cancel out; and the routes the copy rule refuses), which SPEC D1 now names, and
`--landing two --touch` found that counting a unique line after main's own copies are taken out
let a restore of a line main had replaced read as landed (fixture 171). Its fix and the drop of
the prefix subtraction (fixture 172) came before the runs above.

Repeated lines, where git can pair the copies one way when it builds the squash and another way in
the helper's diffs, are run on real `git merge --squash` histories by fuzzers kept with the #399
work, not in the repository. `fuzz13.py` (the devil's-advocate reviewer of round 12 wrote the first
version): a base of 3–7 lines drawn from five repetition-prone code lines, a branch of 2–3 commits
that only insert lines, one edit of main's own, then a squash of the whole branch (full: nothing
may be listed) or of its first commits (prefix: every later commit is an orphan). `fuzzdel2.py`
(round 13's requirements reviewer): one commit deletes one of the repeated lines and changes the
file's last line (in the rename runs it also moves the file), a second adds a file, main edits one
line first, the whole branch is squashed, and a follow-up edits the branch's last line (nothing
may be listed). Round 14's reviewers added `fuzzdel3.py` (`fuzzdel2` plus a commit that adds a copy
of the deleted text), `fuzzcopies.py` (a function copied into new functions and the original
renamed; main edits a line of the original; a clean squash, no follow-up), `fuzzrebase.py` (Rebase
and merge: the commits picked one by one, then a follow-up) and `fuzzrelease.py` (`fuzzdel2`
squashed into another branch that is then merged). Cases whose squash conflicts are skipped.

| Run | Clean cases | Round 15 | Round 14 | Round 13 | 3.5.0 |
|-----|-------------|----------|----------|----------|-------|
| fuzz13 full, seeds 1 and 3 | 311 | 0 false | 0 false | 0 false | 0 false |
| fuzz13 prefix, seeds 2 and 4 | 394 | 0 false, 148 missed | 0 false, 148 missed | 0 false, 148 missed | 0 false, 512 missed |
| fuzzdel2, seeds 11–13, with and without a rename | 258 | 0 false | 0 false | 7 false in seed 11's 44 (each way) | — |
| fuzzcopies, seeds 1–3 | 82 | 0 false | 51 false | 30 false | 0 false |
| fuzzdel3, seeds 11–13 | 64 | 7 false | 7 false | 4 false in seed 11's 23 | 23 false in seed 11's 23 |
| fuzzrebase, seeds 2–4 | 26 | 1 false | 1 false | — | — |
| fuzzrelease, seeds 11–13 | 64 | 7 false | 7 false | — | — |

None of the prefix runs lists a commit that landed; the misses there are at the tip (D1+D2: the
inserted lines are elsewhere in the file), 3 at the landing commit (R1's adjacent copies). The
false listings of `fuzzdel3`, `fuzzrebase` and `fuzzrelease` are the D1 routes the copy rule
refuses (a text two commits touch; a landing in several steps), listed by a follow-up at the tip.

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
- **Round 13 verify.** Four new classes, none built by the world: with
  `core.precomposeUnicode` on, an NFD name matched nothing and a branch that never landed read
  as landed; R1 read the copies of an earlier squash of the same branch as main's and cleared
  the commit that undid them; deleting one of two equal lines next to main's edit left no
  landing commit (a deletion fuzz: 7 of 44 clean squashes listed, with or without a rename);
  and a submodule pointer or a renamed file sent `confirm()` to exit 4. Its R1 class was
  decided from the helper's own count, so a wrong count could never show as unexplained.
- **Round 14.** `--landing two` builds the landing in two squashes, and R1's class needs the
  model's cause. Its first runs found four more holes in the round-14 rules themselves, each
  fixed and pinned: the copy rule for the landing search counted a copy that one branch commit
  added and a later one took away (fixture 148); main's own removal of a copy cancelled the
  copy an earlier squash of the branch brought, so the check for L^1's copies never fired
  (fixture 147, which led to `part_landed`); a later commit squashed before the rest is no
  prefix (fixture 149, `git cherry`); and both of those counted only up to the landed prefix,
  while a later commit's copy arrived in the same step (fixture 150). The oracle's first
  version took all of S for a landing in several steps; the definition takes what main
  received up to the step where the branch landed. The full runs then found three more:
  `--landing merge` gave 8 more wrong verdicts than round 13 (the count at a merge commit,
  whose step brings other commits too: the rule now skips merge commits); `--pairs` found a
  commit that moved a line of repeated text, which leaves the count alone and so went unseen
  (the rule now counts every commit that touches the text: fixture 155); the classifier's
  R1 cause compared the landing step with the head, which let the branch's own changes pass
  as main's (the cause is now main's own change in that step only); and with that cause in
  place, `plain` mode still put 36 cases in R1: the copy rule took a commit of main's own
  that added the branch's text elsewhere for the landing commit (56 such landings in the
  length-2 world). The rule now needs some other line of the net change in place in the
  commit (fixture 157), which leaves none. The mutants of these last rules: M421 (a move
  not a touch) is caught by 155, M422 (counting at a merge commit) by 156, written after it
  survived, and M423 (no line in place needed) by 157. All bounded runs below are on the
  final helper and model. Four mutants survived the suite of the
  chain's snapshot (no rename detection at the tip, either entry check in `confirm()`, the
  check of other commits' copies), and later one more (`confirm()` not following the branch's
  rename since the merge-base); fixtures 151–154 were then written against them, each failing
  on its mutant (154 also on round 13).
- **Round 14 verify.** Four HIGH, two of them from round 14's own rules: with renames detected
  at the tip, a commit that later moved a file no longer carried the lines an earlier commit
  added to it, and the earlier commit was read under its own name, which neither the head nor
  the tip has, so a fix that never landed read as landed; and the check of other commits' copies
  listed a clean squash of a function copied twice (51 of 82 in the DA's fuzz, 3.5.0 none). The
  other two were older: a unique line paired with another function's next to repeated bodies,
  and a repeated text two commits touch, which no landing commit is counted for. The world
  could build none of these: its slots never repeat a block, and it has one file and no
  renames. The routing model also followed the helper's landing rules, so a wrong refusal
  there showed as the tip class.
- **Round 15.** The tip reads each file under its name in the head as well; every finding at
  the landing commit is checked against the copies (a unique line the commit moved excepted);
  L^1's copies are main's less the part of the branch L^1 holds, and only another commit that
  changes the copies and reached L^1 uncounted keeps a finding; the copy rule needs a count to
  compare and a line its own step brought. `bounded.py` follows the new rules in its model of
  the landing step and of R1, and its tip class now needs a cause D1 names, read from how the
  case was built.
- `--after` needs length 2: a single-commit squash is matched by `git cherry`, so no length-1
  case reaches the landing step. Rounds 13 and 14 ran no `--old-git` mode: the helper has not
  called merge-tree since round 12.
- Not covered by the world: branches longer than 3 (and length 3 only by sampling), more than
  one file with lines, merge commits on the branch, renames and repeated blocks (fixtures
  103–157 and the fuzz runs above), and the 200-check and 20-commit limits (fixtures 12, 60 and
  127). Adjacent slots holding the same text are not in the results: there even the positions
  are ambiguous in the text, and no check that reads text can tell which slot a line belongs
  to. The model tracks each line by its slot; the helper sees text and positions, so equal
  texts at the tip are where most disagreements come from.
