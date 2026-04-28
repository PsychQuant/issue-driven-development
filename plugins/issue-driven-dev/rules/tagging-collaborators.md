---
name: tagging-collaborators
description: Mandatory protocol when any IDD skill needs to mention (@-tag) people on GitHub
---

# Tagging Collaborators Rule

**The protocol every IDD skill MUST follow when posting `@xxx` mentions to GitHub.**

## Why this rule exists

Three observed failure modes when AI agents mention people:

1. **Hallucinated handles** — AI guesses `@JaneDoe` from a chat where the user said "tag Jane"; the actual GitHub login is `@jane-d-91` and the wrong account gets pinged.
2. **Display-name confusion** — AI tags `@Hau-Hung Yang` (the real-name field) instead of `@Hardy1Yang` (the login). GitHub does not notify on display names.
3. **Stale memory** — AI uses a handle from prior conversations or training data without verifying the user is still a collaborator on the target repo.

GitHub mentions are an irreversible side effect: the wrong person gets a notification, and you cannot undo it. This rule is mandatory, not advisory.

## The Protocol (5 steps, no skipping)

### Step 1: Detect intent

Trigger when any of these appear in the user request, skill arguments, or comment body:

- Explicit flag: `--mention <name>` / `--mention <name1>,<name2>`
- Natural language: "tag X", "@X", "ping X", "通知 X", "讓 X 知道", "cc X"
- Skill-specific: idd-issue / idd-comment / idd-close / etc. body contains `@` followed by an unverified token

If no tagging intent → skip the rest of this rule.

### Step 2: Fetch the real list (mandatory)

Before resolving any handle:

```bash
# Collaborators (anyone with repo access — outside collaborators included)
gh api repos/$OWNER/$REPO/collaborators --jq '.[] | {login, name, type}' \
  > /tmp/idd-collaborators.json

# Org members (in case the target is an org repo and the person is a member but not direct collaborator)
if [ "$OWNER_TYPE" = "Organization" ]; then
  gh api orgs/$OWNER/members --jq '.[] | {login}' \
    > /tmp/idd-org-members.json
fi

# Recent commit authors (fallback — for forked / public repos with no API access)
git log --pretty=format:'%an <%ae>' | sort -u > /tmp/idd-commit-authors.txt
```

**The combined set of these lists is the only source of truth for valid handles.** Never use:

- Handles from training data
- Handles from prior chat conversations
- Handles inferred from git config / email domains
- Handles from `~/.gitconfig` / `~/.ssh/config` / `gh auth status`

### Step 3: Resolve user input → @login

Apply fuzzy matching against the real list:

| User input | Match against | Resolution |
|------------|---------------|------------|
| `@hardy1yang` (with `@`) | login (case-insensitive) | exact match → use as-is |
| `Hardy1Yang` (no `@`) | login | exact match → prepend `@` |
| `Hardy` (partial) | login + name (substring) | search both fields |
| `Hau-Hung Yang` (display name) | name field → look up login | resolve to `@Hardy1Yang` |

Match outcomes:

- **1 unique match** → use it, but echo back to user one-liner: "Resolved 'Hardy' → `@Hardy1Yang` (Hau-Hung Yang)"
- **0 matches** → DO NOT guess. Use AskUserQuestion (Step 4) with the full list.
- **2+ matches** → ambiguous. Use AskUserQuestion (Step 4) with the matched subset.

### Step 4: AskUserQuestion fallback (when ambiguous or no match)

```
AskUserQuestion(
  question="Which person should be @-mentioned in #NNN?",
  header="Mention",
  multiSelect=true (if multiple people requested) else false,
  options=[
    {label: "@kiki830621", description: "che cheng — owner"},
    {label: "@Hardy1Yang", description: "Hau-Hung Yang — collaborator"},
    {label: "@PsychQuantClaw", description: "bot — usually skip"},
    {label: "Skip — don't tag anyone", description: "remove the mention"}
  ]
)
```

User picks from the **actual list**. The "Other" free-text option is fine for genuine outside contributors not in the API result, but the skill MUST then verify via `gh api users/<login>` before accepting.

### Step 5: Insert and verify

- Use `@login` (not display name, not email)
- Place mention on its own line or in a clear context (`cc @login` / `@login 想聽你的意見...`)
- Before `gh issue comment` / `gh issue create` / `gh issue edit`: grep the body for `@\w+` and confirm every match is in the resolved set.

```bash
# Verification step
for handle in $(grep -oE '@[A-Za-z0-9-]+' /tmp/comment-body.md | sort -u); do
  login=${handle#@}
  if ! jq -e ".[] | select(.login == \"$login\")" /tmp/idd-collaborators.json > /dev/null; then
    echo "ERROR: @$login not in collaborator list. Aborting."
    exit 1
  fi
done
```

## Hard rules (no exceptions)

1. **Never guess.** If `gh api` fails (offline / rate-limited / private repo), abort the tagging — post the comment without the mention and tell the user "tagging skipped: API unavailable".
2. **Never use display names** as `@`-handles. GitHub notifications only work with logins.
3. **Always show the resolution** to the user: "Resolved 'Hardy' → `@Hardy1Yang`" — they can catch wrong matches before you post.
4. **Multi-mention = explicit list.** When the user says "tag both", enumerate. Don't assume "team" or "everyone".
5. **Bots are opt-out by default.** If a login looks like a bot (`*-bot`, `*Claw`, `dependabot`, `github-actions`), exclude unless user explicitly names it.

## Implementation contract for skill authors

Every IDD skill that posts to GitHub (`idd-issue`, `idd-comment`, `idd-diagnose`, `idd-implement`, `idd-verify`, `idd-close`, `idd-edit`, `idd-update`) MUST:

- Reference this rule in its Step 0 task list when a `--mention` flag is set OR when natural-language tagging intent is detected
- Resolve all handles via the protocol above BEFORE the body is finalized
- Refuse to post with unresolved `@xxx` tokens (treat as a hard error, not a warning)

Skills that accept a `--mention` flag (`idd-issue`, `idd-comment`):

```
--mention <login>             single mention
--mention <name1>,<name2>     multiple mentions, comma-separated
--mention-prompt              force AskUserQuestion menu (skip auto-resolve)
```

## Examples

### Good

```
User: "tag hardy in this issue"
Skill: [runs gh api repos/PsychQuant/contact-book/collaborators]
Skill: "Resolved 'hardy' → @Hardy1Yang (Hau-Hung Yang). Inserting in body."
Skill: [posts comment with @Hardy1Yang]
```

### Bad (would fail this rule)

```
User: "tag hardy"
Skill: [posts @Hardy directly without verification]   ← FAIL: no API call
Skill: [posts @hardy123 from training memory]         ← FAIL: hallucination
Skill: [posts @Hau-Hung Yang]                         ← FAIL: display name not login
```

## Related rules

- `sdd-integration.md` — when SDD work involves stakeholders, tagging follows this protocol
- `references/config-protocol.md` — `github_repo` resolution must precede the API call (need to know which repo's collaborators to fetch)
