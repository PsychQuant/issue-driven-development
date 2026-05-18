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

7. **Post `## Implementation Complete` to linked GitHub issue (v1.1+, PsychQuant/issue-driven-development#56)**

   **Purpose**: ensures `/idd-close` Step 0 supersession gate triggers for Spectra-path issues, removing the need for manual retroactive Implementation Complete synthesis. The auto-posted comment is the canonical anchor that `## Implementation Complete > ### Checklist 全 - [x]` supersession logic recognizes.

   **Skip silently** when no linked GitHub issue is detectable — not all changes have GitHub tracker counterparts. Step 8 (Display summary, immediately after this step) reflects the outcome.

   **Single self-contained bash block** — all detection, idempotent guard, body composition, post-comment, and variable carry MUST run in one shell invocation. Variables MUST flow through explicit `if/elif/else` branches; do NOT split into multiple fenced blocks. Each branch SHALL set `IMPLEMENTATION_COMPLETE_POSTED` exactly once. Multi-candidate disambiguation MUST be deferred to agent-level AskUserQuestion (bash cannot prompt) by writing candidate list to a known path; the agent reads the path, prompts, then re-invokes this step with the resolved value via `LINKED_ISSUE_RESOLVED=<N>` env var (subsequent invocation skips detection if env var set).

   ```bash
   # ── Initialization (defaults — readable by Step 8 regardless of which branch fires) ──
   IMPLEMENTATION_COMPLETE_POSTED="(unknown — Step 7 did not complete)"

   # ── Allowlist guard: $CHANGE_NAME ──
   # Prevents shell injection via change names containing $(...), backticks, or whitespace.
   # Spectra CLI already constrains names to slug-safe characters; this is defense-in-depth.
   if ! [[ "$CHANGE_NAME" =~ ^[A-Za-z0-9_-]+$ ]]; then
       IMPLEMENTATION_COMPLETE_POSTED="(skipped — change name contains unsafe characters: $CHANGE_NAME)"
   else
       # ── GH_REPO resolution (hard-fail if empty — wrong-repo post is silent data corruption) ──
       GH_REPO=$(gh repo view --json nameWithOwner -q .nameWithOwner 2>/dev/null)
       if [ -z "$GH_REPO" ]; then
           IMPLEMENTATION_COMPLETE_POSTED="(failed — cannot resolve GitHub repo: gh repo view returned empty; check cwd is a git repo with remote)"
       else
           ARCHIVE_DIR="openspec/changes/archive/$(date +%Y-%m-%d)-${CHANGE_NAME}"
           ARCHIVE_BASENAME=$(basename "$ARCHIVE_DIR")

           # ── Step 7.1: Detect linked issue (3-fallback) with multi-candidate awareness ──
           # All fallbacks emit candidate set (sort -u); single-candidate auto-uses,
           # multi-candidate writes /tmp/spectra-archive-candidates.txt and signals agent.

           # Fallback 1: explicit **GitHub-side tracker** marker
           CANDIDATES=$(grep -hoE '\*\*GitHub-side tracker\*\*[^#]*#[0-9]+' \
               "$ARCHIVE_DIR/proposal.md" "$ARCHIVE_DIR/design.md" 2>/dev/null \
               | grep -oE '#[0-9]+' | tr -d '#' | sort -u)

           # Fallback 2: Refs / Closes / Fixes pattern (only if F1 yielded nothing)
           if [ -z "$CANDIDATES" ]; then
               CANDIDATES=$(grep -rhoE '(Refs|Closes|Fixes) #[0-9]+' \
                   "$ARCHIVE_DIR"/*.md 2>/dev/null \
                   | grep -oE '#[0-9]+' | tr -d '#' | sort -u)
           fi

           # Fallback 3: recent commits — use --follow on the archived path only
           # (Step 6 already moved the source dir, so the pre-archive path doesn't exist
           # as a tracked file anymore; --follow on the archived path traces history through
           # the rename. The pre-archive path argument is intentionally omitted.)
           if [ -z "$CANDIDATES" ]; then
               CANDIDATES=$(git log --follow --oneline -50 -- "$ARCHIVE_DIR" 2>/dev/null \
                   | grep -oE '#[0-9]+' | tr -d '#' | sort -u)
           fi

           # Use $LINKED_ISSUE_RESOLVED env var if agent re-invoked after multi-candidate prompt
           if [ -n "$LINKED_ISSUE_RESOLVED" ]; then
               LINKED_ISSUE="$LINKED_ISSUE_RESOLVED"
               # Validate resolved value is in the original candidate set
               if ! echo "$CANDIDATES" | grep -qx "$LINKED_ISSUE"; then
                   IMPLEMENTATION_COMPLETE_POSTED="(failed — LINKED_ISSUE_RESOLVED=$LINKED_ISSUE not in candidate set: $CANDIDATES)"
                   LINKED_ISSUE=""
               fi
           else
               CANDIDATE_COUNT=$(echo "$CANDIDATES" | grep -c .)
               case "$CANDIDATE_COUNT" in
                   0)
                       LINKED_ISSUE=""
                       IMPLEMENTATION_COMPLETE_POSTED="(none — no linked issue detected)"
                       ;;
                   1)
                       LINKED_ISSUE="$CANDIDATES"
                       ;;
                   *)
                       # Multi-candidate: write candidate list + abort this run, signal agent to prompt
                       echo "$CANDIDATES" > /tmp/spectra-archive-candidates.txt
                       LINKED_ISSUE=""
                       IMPLEMENTATION_COMPLETE_POSTED="(pending — $CANDIDATE_COUNT candidates detected, agent must AskUserQuestion to pick canonical, then re-invoke with LINKED_ISSUE_RESOLVED=<N>)"
                       ;;
               esac
           fi

           # ── Step 7.2: Idempotent guard + Step 7.3 post (only if LINKED_ISSUE resolved) ──
           if [ -n "$LINKED_ISSUE" ]; then
               # Idempotent sentinel includes archive directory name — distinguishes
               # this archive's post from other archives' posts on same issue.
               SENTINEL="auto-posted by spectra-archive for ${ARCHIVE_BASENAME}"
               ALREADY_POSTED=$(gh issue view "$LINKED_ISSUE" --repo "$GH_REPO" --json comments \
                   --jq '.comments[].body' 2>/dev/null \
                   | grep -F "$SENTINEL" | wc -l | tr -d ' ')

               if [ "$ALREADY_POSTED" -gt 0 ]; then
                   IMPLEMENTATION_COMPLETE_POSTED="(skipped — already auto-posted for $ARCHIVE_BASENAME to #${LINKED_ISSUE})"
               else
                   # ── Step 7.3: Compose comment body (concrete, deterministic) ──
                   # Portable mktemp: create temp file then rename with .md suffix.
                   # macOS BSD mktemp doesn't accept extension after XXXXXX template.
                   TMP_BODY=$(mktemp /tmp/spectra-archive-ic.XXXXXX)
                   BODY_FILE="${TMP_BODY}.md"
                   mv "$TMP_BODY" "$BODY_FILE"

                   ARCHIVE_DATE=$(date -u +%Y-%m-%d)
                   SPEC_DELTAS="${SPEC_DELTAS:-(see archived change directory)}"

                   # Derive checklist from archived tasks.md, FILTERING to - [x] only.
                   # Rationale: /idd-close Step 0 supersession requires all items - [x] to
                   # trigger. Including - [~] / - [-] items would defeat the purpose. The
                   # archived tasks.md remains the canonical audit trail for skipped tasks.
                   TASKS_FILE="$ARCHIVE_DIR/tasks.md"
                   if [ -f "$TASKS_FILE" ]; then
                       # Extract completed tasks only; preserve first line of each task description
                       CHECKLIST_BODY=$(grep -E '^- \[x\] ' "$TASKS_FILE" || true)
                   else
                       CHECKLIST_BODY="- [x] (no tasks.md in archived change directory)"
                   fi

                   # Build body using single-quoted heredoc + parameter substitution via sed
                   # (avoids backtick re-evaluation inside tasks.md content)
                   cat > "$BODY_FILE" <<'BODY_TEMPLATE'
## Implementation Complete (auto-posted by spectra-archive for __ARCHIVE_BASENAME__)

> Auto-posted by `/spectra-archive` after archiving `__CHANGE_NAME__`. This comment is the canonical Implementation Complete anchor for `/idd-close` Step 0 supersession gate.

**Spectra change**: `__ARCHIVE_DIR__/`
**Spec deltas applied**: __SPEC_DELTAS__
**Auto-posted**: __ARCHIVE_DATE__

### Checklist

__CHECKLIST_BODY__

> Note: only completed (`- [x]`) tasks shown. For skipped (`- [~]`) and won't-fix (`- [-]`) items with reasons, see archived `__ARCHIVE_DIR__/tasks.md` — the canonical audit trail.

---

*The canonical record of what was implemented is the archived change directory + main spec at `openspec/specs/<capability>/spec.md`. This comment exists to satisfy `/idd-close` Step 0 supersession gate.*
BODY_TEMPLATE

                   # Substitute placeholders (use | as sed delimiter to avoid / collisions in paths)
                   sed -i.bak \
                       -e "s|__ARCHIVE_BASENAME__|$ARCHIVE_BASENAME|g" \
                       -e "s|__CHANGE_NAME__|$CHANGE_NAME|g" \
                       -e "s|__ARCHIVE_DIR__|$ARCHIVE_DIR|g" \
                       -e "s|__SPEC_DELTAS__|$SPEC_DELTAS|g" \
                       -e "s|__ARCHIVE_DATE__|$ARCHIVE_DATE|g" \
                       "$BODY_FILE"
                   rm -f "${BODY_FILE}.bak"

                   # CHECKLIST_BODY may contain multiline content — substitute separately via file
                   # (sed -i with multiline replacement is tricky across BSD/GNU; safer to use python or awk)
                   python3 -c "
import sys
with open('$BODY_FILE', 'r') as f:
    content = f.read()
checklist = '''$CHECKLIST_BODY'''
content = content.replace('__CHECKLIST_BODY__', checklist)
with open('$BODY_FILE', 'w') as f:
    f.write(content)
" || {
                       IMPLEMENTATION_COMPLETE_POSTED="(failed — checklist substitution errored)"
                       rm -f "$BODY_FILE"
                   }

                   # Body size sanity check (GitHub comment limit 65536 chars)
                   if [ -f "$BODY_FILE" ]; then
                       BODY_SIZE=$(wc -c < "$BODY_FILE" | tr -d ' ')
                       if [ "$BODY_SIZE" -gt 60000 ]; then
                           IMPLEMENTATION_COMPLETE_POSTED="(failed — body size ${BODY_SIZE} exceeds 60KB safety limit)"
                           rm -f "$BODY_FILE"
                       else
                           # ── Step 7.4: Post comment ──
                           # Capture URL; on failure, $COMMENT_URL is empty and parameter expansion
                           # ${COMMENT_URL:-fallback} carries the failure message through.
                           COMMENT_URL=$(gh issue comment "$LINKED_ISSUE" --repo "$GH_REPO" --body-file "$BODY_FILE" 2>/dev/null)
                           IMPLEMENTATION_COMPLETE_POSTED="${COMMENT_URL:-(failed — gh issue comment errored; archive itself succeeded)}"
                           rm -f "$BODY_FILE"
                       fi
                   fi
               fi
           fi
       fi
   fi

   # ── End of Step 7 ──
   # IMPLEMENTATION_COMPLETE_POSTED is now guaranteed to be set to one of:
   #   - A GitHub comment URL on success
   #   - "(none — ...)" on legitimate skip (no linked issue)
   #   - "(skipped — already auto-posted for <archive> to #N)" on idempotent hit
   #   - "(skipped — change name contains unsafe characters: ...)" on allowlist fail
   #   - "(pending — N candidates detected, agent must AskUserQuestion ...)" on multi-candidate
   #   - "(failed — ...)" on any error path
   # Step 8 (next) reads this variable.
   ```

   **Failure-mode**: if any sub-step fails (gh auth lost, issue locked, body too large, etc.), archive itself is unaffected — the archived change directory + main spec deltas remain the canonical record. The GitHub comment is the convenience anchor for `/idd-close`. Failures are recorded in `IMPLEMENTATION_COMPLETE_POSTED` for Step 8 summary; user can manually retry by re-running `spectra archive <name>` (idempotent guard prevents duplicate when post succeeds).

   **Multi-candidate flow (agent responsibility)**:
   1. Bash detects ≥2 candidates → writes `/tmp/spectra-archive-candidates.txt` + sets `IMPLEMENTATION_COMPLETE_POSTED="(pending — ...)"`
   2. Agent reads `/tmp/spectra-archive-candidates.txt`, builds AskUserQuestion with each candidate's issue title (via `gh issue view <N> --json title -q .title`)
   3. User picks one; agent re-invokes this step with `LINKED_ISSUE_RESOLVED=<N>` env var
   4. Bash validates the resolved value is in the original candidate set + proceeds to idempotent guard + post

8. **Display summary**

   Show archive completion summary including:
   - Change name
   - Schema that was used
   - Archive location
   - Spec sync status (synced / sync skipped / no delta specs)
   - **Implementation Complete posted to:** `$IMPLEMENTATION_COMPLETE_POSTED` (set by Step 7 above; carries URL on success or one of the documented skip/failure messages)
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
