## REMOVED Requirements

### Requirement: in-place-correction SHALL replace confirmed errors only after archiving the prior version

**Reason**: #424 removes the confirmation; "confirmed" no longer holds.

**Migration**: Replaced by "in-place-correction SHALL replace errors only after archiving the prior version".

## ADDED Requirements

### Requirement: in-place-correction SHALL replace errors only after archiving the prior version

The `in-place-correction` category SHALL cover replacing content that is wrong, as the user states in a discussion or agrees to when an IDD skill proposes it, in an issue body or a comment whose author is the authenticated `gh` user (never a bot's comment, and not the OWNER's unless the OWNER runs it), including content that would otherwise fall under `append-only` (published comments) or the issue body above the `---` separator. An action in this category SHALL (a) archive the prior full text of the target before writing, (b) report its diff and preview, (c) leave a marker that identifies the archive entry without a filesystem path and a visible line stating the date and what is now correct, and (d) refuse the regions that remain `verbatim-preserve`. `/idd-edit --correct` SHALL be the only action declared in this category; other skills SHALL reach it by invoking `/idd-edit`.

#### Scenario: Correction declared in idd-edit

- **WHEN** a plugin contributor reads `plugins/issue-driven-dev/skills/idd-edit/SKILL.md`
- **THEN** the `--correct` mode description SHALL contain the inline note `(category: in-place-correction)`

#### Scenario: Another skill attempts a direct correction

- **WHEN** a skill other than `idd-edit` replaces published comment text to fix an error without invoking `/idd-edit --correct`
- **THEN** the action SHALL be refused at skill review time as an undeclared or misdeclared modify-action
