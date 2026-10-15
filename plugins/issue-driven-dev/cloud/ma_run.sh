#!/usr/bin/env bash
# ma_run.sh — run the issue-driven-dev workflow on Claude Managed Agents
# (EXPERIMENTAL, PsychQuant/issue-driven-development#400, change
# cloud-idd-runtime-spike). The interface may change or disappear.
#
# What it does, one Claude API request per step (beta managed-agents-2026-04-01):
#   1. POST /v1/environments              cloud sandbox, limited networking
#                                         (GitHub + package registries), apt gh
#   2. POST /v1/agents                    agent_toolset_20260401 and a system
#                                         prompt telling the agent to run an IDD
#                                         skill by reading its SKILL.md: Managed
#                                         Agents only discovers <repo>/.claude/
#                                         skills, and IDD keeps its skills under
#                                         plugins/issue-driven-dev/skills
#   3. POST /v1/vaults                    a vault for this run
#   4. POST /v1/vaults/{id}/credentials   the GitHub PAT as environment_variable
#                                         GH_TOKEN (substituted at egress, header
#                                         only, api.github.com and github.com)
#   5. POST /v1/sessions                  mounts the target repo and the IDD repo
#                                         (plugin source, read-only by instruction)
#                                         as github_repository resources, sets a
#                                         budget, and starts the run with the
#                                         prompt file as the initial user.message
# Then it polls GET /v1/sessions/{id} until the status is idle or terminated
# (bounded by --max-wait-minutes; past that it sends user.interrupt), prints the
# session id, stop reason and usage, and archives the vault, which purges the PAT
# on Anthropic's side.
#
# Secrets: the API key comes from the macOS keychain (service anthropic-api,
# account --keychain-account) and reaches curl only on stdin (-H @-). The PAT
# comes from the keychain entry named by --github-token-keychain and reaches the
# request bodies through jq's stdin. Neither is put on a command line, written to
# a file, or printed. --dry-run reads no keychain, sends nothing, and prints every
# request with each secret shown as ***.
#
# Writes are for a sandbox only: --target-repo PsychQuant/issue-driven-development
# is refused before anything else happens.
#
# Usage:
#   bash ma_run.sh --dry-run --prompt-file prompt.txt \
#     --target-repo PsychQuant/idd-cloud-sandbox --keychain-account che830621 \
#     --github-token-keychain github-pat:idd-cloud-sandbox
#   Drop --dry-run to send the requests. --help lists the optional flags.
#
# Requires: bash (3.2 is enough), jq; curl and macOS `security` for a real run.
# Exit codes: 0 session idle with stop reason end_turn; 1 HTTP or curl error, or
# the session terminated; 2 bad arguments, refused target, missing tool or
# keychain entry; 3 session idle for another reason (budget_reached,
# requires_action); 4 --max-wait-minutes exceeded.
#
# Field names follow the Managed Agents docs under
# https://platform.claude.com/docs/en/managed-agents/ (environments, agent-setup,
# tools, vaults, github, sessions, budgets, events-and-streaming,
# session-operations, reference). What the docs do not show is marked
# TODO(spike), for the spike to find out at run time and record in findings.md.

set -euo pipefail

readonly PROG="ma_run.sh"
readonly API_BASE="https://api.anthropic.com"
readonly ANTHROPIC_VERSION="2023-06-01"
readonly BETA_HEADER="managed-agents-2026-04-01"
readonly IDD_REPO="PsychQuant/issue-driven-development"
readonly KEY_SERVICE="anthropic-api"
readonly TARGET_MOUNT="/workspace/target"
readonly IDD_MOUNT="/workspace/idd"
readonly GITHUB_HOSTS='["github.com", "api.github.com"]'

PROMPT_FILE=""; TARGET_REPO=""; KEY_ACCOUNT=""; PAT_LOCATION=""
DRY_RUN=0; MODEL="claude-sonnet-5-5"; IDD_REF="main"; BUDGET_CENTS=500
MAX_WAIT_MIN=60; POLL_SECONDS=15; EVENTS_OUT=""

