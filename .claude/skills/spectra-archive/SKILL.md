---
name: spectra-archive
description: "Archive a completed change"
license: MIT
compatibility: Requires spectra CLI.
metadata:
  author: spectra
  version: "1.0"
  generatedBy: "Spectra"
---

Archive a completed change.

**Input**: Optionally specify a change name after `/spectra-archive` (e.g., `/spectra-archive add-auth`). If omitted, check if it can be inferred from conversation context. If vague or ambiguous you MUST prompt for available changes.

**Prerequisites**: This skill requires the `spectra` CLI. If any `spectra` command fails with "command not found" or similar, report the error and STOP.

**Step 0: Bootstrap Stage Task List** (required)

Before doing anything else, call `TaskCreate` to build a harness-level todo list for this archive run — one entry per step below. Mark each `TaskUpdate → completed` as you finish it; silent completion is a violation. This mirrors the Step 0 Bootstrap discipline every `idd-*` skill enforces, and gives per-step accountability when `/idd-close` cascades into `/spectra-archive`.

```
TaskCreate(name="prompt_change_name", description="Step 1: resolve change name — prompt via AskUserQuestion if not provided / inferable")
TaskCreate(name="check_artifacts", description="Step 2: spectra status --json — warn + confirm if any artifact not done")
TaskCreate(name="check_tasks", description="Step 3: scan tasks.md — warn + confirm if incomplete - [ ] tasks")
TaskCreate(name="assess_delta_sync", description="Step 4: compare delta specs vs main specs; prompt sync now / archive without sync")
TaskCreate(name="cleanup_tracking", description="Step 5: rm -f .spectra/touched/<name>.json")
TaskCreate(name="run_archive_cli", description="Step 6: spectra archive <name>")
TaskCreate(name="dry_run_implementation_complete", description="Step 7a: spectra-archive-post-ic.sh --dry-run — resolve the issue and keep the body for review (#405)")
TaskCreate(name="privacy_scrub_gate", description="Step 7b: privacy self-review of the kept body per rules/privacy-scrubbing.md, and check that the proposed issue is this change's; record the level, the issue confirmed and what the review found (#405)")
TaskCreate(name="post_implementation_complete", description="Step 7c: post ## Implementation Complete with --scrub-attested <level> --linked-issue <N> (#56, #405)")
TaskCreate(name="display_summary", description="Step 8: read Step 7 outcome + show archive completion summary")
```

Complete each step → `TaskUpdate → completed` immediately.

**Steps**

1. **If no change name provided, prompt for selection**

   Run `spectra list --json` to get available changes. Use the **AskUserQuestion tool** to let the user select.

   Show only active changes (not already archived).
   Include the schema used for each change if available.

   **IMPORTANT**: Do NOT guess or auto-select a change. Always let the user choose.

2. **Check artifact completion status**

   Run `spectra status --change "<name>" --json` to check artifact completion.

   Parse the JSON to understand:
   - `schemaName`: The workflow being used
   - `artifacts`: List of artifacts with their status (`done` or other)

   **If any artifacts are not `done`:**
   - Display warning listing incomplete artifacts
   - Prompt user for confirmation to continue
   - Proceed if user confirms

3. **Check task completion status**

   Read the tasks file (typically `tasks.md`) to check for incomplete tasks.

   Count tasks marked with `- [ ]` (incomplete) vs `- [x]` (complete).

   **If incomplete tasks found:**
   - Display warning showing count of incomplete tasks
   - Prompt user for confirmation to continue
   - Proceed if user confirms

   **If no tasks file exists:** Proceed without task-related warning.

