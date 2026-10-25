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
| 9 | Branch creates and deletes a scratch file; main created its own file at that path | all | 0 | 78 |
| 10 | Branch moves a line, or deletes one of two equal lines it keeps | all | 0 | 64, 65 |
| 11 | Branch renames a file; squash / nothing landed | all / ∅ | 0 / 3 | 71, 71b |
| 12 | Branch adds an empty file; dropped | all but it | 3 | 80 |
| 13 | Branch removes a submodule; nothing landed | ∅ | 3 | 68 |
| 14 | Squash, then main reverts it | all | 0: out of scope | 13, 57 |
| 15 | Branch has no net change; one of its commits was cherry-picked, the one undoing it was not | the first | 3: the undoing commit | 51 |
| 16 | Branch changes a value, then restores it; only the change reached the squash (also when the restored line appears elsewhere in the file) | all but the restore | 3: the restore | 19, 82 |
| 17 | Branch adds a line; main had removed its own copy elsewhere before the squash | all | 0: the copy count is main's plus the branch's | 81 |
| 18 | Squash resolved by hand (checked at the tip); main removed a line of its own that the branch also adds (a shared `}`) | all | 0 | 65, 83 |
| 19 | Branch adds a second copy of a line, then deletes it; main removed its own copy before the squash of the earlier commits | all but the deletion | 3: the deletion | 84 |
| 20 | Squash kept the branch's line over main's own edit of it (resolved by hand); another commit dropped | all but it | 3: the dropped commit, checked at the tip | 85 |
| 21 | Branch drops a line, adds another, then puts the first back; main had turned a line of its own into the same text; squash of the first two | all but the last | 3: the last commit (its copy is missing although the text is elsewhere) | 86 |
| 22 | Two commits landed as one squash; a later commit adds a second copy of their line plus a line of its own, and never landed | the first two | 3: the later commit only | 87 |
| 23 | A commit adds a line the branch later drops again; main had the same text and the landing commit dropped it too | all | 0 | 88 |
| 24 | Squash edited by hand: the branch moves a line, and the squash also turns one of main's lines into the same text | all | 0: undoing the moving commit on the landing commit changes it, so its change is there (git 2.38 and 2.39, which count, list it: fixture 94) | 89, 94 |
| 25 | Release merge: the squash lands on a side branch next to another PR that adds the same text as a line the branch dropped; main merges the side branch | all | 0 | 90 |
| 26 | Branch has no net change; its first commits were squashed, the commits that undid them were not | the first ones | 3: the undoing commits | 91, 92 |

## The small world (`bounded.py`)

- **Units.** f.txt has three slots, each one line from {A, B, C} or empty, separated by fixed
  lines. g.txt (one line) and e.txt (empty) each exist or not. The same text in two slots is
  "the same line elsewhere in the file". The helper sees only text, so it has to tell these
  collisions apart.
- **Merge-base.** Two states: slots (A, –, B) without g.txt and e.txt, and the same with both.
- **Branch.** Every sequence of 1 to N single-unit edits.
- **Main.** An unrelated commit. Optionally one edit of its own to a unit the branch does not
  touch; its text can collide with the branch's. Then, unless S is empty, one squash of S, for
  every subset S of the branch that applies cleanly.
- `--landing own` makes that squash also carry one edit of main's own (a squash edited by
  hand), to a unit neither the branch nor main's earlier edit touched. `--landing merge` puts
  the squash on a side branch, optionally followed there by another PR's edit of such a unit,
  while main gets one more unrelated commit; main then merges the side branch (a release merge,
  or a `git pull` merge). In both modes S is never empty.
- `--after` adds one more main edit after the squash, to a unit the branch touched. This is
  out of scope by decision A.
- `--old-git` puts a `git` shim first on PATH that refuses `merge-tree --write-tree`, the way
  git older than 2.38 does.

Every case is run with the real helper on a real repository. Exit 0 means every
disagreement belongs to a class below.

## Known deviations (only these)

