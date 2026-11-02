#!/usr/bin/env bash
# idd-ci-gate.sh — does a commit pass the CI command configured on this machine? (#465, spec local-ci-gate)
#
# Usage: idd-ci-gate.sh run --commit <sha> [--cwd <clone>]
# Stdout: RESULT=<...>, and when the command ran RECORD=<file> and LOG=<file>
# Exit (closed list):
#   0 pass · 1 fail · 2 timeout · 3 not-configured · 4 error · 10 remote
#
# The command comes ONLY from ci.command in the walked-up, untracked .claude/.idd/local.json: nothing in the
# repository is executed or inferred, so running this in someone else's clone runs only what you configured.
# It runs in a detached worktree of the commit, removed on every exit path. Anything the gate cannot decide is
# error (4), which never counts as passing.
set -u
exec python3 - "$@" <<'PY'
import json, os, shutil, signal, subprocess, sys, tempfile, time
from datetime import datetime

DEFAULT_TIMEOUT = 3600
TAIL_LINES = 40
GRACE_SECONDS = 5
EXIT = {'pass': 0, 'fail': 1, 'timeout': 2, 'not-configured': 3, 'error': 4, 'remote': 10}


def finish(result, reason=''):
    if reason:
        print(f'idd-ci-gate: {reason}', file=sys.stderr)
    print(f'RESULT={result}', flush=True)
    sys.exit(EXIT[result])


def git(cwd, *args):
    return subprocess.run(['git', '-C', cwd, *args], capture_output=True, text=True)


def find_config(cwd):
    """Walk up from cwd, then from the main worktree (a linked worktree has no untracked config of its own)."""
    starts = [cwd]
    common = git(cwd, 'rev-parse', '--path-format=absolute', '--git-common-dir')
    if common.returncode == 0:
        starts.append(os.path.dirname(common.stdout.strip()))
    home = os.path.realpath(os.path.expanduser('~'))
    for start in starts:
        d = os.path.realpath(start)
        while True:
            p = os.path.join(d, '.claude', '.idd', 'local.json')
            if os.path.isfile(p):
                return p
            if d == home or d == os.path.dirname(d):
                break
            d = os.path.dirname(d)
    return None


def load_ci(path):
    try:
        with open(path, encoding='utf-8') as f:
            cfg = json.load(f)
    except (OSError, ValueError) as e:
        finish('error', f'cannot read {path}: {e}')
    if not isinstance(cfg, dict):
        finish('error', f'{path} is not a JSON object')
    ci = cfg.get('ci', {})
    if not isinstance(ci, dict):
        finish('error', 'ci must be an object')
    return ci


def normalize(text, checkout):
    home = os.path.expanduser('~')
    # Longest first: the checkout may sit under the home directory.
    for path, name in sorted({(checkout, '<checkout>'), (os.path.realpath(checkout), '<checkout>'),
                              (home, '~'), (os.path.realpath(home), '~')}, key=lambda x: -len(x[0])):
        text = text.replace(path, name)
    return text


def now():
    return datetime.now().astimezone().isoformat(timespec='seconds')


def kill_group(pgid, sig):
    try:
        os.killpg(pgid, sig)
        return True
    except (ProcessLookupError, PermissionError):
        return False


def run_command(command, checkout, log_path, timeout):
    """Returns the command's exit code, or None on timeout. No process of the group outlives this call."""
    with open(log_path, 'wb') as log:
        proc = subprocess.Popen(['bash', '-c', command], cwd=checkout, stdin=subprocess.DEVNULL,
                                stdout=log, stderr=subprocess.STDOUT, start_new_session=True)
    code = None
    try:
        code = proc.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        pass
    finally:
        if kill_group(proc.pid, signal.SIGTERM):
            deadline = time.monotonic() + GRACE_SECONDS
            while time.monotonic() < deadline and kill_group(proc.pid, 0):
                proc.poll()
                time.sleep(0.1)
            kill_group(proc.pid, signal.SIGKILL)
        proc.wait()
    return code


