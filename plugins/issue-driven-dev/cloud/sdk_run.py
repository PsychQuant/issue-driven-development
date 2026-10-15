#!/usr/bin/env python3
"""Run the issue-driven-dev plugin through the Claude Agent SDK (EXPERIMENTAL, #400).

Experimental spike tool for change `cloud-idd-runtime-spike`; the interface may
change or disappear. The reusable workflow `.github/workflows/idd-cloud-run.yml`
calls it after cloning IDD, superpowers and parallel-ai-agents into
$RUNNER_TEMP, with the user prompt passed through an environment variable:

    python3 sdk_run.py --prompt "$IDD_PROMPT" \
        --plugin-dir "$RUNNER_TEMP/idd/plugins/issue-driven-dev" \
        --plugin-dir "$RUNNER_TEMP/superpowers/<plugin root>" \
        --plugin-dir "$RUNNER_TEMP/parallel-ai-agents/<plugin root>" \
        --cwd "$GITHUB_WORKSPACE" --max-turns "$MAX_TURNS"

ANTHROPIC_API_KEY is read from the environment only. The SDK's CLI subprocess
inherits it from this process's environment; it is never put on a command line
and never printed. --dry-run prints the options and exits without importing
claude_agent_sdk, so it works where the SDK is not installed.

Output, in order: labelled evidence lines from the session's init message
(LOADED_PLUGINS, PLUGIN_ERRORS, TOOLS, WATCHED_TOOLS, SKILLS, ...), one summary
line per message, then RESULT / COST_USD / DURATION_MS / NUM_TURNS.

Exit codes: 0 success; 1 the SDK reported an error (or no result arrived);
2 bad arguments, missing plugin dir, missing key, or SDK not installed.

SDK API names used (Python reference https://code.claude.com/docs/en/agent-sdk/python.md
and plugin guide https://code.claude.com/docs/en/agent-sdk/plugins.md):
claude_agent_sdk.query, ClaudeAgentOptions(plugins, cwd, max_turns,
permission_mode, setting_sources), SystemMessage(subtype, data),
ResultMessage(subtype, is_error, result, total_cost_usd, duration_ms,
num_turns, terminal_reason, errors, api_error_status), ClaudeSDKError.
Init-message keys (plugins, plugin_errors, tools, skills, ...) follow the
TypeScript SDKSystemMessage shape (https://code.claude.com/docs/en/agent-sdk/typescript.md)
and are read with dict.get, so a missing key prints as absent instead of failing.
"""

import argparse
import asyncio
import json
import os
import re
import sys
from typing import Any, Iterable, NoReturn

EXIT_OK = 0
EXIT_RUN_FAILED = 1
EXIT_CONFIG = 2

API_KEY_ENV = "ANTHROPIC_API_KEY"
SDK_PACKAGE = "claude-agent-sdk"
DEFAULT_MAX_TURNS = 80
SUMMARY_CHARS = 200

# The workflow sets CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1 so a prompt-injected
# command cannot read ANTHROPIC_API_KEY. With the scrub on, Claude Code forces
# the session to the default permission mode whatever is requested, and says so
# only on stderr ("Permission mode forced to default ... Declare allowedTools
# explicitly"; sandbox run 38684468139 and a local repro with CLI 2.1.300). So
# the runner asks for default openly and pre-approves the tools IDD uses. A tool
# not on the list is denied, which shows up as permission_denied in the log.
PERMISSION_MODE = "default"

# Bare names approve every call to that tool. Names a given CLI version does not
# have are ignored. Kept to what IDD's skills, superpowers and pai actually call.
ALLOWED_TOOLS = (
    "Bash", "Read", "Write", "Edit", "NotebookEdit", "Glob", "Grep",
    "Skill", "Task", "Agent", "TaskCreate", "TaskGet", "TaskList", "TaskUpdate",
    "TaskStop", "Workflow", "WebFetch", "WebSearch", "ToolSearch", "Monitor",
    "EnterWorktree", "ExitWorktree",
)

# Load only the target repo's shared .claude/settings.json (and its CLAUDE.md).
# Leaving setting_sources unset would also load ~/.claude (user) and
# .claude/settings.local.json. On a CI runner those are empty, but on a
# maintainer's laptop the user source would enable that person's own plugins
# and settings, which would contaminate the LOADED_PLUGINS / TOOLS evidence.
SETTING_SOURCES = ["project"]

