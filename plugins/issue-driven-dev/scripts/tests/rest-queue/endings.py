#!/usr/bin/env python3
"""endings.py <rest-queue.py> <process-attachments.sh> — the Example "endings of the single-issue pipeline" (#478).

One temporary repository (with a bare origin) per row of that table. Every one holds files that were there before
the run and that git ignores; the run state is written by the real `start`, `next` and `record`. After settle,
with either exit code, treecheck.py accounts for every file from the file system, not from `git status`.
What `idd-diagnose` leaves is written by
the real writer, `process-attachments.sh download`, with gh and curl replaced on PATH; the line in
routing-stats.jsonl is appended here, because its writer (idd-route) is an external program; the meeting row
repeats the two git commands of the meeting unwind; a rejecting commit hook and an ignore rule of the issue's own
branch are really installed and committed. GitHub's side of each row (the phase, `### Blocking`, the Diagnosis
type) is what that ending leaves there, so the last column is checked against the class a later run really sees.
Each row then runs `rest-queue.py settle` and checks the result, not the steps:

  exit 0  the working tree is on the default branch and `git status --porcelain` prints nothing (the check
          every issue on the PR path starts with); the branches of #5 are those of the row and the run state
          names exactly them; a path that was left over is either in the commit settle made, byte for byte, or
          it is the manifest or a file the manifest vouches for (nothing else may be discarded); a stash the row
          names can be applied again and gives the file back; and a later run does with #5 what the row says
  exit 3  HEAD, the branch, every branch tip and the output of git status are unchanged, and there is one
          reason line that names #5

A step the report tells a person to take is taken here: a kept branch without an upstream is deleted, and a new
run then hands the issue out; a stash is applied where the report says (on the kept branch, or in the working tree
when that branch is gone). For a row whose issue is closed, the report is checked and a later run must not know
the issue.

Every cell of the table is compared with the spec when the spec is on disk (a change that is not archived yet
wins over the main spec): the row names, the exit codes, the branches afterwards and the later run against what the
rows here expect, and the two cells that describe the fixture against the copy in CELLS.
"""
import glob
import hashlib
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import treecheck  # noqa: E402

RQ, PA = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.abspath(os.path.join(HERE, "..", "..", "..", "..", ".."))
GIT_ENV = dict(os.environ, GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_NOSYSTEM="1", GIT_TERMINAL_PROMPT="0",
               GIT_AUTHOR_NAME="t", GIT_AUTHOR_EMAIL="t@example.invalid",
               GIT_COMMITTER_NAME="t", GIT_COMMITTER_EMAIL="t@example.invalid")
FOLDER = ".claude/.idd/attachments/issue-5/"
M = FOLDER + "_manifest.json"
DOC = FOLDER + "spec.docx"
LOG = ".claude/.idd/routing-stats.jsonl"
PROPOSAL = "openspec/changes/idd-5-x/proposal.md"
B = "idd/5-x"
STATE = ".claude/.idd/state/idd-all-rest.json"
STASH_MESSAGE = f"idd rest: files of #5 that only {B} ignores"
STASH_TRACKED = f"idd rest: files of #5 that {B} ignores and the default branch tracks"
# in every row: in the working tree before the run, and ignored there (the top rule `local/`, the rule `.env` of tools/.gitignore)
HERE_BEFORE = {"tools/.env": "TOKEN=ghp_secret\n", "local/settings.json": '{"mine": true}\n'}

