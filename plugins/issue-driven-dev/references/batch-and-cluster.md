# Batch and Cluster Reference

Single source of truth for **multi-issue invocation** in IDD. Two modes, different semantics — pick by the operation's safety profile.

| Mode | Skills using it | Semantic |
|------|----------------|----------|
| **Batch mode** | `idd-diagnose`, `idd-update`, `idd-comment`, `idd-edit` | Independent per-issue ops looped sequentially. No shared state. |
| **Cluster-PR mode** | `idd-implement`, `idd-verify`, `idd-close` | Multi-issue work sharing one feature branch + one PR. Per-commit `Refs #N` per issue. |
| _(neither)_ | `idd-issue`, `idd-list`, `idd-report`, `idd-config`, `idd-all` | Single-issue or already-multi-by-design. Out of scope. |

Why split: batch is safe when each issue's op is order-independent and idempotent. Cluster-PR is needed when ops produce *correlated artifacts* (commits, PR, verify report) that must stay coherent across the issue group.

---

## Batch mode

### Trigger

Skill receives ≥2 `#NNN` tokens in args before any other flag:

```
idd-diagnose #34 #36 #38              → batch (3 issues)
idd-update #19                         → single
idd-comment #34 #36 --type note --body '...'  → batch (2 issues, --type/--body apply to all)
```

### Execution

```
for each #N in the list (sequentially):
    run the skill's normal single-issue logic on #N
    auto-update phase (each idd-* skill's existing Step) runs per-issue
    capture per-issue outcome (success / abort / skipped)

at end:
    print Aggregate Report (table: #N | outcome | ref to artifact e.g. comment URL)
```

### Failure handling

- **Per-issue abort does NOT stop the batch.** If #36 fails, #34 (already done) is not rolled back; #38 still runs.
- Final Aggregate Report explicitly lists `aborted` issues with reason. User decides remediation per-issue.
- Exception: if a hard pre-flight gate fails (gh auth missing, target repo unreachable), abort the entire batch before iteration.

### Issue selector syntax (v1)

Explicit list only: `#34 #36 #38`. Selector syntax (`--label needs-update`, `--milestone v2`) deferred to v2 if real workflow demands it. Parsing rule: tokens matching `^#\d+$` before any `--flag` are issue numbers; everything after is flags applied to every issue.

### What batch does NOT do

- Does not parallelize (sequential to keep GitHub API quotas + log readability sane).
- Does not deduplicate the per-issue auto-update step — each issue's body Phase still gets bumped after its op.
- Does not aggregate comments into one — each issue still gets its own comment posted.

---

## Cluster-PR mode

Designed around the real workflow pattern: "I have 7 issues that fall into 2 themes (e.g., Docs + Sanitizer-hardening). I want 2 PRs, not 7." (See archive 2026-04-27.)

### Trigger

`idd-implement` (or `idd-verify` / `idd-close`) receives ≥2 `#NNN` tokens:

```
idd-implement #34 #36 #38              → cluster-PR mode (3 issues, 1 branch, 1 PR)
idd-implement #19                      → single-issue mode (existing v2.27 behavior)
```

### Branch naming

```
BRANCH="idd/cluster-{slug}"
```

`{slug}` resolution priority:
1. `--slug <name>` flag (per-invocation override)
2. Common prefix of all issue titles, slugified, ≤40 chars
3. Sorted issue numbers joined: `idd/cluster-34-36-38`

### Commits

Each commit MUST include at least one `Refs #N` for an issue in the cluster. Format:

```
fix: tighten URL scheme validation

Refs #34, #36
```

Multi-`Refs` is allowed and encouraged when one commit genuinely addresses multiple cluster issues. `Closes`/`Fixes`/`Resolves` trailers remain forbidden (see `idd-implement` rationale).

### PR

One PR per cluster, opened by `idd-implement` (PR path) or whatever phase first triggers PR creation. PR body MUST include:

```markdown
## Cluster

This PR addresses:
- Refs #34 — {issue 34 title}
- Refs #36 — {issue 36 title}
- Refs #38 — {issue 38 title}

(Full closing summary remains per-issue; manual /idd-close after merge writes
the closing comment for each issue in the cluster.)
```

PR title: `cluster: {slug}` (e.g., `cluster: sanitizer-hardening`) so reviewers know it's multi-issue without scrolling.

### Per-skill cluster behavior

| Skill | Cluster semantic |
|-------|------------------|
| `idd-implement` | Single feature branch shared by all cluster issues. Strategy-level TaskList aggregates from each issue's diagnosis Strategy. Each commit tags `Refs #N` (or multiple). Auto-update bumps phase=`implemented` on every cluster issue's body. |
| `idd-verify` | 6-AI Agent Team + Codex see ALL cluster issues' diagnoses + the full PR diff. Verify report is **partitioned per-issue** (one section per #N) so each issue's findings are traceable. Aggregate PASS/FAIL applies to PR as a whole; per-issue findings auto-create follow-up issues as usual. |
| `idd-close` | Refuses if any cluster issue's checklist gate fails. Refuses if PR is unmerged. After merge: writes per-issue closing summary (each summary fetches that issue's commits via `git log --grep "#N"` filtered to PR commits), then closes each issue via `gh issue close`. Phase=`closed` auto-updated per issue. |

### Failure handling in cluster mode

- **Implement phase abort** (e.g., one issue's strategy needs human input): stop. Branch + commits already made stay; user finishes manually or restarts cluster.
- **Verify blocking findings**: same as single-issue (auto-fix loop max 2 rounds), but findings span all cluster issues — fix touches the shared branch.
- **Close gate fail on one cluster issue**: refuse close on entire cluster (don't half-close). User edits the failing issue's checklist or fixes the unticked work, then re-runs `idd-close --cluster`.

### Backward compatibility

Single-issue invocation (`idd-implement #19`) behavior is **unchanged**. Cluster mode only triggers on ≥2 `#NNN`. Existing scripts and muscle memory keep working.

---

## Cross-references

- [pr-flow.md](pr-flow.md) — PR path resolution. Cluster mode is a precondition that pre-empts the resolution algorithm and forces PR path; full semantics + override notice format in [§ Cluster mode override](pr-flow.md#cluster-mode-override). `--no-pr` / `pr_policy:"never"` colliding with cluster mode trigger an explicit override notice (mirror fork detection), then proceed as PR — no abort, no silent ignore.
- [config-protocol.md](config-protocol.md) — `--target` / multi-repo support. All issues in a cluster MUST share one target repo (cross-repo clusters not supported).
- IDD checklist gate (idd-close Step 0) and PR Gate (Step 1.5) apply per-issue inside the cluster.

## Versioning

- v2.34.0 introduces both modes. Skills not in the table above explicitly document "no batch / cluster support — out of scope" so future contributors don't accidentally add it.
- Selector syntax (`--label`, `--milestone`) reserved for a future minor bump if workflow patterns warrant it.
