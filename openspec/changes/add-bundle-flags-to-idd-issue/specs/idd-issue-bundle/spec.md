## ADDED Requirements

### Requirement: idd-issue SHALL accept --parent flag to register child in parent task list

The `idd-issue` skill SHALL accept a `--parent <N>` flag where `<N>` is a positive integer issue number in the same target repository. After successfully creating the child issue, the skill SHALL PATCH the parent issue's body to add a task list entry referencing the child issue.

The PATCH operation SHALL be idempotent: invoking `--parent <N>` multiple times for the same child issue SHALL NOT produce duplicate entries.

The PATCH operation SHALL preserve existing parent body content: it SHALL NOT reorder existing entries, modify text outside the targeted task list section, or remove unrelated checkboxes.

#### Scenario: First child added to parent with existing task list

- **WHEN** `idd-issue --parent 100` is invoked and parent #100 body contains a task list section with `- [ ] #101`
- **THEN** the new child #102 is created
- **AND** parent #100 body is PATCHed to append `- [ ] #102` to the existing task list section
- **AND** the existing `- [ ] #101` entry is preserved unchanged

#### Scenario: Idempotent re-invocation does not duplicate entry

- **WHEN** `idd-issue --parent 100` is invoked, child #102 is created, parent task list now contains `- [ ] #102`
- **AND** `idd-issue --parent 100` is invoked again referencing the same child #102 (e.g., retry after partial failure)
- **THEN** the parent body task list still contains exactly one `- [ ] #102` entry

#### Scenario: Parent without existing task list creates Children section

- **WHEN** `idd-issue --parent 100` is invoked and parent #100 body contains no task list checkboxes
- **THEN** the skill SHALL append a `## Children` section at the end of parent #100 body
- **AND** the `## Children` section SHALL contain `- [ ] #<new-child>` as its first entry

#### Scenario: Parent in different repo refuses operation

- **WHEN** `idd-issue --parent 100` is invoked, but parent #100 belongs to a repo different from the resolved target repo
- **THEN** the skill SHALL refuse to create the child issue
- **AND** SHALL emit an error message naming both the resolved target repo and the parent's repo
- **AND** SHALL suggest using the `groups` mechanism for cross-repo coordinated issues

##### Example: Idempotent task list edit algorithm

| Parent body before | Invocation | Parent body after |
| ----- | ----- | ----- |
| `## Children\n- [ ] #101\n- [ ] #102\n` | `--parent <P> #103` | `## Children\n- [ ] #101\n- [ ] #102\n- [ ] #103\n` |
| `## Children\n- [ ] #101\n- [ ] #102\n- [ ] #103\n` | `--parent <P> #103` (retry) | `## Children\n- [ ] #101\n- [ ] #102\n- [ ] #103\n` (no-op) |
| `Plain prose body, no checkboxes` | `--parent <P> #103` | `Plain prose body, no checkboxes\n\n## Children\n- [ ] #103\n` |
| `## Repro\n- [ ] open app\n- [ ] click X` | `--parent <P> #103` | `## Repro\n- [ ] open app\n- [ ] click X\n\n## Children\n- [ ] #103\n` (creates new section, does not contaminate Repro) |

### Requirement: idd-issue SHALL accept --blocked-by flag with three-layer fallback

The `idd-issue` skill SHALL accept a `--blocked-by <M>[,<M2>...]` flag where each value is a positive integer issue number. After creating the child issue, the skill SHALL apply the dependency annotation through three layers:

1. The skill SHALL prepend a blockquote `> Blocked by #M` (one line per `M`) to the child issue body, regardless of subsequent layer outcomes.
2. The skill SHALL attempt the GitHub GraphQL `addBlockedByDependency` mutation for each `M`. Failure SHALL NOT abort the operation;the skill SHALL emit a warning naming the failed `M` and continue.
3. When `--parent <N>` is also provided, the skill SHALL annotate the corresponding parent task list entry as `- [ ] #child (blocked by #M)` to surface dependency at parent view level.

#### Scenario: Native dependency mutation succeeds

- **WHEN** `idd-issue --blocked-by 50` is invoked and the GraphQL `addBlockedByDependency` mutation returns success
- **THEN** child body contains `> Blocked by #50` blockquote
- **AND** GitHub UI displays the native "Blocked by" dependency on the child issue
- **AND** no warning is emitted

#### Scenario: Native dependency mutation fails, body annotation persists

- **WHEN** `idd-issue --blocked-by 50` is invoked and the GraphQL mutation fails (repo not enabled / permission / API error)
- **THEN** child body still contains `> Blocked by #50` blockquote
- **AND** the skill SHALL emit a warning naming the mutation failure and the blocked-by target
- **AND** the child issue creation SHALL NOT be aborted

#### Scenario: Multiple blocked-by targets