# The tools whose presence criterion C6 asks about. The init message lists the
# Agent tool under its legacy name "Task" (typescript.md, Agent tool section).
WATCHED_TOOLS = {
    "Skill": ("Skill",),
    "Agent": ("Agent", "Task"),
    "TaskCreate": ("TaskCreate",),
    "AskUserQuestion": ("AskUserQuestion",),
    "Workflow": ("Workflow",),
}

SECRET_NAME_MARKERS = ("KEY", "TOKEN", "SECRET", "PASSWORD")
MIN_SECRET_LEN = 8


# ── secret handling ──────────────────────────────────────────────────────────


def secret_values() -> list[str]:
    """Values of env vars whose names look secret, longest first."""
    values = {
        value
        for name, value in os.environ.items()
        if any(marker in name.upper() for marker in SECRET_NAME_MARKERS)
        and len(value) >= MIN_SECRET_LEN
    }
    return sorted(values, key=len, reverse=True)


def redact(text: str, secrets: Iterable[str]) -> str:
    """Replace every secret value in text with ***."""
    for value in secrets:
        text = text.replace(value, "***")
    return text


def presence(name: str) -> str:
    """Show only whether an env var is set, never its value."""
    return "*** (set)" if os.environ.get(name) else "(not set)"


class Printer:
    """stdout/stderr writer that redacts secret env values from every line."""

    def __init__(self) -> None:
        self._secrets = secret_values()

    def out(self, text: str) -> None:
        print(redact(text, self._secrets), flush=True)

    def err(self, text: str) -> None:
        print(redact(text, self._secrets), file=sys.stderr, flush=True)


def fail(printer: Printer, message: str, code: int) -> NoReturn:
    printer.err(f"sdk_run.py: error: {message}")
    raise SystemExit(code)


# ── arguments and validation ─────────────────────────────────────────────────


def positive_int(raw: str) -> int:
    try:
        value = int(raw)
    except ValueError:
        raise argparse.ArgumentTypeError(f"not an integer: {raw!r}") from None
    if value < 1:
        raise argparse.ArgumentTypeError(f"must be at least 1: {value}")
    return value


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="sdk_run.py",
        description="EXPERIMENTAL (#400): run the issue-driven-dev plugin via the Claude Agent SDK.",
    )
    parser.add_argument("--prompt", required=True, help="prompt sent to the agent")
    parser.add_argument(
        "--plugin-dir",
        dest="plugin_dirs",
        action="append",
        required=True,
        metavar="PATH",
        help="plugin root directory to load (repeatable, at least one)",
    )
    parser.add_argument("--cwd", default=os.getcwd(), help="working directory (default: current dir)")
    parser.add_argument(
        "--max-turns",
        type=positive_int,
        default=DEFAULT_MAX_TURNS,
        help=f"maximum agentic turns (default: {DEFAULT_MAX_TURNS})",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="print the options and exit; no API call, no SDK import",
    )
    return parser.parse_args(argv)


def absolute_dir(path: str) -> str:
    # The SDK resolves relative plugin paths against its `cwd` option and does
    # not expand "~"; resolve here so --plugin-dir means what the caller typed.
    return os.path.abspath(os.path.expanduser(path))


def validate_dirs(printer: Printer, args: argparse.Namespace) -> tuple[list[str], str]:
    plugin_dirs = [absolute_dir(p) for p in args.plugin_dirs]
    for path in plugin_dirs:
        if not os.path.isdir(path):
            fail(printer, f"--plugin-dir is not an existing directory: {path}", EXIT_CONFIG)
    cwd = absolute_dir(args.cwd)
    if not os.path.isdir(cwd):
        fail(printer, f"--cwd is not an existing directory: {cwd}", EXIT_CONFIG)
    return plugin_dirs, cwd


# ── output helpers ───────────────────────────────────────────────────────────


def shorten(text: str, limit: int = SUMMARY_CHARS) -> str:
    flat = re.sub(r"\s+", " ", text).strip()
    return flat if len(flat) <= limit else flat[: limit - 1] + "…"


def print_options(printer: Printer, plugin_dirs: list[str], cwd: str, args: argparse.Namespace) -> None:
    printer.out(f"PROMPT: {shorten(args.prompt)}")
    printer.out(f"PROMPT_CHARS: {len(args.prompt)}")
    for path in plugin_dirs:
        printer.out(f"PLUGIN_DIR: {path}")
    printer.out(f"CWD: {cwd}")
    printer.out(f"MAX_TURNS: {args.max_turns}")
    printer.out(f"PERMISSION_MODE: {PERMISSION_MODE}")
    printer.out(f"ALLOWED_TOOLS: {', '.join(ALLOWED_TOOLS)}")
    for path in plugin_dirs:
        printer.out(f"ADD_DIR: {path}")
    printer.out(f"SETTING_SOURCES: {','.join(SETTING_SOURCES)}")
    printer.out(f"{API_KEY_ENV}: {presence(API_KEY_ENV)}")


