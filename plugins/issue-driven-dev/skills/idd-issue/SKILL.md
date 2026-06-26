---
name: idd-issue
description: |
  建立 well-documented GitHub Issue。每個改動的起點。
  Use when: 報 bug、追蹤需求、任何需要正式記錄的工作。
  防止的失敗：改了東西卻沒有文件記錄「為什麼改」。
argument-hint: "[description or path to .docx] [--target owner/repo]"
allowed-tools:
  - Bash(gh:*)
  - Bash(cp:*)
  - Bash(ls:*)
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
---

# /issue — 定義問題

每個改動都從 issue 開始。Issue 是人和 AI 的介面。

## Configuration

Target repo resolution follows the [config-protocol](../../references/config-protocol.md). Six mechanisms in priority order:

```
1. --target <owner/repo|group:label> flag    ← runtime override (this invocation only)
2. ask_each_time + candidates/groups menu    ← prompt picker from config
3. Predicate-based auto-selection (when)     ← path/title/label predicates pick default
4. Cascading config (walk up)                ← closest .claude/issue-driven-dev.local.json wins
5. git remote fallback (fork-aware detect)   ← first-run setup, writes config
6. Groups (orthogonal): multi-repo issues    ← primary + tracking issues with cross-links
```

Schema (full, see [config-protocol](../../references/config-protocol.md) for details):

```json
{
  "github_repo": "owner/repo",
  "github_owner": "owner",
  "attachments_release": "attachments",
  "tracking_upstream": "upstream/repo",
  "candidates": [
    {
      "label": "Music workspace",
      "github_repo": "kiki/music-notes",
      "when": { "path_contains": "creative/music" }
    },
    {
      "label": "Plugin marketplace (auto by title)",
      "github_repo": "PsychQuant/psychquant-claude-plugins",
      "when": { "title_matches": "(?i)\\b(plugin|mcp|skill)\\b" }
    }
  ],
  "groups": [
    {
      "label": "Cross-package bug",
      "repos": [
        {"github_repo": "PsychQuant/foo", "role": "primary"},
        {"github_repo": "PsychQuant/bar", "role": "tracking"}
      ],
      "when": { "label_in": ["cross-package"] },
      "tracking_body_mode": "minimal"
    }
  ],
  "ask_each_time": false
}
```

`candidates` / `groups` / `when` / `ask_each_time` are all optional. Without them, behavior is identical to v2.22.x (single-target).

### Why monorepo + predicates + groups

- **Sub-packages** in a monorepo often have separate upstream repos → cascading config + path predicates auto-route by `cwd`.
- **Same `cwd`, different topic** (e.g. infrastructure issue vs. package bug) → content predicates (`title_matches`, `label_in`) re-resolve after Step 2.
- **Cross-package issues** (one logical change touching multiple repos) → groups create a primary + tracking issues with bidirectional cross-links.

See [config-protocol](../../references/config-protocol.md) for full algorithm, predicate reference, and edge cases.

### Fork-aware Target Selection（為什麼）

Fork 有兩種相反的使用情境：

| 情境 | 正確 target |
|------|------------|
| **Contributor fork** — 要回饋上游、報 bug、提問 | upstream |
| **Customization fork** — fork 下來自己用、記個人 TODO | own fork |
| **Divergent fork** — 路線分岔後變成自己的專案 | own fork |

硬性預設任何一邊都會錯一半情境。所以第一次執行必須**強制讓使用者選**，然後記住。

## Execution

### Step 0: Bootstrap Stage Task List（強制)

**在動任何事之前**先用 `TaskCreate` 為這個 stage 建 todo list,確保每個 sub-step 都被追蹤:

```
TaskCreate(name="detect_target_repo", description="Step 0.5: 解析 target — --target flag → walked-up config → predicate pre-resolve → fork/third-party detection (順序: fork E2 → third-party E-TP → E1)")
TaskCreate(name="read_source", description="讀取來源(docx → mcp__che-word-mcp 讀文字 + 列圖片)")
TaskCreate(name="gather_info", description="Step 2: 蒐集 title / type / priority / description")
TaskCreate(name="reresolve_target", description="Step 2.5: 用 title/labels 重評 content predicates,若新匹配 != tentative_default 則問使用者要不要切")
TaskCreate(name="resolve_mentions", description="若有 --mention 或 description 含 @xxx，強制走 rules/tagging-collaborators.md 協定（v2.32.0+）")
TaskCreate(name="create_issue", description="Step 3: gh issue create — Single mode / Group mode / Bundle mode(--parent / --blocked-by / --bundle-mode,見 Step 3.B),body 含已驗證的 @login")
TaskCreate(name="resolve_parent_link", description="Step 3.B: 若 --parent <N> set,驗證 #N 在 target repo + idempotent PATCH parent body task list(見 references/bundle-flags.md § Edit Algorithm)")
TaskCreate(name="apply_blocked_by", description="Step 3.B: 若 --blocked-by <M>[,...] set,三層 fallback chain — body blockquote(unconditional)+ GraphQL addBlockedByDependency(嘗試)+ parent annotation(若 --parent co-used)")
TaskCreate(name="orchestrate_bundle_mode", description="Step 3.B: 若 --bundle-mode <ordered|unordered> set,建 epic + N children + 自動套用 --parent + (ordered 時)Blocked-by 鏈;與 group 模式互斥")
TaskCreate(name="attach_images", description="上傳圖片到 attachments release 並編輯 issue body 嵌入(若有)")
TaskCreate(name="create_milestone", description="來源為文件時自動建立 milestone 並指派(見 Step 4.5)")
TaskCreate(name="clarity_surface", description="Step 4.6: delegate to /idd-clarify $NEW_ISSUE_NUMBER per IC clarity axis (skip in --multi-finding mode); failure → emit 'deferred' placeholder block + continue to Step 4.7 (per #135 v4 composable primitive design)")
TaskCreate(name="linked_context_sister_sweep", description="Step 4.7: scan body draft + linked attachments + recent session conversation for sibling-concern markers (also / additionally / 另外 / 順便 / etc); if hits AskUserQuestion 3-option per canonical references/ic-r011-checkpoint.md; PATCH just-created issue body with `### Linked-Context Siblings Filed` audit trail (advisory, non-blocking, per IC_R011 #529)")
TaskCreate(name="report_and_stop", description="回報 issue number/URL(group 模式列全部 + cross-link),停下等使用者決定下一步")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。中途若發現要分更多 sub-tasks(例如批次建 10+ issues),用 `TaskCreate` 補加。

**為什麼**:確保文件來源等多要點情境,「建 issue」→「建 milestone」→「上傳圖片」→「指派 issues」等步驟不會漏掉。歷史上看到「建完 issue 忘了建 milestone」的錯誤(見 idd-issue 2.18.0 之前的 5 個 source-file labels 全部沒 milestone 的 incident)。

---

### Step 0.5: 解析 Target Repo（按 config-protocol 六機制）

**Step 1 ~ 5 使用的 `$GITHUB_REPO`(或 `$GROUP`)必須在這一步決定。不可靜默 fallback。**

完整演算法見 [config-protocol.md](../../references/config-protocol.md)。下面是給 idd-issue 用的具體流程:

#### Step 0.5.A — `--target` flag（runtime override）

如果 invocation 有 `--target owner/repo` 或 `--target group:<label>`:
- `owner/repo` 形式 → 直接用該 repo,跳到 Step 1
- `group:<label>` 形式 → 從 walked-up config 找對應 group,跳到 Step 1(後續 Step 3 走 group flow)
- `attachments_release` 用 `attachments`(default)或從 walked-up config 繼承
- **不**寫入任何 config 檔案
- **不**進入 fork detection / candidates 選單

#### Step 0.5.B — Cascading config(walk up from cwd)

從 `$PWD` 往上走找第一個 `.claude/issue-driven-dev.local.json`。Stop 在 `$HOME` 或 `/`。

```bash
find_idd_config() {
  local dir="$PWD"
  while [ "$dir" != "/" ]; do
    if [ -f "$dir/.claude/issue-driven-dev.local.json" ]; then
      echo "$dir/.claude/issue-driven-dev.local.json"
      return 0
    fi
    [ "$dir" = "$HOME" ] && break
    dir=$(dirname "$dir")
  done
  return 1
}

CONFIG_PATH=$(find_idd_config)
```

如果找到 config → 進 Step 0.5.C(predicate pre-resolve)。
如果沒找到任何 config → 跳到 Step 0.5.E(fork detection)。

#### Step 0.5.C — Predicate pre-resolve(Phase 2A,只看 path / git 類)

讀完 config 後,先掃 `groups[].when` 再掃 `candidates[].when`,評估**只用 Step 0.5 階段可看的 predicate**(`path_contains` / `path_matches` / `git_remote_matches` / `git_branch_matches` / 以及這些的 `all` / `any` / `not`組合)。內容類 predicate(`title_matches` / `label_in` 等)在 Step 2.5 才會評估,**現階段跳過**。

```
context_step05 = {
  cwd:               $PWD,
  git_remote_origin: $(git remote get-url origin 2>/dev/null),
  git_branch:        $(git rev-parse --abbrev-ref HEAD 2>/dev/null)
}

# Group 優先(更強的意圖)
matched_group = first(g in config.groups where evaluate(g.when, context_step05, only_phase05=true))
matched_cand  = first(c in config.candidates where evaluate(c.when, context_step05, only_phase05=true))

tentative_default =
  matched_group   if matched_group    else
  matched_cand    if matched_cand     else
  config.github_repo
```

`tentative_default` 可能是 `Single(repo)` 或 `Group(repos)`。記住這個值給 Step 2.5 對照。

#### Step 0.5.D — Candidates menu(`ask_each_time: true` 時)

當 walked-up config 有 `candidates` 或 `groups` 且 `ask_each_time: true`:

```
AskUserQuestion 列出每個 candidate 和 group 的 label,讓使用者選
- preselect = Step 0.5.C 算出的 tentative_default
- 顯示「(auto-matched by predicate)」標籤在被 predicate 命中的選項旁邊
```

選後 lock 這次 invocation 的選擇:**Step 2.5 不再 re-resolve**(尊重使用者明確選擇)。

如果 `ask_each_time: false` (或沒設):用 Step 0.5.C 的 `tentative_default` 進 Step 1,Step 2.5 會再 re-resolve 一次。

如果使用者下了 `--target <label>` 對應某 candidate / group,直接 match,當作 explicit choice 處理。

#### Step 0.5.E — Fork-aware detection(沒任何 config 時)

```bash
# 1. 拿到 origin 的 owner/repo
ORIGIN=$(git remote get-url origin 2>/dev/null | sed -E 's#.*[:/]([^/]+/[^/]+?)(\.git)?$#\1#')

# 2. 一次拿 origin 的 fork 狀態、upstream、以及你對它的權限。
#    viewerPermission 折進這支 gh repo view → 省掉獨立的 push-permission probe(#192)。
REPO_JSON=$(gh repo view "$ORIGIN" --json isFork,parent,viewerPermission 2>/dev/null)
IS_FORK=$(echo "$REPO_JSON" | jq -r '.isFork')
UPSTREAM=$(echo "$REPO_JSON" | jq -r '.parent.nameWithOwner // empty')

# 3. third-party clone 偵測(hybrid,#192)。owner-mismatch 當 cheap pre-filter;
#    不符才看權限。viewerPermission ∈ {WRITE,MAINTAIN,ADMIN} = 你能寫 → 視同自己的。
ORIGIN_OWNER="${ORIGIN%%/*}"
SELF_LOGIN=$(gh api user --jq .login 2>/dev/null)
IS_THIRD_PARTY=false
if [ -n "$SELF_LOGIN" ] && [ "$ORIGIN_OWNER" != "$SELF_LOGIN" ]; then
  case "$(echo "$REPO_JSON" | jq -r '.viewerPermission // empty')" in
    WRITE|MAINTAIN|ADMIN) IS_THIRD_PARTY=false ;;   # org / collaborator 可寫
    *)                    IS_THIRD_PARTY=true  ;;   # READ/TRIAGE/NONE/probe 失敗 → fail-safe 當 third-party
  esac
fi
```

**解析順序（決策,first match wins）:E2 fork → E-TP third-party → E1。** fork 也是別人 upstream,但有自己的語意,必須**先判**,否則 third-party 會把 fork 誤吞 → double-prompt。

**E2. `IS_FORK=true` 且 `UPSTREAM` 存在**（最先判） → **強制使用 `AskUserQuestion` 呈現三選項**：

| 選項 | target | 適合情境 |
|------|--------|---------|
| **Upstream** (`$UPSTREAM`) | upstream | Bug report、feature 提議、跟原作者討論架構、PR 先行討論 |
| **Own fork** (`$ORIGIN`) | origin | 個人 TODO、客製化筆記、只給自己看的追蹤、路線分岔後的獨立專案 |
| **Both (cross-linked)** | upstream 主 + origin 追蹤 | 想貢獻上游但同時要在自己 fork 記錄進度 |

「Both」模式：等同於建立一個 ad-hoc group(primary=upstream, tracking=origin)。Step 3 會走 group flow。

**E-TP. `IS_FORK=false` 且 `IS_THIRD_PARTY=true`**（clone 別人的 repo、你無 push 權,#192） → **強制使用 `AskUserQuestion` 呈現三選項**：

| 選項 | target | 寫入 |
|------|--------|------|
| **Upstream**（原作者 `$ORIGIN`） | origin | config `github_repo=$ORIGIN`；⚠ **警示:issue 在原作者公開 repo 上人人可見** |
| **自己的 tracking repo** | 使用者給的 `--target you/repo`（**不自動建**;缺則問） | config `github_repo=<該 repo>` |
| **Local-only** | — | 不開 GitHub issue;提示 GitHub-backed idd-* 暫不可用 |

選 Upstream 或 tracking repo → 一律走 **F 的 third-party 寫法**（config 加 `pr_policy: never` + `.claude/.idd/` 寫進 `.git/info/exclude`,不污染對方 repo）。

**E1. `IS_FORK=false` 且 `IS_THIRD_PARTY=false`**（你自己的 repo / 你能寫的 org repo） → 直接用 origin,**寫 config（同既有）**,不需要詢問。與既有行為相同。

#### F. 寫回 config(僅在 Step 0.5.E 觸發時)

無論 E1/E2/E-TP 選了什麼，都把結果寫入 config（E1/E2 用 `$PWD/.claude/issue-driven-dev.local.json`；E-TP 用新路徑 `$PWD/.claude/.idd/local.json`）：

```json
{
  "github_repo": "chosen/repo",
  "github_owner": "chosen",
  "attachments_release": "attachments",
  "tracking_upstream": "upstream/repo"
}
```

`tracking_upstream` 只在 Both 模式或 fork 情境下寫入（讓後續 skill 知道 upstream 是誰）。

**E-TP（third-party clone）額外寫入（#192）**:除上面 config 外,