# on: where the working tree is when settle runs · work: the branch has a commit of its own · leave: what the
# ending leaves · gh: the open issues on GitHub after the ending (scenario.py; a closed #5 is not among them) ·
# exit / branches / committed (the paths of settle's commit, None = no commit) / discarded / later (what a later
# run does with #5) · intact: files that must hold this content after an exit 3
ROWS = [
    dict(id="closed-before-start", on="main", outcome="closed", gh="9", exit=0, branches=[], later="closed"),
    dict(id="existing-work", on="main", exit=0, branches=[], later="handed"),
    dict(id="stop-before-download", on="own", exit=0, branches=[], later="handed"),
    dict(id="stop-after-diagnose", on="own", leave=["manifest"], exit=0, branches=[], discarded=[M], later="handed"),
    dict(id="stop-after-diagnose-attachments", on="own", leave=["attachment"], exit=0, branches=[],
         discarded=[M, DOC], later="handed"),
    dict(id="stop-after-diagnose-ignored-attachments", on="own", ignore_files=True, leave=["attachment"], exit=0,
         branches=[], discarded=[M], later="handed"),
    dict(id="stop-after-diagnose-tracked-manifest", on="own", tracked_manifest=True, leave=["manifest"], exit=0,
         branches=[], discarded=[M], later="handed"),
    dict(id="stop-after-diagnose-failed-download", on="own", leave=["failed-download"], exit=0, branches=[],
         discarded=[M, DOC], later="handed"),
    dict(id="stop-after-diagnose-foreign-file", on="own", leave=["manifest", "foreign"], exit=0, branches=[B],
         committed=[M, FOLDER + "notes.txt"], later="existing"),
    dict(id="meeting", on="main", meeting=True, gh="5:diag=meeting", exit=0, branches=[B], later="meeting"),
    dict(id="stop-in-implement", on="own", work=True, leave=["edit", "proposal", "manifest"], exit=0, branches=[B],
         committed=["a.txt", PROPOSAL], discarded=[M], later="existing"),
    dict(id="stop-in-implement-attachments", on="own", work=True, leave=["edit", "attachment"], exit=0, branches=[B],
         committed=["a.txt", M, DOC], later="existing"),
    dict(id="stop-in-implement-hooks-reject", on="own", work=True, leave=["edit", "rejecting-hook"], exit=0,
         branches=[B], committed=["a.txt"], no_hooks=True, later="existing"),
    dict(id="stop-in-implement-ignored-files", on="own", work=True, work_ignore=True, leave=["ignored"], exit=0,
         branches=[B], stash=["coverage/"], later="existing"),
    dict(id="stop-before-commit-ignored-files", on="own", origin_ignore=True, leave=["ignored"], exit=0, branches=[],
         stash=["coverage/"], later="handed"),
    # what was there before the run, on a branch that no longer ignores it
    dict(id="stop-rule-deleted", on="own", work=True, work_rm_tools=True, exit=0, branches=[B], later="existing"),
    dict(id="merged-rule-deleted", on="own", work=True, work_rm_tools=True, upstream=True, squash=True, outcome="closed",
         gh="9", exit=0, branches=[B], excluded=["tools/.env"], later="closed"),
    dict(id="stop-rule-rewritten", on="own", work=True, work_rewrite_ignore=True, exit=0, branches=[B], later="existing"),
    dict(id="local-default-rule", on="own", local_rule=True, exit=0, branches=[], later="handed"),
    dict(id="stop-after-verify-failed", on="own", work=True, leave=["manifest", "log"], gh="5:blocking=verify findings",
         exit=0, branches=[B], committed=[LOG], discarded=[M], later="blocked"),
    dict(id="stop-at-close-stage", on="own", work=True, upstream=True, leave=["manifest", "log"],
         gh="5:html=body-verified", exit=0, branches=[B], committed=[LOG], discarded=[M], later="verified"),
    dict(id="merged-and-closed", on="own", work=True, work_manifest=True, upstream=True, squash=True,
         outcome="closed", gh="9", leave=["manifest", "log"], exit=0, branches=[B], committed=[LOG], discarded=[M],
         later="closed"),
    dict(id="on-another-branch", on="wip", exit=3),
    dict(id="leftover-on-default", on="main", leave=["b"], exit=3),
    dict(id="never-committed-place", on="own", work=True, leave=["lock", "edit"], exit=3),
    # a file the issue stopped tracking: the default branch still tracks it until the issue is merged
    dict(id="file-the-default-branch-tracks", on="own", work=True, work_untrack=True, leave=["ignored-tracked"], exit=0,
         branches=[B], stash=["a.txt"], stash_message=STASH_TRACKED, stash_file=("a.txt", "the run wrote this\n"), later="existing"),
    dict(id="merged-file-untracked", on="own", work=True, work_untrack=True, upstream=True, squash=True, outcome="closed",
         gh="9", exit=0, branches=[B], later="closed"),
]

