---
name: issue
description: |
  Create and manage well-documented GitHub Issues with original text quotes,
  image attachments, and mandatory closing comments. Enforces issue-driven
  development discipline. Use when: reporting bugs, tracking requests, or
  any work that needs formal tracking.
argument-hint: "[description or path to .docx]"
allowed-tools:
  - Bash(gh:*)
  - Bash(cp:*)
  - Bash(ls:*)
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
---

# /issue — GitHub Issue Management

Create and manage issues in GitHub Issues with enforced documentation standards.

## Configuration

This skill reads settings from `.claude/issue-driven-dev.local.md` frontmatter:

```yaml
---
github_repo: "owner/repo"
github_owner: "owner"
attachments_release: "attachments"
---
```

## When to Use

- User reports a bug/problem
- User asks to open or update an issue
- Work needs formal tracking

## Execution Steps

### Step 0: Read Source Document (if .docx)

When input is a `.docx` file, use `che-word-mcp` MCP tools:

```
mcp__che-word-mcp__read_docx(path)
mcp__che-word-mcp__extract_images(path)
```

### Step 1: Gather Required Info

Ask user if missing:
1. **Title**
2. **Priority** (P0 / P1 / P2 / P3)
3. **Description** (repro, expected, actual, impact)

### Step 2: Create GitHub Issue

```bash
gh issue create \
  --repo $GITHUB_REPO \
  --title "<title>" \
  --body "<markdown body>" \
  --label "bug"
```

Body template:

```markdown
## Problem

> **Original text**:
> 「...exact original text from source document...」
> — Source: {document_name}

{Plain language interpretation}

## Expected
...

## Actual
...

## Impact
...
```

> **CRITICAL**: When issues come from a source document, you MUST include the **exact original text** quoted verbatim. AI summaries lose precision — the original text is the only thing that won't drift.

### Step 2.1: Attach Images (If Applicable)

1. Upload to the `attachments` release:
```bash
gh release upload $ATTACHMENTS_RELEASE <image_path> \
  --repo $GITHUB_REPO --clobber
```

2. Naming: `issue_<number>_<description>.png`

3. Workflow (issue number not known until creation):
   1. Create issue first
   2. Upload image with issue number
   3. Edit issue body to add image link

### Step 3: Confirm Back to User

Return: issue number, URL, labels used.

## Source Document Rule (CRITICAL)

### One Point = One Issue

- **Every point** from a source document gets its own issue
- **Never merge** — even similar topics get separate issues
- **Never skip** — duplicates can be closed later, but missing issues = forgotten customer feedback
- After processing, verify: `document points count == created issues count`

## Closing an Issue (MANDATORY)

**Never close without a closing comment.**

### Closing Comment Format

```markdown
## Closing Summary

### Problem
{what was found, scope of impact}

### Solution
{what was changed, key logic}

### Verification
{how it was verified: codex-review, testing, screenshots}

### Related Commits
{commit hash or link}
```

### Workflow

```
1. Create issue
2. Implement code changes
3. /issue-driven-dev:codex-review #NNN    ← verify
4. Findings? → fix → re-verify
5. All passed? → commit with #NNN reference
6. gh issue comment #NNN                   ← closing comment
7. gh issue close #NNN
```

## Post-Implementation Verification

After implementing, run `/issue-driven-dev:codex-review #NNN` to verify all requirements are met. **Never commit with unresolved findings.**

For UI-visible changes, also run runtime verification (app testing, E2E tests).

## Notes

- Source of truth is GitHub issue status
- IC_R009: every commit references an issue, every issue has a commit
- Closing comment takes 3 minutes to write, saves 30 minutes finding "what was done" later