1. config 加 `"pr_policy": "never"`（你對 origin 無 push 權 → local direct-commit;見 `idd-all` Phase 0.5）。third-party 的 config 放新路徑 `.claude/.idd/local.json`。
2. 用共用 helper 把 IDD config 寫進 `.git/info/exclude`（per-clone、不 commit/push、**不動對方 tracked `.gitignore`**）:

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/git-ignore-block.sh" \
  --target "$(git rev-parse --git-dir)/info/exclude" \
  --marker "IDD third-party clone config (#192)" \
  --direction exclude \
  ".claude/.idd/" ".claude/issue-driven-dev.local.json" ".claude/issue-driven-dev.local.md"
```

   helper 是 idempotent（重跑不重複、stale block 原地替換）。寫完 `git check-ignore .claude/.idd/local.json` 應回報 ignored、`git status` 不該出現任何 IDD 檔。為什麼用 `.git/info/exclude` 不改 `.gitignore`:後者是 tracked 檔,改它＝在對方 history 疊 commit＝污染;前者住 `.git/` 內、永不 push、別人 clone 拿不到。

下次執行時 walked-up config 已存在,走 Step 0.5.B → C 路徑,不再詢問。

**注意**:Step 0.5.A(--target flag)和 Step 0.5.D(candidates menu)的選擇**不寫回 config** — 它們是 per-invocation 決定。

#### G. 使用者想改變 target

- 一次性切換:用 `--target owner/repo` 或 `--target group:<label>`
- 永久改:直接編輯 `.claude/issue-driven-dev.local.json`
- 全部重來:刪掉 config,讓 skill 重新跑 Step 0.5.E fork detection

---

### Step 1: 讀取來源並保留所有原始資料

> **資料保留鐵律（HARD RULE）**
>
> 來源中**所有可擷取的素材都要保留**並上傳到 attachments release。**不問使用者，預設全保留**，除非擷取技術上失敗（MCP tool 不存在、檔案損毀、權限不足）才回退到「請使用者明確存到 path X」的 fallback。
>
> 理由：issue 是審計軌跡。三個月後回來看 issue 應該能還原當時所有 context — 文字、圖、附件、原始連結都在。「先問使用者要不要附」會把保留責任推給人，AI 偷懶第一個跳過的就是這步。歷史上 SNQ issue（kiki830621/collaboration_gukai#5）的 PDF + 兩張時程圖就是因為這個 gap 被漏掉，後來才補。

#### Source Type Adapter

<!-- KEEP IN SYNC: plugins/issue-driven-dev/README.md#optional-per-source-type — 加新 source type 必須同步更新 README matrix -->

依來源類型挑對應的讀取 + 抽附件 tool；**Step 4 上傳時不分類型，一視同仁全部 push 到 release**。

| Source type | 讀文字 | 抽附件 |
|-------------|--------|--------|
| `.docx` / `.doc` | `mcp__che-word-mcp__get_document_text(source_path)` | `mcp__che-word-mcp__list_images` → `mcp__che-word-mcp__export_image(image_id, output_path)` 逐張存檔 |
| `.pdf` | `pdftotext` 或 `mcp__che-word-mcp` 開啟（若可） | `pdfimages -all input.pdf prefix` 抽全部嵌入圖 |
| Telegram chat range | `mcp__plugin_che-telegram-mcp_telegram-all__get_chat_history(chat_id, limit)` 或 `dump_chat_to_markdown` | 列舉 chat 中所有 `[photo]` / `[document]` / `[video]` placeholder → 嘗試 MCP `download_file`（若存在）→ 否則**明列檔名 + 必要請求**讓使用者用 Telegram client 手動存檔到指定路徑後 skill 接手 upload |
| Apple Mail / 郵件 | `mcp__plugin_che-apple-mail-mcp_mail__get_email(message_id)` | `list_attachments` → `save_attachment(filename, output_path)` |
| Apple Notes | `mcp__plugin_che-apple-notes-mcp_notes__get_note` | 同上 export 全部 inline 圖 |
| Pasted image (`[Image: source: ~/.claude/image-cache/...]`) | n/a — image-only | **立即** `cp` 到 `/tmp/idd-issue-attachments/issue_pending_XXXXXX.png` (via `mktemp`) 在 *讀到 annotation 的同一 tool turn* — see "Pasted-image immediate-persistence" below (v2.70.0+, #112) |
| 直接貼文字（無附件） | argument 直接帶文字 | n/a |
| 混合（文字 + 圖片貼上） | argument 帶文字 + `[Image:...]` annotation | **每張 pasted image 都套用 Pasted-image immediate-persistence**;使用者額外提供的 file path 直接納入 Step 4 上傳清單 |

#### Pasted-image immediate-persistence (v2.70.0+, #112)

**Why this step**: Claude Code's `~/.claude/image-cache/<session-id>/` is per-session + cleared by context compaction / session lifecycle / session-id rollover (continued session under fresh id). Step 1 → Step 4 separation (read annotation in Step 1, upload in Step 4) spans `AskUserQuestion` + Step 2.5/2.6 + Step 3 `gh issue create` + Step 4 upload — easily long enough for the cache to be evicted between turns. When this hits, Step 4's `gh release upload <image-cache-path>` fails because `ls` returns nothing; the user has to re-paste, violating the *spirit* of Step 1's data-preservation hard rule.

**Rule (SHALL)**: when Step 1 encounters a `[Image: source: <path>]` annotation in the prompt, **`cp` the image to a stable staging path within the SAME tool turn** that first sees the annotation. Do NOT defer to Step 4. The staged path joins Step 4's upload list; the original `~/.claude/image-cache/` path is no longer referenced after Step 1.

**PASTED_IMAGE_PATHS source contract** (as of v2.70.0+): when the agent (Claude Code) sees `[Image: source: <path>]` annotation(s) in the user's prompt (one or more), populate a bash array `PASTED_IMAGE_PATHS=( "/Users/che/.claude/image-cache/<session-id>/1.png" ... )` with one entry per annotation before invoking the staging loop below. The annotation is currently the only authoritative source per the v2.70.0+ Claude Code prompt format — there is no separate enumeration API; the agent reads the prompt text and extracts annotation `source:` values verbatim. (If future Claude Code versions add drag-drop or other attachment annotation forms, this contract may need extension.)

```bash
# Run in the SAME tool turn that first sees the [Image: source: ...] annotation.
# Do NOT split into a separate turn — that's the bug class #112 surfaced.
mkdir -p /tmp/idd-issue-attachments

# Track staged paths for Step 4 upload. MUST be declared as array (not string) so
# Step 4's ATTACHMENT_PATHS+=("${PASTED_IMAGES_STAGED[@]}") concatenation works.
declare -a PASTED_IMAGES_STAGED=()

for src_path in "${PASTED_IMAGE_PATHS[@]}"; do
  if [ ! -f "$src_path" ]; then
    # Cache already evicted before Step 1 ran (rare — happens in compaction-resumed sessions
    # where the new agent loop runs under a fresh session id, original cache dir is gone).
    # Fallback: ask user to re-provide. Documented in spec as the known failure mode.
    echo "⚠ Pasted-image source $src_path no longer exists (cache evicted)." >&2
    echo "  Please re-paste the image OR provide a stable path; continuing without this attachment." >&2
    continue
  fi
  # Stage to /tmp via mktemp — collision-safe even under hostile concurrency.
  # mktemp guarantees uniqueness (atomic create-or-fail per POSIX); pre-existing
  # `$(date +%s)_$RANDOM` had ~0.4% collision rate at 1000 tight-loop trials
  # (v2.70.0+ #112 logic-reviewer finding). mktemp closes that channel structurally.
  #
  # macOS BSD mktemp uses 6-X template by default; GNU mktemp accepts the same. Output
  # is the actual unique pathname. The .png extension is appended after mktemp returns
  # to preserve mime detection downstream.
  staged_base=$(mktemp /tmp/idd-issue-attachments/issue_pending_XXXXXX) || {
    echo "✗ mktemp failed for /tmp/idd-issue-attachments — skipping $src_path" >&2
    continue
  }
  staged_path="${staged_base}.png"
  mv "$staged_base" "$staged_path"   # rename so .png extension is present
  cp "$src_path" "$staged_path"
  PASTED_IMAGES_STAGED+=("$staged_path")
  echo "→ Staged $src_path → $staged_path"
done
```

**Step 4 hand-off contract**: Step 4's attachment-upload loop MUST concatenate `PASTED_IMAGES_STAGED[@]` into its `ATTACHMENT_PATHS[@]` upload list. Explicit example:

```bash
# In Step 4, after gathering other attachment paths (from docx export_image / pdfimages / etc):
ATTACHMENT_PATHS+=("${PASTED_IMAGES_STAGED[@]}")

# Then iterate ATTACHMENT_PATHS for gh release upload.
```

This makes the hand-off explicit — staged paths from Step 1's pasted-image handler flow through to Step 4 without a separate enumeration step.

**Step 4 reference contract**: when uploading attachments, iterate `PASTED_IMAGES_STAGED[@]` (NOT the original `[Image: source:...]` paths). The annotation in the prompt is only the *initial pointer*; the staged copy is the durable artifact.

**Why `/tmp` not in-repo `.claude/.idd/issue-pending/`**: anonymous + system-cleanup-friendly + doesn't pollute version control. The in-repo alternative was considered but rejected per `feedback_lead_minimal` — system housekeeping handles cleanup without policy surface.

**Why not Read-then-Write via Claude Code tools**: Bash `cp` preserves bytes exactly + handles binary efficiently. Read/Write would re-encode through Claude's text channel for binary content.

**Compaction-resumed session edge case**: if the cache was evicted before Step 1 even runs (extreme: long pre-Step-1 turn or session-id rollover), the `[ ! -f "$src_path" ]` check fails — fallback prints a warning + continues without that attachment. User can re-paste in a follow-up.

#### MCP plugin presence pre-flight (v2.54+, #27 fail-fast)

當 source 是 `.docx` / Telegram / Apple Mail / Apple Notes(任一需要 MCP plugin 的類型),Step 1 一開始就 invoke `check-plugin-presence.sh` detect — 缺失則 **fail-fast abort** with structured error message (per #32 absorbed acceptance criteria)。

```bash
# Source-type → required plugin mapping
case "$SOURCE_TYPE" in
  docx|doc)
    "$CLAUDE_PLUGIN_ROOT/scripts/check-plugin-presence.sh" psychquant-claude-plugins che-word-mcp || abort_source_unsupported "che-word-mcp" ".docx" "psychquant-claude-plugins" ;;
  telegram)
    "$CLAUDE_PLUGIN_ROOT/scripts/check-plugin-presence.sh" psychquant-claude-plugins che-telegram-mcp || abort_source_unsupported "che-telegram-mcp" "Telegram chat" "psychquant-claude-plugins" ;;
  apple-mail)
    "$CLAUDE_PLUGIN_ROOT/scripts/check-plugin-presence.sh" psychquant-claude-plugins che-apple-mail-mcp || abort_source_unsupported "che-apple-mail-mcp" "Apple Mail" "psychquant-claude-plugins" ;;
  apple-notes)
    "$CLAUDE_PLUGIN_ROOT/scripts/check-plugin-presence.sh" psychquant-claude-plugins che-apple-notes-mcp || abort_source_unsupported "che-apple-notes-mcp" "Apple Notes" "psychquant-claude-plugins" ;;
  text|md|mixed)
    : ;; # no plugin needed for raw text / markdown / pasted text+paths
esac
```

`abort_source_unsupported` 印出 structured error message(format spec from #32 absorbed acceptance criteria):

```
✗ Source detected as <SOURCE_DESC> but `<PLUGIN>` MCP plugin is not installed.

該 source type 需要對應 MCP plugin 才能讀取文字 + 抽圖。

Options:
  1) Install plugin (recommended):
     claude plugin marketplace add PsychQuant/<MARKETPLACE>
     claude plugin install <PLUGIN>@<MARKETPLACE>
     # 不知道 marketplace? 跑: claude plugin marketplace list
     # 詳見: plugins/issue-driven-dev/README.md#optional-per-source-type

  2) Convert to another supported format:
     - Save as `.md` or `.txt` then paste content directly
     - Or screenshot then attach as image (如果 主要內容是 figures)

  3) Manual fallback (not recommended for archives):
     paste relevant text into prompt directly

Aborting /idd-issue. Run again after installing or converting.
```

**Why fail-fast not silent fallback** (per #27 + #32 absorbed):
- Silent fallback (e.g. "讓使用者手動處理") 讓使用者誤以為 IDD **不支援**該格式,而非少裝 plugin
- Explicit error + 3 options 把責任 explicit 還給使用者,各 source-type 統一格式建立 mental model

**Bypass**: `IDD_SKIP_PLUGIN_CHECK=1` env var 跳過 detect(同 #34 generic helper escape hatch)。

#### Telegram source 專屬流程（最常見且最容易漏的）

當原始描述中含 `chat_id` / Telegram URL / `@username` 引用時，**強制**走以下流程，不問：

1. **列出 chat 中所有有 attachment 的訊息**（`get_chat_history` 抓最近 N 條，掃 `media_type` 不為 null 的）
2. **逐項嘗試 MCP 下載**到本機暫存（如 `/tmp/idd-issue-attachments/`）
3. **MCP 不支援下載**（目前 `che-telegram-mcp` 是這狀況，見 `PsychQuant/che-msg#17`）→ 進 fallback：明確列出**每個檔案是什麼**（時間戳 + sender + caption + 推測檔名），請使用者用 Telegram client 各別存到指定路徑，skill 等待後接手 Step 4 上傳
4. **絕對不可省略 fallback 提示**——靜默跳過 = 違反保留鐵律

```bash
# Fallback 提示模板（Telegram MCP 無 download 支援時）
echo "Telegram source 含 ${N} 個附件需要保留。MCP 目前不支援自動下載，請手動操作:"
echo ""
echo "  1) 開啟 Telegram → 對話 ${chat_id}"
echo "  2) 找到以下訊息並 Save As 到指定路徑:"
echo ""
for att in "${ATTACHMENTS[@]}"; do
  echo "     [${att.timestamp}] ${att.sender}: ${att.caption_preview}"
  echo "       → 存成 /tmp/idd-issue-attachments/${att.suggested_filename}"
done
echo ""
echo "  3) 全部存好後告訴我「ok」，skill 會接手 upload + 嵌入 issue body"
```

### Step 2: 蒐集資訊

缺少的話詢問使用者：

1. **Title** — 一句話描述問題
2. **Type** — bug / feature / refactor / docs
3. **Priority** — P0（立即）/ P1（本週）/ P2（排程）/ P3（有空再做）
4. **Description** — 問題描述（bug: 重現步驟 + expected + actual；feature: 需求 + 目的）
5. **Stakeholders（v2.32.0+，可選）** — 若需要在 issue body 中 tag 人，使用 `--mention <login>[,<login>...]` flag 或自然語言（"tag X"）。**任何 @xxx 必走 [`rules/tagging-collaborators.md`](../../rules/tagging-collaborators.md) 5 步協定**（gh api → fuzzy match → AskUserQuestion fallback → @login 不用 display name → post 前 verify）。違反 = 通知錯人，不可逆。

#### Step 2.0.5: Title sanitization (v2.46.0+, P9 follow-up of #1)

不論 title 來源（user 輸入、文件 mining、`idd-verify` follow-up triage、其他 skill caller），post 前**必須**做以下 sanitization：

- **Length cap**: 200 chars (GitHub issue title 上限約 256;留 buffer 給後續編輯)
- **Strip control chars except space**: `tr -cd '[:print:]\t '`(去掉 `\n`、`\r`、零寬字元、bidirectional override 等;`\t` → 空白由下一步處理)
- **Collapse whitespace**: `tr -s '\t ' ' '`(多個空白 → 單一空白;tab → space)
- **Trim leading / trailing whitespace**

```bash
sanitize_title() {
  local raw="$1"
  echo "$raw" \
    | tr -cd '[:print:]\t ' \
    | tr -s '\t ' ' ' \
    | sed -E 's/^ +//; s/ +$//' \
    | cut -c1-200
}
TITLE=$(sanitize_title "$RAW_TITLE")
```

**為什麼集中在 idd-issue 而非各 caller**:`idd-verify` follow-up triage、`idd-implement` sister-bug sweep、`idd-close` orphan-mention scan 全部 forward title 給 idd-issue。Sanitization 集中在 issue creation 邊界,所有 caller 都受惠;違反者唯一防線。

**警告 (不阻擋)**:若發現 RTL/LTR override(U+202D-U+202E)、zero-width chars(U+200B-U+200D)、homoglyphs(`а` Cyrillic vs `a` Latin)被 strip,echo `⚠ stripped suspicious chars from title` 提示 user 重審。

### Step 2.6: Resolve Mentions（v2.32.0+）

若 Step 2 蒐集到的 description 含 `@xxx` token，或使用者下了 `--mention` flag：

```bash
OWNER=$(echo "$GITHUB_REPO" | cut -d/ -f1)
REPO=$(echo "$GITHUB_REPO" | cut -d/ -f2)
gh api repos/$OWNER/$REPO/collaborators --jq '.[] | {login, name}' \
  > /tmp/idd-collaborators-$$.json
```

接 [`rules/tagging-collaborators.md`](../../rules/tagging-collaborators.md) Step 3-5。Post 前 grep `@\w+` 全部 cross-check，未驗證 token = abort。

### Step 2.5: Re-resolve target with content predicates(Phase 2A)

**只有當 Step 0.5 的選擇是 implicit(走 Step 0.5.C predicate pre-resolve 或 fall-through 到 `github_repo`)時才執行。** 使用者明確選的(--target / ask_each_time menu)直接 lock,跳過 re-resolve。

```
context_full = context_step05 ∪ {
  title:    $TITLE,
  type:     $TYPE,
  labels:   $LABELS,
  priority: $PRIORITY,
  body:     $DESCRIPTION
}

# 重掃 groups + candidates,這次所有 predicate 都可以評估
new_match_group = first(g in config.groups where evaluate(g.when, context_full))
new_match_cand  = first(c in config.candidates where evaluate(c.when, context_full))
new_match = new_match_group or new_match_cand

# 若新匹配 != Step 0.5 的 tentative_default → 詢問使用者
if new_match exists AND new_match != tentative_default:
    AskUserQuestion(
      question = "Title/labels match {new_match.label} better than {tentative_default}. Switch?",
      options = [
        {label: "Yes, switch to {new_match.label}",  description: "..."},
        {label: "No, keep {tentative_default}",      description: "..."}
      ]
    )
    if user picks Yes → 切換到 new_match
```

**為什麼**:有些 routing 規則只能用內容判斷,例如「title 含 plugin / mcp / skill 的 issue 應該送到 plugin marketplace repo」。Step 0.5 時還沒蒐集資訊,只能先用 path 預設;Step 2 拿到 title 後才能精準路由。