def join_or_absent(data: dict[str, Any], key: str) -> str:
    if key not in data:
        return "(absent from init message)"
    value = data[key]
    if isinstance(value, list):
        return ", ".join(str(item) for item in value) if value else "(none)"
    return str(value)


def describe_plugins(data: dict[str, Any]) -> str:
    plugins = data.get("plugins")
    if plugins is None:
        return "(absent from init message)"
    if not plugins:
        return "(none)"
    parts = []
    for plugin in plugins:
        if isinstance(plugin, dict):
            parts.append(f"{plugin.get('name')} @ {plugin.get('path')}")
        else:
            parts.append(str(plugin))
    return "; ".join(parts)


def describe_watched_tools(tools: list[str]) -> str:
    present = set(tools)
    parts = []
    for label, names in WATCHED_TOOLS.items():
        found = next((n for n in names if n in present), None)
        if found is None:
            parts.append(f"{label}=absent")
        elif found == label:
            parts.append(f"{label}=present")
        else:
            parts.append(f"{label}=present(as {found})")
    return " ".join(parts)


def print_init(printer: Printer, data: dict[str, Any]) -> None:
    """Evidence for C1 (plugin load) and C6 (tool availability)."""
    printer.out(f"LOADED_PLUGINS: {describe_plugins(data)}")
    if data.get("plugin_errors"):
        printer.out(f"PLUGIN_ERRORS: {json.dumps(data['plugin_errors'], ensure_ascii=False)}")
    else:
        printer.out("PLUGIN_ERRORS: (none reported)")
    printer.out(f"TOOLS: {join_or_absent(data, 'tools')}")
    tools = data.get("tools")
    if isinstance(tools, list):
        printer.out(f"WATCHED_TOOLS: {describe_watched_tools(tools)}")
    printer.out(f"SKILLS: {join_or_absent(data, 'skills')}")
    printer.out(f"AGENTS: {join_or_absent(data, 'agents')}")
    printer.out(f"SLASH_COMMANDS: {join_or_absent(data, 'slash_commands')}")
    printer.out(f"MCP_SERVERS: {json.dumps(data.get('mcp_servers'), ensure_ascii=False)}")
    for label, key in (
        ("CLAUDE_CODE_VERSION", "claude_code_version"),
        ("MODEL", "model"),
        ("SESSION_PERMISSION_MODE", "permissionMode"),
        ("API_KEY_SOURCE", "apiKeySource"),
        ("SESSION_CWD", "cwd"),
    ):
        printer.out(f"{label}: {data.get(key, '(absent from init message)')}")


def block_text(block: Any) -> str:
    """Text of one content block, identified by its fields (no SDK isinstance)."""
    if hasattr(block, "text"):
        return str(block.text)
    if hasattr(block, "name") and hasattr(block, "input"):
        return f"tool_use {block.name} {json.dumps(block.input, ensure_ascii=False, default=str)}"
    if hasattr(block, "tool_use_id"):
        flag = " (error)" if getattr(block, "is_error", False) else ""
        content = block.content
        if not isinstance(content, str):
            content = json.dumps(content, ensure_ascii=False, default=str)
        return f"tool_result{flag} {content}"
    if hasattr(block, "thinking"):
        return "(thinking)"
    return repr(block)


def message_text(message: Any) -> str:
    if hasattr(message, "subtype") and hasattr(message, "data"):
        data = message.data if isinstance(message.data, dict) else {}
        return f"{message.subtype} keys={sorted(data)}"
    content = getattr(message, "content", None)
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        return " | ".join(block_text(block) for block in content)
    return repr(message)


def summarize(message: Any) -> str:
    kind = type(message).__name__
    nested = " (subagent)" if getattr(message, "parent_tool_use_id", None) else ""
    return f"MSG [{kind}{nested}] {shorten(message_text(message))}"


def print_result(printer: Printer, result: Any) -> bool:
    """Print the final result; return True when the SDK reported an error."""
    printer.out(f"RESULT: {getattr(result, 'result', None)}")
    printer.out(f"RESULT_SUBTYPE: {getattr(result, 'subtype', None)}")
    printer.out(f"TERMINAL_REASON: {getattr(result, 'terminal_reason', None)}")
    for label, attr in (
        ("COST_USD", "total_cost_usd"),
        ("DURATION_MS", "duration_ms"),
        ("NUM_TURNS", "num_turns"),
        ("API_ERROR_STATUS", "api_error_status"),
        ("ERRORS", "errors"),
    ):
        value = getattr(result, attr, None)
        if value is not None:
            printer.out(f"{label}: {value}")
    is_error = bool(getattr(result, "is_error", False))
    return is_error or getattr(result, "subtype", "success") != "success"


