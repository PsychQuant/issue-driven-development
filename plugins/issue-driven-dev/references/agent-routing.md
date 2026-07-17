# Agent Routing Reference

Single source of truth for **how `issue-driven-dev` integrates with `idd-route`** to recommend / record / finalize agent routing decisions across the IDD lifecycle.

This is the consumer-side contract; the binary impl lives in [`PsychQuant/idd-route-swift`](https://github.com/PsychQuant/idd-route-swift).

---

## Why this exists

Yesterday's #98 (Claude IDD, 3 round trips, 2 P1 caught) vs today's #111 (Codex implement, 1 commit, 0 blocking, 8 follow-ups) showed each agent has consistent strengths/weaknesses but the right call depends on issue features × observed track record. Static rubrics can't keep up — need data-driven recommendation that learns over time.

`idd-route` solves this by recording every IDD verify outcome to JSONL, aggregating by `(agent, complexity, scope_class)` bucket with exponential decay (recent decisions weight more), then recommending the best agent for new issues. Falls back to a static heuristic rubric on cold start (< 5 data points).

---

## Lifecycle integration

```
idd-diagnose  ─→  ~/bin/idd-route recommend ...
                  └─→ inject "Recommended Agent" section into diagnosis comment
                  └─→ user accepts or overrides (delegation choice is theirs)

idd-implement (Claude OR external agent — out of routing scope)
                  └─→ commits land via PR or local

idd-verify    ─→  ~/bin/idd-route record ... --outcome in_review
                  └─→ <repo>/.claude/.idd/routing-stats.jsonl (+ global mirror)

idd-close     ─→  ~/bin/idd-route update-outcome ... --outcome merged|abandoned
                  └─→ append new record (jsonl is append-only; original in_review stays for audit)
```

---

## Hard binary requirement: `~/bin/idd-route`

- Skills check binary existence with `command -v idd-route`
- If missing: log `idd-route not installed; recommendation skipped` to stderr, **proceed without recommendation** (don't break IDD flow)
- Install via:
  - Recommended: `claude plugin install idd-route@issue-driven-development` (auto-downloads via wrapper)
  - Manual: `cli-tools:cli-install PsychQuant/idd-route-swift`

---

## Step-by-step: when each skill calls idd-route

### `idd-diagnose` Step 3.7: Recommend

Runs after Step 3.5 (Complexity Assessment) and before Step 4 (Confirm + Routing).

```bash
if command -v idd-route &>/dev/null; then
  STATS="$REPO_PATH/.claude/.idd/routing-stats.jsonl"
  GLOBAL="$HOME/.cache/idd-route/stats.jsonl"

  # Extract signals from issue body + diagnosis (controlled vocabulary in
  # idd-route plugin's references/signal-vocabulary.md)
  SIGNALS=$(detect_signals "$ISSUE_BODY" "$DIAGNOSIS")

  # Estimate scope LOC from diagnosis Strategy
  SCOPE_LOC=$(estimate_scope_loc "$DIAGNOSIS_STRATEGY")

  RECOMMENDATION=$(idd-route recommend \
    --stats-file "$STATS" \
    --global-stats-file "$GLOBAL" \
    --complexity "$COMPLEXITY" \
    --scope-loc-estimate "$SCOPE_LOC" \
    --signals "$SIGNALS" \
    --candidates codex-xhigh,claude-opus-4.7,claude-sonnet-4.6,claude-haiku-4.5)
  EXIT=$?  # 0=warm, 3=fallback, other=error

  # Inject "Recommended Agent" section into diagnosis comment markdown:
  # ### Recommended Agent: <recommended>
  # **Confidence**: <confidence>
  # **Data source**: <data_source>  (per_repo / global / static_heuristic)
  # **Reasoning**: <reasoning>
  # **Compare**: <markdown table from candidates[]>
fi
```

User can accept or ignore. The routing recommendation is informational, not binding.

### `idd-verify` Step 5d: Record

Runs after Step 5c (Routing decision based on findings) and before Auto-Update.

```bash
if command -v idd-route &>/dev/null; then
  STATS="$REPO_PATH/.claude/.idd/routing-stats.jsonl"

  # Determine which agent actually implemented this round.
  # Heuristic: PR head commit author (codex/* branches → codex-xhigh;
  # other authors → claude-opus-4.7 default; user can override via --agent).
  AGENT=$(detect_agent_from_commits "$VERIFIED_COMMITS")

  # Extract scope from PR diff or commit range
  SCOPE_FILES=$(echo "$VERIFIED_DIFF" | grep -c '^diff --git')
  SCOPE_LOC=$(echo "$VERIFIED_DIFF" | grep -cE '^[+-][^+-]')

  # Round trips: count implement→verify cycles for this issue
  ROUND_TRIPS=$(count_round_trips "$ISSUE_NUMBER")

  # Findings count from verify report
  BLOCKING=$(grep -c "Blocking" "$VERIFY_REPORT")
  MEDIUM=$(grep -c "MEDIUM" "$VERIFY_REPORT")
  LOW=$(grep -c "LOW" "$VERIFY_REPORT")

  idd-route record \
    --stats-file "$STATS" \
    --issue "$ISSUE_NUMBER" --issue-repo "$REPO" \
    --agent "$AGENT" \
    --complexity "$COMPLEXITY" \
    --scope-files "$SCOPE_FILES" --scope-loc "$SCOPE_LOC" \
    --signals "$SIGNALS" \
    --round-trips "$ROUND_TRIPS" \
    --verify-blocking "$BLOCKING" --verify-medium "$MEDIUM" --verify-low "$LOW" \
    --followups "$FOLLOWUP_COUNT" \
    --outcome in_review \
    --recorded-by "idd-verify-$IDD_VERSION"
fi
```

Failures (non-zero exit) are logged to stderr but don't break verify flow.

### `idd-close` Step 5: Update outcome

Runs after Step 4 (Publish + close issue).

```bash
if command -v idd-route &>/dev/null; then
  STATS="$REPO_PATH/.claude/.idd/routing-stats.jsonl"

  # Outcome:
  #   - PR was merged → merged
  #   - Issue closed without merge (e.g., wontfix) → abandoned
  #   - Issue reopened later → reverted (rare; not handled here)
  if [[ -n "$PR_NUMBER" ]] && gh pr view "$PR_NUMBER" --json merged -q .merged | grep -q true; then
    OUTCOME="merged"
  else
    OUTCOME="abandoned"
  fi

  idd-route update-outcome \
    --stats-file "$STATS" \
    --issue "$ISSUE_NUMBER" --issue-repo "$REPO" \
    --outcome "$OUTCOME"
fi
```

This appends a new record (jsonl is append-only). Original `in_review` record from `idd-verify` stays for audit. Recommendation engine reads the latest matching record per issue.

> **NOTE**: `update-outcome` ships in `idd-route-swift` v0.3.0 (P2 of plan). Until then, `idd-close` skips this step gracefully.

---

## Signal extraction

The `--signals` flag drives both static-heuristic scoring and bucket routing. Skills should extract signals from issue body + diagnosis using the controlled vocabulary documented in [`idd-route/references/signal-vocabulary.md`](../../idd-route/references/signal-vocabulary.md).

Example signals to detect:

- `explicit_acceptance` — issue body has structured "Suggested fix" or "Acceptance criteria" section
- `single_handler` — diagnosis identifies one function/handler as the sole change site
- `cross_repo` — touches submodule or sibling repo
- `breaking_change` — caller-visible contract change (label `breaking-change` or body explicit)
- `requires_changelog` — change warrants CHANGELOG.md entry

Detection is heuristic; false positives are OK (signal vocabulary is informational at the warm-state recommendation level).

---

## Disable / opt-out

| Mechanism | Effect |
|-----------|--------|
| `~/.cache/idd-route/disabled` flag file | Skills skip all `idd-route` calls entirely |
| `<repo>/.claude/idd-route.json` `{"enabled": false}` | Per-project skip |
| `~/.cache/idd-route/config.json` `{"global_mirror": false}` | Per-machine: don't mirror to global |
| Uninstall `idd-route` plugin (binary missing) | Skills auto-skip with stderr log |

---

## Cross-references

- [`idd-route/CLAUDE.md`](../../idd-route/CLAUDE.md) — plugin design + 3-tier config injection
- [`idd-route/references/signal-vocabulary.md`](../../idd-route/references/signal-vocabulary.md) — controlled vocabulary
- [`idd-route/references/static-heuristic.md`](../../idd-route/references/static-heuristic.md) — cold-start fallback rubric
- [`PsychQuant/idd-route-swift`](https://github.com/PsychQuant/idd-route-swift) — binary source + JSONL schema spec

---

## Versioning

- v2.38.0 introduces this integration. Pre-v2.38 users (or users who don't install `idd-route` plugin) get unchanged IDD flow.
- `idd-route` binary version is pinned via `binaries.idd-route.version` in `idd-route` plugin's `plugin.json`. Bump independently.
