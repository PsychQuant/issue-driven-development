## 1. Tests first

- [ ] 1.1 Tests for every new and changed Example of the delta, failing on the code at `4064fb3`. Verified by running the suite `rest-queue` before the change and seeing them fail.

## 2. The implementation

- [ ] 2.1 The lock of a run (`start`, `next`, `record`, `stop`, `report`). Verified by the example "two sessions at the same run".
- [ ] 2.2 The directory's identity: the pointer and the exclude lines not through a link; `here` with the given path, no link on the way and the shell's directory. Verified by the examples "the pointer file is not written through a symbolic link" and "here names the directory an issue runs in".
- [ ] 2.3 What `record` judges and does: fetch with pruning, the index flags, folders that cannot be listed, the routing log whatever the ignore rules, the mark of a removal, the outcome read again. Verified by the examples "what becomes of a directory", "a routing log that git ignores is carried over", "a record ended before it decided reads the outcome again", "record ended part of the way comes to the same end".
- [ ] 2.4 No optional locks; the index compared as bytes. Verified by the example "reading the starting working tree does not write its index".
- [ ] 2.5 The close stage: the record of a rest issue, one reader of the files. Verified by the examples "a lost pointer stops the close stage of a rest issue", "the review flag of a rest run has one reader", "a state that cannot be used".
- [ ] 2.6 The skill and the documents. Verified by the examples "the skill runs each issue in its directory" and "no text describes the removed step between two issues".

## 3. Checks

- [ ] 3.1 The sweep compares the content of a kept directory and ends `record` inside the removal. Verified by the suite `rest-queue-sweep`.
- [ ] 3.2 `scripts/run-all-tests.sh` and the mutation checks on the new code.