# the cells `The working tree is on` and `What the ending leaves` of each row, as the spec has them
CELLS = {
    'closed-before-start': ('`main`',
        'nothing'),
    'existing-work': ('`main`',
        'nothing'),
    'stop-before-download': ('`idd/5-x`, no commit',
        'nothing'),
    'stop-after-diagnose': ('`idd/5-x`, no commit',
        'the untracked manifest, written by `process-attachments.sh download`'),
    'stop-after-diagnose-attachments': ('`idd/5-x`, no commit',
        'the untracked manifest and the downloaded file, both written by `process-attachments.sh download`'),
    'stop-after-diagnose-ignored-attachments': ('`idd/5-x`, no commit',
        'the untracked manifest, which lists one file'),
    'stop-after-diagnose-tracked-manifest': ('`idd/5-x`, no commit',
        'the tracked manifest, changed by `process-attachments.sh download`'),
    'stop-after-diagnose-failed-download': ('`idd/5-x`, no commit',
        'the untracked manifest, which lists the file as a failed download, and the part of the file that arrived'),
    'stop-after-diagnose-foreign-file': ('`idd/5-x`, no commit',
        'the untracked manifest and `notes.txt`'),
    'meeting': ('`main`',
        'nothing; `idd/5-x` has one commit'),
    'stop-in-implement': ('`idd/5-x`, one commit',
        'a changed `a.txt`, a new `openspec/changes/idd-5-x/proposal.md`, and the untracked manifest'),
    'stop-in-implement-attachments': ('`idd/5-x`, one commit',
        'a changed `a.txt`, the untracked manifest and the downloaded file'),
    'stop-in-implement-hooks-reject': ('`idd/5-x`, one commit',
        'a changed `a.txt`'),
    'stop-in-implement-ignored-files': ('`idd/5-x`, one commit',
        'nothing git shows on that branch; `coverage/report.txt`, ignored there'),
    'stop-before-commit-ignored-files': ('`idd/5-x`, no commit',
        'nothing git shows on that branch; `coverage/report.txt`, ignored there'),
    'stop-rule-deleted': ('`idd/5-x`, one commit',
        'nothing of the run; `tools/.env`, which that branch no longer ignores'),
    'merged-rule-deleted': ('`idd/5-x`, one commit, with an upstream; `origin/main` has the squash commit',
        'nothing of the run; `tools/.env`, which neither branch ignores any more'),
    'stop-rule-rewritten': ('`idd/5-x`, one commit',
        'nothing of the run; `local/settings.json`, which that branch no longer ignores'),
    'local-default-rule': ('`idd/5-x`, no commit',
        'nothing of the run; `settings.local.json`, which that branch does not ignore'),
    'stop-after-verify-failed': ('`idd/5-x`, one commit',
        'the untracked manifest and one new line in the tracked `.claude/.idd/routing-stats.jsonl`'),
    'stop-at-close-stage': ('`idd/5-x`, one commit, with an upstream',
        'the same as `stop-after-verify-failed`'),
    'merged-and-closed': ('`idd/5-x`, one commit, with an upstream; `origin/main` has the squash commit',
        'a changed tracked manifest and one new line in the tracked `.claude/.idd/routing-stats.jsonl`'),
    'on-another-branch': ('`wip`',
        'nothing'),
    'leftover-on-default': ('`main`',
        'an untracked `b.txt`'),
    'never-committed-place': ('`idd/5-x`, one commit',
        'an untracked `.claude/.idd/tree-lock` and a changed `a.txt`'),
    'file-the-default-branch-tracks': ('`idd/5-x`, one commit',
        'nothing git shows on that branch; `a.txt`, ignored there and tracked on `main`'),
    'merged-file-untracked': ('`idd/5-x`, one commit, with an upstream; `origin/main` has the squash commit',
        'nothing git shows on that branch; `a.txt`, ignored there'),
}


def sh(args, cwd=None, env=None, check=True):
    return subprocess.run(args, cwd=cwd, env=env or GIT_ENV, capture_output=True, text=True, check=check)


def git(cwd, *args, check=True):
    return sh(["git", "-C", cwd, *args], check=check).stdout


def write(path, text, mode="w"):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, mode) as fh:
        fh.write(text)


def executable(path, text):
    write(path, text)
    os.chmod(path, 0o755)


def stubs(base):
    """gh and curl as process-attachments.sh calls them: an issue with or without one attachment, and its bytes;
    with CURL_STUB_MODE=fail the download breaks off after part of the file arrived."""
    d = os.path.join(base, "stub")
    os.mkdir(d)
    executable(os.path.join(d, "gh"), """#!/usr/bin/env bash
case "${1:-}" in
  issue) case "${GH_STUB_MODE:-empty}" in
           empty)    printf '{"body":"no attachment here","comments":[]}\\n' ;;
           with_url) printf '{"body":"spec: https://github.com/user-attachments/files/123/spec.docx ok","comments":[]}\\n' ;;
         esac ;;
  auth)  echo stub-token ;;
  *)     echo "gh stub: unhandled: $*" >&2; exit 1 ;;
esac
""")
    executable(os.path.join(d, "curl"), """#!/usr/bin/env bash
out=""; while [ $# -gt 0 ]; do [ "$1" = "-o" ] && out="$2"; shift; done
if [ "${CURL_STUB_MODE:-ok}" = fail ]; then [ -n "$out" ] && printf 'attach' > "$out"; exit 18; fi
[ -n "$out" ] && printf 'attachment bytes\\n' > "$out"
""")
    return d


def download(tree, stub, mode, caller, curl="ok"):
    """The real writer, run from the working tree, for issue 5."""
    env = dict(GIT_ENV, PATH=stub + os.pathsep + os.environ["PATH"], GH_STUB_MODE=mode, CURL_STUB_MODE=curl)
    env["IDD_CALLER"] = caller   # recorded in the manifest as fetched_by
    proc = sh(["bash", PA, "download", "5", "--repo", "o/r"], cwd=tree, env=env, check=False)
    if proc.returncode != 0 and curl == "ok":   # with a broken download the writer itself reports the failure
        raise RuntimeError(f"process-attachments.sh download failed: {proc.stderr.strip()[:300]}")


