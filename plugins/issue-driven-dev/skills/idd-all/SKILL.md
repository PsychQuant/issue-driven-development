---
name: idd-all
description: |
  自動串連 IDD 完整 workflow（issue → diagnose → implement → verify），按 pr_policy 解析 path 與 interaction 兩軸：PR + unattended（自動化、/loop friendly）或 direct-commit + attended（HITL、user 在 keyboard，sub-skill AskUserQuestion 自然 fire）。verify 乾淨通過、意圖確認過、而且沒有別人插手時就 merge（PR mode）或 push（direct-commit mode，限預設 branch）並跑 /idd-close，最後回報做了什麼與怎麼復原；guardrail 沒過、有還沒回答的釐清問題或未回應的略過紀錄、帶 --review 或 --in-chain 時停在 verified（tier 是哪一個不影響）；type=meeting 停在 diagnosed 或 planning，不 verify、不開 PR。
  Use when: 想一次跑完整條 IDD pipeline、信任 6-AI verify 會抓錯、希望交出去就不用管（verify 乾淨就跑到 closed，沒過就停在 verified 回報原因）；HITL 模式則用於 solo repo 想被 sub-skill 諮詢的情境。
  防止的失敗：手動跑 5 個 idd-* skill 太繁瑣、忘記中間某一步、orchestration 一致性。
argument-hint: "[#NNN | 'issue description'] [--pr | --no-pr] [--review] [--cwd /path/to/clone] (empty = interactive; --no-pr 觸發 HITL direct-commit + attended; --review 停在 verified、不 merge 也不 close)"
allowed-tools:
  - Bash(gh:*)
  - Bash(git:*)
  - Bash(grep:*)
  - Bash(jq:*)
  - Bash(python3:*)
  - Bash(find:*)
  - Read
  - Glob
  - Grep
  - AskUserQuestion
  - Skill
---

# /idd-all — 自動 IDD Pipeline

把 idd-issue → idd-diagnose → idd-implement → idd-verify 串成一條自動跑的鏈。**Mode 由 `pr_policy` config 與 `--pr/--no-pr` flag 共同推導**：PR mode 在 feature branch + 開 PR + sub-skill unattended；direct-commit mode 留在當前 branch + 不開 PR + sub-skill attended。verify 乾淨通過就自己 merge（或 push）並跑 `/idd-close`，最後回報做了什麼、怎麼復原（#392）。

## 核心原則

