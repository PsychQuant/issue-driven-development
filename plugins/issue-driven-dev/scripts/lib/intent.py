"""intent.py — was the run's intent confirmed, and did anyone else get involved? (#392)

Split out of close-stage.py (r5: the helper passed 800 lines). The close stage
merges without a person only when both answers allow it; each check raises
Stop with the reason. Threat model (decision 6568180861): the orchestrator can
be wrong, not deceptive.
"""

import os
import re

import rendered
from ghread import (Stop, TRUSTED, can_write, connection, entry_count, first_line, gh_json, html_root,
                    latest_diagnosis, run_cmd, ts)

SCRIPTS = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
# Reason literals of the structured records an unattended run leaves when it
# takes a decision a person would otherwise confirm (rules/append-vs-modify.md
# § Reason pattern registry). Matched only as a record's `- **Reason**:` line in
# the latest Diagnosis, outside code fences, so prose that names them does not count.
OPEN_STATUSES = ("surfaced", "deferred")
INTENT_SKIP_REASONS = ("unattended-auto-Step-3.4-layerV-deferred", "unattended-auto-Step-4-choice-default")
REASON_LINE_RE = re.compile(r"^Reason\s*[:：]")
DECISION_HEAD_RE = re.compile(r"^#{1,6}[ \t]*(?:\U0001F3AF[ \t]*)?Decision\b")
ORIGINAL_RE = re.compile(r"(?m)^>[ \t]*\*\*Original")


def issue_meta(repo, n):
    """Author, body edits and comment deletions of the issue, in one GraphQL read."""
    owner, name = repo.split("/", 1)
    actor = "createdAt actor{login __typename}"
    q = ("query($o:String!,$r:String!,$n:Int!){repository(owner:$o,name:$r){issue(number:$n)"
         "{state author{login} editor{login} userContentEdits(first:100){totalCount nodes{editedAt editor{login}}}"
         " timelineItems(last:100,itemTypes:[COMMENT_DELETED_EVENT,LABELED_EVENT,UNLABELED_EVENT,RENAMED_TITLE_EVENT,"
         "CLOSED_EVENT,REOPENED_EVENT]){totalCount filteredCount nodes{__typename"
         " ... on CommentDeletedEvent{createdAt deletedCommentAuthor{login}}"
         f" ... on LabeledEvent{{{actor}}} ... on UnlabeledEvent{{{actor}}} ... on RenamedTitleEvent{{{actor}}}"
         f" ... on ClosedEvent{{{actor}}} ... on ReopenedEvent{{{actor}}}}}}}}}}}}}")
    data = gh_json(["api", "graphql", "-f", f"query={q}", "-f", f"o={owner}", "-f", f"r={name}", "-F", f"n={n}"],
                   "the issue's author, edits and deleted comments")
    issue = ((data.get("data") or {}).get("repository") or {}).get("issue")
    if not isinstance(issue, dict):
        raise Stop("could not read the issue's author, edits and deleted comments — not merging")
    return issue


def check_meeting(comments):
    body = latest_diagnosis(comments)
    rc, out, err = run_cmd(["bash", "-c", '. "$1/lib/actionability.sh" && idd_diagnosis_type "$2"', "_", SCRIPTS, body])
    if rc != 0:
        raise Stop("could not re-read the Diagnosis type")
    if out.strip() == "meeting":
        raise Stop("the latest trusted Diagnosis records type meeting — meeting issues are never merged or pushed")


def check_issue_authors(repo, meta):
    """The issue's author and the last editor of its body must be able to write.

    The issue text is what implement builds and verify checks against; on a
    public repo anyone can open one, and an author can edit it after a
    maintainer read it. Without a person merging, that text must come from
    someone who could have pushed the change anyway (#392 verify r2 #4).
    """
    author = (meta.get("author") or {}).get("login")
    editor = (meta.get("editor") or {}).get("login")
    if not author:
        raise Stop("could not read the issue's author — not merging")
    for role, login in (("author", author), ("last editor", editor)):
        if login and not can_write(repo, login):
            raise Stop(f"the issue's {role} {login} has no write access — a person reviews and merges this one")


