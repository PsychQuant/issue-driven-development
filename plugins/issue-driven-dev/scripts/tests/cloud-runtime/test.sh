#!/usr/bin/env bash
# Test: the experimental cloud flow (#400, change cloud-idd-runtime-spike).
#
# WHAT IT LOCKS
#
#   1. Secrets never reach output. Both entry points (the Agent SDK runner and
#      the Managed Agents launcher) take --dry-run; with a sentinel standing in
#      for the API key, the sentinel must not appear and `***` must.
#   2. No network and no keychain read in a dry run. `curl` and `security` are
#      stubbed on PATH; each stub records that it ran.
#   3. A missing key fails loudly, before any request.
#   4. The reusable workflow keeps the split "flow in IDD, key in the deployer's
#      repo": its only trigger is workflow_call, it declares and reads only the
#      ANTHROPIC_API_KEY secret, and no run: block interpolates ${{ }} — user
#      text reaches the shell through env only (workflow script injection).
#   5. The caller template passes only that one secret, never `secrets: inherit`,
#      and grants write on contents / issues / pull-requests only.
#
# Needs no network, no real key, and no claude-agent-sdk install, so it runs in CI.
#
# Usage: bash test.sh   (exit 0 = pass, 1 = fail)

set -u
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ROOT="$(cd "$HERE/../../.." && pwd)"
REPO_ROOT="$(cd "$PLUGIN_ROOT/../.." && pwd)"
. "$PLUGIN_ROOT/scripts/lib/assert-helpers.sh"

RUNNER="$PLUGIN_ROOT/cloud/sdk_run.py"
LAUNCHER="$PLUGIN_ROOT/cloud/ma_run.sh"
CALLER="$PLUGIN_ROOT/cloud/caller-example.yml"
WORKFLOW="$REPO_ROOT/.github/workflows/idd-cloud-run.yml"

SENTINEL="SENTINEL-KEY-4f9c2e"
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
STUB="$WORK/bin"; mkdir -p "$STUB"
MARK="$WORK/marks"; mkdir -p "$MARK"

# curl stub: record the call, fail like an unreachable host.
cat > "$STUB/curl" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$MARK/curl"
exit 7
EOF
# security stub: record the call; answer with the sentinel unless told the
# entry is missing (exit 44 is what the real binary returns for "not found").
cat > "$STUB/security" <<EOF
#!/usr/bin/env bash
echo "\$*" >> "$MARK/security"
if [ "\${STUB_SECURITY_MISSING:-}" = 1 ]; then
  echo "security: SecKeychainSearchCopyNext: The specified item could not be found in the keychain." >&2
  exit 44
fi
printf '%s' "$SENTINEL"
EOF
chmod +x "$STUB/curl" "$STUB/security"

PROMPT_FILE="$WORK/prompt.txt"
printf 'run /issue-driven-dev:idd-list\n' > "$PROMPT_FILE"

echo "── files exist ──"
assert_file_exists "runner exists"        "$RUNNER"
assert_file_exists "launcher exists"      "$LAUNCHER"
assert_file_exists "caller template exists" "$CALLER"
assert_file_exists "reusable workflow exists" "$WORKFLOW"

