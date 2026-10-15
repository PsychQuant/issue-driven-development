# Cloud runs (experimental)

> **Experimental.** This directory is the spike for
> [#400](https://github.com/PsychQuant/issue-driven-development/issues/400):
> running a whole IDD cycle in the cloud, started by one API call. Interfaces,
> file names and defaults may change or disappear. The supported entry point
> will be `/idd-all api`, which does not exist yet.

The split is the same for both routes: **the flow lives in this repository; your
API key stays with you.** You never fork IDD or copy its code. You add your own
key and, for route A, one small workflow file to your own repository.

| | Route A: Agent SDK on GitHub Actions | Route B: Claude Managed Agents |
|---|---|---|
| Where it runs | A GitHub-hosted runner in your repository | An Anthropic cloud sandbox |
| How you start it | `gh workflow run`, or the GitHub dispatches API | `ma_run.sh` from a Mac (one Claude API session request) |
| What you add | One secret and one workflow file in your repository | Two keychain entries on your Mac |
| IDD plugin | Loaded as a real plugin, with hooks | Skills read as files; no hooks |
| You pay for | API usage on your key, Actions minutes on private repos | API usage on your key, sandbox hours |

Neither route is the recommended one yet; the spike findings in #400 will decide.

## Route A: Agent SDK on GitHub Actions

IDD works on the repository that holds the workflow file: issues, branches and
pull requests are created there, using that repository's own `GITHUB_TOKEN`.

### What you need

- A GitHub repository you can write to. A private one is fine. IDD will open
  branches and pull requests in it.
- An Anthropic API key for the organization that should pay for the runs.
- The GitHub CLI (`gh`), logged in, on the machine you deploy from.

### Steps

1. **Store the API key as a repository secret.** Pipe it in so it never appears on
   a command line or in your shell history. With the key in the macOS keychain:

   ```bash
   security find-generic-password -s anthropic-api -a <account> -w \
     | tr -d '\n' | gh secret set ANTHROPIC_API_KEY -R <owner>/<repo>
   ```

   Without the keychain, run `gh secret set ANTHROPIC_API_KEY -R <owner>/<repo>`
   and paste the key at the prompt.

2. **Add the caller workflow.** Copy
   [`caller-example.yml`](caller-example.yml) from this directory to
   `.github/workflows/idd-cloud.yml` in your repository. Change both `@main` (in
   `uses:`) and `idd_ref: main` to the same tag or commit SHA of this repository,
   so an IDD update cannot change what runs in your repository without notice.
   Do not add other secrets to it; it passes only `ANTHROPIC_API_KEY`.

3. **Tell IDD which repository it works on.** Add
   `.claude/issue-driven-dev.local.json` to your repository:

   ```json
   {
     "github_repo": "<owner>/<repo>",
     "github_owner": "<owner>",
     "attachments_release": "attachments"
   }
   ```

   Without it, IDD tries to detect the target from the git remote and can stop
   to ask, which nobody can answer in the cloud.

4. **If your organization does not let GitHub Actions open pull requests**
   (Settings → Actions → General → Workflow permissions, often locked at the
   organization level), create a **fine-grained** token for this repository only
   (Contents, Issues, Pull requests: Read and write; shortest expiry) and store it
   as a second secret:

   ```bash
   gh secret set IDD_GITHUB_TOKEN -R <owner>/<repo>   # paste the token at the prompt
   ```

   Without it the run uses the job's own token, which can comment and push but
   cannot open a pull request under such a policy.

5. **Commit and push** the two files to your default branch.

6. **Try a dry run first.** It prints the options the runner would use and makes
   no API call:

   ```bash
   gh api -X POST repos/<owner>/<repo>/dispatches \
     -f event_type=idd-run \
     -f 'client_payload[prompt]=/issue-driven-dev:idd-list' \
     -F 'client_payload[dry_run]=true'
   gh run watch -R <owner>/<repo>
   ```

7. **Run it.**

   ```bash
   gh workflow run idd-cloud -R <owner>/<repo> \
     -f prompt='/issue-driven-dev:idd-all #<issue-number>'
   ```

   or send the same dispatches request without `dry_run`. Each run prints, near
   the top of the log, `LOADED_PLUGINS`, `TOOLS` and `WATCHED_TOOLS`, and at the end
   `RESULT` and `COST_USD`.

### Limits of route A

- **Verify runs without Codex.** The cloud run has no OpenAI key, so the
  cross-model reviewer is missing. The verify report must say so.
- **Dependency pre-flight.** IDD checks for its dependency plugins in
  `~/.claude/plugins/cache/`. Plugins loaded from a path are not there, so a skill
  that runs that check can stop. The spike is measuring this; there is no
  workaround yet.
- **One repository.** The run can only write to the repository that holds the
  workflow, because it uses that repository's `GITHUB_TOKEN`.
- **Time limit.** A run stops after 60 minutes.

## Route B: Claude Managed Agents

The run happens in an Anthropic sandbox. Your Mac only sends the requests and
waits for the result.

### What you need

- macOS with `jq` and `curl` (both come with the system or Homebrew).
- An Anthropic API key in the macOS keychain, service `anthropic-api`, under an
  account name of your choice.
- A **fine-grained** GitHub token that can only reach the repository IDD will work
  on, with Contents, Issues and Pull requests set to Read and write. Create it at
  GitHub → Settings → Developer settings → Fine-grained tokens. Repository access:
  *Only select repositories*.
- A clone of this repository, or the installed plugin, for `ma_run.sh`.

### Steps

1. **Store the GitHub token in the keychain.** Copy the token, then:

   ```bash
   security add-generic-password -s github-pat -a <repo> -w
   ```

   and paste it at the prompt (leaving the value off the command line keeps it out
   of your shell history).

2. **Write the prompt to a file**, for example `prompt.txt` containing
   `/issue-driven-dev:idd-all #<issue-number>`.

3. **Dry run.** It reads no keychain entry, sends nothing, and prints the five
   requests with every secret shown as `***`:

   ```bash
   bash plugins/issue-driven-dev/cloud/ma_run.sh --dry-run \
     --prompt-file prompt.txt --target-repo <owner>/<repo> \
     --keychain-account <account> --github-token-keychain github-pat:<repo>
   ```

4. **Run it** by dropping `--dry-run`. macOS asks for permission to read the two
   keychain entries; choose *Allow*, not *Always Allow*. The launcher prints the
   session ID, waits until the session is idle or stopped, then prints the stop
   reason and usage. `--help` lists the optional flags (`--model`, `--idd-ref`,
   `--budget-cents`, `--max-wait-minutes`, `--poll-seconds`, `--events-out`).

### Limits of route B

- **IDD runs as files, not as a plugin.** Managed Agents only discovers skills
  under a repository's `.claude/skills/`. The agent is told to read each
  `SKILL.md` and follow it. Hooks do not run, and the Skill, AskUserQuestion and
  TaskCreate tools are not available.
- **Verify runs without Codex**, as in route A.
- **Spending cap.** Each session has a budget, `--budget-cents` (default 500,
  that is USD 5). Billing is model tokens plus sandbox running time.
- **Spike-only restriction.** During the spike the launcher refuses
  `PsychQuant/issue-driven-development` as a target.
- **The token is removed after the run.** The launcher archives the vault that
  held your GitHub token when it exits, including on failure.

## Security notes

- **Deploy only where you trust the issue authors.** The agent reads issue bodies
  and comments and acts on them with shell access and no permission prompts. Text
  planted in an issue can steer it (prompt injection). On a private repository only
  collaborators can write issues; on a public one, anyone can.
- **Route A keeps the API key out of the agent's shell.** The workflow sets
  `CLAUDE_CODE_SUBPROCESS_ENV_SCRUB=1`, which removes `ANTHROPIC_API_KEY` from every
  Bash command, hook and MCP server the agent starts. `GH_TOKEN` stays (gh needs it).
  The job's own token can only write to your repository and expires when the job
  ends; an `IDD_GITHUB_TOKEN` you add lives until its expiry, so scope it to this
  one repository and keep the expiry short.
- **Route B never sends your API key to the sandbox.** The GitHub token reaches the
  sandbox in two ways: as `GH_TOKEN`, which the platform substitutes at the network
  edge so the agent never sees the value, and as the token used to clone your
  repository, which the agent may be able to read. Give that token the shortest
  expiry GitHub offers and revoke it after the run.
- Your API key is read at run time and is never written to a file in either
  repository or printed. Both entry points have a `--dry-run` that masks secrets.
- The reusable workflow (`.github/workflows/idd-cloud-run.yml` in this repository)
  accepts exactly one secret, `ANTHROPIC_API_KEY`, and passes the prompt to the
  shell only through an environment variable.
- `tests/cloud-runtime` in this plugin checks both properties.
