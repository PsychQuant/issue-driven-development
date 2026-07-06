# fixture 13 — empty candidate set REFUSES --linked-issue (#172)

Tests that `--linked-issue <N>` with an EMPTY candidate set fails with a
redirect message pointing at `--force-linked-issue <N>` — the pre-#172 escape
hatch (empty set = authoritative accept) was removed as timing-dependent;
the authoritative path is now the dedicated force flag (fixture 15).

## Why this fixture runs from /tmp (env coupling — #170 verify DA-3 / codex)

The escape hatch fires only when `detect_candidates` returns empty. Fallback 3
(`git log -- <archive_dir>`) is empty here ONLY because the test harness invokes
the script from a `/tmp` cwd (non-git), so git-log finds nothing for this path.

From the **repo cwd**, F3 would find this committed fixture's own `#170` commit,
making the candidate set `{170}` (non-empty) and exercising the membership path,
NOT the escape hatch. The production trigger differs again: `spectra-archive`
posts the IC **before committing** the moved archive, so F3 sees an untracked
path and returns empty — the real empty-candidate scenario this fixture stands in
for. The `/tmp` isolation is a deliberate unit-test of `detect_candidates` in
isolation, not a faithful reproduction of the production filesystem timing.