echo "── Agent SDK runner ──"
if [ -f "$RUNNER" ]; then
  OUT="$WORK/runner-dry.out"; ERR="$WORK/runner-dry.err"
  ANTHROPIC_API_KEY="$SENTINEL" PATH="$STUB:$PATH" \
    python3 -I "$RUNNER" --dry-run --prompt "hello" --plugin-dir "$PLUGIN_ROOT" --cwd "$WORK" \
    >"$OUT" 2>"$ERR"; rc=$?
  assert_exit "runner --dry-run exits 0 (no SDK import needed)" 0 "$rc"
  refute_output_grep "runner dry run hides the key (stdout)" "$SENTINEL" "$OUT"
  refute_output_grep "runner dry run hides the key (stderr)" "$SENTINEL" "$ERR"
  assert_output_grep "runner dry run masks the key as ***" "***" "$OUT"
  assert_file_absent "runner dry run makes no curl call" "$MARK/curl"
  # With CLAUDE_CODE_SUBPROCESS_ENV_SCRUB set, Claude Code forces the session to
  # the default permission mode and prints a warning on stderr (sandbox run
  # 38684468139: SESSION_PERMISSION_MODE default, five permission_denied). The
  # runner therefore asks for default openly, pre-approves IDD's tools, grants
  # the plugin directories, and surfaces the CLI's stderr.
  assert_output_grep "runner asks for the default permission mode" "PERMISSION_MODE: default" "$OUT"
  assert_output_grep "runner pre-approves Bash" "ALLOWED_TOOLS: " "$OUT"
  assert_grep_re "allowlist includes Bash, Skill and Workflow" "ALLOWED_TOOLS: .*Bash.*Skill.*Workflow" "$(grep '^ALLOWED_TOOLS: ' "$OUT")"
  # add_dirs made bwrap try to create a protected .mcp.json inside each plugin
  # dir, which is read-only in the sandbox (sandbox run 38685072135). Plugins now
  # live inside the working directory instead, so no extra directory is granted.
  refute_output_grep "runner grants no extra directories" "ADD_DIR:" "$OUT"
  refute_output_grep "runner does not pass add_dirs" "add_dirs=" "$RUNNER"
  assert_output_grep "runner wires the CLI stderr callback" "stderr=" "$RUNNER"

  OUT="$WORK/runner-nokey.out"; ERR="$WORK/runner-nokey.err"
  env -u ANTHROPIC_API_KEY PATH="$STUB:$PATH" \
    python3 -I "$RUNNER" --prompt "hello" --plugin-dir "$PLUGIN_ROOT" --cwd "$WORK" \
    >"$OUT" 2>"$ERR"; rc=$?
  refute "runner without a key exits non-zero" test "$rc" -eq 0
  assert_output_grep "runner names the missing ANTHROPIC_API_KEY" "ANTHROPIC_API_KEY" "$ERR"

  OUT="$WORK/runner-noplugin.out"; ERR="$WORK/runner-noplugin.err"
  ANTHROPIC_API_KEY="$SENTINEL" PATH="$STUB:$PATH" \
    python3 -I "$RUNNER" --dry-run --prompt "hello" --plugin-dir "$WORK/does-not-exist" \
    >"$OUT" 2>"$ERR"; rc=$?
  refute "runner rejects a missing plugin dir" test "$rc" -eq 0
  refute_output_grep "runner error path still hides the key" "$SENTINEL" "$ERR"
fi

echo "── Managed Agents launcher ──"
if [ -f "$LAUNCHER" ]; then
  rm -f "$MARK/curl" "$MARK/security"
  OUT="$WORK/ma-dry.out"; ERR="$WORK/ma-dry.err"
  ANTHROPIC_API_KEY="$SENTINEL" PATH="$STUB:$PATH" \
    bash "$LAUNCHER" --dry-run --prompt-file "$PROMPT_FILE" \
      --target-repo PsychQuant/idd-cloud-sandbox --keychain-account che830621 \
      --github-token-keychain github-pat:idd-cloud-sandbox \
    >"$OUT" 2>"$ERR"; rc=$?
  assert_exit "launcher --dry-run exits 0" 0 "$rc"
  refute_output_grep "launcher dry run hides the key (stdout)" "$SENTINEL" "$OUT"
  refute_output_grep "launcher dry run hides the key (stderr)" "$SENTINEL" "$ERR"
  assert_output_grep "launcher dry run masks secrets as ***" "***" "$OUT"
  assert_output_grep "launcher dry run shows the session request" "/v1/sessions" "$OUT"
  assert_file_absent "launcher dry run makes no curl call" "$MARK/curl"
  assert_file_absent "launcher dry run does not read the keychain" "$MARK/security"

  rm -f "$MARK/curl" "$MARK/security"
  OUT="$WORK/ma-nokey.out"; ERR="$WORK/ma-nokey.err"
  STUB_SECURITY_MISSING=1 PATH="$STUB:$PATH" \
    bash "$LAUNCHER" --prompt-file "$PROMPT_FILE" \
      --target-repo PsychQuant/idd-cloud-sandbox --keychain-account che830621 \
      --github-token-keychain github-pat:idd-cloud-sandbox \
    >"$OUT" 2>"$ERR"; rc=$?
  refute "launcher without a key exits non-zero" test "$rc" -eq 0
  assert_output_grep "launcher names the missing keychain entry" "anthropic-api" "$ERR"
  assert_file_absent "launcher without a key sends no request" "$MARK/curl"

  rm -f "$MARK/curl" "$MARK/security"
  OUT="$WORK/ma-idd.out"; ERR="$WORK/ma-idd.err"
  PATH="$STUB:$PATH" \
    bash "$LAUNCHER" --dry-run --prompt-file "$PROMPT_FILE" \
      --target-repo PsychQuant/issue-driven-development --keychain-account che830621 \
      --github-token-keychain github-pat:idd-cloud-sandbox \
    >"$OUT" 2>"$ERR"; rc=$?
  refute "launcher refuses the IDD repo as a target" test "$rc" -eq 0
  assert_file_absent "refused target sends no request" "$MARK/curl"
fi

echo "── reusable workflow ──"
if [ -f "$WORKFLOW" ]; then
  REPORT="$WORK/workflow-check.txt"
  python3 -I - "$WORKFLOW" >"$REPORT" 2>&1 <<'PY'
