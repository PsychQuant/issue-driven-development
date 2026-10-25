#!/usr/bin/env python3
"""gh_egress_rest.py — the REST transport behind scripts/gh-egress.sh (#416, change cloud-session-idd-all D2).

ONLY gh-egress.sh calls this, after every gate (attestation, privacy / mention / tier-floor nets,
empty-body guard) has passed. Calling it directly skips those gates — don't.

It turns the `gh issue create|comment|edit` arguments the wrapper forwards into `gh api` REST calls.
Porcelain `gh issue …` is GraphQL underneath, which Claude Code cloud sessions block; REST works
everywhere, so this is the transport in every environment (one path, no environment branch).

  create   gh api repos/R/issues -X POST --input - --jq .html_url            stdin {"title",…}
  comment  gh api repos/R/issues/N/comments -X POST --input - --jq .html_url stdin {"body"}
  edit     label / assignee add & remove calls (--silent), then
           gh api repos/R/issues/N -X PATCH --input - --jq .html_url         stdin {"title","body","milestone"}
           (no PATCH fields → gh api repos/R/issues/N --jq .html_url, to print the URL)

Stdout on success: one URL line (issue URL for create / edit, comment URL for comment).
Exit: 14 for anything this translator refuses (unsupported flag, missing title or issue, extra
positional, unknown milestone, both --body and --body-file); 12 when the body file is not UTF-8;
otherwise the exit code of the gh call that failed (gh's codes are < 10 — the #227 band split).
The body always reaches gh through stdin (an unlinked temp file), never through argv.
"""
import json
import os
import subprocess
import sys
import tempfile
import urllib.parse

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gh_rest  # noqa: E402  (shared REST helpers; same directory)

VALUE_FLAGS = {
    "create": {"--repo": "repo", "-R": "repo", "--title": "title", "-t": "title", "--body": "body", "-b": "body",
               "--body-file": "body_file", "-F": "body_file", "--label": "label", "-l": "label",
               "--assignee": "assignee", "-a": "assignee", "--milestone": "milestone", "-m": "milestone"},
    "comment": {"--repo": "repo", "-R": "repo", "--body": "body", "-b": "body", "--body-file": "body_file",
                "-F": "body_file"},
    "edit": {"--repo": "repo", "-R": "repo", "--title": "title", "-t": "title", "--body": "body", "-b": "body",
             "--body-file": "body_file", "-F": "body_file", "--add-label": "add_label",
             "--remove-label": "remove_label", "--add-assignee": "add_assignee",
             "--remove-assignee": "remove_assignee", "--milestone": "milestone", "-m": "milestone"},
}
BOOL_FLAGS = {"edit": {"--remove-milestone": "remove_milestone"}}
LIST_KEYS = {"label", "assignee", "add_label", "remove_label", "add_assignee", "remove_assignee"}


class Refuse(Exception):
    def __init__(self, message, code=14):
        super().__init__(message)
        self.code = code


def parse(verb, args):
    """Return (opts, positionals). Lists are comma-split like gh; scalars keep the last value."""
    values, bools = VALUE_FLAGS[verb], BOOL_FLAGS.get(verb, {})
    opts, pos, i = {}, [], 0

    def put(key, value):
        if key in LIST_KEYS:
            opts.setdefault(key, []).extend(v.strip() for v in value.split(",") if v.strip())
        else:
            opts[key] = value

    while i < len(args):
        tok = args[i]
        if tok in bools:
            opts[bools[tok]] = True
        elif tok in values:
            if i + 1 >= len(args):
                raise Refuse(f"{tok} needs a value")
            put(values[tok], args[i + 1])
            i += 1
        elif tok.startswith("--") and "=" in tok and tok.split("=", 1)[0] in values:
            flag, value = tok.split("=", 1)
            put(values[flag], value)
        elif tok.startswith("-") and not tok.startswith("--") and len(tok) > 2 and tok[:2] in values:
            put(values[tok[:2]], tok[2:])
        elif tok.startswith("-") and tok != "-":
            raise Refuse(f"'{tok.split('=', 1)[0]}' is not supported by the REST transport for `{verb}` "
                         f"(supported: {', '.join(sorted(set(values) | set(bools)))})")
        else:
            pos.append(tok)
        i += 1
    return opts, pos


def body_of(opts):
    if "body" in opts and "body_file" in opts:
        raise Refuse("pass only one of --body or --body-file")
    if "body_file" in opts:
        try:
            with open(opts["body_file"], encoding="utf-8") as f:
                return f.read()
        except UnicodeDecodeError:
            raise Refuse(f"body file {opts['body_file']} is not UTF-8 text", code=12)
        except OSError as exc:
            raise Refuse(f"body file {opts['body_file']} could not be read: {exc}", code=12)
    return opts.get("body")


def host_args(host):
    return ["--hostname", host] if host else []


def run(args, payload=None, quiet=False):
    """Run gh with payload on stdin (unlinked temp file). Stdout/stderr pass through unless quiet."""
    stdin = None
    try:
        if payload is not None:
            stdin = tempfile.TemporaryFile(mode="w+", encoding="utf-8")
            json.dump(payload, stdin, ensure_ascii=False)
            stdin.seek(0)
        r = subprocess.run([gh_rest.gh_bin()] + args, stdin=stdin if stdin else subprocess.DEVNULL,
                           stdout=subprocess.DEVNULL if quiet else None)
        return r.returncode
    except OSError as exc:
        print(f"✗ gh-egress: could not run gh: {exc}", file=sys.stderr)
        return 1
    finally:
        if stdin:
            stdin.close()