`bounded.py` decides each class from the model, never from the helper's own answer. Where
each commit is checked (the landing commit or the tip) comes from a model of the landing step
written from the helper's header; the helper also writes where it checked each commit to a
trace file (only when the test sets `CHECK_MERGE_COMPLETENESS_TRACE`), and a trace that differs
from the model is a bug in the landing step, whatever the list says. Round 10 took the sides
from the trace itself, so a helper with the landing step switched off still came out with
nothing unexplained.

- **D1, tip fallback.** Some commits have no landing commit to be checked at, and are
  checked at the tip: the case runs with `--old-git` or `--after`; nothing landed (S = ∅);
  the landed commits are not a prefix of the branch; or the landed part does not merge
  cleanly onto main just before its landing commit (a squash resolved by hand). At the tip
  main's own edits, before or after landing, are part of the target. The helper cannot tell
  "nothing landed" from "landed, then main changed it" there; counting would list landed
  branches in the second case, so the deviation is documented instead of fixed.
- **D2, presence at the tip.** At the tip only presence is compared: a commit is listed when
  a line or path it adds is in the head and not in the tip, or one it deletes is not in the
  head and is in the tip. A text that is elsewhere in the tip or the head can therefore hide
  a commit or list one.
- **D3, its place, not its value.** At the landing commit each commit is checked in its own
  place: it is listed when undoing it changes the head and changes nothing on the landing
  commit. The check sees where a change is, not which commit made it: a commit that landed
  and was undone by a later commit that landed too, then changed again by a commit that did
  not land, is listed along with that last commit; so is a commit that did not land and added a
  line that a later commit, which did not land either, rewrote (the head shows the rewrite, not
  the line). Only over-listing, and only with the right verdict (exit 3), since the later commit
  that did not land is listed too.
- **D4, git 2.38 and 2.39 only.** The check in place needs `merge-tree --merge-base` (git
  2.40). Without it lines are counted against the clean merge of the landed part onto main
  just before the landing commit (round 10's rule), and an edit of main's own in the landing
  step that touches a branch commit's text (a squash edited by hand, a release merge, a
  `git pull` merge) can list a commit that landed or hide one that did not. `bounded.py` runs
  with a git that has the option, so it never sees this class; fixture 94 pins it with a shim,
  and the `merge-completeness-count` suite runs every fixture under that shim.
- **B1, a listed blind spot.** A commit that set its line back to the merge-base value, left
  out after an earlier commit already held the branch's net change (here: the branch has no
  net change, so it lands at the merge-base) and no prefix of the branch landed later. Round 11
  runs the prefix search in that case too, which removed every B1 case of round 10's samples;
  the class stays in the list because the earlier commits can reach main in a form no earlier
  state of the branch matches (a squash of them edited by hand), and then nothing lands later
  than the merge-base. Its verdict is wrong (exit 0).

A disagreement is known when every commit the two answers differ on falls in one of these:
checked at the tip and the tip rule (D2), computed on the model's head and tip, gives the
helper's answer; or checked at the landing commit, listed, with the right verdict (D3); or
checked at the landing commit, missed, and B1 holds in the model, including that no prefix
lands after the merge-base. At the landing commit the model also decides the helper's
answer: for a one-unit edit, undoing it changes the head when the head no longer holds the
unit's value from before the edit, and changes nothing on the landing commit when that commit
still holds it. A commit checked there whose listing differs from that is a bug.

## Results

Runs of 2026-10-25 against the round-11 helper (`python3 bounded.py --max-len N [--sample K
--seed S] [mode]`). "Tip" counts cases whose only class is D1+D2; no other class occurred.
"Wrong verdict" counts the known cases whose exit code differs from the definition's;
"Landing" counts cases in which at least one commit was checked at a landing commit (a run
that never gets there says nothing about the landing step).

