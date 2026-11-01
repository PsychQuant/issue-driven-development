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
copy is an effect too. A file is followed across moves (and a copy that replaced it), so for such a file
"a path" is the file at that path: a move that took it from a name still shows in the head
when the head's file there is another one (a new file put at the old name), and a name the
file reached shows only while the file is there.

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
| 56b | Row 56 when another commit of the branch adds or deletes a copy of the same text, or the branch landed in several steps (Rebase and merge, a squash into another branch that is then merged) | all | 0 in the definition; the helper finds no landing commit for the whole branch and checks the commits it cannot place at the tip (D1+D2), where the follow-up lists them; accepted as a known limit (2026-10-31) | 179, 180 (pin the route) |
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
| 68 | Row 54 when the first PR is older than the newest 20 earlier commits (round 14 searched only those for a part of the branch in L^1) | the landed commits | 3: the restore (the first PR's commit is in place in L^1) | 164 |
| 69 | A squash edited by hand dropped a commit adding a copy, or moving one; later main's own commit adds the same text | the other commits | 3 in the definition; the landing is the squash of what landed, not main's commit, and the dropped commit is checked at the tip (D1+D2), where the copies hide it | 165, 166 (pin the route) |
| 69b | A unique line restored by a commit that never landed, after the commit that moved it landed | all but the restore | 3: the restore (a move is judged by position) | 169 |
| 69c | A file whose name has a backslash; main's own commit already had the branch's line in another file; squash; follow-up | all | 0 | 170 |
| 70 | More than 64 KB of paths: a path `update-index` refuses (an NTFS form of `.git`), changed only on the branch; a repository whose path has `:`, with `core.splitIndex` on | ∅ there / all | 3 / 0, and nothing written into the repository's `.git` | 167, 168 |
| 71 | A restore of a unique line never landed; main had replaced that line itself before the branch landed | the first commit | 3: the restore (the line is not in the landing commit; main's replacement does not count as main removing the branch's copy) | 171 |
| 72 | A commit dropped after picks of the commits around it, the first pick replacing the line the branch's net change deletes | the picks | 3: the dropped commit | 172 |
| 73 | Row 71 for a deletion: a commit deleting a unique line never landed, and main had put the same line in the same place itself | all but it | 3: that commit (the line is still in the landing commit) | 173 |
| 74 | Row 63 after the branch moved the file between the commit in L^1 and the restore | the landed commits | 3: the restore | 174 |
| 75 | Row 56 with an inserted line instead of a replaced one, in a file the branch moved | all | 0 | 175 |
| 76 | Row 63 with the branch moving the file last, the move landing with the last PR | the landed commits | 3: the restore | 176 |
| 77 | A line set and set back, then the file moved; main took the first change and the move | all but the set-back | 3: the set-back only | 177 |
| 78 | Rows 55 and 70 with a post-index-change hook in the repository | ∅ | 3, and the hook does not run | 178 |
| 79 | Row 46 with the file moved twice on the branch (f, then mid/f, then lib/f); the commit edited only under the middle name was picked to main early | the commits up to the last move | 3: the restore (the branch's commits are found by every name the file had) | 181 |
| 80 | A commit adds (or deletes) a line; a later commit moves the file; a third puts a new file at the old name; main picks the last two | the move and the new file | 3: the first commit (its file is the moved one, not the new file at its old name) | 182, 184 |
| 81 | Row 65 with the moved file mostly rewritten afterwards (the first commit and the head are below git's rename similarity) | the move, and the rewrite without the first commit's line | 3: the first commit | 183 |
| 82 | Every commit lands, as picks folded into one squash that moves the file and puts a new file at its old name (git records no move in that squash) | all | 0 | 185 |
| 83 | A later commit replaces more than 1000 files (no move) / deletes a file an earlier commit edited, where git skipped its rename detection | all / ∅ | 0 / exit 4 with the reason | 186, 186b |
| 84 | A line set from `1` to `01` and back; main took the first change only | the first | 3: the set-back (lines compare as text) | 187 |
| 85 | Rows 55 and 70 with a hook defined in the configuration (`hook.<name>.event`), small (a moved file) and wide | ∅ | 3, and the hook does not run | 188, 188b |
| 86 | A partial clone, with git older than 2.45 (which cannot be told not to fetch) / with 2.45 or newer | — | exit 4 with the reason / the check runs | 189 |
| 87 | A move over two commits (one deletes a file, the next adds it under another name, edited); main edits another line of it, then squashes | all | 3 by D4 (the second commit re-adds main's edited line), at the squash as the landing commit (one rename detection between the merge-base and the head pairs the two names) | 190 |
| 88 | Part of the branch lands as picks folded into one squash that moves the file to a name it had before its last one and puts a new file at the old name (git records no move) | the first move, the new file, an edit before them | 3: the commits that never landed, and not the ones that did (the branch's file is the one main created at a name it had on the branch, latest first) | 191 |
| 89 | Row 56b (two commits touch a repeated text, whose copies the net change changes) with the file moved between them | all | the route of row 56b: no landing commit by the copy rule, the first commit checked at the tip (the branch's commits are found by every name the file had) | 192 |
| 90 | The branch's newest commit is empty (`--allow-empty`); squash; follow-up | all | 0 (not exit 4: the log's last commit has no entry) | 193 |
| 91 | Every commit lands as picks folded into one squash: two moves, and a new file at the middle name | all | 0 (main's history follows the file to its last name; the file main created at the middle name is the new file) | 194 |
| 92 | A move, a new file at the old name; later the file moves on and a new file takes the name it left (never landed); main picks the first moves and the first new file | the first move, the first new file, the second move | 3: the commits that never landed, not the first move (an added path is an effect only while it is still the file's path in the head) | 195 |
| 93 | One commit adds a copy of a file, the next deletes the original; squash (git records a move); with or without a follow-up | all | 0 (the head and the tip have the same thing at every name; a commit taken as the landing commit holds the branch's files at their names in what landed) | 196, 196b |
| 94 | Two files swap names over three commits; a fourth deletes a line of one (never landed); main squashes the first three | the swap | 3: the fourth commit (the squash records two edits; the landing commit and the tip hold each file at its name in what landed) | 197 |
| 95 | Main squashes the first commits of the branch (a file added and moved); the branch merges main, then deletes main's copies of a line (never landed) | the first commits | 3: the deletion (a path two lines of history bring a file to holds one file, whatever order the log lists them in) | 198 |
| 96 | Row 70 with the moved file's name sorting before the wide directory | all | 0 (no check stops reading a list early: with pipefail the writer's SIGPIPE was the answer) | 199 |
| 97 | A partial clone made by `git clone --filter` (a promisor remote, no `extensions.partialClone`), git older than 2.45 | — | exit 4 with the reason | 200 |
| 98 | A path holding byte `\034` (awk's subscript separator); an edit that never landed | ∅ | 3 | 201 |
| 99 | No merge-base (an orphan branch); main took its file in a commit with another file | — | 0 (no file is followed; the head's content is at the tip) | 202 |
| 100 | A deletion from a file main moved, never landed | ∅ | 3 (main's file followed to its new name; 3.5.0 and round 16 missed it) | 203 |
| 101 | Row 94 when nothing landed (main took a commit of its own) | ∅ | 3: the swap's three moves and the deletion (main never touched the two files, so its history says where each is; read by the head's names the deletion read as landed) | 204 |
| 102 | Row 94 landed; the branch merges main, swaps the files back and deletes a line (none of it landed) | the first swap | 3: the swap back and the deletion, not the first swap (the squash the branch merged is still read by the names of what landed) | 205 |
| 103 | Row 55 with git 2.54's hook switches (no event switch, only a hook's own name) | ∅ | 3, and the hook does not run | 206 |
| 104 | A copy, the original deleted, the copy moved on; main picks the first two | the copy and the deletion | 3: the commits that never landed, not the copy or the deletion (the deleted file and the one at the name the merge-base and the head pair it with are one file) | 207 |
| 105 | A chain of copies (copy, delete the original, edit, copy again, delete the first copy); main squashes the first copy and deletion | the first two | 3: the last three (each deletion is paired with the copies the branch made before it) | 208 |
| 106 | Row 94 landed; a later commit moves the first file out of the name the swap gave it (never landed) | the swap | 3: the later commit, and the swap's first move by D3 (it took the file to the name the later commit takes it back to), not the second move (at the landing commit a path is compared by file: the file there is not the one the second move took away) | 209 |
| 107 | A line, then a copy of the file; the original's deletion never lands; main squashes the first two | the line and the copy | 3: the deletion only (the prefix up to the copy holds the file at both names, and the squash has it at the copy's) | 210 |
| 108 | A copy picked to main alone; the original's deletion and a new file at its name never land | the copy | 3: the deletion and the new file (a name the landed prefix gives the copied file is no other file's) | 211 |
| 109 | A move, a deletion, a rewrite, a new file at the old name; main picks the deletion and the rewrite (git applies them at the old name) | the deletion and the rewrite | 3: the move and the new file, not the rewrite (nothing landed by the search; where main changed the file at a name the head gives one file and main's history another, the content says which) | 212 |
| 110 | The branch adds a file and edits it; main squashes them and moves the file; the branch merges main and edits the file at its old name (never landed) | the add and the edit | 3: the last edit (a name the revision holds that the view of two lines of history lost is a file of its own) | 213 |
| 111 | A move, then the original put back at the old name; squash; main's later edit | all | 0 (a file history puts at a name keeps it only when it has no place of its own) | 214 |
| 112 | Row 111 with the old name recreated byte for byte and the moved file edited | all | 0 | 215 |
| 113 | A swap and a copy, the last move of the swap never landed; main squashes the rest (not a prefix) | the rest | 3: the move that never landed (a name the landing commit gives no file of the head can still hold the file a commit took away) | 216 |
| 114 | A file copied twice, its deletion never landed, the first copy edited; main squashes the copies and the edit | the copies, the edit | 3: the deletion only (the deletion pairs with the newest copy, in a fixed order; a name the reference gives the file is the file) | 217 |
| 115 | Row 97 with `GIT_CONFIG` set in the environment | — | exit 4 with the reason (the check reads the repository's configuration) | 218 |
| 116 | A remote with only `remote.<name>.partialclonefilter`, git older than 2.45 | — | exit 4 with the reason | 219 |
| 117 | Another commit (never landed), a deletion, a copy, the original deleted; main picks the copy alone | the copy | 3: the deletion before the copy and the original's deletion, not the copy (a line a commit deleted is kept at the tip when any name of the file still has it) | 220 |

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
  commits are not a prefix of the branch; the commits after a landed prefix (which never
  landed, or landed on their own); a squash resolved by hand left one of the branch's
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
  the tip, as they are when some of its commits reached main through cherry-picks; a `git pull`
  merge on main bringing the squash in through its second parent, when that side edited the
  branch's lines after the squash; a stacked branch merged after its base branch changed the
  stack's lines after the stack was cut; and, outside the small world (fixtures 12, 60 and
  127), a landing commit beyond the 200 checks or a landed prefix followed by more than 20
  commits that never landed. The maintainer accepted the repeated-text and several-step routes
  as known limits on 2026-10-31 (fixtures 179 and 180 pin them). `bounded.py` requires one of
  these causes, read from how the case was built, for every disagreement at the tip (round 15;
  before it, the class followed the routing model, which follows the helper's own landing
  rules; round 16 stopped counting a landing mode as a cause by itself; round 17 narrowed the
  rest to what this list says: a squash edited by hand or a merge counts only when main's own
  edit in that step itself touches a unit the branch edits, not a commit of main's own before
  it; a branch with no net change is no cause by itself; and each repeated-text cause needs the
  repeated text at a unit the net change changes). At the tip main's own edits, before or after landing,
  are part of the target. The helper cannot tell "nothing landed" from "landed, then main
  changed it" there, so only presence is compared (D2), and the deviation is documented
  instead of fixed.
- **M1, moved files the readings cannot place (accepted 2026-11-01, only these).** Which
  file of the branch a name on main holds is read from the names the branch's files had in
  what landed, from main's history, and where the two disagree on a file main changed, from
  the files' lines. These five shapes are outside what those readings settle; in them the
  verdict can be wrong in either direction (a commit that landed listed, one that did not
  missed), measured by the rename fuzzers in Results:
  1. the landed commits are not a prefix of the branch and the branch moved, swapped or
     copied a file (at the landing commit or at the tip);
  2. a copy and its original are both in what landed: a deletion the branch made before the
     copy is read from the copy at the landing commit (fixture 220 shows the tip's route);
  3. a pure move onto a name where main has a file of its own (another PR added it): the
     move reads as landed (every version so far);
  4. two nearly identical files the branch swapped, when main edited the lines that tell them
     apart: main's own commit can read as holding the swap;
  5. beyond 200 copy detections, 100,000 candidate pairs, or a group of paths over 64 KB: a
     deletion stays a deletion, not a move onto the copy.
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

Runs of 2026-11-01 with `bounded.py` (blob `d62273e`) and
`python3 bounded.py --max-len N [--sample K --seed S] [mode]`. Round 18 ran every mode on helper
blob `77f9d09`, whose reading of main's files was then reworked once more (`nm_of` only:
the world builds no moves, so no case reaches it); every number came out exactly as
round 17's (helper `2d31d56`), shown below. Round 19 pairs a deletion with an earlier copy on
any branch, so it ran five modes again on its helper (`plain` length 2 in full, `--landing own`,
`--landing merge`, `--after`, `--touch --landing own`): every number the same. The suite and
the fuzz runs used the final helper (the fuzzers one revision before a change that only reaches
copy detections over 64 KB of paths).
The machine carried other work at a load of 20 to 650, so apart from `plain` length 2 (every
case) the samples are smaller than round 14's (400 to 1,000 cases a mode, against 3,000 to 6,000). "Known" lists the cases by class ("tip" is D1+D2 alone); "Wrong verdict" counts the
known cases whose exit code differs from the definition's; "Landing" counts cases in which at
least one commit was checked at a landing commit.

| Mode | Length | Cases | Agree | Known | Wrong verdict | Landing | Unexplained |
|------|--------|-------|-------|-------|---------------|---------|-------------|
| default | ≤ 2 | 7,058 (all) | 5,938 | tip 1,120 | 716 (3 → 0) | 1,260 | 0 |
| default | ≤ 3 | 1,000 of 109,788, seed 399 | 723 | tip 277 | 105 (3 → 0) | 293 | 0 |
| default | ≤ 3 | 600 of 109,788, seed 4242 | 442 | tip 157, tip+D3 1 | 59 (3 → 0) | 182 | 0 |
| `--landing own` | ≤ 2 | 800 of 22,440, seed 399 | 692 | tip 100, R1 8 | 84 (3 → 0) | 553 | 0 |
| `--landing own` | ≤ 3 | 400 of 300,448, seed 399 | 308 | tip 87, R1 4, tip+D3 1 | 25 (3 → 0) | 262 | 0 |
| `--landing merge` | ≤ 2 | 800 of 27,498, seed 399 | 723 | tip 71, R1 6 | 77 (3 → 0) | 250 | 0 |
| `--landing merge` | ≤ 3 | 400 of 392,358, seed 399 | 304 | tip 93, R1 3 | 29 (3 → 0) | 165 | 0 |
| `--landing two` | ≤ 3 | 600, seed 399 | 552 | tip 48 | 48 (3 → 0) | 200 | 0 |
| `--landing two` | ≤ 3 | 400, seed 4242 | 372 | tip 28 | 28 (3 → 0) | 133 | 0 |
| `--landing two --touch` | ≤ 3 | 600, seed 12 | 548 | tip 44, B2 5, D4 3 | 46 (3 → 0), 4 (0 → 3) | 163 | 0 |
| `--after` | ≤ 2 | 600 of 22,350, seed 399 | 480 | tip 91, B2 29 | 117 (3 → 0), 3 (0 → 3) | 229 | 0 |
| `--adjacent --distinct` | ≤ 2 | 600 of 7,058, seed 12 | 600 | — | — | 155 | 0 |
| `--adjacent --distinct --landing own` | ≤ 2 | 400 of 22,440, seed 12 | 400 | — | — | 280 | 0 |
| `--adjacent --distinct --landing merge` | ≤ 2 | 400 of 27,498, seed 12 | 400 | — | — | 195 | 0 |
| `--touch` | ≤ 2 | 600 of 11,448, seed 12 | 498 | tip 100, B2 2 | 77 (3 → 0), 1 (0 → 3) | 103 | 0 |
| `--touch --landing own` | ≤ 2 | 600 of 71,070, seed 12 | 428 | tip 165, R1 3, B1 2, B2 1, D4 1 | 70 (3 → 0), 52 (0 → 3) | 310 | 0 |
| `--touch --landing merge` | ≤ 2 | 600 of 79,350, seed 12 | 492 | tip 103, B2 5 | 71 (3 → 0), 36 (0 → 3) | 178 | 0 |
| `--pairs` | ≤ 2 | 800 of 103,986, seed 12 | 681 | tip 119 | 47 (3 → 0) | 155 | 0 |

Every number in the table is round 16's, mode by mode; `plain` length 2 gives exactly rounds
13 to 16's answers on all 7,058 cases (5,938 agree, 716 wrong verdicts at the tip, all 3 → 0).
In every mode the tip class needs a cause D1 names, read from how the case was built, and
round 17 narrowed that check to D1's wording (no commit of main's own before the squash, no
branch with no net change by itself, repeated texts only at a unit the net change changes):
the runs above have no case left unexplained by it. The world builds no moves; round 17's file
identities are checked by the fixtures (181–195), the reviewers' repro scripts and the rename
fuzzer below.

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

| Run | Clean cases | Rounds 15 to 17 | Round 14 | Round 13 | 3.5.0 |
|-----|-------------|------------------|----------|----------|-------|
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
refuses (a text two commits touch; a landing in several steps), listed by a follow-up at the tip,
which the maintainer accepted as known limits on 2026-10-31. Rounds 16 and 17 give exactly round
15's answers in every run.

Moves are run by `fuzzrename.py` (round 17, kept with the other fuzzers): one file of 8 to 12
base lines, a branch of 3 to 6 commits each of which adds a unique marker line, deletes a base
line, moves the file to a new name, puts a new file at a name the file left, rewrites most of
the file, or adds an unrelated file; main receives a random subset of the commits as picks
folded into one squash (all of them in a fifth of the cases), sometimes after a commit of its
own, sometimes followed by a follow-up on a landed marker. The right answer is known by
construction: a commit outside the subset is an orphan when an effect of it is still in the
head (its marker, the base line it deleted while main still has it, its new file, the name it
moved the file to, the path it left while main still has it). Cases whose picks conflict are
skipped. A listing the follow-up causes when the landed commits are not a prefix of the branch
is D1+D2 (they are checked at the tip).

| Run | Cases | Agree | D1+D2 | False clean | False listing | Round 16 |
|-----|-------|-------|-------|-------------|---------------|----------|
| fuzzrename, seeds 7, 21, 33, 45 (80 each) | 251 | 243 | 8 | 0 | 0 | 215 agree, 4 D1+D2, 19 false clean, 13 false listing |
| the same, rounds 18 and 19 | 251 | 241 | 8 | 0 | 2 | (round 17: the row above) |

Round 17's own drafts gave 0 false clean throughout, and false listings that fixtures 185, 191,
194 and 195 now pin (and the `same_paths` change).

The two listings (rounds 18 and 19) are both where the landed commits are not a prefix of the
branch (M1, shape 1). Seed 45's case 60 lists a move and a new file that landed, where round
17 listed only the two commits that did not; seed 21's case 60 lists a move that never landed
whose old name a new file then took: this fuzzer's ground truth reads paths by name and counts
it as no orphan, while the definition, which follows the file, counts it as one.

`fuzzrename2.py` (round 18) builds the shapes round 17's verify found the first fuzzer never
did: two files, A and B, each line naming its file, so which file sits at a name is read from
the lines. A branch commit adds a marker, deletes a base line, moves a file to a free name,
moves it back to a name it had, swaps A and B over three commits, copies a file to a new name
and deletes the original in the next commit, rewrites most of a file, puts a new file at a
name a file left, or adds an unrelated file. Main may commit on its own first, may move A
itself (before the picks), and squashes a random subset of the branch's commits as picks; in
a quarter of the cases the branch then merges main and adds one to three commits, of which
main sometimes squashes some too. A commit outside what landed is an orphan when one of its
effects is in the head and not on main: its marker, the base line it deleted, a file at a
name (read from the lines), or a file no longer at a name. A disagreement is "not a prefix"
when the landed commits are not a prefix of the branch: M1 (shape 1) accepts wrong answers
there when the branch moved, swapped or copied a file.

| fuzzrename2, seeds 1–8 (60 each) | Cases | Agree | False clean (prefix / not a prefix) | False listing (prefix / not a prefix) |
|----------------------------------|-------|-------|-------------------------------------|---------------------------------------|
| Round 19 | 353 | 343 | 0 / 1 | 1 / 8 |
| Round 18 | 353 | 340 | 0 / 2 | 1 / 10 |
| Round 17 | 353 | 277 | 6 / 11 | 44 / 15 |
| Round 16 | 353 | 302 | 6 / 14 | 17 / 14 |

The one listing on the prefix route is D3: a move that landed, undone by one that landed and
done again by one that did not, is listed with the last. Round 19's ten disagreements, each with
the four rounds' lists (the exit code is 3 and right in all ten; only the lists differ):

| Case (seed, case) | Landed | Right list | Round 19 | Round 18 | Round 17 | Round 16 |
|-------------------|--------|------------|----------|----------|----------|----------|
| 2, 14 | c0, c2–c4 | c1 | c1–c4 | c1–c4 | c1 | — |
| 2, 23 | c1–c3 | c0, c4–c7 | c0, c7 | c0, c7 | c0, c7 | c0, c7 |
| 2, 57 | c0, c1, c3 | c2, c4–c6 | c0, c2, c4–c6 | same | c2, c4–c6 | c0, c2, c4–c6 |
| 4, 52 | c0–c3, c5 | c4 | c1–c5 | c1–c5 | c4, c5 | c1, c4 |
| 6, 16 (prefix, D3) | c0–c4 | c5 | c2, c5 | c2, c5 | c0–c3, c5 | c2, c3, c5 |
| 6, 55 (merges main) | c0, c1, c3–c5 | c2 | c2, c5 | c2 | c2 | c2 |
| 7, 14 | c0, c3 | c1, c2 | c1–c3 | c1–c3 | c1, c2, c4 | c1, c2 |
| 8, 24 | c0–c2, c4 | c3 | c2–c4 | c2–c4 | c3 | c3 |
| 8, 36 (merges main) | c0, c1, c4 | c2, c5 | c2, c3, c5 | same | c2, c5 | c2, c5 |
| 8, 44 (main moves a file) | c1, c3 | c0, c2 | c0–c2 | c0–c2 | c0, c2 | c1, c2 |

In six of the nine cases off the prefix route round 17's list is right and round 19's is not
(2/14, 2/57, 6/55, 8/24, 8/36, 8/44): M1 accepts these, and they are the cost of the shapes
rounds 18 and 19 fixed on the prefix route, where round 17 had 6 false cleans and 44 false
listings. Round 18's own drafts gave, in turn:
a merged squash read by history (fixture 205), the swap read by names in the landing search
and at the tip (197, 204), a copy chain (207, 208), a link joined to the wrong file, a path
compared by name at the landing commit (209), a copy's original read as another file (210,
211).

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
  L^1's copies are main's unless another commit that changes them has its own change in place
  in L^1; the copy rule needs a count to compare and a line its own step brought. `bounded.py`
  follows the new rules in its model of the landing step and of R1, and its tip class needs a
  cause D1 names, read from how the case was built.
- **Round 15 verify.** Three HIGH of one kind: every diff record carried the new side's name of
  its file, also for the old side's lines, so once the branch had moved a file, two diffs about
  the same line never met. The check at the landing commit read a candidate under its own
  names (round 15 had fixed only the tip), `in_l1` missed a commit that reached L^1 before the
  move, and the copy rule's line brought by the step was never found in a moved file. The world
  builds no renames. The devil's-advocate reviewer did not run (the API was unreachable).
- **Round 16.** Each record carries the name of the side its line number belongs to; a move
  with no edit gets its rename records from git's "rename from"/"rename to" lines; the diffs at
  the landing commit list the head's names of a candidate's files too. Every git call runs with
  `core.hooksPath=/dev/null`; skipped rename detection is an error. `bounded.py`'s tip causes no
  longer accept a landing mode by itself.
- **Round 16 verify.** Two HIGH of one kind, which round 16's records did not reach: a file's
  identity came from one rename detection between two trees, or from the first of four fixed
  names a revision had. A file moved twice, a file moved away with a new file put at its old
  name, and a file moved and then mostly rewritten were paired wrongly, and commits that never
  landed read as landed (the first is a regression from round 15; the others 3.5.0 caught).
  Skipped rename detection as an error made branches that move nothing exit 4 when a later
  commit replaced a thousand files. awk compared lines that look like numbers as numbers. The
  devil's-advocate reviewer pointed out that neither the world nor the fuzzers built any of
  these shapes.
- **Round 17.** Every file is followed commit by commit (git's rename detection inside each
  commit, as `git log --follow`), known by its name in the head, and every diff compares trees
  that hold each file under that name: the only rename detection between two trees left pairs
  the files added and deleted between the merge-base and the head (a move over two commits). On main
  a file the branch moved is the one main created at its name in the head, when there is one.
  A skipped rename detection matters only where it deletes a file a candidate touched, read
  after it (exit 4). Lines compare as text; hooks from the configuration are off; a partial
  clone with git before 2.45 stops at once. `bounded.py`'s tip causes follow D1's wording
  (no `mop`, no "no net change" by itself, repeated texts at a unit the net change changes). A
  rename fuzzer (`fuzzrename.py`, below) builds moves, new files at old names and rewrites,
  with the right answer known by construction; its first runs found two faults in round
  17's own first draft: a squash that moves a file and puts a new one at its old name
  (fixture 185), and a `same_paths` read by key, which let a squash without the move hold a
  prefix that moved the file; a third run found main landing the file under a name it had
  before its last one (fixture 191). Reading the draft once more found a log ending on an
  empty commit read as an error (fixture 193), and the final fuzz runs two more false
  listings: main's step 1 taking a middle name where history had already followed the
  move (fixture 194), and an added path counted as an effect when the head's file there is
  another one (fixture 195).
- **Round 17 verify.** Six HIGH. Three of one kind: main's files were read by main's history,
  and a squash records the branch's moves as one step's rename detection, which pairs files
  otherwise: a copy and then the original deleted reads as a move (a branch whose head and tip
  were the same tree was listed), two files that swap names read as two edits (a deletion that
  never landed read as landed), and a branch that merged main's squash had the same file reach
  one path by two lines of history, kept by whichever the log listed first (a deletion that
  never landed read as landed). Two checks stopped reading a pipe at their first match, and
  with pipefail the writer's SIGPIPE became the answer on a wide branch. A partial clone made by
  `git clone --filter` (a promisor remote) was not recognized. Also: a path with awk's subscript
  separator split in two, git 2.54's configured hooks not turned off, no merge-base read as an
  error, and every revision replaying every commit since the fork point.
- **Round 18.** A commit of main tried as the landing commit, the landing commit and the tip
  after it are read by the names the branch's files had in what landed (where main changed a
  file or the branch's name holds one); before the landing commit, by main's history; with
  nothing landed, the head's names except where main's history puts another of the branch's
  files at a name main never changed. A revision in its reference's history (a squash the
  branch merged, read for a later commit of the branch) is read by history. A path two lines
  bring a file to holds one file; where main changed the file at a name the head gives one
  file and main's history another, the file goes to the head file it shares more lines with.
  The landing search also asks that every file the net change
  moved be at the reference's name (two files that swap names leave each name holding a
  file), and reads each candidate the cautious way (a commit of main's own that never touched
  two swapped files held the swap by their names alone). At the tip a path a commit added or
  deleted is compared by file. A move split into a copy and a later deletion is one file even
  when the copy reached the head's name by another move, and of a copy and its original in one
  revision the copy stands for the file. P0 compares names. No check stops reading a pipe
  early; awk never joins two paths in one string; promisor remotes count as a partial clone;
  configured hooks are turned off by name too; with no merge-base no file is followed; a
  revision replays only the commits that move or add or delete a followed name. A second rename
  fuzzer (`fuzzrename2.py`, below) builds two files that swap names, files moved back, copies
  with the original deleted later, main moving a file itself, and branches that merge main;
  its first runs found the reading of a merged squash (fixture 205), the swap read by names at
  the tip and in the landing search (197, 204), the copy chains (207), and the link joined to
  the wrong file.
- **Round 18 verify.** One CRITICAL and three HIGH, most of them the new rules breaking shapes
  earlier rounds got right: a path two lines of history brought a file to was one file, and a
  move on one line took the other line's file with it (an edit at the old path read as no
  change); a name the branch made and removed again, which a squash of some of its commits
  kept, was in no net change and the commit that left it was missed; a move and the original
  put back, squashed and edited later by main (#399's own shape), listed both commits; and the
  new limit was worded narrower than what the fuzzers measured. Also: copy pairing in awk's
  hash order (macOS and Linux answered differently) and with unbounded paths, `GIT_CONFIG` in
  the environment, slower runs. On 2026-11-01 the maintainer chose to converge: fix the
  common shapes and #399's own, and accept the rest as known limits (M1).
- **Round 19.** Each view of the files is checked against its revision's tree: a name the
  revision holds and the view lost is a file of its own, and one the view holds and the
  revision does not is gone. A file history puts at a name keeps it only when it has no
  place of its own at its name in the reference; the history exception of step 1 applies only
  when the head has another file at the reference name; a name the reference gives another
  file is skipped only while that file has no place elsewhere (or when it is the other name
  of a copy); a tie in the content decision goes to history. At the tip and the landing
  commit a deleted name that holds a file the reading gives no file of the head counts as not
  landed, and a deleted line is kept while any name of the file has it (at the tip). Copy
  pairing runs newest copy first in a fixed order, bounded. `GIT_CONFIG` and an inherited
  `GIT_CONFIG_PARAMETERS` are unset; `remote.<name>.partialclonefilter` marks a partial
  clone; `GIT_CONFIG_COUNT` is read in base 10; `cand_keys` fails on a read error;
  `same_files` runs only when the net change touches a followed file. The rename fuzzers are
  in this directory.
- `--after` needs length 2: a single-commit squash is matched by `git cherry`, so no length-1
  case reaches the landing step. Rounds 13 and 14 ran no `--old-git` mode: the helper has not
  called merge-tree since round 12.
- Not covered by the world: branches longer than 3 (and length 3 only by sampling), more than
  one file with lines, merge commits on the branch, renames and repeated blocks (fixtures
  103–212 and the fuzz runs above, `fuzzrename.py` and `fuzzrename2.py` for moves, swaps, copies
  and branches that merge main), and the 200-check and 20-commit limits (fixtures 12, 60 and
  127). Adjacent slots holding the same text are not in the results: there even the positions
  are ambiguous in the text, and no check that reads text can tell which slot a line belongs
  to. The model tracks each line by its slot; the helper sees text and positions, so equal
  texts at the tip are where most disagreements come from.