**不打擾原則**:
- 只在 `tentative_default` 和 `new_match` **不同**時才問
- 已是 explicit choice(--target / ask_each_time)→ 不問
- 沒新匹配,或新匹配等於 tentative → 不問

### Step 3: 建立 Issue

根據 Step 0.5 / Step 2.5 解析結果 + flag,分三種情境:

- **Single repo 模式**(常見) → 直接 `gh issue create` 到 `$GITHUB_REPO`,如下方範例
- **Group 模式**(`tentative_default` 或 user 選擇是 group,或 fork-aware 選了 Both) → 走 Step 3.G
- **Bundle 模式**(任一 `--parent` / `--blocked-by` / `--bundle-mode` flag set,v2.52.0+) → 走 Step 3.B 在 Single repo 模式之上補強;與 Group 模式**互斥**(同時 set → refuse)

#### 3.A — Single repo creation

```bash
gh issue create \
  --repo $GITHUB_REPO \
  --title "$TITLE" \
  --body "$(cat <<'EOF'
## Problem

> **Original text**:
> 「...exact original text...」
> — Source: {source}

{Plain language interpretation}

## Type
{bug / feature / refactor / docs}

## Expected
...

## Actual
...

## Impact
...
EOF
)" \
  --label "$TYPE"
```

> **CRITICAL**: 來自文件的 issue **必須**逐字引用原文。AI 摘要會失真，原文是唯一不會漂移的東西。

> **CRITICAL**: 所有原文引用**必須**使用 blockquote（`>`）格式。不論出現在 issue body 或 comment 中，只要是逐字引用的原文，都要用 `>` 包住整段。這是審計軌跡，必須在視覺上與分析/解讀明確區分。

> **數學公式格式**：GitHub 支援 `$...$`（inline）和 `$$...$$`（display）。含底線的程式變數名**不放 math mode**，改用 backtick code。混合寫法：`$R_I = J \cdot$` `` `mse_info` ``。

#### 3.B — Bundle flags(`--parent` / `--blocked-by` / `--bundle-mode`,v2.52.0+)

任一 bundle flag set 時走這條路徑。完整 spec / edit algorithm / fallback chain / partial failure 處理見 [`references/bundle-flags.md`](../../references/bundle-flags.md);本節是 inline reference。

##### Pre-flight Gates(必須先過)

```bash
# Gate 1:Bundle 與 Group 模式互斥
if [[ -n "$BUNDLE_MODE" && "$RESOLVED" == group:* ]]; then
  echo "✗ refuse: --bundle-mode 和 group mode 互斥"
  echo "  group mode 已 implicitly 表達多 issue + cross-link;"
  echo "  bundle 是同 repo parent-child + dependency,語意不同。請選一個。"
  exit 1
fi

# Gate 2:--parent 必須在同 repo
if [[ -n "$PARENT_NUM" ]]; then
  PARENT_REPO=$(gh issue view "$PARENT_NUM" --json repository \
    --jq '.repository.nameWithOwner' 2>/dev/null)
  if [[ "$PARENT_REPO" != "$GITHUB_REPO" ]]; then
    echo "✗ refuse: parent #$PARENT_NUM 在 '$PARENT_REPO',target repo 是 '$GITHUB_REPO'"
    echo "  Bundle mechanism is same-repo only."
    echo "  跨 repo coordinated issues 用 'groups' 機制,見 CLAUDE.md § Configuration § groups"
    exit 1
  fi
fi
```

##### `--parent <N>` Handler(child 建完後 PATCH parent body)

走完 3.A 建好 child(`$CHILD_NUM`)後執行:

```bash
# 1. 抓 parent body
PARENT_BODY=$(gh issue view "$PARENT_NUM" --repo "$GITHUB_REPO" --json body --jq '.body')

# 2. Idempotency check:scan #N references in existing task list
if echo "$PARENT_BODY" | grep -qE "^- \[[ x]\] #${CHILD_NUM}\b"; then
  echo "→ #${CHILD_NUM} already in parent #${PARENT_NUM} task list, skip (idempotent)"
else
  # 3. 找第一個連續 task list 段落,append `- [ ] #child`(若 --blocked-by 同時 used,加註解)
  ENTRY="- [ ] #${CHILD_NUM}"
  if [[ -n "$BLOCKED_BY_LIST" ]]; then
    ENTRY="${ENTRY} (blocked by ${BLOCKED_BY_LIST_FORMATTED})"  # e.g. "(blocked by #50, #51)"
  fi

  # Algorithm: append to first contiguous "- [ ]"/"- [x]" section, OR append fresh `## Children` anchor
  NEW_BODY=$(append_to_task_list "$PARENT_BODY" "$ENTRY")

  gh issue edit "$PARENT_NUM" --repo "$GITHUB_REPO" --body "$NEW_BODY"
fi
```

> **Edit algorithm 細節** — 演算法在 `references/bundle-flags.md § Edit Algorithm` 有完整定義:找第一個連續 `- [ ]`/`- [x]` 區段 → scan `#child` reference → append-if-absent → fallback `## Children` anchor。重複呼叫保證 idempotent。

##### `--blocked-by <M>[,<M2>...]` Handler(三層 fallback chain)

走完 3.A 建好 child 後,**三層全部執行**:

```bash
# Layer 2:Body blockquote 標註(無條件,先做)
BLOCKED_BLOCKQUOTE=""
for M in $(echo "$BLOCKED_BY_LIST" | tr ',' '\n'); do
  BLOCKED_BLOCKQUOTE="${BLOCKED_BLOCKQUOTE}> Blocked by #${M}\n"
done
NEW_CHILD_BODY="${BLOCKED_BLOCKQUOTE}\n${ORIGINAL_BODY}"
gh issue edit "$CHILD_NUM" --repo "$GITHUB_REPO" --body "$NEW_CHILD_BODY"

# Layer 1:GraphQL native dependency(嘗試,失敗不 abort)
CHILD_NODE_ID=$(gh issue view "$CHILD_NUM" --repo "$GITHUB_REPO" --json id --jq '.id')
for M in $(echo "$BLOCKED_BY_LIST" | tr ',' '\n'); do
  M_NODE_ID=$(gh issue view "$M" --repo "$GITHUB_REPO" --json id --jq '.id')
  if ! gh api graphql -f query='
    mutation($i:ID!,$b:ID!){addBlockedByDependency(input:{issueId:$i,blockedByIssueId:$b}){issue{id}}}
  ' -F i="$CHILD_NODE_ID" -F b="$M_NODE_ID" 2>/dev/null; then
    echo "⚠ GraphQL addBlockedByDependency #${CHILD_NUM} ← #${M} failed (repo not enabled / API error / permission); body blockquote already in place"
  fi
done

# Layer 3:Parent task list annotation(僅 --parent co-used 時)
# 已由上面 --parent handler 的 ENTRY 計算邏輯處理(若 BLOCKED_BY_LIST set,task list entry 含 `(blocked by ...)`)
```

> **三層全執行 vs 階層式 fallback** — 詳見 `references/bundle-flags.md § Fallback Chain`。Layer 2 在所有情境下執行(可讀性最高);Layer 1 只是錦上添花(GitHub UI native warning);Layer 3 只在 `--parent` 同時 used 時才有意義。

##### `--bundle-mode <ordered|unordered>` Handler(orchestration)

當 `--bundle-mode` set 且 input 含 ≥2 個 item:

```bash
# 0. 驗證 item 數量
if [[ ${#ITEMS[@]} -lt 2 ]]; then
  echo "✗ refuse: --bundle-mode 需要 ≥2 個 item;單一 item 用 idd-issue 不帶 flag"
  exit 1
fi

# 1. 建 epic parent(用 bundle-level title;若 input 沒 epic title 則 AskUserQuestion 索取)
EPIC_NUM=$(gh issue create --repo "$GITHUB_REPO" \
  --title "$EPIC_TITLE" \
  --body "Epic for ${#ITEMS[@]}-item bundle (${BUNDLE_MODE})\n\n## Children\n" \
  --label "epic" | basename)

# 2. 建 N children,逐個 auto-apply --parent <epic> + (ordered 時)--blocked-by <prev>
PREV_CHILD=""
for ITEM in "${ITEMS[@]}"; do
  # ordered 模式:除第一個外,加 --blocked-by <prev>
  EXTRA_FLAGS=()
  if [[ "$BUNDLE_MODE" == "ordered" && -n "$PREV_CHILD" ]]; then
    EXTRA_FLAGS+=(--blocked-by "$PREV_CHILD")
  fi

  # 遞迴呼叫 idd-issue 邏輯(內部 reuse 3.A + 上面的 --parent / --blocked-by handler)
  CHILD_NUM=$(create_child_with_parent "$ITEM" "$EPIC_NUM" "${EXTRA_FLAGS[@]}")
  PREV_CHILD="$CHILD_NUM"
done
```

`unordered` 模式跳過 `--blocked-by` 套用,純 task list。`ordered` 模式形成嚴格鏈式(child[i] only blocked by child[i-1])。

##### Partial Failure(bundle 中途某 child 失敗)

| 失敗點 | 行為 |
|--------|------|
| 第一個 child 建立失敗 | abort 整個 invocation,清理已建的 epic(用 `gh issue close $EPIC_NUM --reason "not planned"`)。錯誤訊息名指失敗 child title |
| 第 N 個 child 失敗(N>1) | 不 abort;**continue** 後續 children;最後報告 partial success(N-1 成功 / total)。使用者可重跑 invocation 並用 `--parent <epic>` 補建漏掉的 |
| `--blocked-by` 中某 target GraphQL 失敗 | 該 target 的 Layer 1 失敗 → warning + 繼續嘗試下個 target;Layer 2 body blockquote 一律加(包括失敗 target);Layer 3 parent annotation 一律加 |
| Parent body PATCH 失敗 | child 仍建立成功;parent body 未更新 → warning + 退出非零 code,使用者可 `gh issue edit` 手動補 |

##### 與既有機制正交(不互相干擾)

| 機制 | 互動 |
|------|------|
| **Step 4.5 Auto-milestone** | 不論 bundle 是否 used,`--bundle-mode` 觸發時 epic + children 全部 assign 到該 milestone |
| **Step 4.7 Sister Sweep** | 對 bundle 的 epic parent 仍跑 sister sweep;sibling issues 不會被加進 epic 的 task list(它們是正交旁支) |
| **Group 模式** | 互斥(見 Pre-flight Gate 1) |
| **Step 0.5 / Step 2.5 Target Resolution** | 在 bundle flag handler 之前執行;`$GITHUB_REPO` 是 cross-repo refuse 的 source of truth |

#### 3.G — Group creation(multi-repo cross-linked,Phase 2B)

當解析結果是 group(從 `groups[]`、`--target group:<label>`、或 fork-aware Both 模式):

```
group = {
  primary:  {github_repo: "PsychQuant/foo"},
  tracking: [{github_repo: "PsychQuant/bar"}, {github_repo: "PsychQuant/glue"}],
  tracking_body_mode: "minimal" | "full"   # default "minimal"
}
```

**驗證**:`primary` 必須**剛好一個** repo。零個或多個 → refuse to create,報錯指出 group label。

**建立順序**:

```bash
# 1. 在 primary repo 建 issue,用完整 body
PRIMARY_URL=$(gh issue create \
  --repo $PRIMARY_REPO \
  --title "$TITLE" \
  --body "$FULL_BODY" \
  --label "$TYPE")
PRIMARY_NUM=$(basename "$PRIMARY_URL")

# 2. 在每個 tracking repo 建追蹤 issue
TRACKING_REFS=()
for TRACKING_REPO in "${TRACKING_REPOS[@]}"; do
  if [ "$TRACKING_BODY_MODE" = "full" ]; then
    TRACKING_BODY="> Tracking primary: ${PRIMARY_REPO}#${PRIMARY_NUM}

${FULL_BODY}"
  else
    # minimal mode (default)
    TRACKING_BODY="> Tracking primary: ${PRIMARY_REPO}#${PRIMARY_NUM}
> ${ONE_LINE_SUMMARY}"
  fi

  TRACKING_URL=$(gh issue create \
    --repo $TRACKING_REPO \
    --title "$TITLE" \
    --body "$TRACKING_BODY" \
    --label "$TYPE")
  TRACKING_NUM=$(basename "$TRACKING_URL")
  TRACKING_REFS+=("${TRACKING_REPO}#${TRACKING_NUM}")
done

# 3. 在 primary issue 留 comment,列出所有 tracking refs
gh issue comment $PRIMARY_NUM --repo $PRIMARY_REPO --body "$(cat <<EOF
Tracked in:
$(for ref in "${TRACKING_REFS[@]}"; do echo "- $ref"; done)
EOF
)"
```

**部分失敗處理**:若 primary 建好但某個 tracking 失敗:
- **不**回滾已建的 issues(手動清理比較透明)
- 報告哪些成功、哪些失敗
- 使用者可以後續用 `--target <failed-repo>` 補建,然後手動加 cross-link

**Body mode 選擇**:
- `minimal`(預設):tracking issues 只放 `Tracking primary: X#N` + 一行摘要 → 適合單純記錄
- `full`:tracking issues 也放完整 body → 適合每個 repo 都需要獨立完整脈絡(例如不同團隊維護)

**回報格式**:
```
✓ Primary:    PsychQuant/foo#42  (https://github.com/PsychQuant/foo/issues/42)
✓ Tracking:   PsychQuant/bar#15  (https://github.com/PsychQuant/bar/issues/15)
✓ Tracking:   PsychQuant/glue#8  (https://github.com/PsychQuant/glue/issues/8)
✓ Cross-link comment added to PsychQuant/foo#42
```

### Step 4: 附加所有原始素材（鐵律：預設全保留）

> 引用 Step 1 的「資料保留鐵律」：來源中**任何附件都要全部上傳**，不論張數、不論格式。
> 詢問「要不要附」屬於違規。例外只在 Step 1 fallback 已經說明擷取技術失敗時才成立。

```bash
# 確保 attachments release 存在
gh release view $ATTACHMENTS_RELEASE --repo $GITHUB_REPO 2>/dev/null || \
  gh release create $ATTACHMENTS_RELEASE --repo $GITHUB_REPO \
    --title "Attachments" --notes "Issue attachments and figures"

# 對 Step 1 蒐集到的每個附件依序上傳（命名規則：issue_${NUMBER}_${DESC}.${ext}）
for f in "${ATTACHMENT_PATHS[@]}"; do
  ext="${f##*.}"
  desc=$(make_desc "$f")  # 簡短描述 e.g. "snq_timeline" / "telegram_msg_8169455616_photo1"
  upload_name="issue_${NUMBER}_${desc}.${ext}"
  gh release upload $ATTACHMENTS_RELEASE "$f" \
    --repo $GITHUB_REPO --clobber
done

# 圖片 URL 格式（private 和 public repo 都適用）
# https://github.com/$GITHUB_REPO/releases/download/$ATTACHMENTS_RELEASE/issue_${NUMBER}_${DESC}.${ext}

# 編輯 issue body 加入所有附件的 markdown link / 圖片嵌入
# - .png/.jpg/.gif → ![desc](url)  讓 issue 直接渲染
# - .pdf/.docx/其他 → [desc](url)  讓使用者點下載
gh issue edit $NUMBER --repo $GITHUB_REPO --body "..."
```

#### 命名規則

`issue_${NUMBER}_${DESC}.${EXT}` — `DESC` 用 snake_case 簡短描述附件內容。範例：

- `issue_5_snq_timeline.png` — SNQ 申請時程圖
- `issue_5_snq_criteria.png` — SNQ 評分標準
- `issue_5_snq_example_113A272.pdf` — 同類前例計畫書
- `issue_4_telegram_msg_8169455616_photo1.jpg` — Telegram 原圖

#### 違規情境（檢查清單）

跑完 Step 4 後**必須**確認以下都成立，否則回頭補：

- [ ] Step 1 列出的每個附件都已 upload（用 `gh release view $ATTACHMENTS_RELEASE` 確認 asset 數 = 附件總數）
- [ ] 每個 asset URL 都已寫入 issue body（`![]()` 或 `[]()`）
- [ ] 沒有以「使用者沒明說要附」為由跳過任何素材
- [ ] Telegram MCP 失敗時有走 fallback 提示，不是靜默略過

> **Private repo 圖片渲染**：Release asset URL 在 issue/comment 的 markdown 中可以正常渲染，前提是查看者是 repo 的 collaborator 且已登入 GitHub。不需要把 repo 改成 public。

### Step 4.5: 自動建立 Milestone（來源為文件時）

當來源是一整個文件（.docx 等），所有 issues 建完後自動建立 milestone 並指派：

