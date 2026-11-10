#!/usr/bin/env python3
"""spec-change.py (#480) — the mechanical checks behind "every issue leaves a spec change".

Contract: capability spec-on-every-issue (openspec), design.md Implementation Contract.
Each subcommand prints one JSON line on stdout (except `declared` on an unreadable
file) and exits with a fixed code. A usage error prints to stderr and exits 64.

  declared  --file <comment>
      Read the `**Spec**:` line of an Implementation Complete comment.
      {"form": change|no-behaviour-change|third-party-clone|legacy|invalid,
       "changes": [...], "reason": "..."}   exit 0, 1 (invalid), 2 (file unreadable, no JSON)

  archived  --file <comment> --cwd <dir> --ref <rev>
      Is every declared change archived at <rev>?
      {"status": pass|refuse|error, "not_archived": [...], "reason": "..."}   exit 0, 1, 2

  links     --base <rev> [--head <rev>] [--cwd <dir>]
      Does every requirement added or changed in base..head carry an executable check?
      {"status": ok|missing|error, "missing": [{capability, requirement, example, why}],
       "reason": "..."}   exit 0, 1, 2

  preflight --cwd <dir> --can-write yes|no
      May a wrapper start writing a spec change here?
      {"status": ready|third-party|linked-worktree|install-spectra|init-openspec|error,
       "message": "..."}   exit 0 (ready, third-party), 1 (the three stops), 2 (error)

Paths named openspec/ above are relative to the spec directory Spectra uses: the `spec_dir:` line of
.spectra.yaml, or `openspec` when there is none (read at the revision checked; preflight reads the working tree).

Anything that cannot be read or decided is `error` (exit 2), never `ok` or `pass`.
"""
import json
import os
import re
import shutil
import subprocess
import sys

MARKER = "<!-- idd:comment type=implementation-complete -->"
NAME_RE = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
SPEC_LINE_RE = re.compile(r"^ {0,3}\*\*Spec\*\*:(.*)$")
FENCE_RE = re.compile(r"^ {0,3}(`{3,}|~{3,})")
ARCHIVE_DIR_RE = r"^\d{4}-\d{2}-\d{2}-%s$"
REQ_RE = re.compile(r"^### Requirement:\s*(.*?)\s*$")
EXAMPLE_RE = re.compile(r"^##### Example:(.*)$")
NO_CHECK_RE = re.compile(r"^\s*No executable check:(.*)$")
INSTALL_HINT = ("install the Spectra CLI (see https://github.com/spectra-app/spectra) and run the wrapper again; "
                "the spec change is not optional in a repository you can write to")


class Usage(Exception):
    pass


class Fail(Exception):
    """Something could not be read or decided: the subcommand answers error (exit 2)."""


def emit(obj, code):
    print(json.dumps(obj, ensure_ascii=False))
    return code


def parse(argv, allowed, required):
    out, i = {}, 0
    while i < len(argv):
        flag = argv[i]
        if flag not in allowed or flag in out or i + 1 >= len(argv) or argv[i + 1] == "":
            raise Usage(f"unexpected or incomplete argument: {flag}")
        out[flag] = argv[i + 1]
        i += 2
    missing = [f for f in required if f not in out]
    if missing:
        raise Usage("missing " + ", ".join(missing))
    for flag in ("--ref", "--base", "--head"):
        if out.get(flag, "").startswith("-"):
            raise Usage(f"{flag} must name a revision, not an option: {out[flag][:40]!r}")
    return out


def git(cwd, *args, check=True):
    p = subprocess.run(["git", "-C", cwd, *args], capture_output=True)
    if check and p.returncode != 0:
        raise Fail(f"git {' '.join(args[:2])} failed: {p.stderr.decode('utf-8', 'replace').strip()[:200]}")
    return p


def git_text(cwd, *args):
    return git(cwd, *args).stdout.decode("utf-8")


def repo_top(cwd):
    if not os.path.isdir(cwd):
        raise Fail(f"{cwd} is not a directory")
    p = git(cwd, "rev-parse", "--show-toplevel", check=False)
    if p.returncode != 0:
        raise Fail(f"{cwd} is not inside a git repository")
    return p.stdout.decode("utf-8").strip()


