# Claude Code Cloud Session Tool Contracts

Claude Code on the web, in the mobile app, and in scheduled cloud sessions runs IDD inside a remote
container. It is the same Claude Code runtime as a local session (see
[`claude-code-tools.md`](claude-code-tools.md)) with a different GitHub access path. This reference
records what differs and how in-scope skills keep their semantics (#416, Spectra change
`cloud-session-idd-all`).

Skill bodies are not rewritten: each in-scope `SKILL.md` carries a one-line runtime note pointing
here, and the agent applies the mapping below wherever the skill shows `gh` porcelain.

## Detection

Source `scripts/lib/cloud-session.sh` (or read the same variables in Python):

| Signal | Meaning |
|---|---|
| `CLAUDE_CODE_REMOTE` is exactly `true` | cloud session (`idd_is_cloud_session` exits 0) |
| `CLAUDE_CODE_SESSION_ATTENDED` is exactly `1` | a human is attending (`idd_cloud_interaction` prints `attended`) |
| anything else, including unset | not cloud / `unattended` |

Unattended is the safe default: attended sub-skill questions never time out, so an unwatched session
judged attended would wait forever. Never infer a cloud session from a GitHub error.

## GitHub access in a cloud session

| Works | Does not work |
|---|---|
| `gh api repos/{owner}/{repo}/…` (REST) for repositories attached to the session | GitHub GraphQL — so every `gh issue …`, `gh pr …`, `gh label list`, `gh repo view` porcelain call (HTTP 403 `GitHub GraphQL is not available from Claude Code sessions`) |
| `gh api user` | `gh auth status` (the session's `GH_TOKEN` is a placeholder; the proxy injects the real credential) |
| `git push` to attached repositories | `gh api search/…` and repositories not attached to the session (HTTP 403 `GitHub access to this repository is not enabled for this session`) |

## Porcelain → REST mapping

`R` is `OWNER/REPO`; `$LIB` is `"$CLAUDE_PLUGIN_ROOT/scripts/lib"`. `gh-rest.sh` returns the same field
names and shapes as `gh … --json`, pages through results, and adds a `hint:` line on cloud refusals.
Where a skill uses `--jq EXPR` / `-q EXPR`, pipe the helper's output to `jq -r EXPR`.

| Porcelain in a skill | Cloud replacement |
|---|---|
| `gh issue view N --repo R --json F` | `bash "$LIB/gh-rest.sh" issue-view N --repo R --json F` (fields: `number,title,state,body,url,createdAt,updatedAt,closedAt,author,labels,assignees,milestone,comments`) |
| `gh issue list --repo R --state S --label L --limit K --json F` | `bash "$LIB/gh-rest.sh" issue-list --repo R --state S --label L --limit K --json F` (pull requests excluded; `comments` is every comment, one extra call per issue) |
| `gh issue list … --search "sort:updated-desc"` (`idd-list`) | `… issue-list … --sort updated` — GitHub sorts before the limit cuts (#299). `--search "closed:>=DATE"` → `--closed-since DATE`. Any other `--search` query needs the search API: unsupported |
| `gh issue create …` | `bash "$CLAUDE_PLUGIN_ROOT/scripts/gh-egress.sh" create …` — same arguments; the wrapper already dispatches through REST |
| `gh issue comment N …` | `bash "$CLAUDE_PLUGIN_ROOT/scripts/gh-egress.sh" comment N …` |
| `gh issue edit N …` | `bash "$CLAUDE_PLUGIN_ROOT/scripts/gh-egress.sh" edit N …` (flags: `--title --body --body-file --add-label --remove-label --add-assignee --remove-assignee --milestone --remove-milestone`) |
| `gh pr list --repo R --state S --limit K --json F` | `bash "$LIB/gh-rest.sh" pr-list --repo R --state S --limit K --json F` (`S` = `open`/`closed`/`merged`/`all`; `mergeable` costs one extra call per PR; `--search` is unsupported) |
| `gh pr view P --repo R --json F` | `gh api repos/R/pulls/P` — `state` + `merged_at` (merged when non-null), `head.ref`, `head.sha`, `base.ref`, `draft`, `mergeable` (`true`/`false`/`null` ↔ porcelain `MERGEABLE`/`CONFLICTING`/`UNKNOWN`) |
| `gh pr create --title T --body-file B --base D --head H` | `gh api repos/R/pulls -X POST -f title=T -f head=H -f base=D -F body=@B --jq .html_url` |
| `gh repo view R --json F` | `bash "$LIB/gh-rest.sh" repo-view --repo R --json F` (fields: `nameWithOwner,defaultBranchRef,isFork,visibility,url,viewerPermission`) |
| `gh label list --repo R` | `gh api "repos/R/labels?per_page=100" --paginate --jq '.[].name'` |
| `gh auth status` | `gh auth status \|\| gh api user --jq .login` (`gh auth status` always fails in a cloud session; `gh api user` checks the API the run will use, and GitHub App tokens that cannot call `/user` still pass the first) |
| `gh issue close N --repo R` (not on the `idd-all` path) | `gh api repos/R/issues/N -X PATCH -f state=closed -f state_reason=completed` — and only through `/idd-close`, never by hand |

Pull-request operations that are GraphQL-only on github.com have cloud-session REST routes:
`PUT`/`DELETE repos/R/pulls/P/ccr/auto_merge`, `POST repos/R/pulls/P/ccr/ready_for_review`,
`POST repos/R/pulls/P/ccr/convert_to_draft`, `GET repos/R/pulls/P/ccr/review_threads`,
`POST repos/R/pulls/P/ccr/comments/{comment_id}/resolve` (or `/unresolve`). Their existence is not
permission: verify PASS is a state, not a merge authorization — no IDD skill merges or enables
auto-merge, and `gh pr merge` stays a human action.

Issue writes always go through `scripts/gh-egress.sh`, cloud or not: it is the only egress path and
runs the privacy, mention and attestation gates. Never write an issue body with a raw `gh api -X POST`.

## Orchestration (`idd-all`)

- Mode: a cloud session forces the PR path (a direct commit would be lost when the container is
  reclaimed); the interaction axis follows `idd_cloud_interaction`. `--no-pr` is overridden with a
  notice; `--pr` and `--in-chain` keep their meaning. Spec: `idd-pr-hitl-modes`.
- `(PR, unattended)` in a cloud session needs the ralph-loop plugin; when it is missing, `idd-all`
  aborts after removing the branch it created instead of degrading to direct-commit.
- The PR is opened only after verify PASS. When `(PR, attended)` ends with blocking findings, or the
  unattended verify-fix loop gives up, a cloud session still pushes the branch (no PR) so the commits
  survive the container — unless a blocking finding is a security finding: a push could publish a
  committed secret. Aborts that deliberately do not push (the Phase 4/5 type guards, security findings,
  lost shell state, a failed push) say so: push the branch by hand before the session ends, after
  checking the commits for secrets when a security finding stopped the run.
- `idd-all`'s own state-changing steps (issue check, branch setup, unwind, PR creation) already call
  REST directly (`gh api repos/R`, `…/issues/N`, `…/pulls`); there is nothing to translate there.
- Push before the session ends: `.claude/.idd/state/` and every unpushed commit live only as long
  as the container.

## Verify

`idd-verify` runs Claude-only in a cloud session: no Codex credentials or executable exist there.
The cross-model leg is skipped up front (`codexEnabled: false`), codex-pro governance is not
resolved, and the master report states `Codex leg not run — cloud session (degraded: Claude-only)`.

## Unsupported in a cloud session

These stop with the stated reason; there is no workaround inside the session. Run them from a local
Claude Code session.

| Surface | Why | What the user sees |
|---|---|---|
| `idd-find`, issue retrieval in `idd-ask` | GitHub search API is blocked | the skill's runtime note: stop and say it is unsupported |
| `idd-report`, `idd-discuss` publishing, Discussions in `idd-ask` | Discussions are GraphQL-only | `discussions_api` raises `GitHub Discussions need GraphQL, which Claude Code cloud sessions block …` |
| `idd-issue --blocked-by` native relation | GraphQL mutation | GitHub's 403 is printed verbatim (existing behavior); the body blockquote is still written |
| `--target` / group issues in a repository not attached to the session | session is bound to attached repositories | `gh-rest.sh` and `gh-egress.sh` add `hint: this cloud session cannot reach R; attach the repository …` |
| Spectra tier (`spectra` CLI) | not installed in the container | `idd-all` Step 0.35 warning, Phase 3b hard gate |
| `idd-close`, `idd-comment`, `idd-edit`, `idd-config`, `idd-reorganize`, `idd-all-chain` | not migrated (outside the `idd-all` path) | their porcelain calls fail with GitHub's own 403 message; their `gh-egress.sh` writes and `check-*` script reads work |
| private attachment downloads (`process-attachments.sh download`) | it authenticates with `gh auth token`, a placeholder in a cloud session | unverified in a cloud session; public attachment URLs are unaffected |

## Status

Verified in a cloud container (2026-10-19 / 25): GraphQL and `gh auth status` fail while REST works;
`gh-rest.sh` reads (issue, repo, merged PRs, an unattached repo's hint) against the real API; plugins
installed into the user scope load after a session restart. Not yet verified: a fresh session started
from the setup script below, and an end-to-end `/idd-all` run in a cloud session. Issue writes through
the REST transport are covered by tests against a stub `gh`, not by a live cloud write.

## Setup script

Plugins load only at session start, so install them in the cloud environment's setup script (cloud
environment menu in the session title bar → Edit). The pins match
`scripts/requirements-egress.txt`; the setup script may run before the repository is checked out,
so they are spelled out here.

```bash
claude plugin marketplace add PsychQuant/issue-driven-development
claude plugin marketplace add anthropics/claude-plugins-official
claude plugin marketplace add PsychQuant/parallel-ai-agents
claude plugin marketplace add PsychQuant/codex-pro
claude plugin install issue-driven-dev@issue-driven-development
claude plugin install ralph-loop@claude-plugins-official
python3 -m pip install markdown-it-py==4.0.0 linkify-it-py==2.0.3 uc-micro-py==2.0.0
```

All four marketplaces are needed: `issue-driven-dev` declares superpowers, parallel-ai-agents and
codex-pro as dependencies and does not load without them.