def lookup_milestone(title, host, repo):
    items = gh_rest.pages(f"repos/{repo}/milestones", "state=all", host, "milestone lookup", repo)
    for m in items:
        if isinstance(m, dict) and m.get("title") == title:
            return m.get("number")
    raise Refuse(f"milestone '{title}' does not exist in {gh_rest.subject(repo)} (exact title match)")


def resolve_assignees(names, host, cache):
    out = []
    for n in names:
        if n == "@me":
            if "me" not in cache:
                user = gh_rest.api("user", host, "assignee lookup (@me)", "the current user")
                cache["me"] = user.get("login") if isinstance(user, dict) else None
                if not cache["me"]:
                    raise gh_rest.GhError("assignee lookup (@me) returned no login")
            out.append(cache["me"])
        else:
            out.append(n)
    return out


def issue_target(pos, opts, verb):
    if len(pos) != 1:
        raise Refuse(f"`{verb}` needs exactly one issue (number or URL); got {len(pos)}: {' '.join(pos) or '(none)'}")
    try:
        return gh_rest.parse_issue_ref(pos[0], opts.get("repo"))
    except gh_rest.UsageError as exc:
        raise Refuse(str(exc))


def create(opts, pos):
    if pos:
        raise Refuse(f"`create` takes no positional arguments; got: {' '.join(pos)}")
    if not opts.get("title"):
        raise Refuse("`create` needs --title (the REST API requires a title)")
    try:
        host, repo = gh_rest.split_repo(opts.get("repo"))
    except gh_rest.UsageError as exc:
        raise Refuse(str(exc))
    payload = {"title": opts["title"]}
    body = body_of(opts)
    if body is not None:
        payload["body"] = body
    if opts.get("label"):
        payload["labels"] = opts["label"]
    if opts.get("assignee"):
        payload["assignees"] = resolve_assignees(opts["assignee"], host, {})
    if opts.get("milestone"):
        payload["milestone"] = lookup_milestone(opts["milestone"], host, repo)
    return run(["api", f"repos/{repo}/issues", "-X", "POST", "--input", "-", "--jq", ".html_url"] + host_args(host),
               payload)


def comment(opts, pos):
    host, repo, n = issue_target(pos, opts, "comment")
    body = body_of(opts)
    if body is None:
        raise Refuse("`comment` needs --body or --body-file")
    return run(["api", f"repos/{repo}/issues/{n}/comments", "-X", "POST", "--input", "-", "--jq", ".html_url"]
               + host_args(host), {"body": body})


def edit(opts, pos):
    host, repo, n = issue_target(pos, opts, "edit")
    if opts.get("milestone") and opts.get("remove_milestone"):
        raise Refuse("pass only one of --milestone or --remove-milestone")
    patch = {}
    if "title" in opts:
        patch["title"] = opts["title"]
    body = body_of(opts)
    if body is not None:
        patch["body"] = body
    if opts.get("milestone"):
        patch["milestone"] = lookup_milestone(opts["milestone"], host, repo)
    if opts.get("remove_milestone"):
        patch["milestone"] = None
    cache = {}
    add_assignees = resolve_assignees(opts.get("add_assignee", []), host, cache)
    remove_assignees = resolve_assignees(opts.get("remove_assignee", []), host, cache)
    base, h = f"repos/{repo}/issues/{n}", host_args(host)
    steps = []
    if opts.get("add_label"):
        steps.append((["api", f"{base}/labels", "-X", "POST", "--input", "-", "--silent"] + h,
                      {"labels": opts["add_label"]}))
    for name in opts.get("remove_label", []):
        steps.append((["api", f"{base}/labels/{urllib.parse.quote(name, safe='')}", "-X", "DELETE", "--silent"] + h,
                      None))
    if add_assignees:
        steps.append((["api", f"{base}/assignees", "-X", "POST", "--input", "-", "--silent"] + h,
                      {"assignees": add_assignees}))
    if remove_assignees:
        steps.append((["api", f"{base}/assignees", "-X", "DELETE", "--input", "-", "--silent"] + h,
                      {"assignees": remove_assignees}))
    for args, payload in steps:
        rc = run(args, payload, quiet=True)
        if rc != 0:
            return rc
    if patch:
        return run(["api", base, "-X", "PATCH", "--input", "-", "--jq", ".html_url"] + h, patch)
    return run(["api", base, "--jq", ".html_url"] + h)


def main(argv):
    if not argv or argv[0] not in VALUE_FLAGS:
        print("✗ gh-egress: REST transport needs a verb: create | comment | edit", file=sys.stderr)
        return 14
    verb, args = argv[0], argv[1:]
    try:
        opts, pos = parse(verb, args)
        return {"create": create, "comment": comment, "edit": edit}[verb](opts, pos)
    except Refuse as exc:
        print(f"✗ gh-egress: REFUSED — {exc}", file=sys.stderr)
        return exc.code
    except gh_rest.GhError as exc:
        print(f"✗ gh-egress: {exc}", file=sys.stderr)
        if exc.hint:
            print(exc.hint, file=sys.stderr)
        return exc.exit_code if 0 < exc.exit_code < 10 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
