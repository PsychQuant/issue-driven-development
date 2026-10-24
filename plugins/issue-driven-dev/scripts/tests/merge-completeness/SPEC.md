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
- `--after` adds one more main edit after the squash, to a unit the branch touched. This is
  out of scope by decision A.
- `--old-git` puts a `git` shim first on PATH that refuses `merge-tree --write-tree`, the way
  git older than 2.38 does.

Every case is run with the real helper on a real repository. Exit 0 means every
disagreement belongs to a class below.

## Known deviations (only these)

`bounded.py` decides each class from the model, never from the helper's own answer. It
reads one thing from the helper besides the answer: where each commit was checked (the
landing commit or the tip), from a trace the helper writes only for this test.

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
- **D3, shared text at the landing commit.** At the landing commit lines are counted, not
  told apart: when a copy of a text is missing from it, or extra, every commit whose effect
  is that text is listed, including one that did land. Only over-listing, and only with the
  right verdict (exit 3).
- **B1, a listed blind spot.** A commit that set its line back to the merge-base value, left
  out after an earlier commit already held the branch's net change (here: the branch has no
  net change, so it lands at the merge-base). The helper's header lists it; it is the one
  class with a wrong verdict (exit 0).

A disagreement is known when every commit the two answers differ on falls in one of these:
checked at the tip and the tip rule (D2), computed on the model's head and tip, gives the
helper's answer; or checked at the landing commit, listed, sharing a text with another
branch commit, with the right verdict (D3); or checked at the landing commit, missed, and
B1 holds in the model.

## Results

Runs of 2026-10-25 against the round-10 helper (`python3 bounded.py --max-len N [--sample K
--seed S] [mode]`). "Tip" is D1+D2; "D3" counts cases whose only class is D3, "tip+D3" cases
with both.

| Mode | Branch length | Cases | Agree | Tip | D3 | Tip+D3 | B1 | Unexplained |
|------|---------------|-------|-------|-----|----|--------|----|-------------|
| default | 1 | 412 (all) | 384 | 28 | 0 | 0 | 0 | 0 |
| default | ≤ 2 | 7058 (all) | 5902 | 1156 | 0 | 0 | 0 | 0 |
| default | ≤ 3 | 6000 of 109,788, seed 399 | 4259 | 1632 | 82 | 11 | 16 | 0 |
| default | ≤ 3 | 6000 of 109,788, seed 4242 | 4205 | 1663 | 107 | 12 | 13 | 0 |
| `--old-git` | 1 | 412 (all) | 384 | 28 | 0 | 0 | 0 | 0 |
| `--after` | 1 | 530 (all) | 530 | 0 | 0 | 0 | 0 | 0 |

How the numbers got here:

- **Round 9, length ≤ 2.** The first run left 32 cases unexplained: nothing had landed, main
  had made an edit of its own, and that edit shared text with the branch. That is the tip
  fallback (D1), whose definition then covered only `--old-git` and `--after`. D1 was widened
  to every commit checked at the tip; the helper did not change.
- **Round 9, length ≤ 3 (seed 399).** 228 disagreements at the landing commit. Under the final
  classes, 19 stay unexplained, all of them exit-code misses (3 → 0): the landing commit was
  compared with the head's count of a line (the guards `t < h`, `t > h`) and with main's state
  just before it plus the branch's net change, which is wrong when the landing commit is the
  merge-base, when its first parent already holds the branch (a stacked branch), and when only a
  prefix landed. Fixtures 84 and 86 are two of them.
- **Round 10.** The landing commit is compared with the clean merge of the landed part onto
  main just before it. The same 6000 cases: 0 unexplained; a second sample with another seed:
  0 unexplained. The remaining disagreements at the landing commit are over-listing with the
  right verdict (D3) and the listed blind spot B1.
- The classifier can still find bugs: under the final classes it leaves round 9 with 19
  unexplained cases, so D3 and B1 do not absorb everything at the landing commit.
- In `--old-git` runs every commit is checked at the tip, so the run measures the tip rule
  only. With `--after` there was no disagreement at length 1: the landing commit was found
  before main's later edit in every case.
- Not covered: branches longer than 3 (and length 3 only by sampling), more than one file
  with lines, merge commits on the branch, renames, and the 200-call and 20-commit limits
  (fixtures 12 and 60 pin those). The model tracks each line by its slot; the helper sees only
  text, so collisions between equal texts are exactly where the two can differ.
