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

7. **Display summary**

   Show archive completion summary including:
   - Change name
   - Schema that was used
   - Archive location
   - Spec sync status (synced / sync skipped / no delta specs)
   - **Implementation Complete posted to:** `#N` (from Step 8) or `(none — no linked issue detected)` if Step 8 skipped
   - Note about any warnings (incomplete artifacts/tasks)

8. **Post `## Implementation Complete` to linked GitHub issue (v1.1+, PsychQuant/issue-driven-development#56)**

   **Purpose**: ensures `/idd-close` Step 0 supersession gate triggers for Spectra-path issues, removing the need for manual retroactive Implementation Complete synthesis. The auto-posted comment is the canonical anchor that `## Implementation Complete > ### Checklist 全 - [x]` supersession logic recognizes.

   **Skip silently** when no linked GitHub issue is detectable — not all changes have GitHub tracker counterparts. Step 7 summary line reflects the outcome.

   **8.1 Detect linked issue number** (3-fallback chain):

   ```bash
   ARCHIVE_DIR="openspec/changes/archive/$(date +%Y-%m-%d)-${CHANGE_NAME}"
   LINKED_ISSUE=""

   # Fallback 1: explicit **GitHub-side tracker** marker (preferred convention)
   LINKED_ISSUE=$(grep -hoE '\*\*GitHub-side tracker\*\*[^#]*#[0-9]+' \
       "$ARCHIVE_DIR/proposal.md" "$ARCHIVE_DIR/design.md" 2>/dev/null \
       | grep -oE '#[0-9]+' | head -1 | tr -d '#')

   # Fallback 2: Refs / Closes / Fixes pattern in any archive artifact
   if [ -z "$LINKED_ISSUE" ]; then
       LINKED_ISSUE=$(grep -rhoE '(Refs|Closes|Fixes) #[0-9]+' \
           "$ARCHIVE_DIR"/*.md 2>/dev/null \
           | grep -oE '#[0-9]+' | head -1 | tr -d '#')
   fi

   # Fallback 3: recent commits (last 50) touching the change directory
   if [ -z "$LINKED_ISSUE" ]; then
       LINKED_ISSUE=$(git log --oneline -50 -- "openspec/changes/${CHANGE_NAME}" "$ARCHIVE_DIR" 2>/dev/null \
           | grep -oE '#[0-9]+' | head -1 | tr -d '#')
   fi

   # Final silent skip
   if [ -z "$LINKED_ISSUE" ]; then
       IMPLEMENTATION_COMPLETE_POSTED="(none — no linked issue detected)"
       # Skip rest of Step 8 — proceed to Step 7 summary
   fi
   ```

   **Multi-candidate disambiguation**: if Fallback 1 returned multiple distinct `#N` values (e.g. proposal mentions both `**GitHub-side tracker**: #44` AND `**GitHub-side tracker**: #46`), use AskUserQuestion to let the user pick the canonical one — **never auto-pick** to avoid posting to the wrong issue.

   **8.2 Idempotent guard** — skip if same archive already auto-posted:

   ```bash
   GH_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
   ALREADY_POSTED=$(gh issue view "$LINKED_ISSUE" --repo "$GH_REPO" --json comments \
       --jq '.comments[].body' 2>/dev/null \
       | grep -c "auto-posted by spectra-archive" || echo 0)

   if [ "$ALREADY_POSTED" -gt 0 ]; then
       IMPLEMENTATION_COMPLETE_POSTED="(skipped — already auto-posted to #${LINKED_ISSUE})"
       # Skip rest of Step 8
   fi
   ```

   **8.3 Compose Implementation Complete comment body**:

   Build a comment that derives its checklist from the archived `tasks.md`. Each `- [x]` / `- [~]` / `- [-]` task → corresponding marker here. The auto-posted comment is intentionally short — the canonical record of *what was implemented* lives in the archived change directory and the main spec, not in the GitHub comment.

   Template:

   ```markdown
   ## Implementation Complete (auto-posted by spectra-archive YYYY-MM-DD)

   > Auto-posted by `/spectra-archive` after archiving `<change-name>`. This comment is the canonical Implementation Complete anchor for `/idd-close` supersession.

   **Spectra change**: `openspec/changes/archive/YYYY-MM-DD-<change-name>/`
   **Spec deltas applied**: <capability names from spectra archive output, comma-separated>

   ### Checklist

   <derived from archived tasks.md: each top-level task line, keeping its - [x] / - [~] / - [-] marker and first-line description only;
   skipped/won't-fix tasks must preserve their reason annotation>

   ---

   *The canonical record of what was implemented is the archived change directory + main spec at `openspec/specs/<capability>/spec.md`. This comment exists to satisfy `/idd-close` Step 0 supersession gate.*
   ```

   Build with bash + jq + sed (avoid shell escape pitfalls — write body to temp file, post via `--body-file`).

   **8.4 Post comment**:

   ```bash
   BODY_FILE=$(mktemp -t spectra-archive-ic.XXXXXX.md)
   # ... build body into $BODY_FILE ...

   COMMENT_URL=$(gh issue comment "$LINKED_ISSUE" --repo "$GH_REPO" --body-file "$BODY_FILE") || {
       IMPLEMENTATION_COMPLETE_POSTED="(failed — gh issue comment errored; check stderr)"
       rm -f "$BODY_FILE"
       # Continue to Step 7 summary; archive itself already succeeded — don't abort
   }

   rm -f "$BODY_FILE"
   IMPLEMENTATION_COMPLETE_POSTED="$COMMENT_URL"
   ```

   **Failure-mode**: if `gh issue comment` fails (auth / network / issue locked / issue deleted), archive itself is unaffected — record the failure in Step 7 summary and continue. The archived change directory + main spec deltas are the canonical record; the GitHub comment is the convenience anchor for `/idd-close`.

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
