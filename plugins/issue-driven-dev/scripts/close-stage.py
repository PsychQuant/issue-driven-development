#!/usr/bin/env python3
"""close-stage.py — /idd-all's close stage, in one process (#392).

Why a helper and not bash blocks in the skill: every check that guards a merge
or a push has to run in the SAME process as the merge or push. Bash blocks in a
skill run one tool call at a time, and a failed check that ends its own block
with `exit 0` does not stop the next block (#383 r2 #12; #392 verify r1 #9).
Shell variables do not survive between tool calls either, so the values the
checks depend on (the run's flags, the PR, the verified commit) are read from a
state file and from GitHub here, never from the model's memory.

Subcommands
  init  --cwd C --repo O/R --issue N --path PR|direct-commit --requested-path PR|direct-commit
        --interaction attended|unattended --branch B --default D --review yes|no --in-chain yes|no
        --stop none|early|exhaustive-blocking|exhaustive-all
        Step 0.7: record the run's flags in C/.claude/.idd/state/idd-all-run-N.json,
        with the stop mode (#595) and an empty round record.
        Every value is required: a value lost between tool calls is a usage
        error (64), never a silent "no" (#392 verify r2 #3).
  gate  --cwd C --repo O/R --issue N --sha SHA [--base SHA]
        Read the newest verify report this account posted on the issue since
        the run began, as GitHub renders it (body_html), and judge it with
        verify-gate.py --expect-sha [--expect-base]. The newest one must be a
        '## Verify: #N' report (a PR-mode report or pointer is not read here).
        Prints the gate JSON plus comment_id / verify_url / round.
        A report this run has not read yet is appended to the round record of the
        run state (#595); reading the same report again adds nothing.
        Exit 0 clean, 1 not clean, 2 unparseable (including: no such report,
        any error), 64 usage.
  next  --cwd C --repo O/R --issue N
        After each verify round (#595): fix and verify again, or stop, and whether
        the stop merges — from the run state's stop mode and round record only
        (scripts/lib/stopmode.py). Prints one JSON line. Exit 0 decided, 3 could
        not decide (no run state, no round): the answer is then stop, no merge.
  run   --cwd C --repo O/R --issue N [--ci-timeout S] [--ci-grace S]
        Phase 5c: every guardrail, then the squash merge (PR) or the push
        (direct-commit). The CI guardrail runs the local CI gate
        (idd-ci-gate.sh) on the verified commit; only in remote mode (exit 10)
        does it wait for the PR's remote checks. Prints one JSON line and writes it to
        C/.claude/.idd/state/idd-all-result-N.json.
        Exit 0 merged/pushed, 3 stopped (reason in the JSON, including any
        error), 64 usage.
  reset --cwd C --issue N
        Abort duty: remove this issue's run-state and result files. (init does the
        same for the run it records.)
  confirm-close --cwd C --repo O/R --issue N
        After /idd-close: the issue is CLOSED and a comment by this account
        that opens with the canonical '## Closing Summary' heading was posted
        after the merge or push recorded in the result file. Exit 0 confirmed,
        3 not confirmed, 64 usage.

Fail closed throughout: anything that cannot be read or checked stops the
stage. Nothing here asks a person; a stop is reported, not negotiated.

Test seams (honoured only when IDD_CLOSE_STAGE_TEST=1): IDD_GH / IDD_GIT name
the gh and git executables; IDD_CI_GATE names the local CI gate; IDD_SLEEP=0
makes the wait loops not sleep.

Result fields a merge or push can carry besides the commit: `low_in_scope` (LOW
In-scope fix findings the merge did not wait for), `proposed_corrections`
(comments whose Proposed Corrections nobody answered), `local_ci` (pass or
remote), and with local CI `remote_ci_failed` / `remote_ci_pending` (remote
checks read once; they are reported and do not stop the merge).

Modules (scripts/lib/): ghread.py reads GitHub and git and fails closed;
intent.py decides whether the intent was confirmed and whether anyone else got
involved; workflows.py decides whether a push to the default branch publishes;
rendered.py reads GitHub's rendering of a comment, shared with verify-gate.py.
"""

import contextlib
import fcntl
import json
import math
import os
import re
import secrets
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.join(HERE, "lib"))
import workflows  # noqa: E402  scripts/lib/workflows.py — does a push to the default branch publish?
from ghread import (CI_GATE_RESULTS, GH, GIT, SLEEP, TEST, Stop, gh_json, git, issue_comments, issue_view, iso,  # noqa: E402
                    local_ci, now, gh_paginated, parse_iso, run_cmd, session_login, ts, first_line)
from intent import (check_intent, check_issue_authors, check_meeting, check_others,  # noqa: E402
                    check_pr_people, issue_meta)
from stopmode import MODES, answered_fix, decide, fix_key  # noqa: E402  scripts/lib/stopmode.py — when the fix loop stops (#595)

WRITE_PERMS = {"WRITE", "MAINTAIN", "ADMIN"}
STATE_TTL = 24 * 3600
REPO_RE = re.compile(r"^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$")
SHA_RE = re.compile(r"^[0-9a-f]{40}$")
# A close keyword next to an issue reference in any form GitHub acts on:
# `#N`, `owner/repo#N`, or an issue/PR URL. Unlike idd-verify Step 0.8's
# warn-only Source 2, a hyphen or slash before the keyword does NOT exempt it:
# GitHub splits `idd-close #N` and closes the issue (#173).
TRAP_RE = re.compile(
    r"(?<![A-Za-z0-9])(close[sd]?|fix(?:e[sd])?|resolve[sd]?)\s*:?\s*"
    r"(#\d+|[\w.-]+/[\w.-]+#\d+|https?://github\.com/[\w.-]+/[\w.-]+/(?:issues|pull)/\d+)",
    re.IGNORECASE,
)


def state_dir(cwd):
    cwd = os.path.realpath(cwd)   # a trailing slash or a symlinked ancestor of --cwd must not move the walk (r4 #43)
    d = os.path.join(cwd, ".claude", ".idd", "state")
    probe = d
    while probe and probe != cwd and probe != os.path.dirname(probe):
        if os.path.islink(probe):
            raise Stop(f"{probe} is a symlink — refusing to read or write run state through it")
        probe = os.path.dirname(probe)
    return d


def safe_path(path):
    if os.path.islink(path):
        raise Stop(f"{path} is a symlink — refusing to use it")
    return path


def state_path(cwd, n):
    return safe_path(os.path.join(state_dir(cwd), f"idd-all-run-{n}.json"))


def result_path(cwd, n):
    return safe_path(os.path.join(state_dir(cwd), f"idd-all-result-{n}.json"))


def gate_answer_path(cwd, n):
    return safe_path(os.path.join(state_dir(cwd), f"idd-all-gate-{n}.json"))


def write_gate_answer(cwd, n, result):
    """#623: the gate's answer for the Phase 4 `next` block, a separate Bash call that cannot keep a variable. It
    goes through the run state's guards: no symlinked ancestor (state_dir), no symlink at the path (safe_path), and
    a temporary file made exclusively (mkstemp, mode 0600) moved into place, so a planted link is never written
    through. A write that fails removes the previous answer when that is a regular file, so the next block cannot
    read an old one, and only warns: the gate's answer on stdout and its exit code do not change."""
    try:
        path = gate_answer_path(cwd, n)
        fd, tmp = tempfile.mkstemp(prefix=os.path.basename(path) + ".", suffix=".tmp", dir=os.path.dirname(path))
        try:
            with os.fdopen(fd, "w", encoding="utf-8") as fh:
                fh.write(json.dumps(result, ensure_ascii=False) + "\n")
            os.replace(tmp, path)
        except BaseException:
            if os.path.exists(tmp):
                os.unlink(tmp)
            raise
    except Exception as exc:
        try:
            old = os.path.join(state_dir(cwd), f"idd-all-gate-{n}.json")
            if os.path.isfile(old) and not os.path.islink(old):
                os.unlink(old)
        except Exception:
            pass
        print(f"⚠ the gate's answer was not written for the next block ({exc.__class__.__name__}: {exc})",
              file=sys.stderr)