import re, sys
lines = open(sys.argv[1], encoding="utf-8").read().splitlines()
def indent(s): return len(s) - len(s.lstrip(" "))
# 1. top-level `on:` children
on_idx = next((i for i, l in enumerate(lines) if re.match(r"^on:\s*$", l)), None)
triggers = []
if on_idx is not None:
    for l in lines[on_idx + 1:]:
        if l.strip() == "" or l.lstrip().startswith("#"): continue
        if indent(l) == 0: break
        if indent(l) == 2: triggers.append(l.strip().rstrip(":").split(":")[0])
print("TRIGGERS=" + ",".join(triggers))
# 2. every secrets.X reference
refs = sorted(set(re.findall(r"secrets\.([A-Za-z0-9_]+)", "\n".join(lines))))
print("SECRET_REFS=" + ",".join(refs))
# 3. declared workflow_call secrets
decl, in_secrets, base = [], False, None
for l in lines:
    if re.match(r"^\s+secrets:\s*$", l) and indent(l) == 4:
        in_secrets, base = True, indent(l); continue
    if in_secrets:
        if l.strip() == "" or l.lstrip().startswith("#"): continue
        if indent(l) <= base: in_secrets = False; continue
        if indent(l) == base + 2: decl.append(l.strip().rstrip(":"))
print("SECRET_DECL=" + ",".join(decl))
# 4. ${{ }} inside run: blocks (single-line or block scalar)
bad, in_run, run_indent = [], False, None
for n, l in enumerate(lines, 1):
    m = re.match(r"^(\s*)(-\s+)?run:\s*(.*)$", l)
    if m:
        rest = m.group(3)
        if rest in ("|", ">", "|-", ">-", "|+", ">+"):
            in_run, run_indent = True, len(m.group(1)) + (len(m.group(2)) if m.group(2) else 0)
        else:
            in_run = False
            if "${{" in rest: bad.append(n)
        continue
    if in_run:
        if l.strip() == "": continue
        if indent(l) <= run_indent: in_run = False
        elif "${{" in l: bad.append(n)
