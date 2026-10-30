"""Regression: a successful helper write must actually hide local IDD config.

Execute both skills' third-party exclude blocks, rather than duplicating their
commands. Reverting either caller to --git-dir must fail the worktree cases.
Only disposable fixtures are read; subprocess output/config contents are never
included in failure diagnostics.
"""

import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest


PLUGIN = Path(__file__).resolve().parents[3]
MARKER = "IDD third-party clone config (#192)"
CONFIG_PATHS = (
    ".claude/.idd/local.json",
    ".claude/issue-driven-dev.local.json",
    ".claude/issue-driven-dev.local.md",
)


class ExcludeCallersTest(unittest.TestCase):
    def run_command(self, args, cwd, expected=0):
        result = subprocess.run(
            args, cwd=cwd, env=self.env, capture_output=True, text=True,
            timeout=30,
        )
        self.assertEqual(result.returncode, expected, "unexpected command exit code")
        return result.stdout.strip()

    def test_skill_exclude_blocks(self):
        for skill in ("idd-issue", "idd-config"):
            source = (PLUGIN / "skills" / skill / "SKILL.md").read_text()
            blocks = [block for block in re.findall(r"```bash\n(.*?)\n```", source, re.S)
                      if "git-ignore-block.sh" in block and MARKER in block]
            self.assertEqual(len(blocks), 1, "expected one third-party exclude block")
            for layout in ("ordinary", "linked", "separate-git-dir"):
                with self.subTest(skill=skill, layout=layout), tempfile.TemporaryDirectory(
                    prefix="idd exclude "
                ) as temporary:
                    root = Path(temporary).resolve()
                    # Drop all inherited Git controls, including indexed config
                    # overrides; never let a test command target its caller (#452).
                    self.env = {key: value for key, value in os.environ.items()
                                if not key.startswith("GIT_") and key not in (
                                    "BASH_ENV", "ENV", "CDPATH", "SHELLOPTS", "BASHOPTS"
                                ) and not key.startswith("BASH_FUNC_")}
                    home = root / "home"
                    home.mkdir()
                    self.env.update(
                        HOME=str(home), XDG_CONFIG_HOME=str(home),
                        GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=os.devnull,
                        GIT_TERMINAL_PROMPT="0", GIT_ATTR_NOSYSTEM="1",
                        GIT_TEMPLATE_DIR=str(home), CLAUDE_PLUGIN_ROOT=str(PLUGIN),
                        LC_ALL="C",
                    )
                    repo = root / "main repo"
                    repo.mkdir()
                    init = ["git", "init", "-q", "-b", "main"]
                    if layout == "separate-git-dir":
                        init += ["--separate-git-dir", str(root / "git data")]
                    self.run_command(init, repo)
                    work = repo
                    if layout == "linked":
                        self.run_command([
                            "git", "-c", "user.name=Fixture", "-c", "user.email=fixture@example.invalid",
                            "commit", "--allow-empty", "-qm", "fixture",
                        ], repo)
                        work = root / "linked worktree"
                        self.run_command(["git", "worktree", "add", "-q", "-b", "fixture", str(work)], repo)
                    exclude = Path(self.run_command(["git", "rev-parse", "--git-path", "info/exclude"], work))
                    if not exclude.is_absolute():
                        exclude = work / exclude
                    exclude.parent.mkdir(parents=True, exist_ok=True)
                    preserved = "# pre-existing user rule\n*.log\n"
                    exclude.write_text(preserved)
                    tracked_ignore = work / ".gitignore"
                    tracked_ignore.write_text("# upstream ignore file\n")
                    for relative in (*CONFIG_PATHS, "debug.log", "visible.txt"):
                        fixture = work / relative
                        fixture.parent.mkdir(parents=True, exist_ok=True)
                        fixture.touch()
                    # Establish a negative control before running the skill.
                    self.run_command(["git", "check-ignore", "-q", CONFIG_PATHS[0]], work, expected=1)
                    self.run_command(["bash", "-eu", "-c", blocks[0]], work)
                    for relative in (*CONFIG_PATHS, "debug.log"):
                        self.run_command(["git", "check-ignore", "-q", relative], work)
                    first = exclude.read_bytes()
                    self.run_command(["bash", "-eu", "-c", blocks[0]], work)
                    self.assertTrue(exclude.read_bytes() == first, "repeat changed the exclude file")
                    self.assertEqual(first.count(("# >>> " + MARKER + " >>>").encode()), 1)
                    self.assertTrue(first.startswith(preserved.encode()), "lost existing user rules")
                    self.run_command(["git", "check-ignore", "-q", "visible.txt"], work, expected=1)
                    self.assertEqual(tracked_ignore.read_text(), "# upstream ignore file\n")
                    status = self.run_command(["git", "status", "--porcelain", "--untracked-files=all"], work)
                    self.assertFalse(".claude/" in status, "local config appears in git status")
                    self.assertIn("?? visible.txt", status)
                    if layout == "linked":
                        admin = Path(self.run_command(["git", "rev-parse", "--git-dir"], work))
                        self.assertFalse((admin / "info" / "exclude").exists(), "wrote an ineffective worktree exclude")
                        # info/exclude is shared by all worktrees of this clone.
                        self.run_command(["git", "check-ignore", "-q", CONFIG_PATHS[0]], repo)


if __name__ == "__main__":
    unittest.main(verbosity=2)