class Replaced(Stop):
    """The run state now belongs to another run (#602 verify r1): Phase 4 stops on it and never counts or fixes."""


def lock_path(cwd, n):
    return safe_path(os.path.join(state_dir(cwd), f"idd-all-run-{n}.lock"))


@contextlib.contextmanager
def state_lock(cwd, n):
    """One exclusive lock per issue around every write of its run state (#602): init, the gate's round record and
    next's fix answer. A lock held on an open file is released when the process ends, even on a crash; the file's
    existence is never the lock. O_NOFOLLOW: a planted symlink is not followed."""
    path = lock_path(cwd, n)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd = os.open(path, os.O_RDWR | os.O_CREAT | getattr(os, "O_NOFOLLOW", 0), 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        try:
            fcntl.flock(fd, fcntl.LOCK_UN)
        finally:
            os.close(fd)


# ── arguments ──────────────────────────────────────────────────────────────

def parse(argv, spec):
    """spec: {flag: 'value'}. Returns dict or None on a malformed command line."""
    out, i = {}, 0
    while i < len(argv):
        flag = argv[i]
        if flag not in spec or flag in out or i + 1 >= len(argv) or argv[i + 1] == "":
            return None
        out[flag] = argv[i + 1]
        i += 2
    return out


def usage(msg):
    print(f"close-stage: {msg}", file=sys.stderr)
    return 64


def common_ok(a):
    return bool(a.get("--cwd") and os.path.isdir(a["--cwd"])
                and REPO_RE.match(a.get("--repo", ""))
                and re.match(r"^[0-9]+$", a.get("--issue", "")))


# ── init ───────────────────────────────────────────────────────────────────

def cmd_init(argv):
    keys = ["--cwd", "--repo", "--issue", "--path", "--requested-path", "--interaction", "--branch",
            "--default", "--review", "--in-chain", "--stop"]
    a = parse(argv, {k: "value" for k in keys})
    if a is None or not common_ok(a) or any(k not in a for k in keys):
        return usage("init needs every one of: " + " ".join(keys) + " (each with a value)")
    if a["--path"] not in ("PR", "direct-commit") or a["--requested-path"] not in ("PR", "direct-commit"):
        return usage("--path and --requested-path must be PR or direct-commit")
    if a["--interaction"] not in ("attended", "unattended"):
        return usage("--interaction must be attended or unattended")
    if a["--review"] not in ("yes", "no") or a["--in-chain"] not in ("yes", "no"):
        return usage("--review and --in-chain must be yes or no")
    if a["--stop"] not in ("none",) + MODES:
        return usage("--stop must be none, " + ", ".join(MODES))
    cwd = os.path.realpath(a["--cwd"])
    try:
        spath, rpath = state_path(cwd, a["--issue"]), result_path(cwd, a["--issue"])
    except Stop as exc:
        print(f"close-stage: {exc}", file=sys.stderr)
        return 3
    state = {
        "repo": a["--repo"], "issue": int(a["--issue"]), "path": a["--path"],
        "requested_path": a["--requested-path"], "interaction": a["--interaction"],
        "branch": a["--branch"], "default": a["--default"],
        "review": a["--review"] == "yes", "in_chain": a["--in-chain"] == "yes",
        "verify_stop": None if a["--stop"] == "none" else a["--stop"], "rounds": [], "attempts": [], "last_gate": None,
        "created_at": iso(now()), "run_id": secrets.token_hex(8),   # #602: one identity per run, unique within a second
    }
    os.makedirs(os.path.dirname(spath), exist_ok=True)
    try:
        with state_lock(cwd, a["--issue"]):
            write_state(cwd, a["--issue"], state)
    except (Stop, OSError) as exc:
        print(f"close-stage: init failed: {exc}", file=sys.stderr)
        return 3
    if os.path.exists(rpath):
        os.unlink(rpath)
    print(spath)
    return 0


def cmd_reset(argv):
    a = parse(argv, {"--cwd": "value", "--issue": "value"})
    if a is None or not a.get("--cwd") or not os.path.isdir(a["--cwd"]) or not re.match(r"^[0-9]+$", a.get("--issue", "")):
        return usage("reset needs --cwd <dir> --issue <digits>")
    try:
        paths = [p for p in (state_path(a["--cwd"], a["--issue"]), result_path(a["--cwd"], a["--issue"]))
                 if os.path.lexists(p)]
        if not paths:
            return 0           # #602 r2: nothing to delete — no state directory and no lock file are created
        try:
            lock = state_lock(a["--cwd"], a["--issue"])     # #602 r1: a gate holding the lock cannot write it back
            lock.__enter__()
        except (Stop, OSError) as exc:
            # #602 r2: a lock that cannot be used must not keep an earlier run's state alive
            print(f"close-stage: reset: the run-state lock could not be taken ({exc}); deleting without it",
                  file=sys.stderr)
            lock = None
        try:
            for path in paths:
                if os.path.lexists(path):
                    os.unlink(path)
        finally:
            if lock is not None:
                lock.__exit__(None, None, None)
    except (Stop, OSError) as exc:
        print(f"close-stage: reset failed: {exc}", file=sys.stderr)
        return 3
    return 0


# ── gate ───────────────────────────────────────────────────────────────────


def latest_report(n, me, since, comments):
    """The newest verify comment THIS account posted since the run began.

    Only this account: anyone else's comment after the run began stops the
    close stage on its own (check_others), so a teammate's report is never
    weighed here. Every verify heading counts when picking the newest, and the
    newest must be the branch-mode `## Verify: #N` report: a PR-mode report or
    its `## Verify (via PR #P)` pointer, posted later by someone running
    /idd-verify --pr with this account, is not read past (r4 #22). Reports older
    than the run's state are an earlier run's (r3 #6; no slack, r4 #8).
    """
    any_verify = re.compile(r"^#{1,6}[ \t]*Verify\b")
    found = [c for c in comments if c.get("login") == me and any_verify.match(first_line(c.get("body")))
             and (since is None or ts(c.get("created_at")) >= since)]
    if not found:
        return None, "none"
    newest = found[-1]
    if not re.match(rf"^## Verify: #{n}(?![0-9])", first_line(newest.get("body"))):
        return None, first_line(newest.get("body"))[:60]
    return newest, ""


def run_report_ids(n, me, since, comments):
    """The ids of every `## Verify: #N` report this account posted since the run began (#602 r2). A round is a
    report: one that is not in the round record is a round that was not recorded, and the record then undercounts
    the rounds, whatever Phase 4 remembers."""
    own = re.compile(rf"^## Verify: #{n}(?![0-9])")
    return [c.get("id") for c in comments if c.get("login") == me and own.match(first_line(c.get("body")))
            and (since is None or ts(c.get("created_at")) >= since)]


def judge_report(repo, n, sha, base, since):
    me = session_login()
    comments = issue_comments(repo, n)
    report, other = latest_report(n, me, since, comments)
    if report is None:
        when = f" since {iso(since)}" if since is not None else ""
        if other == "none":
            return 2, {"status": "unparseable", "reason": f"no verify report by this account{when}"}
        return 2, {"status": "unparseable",
                   "reason": f"the newest verify comment by this account{when} is '{other}', not a '## Verify: #{n}' report"}
    # A verdict changes only with a new verify round: a report edited after it was posted is not read (r5 #14),
    # nor one a maintainer hid as outdated or off-topic.
    named = {"comment_id": report.get("id"), "verify_url": report.get("html_url")}
    if ts(report.get("updated_at")) != ts(report.get("created_at")):
        return 2, dict(named, status="unparseable", reason="the verify report was edited after it was posted — run verify again")
    if not report.get("node_id"):
        return 2, dict(named, status="unparseable", reason="could not tell whether the verify report is hidden (no node id)")
    q = "query($id:ID!){node(id:$id){... on IssueComment{isMinimized}}}"
    node = (gh_json(["api", "graphql", "-f", f"query={q}", "-f", f"id={report['node_id']}"],
                    "whether the verify report is hidden").get("data") or {}).get("node") or {}
    if node.get("isMinimized"):
        return 2, dict(named, status="unparseable", reason="the verify report is hidden on GitHub — a person set it aside")
    html = report.get("body_html")
    if not html:
        return 2, dict(named, status="unparseable", reason="GitHub returned no rendered HTML for the verify report")
    with tempfile.NamedTemporaryFile("w", suffix=".html", delete=False, encoding="utf-8") as fh:
        fh.write(html)
        tmp = fh.name
    try:
        cmd = [sys.executable, "-I", os.path.join(HERE, "verify-gate.py"), "--html-file", tmp, "--expect-sha", sha]
        if base:
            cmd += ["--expect-base", base]
        rc, out, err = run_cmd(cmd)
    finally:
        os.unlink(tmp)
    try:
        result = json.loads(out)
    except ValueError:
        return 2, dict(named, status="unparseable", reason=f"verify-gate.py gave no JSON (exit {rc})")
    result["comment_id"] = report.get("id")
    result["verify_url"] = report.get("html_url")
    result["reports_since"] = run_report_ids(n, me, since, comments)   # #602 r2: the ledger merge_gate checks
    result["report_author"] = report.get("login")
    return (rc if rc in (0, 1, 2) else 2), result


def gate_stop(rc, gate):
    """The one predicate every merge and push of a run without a stop mode passes (r6 #1): clean, and nothing
    a person has to settle. A clean result without these fields stops too."""
    if rc != 0:
        raise Stop(f"guardrail 1 (verify gate) — {gate.get('status')}: {gate.get('reason')}")
    settled_stop(gate)


def settled_stop(gate):
    """Nothing in the report that a person has to settle (shared by the clean merge and the stop-mode merge)."""
    for field in ("rejected", "high_follow_up", "process_gaps"):
        if field not in gate or gate[field] is None:
            raise Stop(f"guardrail 1 (verify gate) — the gate did not report {field}")
    if gate["rejected"]:
        raise Stop(f"guardrail 1 (verify gate) — the report marks {gate['rejected']} finding(s) Rejected: the run judged "
                   "a reviewer wrong about its own code; a person decides whether they stand")
    if gate["high_follow_up"]:
        raise Stop(f"guardrail 1 (verify gate) — {gate['high_follow_up']} serious finding(s) filed as Follow-up; "
                   "a person agrees before they are left for later")
    if gate["process_gaps"]:
        raise Stop("guardrail 1 (verify gate) — the verify ran degraded (a reviewer or the cross-model pass is missing); "
                   "a person reviews this one")


def run_since(cwd, n):
    return run_identity(cwd, n)["created_at"]


def run_identity(cwd, n):
    """The run a gate reads for: its start time and its run_id (#602), both None when there is no readable record."""
    try:
        with open(state_path(cwd, n), encoding="utf-8") as fh:
            st = json.load(fh)
        return {"created_at": parse_iso(st["created_at"]), "run_id": st.get("run_id")}
    except (OSError, ValueError, KeyError, TypeError, AttributeError):
        return {"created_at": None, "run_id": None}


def cmd_gate(argv):
    a = parse(argv, {"--cwd": "value", "--repo": "value", "--issue": "value", "--sha": "value", "--base": "value",
                     "--read-only": "value", "--write-answer": "value"})
    if a is None or not common_ok(a) or not SHA_RE.match(a.get("--sha", "")) \
            or ("--base" in a and not SHA_RE.match(a["--base"])) or a.get("--read-only", "yes") != "yes" \
            or a.get("--write-answer", "yes") != "yes":
        return usage("gate needs --cwd --repo --issue and --sha (40 lowercase hex digits), optionally --base, "
                     "--read-only yes and --write-answer yes")
    since = run_id = None
    try:
        ident = run_identity(a["--cwd"], a["--issue"])   # the run this gate reads for; the record is written for it only
        since, run_id = ident["created_at"], ident["run_id"]
        rc, result = judge_report(a["--repo"], a["--issue"], a["--sha"], a.get("--base"), since)
    except Stop as exc:
        rc, result = 2, {"status": "unparseable", "reason": str(exc)}
    except Exception as exc:  # fail closed: any surprise is unparseable, never "not clean"
        rc, result = 2, {"status": "unparseable", "reason": f"internal error: {exc.__class__.__name__}: {exc}"}
    try:
        # --read-only (Phase 5's PR body, verify r3 #1): judge, but leave the round record as Phase 4 left it
        if "--read-only" not in a:
            record_round(a["--cwd"], a["--repo"], a["--issue"], result, a["--sha"], since, run_id)
    except Exception as exc:  # fail closed: a round that was not recorded must not read as a judged round
        rc, result = 2, {"status": "unparseable", "reason": f"the round record could not be written: "
                         f"{exc.__class__.__name__}: {exc}", "comment_id": result.get("comment_id")}
        if isinstance(exc, Replaced):
            result["replaced"] = True     # #602 r1: Phase 4 stops; this is not a write that failed
    if "--write-answer" in a:             # #623: the Phase 4 gate block, for its next block
        write_gate_answer(a["--cwd"], a["--issue"], result)
    print(json.dumps(result, ensure_ascii=False))
    return rc


def write_state(cwd, n, st):
    """Replace the run state in one step: a crash halfway leaves the old record, never half of a new one.
    The temporary file is created exclusively (mkstemp), so a planted symlink is never written through."""
    path = state_path(cwd, n)
    fd, tmp = tempfile.mkstemp(prefix=os.path.basename(path) + ".", suffix=".tmp", dir=os.path.dirname(path))
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as fh:
            json.dump(st, fh, ensure_ascii=False)
        os.replace(tmp, path)
    except BaseException:
        if os.path.exists(tmp):
            os.unlink(tmp)
        raise


def read_state(cwd, repo, n):
    """The run state as a dict with list-valued `rounds` and `attempts`, or Stop. One reader for gate, next and run."""
    try:
        with open(state_path(cwd, n), encoding="utf-8") as fh:
            st = json.load(fh)
    except OSError:
        raise Stop("no run state for this issue")
    except ValueError:
        raise Stop("the run state is not valid JSON")
    if not isinstance(st, dict):
        raise Stop("the run state is not a JSON object")
    if st.get("repo") != repo or str(st.get("issue")) != str(n):
        raise Stop("the run state names another repo or issue")
    for key in ("rounds", "attempts", "fix_answers"):
        if not isinstance(st.get(key) or [], list) or not all(isinstance(r, dict) for r in st.get(key) or []):
            raise Stop(f"the run state's {key} is not a list of records")
    # #602: a missing verify_stop is not "no stop mode" — init has always written it; without it the record is unusable
    if "verify_stop" not in st:
        raise Stop("the run state has no verify_stop field (written by an older close-stage, or edited); rerun /idd-all")
    if st["verify_stop"] is not None and st["verify_stop"] not in MODES:
        raise Stop(f"the run state's verify_stop is {st['verify_stop']!r}, not null or one of {', '.join(MODES)}")
    return st


def record_round(cwd, repo, n, result, sha, since=None, run_id=None):
    """#595/#591: the latest gate result; one attempt per verify round — a new commit, or a new report on the same
    commit (a round whose report is missing or unreadable still counts); and one round per verify report this run
    has not read yet. An unparseable
    report's counts are not kept. No run state (gate run outside /idd-all): nothing is recorded."""
    if not os.path.exists(state_path(cwd, n)):
        if since is not None:   # #602 r2: the record this gate read for was deleted (a reset by another /idd-all)
            raise Replaced("the run state this gate read for is gone; the result is not recorded")
        return
    with state_lock(cwd, n):
        _record_round_locked(cwd, repo, n, result, sha, since, run_id)


def _record_round_locked(cwd, repo, n, result, sha, since, run_id):
    if not os.path.exists(state_path(cwd, n)) and since is not None:
        raise Replaced("the run state this gate read for is gone; the result is not recorded")
    st = read_state(cwd, repo, n)
    # The report was picked with this run's start time (`since`). If another /idd-all replaced the run state while the
    # gate was reading (or there was none then), the result belongs to no round of this run (verify r4 #1). The check
    # and the write below hold the same lock as init, and the run_id tells two runs started in the same second apart
    # (#602).
    try:
        created = parse_iso(st["created_at"])
    except (KeyError, ValueError, TypeError):
        created = None
    if since is None or created != since or st.get("run_id") != run_id:
        raise Replaced("the run state was replaced while the gate was reading; the result is not recorded")
    rid = result.get("comment_id")
    rounds, attempts = list(st.get("rounds") or []), list(st.get("attempts") or [])
    at = iso(now())
    st["last_gate"] = {"status": result.get("status"), "report_id": rid, "sha": sha, "reason": result.get("reason"),
                       "at": at}
    seen = [r.get("report_id") for r in rounds]
    # An attempt is a verify round: a new commit, or on the same commit a report id (or no report id: the round's
    # report is missing or could not be fetched, verify r2 #2) not read on it before. A fix pass that made no
    # commit still counts, so the limit holds; reading the same result again on the same commit adds nothing.
    on_sha = [a.get("report_id") for a in attempts if a.get("sha") == sha]
    if not attempts or attempts[-1].get("sha") != sha or rid not in on_sha:
        attempts.append({"sha": sha, "report_id": rid, "at": at})
    if rid is not None and rid not in seen:
        judged = result.get("status") != "unparseable"
        rounds.append({"round": len(rounds) + 1, "sha": sha, "status": result.get("status"),
                       "blocking": result.get("blocking") if judged else None,
                       "in_scope": result.get("in_scope") if judged else None,
                       "low_in_scope": result.get("low_in_scope") if judged else None,
                       "high_in_scope": result.get("high_in_scope") if judged else None,
                       "rejected": result.get("rejected") if judged else None,
                       "report_id": rid, "at": at})
        seen.append(rid)
    st["rounds"], st["attempts"] = rounds, attempts
    if rid is not None:
        result["round"] = seen.index(rid) + 1
    result["attempt"] = len(attempts)
    write_state(cwd, n, st)


# ── next ───────────────────────────────────────────────────────────────────

def cmd_next(argv):
    a = parse(argv, {"--cwd": "value", "--repo": "value", "--issue": "value", "--read-only": "value"})
    if a is None or not common_ok(a) or a.get("--read-only", "yes") != "yes":
        return usage("next needs --cwd <dir> --repo owner/repo --issue <digits>, optionally --read-only yes")
    unknown = {"decision": "stop", "merge": False, "mode": None, "rounds": [], "decided": False}
    try:
        st = read_state(a["--cwd"], a["--repo"], a["--issue"])
        answer = decide(st)
        if answer["decision"] == "fix" and "--read-only" not in a:
            # Remember the result this fix answer is about: asked again with no new report or commit, it is a stop.
            # Not recorded means no fix: a loop whose stop cannot be guaranteed does not run another round.
            try:
                with state_lock(a["--cwd"], a["--issue"]):   # #602: re-read under the lock; a replaced run is not written
                    if not os.path.exists(state_path(a["--cwd"], a["--issue"])):
                        raise Replaced("the run state was deleted while next was deciding")
                    now_st = read_state(a["--cwd"], a["--repo"], a["--issue"])
                    if (now_st.get("run_id"), now_st.get("created_at")) != (st.get("run_id"), st.get("created_at")):
                        raise Replaced("the run state was replaced while next was deciding")
                    now_st["fix_answers"] = list(now_st.get("fix_answers") or []) + [fix_key(st)]
                    write_state(a["--cwd"], a["--issue"], now_st)
            except Exception as exc:
                answer = dict(answer, decision="stop", merge=False, decided=False,
                              reason=f"the fix answer could not be recorded ({exc.__class__.__name__}: {exc})")
                if isinstance(exc, Replaced):
                    answer["replaced"] = True
    except Stop as exc:
        answer = dict(unknown, reason=f"no readable run state: {exc}")
    except Exception as exc:  # fail closed: a surprise is a stop without a merge, never "fix"
        answer = dict(unknown, reason=f"internal error: {exc.__class__.__name__}: {exc}")
    decided = answer.pop("decided", True)
    answer["decided"] = bool(decided)   # #602: printed too, so Phase 4 can take its fallback without the exit code
    print(json.dumps(answer, ensure_ascii=False))
    return 0 if decided else 3


def ledger_check(gate, rounds):
    """#602 r2: every verify report of this run is a round of the record. One that is not is a round the gate could
    not record, so the record undercounts the rounds: such a run is not merged, with or without a stop mode. Run
    after the checks on the newest report, which name the more specific cause."""
    ids = gate.get("reports_since")
    if not isinstance(ids, list):
        raise Stop("guardrail 1 (verify rounds) — the gate did not list this run's verify reports")
    missing = [i for i in ids if i not in [r.get("report_id") for r in rounds]]
    if missing:
        raise Stop(f"guardrail 1 (verify rounds) — {len(missing)} verify report(s) of this run are not in the round "
                   "record: a round was not recorded, so the rounds cannot be counted — not merging")


def merge_gate(st, rc, gate, sha):
    """Guardrail 1 for every merge and push. Without a stop mode: a clean round, and no more than 2 recorded
    rounds when unattended (#591). With one (#595): the newest report is the round `next` judged, and its
    answer is stop with a merge."""
    mode = st.get("verify_stop")
    rounds = st.get("rounds") or []
    # A result `next` answered with fix is never merged as it stands (verify r2 #3), with or without a stop mode.
    if answered_fix(st, {"sha": sha, "report_id": gate.get("comment_id")}):
        raise Stop("guardrail 1 (verify rounds) — next gave a fix answer for this report on this commit, and no new "
                   "commit or report followed it")
    if mode is None:
        gate_stop(rc, gate)
        if gate.get("comment_id") not in [r.get("report_id") for r in rounds]:   # an empty record too
            raise Stop("guardrail 1 (verify rounds) — the newest verify report was never judged in Phase 4 "
                       "(it is not in the round record)")
        attempts = st.get("attempts") or []
        # every round the gate recorded is also an attempt: fewer attempts than rounds is a record that cannot be
        # counted (verify r3 #2), never "no rounds yet"
        if not attempts or len(attempts) < len(rounds):
            raise Stop(f"guardrail 1 (verify rounds) — the round record is inconsistent ({len(rounds)} round(s), "
                       f"{len(attempts)} attempt(s)); the verify rounds cannot be counted")
        if st.get("interaction") == "unattended" and len(attempts) > 2:
            raise Stop(f"guardrail 1 (verify rounds) — {len(attempts)} verify rounds are recorded and a run without a stop "
                       "mode allows 2 verify rounds; a person reviews the fixes after the second")
        ledger_check(gate, rounds)
        return
    if rc == 2:
        raise Stop(f"guardrail 1 (verify gate) — unparseable: {gate.get('reason')}")
    if not rounds or rounds[-1].get("report_id") != gate.get("comment_id") or rounds[-1].get("sha") != sha:
        raise Stop(f"guardrail 1 (stop mode {mode}) — the newest verify report is not the round the stop mode judged; "
                   "run close-stage.py gate and next again")
    ledger_check(gate, rounds)
    # The table is applied to the counts the gate just re-read, not only to the record (verify r2 #1).
    for field in ("blocking", "in_scope", "low_in_scope"):
        if rounds[-1].get(field) != gate.get(field):
            raise Stop(f"guardrail 1 (stop mode {mode}) — the round record's {field} ({rounds[-1].get(field)}) does not "
                       f"match the report the close stage re-read ({gate.get(field)}); run close-stage.py gate and next again")
    answer = decide(st)
    if answer["decision"] != "stop" or not answer["merge"]:
        raise Stop(f"guardrail 1 (stop mode {mode}) — {answer['reason']}; the stop mode does not merge this round "
                   f"(answer: {answer['decision']})")
    settled_stop(gate)
    # A serious In-scope fix finding is not left behind by a merge (verify round 1 #1): the close stage checks it
    # itself, whatever Phase 4 did about security findings.
    high = gate.get("high_in_scope")
    if not isinstance(high, int) or high:
        left = "an unknown number of" if not isinstance(high, int) else str(high)
        raise Stop(f"guardrail 1 (stop mode {mode}) — the report leaves {left} In-scope fix finding(s) of severity "
                   "CRITICAL, HIGH, P0 or P1; a stop mode merges only when none is left")
    # The clean merge requires a complete coverage line and reviewers line; verify-gate reads them for every verdict.
    for field, what in (("coverage_complete", "a complete coverage line (X / X requirements addressed)"),
                        ("reviewers_complete", "a complete reviewers line (X / X reviewers completed)")):
        if gate.get(field) is not True:
            raise Stop(f"guardrail 1 (stop mode {mode}) — the report has no {what}; a merge needs it as a clean one does")


# ── run: shared checks ─────────────────────────────────────────────────────

def load_state(cwd, repo, n):
    try:
        st = read_state(cwd, repo, n)
    except Stop as exc:
        raise Stop(f"{exc} (Step 0.7 records the run's flags) — not merging")
    try:
        age = now() - parse_iso(st["created_at"])
    except (KeyError, ValueError, TypeError):
        raise Stop("the run state has no readable creation time — not merging")
    # A run with a stop mode can run for long (#595): its age counts from the last verify round it recorded.
    if st.get("verify_stop") and st.get("rounds"):
        try:
            age = now() - parse_iso(st["rounds"][-1]["at"])
        except (KeyError, ValueError, TypeError):
            raise Stop("the run state has no readable time for its last verify round — not merging")
    if age > STATE_TTL or age < -300:
        raise Stop("the run state is older than 24 hours (an earlier run's) — not merging; rerun /idd-all")
    return st


def check_origin(cwd, repo):
    """Every fetch and push URL of origin must be github.com/<repo> (git pushes to each push URL, r4 #33)."""
    urls = git(cwd, "remote", "get-url", "--all", "origin").splitlines() \
        + git(cwd, "remote", "get-url", "--push", "--all", "origin").splitlines()
    for url in [u.strip() for u in urls if u.strip()]:
        if TEST and url.startswith("/"):
            host, path = "github.com", url
        else:
            # userinfo may be empty (`https://@github.com/...`, r4 #19)
            m = re.match(r"^(?:https?://(?:[^@/]*@)?|ssh://(?:[^@/]*@)?|git@)([^/:]+)[:/](.+)$", url)
            if not m:
                raise Stop(f"origin URL {url} is not a GitHub URL — not pushing or merging")
            host, path = m.group(1).lower(), m.group(2)
        m2 = re.search(r"([^/:]+/[^/]+?)(?:\.git)?/?$", path)
        if host != "github.com" or not m2 or m2.group(1).lower() != repo.lower():
            raise Stop(f"origin ({url}) is not github.com/{repo} — not pushing or merging")


def workflow_files(cwd, ref):
    rc, out, err = run_cmd([GIT, "-C", cwd, "ls-tree", "-r", "-z", "--name-only", ref, "--", ".github/workflows"])
    if rc != 0:
        raise Stop(f"could not list the workflows at {ref[:12]}: {err.strip()[:200]}")
    files = []
    for path in [p for p in out.split("\0") if p]:
        rc, text, err = run_cmd([GIT, "-C", cwd, "show", f"{ref}:{path}"])
        if rc != 0:
            raise Stop(f"could not read {path} at {ref[:12]}")
        files.append((path, text))
    return files


def read_at(cwd, ref, path):
    rc, out, err = run_cmd([GIT, "-C", cwd, "show", f"{ref}:{path}"])
    return out if rc == 0 else None


def releases_on_push(cwd, ref, default):
    """Workflows at `ref` that publish when `default` moves (scripts/lib/workflows.py; unknown counts as yes)."""
    return workflows.publishing(workflow_files(cwd, ref), lambda path: read_at(cwd, ref, path), default)


def expects_pr_checks(cwd, ref, default):
    """A workflow that runs on every pull_request into the default branch will report a check."""
    return any(workflows.runs_on_every_pr(text, default) for _, text in workflow_files(cwd, ref))


def touches_ci(cwd, base, head):
    out = git(cwd, "diff", "--name-only", f"{base}..{head}", "--", ".github/workflows", ".github/actions")
    return [p for p in out.splitlines() if p]


def scan_commits(cwd, base, head, n=None):
    """(foreign, trapped) short SHAs for base..head, from local git (no list cap)."""
    log = git(cwd, "log", "--format=%H%x00%s%x00%b%x1e", f"{base}..{head}")
    commits = [c.strip("\n") for c in log.split("\x1e") if c.strip()]
    ref = re.compile(rf"#{n}(?![0-9])") if n is not None else None
    foreign, trapped = [], []
    for entry in commits:
        oid, subj, body = (entry.split("\x00") + ["", ""])[:3]
        text = subj + "\n" + body
        if ref is not None and not ref.search(text):
            foreign.append(oid[:7])
        if trap_hits(text):
            trapped.append(oid[:7])
    return commits, foreign, trapped


def trap_hits(text):
    return [m.group(0) for m in TRAP_RE.finditer(text or "")]


# ── run: PR ────────────────────────────────────────────────────────────────

def wait_for_checks(repo, pr, expect_pr_event, timeout, grace):
    """Accept only a check set that is all passed AND has not changed for `grace` seconds.

    Jobs that depend on other jobs (`needs:`) create their check runs only when
    the earlier job ends; a set that looks complete for one poll can still grow
    (#392 verify r3 #40). The grace window restarts whenever the set changes.
    """
    start = now()
    last_set, stable_since = None, start
    while True:
        rc, out, err = run_cmd([GH, "pr", "checks", str(pr), "--repo", repo, "--json", "name,bucket,event"])
        checks = None
        if rc in (0, 1, 8):   # 1: a check failed, 8: one is pending — gh still prints the list (verify r8 #12)
            try:
                checks = json.loads(out)
                assert isinstance(checks, list)
            except (ValueError, AssertionError):
                checks = None
        if checks is None:
            if "no checks reported" in (err + out):
                checks = []
            elif rc in (0, 8):
                raise Stop("guardrail 2 (CI checks) — unreadable gh output")
            else:
                raise Stop(f"guardrail 2 (CI checks) — gh pr checks exited {rc}: {err.strip()[:200]}")
        bad = [str(c.get("name")) for c in checks if c.get("bucket") in ("fail", "cancel")]
        if bad:
            raise Stop(f"guardrail 2 (CI checks) — failed: {', '.join(bad)}")
        pending = [str(c.get("name")) for c in checks if c.get("bucket") == "pending"]
        pr_event = any(c.get("event") in ("pull_request", "pull_request_target") for c in checks)
        current = sorted((str(c.get("name")), str(c.get("bucket"))) for c in checks)
        t = now()
        if current != last_set:
            last_set, stable_since = current, t
        if not pending and (t - stable_since) >= grace and (pr_event or not expect_pr_event):
            return f"{len(checks)} check(s) passed" if checks else "no checks reported and no workflow runs on every pull_request"
        if t - start >= timeout:
            if pending:
                what = "pending: " + ", ".join(pending)
            elif expect_pr_event and not pr_event:
                what = "no pull_request check has appeared although a workflow runs on every pull_request"
            else:
                what = "the check set was still changing"
            raise Stop(f"guardrail 2 (CI checks) — still waiting after {int(timeout // 60)} minute(s): {what}")
        time.sleep(20 * SLEEP)


def remote_checks_once(repo, pr):
    """The PR's remote checks read once, without waiting: (failed names, pending names), or (None, None) when unreadable."""
    rc, out, err = run_cmd([GH, "pr", "checks", str(pr), "--repo", repo, "--json", "name,bucket,event"])
    if rc not in (0, 1, 8):   # 1: a check failed, 8: one is pending — gh still prints the list
        return None, None
    try:
        checks = json.loads(out)
        assert isinstance(checks, list)
    except (ValueError, AssertionError):
        return ([], []) if "no checks reported" in (err + out) else (None, None)
    return ([str(c.get("name")) for c in checks if c.get("bucket") in ("fail", "cancel")],
            [str(c.get("name")) for c in checks if c.get("bucket") == "pending"])


def ci_guardrail(cwd, sha):
    """Guardrail 2: the local CI gate decides (capability local-ci-gate, #465). Returns "pass" or "remote"; anything
    else stops. The gate runs here, in the process that merges or pushes: a result handed over from an earlier
    step could be another commit's."""
    rc = local_ci(cwd, sha)
    if rc == 0:
        return "pass"
    if rc == 10:
        return "remote"
    raise Stop(f"guardrail 2 (CI) — the local CI gate ended with {CI_GATE_RESULTS.get(rc, 'an unknown code')} (exit {rc}) "
               f"for {sha[:7]}; run scripts/idd-ci-gate.sh run --commit {sha[:7]} to see it")


def check_merge_queue(repo, branch):
    owner, name = repo.split("/", 1)
    q = "query($o:String!,$r:String!,$b:String!){repository(owner:$o,name:$r){mergeQueue(branch:$b){id}}}"
    data = gh_json(["api", "graphql", "-f", f"query={q}", "-f", f"o={owner}", "-f", f"r={name}", "-f", f"b={branch}"],
                   "whether the default branch uses a merge queue")
    if (((data.get("data") or {}).get("repository") or {}).get("mergeQueue")):
        raise Stop(f"{branch} uses a merge queue; the close stage merges only directly — merge it through the queue by hand")


def pr_base(cwd, repo, default, sha):
    """Fetch the default branch and check what a merge onto its tip would do; return the tip.

    Run before the CI wait and again after it, right before the merge: the
    wait can last 15 minutes and other PRs land meanwhile (r4 #1, #32, #38, #45).
    """
    git(cwd, "fetch", "-q", "origin", default)
    tip = git(cwd, "rev-parse", f"origin/{default}")
    if git(cwd, "merge-base", tip, sha) != tip:
        raise Stop(f"the branch is behind {default} (new commits landed during the run) — the merged tree was never "
                   "reviewed; update the branch and verify again")
    # Both trees: a change can add publishing to a script a push workflow already runs (r6 #13).
    published = releases_on_push(cwd, tip, default) + releases_on_push(cwd, sha, default)
    if published:
        raise Stop(f"a workflow publishes on push to {default} ({', '.join(published)}): merging is a release — run with --review")
    changed_ci = touches_ci(cwd, tip, sha)
    if changed_ci:
        raise Stop(f"the change edits CI ({', '.join(changed_ci[:3])}) — workflow changes are merged by a person")
    check_merge_queue(repo, default)
    return tip


def write_result(cwd, n, result):
    os.makedirs(state_dir(cwd), exist_ok=True)
    with open(result_path(cwd, n), "w", encoding="utf-8") as fh:
        json.dump(result, fh, ensure_ascii=False)


def run_pr(st, cwd, repo, n, timeout, grace, partial):
    default = st["default"]
    prs = gh_json(["pr", "list", "--repo", repo, "--head", st["branch"], "--state", "open",
                   "--json", "number,headRefName,baseRefName,headRefOid,title,url,isCrossRepository"], "the open PRs")
    prs = [p for p in prs if p.get("headRefName") == st["branch"] and p.get("baseRefName") == default
           and p.get("isCrossRepository") is False]
    if len(prs) != 1:
        raise Stop(f"expected exactly one open PR from {st['branch']} (this repo) into {default}, found {len(prs)}")
    pr = prs[0]
    sha = pr.get("headRefOid") or ""
    local = git(cwd, "rev-parse", "HEAD")
    if local != sha:
        raise Stop(f"the PR head {sha[:7]} is not this run's commit {local[:7]} — not merging")
    base = pr_base(cwd, repo, default, sha)
    since = parse_iso(st["created_at"])

    rc, gate = judge_report(repo, n, sha, base, since)
    merge_gate(st, rc, gate, sha)

    # Local CI decides; remote checks are waited for only in remote mode. With a local pass they are read once,
    # right before the merge, and reported (capability local-ci-gate: they do not block the merge decision).
    local = ci_guardrail(cwd, sha)
    if local == "remote":
        ci = wait_for_checks(repo, pr["number"], expects_pr_checks(cwd, sha, default), timeout, grace)
    else:
        ci = "local CI passed"

    refs = gh_json(["pr", "view", str(pr["number"]), "--repo", repo, "--json", "closingIssuesReferences"],
                   "the PR's closing references").get("closingIssuesReferences") or []
    if refs:
        raise Stop("guardrail 3 (auto-close trap) — the PR body would close: "
                   + ", ".join(str(r.get("url", "?")) for r in refs))
    # The PR's commits, read from local git over the exact range (local HEAD == PR head was checked
    # above): `gh pr view --json commits` is capped and would leave later commits unscanned (r3 #2).
    _, foreign, hits = scan_commits(cwd, base, sha, n)
    if foreign:
        # Only this run's commits go into the squash, as on the direct-commit path (r5 #23)
        raise Stop(f"commit(s) {', '.join(foreign)} on the branch do not reference #{n} — they are not this run's; not merging")
    if hits:
        raise Stop("guardrail 3 (auto-close trap) — close keyword next to an issue reference in commit(s): " + ", ".join(hits))

    subject = f"{pr.get('title') or ''} (#{pr['number']})"
    how = f"stop mode {st['verify_stop']}" if st.get("verify_stop") else "a clean verify"
    body = f"Refs #{n}\n\nMerged by /idd-all after {how}: {gate.get('verify_url')}\n"
    if trap_hits(subject + "\n" + body):
        raise Stop(f"guardrail 4 (squash message) — close keyword next to an issue reference: {subject[:120]}")

    # The CI wait can take minutes: everything that can change meanwhile is read again right before the merge.
    base = pr_base(cwd, repo, default, sha)
    rc, gate = judge_report(repo, n, sha, base, since)
    merge_gate(st, rc, gate, sha)
    me = session_login()
    comments = issue_comments(repo, n)
    check_others(me, since, comments, issue_meta(repo, n))
    check_pr_people(repo, pr["number"], me)
    remote = {}
    if local == "pass":
        failed, pending = remote_checks_once(repo, pr["number"])
        remote = {"remote_ci_failed": "not readable" if failed is None else failed,
                  "remote_ci_pending": [] if pending is None else pending}

    partial.update({"pr": pr["number"], "pr_url": pr.get("url"), "verified_sha": sha, "merge_attempted": True})
    # Written before the merge call: if this process dies after GitHub merged, the
    # result still says a merge may have happened (r4 #34).
    write_result(cwd, n, dict(partial, status="stopped",
                              reason=f"interrupted after the merge call started — PR #{pr['number']} may be merged; check it",
                              interaction=st.get("interaction", "unknown")))
    rc, out, err = run_cmd([GH, "pr", "merge", str(pr["number"]), "--repo", repo, "--squash",
                            "--subject", subject, "--body", body, "--match-head-commit", sha])
    if rc != 0:
        try:
            after = gh_json(["pr", "view", str(pr["number"]), "--repo", repo, "--json", "state"], "the PR").get("state")
        except Stop:
            after = "unreadable"
        if after != "MERGED":
            partial["merge_attempted"] = "refused" if after == "OPEN" else True
            raise Stop(f"merge — gh pr merge failed (PR #{pr['number']} reads {after}): {err.strip()[:300]}"
                       + ("" if after == "OPEN" else " — it may have merged; check the PR"))
    view, merge_sha = {}, ""
    for attempt in range(4):
        try:
            view = gh_json(["pr", "view", str(pr["number"]), "--repo", repo, "--json", "state,mergeCommit,mergedAt"],
                           "the PR after merging")
        except Stop:
            view = {}
        merge_sha = ((view.get("mergeCommit") or {}).get("oid")) or ""
        if view.get("state") == "MERGED" and merge_sha:
            break
        time.sleep(5 * SLEEP)
    else:
        state = view.get("state") or "unreadable"
        if state == "OPEN":
            partial["merge_attempted"] = "refused"
            rc2, _, err2 = run_cmd([GH, "pr", "merge", str(pr["number"]), "--repo", repo, "--disable-auto"])
            note = "auto-merge disabled" if rc2 == 0 else f"could not disable auto-merge: {err2.strip()[:120]}"
            raise Stop(f"merge — PR #{pr['number']} is still OPEN after gh pr merge ({note}); not closing — check the PR")
        raise Stop(f"merge — gh pr merge succeeded but PR #{pr['number']} reads {state} without a merge commit; "
                   "it may have merged — check the PR before running /idd-close")
    run_cmd([GIT, "-C", cwd, "fetch", "-q", "origin"])
    return {"status": "merged", "pr": pr["number"], "pr_url": pr.get("url"), "merge_sha": merge_sha,
            "merged_at": view.get("mergedAt"),
            "verified_sha": sha, "reviewed_base": base, "verify_url": gate.get("verify_url"), "ci": ci,
            "local_ci": local, "low_in_scope": gate.get("low_in_scope") or 0, "default": default, **remote}


# ── run: direct-commit ─────────────────────────────────────────────────────

def run_direct(st, cwd, repo, n, partial):
    default = st["default"]
    cur = git(cwd, "branch", "--show-current")
    if cur != default:
        raise Stop(f"the fix is on '{cur}', not on the default branch '{default}' — not pushing, not closing")
    git(cwd, "fetch", "-q", "origin", default)
    head = git(cwd, "rev-parse", "HEAD")
    base = git(cwd, "rev-parse", f"origin/{default}")
    if git(cwd, "merge-base", base, head) != base:
        raise Stop(f"origin/{default} has commits this clone does not — not pushing (no automatic rebase)")
    published = releases_on_push(cwd, base, default) + releases_on_push(cwd, head, default)
    if published:
        raise Stop(f"a workflow publishes on push to {default} ({', '.join(published)}): pushing is a release — run with --review")
    changed_ci = touches_ci(cwd, base, head)
    if changed_ci:
        raise Stop(f"the change edits CI ({', '.join(changed_ci[:3])}) — workflow changes are pushed by a person")
    rc, gate = judge_report(repo, n, head, base, parse_iso(st["created_at"]))
    merge_gate(st, rc, gate, head)
    # Local CI before the push. In remote mode there is no remote result for commits that were never pushed,
    # so the push proceeds and remote CI runs after it (as before #465).
    local = ci_guardrail(cwd, head)
    # The local CI gate can run for up to an hour: what can change meanwhile is read again before the push,
    # as the PR path does after its CI wait (verify r8 #1).
    since = parse_iso(st["created_at"])
    rc, gate = judge_report(repo, n, head, base, since)
    merge_gate(st, rc, gate, head)
    check_others(session_login(), since, issue_comments(repo, n), issue_meta(repo, n))
    # Everything below names `head`, never HEAD: another session can move HEAD
    # or switch the branch while the checks run (#392 verify r2 #1).
    commits, foreign, trapped = scan_commits(cwd, base, head, n)
    if not commits:
        raise Stop(f"nothing to push: {head[:7]} is already on origin/{default}")
    if foreign:
        raise Stop(f"commit(s) {', '.join(foreign)} do not reference #{n} — they are not this run's, not pushing")
    if trapped:
        raise Stop(f"commit(s) {', '.join(trapped)} carry a close keyword next to an issue reference — "
                   "GitHub would close the issue without /idd-close; not pushing")
    if git(cwd, "rev-parse", "HEAD") != head or git(cwd, "branch", "--show-current") != default:
        raise Stop("HEAD or the branch changed while the checks ran — not pushing")
    partial.update({"verified_sha": head, "push_attempted": True, "push_from": base, "push_to": head})
    write_result(cwd, n, dict(partial, status="stopped",
                              reason=f"interrupted after the push started — {default} may already be at {head[:7]}; check it",
                              interaction=st.get("interaction", "unknown")))
    rc, out, err = run_cmd([GIT, "-C", cwd, "push", "origin", f"{head}:refs/heads/{default}"])
    if rc != 0:
        partial["push_attempted"] = "refused"
        raise Stop(f"push rejected (no automatic rebase) — not closing: {err.strip()[:300]}")
    # Confirm on GitHub that the default branch now points at the verified commit (r3 #9).
    landed = (gh_json(["api", f"repos/{repo}/branches/{default}"], f"{default} on GitHub").get("commit") or {}).get("sha")
    if landed != head:
        raise Stop(f"pushed, but GitHub's {default} is at {str(landed)[:7]}, not {head[:7]} — check the remote before closing")
    return {"status": "pushed", "push_from": base, "push_to": head, "count": len(commits),
            "verified_sha": head, "reviewed_base": base, "verify_url": gate.get("verify_url"), "default": default,
            "local_ci": local, "low_in_scope": gate.get("low_in_scope") or 0}


def cmd_run(argv):
    a = parse(argv, {"--cwd": "value", "--repo": "value", "--issue": "value",
                     "--ci-timeout": "value", "--ci-grace": "value"})
    if a is None or not common_ok(a):
        return usage("run needs --cwd <dir> --repo owner/repo --issue <digits>")
    try:
        timeout = float(a.get("--ci-timeout", 900))
        grace = float(a.get("--ci-grace", 90))
        assert math.isfinite(timeout) and math.isfinite(grace) and timeout >= 0 and grace >= 0
    except (ValueError, AssertionError):
        return usage("--ci-timeout and --ci-grace are non-negative seconds")
    cwd, repo, n = os.path.realpath(a["--cwd"]), a["--repo"], a["--issue"]
    try:
        if os.path.exists(result_path(cwd, n)):
            os.unlink(result_path(cwd, n))   # never let an earlier run's result stand for this one
    except (OSError, Stop):
        pass
    st, partial = {}, {}
    try:
        st = load_state(cwd, repo, n)
        if st.get("review"):
            raise Stop("--review: the run stays at verified (no merge, no close)")
        if st.get("in_chain"):
            raise Stop("--in-chain: /idd-all-chain owns the cluster PR (no merge, no close)")
        if st.get("path") != st.get("requested_path"):
            raise Stop(f"the run was downgraded from {st.get('requested_path')} to {st.get('path')} "
                       "(ralph-loop missing) — stays at verified; a person decides where the change goes")
        perm = gh_json(["repo", "view", repo, "--json", "viewerPermission"], "the repo permission").get("viewerPermission")
        if perm not in WRITE_PERMS:
            raise Stop(f"this account has {perm or 'no'} permission on {repo}; the close stage runs only where it can write")
        check_origin(cwd, repo)
        me = session_login()
        since = parse_iso(st["created_at"])
        comments = issue_comments(repo, n)
        meta = issue_meta(repo, n)
        issue = issue_view(repo, n)
        check_meeting(comments)
        check_issue_authors(repo, meta)
        check_others(me, since, comments, meta)
        corrections = check_intent(repo, n, st, comments, issue)
        if st.get("path") == "PR":
            result = run_pr(st, cwd, repo, n, timeout, grace, partial)
        elif st.get("path") == "direct-commit":
            result = run_direct(st, cwd, repo, n, partial)
        else:
            raise Stop("the run state has no path")
        result["done_at"] = iso(now())
        result["proposed_corrections"] = corrections
        code = 0
    except Stop as exc:
        result, code = dict(partial, status="stopped", reason=str(exc)), 3
    except Exception as exc:  # fail closed: a crash is a stop, with whatever was already done
        result, code = dict(partial, status="stopped", reason=f"internal error: {exc.__class__.__name__}: {exc}"), 3
    result["interaction"] = st.get("interaction", "unknown")
    try:
        write_result(cwd, n, result)
    except (OSError, Stop) as exc:
        result["result_file"] = f"not written: {exc}"
    print(json.dumps(result, ensure_ascii=False))
    return code


# ── confirm-close ──────────────────────────────────────────────────────────

def cmd_confirm(argv):
    a = parse(argv, {"--cwd": "value", "--repo": "value", "--issue": "value"})
    if a is None or not common_ok(a):
        return usage("confirm-close needs --cwd --repo --issue")
    cwd, repo, n = a["--cwd"], a["--repo"], a["--issue"]
    try:
        try:
            with open(result_path(cwd, n), encoding="utf-8") as fh:
                res = json.load(fh)
        except (OSError, ValueError):
            raise Stop("no close-stage result for this issue")
        if res.get("status") not in ("merged", "pushed") or not res.get("done_at"):
            raise Stop("the close stage did not merge or push, so there is nothing to confirm")
        # GitHub's own clock where GitHub recorded the event (the merge); the local clock, with slack, for a push.
        since = parse_iso(res["merged_at"]) - 5 if res.get("merged_at") else parse_iso(res["done_at"]) - 300
        state = gh_json(["issue", "view", n, "--repo", repo, "--json", "state"], "the issue state").get("state")
        if state != "CLOSED":
            raise Stop(f"the issue is {state}")
        me = session_login()
        comments = gh_paginated(f"repos/{repo}/issues/{n}/comments",
                                "[.[] | {html_url, login: .user.login, created_at, body}]", f"the comments of #{n}")
        # Positive confirmation, not the audit classifier: that one may only veto
        # (check-closed-without-summary.sh --issue, "MAY VETO. IT MAY NOT PERMIT"),
        # and counts prose mentions. /idd-close writes the canonical heading.
        ok = [c for c in comments if c.get("login") == me
              and (c.get("body") or "").lstrip("\ufeff").lstrip().split("\n", 1)[0].strip() == "## Closing Summary"
              and parse_iso(c.get("created_at", "1970-01-01T00:00:00Z")) >= since]
        if not ok:
            raise Stop("no '## Closing Summary' comment by this account after the merge or push")
        print(json.dumps({"status": "closed", "summary_url": ok[-1].get("html_url")}, ensure_ascii=False))
        return 0
    except Stop as exc:
        print(json.dumps({"status": "not_confirmed", "reason": str(exc)}, ensure_ascii=False))
        return 3
    except Exception as exc:
        print(json.dumps({"status": "not_confirmed", "reason": f"internal error: {exc.__class__.__name__}: {exc}"}))
        return 3


# ── pr-check: may the run open its pull request without asking? ────────────
# The SKILL's 權限 section: opening the pull request is reversible (it can be closed and edited)
# unless it notifies a person or would close the issue on merge. The privacy self-review of the
# text is the model's; this check covers what a program can decide.

CODEOWNERS_PATHS = (".github/CODEOWNERS", "CODEOWNERS", "docs/CODEOWNERS")
# An @ before a letter or digit, unless a letter or digit comes right before it (an e-mail address, a version
# pin such as pkg@1.2). Wider than what GitHub notifies on (code spans count too): the extra cases only ask.
# An @ written as a character reference is counted whatever follows it.
MENTION_RE = re.compile(r"(?<![A-Za-z0-9])@[A-Za-z0-9][A-Za-z0-9-]*|&#0*64;|&#[xX]0*40;|&commat;")
BRANCH_RE = re.compile(r"^[A-Za-z0-9._/][A-Za-z0-9._/-]*$")


def pr_check(cwd, default, title, body):
    """The reason the run must ask before opening the pull request, or None."""
    if not title.strip():
        return "the title is empty — the run did not set the pull request's title"
    text = title + "\n" + body
    mention = MENTION_RE.search(text)
    if mention:
        return f"the title or the body mentions an account ({mention.group(0)[:40]}): a notification cannot be recalled"
    hits = trap_hits(text)
    if hits:
        return "a close keyword next to an issue reference in the title or the body: " + ", ".join(h[:40] for h in hits[:3])
    ref = f"refs/remotes/origin/{default}"
    # Read the default branch as the remote has it now: a CODEOWNERS file added during the run counts (verify r8 #7).
    rc, out, err = run_cmd([GIT, "-C", cwd, "fetch", "-q", "origin", f"+refs/heads/{default}:{ref}"])
    if rc != 0:
        return f"could not fetch origin/{default} — cannot tell whether a CODEOWNERS file exists"
    rc, out, err = run_cmd([GIT, "-C", cwd, "rev-parse", "--verify", "--quiet", ref + "^{commit}"])
    if rc != 0:
        return f"could not read origin/{default} in the local clone — cannot tell whether a CODEOWNERS file exists"
    rc, out, err = run_cmd([GIT, "-C", cwd, "ls-tree", "-z", "--name-only", ref, "--"] + list(CODEOWNERS_PATHS))
    if rc != 0:
        return f"could not list origin/{default} — cannot tell whether a CODEOWNERS file exists"
    found = [path for path in out.split("\0") if path]
    if found:
        return f"the default branch has {found[0]}: opening the pull request would request a review from a person"
    return None


def cmd_pr_check(argv):
    a = parse(argv, {"--cwd": "value", "--default": "value", "--title-file": "value", "--body-file": "value"})
    if a is None or not (a.get("--cwd") and os.path.isdir(a["--cwd"])) or not BRANCH_RE.match(a.get("--default", "")) \
            or not all(a.get(k) and os.path.isfile(a[k]) for k in ("--title-file", "--body-file")):
        return usage("pr-check needs --cwd --default (a branch name) --title-file --body-file (existing files)")
    try:
        with open(a["--title-file"], encoding="utf-8") as fh:
            title = fh.read()
        with open(a["--body-file"], encoding="utf-8") as fh:
            body = fh.read()
        reason = pr_check(a["--cwd"], a["--default"], title, body)
    except Exception as exc:  # fail closed: a surprise means ask, never open
        reason = f"internal error: {exc.__class__.__name__}: {exc}"
    if reason:
        print(json.dumps({"status": "ask", "reason": reason}, ensure_ascii=False))
        return 3
    print(json.dumps({"status": "open"}))
    return 0


def main(argv):
    if not argv:
        return usage("subcommand required: init | reset | gate | next | pr-check | run | confirm-close")
    sub, rest = argv[0], argv[1:]
    handlers = {"init": cmd_init, "reset": cmd_reset, "gate": cmd_gate, "next": cmd_next, "pr-check": cmd_pr_check,
                "run": cmd_run,
                "confirm-close": cmd_confirm}
    if sub not in handlers:
        return usage(f"unknown subcommand '{sub}'")
    return handlers[sub](rest)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
