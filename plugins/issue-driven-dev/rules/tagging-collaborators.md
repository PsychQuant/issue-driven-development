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
# One per-run scratch dir. Fixed names under the system temp directory are
# shared by every concurrent session and by every repo: two runs tagging in
# different repos read each other's collaborator list, and the mention gate
# below decides who gets notified from exactly these files. #288 mechanised the
# no-fixed-scratch-paths rule for idd-verify and this file was outside the scan
# it declared -- while idd-verify MANDATES this protocol, so the rule and its
# largest violation shipped together.
TAG_DIR=$(mktemp -d "${TMPDIR:-/tmp}/idd-tagging-XXXXXX") || {
  echo "✗ cannot create a scratch dir for tagging — refusing to continue" >&2; exit 1; }
# EXIT cleans up; each SIGNAL cleans up, restores the default disposition, and
# re-raises itself. The one-liner `trap '...' EXIT HUP INT TERM` looked tidier
# and did something else: on HUP/TERM it ran the cleanup AND replaced the
# default termination semantics, so a caller without `set -e` carried on into
# the verification loop below with the directory already deleted — grep found
# nothing, the loop ran zero times, and the mention gate passed silently. Third
# route into the same silent pass (missing file, missing value, now a swallowed
# signal); this one dies the way the sender asked.
idd_tag_cleanup() { rm -rf "$TAG_DIR"; }
idd_tag_on_signal() { sig="$1"; idd_tag_cleanup; trap - "$sig"; kill -s "$sig" $$; }
trap idd_tag_cleanup EXIT
for sig in HUP INT TERM; do
  # shellcheck disable=SC2064  — $sig must expand NOW, one handler per signal
  trap "idd_tag_on_signal $sig" "$sig"
done
# Fail-closed on purpose. Without the `|| exit`, a full or read-only /tmp left
# TAG_DIR empty, the paths below became `/collaborators.json` etc., and the
# verification loop read a file that does not exist — so `grep` produced nothing,
# the `for handle in ...` body ran zero times, and **the mention gate passed
# silently**. A gate that cannot read its own inputs must refuse, not pass.
#
# The draft body must be WRITTEN here, not assumed. The consumer below reads
# $TAG_DIR/comment-body.md; nothing created it, so the loop was scanning a
# missing file — the same silent-zero-iterations failure by a different route.
#
# And writing it is not enough either. `COMMENT_BODY` is supplied by the CALLING
# skill; this protocol does not produce it. If the caller has not set it,
# `printf '%s' ""` SUCCEEDS, writes a 0-byte file, the `||` never fires, and the
# loop below greps an empty file and runs zero times — the gate passes silently
# for a third time, now on a missing VALUE rather than a missing file. Each
# previous fix closed the layer it was looking at and left the one under it.
#
# So the value is checked before it is staged. An empty draft body is not a
# thing this protocol can be asked about: there is nothing to scan for mentions,
# and answering "no mentions found" about text you were never given is the
# failure this whole file exists to prevent.
: "${COMMENT_BODY:?the calling skill must set COMMENT_BODY to the draft text before running this protocol — an empty body cannot be checked for mentions, and a gate that cannot read its input must refuse}"
printf '%s' "$COMMENT_BODY" > "$TAG_DIR/comment-body.md" || {
  echo "✗ cannot stage the comment body for mention checking — refusing" >&2; exit 1; }
# Non-empty on disk too: `printf` can succeed while writing nothing if the
# variable was set but empty (`COMMENT_BODY=""` passes `:?`).
[ -s "$TAG_DIR/comment-body.md" ] || {
  echo "✗ the staged comment body is empty — refusing to certify 'no mentions'" >&2; exit 1; }
# Collaborators (anyone with repo access — outside collaborators included)
# `[...]` and `--paginate`, and both matter for the same reason: the consumer
# below runs `jq -e ".[] | select(.login == ...)"` on this file.
#
# Without the brackets `--jq` emits a STREAM of objects, so `.[]` iterates the
# FIELDS of each one and `select` asks a STRING for `.login` — a type error, rc=5,
# and EVERY legitimate mention refused. The MENTION_ATTESTED path shipped last
# round could not work for anyone.
#
# Without `--paginate`, collaborator 31 and onward simply are not in the file, and
# the gate aborts the post naming a real collaborator as unverified.
gh api repos/$OWNER/$REPO/collaborators --paginate --jq '[.[] | {login, name, type}]' \
  | jq -s 'add // []' > "$TAG_DIR/collaborators.json"