def template(base):
    origin, tree = os.path.join(base, "tpl", "origin.git"), os.path.join(base, "tpl", "tree")
    os.makedirs(os.path.dirname(origin))
    sh(["git", "init", "-q", "--bare", "-b", "main", origin])
    sh(["git", "init", "-q", "-b", "main", tree])
    write(os.path.join(tree, ".git", "info", "exclude"), ".claude/.idd/state/\n", "a")
    write(os.path.join(tree, "a.txt"), "a\n")
    write(os.path.join(tree, LOG), '{"issue": 1}\n')
    write(os.path.join(tree, "tools", "run.sh"), "#!/bin/sh\n")
    write(os.path.join(tree, "tools", ".gitignore"), ".env\n")
    write(os.path.join(tree, ".gitignore"), "local/\n")
    git(tree, "add", "-A")
    git(tree, "commit", "-q", "-m", "init")
    git(tree, "remote", "add", "origin", origin)
    git(tree, "push", "-q", "-u", "origin", "main")
    # there before any run, and ignored: a person's own files, never the work of an issue
    for path, text in HERE_BEFORE.items():
        write(os.path.join(tree, path), text)


def rq(tree, gh_dir, *args):
    env = dict(GIT_ENV, IDD_GH=os.path.join(HERE, "fake-gh.py"), FAKE_GH_DIR=gh_dir, IDD_CLOSE_STAGE_TEST="1")
    scoped = [] if args[0] == "list" else ["--cwd", tree]
    return sh([sys.executable, RQ, args[0], *scoped, "--repo", "o/r", *args[1:]], env=env, check=False)


def state_of(tree):
    with open(os.path.join(tree, STATE)) as fh:
        return json.load(fh)


def answer(proc):
    try:
        return json.loads(proc.stdout)
    except ValueError:
        return {}


def left_over(tree):
    out = git(tree, "status", "--porcelain=v1", "-z", "--untracked-files=all")
    return sorted(e[3:] for e in out.split("\0") if len(e) > 3)


def tips(tree):
    return git(tree, "for-each-ref", "--format=%(refname:short) %(objectname)", "refs/heads/")


def branches_of_5(tree):
    return sorted(b for b in git(tree, "for-each-ref", "--format=%(refname:short)", "refs/heads/idd/").split() if re.match(r"^idd/5(-.*)?$", b))


def regenerated(tree, path):
    """True for the manifest, and for a file the manifest vouches for: it lists the file with the SHA-256 the
    file has, or as a download that failed (the spec's rule)."""
    if path == M:
        return True
    try:
        with open(os.path.join(tree, M)) as fh:
            listed = {f.get("filename"): f for f in json.load(fh)["files"]}
        with open(os.path.join(tree, path), "rb") as fh:
            digest = hashlib.sha256(fh.read()).hexdigest()
    except (OSError, ValueError, KeyError):
        return False
    row = listed.get(path[len(FOLDER):]) if path.startswith(FOLDER) else None
    return bool(row) and (row.get("sha256") == digest or bool(row.get("error")))


