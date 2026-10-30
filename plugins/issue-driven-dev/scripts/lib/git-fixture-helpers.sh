#!/usr/bin/env bash
# Test-only Git sandbox (#452). Source, then call git_fixture_setup BEFORE any
# Git command. It changes only this suite's process environment, never the
# invoking shell or its repository. See tests/git-fixture-isolation/README.md.

git_fixture_die() {
  printf 'FATAL: Git fixture %s\n' "$1" >&2
  exit 1
}

git_fixture_clear_environment() {
  # No Git invocation before this loop: even rev-parse can reject malformed
  # GIT_CONFIG_COUNT/PARAMETERS. Clear ALL GIT_* names (including config pairs,
  # templates, trace destinations, identity, object storage and future names).
  # Expand names only; never read or print the caller's values. Bash 3.2-safe.
  local fixture_name
  for fixture_name in ${!GIT_@}; do
    unset "$fixture_name" || git_fixture_die 'cannot clear inherited environment'
  done
}

git_fixture_mktemp() { # [absolute mktemp template]; stdout = existing directory
  local fixture_dir
  if [ "$#" -eq 0 ]; then
    set -- "${IDD_GIT_FIXTURE_ROOT:?call git_fixture_setup first}/repo-XXXXXX"
  fi
  fixture_dir=$(command mktemp -d "$@") || git_fixture_die 'mktemp -d failed'
  case "$fixture_dir" in
    /*) [ "$fixture_dir" != / ] && [ -d "$fixture_dir" ] && [ ! -L "$fixture_dir" ] \
          || git_fixture_die 'mktemp returned an invalid directory' ;;
    *) git_fixture_die 'mktemp returned an invalid directory' ;;
  esac
  (cd -- "$fixture_dir" && pwd -P) || git_fixture_die 'cannot resolve temp directory'
}

git_fixture_cleanup() {
  # setup owns this path; callers must not overwrite it. No global EXIT trap is
  # exported to child shells. A suite with its own trap must call this as well.
  if [ -n "${IDD_GIT_FIXTURE_ROOT:-}" ] && [ -d "$IDD_GIT_FIXTURE_ROOT" ]; then
    chmod -R u+rwX "$IDD_GIT_FIXTURE_ROOT" 2>/dev/null || :
    rm -rf -- "$IDD_GIT_FIXTURE_ROOT"
  fi
}

git_fixture_setup() {
  git_fixture_clear_environment
  IDD_GIT_FIXTURE_ROOT=$(git_fixture_mktemp "${TMPDIR:-/tmp}/idd-git-fixtures-XXXXXX") || exit 1
  trap git_fixture_cleanup EXIT
  # TMPDIR can itself live inside a checkout. A deliberately non-Git fixture
  # must not discover that ancestor repository when Git walks upwards.
  case "$IDD_GIT_FIXTURE_ROOT" in
    *:*) git_fixture_die 'temp path contains the Git ceiling separator' ;;
  esac
  export GIT_CEILING_DIRECTORIES="$IDD_GIT_FIXTURE_ROOT"
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_SYSTEM=/dev/null GIT_ATTR_NOSYSTEM=1
  export GIT_CONFIG_GLOBAL="$IDD_GIT_FIXTURE_ROOT/config"
  export GIT_TEMPLATE_DIR="$IDD_GIT_FIXTURE_ROOT/template"
  mkdir -p -- "$GIT_TEMPLATE_DIR" || git_fixture_die 'cannot create empty template'
  # One private global config covers descendant Git commands, clones and
  # submodules too. Repository-local settings and explicit -c remain available
  # to tests. HOME and the real global/system config files are never changed.
  cat > "$GIT_CONFIG_GLOBAL" <<'CONFIG' || git_fixture_die 'cannot write private config'
[core]
    hooksPath = /dev/null
    fsmonitor = false
    excludesFile = /dev/null
    attributesFile = /dev/null
[commit]
    gpgsign = false
[tag]
    gpgsign = false
[user]
    name = IDD Fixture
    email = fixture@example.invalid
CONFIG
}

git_fixture_init() { # existing directory under sandbox root, then init options
  local fixture_path fixture_gitdir
  [ "$#" -ge 1 ] && [ -n "$1" ] && [ -d "$1" ] \
    || git_fixture_die 'init requires an existing nonempty path'
  fixture_path=$(cd -- "$1" && pwd -P) || git_fixture_die 'cannot resolve init path'
  shift
  case "$fixture_path" in
    "${IDD_GIT_FIXTURE_ROOT:?call git_fixture_setup first}"/*) ;;
    *) git_fixture_die 'init path is outside the sandbox' ;;
  esac
  # Do not reinitialize a checkout or follow a .git symlink/gitfile, including a
  # linked worktree. An ordinary fixture may already contain non-Git files.
  [ ! -e "$fixture_path/.git" ] && [ ! -L "$fixture_path/.git" ] \
    && [ ! -e "$fixture_path/HEAD" ] || git_fixture_die 'init target already has Git metadata'
  git -C "$fixture_path" init "$@" --template= -q || git_fixture_die 'init failed'
  fixture_gitdir=$(git -C "$fixture_path" rev-parse --absolute-git-dir) \
    || git_fixture_die 'cannot resolve initialized Git directory'
  case "$fixture_gitdir" in
    "$fixture_path"|"$fixture_path/.git") ;;
    *) git_fixture_die 'init escaped the requested directory' ;;
  esac
  # An empty template has no info directory; consumers intentionally edit
  # info/exclude. Also retain safe defaults for tests that launch env -i shells.
  mkdir -p -- "$fixture_gitdir/info" || git_fixture_die 'cannot create info directory'
  : > "$fixture_gitdir/info/exclude" || git_fixture_die 'cannot create empty exclude file'
  git -C "$fixture_path" config core.hooksPath /dev/null &&
  git -C "$fixture_path" config core.fsmonitor false &&
  git -C "$fixture_path" config core.excludesFile /dev/null &&
  git -C "$fixture_path" config core.attributesFile /dev/null &&
  git -C "$fixture_path" config commit.gpgsign false &&
  git -C "$fixture_path" config tag.gpgsign false || git_fixture_die 'cannot configure repository'
}