4. **Assess delta spec sync state**

   Check for delta specs at `openspec/changes/<name>/specs/`. If none exist, proceed without sync prompt.

   **If delta specs exist:**
   - Compare each delta spec with its corresponding main spec at `openspec/specs/<capability>/spec.md`
   - Determine what changes would be applied (adds, modifications, removals, renames)
   - Show a combined summary before prompting

   **Prompt options:**
   - If changes needed: "Sync now (recommended)", "Archive without syncing"
   - If already synced: "Archive now", "Sync anyway", "Cancel"

   If user chooses sync, use Task tool (subagent_type: "general-purpose", prompt: "Use Skill tool to invoke spectra-sync-specs for change '<name>'. Delta spec analysis: <include the analyzed delta spec summary>"). Proceed to archive regardless of choice.

5. **Clean up tracking file**

   Delete `.spectra/touched/<change-name>.json` if it exists. This file contains implementation tracking data that is not needed after archiving.

   ```bash
   rm -f .spectra/touched/<change-name>.json
   ```

   If the file does not exist, silently continue.

6. **Perform the archive**

   Use the `spectra archive` CLI command which handles the full archive workflow
   (spec snapshot, delta application, @trace injection, identity recording, vector indexing):

   ```bash
   spectra archive <name>
   ```

   **Optional flags:**
   - `--skip-specs` — skip delta spec application (for tooling/doc-only changes)
   - `--mark-tasks-complete` — mark all incomplete tasks as complete before archiving
   - `--no-validate` — skip delta spec validation

   **If archive fails** with "already exists" error, suggest renaming existing archive.

