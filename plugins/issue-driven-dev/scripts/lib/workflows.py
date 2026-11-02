"""workflows.py — does a merge or push to the default branch run a workflow that publishes? (#392)

The close stage merges without a person only when the merge is reversible. A
workflow that publishes (a release, a package, a deploy) when the default
branch moves makes the merge itself a release, so the stage stops.

Reading GitHub Actions triggers here is a heuristic, so every unknown answers
"yes, it runs on a push to the default branch" (fail closed, #392 verify r5):
an `on:` this reader cannot follow, quoted keys it does not recognise, inline
mappings, negated or bracketed branch patterns, a reusable workflow in another
repository. Standard library only (PyYAML is not guaranteed).
"""

import re

# Text that publishes when found in a workflow, in a local reusable workflow or
# composite action it calls, or in a local script one of its `run:` steps calls.
RELEASE_RE = re.compile(
    r"gh release|action-gh-release|create-release|npm publish|semantic-release|goreleaser|pypi-publish|"
    r"twine upload|cargo publish|docker push|vsce publish|release-please|changesets/action|deploy-pages|"
    r"vercel|netlify|wrangler|firebase deploy|kubectl apply|aws s3 sync|gh-pages|"
    r"\bpublish\b|\bdeploy\b|\brelease\.(?:sh|py|js|mjs|ts|rb)\b",
    re.IGNORECASE,
)
REMOTE_WORKFLOW_RE = re.compile(r"uses:\s*[\"']?([\w.-]+/[\w.-]+/\.github/workflows/[^\s@\"']+)@")
LOCAL_USES_RE = re.compile(r"uses:\s*[\"']?\./([^\s@\"']+)")
LOCAL_SCRIPT_RE = re.compile(r"(?:^|[\s;&|(])(?:bash\s+|sh\s+|python3?\s+|node\s+)?\.?/?((?:scripts|bin|tools|\.github)/[\w./-]+)")
KEY_RE = re.compile(r"""^(["']?)([A-Za-z_][\w-]*)\1\s*:\s*(.*?)\s*(?:#.*)?$""")
ITEM_RE = re.compile(r"""^-\s*(["']?)([^"'#]*?)\1\s*(?:#.*)?$""")


def _indent(line):
    return len(line) - len(line.lstrip(" "))


def _children(lines, start, parent_indent):
    """The lines indented deeper than parent_indent that follow `start` (blank and comment lines skipped)."""
    out = []
    for line in lines[start:]:
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if "\t" in line[:_indent(line) + 1]:
            return None
        if _indent(line) <= parent_indent:
            break
        out.append(line)
    return out


def _entries(lines):
    """Parse one mapping or list level: {key: (inline_value, child_lines)} or a list of items; None when unsure."""
    if not lines:
        return {}
    level = _indent(lines[0])
    mapping, items, i = {}, [], 0
    while i < len(lines):
        line = lines[i]
        ind = _indent(line)
        if ind < level:
            return None
        if ind > level:
            i += 1
            continue
        text = line.strip()
        item = ITEM_RE.match(text)
        if item and not text.startswith("- {") and not text.startswith("- ["):
            items.append(item.group(2).strip())
            i += 1
            continue
        key = KEY_RE.match(text)
        if not key:
            return None
        kids = _children(lines, i + 1, ind)
        if kids is None:
            return None
        mapping[key.group(2)] = (key.group(3), kids)
        i += 1 + len(kids)
    if mapping and items:
        return None
    return items if items else mapping


def _flow_list(value):
    value = value.strip()
    if not (value.startswith("[") and value.endswith("]")):
        return None
    return [x.strip().strip("\"'") for x in value[1:-1].split(",") if x.strip()]