SPEC_DIR_RE = re.compile(r"^spec_dir:(.*)$")


def spec_dir_of(text):
    """The spec directory named by .spectra.yaml text (None = no file): Spectra's own rule."""
    if text is None:
        return "openspec"
    values = [m.group(1) for m in (SPEC_DIR_RE.match(l) for l in text.splitlines()) if m]
    if not values:
        return "openspec"
    value = values[-1].split(" #", 1)[0].strip().strip('"').strip("'").strip()
    parts = value.replace("\\", "/").split("/")
    if not value or value.startswith("/") or ".." in parts or re.match(r"^[A-Za-z]:", value):
        raise Fail(f".spectra.yaml spec_dir {value!r} must be a relative path inside the repository")
    return "/".join(p for p in parts if p not in ("", "."))


def spec_dir_at(top, rev):
    p = git(top, "show", f"{rev}:.spectra.yaml", check=False)
    if p.returncode != 0:
        return spec_dir_of(None)
    return spec_dir_of(p.stdout.decode("utf-8", "replace"))


def spec_dir_worktree(top):
    path = os.path.join(top, ".spectra.yaml")
    if not os.path.isfile(path):
        return spec_dir_of(None)
    with open(path, encoding="utf-8", errors="replace") as fh:
        return spec_dir_of(fh.read())


def resolve(cwd, rev):
    p = git(cwd, "rev-parse", "--verify", "--quiet", f"{rev}^{{commit}}", check=False)
    if p.returncode != 0:
        raise Fail(f"revision {rev!r} does not exist")
    return p.stdout.decode("utf-8").strip()


# ── declared ────────────────────────────────────────────────────────────────

def declared_of(text):
    """(form, changes, reason) for the text of an Implementation Complete comment."""
    has_marker, specs, fence = False, [], None
    for line in text.splitlines():
        m = FENCE_RE.match(line)
        if m:
            tick = m.group(1)[0]
            if fence is None:
                fence = tick
            elif fence == tick:
                fence = None
            continue
        if fence is not None:
            continue
        if MARKER in line:
            has_marker = True
        s = SPEC_LINE_RE.match(line)
        if s:
            specs.append(s.group(1).strip())
    if not specs:
        if has_marker:
            return "invalid", [], "the comment carries the marker but no **Spec**: line outside a code block"
        return "legacy", [], "no marker and no **Spec**: line: posted before this check existed"
    if len(specs) > 1:
        return "invalid", [], f"{len(specs)} **Spec**: lines; there must be exactly one"
    value = specs[0]
    if value == "no behaviour change":
        return "no-behaviour-change", [], ""
    if value == "third-party clone":
        return "third-party-clone", [], ""
    if value == "change" or value.startswith("change "):
        names = [n.strip() for n in value[len("change"):].split(",")]
        if not names or any(not n for n in names):
            return "invalid", [], "`change` needs one or more change names separated by commas"
        bad = [n for n in names if not NAME_RE.match(n)]
        if bad:
            return "invalid", [], f"not a change name (lower-case letters, digits, hyphens): {bad[0][:60]!r}"
        if len(set(names)) != len(names):
            return "invalid", [], "a change name is listed twice"
        return "change", names, ""
    return "invalid", [], f"unknown form {value[:60]!r}; expected `change <name>`, `no behaviour change` or `third-party clone`"


def read_comment(path):
    try:
        with open(path, encoding="utf-8") as fh:
            return fh.read()
    except (OSError, UnicodeDecodeError) as exc:
        raise Fail(f"cannot read {path}: {exc.__class__.__name__}")


def cmd_declared(argv):
    a = parse(argv, {"--file"}, ["--file"])
    try:
        text = read_comment(a["--file"])
    except Fail as exc:
        print(f"spec-change: {exc}", file=sys.stderr)
        return 2
    form, changes, reason = declared_of(text)
    return emit({"form": form, "changes": changes, "reason": reason}, 1 if form == "invalid" else 0)


# ── archived ────────────────────────────────────────────────────────────────