API_KEY=""; GH_TOKEN_VALUE=""; RESP_BODY=""; API_SOFT=0; EVENTS_JSON="[]"
VAULT_ID=""; VAULT_ARCHIVED=0; SESSION_ID=""; SESSION_DONE=0
SESSION_STATUS=""; SESSION_JSON="{}"
RUN_STAMP=""; SYSTEM_PROMPT=""

die() { local code=$1; shift; printf '%s: %s\n' "$PROG" "$*" >&2; exit "$code"; }
log() { printf '[%s] %s\n' "$(date '+%H:%M:%S%z')" "$*" >&2; }

usage() {
  cat <<'EOF'
Usage: ma_run.sh --prompt-file PATH --target-repo OWNER/REPO
                 --keychain-account NAME --github-token-keychain SERVICE:ACCOUNT
                 [--dry-run] [--model ID] [--idd-ref BRANCH|SHA]
                 [--budget-cents N] [--max-wait-minutes N] [--poll-seconds N]
                 [--events-out FILE]

  --prompt-file PATH          first user message (for example: run /issue-driven-dev:idd-list)
  --target-repo OWNER/REPO    repository the run may write to; never PsychQuant/issue-driven-development
  --keychain-account NAME     account of the keychain entry (service anthropic-api) holding the API key
  --github-token-keychain S:A keychain service and account holding a fine-grained PAT for the target repo
  --dry-run                   print the requests (secrets as ***); read no keychain, send nothing
  --model ID                  agent model (default claude-sonnet-5-5)
  --idd-ref REF               IDD branch name or full 40-char commit SHA to mount (default main)
  --budget-cents N            session budget, whole US cents (default 500 = $5.00)
  --max-wait-minutes N        stop waiting and interrupt the session after N minutes (default 60)
  --poll-seconds N            seconds between status polls (default 15)
  --events-out FILE           also save the session's full event history (JSON) to FILE
EOF
}

need_value() { [ "$#" -ge 2 ] || die 2 "$1 needs a value (see --help)"; }

parse_args() {
  while [ "$#" -gt 0 ]; do
    case $1 in
      --prompt-file)           need_value "$@"; PROMPT_FILE=$2; shift 2 ;;
      --target-repo)           need_value "$@"; TARGET_REPO=$2; shift 2 ;;
      --keychain-account)      need_value "$@"; KEY_ACCOUNT=$2; shift 2 ;;
      --github-token-keychain) need_value "$@"; PAT_LOCATION=$2; shift 2 ;;
      --model)                 need_value "$@"; MODEL=$2; shift 2 ;;
      --idd-ref)               need_value "$@"; IDD_REF=$2; shift 2 ;;
      --budget-cents)          need_value "$@"; BUDGET_CENTS=$2; shift 2 ;;
      --max-wait-minutes)      need_value "$@"; MAX_WAIT_MIN=$2; shift 2 ;;
      --poll-seconds)          need_value "$@"; POLL_SECONDS=$2; shift 2 ;;
      --events-out)            need_value "$@"; EVENTS_OUT=$2; shift 2 ;;
      --dry-run)               DRY_RUN=1; shift ;;
      -h|--help)               usage; exit 0 ;;
      *)                       die 2 "unknown argument: $1 (see --help)" ;;
    esac
  done
}

lower() { printf '%s' "$1" | tr '[:upper:]' '[:lower:]'; }
matches() { [[ $1 =~ $2 ]]; }

