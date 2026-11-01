#!/usr/bin/env python3
"""close-stage.py — /idd-all's close stage, in one process (#392).

Why a helper and not bash blocks in the skill: every check that guards a merge
or a push has to run in the SAME process as the merge or push. Bash blocks in a
skill run one tool call at a time, and a failed check that ends its own block
with `exit 0` does not stop the next block (#383 r2 #12; #392 verify r1 #9).
Shell variables do not survive between tool calls either, so values the checks
depend on (the run's flags, the PR, the verified commit) are read from a state
file and from GitHub here, never from the model's memory.

Subcommands
  init  --cwd C --repo O/R --issue N --path PR|direct-commit
        --interaction attended|unattended --branch B --default D [--review] [--in-chain]
        Phase 0.5: record the run's flags in C/.claude/.idd/state/idd-all-run-N.json.
  gate  --cwd C --repo O/R --issue N --sha SHA
        Read the newest '## Verify: #N' report posted by the account running this
        session and judge it with verify-gate.py --expect-sha SHA.
        Prints the gate JSON plus comment_id / verify_url. Exit 0 clean, 1 not
        clean, 2 unparseable (including: no such report), 64 usage.
  run   --cwd C --repo O/R --issue N [--ci-timeout S] [--ci-grace S]
        Phase 5c: every guardrail, then the squash merge (PR) or the push
        (direct-commit). Prints one JSON line and writes it to
        C/.claude/.idd/state/idd-all-result-N.json.
        Exit 0 merged/pushed, 3 stopped (reason in the JSON), 64 usage.

Fail closed throughout: anything that cannot be read or checked stops the
stage. Nothing here asks a person; a stop is reported, not negotiated.

Test seams: IDD_GH / IDD_GIT name the gh and git executables; IDD_SLEEP=0
makes the CI wait loop not sleep.
"""

import json
import os
import re
import subprocess
import sys
import tempfile
import time

HERE = os.path.dirname(os.path.abspath(__file__))
GH = os.environ.get("IDD_GH", "gh")
GIT = os.environ.get("IDD_GIT", "git")
WRITE_PERMS = {"WRITE", "MAINTAIN", "ADMIN"}
TRUSTED = {"OWNER", "MEMBER", "COLLABORATOR"}
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


class Stop(Exception):
    """A guardrail did not pass; the message is the reason, reported verbatim."""


def run_cmd(cmd, cwd=None, check=False):
    proc = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    if check and proc.returncode != 0:
        raise Stop(f"{' '.join(cmd[:3])} failed: {proc.stderr.strip()[:300]}")
    return proc.returncode, proc.stdout, proc.stderr


def gh_json(args, what):
    rc, out, err = run_cmd([GH] + args)
    if rc != 0:
        raise Stop(f"could not read {what}: {err.strip()[:300] or 'gh exited ' + str(rc)}")
    try:
        return json.loads(out)
    except ValueError:
        raise Stop(f"could not read {what}: gh did not return JSON")


def gh_paginated(path, jq, what):
    rc, out, err = run_cmd([GH, "api", path, "--paginate", "--jq", jq])
    if rc != 0:
        raise Stop(f"could not read {what}: {err.strip()[:300] or 'gh exited ' + str(rc)}")
    items, dec, i = [], json.JSONDecoder(), 0
    out = out.strip()
    while i < len(out):
        page, j = dec.raw_decode(out, i)
        items.extend(page)
        i = j
        while i < len(out) and out[i].isspace():
            i += 1
    return items


def git(cwd, *args, check=True):
    rc, out, err = run_cmd([GIT, "-C", cwd] + list(args))
    if check and rc != 0:
        raise Stop(f"git {args[0]} failed: {err.strip()[:300]}")
    return out.strip()


def state_dir(cwd):
    return os.path.join(cwd, ".claude", ".idd", "state")


def state_path(cwd, n):
    return os.path.join(state_dir(cwd), f"idd-all-run-{n}.json")


def result_path(cwd, n):
    return os.path.join(state_dir(cwd), f"idd-all-result-{n}.json")


# ── arguments ──────────────────────────────────────────────────────────────

def parse(argv, spec):
    """spec: {flag: kind} with kind in ('value', 'switch'). Returns dict or None."""
    out, i = {}, 0
    while i < len(argv):
        flag = argv[i]
        if flag not in spec or flag in out:
            return None
        if spec[flag] == "switch":
            out[flag] = True
            i += 1
        else:
            if i + 1 >= len(argv) or argv[i + 1] == "":
                return None
            out[flag] = argv[i + 1]
            i += 2
    return out


def usage(msg):
    print(f"close-stage: {msg}", file=sys.stderr)
    return 64


def common_ok(a):
    return (a.get("--cwd") and os.path.isdir(a["--cwd"])
            and REPO_RE.match(a.get("--repo", ""))
            and re.match(r"^[0-9]+$", a.get("--issue", "")))