def check_others(me, since, comments, meta):
    """Nobody but this account touched the issue after the run began (#392 verify r4 #4, #48).

    The run read the issue when it started; what arrives later is intent the
    run never read: a new or edited comment (an objection, a scope change), an
    edit to the issue text, or a comment deleted after diagnose had read it
    (an outsider can post an instruction and delete it once the Diagnosis
    notification arrives). Any of these means a person is involved, so the run
    stays at verified. Bots are exempt: a repo admin installed them. This
    account's own comments are the run's, and cannot be told apart from a
    person typing as this account (a known limit).
    """
    for c in comments:
        login = c.get("login") or "an unknown account"
        if login == me or c.get("type") == "Bot":   # bots: installed by a repo admin (also exempt in check_intent)
            continue
        # The run itself rewrites the dashboard comment, whoever posted it (r6 #39).
        if ts(c.get("created_at")) < since and "<!-- idd:dashboard -->" in (c.get("body") or ""):
            continue
        if ts(c.get("created_at")) >= since or ts(c.get("updated_at")) >= since:
            raise Stop(f"{login} commented on the issue (or edited a comment) after the run started — "
                       "intent the run never read; a person reviews and merges this one")
    if meta.get("state") != "OPEN":
        raise Stop(f"the issue is {meta.get('state') or 'not readable'} — someone closed it during the run; not merging")
    edits = connection(meta, "userContentEdits", since, "editedAt", "the issue's edit history")
    for e in edits:
        who = (e.get("editor") or {}).get("login")
        if who != me and ts(e.get("editedAt")) >= since:
            raise Stop(f"{who or 'an unknown account'} edited the issue text after the run started — "
                       "a person reviews and merges this one")
    for d in connection(meta, "timelineItems", since, "createdAt", "the issue's timeline"):
        if ts(d.get("createdAt")) < since:
            continue
        if d.get("__typename") == "CommentDeletedEvent":
            who = (d.get("deletedCommentAuthor") or {}).get("login")
            if who != me:
                raise Stop(f"a comment by {who or 'an unknown account'} was deleted after the run started — "
                           "the run may have read it; a person reviews and merges this one")
            continue
        actor = d.get("actor") or {}
        if actor.get("login") != me and actor.get("__typename") != "Bot":
            what = {"LabeledEvent": "labelled", "UnlabeledEvent": "unlabelled", "RenamedTitleEvent": "retitled",
                    "ClosedEvent": "closed", "ReopenedEvent": "reopened"}.get(d.get("__typename"), "changed")
            raise Stop(f"{actor.get('login') or 'an unknown account'} {what} the issue after the run started (r5 #6) — "
                       "a person reviews and merges this one")


def is_decision(comment):
    """A Decision comment opens with the heading (leading HTML comments aside) and quotes what a person said (r6 #15, #19)."""
    body = comment.get("body") or ""
    lines = [l for l in body.lstrip("\ufeff").splitlines() if l.strip() and not l.strip().startswith("<!--")]
    return bool(lines and DECISION_HEAD_RE.match(lines[0].strip()) and ORIGINAL_RE.search(body))


def reason_records(comment):
    """Registry literals of the `- **Reason**: <literal>` lines GitHub shows in a comment (code blocks excluded)."""
    out = []
    for _, run, _ in rendered.lines(html_root(comment.get("body_html"), comment.get("body"))):
        text = rendered.line_text(run)   # any line labelled Reason naming a literal: format drift still counts (r6 #12, #16)
        if REASON_LINE_RE.match(text):
            out.extend(lit for lit in INTENT_SKIP_REASONS if lit in text)
    return out


def has_corrections(comment):
    """The comment shows a Proposed Corrections section with content, at any heading level and inside any container."""
    root = html_root(comment.get("body_html"), comment.get("body"))
    for section in rendered.sections(root, "proposed corrections", max_level=6, ignore_case=True, deep=True):
        for table in rendered.tables(section):
            if any(not head and any(cells) for head, cells in rendered.table_rows(table)):
                return True
        if not rendered.tables(section) and any(rendered.norm(rendered.text_of(n)) for n in section):
            return True   # a section GitHub did not draw as a table (r6 #16, #26)
    return False