> Orchestrator skill 的 contract:**便利不能犧牲安全,attended 與否是模式而非預設**。
>
> - **Two-axis mode resolution**: idd-all 在 Phase 0.5 從 `pr_policy` config + `--pr/--no-pr` flag 解析 `(path, interaction)` tuple — 兩軸從同一 source 推導,避免 duplicate config surface。完整 algorithm 見 [pr-flow.md](../../references/pr-flow.md)。
>   - `(PR, unattended)`: 強制 feature branch、push、開 PR;sub-skill 收到 `UNATTENDED MODE` directive 抑制 `AskUserQuestion`。**v2.40.0 既有 caller(如 `/loop`)的 default 行為**。
>   - `(direct-commit, attended)`: 留在當前 branch、不開 PR(verify 乾淨且在預設 branch 上時,Phase 5c push 並 close,#392);sub-skill 不收 unattended hint,native attended 行為(`AskUserQuestion`、`EnterPlanMode`、`Park/Apply` prompt)自然 fire。HITL 場景。
> - **Attended assumes user in session**: attended interaction 模式下,idd-all **不**對 sub-skill `AskUserQuestion` / `EnterPlanMode` prompt 設任何 silent timeout。user 沒回應就一直等。Attended mode = user 在 keyboard 是契約前提;若 user 預期不在,該選 unattended。
> - **Branch behavior follows path**: PR mode 從 default branch 開 `idd/<N>-<slug>` feature branch;direct-commit mode 留在 user 當前 checkout 的 branch(可能是 main、可能是 feature branch、可能是 wip/foo)。
> - **Clean verify ends in merge and close**（#392）: verify gate（`scripts/verify-gate.py`，報告須寫出它審查的 commit）判定乾淨、而且 merge guardrail 全過時（全部在 `scripts/close-stage.py` 的同一個 process 裡檢查），PR mode squash-merge PR、direct-commit mode 在預設 branch 上 push，接著以 `ORCHESTRATED BY /idd-all` 指示呼叫 `/idd-close`，不先問人。merge 可 revert、close 可 reopen，依 Foresay 屬於 traceable：做完必須回報（`Done:`／`Undo:`）。gate 判定不乾淨或讀不出來、任一 guardrail 不過、意圖沒有確認過、run 開始後有別人插手、帶 `--review`、或在 `--in-chain` 裡時，停在 verified 並回報 `Stopped:`（Phase 5c 的兩張表）。meeting issue 不跑 verify，停在 planning 或 diagnosed（見 Phase 6 meeting report）。
> - **Fail-safe escalation**: 遇到 ambiguity 寧可 abort,絕不亂猜 — 但 SDD path 預設是「文件化 assumption 後繼續」(見 Phase 3b),不是 abort。Abort 是最後手段。

## 權限：這個 skill 自己做的事，與先問人的事（#392）

依據是 Foresay 的 `reversible`：狀態復原得了、沒有收不回的成本、沒有別人已經看到而收不回的東西。三個都成立的動作，這個 skill 做完就回報並附 `Undo:`，不先問；不成立的先問。下面兩張表是封閉列舉，範圍是這個 skill 自己發起的對外動作（sub-skill 發起的照各自的 skill）。**不在表上的對外動作一律先問，不得因為性質相似就當成第一張表的動作。** 執行者自己的規則比這一節嚴格時，以他的規則為準。

**做完回報**

| 動作 | 條件 | Undo |
|---|---|---|
| 建 issue、留言、改自己的 issue 正文、設 label、baseline tag | 內文過隱私自審；留言與正文經 `gh-egress.sh` 送出（follow-up issue 的建立程序還沒有走它，#483） | 編輯或刪除那一筆 |
| 推這次 run 的 branch（Phase 5） | 不是預設 branch、不帶 `--force` | 刪掉遠端 branch |
| 開這次 run 的 PR，或續跑時更新它的正文（Phase 5） | `close-stage.py pr-check` 回 `open`，標題與內文過隱私自審 | `gh pr close <N>`；正文的舊版在 GitHub 的編輯紀錄裡 |
| squash-merge、在預設 branch 推送、`/idd-close`（Phase 5c） | `close-stage.py run` 的閘門全過 | `git revert`、`gh issue reopen` |

**先問人**

| 動作 | 為什麼收不回 |
|---|---|
| `pr-check` 回 `ask` 的 PR（開新的或改正文都算）：標題是空的、標題或內文 `@` 到帳號、預設 branch 有 `CODEOWNERS`（開 PR 會自動請人 review）、close 關鍵字緊鄰 issue 號、預設 branch 抓不到 | 通知送出去就收不回；合併時會繞過 `/idd-close` 關掉 issue |
| 開到別人的 repo 的 PR | 對方已經看到。這個 skill 不會做這件事：PR 一律開在 `origin` 指向的 repo，推不上去就不會有 PR |
| 內文沒過隱私自審的任何對外動作 | 公開出去的內容收不回 |
| 刪除 branch、`--force` | 被覆蓋或刪掉的 commit 找不回來 |
| 發布：`gh release`、marketplace 同步、baseline 以外的 tag | 已經到使用者手上 |
| 帶 `--review` 的 run 的合併與結案 | 由人做：這個旗標的意思就是人要先看 |

還沒回答的釐清問題不是操作，是意圖確認：由人回答，run 停在那裡（Phase 5c 的意圖那一列）。

要先問的動作，attended 用 `AskUserQuestion` 問；unattended 不做，把原因寫進 Phase 6 報告的 `Stopped:`。PR path 目前一律是 unattended，所以 `pr-check` 回 `ask` 時就是不開、不改，並回報。

已知限制：repo 的 watcher 會收到「有新 PR」的一般通知，`pull_request` 觸發的 workflow 也可能自己指派或提到人，這兩種 `pr-check` 看不到。

## 與其他 idd-* skills 的關係

| Skill | 模式 | 用途 |
|-------|------|------|
| `idd-issue/diagnose/implement/verify/close` | Atomic — 手動逐步 | 細緻控制、需要中途插手 |
| **`idd-all`** | **Orchestrator — 一鍵跑完** | 信任 pipeline、交出去就不用管（不能自動收尾時停在 verified 並說明原因） |

idd-all 不取代 atomic skills,而是包它們。每個 phase 仍透過 `Skill(skill=...)` 呼叫對應的 atomic skill,所有 sub-skill 的 stage TaskList、auto-update、IDD 紀律都繼承下來。

## Multi-issue batch mode（conflict-class-ordered，v2.83.0+，#182）

`/idd-all #a #b #c`（≥2 個 distinct `#N`）= 對一個 backlog 做 **conflict-class-ordered sequential** drain。每個 issue 仍走完整 idd-all pipeline（Phase 1–6），只是**多了一個按 conflict class 排序的外圈**。

> **誠實邊界（CRITICAL）**：這個 mode 是 **sequential**，不是 concurrent。「在單一 session 內並發跑 N 個 stateful lane」目前**沒有真 primitive** —— within-window agent teams 在 [`references/worktree-isolation.md`](../../references/worktree-isolation.md) 是 **Deferred: Case A**，`TeamCreate` 已在 idd-verify 因 #47/#52 incident 廢棄。所以 batch mode **不宣稱並發執行**；conflict-class taxonomy 是「**當你（手動跨 session / worktree）並行、或未來有真 primitive 時**，什麼能安全並行」的前瞻性安全契約。詳見 [`references/parallel-orchestration.md`](../../references/parallel-orchestration.md)。

行為：

1. 對每個 `#N` 讀最新 Diagnosis 的 `### Conflict Class`（emit 契約見 `idd-diagnose`）。缺 / 無法 parse → 預設 `D_diagnose_first` 並 **surface**（印出來），不靜默、不預設成 parallel class。
2. 按 conflict-class discipline 排序處理順序：`E_verified_close`（cheap verify+close）與 `D_diagnose_first`（先 read-only diagnose、再 re-bucket）優先；`B_resource_serialize` / `C_shared_module_coord` 觸碰**同一具名資源**者相鄰序列化、不交錯；`A_parallel_safe` 之間順序不拘。同檔的 issue 視為一組（不拆開）。
3. 逐一（sequential）跑 `/idd-all #N`。`A_parallel_safe` issue **可選**用 `scripts/idd-worktree.sh create <N>` 隔離工作樹，讓你**事後**能把這些 branch 手動並行推進；serialize-class 不隔離也安全（反正 sequential）。
4. 每張的終點與單張相同（#392）：verify 乾淨就 merge 並 close；停在 guardrail 的留在 verified；meeting 停在 diagnosed 或 planning。**PR mode** 的每一張結束後（不論有沒有 merge），先 `git -C "$CWD" checkout -q <default> && git -C "$CWD" pull --ff-only -q` 回到並更新預設 branch，再開始下一張，任一步失敗就停止整批並回報是哪一張、哪一步。**direct-commit** 的 batch 不切換 branch：每一張都留在使用者開始時的 branch（Phase 0.5 的契約）。

> **為什麼仍值得排序（即使 sequential）**：sequential 本身永遠安全，所以排序不是為了正確性，而是為了 (a) 把 cheap/E 與 read-first/D 先清掉、(b) 把同資源的 B/C 相鄰處理便於 review、(c) 替「日後手動並行」預先把 class-A 隔離好。真正的價值在 taxonomy 作為**並行安全契約**，而非這個 sequential 外圈本身。

## Configuration

從 `.claude/issue-driven-dev.local.md` frontmatter 讀 `github_repo`。如不存在,呼叫 `idd-issue` 流程會自動處理。

## Execution

### Step 0: Bootstrap Stage Task List(強制)

**動任何事之前**先用 `TaskCreate` 建 stage-level todo list:

```
TaskCreate(name="preflight", description="Phase 0: 解析 args(含 --pr/--no-pr/--review/--cwd)、gh auth、resolve target repo")
TaskCreate(name="parse_review_flag", description="Phase 0: 解析 --review flag → $REVIEW_FLAG (Phase 6 terminal report 切換 verify-gated default vs awaiting human acceptance; per #102 Foresay doctrine)")
TaskCreate(name="resolve_mode", description="Phase 0.5: 從 pr_policy + flag + fork detection 解析 (path, interaction) tuple,印 notice line。PR mode 才檢查 git clean + on-default-branch + 建 feature branch;direct-commit mode 留在當前 branch。")
TaskCreate(name="existing_work_check", description="Phase 0.5.1 (#366): 在建任何 branch 之前呼叫 scripts/check-existing-work.sh;blocked → attended 問三選項、unattended 停該張並記入 Phase 6 Action items;resume → 在該 PR/branch 上繼續;unknown → 印出並繼續")
TaskCreate(name="record_run", description="Step 0.7 (#392): close-stage.py init 把 path/interaction/branch/default/--review/--in-chain 寫進 run-state（from-scratch 在 Phase 1 之後）")
TaskCreate(name="ensure_issue", description="Phase 1: 若 from-scratch 則跑 idd-issue; from-issue 則 verify issue 存在")
TaskCreate(name="diagnose", description="Phase 2: 跑 idd-diagnose,讀回 complexity 判定")
TaskCreate(name="implement_or_sdd", description="Phase 3: type=meeting → attended 走 meeting 版 /idd-plan、unattended 跳過(#383,先跑 meeting unwind); Simple/Plan → idd-implement; Spectra → spectra-discuss → spectra-propose → spectra-apply。Args 含 UNATTENDED MODE 與否依 Phase 0.5 解析的 interaction 軸決定。")
TaskCreate(name="verify_loop", description="Phase 4: type=meeting → 跳過(#383); 每輪 idd-verify 後跑 scripts/verify-gate.py 讀這一輪新貼出的報告(#392); clean → 往下(low_in_scope 大於 0 時把那些列合成一張 follow-up issue,不為它們改 branch); unparseable → STOP_REASON; not_clean: unattended 修 Blocking 與 In-scope fix 後重跑(最多 2 輪 verify), attended 交回 user; follow-ups → 開新 issue")
TaskCreate(name="ci_gate", description="Phase 4.5 (#465): type=meeting → 跳過; 對 HEAD 跑 scripts/idd-ci-gate.sh，紀錄貼到 issue；只有 exit 0 繼續、exit 10 改看遠端 CI；exit 3 attended 問指令、unattended 停下回報；exit 1/2/4 停下回報")
TaskCreate(name="open_pr", description="Phase 5: type=meeting → 跳過、不 push(#383); PR mode → git push + 已有自家 open PR 就沿用並更新 body,否則 gh pr create(body 照 verify gate 結果寫,含 Refs #N, 不含 Closes); direct-commit mode → 不開 PR,進 Phase 5c")
TaskCreate(name="close_stage", description="Phase 5c (#392): scripts/close-stage.py run（同一個 process，run_in_background）：讀 Step 0.7 的 run-state，擋 --review/--in-chain/meeting/無寫入權限/run 開始後別人插手/意圖沒確認(tier 與沒人處理的 Proposed Corrections 不擋)；gate 綁 HEAD SHA、只認本帳號的報告、讀 GitHub 渲染後的 HTML，有 Rejected finding 就停；CI 等完再重查預設 branch 與 PR 上的人；PR → 本機 CI 閘門 idd-ci-gate.sh(0 過、10 才等遠端 check:pending 最多 15 分鐘、有 pull_request workflow 就等 check 出現;其他結束碼停)、auto-close trap、squash message，全過才 gh pr merge --squash --match-head-commit 並確認 MERGED；direct-commit → 在預設 branch、每個要推的 commit 都引用 #N 才 push。merged/pushed 才以 ORCHESTRATED BY /idd-all 呼叫 /idd-close --repo，最後確認 CLOSED 且有 closing summary")
TaskCreate(name="report_and_stop", description="Phase 6: Done:/Undo: 回報(merge 或 push 的 commit、closed issue 與 closing summary、改動規模、follow-up、residue、distribution sync、verify reviewers); 停下時只列做到的步驟加 Stopped:; --review → awaiting human acceptance 措辭; type=meeting → meeting report(#383)")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。

`idd-all` 內部呼叫的 atomic skill 會各自建自己的 stage TaskList(那是它們的責任),idd-all 的 task list 只追 phase-level 進度。

---

### Phase 0: Pre-flight Checks

#### Step 0.1: Argument Parsing

| 輸入 | Mode | 行為 |
|------|------|------|
| `/idd-all` | interactive | AskUserQuestion: 建新 issue 還是用既有 issue? |
| `/idd-all #19` | from-issue | 直接從 #19 進 diagnose,mode 由 Phase 0.5 解析 |
| `/idd-all #19 --pr` | from-issue, force PR | 強制 (PR, unattended) — v2.40.0 既有行為,/loop friendly |
| `/idd-all #19 --no-pr` | from-issue, force HITL | 強制 (direct-commit, attended) — user 在 keyboard,sub-skill 自然問問題 |
| `/idd-all #19 --cwd /path/to/clone` | from-issue cross-repo | 在指定 local clone 跑(不依賴 session cwd);可與 `--pr/--no-pr` 並用 |
| `/idd-all #a #b #c` (≥2 issues) | **multi-issue batch** | conflict-class-**ordered sequential** backlog drain(見下方 `## Multi-issue batch mode`,v2.83.0+)|
| `/idd-all "bug: foo doesn't work"` | from-scratch | 用該字串當 issue title 進 idd-issue |
| `/idd-all path/to/spec.md` | from-scratch | 把檔案當 issue 描述進 idd-issue |

#### Step 0.2: Resolve Working Tree + Flags + Config(v2.46.0+ 擴充)

idd-all 的所有 git/gh 操作都針對單一 target repo,且 Phase 0.5 mode resolution 需要 `PR_FLAG` 與 `CONFIG_PATH` 變數。Step 0.2 一次解析三項。

```bash
# 1. 解析 flags(per-invocation override) — 順序逐一掃描 argv
CWD_FLAG=""
PR_FLAG=""        # "" | "--pr" | "--no-pr"
IN_CHAIN=""       # "" | "1" — set by --in-chain flag (v2.55+ #44)
REVIEW_FLAG=""    # "" | "--review" — set by --review flag (v2.65+ #102)
# #392: the same two opt-outs as explicit yes/no for Step 0.7. A lost variable must be an
# error there, never a silent "no" that lets the close stage merge (#392 verify r2 #3).
REVIEW_YN="no"; IN_CHAIN_YN="no"
ARGS=("$@")
for ((i=0; i<${#ARGS[@]}; i++)); do
  arg="${ARGS[i]}"
  case "$arg" in
    --cwd=*)    CWD_FLAG="${arg#--cwd=}" ;;
    --cwd)      i=$((i+1)); CWD_FLAG="${ARGS[i]}" ;;
    --pr)
      [ -n "$PR_FLAG" ] && abort "Conflicting flags: '$PR_FLAG' and '--pr' both passed. Pick one."
      [ -n "$IN_CHAIN" ] && abort "Conflicting flags: '--in-chain' and '--pr' cannot be combined. --in-chain implies (direct-commit, unattended); pick one."
      PR_FLAG="--pr" ;;
    --no-pr)
      [ -n "$PR_FLAG" ] && abort "Conflicting flags: '$PR_FLAG' and '--no-pr' both passed. Pick one."
      [ -n "$IN_CHAIN" ] && abort "Conflicting flags: '--in-chain' and '--no-pr' cannot be combined. --in-chain implies (direct-commit, unattended); pick one."
      PR_FLAG="--no-pr" ;;
    --in-chain)
      # v2.55+ #44 — chain context tuple (direct-commit, unattended)
      [ -n "$PR_FLAG" ] && abort "Conflicting flags: '--in-chain' and '$PR_FLAG' cannot be combined. Pick one."
      IN_CHAIN="1"; IN_CHAIN_YN="yes" ;;
    --review)
      # v2.65+ #102 — opt-in re-open Foresay confirmation loop at terminal report.
      # Orthogonal to --pr/--no-pr/--in-chain (no mutex). Orchestrator-scope messaging-only effect (per #108 DA3 — humans/CI downstream may react to the changed text, so the flag is messaging-only at orchestrator scope, not necessarily end-to-end):
      # Phase 6 report swaps to "awaiting human acceptance" wording. Does NOT
      # change idd-all behavior, does NOT make idd-all wait. Per MANIFESTO
      # "Human-in-the-loop: IDD 即 Foresay Confirmation Protocol" doctrine.
      REVIEW_FLAG="--review"; REVIEW_YN="yes" ;;
  esac
done

# 2. 確定 working tree 路徑
if [ -n "$CWD_FLAG" ]; then
    [ -d "$CWD_FLAG" ] || abort "--cwd path '$CWD_FLAG' does not exist."
    CWD="$CWD_FLAG"
else
    CWD="$(pwd)"
fi

# 3. 從 working tree 推導 GITHUB_REPO + post-derive shape assertion (#8)
GITHUB_REPO=$(git -C "$CWD" remote get-url origin 2>/dev/null \
    | sed -E 's#(\.git)?$##; s#.*[:/]([^/]+/[^/]+)$#\1#') \
    || abort "Could not determine github_repo from $CWD/.git/config (no 'origin' remote?)"

# Origin URL might be local path / non-typical format; sed could output garbage.
# Assert owner/repo shape before any gh -R "$GITHUB_REPO" call.
if [[ ! "$GITHUB_REPO" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]]; then
  abort "Could not derive owner/repo shape from origin URL of $CWD.
   Got: '$GITHUB_REPO'
   Pass --target owner/repo or check 'git -C $CWD remote get-url origin'."
fi

# 4. Walked-up CONFIG_PATH discovery(從 $CWD 往上找 IDD config;新路徑優先,#195)
find_idd_config() {
  local dir="$1"
  while [ "$dir" != "/" ]; do
    # New path wins at the same level (config-protocol mechanism 4, #195)
    if [ -f "$dir/.claude/.idd/local.json" ]; then
      echo "$dir/.claude/.idd/local.json"
      return 0
    fi
    if [ -f "$dir/.claude/issue-driven-dev.local.json" ]; then
      echo "$dir/.claude/issue-driven-dev.local.json"
      return 0
    fi
    [ "$dir" = "$HOME" ] && break
    dir=$(dirname "$dir")
  done
  return 1
}
CONFIG_PATH=$(find_idd_config "$CWD")  # may be empty if no config found
```

> **Why parse `--pr/--no-pr` here, not in Phase 0.5**: Phase 0.5 references `$PR_FLAG` and `$CONFIG_PATH` in its precedence chain. Both variables must be initialized before that chain runs. Conflict detection between `--pr` and `--no-pr` (Task: P1 finding 4) lands here at parse time so we abort early with a clear message.

**為什麼需要 explicit `--cwd`**:Skill tool 呼叫繼承 Claude Code session-level cwd,不會跟著 mid-session `cd` 移動。跨 repo 工作(例如 thesis 在 repo A、要對 repo B 跑 idd-all)時,沒有 `--cwd` 就只能重啟 Claude Code session — 違反 unattended pipeline contract。

#### Step 0.3: Universal pre-flight gates

不論 mode,以下兩個 gate 都必須過。所有 git 操作用 `git -C "$CWD"`,所有 gh 操作用 `gh -R "$GITHUB_REPO"`。

```bash
# 1. 必須在 git repo
git -C "$CWD" rev-parse --git-dir > /dev/null 2>&1 \
    || abort "'$CWD' is not a git repository.
   Either:
     - cd to the target repo first, then re-run /idd-all
     - OR pass --cwd /path/to/local/clone"

# 2. 必須 gh auth
gh auth status > /dev/null 2>&1 || abort "gh CLI not authenticated. Run: gh auth login"
```

> **Mode-specific gates(working tree clean、on default branch)移到 Phase 0.5**:那些 gate 只在 PR mode 必須,direct-commit mode 預設留在 user 當前 branch + 容許未 commit 變更(由 user 自負其責)。

#### Step 0.35: Dependency early gates（v2.92+ #211；scope 含 spectra per #210 audit）

Phase 1 之前先驗 delegation 依賴，避免 unattended chain 中途 abort 留孤兒 issue/branch：

```bash
# superpowers — 無條件 hard gate（diagnose/implement 的 delegation 必經）
"${CLAUDE_PLUGIN_ROOT}/scripts/check-plugin-presence.sh" \
  claude-plugins-official superpowers || abort "superpowers missing — install first (see hint above), then re-run /idd-all"

# spectra — Phase 0 只 warn（complexity 尚未判定，SDD path 不一定觸發）；
# Phase 3b 入口另有 hard gate（見該段）— fail 發生在任何 spectra artifact 產生之前
if ! command -v spectra >/dev/null 2>&1; then
  echo "⚠ spectra CLI not on PATH — if diagnosis routes to Spectra tier, Phase 3b will abort."
  echo "  Pre-empt: install the Spectra plugin/CLI before long unattended runs."
fi
```

#### Step 0.4: Resolve Issue Number

- **from-issue mode**(`/idd-all #19`): 確認 issue #19 存在且 OPEN(`gh issue view 19 -R "$GITHUB_REPO" --json state -q .state`); 若 state=CLOSED → abort
- **from-scratch mode**: skip 到 Phase 1 跑 idd-issue
- **interactive mode**: AskUserQuestion 兩選一
- **開工前檢查（已有 PR／branch 在處理這張 issue？）**: 見 Step 0.5.1。它需要先知道 interaction 軸，所以排在 mode 解析之後、建 branch 之前

#### Step 0.5: Resolve Mode + Conditional Branch Setup

**先解析 `(path, interaction)` tuple,再依 path 決定 branch 行為。** 完整 algorithm 見 [pr-flow.md](../../references/pr-flow.md)「`idd-all` path resolution」段。

**Resolution precedence(first match wins)**:

```
1. --in-chain flag                                → (direct-commit, unattended)  [v2.55+ #44 chain context tuple]
2. --pr flag                                      → (PR, unattended)
3. --no-pr flag                                   → (direct-commit, attended)
4. Fork detected (gh repo view --json isFork)     → (PR, unattended)  [override config]
5. pr_policy: always                              → (PR, unattended)
6. pr_policy: never                               → (direct-commit, attended)
7. pr_policy: ask (explicitly set)                → AskUserQuestion (Claude tool)
7.5 third-party clone + pr_policy absent (#192)   → (direct-commit, attended)  [no push access → local; overrides only the absent default]
8. pr_policy absent (config 缺 / 整個 config 不存在) → (PR, unattended)  [v2.40.0 backward-compat default]
```

> **Step 1 (v2.55+ #44, `--in-chain` chain context)**: `/idd-all-chain` 在 Phase 0 已建好 cluster branch 並透過 `--in-chain` 呼叫 sub `/idd-all`。第 4 種 mode tuple `(direct-commit, unattended)` 確保 sub-skill 不再建自己的 feature branch (Phase 0.5 PR mode skip)、不開自己的 PR (Phase 5.5 skip)、不 fire AskUserQuestion (UNATTENDED MODE directive)。**`--in-chain` 與 `--pr` / `--no-pr` 互斥**(在 Step 0.2 parse-time abort)。
>
> **Step 7 vs Step 8 distinction (Task: P1 finding 3, proposal "no backward incompat")**: 顯式 `"pr_policy": "ask"` = user 明確要被問 → 用 AskUserQuestion Claude tool。Config 完全沒寫(field 缺或 file 不存在)= /loop 等舊 caller 場景 → 默認 PR mode 維持 v2.40.0 行為,不卡住自動化。

```bash
# 讀 pr_policy from cascading config
# Distinguish "absent" (no config / no field) from explicit "ask"
if [ -z "$CONFIG_PATH" ] || [ ! -f "$CONFIG_PATH" ]; then
  PR_POLICY="absent"
else
  PR_POLICY=$(jq -r '.pr_policy // "absent"' "$CONFIG_PATH" 2>/dev/null || echo "absent")
fi

# 1. --in-chain flag (v2.55+ #44 chain context tuple) — highest precedence
if   [ -n "$IN_CHAIN" ];          then PATH_AXIS="direct-commit"; INTERACTION="unattended"; REASON="flag=--in-chain"
# 2-3. Explicit flags
elif [ "$PR_FLAG" = "--pr" ];     then PATH_AXIS="PR";            INTERACTION="unattended"; REASON="flag=--pr"
elif [ "$PR_FLAG" = "--no-pr" ];  then PATH_AXIS="direct-commit"; INTERACTION="attended";   REASON="flag=--no-pr"
else
  # 3. Fork detection — fail-closed (#5 fix). gh failure defaults IS_FORK="true"
  # so we resolve to PR mode for safety. Direct-commit fall-through on a real
  # fork would silently drop user's work (no push permission to upstream).
  # The user gets a visible warning and can override with --pr / --no-pr.
  IS_FORK_RAW=$(gh repo view "$GITHUB_REPO" --json isFork -q .isFork 2>&1)
  IS_FORK_EXIT=$?
  if [ $IS_FORK_EXIT -ne 0 ]; then
    echo "⚠ Could not query fork status (gh exit $IS_FORK_EXIT): $IS_FORK_RAW"
    echo "  Defaulting to PR mode for safety. Pass --no-pr to override."
    IS_FORK="true"
  else
    IS_FORK="$IS_FORK_RAW"
  fi

  if [ "$IS_FORK" = "true" ]; then
    PATH_AXIS="PR"; INTERACTION="unattended"; REASON="fork detected (override pr_policy=$PR_POLICY)"
  else
    # 4-5-7. Config-driven non-ask paths
    case "$PR_POLICY" in
      always) PATH_AXIS="PR";            INTERACTION="unattended"; REASON="pr_policy=always" ;;
      never)  PATH_AXIS="direct-commit"; INTERACTION="attended";   REASON="pr_policy=never" ;;
      absent)
        # third-party clone detection (#192) — computed LAZILY here (#196): only
        # the `absent` default consults it, so explicit pr_policy=always/never (and
        # the explicit --pr/--no-pr flags handled earlier) never pay the
        # `gh api user` + `gh repo view --json viewerPermission` probe.
        IS_THIRD_PARTY=false
        SELF_LOGIN=$(gh api user --jq .login 2>/dev/null)
        if [ -n "$SELF_LOGIN" ] && [ "${GITHUB_REPO%%/*}" != "$SELF_LOGIN" ]; then
          case "$(gh repo view "$GITHUB_REPO" --json viewerPermission -q .viewerPermission 2>/dev/null)" in
            WRITE|MAINTAIN|ADMIN) IS_THIRD_PARTY=false ;;
            *)                    IS_THIRD_PARTY=true  ;;   # READ/TRIAGE/NONE/probe-fail → fail-safe
          esac
        fi
        if [ "$IS_THIRD_PARTY" = "true" ]; then
          PATH_AXIS="direct-commit"; INTERACTION="attended"; REASON="third-party clone, no push access (#192)"
        else
          PATH_AXIS="PR";            INTERACTION="unattended"; REASON="pr_policy absent (v2.40.0 default)"
        fi
        ;;
      ask)
        # 6. Explicit ask — break out of bash flow.
        # AskUserQuestion is a Claude tool, NOT a shell command.
        # See "Phase 0.5 ask-policy interaction" prose below.
        : "Phase 0.5 ask-policy escape — see prose below"
        ;;
      *)
        abort "Unknown pr_policy value: '$PR_POLICY'. Must be always / never / ask, or absent."
        ;;
    esac
  fi
fi
```

**Phase 0.5 ask-policy interaction** (prose — NOT a shell-callable function; this is what the Claude agent does when `pr_policy == "ask"` and no flag was passed):

When the resolution chain reaches the explicit `ask` case, the idd-all agent MUST invoke the **AskUserQuestion** tool (a Claude Code tool, not a CLI). Question template:

> "Path for `idd-all #${N}`?"
> - **PR** — feature branch + push + open PR + sub-skills run unattended (`/loop` friendly, public review path)
> - **direct-commit** — stay on current branch + no PR + sub-skills attended (HITL, solo/personal repo); after a clean verify on the default branch, idd-all pushes it and closes the issue (#392)

Based on the user's selection, set:
- PR → `PATH_AXIS="PR"; INTERACTION="unattended"; REASON="pr_policy=ask, user picked PR"`
- direct-commit → `PATH_AXIS="direct-commit"; INTERACTION="attended"; REASON="pr_policy=ask, user picked direct-commit"`

> **Why prose instead of bash**: `AskUserQuestion` is a tool the LLM agent invokes, not a binary on `$PATH`. Embedding `ANSWER=$(AskUserQuestion ...)` in the bash block was a category error caught in #1 verify (P0 finding 2). The agent reads the bash up to the `ask)` case label, then handles the question turn at the agent level, then resumes bash with the assigned variables.

```bash
# Resolved-tuple notice (mandatory — print before any state-mutating action)
echo "→ Path: ${PATH_AXIS} (${INTERACTION}) — ${REASON}"
REQUESTED_PATH="$PATH_AXIS"   # #392: Step 0.6 may downgrade PATH_AXIS; Step 0.7 records both
echo "→ requested path: $REQUESTED_PATH"

# Unattended signal (#123 — normative contract: references/unattended-contract.md)
# State file 是 harness 內唯一跨 tool-call 可靠訊號（env var 不跨 fresh shell、
# TTY 恆非互動 #222）。attended 分支的 clear 是防呆：清掉 crashed prior run 的殘留。
. "${CLAUDE_PLUGIN_ROOT}/scripts/lib/unattended-state.sh"
if [ "$INTERACTION" = "unattended" ]; then
  mark_unattended "$CWD" "idd-all"
else
  clear_unattended "$CWD"
fi
```

> **Subprocess hand-off（#123 契約訊號 2）**：unattended 模式下，idd-all 內部啟動的**真 subprocess**（如 plugin-tools `plugin-update`）必須在命令列前綴 `IDD_ALL_UNATTENDED=1`（state file 只對經 `is_unattended` 的 detector 有效；外部 plugin 讀 env var）。

#### Step 0.5.1: Existing-work check（#366）

在**建任何 branch 之前**，問「這張 issue 是否已有 PR 或 branch 在處理」。查詢只有一個實作：`scripts/check-existing-work.sh`（契約見 [`references/pr-issue-matching.md`](../../references/pr-issue-matching.md)，行為見 spec `idd-existing-work-lookup`）；本 skill **不得**自帶 PR 比對。from-scratch mode（還沒有 issue）與 `--in-chain`（`/idd-all-chain` 的 Phase 0.4 已對每個 root 做過）跳過。批次（`/idd-all #a #b #c`）逐張各跑一次，一張被停下不影響其他張。

```bash
if [ -z "$IN_CHAIN" ] && [ -n "${N:-}" ]; then
  EW_JSON=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/check-existing-work.sh" --cwd "$CWD" "$GITHUB_REPO" "$N") || EW_JSON='{}'
  # 跑不出結果也要講出來 —— 「不知道」不得讀成「沒有」。fallback 必須是 `{}` 不是空字串：jq 收到空輸入什麼都不印，
  # `// "unknown"` 根本不會執行，verdict 會變成空字串，處置表裡沒有這一列
  EW_VERDICT=$(printf '%s' "$EW_JSON" | jq -r --arg n "$N" '.issues[$n].verdict // "unknown"')
  EW_REASON=$(printf '%s' "$EW_JSON" | jq -r --arg n "$N" '.issues[$n].reason // "lookup produced no result"')
  # 一定要印 —— skill 是模型執行的，Bash 輸出是唯一的觀測通道；只賦值不印，blocked 與 clear 在執行者眼裡一樣
  echo "→ Existing work: #$N verdict=$EW_VERDICT ${EW_REASON:+($EW_REASON)}"
fi
```

| `$EW_VERDICT` | 行為 |
|---|---|
| `clear` | 繼續 |
| `unknown` | 印出原因並繼續（重複實作可逆；壞掉的網路不該停掉整批）。unattended 時另在 Action items 加一行 |
| `resume` | 在該 PR／branch 上繼續：設 `RESUME_BRANCH` 為證據裡自家的 `idd/N-*` branch，下面的 branch setup 改為 checkout 它，不再從預設 branch 開新的 |
| `blocked` | **attended**：用 **AskUserQuestion** 問三選一 —— (a) 接著在該 PR 上做、(b) 用 `idd-verify #N --pr P` 驗證它、(c) 忽略（在 issue body 加一行 `### Existing work: ignored #P by maintainer`）。選 (c) 才繼續往下；選 (a)(b) 不建 branch。**unattended**：**不**開始這張，印出 outcome，並把一行記進 `EXISTING_WORK_ITEMS`（Phase 6 會放進 `## Action items (require human review)`），然後結束這一張（批次繼續下一張） |

blocked 的 outcome 文字：E1 → `existing PR #P`；E3 → `already merged in PR #P -> /idd-close #N`。Action items 的一行：`- #N: existing PR #P declares it — not started; review it (/idd-verify #N --pr P) or run /idd-all #N interactively`（E3：`- #N: already merged in PR #P — run /idd-close #N`）。

**清掉上一次 run 的狀態（#392）**：existing-work check 放行之後（`clear`、`unknown`、`resume`，或 attended 選了 (c)），先跑 `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/close-stage.py" reset --cwd "$CWD" --issue "$N"`，刪掉這張 issue 上一次 run 留下的 run-state 與結果檔。排在這裡有兩個理由：之後 Step 0.7 若因 N 遺失而中止，close stage 讀不到上一次 run 的旗標（verify r3 #17、r5 #36）；同一個 clone 裡另一個還在等 CI 的 run 已經被上面的檢查擋下，不會被這裡清掉狀態（r4 #47）。from-scratch 在 Phase 1 建出 issue 之後跑。

> **為什麼 unknown 不擋**：這個檢查防的是重複實作，最壞只是多做一次；`idd-close` 擋的是把還沒做完的 issue 結掉——close 能 reopen，但結案摘要一貼出就通知了關注這張的人——所以它對失敗維持 fail-closed。兩者的差別是刻意的。

**PR mode branch setup**(只在 `PATH_AXIS=PR` 執行):

```bash
if [ "$PATH_AXIS" = "PR" ]; then
  # PR-mode-only preconditions
  if [ -n "$(git -C "$CWD" status --porcelain)" ]; then
    echo "Uncommitted changes detected in $CWD. PR mode needs a clean working tree."
    git -C "$CWD" status --short
    abort "Run 'git -C $CWD stash' or commit first, then re-run /idd-all."
  fi

  CURRENT=$(git -C "$CWD" branch --show-current)
  DEFAULT=$(gh repo view "$GITHUB_REPO" --json defaultBranchRef -q .defaultBranchRef.name)
  if [ "$CURRENT" != "$DEFAULT" ]; then
    abort "$CWD is currently on '$CURRENT'. PR mode must start from '$DEFAULT'.
   Run: git -C $CWD checkout $DEFAULT"
  fi

  # Build feature branch name
  N="19"  # 從 args 或 idd-issue 結果取得
  TITLE=$(gh issue view "$N" -R "$GITHUB_REPO" --json title -q .title)
  # SLUG sanitization — POSIX-portable; avoids BSD/GNU sed `\|` divergence (#6 fix)
  SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' \
      | sed -E 's/[^a-z0-9]/-/g; s/-+/-/g; s/^-//; s/-$//' \
      | cut -c1-40)
  BRANCH="idd/${N}-${SLUG}"
  # #366: resume — 證據裡自家的 idd/N-* branch 取代新 branch 名
  [ -n "${RESUME_BRANCH:-}" ] && BRANCH="$RESUME_BRANCH"

  # #3 fix: branch-already-exists is now a real AskUserQuestion handoff,
  # not a no-op `:` followed by guaranteed-fail `git checkout -b`.
  if git -C "$CWD" show-ref --verify --quiet "refs/heads/$BRANCH"; then
    # The agent invokes AskUserQuestion (Claude tool — see Phase 0.5 ask-policy
    # prose for the same pattern). Three options:
    #   (a) Checkout existing — continue work on the prior branch
    #   (b) Use suffix — try BRANCH-2, BRANCH-3, ... until unused
    #   (c) Abort — let user clean up manually
    # Per (a): git checkout "$BRANCH"
    # Per (b): NEXT=$(suffix_for "$BRANCH"); BRANCH="$NEXT"; git checkout -b "$BRANCH"
    # Per (c): abort "Branch $BRANCH already exists. Run: git -C $CWD branch -D $BRANCH or pick a different issue."
    :  # bash flow exits the if; agent assigns BRANCH per user's choice and falls through
  elif [ -n "${RESUME_BRANCH:-}" ]; then
    git -C "$CWD" checkout -b "$BRANCH" "origin/$BRANCH"   # #366: resume 該 remote branch
  else
    # #392 verify r5 #21, #23: branch from the remote default branch as it is now, not from the local
    # one. A local default that missed a merge makes the close stage stop as "behind" only after
    # implement and verify; one with unpushed commits would put work that is not this issue's in the PR.
    git -C "$CWD" fetch -q origin "$DEFAULT" || abort "Could not fetch origin/$DEFAULT."
    git -C "$CWD" checkout --no-track -b "$BRANCH" "origin/$DEFAULT"   # no upstream: the meeting unwind reads it (r6 #18)
  fi
fi
```

**Chain-context mode**(`IN_CHAIN=1` set,v2.55+ #44):

```bash
if [ -n "$IN_CHAIN" ]; then
  # Sub /idd-all called by /idd-all-chain. Cluster branch already created by
  # chain shell — DO NOT create per-issue feature branch, DO NOT change branch.
  CURRENT_BRANCH=$(git -C "$CWD" branch --show-current)

  # Sanity check: cluster branch convention is `idd/chain-*` — refuse if not on
  # one (prevents external misuse like `/loop --in-chain` without chain shell).
  if [[ ! "$CURRENT_BRANCH" =~ ^idd/chain- ]]; then
    abort "--in-chain set but current branch '$CURRENT_BRANCH' does not match cluster convention 'idd/chain-*'.
   /idd-all --in-chain is meant to be invoked from within /idd-all-chain only.
   If you reached here directly, run /idd-all-chain #N instead."
  fi

  BRANCH="$CURRENT_BRANCH"
  # Phase 5.5 PR creation will also be skipped (see Phase 5 conditional).
fi
```

**Direct-commit mode**(`PATH_AXIS=direct-commit` AND `IN_CHAIN` unset):

```bash
if [ "$PATH_AXIS" = "direct-commit" ] && [ -z "$IN_CHAIN" ]; then
  CURRENT_BRANCH=$(git -C "$CWD" branch --show-current)
  echo "→ direct-commit path: committing to ${CURRENT_BRANCH}, no PR will be opened"

  # Passive warnings (#2 — surface risks without aborting; user is in HITL session)
  if [ -n "$(git -C "$CWD" status --porcelain)" ]; then
    echo "⚠ Working tree has uncommitted changes — these will be intermingled with idd-all commits."
    echo "  If sensitive (e.g. .env, secrets), abort now and stash or commit them first."
  fi
  DEFAULT_FOR_WARN=$(gh repo view "$GITHUB_REPO" --json defaultBranchRef -q .defaultBranchRef.name 2>/dev/null)
  if [ -n "$DEFAULT_FOR_WARN" ] && [ "$CURRENT_BRANCH" = "$DEFAULT_FOR_WARN" ]; then
    echo "⚠ direct-commit on default branch '${DEFAULT_FOR_WARN}' — no PR review gate."
  fi

  # 不檢查 working-tree clean,不檢查 on default branch (HITL trade-off — user 自負其責)
  # 不建 feature branch — 留在 user 當前 checkout
  BRANCH="$CURRENT_BRANCH"
fi
```

> **為什麼 direct-commit 不強制 clean tree / default branch**: HITL 場景下 user 可能在自己的 wip branch 上工作、可能有未 commit 的 staging — idd-all 不該擾動這些 user state。Trade-off: user 自負「commit 落在哪個 branch」的責任。
>
> **為什麼 PR mode 仍從 default branch 起跳**: PR 是給人 review 的;從 feature-on-feature 起跳的 PR diff 會包含上層 feature 的所有 commit,review noise 太大 — 應 abort 讓 user 想清楚。

---

#### Step 0.6: ralph-loop graceful degrade gate（v2.53+, #28）

Phase 0.5 解析出 `(PATH_AXIS, INTERACTION)` 後,若 tuple 是 `(PR, unattended)`(無論來自 flag、fork detection、`pr_policy=always`、或 v2.40.0 default),**必須**檢查 ralph-loop 是否 installed。缺失則 graceful degrade 而非 abort。

```bash
if [ "$PATH_AXIS" = "PR" ] && [ "$INTERACTION" = "unattended" ]; then
  if ! "${CLAUDE_PLUGIN_ROOT}/scripts/check-ralph-loop.sh" 2>/dev/null; then
    echo "⚠ ralph-loop plugin not detected — required to drive (PR, unattended) verify-fix loop."
    echo "  Degrading to (direct-commit, attended) for backward-compat (#28 B4 design)."
    echo "  To restore (PR, unattended): claude plugin install ralph-loop@claude-plugins-official"
    echo ""

    # F2 fix: Phase 0.5 PR mode branch setup already created `idd/<N>-<slug>`
    # and checked it out. Without unwinding, degrade leaves user committing to
    # a dangling feature branch they never wanted (silent state corruption per
    # verify finding F2). MUST unwind before flipping mode.
    if [ -n "${BRANCH:-}" ] && git -C "$CWD" show-ref --verify --quiet "refs/heads/$BRANCH"; then
      DEFAULT=$(gh repo view "$GITHUB_REPO" --json defaultBranchRef -q .defaultBranchRef.name)
      echo "→ Unwinding Phase 0.5 PR-mode branch setup before degrade:"
      echo "    git checkout $DEFAULT"
      git -C "$CWD" checkout "$DEFAULT" 2>&1 | tail -1
      echo "    git branch -d $BRANCH (no commits yet — safe delete)"
      git -C "$CWD" branch -d "$BRANCH" 2>&1 | tail -1
    fi

    PATH_AXIS="direct-commit"
    INTERACTION="attended"
    REASON="$REASON + ralph-loop missing → graceful degrade (#28)"
    BRANCH=$(git -C "$CWD" branch --show-current)
    echo "→ Path: ${PATH_AXIS} (${INTERACTION}) — ${REASON}"
    echo "→ Will commit to current branch: ${BRANCH}"
  fi
fi
```

**為什麼 graceful degrade 不 abort**: `(PR, unattended)` 是 v2.40.0 default(`pr_policy` 缺省 → fall to step 7)。abort 會 break 所有既有 callers(包含 `/loop` 等舊 caller)違反 backward compat。Degrade 讓 IDD 仍能跑完整 pipeline(只是改 attended),user 看到 warning 可選 install + retry。

> **Native alternative driver — `/goal`（v2.1.139+，#138）**：上面的 verify-fix loop driver 角色也可由 Claude Code 內建的 [`/goal`](https://code.claude.com/docs/en/goal.md) 擔任 —— 設一個 completion condition，它每 turn 後自動檢查、未達成就再跑下一 turn 直到滿足，是 native（無需第三方 plugin）。**本 gate 目前偵測的是 `ralph-loop` plugin**；若使用者偏好 native，可在 idd-all 之外手動以 `/goal` 驅動同一 verify-fix 迴圈。把本 gate 改為原生支援 `/goal`（少一個外部依賴）是更大的設計題，列為 #138 residue 不在此處理。

**為什麼必須 unwind branch (F2 fix)**: Phase 0.5 PR mode setup 已 `git checkout -b idd/<N>-<slug>` 建好 feature branch。若 Phase 0.6 直接翻 `PATH_AXIS=direct-commit` 而不 unwind,degrade 後 commits 落在這個 dangling branch — user 預期落在自己 branch (e.g. main),結果靜默偏離。必須先 `git checkout $DEFAULT` + `git branch -d $BRANCH` 清掉,才能 flip mode。**Edge case**: 若 Phase 0.6 在 mid-implement 才偵測到 (例如 ralph-loop 中途被卸載) — 此時 feature branch 已有 commits,`git branch -d` 會 refuse,改要 user 手動處理 + abort。但本 skill 設計 Phase 0.6 在 Phase 1 (idd-issue) 之前跑,unwind 必為 safe-delete 場景。

**對比 `/idd-verify --loop` Step 0a 是 fail-fast**: `--loop` 是 user explicit feature request,silent fallback 違反 user 預期。兩條 path 對缺失的處理不同,各有理由。

#### Step 0.7: Record the run（#392）

mode 定案之後（含 Step 0.6 的 degrade），把這次 run 的旗標寫進 run-state 檔。Phase 5c 的 helper 從這裡讀 `--review`、`--in-chain`、path、interaction 與 branch，不靠 shell 變數或模型記得：

```bash
# from-scratch runs this after Phase 1 has created the issue. N must be set here: a lost N is
# an error, not a reason to skip the block silently (#392 verify r3 #17).
case "${N:-}" in ''|*[!0-9]*) echo "FATAL: Step 0.7: issue number is missing — re-derive N, then run this block" >&2; exit 1 ;; esac
DEFAULT_BRANCH=$(gh repo view "$GITHUB_REPO" --json defaultBranchRef -q .defaultBranchRef.name)
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/close-stage.py" init --cwd "$CWD" --repo "$GITHUB_REPO" --issue "$N" \
  --path "$PATH_AXIS" --requested-path "$REQUESTED_PATH" --interaction "$INTERACTION" \
  --branch "$BRANCH" --default "$DEFAULT_BRANCH" --review "$REVIEW_YN" --in-chain "$IN_CHAIN_YN" \
  || { echo "⚠ Step 0.7: the run state was not recorded — the run continues, and the close stage will stop at verified (it merges only with a run state)"
       python3 "${CLAUDE_PLUGIN_ROOT}/scripts/close-stage.py" reset --cwd "$CWD" --issue "$N"; }   # a failed init leaves no run state
```

每個值都必填：shell 變數跨 tool call 遺失時，init 會因為空值而報 usage error（exit 64），不會悄悄記成「沒有 `--review`」。run 照常往下走，close stage 因為沒有 run-state 而停在 verified：上一次 run 的狀態已在 Step 0.5.1 之後清掉，`||` 之後的 reset 再清一次，不沿用上一次 run 的旗標（verify r3 #17、r5 #36）。N 本身遺失時，上面的 FATAL 先中止這一段，同樣沒有舊狀態可讀。在新的 shell 重跑這一段時，`REVIEW_YN`／`IN_CHAIN_YN`／`REQUESTED_PATH` 要從這次 `/idd-all` 的原始參數與 Phase 0.5 印出的那兩行重新得出。

檔案在 `$CWD/.claude/.idd/state/`，與 unattended flag 同一個目錄；請確認目標 repo 的 ignore 規則涵蓋它（`scripts/git-ignore-block.sh`）。run-state 超過 24 小時就不算數；Phase 6 結束時刪掉。沒有這個檔，Phase 5c 一律不 merge、不 push。

---

### Phase 1: Ensure Issue Exists

```
if [ from-scratch mode ]:
    Skill(skill="issue-driven-dev:idd-issue", args="<arg from /idd-all> --target $GITHUB_REPO")
    # idd-issue 會 post issue 並 print 出 number → capture 它
    N = parse from idd-issue output
    # then run Step 0.7 (record the run) — it needs the issue number
elif [ from-issue mode ]:
    # already validated in Phase 0.3
    pass
```

> **`--target` not `--cwd` for idd-issue**: idd-issue 是 read-only(只 `gh issue create`),不 touch local git。所以用 `--target $GITHUB_REPO` 即可,不需要 `--cwd`。

---

### Phase 2: Diagnose

idd-all 必須把 `--cwd "$CWD"` 傳給 idd-diagnose,否則 sub-skill 會在 Claude Code session 的 default cwd 跑(可能是錯的 repo):

```
Skill(skill="issue-driven-dev:idd-diagnose", args="#$N --cwd $CWD")
```

**讀回 complexity 並過 actionability gate**:idd-diagnose 結束後抓最新 `## Diagnosis` comment、labels 與 body 的 `### Blocking`,**tier 抽取與可動性判定都不在此處自行寫**,改呼叫 [`references/actionability-gate.md`](../../references/actionability-gate.md) 契約下的共用實作:

```bash
# 缺 helper 一律 fail loud + 指名 path，禁止 fallback 到私有 regex（契約 §Consumer contract）
. "${CLAUDE_PLUGIN_ROOT}/scripts/lib/actionability.sh" || {
    echo "FATAL: missing ${CLAUDE_PLUGIN_ROOT}/scripts/lib/actionability.sh — 不得改用私有 regex" >&2
    exit 1
}

# 0. issue 號進 REST path 前先驗型
case "$N" in ''|*[!0-9]*) echo "FATAL: non-numeric issue number: $N" >&2; exit 1 ;; esac

# 1. 最新 Diagnosis comment —— 只信任 OWNER / MEMBER / COLLABORATOR 寫的（public repo 任何帳號都能留言）；必須分頁。`gh issue view --json comments` 只回最舊的 100 則，
#    issue 一長，最新的 diagnosis 正好是被丟掉的那一則（#295 同族；`--paginate --jq` 每頁一個 array，`jq -s add` 收攏）。
#    抓取與折疊分開捕捉（折疊 `jq -s | python3` 仍是同一條管線）：管線裡 `gh` 失敗時 `jq -s` 收到空輸入照樣回 `[]`，失敗的抓取會被讀成「沒有 diagnosis」；第 2 頁以後才失敗則會拿不完整的 comment 判定。
PAGES=$(gh api "repos/$GITHUB_REPO/issues/$N/comments" --paginate --jq '[.[] | select(.author_association == "OWNER" or .author_association == "MEMBER" or .author_association == "COLLABORATOR") | {body}]') \
    || { echo "FATAL: gate #$N: comment fetch failed — gate not evaluated" >&2; exit 1; }
LATEST_DIAGNOSIS=$(jq -s 'add // []' <<<"$PAGES" | python3 -c '
import json, sys, re
cs = json.load(sys.stdin)
ds = [c for c in cs if re.search(r"(?m)^## Diagnosis", c["body"])]   # line-anchored，引述/inline 不算（v2.68.0+ #59）
print(ds[-1]["body"] if ds else "")') \
    || { echo "FATAL: gate #$N: comment fold failed — gate not evaluated" >&2; exit 1; }

# 2. 另外兩個訊號：labels，與 body 的 ### Blocking（經 helper 讀；idd-update 的 `- (none)` placeholder 算空）
ISSUE_JSON=$(gh issue view "$N" --repo "$GITHUB_REPO" --json labels,body) \
    || { echo "FATAL: gate #$N: issue fetch failed — gate not evaluated" >&2; exit 1; }
HAS_PARKING=$(jq -r 'if any(.labels[]; .name == "parking-lot") then "yes" else "no" end' <<<"$ISSUE_JSON")
BLOCK_LINE=$(idd_blocking_section "$(jq -r '.body // ""' <<<"$ISSUE_JSON")")
if [ -n "$BLOCK_LINE" ]; then BLOCKING=yes; else BLOCKING=no; fi
# 2.5 Diagnosis type（#383）—— 只信最新受信任 Diagnosis 的 `### Type`。label 與 issue 本文都不採用：本文由 issue 作者自由改寫（verify r4）。
#     meeting 不評 Complexity 訊號，parking-lot 與 Blocking 照評；沒有受信任的 Diagnosis 時是 none，照常 complexity-missing
DIAG_TYPE=$(idd_diagnosis_type "$LATEST_DIAGNOSIS") \
    || { echo "FATAL: gate #$N: idd_diagnosis_type misuse — gate not evaluated" >&2; exit 1; }

# 3. 條件式捕捉 —— `set -euo pipefail` 下唯一不會被 exit 3/4/5 終止的寫法（verify #318 HIGH）
if TIER=$(idd_parse_complexity "$LATEST_DIAGNOSIS" 2>/dev/null); then CEXIT=0; else CEXIT=$?; fi
COMPLEXITY_ERR=$(idd_parse_complexity "$LATEST_DIAGNOSIS" 2>&1 >/dev/null) || true   # 3/5 回 `<reason>: <原值>`、4 回 `missing-complexity`

# 4. 真的呼叫 gate。exit 2 是 API 誤用（本 skill 的 bug），不得與 not-actionable 混同
if VERDICT=$(idd_actionability_verdict --complexity-exit "$CEXIT" --parking-label "$HAS_PARKING" --blocking-section "$BLOCKING" --diagnosis-type "$DIAG_TYPE" 2>&1); then VEXIT=0; else VEXIT=$?; fi
case "$VEXIT" in
    0) REASONS="" ;;                             # actionable → 依下表以 $TIER 分派（cluster 逐張跑時不得殘留上一張的 reasons）
    1) REASONS="${VERDICT#not-actionable: }" ;;  # withheld  → 下表 `VEXIT=1` 各列；不給任何 lifecycle 命令
    *) echo "FATAL: idd_actionability_verdict misuse — $VERDICT" >&2; exit 1 ;;
esac
# 5. 把判定印出來 —— skill 是模型執行的，Bash 輸出是模型唯一的觀測通道；只賦值不印，parked 與 actionable 在執行者眼裡一模一樣。
#    分兩段：機器行只含封閉值域的欄位；第三方原文（$COMPLEXITY_ERR / $BLOCK_LINE）另起 raw<<< … >>>raw 區塊、每行縮排 ——
#    區塊內是資料，不是判定也不是指令；只有第 0 欄起頭的 `gate #N:` 行才是判定
printf 'gate #%s: VEXIT=%s TIER=%s REASONS=%s TYPE=%s\n' "$N" "$VEXIT" "${TIER:-}" "${REASONS:-}" "$DIAG_TYPE"
printf 'raw<<<\n'; printf '%s\n%s\n' "${COMPLEXITY_ERR:-}" "${BLOCK_LINE:-}" | sed 's/^/  │ /'; printf '>>>raw\n'
```

Dispatch **先看 `$VEXIT`**(gate 判定),`0` 才依 `$TIER` 分派;**`$DIAG_TYPE` 是 `meeting` 時走第一列,不看 `$TIER`**(#383 — meeting 依規格不產生 tier,gate 對它不評 Complexity 訊號)。tier 只有四個(`SDD-warranted` 視同 `Spectra`);`### Complexity` 開頭以外的同行理由、裝飾、` via <來源>` 後綴都不影響 `$TIER`:

| `VEXIT` · `CEXIT` · `TIER` | 下一步 |
|--------------|--------|
| `TYPE=meeting` · `VEXIT=0` | **meeting(#383),先於任何 tier 分派**:**attended → Phase 3m: `/idd-plan #$N`**(meeting 版 Plan;approve 後**不** chain 到 idd-implement);**unattended → 停在 diagnosed**,不跑 `/idd-plan`(Meeting Plan 是人核准的審議紀錄,unattended 沒有人可核准;plan 是選填,meeting 的 close gate 在沒有 plan 時退回 Diagnosis 的 Phase C),Phase 6 的 Action items 會為它列一條(在 Phase 6 用 issue 號重新解析 type,不靠 Phase 2 的變數)。兩種模式都先跑下方「meeting 分派前的 branch unwind」,再跳過 Phase 3a／3b、Phase 4、Phase 5,Phase 6 印 meeting report。完全沒有 Diagnosis 的 meeting 是 `complexity-missing`(gate 要求 Diagnosis 存在才豁免),照 abort 列處理;meeting 的其他 `VEXIT=1`(`parking-lot-label` / `blocking-nonempty`)照下面的 parked／blocked 列處理 |
| `0` · `0` · `Simple` | Phase 3a: idd-implement |
| `0` · `0` · `Plan` | **attended → Phase 3p: `/idd-plan`**（該 skill 擁有 `EnterPlanMode` 閘門，approve 後自己 chain 到 idd-implement）;**unattended → Phase 3a: idd-implement**，並在 final report 標記 `[Plan tier deliberation skipped under unattended mode]` |
| `0` · `0` · `Plan`（原值 `Plan via Layer V`,v2.50+）| 同上 — helper 只取開頭的 tier,` via <來源>` 後綴與同行理由皆不影響;verdict 是 user 在 idd-diagnose Step 3.4 選 escalate 觸發,routing 行為跟 bare `Plan` 一致 |
| `0` · `0` · `Spectra` | Phase 3b: spectra-discuss → spectra-propose → spectra-apply(unattended → 一輪收斂;attended → multi-turn 對話自然進行) |
| `0` · `0` · `SDD-warranted` (legacy alias) | 視同 `Spectra` 處理(v2.36.0+ backward compat) |
| `VEXIT=1` · `$REASONS` 含 `complexity-deferral-marker`(如 `Simple when triggered`、`**Spectra**(… if/when triggered)`)或 `parking-lot-label` | **abort(parked)** — 印出 `$REASONS` 與原文(`$COMPLEXITY_ERR` 的 `deferral-marker: <原值>`,或 label 名)。這是**合法的延期狀態,不是資料錯誤**:不要求 user「修正」Diagnosis;要動它,先由人移除 label 或重新 diagnose。**禁止**截斷成 tier 前綴、**禁止**降級成任何 tier、**禁止**因為 tier 前綴合法就分派 |
| `VEXIT=1` · `$REASONS` 含 `blocking-nonempty` | **abort(blocked)** — 印出 `$BLOCK_LINE`;等 blocker 解除(`idd-update` 清 `### Blocking`)|
| `VEXIT=1` · `complexity-unparseable`(值不以 tier 開頭,如 `移入 discussion list`)| **abort** — 印出 `$COMPLEXITY_ERR` 的 `unparseable-complexity: <原值>`,要求 user 修正 Diagnosis(這才是資料錯誤)|
| `VEXIT=1` · `complexity-missing`(無 `### Complexity` 區段,含完全沒有 `## Diagnosis` comment)| **abort** — diagnose 沒判定 complexity,user 需手動釐清(即舊表的 `UNKNOWN` 列,語意不變)|

#### meeting 分派前的 branch unwind(#383 verify r1, r2)

Phase 0.5 在得知 type **之前**就建好 feature branch(PR 模式)。meeting 不 implement,不收的話使用者會停在那個 branch 上。這段**在 code 裡**判斷 type——第一版只靠註解限定 meeting,模型由上往下照做時,非 meeting 的 PR run 也會把 branch 刪掉(verify r2 #4,已用行為測試釘住)。

diagnose 寫的 `.claude/.idd/attachments/issue-N/` 依 repo 慣例要追蹤(`rules/process-attachments.md`),一般 run 由 implement 的 commit 帶走;meeting 沒有 implement,不處理的話它會以 untracked 跟著 checkout 到預設 branch,下一次 PR 模式的 Phase 0.5 就因工作樹不乾淨而 abort(r2 #6)。所以先把它 commit 在 feature branch 上、保留那個 branch(不 push),再切回預設 branch;沒有任何東西要留時才刪掉空 branch。

```bash
# N 進 gh 與 git pathspec 前先驗型（r3 #19）
case "$N" in ''|*[!0-9]*) echo "FATAL: meeting unwind: issue number is not numeric: $N" >&2; exit 1 ;; esac
# direct-commit 沒有 Phase 0.5 branch，也不必查 type（r3 #23）。diagnose 寫的 manifest 留在工作樹，
# 跟下一個 commit 一起提交（r4 #26；direct-commit 的 Phase 0.5 不因工作樹不乾淨而 abort）
if [ "${PATH_AXIS:-}" = "direct-commit" ]; then
  echo "→ direct-commit: no Phase 0.5 branch — nothing to unwind; the attachment manifest written by diagnose, if any, stays uncommitted in the working tree — commit it with your next change"
  exit 0
fi
# type 只信最新受信任 Diagnosis 的 ### Type，不看 issue 本文（r4 #19／#35：本文由 issue 作者自由改寫）。
# 先判 type（只需要 issue 號）：非 meeting 的 run 不因下面任何 shell 狀態遺失而中止（r4 #3／#8、r5 #10）
. "${CLAUDE_PLUGIN_ROOT}/scripts/lib/actionability.sh" || { echo "FATAL: meeting unwind: actionability helper missing — branch left as is" >&2; exit 1; }
# GITHUB_REPO 是 Phase 0.3 的 shell 狀態，少了它就讀不到 type。讀不到 type 時與 fetch 失敗同樣只警告、不中止：
# 非 meeting 的 run 不因 shell 狀態遺失而中止（r4 #3／#8）。訊息分開寫，看得出是遺失而不是暫時性失敗（r6 #14、PR #398 review）
[ -n "${GITHUB_REPO:-}" ] || { echo "⚠ meeting unwind: GITHUB_REPO is empty (shell state lost) — cannot read the Diagnosis type of #$N; branch left as is. If #$N is a meeting issue, re-run the repo resolution and then the unwind, or commit .claude/.idd/attachments/issue-$N on the idd/$N-* branch and return to the default branch by hand"; exit 0; }
# 查詢失敗時不知道 type：branch 原樣保留本來就是非 meeting run 該有的結果，所以只警告、不中止（r5 #14）
UW_PAGES=$(gh api "repos/$GITHUB_REPO/issues/$N/comments" --paginate --jq '[.[] | select(.author_association == "OWNER" or .author_association == "MEMBER" or .author_association == "COLLABORATOR") | .body | select(split("\n") | any(startswith("## Diagnosis")))]') \
  || { echo "⚠ meeting unwind: could not read the Diagnosis type of #$N (comment fetch failed) — branch left as is; if #$N is a meeting issue, commit .claude/.idd/attachments/issue-$N on the idd/$N-* branch and return to the default branch by hand"; exit 0; }
# jq 讀不了 comment 清單時與 fetch 失敗同樣處理；helper 拿到一個參數恆 exit 0（r6 #12）
UW_LATEST=$(jq -s -r 'add // [] | last // ""' <<<"$UW_PAGES") \
  || { echo "⚠ meeting unwind: the comment list of #$N is not readable — branch left as is; if #$N is a meeting issue, commit .claude/.idd/attachments/issue-$N on the idd/$N-* branch and return to the default branch by hand"; exit 0; }
UW_TYPE=$(idd_diagnosis_type "$UW_LATEST")
[ "$UW_TYPE" = meeting ] || { echo "→ #$N: the trusted Diagnosis says '$UW_TYPE', not meeting — no unwind"; exit 0; }
# CWD 是 Phase 0.2 的 shell 狀態。空字串時 `git -C ""` 會讀 session 目錄，回報「nothing to unwind」——
# 跟 r3 #2 修掉的 PATH_AXIS 同一種靜默略過（r5 #10）。只有確定是 meeting 才要求它
[ -n "${CWD:-}" ] || { echo "FATAL: meeting unwind: CWD is empty — the Phase 0.2 shell state was lost; re-run its resolution. Branch left as is" >&2; exit 1; }
# 要收的 branch 由 git 判斷，不信任 $BRANCH：只收「現在所在、名為 idd/N-*」的那個（r3 #2、#10）
CUR=$(git -C "$CWD" branch --show-current) || { echo "FATAL: meeting unwind: cannot read the current branch" >&2; exit 1; }
case "$CUR" in "idd/$N-"*) ;; *) echo "→ on '$CUR', not the Phase 0.5 branch of #$N — nothing to unwind"; exit 0 ;; esac
# PATH_AXIS 是 Phase 0.5 的 shell 狀態，不跨 Bash 呼叫。只有確定是 meeting 才要求它；遺失時明講，
# 不能當成「沒有 branch」悄悄略過（r3 #2）。放在 type 之後：非 meeting 的 run 不因此 abort（r4 #3／#8）
[ "${PATH_AXIS:-}" = "PR" ] || { echo "FATAL: meeting unwind: PATH_AXIS is '${PATH_AXIS:-}' — the Phase 0.5 shell state was lost; re-run its mode resolution. Branch left as is" >&2; exit 1; }
DEFAULT=$(gh repo view "$GITHUB_REPO" --json defaultBranchRef -q .defaultBranchRef.name) && [ -n "$DEFAULT" ] \
  || { echo "FATAL: meeting unwind: default branch lookup failed — still on $CUR" >&2; exit 1; }
ATT=".claude/.idd/attachments/issue-$N"; COMMITTED=""
if [ -n "$(git -C "$CWD" status --porcelain -- "$ATT")" ]; then
  { git -C "$CWD" add -- "$ATT" && git -C "$CWD" commit -q -m "chore: record the attachment manifest of a meeting issue (#$N)" -m "Refs #$N" -- "$ATT"; } \
    || { echo "FATAL: meeting unwind: could not commit $ATT — still on $CUR" >&2; exit 1; }
  COMMITTED=1
fi
AHEAD=$(git -C "$CWD" rev-list --count "$DEFAULT..$CUR") || { echo "FATAL: meeting unwind: rev-list failed — still on $CUR" >&2; exit 1; }
UPSTREAM=$(git -C "$CWD" rev-parse --abbrev-ref --symbolic-full-name "$CUR@{upstream}" 2>/dev/null || true)
git -C "$CWD" checkout -q "$DEFAULT" || { echo "FATAL: meeting unwind: checkout $DEFAULT failed — still on $CUR" >&2; exit 1; }
if [ "$AHEAD" = 0 ] && [ -z "$UPSTREAM" ]; then
  # 沒有 commit、沒有 upstream 才刪;-d 只在這個前提下是 safe delete(r2 #13/#19)
  if git -C "$CWD" branch -q -d "$CUR"; then echo "→ type=meeting: removed the empty Phase 0.5 branch $CUR (now on $DEFAULT)"
  else echo "⚠ type=meeting: could not delete $CUR — left in place (now on $DEFAULT)"; fi
else
  # 說實際的狀態，不預設（r4 #17）：有 upstream 就不說「not pushed」，只有本次 commit 了 manifest 才提它
  if [ -n "$UPSTREAM" ]; then STATE="tracks $UPSTREAM"; else STATE="not pushed"; fi
  echo "→ type=meeting: back on $DEFAULT; kept $CUR ($AHEAD commit(s) not on $DEFAULT${COMMITTED:+, including the attachment manifest written by diagnose}) — $STATE. To use the manifest in a later /idd-plan or /idd-close, check that branch out; push it with a later PR, or delete it with git branch -D $CUR if it is not needed. A later PR-mode /idd-all #$N stops at Phase 0.5 until this branch is dealt with (r4 #25)"
fi
REST=$(git -C "$CWD" status --porcelain)
[ -z "$REST" ] || printf '⚠ working tree not clean after the meeting unwind — the next PR-mode run will stop at Phase 0.5:\n%s\n' "$REST"
```

> **為何不在此處寫 regex（#298 → #316）**：本段原本就地用一條 `(.+?)` 窄化抓 `### Complexity` 標題下的整行，再自行 `split(' via ')` 取 canonical tier。那條 regex 對 `Simple when triggered` 這類**帶延期修飾語**的值會**匹配成功**，回傳一個非 tier 字串——它對不上任何 dispatch 列，卻也不是 `UNKNOWN`。舊表的 `UNKNOWN → abort` 安全網結構上接不住它：`UNKNOWN` 只在 regex **完全匹配失敗**時才產生（`if m else` 分支），值域外的**成功**匹配永遠落不進那一格，routing 因此進入未定義行為。修法不是把 regex 寫得更嚴——那只會讓第四份私有窄化加入既有的三方分歧——而是讓判定只剩一份實作：tier 前綴抽取、延期語彙偵測、`### Blocking` 讀取、三訊號 gate、原值 surface 全在 `scripts/lib/actionability.sh`，本 skill 只讀它的 exit code。**只換 parser 不呼叫 verdict 等於沒修**——第 1 輪（PR #318）正是如此：gate 完整、66 測試全綠、零 consumer 呼叫（verify CRITICAL-1）。「不得截斷、不得降級、不得靜默」的規定見 [`references/actionability-gate.md`](../../references/actionability-gate.md)。

> **Layer V under (PR, unattended) — v2.50+**: Layer V Vagueness Pre-check (idd-diagnose Step 3.4) 在 unattended 仍評分 + 寫 audit trail,但 trigger 時自動 apply `proceed anyway` 不跳 AskUserQuestion。final report 應 surface `idd-diagnose` audit trail 中含 `[Layer V: V1=N V4=M, clarify-default skipped under unattended mode, defaulting to proceed]` 的 issue,讓 user 後續可以手動重 route。
>
> **Plan tier under (PR, unattended)**: Plan tier 的核心價值是 user approval via `EnterPlanMode`/`ExitPlanMode`。unattended 沒有 user 在 review plan,所以 Plan path 直接跳到 idd-implement,**在 final report 標記 `[Plan tier deliberation skipped under unattended mode]`**。
>
> **Plan tier under (direct-commit, attended)**: 路由到 **`/idd-plan`**,由它 `EnterPlanMode` 呈現 plan 給 user,user `ExitPlanMode` approve 後由 `/idd-plan` 自己 chain 到 `/idd-implement`。這是 attended mode 的設計目的之一。
>
> **修正紀錄（#292）**：本表過去把 Plan tier 直送 `idd-implement`,並宣稱該 skill 的 `EnterPlanMode` 閘門會「自然 fire」。**那個閘門不在 `idd-implement` 裡** —— 它住在 `/idd-plan`（見該 skill Step 4 `enter_plan_mode_for_approval`）。`idd-implement` 收到 Plan tier 時做的是**印一句警告**並用 AskUserQuestion 問要不要繼續（見其 SKILL.md 的 Complexity 表）。而 `grep "idd-plan" idd-all/SKILL.md` 在修正前**沒有任何命中** —— `/idd-plan` 從 `/idd-all` 根本到不了。結果是 Plan tier 的 approval checkpoint 在 orchestrated 路徑上整個消失,而三處文件都宣稱它在。
>
> **SDD path under (PR, unattended)**: 三步 chain `spectra-discuss → spectra-propose → spectra-apply`,每步傳 `UNATTENDED MODE` directive 抑制 `AskUserQuestion`,一輪收斂、不停 Park。
>
> **SDD path under (direct-commit, attended)**: 三步同樣 chain,但**完全不傳** unattended hint。`spectra-discuss` 多輪節奏、`spectra-propose` Step 10 Park/Apply 問題、`spectra-apply` Step 4 continue-confirmation 都自然 fire。這是 HITL 的核心場景。

---

### Phase 3a: Simple/Plan Path — idd-implement

依 Phase 0.5 的 `(PATH_AXIS, INTERACTION)` 條件組 invocation args。**Args 構造遵守「two axes derived from one source」原則**(見 spec `idd-pr-hitl-modes`「Attended interaction permits sub-skill questions」requirement):

```bash
# Build args conditionally — UNATTENDED MODE directive only when interaction == unattended
IMPL_ARGS="#$N --cwd $CWD"
# #366: 本 skill 已在 Step 0.5.1 做過存在工作檢查，idd-implement 不必再問
IMPL_ARGS="$IMPL_ARGS --existing-work-checked"
if [ "$PATH_AXIS" = "PR" ]; then
  IMPL_ARGS="$IMPL_ARGS --pr"
elif [ "$PATH_AXIS" = "direct-commit" ]; then
  IMPL_ARGS="$IMPL_ARGS --no-pr"
fi

if [ "$INTERACTION" = "unattended" ]; then
  # Inline directive — sub-skill suppresses AskUserQuestion / EnterPlanMode prompts
  IMPL_ARGS="$IMPL_ARGS

UNATTENDED MODE — called by /idd-all orchestrator. Suppress AskUserQuestion. If complexity is Plan, this is a DELIBERATE DOWNGRADE to the Simple path — there is no approval gate in this skill to skip (it lives in /idd-plan); proceed straight to TDD and mark in your final comment that Plan deliberation was skipped."
fi

Skill(skill="issue-driven-dev:idd-implement", args="$IMPL_ARGS")
```

> **Why conditional, not unconditional `UNATTENDED MODE`** (Task 4.1, Requirement: "Attended interaction permits sub-skill questions"): when interaction = `attended`, idd-all MUST NOT inject the directive — the sub-skills' native attended-by-default behaviour is precisely what the HITL user wants. Concretely that is `idd-implement`'s mid-implementation `AskUserQuestion`, **plus the Plan-tier `EnterPlanMode` gate that lives in `/idd-plan`** (reached via Phase 3p; see the dispatch table above and the #292 correction note).
>
> **這句原本把 `EnterPlanMode` 算成 `idd-implement` 的原生行為** —— 那正是 #292 在本檔上方那則修正紀錄裡推翻掉的宣稱，而它以第二人稱的形式活在同一份檔案裡三輪。偵測器看不到它，因為 normative source 被整檔豁免掃描：「不掃這個檔」與「這個檔是對的」是兩件事，而豁免讓後者搭了前者的便車。現在 source 有自己的窄規則（見 `plan-routing-consistency` 的 self-contradiction 檢查）：它可以陳述任何 routing，就是不能把 `EnterPlanMode` 掛在 `idd-implement` 名下。

**`--cwd` flag is mandatory when forwarded from idd-all**: 確保 idd-implement 在跟 idd-all 同一個 local clone 跑(否則 sub-skill 跑在 session cwd,branch/commit 會 land 錯地方)。

**Branch behavior**:
- PR mode → idd-implement 看到 `--pr` flag + 已在 feature branch → reuse(Step 0.5 fork detection 直接認得)
- direct-commit mode → idd-implement 看到 `--no-pr` flag → 不再開 branch,直接在當前 branch commit

**PR creation timing**: PR mode 下,idd-implement 的 Step 5.5(PR creation)用 `gh pr list --head $BRANCH` 先查當前 branch 有沒有 open PR,有就 skip — 與 idd-all Phase 5 自然相容(idd-all 在 verify PASS 後才開 PR with verify result)。direct-commit mode 下 idd-implement 收到 `--no-pr` 不會嘗試開 PR,Phase 5 也直接 skip。

### Phase 3b: SDD Path — discuss → propose → apply (mode-aware chain)

idd-all 走 SDD path 時,**必須**串完三步:`spectra-discuss` → `spectra-propose` → `spectra-apply`(無論 mode — `spectra-propose` 本身有禁令 `NEVER invoke /spectra-apply`,所以 chain 由 idd-all 主導)。

**每步的 args 構造依 `INTERACTION` 軸條件化**(Task 4.2, Requirement: "Attended interaction permits sub-skill questions"):

> - `INTERACTION=unattended` → 每個 spectra-* args 都附加 **`UNATTENDED MODE` directive block**(下方範例的 attended-only 區段;sub-skill 看到直接抑制 `AskUserQuestion`)
> - `INTERACTION=attended` → **完全不傳** unattended hint。`spectra-discuss` 多輪節奏、`spectra-propose` Step 10 Park/Apply 問題、`spectra-apply` Step 4 continue-confirmation 都 native fire,user 在 keyboard 自然回應
>
> idd-all 不修改 spectra 任何檔案 — 全程用 args 傳指示(或不傳)override sub-skill 的 attended 預設。

#### Step 3b.0: Spectra presence hard gate（#211/#210）

```bash
command -v spectra >/dev/null 2>&1 || abort "Spectra tier routed but spectra CLI is missing.
   Install the Spectra plugin, then re-run /idd-all #$N — aborting BEFORE any
   spectra artifact is created (no half-baked openspec/changes/ residue)."
```

#### Step 3b.1: Capture issue context for prompt

```bash
ISSUE_TITLE=$(gh issue view "$N" --repo "$GITHUB_REPO" --json title -q .title)
ISSUE_BODY=$(gh issue view "$N" --repo "$GITHUB_REPO" --json body -q .body | head -50)
# Phase 2 已分頁抓過最新 Diagnosis；跨 Bash 區塊 shell 變數不保證存活,所以缺值時**用同一種分頁方式**重抓
# （不得改用 `--json comments` —— 那只回最舊 100 則）。
DIAGNOSIS="${LATEST_DIAGNOSIS:-}"
[ -n "$DIAGNOSIS" ] || DIAGNOSIS=$(gh api "repos/$GITHUB_REPO/issues/$N/comments" --paginate \
    --jq '[.[] | select(.author_association == "OWNER" or .author_association == "MEMBER" or .author_association == "COLLABORATOR") | {body}]' \
    | jq -s 'add // []' | python3 -c 'import json,sys,re; cs=json.load(sys.stdin); ds=[c for c in cs if re.search(r"(?m)^## Diagnosis", c["body"])]; print(ds[-1]["body"] if ds else "")')
```

#### Step 3b.2: Discuss

Build args conditionally — **inline comment cross-references "Attended interaction permits sub-skill questions" requirement**(Task 4.4):

```bash
DISCUSS_ARGS="Topic: ${ISSUE_TITLE} (#${N})

Context (from issue body + diagnosis):
${ISSUE_BODY}
${DIAGNOSIS}"

# Conditional: unattended only — see spec idd-pr-hitl-modes,
# requirement "Attended interaction permits sub-skill questions".
if [ "$INTERACTION" = "unattended" ]; then
  DISCUSS_ARGS="$DISCUSS_ARGS

UNATTENDED MODE — called by /idd-all orchestrator.

Discipline overrides for this invocation:
- Converge in ONE round. Do NOT use AskUserQuestion to pace the discussion across multiple turns.
- If you have a strong recommendation among 2-3 options, pick it and state your reasoning.
- If multiple viable approaches exist, choose the one with the smallest blast radius and document the trade-off.
- End your output with a single line: 'Conclusion: <chosen approach in one sentence>' so the orchestrator can pass it to spectra-propose.
- Do NOT pause to ask the user — there is no user available."
fi

Skill(skill="spectra-discuss", args="$DISCUSS_ARGS")
```

**Capture the conclusion** — extraction strategy depends on `$INTERACTION`:

```python
# Pseudocode — agent-level extraction logic
if INTERACTION == "unattended":
    # Unattended hint enforced 'Conclusion: <text>' format.
    conclusion = grep_last_match(spectra_discuss_output, r'^Conclusion:\s*(.+)$')
    if not conclusion:
        # Re-prompt once with the format requirement; if still missing, abort with branch preserved.
        # (See Failure handling table below.)
        retry_or_abort()
else:  # INTERACTION == "attended"
    # No format directive was injected (spec SHALL NOT inject). spectra-discuss may emit
    # a free-form multi-turn conclusion. Try in order:
    #   1. Last 'Conclusion:' line if user/sub-skill happened to write one
    #   2. Last paragraph of the final spectra-discuss message (heuristic — typical wrap-up)
    #   3. Otherwise: AskUserQuestion the user "請用一句話總結 spectra-discuss 達成的方向"
    #      Reason: in attended mode the user is in session, so a clarifying question is
    #      acceptable here (and ideal — the user is the one steering the discussion).
    conclusion = (
        grep_last_match(output, r'^Conclusion:\s*(.+)$')
        or last_paragraph(output)
        or ask_user("請用一句話總結 spectra-discuss 達成的方向,作為 spectra-propose 的 input。")
    )
```

> **Why fallback chain instead of just AskUserQuestion**: the heuristic-then-ask order avoids interrupting the user when they (or spectra-discuss itself) already wrapped up cleanly. AskUserQuestion is the safety net, not the default. This is consistent with the spec's "attended assumes user in session" — the cost of one clarifying question is much lower than passing an empty conclusion to spectra-propose.

#### Step 3b.3: Propose

```bash
PROPOSE_ARGS="<conclusion line from Step 3b.2>

Original issue: #${N} ${ISSUE_TITLE}"

# Conditional: unattended only — see spec idd-pr-hitl-modes,
# requirement "Attended interaction permits sub-skill questions".
if [ "$INTERACTION" = "unattended" ]; then
  PROPOSE_ARGS="$PROPOSE_ARGS

UNATTENDED MODE — called by /idd-all orchestrator.

Discipline overrides for this invocation:
- Skip ALL AskUserQuestion checkpoints. Make reasonable decisions and document them inline in the proposal/design artifacts.
- Step 10 'Park or Apply' question: SUPPRESS. Do NOT call spectra park. Do NOT call /spectra-apply (your guardrail at L267 still applies). Just end the workflow after artifact validation succeeds.
- If a 'plan file' check (Step 1.x) finds an existing plan, use it without asking.
- If context is insufficient, prefer making a documented assumption over asking — write the assumption explicitly in proposal.md so it can be challenged later.
- Output the final change-name on its own line as 'Change: <name>' so the orchestrator can pass it to spectra-apply."
fi
# Attended mode: spectra-propose's Step 10 Park/Apply prompt fires natively.
# If user picks Park, the chain stops here — idd-all reports the parked state and exits.

Skill(skill="spectra-propose", args="$PROPOSE_ARGS")
```

Capture the change-name line(unattended)or whatever spectra-propose prints last(attended).

#### Step 3b.4: Apply

```bash
APPLY_ARGS="<change-name from Step 3b.3>

Issue ref: #${N}"

# Conditional: unattended only — see spec idd-pr-hitl-modes,
# requirement "Attended interaction permits sub-skill questions".
if [ "$INTERACTION" = "unattended" ]; then
  APPLY_ARGS="$APPLY_ARGS

UNATTENDED MODE — called by /idd-all orchestrator.

Discipline overrides for this invocation:
- Skip Step 4 continue-confirmation. Proceed directly through implementation tasks.
- If validation reveals ambiguity that would normally trigger AskUserQuestion: document the assumption in tasks.md (mark with 'ASSUMPTION:'), proceed with the most conservative interpretation, and surface it in the verify phase.
- Every commit MUST reference (#${N}) — same convention as idd-implement.
- All commits land on the branch from Phase 0.5 ('${BRANCH}')."
fi
# Attended mode: APPLY_ARGS contains ONLY the change-name + issue ref.
# Per spec idd-pr-hitl-modes requirement "Attended interaction permits sub-skill questions":
# idd-all SHALL NOT inject any directive when interaction=attended. spectra-apply's
# native attended-by-default behavior (Step 4 continue-confirmation, AskUserQuestion
# on ambiguity) fires unmodified.

Skill(skill="spectra-apply", args="$APPLY_ARGS")
```

> **Branch context for spectra-apply (both modes)**: `BRANCH` is set in Phase 0.5 — PR mode → `idd/<N>-<slug>`, direct-commit mode → user's current checkout. spectra-apply doesn't need to be told this; it commits to whatever HEAD points at. The Phase 0.5 branch setup is the single source of truth.

#### Step 3b.5: 把 checklist 路徑交給 `idd-update`（#290）

SDD path **不經過 `idd-implement`**，所以不會產生 `## Implementation Complete > ### Checklist`
——也就是 `authoritative_source` 的第一層。若不做本步，該 issue 走到 `idd-close` 時沒有任何
authoritative source，會 fallback 去掃 diagnosis 當初寫的 pre-implementation checkbox，而
**那些 checkbox 在整個 SDD 流程裡沒有任何一步會勾**。

本步補上第二層（`## Current Status > ### Tasks`，producer 見
[`idd-update`](../idd-update/SKILL.md) 的 Step 4）：

```bash
# 路徑用「查」不用「組」——組路徑只是把佈局知識換個位置，對方改佈局會靜默失效。
# **在 $CWD 下執行**——registry 的選擇已知與 cwd 有關，不可用繼承來的工作目錄。
TASKS_FILE=$( cd "$CWD" && spectra instructions apply --change "$CHANGE_NAME" --json 2>/dev/null \
  | python3 -c 'import json,sys; print(json.load(sys.stdin).get("contextFiles",{}).get("tasks",""))' 2>/dev/null )

if [ -n "$TASKS_FILE" ]; then
  # 路徑加引號——含空白的合法路徑不加引號會被拆成多個參數，甚至被當成別的 flag。
  Skill(skill="issue-driven-dev:idd-update", args="#$N --cwd $CWD --tasks-file '$TASKS_FILE'")
else
  # 查詢失敗 / 工具未安裝 → 不附 flag，行為退回現行 fallback。**不 abort**。
  echo "note: 無法取得 checklist 路徑,#$N 的 close gate 將 fallback 掃 Strategy"
  Skill(skill="issue-driven-dev:idd-update", args="#$N --cwd $CWD")
fi
```

**為什麼由本 orchestrator 查而非 `idd-update` 自己查**：`idd-all` 的 SDD 分支**本來就**按名字
呼叫那三個 skill，已與該工具耦合；再多一次查詢不擴大耦合面。而 `idd-update` 是**通用** skill，
在完全不涉及該工具的路徑上也會被呼叫——讓它認得對方，才是把耦合擴散出去。

**`idd-update` 端另有 toplevel 圍籬**（見其 Step 4）：實測該工具的 registry 不一定 cwd-scoped，
回傳的路徑可能指向同一 repo 的另一個 worktree。本步不做該檢查——圍籬屬於**消費路徑的一方**，
放在 `idd-update` 才能同時保護手動呼叫。

#### Failure handling

| Situation | Action |
|---|---|
| `spectra-discuss` doesn't emit `Conclusion:` (unattended) | Re-prompt once with explicit format requirement; if still missing, abort with branch preserved |
| `spectra-discuss` doesn't emit `Conclusion:` (attended) | Fall back through last-paragraph heuristic → AskUserQuestion the user; never abort just for missing line |
| `spectra-propose` doesn't emit a `Change:` line | Same as above |
| `spectra-propose` hits a hard stop (e.g. spec validation fail it can't auto-fix) | Abort, preserve artifacts, instruct user to run `/spectra-propose` manually |
| `spectra-apply` reports tasks remaining unfinished | Continue to Phase 4 (verify) — verify will surface incompleteness |

> **Why idd-all overrides spectra defaults via args, not by modifying spectra**: spectra is a separate plugin with its own attended-by-default contract that's correct for solo use. idd-all is the one promising "unattended", so it's idd-all's responsibility to configure each sub-skill invocation to honor that promise. Args-based override keeps the boundary clean.

---

### Phase 4: Verify Loop

> **`TYPE=meeting` → 跳過 Phase 4**(#383):meeting 沒有 TDD verify(meeting-issue-type 規格;結案走 `idd-close` 的 meeting gate),不呼叫 `idd-verify`。meeting run 在 Phase 2 的 meeting 列就跳到 Phase 6,不會進到這裡。進到 Phase 4 代表 Phase 2 把它當 code work 分派、而且已經 implement;此時最新受信任 Diagnosis 若記 meeting,就是 Phase 2 之後 type 被改了(同一張 issue 另一個 run 重新 diagnose,或受信任成員貼了新的 Diagnosis)。這時**不能**當 meeting 跳過 verify——那會讓 implement 的 commit 未經驗證地留下,報告還寫「沒有 implement」(r5 #11)。所以呼叫 `idd-verify` 之前先跑下面的 guard:type 從最新受信任 Diagnosis 的 `### Type` 重新取得(Phase 2 的變數不跨 Bash 呼叫;也不看 issue 本文,r4 #35),讀到 meeting 就 abort,不 verify、不 push,照下方 abort 職責 `clear_unattended`。

```bash
# issue 號進 REST path 前先驗型（r5 #12）
case "$N" in ''|*[!0-9]*) echo "FATAL: Phase 4: issue number is not numeric: $N — verify not started" >&2; exit 1 ;; esac
. "${CLAUDE_PLUGIN_ROOT}/scripts/lib/actionability.sh" || { echo "FATAL: Phase 4: actionability helper missing — verify not started" >&2; exit 1; }
# 只有「確定讀到 meeting」才中止。讀不到 type（GITHUB_REPO 遺失、fetch 失敗、comment 清單不是 JSON）時，
# 照 Phase 2 選的 code 路線進 verify——那本來就是這種 run 的安全預設，而 verify 自己也要打同一組 API（r6 #2、#14）。
# 錯誤處理掛在會失敗的 jq 那一步，不掛在恆 exit 0 的 helper 上（r6 #12）
P4_TYPE=unknown
if [ -z "${GITHUB_REPO:-}" ]; then
  echo "⚠ Phase 4: GITHUB_REPO is empty (shell state lost) — cannot re-read the Diagnosis type of #$N; continuing into verify on the route Phase 2 chose"
elif ! P4_PAGES=$(gh api "repos/$GITHUB_REPO/issues/$N/comments" --paginate --jq '[.[] | select(.author_association == "OWNER" or .author_association == "MEMBER" or .author_association == "COLLABORATOR") | .body | select(split("\n") | any(startswith("## Diagnosis")))]'); then
  echo "⚠ Phase 4: comment fetch failed — cannot re-read the Diagnosis type of #$N; continuing into verify on the route Phase 2 chose"
elif ! P4_LATEST=$(jq -s -r 'add // [] | last // ""' <<<"$P4_PAGES"); then
  echo "⚠ Phase 4: the comment list of #$N is not readable — cannot re-read the Diagnosis type; continuing into verify on the route Phase 2 chose"
else
  P4_TYPE=$(idd_diagnosis_type "$P4_LATEST")
fi
if [ "$P4_TYPE" = meeting ]; then
  echo "FATAL: Phase 4: the latest trusted Diagnosis of #$N now records meeting, but Phase 2 routed this run as code work — not verifying, not pushing. Any commits this run made stay where they are (check git log); if it made none — for example /idd-plan wrote a Meeting Plan — run the meeting unwind. Re-run /idd-diagnose #$N, then decide by hand (r5 #11)" >&2
  exit 1
fi
```

Args 構造同樣依 `INTERACTION` 軸條件化(Task 4.3, Requirement: "Attended interaction permits sub-skill questions"):

```bash
# Build idd-verify args conditionally — see spec idd-pr-hitl-modes,
# requirement "Attended interaction permits sub-skill questions".
# #392: a run that can reach the close stage pins verify's input to the whole branch
# (origin/<default>...<branch>), so the range it reviews is the range that gets merged or pushed.
# --in-chain and --review runs never merge: they keep the earlier auto-detected range, so a chain
# sub-run does not review the root's and the other spawns' commits on the cluster branch (r3 #4).
RUN_STATE="$CWD/.claude/.idd/state/idd-all-run-$N.json"
if [ "$(jq -r 'if (.review or .in_chain) then "no" else "yes" end' "$RUN_STATE" 2>/dev/null)" = yes ]; then
  VERIFY_ARGS="#$N --cwd $CWD --branch $(git -C "$CWD" branch --show-current)"
else
  VERIFY_ARGS="#$N --cwd $CWD"
fi
if [ "$INTERACTION" = "unattended" ]; then
  VERIFY_ARGS="$VERIFY_ARGS

UNATTENDED MODE — called by /idd-all orchestrator. Do not pause for AskUserQuestion; emit findings to the verify comment as usual."
fi
```

每一輪 verify 之後，用 verify gate 判定這一輪（#392）：`close-stage.py gate` 找 issue 上**由執行這個 session 的帳號**在這次 run 開始之後貼出的最新一則 verify comment，它必須是 `## Verify: #N` 報告（PR mode 的報告或 `## Verify (via PR #P)` 指標不算），再把 GitHub 渲染這則 comment 得到的 HTML 交給 `verify-gate.py --expect-sha <目前的 HEAD>`。判斷由 helper 做，不由模型讀報告自己判：這是唯一會讓程式碼不經人手進預設 branch 的判斷，必須可重現、讀不出來就當成不乾淨。gate 讀渲染後的 HTML，所以報告裡 GitHub 畫成表格的東西，gate 都看得到（verify r4 #11、#12、#14、#21）。

報告要寫出它審查的範圍（``**Reviewed**: `<base>..<head>` ``，idd-verify Step 4 的樣板）。會走到 close stage 的 run，gate 要求 head 就是目前的 HEAD、base 就是它與 `origin/<default>` 的 merge-base——也就是之後會被 merge 或 push 的整段——所以「這一輪沒貼出報告、issue 上留著舊的乾淨報告」與「報告貼出後 branch 又多了 commit」都會讀成 `unparseable`，不靠記住上一份報告的 id。`--review` 與 `--in-chain` 的 run 不 merge，verify 範圍也不釘在整條 branch 上，gate 只比對 head（verify r4 #44）。只認這個帳號貼的報告：別人在 run 開始之後留的 comment（包括同事貼的 FAIL）由 Phase 5c 的 helper 直接停下，不在這裡比較誰的報告比較新。

```bash
case "$N" in ''|*[!0-9]*) echo "FATAL: Phase 4: issue number is not numeric: $N" >&2; exit 1 ;; esac
DEFAULT_BRANCH=$(gh repo view "$GITHUB_REPO" --json defaultBranchRef -q .defaultBranchRef.name)
git -C "$CWD" fetch -q origin "$DEFAULT_BRANCH"
HEAD_SHA=$(git -C "$CWD" rev-parse HEAD)
BASE_SHA=$(git -C "$CWD" merge-base "origin/$DEFAULT_BRANCH" "$HEAD_SHA")
# --review / --in-chain runs never merge and verify does not pin their range: compare the head only (r4 #44)
GATE_BASE=(--base "$BASE_SHA")
[ "$(jq -r 'if (.review or .in_chain) then "no" else "yes" end' "$CWD/.claude/.idd/state/idd-all-run-$N.json" 2>/dev/null)" = yes ] || GATE_BASE=()
GATE_JSON=$(python3 "${CLAUDE_PLUGIN_ROOT}/scripts/close-stage.py" gate --cwd "$CWD" --repo "$GITHUB_REPO" --issue "$N" --sha "$HEAD_SHA" "${GATE_BASE[@]}")
echo "→ verify gate (round $ROUND, head $HEAD_SHA${GATE_BASE:+, range from $BASE_SHA}): $GATE_JSON"
```

```python
MAX_ROUND = 2 if INTERACTION == "unattended" else 1   # verify rounds; at most one fix pass between them
# In-scope fix findings are fixed and re-verified only when this run can reach the close stage.
# --review and --in-chain runs never merge, so they keep the earlier scope: fix Blocking only.
FIX_IN_SCOPE = not REVIEW_FLAG and not IN_CHAIN      # read the run-state file if the shell lost them
STOP_REASON = None
for ROUND in 1..MAX_ROUND:
    Skill(skill="issue-driven-dev:idd-verify", args=VERIFY_ARGS)
    gate = verify_gate()                     # the bash block above → GATE_JSON

    if gate.status == "clean" or (gate.status == "not_clean" and gate.blocking == 0 and not FIX_IN_SCOPE):
        if gate.status == "clean" and gate.low_in_scope > 0:
            # LOW / INFO / P3 In-scope fix rows do not hold the merge (decision of 2026-11-10). Do NOT change the
            # branch for them: the commit that merges is the commit this round reviewed. File them together.
            file_one_follow_up_issue(report_rows(action="In-scope fix", severity=("LOW", "INFO", "P3")))
        break                                # → Phase 5; Phase 5c runs only for a clean gate

    if gate.status == "unparseable":
        # The gate decides the MERGE, not the fix loop. It could not read this report (a format
        # slip, gh api user refused on a CI token, ...), so the close stage will not run — but
        # Blocking findings are still handled as before #392: read the report yourself.
        STOP_REASON = f"verify gate: unparseable — {gate.reason}"
        if not model_reads_report_has_blocking():
            break                            # Phase 5 opens the PR with a "not clean" body; Phase 5c does not run
        if INTERACTION == "attended":
            report_findings_and_exit_to_user(); break
        if ROUND == MAX_ROUND:
            abort_with_message("verify still has Blocking findings after the last round; manual intervention needed")
        attempt_auto_fix(report_rows(action="Blocking")); continue

    # not_clean
    if INTERACTION == "attended":
        # User is in session — surface findings and let them decide whether to keep iterating.
        # Do NOT auto-fix in attended mode; that defeats the purpose of HITL.
        report_findings_and_exit_to_user()
        STOP_REASON = "verify gate: not_clean — findings handed back to the user"
        break

    if ROUND == MAX_ROUND:
        if gate.blocking > 0:
            abort_with_message(f"verify still has Blocking findings after {MAX_ROUND} rounds; manual intervention needed")
            # the abort report carries one line: Stopped: verify still has Blocking findings after round N (report URL)
        STOP_REASON = f"verify gate: not_clean after {MAX_ROUND} rounds — {gate.in_scope} In-scope fix finding(s) remain"
        break                                # 0 Blocking: Phase 5 still opens the PR (its body says so); Phase 5c does not run

    # unattended: fix the rows of the verify report whose Action is Blocking
    # (and In-scope fix when FIX_IN_SCOPE), then run the next round
    attempt_auto_fix(report_rows(action="Blocking") + (report_rows(action="In-scope fix") if FIX_IN_SCOPE else []))
```

**`MAX_ROUND`**：unattended 2 輪 verify（中間最多修一次）；attended 1 輪（讀出結果、交回使用者）。attended 的使用者在同一個 session 裡處理完 findings、說要繼續時，再跑一輪 verify（不限輪數，不自動修），乾淨了就照常進 Phase 5 與 Phase 5c；這是 attended 走到「某一輪乾淨才 merge 並 close」的路徑（spectra-discuss 結論 2，verify r3 #8）。`STOP_REASON` 不跨 Bash 呼叫存活：Phase 5 與 Phase 6 需要它時，重跑上面的 gate 區塊得到同一個結果（gate 只讀 GitHub 與 HEAD，結果可重現）。

**Auto-fix 策略**(unattended only — best-effort):

對每個要修的 finding（verify 報告 Findings 表裡 Action 為 Blocking，`FIX_IN_SCOPE` 時加上 In-scope fix 的列），讀其描述 + suggested action，套用 Edit/Write 修正：

- 文法/拼字/字串 typo → 安全可修
- 邏輯錯誤(null check, edge case) → 嘗試但 risky
- 安全漏洞 → **不 auto-fix**,直接 abort 讓 user 處理

每個 auto-fix commit:`fix: address verify finding — {finding summary} (#$N)`

**乾淨的定義（#392，2026-11-10 的決定）**：gate 判 `clean` ＝ 報告判定 PASS、Blocking 為 0、In-scope fix 只剩 LOW／INFO／P3。這些沒擋住 merge 的列數在 gate JSON 的 `low_in_scope`。大於 0 時：

- **不為它們改 branch**。合併的 commit 必須是這一輪審過的 commit；在乾淨的一輪之後再加修正，那些修正就沒有人審過。
- 把它們**合成一張** follow-up issue（`Skill(skill="issue-driven-dev:idd-issue", …)`，標題寫明來自哪張 issue 的 verify，正文逐列引用報告），不是一列一張。issue 號記下來，Phase 6 的回報要列。
- 接著照常進 Phase 4.5、Phase 5 與 Phase 5c。

> **與 `idd-verify` Step 5a 的差異（#392）**：手動流程裡 In-scope fix 修完**不必**重跑 verify。idd-all 的自動 merge 路徑**要**重跑：自動修的程式碼若沒被 verify 看過就自動進預設 branch，等於沒有人審過。手動流程不變。

**Follow-up findings**(設計決策 #4:auto-create issues):

每個 P3/follow-up finding → 呼叫 `Skill(skill="issue-driven-dev:idd-issue", args="<title> --target $GITHUB_REPO")` 建新 issue(用 `--target` 而非 `--cwd`,因為 idd-issue read-only),body 引用本次 verify report 原文。新 issue target main(不是當前 branch)。

---

### Phase 4.5: CI gate（#465）

`TYPE=meeting` 跳過。其餘在 verify 之後、push 或收尾之前，對目前的 commit 跑閘門。契約見 spec `local-ci-gate` 與 [`references/config-protocol.md`](../../references/config-protocol.md) 的 `ci` 欄位。

```bash
# 隱私等級照 rules/privacy-scrubbing.md 解析（第三方 enforce、自己的 public warn、private light）；解析不到就用最嚴的
case "$(gh repo view "$GITHUB_REPO" --json viewerPermission,isPrivate --jq '"\(.viewerPermission)/\(.isPrivate)"' 2>/dev/null)" in
  ADMIN/true|MAINTAIN/true|WRITE/true) SCRUB_LEVEL=light ;;
  ADMIN/false|MAINTAIN/false|WRITE/false) SCRUB_LEVEL=warn ;;
  *) SCRUB_LEVEL=enforce ;;
esac
GATE_OUT=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/idd-ci-gate.sh" run --commit "$(git -C "$CWD" rev-parse HEAD)" --cwd "$CWD"); GATE_RC=$?
printf '%s\n' "$GATE_OUT"
GATE_RECORD=$(printf '%s\n' "$GATE_OUT" | sed -n 's/^RECORD=//p')
# 紀錄預設不含指令與輸出；開了 ci.post_output_tail 時輸出末段只換掉路徑與控制字元，不保證其他內容安全，隱私自審照 rules/privacy-scrubbing.md
[ -n "$GATE_RECORD" ] && bash "${CLAUDE_PLUGIN_ROOT}/scripts/gh-egress.sh" comment "$N" --repo "$GITHUB_REPO" --body-file "$GATE_RECORD" --scrub-attested "$SCRUB_LEVEL"
```

紀錄送不出去不改變閘門結果，但要在 Phase 6 回報。Phase 5c 的 helper 會對同一個 commit 再跑一次這個閘門（#392）：這裡擋的是 push 與開 PR，那裡擋的是 merge 或 push 到預設 branch，而擋 merge 的檢查必須跟 merge 在同一個 process。依結束碼（封閉列舉）：

| 結束碼 | 動作 |
|---|---|
| 0 pass | 繼續 Phase 5 |
| 10 remote | 不跑本機指令；繼續 Phase 5，由遠端 CI 決定 |
| 3 not-configured | attended：用 AskUserQuestion 問指令。可列 repo 裡找到的候選（如 `scripts/ci.sh`），**不執行它們**，並說明這類指令會以使用者的環境執行 repo 每個 commit 裡的內容，只適合信任的 repo；確認後才寫入 `ci.command`，再跑一次。unattended：不寫 config，跳到 Phase 6，列入 Action items，寫明怎麼設定 `ci.command` 或 `ci.mode` |
| 1 fail、2 timeout、4 error | 不 push、不開 PR，跳到 Phase 6 回報結果與 `LOG=` 路徑 |

### Phase 5: Push + Open PR (PR mode only)

> **`TYPE=meeting` → 跳過 push 與 PR**(#383):meeting 沒有 code branch 可推,不論 PR 或 direct-commit mode 都不 push、不開 PR。meeting run 在 Phase 2 就跳到 Phase 6,不會進到這裡;進到這裡才讀到 meeting,代表 Phase 2 之後 type 被改了,下方 guard fail-closed:不 push、不開 PR、abort(r5 #11)。

**Conditional push + PR creation** (#3 Task 3.2 — replaces earlier `goto Phase 6` pseudocode that wasn't valid bash; structural conditional with explicit comment instead):

```bash
if [ -n "$IN_CHAIN" ]; then
  echo "→ chain context (--in-chain): skipping push + PR (cluster PR opened later by /idd-all-chain Phase 3)"
  # v2.55+ #44 — no per-issue PR; cluster PR is opened by /idd-all-chain after chain queue completes.
elif [ "$PATH_AXIS" = "direct-commit" ]; then
  echo "→ direct-commit path: skipping PR (a push, if any, happens in Phase 5c after a clean verify)"
  # No-op — fall through to Phase 5c below.
elif [ "$PATH_AXIS" = "PR" ]; then
  # #383 verify r2: meeting 不 push、不開 PR。guard 與 push 在同一個 shell、同一個分支裡 ——
  # 放在另一個 fence 時,它的 exit 0 擋不住下一個 fence 的 push(r2 #12);放在分支外時,
  # 不 push 的 direct-commit / in-chain 也會多一個網路失敗點(r2 #5)。type 只信最新受信任 Diagnosis 的
  # ### Type —— issue 作者在 implement 之後把本文改成 meeting,不能讓這裡跳過 push(r4 #35)。
  case "$N" in ''|*[!0-9]*) echo "FATAL: Phase 5: issue number is not numeric: $N — not pushing" >&2; exit 1 ;; esac   # r5 #12
  . "${CLAUDE_PLUGIN_ROOT}/scripts/lib/actionability.sh" || { echo "FATAL: Phase 5: actionability helper missing — not pushing" >&2; exit 1; }
  # 遺失的 shell 狀態不是暫時性的 fetch 失敗，分開講（r6 #14）；push 之前讀不到 type 一律 fail-closed（r2）
  [ -n "${GITHUB_REPO:-}" ] || { echo "FATAL: Phase 5: GITHUB_REPO is empty (shell state lost) — not pushing" >&2; exit 1; }
  P5_PAGES=$(gh api "repos/$GITHUB_REPO/issues/$N/comments" --paginate --jq '[.[] | select(.author_association == "OWNER" or .author_association == "MEMBER" or .author_association == "COLLABORATOR") | .body | select(split("\n") | any(startswith("## Diagnosis")))]') \
    || { echo "FATAL: Phase 5: comment fetch failed — not pushing" >&2; exit 1; }
  # 錯誤處理掛在會失敗的 jq 那一步；helper 拿到一個參數恆 exit 0（r6 #12）
  P5_LATEST=$(jq -s -r 'add // [] | last // ""' <<<"$P5_PAGES") || { echo "FATAL: Phase 5: the comment list is not readable — not pushing" >&2; exit 1; }
  P5_TYPE=$(idd_diagnosis_type "$P5_LATEST")
  # meeting run 不會到這裡（Phase 2 → Phase 6）；到這裡才讀到 meeting = Phase 2 之後 type 被改了：fail-closed（r5 #11）
  if [ "$P5_TYPE" = meeting ]; then echo "FATAL: Phase 5: the latest trusted Diagnosis of #$N now records meeting, but Phase 2 routed this run as code work — not pushing, no PR; any commits this run made stay on $BRANCH (check git log). Re-run /idd-diagnose #$N, then decide by hand (r5 #11)" >&2; exit 1; fi
  # PR mode (v2.40.0 behaviour below; #383 adds the type guard above, which fails closed before the push — r4 #20)
  # WARNING (#7): heredoc below is NOT quoted — variable expansion happens.
  # Do NOT insert untrusted strings (e.g. issue titles) into the body without
  # sanitization. Current placeholders {...} are markdown-style note text, not
  # ${...} shell expansions, so safe today; future maintainers must keep it that way.
  git -C "$CWD" push -u origin "$BRANCH" || abort "Phase 5: git push failed — no PR opened; the commits stay on the local branch $BRANCH"

  # The PR body states what the verify gate actually says (#392 verify r1 #20, #29): a run that
  # stops at verified must not open a PR that claims PASS and promises a merge.
  # Only the gate's status goes into the body, never its reason: the reason quotes report text,
  # which could carry a close keyword next to an issue number (#392 verify r2 #35).
  DEFAULT_BRANCH=$(gh repo view "$GITHUB_REPO" --json defaultBranchRef -q .defaultBranchRef.name)
  HEAD_SHA=$(git -C "$CWD" rev-parse HEAD)
  BASE_SHA=$(git -C "$CWD" merge-base "origin/$DEFAULT_BRANCH" "$HEAD_SHA")
  RUN_REVIEW=$(jq -r 'if .review then "yes" else "no" end' "$CWD/.claude/.idd/state/idd-all-run-$N.json" 2>/dev/null || echo unknown)
  GATE_BASE=(--base "$BASE_SHA"); [ "$RUN_REVIEW" = no ] || GATE_BASE=()   # --review: verify's range is not pinned (r4 #44)
  GATE_OUT=$(python3 "${CLAUDE_PLUGIN_ROOT}/scripts/close-stage.py" gate --cwd "$CWD" --repo "$GITHUB_REPO" --issue "$N" --sha "$HEAD_SHA" "${GATE_BASE[@]}")
  VERIFY_STATE=$(printf '%s' "$GATE_OUT" | jq -r '.status // "unparseable"')
  # A Rejected finding is a disagreement no person has settled: the close stage stops on it, so the body must not promise a merge
  [ "$VERIFY_STATE" = clean ] && [ "$(printf '%s' "$GATE_OUT" | jq -r '.rejected // 0')" != 0 ] && VERIFY_STATE="clean, with Rejected findings"
  if [ "$VERIFY_STATE" != clean ]; then
    VERIFY_BOX="[ ]"; VERIFY_LINE="Verify gate: ${VERIFY_STATE} (see the latest verify report on issue #${N}). /idd-all will not merge this PR; a person decides."
  elif [ "$RUN_REVIEW" != no ]; then   # --review, or the run state cannot be read: a person merges
    VERIFY_BOX="[x]"; VERIFY_LINE="Verify gate clean — ready to merge → after merge, run /idd-close to finalize this issue (this run carries --review: no automatic merge)."
  else
    VERIFY_BOX="[x]"; VERIFY_LINE="Verify gate clean — see the verify report on issue #${N}. /idd-all merges this PR next if CI and the close-stage guardrails pass."
  fi

  PR_BODY=$(cat <<EOF
Refs #${N}

## Summary
{從 issue title + diagnosis 的 Strategy 摘要}

## Verification
${VERIFY_LINE}

## Checklist
- [x] Diagnose ✓
- [x] Implement(${COMMIT_COUNT} commits)
- ${VERIFY_BOX} Verify — ${VERIFY_STATE}
- [x] No auto-close trailer: /idd-close runs after the merge (idd-all's close stage, or by hand)

## Related
{若有 follow-up issues,列出 #N #M ...}

---
🤖 Generated by /idd-all. **Do NOT add a GitHub close trailer** (Closes/Fixes/Resolves) — IDD discipline requires /idd-close (run by /idd-all's close stage, or by hand) to enforce the checklist gate + closing summary.
EOF
)

  # 標題在這個 block 裡設定（shell 狀態不跨 tool call）：issue 的標題，結尾加 (#N)；不放 close 關鍵字、不 @ 人。
  PR_TITLE="{issue 的標題} (#${N})"
  # 〈權限〉：開 PR、或更新這次 run 已經開的 PR 之前，都先由程式判定它算不算可逆
  # （會不會通知到人、會不會在合併時關掉 issue）。隱私自審是模型的事，在這之前做完。
  PRC_DIR=$(mktemp -d) || abort "mktemp failed — not opening the PR"
  printf '%s' "$PR_TITLE" > "$PRC_DIR/title"; printf '%s' "$PR_BODY" > "$PRC_DIR/body"
  PRC=$(python3 "${CLAUDE_PLUGIN_ROOT}/scripts/close-stage.py" pr-check --cwd "$CWD" --default "$DEFAULT_BRANCH" \
      --title-file "$PRC_DIR/title" --body-file "$PRC_DIR/body"); PRC_RC=$?
  rm -f "$PRC_DIR/title" "$PRC_DIR/body"; rmdir "$PRC_DIR"
  # A resumed run (Step 0.5.1 → resume) already has this branch's PR open: reuse it and refresh
  # its body instead of failing on "a pull request already exists" (#392 verify r2 #23).
  ME=$(gh api user --jq .login)
  PR_URL=$(gh pr list -R "$GITHUB_REPO" --head "$BRANCH" --state open --json url,isCrossRepository,author \
      -q "[.[] | select(.isCrossRepository == false and .author.login == \"$ME\")] | .[0].url // empty")
  if [ "$PRC_RC" -ne 0 ]; then
    # exit 3 = ask（原因在 JSON）；其他 = 用法錯誤。兩種都不開 PR，也不改已經開著的 PR（verify r8 #2）。
    echo "→ PR not opened or changed — pr-check: $(printf '%s' "$PRC" | jq -r '.reason // empty' 2>/dev/null || true) (exit $PRC_RC)${PR_URL:+; the open PR $PR_URL keeps its current text}"
    echo "   Put this reason in the Phase 6 report (Stopped:). Phase 5c will stop too: without a PR it finds none; with the old PR its text was not refreshed."
  elif [ -n "$PR_URL" ]; then
    gh pr edit "$PR_URL" -R "$GITHUB_REPO" --body "$PR_BODY" >/dev/null || echo "⚠ could not refresh the body of $PR_URL"
    echo "→ reusing $PR_URL (body refreshed)"
  else
    PR_URL=$(gh pr create -R "$GITHUB_REPO" --title "$PR_TITLE" --body "$PR_BODY" \
        --base "$DEFAULT_BRANCH" --head "$BRANCH") || abort "gh pr create failed — branch $BRANCH is pushed; open the PR by hand"
    echo "→ opened $PR_URL"
    echo "Undo: gh pr close ${PR_URL##*/} -R $GITHUB_REPO"
  fi
  fi   # Phase 5c finds the PR itself (close-stage.py run), it does not take this URL
fi
# Every path falls through to Phase 5c below.
```

> **絕對不能在 PR body 用 Closes/Fixes/Resolves trailer**。User-facing canonical 紀律見 [`rules/commit-issue-reference.md`](../../rules/commit-issue-reference.md)（#214）；理由見 idd-implement skill 裡的 trailer 禁令說明 — auto-close 會繞過 idd-close 的 checklist gate 和 closing summary。

---

### Phase 5c: Close stage — merge（或 push）並 `/idd-close`（#392）

verify 乾淨就收尾：PR mode squash-merge PR，direct-commit mode 在預設 branch 上 push，然後以 `ORCHESTRATED BY /idd-all` 指示呼叫 `/idd-close`。**不先問人**：merge 可以 revert、close 可以 reopen，依 Foresay 屬於 traceable 分支——做完必須在 Phase 6 回報實際做了什麼、怎麼復原（MANIFESTO〈auto-merge 的合法性與限制〉）。`/idd-all` 這個呼叫本身就是要它做完的請求；想先看過再 merge 的人帶 `--review`。

**所有檢查與 merge／push 都在 `scripts/close-stage.py run` 這一個 process 裡**。檢查不能放在 skill 的 bash 區塊：每個區塊是一次獨立的 tool call，一個區塊判了 `Stopped` 再 `exit 0`，擋不住下一個區塊的 `gh pr merge`（#383 r2 #12，#392 verify r1 #9）；shell 變數也不跨呼叫存活。helper 需要的值從 Step 0.7 寫下的 run-state 檔與 GitHub 讀，不從模型的記憶讀。

**不 merge、不 close 的情況**——封閉列舉，只有這九種，不得依性質相似類推：

| 情況 | 誰擋 | 結果 |
|---|---|---|
| 帶 `--review` | helper（讀 run-state） | `Stopped: --review …`；Phase 6 用「awaiting human acceptance」措辭 |
| `--in-chain` | helper（讀 run-state） | cluster PR 由 `/idd-all-chain` 處理 |
| Step 0.6 把 PR mode 降成 direct-commit（沒裝 ralph-loop） | helper（run-state 的 requested path 與 path 不同） | 停在 verified：使用者要的是 PR review，不是直接推上預設 branch |
| `type=meeting` | helper（重讀最新受信任 Diagnosis） | meeting 不 merge、不 push；正常不會到這裡（Phase 2 直接到 Phase 6） |
| issue 的作者或最後編輯正文的人沒有寫入權限 | helper | 停在 verified：issue 正文是 implement 照著做、verify 照著驗的規格，沒有人 merge 時它必須出自本來就能推這個改動的人 |
| 意圖沒有確認過，封閉列舉，只有這四種：(1) 有 comment 出自沒有寫入權限的人（bot 除外）；(2) issue 正文有還沒回答的釐清問題：任何一張表的 `Status` 欄以 `surfaced` 或 `deferred` 開頭的列，不論它在哪個標題下、是否收在 `<details>` 或引用裡，GitHub 沒畫成表格的那種列也算；(3) Phase 2 據以分派的那則 Diagnosis（最新一則有 `## Diagnosis` 行的受信任 comment）讀不出 tier；(4) 任何一則 comment 有 Layer V 延後或 choice-first 預設的紀錄（GitHub 顯示的 `- **Reason**:` 行），而之後沒有 Decision comment 回應它。**不在此列**（2026-11-10 的決定，#392 comment 6761657951、6761899504）：tier 是哪一個（unattended run 做了 Plan、Spectra 或 SDD-warranted 的 issue 照樣 merge）；沒有人處理的 Proposed Corrections（不擋，數量在結果的 `proposed_corrections`，回報裡寫明沒有套用） | helper | 停在 verified、PR 照開。Foresay 的 traceable 分支要求意圖清楚**且**可逆；unattended run 會自己略過意圖確認，comment 與附件也會帶進實作（#392 決定，comment 6566557673、6567272352）。unattended diagnose 自己做的 Stage 1 策略確認算是一次注意、不算略過（comment 6568180861：「ai的attention也算attention，只是人類的更稀少」） |
| 這次 run 開始之後有別人插手：不是這個帳號、也不是 bot 的人在 issue 上留言或改了 comment、改了 issue 正文、加或拿掉 label、改標題、關掉或重開 issue，或刪了任何不是這個帳號的 comment；issue 已經不是 OPEN；PR 不是這個帳號開的、是 draft、changes requested，或有別人的 comment、review、label、標題或描述修改；這些紀錄多到一次讀不完 | helper | 停在 verified。run 開始時讀過的 issue 才是它照著做的意圖，之後進來的話它沒讀過（verify r4 #4、#15、#48；r5 #2、#6、#16、#33）。同事貼的 verify FAIL 也在這一列 |
| Phase 4 留下 `STOP_REASON` | helper 的 guardrail 1 再判一次 gate | `Stopped: guardrail 1 (verify gate) …` |
| Phase 4 或 Phase 5 已 abort | — | 照 abort 職責處理（見 Failure Modes） |

即使模型漏看上表直接呼叫 helper，前八種也會被 helper 自己擋下。

#### 5c.1 跑 helper

```bash
case "$N" in ''|*[!0-9]*) echo "FATAL: Phase 5c: issue number is not numeric: $N — not merging" >&2; exit 1 ;; esac
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/close-stage.py" run --cwd "$CWD" --repo "$GITHUB_REPO" --issue "$N"
echo "close-stage exit: $?"
```

CI 等待最多 15 分鐘，超過 Bash 工具單次的時間上限：**用 `run_in_background` 執行這個區塊，等它完成的通知**，不要拆成好幾次呼叫（拆開就回到上面說的 fence 問題）。環境不允許背景執行時（例如背景工作被停用），改帶 `--ci-timeout 420` 在前景跑，並把 Bash 工具的 timeout 設成 600000 ms（helper 還要加上寬限期與 merge 的時間）；遠端的 check 在 7 分鐘內沒跑完就停在 verified。`--ci-timeout` 只管等遠端 check 的時間：本機 CI 閘門有自己的時限（`ci.timeout_seconds`，預設一小時），本機 CI 會跑超過 Bash 工具上限的 repo 只能用背景執行。結果也寫在 `$CWD/.claude/.idd/state/idd-all-result-$N.json`（每次 run 開始時先刪掉舊的；helper 出錯也一律寫 `"status": "stopped"`，不會留下上一次的結果）。呼叫 `gh pr merge` 或 `git push` 之前，helper 先寫一份「可能已 merge／已 push」的結果，做完再改寫：process 在兩者之間被中斷時，結果檔仍說得出可能已經發生了什麼（verify r4 #34）。

helper 依序檢查，第一道不過就停，印一行 JSON（`"status": "stopped"`、`"reason"` 寫出是哪一道與原因），exit 3：

| 道 | 檢查 | 過的條件 |
|---|---|---|
| 0 | run 本身 | run-state 存在、是這個 repo 與 issue、不超過 24 小時；沒有 `--review`／`--in-chain`；沒有被降級；這個帳號對 repo 有 WRITE 以上的權限；clone 的 `origin` 的每個 fetch 與 push URL 都是 `github.com/<repo>`；最新受信任 Diagnosis 不是 meeting；issue 的作者與最後編輯者都有寫入權限；沒有別人插手、意圖確認過（上表「別人插手」與「意圖」兩列） |
| 發佈 | 預設 branch 最新的 workflow | 沒有任何 workflow 在 push 到預設 branch（或 `workflow_run`）時發佈或部署（`gh release`、`npm publish`、`docker push`、`deploy-pages`、名稱帶 publish 或 deploy 的 action 之類，含它呼叫的本地 reusable workflow、composite action 與 `run:` 呼叫的本機 script）；呼叫別的 repo 的 reusable workflow 一律當成會發佈；只由 tag 觸發的不算。trigger 讀不懂（加引號的鍵、list 寫法以外的形式、否定或方括號的 branch pattern）就當成會在 push 時跑（`scripts/lib/workflows.py`，r5 #1）。有的話，merge 或 push 本身就是發版，停下要人帶 `--review`。這次改動動到 `.github/workflows` 或 `.github/actions` 也停下：改 CI 的改動由人 merge |
| 1 | verify gate | 這次 run 開始之後、這個帳號貼的最新 verify comment 是 `## Verify: #N` 報告，貼出後沒有被編輯、沒有被藏起來，它的渲染結果經 `verify-gate.py --expect-sha --expect-base` 判定 `clean`（含完整的覆蓋率行），`**Reviewed**` 的範圍正好是要 merge（`merge-base(origin/<default>, PR head)..PR head`）或要 push（`origin/<default>..HEAD`）的那一段；報告裡沒有 `Rejected` 的 finding（被 run 自己判為不成立的意見，r4 #7）、沒有 Severity 是 CRITICAL／HIGH／P0／P1 的 Follow-up（嚴重的意見被歸為範圍外，r5 #4）、verify 沒有降級跑（報告任何地方都沒有 `Process Gaps` 字樣，reviewers 行是 `R / T` 且 R 等於 T；r5 #22、r7 #11、#14）。In-scope fix 只剩 LOW／INFO／P3 仍算 `clean`（`low_in_scope`） |
| 2 | CI | helper 在同一個 process 裡跑本機 CI 閘門 `idd-ci-gate.sh run --commit <verified sha>`（capability `local-ci-gate`，#465），照結束碼：**0**（pass）就過，PR 的遠端 check 在 merge 前讀一次、不等待，失敗或取消的列在結果的 `remote_ci_failed`、還在跑的列在 `remote_ci_pending`，都不擋 merge；**10**（`ci.mode` 是 `remote`）才照遠端 check 判定：`gh pr checks` 的每一項都是 `pass` 或 `skipping`，`pending` 時等待、總共最多 15 分鐘，`fail`、`cancel` 即停，repo 有一個對每個 `pull_request` 都會跑的 workflow（沒有 path 篩選）時要等到至少一個 `pull_request` 事件的 check 出現，check 的集合連續 90 秒沒有變化才接受；**其他結束碼**（1 fail、2 timeout、3 沒設定指令、4 error，或清單外的值）即停。direct-commit 推送前也跑這一道，10 時沒有遠端結果可看（commit 還沒推），照舊直接推 |
| 3 | auto-close trap 與 commit 歸屬（PR） | 同 `idd-verify` Step 0.8 的兩個 source（idd-all 以 branch 模式呼叫 verify，Step 0.8 沒有跑）：PR body 沒有 closing reference；每個 commit（從本機 git 讀完整範圍，`gh pr view --json commits` 有筆數上限）的 subject 與 body 沒有 close 類關鍵字接在 `#N`、`owner/repo#N` 或 issue／PR 網址前，而且都引用 `#N`（不是這次 run 的 commit 不 squash 進預設 branch，r5 #23）。連字號不豁免：GitHub 會把 `/idd-close #N` 拆開並關掉 issue（#173） |
| 4 | squash message（PR） | subject（PR 標題加 `(#PR)`）與 body（`Refs #N` 加 verify 報告連結）同樣掃一次；標題來自 issue，外人寫得到 |
| merge | PR | CI 等完之後重讀一次會變的東西：重新 fetch 預設 branch，branch 沒有落後它（落後的話 merge 的結果沒被審過，更新 branch 後重新 verify）、它最新的 workflow 不在 push 時發佈、這次改動不動 CI、沒有 merge queue（有的話停下，由人經 queue merge），gate 再判一次，沒有別人插手，PR 不是 draft、沒有 changes requested、沒有別人（非 bot）的 comment 或 review（verify r4 #1、#15）；剛好一個從 run 的 branch 開到預設 branch、不是 fork 的 open PR，它的 head 等於本機 HEAD；`gh pr merge --squash --subject --body --match-head-commit <verified sha>`，不刪 branch；merge 後重讀幾次確認 `MERGED` 且有 merge commit。仍是 OPEN 就關掉 auto-merge 並停下；讀不到確認時回報「可能已 merge」並保留 PR 號 |
| push | direct-commit | 目前在預設 branch，`origin/<default>` 是 HEAD 的祖先；`origin/<default>..<verified sha>` 的每個 commit 都引用 `#N`（不是這次 run 的 commit 就不推）且沒有 trap 字樣；本機 CI 閘門的結束碼是 0 或 10（第 2 道）；推送前再確認 HEAD 與 branch 沒變；推的是 verified sha 本身（`git push origin <sha>:refs/heads/<default>`），不是當下的 HEAD；被拒就停，不自動 rebase；推完向 GitHub 確認預設 branch 指向那個 commit |

#### 5c.2 呼叫 `/idd-close`

helper 的結果是 `"merged"` 或 `"pushed"` 時才做，否則直接到 Phase 6。指示文字裡不寫任何 `#數字`：`/idd-close` 從 args 讀 issue 號，多一個號碼就多一張可能被關的 issue（#392 verify r1 #33）。

```bash
RESULT="$CWD/.claude/.idd/state/idd-all-result-$N.json"
STATUS=$(jq -r '.status // "missing"' "$RESULT" 2>/dev/null || echo missing)
case "$STATUS" in merged|pushed) ;; *) echo "Stopped: the close stage ended with '$STATUS' — not calling /idd-close"; exit 0 ;; esac
INTER=$(jq -r '.interaction // "unknown"' "$RESULT")
CLOSE_ARGS="#$N --repo $GITHUB_REPO

ORCHESTRATED BY /idd-all — the close stage of the issue-driven-dev plugin's idd-all skill (Phase 5c). Do not ask the user at the stop points; apply the defaults of this skill's 'Orchestrated close' section. List every default you applied. If you stop without closing, end with exactly one line: 'Close stopped: <step> — <reason>'. The repository is the local clone at $CWD: run every git command of this skill there (git -C $CWD, WORKDIR=$CWD), not in the session's working directory."
if [ "$INTER" != "attended" ]; then   # unknown counts as unattended: skipping a sync is the safe direction
  CLOSE_ARGS="$CLOSE_ARGS

UNATTENDED MODE — called by /idd-all orchestrator. No one is present: skip the Step 6.5 distribution sync and list the command instead."
fi
printf '%s\n' "$CLOSE_ARGS"
```

然後 `Skill(skill="issue-driven-dev:idd-close", args=<上面印出的 CLOSE_ARGS>)`。兩個指示互相獨立：`ORCHESTRATED` 決定「誰在呼叫」（停點取預設），`UNATTENDED MODE` 決定「有沒有人在場」（只影響 distribution sync）。

#### 5c.3 確認真的結案

只看 issue 的 state 不夠：push 上去的 commit 若被 GitHub 解讀成關閉指令、或有人在等 CI 時手動關掉 issue，state 也是 CLOSED，卻沒有 closing summary。plugin 的 closing-summary 分類器（`check-closed-without-summary.sh --issue`）只能否決、不能放行，也把正文裡提到「closing summary」算進去，所以不能拿來確認。改用正面的確認：

```bash
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/close-stage.py" confirm-close --cwd "$CWD" --repo "$GITHUB_REPO" --issue "$N"
echo "confirm-close exit: $?"   # 0 = CLOSED, and this account posted a comment opening with '## Closing Summary' after the merge or push
```

exit 不是 0 時印 `Stopped: /idd-close did not finish (<reason>); the merge or push already happened — run /idd-close #N`。PR 已 merge（或已 push）而 `/idd-close` 停下時，**不回滾**：回報寫明「已 merge、issue 仍開著」、停在哪一步、原因，並給出 `/idd-close #N`。close 的 gate 不在 merge 前先跑，因為 Step 1.55 要讀已 merge 的 PR 才能判斷。

> **威脅模型（#392 決定，comment 6568180861）**：close stage 防的是 orchestrator **出錯**，不是 orchestrator **刻意欺騙**。寫程式碼的 orchestrator 同時寫 verify 報告的分類、略過確認的紀錄與 Decision comment；它若刻意把 Blocking 寫成別的、不寫紀錄，或自己貼 Decision，本機檢查擋不住。上面的檢查讓誠實的錯誤（漏讀、誤判、格式走樣）停下，讀不準的一律停。
>
> **已知限制**：
> - **close 的 Step 0 與 Step 1.5 排在 merge 之後**：issue 上還有未勾的 task（例如一份未完成的 Spectra tasks）時，`/idd-close` 會在 merge 之後拒絕結案，結果同樣是「已 merge、issue 仍開」。
> - **`gh api user` 被拒的環境**（GitHub App 安裝 token、Actions 的 `GITHUB_TOKEN`）：gate 認不出「本帳號」，一律讀成 `unparseable`，close stage 不會 merge。
> - **同一個帳號**：run 自己的 comment 與人用同一個帳號打的 comment 分不出來，所以「別人插手」只看別的帳號。要叫一個進行中的 run 停下，用別的帳號留言，或在 PR 上留言（run 從不在自己的 PR 上留言）。
> - **最後檢查到 merge 之間的幾秒**：`--match-head-commit` 只釘住 PR head。最後一次讀預設 branch 之後、GitHub 實際 squash 之前，若有別的 PR 剛好落地，squash 會落在新的 tip 上；GitHub 沒有釘住 base 的 merge 參數。
> - **direct-commit 不等遠端 CI**：推送前跑本機 CI 閘門；`ci.mode` 是 `remote` 時沒有 PR、沒有 check 可等，推上去之後由 repo 自己的 CI 跑。
> - **本機 CI 對同一個 commit 跑兩次**：Phase 4.5 一次（擋 push 與開 PR）、close stage 一次（擋 merge）。指令跑得久的 repo，一張 issue 會多等一次。
> - **direct-commit 不讀 branch protection**：admin 權限的 token 推送時，GitHub 會讓它越過要求 PR 或 check 的規則（#464）。
> - **verify 報告格式走樣就停**：gate 只認 `idd-verify` 樣板的寫法（恰好一行判定、Findings 表、覆蓋率行、reviewers 行）。2026-11-10 拿本 repo 80 份既有的 verify 報告（都早於這份樣板）給 gate 讀，76 份是 `unparseable`。照樣板寫的報告才會自動 merge，其他一律停在 verified 由人處理。
> - **發佈偵測是清單（維護者接受的限制，#392 第 7 輪後）**：清單外的發佈指令（`make ship`、`rsync`、遠端 action、repo 根目錄的 script）偵測不到，merge 就會發佈。會這樣發佈的 repo 帶 `--review`，repo 層級的設定在 #460。
> - **workflow 以外的發佈管道不偵測**：預設 branch 由 plugin marketplace 直接服務（例如本 repo 的 `.claude-plugin/marketplace.json`）、GitHub Pages 從 branch 部署、Vercel／Netlify 的 Git 整合，merge 就是把改動交給下一個安裝或部署的人。這類 repo 要帶 `--review`，或等 #460 決定怎麼偵測。push 時跑的 workflow 呼叫的 script（不在 `.github/` 下）被這次改動改到，也不偵測。
> - **`/idd-all` 仍可被模型自己呼叫**：「`/idd-all #N` 本身就是確認」的前提是人下了這個指令；把 idd-all 限定為只由人呼叫的工作在 #457。
> - **attended 是依 path 推出來的**：`--no-pr`、`pr_policy: never` 的 run 標為 attended。以 `claude -p` 或排程無人值守地跑 attended 模式，就沒有人回答 Plan 核准與 sub-skill 的問題；無人值守時用 PR mode。
> - **unattended 的 Plan tier 沒有人核准計畫**（2026-11-10 的決定接受的代價）：unattended run 遇到 Plan tier 是跳過 `/idd-plan` 直接實作的，close stage 不再因此停下，實作出來的東西只有 verify 把關。
> - **Decision comment 回應紀錄**：任何 Decision comment 都會讓它之前的略過紀錄不再擋 merge（也讓它之前的 Proposed Corrections 不再列入 `proposed_corrections`），不檢查它回應的是哪一則。照威脅模型，Decision comment 只記錄人說的話（`idd-comment --type decision`），不由 run 自己決定貼。

---

### Phase 6: Report and Stop (mode-aware)

Phase 6 回報這次 run 實際做到哪裡（#392）：merge（或 push）並 close 都完成時是 `Done:`／`Undo:`；在 gate、guardrail 或 `/idd-close` 停下時是 `Done:` 加上 `Stopped:`；帶 `--review` 時沿用「awaiting human acceptance」措辭；meeting issue 印 meeting report。

#### Meeting report(#383 verify r1)

選樣板看本次**實際走的路線**,不看重讀的 type(r6 #1):Phase 2 走了 meeting 列 → 印下面的 meeting report;Phase 3 有跑(implement、Plan 或 Spectra)→ 印後面的 Run report 樣板。

再照 Phase 5 guard 的寫法(`idd_diagnosis_type` 讀最新受信任 Diagnosis)重新取得 type 做交叉核對,attended 與 unattended 都一樣(meeting-issue-type 規格:後續需要 type 的步驟——unwind、verify、push、final report——都要從受信任 Diagnosis 重新取得,r5 #7)。重讀結果與路線不一致時——例如 direct-commit 或 `--in-chain` 的 run 在 verify 期間被貼了 meeting 的 Diagnosis(Phase 5 guard 只在 PR 路徑跑)——樣板仍照路線印,最上方加一行 `⚠ type changed during this run: the latest trusted Diagnosis of #N now records <type>; re-run /idd-diagnose #N`;重讀失敗時也照路線印,加一行 `⚠ could not re-read the Diagnosis type of #N`(r6 #9、#17)。換樣板會讓一個真的 implement、verify、開了 PR 的 run 印出「no implement, no verify, no push, no PR」。

Phase 2 走 meeting 列的 run 不印 Run report 樣板——那些樣板宣稱的 verify、implementation commits、PR 都沒有發生。改印:

```
✓ idd-all stopped (type=meeting)

  Issue:        #${N} — ${TITLE}
  Path:         meeting — no implement, no verify, no push, no PR
  Plan:         ${MEETING_PLAN_URL:-none — /idd-plan did not run (unattended) or did not finish}
  Branch:       ${UNWIND_LINE}   (照抄 meeting unwind 實際印出的那一行;沒跑 unwind 就寫目前的 branch)

  Next: attended → /idd-close #${N} once the Meeting Plan's Phase C is done
        unattended → see Action items (an attended /idd-plan, or /idd-close)
```

報告由模型照實填寫(Plan 填 `/idd-plan` 貼出的 Meeting Plan comment URL,unattended 時用預設文字)。之後照常附上「Phase 6 Action items surface」那一節的 Action items。**順序:先跑 Action items 區塊,再清理**——INTERACTION 遺失時,那個區塊要靠 unattended state file 回推,清掉之後就讀不到(r6 #8、#11)。meeting report 印出後同樣 `clear_unattended "$CWD"`(#123)——跳過 Run report 樣板不代表跳過這個清理(verify r2 #9)。

#### 遠端 CI 紅燈（#465）

本機閘門通過（exit 0）而遠端 check 失敗時，報告列出失敗的 check 名稱與連結，**不算阻擋合併**：本機模式下遠端 CI 只回報。查不到 PR 或還沒有結果時照實寫，不寫成通過。

#### Run report（PR 與 direct-commit 共用，#392）

回報寫實際發生的事，不寫預估；要短——人只需要知道做了什麼、哪裡可能要他處理、怎麼復原。

merge（或 push）並 close 都完成時：

```
✓ idd-all #${N} — ${TITLE}

Done:
  merged PR #${PR} into ${DEFAULT} as ${MERGE_SHA}     (direct-commit: pushed ${K} commit(s) to ${DEFAULT}, ${PUSH_FROM}..${PUSH_TO})
  closed #${N} — closing summary: ${CLOSING_SUMMARY_URL}
  changed: ${FILES} files, +${ADDS}/-${DELS}
  follow-ups filed: ${FOLLOWUPS or "none"}            (verify's Follow-up findings and /idd-close's, together)
  residue recorded: ${RESIDUE or "none"}
  distribution sync: ${done | asked: <answer> | skipped — run <command> | n/a}
  verify: ${ENGINE line of the verify report}; degraded: ${missing reviewers or "none"}
  left open: ${LOW} LOW in-scope finding(s) not fixed — listed in #${LOW_FOLLOWUP}        (only when low_in_scope > 0)
  left open: ${PC} comment(s) list Proposed Corrections that were not applied              (only when proposed_corrections > 0)
  remote CI: ${failed check names} failed while local CI passed                            (only when remote_ci_failed is not empty; "not readable" → say the remote checks could not be read; list remote_ci_pending as still running)
Next: run /spectra-archive ${CHANGE} on ${DEFAULT}       (only for a Spectra-tier run: the change is not archived yet)
Undo:
  gh issue reopen ${N}
  git -C ${CWD} checkout ${DEFAULT} && git -C ${CWD} pull --ff-only
  git -C ${CWD} revert ${MERGE_SHA}                     (direct-commit: git -C ${CWD} revert --no-edit ${PUSH_FROM}..${PUSH_TO})
  then push the revert, or open a PR with it — pushing is your call
```

merge 與 push 的欄位取自 `$CWD/.claude/.idd/state/idd-all-result-$N.json`（`pr`、`merge_sha`、`push_from`、`push_to`、`count`、`verify_url`，以及只在不是 0 或空的時候才列的 `low_in_scope`、`proposed_corrections`、`remote_ci_failed`、`remote_ci_pending`）；closing summary 連結取自 5c.3 `confirm-close` 印出的 `summary_url`；follow-up 取自 Phase 4 開的 issue 加上 `/idd-close` 列出的；residue、distribution sync 取自 `/idd-close` 列出的預設。`changed` 取自 `git diff --shortstat ${MERGE_SHA}^ ${MERGE_SHA}`（direct-commit：`${PUSH_FROM} ${PUSH_TO}`）；`verify` 照抄 verify 報告的 `### Engine` 那一行。`Next:` 那一行只在 Spectra tier 出現：`/idd-close` 不做 archive（`rules/sdd-integration.md`〈Close triggers archive〉），跳過它 change 就一直留在 `openspec/changes/`。

停下時（gate 不乾淨、guardrail 沒過、push 被拒、`/idd-close` 停下、Phase 4 在最後一輪仍有 Blocking 而 abort），`Done:` 只列實際做到的步驟，接著一行 `Stopped:`，原因照抄 Phase 4 或 Phase 5c 印出的那一行：

```
✓ idd-all #${N} — ${TITLE} (stopped)

Done:
  ${only what happened, e.g. "opened PR #${PR}" or "merged PR #${PR} into ${DEFAULT} as ${MERGE_SHA}"}
Stopped: ${guardrail or stop point} — ${reason, verbatim}
Next: ${one line for the human, e.g. "review PR #${PR}; after merging it run /idd-close #${N}" or "run /idd-close #${N}"}
Undo:                                                   (only when something was merged or pushed — same steps as above)
```

結果檔的 status 是 `stopped`、而 `merge_attempted` 或 `push_attempted` 的值是 `true` 時，merge 或 push 可能已經發生（例如 merge 成功但讀不到確認，或 helper 在呼叫之後被中斷）：照 reason 回報，並列出 `Undo:`。值是 `"refused"` 時，GitHub 拒絕了 merge 或 push、什麼都沒落地，不列 `Undo:`（verify r4 #23）。

這行 `Next:` 是 Phase 6 要人接手的地方；merge 與 close 都完成、又不是 Spectra tier 時沒有 `Next:`。

**清理**：回報印出後刪掉 `$CWD/.claude/.idd/state/idd-all-run-$N.json` 與 `idd-all-result-$N.json`，下一次 run 不會讀到這次的值。

#### `--review` report

帶 `--review` 時不進 Phase 5c，沿用「awaiting human acceptance」措辭：

PR mode：

```
✓ idd-all complete (PR mode, --review)

  Issue:        #${N} — ${TITLE}
  Branch:       ${BRANCH}
  Commits:      ${COMMIT_COUNT} (implementation + ${FIX_ROUND_COUNT} verify-fix rounds)
  PR:           ${PR_URL}
  Verify:       gate ${VERIFY_STATE} — awaiting human acceptance (re-opened confirmation loop per --review)
  Follow-ups:   ${FOLLOWUP_ISSUE_LIST or "(none)"}

Next: review PR ${PR_URL}, merge after acceptance, then run /idd-close #${N}
```

`${VERIFY_STATE}` 是 Phase 5 寫進 PR body 的同一個 gate 狀態（`clean`、`not_clean` 或 `unparseable`），兩處說法一致。

direct-commit mode：

```
✓ idd-all complete (direct-commit mode — HITL, --review)

  Issue:        #${N} — ${TITLE}
  Branch:       ${BRANCH}  (commits landed on user's current checkout)
  Commits:      ${COMMIT_COUNT} (implementation + ${FIX_ROUND_COUNT} verify-fix rounds)
  Verify:       verify-gated ${VERIFY_STATE} — awaiting human acceptance (re-opened confirmation loop per --review)
  Follow-ups:   ${FOLLOWUP_ISSUE_LIST or "(none)"}

Next: review last ${COMMIT_COUNT} commits (git log -${COMMIT_COUNT}), then run /idd-close #${N}
```

**Cleanup（#123）**：terminal report 與下一節的 Action items 都印出後才 `clear_unattended "$CWD"` — unattended flag 的生命週期 = 本次 orchestration。Action items 區塊在 INTERACTION 遺失時要靠這個 state file 回推，所以不能先清（#383 verify r6 #8、#11）。

**STOP**。Phase 6 之後 idd-all 不再做任何事：merge 與 close 已在 Phase 5c 做完或停下並寫明原因。`--review` 是 **orchestrator-scope** opt-in：它讓 run 停在 verified，不做 merge 與 close，Phase 6 改用「awaiting human acceptance」措辭（per #108 DA3: orchestrator-scope qualifier matters — humans/CI downstream may react to the changed text differently）。

#### Phase 6 Action items surface (v2.74.0+, #137)

`(category: audit-block-append, scope: "## Action items" final report section)` per [`rules/append-vs-modify.md`](../../rules/append-vs-modify.md)。 Phase 6 終端 report 之後,scan invoked sub-issues(本 invocation 直接處理的 root + spawn manifest 上記錄的衍生 issue,if any)for **三類** registry-cited deferred 記錄(cite [Reason pattern registry](../../rules/append-vs-modify.md#reason-pattern-registry)):(1) issue **body** 的 `### Clarity Surface` rows with reason literal `unattended-auto-Step-4.6-deferred`(#137);(2) issue **comments** 的 `#### Layer V Deferred Record` with reason literal `unattended-auto-Step-3.4-layerV-deferred`(#120 — Layer V 在 unattended 下 auto-proceed 的回補記錄,寫在 Diagnosis comment 不在 body)。(3) Diagnosis comment 的 `#### Choice Default Record`,reason literal `unattended-auto-Step-4-choice-default`(#392 — unattended diagnose 替人取了預設的決策)。 找到 → append 到 final report 末尾「## Action items (require human review)」section:

```bash
# After Phase 6 main report emit (see PR mode / direct-commit mode above), append action items:
ACTION_ITEMS=""
for sub_n in "$ROOT_N" "${SPAWNED_ISSUES[@]:-}"; do
  sub_n=${sub_n#\#}   # manifest 由模型填寫、未正規化：`#123` 先去掉 `#` 再驗型，否則兩項掃描都被靜默跳過（verify #318 round 5）
  case "$sub_n" in
    '') continue ;;   # 空值（例如 SPAWNED_ISSUES 為空時的 `:-` 展開）
    *[!0-9]*) printf '⚠ skipping non-numeric sub-issue: %s — Clarity Surface / Layer V scan not run\n' "$sub_n" | LC_ALL=C tr -d '\000-\010\013-\037\177' >&2; continue ;;   # printf, not echo：zsh 的 echo 會解譯值裡的反斜線跳脫（`\n` 偽造一行、`\c` 吞掉後半句）；值由模型填寫，剝 C0/DEL
  esac   # 進任何 gh 呼叫前驗型（manifest 內容不可信）。驗型必須在第一次使用之前，不是兩次使用之間（verify #318 round 4）
  SUB_BODY=$(gh issue view "$sub_n" --repo "$GITHUB_REPO" --json body --jq '.body' 2>/dev/null)
  # NOTE (v2.74.1+, #137 verify R1 fix): naive `awk '/^### Clarity Surface/,/^### /'`
  # range collapses on line 1 (start regex matches end regex); use flag pattern.
  AUTO_DEFERRED_COUNT=$(echo "$SUB_BODY" \
    | awk '/^### Clarity Surface/{flag=1; print; next} flag && /^### /{flag=0} flag' \
    | grep -cE '\| deferred \| unattended-auto-Step-4\.6-deferred \|')
  if [ "$AUTO_DEFERRED_COUNT" -gt 0 ]; then
    ACTION_ITEMS+=$'\n'"- #${sub_n}: ${AUTO_DEFERRED_COUNT} row(s) auto-deferred at /idd-clarify Step 4.8 (unattended mode) — resolve via /idd-clarify #${sub_n} --status resolved=<idx>,<reason>"
  fi
  # #120 (v2.97.0+): Layer V deferred records live in Diagnosis COMMENTS (not body); $sub_n was digit-checked at the top of the loop
  SUB_COMMENTS=$(gh api "repos/$GITHUB_REPO/issues/$sub_n/comments" --paginate --jq '[.[] | select(.author_association == "OWNER" or .author_association == "MEMBER" or .author_association == "COLLABORATOR") | .body]' 2>/dev/null | jq -s 'add // []' | jq -r 'join("\n---\n")')   # 分頁 + 只信任 repo 成員（外人留一則含 marker 的 comment 就能灌大計數）
  LAYERV_DEFERRED_COUNT=$(echo "$SUB_COMMENTS" \
    | grep -cE 'unattended-auto-Step-3\.4-layerV-deferred')
  if [ "$LAYERV_DEFERRED_COUNT" -gt 0 ]; then
    ACTION_ITEMS+=$'\n'"- #${sub_n}: ${LAYERV_DEFERRED_COUNT} Layer V deferred record(s) — vagueness trigger auto-proceeded under unattended mode; catch up via /idd-clarify #${sub_n}（或確認 proceed 正確後 dismiss）"
  fi
  # #392: choice-first defaults an unattended diagnose took for a decision a stakeholder should pick
  CHOICE_DEFAULT_COUNT=$(echo "$SUB_COMMENTS" | grep -cE '^[[:space:]]*- \*\*Reason\*\*: unattended-auto-Step-4-choice-default[[:space:]]*$')
  if [ "$CHOICE_DEFAULT_COUNT" -gt 0 ]; then
    ACTION_ITEMS+=$'\n'"- #${sub_n}: ${CHOICE_DEFAULT_COUNT} choice default(s) taken under unattended mode — pick the option yourself (see the Choice Default Record); once you have, tell Claude, who records it as a Decision comment, and the close stage no longer stops on it"
  fi
done

# #366: Step 0.5.1 停下的 issue 與 unknown 的查詢（EXISTING_WORK_ITEMS 由 Step 0.5.1 逐行累積；shell 狀態沒存活時重跑 helper 重建）
ACTION_ITEMS+="${EXISTING_WORK_ITEMS:-}"
# #383: 本次 gate 判為 meeting、停在 diagnosed 的 issue。idd-all 從沒有賦值 ROOT_N（上面那個 loop 靠
# `''` 那一列略過了它，#390），本次處理的就是 $N（verify r3 #4）。type 只信最新受信任 Diagnosis 的
# ### Type（r4）。Step 0.5.1 擋下（blocked）的 issue 沒有跑 diagnose，不列；unknown 的查詢行不算擋下
# （r4 #4）。
# r5 #2／#13：先只用 issue 號解析 type，不看 INTERACTION——非 meeting 的 run 什麼都不印、也不抓本文
# （回到 non-noisy）。attended 的 meeting run 已走 /idd-plan，由 meeting report 交代，不查。INTERACTION
# 是 shell 狀態，遺失時先問 unattended state file；仍不知道，而且確定是 meeting，才印「請手動確認」。
RN="${ROOT_N:-$N}"
case "$RN" in ''|*[!0-9]*) RN="" ;; esac
MODE="${INTERACTION:-}"
if [ -z "$MODE" ] && [ -n "${CWD:-}" ] && . "${CLAUDE_PLUGIN_ROOT}/scripts/lib/unattended-state.sh" 2>/dev/null && is_unattended "$CWD" 2>/dev/null; then
  MODE=unattended
fi
if [ "$MODE" = attended ]; then
  :
elif [ -z "$RN" ]; then
  # 沒有 issue 號就查不了 type：只有確定是 unattended 才提醒（非 meeting 的 run 是常態，不製造雜訊）
  if [ "$MODE" = unattended ]; then
    ACTION_ITEMS+=$'\n'"- the issue number of this run was lost (shell state) — if it was a meeting issue, it stopped at diagnosed; check it by hand"
  fi
elif [ -n "${GITHUB_REPO:-}" ] && . "${CLAUDE_PLUGIN_ROOT}/scripts/lib/actionability.sh" \
     && MT_PAGES=$(gh api "repos/$GITHUB_REPO/issues/$RN/comments" --paginate --jq '[.[] | select(.author_association == "OWNER" or .author_association == "MEMBER" or .author_association == "COLLABORATOR") | .body | select(split("\n") | any(startswith("## Diagnosis")))]') \
     && MT_LATEST=$(jq -s -r 'add // [] | last // ""' <<<"$MT_PAGES"); then
  if [ "$(idd_diagnosis_type "$MT_LATEST")" = meeting ]; then
    if printf '%s\n' "${EXISTING_WORK_ITEMS:-}" | grep -qE "^- #${RN}: (existing PR #[0-9]+ declares it — not started|already merged in PR #[0-9]+)"; then
      :   # Step 0.5.1 stopped it before diagnose; its own line above says why
    elif [ "$MODE" != unattended ]; then
      ACTION_ITEMS+=$'\n'"- #${RN}: type=meeting, but the interaction mode of this run was lost (shell state) — if it was unattended, it stopped at diagnosed; check it by hand"
    else
      KEPT=""
      [ -n "${CWD:-}" ] && KEPT=$(git -C "$CWD" for-each-ref --format='%(refname:short)' "refs/heads/idd/${RN}-*" 2>/dev/null | head -1)
      NEXT="next: attended /idd-plan #${RN} for a Meeting Plan, or /idd-close #${RN} (a plan is optional — the close gate falls back to the Diagnosis Phase C)${KEPT:+; local branch $KEPT holds the attachment manifest}"
      # phase 從 idd-update 管的 ## Current Status 區段讀（r5 #28）。這是慣例不是信任邊界：整份本文作者都改得到，
      # 這裡只決定兩種 Action item 措辭中的哪一種，兩種都帶同一個 NEXT（r6 #27、#29）
      if MT_BODY=$(gh issue view "$RN" --repo "$GITHUB_REPO" --json body --jq '.body // ""'); then
        if printf '%s\n' "$MT_BODY" | awk '/^## Current Status/{f=1} f' | grep -q '^\*\*Phase\*\*: diagnosed'; then
          ACTION_ITEMS+=$'\n'"- #${RN}: type=meeting — stopped at diagnosed (unattended); ${NEXT}"
        else
          ACTION_ITEMS+=$'\n'"- #${RN}: type=meeting, but the issue body does not show phase diagnosed (not synced?) — if this run diagnosed it, run /idd-update #${RN} first; ${NEXT}"
        fi
      else
        ACTION_ITEMS+=$'\n'"- #${RN}: type=meeting — the issue body could not be read to confirm the phase; if this run diagnosed it, it stopped at diagnosed (unattended); ${NEXT}"
      fi
    fi
  fi
elif [ "$MODE" = unattended ]; then
  # 查不到 type（GITHUB_REPO 遺失、fetch 或 jq 失敗）：只有確定是 unattended 才提醒，理由同上面 issue 號遺失那一列（r6 #14、#23）
  ACTION_ITEMS+=$'\n'"- #${RN}: could not re-resolve the issue type for this report — if it is a meeting issue, it stopped at diagnosed; check it by hand"
fi

if [ -n "$ACTION_ITEMS" ]; then
  cat <<EOF

## Action items (require human review)
${ACTION_ITEMS}

Reason literal source: rules/append-vs-modify.md § Reason pattern registry.
EOF
fi
```

**Trigger condition**:per-invocation;若無 auto-deferred rows → section 不 emit(non-noisy)。 attended mode 通常無 auto-deferred(`/idd-clarify` Step 4.8.A detection 預設 attended → 寫 `surfaced` rows + AskUserQuestion),unattended chain (`/loop` / `IDD_ALL_UNATTENDED=1`) 才會 surface。

**Multi-issue scope**:`SPAWNED_ISSUES` 變數涵蓋 idd-all-chain 的 spawn manifest 或 cluster mode 的所有 #N(per [`references/spawn-manifest.md`](../../references/spawn-manifest.md));single-issue invocation 只 scan root。

---

## Failure Modes(每個都該明確 abort,不該 swallow)

| 情況 | 行為 |
|------|------|
| `--cwd /path` 不存在 | Phase 0.2 abort,提示 user 確認 path |
| `--cwd` 給的目錄沒 origin remote | Phase 0.2 abort,顯示 cd path 與 git config 修法 |
| 沒給 --cwd 且 session cwd 不是 git repo | Phase 0.3 abort,訊息含「pass --cwd /path」alternative |
| Working tree dirty (PR mode only) | Phase 0.5 abort,顯示 `git -C $CWD status`(direct-commit mode 改 passive warning,不 abort) |
| Not on default branch (PR mode only) | Phase 0.5 abort,提示 `git -C $CWD checkout $DEFAULT`(direct-commit mode 留 user 當前 branch) |
| gh auth 沒設定 | Phase 0.3 abort,提示 gh auth login |
| Issue #N 不存在 / CLOSED | Phase 0 abort |
| Branch 已存在 | Phase 0 AskUserQuestion(checkout / -2 suffix / abort) |
| Diagnosis 缺 `### Complexity` 區段(helper cexit=4) | Phase 2 abort,提示手動跑 idd-diagnose。**非 meeting;meeting 只在完全沒有受信任的 Diagnosis 時才 abort**——有 Diagnosis 的 meeting 走分派表的 meeting 列(#383 verify r2) |
| Phase 4 type guard:issue 號不是數字、helper 缺失,或最新受信任 Diagnosis 記 meeting(Phase 2 之後 type 被改了)| Phase 4 abort,**不 verify、不 push**;本次做過的 commits 原地保留,訊息提醒查 git log,沒有 commit 時去跑 meeting unwind;照下方 abort 職責 `clear_unattended`(#383 verify r5 #11、#12)。**`GITHUB_REPO` 遺失、comment fetch 或 jq 失敗不 abort**:讀不到 type 時照 Phase 2 選的 code 路線進 verify,只印警告(r6 #2、#14)|
| Phase 5 type guard 失敗(PR 路徑):issue 號不是數字、helper 缺失、`GITHUB_REPO` 遺失、comment fetch 失敗、comment 清單無法用 jq 讀取,或最新受信任 Diagnosis 記 meeting | Phase 5 abort,**不 push、不開 PR**;branch 與 commits 保留,照下方 abort 職責 `clear_unattended`。direct-commit / `--in-chain` 不跑這個 guard(#383 verify r2、r5) |
| meeting unwind 失敗(helper、`CWD` 遺失、manifest commit、checkout 任一步) | Phase 2 abort,印出停在哪個 branch;不刪任何 branch(#383 verify r2、r5 #10)。**`GITHUB_REPO` 遺失、comment fetch 或 jq 失敗不 abort**:不知道 type 時 branch 原樣保留本來就是非 meeting run 該有的結果,只印警告,說明若是 meeting 要怎麼手動收(r5 #14)|
| actionability gate 判 not-actionable(`VEXIT=1`:`### Complexity` 不可路由 exit 3/4/5、`parking-lot` label、`### Blocking` 非空)| Phase 2 abort,印出 `$REASONS` 與原文(`$COMPLEXITY_ERR` / label 名 / `$BLOCK_LINE`);不截斷、不降級成任何 tier;`complexity-deferral-marker` / `parking-lot-label` 是合法延期狀態,不要求「修正」|
| spectra-discuss 沒 emit `Conclusion:` line(unattended hint 失敗)| Re-prompt 一次;再失敗 abort,branch 保留 |
| spectra-propose 沒 emit `Change:` line | 同上 |
| spectra-propose 遇到 unrecoverable validation error | Phase 3b abort,artifacts 保留,提示手動 `/spectra-propose` |
| spectra-apply 留下 unfinished tasks | 不 abort — Phase 4 verify 會抓出來 |
| Verify 2 round 後仍 blocking | Phase 4 abort,留 branch 給 user 手動修 |
| `gh pr create` fail | Phase 5 abort,branch 已 push,提示手動開 PR |
| verify gate `unparseable`(報告讀不出來、沒有新報告、判定與表格矛盾) | 不修、不 merge、不 close;停在 verified,Phase 6 `Stopped:` 寫出 gate 的 reason(#392) |
| Phase 5c 任一道 guardrail 沒過(CI 失敗或 15 分鐘仍 pending、auto-close trap、squash message) | 不 merge;PR 保留,Phase 6 `Stopped:` 寫出是哪一道與原因(#392) |
| direct-commit 不在預設 branch、要推的 commit 有不是這張 issue 的、push 前掃到 close 關鍵字、或 push 被拒 | 不 push(或 push 失敗)、不 close、不自動 rebase;Phase 6 `Stopped:`(#392) |
| PR 已 merge(或已 push)但 `/idd-close` 停下 | 不回滾;Phase 6 `Done:` 列出 merge,`Stopped:` 寫出 close 停在哪一步,`Next:` 給 `/idd-close #N`(#392) |

abort 時:
- `clear_unattended "$CWD"`（#123 — 絕不留 stale unattended flag 誤導下一個 attended session）
- `close-stage.py reset --cwd "$CWD" --issue "$N"`（#392 — 不留這次 run 的 run-state 給下一次 run 讀）
- TaskList 標記當前 phase 為 in_progress(不要 mark completed)
- 顯示「自己手動接手」的具體命令(例:`/idd-verify #19` 或 `gh pr create ...`)
- branch 不刪除(保留進度,user 可繼續)

---

## 鐵律

- **PR mode 一律在 feature branch**。direct-commit mode 留在 user 當前 branch — 兩者都是合法 path。
- **merge 與 close 只跟在乾淨的 verify 之後**(#392)。verify gate 判 `clean`、guardrail 全過才 merge(或 push)並 `/idd-close`;判不出來一律當成不乾淨。closing summary 照 `/idd-close` 的格式寫,root cause、solution、verification trail 都要有,Phase 6 附上它的連結。
- **做了就回報怎麼復原**。merge 與 close 不先問人(Foresay traceable),所以 Phase 6 一定列出 `Undo:`(`gh issue reopen`、`git revert`)。
- **Attended mode 沒有 silent timeout**。user 沒回應就一直等;若 user 不在,該選 unattended。
- **abort 比硬撐好**。任何 ambiguity → 停下、保留進度、告訴 user 怎麼接手。

## Examples

### Trace 1: `(PR, unattended)` — `/loop` 與預設 caller

```
/idd-all #42 --pr
```

Phase 0.5 印 `→ Path: PR (unattended) — flag=--pr`,sub-skill args 全帶 `UNATTENDED MODE` directive。verify 第 1 輪有 2 項 In-scope fix → 自動修 → 第 2 輪 gate `clean` → Phase 5 開 PR → Phase 5c 的檢查全過(意圖確認過、gate、CI、trap、squash message),squash-merge 後以 `ORCHESTRATED BY /idd-all` 跑 `/idd-close`(#392):

```
✓ idd-all #42 — bug: login button stops after 3 failed attempts

Done:
  merged PR #87 into main as 3f2c1ab
  closed #42 — closing summary: https://github.com/owner/repo/issues/42#issuecomment-111
  changed: 3 files, +48/-9
  follow-ups filed: none
  residue recorded: none
  distribution sync: n/a
  verify: pai-ensemble 2.18.0 — 4 IDD lenses + DA + Codex, model: opus; degraded: none
Undo:
  gh issue reopen 42
  git -C ~/src/repo checkout main && git -C ~/src/repo pull --ff-only
  git -C ~/src/repo revert 3f2c1ab
  then push the revert, or open a PR with it — pushing is your call
```

CI 有一項失敗時,Phase 5c 不 merge:

```
✓ idd-all #42 — bug: login button stops after 3 failed attempts (stopped)

Done:
  opened PR #87
Stopped: guardrail 2 (CI checks) — failed: test
Next: fix the failing check on PR #87; after merging it run /idd-close #42
```

With `--review` opt-in(不進 Phase 5c):

```
✓ idd-all complete (PR mode, --review)
  Issue:        #42 — bug: login button stops after 3 failed attempts
  Branch:       idd/42-bug-login-button-stops-after-3-faile
  Commits:      3 (implementation + 1 verify-fix rounds)
  PR:           https://github.com/owner/repo/pull/87
  Verify:       verify-gated PASS — awaiting human acceptance (re-opened confirmation loop per --review)
  Follow-ups:   (none)

Next: review PR https://github.com/owner/repo/pull/87, merge after acceptance, then run /idd-close #42
```

`/loop` 等自動化 caller 自 #392 起看到的終點是 closed,不再是 verified(CHANGELOG 標 BREAKING);需要舊行為的 caller 帶 `--review`。PR 仍帶 `Refs #42`、不含 `Closes`;issue 由 `/idd-close` 關,不靠 GitHub 的 auto-close。

### Trace 2: `(direct-commit, attended)` — HITL 場景

`.claude/issue-driven-dev.local.json` 含 `"pr_policy": "never"`,user 在 keyboard、目前在 `main`:

```
/idd-all #42
```

Phase 0.5 印 `→ Path: direct-commit (attended) — pr_policy=never`,sub-skill args **不帶** unattended hint。

中間流程:
- Phase 2 diagnose 判定 `Plan` → Phase 3p `/idd-plan` 用 `EnterPlanMode` 把 plan 呈現給 user → user `ExitPlanMode` approve → `/idd-plan` chain 到 `/idd-implement` 跑 TDD
- Phase 4 verify gate `clean`(只剩 1 項 Follow-up,照常開 follow-up issue)
- Phase 5c:在預設 branch 上,每個要推的 commit 都引用 #42、沒有 trap 字樣 → 推 verify 過的那個 commit 到 main → `/idd-close`;Step 6.5 有人在場,照常詢問 distribution sync

```
✓ idd-all #42 — bug: login button stops after 3 failed attempts

Done:
  pushed 3 commit(s) to main, 9a1b2c3..4d5e6f7
  closed #42 — closing summary: https://github.com/owner/repo/issues/42#issuecomment-222
  changed: 3 files, +48/-9
  follow-ups filed: #43
  residue recorded: none
  distribution sync: asked: skip
  verify: pai-ensemble 2.18.0 — 4 IDD lenses + DA + Codex, model: opus; degraded: none
Undo:
  gh issue reopen 42
  git -C ~/src/repo checkout main && git -C ~/src/repo pull --ff-only
  git -C ~/src/repo revert --no-edit 9a1b2c3..4d5e6f7
  then push the revert, or open a PR with it — pushing is your call
```

若 user 一開始在 `wip/foo` 而不是 `main`,Phase 5c 不 push、不 close,回報 `Stopped: the fix is on 'wip/foo', not on the default branch 'main'`。若 verify 有 Blocking,attended 不自動修,findings 交回 user,同樣不進 Phase 5c。

### Trace 4: `(PR, unattended)` + ralph-loop missing — graceful degrade (v2.53+, #28)

`pr_policy` 缺省(預設) + ralph-loop 沒裝:

```
/idd-all #42
```

Phase 0.5 印 `→ Path: PR (unattended) — pr_policy absent (v2.40.0 default)` 並 `git checkout -b idd/42-bug-foo`。Phase 0.6 偵測到 ralph-loop missing,unwind branch 並 degrade。

```
⚠ ralph-loop plugin not detected — required to drive (PR, unattended) verify-fix loop.
  Degrading to (direct-commit, attended) for backward-compat (#28 B4 design).
  To restore (PR, unattended): claude plugin install ralph-loop@claude-plugins-official

→ Unwinding Phase 0.5 PR-mode branch setup before degrade:
    git checkout main
    Switched to branch 'main'
    git branch -d idd/42-bug-foo (no commits yet — safe delete)
    Deleted branch idd/42-bug-foo (was 0e9bb99).
→ Path: direct-commit (attended) — pr_policy absent (v2.40.0 default) + ralph-loop missing → graceful degrade (#28)
→ Will commit to current branch: main
```

後續 sub-skill 全部進 attended 模式(像 Trace 2),user 在 keyboard 自然推進。final report 標明 degrade 原因。

無 abort、無 silent break — backward-compat 對 v2.40.0 既有 caller 維持。

### 從零開始 — 文字描述

```
/idd-all "bug: login button stops responding after 3 failed attempts"
```

跑 idd-issue 建 issue #N → Phase 0.5 解析 mode → 後續依 mode 走 PR 或 direct-commit path。

### 從零開始 — 用 spec 檔

```
/idd-all docs/specs/new-feature.md
```

把 spec 內容當 issue body 跑 idd-issue → 後續同上。

### 跨 repo invocation(v2.39.0+)

當 Claude Code session 的 cwd 不在目標 repo(例如同時在 thesis 工作要對 ooxml-swift 跑 idd-all):

```
/idd-all #43 --cwd /Users/che/Developer/macdoc/packages/ooxml-swift --pr
```

idd-all 在指定 local clone 跑完整 pipeline:branch 開在那邊、commits land 那邊、PR 從那 push,Claude Code session cwd 不變。`--pr` 與 `--cwd` 可並用;不帶 `--pr/--no-pr` 則由 walked-up config 的 `pr_policy` 決定。

---

## Auto-Update

每個 sub-skill(idd-issue / idd-diagnose / idd-implement / idd-verify)在自己的 Step N Auto-Update 都會跑 idd-update,所以 issue body 的 Current Status 會在每個 phase 後自動 sync。idd-all 不需要額外 update。

## Next Step

merge 與 close 都完成時沒有下一步:Phase 6 的 `Done:` 是給人事後看的紀錄,`Undo:` 是要撤回時的命令。

只有回報裡出現 `Stopped:` 或 `Next:` 時,人才需要接手,做的就是那一行寫的事——通常是兩種之一:

- **停在 verified**(gate 不乾淨、guardrail 沒過、帶 `--review`):看過 PR 或 commit、處理 `Stopped:` 寫的原因,merge 之後跑 `/idd-close #N`;或再跑一次 `/idd-all #N`。
- **已 merge、`/idd-close` 停下**:處理 close 停下的原因(例如 Step 1.6 的警告),再跑 `/idd-close #N`。

### meeting run(#383)

最新受信任 Diagnosis 的 `### Type` 是 meeting 時,沒有 PR、沒有 implementation commit 可 review:attended run 寫完 Meeting Plan,做完 Phase C 的行動項後跑 `/idd-close #N`;unattended run 停在 diagnosed,照 Action items 在有人在場時跑 `/idd-plan #N` 或 `/idd-close #N`。PR 模式若保留了只帶 attachment manifest 的 `idd/N-*` branch,先決定 push 或刪除。

`/idd-close` 仍是人可以直接呼叫的入口:手動結案的流程與問題都不變,只有 idd-all 帶 `ORCHESTRATED BY /idd-all` 指示呼叫時才取預設。
