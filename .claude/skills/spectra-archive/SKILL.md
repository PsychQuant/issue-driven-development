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

7. **Post `## Implementation Complete` to linked GitHub issue (v1.2+, PsychQuant/issue-driven-development#56)**

   **Purpose**: ensures `/idd-close` Step 0 supersession gate triggers for Spectra-path issues, removing the need for manual retroactive Implementation Complete synthesis.

   **Delegated to executable helper script** `.claude/scripts/spectra-archive-post-ic.sh` (with unit tests at `.claude/scripts/tests/spectra-archive-post-ic/`). The script is the source of truth — this skill calls it and reads the outcome. Behavior contract (detection / idempotent guard / safe body composition / multi-candidate handling) lives in the script + its tests, not in skill prose. This separation was introduced after R2 verify found that prose-with-illustrative-bash had structural defects (variable persistence across Bash tool calls, Python3 RCE via shell-string interpolation, etc.) — see PsychQuant/issue-driven-development#56 R2 verify report.

   **Invocation**:

   ```bash
   ARCHIVE_DIR="openspec/changes/archive/$(date +%Y-%m-%d)-${CHANGE_NAME}"

   # Spec deltas list from Step 6 (e.g. "idd-all-chain, idd-spawn-manifest");
   # falls back to descriptive placeholder if not provided.
   SPEC_DELTAS="${SPEC_DELTAS:-(see archived change directory)}"

   bash .claude/scripts/spectra-archive-post-ic.sh \
       --change-name "$CHANGE_NAME" \
       --archive-dir "$ARCHIVE_DIR" \
       --spec-deltas "$SPEC_DELTAS"
   POST_IC_EXIT=$?
   ```

   **Exit codes**:

   | Exit | Meaning | Agent action |
   |------|---------|--------------|
   | `0` | Success or normal skip (posted / none / idempotent / unsafe-name / generic failure) | Read outcome from `/tmp/spectra-archive-ic-outcome.txt`, proceed to Step 8 |
   | `2` | Usage error (missing args) | Skill bug — fix invocation |
   | `64` | Dependency missing (python3) | Surface to user; archive itself succeeded; manual retry after install |
   | `75` | Multi-candidate detected | **AskUserQuestion required** — read `/tmp/spectra-archive-candidates.txt` for the candidate list, prompt user to pick canonical issue (show `#N + gh issue title` for each), then re-invoke script with `--linked-issue <chosen>` |

   **Stdout**: a single line that is either the IC comment URL, or one of the documented status messages (`(none — ...)`, `(skipped — ...)`, `(pending — ...)`, `(failed — ...)`). Also written to `/tmp/spectra-archive-ic-outcome.txt` for cross-Bash-call persistence (Step 8 reads from there).

   **Multi-candidate flow (agent responsibility)**:

   ```bash
   if [ "$POST_IC_EXIT" = "75" ]; then
     # Read candidates + AskUserQuestion + re-invoke
     CANDIDATES=$(cat /tmp/spectra-archive-candidates.txt)
     # For each candidate, fetch title via `gh issue view <N> --json title -q .title`
     # Then AskUserQuestion: "Multi-candidate detected: which is canonical?"
     # User picks → CHOSEN_ISSUE=<N>
     bash .claude/scripts/spectra-archive-post-ic.sh \
         --change-name "$CHANGE_NAME" \
         --archive-dir "$ARCHIVE_DIR" \
         --spec-deltas "$SPEC_DELTAS" \
         --linked-issue "$CHOSEN_ISSUE"
   fi
   ```

   The agent (LLM-driven) handles the AskUserQuestion step — bash cannot prompt. The script validates `$CHOSEN_ISSUE` against the original candidate set on re-invoke.

   **Failure semantics**: any failure in Step 7 (gh auth lost, network, body too large, etc.) is recorded in the outcome file but does NOT abort the overall archive operation — the archive itself (Step 6) has already succeeded, and the archived change directory + main spec deltas are the canonical record. The GitHub comment is the convenience anchor for `/idd-close` supersession.

   **Testing**: run `.claude/scripts/tests/spectra-archive-post-ic/test.sh` to validate the script against fixture archive directories (covers explicit-marker / Refs-fallback / no-marker / multi-candidate / malicious-tasks.md / missing-tasks.md / unsafe-change-name / linked-issue-resolved / linked-issue-invalid). All 9 fixtures pass as of v1.2.

8. **Display summary**

   Read the outcome from Step 7 (the helper script writes to `/tmp/spectra-archive-ic-outcome.txt` — persistent across Bash tool invocations):

   ```bash
   IMPLEMENTATION_COMPLETE_POSTED=$(cat /tmp/spectra-archive-ic-outcome.txt 2>/dev/null \
       || echo "(unknown — outcome file missing)")
   ```

   Show archive completion summary including:
   - Change name
   - Schema that was used
   - Archive location
   - Spec sync status (synced / sync skipped / no delta specs)
   - **Implementation Complete posted to:** `$IMPLEMENTATION_COMPLETE_POSTED`
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