def open_clarity_row(issue):
    """The text of an open clarity question the issue body shows, or None.

    Read wherever GitHub shows it, without looking at the heading above it (r7 #2: a block inside a details
    element, under a level-4 heading or in a quote was missed while the check went through top-level
    `Clarity Surface` headings). Open means:
    - in a table with a `Status` header: a row whose Status cell starts with `surfaced` or `deferred`
      (a note after the word, as in `deferred (see retry hint)`, does not close it);
    - in a table without one: a row with a cell that is exactly `surfaced` or `deferred`;
    - outside any table: a line with pipes GitHub did not draw as a table whose cell starts with one of them.
    A resolved row keeps its Reason and may quote the words in other cells, so only the status decides.
    """
    root = html_root(issue.get("body_html"), issue.get("body"))
    for table in rendered.tables([root]):
        rows = rendered.table_rows(table)
        header = [c.strip().lower() for c in rows[0][1]] if rows and rows[0][0] else []
        status = header.index("status") if "status" in header else None
        for head, cells in rows:
            if head:
                continue
            if status is not None:
                if status < len(cells) and cells[status].strip().lower().startswith(OPEN_STATUSES):
                    return " | ".join(cells)
            elif any(cell.strip().lower() in OPEN_STATUSES for cell in cells):
                return " | ".join(cells)
    for el, run, _ in rendered.lines(root):
        if el.tag in ("td", "th"):
            continue
        for text in rendered.raw_line_texts(run):
            if "|" in text and any(cell.strip().lower().startswith(OPEN_STATUSES) for cell in text.split("|")):
                return text
    return None


def check_intent(repo, n, st, comments, issue):
    """Merge without a person only when the intent was confirmed (#392 decisions 6566557673, 6567272352, 6568180861,
    and of 2026-11-10: 6761657951, 6761899504). Returns the number of comments whose Proposed Corrections nobody answered.

    Threat model (decision 6568180861): the orchestrator can be wrong, not
    deceptive. An unattended run takes some decisions a person would
    otherwise confirm; each shows in the run's own state or leaves a record.
    Everything is read from GitHub's rendering, so code blocks and quotes a
    person does not read as content are not read here either (r5 #12).
    - every comment comes from someone with write access (comments and their
      attachments steer diagnose and implement); bots are exempt, as in
      check_others (r5 #19);
    - the issue body shows no open clarity question (open_clarity_row);
    - the Diagnosis Phase 2 routed on has a readable tier. Which tier does not
      matter: since the decision of 2026-11-10 an unattended run that
      implemented a Plan, Spectra or SDD-warranted issue merges like any other;
    - no comment carries a skipped-confirmation record (`- **Reason**:` line
      with a Layer V deferral or choice-first default literal) that no later
      Decision comment answered — any comment, not only the latest Diagnosis,
      so a record posted as its own comment or an unattended re-diagnosis does
      not hide it (r5 #7, #18, #20);
    Proposed Corrections nobody answered do not stop the stage (decision of
    2026-11-10); the comments that list them after the latest Decision are
    counted and returned, and the run report says they were not applied.
    The Stage 1 strategy confirmation an unattended diagnose performs itself
    counts as attention, not as a skipped confirmation (decision 6568180861).
    """
    for c in comments:
        login = c.get("login") or ""
        if c.get("type") == "Bot":
            continue
        if not login or not can_write(repo, login):
            raise Stop(f"a comment on the issue is by {login or 'an unknown account'}, who has no write access — "
                       "intent not confirmed; a person reviews and merges this one")
    row = open_clarity_row(issue)
    if row is not None:
        raise Stop(f"the issue has an open question (a clarity row still surfaced or deferred: {row[:80]}) — intent not "
                   "confirmed; a person reviews and merges this one")
    diag = latest_diagnosis(comments)
    if not diag:
        raise Stop("no trusted Diagnosis on the issue — intent not confirmed")
    rc, out, err = run_cmd(["bash", "-c", '. "$1/lib/actionability.sh" && idd_parse_complexity "$2"', "_", SCRIPTS, diag])
    tier = out.strip() if rc == 0 else ""
    if not tier:
        raise Stop("the latest Diagnosis has no readable Complexity tier — intent not confirmed")
    decided = max([ts(c.get("created_at")) for c in comments
                   if c.get("type") != "Bot" and is_decision(c)]
                  or [0])
    unanswered = 0
    for c in comments:
        if c.get("type") == "Bot" or ts(c.get("created_at")) <= decided:
            continue
        found = reason_records(c)
        if found:
            raise Stop(f"a comment records a skipped confirmation ({found[0]}) that no later Decision answered — "
                       "a person reviews and merges this one")
        if has_corrections(c):
            unanswered += 1
    return unanswered