def cmd_archived(argv):
    a = parse(argv, {"--file", "--cwd", "--ref"}, ["--file", "--cwd", "--ref"])
    try:
        form, changes, reason = declared_of(read_comment(a["--file"]))
        if form == "invalid":
            return emit({"status": "refuse", "not_archived": [], "reason": "the **Spec**: line is invalid: " + reason}, 1)
        if form != "change":
            return emit({"status": "pass", "not_archived": [], "reason": f"form {form}: nothing to archive"}, 0)
        top = repo_top(a["--cwd"])
        rev = resolve(top, a["--ref"])
        sd = spec_dir_at(top, rev)
        listing = git_text(top, "ls-tree", "-d", "--name-only", rev, f"{sd}/changes/", f"{sd}/changes/archive/")
        dirs = set(listing.splitlines())
        archived = [d.rsplit("/", 1)[1] for d in dirs if d.startswith(f"{sd}/changes/archive/")]
        not_archived, why = [], []
        for name in changes:
            open_dir = f"{sd}/changes/{name}" in dirs
            hits = [d for d in archived if re.match(ARCHIVE_DIR_RE % re.escape(name), d)]
            if open_dir or len(hits) != 1:
                not_archived.append(name)
                why.append(f"{name}: " + (f"still under {sd}/changes/" if open_dir else
                                          "no archive directory" if not hits else f"{len(hits)} archive directories"))
        if not_archived:
            return emit({"status": "refuse", "not_archived": not_archived,
                         "reason": f"not archived at {rev[:12]}: " + "; ".join(why)}, 1)
        return emit({"status": "pass", "not_archived": [], "reason": f"archived at {rev[:12]}"}, 0)
    except Fail as exc:
        return emit({"status": "error", "not_archived": [], "reason": str(exc)}, 2)


# ── links ───────────────────────────────────────────────────────────────────

def spec_files(top, rev, sd):
    out = git_text(top, "ls-tree", "-r", "--name-only", rev, "--", f"{sd}/specs/")
    return [p for p in out.splitlines() if re.match(r"^%s/specs/[^/]+/spec\.md$" % re.escape(sd), p)]


def read_at(top, rev, path):
    raw = git(top, "show", f"{rev}:{path}").stdout
    try:
        return raw.decode("utf-8")
    except UnicodeDecodeError:
        raise Fail(f"{path} at {rev[:12]} is not UTF-8 text")


THEMATIC_RE = re.compile(r"^ {0,3}([-*_])(?:[ \t]*\1){2,}[ \t]*$")


def block_text(lines):
    """A requirement block without the blank lines and separators (---, ***, ___) at its end.

    Spectra's archive appends a requirement to an existing spec as "\\n\\n---\\n### Requirement: …".
    Those lines belong between blocks, not to the block before them; counting them made an untouched
    requirement read as changed (found on this repository's own idd-verify spec, #480).
    """
    lines = list(lines)
    while lines and (not lines[-1].strip() or THEMATIC_RE.match(lines[-1])):
        lines.pop()
    return "\n".join(lines).strip()


def requirements(text):
    """{name: block text} for the `### Requirement:` blocks of a spec (outside code fences)."""
    reqs, name, buf, fence = {}, None, [], None
    for line in text.splitlines():
        m = FENCE_RE.match(line)
        if m:
            tick = m.group(1)[0]
            fence = tick if fence is None else (None if fence == tick else fence)
        if fence is None and not m:
            r = REQ_RE.match(line)
            if r or re.match(r"^#{1,3} ", line):
                if name is not None:
                    reqs[name] = block_text(buf)
                name, buf = (r.group(1), [line]) if r else (None, [])
                continue
        if name is not None:
            buf.append(line)
    if name is not None:
        reqs[name] = block_text(buf)
    return reqs


def examples(block):
    return [m.group(1).strip() for m in (EXAMPLE_RE.match(l) for l in block.splitlines()) if m]


def marker_files(top, head, needle, sd):
    """Tracked files at head, outside the spec directory and not .md, whose text contains needle."""
    p = git(top, "grep", "-l", "-F", "-e", needle, head, "--", ".", check=False)
    if p.returncode not in (0, 1):
        raise Fail("git grep failed: " + p.stderr.decode("utf-8", "replace").strip()[:200])
    files = []
    for line in p.stdout.decode("utf-8", "replace").splitlines():
        path = line.split(":", 1)[1] if line.startswith(head + ":") else line
        if path.startswith(sd + "/") or path.lower().endswith(".md"):
            continue
        files.append(path)
    return files