print("RUN_INTERPOLATION_LINES=" + ",".join(map(str, bad)))
PY
  assert_output_grep "workflow trigger is workflow_call only" "TRIGGERS=workflow_call" "$REPORT"
  refute_grep_re  "workflow has no other trigger" "TRIGGERS=.*,"  "$(grep '^TRIGGERS=' "$REPORT")"
  # Two secrets, no more: the API key, and an optional fine-grained PAT for orgs
  # that forbid GitHub Actions from opening pull requests (PsychQuant does; sandbox
  # run 38685626718: "GitHub Actions is not permitted to create or approve pull
  # requests"). Without the PAT the run falls back to the job's GITHUB_TOKEN.
  assert_output_grep "workflow reads exactly the two allowed secrets" "SECRET_REFS=ANTHROPIC_API_KEY,IDD_GITHUB_TOKEN" "$REPORT"
  refute_grep_re  "workflow reads no third secret" "SECRET_REFS=([^,]*,){2}"  "$(grep '^SECRET_REFS=' "$REPORT")"
  assert_output_grep "workflow declares exactly the two allowed secrets" "SECRET_DECL=ANTHROPIC_API_KEY,IDD_GITHUB_TOKEN" "$REPORT"
  refute_grep_re  "workflow declares no third secret" "SECRET_DECL=([^,]*,){2}"  "$(grep '^SECRET_DECL=' "$REPORT")"
  assert_output_grep "GH_TOKEN falls back to the job token" 'GH_TOKEN: ${{ secrets.IDD_GITHUB_TOKEN || github.token }}' "$WORKFLOW"
  assert_grep_re "the PAT secret is optional" "IDD_GITHUB_TOKEN:" "$(cat "$WORKFLOW")"
  # The Bash sandbox leaves empty placeholders in the working directory (sandbox
  # runs 38685626718 and 38706723482). An untracked one dirties the tree, which
  # PR mode refuses, and `git add -A` would commit it. Each name is excluded only
  # when the repo did not already have it at checkout, so a real scripts/ stays.
  PH_LINE=$(grep -E '^[[:space:]]+SANDBOX_PLACEHOLDERS=' "$WORKFLOW" | head -1)
  for f in .bashrc .bash_profile .profile .zshrc .zprofile .gitconfig .ripgreprc .mcp.json .idea .vscode scripts; do
    assert_grep "sandbox placeholder $f is on the exclude list" " $f" "$PH_LINE "
  done
  assert_output_grep "placeholders are excluded only when absent at checkout" '[ -e "$GITHUB_WORKSPACE/$p" ] ||' "$WORKFLOW"
  assert_output_grep "no \${{ }} inside run: blocks" "RUN_INTERPOLATION_LINES=" "$REPORT"
  refute_grep_re  "run: blocks are free of \${{ }}" "RUN_INTERPOLATION_LINES=[0-9]" "$(grep '^RUN_INTERPOLATION_LINES=' "$REPORT")"
  assert_output_grep "prompt reaches the runner through env" "IDD_PROMPT" "$WORKFLOW"
  # Prompt injection could make the agent print its environment. The scrub takes
  # ANTHROPIC_API_KEY out of every Bash / hook / MCP subprocess Claude Code starts.
  assert_output_grep "subprocess env scrub is on" 'CLAUDE_CODE_SUBPROCESS_ENV_SCRUB: "1"' "$WORKFLOW"
  # On Linux the scrub needs bubblewrap; without it the CLI exits at startup
  # (first real run, workflow run 38683885702). It must be installed in a step
  # that does not hold the key.
  # ralph-loop drives idd-all's (PR, unattended) verify-fix loop; without it
  # idd-all degrades to direct-commit + attended (Step 0.6).
  for dep in issue-driven-dev superpowers parallel-ai-agents codex-pro ralph-loop; do
    assert_grep_re "workflow loads $dep from inside the workspace" "--plugin-dir \"\\\$GITHUB_WORKSPACE/\\.idd-cloud/plugins/$dep\"" "$(cat "$WORKFLOW")"
  done
  assert_output_grep "the plugin copies are excluded from the caller's git" ".git/info/exclude" "$WORKFLOW"
  # The Bash sandbox also needs socat (sandbox run 38684924067: "Sandbox
  # dependencies not available: socat not installed").
  # IDD's presence pre-flight only reads the install cache; the workflow loads
  # every dependency itself (LOADED_PLUGINS in each run), so the check is skipped
  # on purpose. C1 records the gap; the real fix is a path-aware check.
  assert_output_grep "presence pre-flight is skipped on purpose" 'IDD_SKIP_PLUGIN_CHECK: "1"' "$WORKFLOW"
  assert_output_grep "bubblewrap and socat are installed for the sandbox" "apt-get install -y bubblewrap socat" "$WORKFLOW"
  BWRAP_LINE=$(grep -n "apt-get install -y bubblewrap socat" "$WORKFLOW" | head -1 | cut -d: -f1)
  KEY_LINE=$(grep -n 'ANTHROPIC_API_KEY: \${{ secrets.ANTHROPIC_API_KEY }}' "$WORKFLOW" | head -1 | cut -d: -f1)
  assert_true "bubblewrap is installed before the key appears" "[ -n '$BWRAP_LINE' ] && [ -n '$KEY_LINE' ] && [ '$BWRAP_LINE' -lt '$KEY_LINE' ]"
  # Code fetched by tag or branch can change under us and then runs in the job
  # that holds the key. Every action and every plugin ref must be a commit SHA.
  UNPINNED=$(grep -E '^[[:space:]]*(-[[:space:]]+)?uses:' "$WORKFLOW" | grep -vE '@[0-9a-f]{40}([[:space:]]|$)' || true)
  assert_eq "every uses: is pinned to a commit SHA" "" "$UNPINNED"
  # IDD's plugin.json declares three dependencies; a missing one stops IDD from
  # loading at all (dependency-unsatisfied, workflow run 38684015025).
  for ref in SUPERPOWERS_REF PAI_REF CODEX_PRO_REF CLAUDE_PLUGINS_OFFICIAL_REF; do
    assert_grep_re "$ref is a commit SHA" "^[[:space:]]+$ref: [0-9a-f]{40}[[:space:]]*$" "$(grep -E "^[[:space:]]+$ref:" "$WORKFLOW")"
  done
fi

echo "── caller template ──"
if [ -f "$CALLER" ]; then
  refute_output_grep "caller does not use secrets: inherit" "secrets: inherit" "$CALLER"
  assert_output_grep "caller calls the IDD reusable workflow" \
    "uses: PsychQuant/issue-driven-development/.github/workflows/idd-cloud-run.yml@" "$CALLER"
  assert_output_grep "caller passes ANTHROPIC_API_KEY explicitly" \
    "ANTHROPIC_API_KEY: \${{ secrets.ANTHROPIC_API_KEY }}" "$CALLER"
  assert_output_grep "caller passes the optional PAT explicitly" \
    "IDD_GITHUB_TOKEN: \${{ secrets.IDD_GITHUB_TOKEN }}" "$CALLER"
  # POSIX classes, not \s: BSD sed on macOS treats \s as a literal 's'.
  WRITES=$(grep -E '^[[:space:]]+[a-z-]+:[[:space:]]*write[[:space:]]*$' "$CALLER" \
    | sed -E 's/^[[:space:]]+//; s/:.*//' | sort | tr '\n' ',')
  assert_eq "caller grants write on exactly contents, issues, pull-requests" \
    "contents,issues,pull-requests," "$WRITES"
fi

print_summary "cloud-runtime"
