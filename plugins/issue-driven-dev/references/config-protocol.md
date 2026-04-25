# Config Resolution Protocol

This file is the single source of truth for how every `idd-*` skill resolves the **target GitHub repo** and related settings.

All `idd-*` skills MUST follow this protocol. Where individual skill SKILL.md files refer to "reading `.claude/issue-driven-dev.local.json`", they implicitly mean the algorithm here.

## Why this exists

Issue-driven development frequently runs in monorepos or nested project structures where:

- Different sub-packages have different upstream GitHub repos
- The same directory might want to send issues to **multiple** repos depending on the issue topic
- Sometimes the user wants a one-off override without changing config

A single `cwd-only` config check is insufficient. This protocol defines three composable mechanisms.

## Five mechanisms (priority order)

When an idd-* skill needs to determine the target repo, it walks this priority list and uses the first match:

```
1. --target <owner/repo> flag     ← runtime override (per invocation)
2. ask_each_time + candidates     ← runtime menu (from config)
3. Predicate match (when clauses) ← auto-pick candidate or group by context
4. Cascading config (walk up)     ← static routing by directory
5. git remote fallback            ← last resort, with prompt
```

In addition, **groups** (multi-repo cross-linked issue creation) are an orthogonal feature that may be triggered at mechanism 2 or 3, regardless of which routing layer applied.

### Mechanism 1: per-invocation override flag

Skills accept a runtime flag to override target resolution for one invocation:

| Skill | Flag | Accepted values |
|-------|------|-----------------|
| `idd-issue` | `--target` | `owner/repo` OR `group:<label>` (groups only meaningful for idd-issue) |
| `idd-list`, `idd-diagnose`, `idd-update`, `idd-verify`, `idd-close`, `idd-implement`, `idd-edit`, `idd-report` | `--repo` | `owner/repo` only |
| `idd-comment` | `--repo` | `owner/repo` only — `--target` already means "link target issue" |

```bash
/idd-issue --target PsychQuant/foo
/idd-issue --target group:cross-package-bug
/idd-list  --repo owner/monorepo
/idd-diagnose #42 --repo PsychQuant/bar
```

**Behavior**:
- Use the value directly for this invocation
- Do NOT write back to config
- Do NOT trigger the AskUserQuestion menu
- This is a one-off — the next invocation goes back to normal resolution

**Why two flag names**: only `idd-issue` resolves to a group (vs. a single repo). Sibling skills always operate on one repo, so `--repo` is more natural and avoids collision with `idd-comment`'s pre-existing `--target` (link target). The semantic intent is identical — both are "use this repo, ignore config for this invocation."

### Mechanism 2: Candidates list (`ask_each_time`)

A single config can list multiple candidate repos. When `ask_each_time: true`, the skill always prompts.

```json
{
  "github_repo": "owner/default-repo",
  "github_owner": "owner",
  "attachments_release": "attachments",
  "candidates": [
    {"label": "Outer monorepo",      "github_repo": "owner/monorepo",      "github_owner": "owner",      "attachments_release": "attachments"},
    {"label": "Sub: vibe-mixing",    "github_repo": "PsychQuant/vibe-mixing", "github_owner": "PsychQuant", "attachments_release": "attachments"},
    {"label": "Sub: che-word-mcp",   "github_repo": "PsychQuant/che-word-mcp", "github_owner": "PsychQuant", "attachments_release": "attachments"}
  ],
  "ask_each_time": true
}
```

**Behavior**:
- If `candidates` exists AND `ask_each_time: true`, use AskUserQuestion to let user pick
- Each candidate inherits unset fields (`github_owner`, `attachments_release`) from the top-level config if not provided
- The chosen candidate's fields are used for that invocation only — config is NOT modified

If `ask_each_time` is `false` or missing, the top-level `github_repo` wins by default. Candidates are ignored unless the user supplies `--target` matching a candidate label or repo.

### Mechanism 4: Cascading config (walk-up)

The skill walks up the directory tree from `cwd` looking for `.claude/issue-driven-dev.local.json`. **First found wins**.

Note: this happens **before** mechanisms 2 and 3 in execution order — we need to find the config before we can read candidates / evaluate predicates. The numbering reflects logical priority, not execution order.