def cmd_links(argv):
    a = parse(argv, {"--base", "--head", "--cwd"}, ["--base"])
    try:
        top = repo_top(a.get("--cwd", "."))
        base = resolve(top, a["--base"])
        head = resolve(top, a.get("--head", "HEAD"))
        sd, sd_base = spec_dir_at(top, head), spec_dir_at(top, base)
        base_files = {p[len(sd_base):]: p for p in spec_files(top, base, sd_base)}
        head_files = spec_files(top, head, sd)
        missing = []
        for path in head_files:
            cap = path[len(sd) + len("/specs/"):].split("/")[0]
            new = requirements(read_at(top, head, path))
            rel = path[len(sd):]
            old = requirements(read_at(top, base, base_files[rel])) if rel in base_files else {}
            titles = [t for block in new.values() for t in examples(block)]
            for name, block in new.items():
                if old.get(name) == block:
                    continue
                exs = examples(block)
                if not exs:
                    reasons = [m.group(1).strip() for m in (NO_CHECK_RE.match(l) for l in block.splitlines()) if m]
                    if not any(reasons):
                        missing.append({"capability": cap, "requirement": name, "example": "",
                                        "why": "no Example and no `No executable check:` line with a reason"})
                    continue
                for title in exs:
                    if not title:
                        missing.append({"capability": cap, "requirement": name, "example": "",
                                        "why": "an Example has no title"})
                    elif titles.count(title) > 1:
                        missing.append({"capability": cap, "requirement": name, "example": title,
                                        "why": "the Example title is used more than once in this capability"})
                    elif not marker_files(top, head, f"spec-example: {cap} / {title}", sd):
                        missing.append({"capability": cap, "requirement": name, "example": title,
                                        "why": f"no tracked file outside {sd}/ (and not .md) carries its marker"})
        if missing:
            return emit({"status": "missing", "missing": missing, "reason": f"{len(missing)} item(s) without a check"}, 1)
        return emit({"status": "ok", "missing": [], "reason": ""}, 0)
    except Fail as exc:
        return emit({"status": "error", "missing": [], "reason": str(exc)}, 2)


# ── preflight ───────────────────────────────────────────────────────────────

def cmd_preflight(argv):
    a = parse(argv, {"--cwd", "--can-write"}, ["--cwd", "--can-write"])
    if a["--can-write"] not in ("yes", "no"):
        raise Usage("--can-write must be yes or no")
    try:
        top = repo_top(a["--cwd"])
        if a["--can-write"] == "no":
            return emit({"status": "third-party", "message": "the account cannot write to this repository: "
                         "implement without a spec change and declare `**Spec**: third-party clone`"}, 0)
        gd = git_text(top, "rev-parse", "--path-format=absolute", "--git-dir").strip()
        cd = git_text(top, "rev-parse", "--path-format=absolute", "--git-common-dir").strip()
        if os.path.realpath(gd) != os.path.realpath(cd):
            return emit({"status": "linked-worktree", "message": "this is a git linked worktree; spectra writes into "
                         "the main working tree from here. Run in the main tree or a standalone clone"}, 1)
        if shutil.which("spectra") is None:
            return emit({"status": "install-spectra", "message": INSTALL_HINT}, 1)
        sd = spec_dir_worktree(top)
        if not os.path.isdir(os.path.join(top, sd)):
            return emit({"status": "init-openspec", "message": f"this repository has no {sd}/ directory: "
                         "run `spectra init` at its top level, commit it, and run the wrapper again"}, 1)
        return emit({"status": "ready", "message": ""}, 0)
    except Fail as exc:
        return emit({"status": "error", "message": str(exc)}, 2)


def main(argv):
    handlers = {"declared": cmd_declared, "archived": cmd_archived, "links": cmd_links, "preflight": cmd_preflight}
    if not argv or argv[0] not in handlers:
        print("spec-change: subcommand required: declared | archived | links | preflight", file=sys.stderr)
        return 64
    try:
        return handlers[argv[0]](argv[1:])
    except Usage as exc:
        print(f"spec-change {argv[0]}: {exc}", file=sys.stderr)
        return 64


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