def build(base, stub, row):
    """A repository in which #5 was handed out by the real `next`, ended in the way of the row, and was recorded by
    the real `record`. Returns (root, origin, tree, gh_dir, what git did not track at hand-out)."""
    root = tempfile.mkdtemp(prefix=row["id"] + ".", dir=base)
    shutil.copytree(os.path.join(base, "tpl"), root, dirs_exist_ok=True, symlinks=True)
    origin, tree, gh_dir = os.path.join(root, "origin.git"), os.path.join(root, "tree"), os.path.join(root, "gh")
    git(tree, "remote", "set-url", "origin", origin)
    os.mkdir(gh_dir)
    sh([sys.executable, os.path.join(HERE, "scenario.py"), gh_dir, "5", "9"])
    # ── the repository before the run ──
    if row.get("ignore_files"):   # the documented rule: the downloaded files are ignored, the manifest is not
        write(os.path.join(tree, ".gitignore"), ".claude/.idd/attachments/*/*\n!.claude/.idd/attachments/*/_manifest.json\n", "a")
        git(tree, "add", ".gitignore")
    if row.get("tracked_manifest"):   # an earlier run committed the manifest on the default branch
        download(tree, stub, "empty", "idd-issue")
        git(tree, "add", M)
    if row.get("ignore_files") or row.get("tracked_manifest"):
        git(tree, "commit", "-q", "-m", "earlier")
        git(tree, "push", "-q", "origin", "main")
    if row.get("origin_ignore"):   # origin/main gets an ignore rule; the local default branch lacks it and has a commit of its own
        git(tree, "checkout", "-q", "-b", "elsewhere")
        write(os.path.join(tree, ".gitignore"), "coverage/\n", "a")
        git(tree, "add", ".gitignore")
        git(tree, "commit", "-q", "-m", "ignore coverage")
        git(tree, "push", "-q", "origin", "elsewhere:main")
        git(tree, "checkout", "-q", "main")
        git(tree, "branch", "-q", "-D", "elsewhere")
        write(os.path.join(tree, "local.txt"), "l\n")
        git(tree, "add", "local.txt")
        git(tree, "commit", "-q", "-m", "a commit only this clone has")
    if row.get("local_rule"):   # the local default branch has an ignore rule of its own, and the file it covers is there
        write(os.path.join(tree, ".gitignore"), "settings.local.json\n", "a")
        git(tree, "add", ".gitignore")
        git(tree, "commit", "-q", "-m", "a rule only this clone has")
        write(os.path.join(tree, "settings.local.json"), '{"token": "local"}\n')
    # ── the run: start and next, as idd-all calls them ──
    started = rq(tree, gh_dir, "start", "--path", "PR", "--review", "no")
    if started.returncode != 0:
        raise RuntimeError(f"start: {started.stderr.strip()[:200]}")
    at_handout = treecheck.handout(tree)
    handed = answer(rq(tree, gh_dir, "next"))
    if handed.get("next") != 5:
        raise RuntimeError(f"next did not hand out #5: {handed}")
    # ── the ending ──
    outcome = row.get("outcome", "stopped")
    if row["on"] == "own" or row.get("meeting"):
        git(tree, "checkout", "-q", "--no-track", "-b", B, "origin/main")   # as Phase 0.5 creates it
    if row.get("work"):   # the issue's own commit; staged by name, as idd-implement does
        write(os.path.join(tree, "w.txt"), "w\n")
        git(tree, "add", "--", "w.txt")
        if row.get("work_manifest"):   # the run's own commit carried the manifest
            download(tree, stub, "empty", "idd-issue")
            git(tree, "add", "--", M)
        if row.get("work_ignore"):     # a commit of the issue adds an ignore rule the default branch lacks
            write(os.path.join(tree, ".gitignore"), "coverage/\n", "a")
            git(tree, "add", "--", ".gitignore")
        if row.get("work_untrack"):    # a commit of the issue stops tracking a file the default branch tracks, and ignores it
            git(tree, "rm", "-q", "--cached", "a.txt")
            write(os.path.join(tree, ".gitignore"), "a.txt\n", "a")
            git(tree, "add", "--", ".gitignore")
        if row.get("work_rm_tools"):   # a commit of the issue deletes a folder together with its own ignore rules
            git(tree, "rm", "-q", "-r", "tools")
        if row.get("work_rewrite_ignore"):   # a commit of the issue rewrites the top ignore rules and drops `local/`
            write(os.path.join(tree, ".gitignore"), "coverage/\n")
            git(tree, "add", "--", ".gitignore")
        git(tree, "commit", "-q", "-m", "work of #5 (#5)")
    if row.get("upstream"):
        git(tree, "push", "-q", "-u", "origin", B)
    if row.get("squash"):   # GitHub squash-merged the pull request: origin/main gets one new commit
        c = git(origin, "commit-tree", git(origin, "rev-parse", B + "^{tree}").strip(), "-p", "main", "-m", "squash (#5)").strip()
        git(origin, "update-ref", "refs/heads/main", c)
    for kind in row.get("leave", []):
        if kind == "manifest":
            download(tree, stub, "empty", "idd-diagnose")
        elif kind == "attachment":
            download(tree, stub, "with_url", "idd-diagnose")
        elif kind == "failed-download":
            download(tree, stub, "with_url", "idd-diagnose", curl="fail")
        elif kind == "foreign":
            write(os.path.join(tree, FOLDER, "notes.txt"), "a person's notes\n")
        elif kind == "edit":
            write(os.path.join(tree, "a.txt"), "changed\n")
        elif kind == "proposal":
            write(os.path.join(tree, PROPOSAL), "## Why\n")
        elif kind == "log":
            write(os.path.join(tree, LOG), '{"issue": 5}\n', "a")
        elif kind == "b":
            write(os.path.join(tree, "b.txt"), "b\n")
        elif kind == "lock":
            write(os.path.join(tree, ".claude/.idd/tree-lock"), "pid\n")
        elif kind == "rejecting-hook":   # a lint hook: it rejects what the run left
            executable(os.path.join(tree, ".git", "hooks", "pre-commit"), "#!/bin/sh\necho 'lint: a.txt fails' >&2\nexit 1\n")
        elif kind == "ignored":          # written by the run, ignored by a rule the issue's branch has
            write(os.path.join(tree, "coverage", "report.txt"), "the report\n")
        elif kind == "ignored-tracked":  # written by the run, ignored on the branch, tracked on the default branch
            write(os.path.join(tree, "a.txt"), "the run wrote this\n")
    if row.get("meeting"):   # the meeting unwind: commit the attachment folder on the branch, return to the default branch
        download(tree, stub, "empty", "idd-diagnose")
        git(tree, "add", "--", FOLDER.rstrip("/"))
        git(tree, "commit", "-q", "-m", "chore: keep the attachments of the meeting issue (#5)")
        git(tree, "checkout", "-q", "main")
    if row["on"] == "wip":
        git(tree, "checkout", "-q", "-b", "wip")
    # ── GitHub after the ending, and the record ──
    sh([sys.executable, os.path.join(HERE, "scenario.py"), gh_dir, row.get("gh", "5")])
    if outcome == "closed":
        write(os.path.join(gh_dir, "state-5"), "CLOSED\n")
    recorded = rq(tree, gh_dir, "record", "--issue", "5", *([] if outcome == "closed" else ["--reason", "x"]))
    if recorded.returncode != 0 or answer(recorded).get("outcome") != outcome:
        raise RuntimeError(f"record: {recorded.stdout.strip()[:120]} {recorded.stderr.strip()[:200]}")
    return root, origin, tree, gh_dir, at_handout