def on_events(text):
    """{event: filter-lines or None} from the workflow's `on:`; None when it cannot be read."""
    lines = (text or "").splitlines()
    for i, line in enumerate(lines):
        m = re.match(r"""^(["']?)on\1\s*:\s*(.*?)\s*(?:#.*)?$""", line)
        if not m:
            continue
        rest = m.group(2)
        if rest:
            listed = _flow_list(rest)
            if listed is not None:
                return {e: [] for e in listed}
            if re.match(r"""^["']?[A-Za-z_]+["']?$""", rest):
                return {rest.strip("\"'"): []}
            return None   # inline mapping, anchors, block scalars: not followed
        kids = _children(lines, i + 1, 0)
        level = _entries(kids) if kids is not None else None
        if level is None:
            return None
        if isinstance(level, list):
            return {e: [] for e in level}
        out = {}
        for event, (inline, child) in level.items():
            if inline and inline not in ("null", "~", "{}"):
                out[event] = None   # inline filters: not followed
            else:
                out[event] = child
        return out
    return None


def _filters(block):
    """{filter: [patterns] or None} for one event's block; None when unsure."""
    level = _entries(block) if block else {}
    if level is None or isinstance(level, list):
        return None
    out = {}
    for key, (inline, child) in level.items():
        if inline:
            out[key] = _flow_list(inline)
        else:
            items = _entries(child)
            out[key] = items if isinstance(items, list) else None
    return out


def _matches(pattern, name):
    """GitHub filter glob: `*` stays within one path segment, `**` crosses them. None when the pattern is not followed."""
    if pattern is None or re.search(r"[?+\[\]!]", pattern):
        return None
    rx = re.escape(pattern).replace(r"\*\*", "\0").replace(r"\*", "[^/]*").replace("\0", ".*")
    return re.fullmatch(rx, name) is not None


def runs_on_default_push(text, default):
    """True when a push to `default` runs this workflow (or when that cannot be ruled out)."""
    events = on_events(text)
    if events is None:
        return True
    if "workflow_run" in events:
        return True
    if "push" not in events:
        return False
    block = events["push"]
    if block is None:
        return True
    f = _filters(block)
    if f is None:
        return True
    if "branches" in f:
        pats = f["branches"]
        if pats is None:
            return True
        hits = [_matches(p, default) for p in pats]
        return None in hits or any(hits)
    if "branches-ignore" in f:
        pats = f["branches-ignore"]
        if pats is None:
            return True
        hits = [_matches(p, default) for p in pats]
        return None in hits or not any(hits)
    if "tags" in f or "tags-ignore" in f:
        return False    # a push filtered to tags only does not run for branch pushes
    return True


def runs_on_every_pr(text, default):
    """True when every pull_request into `default` runs this workflow, so a check must appear."""
    events = on_events(text)
    if events is None:
        return True
    for event in ("pull_request", "pull_request_target"):
        if event not in events:
            continue
        block = events[event]
        if block is None:
            return True
        f = _filters(block)
        if f is None:
            return True
        if "paths" in f or "paths-ignore" in f:
            continue
        if "types" in f and f["types"] is not None and not set(f["types"]) & {"opened", "synchronize", "reopened"}:
            continue
        if "branches" in f:
            pats = f["branches"] or []
            if not any(_matches(p, default) is not False for p in pats):
                continue
        if "branches-ignore" in f and f["branches-ignore"] and any(_matches(p, default) for p in f["branches-ignore"]):
            continue
        return True
    return False


def publishing(files, read, default):
    """Workflows that publish on a push to `default`, each with why.

    files: [(path, text)] of .github/workflows; read(path) returns a file's text
    at the same commit, or None when it does not exist.
    """
    by_path = dict(files)
    hits = []
    for path, text in files:
        if not runs_on_default_push(text, default):
            continue
        remote = REMOTE_WORKFLOW_RE.findall(text)
        if remote:
            hits.append(f"{path} (calls {remote[0]}, a workflow in another repository)")
            continue
        texts = [text]
        for local in LOCAL_USES_RE.findall(text):
            local = local.rstrip("/")
            if local in by_path:
                texts.append(by_path[local])
            else:
                for name in ("action.yml", "action.yaml"):
                    body = read(f"{local}/{name}")
                    if body is not None:
                        texts.append(body)
        for script in set(LOCAL_SCRIPT_RE.findall(text)):
            body = read(script.rstrip("/"))
            if body is not None:
                texts.append(body)
        m = next((RELEASE_RE.search(t) for t in texts if RELEASE_RE.search(t)), None)
        if m:
            hits.append(f"{path} ({m.group(0)})")
    return hits
