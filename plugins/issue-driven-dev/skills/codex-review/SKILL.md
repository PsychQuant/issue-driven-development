---
name: codex-review
description: |
  Call OpenAI Codex CLI to verify issue completion against uncommitted changes.
  Uses gpt-5.4 by default. Catches missed items, incomplete renames, unaddressed requirements.
  Use when: code changes are ready, before committing, to verify against issue requirements.
argument-hint: "#issue [effort] e.g. '#42' or '#100 high'"
allowed-tools:
  - Bash(codex:*)
  - Bash(git:*)
  - Bash(gh:*)
  - Bash(mktemp:*)
  - Bash(cat:*)
  - Bash(rm:*)
  - Read
  - Grep
  - AskUserQuestion
---

# /codex-review — Issue Completion Verification

Use OpenAI Codex CLI to verify that a GitHub issue's requirements are **fully implemented** in uncommitted changes.

## Configuration

This skill reads settings from `.claude/issue-driven-dev.local.md` frontmatter:

```yaml
---
github_repo: "owner/repo"           # GitHub repo for gh issue view
github_owner: "owner"               # For project board linking
attachments_release: "attachments"   # Release tag for image uploads
---
```

If no config found, the skill will ask the user for the repo on first use.

## Arguments

Format: `/issue-driven-dev:codex-review #issue [effort] [custom instructions]`

- `#NNN` — **recommended** (fetches issue requirements for targeted review)
- Omit `#NNN` for a general code review of uncommitted changes

### Model

**Fixed: `gpt-5.4`** (~1M context window). No model selection needed.

### Speed modifier: `fast`

Append `fast` to enable `service_tier = "fast"` (lower latency, same model).

### Effort levels

| Level | When to use |
|-------|-------------|
| `low` | Quick sanity check, small diffs (<50 lines) |
| `medium` | Normal review, moderate diffs (50-200 lines) |
| `high` | Thorough review, large diffs (200-500 lines) |
| `xhigh` | Deep review, catch everything **(default)** |

### Effort auto-adjustment

When effort is not explicitly specified, auto-select based on diff size:

```
< 50 lines changed   → medium
50-200 lines changed  → high
> 200 lines changed   → xhigh (default)
```

## Execution Steps

### Step 1: Parse Arguments

Extract issue number, effort, fast modifier, and custom instructions.

### Step 2: Read Config

```bash
# Read repo from .local.md config
CONFIG_FILE=".claude/issue-driven-dev.local.md"
```

If config doesn't exist, ask user for `github_repo` and create the config file.

### Step 3: Fetch Issue Context (if #NNN provided)

```bash
gh issue view NNN --repo $GITHUB_REPO --json title,body,labels
```

### Step 4: Check for Uncommitted Changes

```bash
git status --short
git diff --stat
```

If no changes, inform user and stop.

### Step 5: Run Codex Review

**Mode A: Issue-focused (with #NNN)** — diff embedded in prompt via stdin:

```bash
PROMPT_FILE=$(mktemp /tmp/codex_review_XXXXX)

{
  echo "You are reviewing code changes for GitHub Issue #NNN: <title>"
  echo ""
  echo "Issue requirements:"
  echo "<body>"
  echo ""
  echo "YOUR PRIMARY TASK:"
  echo "1. Go through EACH requirement in the issue"
  echo "2. For each requirement, determine if it is addressed"
  echo "3. List: FULLY addressed, PARTIALLY addressed, NOT addressed"
  echo "4. Flag unrelated changes"
  echo ""
  echo "=== UNCOMMITTED CHANGES ==="
  git diff
  git diff --cached
} > "$PROMPT_FILE"

codex review -c 'model="gpt-5.4"' -c 'model_reasoning_effort="<effort>"' - < "$PROMPT_FILE"
rm "$PROMPT_FILE"
```

**Mode B: Generic (no #NNN)** — use --uncommitted:

```bash
codex review -c 'model="gpt-5.4"' -c 'model_reasoning_effort="<effort>"' --uncommitted
```

**Important**:
- `codex review` uses `-c 'model="..."'` not `-m`
- `--uncommitted` and `[PROMPT]` (stdin) are mutually exclusive
- `-c 'service_tier="fast"'` for fast mode

### Step 6: Present Results

Display completion status: X/Y requirements done, effort used, findings.

### Step 7: Offer Follow-up

- If findings exist: "要繼續修正嗎？"
- If all passed: "全部通過！要 commit 嗎？"

## Notes

- Codex CLI authenticates via ChatGPT Pro account (no API key needed)
- `plotly_click` is in the defaults, so no explicit `event_register()` needed
- Output includes token usage for cost awareness