validate_args() {
  local missing=""
  [ -n "$PROMPT_FILE" ]  || missing="$missing --prompt-file"
  [ -n "$TARGET_REPO" ]  || missing="$missing --target-repo"
  [ -n "$KEY_ACCOUNT" ]  || missing="$missing --keychain-account"
  [ -n "$PAT_LOCATION" ] || missing="$missing --github-token-keychain"
  [ -z "$missing" ] || die 2 "missing required argument(s):$missing (see --help)"

  matches "$TARGET_REPO" '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' \
    || die 2 "--target-repo must be OWNER/REPO, got: $TARGET_REPO"
  case $TARGET_REPO in *.git) die 2 "--target-repo takes OWNER/REPO without .git" ;; esac
  if [ "$(lower "$TARGET_REPO")" = "$(lower "$IDD_REPO")" ]; then
    die 2 "refusing --target-repo $TARGET_REPO: the run writes to GitHub, and the target must be the sandbox repository (for example PsychQuant/idd-cloud-sandbox), never $IDD_REPO"
  fi

  [ -f "$PROMPT_FILE" ] && [ -r "$PROMPT_FILE" ] || die 2 "--prompt-file not found or unreadable: $PROMPT_FILE"
  [ -s "$PROMPT_FILE" ] || die 2 "--prompt-file is empty: $PROMPT_FILE"

  case $PAT_LOCATION in
    ?*:?*) ;;
    *) die 2 "--github-token-keychain must be SERVICE:ACCOUNT, got: $PAT_LOCATION" ;;
  esac
  local n
  for n in "$BUDGET_CENTS" "$MAX_WAIT_MIN" "$POLL_SECONDS"; do
    matches "$n" '^[1-9][0-9]*$' || die 2 "expected a positive whole number, got: $n"
  done
  matches "$MODEL" '^[A-Za-z0-9._-]+$' || die 2 "--model has unexpected characters: $MODEL"
  matches "$IDD_REF" '^[A-Za-z0-9._/-]+$' || die 2 "--idd-ref has unexpected characters: $IDD_REF"
  if [ -n "$EVENTS_OUT" ]; then
    [ -d "$(dirname -- "$EVENTS_OUT")" ] || die 2 "--events-out directory does not exist: $EVENTS_OUT"
  fi
}

check_tools() {
  command -v jq >/dev/null 2>&1 || die 2 "jq is required (brew install jq)"
  [ "$DRY_RUN" = 1 ] && return 0
  command -v curl >/dev/null 2>&1 || die 2 "curl is required"
  command -v security >/dev/null 2>&1 || die 2 "the macOS 'security' command is required to read the keychain"
}