# ── init ───────────────────────────────────────────────────────────────────

def cmd_init(argv):
    a = parse(argv, {"--cwd": "value", "--repo": "value", "--issue": "value", "--path": "value",
                     "--interaction": "value", "--branch": "value", "--default": "value",
                     "--review": "switch", "--in-chain": "switch"})
    if a is None or not common_ok(a):
        return usage("init needs --cwd <dir> --repo owner/repo --issue <digits> and the run's flags")
    if a.get("--path") not in ("PR", "direct-commit") or a.get("--interaction") not in ("attended", "unattended"):
        return usage("--path must be PR or direct-commit; --interaction must be attended or unattended")
    if not a.get("--branch") or not a.get("--default"):
        return usage("--branch and --default are required")
    state = {
        "repo": a["--repo"], "issue": int(a["--issue"]), "path": a["--path"],
        "interaction": a["--interaction"], "branch": a["--branch"], "default": a["--default"],
        "review": bool(a.get("--review")), "in_chain": bool(a.get("--in-chain")),
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    os.makedirs(state_dir(a["--cwd"]), exist_ok=True)
    with open(state_path(a["--cwd"], a["--issue"]), "w") as fh:
        json.dump(state, fh)
    print(state_path(a["--cwd"], a["--issue"]))
    return 0


# ── gate ───────────────────────────────────────────────────────────────────

def session_login():
    rc, out, err = run_cmd([GH, "api", "user", "--jq", ".login"])
    login = out.strip()
    if rc != 0 or not login:
        raise Stop("could not read the account running this session (gh api user)")
    return login


def latest_report(repo, n):
    """Newest '## Verify: #N' comment written by the account running this session.

    Only that account: `author_association` MEMBER / COLLABORATOR also covers
    people with read access, and this report decides a merge (#392 verify r1 #26).
    """
    me = session_login()
    comments = gh_paginated(f"repos/{repo}/issues/{n}/comments",
                            "[.[] | {id, html_url, login: .user.login, body}]",
                            f"the comments of #{n}")
    head = re.compile(rf"^## Verify: #{n}(?![0-9])")
    mine = [c for c in comments if c.get("login") == me and head.match(c.get("body") or "")]
    return mine[-1] if mine else None


def judge_report(repo, n, sha):
    report = latest_report(repo, n)
    if report is None:
        return 2, {"status": "unparseable", "reason": f"no '## Verify: #{n}' report by the account running this session"}
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False) as fh:
        fh.write(report["body"])
        tmp = fh.name
    try:
        rc, out, err = run_cmd([sys.executable, "-I", os.path.join(HERE, "verify-gate.py"),
                                "--comment-file", tmp, "--expect-sha", sha])
    finally:
        os.unlink(tmp)
    try:
        result = json.loads(out)
    except ValueError:
        return 2, {"status": "unparseable", "reason": f"verify-gate.py gave no JSON (exit {rc})"}
    result["comment_id"] = report["id"]
    result["verify_url"] = report["html_url"]
    return rc, result


def cmd_gate(argv):
    a = parse(argv, {"--cwd": "value", "--repo": "value", "--issue": "value", "--sha": "value"})
    if a is None or not common_ok(a) or not SHA_RE.match(a.get("--sha", "")):
        return usage("gate needs --cwd --repo --issue and --sha <40 lowercase hex digits>")
    try:
        rc, result = judge_report(a["--repo"], a["--issue"], a["--sha"])
    except Stop as exc:
        rc, result = 2, {"status": "unparseable", "reason": str(exc)}
    print(json.dumps(result, ensure_ascii=False))
    return rc


# ── run ────────────────────────────────────────────────────────────────────

def load_state(cwd, repo, n):
    try:
        with open(state_path(cwd, n)) as fh:
            st = json.load(fh)
    except (OSError, ValueError):
        raise Stop("no run state for this issue (Phase 0.5 did not record the run's flags) — not merging")
    if st.get("repo") != repo or str(st.get("issue")) != str(n):
        raise Stop("the run state names another repo or issue — not merging")
    return st


def check_meeting(repo, n):
    comments = gh_paginated(f"repos/{repo}/issues/{n}/comments",
                            "[.[] | {assoc: .author_association, body}]", f"the comments of #{n}")
    diag = [c["body"] for c in comments
            if c.get("assoc") in TRUSTED and re.match(r"^## Diagnosis[ \t]*(\r?\n|$)", c.get("body") or "")]
    body = diag[-1] if diag else ""
    rc, out, err = run_cmd(["bash", "-c", '. "$1/lib/actionability.sh" && idd_diagnosis_type "$2"', "_", HERE, body])
    if rc != 0:
        raise Stop("could not re-read the Diagnosis type")
    if out.strip() == "meeting":
        raise Stop("the latest trusted Diagnosis records type meeting — meeting issues are never merged or pushed")