def later_run(tree, gh_dir, row, problems):
    """What a later run does with #5: the last column of the table."""
    later = row["later"]
    started = rq(tree, gh_dir, "start", "--path", "PR", "--review", "no")
    if started.returncode != 0:
        problems.append(f"a new run does not start after settle: {started.stderr.strip()[:200]}")
        return
    nxt = answer(rq(tree, gh_dir, "next"))
    attempts = state_of(tree)["attempts"]
    if later == "handed":
        if nxt.get("next") != 5:
            problems.append(f"a later run does not hand #5 out: {nxt}")
    elif later == "existing":
        if nxt.get("next") is not None or not attempts or not attempts[0]["reason"].startswith("existing work: local branch " + B):
            problems.append(f"a later run does not record #5 as existing work: {nxt} {attempts[:1]}")
    elif later == "closed":   # not among the open issues: in no class, and not the one handed out
        classes = answer(rq(tree, gh_dir, "list", "--json")).get("classes", {})
        if any(5 in numbers for numbers in classes.values()) or nxt.get("next") == 5 or any(a["issue"] == 5 for a in attempts):
            problems.append(f"a later run still knows the closed #5: {classes} {nxt}")
    else:   # no longer a candidate: listed under its class, not handed out, not recorded
        classes = answer(rq(tree, gh_dir, "list", "--json")).get("classes", {})
        if 5 not in classes.get(later, []):
            problems.append(f"#5 is not in the class {later} for a later run: {classes}")
        if nxt.get("next") is not None or attempts:
            problems.append(f"a later run hands out or records #5 although it is {later}: {nxt} {attempts[:1]}")
    rq(tree, gh_dir, "report")