# ── the agent's system prompt ──
build_system_prompt() {
  local t
  IFS= read -r -d '' t <<'EOF' || true
You are running the issue-driven-dev (IDD) workflow unattended on Claude Managed Agents. This is an experimental spike (PsychQuant/issue-driven-development#400): report what works and what does not, quoting errors verbatim, instead of working around gaps silently.

Workspace
- @TARGET_MOUNT@ is a clone of @TARGET_REPO@. It is the only repository you may write to: issue comments, branches, pushes, pull requests and merges go to @TARGET_REPO@ and nowhere else. Run git and gh from inside @TARGET_MOUNT@.
- @IDD_MOUNT@ is a read-only copy of the IDD plugin source, PsychQuant/issue-driven-development at @IDD_REF@. Never commit, push, open issues or pull requests, or comment on PsychQuant/issue-driven-development.

Plugin root
- Before running any plugin script, run: export CLAUDE_PLUGIN_ROOT=@IDD_MOUNT@/plugins/issue-driven-dev
- Wherever a skill writes $CLAUDE_PLUGIN_ROOT or ${CLAUDE_PLUGIN_ROOT}, it means that path. If the variable does not survive from one bash call to the next, set it again in each call and report that it did not survive.

Running a skill
- A request such as /issue-driven-dev:idd-list means: read @IDD_MOUNT@/plugins/issue-driven-dev/skills/idd-list/SKILL.md and follow it step by step. When a skill tells you to run another skill, read that skill's SKILL.md the same way. Paths a skill gives relative to the plugin (references/, scripts/, rules/) are relative to $CLAUDE_PLUGIN_ROOT.
- The superpowers and parallel-ai-agents plugins are not mounted. If a skill's pre-flight checks for them, run the check and report its output verbatim.

Tools that do not exist here
- You have bash, read, write, edit, glob, grep, web_fetch and web_search. The Claude Code tools Skill, AskUserQuestion, TaskCreate/TaskUpdate/TaskList, Agent (subagents) and Workflow are not available, and plugin hooks (such as SessionStart) are not run by this runtime as far as its documentation says.
- Treat the run as unattended. Where a skill would ask the user, take the skill's documented unattended or default path. If it has none, do not guess an answer: stop that step and record it. Never weaken a gate silently.
- Record every step you could not perform the way the skill describes as a degraded step: skill, step, what was skipped or substituted, and why.

GitHub CLI
- gh may already be installed from the environment's apt packages; check with gh --version. If it is missing or does not work, download the official release tarball from https://github.com/cli/cli/releases/latest (the linux build matching uname -m), put gh on PATH, and report which route worked and the gh version.
- GH_TOKEN comes from a vault. Inside the sandbox it holds a placeholder that is replaced with the real token only in request headers sent to api.github.com and github.com. Never print it. If gh or git rejects it, record the exact error, then try the GitHub REST API with curl -H "Authorization: Bearer $GH_TOKEN" and record that result too.

Final report
- End with one message that has these sections: Result (what the requested skill produced); Tools (the name of every tool you have in this session); Degraded steps; Errors (verbatim error text, if any).
EOF
  t=${t//@TARGET_MOUNT@/$TARGET_MOUNT}
  t=${t//@TARGET_REPO@/$TARGET_REPO}
  t=${t//@IDD_MOUNT@/$IDD_MOUNT}
  t=${t//@IDD_REF@/$IDD_REF}
  SYSTEM_PROMPT=$t
}

# ── request bodies (secrets arrive on stdin, never as arguments) ──
env_body() {
  jq -n --arg name "idd-cloud-$RUN_STAMP" --argjson hosts "$GITHUB_HOSTS" '{
    name: $name,
    config: {
      type: "cloud",
      packages: {apt: ["gh"]},
      networking: {type: "limited", allowed_hosts: $hosts, allow_package_managers: true}
    }
  }'
}

agent_body() {
  jq -n --arg model "$MODEL" --arg system "$SYSTEM_PROMPT" --arg target "$TARGET_REPO" '{
    name: "idd-cloud-runner",
    description: "Runs issue-driven-dev skills by reading their SKILL.md (experimental, issue-driven-development#400)",
    model: $model,
    system: $system,
    tools: [{type: "agent_toolset_20260401"}],
    metadata: {source: "PsychQuant/issue-driven-development#400", target_repo: $target}
  }'
}

vault_body() {
  jq -n --arg name "idd-cloud $TARGET_REPO $RUN_STAMP" \
    '{display_name: $name, metadata: {source: "PsychQuant/issue-driven-development#400"}}'
}

credential_body() { # stdin: the GitHub token
  jq -Rs --arg target "$TARGET_REPO" --argjson hosts "$GITHUB_HOSTS" '{
    display_name: ("GitHub token for " + $target),
    auth: {
      type: "environment_variable",
      secret_name: "GH_TOKEN",
      secret_value: .,
      networking: {type: "limited", allowed_hosts: $hosts},
      injection_location: {header: true}
    }
  }'
}

session_body() { # args: environment_id agent_id vault_id; stdin: the GitHub token
  local checkout
  if matches "$IDD_REF" '^[0-9a-f]{40}$'; then
    checkout=$(jq -n --arg sha "$IDD_REF" '{type: "commit", sha: $sha}')
  else
    checkout=$(jq -n --arg name "$IDD_REF" '{type: "branch", name: $name}')
  fi
  jq -Rs --arg env "$1" --arg agent "$2" --arg vault "$3" \
    --arg target "$TARGET_REPO" --arg idd "$IDD_REPO" \
    --arg tmount "$TARGET_MOUNT" --arg imount "$IDD_MOUNT" \
    --argjson checkout "$checkout" --arg cents "$BUDGET_CENTS" \
    --arg title "IDD cloud run on $TARGET_REPO ($RUN_STAMP)" \
    --rawfile prompt "$PROMPT_FILE" '. as $token | {
    agent: $agent,
    environment_id: $env,
    title: $title,
    vault_ids: [$vault],
    budget: {type: "limit", max_list_cost: {amount: $cents, currency: "USD"}},
    resources: [
      {type: "github_repository", url: ("https://github.com/" + $target),
       mount_path: $tmount, authorization_token: $token},
      {type: "github_repository", url: ("https://github.com/" + $idd),
       mount_path: $imount, authorization_token: $token, checkout: $checkout}
    ],
    initial_events: [{type: "user.message", content: [{type: "text", text: $prompt}]}]
  }'
}

# ── output helpers ──
mask() { # print $1 with every known secret replaced by ***
  local s=$1
  if [ -n "$API_KEY" ]; then s=${s//"$API_KEY"/***}; fi
  if [ -n "$GH_TOKEN_VALUE" ]; then s=${s//"$GH_TOKEN_VALUE"/***}; fi
  printf '%s\n' "$s"
}

jget() { printf '%s' "$RESP_BODY" | jq -r "$1"; }

show_request() { # label method path [body]
  printf '\n### %s\n%s %s%s\n' "$1" "$2" "$API_BASE" "$3"
  printf 'x-api-key: ***\nanthropic-version: %s\nanthropic-beta: %s\n' "$ANTHROPIC_VERSION" "$BETA_HEADER"
  if [ -n "${4-}" ]; then printf 'content-type: application/json\n\n%s\n' "$4"; fi
}

# ── HTTP ──
# Sets RESP_BODY. On a curl failure or a non-2xx status it prints the status and
# the masked body to stderr, then exits 1 (or returns 1 when API_SOFT=1).
api() { # method path [body]
  local method=$1 path=$2 body=${3-} out code rc=0
  local -a args=(-sS -g --proto '=https' --max-time 120 -X "$method" -H @-
    -H "anthropic-version: $ANTHROPIC_VERSION" -H "anthropic-beta: $BETA_HEADER"
    -w '\n%{http_code}')
  # Retry transient failures on reads only; a retried create could duplicate it.
  if [ "$method" = GET ]; then args+=(--retry 3 --retry-delay 2); fi
  if [ -n "$body" ]; then
    out=$(printf 'x-api-key: %s\n' "$API_KEY" | curl "${args[@]}" \
      -H 'content-type: application/json' --data-binary @<(printf '%s' "$body") \
      "$API_BASE$path") || rc=$?
  else
    out=$(printf 'x-api-key: %s\n' "$API_KEY" | curl "${args[@]}" "$API_BASE$path") || rc=$?
  fi
  if [ "$rc" -ne 0 ]; then
    printf '%s: curl failed (exit %s) on %s %s\n' "$PROG" "$rc" "$method" "$path" >&2
    if [ "$API_SOFT" = 1 ]; then return 1; fi
    exit 1
  fi
  code=${out##*$'\n'}
  RESP_BODY=${out%$'\n'*}
  case $code in
    2??) return 0 ;;
  esac
  printf '%s: HTTP %s on %s %s\n' "$PROG" "$code" "$method" "$path" >&2
  mask "$RESP_BODY" >&2
  if [ "$API_SOFT" = 1 ]; then return 1; fi
  exit 1
}

created_id() { # label → prints the id from RESP_BODY, or exits 1
  local id
  id=$(jget '.id // empty')
  [ -n "$id" ] || { mask "$RESP_BODY" >&2; die 1 "no id in the $1 response"; }
  printf '%s' "$id"
}

# Sets EVENTS_JSON to every event of the session matching the extra query
# (for example '&types[]=agent.message'), following next_page.
list_events() {
  local query=$1 page="" pages=0 path
  EVENTS_JSON="[]"
  while :; do
    path="/v1/sessions/$SESSION_ID/events?beta=true$query"
    if [ -n "$page" ]; then path="$path&page=$(printf '%s' "$page" | jq -sRr @uri)"; fi
    api GET "$path"
    EVENTS_JSON=$({ printf '%s\n' "$EVENTS_JSON"; printf '%s' "$RESP_BODY"; } \
      | jq -cs '.[0] + (.[1].data // [])')
    page=$(jget '.next_page // empty')
    pages=$((pages + 1))
    if [ -z "$page" ] || [ "$pages" -ge 1000 ]; then break; fi
  done
}

# ── keychain ──
read_secrets() {
  local svc=${PAT_LOCATION%%:*} acct=${PAT_LOCATION#*:}
  API_KEY=$(security find-generic-password -s "$KEY_SERVICE" -a "$KEY_ACCOUNT" -w 2>/dev/null) \
    && [ -n "$API_KEY" ] \
    || die 2 "cannot read the API key from the keychain entry service '$KEY_SERVICE', account '$KEY_ACCOUNT' (add it with: security add-generic-password -s $KEY_SERVICE -a $KEY_ACCOUNT -w); no request was sent"
  GH_TOKEN_VALUE=$(security find-generic-password -s "$svc" -a "$acct" -w 2>/dev/null) \
    && [ -n "$GH_TOKEN_VALUE" ] \
    || die 2 "cannot read the GitHub token from the keychain entry service '$svc', account '$acct'; no request was sent"
}

# ── dry run ──
dry_run() {
  local body
  printf 'DRY RUN: the keychain is not read and nothing is sent. Secrets are shown as ***.\n'
  printf 'target %s, IDD %s@%s, model %s, budget %s cents, wait at most %s min\n' \
    "$TARGET_REPO" "$IDD_REPO" "$IDD_REF" "$MODEL" "$BUDGET_CENTS" "$MAX_WAIT_MIN"
  body=$(env_body);   show_request "[1/5] create environment" POST /v1/environments "$body"
  body=$(agent_body); show_request "[2/5] create agent" POST /v1/agents "$body"
  printf -- '--- system prompt, as text ---\n%s--- end of system prompt ---\n' "$SYSTEM_PROMPT"
  body=$(vault_body); show_request "[3/5] create vault" POST /v1/vaults "$body"
  body=$(printf '%s' '***' | credential_body)
  show_request "[4/5] add the GitHub token to the vault" POST "/v1/vaults/<vault_id>/credentials" "$body"
  body=$(printf '%s' '***' | session_body '<environment_id>' '<agent_id>' '<vault_id>')
  show_request "[5/5] create session (starts the run)" POST /v1/sessions "$body"
  printf '\n### then\n'
  printf 'GET %s/v1/sessions/<session_id>  every %ss, at most %s min, until .status is idle or terminated\n' \
    "$API_BASE" "$POLL_SECONDS" "$MAX_WAIT_MIN"
  printf 'GET %s/v1/sessions/<session_id>/events?beta=true&types[]=session.status_idle  (stop reason)\n' "$API_BASE"
  printf 'GET %s/v1/sessions/<session_id>/events?beta=true&types[]=agent.message  (final message)\n' "$API_BASE"
  printf 'POST %s/v1/sessions/<session_id>/events  {"events":[{"type":"user.interrupt"}]}  (only past the wait limit)\n' "$API_BASE"
  printf 'POST %s/v1/vaults/<vault_id>/archive  (purges the stored token)\n' "$API_BASE"
}

# ── real run ──
on_exit() {
  local rc=$?
  API_SOFT=1
  if [ -n "$SESSION_ID" ] && [ "$SESSION_DONE" = 0 ]; then
    log "sending user.interrupt to $SESSION_ID"
    api POST "/v1/sessions/$SESSION_ID/events" '{"events":[{"type":"user.interrupt"}]}' \
      || log "interrupt failed; the session may still be running"
  fi
  if [ -n "$VAULT_ID" ] && [ "$VAULT_ARCHIVED" = 0 ]; then
    if api POST "/v1/vaults/$VAULT_ID/archive"; then
      VAULT_ARCHIVED=1; log "archived vault $VAULT_ID (stored token purged)"
    else
      log "could not archive vault $VAULT_ID; archive it by hand to purge the token"
    fi
  fi
  exit "$rc"
}

create_resources() {
  local body env_id agent_id
  body=$(env_body); api POST /v1/environments "$body"
  env_id=$(created_id environment); printf 'environment_id=%s\n' "$env_id"
  # TODO(spike): no environment field for plain environment variables is
  # documented, so CLAUDE_PLUGIN_ROOT is set by the system prompt instead.
  body=$(agent_body); api POST /v1/agents "$body"
  agent_id=$(created_id agent); printf 'agent_id=%s\n' "$agent_id"
  body=$(vault_body); api POST /v1/vaults "$body"
  VAULT_ID=$(created_id vault); printf 'vault_id=%s\n' "$VAULT_ID"
  # TODO(spike): whether gh accepts the vault placeholder in GH_TOKEN, and
  # whether git push authenticates through the github_repository resource's
  # token (the docs only say it is used to clone).
  body=$(printf '%s' "$GH_TOKEN_VALUE" | credential_body)
  api POST "/v1/vaults/$VAULT_ID/credentials" "$body"
  body=$(printf '%s' "$GH_TOKEN_VALUE" | session_body "$env_id" "$agent_id" "$VAULT_ID")
  api POST /v1/sessions "$body"
  SESSION_ID=$(created_id session); printf 'session_id=%s\n' "$SESSION_ID"
}

# Returns 0 once the session is idle or terminated, 1 when the wait runs out.
# The agent declares no multiagent block, so no workflow run can keep work open
# behind an idle status.
poll_session() {
  local deadline status last=""
  deadline=$(( $(date +%s) + MAX_WAIT_MIN * 60 ))
  while :; do
    api GET "/v1/sessions/$SESSION_ID"
    SESSION_JSON=$RESP_BODY
    status=$(jget '.status // "unknown"')
    SESSION_STATUS=$status
    if [ "$status" != "$last" ]; then log "session $SESSION_ID is $status"; last=$status; fi
    case $status in idle|terminated) return 0 ;; esac
    if [ "$(date +%s)" -ge "$deadline" ]; then return 1; fi
    sleep "$POLL_SECONDS"
  done
}

# TODO(spike): the default order of the events list is not documented, so the
# latest event is picked by processed_at rather than by position.
latest() { # jq expression applied to the newest event in EVENTS_JSON
  printf '%s' "$EVENTS_JSON" | jq -r "sort_by(.processed_at // \"\") | last | $1"
}

report() { # stop_reason
  local usage
  usage=$(printf '%s' "$SESSION_JSON" | jq -c '.usage // null')
  printf 'session_id=%s\nstatus=%s\nstop_reason=%s\nusage=%s\n' \
    "$SESSION_ID" "$SESSION_STATUS" "$1" "$usage"
  list_events '&types[]=agent.message'
  printf -- '--- final agent message ---\n'
  mask "$(latest '(.content // []) | map(select(.type == "text") | .text) | join("\n")')"
  if [ -n "$EVENTS_OUT" ]; then
    list_events ''
    (umask 077; mask "$EVENTS_JSON" > "$EVENTS_OUT")
    log "saved $(printf '%s' "$EVENTS_JSON" | jq length) events to $EVENTS_OUT"
  fi
}

real_run() {
  read_secrets
  trap on_exit EXIT
  trap 'exit 130' INT TERM
  create_resources
  if ! poll_session; then
    log "still $SESSION_STATUS after $MAX_WAIT_MIN min; stopping"
    report "max_wait_exceeded"
    exit 4   # on_exit interrupts the session and archives the vault
  fi
  SESSION_DONE=1
  local stop
  if [ "$SESSION_STATUS" = terminated ]; then
    list_events '&types[]=session.error'
    stop="terminated: $(latest '.error.message // "no session.error event"')"
    report "$stop"
    exit 1
  fi
  list_events '&types[]=session.status_idle'
  stop=$(latest '.stop_reason.type // "unknown"')
  report "$stop"
  [ "$stop" = end_turn ] || exit 3
}

main() {
  parse_args "$@"
  validate_args
  check_tools
  RUN_STAMP=$(date '+%Y%m%d-%H%M%S%z')
  build_system_prompt
  if [ "$DRY_RUN" = 1 ]; then dry_run; exit 0; fi
  real_run
}

main "$@"