7. **Post `## Implementation Complete` to linked GitHub issue (v1.3+, PsychQuant/issue-driven-development#56)**

   **Purpose**: ensures `/idd-close` Step 0 supersession gate triggers for Spectra-path issues, removing the need for manual retroactive Implementation Complete synthesis.

   **Delegated to executable helper script** `.claude/scripts/spectra-archive-post-ic.sh` (with unit tests at `.claude/scripts/tests/spectra-archive-post-ic/`). The script is the source of truth — this skill calls it and reads the outcome. Behavior contract (detection / idempotent guard / safe body composition / multi-candidate handling) lives in the script + its tests, not in skill prose. This separation was introduced after R2 verify found that prose-with-illustrative-bash had structural defects (variable persistence across Bash tool calls, Python3 RCE via shell-string interpolation, etc.) — see PsychQuant/issue-driven-development#56 R2 verify report.

   **Required inputs from caller (agent)**: before invoking Step 7, the agent MUST have these in scope (from earlier skill steps):
   - `$CHANGE_NAME` — the Spectra change name (slug; same value passed to `spectra archive`). **This exact value must also be reused, byte-identical, in Step 8** — the outcome file path is derived from it, so any drift (typo / whitespace / case) makes Step 8 read the wrong path.
   - `$SPEC_DELTAS` (optional) — comma-separated capability names from `spectra archive` stdout in Step 6 (e.g., `"idd-all-chain, idd-spawn-manifest"`); defaults to placeholder if absent

   **Invocation**:

   ```bash
   # Resolve repo root to make the script path cwd-independent — the skill may be
   # invoked from a subdirectory (cd openspec && /spectra-archive ...). Relative
   # path .claude/scripts/... breaks; absolute path via git-root prefix doesn't.
   REPO_ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)

   # The directory `spectra archive` just created, found once: recomputing it from today's
   # date in 7c would miss it after midnight (#405).
   ARCHIVE_DIR=$(ls -d "${REPO_ROOT}"/openspec/changes/archive/*-"${CHANGE_NAME}" 2>/dev/null | sort | tail -1)
   SPEC_DELTAS="${SPEC_DELTAS:-(see archived change directory)}"

   # The helper script DERIVES the outcome file path internally from
   # --change-name: /tmp/spectra-archive-ic-outcome-<change-name>.txt
   # (--change-name is allowlist-validated inside the script before being used
   # in the path, so the derived path is always traversal-safe). The formula
   # has a single source of truth — the script — so this skill does NOT pass
   # --outcome-file. Step 8 recomputes the same path from the same $CHANGE_NAME
   # to read the outcome across separate Bash tool calls.
   # Why deterministic, not $$-$(date +%s): a random suffix cannot be recomputed
   # in a second shell, which breaks the Step 7 → Step 8 handoff (R4 verify
   # R4-S1 finding). The change name is the skill's primary input — always known
   # to Step 8 — so the derived path IS recoverable.
   # 7a. Dry run (#405): resolves the issue exactly as the real run will, and keeps the
   # comment body and that issue for review in a private directory. Stderr names the file
   # (~/.cache/idd/spectra-archive/body-$CHANGE_NAME.md) and the issue it chose with its
   # title ("issue for review: ..."). Nothing is posted.
   bash "${REPO_ROOT}/.claude/scripts/spectra-archive-post-ic.sh" \
       --change-name "$CHANGE_NAME" \
       --archive-dir "$ARCHIVE_DIR" \
       --spec-deltas "$SPEC_DELTAS" \
       --dry-run
   POST_IC_EXIT=$?
   ```

   **7b. Review the body before it is posted (#405)**: read
   `~/.cache/idd/spectra-archive/body-$CHANGE_NAME.md` and run the privacy self-review of
   [`plugins/issue-driven-dev/rules/privacy-scrubbing.md`](../../../plugins/issue-driven-dev/rules/privacy-scrubbing.md)
   on it, then resolve the level the rule defines for the target repository (third-party
   `enforce`, your own public repository `warn`, private `light`). The `tasks.md` lines are
   copied into the comment as they are, so this is where third-party names or
   unpublished details would be caught. If the review finds something, do not post: tell
   the user what and where.

   Check the issue too: read the title 7a printed against this change's `proposal.md`. The
   script cannot tell that a number is this change's issue (a squash, a commit that swept
   several changes, a reused change name all mislead it), so this check is what approves
   it. If it is another issue, re-run 7a with `--linked-issue <N>` (one of the candidates)
   or `--force-linked-issue <N>`, and review again. If the change has no issue, skip 7c and
   report **not posted (no linked issue)** in Step 8.

   **7c. Post**: run the same command without `--dry-run`, adding
   `--scrub-attested <level>` and `--linked-issue <N>` for the issue 7b confirmed (or the
   `--force-linked-issue <N>` 7a used). The script refuses to post without either: it cannot
   review text or tell which issue is right itself;
   a level below the repository's own is refused (review again at that level), and at
   `enforce` it does not post at all. It also composes the body again and posts only if
   the body, the repository and the issue are the ones 7a kept: if `tasks.md` changed,
   the arguments or `--gh-repo` differ, or detection now resolves another issue, it posts
   nothing and asks for 7a and 7b again. The date in the body is the archive's own (its
   directory name), so a review that crosses midnight UTC still matches.

   **Exit codes**:

   | Exit | Meaning | Agent action |
   |------|---------|--------------|
   | `0` | Success or normal skip (posted / none / idempotent / unsafe-name / generic failure) | Read outcome from the derived outcome file (see Step 8), proceed to Step 8 |
   | `2` | Usage error (missing args, unsafe `--outcome-file` path, or a `--scrub-attested` value other than light / warn / enforce) | Skill bug — fix invocation |
   | `64` | Dependency missing (python3) | Surface to user; archive itself succeeded; manual retry after install |
   | `75` | A person must choose: several candidates, or one that neither a `GitHub-side tracker` nor the commits confirm (see below); the outcome says why. If none of them is this change's issue and it has none, skip 7c (**not posted (no linked issue)**) | **AskUserQuestion required** — read `/tmp/spectra-archive-candidates.txt` for the candidate list, prompt user to pick canonical issue (show `#N + gh issue title` for each), then re-invoke script with `--linked-issue <chosen>` |

   **Stdout**: a single line that is either the IC comment URL, or one of the documented status messages (`(none — ...)`, `(skipped — ...)`, `(pending — ...)`, `(failed — ...)`). The same line is also written to the derived outcome file `/tmp/spectra-archive-ic-outcome-${CHANGE_NAME}.txt` for cross-Bash-call persistence (Step 8 reads from there).

   **What 7a proposes without listing alternatives (#405)**: exactly two cases. (1) A
   `**GitHub-side tracker**: #N` in `proposal.md` or `design.md`, in that form and outside code,
   names one issue of this repository, and neither the commits nor an explicit reference name
   another. (2) The commits that touched the change name one issue as the commit rule writes it (a
   subject group `(#N)`, a body line `Refs #N`, or a squash body's `* subject (#N)` line), and no
   explicit reference (GitHub's closing keywords or ref/refs) in the change's text or in those
   commits names another. Everything else is offered with exit 75 and the reason. Either way 7b
   confirms the issue: four verify rounds showed that no rule here can approve it.

   **Multi-candidate flow (agent responsibility)**: in 7a, before the review. Re-run the dry run with `--linked-issue <chosen>`, review, then post with the same `--linked-issue`.

   ```bash
   if [ "$POST_IC_EXIT" = "75" ]; then
     # Read candidates + AskUserQuestion + re-invoke (script re-derives the outcome path from --change-name)
     CANDIDATES=$(cat /tmp/spectra-archive-candidates.txt)
     # For each candidate, fetch title via `gh issue view <N> --json title -q .title`
     # Then AskUserQuestion: "Multi-candidate detected: which is canonical?"
     # User picks → CHOSEN_ISSUE=<N>
     bash "${REPO_ROOT}/.claude/scripts/spectra-archive-post-ic.sh" \
         --change-name "$CHANGE_NAME" \
         --archive-dir "$ARCHIVE_DIR" \
         --spec-deltas "$SPEC_DELTAS" \
         --linked-issue "$CHOSEN_ISSUE" \
         --dry-run
   fi
   ```

   The agent (LLM-driven) handles the AskUserQuestion step — bash cannot prompt. The script validates `$CHOSEN_ISSUE` against the original candidate set on re-invoke.

   **What reaches GitHub (#405)**: the path to the archive in the comment is the path inside the repository, whatever form `--archive-dir` took; when no remote of that repository is the target repository, the conventional `openspec/changes/archive/<dir>` is used instead. Without `--gh-repo`, the target is resolved in the archive's repository, not in the cwd. The rest of the body (`--spec-deltas`, the `tasks.md` lines) is what 7b reviews. The comment is posted through `plugins/issue-driven-dev/scripts/gh-egress.sh`. If the gate refuses, the wrapper is missing or fails to run, permissions cannot be read, the level is below the repository's or is `enforce`, or the repository itself cannot be read during detection, nothing is posted and the outcome line starts with `(failed — ...)` and says why. Do not edit the archived files to get past a refusal (they are the audit record, and archive protection blocks the edit): post a corrected copy of the kept body by hand through `gh-egress.sh`.

   **Failure semantics**: any failure in Step 7 (gh auth lost, network, body too large, etc.) is recorded in the outcome file but does NOT abort the overall archive operation — the archive itself (Step 6) has already succeeded, and the archived change directory + main spec deltas are the canonical record. The GitHub comment is the convenience anchor for `/idd-close` supersession.

   **Testing**: run `.claude/scripts/tests/spectra-archive-post-ic/test.sh` to validate the script against fixture archive directories (covers explicit-marker / Refs-fallback / no-marker / multi-candidate / malicious-tasks.md / missing-tasks.md / unsafe-change-name / linked-issue-resolved / linked-issue-invalid / outcome-path-derivation / unsafe-outcome-file / prose-issue-detect / linked-issue-empty-candidates / word-boundary / cross-repo references / same-repo full references), plus scenario checks that need a real repository or a stubbed `gh` (paths, the review level, the egress gate, commit evidence, pull-request numbers). All fixtures and scenario checks pass.

8. **Display summary**

   Read the outcome from Step 7. Recompute the outcome file path the same way the
   script derived it — from the **identical** `$CHANGE_NAME` slug passed to
   `spectra archive` in Step 6. This works whether Step 7 + Step 8 ran in the same
   Bash invocation (var still in scope) OR in separate Bash calls (the formula is
   deterministic). **The `$CHANGE_NAME` here MUST be byte-identical to Step 7's —
   no typo, trailing whitespace, or case difference** — otherwise Step 8 reads a
   different path:

   ```bash
   # Recompute the same path the script derived in Step 7.
   # MUST use the identical $CHANGE_NAME slug — see contract note in Step 7.
   OUTCOME_FILE="/tmp/spectra-archive-ic-outcome-${CHANGE_NAME}.txt"

   if [ -f "$OUTCOME_FILE" ]; then
       IMPLEMENTATION_COMPLETE_POSTED=$(cat "$OUTCOME_FILE")
   else
       # Loud failure — NOT a quiet "(unknown)". A missing outcome file means
       # either Step 7 never ran, or $CHANGE_NAME drifted between Step 7 and
       # Step 8. Both are real errors the user must see.
       IMPLEMENTATION_COMPLETE_POSTED="⚠️  ERROR — outcome file not found: $OUTCOME_FILE (Step 7 did not run, or \$CHANGE_NAME drifted between Step 7 and Step 8)"
       echo "WARNING: spectra-archive Step 8 — outcome file missing: $OUTCOME_FILE" >&2
   fi
   ```

   Show archive completion summary including:
   - Change name
   - Schema that was used
   - Archive location
   - Spec sync status (synced / sync skipped / no delta specs)
   - **Implementation Complete posted to:** `$IMPLEMENTATION_COMPLETE_POSTED` — if it ends in
     `#issuecomment-DRY-RUN`, only 7a ran: write **not posted (dry run only)** and say why 7c
     did not run (#405)
   - Note about any warnings (incomplete artifacts/tasks)

**Output On Success**

```
## Archive Complete

**Change:** <change-name>
**Schema:** <schema-name>
**Archived to:** openspec/changes/archive/YYYY-MM-DD-<name>/
**Specs:** ✓ Synced to main specs

All artifacts complete. All tasks complete.
```

**Output On Success (No Delta Specs)**

```
## Archive Complete

**Change:** <change-name>
**Schema:** <schema-name>
**Archived to:** openspec/changes/archive/YYYY-MM-DD-<name>/
**Specs:** No delta specs

All artifacts complete. All tasks complete.
```

**Output On Success With Warnings**

```
## Archive Complete (with warnings)

**Change:** <change-name>
**Schema:** <schema-name>
**Archived to:** openspec/changes/archive/YYYY-MM-DD-<name>/
**Specs:** Sync skipped (user chose to skip)

**Warnings:**
- Archived with 2 incomplete artifacts
- Archived with 3 incomplete tasks
- Delta spec sync was skipped (user chose to skip)

Review the archive if this was not intentional.
```

**Output On Error (Archive Exists)**

```
## Archive Failed

**Change:** <change-name>
**Target:** openspec/changes/archive/YYYY-MM-DD-<name>/

Target archive directory already exists.

**Options:**
1. Rename the existing archive
2. Delete the existing archive if it's a duplicate
3. Wait until a different date to archive
```

**Guardrails**

- Always prompt for change selection if not provided
- Use artifact graph (spectra status --json) for completion checking
- Don't block archive on warnings - just inform and confirm
- Preserve .openspec.yaml when moving to archive (it moves with the directory)
- Show clear summary of what happened
- If sync is requested, use the Skill tool to invoke `spectra-sync-specs` (agent-driven)
- If delta specs exist, always run the sync assessment and show the combined summary before prompting
- If **AskUserQuestion tool** is not available, ask the same questions as plain text and wait for the user's response
- **Step 8 multi-candidate disambiguation**: if linked-issue detection (Fallback 1 explicit marker) returns multiple distinct `#N` values, MUST prompt user via AskUserQuestion to pick the canonical one — never auto-pick to avoid posting to the wrong issue
- **Step 8 silent skip on no linked issue**: do not warn or prompt; not all archives have GitHub trackers (legacy archives, design-only changes). Reflect skip reason in Step 7 summary line