def check(base, stub, row):
    problems = []
    root, origin, tree, gh_dir, at_handout = build(base, stub, row)
    before = dict(head=git(tree, "rev-parse", "HEAD"), on=git(tree, "symbolic-ref", "--short", "HEAD"),
                  status=git(tree, "status", "--porcelain", "--untracked-files=all"), tips=tips(tree))
    files_before = treecheck.snapshot(tree)
    left = [p for p in left_over(tree) if p not in at_handout]   # what git shows, without what was there before the run
    blobs = {p: git(tree, "hash-object", "--", p).strip() for p in left if os.path.isfile(os.path.join(tree, p))}
    may_go = {p for p in left if regenerated(tree, p)}
    tip_before = git(tree, "rev-parse", "-q", "--verify", "refs/heads/" + B, check=False).strip()
    proc = rq(tree, gh_dir, "settle", "--issue", "5")
    attempt = state_of(tree)["attempts"][0]
    kept, stashes = attempt.get("kept", []), attempt.get("stashes", [])
    tip = git(tree, "rev-parse", "-q", "--verify", "refs/heads/" + B, check=False).strip()
    # every file, read from the file system: with either exit code
    refs = [before["head"].strip(), tip_before, tip, "refs/heads/main", *(k.get("commit") for k in kept)]
    for st in stashes:
        refs += [st.get("commit", ""), st.get("commit", "") + "^3"]
    problems += treecheck.account(tree, at_handout, files_before, refs=refs, discarded=attempt.get("discarded", []))
    if proc.returncode != row["exit"]:
        problems.append(f"exit {proc.returncode}, want {row['exit']}: {proc.stderr.strip()[:200]}")
        return problems
    if row["exit"] == 3:
        after = dict(head=git(tree, "rev-parse", "HEAD"), on=git(tree, "symbolic-ref", "--short", "HEAD"),
                     status=git(tree, "status", "--porcelain", "--untracked-files=all"), tips=tips(tree))
        if after != before:
            problems.append("exit 3 but something changed")
        lines = proc.stderr.strip().splitlines()
        if len(lines) != 1 or "#5" not in lines[0]:
            problems.append(f"exit 3 without exactly one reason line that names #5: {proc.stderr.strip()[:200]!r}")
        return problems
    if git(tree, "symbolic-ref", "--short", "HEAD").strip() != "main":
        problems.append("the working tree is not on the default branch")
    if git(tree, "status", "--porcelain"):   # the literal check of Phase 0.5
        problems.append("git status --porcelain prints something: the next issue would stop")
    if branches_of_5(tree) != row["branches"]:
        problems.append(f"branches of #5: {branches_of_5(tree)}, want {row['branches']}")
    if sorted(k["branch"] for k in kept) != row["branches"]:
        problems.append(f"the run state keeps {[k['branch'] for k in kept]}, want {row['branches']}")
    if kept and kept[0].get("upstream") is not bool(row.get("upstream")):
        problems.append(f"the run state says upstream {kept[0].get('upstream')!r}, the branch has {'one' if row.get('upstream') else 'none'}")
    discarded = set(row.get("discarded", []))
    if not discarded <= set(left):
        problems.append(f"fixture: {sorted(discarded - set(left))} was not left over")
    if not discarded <= may_go:
        problems.append(f"the row discards something the manifest does not vouch for: {sorted(discarded - may_go)}")
    committed = row.get("committed")
    if committed is None:
        if tip and tip != tip_before:
            problems.append(f"settle made a commit and the row has none: {git(tree, 'show', '--name-only', '--format=', B).split()}")
        if any(k.get("commit") for k in kept):
            problems.append("the run state names a commit and the row has none")
    else:
        names = sorted(git(tree, "show", "--name-only", "--format=", B).split("\n")[:-1]) if tip else []
        if names != sorted(committed):
            problems.append(f"the commit holds {names}, want {sorted(committed)}")
        if not kept or kept[0].get("commit") != tip or sorted(kept[0].get("paths", [])) != sorted(committed):
            problems.append(f"the run state does not record the commit and its paths: {kept}")
        body = git(tree, "log", "-1", "--format=%b", B) if tip else ""
        skipped = "hooks" in body and "skipped" in body
        if bool(row.get("no_hooks")) is not skipped or bool(row.get("no_hooks")) is not (bool(kept) and kept[0].get("hooks") == "skipped"):
            problems.append(f"hooks skipped: the commit message says {skipped}, the run state {kept[0].get('hooks') if kept else None!r}, the row {bool(row.get('no_hooks'))}")
    for p in left:
        if p in discarded:
            continue
        held = git(tree, "rev-parse", "-q", "--verify", f"{B}:{p}", check=False).strip() if tip else ""
        if p in blobs and held != blobs[p]:
            problems.append(f"{p} was left over and is not on {B} as it was")
    if set(left) - discarded - set(committed or []):
        problems.append(f"neither kept nor discarded: {sorted(set(left) - discarded - set(committed or []))}")
    # what settle put into the local exclude file
    excluded = attempt.get("excluded", [])
    if excluded != row.get("excluded", []):
        problems.append(f"the run state says these paths went into the local exclude file: {excluded}, want {row.get('excluded', [])}")
    lines = open(os.path.join(tree, ".git", "info", "exclude")).read().splitlines()
    for path in row.get("excluded", []):
        if "/" + path not in lines:
            problems.append(f"/{path} is not a line of .git/info/exclude")
    stash = stashes[0] if stashes else None
    if row.get("stash"):
        listed = git(tree, "stash", "list", "--format=%H %gs")
        message = row.get("stash_message", STASH_MESSAGE)
        if len(stashes) != 1 or stash.get("paths") != row["stash"] or stash.get("commit", "?") not in listed or message not in listed:
            problems.append(f"the stash is not recorded with its commit and paths: state {stashes}, stash list {listed.strip()[:160]!r}")
    elif stashes or git(tree, "stash", "list"):
        problems.append(f"a stash was made and the row has none: {stashes}")
    report = rq(tree, gh_dir, "report").stdout
    for path in row.get("excluded", []):
        if not any(path in ln and "exclude" in ln for ln in report.splitlines()):
            problems.append(f"the report does not say that {path} went into the local exclude file")
    if any(p in report for p in at_handout if p not in row.get("excluded", [])):
        problems.append("the report names a file that was there before the run as something the run left")
    if row["later"] == "closed":   # what the report says about a closed issue, and what a later run knows of it
        lines = [ln for ln in report.splitlines() if B in ln]
        if committed is None and any("is kept" in ln or "what the run left" in ln for ln in lines):
            problems.append(f"the report names a commit of settle for the closed issue: {lines[0][:160]}")
        if committed is not None and not any(tip[:7] in ln and all(p in ln for p in committed) for ln in lines):
            problems.append(f"the report does not name {B}, the commit and its paths under the closed issue: {lines[:1]}")
        if "open again" in report:
            problems.append("the report says the closed issue is open again")
        later_run(tree, gh_dir, row, problems)
    else:
        if row.get("no_hooks") and "without the repository's commit hooks" not in report:
            problems.append("the report does not say that the commit was made without the commit hooks")
        advice = "deleting it lets a later rest run start the issue over" in report
        want_advice = bool(row["branches"]) and not row.get("upstream")
        if advice is not want_advice:
            problems.append(f"the report {'gives' if advice else 'does not give'} the delete-the-branch step; the row {'has a kept branch without an upstream' if want_advice else 'has none'}")
        later_run(tree, gh_dir, row, problems)
        if want_advice and row["later"] == "existing":   # the step the report gives, taken: the issue is then handed out
            git(tree, "branch", "-D", B)
            again = dict(row, later="handed")
            later_run(tree, gh_dir, again, problems)
    if row.get("stash") and stash:   # the other step the report gives: the stash applied where the report says gives the file back
        line = next((ln for ln in report.splitlines() if f"git stash apply {stash['commit']}" in ln), "")
        if not line:
            problems.append("the report does not say how to get the stashed files back")
        if stash.get("kept") is not bool(row["branches"]):
            problems.append(f"the run state says the branch of the stash was kept: {stash.get('kept')!r}; the row keeps {row['branches']}")
        if row["branches"]:
            if "on that branch" not in line:
                problems.append("the report does not say to apply the stash on the kept branch")
            if not branches_of_5(tree):
                git(tree, "branch", B, tip)   # deleted above to take the report's first step
            git(tree, "checkout", "-q", "--no-overwrite-ignore", B)
        elif "is deleted" not in line or "on that branch" in line:
            problems.append(f"the branch of the stash is gone and the report does not say so: {line[:200]}")
        applied = sh(["git", "-C", tree, "stash", "apply", "-q", stash["commit"]], check=False)
        name, content = row.get("stash_file", ("coverage/report.txt", "the report\n"))
        path = os.path.join(tree, name)
        if applied.returncode != 0 or not os.path.isfile(path) or open(path).read() != content:
            problems.append(f"the stash does not give {name} back: {applied.stderr.strip()[:160]}")
    return problems


