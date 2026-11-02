#!/bin/bash
# idd-ci-gate.sh — does a commit pass the CI command configured on this machine? (#465, spec local-ci-gate)
#
# Usage: idd-ci-gate.sh run --commit <sha> [--cwd <clone>]
# Stdout: RESULT=<...>, and when the command ran RECORD=<file> and LOG=<file>
# Exit (closed list):
#   0 pass · 1 fail · 2 timeout · 3 not-configured · 4 error · 10 remote
#
# The command comes ONLY from ci.command in the repository's untracked .claude/.idd/local.json, which must be yours
# and reached through no link (a linked worktree reads the main worktree's); nothing in the
# repository is executed or inferred, so running this in someone else's clone runs only what you configured.
# It runs in a detached worktree of the commit, removed on every exit path. Anything the gate cannot decide is
# error (4), which never counts as passing.
set -u
# A relative PATH entry or BASH_ENV would resolve inside the clone, and a tracked bash could report a pass.
unset BASH_ENV ENV
CLEAN_PATH=""; IFS=:; for d in $PATH; do case "$d" in /*) CLEAN_PATH="${CLEAN_PATH:+$CLEAN_PATH:}$d" ;; esac; done; unset IFS
export PATH="$CLEAN_PATH"
# -I: a script on stdin would otherwise import from the current directory, and a tracked json.py would run as code.
exec python3 -I - "$@" <<'PY'
import hashlib, json, os, re, shutil, signal, stat, subprocess, sys, tempfile, time, unicodedata
from datetime import datetime

DEFAULT_TIMEOUT = 3600
TAIL_LINES = 40
CONTROL = re.compile(r'\x1b\[[0-9;?]*[ -/]*[@-~]|[\x00-\x08\x0b-\x1f\x7f-\x9f]')
GRACE_SECONDS = 5
CONFIG_PARTS = ('.claude', '.idd', 'local.json')
EXIT = {'pass': 0, 'fail': 1, 'timeout': 2, 'not-configured': 3, 'error': 4, 'remote': 10}


def finish(result, reason=''):
    if reason:
        print(f'idd-ci-gate: {reason}', file=sys.stderr)
    print(f'RESULT={result}', flush=True)
    sys.exit(EXIT[result])


def clean_env():
    """The environment without git's repository-local variables: GIT_DIR, GIT_INDEX_FILE and the like would answer
    for a different repository."""
    names = subprocess.run(['git', 'rev-parse', '--local-env-vars'], capture_output=True, text=True, errors='surrogateescape')
    drop = set(names.stdout.split()) if names.returncode == 0 else set()
    return {k: v for k, v in os.environ.items() if k not in drop and not (k.startswith('GIT_') and names.returncode != 0)}


ENV = clean_env()
ENV['GIT_LFS_SKIP_SMUDGE'] = '1'   # .lfsconfig is tracked: it must not choose a server the checkout contacts
# safe.bareRepository: a tracked directory holding HEAD, objects and refs must not be discovered as a repository.
# hooksPath, fsmonitor: nothing the repository supplies runs during the gate's own git calls.
GIT_GUARD = ['-c', 'safe.bareRepository=explicit', '-c', 'core.hooksPath=/dev/null', '-c', 'core.fsmonitor=false']


def git(cwd, *args):
    return subprocess.run(['git', '-C', cwd, *GIT_GUARD, *args], capture_output=True, text=True, errors='surrogateescape', env=ENV)


def repo_roots(cwd):
    """The repository's own root, then the main worktree's (a linked worktree has no untracked config of its own).
    Nothing above them is searched: a config in a parent directory is not this repository's."""
    top = git(cwd, 'rev-parse', '--show-toplevel')
    if top.returncode != 0 or not top.stdout.strip():
        finish('error', f'{cwd} has no work tree')
    root = top.stdout.strip()
    gitdir = git(cwd, 'rev-parse', '--path-format=absolute', '--git-dir')
    common = git(cwd, 'rev-parse', '--path-format=absolute', '--git-common-dir')
    if gitdir.returncode != 0 or common.returncode != 0:
        finish('error', f'{cwd}: cannot read the git directory')
    # git before 2.31 echoes the unknown --path-format flag with status 0
    if not all(len(o.stdout.splitlines()) == 1 and os.path.isabs(o.stdout.strip()) for o in (gitdir, common)):
        finish('error', 'git did not report absolute paths; this gate needs git 2.31 or newer')
    common_dir = os.path.realpath(common.stdout.strip())
    # The repository must be the ordinary shape: <root>/.git is what git reports, as a directory or, in a linked
    # worktree, the file that points at it. Anything else is a repository this gate does not trust to answer.
    dotgit = os.path.join(root, '.git')
    if os.path.isdir(dotgit) and not os.path.islink(dotgit):
        if os.path.realpath(dotgit) != os.path.realpath(gitdir.stdout.strip()):
            finish('error', f'{dotgit} is not the git directory git reports')
        return root
    if os.path.isfile(dotgit) and not os.path.islink(dotgit) and os.path.basename(common_dir) == '.git':
        return os.path.dirname(common_dir)      # linked worktree: the main worktree's config, and only that
    finish('error', f'{root} is not an ordinary work tree: a symlinked .git, a submodule checkout, --separate-git-dir and worktrees of a bare repository are not supported')


def norm(path):
    return unicodedata.normalize('NFC', path).casefold()


def check_config(root):
    """Refuse the config unless it is this user's own, not reachable through a link, and untracked."""
    uid = os.getuid()
    current = root
    for part in CONFIG_PARTS:
        current = os.path.join(current, part)
        st = os.lstat(current)
        if stat.S_ISLNK(st.st_mode):
            finish('error', f'{current} is a symbolic link; the config must be a real file in this repository')
        if st.st_uid != uid:
            finish('error', f'{current} belongs to another user')
        if st.st_mode & 0o022:
            finish('error', f'{current} is writable by group or others')
    if not stat.S_ISREG(os.lstat(current).st_mode):
        finish('error', f'{current} is not a regular file')
    # Ask from the root, never from the config's directory: git discovers a repository upward from where it runs,
    # so a bare repository planted beside the file would answer "untracked". Names are compared casefolded and
    # normalized, because a case-insensitive filesystem serves LOCAL.JSON as local.json. Any git failure refuses.
    # A submodule at .claude or .claude/.idd shows only as a gitlink, never as the file inside it.
    for parent in (os.path.join(root, '.claude'), os.path.join(root, '.claude', '.idd')):
        if os.path.lexists(os.path.join(parent, '.git')):
            finish('error', f'{parent} holds a .git entry; a command from a nested repository is not accepted')
    listed = git(root, 'ls-files', '-s', '-z')
    if listed.returncode != 0:
        finish('error', f'cannot tell whether the config is tracked: {listed.stderr.strip()[:200]}')
    target = norm('/'.join(CONFIG_PARTS))
    gitlinks = {norm('.claude'), norm('.claude/.idd')}
    for entry in listed.stdout.split('\0'):
        if not entry:
            continue
        meta, _, name = entry.partition('\t')
        if norm(name) == target:
            finish('error', f'{current} is tracked by git; a command in a tracked file is not accepted')
        if meta.startswith('160000') and norm(name) in gitlinks:
            finish('error', f'{name} is a submodule; a command from a nested repository is not accepted')
    # Filter names come from the repository's .gitattributes, so they cannot be switched off by name: a filter
    # configured in this clone's own .git/config (a copied directory, a tarball) is refused before any checkout.
    local = git(root, 'config', '--local', '--includes', '--name-only', '--get-regexp', r'^(filter\.|include\.|includeif\.)')
    if local.returncode == 0 and local.stdout.strip():
        finish('error', 'this clone configures git filters or includes in its own .git/config; refusing to check anything out')
    if local.returncode not in (0, 1):
        finish('error', 'cannot read the clone\'s git config')
    return current


def find_config(cwd):
    root = repo_roots(cwd)
    if os.path.lexists(os.path.join(root, *CONFIG_PARTS)) or os.path.islink(os.path.join(root, '.claude')):
        return check_config(root)
    return None


def load_ci(path):
    try:
        fd = os.open(path, os.O_RDONLY | os.O_NOFOLLOW)   # the file checked above, not a link swapped in since
        with os.fdopen(fd, encoding='utf-8') as f:
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
    """Returns the command's exit code, or None on timeout. No process of its process group outlives this call;
    a daemon that starts its own session (setsid) does."""
    with open(log_path, 'wb') as log:
        proc = subprocess.Popen(['bash', '-c', command], cwd=checkout, stdin=subprocess.DEVNULL,
                                stdout=log, stderr=subprocess.STDOUT, start_new_session=True, env=ENV)
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


def write_record(path, result, sha, command, started, ended, code, checkout, log_path, post_tail):
    """What may reach an issue or PR. The command appears only as a hash, and output only on request (ci.post_output_tail),
    because both can hold secrets and this file is meant to be posted."""
    digest = hashlib.sha256(command.encode('utf-8')).hexdigest()[:12]
    lines = [f'## Local CI: {result}', '', f'- **Commit**: `{sha}`',
             f'- **Command**: sha256 `{digest}` (from local config)', f'- **Started**: {started}', f'- **Ended**: {ended}',
             f'- **Exit code**: {"(timed out)" if code is None else code}']
    if result == 'pass':
        pass
    elif post_tail:
        with open(log_path, encoding='utf-8', errors='replace') as f:
            tail = f.read().splitlines()[-TAIL_LINES:]
        tail = [normalize(CONTROL.sub('', l), checkout) for l in tail]
        longest = max((len(run) for l in tail for run in re.findall(r'`+', l)), default=0)
        fence = '`' * max(5, longest + 1)
        lines += ['', f'Last {TAIL_LINES} lines of output:', '', fence, *tail, fence]
    else:
        lines += ['', 'Output is in the local log on the machine that ran this.']
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
    ci = load_ci(config) if config else {}

    mode = ci.get('mode', 'local')
    if mode not in ('local', 'remote'):
        finish('error', f'ci.mode must be local or remote, got {mode!r}')
    timeout = ci.get('timeout_seconds', DEFAULT_TIMEOUT)
    if isinstance(timeout, bool) or not isinstance(timeout, int) or timeout <= 0:
        finish('error', f'ci.timeout_seconds must be a positive integer, got {timeout!r}')
    post_tail = ci.get('post_output_tail', False)
    if not isinstance(post_tail, bool):
        finish('error', f'ci.post_output_tail must be true or false, got {post_tail!r}')
    if 'command' in ci and (not isinstance(ci['command'], str) or not ci['command'].strip()):
        finish('error', 'ci.command must be a non-empty string')
    if mode == 'remote':
        finish('remote')
    if 'command' not in ci:
        finish('not-configured', 'set ci.command in .claude/.idd/local.json, or ci.mode to "remote" to use remote CI')
    command = ci['command']
    with open(config, 'rb') as f:
        config_before = hashlib.sha256(f.read()).digest()

    resolved = git(cwd, 'rev-parse', '--verify', '--quiet', commit + '^{commit}')
    if resolved.returncode != 0:
        finish('error', f'commit not found: {commit}')
    sha = resolved.stdout.strip()

    work = tempfile.mkdtemp(prefix='idd-ci-gate-')
    checkout = os.path.join(work, 'checkout')
    log_path, record = os.path.join(work, 'output.log'), os.path.join(work, 'record.md')
    for s in (signal.SIGTERM, signal.SIGHUP):
        signal.signal(s, lambda *_: sys.exit(EXIT['error']))
    added = False
    try:
        add = git(cwd, 'worktree', 'add', '--quiet', '--detach', checkout, sha)
        if add.returncode != 0:
            finish('error', f'checkout failed: {add.stderr.strip()}')
        added = True
        started = now()
        code = run_command(command, checkout, log_path, timeout)
        result = 'timeout' if code is None else ('pass' if code == 0 else 'fail')
        write_record(record, result, sha, command, started, now(), code, checkout, log_path, post_tail)
        print(f'RECORD={record}\nLOG={log_path}')
    finally:
        if added:
            git(cwd, 'worktree', 'remove', '--force', checkout)
            shutil.rmtree(checkout, ignore_errors=True)
    # A command that rewrites its own config could make every later run pass; this run's verdict cannot be trusted.
    try:
        with open(config, 'rb') as f:
            changed = hashlib.sha256(f.read()).digest() != config_before
    except OSError:
        changed = True
    if changed:
        finish('error', f'{config} changed during the run; check it before trusting this or later results')
    finish(result)


try:
    main(sys.argv[1:])
except SystemExit:
    raise
except Exception as e:      # anything unforeseen is "cannot decide", never a plain failure and never a pass
    finish('error', f'unexpected {type(e).__name__}: {e}')
PY