| Mode | Branch length | Cases | Agree | Tip | Wrong verdict | Landing | Unexplained |
|------|---------------|-------|-------|-----|---------------|---------|-------------|
| default | ≤ 2 | 7,058 (all) | 5,902 | 1,156 | 752 (3 → 0) | 2,000 | 0 |
| default | ≤ 3 | 6,000 of 109,788, seed 399 | 4,353 | 1,647 | 577 (3 → 0) | 2,526 | 0 |
| default | ≤ 3 | 6,000 of 109,788, seed 4242 | 4,320 | 1,680 | 606 (3 → 0) | 2,451 | 0 |
| `--landing own` | ≤ 2 | 22,440 (all) | 19,452 | 2,988 | 2,364 (3 → 0) | 17,472 | 0 |
| `--landing own` | ≤ 3 | 3,000 of 300,448, seed 399 | 2,265 | 735 | 271 (3 → 0) | 2,084 | 0 |
| `--landing merge` | ≤ 2 | 27,498 (all) | 24,490 | 3,008 | 3,008 (3 → 0) | 9,898 | 0 |
| `--landing merge` | ≤ 3 | 3,000 of 392,358, seed 399 | 2,260 | 740 | 258 (3 → 0) | 1,473 | 0 |
| `--old-git` | 1 | 412 (all) | 384 | 28 | 28 (3 → 0) | 0 | 0 |
| `--after` | ≤ 2 | 3,000 of 22,350, seed 399 | 2,451 | 549 | 528 (3 → 0), 21 (0 → 3) | 1,025 | 0 |

Every wrong verdict is at the tip (D1+D2): presence cannot tell main's own copy of a line
from the branch's, and three slots holding three texts make such copies common. At the
landing commit every answer agrees with the definition in these runs.

How the numbers got here:

- **Round 9, length ≤ 2.** The first run left 32 cases unexplained: nothing had landed, main
  had made an edit of its own, and that edit shared text with the branch. That is the tip
  fallback (D1), whose definition then covered only `--old-git` and `--after`. D1 was widened
  to every commit checked at the tip; the helper did not change.
- **Round 9, length ≤ 3 (seed 399).** 19 exit-code misses (3 → 0): the landing commit was
  compared with the head's count of a line and with main's state just before it plus the
  branch's net change, which is wrong when the landing commit is the merge-base, when its first
  parent already holds the branch (a stacked branch), and when only a prefix landed. Fixtures
  84 and 86 are two of them.
- **Round 10.** The landing commit was compared with the clean merge of the landed part onto
  main just before it. Both length-3 samples: 0 unexplained, with 93 and 119 cases of
  over-listing at the landing commit (D3, right verdict) and 16 and 13 misses of the blind spot
  B1 (wrong verdict).
- **Round 10 verify.** The world could not build a landing step that carries main's own edits,
  and the classifier took where each commit was checked from the helper's own trace: with the
  landing step switched off it still reported nothing unexplained. Round 11 added
  `--landing own` and `--landing merge` and decides the sides from a model. Against the
  round-10 helper, samples of 400 left 73 (own) and 48 (merge) cases unexplained.
- **Round 11, two rules that did not hold.** Counting only lines outside the landed part's net
  change missed dropped commits whose text the branch also changed elsewhere (23 and 16 in the
  two length-3 samples). Keeping the count and dropping a listed commit whose change was in
  place still listed pairs of dropped commits that cancel out, and missed a dropped restore
  when main's own edit evened the count (72 and 59 in the own and merge length-3 samples).
- **Round 11, the rule kept.** Each commit is checked in its own place at the landing commit.
  The runs above: 0 unexplained, and D3 and B1 are gone from both length-3 samples (the same
  cases as round 10's).
- In `--old-git` runs every commit is checked at the tip, so the run measures the tip rule
  only. `--after` needs length 2: a single-commit squash is matched by `git cherry`, so no
  length-1 case reaches the landing step.
- Not covered: branches longer than 3 (and length 3 only by sampling), more than one file
  with lines, merge commits on the branch, renames, git 2.38 and 2.39 (D4; fixture 94 and the `merge-completeness-count` suite), and the
  200-call and 20-commit limits (fixtures 12 and 60 pin those). The model tracks each line by
  its slot and every edit touches one slot; the helper checks each commit in its own place at
  the landing commit and by text at the tip, so equal texts at the tip, and commits touching
  several places, are where the two can differ.