def trap_hits(text):
    return [m.group(0) for m in TRAP_RE.finditer(text or "")]


def wait_for_checks(repo, pr, cwd, timeout, grace):
    start, sleep = time.time(), (0 if os.environ.get("IDD_SLEEP") == "0" else 20)
    expects_pr_checks = workflows_on_pull_request(cwd)
    while True:
        rc, out, err = run_cmd([GH, "pr", "checks", str(pr), "--repo", repo, "--json", "name,bucket"])
        if rc not in (0, 8):
            if "no checks reported" in (err + out):
                checks = []
            else:
                raise Stop(f"guardrail 2 (CI checks) — gh pr checks exited {rc}: {err.strip()[:200]}")
        else:
            try:
                checks = json.loads(out)
            except ValueError:
                raise Stop("guardrail 2 (CI checks) — unreadable gh output")
        bad = [c["name"] for c in checks if c.get("bucket") in ("fail", "cancel")]
        if bad:
            raise Stop(f"guardrail 2 (CI checks) — failed: {', '.join(bad)}")
        pending = [c["name"] for c in checks if c.get("bucket") == "pending"]
        elapsed = time.time() - start
        if checks and not pending:
            return f"{len(checks)} check(s) passed"
        if not checks and not expects_pr_checks and elapsed >= grace:
            return "no checks reported and no workflow runs on pull_request"
        if elapsed >= timeout:
            what = ", ".join(pending) if pending else "no check has appeared although a workflow runs on pull_request"
            raise Stop(f"guardrail 2 (CI checks) — still waiting after {int(timeout // 60)} minutes: {what}")
        time.sleep(sleep)


def workflows_on_pull_request(cwd):
    """True when a tracked workflow file mentions pull_request (so checks should appear)."""
    rc, out, err = run_cmd([GIT, "-C", cwd, "ls-files", ".github/workflows"])
    for path in out.split():
        try:
            with open(os.path.join(cwd, path), encoding="utf-8", errors="replace") as fh:
                if "pull_request" in fh.read():
                    return True
        except OSError:
            continue
    return False


def run_pr(st, cwd, repo, n, timeout, grace):
    prs = gh_json(["pr", "list", "--repo", repo, "--head", st["branch"], "--state", "open",
                   "--json", "number,headRefName,baseRefName,headRefOid,title,url"], "the open PRs")
    prs = [p for p in prs if p.get("headRefName") == st["branch"] and p.get("baseRefName") == st["default"]]
    if len(prs) != 1:
        raise Stop(f"expected exactly one open PR from {st['branch']} into {st['default']}, found {len(prs)}")
    pr = prs[0]
    sha = pr["headRefOid"]
    local = git(cwd, "rev-parse", "HEAD")
    if local != sha:
        raise Stop(f"the PR head {sha[:7]} is not this run's commit {local[:7]} — not merging")

    rc, gate = judge_report(repo, n, sha)
    if rc != 0:
        raise Stop(f"guardrail 1 (verify gate) — {gate.get('status')}: {gate.get('reason')}")

    ci = wait_for_checks(repo, pr["number"], cwd, timeout, grace)

    refs = gh_json(["pr", "view", str(pr["number"]), "--repo", repo, "--json", "closingIssuesReferences"],
                   "the PR's closing references").get("closingIssuesReferences") or []
    if refs:
        raise Stop("guardrail 3 (auto-close trap) — the PR body would close: "
                   + ", ".join(r.get("url", "?") for r in refs))
    commits = gh_json(["pr", "view", str(pr["number"]), "--repo", repo, "--json", "commits"],
                      "the PR's commits").get("commits") or []
    hits = [c.get("oid", "?")[:7] for c in commits
            if trap_hits((c.get("messageHeadline") or "") + "\n" + (c.get("messageBody") or ""))]
    if hits:
        raise Stop("guardrail 3 (auto-close trap) — close keyword next to an issue reference in commit(s): " + ", ".join(hits))

    subject = f"{pr['title']} (#{pr['number']})"
    body = f"Refs #{n}\n\nMerged by /idd-all after a clean verify: {gate['verify_url']}\n"
    if trap_hits(subject + "\n" + body):
        raise Stop(f"guardrail 4 (squash message) — close keyword next to an issue reference: {subject[:120]}")

    rc, out, err = run_cmd([GH, "pr", "merge", str(pr["number"]), "--repo", repo, "--squash",
                            "--subject", subject, "--body", body, "--match-head-commit", sha])
    if rc != 0:
        raise Stop(f"merge — gh pr merge failed, PR #{pr['number']} is still open: {err.strip()[:300]}")
    view = gh_json(["pr", "view", str(pr["number"]), "--repo", repo, "--json", "state,mergeCommit"], "the PR after merging")
    merge_sha = ((view.get("mergeCommit") or {}).get("oid")) or ""
    if view.get("state") != "MERGED" or not merge_sha:
        raise Stop(f"merge — PR #{pr['number']} is {view.get('state')} after gh pr merge (merge queue?); not closing")
    run_cmd([GIT, "-C", cwd, "fetch", "-q", "origin"])
    return {"status": "merged", "pr": pr["number"], "pr_url": pr["url"], "merge_sha": merge_sha,
            "verified_sha": sha, "verify_url": gate["verify_url"], "ci": ci}


