#!/usr/bin/env bash
# check-existing-work.sh — does a PR or a branch already address issue N? (#366)
#
# Usage:
#   check-existing-work.sh [--cwd DIR] <owner/repo> <issue-number> [<issue-number>...]
#
# Stdout: JSON
#   {"repo":..., "truncated":bool, "errors":[...],
#    "issues":{"<N>":{"verdict":"blocked|resume|unknown|clear","reason":...,"evidence":[{"kind":"E1",...}]}}}
# Exit: 0 a result was produced (including `unknown` verdicts) · 1 no result could be produced · 2 usage error
#
# This is the ONLY implementation of "which PR/branch addresses issue N". Skills call it; they do not embed a
# pattern of their own (contract: references/pr-issue-matching.md, spec idd-existing-work-lookup).
#
# Evidence — a closed list, no content similarity:
#   E1 open PR with a line (outside a fenced block) starting Refs|Closes|Fixes|Resolves that holds #N   → blocks
#      (not when its head is the issue's own idd/N[-*] branch: that is a resume)
#   E2 open PR that holds #N otherwise                                                                   → shown
#   E3 merged PR that satisfies E1 while the issue is still OPEN                                         → blocks
#      (shown only when the issue was reopened after the PR's merge)
#   E4 remote branch idd/N or idd/N-* that is not a stale merged leftover                                → resume
#   E6 commit not on the default branch with a line `Refs #N`, on a branch that is not stale-merged      → shown
# `#N` matches only when the char before it is not [A-Za-z0-9_/-] and the char after the digits is not a digit.
# A PR created before the issue is never reported (pr-issue-matching.md, #305).
# stale-merged: the branch tip equals the head commit of a merged PR (decided by commit, not by name).
# Branches come from `git fetch` + remote-tracking refs, so --cwd must be a clone of the repo. The default branch
# comes from `gh repo view`, not from the clone's origin/HEAD (which can be stale).
set -u
exec python3 - "$@" <<'PY'
import json, re, subprocess, sys

LIMIT = 100
DECL = re.compile(r'^\s*(refs|closes|fixes|resolves)\b', re.I)
COMMIT_REFS = re.compile(r'^\s*refs\b', re.I)


def usage(msg):
    print(f"check-existing-work.sh: {msg}", file=sys.stderr)
    print("usage: check-existing-work.sh [--cwd DIR] <owner/repo> <issue-number>...", file=sys.stderr)
    sys.exit(2)


args = sys.argv[1:]
cwd = "."
if args[:1] == ["--cwd"]:
    if len(args) < 2:
        usage("--cwd needs a directory")
    cwd, args = args[1], args[2:]
if len(args) < 2:
    usage("need <owner/repo> and at least one issue number")
repo, issues = args[0], args[1:]
if not re.fullmatch(r'[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+', repo):
    usage(f"bad repo '{repo}'")
if not all(re.fullmatch(r'[0-9]+', i) for i in issues):
    usage("issue numbers must be positive integers")
issues = [int(i) for i in issues]

errors = []
truncated = False


def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def gh_json(cmd, what):
    r = run(cmd)
    if r.returncode != 0:
        errors.append(f"{what} failed: {(r.stderr or '').strip()[:160]}")
        return None
    try:
        return json.loads(r.stdout)
    except Exception:
        errors.append(f"{what} returned unparseable output")
        return None


def precise(n):
    return re.compile(r'(?<![A-Za-z0-9_/-])#%d(?!\d)' % n)


def declares(body, n, rx=DECL):
    pat, fenced = precise(n), False
    for line in (body or "").split("\n"):
        if re.match(r'^\s*(```|~~~)', line):
            fenced = not fenced
            continue
        if not fenced and rx.match(line) and pat.search(line):
            return True
    return False


def own(head, n):
    return bool(re.fullmatch(r'idd/%d(-.*)?' % n, head or ""))


# ── fetch once for the whole call ────────────────────────────────────────────
base = ["gh", "pr", "list", "--repo", repo, "--limit", str(LIMIT)]
open_prs = gh_json(base + ["--state", "open", "--json", "number,body,headRefName,headRefOid,createdAt,url"], "gh pr list --state open")
merged_prs = gh_json(base + ["--state", "merged", "--json", "number,body,headRefName,headRefOid,createdAt,mergedAt,url"], "gh pr list --state merged")
open_prs = open_prs or []
merged_prs = merged_prs or []
if len(open_prs) >= LIMIT:
    truncated = True
    errors.append(f"open PR list reached its limit ({LIMIT}); older PRs were not checked")
if len(merged_prs) >= LIMIT:
    truncated = True
    errors.append(f"merged PR list reached its limit ({LIMIT}); older merged PRs were not checked")

branches, default = {}, None
f = run(["git", "-C", cwd, "fetch", "--quiet", "--prune", "origin"])
if f.returncode != 0:
    errors.append(f"git fetch failed: {(f.stderr or '').strip()[:160]}")
