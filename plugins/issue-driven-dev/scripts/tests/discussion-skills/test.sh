#!/usr/bin/env bash
# #331: skill/document interface contracts + one real offline draft smoke.
# These checks do NOT establish semantic consent, answer fidelity, publication
# idempotency, or API paging correctness; publisher/reader suites test I/O.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HERE/../../.." && pwd)"
python3 - "$PLUGIN_ROOT" "$HERE" <<'PY'
import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import sys
import tempfile

try:
    import yaml
except ImportError:
    raise SystemExit("discussion-skills needs PyYAML for actual YAML parsing; install PyYAML before running")

root, here = map(Path, sys.argv[1:])
checks = 0

def check(ok, message):
    global checks
    if not ok:
        raise AssertionError(message)
    checks += 1
    print(f"PASS {message}")

sources = {}
for name in ("idd-discuss", "idd-ask"):
    path = root / "skills" / name / "SKILL.md"
    text = path.read_text()
    parts = text.split("---", 2)
    check(len(parts) == 3 and not parts[0].strip(), f"{name}: delimited frontmatter")
    meta = yaml.safe_load(parts[1])
    check(isinstance(meta, dict) and meta.get("name") == name, f"{name}: parsed skill name")
    check(isinstance(meta.get("description"), str) and bool(meta["description"].strip()), f"{name}: parsed description")
    check(isinstance(meta.get("argument-hint"), str), f"{name}: parsed argument hint")
    allowed = meta.get("allowed-tools")
    check(isinstance(allowed, list) and all(isinstance(x, str) for x in allowed), f"{name}: parsed tool list")
    check({"Read", "TaskCreate", "TaskUpdate"} <= set(allowed), f"{name}: canonical runtime task tools")
    check("Bash(python3:*)" in allowed, f"{name}: documented Python CLI allowed")
    sources[name] = text

reference = root / "references" / "discussion-capture.md"
sources["reference"] = reference.read_text()
for key, text in sources.items():
    path = reference if key == "reference" else root / "skills" / key / "SKILL.md"
    links = re.findall(r"\[[^\]]+\]\(([^)]+)\)", text)
    local = [link.split("#", 1)[0] for link in links if not link.startswith("https:")]
    check(all((path.parent / link).is_file() for link in local if link), f"{key}: local references resolve")

# Normative-document drift checks, explicitly not operational tests.
contracts = {
    "idd-discuss": ["topic_id", "source_id", "role=user", "AskUserQuestion", "--publish", "完整 title/body", "只新增 comment", "盲目重送"],
    "idd-ask": ["--corpus issues|discussions|all", "預設 all", "上限 10", "kind + URL", "`idd-find` 的 search backend", "complete,warnings", "不自動代表正確", "不可信資料", "Referenced Sources"],
    "reference": ["unknown", "user_message_id", "source_scope", "state namespace", "uncertain", "exactly-once", "--mention-attested", "gh-egress.sh check", "不能指揮工具動作"],
}
for name, requirements in contracts.items():
    for requirement in requirements:
        check(requirement in sources[name], f"{name}: contract {requirement}")

# Parse the actual JSON shown to skill consumers and validate provenance links.
examples = re.findall(r"```json\n(.*?)\n```", sources["reference"], re.S)
check(bool(examples), "reference: JSON example exists")
for raw in examples + [(here / "fixtures" / "visible-messages.json").read_text()]:
    payload = json.loads(raw)
    required = {"topic_id", "source_id", "title", "summary", "source_scope", "messages"}
    check(required <= payload.keys(), "example: required payload fields")
    check(all(isinstance(payload[k], str) and payload[k] for k in required - {"messages"}), "example: nonempty scalar fields")
    messages = payload["messages"]
    check(isinstance(messages, list) and bool(messages), "example: selected messages exist")
    by_id = {m["id"]: m for m in messages}
    check(len(by_id) == len(messages), "example: message IDs unique")
    check(all(m["role"] in {"user", "assistant", "tool"} and isinstance(m["text"], str) for m in messages), "example: role and original text")
    check(all(by_id[d["user_message_id"]]["role"] == "user" for d in payload.get("decisions", [])), "example: decisions cite a user message (syntax only)")

# Invoke real argparse help. This catches documentation flags that the CLI
# cannot accept without requiring network or parsing implementation source.
for script, subcommand, expected in (
    ("idd-discuss.py", [], {"--repo", "--payload-file", "--state-dir", "--discussion", "--category-id", "--publish", "--scrub-attested", "--mention-attested"}),
    ("idd-discussions-read.py", ["search"], {"--repo", "--query", "--limit"}),
    ("idd-discussions-read.py", ["get"], {"--repo", "--number", "--max-comments"}),
    ("idd-discussions-read.py", ["list"], {"--repo", "--max-items"}),
    ("idd-discussions-read.py", ["repo"], {"--repo"}),
):
    result = subprocess.run([sys.executable, str(root / "scripts" / script), *subcommand, "--help"], text=True, capture_output=True)
    check(result.returncode == 0, f"{script} {' '.join(subcommand)}: help runs: {result.stderr}")
    flags = set(re.findall(r"--[a-z][a-z-]*", result.stdout))
    check(expected <= flags, f"{script} {' '.join(subcommand)}: documented flags accepted")

# Also parse reference Bash examples rather than silently leaving broken shell.
commands = re.findall(r"```bash\n(.*?)\n```", sources["reference"], re.S)
for block in commands:
    syntax = subprocess.run(["bash", "-n"], input=block, text=True, capture_output=True)
    check(syntax.returncode == 0, "reference: Bash example syntax")
    logical = block.replace("\\\n", " ")
    for line in logical.splitlines():
        if line.startswith("python3 "):
            args = shlex.split(line)
            check("--repo" in args, "reference: command scopes repository")
            if "idd-discuss.py" in args[1]:
                check({"--state-dir", "--payload-file"} <= set(args), "reference: publisher command scopes payload and state")
                check(("--publish" in args) == ("--scrub-attested" in args), "reference: publishing example carries gate attestation")

# Actual default CLI execution with gh sentinel proves this fixture stays local.
with tempfile.TemporaryDirectory(prefix="idd-discussion-skills-") as tmp:
    temp = Path(tmp)
    sentinel = temp / "gh-called"
    gh = temp / "gh"
    gh.write_text('#!/bin/sh\nprintf called > "$IDD_TEST_GH_CALLED"\nexit 98\n')
    gh.chmod(0o755)
    env = dict(os.environ, PATH=f"{temp}{os.pathsep}{os.environ.get('PATH', '')}", IDD_TEST_GH_CALLED=str(sentinel))
    draft = subprocess.run([
        sys.executable, str(root / "scripts" / "idd-discuss.py"),
        "--repo", "example/project", "--payload-file", str(here / "fixtures" / "visible-messages.json"),
        "--state-dir", str(temp / "state"),
    ], env=env, text=True, capture_output=True)
    check(draft.returncode == 0, f"publisher default draft succeeds: {draft.stderr}")
    check(not sentinel.exists(), "publisher default draft never calls gh")
    check(bool(draft.stdout.strip()), "publisher default draft returns reviewable output")

print(f"discussion-skills: {checks} checks passed (document/interface contracts and offline draft only)")
PY