# Org members (in case the target is an org repo and the person is a member but not direct collaborator)
if [ "$OWNER_TYPE" = "Organization" ]; then
  gh api orgs/$OWNER/members --paginate --jq '[.[] | {login}]' \
    | jq -s 'add // []' > "$TAG_DIR/org-members.json"
fi

# Recent commit authors (fallback — for forked / public repos with no API access)
git log --pretty=format:'%an <%ae>' | sort -u > "$TAG_DIR/commit-authors.txt"
```

**The combined set of these lists is the only source of truth for valid handles.** Never use:

- Handles from training data
- Handles from prior chat conversations
- Handles inferred from git config / email domains
- Handles from `~/.gitconfig` / `~/.ssh/config` / `gh auth status`

### Step 2.5: Consult the config registry first (acceleration, not authority)

If the walked-up IDD config has a `collaborators[]` array (schema in [references/config-protocol.md](../references/config-protocol.md)), use it as the **first** resolution attempt — it carries the human's own curated alias/name → `@login` mapping, so it resolves `Hardy` / `楊浩弘` / a student ID that the raw API list can't. Match the input, in priority order:

1. `github_login` exact (case-insensitive)
2. `aliases[]` exact (case-insensitive)
3. `email` exact — **only if** the input literally is an email
4. `display_name` substring

On a **hit**, resolve to that entry's `github_login` — **but the table is an accelerator, never an authority.** It can go stale (a collaborator removed, a login renamed after the config was written), so a hit MUST still be existence-verified via `gh api users/<login>` before it counts as resolved and before `--mention-attested` is passed. A hit that fails existence-verification falls through to Step 3 (treat as no config match).

On a **miss** (no `collaborators[]`, or no entry matches), fall through to Step 3 and fuzzy-match against the API-fetched list from Step 2 as before. The registry never replaces Step 2's fetch — it only front-runs the resolution when it can.

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
- **Unconditional scan（v2.92.0+, #117）**：這個 pre-post 掃描**不是** intent-gated — 即使沒有 `--mention` flag、沒有 tagging 意圖，AI-generated body 中**附帶**的 `@xxx` token（內部 codename 如 `@codex`、引用對話原文、動態值如 `@assignee`）一樣會通知同名真實 user。每個 raw token 二擇一：
  1. **不是 mention** → backtick-escape 成 `` `@xxx` ``（inline code 對 GitHub notification 惰性）或放進 code fence
  2. **是 mention** → 走完 5-step 協定後，經 `scripts/gh-egress.sh` 派送時帶 `--mention-attested <login1,login2>`（涵蓋**每一個**意圖 mention；部分涵蓋一樣 refuse）
- **機械 backstop**：`scripts/gh-egress.sh` 的 mention net（#117）會在派送前剝除 fence/inline-code 後掃 `@login` token，未被 `--mention-attested` 涵蓋者 refuse（exit 11 — #227 refusal 碼帶 ≥10，<10 為 gh 原生碼透傳）。此網對 email-like `user@host` 不誤觸（prefix guard）。未接線 gh-egress 的 skill 依本 rule 自律（prose 層），機械覆蓋隨 gh-egress rollout 生效。

```bash
# Verification step
#
# The COMBINED set, because that is what the paragraph above declares to be the
# source of truth. Only `collaborators.json` used to be consulted, so the
# `org-members.json` this protocol goes and fetches had no consumer at all: an
# org member who is not a direct collaborator is a legitimate mention target,
# and the gate aborted the post naming them as unverified. A produced-but-unread
# allowlist is a spec and an implementation disagreeing in the same file.
#
# `commit-authors.txt` is deliberately NOT in the union: it holds `Name <email>`,
# not logins, so it cannot answer "is @x a valid handle". It feeds the Step 3
# fuzzy resolution (name → login), which is a different question. Said here
# because "the combined set" reads like all three.
for handle in $(grep -oE '@[A-Za-z0-9-]+' "$TAG_DIR/comment-body.md" | sort -u); do
  login=${handle#@}
  if jq -e --arg l "$login" '.[] | select(.login == $l)' \
       "$TAG_DIR/collaborators.json" > /dev/null 2>&1; then
    continue
  fi
  if [ -f "$TAG_DIR/org-members.json" ] \
     && jq -e --arg l "$login" '.[] | select(.login == $l)' \
          "$TAG_DIR/org-members.json" > /dev/null 2>&1; then
    continue
  fi
  echo "ERROR: @$login is in neither the collaborator nor the org-member list. Aborting."
  exit 1
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