def write_record(path, result, sha, command, started, ended, code, checkout, log_path):
    lines = [f'## Local CI: {result}', '', f'- **Commit**: `{sha}`',
             f'- **Command**: `{normalize(command, checkout)}`', f'- **Started**: {started}', f'- **Ended**: {ended}',
             f'- **Exit code**: {"(timed out)" if code is None else code}']
    if result != 'pass':
        with open(log_path, encoding='utf-8', errors='replace') as f:
            tail = f.read().splitlines()[-TAIL_LINES:]
        lines += ['', f'Last {TAIL_LINES} lines of output:', '', '`````',
                  *[normalize(l, checkout) for l in tail], '`````']
    with open(path, 'w', encoding='utf-8') as f:
        f.write('\n'.join(lines) + '\n')


def main(argv):
    if not argv or argv[0] != 'run':
        finish('error', 'usage: idd-ci-gate.sh run --commit <sha> [--cwd <clone>]')
    commit, cwd, rest = None, os.getcwd(), argv[1:]
    while rest:
        if rest[0] in ('--commit', '--cwd') and len(rest) > 1:
            if rest[0] == '--commit':
                commit = rest[1]
            else:
                cwd = rest[1]
            rest = rest[2:]
        else:
            finish('error', f'unknown or incomplete argument: {rest[0]}')
    if not commit or commit.startswith('-'):
        finish('error', '--commit must name a commit')
    if git(cwd, 'rev-parse', '--git-dir').returncode != 0:
        finish('error', f'{cwd} is not a git repository')

    config = find_config(cwd)
    ci = {}
    if config:
        cdir, cname = os.path.split(config)
        if git(cdir, 'ls-files', '--error-unmatch', '--', cname).returncode == 0:
            finish('error', f'{config} is tracked by git; a command in a tracked file is not accepted')
        ci = load_ci(config)

    mode = ci.get('mode', 'local')
    if mode == 'remote':
        finish('remote')
    if mode != 'local':
        finish('error', f'ci.mode must be local or remote, got {mode!r}')
    if 'command' not in ci:
        finish('not-configured', 'set ci.command in .claude/.idd/local.json, or ci.mode to "remote" to use remote CI')
    command = ci['command']
    if not isinstance(command, str) or not command.strip():
        finish('error', 'ci.command must be a non-empty string')
    timeout = ci.get('timeout_seconds', DEFAULT_TIMEOUT)
    if isinstance(timeout, bool) or not isinstance(timeout, int) or timeout <= 0:
        finish('error', f'ci.timeout_seconds must be a positive integer, got {timeout!r}')

    resolved = git(cwd, 'rev-parse', '--verify', '--quiet', commit + '^{commit}')
    if resolved.returncode != 0:
        finish('error', f'commit not found: {commit}')
    sha = resolved.stdout.strip()

    work = tempfile.mkdtemp(prefix='idd-ci-gate-')
    checkout = os.path.join(work, 'checkout')
    log_path, record = os.path.join(work, 'output.log'), os.path.join(work, 'record.md')
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(EXIT['error']))
    added = False
    try:
        add = git(cwd, 'worktree', 'add', '--quiet', '--detach', checkout, sha)
        if add.returncode != 0:
            finish('error', f'checkout failed: {add.stderr.strip()}')
        added = True
        started = now()
        code = run_command(command, checkout, log_path, timeout)
        result = 'timeout' if code is None else ('pass' if code == 0 else 'fail')
        write_record(record, result, sha, command, started, now(), code, checkout, log_path)
        print(f'RECORD={record}\nLOG={log_path}')
    finally:
        if added:
            git(cwd, 'worktree', 'remove', '--force', checkout)
            shutil.rmtree(checkout, ignore_errors=True)
            git(cwd, 'worktree', 'prune')
    finish(result)


main(sys.argv[1:])
PY