**Stop boundaries** (whichever comes first):
- `$HOME` directory (do not look outside the user's home)
- The filesystem root `/`
- A directory containing both `.git/` AND `.claude/issue-driven-dev.local.json` (treat as repo boundary)

**Walk-up algorithm** (bash):

```bash
find_idd_config() {
  local dir="$PWD"
  while [ "$dir" != "/" ] && [ "$dir" != "$HOME/.." ]; do
    if [ -f "$dir/.claude/issue-driven-dev.local.json" ]; then
      echo "$dir/.claude/issue-driven-dev.local.json"
      return 0
    fi
    [ "$dir" = "$HOME" ] && break  # don't go above $HOME
    dir=$(dirname "$dir")
  done
  return 1
}
```

**Example**:

```
~/Developer/big-monorepo/.claude/issue-driven-dev.local.json    → owner/monorepo
~/Developer/big-monorepo/packages/foo/.claude/issue-driven-dev.local.json  → PsychQuant/foo

# Running from various cwds:
~/Developer/big-monorepo/                       → finds ./.claude/...   → owner/monorepo
~/Developer/big-monorepo/packages/foo/          → finds ./.claude/...   → PsychQuant/foo
~/Developer/big-monorepo/packages/foo/src/lib/  → walks up to packages/foo → PsychQuant/foo
~/Developer/big-monorepo/docs/                  → walks up to monorepo  → owner/monorepo
```

This is the standard monorepo tooling pattern (eslintrc, tsconfig, prettier, etc.).

### Mechanism 3: Predicate-based auto-selection (`when` clauses)

Each candidate (and each group, see below) MAY have a `when` clause. When present, the skill evaluates predicates against the current invocation context and picks the **first matching** candidate as the default for this run.

```json
{
  "github_repo": "owner/default",
  "candidates": [
    {
      "label": "Music workspace",
      "github_repo": "kiki/music-notes",
      "when": { "path_contains": "creative/music" }
    },
    {
      "label": "Vibe mixing",
      "github_repo": "PsychQuant/vibe-mixing",
      "when": { "path_contains": "vibe-mixing" }
    },
    {
      "label": "Plugin marketplace (auto by title)",
      "github_repo": "PsychQuant/psychquant-claude-plugins",
      "when": { "title_matches": "(?i)\\b(plugin|mcp|skill)\\b" }
    }
  ]
}
```

#### Supported predicates

| Predicate | Type | Evaluable when | Notes |
|-----------|------|----------------|-------|
| `path_contains` | string | Step 0.5 | Substring match on absolute `cwd` path |
| `path_matches` | glob | Step 0.5 | Glob (`*` `**` `?`) match on absolute `cwd` |
| `git_remote_matches` | regex | Step 0.5 | Regex match on `git remote get-url origin` |
| `git_branch_matches` | regex | Step 0.5 | Regex match on current branch name |
| `label_in` | array of strings | After Step 2 (idd-issue) / immediately (idd-edit etc.) | Any chosen label matches |
| `type_in` | array of strings | After Step 2 (idd-issue) | Issue type matches |
| `title_matches` | regex | After Step 2 (idd-issue) | Regex on issue title |
| `body_matches` | regex | After Step 2 (idd-issue) | Regex on issue body |
| `priority_in` | array of strings | After Step 2 (idd-issue) | P0/P1/P2/P3 |
| `all` | array of predicates | mixed | All sub-predicates must match (logical AND) |
| `any` | array of predicates | mixed | At least one sub-predicate must match (logical OR) |
| `not` | single predicate | mixed | Negate |

#### Two-stage resolution (idd-issue)

`idd-issue` evaluates predicates in two passes because some need the gathered issue info:

1. **Step 0.5 pass** — only path / git / branch predicates are evaluable. Match? → tentative default.
2. **After Step 2 pass** — title / type / label / body / priority predicates become evaluable. If a candidate with content predicates now matches AND the tentative default has lower-priority match, **prompt user to confirm switching**.

For other skills (`idd-list`, `idd-comment`, etc.), only Step 0.5 predicates apply (they don't gather issue content the same way).

#### First-match wins

Candidates are evaluated **in order**. First one whose `when` evaluates true is the tentative default. If none matches, fall through to top-level `github_repo`.

To express "default fallback" as a candidate (so it appears in the menu), include one with no `when` clause as the last entry — it always matches.

#### Composability

Predicates compose with the other mechanisms:

- `--target` flag still overrides everything (mechanism 1)
- `ask_each_time: true` still prompts, but **preselects** the predicate-matched candidate
- Walk-up still applies first to find the config file; predicates evaluate against the contents of whichever config was found

### Mechanism 5: git remote fallback

If no config is found anywhere on the path:

```bash
ORIGIN=$(git remote get-url origin 2>/dev/null | sed -E 's#.*[:/]([^/]+/[^/]+?)(\.git)?$#\1#')
```

Then run the **fork-aware detection** (only `idd-issue` does this; other skills just use origin or prompt).

### Mechanism 6 (orthogonal): Groups — multi-repo cross-linked issue creation

A **group** is a single logical issue spread across multiple repos. The user picks the group; idd-issue creates one **primary** issue and one **tracking** issue in each other repo, with bidirectional cross-references.

```json
{
  "candidates": [...],
  "groups": [
    {
      "label": "Cross-package bug",
      "repos": [
        {"github_repo": "PsychQuant/foo",   "role": "primary"},
        {"github_repo": "PsychQuant/bar",   "role": "tracking"},
        {"github_repo": "PsychQuant/glue",  "role": "tracking"}
      ],
      "when": { "label_in": ["cross-package"] }
    },
    {
      "label": "MCP + plugin marketplace",
      "repos": [
        {"github_repo": "PsychQuant/che-word-mcp",          "role": "primary"},
        {"github_repo": "PsychQuant/psychquant-claude-plugins", "role": "tracking"}
      ]
    }
  ]
}
```

#### Repo roles

| Role | Behavior |
|------|----------|
| `primary` | The "real" issue. Created first. Contains the full body. The other tracking issues link back here. Exactly **one** repo per group must be `primary`. |
| `tracking` | Lightweight tracking issue. Body starts with `Tracking primary: owner/repo#N` and a one-line summary (or full description copy — configurable). |

#### Per-group fields (optional)

```json
{
  "label": "...",
  "repos": [...],
  "when": { ... },
  "tracking_body_mode": "minimal"  // or "full" — default "minimal"
}
```

- `tracking_body_mode: "minimal"` — tracking issues just say "Tracking primary: X#N" + one-line summary
- `tracking_body_mode: "full"` — tracking issues get the full body too (use when each repo needs to track full context independently)

#### Creation flow (idd-issue with group selected)

```
1. Create primary issue in primary.github_repo → get #N
2. For each tracking repo:
   - Create issue with body starting:
     > Tracking primary: {primary.github_repo}#{N}
     > {summary}
3. Add comment to primary issue listing all tracking issues:
   "Tracked in:
   - {tracking-repo-1}#{Na}
   - {tracking-repo-2}#{Nb}"
4. Report all issue URLs to user
```

If any creation fails partway:
- Don't roll back already-created issues (manual cleanup is more transparent)
- Report which succeeded and which failed
- User can retry with `--target` for the missing ones

#### Triggering a group

Groups are picked just like candidates:

- Predicate match: `groups[].when` matches the context → preselect that group
- Menu: `ask_each_time: true` → groups appear alongside candidates in the picker
- `--target group:<label>` → directly trigger a named group from CLI

If a group's `when` matches AND a candidate's `when` matches, **groups take precedence** (because they express a stronger intent — multi-repo coordination). Both can show in the menu when `ask_each_time: true`.

## Schema (full, extended)

```json
{
  "github_repo": "owner/repo",                  // REQUIRED. Default target (fallback when no predicate matches).
  "github_owner": "owner",                      // OPTIONAL. Derived from github_repo if missing.
  "attachments_release": "attachments",         // OPTIONAL. Default "attachments".
  "tracking_upstream": "upstream/repo",         // OPTIONAL. Set when fork-aware detection chose Both mode.

  "candidates": [                                // OPTIONAL. Multi-target list.
    {
      "label": "Human-readable name",
      "github_repo": "owner/repo",
      "github_owner": "owner",                   // Optional, derives from github_repo
      "attachments_release": "attachments",      // Optional, defaults to top-level
      "when": {                                  // OPTIONAL (Phase 2A). Predicates for auto-selection.
        "path_contains": "creative/music"
        // or "path_matches", "git_remote_matches", "title_matches",
        //    "label_in", "type_in", "all", "any", "not", etc.
      }
    }
  ],

  "groups": [                                    // OPTIONAL (Phase 2B). Multi-repo coordinated issues.
    {
      "label": "Cross-package bug",
      "repos": [
        {"github_repo": "PsychQuant/foo", "role": "primary"},
        {"github_repo": "PsychQuant/bar", "role": "tracking"}
      ],
      "when": { "label_in": ["cross-package"] }, // OPTIONAL
      "tracking_body_mode": "minimal"            // OPTIONAL. "minimal" or "full". Default "minimal".
    }
  ],

  "ask_each_time": false                         // OPTIONAL. If true and candidates/groups exist, always prompt.
}
```

**Backward compatibility**: configs without `candidates` / `groups` / `ask_each_time` work exactly as before — they're plain single-target configs. All new fields are additive.

## Resolution algorithm (canonical)

```
function resolve_target(invocation_args, context):
    # 1. CLI flag wins
    if invocation_args has --target T:
        if T starts with "group:":
            return Group(by_label=T[6:], from=walked_up_config)
        return Single(T)  # do not touch config

    # 2. Walk up to find closest config
    config = find_idd_config()
    if config is null:
        return git_remote_or_prompt()

    # 3. Predicate match (Phase 2A) — try groups first, then candidates
    matched_group = first(g in config.groups where evaluate(g.when, context))
    matched_cand  = first(c in config.candidates where evaluate(c.when, context))
    tentative_default = matched_group or matched_cand or config.github_repo

    # 4. Ask if explicit
    if config.ask_each_time:
        chosen = AskUserQuestion(
            options = config.candidates ++ config.groups,
            preselect = tentative_default
        )
        return chosen  # may be Single or Group

    # 5. Otherwise use the tentative default
    if tentative_default is a Group:
        return Group(tentative_default.repos)
    return Single(tentative_default.github_repo)


# Two-stage for idd-issue: re-evaluate after issue info gathered
function reresolve_after_step2(initial, step2_context):
    if initial was forced (--target) or chosen by ask_each_time:
        return initial  # respect explicit user choice

    # Re-evaluate predicates with title/type/label/body now known
    new_match = first(c in config.candidates where evaluate(c.when, full_context))
    if new_match exists AND new_match != initial:
        if AskUserQuestion("Switch to {new_match}?", default=yes):
            return new_match
    return initial
```

When `Single(T)` is returned: ordinary issue creation in repo `T`.
When `Group(repos)` is returned: see Mechanism 6 — primary + tracking issues with cross-linking.

## When skills should write back to config

Only `idd-issue` writes back to config, and only in these specific cases:

1. **First-run fork detection** chose a target and there was no prior config — write the chosen target to `$PWD/.claude/issue-driven-dev.local.json`
2. **First-run non-fork** auto-resolved origin — write to `$PWD/.claude/issue-driven-dev.local.json`

In all other cases (--target override, candidates pick, walk-up to existing config), the config is **read-only**.

## Implementing in a skill

A skill SKILL.md should reference this protocol rather than re-explaining the algorithm:

```markdown
## Configuration

Reads target repo per [config-protocol.md](../../references/config-protocol.md).
Supports `--target owner/repo` flag for one-off override.
```

If the skill needs to know specific resolution behavior beyond reading `github_repo`, document that diff explicitly.

## Edge cases

| Case | Behavior |
|------|----------|
| Multiple `.claude/issue-driven-dev.local.json` on path | Closest to `cwd` wins (walk-up stops at first) |
| `cwd` is outside `$HOME` (e.g. `/tmp`) | Walk up stops at `/`; if no config found, falls to mechanism 5 |
| `candidates` exists but `ask_each_time: false` AND no `when` matches | Top-level `github_repo` is used; candidates available only via `--target <label-or-repo>` |
| `--target` matches a candidate's label | Use that candidate's fields |
| `--target` is `owner/repo` not in candidates | Use it directly with default `attachments_release` |
| `--target group:<label>` | Look up named group in walked-up config; if not found, error |
| Config exists but `github_repo` empty | Treat as "config missing", fall through to mechanism 5 |
| User on a fork with `tracking_upstream` set | Continue routing per the field (idd-issue handles cross-linking; other skills use `github_repo` only) |
| Multiple candidates' `when` clauses match | First (in array order) wins; document this in user-facing error if ambiguity is suspected |
| A group's `when` matches AND a candidate's `when` matches | Group wins (stronger intent — multi-repo coordination) |
| Group has zero `primary` or multiple `primary` | Validation error; refuse to create. Log clear message. |
| Group's primary creation succeeds but tracking fails | Do NOT roll back. Report which succeeded; user retries failed ones with `--target` |
| Predicate references content (title/label) at Step 0.5 | Skip — only re-evaluable at Step 2 stage. Falls through to default for Step 0.5 pass. |

## Migration from v2.22.x

No migration needed. Existing single-target configs continue to work. Users can opt into:

- `candidates` + `ask_each_time` for multi-target prompting (Phase 1, v2.23.0+)
- Multiple per-directory `.local.json` files for cascading (Phase 1, v2.23.0+)
- `--target` flag for one-off overrides (Phase 1, v2.23.0+)
- `candidates[].when` predicates for auto-routing (Phase 2A, v2.24.0+)
- `groups` for multi-repo coordinated issues (Phase 2B, v2.25.0+)

These are all additive.

## Worked examples

### Example 1: Monorepo with sub-package routing by path

```json
// ~/Developer/big-monorepo/.claude/issue-driven-dev.local.json
{
  "github_repo": "owner/big-monorepo",
  "candidates": [
    {
      "label": "Music sub-package",
      "github_repo": "owner/music",
      "when": { "path_contains": "/packages/music" }
    },
    {
      "label": "API sub-package",
      "github_repo": "owner/api",
      "when": { "path_contains": "/packages/api" }
    }
  ]
}
```

`cd ~/Developer/big-monorepo/packages/music/src && /idd-issue` → auto-routes to `owner/music`.
`cd ~/Developer/big-monorepo/docs && /idd-issue` → no match, falls to top-level `owner/big-monorepo`.

### Example 2: Same path, route by issue topic

```json
{
  "github_repo": "owner/main",
  "candidates": [
    {
      "label": "Plugin marketplace",
      "github_repo": "PsychQuant/psychquant-claude-plugins",
      "when": { "title_matches": "(?i)\\b(plugin|skill|hook)\\b" }
    },
    {
      "label": "MCP server",
      "github_repo": "PsychQuant/che-word-mcp",
      "when": { "all": [
        { "label_in": ["mcp"] },
        { "title_matches": "(?i)word|docx" }
      ]}
    }
  ]
}
```

Predicates evaluated in two passes — Step 0.5 sees nothing matches (no path predicates), so tentative default = `owner/main`. After Step 2 gathers title/labels, re-evaluation kicks in. If user typed a title with "plugin", confirm switching to `psychquant-claude-plugins`.

### Example 3: Cross-package bug reported in 3 repos

```json
{
  "github_repo": "PsychQuant/foo",
  "groups": [
    {
      "label": "Cross-stack: foo+bar+glue",
      "repos": [
        {"github_repo": "PsychQuant/foo",  "role": "primary"},
        {"github_repo": "PsychQuant/bar",  "role": "tracking"},
        {"github_repo": "PsychQuant/glue", "role": "tracking"}
      ],
      "when": { "label_in": ["cross-package"] }
    }
  ],
  "ask_each_time": false
}
```

User runs `/idd-issue`, attaches label `cross-package`. Re-resolve picks the group:
1. Creates primary issue in `PsychQuant/foo` → `#42`
2. Creates tracking issue in `bar` → `#15`, body starts `Tracking primary: PsychQuant/foo#42`
3. Creates tracking issue in `glue` → `#8`, body starts `Tracking primary: PsychQuant/foo#42`
4. Comments on `foo#42`: `Tracked in: PsychQuant/bar#15, PsychQuant/glue#8`