BRANCH_CELL = {"none": [], "unchanged": None}   # cells that begin with `idd/5-x` keep that branch; what follows , or ; is prose
LATER_CELL = {"handed out": "handed", "existing work": "existing", "#5 is closed": "closed", "—": None,
              "not run: verified": "verified", "not run: blocked": "blocked", "not run: meeting": "meeting"}


def spec_rows():
    """{row id: (exit code, branches afterwards, later run, the cell `on`, the cell `leaves`)} of the table in the
    spec, or None when no spec with that Example is on disk."""
    for path in sorted(glob.glob(os.path.join(ROOT, "openspec/changes/*/specs/idd-all-rest/spec.md"))) + [os.path.join(ROOT, "openspec/specs/idd-all-rest/spec.md")]:
        try:
            with open(path, encoding="utf-8") as fh:
                text = fh.read()
        except OSError:
            continue
        if "##### Example: endings of the single-issue pipeline" not in text:
            continue
        part = text.split("##### Example: endings of the single-issue pipeline", 1)[1].split("\n#####", 1)[0]
        rows = {}
        for line in part.splitlines():
            cells = [c.strip() for c in line.strip().strip("|").split("|")]
            m = re.match(r"^`([a-z-]+)`:", cells[0]) if len(cells) == 6 else None
            if m:
                kept = [B] if cells[4].startswith(f"`{B}`") else BRANCH_CELL.get(re.split(r"[,;]", cells[4])[0].strip(), "?")
                rows[m.group(1)] = (int(cells[3]), kept, LATER_CELL.get(cells[5], "?"), cells[1], cells[2])
        return rows
    return None


def main():
    base = tempfile.mkdtemp(prefix="idd-endings.")
    bad = 0
    try:
        template(base)
        stub = stubs(base)
        for row in ROWS:
            try:
                problems = check(base, stub, row)
            except Exception as exc:   # a fixture that cannot be built is a failure of that row
                problems = [f"{type(exc).__name__}: {str(exc)[:300]}"]
            for p in problems:
                bad += 1
                print(f"FAIL {row['id']}: {p}")
        table = spec_rows()
        if table is None:
            print("endings: no spec with the table on disk; the row names were not compared")
        else:
            here = {r["id"]: (r["exit"], r.get("branches"), r.get("later"), *CELLS.get(r["id"], ("?", "?"))) for r in ROWS}
            for name in sorted(set(table) | set(here)):
                if table.get(name) != here.get(name):
                    bad += 1
                    print(f"FAIL {name}: the table in the spec says {table.get(name)}, the row here {here.get(name)}")
        print(f"endings: {len(ROWS)} rows, {bad} failure(s)")
        return 1 if bad else 0
    finally:
        shutil.rmtree(base, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