def run_direct(st, cwd, repo, n):
    default = st["default"]
    cur = git(cwd, "branch", "--show-current")
    if cur != default:
        raise Stop(f"the fix is on '{cur}', not on the default branch '{default}' — not pushing, not closing")
    git(cwd, "fetch", "-q", "origin", default)
    head = git(cwd, "rev-parse", "HEAD")
    rc, gate = judge_report(repo, n, head)
    if rc != 0:
        raise Stop(f"guardrail 1 (verify gate) — {gate.get('status')}: {gate.get('reason')}")
    log = git(cwd, "log", "--format=%H%x00%s%x00%b%x1e", f"origin/{default}..HEAD")
    commits = [c.strip("\n") for c in log.split("\x1e") if c.strip()]
    if not commits:
        raise Stop(f"nothing to push: HEAD is already on origin/{default}")
    ref = re.compile(rf"#{n}(?![0-9])")
    foreign, trapped = [], []
    for entry in commits:
        oid, subj, body = (entry.split("\x00") + ["", ""])[:3]
        text = subj + "\n" + body
        if not ref.search(text):
            foreign.append(oid[:7])
        if trap_hits(text):
            trapped.append(oid[:7])
    if foreign:
        raise Stop(f"commit(s) {', '.join(foreign)} on {default} do not reference #{n} — they are not this run's, not pushing")
    if trapped:
        raise Stop(f"commit(s) {', '.join(trapped)} carry a close keyword next to an issue reference — GitHub would close the issue without /idd-close; not pushing")
    push_from = git(cwd, "rev-parse", f"origin/{default}")
    rc, out, err = run_cmd([GIT, "-C", cwd, "push", "origin", f"HEAD:refs/heads/{default}"])
    if rc != 0:
        raise Stop(f"push rejected (no automatic rebase) — not closing: {err.strip()[:300]}")
    return {"status": "pushed", "push_from": push_from, "push_to": head, "count": len(commits),
            "verified_sha": head, "verify_url": gate["verify_url"]}


def cmd_run(argv):
    a = parse(argv, {"--cwd": "value", "--repo": "value", "--issue": "value",
                     "--ci-timeout": "value", "--ci-grace": "value"})
    if a is None or not common_ok(a):
        return usage("run needs --cwd <dir> --repo owner/repo --issue <digits>")
    try:
        timeout = float(a.get("--ci-timeout", 900))
        grace = float(a.get("--ci-grace", 90))
    except ValueError:
        return usage("--ci-timeout and --ci-grace are seconds")
    cwd, repo, n = a["--cwd"], a["--repo"], a["--issue"]
    st = {}
    try:
        st = load_state(cwd, repo, n)
        if st.get("review"):
            raise Stop("--review: the run stays at verified (no merge, no close)")
        if st.get("in_chain"):
            raise Stop("--in-chain: /idd-all-chain owns the cluster PR (no merge, no close)")
        perm = gh_json(["repo", "view", repo, "--json", "viewerPermission"], "the repo permission").get("viewerPermission")
        if perm not in WRITE_PERMS:
            raise Stop(f"this account has {perm or 'no'} permission on {repo}; the close stage runs only where it can write")
        check_meeting(repo, n)
        if st.get("path") == "PR":
            result = run_pr(st, cwd, repo, n, timeout, grace)
        elif st.get("path") == "direct-commit":
            result = run_direct(st, cwd, repo, n)
        else:
            raise Stop("the run state has no path")
        code = 0
    except Stop as exc:
        result, code = {"status": "stopped", "reason": str(exc)}, 3
    result["interaction"] = st.get("interaction", "unknown")
    try:
        os.makedirs(state_dir(cwd), exist_ok=True)
        with open(result_path(cwd, n), "w") as fh:
            json.dump(result, fh, ensure_ascii=False)
    except OSError:
        pass
    print(json.dumps(result, ensure_ascii=False))
    return code


def main(argv):
    if not argv:
        return usage("subcommand required: init | gate | run")
    sub, rest = argv[0], argv[1:]
    if sub == "init":
        return cmd_init(rest)
    if sub == "gate":
        return cmd_gate(rest)
    if sub == "run":
        return cmd_run(rest)
    return usage(f"unknown subcommand '{sub}'")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