# ── SDK run ──────────────────────────────────────────────────────────────────


def import_sdk(printer: Printer) -> Any:
    try:
        import claude_agent_sdk  # noqa: PLC0415 - imported lazily so --dry-run needs no SDK
    except ImportError as exc:
        fail(
            printer,
            f"cannot import claude_agent_sdk ({exc}); install it with: pip install {SDK_PACKAGE}",
            EXIT_CONFIG,
        )
    return claude_agent_sdk


def build_options(printer: Printer, sdk: Any, plugin_dirs: list[str], cwd: str, max_turns: int) -> Any:
    """SDK options. add_dirs lets the agent read the plugins, which live outside
    cwd (default mode otherwise confines Bash and reads to the working directory).
    The stderr callback surfaces CLI warnings such as the forced-default notice,
    which the SDK would otherwise drop."""
    return sdk.ClaudeAgentOptions(
        plugins=[{"type": "local", "path": path} for path in plugin_dirs],
        cwd=cwd,
        max_turns=max_turns,
        permission_mode=PERMISSION_MODE,
        allowed_tools=list(ALLOWED_TOOLS),
        add_dirs=list(plugin_dirs),
        setting_sources=SETTING_SOURCES,
        stderr=lambda line: printer.out(f"CLI_STDERR: {line.rstrip()}"),
    )


async def stream(printer: Printer, sdk: Any, prompt: str, options: Any) -> tuple[bool, Any, Exception | None]:
    """Consume the query; return (init_seen, last ResultMessage or None, exception or None).

    The exception is caught here rather than by the caller so the messages
    already seen are not lost: a single-shot query() raises ResultError
    *after* yielding the error ResultMessage, and that result must still be
    printed. Catching Exception (not only ClaudeSDKError) is deliberate: a
    transport or event-loop failure must also end in a non-zero exit with a
    message on stderr, not in a traceback in the middle of the log.
    """
    init_seen, result, raised = False, None, None
    try:
        async for message in sdk.query(prompt=prompt, options=options):
            if isinstance(message, sdk.SystemMessage) and message.subtype == "init":
                init_seen = True
                print_init(printer, message.data if isinstance(message.data, dict) else {})
            if isinstance(message, sdk.ResultMessage):
                result = message
                continue
            printer.out(summarize(message))
    except Exception as exc:  # noqa: BLE001 - see docstring
        raised = exc
    return init_seen, result, raised


def run(printer: Printer, prompt: str, plugin_dirs: list[str], cwd: str, max_turns: int) -> int:
    sdk = import_sdk(printer)
    printer.out(f"SDK_VERSION: {getattr(sdk, '__version__', '(unknown)')}")
    try:
        options = build_options(printer, sdk, plugin_dirs, cwd, max_turns)
    except TypeError as exc:
        fail(printer, f"this claude_agent_sdk does not accept the runner's options: {exc}", EXIT_CONFIG)

    init_seen, result, raised = asyncio.run(stream(printer, sdk, prompt, options))

    if not init_seen:
        printer.err("sdk_run.py: warning: no init message received; LOADED_PLUGINS / TOOLS unknown")
    sdk_error = print_result(printer, result) if result is not None else True
    if raised is not None:
        printer.err(f"sdk_run.py: error: {type(raised).__name__}: {raised}")
    if result is None:
        printer.err("sdk_run.py: error: the SDK returned no result message")
    return EXIT_RUN_FAILED if (sdk_error or raised is not None) else EXIT_OK


# ── entry point ──────────────────────────────────────────────────────────────


def main(argv: list[str]) -> int:
    printer = Printer()
    args = parse_args(argv)
    plugin_dirs, cwd = validate_dirs(printer, args)

    if args.dry_run:
        printer.out("MODE: dry-run (no API call; claude_agent_sdk not imported)")
        print_options(printer, plugin_dirs, cwd, args)
        return EXIT_OK

    if not os.environ.get(API_KEY_ENV):
        fail(printer, f"{API_KEY_ENV} is not set in the environment", EXIT_CONFIG)

    printer.out("MODE: run (EXPERIMENTAL, #400)")
    print_options(printer, plugin_dirs, cwd, args)
    return run(printer, args.prompt, plugin_dirs, cwd, args.max_turns)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
