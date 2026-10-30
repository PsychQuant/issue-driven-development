"""Safety regressions for #452. Every hostile path belongs to TemporaryDirectory.

Capture subprocess output; never print inherited Git configuration or variables.
The caller is built independently of the helper under test, so a broken helper
can only damage a disposable repository. Compare file bytes, not git status
(status can refresh the index or fail after core.bare has been corrupted).
"""
import os
from pathlib import Path
import re
import shlex
import shutil
import signal
import subprocess
import tempfile
import unittest

SCRIPTS = Path(__file__).resolve().parents[2]
HELPER = SCRIPTS / "lib/git-fixture-helpers.sh"
DOC_SUITE = SCRIPTS / "tests/doc-sync-sweep/test.sh"


def snapshot(root):
    return {str(p.relative_to(root)): (p.lstat().st_mode,
            os.readlink(p) if p.is_symlink() else p.read_bytes() if p.is_file() else None)
            for p in root.rglob("*")}


def fixture_suites():
    # Deliberately broad discovery: includes git with -C/-c/arrays/multiline
    # options, plus helper consumers. False positives must isolate too. This
    # inventory is NOT the safety boundary; the behavioral tests below are.
    for suite in sorted((SCRIPTS / "tests").glob("*/test.sh")):
        source = suite.read_text()
        code = "\n".join(line for line in source.splitlines()
                         if not line.lstrip().startswith("#"))
        code = code.replace("\\\n", " ")
        if "git_fixture_setup" in code or re.search(r"\bgit\b[^;\n]*\b(init|clone)\b", code):
            yield suite


PROBE = '''
    set -eu
    . "$1"
    git_fixture_setup
    repo=$(git_fixture_mktemp) || exit 1
    git_fixture_init "$repo" -b main
    # Intentionally use descendant shells and a clone, not only helper calls.
    bash -c 'cd "$1"; printf content > unignored; git add unignored;
             git commit -qm fixture; git tag -am fixture v1;
             test "$(git ls-files)" = unignored' fixture "$repo"
    git clone -q "$repo" "$IDD_GIT_FIXTURE_ROOT/clone"
    git -C "$IDD_GIT_FIXTURE_ROOT/clone" status --porcelain >/dev/null
    printf 'updated\\n' > "$repo/unignored"
    test "$(git -C "$repo" diff --numstat)" = "$(printf '1\\t1\\tunignored')"
    test ! -e "$repo/.git/hooks/pre-commit"
    printf fixture-ok
'''


class IsolationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="idd-452-regression-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name).resolve()
        self.env = {k: v for k, v in os.environ.items() if not k.startswith("GIT_")}
        self.env.update(GIT_CONFIG_GLOBAL="/dev/null", GIT_CONFIG_SYSTEM="/dev/null",
                        GIT_CONFIG_NOSYSTEM="1", GIT_TERMINAL_PROMPT="0")
        # Synthetic HOME/XDG prevent even a regressed helper from reading real
        # user settings. HOME is changed only in the disposable child process.
        for name in ("home", "xdg", "tmp"):
            (self.root / name).mkdir()
        self.env.update(HOME=str(self.root / "home"),
                        XDG_CONFIG_HOME=str(self.root / "xdg"),
                        TMPDIR=str(self.root / "tmp"))
        self.caller = self.root / "caller"
        self.caller.mkdir()
        self.git("init", "-q", "-b", "main", "--template=")
        self.git("config", "user.name", "Fixture Caller")
        self.git("config", "user.email", "caller@example.invalid")
        (self.caller / "tracked").write_text("committed\n")
        self.git("add", "tracked")
        self.git("commit", "-qm", "seed")
        (self.caller / "tracked").write_text("staged caller work\n")
        self.git("add", "tracked")
        (self.caller / "tracked").write_text("unstaged caller work\n")

    def run_cmd(self, argv, *, env=None, cwd=None):
        with subprocess.Popen(argv, cwd=cwd or self.caller, env=env or self.env,
                              stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                              start_new_session=True) as process:
            try:
                stdout, stderr = process.communicate(timeout=120)
            except subprocess.TimeoutExpired:
                os.killpg(process.pid, signal.SIGKILL)
                process.communicate()
                self.fail("disposable fixture process timed out")
            return subprocess.CompletedProcess(argv, process.returncode, stdout, stderr)

    def git(self, *args, cwd=None):
        p = self.run_cmd(["git", "-c", "core.hooksPath=/dev/null",
                          "-c", "commit.gpgsign=false", *args], cwd=cwd)
        self.assertEqual(p.returncode, 0, "disposable caller setup failed")
        return p.stdout.decode().strip()

    def assert_unchanged(self, before):
        self.assertTrue(snapshot(self.caller) == before,
                        "suite modified disposable caller files/config/index/refs/objects")

    def probe(self, env, code=PROBE):
        return self.run_cmd(["bash", "-c", code, "fixture", str(HELPER)], env=env)

    def executable(self, path, content):
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content)
        path.chmod(0o755)
        return path

    def hostile_settings(self):
        canary = self.root / "external-program-ran"
        program = self.executable(self.root / "canary", "#!/bin/sh\n: > " + shlex.quote(str(canary)) + "\nexit 99\n")
        hooks = self.root / "hooks"
        self.executable(hooks / "pre-commit", program.read_text())
        self.executable(hooks / "post-checkout", program.read_text())
        template = self.root / "template"
        self.executable(template / "hooks/pre-commit", program.read_text())
        ignore = self.root / "ignore"
        ignore.write_text("*\n")
        return canary, {
            "core.hooksPath": str(hooks), "core.fsmonitor": str(program),
            "commit.gpgsign": "true", "tag.gpgsign": "true",
            "gpg.program": str(program), "init.templateDir": str(template),
            "core.excludesFile": str(ignore), "core.bare": "true",
        }

    def test_direct_suite_preserves_caller_with_repository_environment(self):
        before = snapshot(self.caller)
        env = dict(self.env, GIT_DIR=str(self.caller / ".git"),
                   GIT_WORK_TREE=str(self.caller),
                   GIT_INDEX_FILE=str(self.caller / ".git/index"),
                   GIT_COMMON_DIR=str(self.caller / ".git"),
                   GIT_OBJECT_DIRECTORY=str(self.caller / ".git/objects"))
        p = self.run_cmd(["bash", str(DOC_SUITE)], env=env)
        self.assert_unchanged(before)
        self.assertEqual(p.returncode, 0, "doc-sync fixture failed under inherited Git env")

    def test_linked_worktree_alias_preserves_shared_repository(self):
        linked = self.root / "linked"
        self.git("worktree", "add", "-qb", "linked", str(linked))
        before = snapshot(self.caller)
        linked_before = snapshot(linked)
        p = self.run_cmd(["git", "-c", f"alias.fixture=!bash {DOC_SUITE}", "fixture"], cwd=linked)
        self.assert_unchanged(before)
        self.assertTrue(snapshot(linked) == linked_before, "suite modified linked worktree")
        self.assertEqual(p.returncode, 0, "linked alias fixture failed")

    def test_plain_fixture_under_caller_tmpdir_cannot_discover_caller(self):
        nested_tmp = self.caller / "temporary"
        nested_tmp.mkdir()
        before = snapshot(self.caller)
        p = self.run_cmd(["bash", "-c", '''
            . "$1"
            git_fixture_setup
            plain=$(git_fixture_mktemp) || exit 1
            if git -C "$plain" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
                exit 91
            fi
        ''', "fixture", str(HELPER)], env=dict(self.env, TMPDIR=str(nested_tmp)))
        self.assert_unchanged(before)
        self.assertEqual(p.returncode, 0, "plain fixture discovered its caller through TMPDIR")

    def test_global_system_and_command_scope_config_are_isolated(self):
        canary, settings = self.hostile_settings()
        config = self.root / "hostile-config"
        for key, value in settings.items():
            self.git("config", "--file", str(config), key, value)
        original = config.read_bytes()
        channels = {
            "global": dict(self.env, GIT_CONFIG_GLOBAL=str(config)),
            "system": dict(self.env, GIT_CONFIG_SYSTEM=str(config), GIT_CONFIG_NOSYSTEM="0"),
            "parameters": dict(self.env, GIT_CONFIG_PARAMETERS=" ".join(
                shlex.quote(k) + "=" + shlex.quote(v) for k, v in settings.items())),
        }
        pairs = dict(self.env, GIT_CONFIG_COUNT=str(len(settings)))
        for n, (key, value) in enumerate(settings.items()):
            pairs[f"GIT_CONFIG_KEY_{n}"] = key
            pairs[f"GIT_CONFIG_VALUE_{n}"] = value
        channels["pairs"] = pairs
        for name, env in channels.items():
            with self.subTest(channel=name):
                before = snapshot(self.caller)
                p = self.probe(env)
                self.assertEqual(p.returncode, 0, "fixture could not commit/tag/clone under hostile config")
                self.assertEqual(p.stdout, b"fixture-ok")
                self.assertFalse(canary.exists(), "inherited program executed")
                self.assertTrue(config.read_bytes() == original, "caller config file changed")
                self.assert_unchanged(before)

    def test_default_xdg_ignore_and_template_environment_are_isolated(self):
        canary, settings = self.hostile_settings()
        ignore = self.root / "xdg/git/ignore"
        ignore.parent.mkdir()
        ignore.write_text("*\n")
        p = self.probe(dict(self.env, GIT_TEMPLATE_DIR=settings["init.templateDir"]))
        self.assertEqual(p.returncode, 0, "default XDG ignore or template leaked into fixture")
        self.assertFalse(canary.exists(), "template hook executed")

    def test_default_xdg_attributes_cannot_turn_text_diffs_into_binary(self):
        attributes = self.root / "xdg/git/attributes"
        attributes.parent.mkdir()
        attributes.write_text("* binary\n")
        p = self.probe(self.env)
        self.assertEqual(p.returncode, 0, "default XDG attributes changed text diff semantics")

    def test_tmpdir_with_ceiling_separator_fails_closed(self):
        nested_tmp = self.caller / "temporary:colon"
        nested_tmp.mkdir()
        before = snapshot(self.caller)
        p = self.probe(dict(self.env, TMPDIR=str(nested_tmp)))
        self.assertNotEqual(p.returncode, 0, "unrepresentable Git discovery boundary accepted")
        self.assert_unchanged(before)

    def test_malformed_config_and_trace_destinations_are_cleared_before_git(self):
        trace = self.caller / "trace-must-not-exist"
        config = self.caller / "invalid-config"
        config.write_text("invalid config syntax\n")
        before = snapshot(self.caller)
        env = dict(self.env, GIT_CONFIG=str(config), GIT_CONFIG_COUNT="invalid",
                   GIT_CONFIG_PARAMETERS="malformed", GIT_TRACE=str(trace),
                   GIT_TRACE2_EVENT=str(trace), GIT_NAMESPACE="foreign",
                   GIT_ALTERNATE_OBJECT_DIRECTORIES=str(self.caller / ".git/objects"),
                   GIT_SHALLOW_FILE=str(self.caller / ".git/shallow"))
        p = self.probe(env)
        self.assertEqual(p.returncode, 0, "helper consulted Git before clearing inherited variables")
        self.assert_unchanged(before)

    def test_init_rejects_empty_outside_existing_and_symlink_paths(self):
        for target in ("empty", "outside", "existing", "symlink"):
            with self.subTest(target=target):
                before = snapshot(self.caller)
                env = dict(self.env, FIXTURE_CALLER=str(self.caller), FIXTURE_TARGET=target)
                p = self.probe(env, '''
                    . "$1"; git_fixture_setup
                    case "$FIXTURE_TARGET" in
                      empty) target="" ;;
                      outside) target="$FIXTURE_CALLER" ;;
                      existing) target=$(git_fixture_mktemp) || exit 1
                                git_fixture_init "$target" ;;
                      symlink) target="$IDD_GIT_FIXTURE_ROOT/link"
                               ln -s "$FIXTURE_CALLER" "$target" ;;
                    esac
                    git_fixture_init "$target"
                    printf should-not-continue
                ''')
                self.assertNotEqual(p.returncode, 0, "unsafe init target accepted")
                self.assertNotIn(b"should-not-continue", p.stdout)
                self.assert_unchanged(before)

    def test_setup_preserves_parent_environment_and_cleans_owned_root(self):
        p = self.probe(self.env, '''
            . "$1"
            export GIT_DIR=parent-sentinel GIT_CONFIG_COUNT=invalid
            ( git_fixture_setup; printf '%s\n' "$IDD_GIT_FIXTURE_ROOT" )
            test "$GIT_DIR" = parent-sentinel && test "$GIT_CONFIG_COUNT" = invalid
        ''')
        self.assertEqual(p.returncode, 0, "setup changed invoking shell environment")
        self.assertFalse(Path(p.stdout.decode().strip()).exists(), "sandbox was not cleaned")

    def integrity_driver(self):
        # Used from real Git hook/rebase processes. Compare within the callback,
        # so the intentional outer commit/rebase is not mistaken for corruption.
        driver = self.root / "integrity-driver.py"
        driver.write_text('''import os, pathlib, runpy, subprocess, sys
snap = runpy.run_path(sys.argv[1])["snapshot"]
roots = [pathlib.Path(p) for p in sys.argv[3:]]
before = [snap(p) for p in roots]
r = subprocess.run(["bash", sys.argv[2]], capture_output=True)
if r.returncode or before != [snap(p) for p in roots]:
    sys.exit(92)
''')
        return " ".join(shlex.quote(str(x)) for x in
                        [shutil.which("python3"), driver, Path(__file__), DOC_SUITE])

    def test_actual_precommit_hook_in_linked_worktree(self):
        linked = self.root / "linked"
        self.git("worktree", "add", "-qb", "linked", str(linked))
        (linked / "hook-change").write_text("intentional caller change\n")
        self.git("add", "hook-change", cwd=linked)
        hooks = self.root / "entry-hooks"
        command = self.integrity_driver() + " " + shlex.quote(str(self.caller)) + " " + shlex.quote(str(linked))
        self.executable(hooks / "pre-commit", '''#!/bin/sh
# A regression must fail, not recursively launch hooks until timeout.
[ "${IDD_452_HOOK_ACTIVE:-}" != 1 ] || exit 93
export IDD_452_HOOK_ACTIVE=1
''' + command + "\n")
        p = self.run_cmd(["git", "-c", f"core.hooksPath={hooks}",
                          "commit", "-qm", "intentional outer commit"], cwd=linked)
        self.assertEqual(p.returncode, 0, "hook fixture changed caller state or failed")
        self.assertEqual(self.git("show", "HEAD:hook-change", cwd=linked), "intentional caller change")
        self.assertEqual(self.git("rev-list", "--count", "HEAD", cwd=linked), "2")

    def test_actual_rebase_exec_in_linked_worktree(self):
        linked = self.root / "linked"
        self.git("worktree", "add", "-qb", "linked", str(linked))
        (linked / "change").write_text("intentional change\n")
        self.git("add", "change", cwd=linked)
        self.git("commit", "-qm", "intentional change", cwd=linked)
        config_before = (self.caller / ".git/config").read_bytes()
        index_before = (self.caller / ".git/index").read_bytes()
        command = self.integrity_driver() + " " + shlex.quote(str(self.caller)) + " " + shlex.quote(str(linked))
        p = self.run_cmd(["git", "rebase", "--force-rebase", "--exec", command, "main"], cwd=linked)
        self.assertEqual(p.returncode, 0, "rebase exec fixture changed caller state or failed")
        self.assertTrue((self.caller / ".git/config").read_bytes() == config_before)
        self.assertTrue((self.caller / ".git/index").read_bytes() == index_before)

    def test_all_fixture_suites_fail_closed_when_mktemp_fails(self):
        real_mktemp = shutil.which("mktemp")
        shimdir = self.root / "bin"
        git_called = self.root / "git-called"
        self.executable(shimdir / "git", "#!/bin/sh\n: > " + shlex.quote(str(git_called)) + "\nexit 98\n")
        count = self.root / "allocation-count"
        for allocation in (1, 2):
            for suite in fixture_suites():
                with self.subTest(suite=suite.parent.name, allocation=allocation):
                    count.write_text("0")
                    git_called.unlink(missing_ok=True)
                    self.executable(shimdir / "mktemp", f'''#!/bin/sh
n=$(cat {shlex.quote(str(count))}); n=$((n + 1)); echo "$n" > {shlex.quote(str(count))}
[ "$n" -ne {allocation} ] || exit 73
exec {shlex.quote(real_mktemp)} "$@"
''')
                    before = snapshot(self.caller)
                    p = self.run_cmd(["bash", str(suite)], env=dict(self.env, PATH=str(shimdir) + os.pathsep + self.env["PATH"]))
                    self.assertNotEqual(p.returncode, 0, "suite hid mktemp failure")
                    self.assertIn(b"Git fixture mktemp -d failed", p.stderr, "suite did not use checked allocation")
                    self.assertFalse(git_called.exists(), "Git ran after a failed allocation")
                    self.assert_unchanged(before)

    def test_all_fixture_suites_stop_on_init_failure(self):
        shimdir = self.root / "init-bin"
        marker = self.root / "init-called"
        real_git = shutil.which("git")
        self.executable(shimdir / "git", f'''#!/bin/sh
for arg do
    if [ "$arg" = init ]; then : > {shlex.quote(str(marker))}; exit 73; fi
done
exec {shlex.quote(real_git)} "$@"
''')
        for suite in fixture_suites():
            with self.subTest(suite=suite.parent.name):
                marker.unlink(missing_ok=True)
                before = snapshot(self.caller)
                p = self.run_cmd(["bash", str(suite)], env=dict(self.env, PATH=str(shimdir) + os.pathsep + self.env["PATH"]))
                self.assertTrue(marker.exists(), "fixture did not exercise init failure")
                self.assertNotEqual(p.returncode, 0, "suite hid init failure")
                self.assertIn(b"Git fixture init failed", p.stderr)
                self.assert_unchanged(before)

    def test_mktemp_success_with_empty_or_relative_output_is_rejected(self):
        shimdir = self.root / "empty-bin"
        for output in ("", "."):
            with self.subTest(output=output):
                self.executable(shimdir / "mktemp", "#!/bin/sh\nprintf '%s' " + shlex.quote(output) + "\n")
                p = self.probe(dict(self.env, PATH=str(shimdir) + os.pathsep + self.env["PATH"]))
                self.assertNotEqual(p.returncode, 0)
                self.assertIn(b"invalid directory", p.stderr)

    def test_drift_guard_all_git_fixture_suites_use_common_setup(self):
        suites = list(fixture_suites())
        self.assertGreaterEqual(len(suites), 13, "fixture discovery lost existing consumers")
        for suite in suites:
            with self.subTest(suite=suite.parent.name):
                code = "\n".join(line for line in suite.read_text().splitlines()
                                 if not line.lstrip().startswith("#"))
                self.assertIn("git_fixture_setup", code, "new Git fixture suite bypasses common isolation")
                self.assertIn("git_fixture_init", code, "new Git fixture suite bypasses checked initialization")

    def test_all_fixture_suites_preserve_hostile_disposable_caller(self):
        canary, settings = self.hostile_settings()
        config = self.root / "hostile-config"
        for key, value in settings.items():
            self.git("config", "--file", str(config), key, value)
        xdg_git = self.root / "xdg/git"
        xdg_git.mkdir()
        (xdg_git / "ignore").write_text("*\n")
        (xdg_git / "attributes").write_text("* binary\n")
        nested_tmp = self.caller / "temporary"
        nested_tmp.mkdir()
        env = dict(self.env, TMPDIR=str(nested_tmp), GIT_CONFIG_GLOBAL=str(config),
                   GIT_CONFIG_SYSTEM=str(config), GIT_CONFIG_NOSYSTEM="0",
                   GIT_DIR=str(self.caller / ".git"), GIT_WORK_TREE=str(self.caller),
                   GIT_COMMON_DIR=str(self.caller / ".git"),
                   GIT_INDEX_FILE=str(self.caller / ".git/index"),
                   GIT_OBJECT_DIRECTORY=str(self.caller / ".git/objects"),
                   GIT_TEMPLATE_DIR=settings["init.templateDir"],
                   GIT_CONFIG_COUNT="1", GIT_CONFIG_KEY_0="core.bare", GIT_CONFIG_VALUE_0="true")
        for suite in fixture_suites():
            with self.subTest(suite=suite.parent.name):
                before = snapshot(self.caller)
                p = self.run_cmd(["bash", str(suite)], env=env)
                self.assert_unchanged(before)
                self.assertFalse(canary.exists(), "suite ran an inherited program")
                failed_assertions = "\n".join(line for line in p.stdout.decode(errors="replace").splitlines()
                                              if line.lstrip().startswith(("✗", "FAIL:", "Failed:")))
                self.assertEqual(p.returncode, 0, "suite failed under hostile disposable caller:\n" + failed_assertions)


if __name__ == "__main__":
    unittest.main(verbosity=2)