```bash
# 從檔案名稱或文件標題推導 milestone 名稱
# 例：「網站調整內容.docx」→ milestone 名稱問使用者，預設用文件標題

# 建立 milestone
gh api repos/$GITHUB_REPO/milestones \
  -f title="$MILESTONE_NAME" \
  -f description="來源：$SOURCE_FILE — $ISSUE_COUNT 個 issues (#first-#last)" \
  -f state="open"

# 所有剛建立的 issues 都指派到此 milestone
for n in $ALL_ISSUE_NUMBERS; do
  gh issue edit $n --repo $GITHUB_REPO --milestone "$MILESTONE_NAME"
done
```

**觸發條件**：來源為文件（.docx, .pdf, .md 等）且建立了 2 個以上 issues。
**命名**：優先用文件內的主標題，沒有則問使用者。
**不觸發**：單一 issue 或非文件來源。

### Step 4.6: Clarity Surface (v2.71.0+, PsychQuant/issue-driven-development#135)

**Compliance**: this step implements the **Terminology / Semantic accuracy** axis(third axis in IDD quality framework — alongside IC_R010 Confidence + IC_R007 Verbatim)per the composable primitive pattern in `/idd-clarify` skill。

**Why this step**:當 issue 來源含 domain-specific terms(統計 / ML / 商業分析 / medical / legal),source 用詞可能跟 canonical term 有 mismatch(QEF #804「特徵值」實際是「分群變數」typical case)。或 source 描述 analysis 需要 X 但未指明 X 來源(missing-context gap)。Without this step,downstream `idd-diagnose` / `idd-implement` chain 繼承錯誤越走越歪。

**Rule (SHALL, mandatory)**:在 Step 4.5 milestone 完成後、Step 4.7 sister sweep 開始前,**必須** auto-delegate `/idd-clarify $NEW_ISSUE_NUMBER`,除非 `--multi-finding` mode。

**Trigger predicate**:

| Source type | Step 4.6 行為 |
|---|---|
| `.docx` / `.pdf` doc source | auto-delegate `/idd-clarify` |
| Pasted text(含 mixed text+pasted images)| auto-delegate `/idd-clarify` |
| Telegram chat / Apple Mail / Apple Notes | auto-delegate `/idd-clarify` |
| `--multi-finding` mode | **SKIP**(per design D3 — 每 finding sub-invocation 跑會 multiply prompt) |

**Procedure**:

```bash
# Skip in --multi-finding mode
if [ -n "$MULTI_FINDING_MODE" ]; then
  echo "→ Step 4.6 skipped: --multi-finding mode (per #135 v4 design D3)"
else
  # Delegate to idd-clarify; capture exit code
  Skill(skill="issue-driven-dev:idd-clarify", args="#$NEW_ISSUE_NUMBER")
  CLARIFY_EXIT=$?

  if [ $CLARIFY_EXIT -ne 0 ]; then
    # Failure handling: emit deferred placeholder so downstream gate doesn't silently bypass
    DEFERRED_BLOCK="

### Clarity Surface (deferred — see retry hint)

| Type | Source | Suggested canonical | Status |
|---|---|---|---|
| (deferred) | /idd-clarify invocation failed | Run /idd-clarify #$NEW_ISSUE_NUMBER manually to populate | deferred |
"
    NEW_BODY="${CURRENT_BODY}${DEFERRED_BLOCK}"
    gh issue edit $NEW_ISSUE_NUMBER --repo $GITHUB_REPO --body "$NEW_BODY"
    echo "⚠ /idd-clarify failed (exit $CLARIFY_EXIT) — appended deferred placeholder; continuing to Step 4.7" >&2
  fi
fi
```

**Why deferred placeholder on failure**:Step 0.5 gate(in `idd-diagnose`)greps for `### Clarity Surface` block。若 Step 4.6 failure silent skip,downstream gate 看 body 缺 block,fall through to「legacy issue」branch(per `idd-diagnose-clarity-gate` backward-compat scenario)→ silently bypass。Deferred placeholder 強制 user explicit attention,符合「surface 不 silent ignore」哲學。

**Ordering invariant**:

```
Step 4.5 Milestone  →  Step 4.6 Clarity Surface  →  Step 4.7 Sister Sweep  →  Step 4.8 Split Umbrella SOP
```

Step 4.7 sister sweep 讀 body **AFTER** Step 4.6 已 append annotation,所以 sister sweep 看到的 body 是 已加 Clarity Surface 後的版本。Anti-order(clarity 在 sister 之後)會讓 sister scan 看到 source 原詞 surface 出 sister concern,實際只是 terminology problem 該由 clarify 處理 — 兩個 axis 混淆,per design D1 rationale。

**Why mandatory not advisory**:per design D2 + #135 v4 — clarity 是 first-class quality axis,不該被 silent skip。`--multi-finding` 的 skip 是 narrow exemption(cost prevention),不是 escape hatch。

**Backward compat for unattended mode**:`/idd-all` UNATTENDED MODE directive 下 Step 4.6 仍 auto-delegate。`/idd-clarify` 自己處理 unattended decision(per sister #137 contract,deferred — 暫定 fail-fast)。

### Step 4.7: Linked-Context Sister Sweep

**Per IC_R011 follow-up filing checkpoint** (see [`references/ic-r011-checkpoint.md`](../../references/ic-r011-checkpoint.md))。

**Trigger condition**: 在 Step 5 (回報並停止) 前,scan 3 個 linked-context 來源 sibling-concern markers(per canonical §2 heuristic):
- **Issue body draft** — `also` / `additionally` / `related` / 「另外」 / 「順便」 / `BTW` 等 sister marker 暗示超出 primary scope 的旁支
- **Linked attachments** (per IC_R007 attachments policy) — 附件內部 reference 沒被帶進 body 的 sibling concern
- **Recent session conversation** — invocation 前 ~20 turn 的 orphan 提及(bug / refactor / observation 沒被捕捉)

Empty surface list = legitimate silent no-op(per canonical §4 `(none surfaced)`)。

**Per-step deviation**:
- **Light-touch surfacing** — per canonical §6, `/idd-issue` is light-touch (filing-active moment, double-prompt risk)。Heuristic 須**明顯命中** linked context 才 surface;乾淨的 single-issue invocation(無附件、無 scout history)預期 empty,直接跳過 audit trail 的 `(none surfaced)` 也可。
- **Parent direction** — Sibling issues reference the just-created `#NEW_ISSUE` as parent context, **NOT** vice versa。Just-created issue body stays focused on user's primary concern;sibling issue 的 title 用 `(sibling concern from #$NEW_ISSUE)` suffix,body 含 canonical §7 footer。
- **Audit trail target**:`### Linked-Context Siblings Filed (v2.48.0+ #529)` PATCHed into the just-created issue body(per canonical §4.1 heading conventions table)。 `(category: audit-block-append, scope: "### Linked-Context Siblings Filed")` per [`rules/append-vs-modify.md`](../../rules/append-vs-modify.md)。
- **Non-blocking** — user skip / empty list 都不阻擋 Step 5 報告完成。

**Default behavior (v2.72.0+)**: File by default per canonical §1.1。Skip requires 3-category taxonomy per canonical §1.4((a) unactionable / (b) infeasible → filed with `blocker:infeasible` / (c) blocked-on-external → filed with `blocker:waiting`)。Escape hatch(`AI_LOW_BAR_ISSUE_FILING=false` env var / `# Disable IC_R011` CLAUDE.md flag)reverts to legacy 3-option ask per canonical §5。

> **Why light-touch deviation**: per canonical §6 eligibility table, `/idd-issue` is SHALL-tier but light-touch(filing-active moment) — default file still applies, but heuristic gating prevents double-prompt friction on clean single-issue invocations。

### Step 4.8: Split Umbrella SOP (v2.54+, #11)

**When applies**: 將 umbrella issue 拆分為 N sub-issues 的場景(例如 `ai_martech_global_scripts #502 → #536-#541`)。**不適用** atomic issue / 一般 sister sweep。Trigger heuristic:
- 使用者明說「split #X 為 N 個 sub-issue」/「拆 #X umbrella」
- 同 session 連續用 `/idd-issue` 建 ≥3 個都 reference 同一 parent #X

**Why mandatory pre-flight**: umbrella 的 scope 1/2/3 等可能在 split session 之前**幾天前**已 commit / 已歸檔成 spectra change → 若不檢查就 file,N 個 sub-issue 中可能有 X 個從一開始就該 retroactive close,浪費 audit + close 工(`#502` 案例為證)。

**Pre-flight checks (per sub-issue candidate)**:

```bash
# 1. Scan commits since umbrella created — match parent ref
UMBRELLA_DATE=$(gh issue view "$UMBRELLA" --json createdAt --jq .createdAt)
git log --oneline --grep "#$UMBRELLA" --since="$UMBRELLA_DATE"

# 2. Scan commits 用 sub-scope keyword
git log --oneline --grep "<sub-scope keyword from umbrella body>" --since="$UMBRELLA_DATE"

# 3. Scan spectra archive
ls openspec/changes/archive/ 2>/dev/null | grep -i "<keyword>"

# 4. Read commit message trailers (e.g. "(#$UMBRELLA scope N)")
git log --oneline --grep "#$UMBRELLA scope" --since="$UMBRELLA_DATE"
```

任一 step 命中 → **AskUserQuestion**:

```
question: "Sub-issue candidate '<title>' 對應到 commit <hash> (<date>) — 已 shipped。怎麼處理?"
options:
  - file as retroactive tracker (close immediately with link to commit)
  - skip — work already done, no audit needed
  - file fresh (override, 表示 commit 不完整或要做 follow-up work)
```

**Audit trail**:不論選哪個,在 sub-issue body 加 `### Pre-flight scan (v2.54+ #11)` section 紀錄:
- 找到的 commits / archive entries
- 使用者選擇
- Reason

**Why this is SOP-only (不是新 skill / flag, per #11 diagnose option (c))**:
- Split umbrella 是**低頻** workflow,不值得新 skill 的 cognitive cost (per IDD anti-pattern: 「不在沒見過 N instance 之前抽 abstraction」)
- 防範動作是 mental check + 4 個簡單命令 — 寫進 SOP 即可,使用者背一次就會
- 若未來 ≥3 個重複 occurrences,自然演化為 `--split-from <#>` flag 或 dedicated skill

**Historical case**:`ai_martech_global_scripts #502` umbrella (2026-04-29 創建) split (2026-05-04) → #536/#537 為已 shipped (commit `7292219`, 2026-04-29) 工作,retroactive close 成本約 10 分鐘 audit + 2 個 closing summary。本 SOP 是該案例的 prevention 對策。

### Step 5: 回報並停止

輸出：issue number、URL、labels、type。
如果有 milestone：輸出 milestone name、URL、issue count。

**回顯 render 的詮釋（v2.64.0+, #103）**：除了上面的 metadata，**必須**把 AI 自己*產出*的詮釋回顯給使用者 —— issue body 的 `## Type` / `## Expected` / `## Actual` 三段 + plain-language interpretation。使用者已給過的逐字「Original text」不重複貼。

> **為什麼**：建 issue 是一個 NSQL `run → report` 操作（見 repo `CLAUDE.md`「Reference Projects: NSQL」）。建 issue 可逆，不需要 confirm gate；但 report 必須陳述「我做了什麼」，不只「它在哪」。回顯 AI render 的詮釋，讓 misparse（AI 把意圖讀錯）一眼可抓，不用點進 URL 才發現。

> **⚠ CI / `/loop` callers (v2.64.0+, #107)**: Step 5 terminal output expanded from metadata-only (`number / URL / labels / type`) to also echoing the rendered `## Type` / `## Expected` / `## Actual` + plain-language interpretation. If your script hard-parses Step 5 output for the metadata fields only, add a `-m 1` / first-N-lines guard or grep specifically for the `issue.*#NNN.*created` line — the new echo paragraphs follow it. (Parallel precedent: `--no-multi-finding` CI warning below.)

提示下一步：`/issue-driven-dev:idd-diagnose #NNN`

> **CRITICAL: 建立 issue 後必須停止。不要自動開始 diagnose 或 implement。**
> Issue 建立是人的決定點 — 人決定優先級、分配、時機。
> AI 不應該擅自開始解決問題。等使用者明確說「開始做」或呼叫 `idd-diagnose` 才繼續。

## Ordered Bundle Pattern(v2.52.0+)

當 N 個 issue 之間存在 **dependency 或 epic 關係**(schema 在 API 之前、phase 1 在 phase 2 之前、N 個 issue 同屬於一個 epic),用 bundle flags 一次成形;flag spec 完整定義見 [`references/bundle-flags.md`](../../references/bundle-flags.md)。

### 三種 GitHub-native bundle 模式對照

| 模式 | 順序強制 | GitHub UI 支援 | `idd-issue` 自動化 | 適合 |
|------|---------|---------------|------------------|------|
| **Parent + task list**(本 plugin 主推) | 手動標註 blocked by | ⭐⭐⭐ 渲染 sub-issues + 進度條 | `--parent` / `--bundle-mode` | 多數 ordered/unordered 情境 |
| **Native dependency**(GitHub 2024+) | ✅ 強制(UI 紅色 warning) | ⭐⭐⭐ 紅色 blocked banner | `--blocked-by` 自動嘗試 | 想要 hard gate 的依賴 |
| **Milestone**(分組,非依賴) | ❌ 不強制 | ⭐⭐ 列表 | Step 4.5 自動建(文件來源) | 鬆散順序、可平行 |

三軸正交:bundle 表達依賴、milestone 表達分組、group 表達跨 repo。一個 bundle 可以同時屬於 milestone。

### 三種使用情境

#### (a) 單 child 加進既存 parent

```bash
# parent #100 已存在,加第 4 個 child
idd-issue --parent 100 "Step 4: 接 email 通知"
# → 建 child #N + parent #100 task list 多一行 `- [ ] #N`(idempotent;重跑不會重複加)
```

加 dependency:

```bash
idd-issue --parent 100 --blocked-by 102 "Step 4: 接 email 通知"
# → child body 加 `> Blocked by #102`、嘗試 GraphQL native dep、parent task list entry 加 `(blocked by #102)` 註解
```

#### (b) 從零建完整 ordered bundle

```bash
idd-issue --bundle-mode ordered "做會員系統:建 schema; 加 API; 加 UI; 接 email"
# → 建 1 個 epic + 4 children
# → epic body task list 列出全部 4 個
# → child2 blocked by child1, child3 blocked by child2, child4 blocked by child3
```

無依賴版:

```bash
idd-issue --bundle-mode unordered "首頁優化:換 hero 圖; footer 對齊; 加暗色模式"
# → 建 epic + 3 children,純 task list,無 Blocked-by
```

#### (c) Retrofit:把已存在的散落 issue 重組成 bundle

沒有專屬 flag(超出本 change 範圍),手動兩步:

```bash
# 1. 建 epic + 編 task list 引用既存 issues
gh issue create --title "[Epic] 會員系統" --body "## Children
- [ ] #101 (建 schema)
- [ ] #102 (加 API)
- [ ] #103 (加 UI)"

# 2. 對每個 child 補 Blocked-by 標註
idd-issue --blocked-by 101 ...   # 不行 — idd-issue 是建新 issue,不是 edit 既存
# Retrofit 真要做要直接 gh issue edit,或之後另開 proposal 加 idd-issue-edit-bundle 之類
```

### 設計理由:為什麼不另開 `/idd-bundle` skill

考慮過另開新 skill 但選擇加 flag 到 `idd-issue`:

1. **70% 重疊**:bundle 仍要 target resolution(Step 0.5)、attachment upload(Step 4)、mention validation(Step 2.6)、sister sweep(Step 4.7)。複製這些邏輯成本高
2. **漸進式採用**:`--parent` 可獨立用、`--blocked-by` 可獨立用、`--bundle-mode` 是高階組合;三 flag 各有獨立用途
3. **Skill 數量已多**:IDD 已 14+ skills;新增 skill 的 cognitive cost 不值得 ~30% 獨特功能

完整設計理由見 `openspec/specs/idd-issue-bundle/spec.md` 的 Decision §1。

### 反模式

| 想做的 | 為什麼不行 | 改用 |
|--------|-----------|------|
| 「建一個 issue 列 10 個 todo」 | issue 是工作單位,bundling 後沒辦法獨立 close / triage / verify | 10 個 issue + 1 個 epic(`--bundle-mode`)|
| 「先建 epic issue,子任務之後再說」 | epic 在 GitHub 不是原生概念,容易腐爛;沒 task list 的 epic 是空殼 | 建 epic 同時建至少 2 個 child(`--bundle-mode`)|
| 「用 `--parent` 跨 repo 串 issue」 | GitHub task list 跨 repo 不連動進度條,語意被破壞 | 用 `groups` 機制(primary + tracking + cross-link)|
| 「`--bundle-mode` + `--target group:<label>`」 | 兩種機制 mental model 不同(parent-child vs cross-repo cross-link) | 選一個,refuse 同時 set |

## Multi-finding source mode(v2.55.0+)

當 source(transcript / docx / pdf / pasted text)含 **≥2 個獨立 findings** 且部分對應到既存 issues(該 amend 而非建新),走 multi-finding source mode。auto-trigger,backward compat。

> **為什麼有這個 mode**:處理 multi-finding source 時 user 常需要「把 finding 分流:有些開新 issue、有些 amend 既存 #N」。沒這個 mode 時退化成手動跑 N 次 atomic skill 或手敲 `gh api PATCH`(失去結構化 audit trail)。Lesley research 2026-05-09 case:5 個 amendments 用 5 次 `gh api PATCH` 浪費 2.5 min + 失 audit。本 mode 把 batch routing + dispatch 升格 first-class。
>
> **與 bundle mode 區別**:bundle 是**explicit 多 issue creation**(user 已知道要建 N 個 issue + 依賴關係);multi-finding 是 **source-driven mixed routing**(從 source 自動抽 findings,部分新建部分 amend 既存)。**互斥** — 同時 set 兩個 flag refuse。

### Auto-trigger

Step 1 source extraction 後:

```
if len(extracted_findings) >= 2:
  enter multi-finding mode (Stage 1-4 below)
else:
  fall through to single-issue mode (existing behavior unchanged)
```

**Override flags**:

- `--multi-finding` — 強制進 mode 即使 detect 1 finding(罕見:user 知 source 含多 finding 但 AI 沒抽到)
- `--no-multi-finding` — 強制跳 mode 即使 detect ≥2 findings,把整個 source 當一個 issue body

兩 flag 同時 set → refuse。`--bundle-mode` + multi-finding mode 同時觸發 → refuse(見「Mutual exclusion」段落)。

**Flag conflict detection layering (v2.67.0+, #77 Gap 1 / P1.1)** — flag-conflict refusal fires at **different layers** depending on whether both conflicting values are statically known:

| Conflict | Refused at | Why |
|----------|-----------|-----|
| `--multi-finding` + `--no-multi-finding` (both explicit flags) | **Step 0 arg-parse** | Both values known statically — refuse immediately without paying Stage 1 source extraction cost (potentially 30s+ for large docx/srt). |
| `--bundle-mode <m>` + `--multi-finding` (both explicit flags) | **Step 0 arg-parse** | Same — both static. Refuse before adapter load. |
| `--bundle-mode <m>` + multi-finding auto-trigger | **Post-Stage 1** | Auto-trigger detection requires Stage 1 extraction to count findings (≥2 threshold). Can't refuse earlier without Stage 1 having run. |

The general principle: explicit flag pairs refuse at the earliest layer where both values are knowable; auto-trigger detection necessarily waits for the trigger condition to be observable.

> **⚠ Behavioral change for automated / CI callers (v2.55.0+)**: pre-v2.55.0, `idd-issue source.docx` always produced exactly one issue (whole source as body). v2.55.0+ auto-enters multi-finding mode when the source has ≥2 findings — so a CI pipeline or `/loop` script that relied on single-issue output will now silently get multi-finding dispatch. **Automated / unattended callers expecting the legacy single-issue behavior MUST pass `--no-multi-finding` explicitly.**

### 4-Stage Pipeline

```
Stage 1: Extract findings (AI)
   ↓
Stage 2: Per-finding picker (user × N, AI surface top-3 candidates)
   ↓
Stage 3: Batch preview (single confirmation)
   ↓
Stage 4: Dispatch (warn-continue + audit trail)
```

#### Stage 1: Extract findings

AI 從 source 抽 paragraph-level findings,每筆含:

- `finding_id`: 1-indexed integer
- `finding_quote`: **verbatim** original text(no AI rewording — 同 IC_R007 source-preservation 紀律)
- `summary`: AI 1-3 句描述 finding 在講什麼

Granularity 預設 paragraph-level。AI MAY 合併連續同主題段落、MAY 把含 2+ 主題的單段拆開。

**Anchor heuristics for reproducibility (v2.67.0+, #80 Gap 1 / P3.1)** — the MAY clauses above are necessary for fluid source-shape adaptation but allow same source run twice to yield different finding counts (which crosses the ≥2 auto-trigger threshold → mode-switch). Apply these defaults to bound LLM nondeterminism:

- **Default**: preserve original paragraph granularity (no merge / no split)
- **Only split** if paragraph contains ≥3 clearly distinct topics AND topics are mutually independent (each can be a self-contained finding)
- **Only merge** if 2 consecutive paragraphs are on the same topic AND combined length < 200 characters

These anchors do not eliminate LLM variance — they reduce it for the typical case while preserving MAY semantics for genuinely ambiguous sources.

**Source path validation (v2.67.0+, #77 Gap 5 / Security F4)** — Stage 1 entry MUST canonicalize source paths and refuse paths outside the repo work tree. Re-uses Step 1 adapter discipline (see [Step 1: 讀取來源並保留所有原始資料](#step-1-讀取來源並保留所有原始資料)) — multi-finding mode does NOT bypass it. A path like `../../etc/passwd` MUST be refused before any file read, preventing the file's contents from leaking into issue body / jsonl audit trail.

**Source type 沿用 Step 1 既有 adapter**:docx / pdf / Telegram / Apple Mail / Apple Notes / pasted-text / md / srt(v2.67.0+, #79 Gap 3 — srt 作為 first-class adapter,不再隱式 mapped 到 pasted-text)。Adapter 切換對 multi-finding mode 透明。

#### Stage 2: Per-finding picker

對每個 finding,AI 先 surface candidate issues,再讓 user 選 routing。

**Step 2a — AI compute keyword overlap**:

```bash
# Extract noun phrases from finding quote + summary
NOUN_PHRASES=$(extract_keywords "$finding")  # e.g. "schultz scale 12 items environmental"

# Search candidate issues
gh issue list --repo "$GITHUB_REPO" --state open \
  --search "$NOUN_PHRASES" --limit 30 --json number,title,body
```

**Step 2b — Score 計算**:

```
title_overlap     = |finding_keywords ∩ candidate_title_tokens|
body_overlap      = |finding_keywords ∩ candidate_body[:300]_tokens|
max_possible_score = title_token_count × 2 + min(body_token_count, 300) × 1   ← (v2.67.0+, #80 Gap 2 REQ-3)
score             = (title_overlap × 2 + body_overlap × 1) / max_possible_score
```

`max_possible_score` denominator uses the **finding's own keyword set** as the basis: `title_token_count` is the number of finding keywords matched against title-position; `body_token_count` is the number of finding keywords matched against body-position (capped at 300 chars to bound score-window). This normalization yields scores in `[0, 1]` consistently — same candidate produces same absolute score across invocations (#80 Gap 2 REQ-3 — previously undefined `max_possible_score` allowed different LLM interpretations to display 0.42 vs 0.84 for the same candidate).

Top-3 by score.

**Degenerate-case picker shape (v2.67.0+, #80 Gap 3 / REQ-3)** — `gh issue list --search` may return fewer than 3 candidates. Dispatch:

| N candidates | Picker shape |
|-------------:|--------------|
| 0 | Skip top-3 picker entirely. Go directly to `[Other]` second-level picker (`[New issue]` / `[Skip]` / `[Merge]` / `[Pick free-text #N]` + new `[Back to top-3]`) |
| 1 | Show 1 candidate + `[Other]` (2-option AskUserQuestion) |
| 2 | Show 2 candidates + `[Other]` (3-option AskUserQuestion) |
| ≥3 | Show top-3 candidates + `[Other]` (existing 4-option, unchanged) |

This is purely a picker-shape contract — score computation and ranking unchanged.

**Step 2c — 4-option AskUserQuestion picker**:

```
question: "Finding {N} of {M}: \"{finding_quote first 80 chars}...\""
options:
  - "#{X} ({score})"           ← top-1 candidate
  - "#{Y} ({score})"           ← top-2 candidate
  - "#{Z} ({score})"           ← top-3 candidate
  - "Other"                    ← expands to second-level picker
```

選 `Other` → second-level AskUserQuestion:

```
options:
  - "New issue"                ← go through Step 3 normal idd-issue flow
  - "Skip this finding"        ← drop, no dispatch
  - "Merge with another finding" ← see § Merge mechanism
  - "Pick free-text #N"        ← AskUserQuestion for typed N
  - "Back to top-3"            ← (v2.67.0+, #77 Gap 4 / P2.3) return to first-level picker — for users who entered Other by mistake or changed mind after seeing second-level options
```

**Step 2d — Routing intent disambiguation(picked existing #N)**:

```
question: "Finding goes to #{picked}. What action?"
options:
  - "comment"           ← append new comment to #picked
  - "edit body"         ← modify #picked body
  - "update status"     ← call idd-update on #picked Current Status block
  - "skip — change my mind" ← back to picker
```

**Iron rule**: skill SHALL NOT auto-dispatch based on score。Routing 決定要 explicit user selection。

#### Stage 3: Batch preview

Stage 2 完成所有 findings 後 print 完整 dispatch table + single AskUserQuestion:

```
=== Multi-Finding Plan (10 findings → 8 actions, 2 skipped) ===
 1. [NEW]      "Schultz scale 12 items"               → /idd-issue
 2. [COMMENT]  "Lesley reputation 變 core IV"         → #14
 3. [EDIT]     "刪 H4-H6 cue hypotheses"              → #14
 4. [COMMENT]  "Conjoint paired-choice 重要性"         → #17
 5. [SKIP]     "(老師閒聊不相關)"                       —
 6. [NEW]      "問卷 §5b Schultz 加 12 題"             → /idd-issue
 7. [COMMENT]  "Prolific N=200-400 確認"               → #8
 8. [EDIT]     "JCP 1-study → 2-study budget"         → #6
 9. [MERGED:8] (combined into row 8)                   → #6
10. [COMMENT]  "Phase 4 dogfood 紀錄"                 → #48

[Execute all] [Edit row N] [Cancel]
```

- `[Execute all]` → 進 Stage 4 dispatch
- `[Edit row N]` → re-invoke Stage 2 picker for row N only,其他 rows 保留;re-pick 完成後回 Stage 3 preview
- `[Cancel]` → 退出 skill,**no GitHub side effect**,**no jsonl written**

**Edit-row loop soft cap (v2.67.0+, #77 Gap 3 / P2.2)** — after >5 cumulative `[Edit row N]` selections in a single Stage 3 cycle, prepend an additional confirmation prompt:

```
question: "You've edited 6 rows in this Stage 3 cycle. The picker may be drifting from the source intent. What now?"
options:
  - "Continue editing"   ← reset the counter, keep going
  - "Execute all"        ← exit to Stage 4 dispatch
  - "Cancel"             ← discard run, no GitHub side effect
```

Soft cap (warn-not-block) — user can `Continue editing` to opt out. The 5-row threshold is empirical heuristic; rationale is "if reviewer keeps revisiting same dispatch table, signal is more likely 'wrong source extraction' than 'still picking'."

#### Stage 4: Dispatch with warn-continue

Stage 3 confirm 後 sequential 跑 N 個 `gh` action:

| Action | Command |
|--------|---------|
| `create` | `gh issue create --title ... --body ...`(body 含 footer) |
| `comment` | `gh issue comment $N --body ...`(body 含 footer) |
| `edit` | `gh issue edit $N --body "$NEW_BODY_WITH_FOOTER"` |
| `update` | call `idd-update` skill on #N |
| `skip` | no-op |
| `merged-into` | no separate dispatch(content 已在 partner action body) |

**Warn-continue contract** (refined per /idd-verify --pr 71 round 1 P1.4):

- Per-action result is accumulated into **in-memory** `RUN_LOG_ENTRIES` array, NOT directly to disk
- 成功:append entry with `issue_number` / `issue_url` / `comment_url` / `duration_ms`
- 失敗:append entry with `error` + `retry_hint`,**continue** to next action(不 abort)
- 全部 dispatch 完成 → 進 Stage 4.5 gate → gate 決定 jsonl 命運:
  - `committed` / `not-applicable` / `bypass-env-var` → materialize jsonl to disk (one-shot `jq -n ... > $JSONL_PATH`)
  - `add-exception` → materialize jsonl + commit with `.gitignore` change (5-line carve-out chain with `!.claude` parent re-include — universal across all fixable sources) in same dispatch
  - `skip-commit` → materialize jsonl locally, no `git add`
  - `abort` → write minimal `aborted: true` jsonl (v2.67.0+, #79 Gap 1 / P3.2 disposition (a)) recording `actions[]` already dispatched + `started_at` / partial `completed_at`. File exists → footer link is valid → collaborators viewing already-dispatched GitHub bodies don't get 404. **In-memory entries beyond the abort point are still discarded** — the file shows "this run was aborted with N partial actions", not a full audit of pre-abort intent
- Summary line is printed after gate completes (with continuity status appended)

**No rollback**: 已 dispatch 的 GitHub actions **不**回滾(每筆是 user-confirmed 意圖,不是 AI 推論)。失敗的 user 自行手動補 dispatch(`retry_hint` 在 in-memory entry 給 hint;只在 jsonl materialized 時持久化)。Abort 模式下 in-memory entries 也丟,user 看 dispatch summary 看到哪些已 dispatch 即可手動追蹤。

**Agent-crash recovery semantics (v2.67.0+, #77 Gap 6 / REQ-5)** — if the Claude agent crashes between Stage 4 dispatch and Stage 4.5 materialization, the in-memory `RUN_LOG_ENTRIES` array is lost. GitHub actions already dispatched (footer links written) but jsonl never materializes → partial audit trail.

**Documented as a known gap (not auto-recovered)**: the trade-off is between (a) persisting `RUN_LOG_ENTRIES` incrementally to a temp file (extra I/O on every Stage 4 step, write-on-failure semantics) and (b) accepting partial-trail-on-crash. v2.67.0+ chooses (b) — the failure mode is rare in interactive use, and the recovery action is observable: user sees GitHub bodies with footer links pointing to a jsonl file that doesn't exist (or doesn't have the dispatched action recorded).

Recovery workflow:
1. User notices footer link 404 (file doesn't exist) or grep'ing jsonl for the `comment_url` returns no match
2. User manually re-runs `/idd-issue --multi-finding <source>` from scratch — the dispatched GitHub actions are now duplicates of what the crashed run already did. Idempotency at GitHub side is the responsibility of the user (manual reconciliation).
3. Future enhancement (deferred): incremental persistence to `.claude/.idd/issue-runs/.<run_id>.partial.jsonl` flushed on each Stage 4 success/failure — would be N additional `fsync` calls per dispatch. Not implemented in v2.67.0+ pending observed need.

**Unattended-mode fallback for Stage 4.5 gate (v2.67.0+, #77 Gap 7)** — when `/loop` / CI / non-interactive callers run multi-finding mode without `IDD_JSONL_GITIGNORE_GATE=false`, the Stage 4.5 AskUserQuestion has no responder. Default fallback to prevent infinite hang:

```bash
# Add at top of Stage 4.5 gate (before AskUserQuestion):
if [ -z "${JSONL_GITIGNORE_DECISION:-}" ] && [ ! -t 0 ] && [ -n "${IDD_ALL_UNATTENDED:-}${CI:-}" ]; then
  # No TTY AND we're in /idd-all unattended chain OR a CI environment.
  # Auto-select "skip-commit" as the safest default — jsonl writes locally
  # but isn't committed, no .gitignore change. Audit trail still produced
  # locally for whoever runs the unattended job.
  JSONL_GITIGNORE_DECISION="skip-commit"
  echo "ℹ Stage 4.5 gate auto-defaulted to 'skip-commit' under unattended mode (no TTY + IDD_ALL_UNATTENDED/CI)." >&2
fi
```

The `IDD_JSONL_GITIGNORE_GATE=false` env var bypass remains the **explicit** escape hatch (1-line audit `bypass-env-var`); this unattended fallback is the **implicit** safety net for callers who forget to set it.

#### Stage 4.5: jsonl gitignore pre-flight gate (v2.58+, #55)

**Why this step**: D2 spec contract states "JSONL run log SHALL be committed to git by default". But repos that `.gitignore` the `.claude/` directory (common IDE-config pattern, e.g. `kiki830621/teaching_lesley`) silently swallow `.claude/.idd/issue-runs/<run_id>.jsonl` — `git status` shows nothing untracked, cross-machine continuity assumption broken. Gate detects + lets user decide BEFORE jsonl write.

**Rule**: Fires ONCE per dispatch batch (decision cached in `$JSONL_GITIGNORE_DECISION` for the run). Detection uses `git check-ignore -v` to honor all `.gitignore` precedence rules AND surface which source matched (repo `.gitignore`, `.git/info/exclude`, or global `core.excludesfile`) — the remediation strategy differs per source.

**Ordering invariant** (per /idd-verify --pr 71 round 1 P1.4): execution order is **dispatch → gate → materialize**:

1. **Stage 4 dispatch** loop iterates the planned `gh issue create/comment/edit` actions, accumulating each result (success / failure with `retry_hint`) into in-memory `RUN_LOG_ENTRIES` array — NOT to disk yet
2. **Stage 4.5 gate** fires AFTER the dispatch loop completes (or on early abort within the loop). Decides jsonl materialization fate per `JSONL_GITIGNORE_DECISION`
3. **Materialize**: only if gate decision is `committed` / `not-applicable` / `bypass-env-var` / `add-exception` / `skip-commit` does the jsonl actually get written via one-shot `jq -n ... > $JSONL_PATH`. `abort` discards in-memory entries; jsonl never reaches disk.

The name "Stage 4.5" indicates "gate fires after Stage 4 dispatch loop, before jsonl persistence". Already-dispatched GitHub actions are NOT rolled back on `abort` (they're committed user intent from Stage 3 confirmation) — but the local audit artifact (jsonl) is suppressed.

##### Detection (bash)

```bash
# RUN_ID format (v2.67.0+, #76): ISO-8601 with millisecond precision + UTC Z suffix.
# Pre-v2.67.0 second-precision format collided under parallel `/loop` / CI batch /
# two-terminal invocations — same-second invocations produced identical filename →
# silent audit-trail overwrite (D2 "per-invocation 一檔" contract silently violated).
# This is the irreversible-side-effect failure mode (#103 F4 Layer P vocabulary).
#
# Platform NOTE: GNU date supports `%3N` (millisecond truncation), but BSD date
# (macOS native `/bin/date`) does NOT — it silently emits the literal string
# `3N` instead of erroring. So `2>/dev/null || fallback` is NOT a working
# fallback chain on macOS. The correct dispatch is: try GNU `%3N`, then
# validate the output shape, fall through to nanosecond-then-truncate using
# `%N`-supporting platforms, then absolute fallback to `.000Z`.
RUN_ID_RAW="$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null || true)"
if [[ "$RUN_ID_RAW" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z$ ]]; then
  RUN_ID="$RUN_ID_RAW"   # GNU date with %3N succeeded
elif command -v python3 >/dev/null 2>&1; then
  # BSD date emitted literal "3N" or otherwise malformed — fall back to Python
  # which has UTC ms-precision via datetime stdlib on every platform.
  RUN_ID="$(python3 -c 'import datetime; print(datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.") + f"{datetime.datetime.now(datetime.timezone.utc).microsecond // 1000:03d}Z")')"
else
  # No python3 — last-resort `.000Z` second-precision (sortable, but defeats
  # the nonce-retry rationale below; user should install python3 for full
  # collision resistance).
  RUN_ID="$(date -u +%Y-%m-%dT%H:%M:%S.000Z)"
  echo "⚠ run_id falling back to .000Z second-precision (no GNU date %3N, no python3) — collision resistance reduced." >&2
fi
JSONL_PATH=".claude/.idd/issue-runs/${RUN_ID}.jsonl"

# Symlink check (v2.67.0+, #76 TOCTOU MEDIUM): predictable filename at known path
# means an attacker with local FS write access can pre-create the path as a symlink
# pointing at e.g. ~/.ssh/authorized_keys. `jq -n ... > $JSONL_PATH` truncate-writes
# follows symlinks → silent target clobber. Fail-closed before any write.
# Note: symlinking the issue-runs/ directory itself (e.g. to mount on different FS)
# is fine — only the per-run jsonl FILE must not pre-exist as a symlink.
if [ -L "$JSONL_PATH" ]; then
  echo "✗ ABORT: $JSONL_PATH exists as a symlink — refusing to truncate-write a symlinked audit artifact."
  echo "  This is a TOCTOU hardening gate (#76 v2.67.0+). Investigate before proceeding."
  exit 1
fi

# Collision-detect via noclobber (v2.67.0+, #76 P1 HIGH): even with ms-precision
# run_id, very tight parallel invocation (bash for-loop within same ms) could
# still collide. `set -C` causes redirect to fail if target exists — retry with
# random suffix. Combined with symlink-check above and ms-precision run_id, this
# closes the collision channel even under hostile concurrency.
#
# NONCE SPACE NOTE: bash `$RANDOM` is 15-bit (range 0-32767), NOT 16-bit.
# Birthday-paradox collision threshold within the same ms is therefore
# ~sqrt(32768) = ~181 concurrent invocations, not ~256. Second-collision
# abort defends; threat model is "audit overwrite", not "audit forge".
JSONL_WRITE_GUARD() {
  # Called at RUN-START (right after RUN_ID is set) to lock the canonical
  # filename used by all footer composition. NOT called at materialize phase —
  # mutating the path at materialize would invalidate the footer URLs already
  # written to GitHub bodies by Stage 4 dispatch (#79 Gap 1 disposition
  # depends on footer URL stability).
  if [ -e "$JSONL_PATH" ]; then
    local nonce
    nonce=$(printf '%04x' $(( RANDOM % 32768 )))   # bash $RANDOM is 15-bit
    RUN_ID="${RUN_ID%.???Z}-${nonce}"
    JSONL_PATH=".claude/.idd/issue-runs/${RUN_ID}.jsonl"
    echo "⚠ run_id collision detected, retrying with nonce suffix: $RUN_ID" >&2
    if [ -e "$JSONL_PATH" ]; then
      echo "✗ ABORT: jsonl write would clobber existing file even after nonce retry: $JSONL_PATH" >&2
      exit 1
    fi
  fi
}

# CRITICAL ORDERING (v2.67.0+ #76 fix + #79 Gap 1 dependency):
# Invoke JSONL_WRITE_GUARD HERE, BEFORE Stage 4 dispatch composes the footer
# URL. The footer URL `> **Run log**: .claude/.idd/issue-runs/<run_id>.jsonl`
# must point at the SAME path the materialize phase writes. If WRITE_GUARD ran
# at materialize phase only, a nonce-retry would mutate $JSONL_PATH AFTER
# Stage 4 dispatch baked the original path into footer URLs → footer 404.
# Running at run-start locks the canonical path; Stage 4 footer + Stage 4.5
# materialize + Stage 4.5 abort-path all use the same $JSONL_PATH variable.
JSONL_WRITE_GUARD

# Cache the gate decision for this dispatch batch — gate fires once, not per-issue.
if [ -z "${JSONL_GITIGNORE_DECISION:-}" ]; then
  # Escape hatch: env var bypass for CI / unattended runs.
  # Per /idd-verify --pr 71 round 1 P1.1 — must implement bypass in detection, not just doc-claim it.
  if [ "${IDD_JSONL_GITIGNORE_GATE:-}" = "false" ]; then
    JSONL_GITIGNORE_DECISION="bypass-env-var"
  # Outside git work tree? `git rev-parse` returns non-zero — gate is not applicable.
  elif ! git rev-parse --git-dir > /dev/null 2>&1; then
    JSONL_GITIGNORE_DECISION="not-applicable"   # not in a git repo; jsonl writes as local file, no commit attempt
  else
    # Run `git check-ignore -v` to also capture WHICH source matched (repo .gitignore vs global excludesfile).
    IGNORE_SOURCE=$(git check-ignore -v "$JSONL_PATH" 2>/dev/null)
    if [ -n "$IGNORE_SOURCE" ]; then
      # IGNORED — capture source for remediation strategy (agent reads $IGNORE_SOURCE in AskUserQuestion).
      # Example: ".gitignore:1:.claude/        .claude/.idd/issue-runs/test.jsonl"
      # Example: ".git/info/exclude:1:.claude/ .claude/.idd/issue-runs/test.jsonl"
      # Example: "/Users/X/.config/git/ignore:1:.claude/  .claude/.idd/issue-runs/test.jsonl" (global)
      # Example: ".claude/.gitignore:1:*       .claude/.idd/issue-runs/test.jsonl" (nested — UNSUPPORTED for add-carve-out)
      #
      # Classify the source so the agent can offer the right options:
      #   IS_NESTED_GITIGNORE=true  → carve-out in root .gitignore CANNOT override a nested
      #                               .gitignore (e.g. .claude/.gitignore). Per /idd-verify --pr 71
      #                               round 4 P1.2, empirically validated: a root-level rewrite
      #                               leaves the nested rule in force, jsonl stays ignored.
      #                               AskUserQuestion drops "Add carve-out" option → 2-option (skip/abort).
      #   IS_NESTED_GITIGNORE=false → root .gitignore, .git/info/exclude, or global core.excludesfile
      #                               — all fixable by writing the 5-line carve-out block into root
      #                               `.gitignore` (the `!.claude` parent re-include neutralizes any
      #                               outer source via git's last-matching rule).
      SOURCE_FILE=$(printf '%s\n' "$IGNORE_SOURCE" | awk -F: '{print $1}')
      IS_NESTED_GITIGNORE=false
      # ORDER MATTERS (per /idd-verify --pr 71 round 5 P1.2): the `*/.gitignore`
      # glob matches absolute paths like `/Users/X/.config/git/ignore` when
      # `core.excludesfile` is named `.gitignore`. Test absolute paths FIRST
      # so global excludesfile never falls into the nested branch.
      case "$SOURCE_FILE" in
        /*)                          IS_NESTED_GITIGNORE=false ;;  # absolute → global ignore (fixable by 5-line in root)
        .git/info/exclude)           IS_NESTED_GITIGNORE=false ;;  # repo-local but separate from .gitignore (fixable)
        .gitignore)                  IS_NESTED_GITIGNORE=false ;;  # root .gitignore (fixable)
        */.gitignore)                IS_NESTED_GITIGNORE=true  ;;  # nested .gitignore (NOT fixable from root)
        *)                           IS_NESTED_GITIGNORE=false ;;  # other repo-local → defensive fixable
      esac
      # Agent branches at agent level — see AskUserQuestion section below.
      : # JSONL_GITIGNORE_DECISION set by user choice next
    else
      JSONL_GITIGNORE_DECISION="committed"   # not ignored, silent pass
    fi
  fi
fi
```

| `JSONL_GITIGNORE_DECISION` value | Semantic |
|----------------------------------|----------|
| `committed` | jsonl path NOT ignored — proceed with normal write + commit |
| `not-applicable` | outside git work tree — jsonl written as local file, no commit attempt |
| `bypass-env-var` | `IDD_JSONL_GITIGNORE_GATE=false` set — same as `committed` but audit cites env var |
| (unset → enters AskUserQuestion) | ignored, source captured in `$IGNORE_SOURCE` for agent prose |

If decision is `committed` / `not-applicable` / `bypass-env-var` → silent pass with 1-line audit. **Stage 4 dispatch has already completed at this point** (per dispatch→gate→materialize ordering invariant above) — the gate is the green light for materializing the in-memory `RUN_LOG_ENTRIES` to disk as the jsonl file. No further dispatch work needed;proceed to materialization.

If detection found ignore shadow → enter the AskUserQuestion deliberation moment described next.

##### AskUserQuestion 3-option (prose — agent-level, NOT bash)

> **Why prose**: AskUserQuestion is a Claude Code agent-level tool, not a bash function. Embedding `AskUserQuestion(...)` inside bash was a category error caught in /idd-verify #47 P1 finding 2. Same pattern applies here — agent reads bash detection, branches at agent level on detection result, then handles deliberation as prose.

When detection returns "ignored", agent branches on `$IS_NESTED_GITIGNORE`:

**Case A — `IS_NESTED_GITIGNORE=false`** (source is root `.gitignore`, `.git/info/exclude`, or global `core.excludesfile`) → 3-option prose:

> "Multi-finding dispatch will write run log to `.claude/.idd/issue-runs/<run_id>.jsonl`, but `${SOURCE_FILE}` shadows `.claude/` (D2 contract violated: jsonl can't reach git). Choose:"
>
> Options (default = first;agent emits `$IGNORE_SOURCE` in question so user can see WHICH gitignore source matched):
> - **`Add carve-out chain to .gitignore`** — rewrite repo `.gitignore` to replace bare `.claude/` with the 5-line carve-out block (`!.claude` parent re-include + `.claude/*` + `!.claude/.idd` + `.claude/.idd/*` + `!.claude/.idd/issue-runs`). The `!.claude` parent re-include neutralizes any outer ignore source (`.git/info/exclude` or global `core.excludesfile`) via git's last-matching rule. Idempotent (re-run safe via marker comment).
> - **`Skip commit (local-only)`** — write jsonl locally but don't `git add`;dispatch summary flags ⚠ cross-machine continuity gap + manual export command.
> - **`Abort`** — discard in-memory run log + exit dispatch BEFORE any jsonl materialization. Already-dispatched GitHub actions (gh issue create / comment / edit) remain (NOT rolled back per "No rollback" rule above — but the JSONL file never reaches disk).

**Case B — `IS_NESTED_GITIGNORE=true`** (source is a nested `.gitignore` such as `.claude/.gitignore`) → **`Add carve-out` option is NOT offered** (a root-level rewrite cannot override a nested `.gitignore`; the user must edit the nested source themselves or accept local-only). 2-option prose:

> "Multi-finding dispatch will write run log to `.claude/.idd/issue-runs/<run_id>.jsonl`, but nested `${SOURCE_FILE}` shadows it (D2 contract violated). A root-level `.gitignore` carve-out CANNOT override a nested `.gitignore` (git evaluates per-directory rules in scope; the nested file wins for paths beneath it). To use the Add-carve-out path you'd need to edit `${SOURCE_FILE}` yourself. Choose:"
>
> Options (default = first):
> - **`Skip commit (local-only)`** — write jsonl locally but don't `git add`;dispatch summary flags ⚠ cross-machine continuity gap + manual export command + `${SOURCE_FILE}` location.
> - **`Abort`** — discard in-memory run log + exit dispatch BEFORE any jsonl materialization. Already-dispatched GitHub actions remain.

Set `JSONL_GITIGNORE_DECISION` per user choice. Then proceed:

```bash
case "$JSONL_GITIGNORE_DECISION" in
  "add-exception")
    # CRITICAL git limitation (per git docs):
    #   "It is not possible to re-include a file if a parent directory of
    #    that file is excluded. Git doesn't list excluded directories for
    #    performance reasons, so any patterns on contained files have no
    #    effect, no matter where they are defined."
    #
    # Empirically: single-line `!.claude/.idd/issue-runs/` does NOT work
    # when `.claude/` is excluded as a directory. We must rewrite `.claude/`
    # to NOT exclude the directory itself (use `.claude/*` pattern) and
    # carve out each parent dir on the path to issue-runs.
    #
    # ALWAYS-5-LINE BLOCK (per /idd-verify --pr 71 round 4 P1.1):
    # Multiple ignore sources can stack — root `.gitignore` may carry `.claude/`
    # AND `.git/info/exclude` (or global `core.excludesfile`) may also carry it.
    # `git check-ignore -v` only reports the highest-precedence source, so a
    # 4-line block that only handles the reported source still loses to a
    # lower-precedence source that emerges after we sed-out the root pattern.
    #
    # The fix: always emit the 5-line block. The leading `!.claude` line uses
    # git's last-matching rule to re-include `.claude/` regardless of any
    # outer ignore source. The downstream `.claude/*` keeps everything else
    # ignored, and the carve-out re-includes only the run-log path.
    # Empirically validated against {root .gitignore, .git/info/exclude, global,
    # global + root combined, .git/info/exclude + root combined} — all 5/5 pass.
    #
    # CALLER PRECONDITION: this case branch only runs when IS_NESTED_GITIGNORE=false.
    # Nested `.gitignore` (e.g. `.claude/.gitignore`) cannot be fixed from root —
    # the AskUserQuestion prose drops the Add-carve-out option in that case, so
    # we'll never reach here with a nested source.
    GITIGNORE_FILE=".gitignore"

    REWRITE_BLOCK=$(cat <<'BLOCK'
# IDD multi-finding run log carve-out (idd-issue Stage 4.5, #55)
# `.claude/` is excluded by some ignore source (root .gitignore, .git/info/exclude,
# or global core.excludesfile). The `!.claude` line re-includes the parent
# directory itself via git's last-matching rule (neutralizes any outer source),
# then `.claude/*` re-excludes everything inside, and the carve-out re-includes
# only the run-log path. Other contents of .claude/ remain ignored.
!.claude
.claude/*
!.claude/.idd
.claude/.idd/*
!.claude/.idd/issue-runs
BLOCK
)

    # Idempotency + upgrade: detect both presence of marker AND that the block
    # contains the universal `!.claude` parent re-include line (per /idd-verify
    # --pr 71 round 5 P1.1). The marker alone is insufficient — older versions
    # of this skill emitted a 4-line block with the SAME marker but missing
    # `!.claude`, which still loses to stacked ignore sources. We upgrade in
    # place: if marker present BUT `!.claude` line absent, drop the old block
    # entirely (delete lines from marker through the next blank line / EOF)
    # then re-append the current universal 5-line block.
    # `grep -c` exits non-zero on no-match while still printing "0", so `|| echo 0`
    # would emit "0\n0" and break the `-ge 1` integer test. Pipe to `wc -l` instead —
    # always yields a clean integer (0 if grep finds nothing or file is absent).
    HAS_MARKER=$(grep -xF "# IDD multi-finding run log carve-out (idd-issue Stage 4.5, #55)" "$GITIGNORE_FILE" 2>/dev/null | wc -l | tr -d ' ')
    HAS_PARENT_REINCLUDE=$(grep -xF "!.claude" "$GITIGNORE_FILE" 2>/dev/null | wc -l | tr -d ' ')
    NEEDS_REWRITE=true
    if [ "$HAS_MARKER" -ge 1 ] && [ "$HAS_PARENT_REINCLUDE" -ge 1 ]; then
      # Both marker and the universal `!.claude` line already present → block is
      # already the current universal form, skip rewrite.
      NEEDS_REWRITE=false
    elif [ "$HAS_MARKER" -ge 1 ]; then
      # Stale block detected — drop it before re-appending the universal block.
      # State machine (per /idd-verify --pr 71 round 6 P1.1):
      #   STATE 0: outside block — print line
      #   STATE 1: just saw marker, in "header" — only consume # comments adjacent
      #            to marker (the rationale comments we emit) UNTIL first
      #            carve-out pattern line; any non-# / non-pattern line ENDS skip
      #   STATE 2: saw a carve-out pattern — only consume more known patterns;
      #            after consuming the FINAL pattern `!.claude/.idd/issue-runs`,
      #            END skip
      #
      # CRITICAL: do NOT consume blank lines or arbitrary # comments past STATE 1.
      # If user has `\n# User section` immediately after our stale block, the
      # blank line ends skip — user content preserved (round 6 P1.1 regression).
      awk -v marker="# IDD multi-finding run log carve-out (idd-issue Stage 4.5, #55)" '
        function is_block_pattern(line) {
          return (line == "!.claude" \
               || line == ".claude/*" \
               || line == "!.claude/.idd" \
               || line == ".claude/.idd/*" \
               || line == "!.claude/.idd/issue-runs")
        }
        $0 == marker { skip = 1; state = 1; next }
        skip && state == 1 {
          if ($0 ~ /^#/) { next }                      # rationale comment — consume
          if (is_block_pattern($0)) { state = 2; next } # entered patterns
          skip = 0                                      # anything else ends skip
        }
        skip && state == 2 {
          if ($0 == "!.claude/.idd/issue-runs") {       # last pattern → consume and END
            skip = 0
            next
          }
          if (is_block_pattern($0)) { next }            # intermediate pattern — consume
          skip = 0                                      # anything else ends skip
        }
        { print }
      ' "$GITIGNORE_FILE" > "$GITIGNORE_FILE.tmp"
      mv "$GITIGNORE_FILE.tmp" "$GITIGNORE_FILE"
    fi
    if [ "$NEEDS_REWRITE" = "true" ]; then
      # Remove any existing bare `.claude/` or `.claude` line (we're rewriting that
      # pattern to `.claude/*` which behaves differently per git docs). Use sed -E
      # for portable BSD/GNU compatibility; rewrite via tempfile to handle the
      # no-inplace case. Touch first to handle the no-`.gitignore`-yet case
      # (sed errors on missing file → would abort under `set -e`).
      touch "$GITIGNORE_FILE"
      sed -E '/^\.claude\/?$/d' "$GITIGNORE_FILE" > "$GITIGNORE_FILE.tmp"
      mv "$GITIGNORE_FILE.tmp" "$GITIGNORE_FILE"
      # Append carve-out at EOF. If file is now empty, emit without leading newline.
      if [ -s "$GITIGNORE_FILE" ]; then
        printf '\n%s\n' "$REWRITE_BLOCK" >> "$GITIGNORE_FILE"
      else
        printf '%s\n' "$REWRITE_BLOCK" > "$GITIGNORE_FILE"
      fi
    fi
    # .gitignore change is committed together with the jsonl materialization below
    ;;
  "skip-commit")
    # jsonl will be written but not `git add`ed — dispatch summary shows warning
    ;;
  "abort")
    # v2.67.0+ #79 Gap 1 disposition (a): write MINIMAL `aborted: true` jsonl with
    # actions already dispatched + partial timestamps. File EXISTS → footer link
    # written by Stage 4 to GitHub bodies is now valid (no 404). Already-dispatched
    # GitHub actions remain in flight — Stage 3 user confirmation, no rollback.
    #
    # In-memory entries beyond the abort decision point are still discarded —
    # the file shows "this run was aborted with N partial actions", NOT a full
    # pre-abort audit.
    #
    # Order matters: WRITE_GUARD runs BEFORE jq write to avoid nonce-collision
    # path mutation invalidating the footer URL composed in Stage 4 dispatch.
    # (WRITE_GUARD already ran at Stage 4.5 top to lock the canonical RUN_ID
    # used by all footer composition;here it's a defensive re-check only.)
    JSONL_WRITE_GUARD
    jq -n \
      --arg run_id "$RUN_ID" \
      --arg source "$SOURCE_LABEL_SANITIZED" \
      --arg source_type "$SOURCE_TYPE" \
      --argjson total "$TOTAL_FINDINGS" \
      --argjson actions "$RUN_LOG_ENTRIES_JSON" \
      --arg started "$STARTED_AT" \
      --arg completed "$(date -u +%Y-%m-%dT%H:%M:%S.%3NZ 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%S.000Z)" \
      '{run_id: $run_id, aborted: true, source: $source, source_type: $source_type, total_findings: $total, actions: $actions, started_at: $started, completed_at: $completed, succeeded: 0, failed: 0, skipped: 0}' \
      > "$JSONL_PATH"
    echo "Dispatch aborted at Stage 4.5 gate." >&2
    echo "Minimal aborted jsonl written: $JSONL_PATH" >&2
    echo "Already-dispatched GitHub actions remain — no rollback. Footer links in those bodies" >&2
    echo "now point at the aborted jsonl (valid file, aborted: true marker for downstream readers)." >&2
    exit 0
    ;;
  "bypass-env-var")
    # Env var bypass: silent skip the prompt, write jsonl with 1-line audit citing the var.
    # (Audit line emitted in dispatch summary template — see Stage 4.5 summary section.)
    ;;
  "not-applicable")
    # Outside git work tree: jsonl writes as local file, no commit attempted.
    # Dispatch summary shows "Not applicable" status (no continuity contract to violate).
    ;;
  "committed")
    # Standard path: jsonl path not ignored, write + commit normally.
    ;;
esac
```

> **Why a 5-line carve-out, not a 1-line exception or a source-dependent 4/5 split**:
>
> - **1-line `!.claude/.idd/issue-runs/` exception doesn't work**: discovered empirically during this implementation's TDD reproduction (2026-05-11). git docs are explicit — "any patterns on contained files have no effect" when the parent directory is excluded.
> - **4-line block (no `!.claude`) is fragile**: when multiple ignore sources stack (root `.gitignore` + `.git/info/exclude`, or root + global `core.excludesfile`), `git check-ignore -v` only reports the highest-precedence one. After we sed-out the root pattern, a lower-precedence source emerges and the 4-line block can't reach the parent directory (per round-4 P1.1).
> - **5-line block (with `!.claude`) is universal**: the leading `!.claude` line uses git's last-matching rule to re-include `.claude/` regardless of any outer ignore source; the `.claude/*` and following carve-out lines keep everything except the run-log path ignored. Empirically validated against all stacked-source combinations.
> - **Nested `.gitignore` (e.g. `.claude/.gitignore`) is NOT supported by Add-carve-out**: a root-level rewrite cannot override a nested `.gitignore` (git's per-directory scope rules). The AskUserQuestion prose drops the Add-carve-out option in that case and offers skip/abort only.
>
> Marker comment line at top of block makes the rewrite idempotent on re-run.

##### Failure modes

| Scenario | `JSONL_GITIGNORE_DECISION` | Behavior |
|----------|---------------------------|----------|
| Outside git work tree | `not-applicable` | jsonl writes as local file, no commit attempt;dispatch summary "Status: not applicable (outside git work tree)" |
| `.claude/` not ignored | `committed` | silent pass — Stage 4 dispatch materializes jsonl normally + commits |
| Root `.gitignore` ignores `.claude/` + user picks Add carve-out | (user choice) | 5-line carve-out block appended to `.gitignore` (with idempotency marker);both `.gitignore` change and jsonl commit in dispatch |
| `.git/info/exclude` ignores `.claude/` + user picks Add carve-out | (user choice) | Same 5-line block written to **root `.gitignore`** (not `.git/info/exclude`). The `!.claude` line re-includes the parent dir via git's last-matching rule; outer source is neutralized |
| Global `core.excludesfile` ignores `.claude/` + user picks Add carve-out | (user choice) | Same 5-line block written to root `.gitignore` — repo-local override of global ignore via `!.claude` re-include |
| **Nested `.gitignore` (e.g. `.claude/.gitignore`) ignores `.claude/.idd/...`** | (user choice) | **Add carve-out option NOT offered** — root rewrite cannot override per-directory ignore. AskUserQuestion presents skip/abort + tells user the nested source path so they can edit it manually if desired |
| Ignored + user picks Skip commit (local-only) | (user choice) | jsonl written locally, no `git add`;dispatch summary flags ⚠ cross-machine gap + manual export command + ignore source path |
| Ignored + user picks Abort | (user choice) | In-memory run log discarded BEFORE materialization;dispatch summary shows aborted;already-dispatched GitHub actions remain |
| Bypass via env var | `bypass-env-var` | `IDD_JSONL_GITIGNORE_GATE=false` → silent skip prompt (detection still runs for audit cite);1-line audit `Stage 4.5 gate bypassed (IDD_JSONL_GITIGNORE_GATE=false)` — for CI / unattended runs |
| `git check-ignore -v` parse failure | (fallback) | If `$IGNORE_SOURCE` empty or unparseable, default `IS_NESTED_GITIGNORE=false` (assume fixable source) — better to attempt the 5-line block than refuse all options |

### Audit trail(雙軌:footer + jsonl)

#### Per-action body footer

每個 dispatched issue body / comment 結尾(用 `---` separator)加:

```markdown
---
> **Surfaced via**: /idd-issue multi-finding mode <run_id> from `<source>`
> **Action**: {create|comment|edit|update} (v2.67.0+, #79 Gap 2 — reader can identify dispatch shape without cross-referencing jsonl)
> **Run log**: `.claude/.idd/issue-runs/<run_id>.jsonl` (may be invalid on abort/skip-commit — see Stage 4.5 disposition)
```

- `<run_id>`: ISO-8601 timestamp with millisecond precision + optional random suffix, e.g. `2026-05-10T17:00:00.123Z` or `2026-05-10T17:00:00-a3f9` (v2.67.0+, #76 — second-precision collides under parallel `/loop` / CI batch / concurrent terminals → silent audit-trail overwrite, the **irreversible side effect** failure mode added to Layer P vocabulary in v2.64.0 #103 F4)
- `<source>`: 源 file path(e.g. `communications/recordings/0509-research.srt`)或 `pasted-text:<first-30-chars>` — 注意 `<source>` 字面值通過 `sanitize_source_label()` 處理(see § Content sanitization contract below;v2.67.0+, #75 F2)

#### JSONL run log

`.claude/.idd/issue-runs/<run_id>.jsonl` 每次 invocation 一檔。**Commit 進 git**(不 gitignore),確保 cross-machine continuity。

> **CAUTION: `finding_quote` fields contain verbatim source content (per IC_R007 line 1007); treat as untrusted.** Verbatim quotes may contain control characters / ANSI escapes / bidi-override characters (U+202D-U+202E) that can hijack terminals when cat'ed. Sanitize before any human-facing display. The body-composition path uses a sanitized variant via `finding_quote_display`; jsonl preserves verbatim for audit fidelity. (v2.67.0+, #75 F1 + IC_R007 dual-track contract)

Schema:

```typescript
type RunLog = {
  run_id: string;          // ISO-8601 with millisecond precision + optional nonce, e.g. "2026-05-10T17:00:00.123Z" or "2026-05-10T17:00:00-a3f9" (v2.67.0+, #76 — sub-second collision-resistant)
  aborted?: boolean;       // (v2.67.0+, #79 Gap 1) present + true when Stage 4.5 user picked Abort; partial actions[] still recorded for audit trail consistency
  source: string;          // file path or "pasted-text:..."
  source_type: "docx" | "pdf" | "telegram" | "apple-mail" | "apple-notes" | "pasted-text" | "md" | "srt";  // (v2.67.0+, #79 Gap 3) "srt" added as first-class enum; transcript / subtitle sources adopting srt extension previously serialized as "pasted-text" via implicit adapter mapping
  total_findings: number;
  actions: Action[];
  started_at: string;      // ISO-8601 (millisecond precision)
  completed_at: string;    // ISO-8601 (millisecond precision)
  succeeded: number;
  failed: number;
  skipped: number;
};

type Action = {
  finding_id: number;        // 1-indexed
  finding_quote: string;     // verbatim from source
  action: "create" | "comment" | "edit" | "update" | "skip" | "merged-into";
  issue_number?: number;
  issue_url?: string;
  comment_url?: string;
  duration_ms?: number;
  merged_from?: number[];    // present on primary entry of a merge: [partner_finding_id]
  merged_into?: number;      // present on partner entry (action="merged-into")
  error?: string;
  retry_hint?: string;
  reason?: string;           // for action="skip"
};
```

範例(Lesley case):

```jsonl
{"run_id": "2026-05-10T17:00:00", "source": "communications/recordings/0509-research.srt", "source_type": "pasted-text", "total_findings": 10, "actions": [
  {"finding_id": 1, "finding_quote": "Schultz scale 12 items detail", "action": "create", "issue_number": 50, "issue_url": "https://github.com/.../50", "duration_ms": 1234},
  {"finding_id": 2, "finding_quote": "reputation 變 core IV", "action": "comment", "issue_number": 14, "comment_url": "...", "duration_ms": 890},
  {"finding_id": 3, "finding_quote": "刪 H4-H6 cue hypotheses", "action": "edit", "issue_number": 14, "duration_ms": 1100, "merged_from": [4]},
  {"finding_id": 4, "finding_quote": "drop cue branch", "action": "merged-into", "merged_into": 3},
  {"finding_id": 5, "action": "skip", "reason": "user-decision"},
  {"finding_id": 6, "finding_quote": "問卷 §5b Schultz 加 12 題", "action": "create", "error": "GraphQL: rate limit", "retry_hint": "rerun gh issue create with same title manually"}
], "started_at": "2026-05-10T17:00:00", "completed_at": "2026-05-10T17:03:42", "succeeded": 4, "failed": 1, "skipped": 1}
```

### Content sanitization contract (v2.67.0+, #75)

Multi-finding mode handles user-controlled content (file contents, pasted text, filenames) at the boundary between three sinks with different threat models: jsonl audit file (cat-able terminal output), GitHub issue body / comment (markdown renderer), and CLI footer composition (display strings). Each sink has different sanitization rules — the IC_R007 verbatim contract (line 1007) was authored for the audit channel and must NOT be unilaterally violated for the GitHub channel.

#### Dual-track: jsonl verbatim vs GitHub display sanitized (#75 F1)

```
                     ┌─→ jsonl `finding_quote`           = verbatim (IC_R007)
verbatim source ─────┤   (CAUTION banner above schema)
                     └─→ GitHub body `finding_quote_display` = sanitized
                         - strip C0/C1 control chars (U+0000-U+001F, U+007F-U+009F except \n\t)
                         - warn-and-strip bidi-override (U+202A-U+202E + U+2066-U+2069)
                         - normalize CRLF → LF
                         - preserve all other Unicode (CJK, emoji, etc.)
```

**Implementation contract**:

- jsonl `actions[].finding_quote` MUST contain the verbatim source content (IC_R007 line 1007 compliance);文件 schema CAUTION banner makes the untrusted-content invariant readable from the file itself.
- GitHub-bound body composition MUST use the sanitized `finding_quote_display` variant. Sanitization is local to the dispatch path (Stage 4 body composition), not retroactive on the jsonl record.
- `finding_quote_display` does not appear in the schema TypeScript above because it never persists — it's a composition-time projection of `finding_quote`.

**Why dual-track instead of unilateral sanitize**: sanitizing `finding_quote` in the audit file would silently break IC_R007. If a downstream analysis needs to recover what the source literally contained (e.g. forensic / locale investigation), the jsonl is the source of truth. Verbatim + CAUTION banner is the IC_R007-conformant contract; sanitization happens at the rendering boundary, not the storage boundary.

#### Filename / source-label sanitization (#75 F2)

`<source>` footer substitution and any prose embedding of file paths / pasted-text excerpts MUST run `sanitize_source_label()`:

```bash
sanitize_source_label() {
  local raw="$1"
  # v2.67.0+ #75 F2 — UTF-8-safe sanitization.
  #
  # CORRECTNESS: `tr -d '\200-\237'` operates at the BYTE level and would mangle
  # UTF-8 multibyte sequences (CJK / emoji / accented Latin). For example, the
  # byte 0x96 appears inside legitimate UTF-8 encodings of `文` (e4 b8 ad e6 96 87)
  # — stripping it corrupts the character. Use Python's Unicode-aware filter
  # for the C0/DEL/C1 + bidi-override strip; bash `tr` cannot do this safely.
  local stripped
  stripped=$(printf '%s' "$raw" | python3 -c '
import sys
raw = sys.stdin.read()
# Strip C0 controls (U+0000-U+001F) except newline (\n=U+000A) and tab (\t=U+0009),
# DEL (U+007F), C1 controls (U+0080-U+009F), and bidi-override / isolates
# (U+202A-U+202E + U+2066-U+2069 — Trojan-Source CVE-2021-42574 family).
out = []
for ch in raw:
    cp = ord(ch)
    if (0x00 <= cp <= 0x08) or (0x0B <= cp <= 0x0C) or (0x0E <= cp <= 0x1F):
        continue   # C0 controls except \n \t
    if cp == 0x7F:
        continue   # DEL
    if 0x80 <= cp <= 0x9F:
        continue   # C1 controls
    if (0x202A <= cp <= 0x202E) or (0x2066 <= cp <= 0x2069):
        continue   # bidi-override + directional isolates
    out.append(ch)
# Normalize CRLF / lone CR → LF
text = "".join(out).replace("\r\n", "\n").replace("\r", "\n")
sys.stdout.write(text)
' 2>/dev/null) || {
    echo "✗ ABORT: sanitize_source_label python3 step failed" >&2
    return 1
  }
  # Escape backticks (markdown code-fence escape prevention)
  stripped="${stripped//\`/\\\`}"
  # Reject `@[A-Za-z0-9-]+` tokens — defer to tagging-collaborators.md 5-step protocol
  # (rather than silently strip — silently stripping a legitimate `@scope/package.docx`
  # name corrupts the audit trail; refuse instead and force the caller to use the
  # documented mention path). Underscore intentionally included in the refuse pattern
  # — over-broad but conservative: GitHub logins don't allow `_`, so `@scope_name`
  # cannot be a real login, but the refusal prompts the caller to be explicit.
  if printf '%s' "$stripped" | grep -qE '@[A-Za-z0-9_-]+'; then
    echo "✗ ABORT: source label contains '@' mention pattern: '$stripped'" >&2
    echo "  Mentions MUST go through rules/tagging-collaborators.md 5-step protocol." >&2
    echo "  Either rename the source file to remove '@token' or pass --mention <login> explicitly." >&2
    return 1
  fi
  printf '%s' "$stripped"
}
```

**Implementation note**: bash `tr -d '\200-\237'` (LC_ALL=C or default) strips at the byte level and would corrupt UTF-8 multibyte sequences. The Python implementation operates on code points (Unicode-aware) and preserves CJK, emoji, accented Latin characters, etc. — only the targeted control characters and bidi-override code points are removed. Empirically validated: `中文` (U+4E2D U+6587) passes through unchanged; `Schultz scale\x9F12 items` has the C1 byte stripped but `Schultz scale12 items` (and any non-Latin content) preserved.

All footer composition paths (Stage 4 dispatch — `create` / `comment` / `edit`) MUST pass `<source>` through this helper before embedding in body markdown. Mention-validation cross-references the canonical [`rules/tagging-collaborators.md`](../../rules/tagging-collaborators.md) 5-step protocol — multi-finding mode does NOT bypass it.

#### jq invocation pattern mandate (#75 F8)

JSONL write and any body-composition that interpolates user content MUST use `--arg` / `--argjson` parameter binding, never string interpolation:

```bash
# REQUIRED (#75 F8 — safe parameter binding)
jq -n \
  --arg run_id "$RUN_ID" \
  --arg source "$SOURCE" \
  --argjson total "$TOTAL_FINDINGS" \
  --argjson actions "$ACTIONS_JSON" \
  '{run_id: $run_id, source: $source, total_findings: $total, actions: $actions}' \
  > "$JSONL_PATH"

# REFUSED — string interpolation (JSON injection)
# jq -n "{run_id: \"$RUN_ID\", source: \"$SOURCE\"}" > "$JSONL_PATH"
```

The spec uses `--arg` for strings (jq quotes them as JSON strings automatically) and `--argjson` for already-encoded JSON values (numbers / arrays / objects produced upstream). String interpolation into the jq filter is vulnerable to JSON injection when user-controlled values contain `"` / `\` / control characters — the bug class jq's parameter binding exists to prevent.

### Merge mechanism(二方 only)

Stage 2 picker 選 `[Merge with another finding]` 觸發 inline sub-prompt 流程:

**Partner eligibility set (v2.67.0+, #77 Gap 2 / P2.1)** — formal definition consolidating the rules previously scattered 18 lines apart in this section:

```
partner_eligible_set = {f | f.id > current_id
                          AND f.id NOT IN merged_into_set
                          AND f.id NOT IN already_routed_set}

where:
  current_id          = the finding triggering merge picker
  merged_into_set     = findings already participating as merged-into a primary (cannot be re-merged)
  already_routed_set  = findings already assigned an action in Stage 2 (not "remaining unprocessed")
```

Pickers SHALL surface candidates from this set only; refusing to include in-eligible findings prevents the three-way+ merge scenarios that MVP doesn't support.

```
Step 1 — partner picker (4-option):
  question: "Merge finding {current} with which?"
  options: [{candidate-1}] [{candidate-2}] [{candidate-3}] [Other]
  - candidates ∈ partner_eligible_set (per formal definition above)
  - Other → free-pick by finding_id (still subject to eligibility check; refused if violates set)

Step 2 — combined target picker (4-option):
  question: "Merged {current}+{partner} should go to..."
  options: [#X] [#Y] [New issue] [Skip]
  - top-3 candidates 用 combined keyword overlap recompute

Step 3 — routing intent (if picked existing #N):
  same as Stage 2d
```

**Operational semantics**:

- Partner 條目在 jsonl 寫 `action: "merged-into"` + `merged_into: <primary_id>`,**無** issue_url(不 dispatch)
- Primary 條目 dispatch 一個 combined comment / edit / new issue,body 含 partner + primary 的 quote + 各自 summary
- JSONL 雙向可追溯:`merged_from: [<partner_id>]` in primary,`merged_into: <primary_id>` in partner

**Three-way+ merge limit**:已被 merged 的 finding **不能**再被選為新 merge partner — refuse with explanation message。MVP 限二方;三方+ 列為 future enhancement。

### Mutual exclusion (vs `--bundle-mode`)

```bash
if BUNDLE_MODE_FLAG_SET AND multi_finding_triggered:
  abort with: "✗ refuse: --bundle-mode 和 multi-finding mode 互斥
    bundle 是 explicit ordered/unordered 多 issue creation;
    multi-finding 是 source-driven mixed routing(包含 amend existing)。
    請選一個。"
```

### Cross-reference 對應 atomic skills

當 user 用 `/idd-comment #14` 想批次 comment 多筆內容時,SKILL.md 引導改走本 mode:「For batch commenting from source document with multiple findings, use `idd-issue` multi-finding mode (auto-triggers when source contains ≥2 findings)」。同樣對 `idd-edit` / `idd-update`。

### Backward compatibility 保證

既有 invocation 行為**完全不變**:

| Invocation | Behavior |
|-----------|----------|
| `idd-issue "text"` | Single-issue(unchanged)|
| `idd-issue source.docx` 1 finding | Single-issue(unchanged)|
| `idd-issue source.docx` ≥2 findings | **Auto-trigger multi-finding mode** |
| `idd-issue --multi-finding "text"` | **Force multi-finding mode** |
| `idd-issue --no-multi-finding source.docx` | Force single-issue,whole source 變 1 issue body |
| `idd-issue --bundle-mode ordered "..." source.docx (multi)` | **Refuse mutual exclusive** |
| 任何既有 flag(`--target` / `--mention` / `--parent` / `--blocked-by`) | unchanged |

### Step 0 Bootstrap Stage Task List 條件 task

**僅在 multi-finding mode 觸發時** create 以下 5 個 stage tasks(同既有 bundle-mode 條件 task pattern):

```
TaskCreate(name="extract_findings", description="Stage 1: source 抽 paragraph-level findings,verbatim quote + AI summary,寫入 internal state")
TaskCreate(name="per_finding_picker", description="Stage 2: 對每個 finding 跑 4-option AskUserQuestion picker,top-3 + Other expand")
TaskCreate(name="batch_preview", description="Stage 3: print full dispatch table,AskUserQuestion [Execute all][Edit row N][Cancel]")
TaskCreate(name="dispatch_with_warn_continue", description="Stage 4: sequential gh actions,失敗 log to jsonl 不 abort,寫 footer")
TaskCreate(name="merge_handler", description="Stage 2 inline sub-flow handler:partner picker → combined target picker → intent disambiguation,JSONL merged_from/merged_into")
```

不 trigger 時(single-issue mode)不 create 這些 task。

### Examples

#### Example 1: Lesley 0509 transcript

```bash
$ idd-issue communications/recordings/0509-research.srt --target kiki830621/teaching_lesley
→ Auto-trigger multi-finding mode (10 findings extracted)

Stage 2: per-finding picker × 10
  Finding 1 of 10: "Schultz scale 12 items detail..."
    [#15 (0.42)] [#14 (0.31)] [#17 (0.28)] [Other]
    user picks → [Other] → [New issue] → routed: NEW
  Finding 2 of 10: "reputation 變 core IV..."
    [#23 (0.78)] [#14 (0.62)] [#17 (0.41)] [Other]
    user picks → #23 → intent [comment] → routed: COMMENT to #23
  ... (8 more)

Stage 3: batch preview
  === Plan (10 findings → 8 actions, 2 skipped) ===
   1. [NEW]      ...                                  → /idd-issue
   2. [COMMENT]  "reputation 變 core IV"              → #23
   3+4. [EDIT-MERGED] "drop H4-H6 + reframe"          → #14
   ...
  [Execute all]

Stage 4: Dispatch
  ✓ Created issue #50 (1234ms)
  ✓ Posted comment to #23 (890ms)
  ✓ Edited #14 body (1100ms, merged_from: [4])
  ⚠ Failed to create issue from finding 6: rate limit (retry_hint logged)
  ...
Stage 4.5: jsonl gitignore pre-flight
  ✓ Run log path NOT gitignored — committing as-is (D2 contract preserved)
  Summary: 7 succeeded, 1 failed, 2 skipped
  Run log: .claude/.idd/issue-runs/2026-05-10T17:00:00.jsonl
    Status: committed
```

When `.gitignore` shadows `.claude/`, Stage 4.5 surfaces the ignore source + user choice in the same summary block. The carve-out always emits the same universal 5-line block (per round-5 fix), so the summary line doesn't vary by source:

```
Stage 4.5: jsonl gitignore pre-flight
  ⚠ Detected: .gitignore:1:.claude/  shadows run log path
  ✓ User chose: Add carve-out chain to .gitignore
  Summary: 7 succeeded, 1 failed, 2 skipped
  Run log: .claude/.idd/issue-runs/2026-05-10T17:00:00.jsonl
    Status: committed (added universal 5-line carve-out chain to .gitignore — `!.claude` parent re-include neutralizes outer source)
```

Global `core.excludesfile` and `.git/info/exclude` sources produce the same outcome (same 5-line block written to root `.gitignore`). Only the `Detected:` line differs:

```
Stage 4.5: jsonl gitignore pre-flight
  ⚠ Detected: ~/.config/git/ignore:3:.claude/  (global core.excludesfile)
  ✓ User chose: Add carve-out chain to .gitignore
  Summary: 7 succeeded, 1 failed, 2 skipped
  Run log: .claude/.idd/issue-runs/2026-05-10T17:00:00.jsonl
    Status: committed (added universal 5-line carve-out chain to .gitignore — `!.claude` parent re-include neutralizes global ignore)
```

Nested `.gitignore` (e.g. `.claude/.gitignore`) cannot be fixed from root — Add-carve-out option is not offered. Summary shows the nested source + a complete carve-out hint (single-line exception does NOT work per git docs — the parent directory of the run log path is still excluded, so any single-line `!.idd/issue-runs/<file>` rule has no effect). The manual fix mirrors the same chain-style pattern we use in root `.gitignore`, but with paths relative to the nested file's directory:

```
Stage 4.5: jsonl gitignore pre-flight
  ⚠ Detected: .claude/.gitignore:1:*  (nested .gitignore — root carve-out cannot override)
  ⚠ User chose: Skip commit (local-only)
  Summary: 7 succeeded, 1 failed, 2 skipped
  Run log: .claude/.idd/issue-runs/2026-05-10T17:00:00.jsonl
    Status: ⚠ local-only (nested .gitignore shadows path; cross-machine continuity disabled)
    Manual fix: edit .claude/.gitignore — single-line `!...` exceptions DO NOT WORK here
      (parent .idd is still excluded by `*` per git's "parent dir excluded" rule).
      Append the chain instead (paths relative to .claude/ since that's where the
      nested .gitignore lives, and note the trailing slashes on directory patterns
      + the explicit glob on issue-runs/* — empirically validated 2026-05-11):

        !.idd/
        .idd/*
        !.idd/issue-runs/
        !.idd/issue-runs/*

      Then commit both `.claude/.gitignore` and the jsonl file.
```

```
Stage 4.5: jsonl gitignore pre-flight
  ⚠ Detected: .gitignore:1:.claude/  shadows run log path
  ⚠ User chose: Skip commit (local-only)
  Summary: 7 succeeded, 1 failed, 2 skipped
  Run log: .claude/.idd/issue-runs/2026-05-10T17:00:00.jsonl
    Status: ⚠ local-only (gitignored by .claude/ pattern, cross-machine continuity disabled)
    Manual export: cp .claude/.idd/issue-runs/2026-05-10T17:00:00.jsonl <path-outside-.gitignore>
```

```
Stage 4.5: jsonl gitignore pre-flight
  ⚠ Detected: .gitignore:1:.claude/  shadows run log path
  ✗ User chose: Abort
  Summary: dispatch aborted — 3 issues dispatched before gate (NOT rolled back), run log discarded
  Run log: (not written — Abort discards in-memory accumulator)
```

```
Stage 4.5: jsonl gitignore pre-flight
  → Bypassed: IDD_JSONL_GITIGNORE_GATE=false (CI/unattended mode)
  Summary: 7 succeeded, 1 failed, 2 skipped
  Run log: .claude/.idd/issue-runs/2026-05-10T17:00:00.jsonl
    Status: gate bypassed via env var — jsonl written per existing logic (may be silently gitignored)
```

```
Stage 4.5: jsonl gitignore pre-flight
  → Not applicable: outside git work tree
  Summary: 7 succeeded, 1 failed, 2 skipped
  Run log: .claude/.idd/issue-runs/2026-05-10T17:00:00.jsonl (local file, no commit attempted)
    Status: not applicable
```

#### Example 2: Single finding source — fall through

```bash
$ idd-issue short-note.docx
→ Stage 1: 1 finding extracted
→ Multi-finding mode NOT triggered
→ Fall through to existing single-issue creation flow
✓ Created issue #51
```

#### Example 3: Bundle mode + multi-finding source — refuse

```bash
$ idd-issue --bundle-mode ordered transcript.srt
→ Stage 1: 8 findings extracted
✗ refuse: --bundle-mode 和 multi-finding mode 互斥
  bundle 是 explicit ordered/unordered 多 issue creation;
  multi-finding 是 source-driven mixed routing(包含 amend existing)。
  請選一個。
```

### 設計理由 — 為什麼不另起 sibling skill?

考慮過開新 `/idd-fanout` 或 `/idd-triage` skill 但選 mode 擴展 `idd-issue`:

1. **70% 重疊既有 idd-issue logic**:source adapter / target resolution / mention validation / attachment upload / sister sweep / milestone assignment 都要 reuse,複製一份成本高
2. **Bundle mode 已是同類 prior art**:v2.52.0 把 bundle 做成 idd-issue 內部 mode(`--bundle-mode` flag),user 心智模型已建立「idd-issue 是 filing entry point,有多種 mode」
3. **避免 skill 數量爆炸**:IDD 已 14+ skills,新增 cognitive cost 不值得 ~30% 獨特功能
4. **Naming controversy 自然消解**:不需起 new noun(fanout/dispatch/triage),descriptive 命名「multi-finding source mode」即可

設計 trade-off 完整紀錄見 `openspec/changes/add-multi-finding-source-mode-to-idd-issue/design.md` D1-D7。

## 來源文件規則

### One Point = One Issue

- **每個要點**獨立建一個 issue
- **不合併** — 類似主題也分開
- **不跳過** — 重複可以之後關，遺漏 = 遺忘
- 處理完畢後驗證：`文件要點數 == 建立的 issue 數`

## Next Step

建立 issue 後，進入 `diagnose`：

```
/issue-driven-dev:idd-diagnose #NNN
```