r = run(["git", "-C", cwd, "for-each-ref", "--format=%(refname:short)\t%(objectname)", "refs/remotes/origin"])
if r.returncode == 0:
    for line in r.stdout.splitlines():
        name, _, oid = line.partition("\t")
        if name.startswith("origin/") and name != "origin/HEAD":
            branches[name[len("origin/"):]] = oid
else:
    errors.append("git for-each-ref failed")
# The default branch comes from GitHub. The clone's refs/remotes/origin/HEAD is a snapshot from clone time and can
# point at an old feature branch (seen on a real clone), which makes every commit on the real default branch look
# unmerged. It is only the fallback when GitHub cannot be asked.
rv = gh_json(["gh", "repo", "view", repo, "--json", "defaultBranchRef"], "gh repo view")
default = ((rv or {}).get("defaultBranchRef") or {}).get("name")
if default is None:
    h = run(["git", "-C", cwd, "symbolic-ref", "--short", "refs/remotes/origin/HEAD"])
    if h.returncode == 0 and h.stdout.strip().startswith("origin/"):
        default = h.stdout.strip()[len("origin/"):]
    else:
        default = next((d for d in ("main", "master") if d in branches), None)
if default is None:
    errors.append("could not determine the default branch")

merged_heads = {p["headRefOid"] for p in merged_prs}
stale = {b for b, oid in branches.items() if oid in merged_heads}

commit_refs = {}  # branch -> [commit message, ...] not on the default branch
if default:
    for b in branches:
        if b == default or b in stale:
            continue
        lr = run(["git", "-C", cwd, "log", "--format=%B%x1e", f"origin/{default}..origin/{b}"])
        if lr.returncode == 0:
            commit_refs[b] = [m for m in lr.stdout.split("\x1e") if m.strip()]


def reopened_after(n, when):
    r = run(["gh", "api", f"repos/{repo}/issues/{n}/events", "--paginate"])
    if r.returncode != 0:
        errors.append(f"gh api events for #{n} failed; reopen exception not applied")
        return False
    dec, s, i, times = json.JSONDecoder(), r.stdout.strip(), 0, []
    try:
        while i < len(s):
            obj, j = dec.raw_decode(s, i)
            times += [e.get("created_at", "") for e in obj if e.get("event") == "reopened"]
            i = j
            while i < len(s) and s[i].isspace():
                i += 1
    except Exception:
        return False
    return any(t > when for t in times)


out = {}
for n in issues:
    meta = gh_json(["gh", "issue", "view", str(n), "--repo", repo, "--json", "createdAt,state"], f"gh issue view {n}")
    ev, issue_errs = [], []
    if meta is None:
        out[str(n)] = {"verdict": "unknown", "reason": f"could not read issue #{n}", "evidence": []}
        continue
    created, state = meta["createdAt"], meta["state"]
    pat = precise(n)
    for p in open_prs:
        if p["createdAt"] < created or not pat.search(p.get("body") or ""):
            continue
        if declares(p["body"], n):
            ev.append({"kind": "E1", "ref": f"PR #{p['number']}", "pr": p["number"], "head": p["headRefName"],
                       "url": p.get("url"), "own": own(p["headRefName"], n)})
        else:
            ev.append({"kind": "E2", "ref": f"PR #{p['number']}", "pr": p["number"], "head": p["headRefName"], "url": p.get("url")})
    if state == "OPEN":
        for p in merged_prs:
            if p["createdAt"] >= created and declares(p.get("body"), n):
                ev.append({"kind": "E3", "ref": f"PR #{p['number']}", "pr": p["number"], "head": p["headRefName"],
                           "url": p.get("url"), "mergedAt": p.get("mergedAt"),
                           "excused": reopened_after(n, p.get("mergedAt") or "")})
    for b in sorted(branches):
        if b in stale or b == default:
            continue
        if own(b, n):
            ev.append({"kind": "E4", "ref": f"branch {b}", "branch": b})
        if any(declares(m, n, COMMIT_REFS) for m in commit_refs.get(b, [])):
            ev.append({"kind": "E6", "ref": f"commit on {b}", "branch": b})

    blocking = [e for e in ev if (e["kind"] == "E1" and not e["own"]) or (e["kind"] == "E3" and not e["excused"])]
    resume = [e for e in ev if (e["kind"] == "E1" and e["own"]) or e["kind"] == "E4"]
    if blocking:
        verdict, reason = "blocked", "; ".join(f"{e['ref']} ({e['kind']})" for e in blocking)
    elif resume:
        verdict, reason = "resume", "; ".join(f"{e['ref']} ({e['kind']})" for e in resume)
    elif errors:
        verdict, reason = "unknown", "; ".join(errors)
    else:
        verdict, reason = "clear", ""
    out[str(n)] = {"verdict": verdict, "reason": reason, "evidence": ev}

print(json.dumps({"repo": repo, "truncated": truncated, "errors": errors, "issues": out}, ensure_ascii=False))
PY