def check_pr_people(repo, pr, me):
    """The PR is this account's, not a draft, and nobody else touched it (r4 #15, #22; r5 #2, #16, #33).

    The run itself never comments on, reviews, labels or edits its PR (verify
    runs in branch mode and posts on the issue), so any comment or review
    there — an objection, CHANGES_REQUESTED, a PR-mode verify report — or a
    label, title or body change by another account came from a person.
    """
    owner, name = repo.split("/", 1)
    actor = "createdAt actor{login __typename}"
    q = ("query($o:String!,$r:String!,$p:Int!){repository(owner:$o,name:$r){pullRequest(number:$p){isDraft reviewDecision "
         "author{login} reviews(last:100){totalCount nodes{author{login __typename} state}} "
         "comments(last:100){totalCount nodes{author{login __typename}}} "
         "userContentEdits(first:100){totalCount nodes{editor{login}}} "
         "timelineItems(last:100,itemTypes:[LABELED_EVENT,UNLABELED_EVENT,RENAMED_TITLE_EVENT,CONVERT_TO_DRAFT_EVENT,"
         "CLOSED_EVENT,REOPENED_EVENT]){totalCount filteredCount nodes{__typename"
         f" ... on LabeledEvent{{{actor}}} ... on UnlabeledEvent{{{actor}}} ... on RenamedTitleEvent{{{actor}}}"
         f" ... on ConvertToDraftEvent{{{actor}}} ... on ClosedEvent{{{actor}}} ... on ReopenedEvent{{{actor}}}}}}}}}}}}}")
    data = gh_json(["api", "graphql", "-f", f"query={q}", "-f", f"o={owner}", "-f", f"r={name}", "-F", f"p={pr}"],
                   f"the reviews and comments of PR #{pr}")
    view = ((data.get("data") or {}).get("repository") or {}).get("pullRequest")
    if not isinstance(view, dict):
        raise Stop(f"could not read the reviews and comments of PR #{pr} — not merging")
    author = (view.get("author") or {}).get("login")
    if author != me:
        raise Stop(f"PR #{pr} was opened by {author or 'an unknown account'}, not by this account — not merging someone else's PR")
    if view.get("isDraft"):
        raise Stop(f"PR #{pr} is a draft — not merging")
    if view.get("reviewDecision") == "CHANGES_REQUESTED":
        raise Stop(f"PR #{pr} has changes requested — a person reviews and merges this one")
    for kind in ("reviews", "comments", "userContentEdits", "timelineItems"):
        conn = view.get(kind) or {}
        nodes = conn.get("nodes") or []
        if entry_count(conn, kind, f"PR #{pr}'s timeline") > len(nodes):
            raise Stop(f"PR #{pr} has more {kind} than one read returns — not merging; a person reviews this one")
        for node in nodes:
            who = node.get("author") or node.get("actor") or node.get("editor") or {}
            if kind == "userContentEdits":
                if who.get("login") != me:
                    raise Stop(f"{who.get('login') or 'an unknown account'} edited PR #{pr}'s description — "
                               "a person is involved; they merge this one")
                continue
            if who.get("__typename") == "Bot" or (kind == "timelineItems" and who.get("login") == me):
                continue
            who_name = who.get("login") or "an unknown account"
            if kind in ("reviews", "comments"):
                raise Stop(f"PR #{pr} has a {kind[:-1]} by {who_name} — a person is involved; they merge this one")
            what = {"LabeledEvent": "labelled", "UnlabeledEvent": "unlabelled", "RenamedTitleEvent": "retitled",
                    "ConvertToDraftEvent": "turned to draft", "ClosedEvent": "closed",
                    "ReopenedEvent": "reopened"}.get(node.get("__typename"), "changed")
            raise Stop(f"{who_name} {what} PR #{pr} — a person is involved; they merge this one")