- **WHEN** `idd-issue --blocked-by 50,51,52` is invoked
- **THEN** child body contains three blockquote lines: `> Blocked by #50`, `> Blocked by #51`, `> Blocked by #52`
- **AND** the GraphQL mutation is attempted independently for each target
- **AND** failure of one target SHALL NOT prevent attempts for the others

##### Example: Three-layer fallback outcomes

| GraphQL result | Body blockquote | Parent annotation (when --parent used) | Final state |
| ----- | ----- | ----- | ----- |
| Success | Present | Present | All three layers active |
| API failure | Present | Present | UI lacks native warning, but markdown still readable |
| Repo not enabled | Present | Present | Same as API failure, plus one-time warning |
| Both --blocked-by and --parent absent | N/A | N/A | Child created normally without dependency annotation |

### Requirement: idd-issue SHALL accept --bundle-mode flag for batch bundle creation

The `idd-issue` skill SHALL accept a `--bundle-mode <ordered|unordered>` flag valid only when the invocation creates two or more child issues in a single call. The flag SHALL trigger the following orchestration:

1. The skill SHALL create a parent epic issue with a title derived from the bundle's overall theme (asked from user if not derivable from input).
2. The skill SHALL create N child issues, each with `--parent <epic-N>` semantics applied automatically.
3. When `--bundle-mode ordered`, the skill SHALL apply `--blocked-by <prev-child>` to each child after the first, forming a strict chain (child[i] blocked by child[i-1] only).
4. When `--bundle-mode unordered`, the skill SHALL omit blocked-by relationships entirely and produce only the parent task list.

#### Scenario: Ordered bundle creates parent + chain

- **WHEN** `idd-issue --bundle-mode ordered "epic title:item1; item2; item3"` is invoked
- **THEN** an epic issue is created (e.g., #100)
- **AND** three child issues are created (#101, #102, #103) each linked to #100 via task list
- **AND** #102 body contains `> Blocked by #101`
- **AND** #103 body contains `> Blocked by #102`
- **AND** #101 has no blocked-by annotation (first in chain)

#### Scenario: Unordered bundle skips blocked-by

- **WHEN** `idd-issue --bundle-mode unordered "epic title:item1; item2; item3"` is invoked
- **THEN** parent epic and three child issues are created
- **AND** parent body task list lists all three children
- **AND** none of the children contain `Blocked by` blockquote
- **AND** no GraphQL mutation is attempted

#### Scenario: Single-issue invocation rejects bundle-mode

- **WHEN** `idd-issue --bundle-mode ordered "single item"` is invoked with only one item
- **THEN** the skill SHALL refuse the invocation
- **AND** SHALL emit an error message stating bundle-mode requires two or more items

##### Example: Bundle creation result matrix

| Input items | Mode | Parent | Children | Blocked-by chain |
| ----- | ----- | ----- | ----- | ----- |
| 3 items | ordered | 1 epic created | 3 children with parent task list | child2 → child1, child3 → child2 |
| 4 items | ordered | 1 epic created | 4 children | child2 → child1, child3 → child2, child4 → child3 |
| 3 items | unordered | 1 epic created | 3 children with parent task list | none |
| 1 item | (any) | refused | refused | refused |

### Requirement: Bundle mechanism SHALL coexist orthogonally with milestone, group, and sister sweep

Bundle flags SHALL NOT modify the behavior of existing `idd-issue` mechanisms:

- Step 4.5 auto-milestone (when source is a document with two or more issues) SHALL still create the milestone and assign all bundle children to it.
- Step 4.7 sister sweep SHALL still scan body draft + linked attachments + recent session conversation for orphan-mention markers and apply the IC_R011 checkpoint.
- Step 0.5 / Step 2.5 target resolution SHALL run before any bundle flag handling;cross-repo bundle attempts SHALL refuse per the cross-repo rule.
- The `groups` mechanism (cross-repo primary + tracking) SHALL remain the canonical mechanism for cross-repo coordinated issues;bundle flags SHALL NOT attempt to substitute for groups.

#### Scenario: Bundle within document-source invocation gets milestone

- **WHEN** `idd-issue --bundle-mode ordered <source.docx>` is invoked and the document yields three items
- **THEN** Step 4.5 creates a milestone derived from the document title
- **AND** the parent epic and all three children are assigned to that milestone
- **AND** the parent body task list and ordered chain are still created per bundle flag semantics

#### Scenario: Sister sweep runs on parent epic

- **WHEN** `idd-issue --bundle-mode ordered ...` creates a parent epic
- **THEN** Step 4.7 sister sweep evaluates the parent epic's body draft + attachments + recent conversation for orphan markers
- **AND** if hits found, the IC_R011 3-option AskUserQuestion fires per canonical reference
- **AND** sibling issues filed by sister sweep SHALL NOT be added to the parent epic's task list (they are orthogonal concerns, not bundle children)
