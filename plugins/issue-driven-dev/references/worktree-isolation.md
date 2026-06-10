# Worktree Isolation — Parallel IDD via git worktree

> **Applies to**: `idd-implement`, `idd-verify`, `idd-close`（透過 `--cwd`）+ helper `scripts/idd-worktree.sh`（v1）
> **Purpose**: 讓 N 個 Claude Code window 對同一個 repo 各自跑一條完整 IDD pipeline，互不踩到 working tree / branch HEAD / `.claude/.idd/` staging。
> **Issue**: PsychQuant/issue-driven-development#167

## Purpose & Layout

IDD skills 假設只有一個 serial executor 在動 git/filesystem state。同時跑兩條 pipeline 會在三個地方對撞：共享的 **working tree**、共享的 **branch HEAD**、以及 repo 相對的 **`.claude/.idd/` staging** 目錄。

關鍵洞察：**一個 git worktree 同時解掉這三個碰撞。** 因為 worktree 有自己獨立的 working directory，而 `.claude/.idd/` 是 repo 相對路徑，所以每個 worktree 自動拿到自己的 working tree、自己 check out 的 branch、自己的 `.claude/.idd/`。一個 isolation primitive 蓋掉全部三層 —— 不需要新的 isolation 機制，只需要一個**約定 + 一個薄 helper**。

**Layout**：

```
<repo-root>/
  .claude/
    worktrees/              ← gitignored（marker-guarded append）
      idd-12/               ← worktree on branch idd/12-<slug>
        .claude/.idd/       ← 這個 worktree 私有的 staging（自動隔離）
      idd-34/               ← worktree on branch idd/34-<slug>
        .claude/.idd/
```

- **Worktree path**：`.claude/worktrees/idd-<N>/`，落在 repo root 底下（與 harness `EnterWorktree` 的位置一致）。
- **Branch**：helper 在建 worktree 時就把 feature branch `idd/<N>-<slug>` 一起建出來（`git worktree add -b idd/<N>-<slug> <path> <default-base>`）。
- **Gitignore**：`.claude/worktrees/` 會被冪等地（marker 註解守衛）加進 target repo 的 `.gitignore`，這樣 worktree 目錄不會在主 working tree 裡顯示成 untracked。

## Helper Workflow

Helper 是一支 bash script，不是 skill（D3：與既有 extracted-helper 慣例一致，~30% 獨特 surface 不值得開第 15 個 skill）。位置：

```
plugins/issue-driven-dev/scripts/idd-worktree.sh
```

三個 subcommand：

### `create <N> [--slug <s>] [--repo-root <path>]`

建 `.claude/worktrees/idd-<N>/`，check out 在 branch `idd/<N>-<slug>`，確保 `.claude/worktrees/` 已 gitignored，然後**把 worktree 的絕對路徑印到 stdout（且只印這個）** —— 這個值就是要餵給 `--cwd` 的東西。所有診斷訊息走 stderr，stdout 保持可被 caller / `--cwd` 直接 parse。

- **Slug 來源**（高到低）：`--slug` flag → gh issue title slugified（lowercase、non-alnum runs → `-`、capped 40 chars）→ 無 title source 時 bare `idd/<N>`。
- **Idempotent**：對已存在的 `<N>` 再跑一次 → 印既有路徑、exit 0，不會建第二個 worktree。
- **Base branch**：預設從 `origin/HEAD` 的 target，否則本地 `main`/`master`，否則當前 HEAD。

```bash
# 典型用法：拿印出的路徑去開 pipeline
WT=$(bash plugins/issue-driven-dev/scripts/idd-worktree.sh create 42)
echo "$WT"   # → /abs/path/to/repo/.claude/worktrees/idd-42
```

### `cleanup <N> [--force] [--repo-root <path>]`

移除 `.claude/worktrees/idd-<N>/`。

- 不存在 → exit 0（idempotent no-op）。
- 有 uncommitted changes 且未給 `--force` → **拒絕**、exit 5、worktree 保持原狀、stderr 指出哪個 worktree 是 dirty。
- 給 `--force` → 不管有沒有 uncommitted changes 都移除。
- **Branch 永遠保留**（關聯的 PR 可能還開著或已 merge，與 worktree 生命週期解耦）。

### `list [--repo-root <path>]`

每個 IDD worktree 印一行：`<N>\t<branch>\t<path>`（tab 分隔）。沒有任何 IDD worktree 時印空、exit 0。用來巡 orphan（`idd-close` 沒跑到、issue 被放棄留下的 worktree）。

### Exit Codes

| Code | 意義 |
|------|------|
| `0` | success（含 idempotent re-create / cleanup no-op）|
| `1` | generic error |
| `2` | usage error（壞 subcommand / N 非正整數或缺漏）|
| `3` | target 不是 git repository（訊息會指名 `--repo-root`）|
| `4` | branch-name conflict（`idd/<N>-*` 已 check out 在**另一個** worktree/path 上）|
| `5` | refuse-dirty（cleanup 被 uncommitted changes 擋住、未給 `--force`）|

### Env

| Var | 效果 |
|-----|------|
| `IDD_WORKTREE_NO_GH=1` | 跳過 gh-title slug 推導（offline / hermetic 環境）。slug 退回 bare `idd/<N>`，除非有給 `--slug`。|

## Case B Usage Pattern（multi-window）

Case B = N 個獨立的 Claude Code window，各自對同一 repo 跑一條完整 pipeline。**人 / orchestrator 負責開 window 並呼叫 helper**；IDD 不決定「何時該平行」。

在一個**新開的 Claude Code window** 裡：

```bash
# 1. 建 worktree，拿印出的絕對路徑
bash plugins/issue-driven-dev/scripts/idd-worktree.sh create 42
# stdout → /Users/che/Developer/myrepo/.claude/worktrees/idd-42
```

```text
# 2. 把那個路徑餵給整條 pipeline 的 --cwd（這裡用 /Users/.../idd-42 代表它）
/idd-implement #42 --cwd /Users/che/Developer/myrepo/.claude/worktrees/idd-42
/idd-verify    #42 --cwd /Users/che/Developer/myrepo/.claude/worktrees/idd-42
/idd-close     #42      # ← 自動 GC 這個 worktree
```

同時，**另一個 window** 對 `#43` 跑一模一樣的流程（`create 43` → `--cwd .../idd-43`），兩條 pipeline 因為各自有 working tree / branch / `.claude/.idd/` 而互不干擾。

`idd-implement` 透過 **Phase 0.5 worktree-branch acceptance clause** 接住這個流程：當 `git branch --show-current` 命中 `idd/<N>-*`（正在被 implement 的 issue 號），就把它當成 feature branch、跳過「必須從 default branch 起步」的 precondition。acceptance 是 **slug-agnostic** 的（`idd/<N>-` 後面接什麼 slug 都算），所以 helper 建的 slug 和人預期的不一致也沒關係。

`idd-close #N` 完成 close 後會呼叫 `idd-worktree.sh cleanup <N>` 自動 GC：clean tree → worktree 消失；dirty tree → 印一行 warning、worktree 留著等手動處理。GC 是 **best-effort** —— helper 不存在（舊版 plugin）或 cleanup 拒絕，`idd-close` 只 surface warning，**永遠不擋 / 不 fail close**。

## Convergence Model

**N parallel issues → N independent branches → N PRs。沒有 merge-back。**（D1）

每條平行 IDD 產出自己的 feature branch 和自己的 PR（一個 issue 一個）。v1 **不**把 N 個 worktree branch 併成一個 cluster PR。

這裡有一個必須講白的張力：**single-clustered-PR 和 parallelism 是相反的 convergence model。**

| 想要的結果 | 用什麼 | Convergence |
|-----------|--------|-------------|
| N 個獨立 issue、各自一個 PR、平行跑 | **worktree isolation（本 doc）** | N branches → N PRs（fan-out）|
| 一組相關改動、整鏈收進**一個** review PR | **sequential `/idd-all-chain`** | root + emergent spawn → 1 cluster branch → 1 PR（fan-in）|

IDD 已經擁有 sequential 的 single-PR 那一側（`/idd-all-chain` Phase 2 是在**一條** cluster branch 上的 pop-invoke-enqueue loop）。追求 parallel-into-one-PR 會重蹈那套機制、再多加一個 worktree-branch merge-back + 衝突解決步驟。走 N-PRs 這條直接刪掉整個問題。**需要一個 clustered PR 的工作，請用既有的 sequential `/idd-all-chain`，不要用 worktree isolation。**

## Shared-State Parallel Safety

v1 **不加任何新的 locking layer**。平行安全靠三件已存在的事撐住（D7）：

1. **Per-worktree working dirs** — 每個 worktree 有自己的 `.claude/.idd/`，attachment staging / run-log path / 任何 repo 相對的 `.claude/.idd/` artifact 都自動落在各自的 worktree 目錄裡，不互相覆蓋。
2. **Issue-scoped attachment naming** — attachment upload 命名為 `issue_<N>_*`（issue 範圍）。不同 issue 永遠不撞名；同一 issue 的平行處理是罕見 re-run。
3. **#76-hardened run-log** — `.claude/.idd/issue-runs/<run_id>.jsonl` 已經 collision-hardened（ms-precision run_id + nonce + noclobber），即使在同一個 `.git` 底下也安全。

**已知邊界（documented, not fixed in v1）**：worktree 各自有獨立 index，但共享 `refs` / `packed-refs`。更新**不同** branch ref 的 concurrent commit 通常安全，但高並發極少數情況可能在 `.git` 層的 `index.lock` 上 contend。v1 鎖定**人類節奏的 multi-window 低並發**用途，不是 high-fanout automation。`~/.cache/idd-route/stats.jsonl` 的 append 是 line-oriented 且容忍罕見 interleave。

## Deferred: Case A（within-window agent teams）

> **此區段刻意標明為 DEFERRED。** 以下能力**不在 v1**，記錄於此是為了讓本 doc/contract 成為它未來建構時的**穩定地基**。

**Case A** = 單一 Claude Code window 內、由 orchestrator 叫起平行 **sub-agent**，一群 sub-agent 在**同一個 coherent feature** 上協作，最後必須 **merge 回一個 cluster PR**。

為什麼 defer（D2）：

- 目前**零** IDD code 把 skill 當 parallel sub-agent 叫起 —— Case A 是淨新增的 orchestration entry point。
- Case A 需要 D1 non-goal 裡那套 **merge-back 協定**（N 個 worktree branch 收進一個 cluster PR + 衝突解決），這正是本 doc 刻意刪掉的問題。
- diagnose 標記 Case A 可能 premature：真實使用若以 Case B 為主，先做 Case B 才務實。User 已確認 Case B 是 primary target。

Case A 落地時會用的 harness primitive：**`Agent(isolation:"worktree")`** —— 由 harness 在 spawn sub-agent 時替它開一個隔離 worktree，正好對應本 doc 描述的 `.claude/worktrees/idd-<N>/` 約定。換句話說，Case A 是把本 doc 的 isolation primitive 從「人手動開 window + 跑 helper」升級成「orchestrator 程式化 spawn」，**isolation 契約本身不變** —— 這就是 v1 把它凍結成 reference doc 的意義。

## Tree-lock: asymmetric escalation（v2.85.0+, #183）

上面的 worktree primitive 在 v1 是 **advisory**——「prefer a worktree」靠人記得手動跑 helper。**Tree-lock 把它變成 normative 機制**：`idd-implement` Step 0.4 在 path resolution 之前先跑 `scripts/idd-tree-lock.sh acquire`，由 lock 狀態**自動**決定要不要 escalate 進 worktree。這是 #183 discuss（2026-06-03）收斂的 **Option D — lock-based asymmetric escalation**。

| acquire 結果 | 行為 |
|--------------|------|
| **exit 0**（first-come / solo） | 留在 shared main tree、direct-commit、**零 worktree 稅**、慣例不變 |
| **exit 3**（另一 live session 持鎖） | **自己** escalate：`idd-worktree.sh create <N>`，在自己的 worktree+branch 工作，close 時 merge 回去（solo fast-forward 看起來像 direct-commit；真分歧 → real merge） |
| **exit 4 / 其他**（lock infra 壞） | **fail-open**：留在 main tree + visible warning，**永不**擋工作 |

**Lock 契約**（`scripts/idd-tree-lock.sh`）：

- Lock = 目錄 `.claude/.idd/tree-lock`（`mkdir` atomic，兩個同時 acquire 不會都贏），內含 `info`：holder / pid / heartbeat / epoch。
- **Scope = cross-terminal；anchor = `$PPID`**：lock 記錄的是 **`$PPID`（harness shell，持久跨 instance 的 Bash calls、instance 結束才死）**，不是 helper 自己的 `$$`（subprocess，一返回就死 → 會讓 lock 變 no-op，#183 verify B1）。所以 isolation 對「**分開 terminal / 分開 `claude` instance**」的並行（就是 ai_martech ~3 個並行 session 的真實情境）生效。`$PPID` 唯一分不出的——**同一 instance 內** sub-agent 共用 `$PPID`——正是 already-deferred 的 Case A（見上節），刻意 out of scope。
- **Liveness, never doneness**：acquire 撞到既有 lock 時，用 **PID liveness**（`kill -0` recorded `$PPID`）判定 holder 是否還活著——dead → 自動 reclaim、alive → exit 3。**永不**問「holder 做完沒」。PID 不可驗時（含 atomic-create 的短暫窗）用 heartbeat / mtime-TTL（`IDD_TREE_LOCK_TTL`，預設 1800s）作 backup：fresh lock 視為 held、stale 才 reclaim。
- **Atomicity**：lock 是用 `set -C`（noclobber）原子建立的**檔案**（create + 寫 content 一步到位，無 mkdir-then-write 窗），stale reclaim 用 `mv` 移開（一個 racer 贏）再重建，避免晚到的 reclaimer 抹掉別人剛拿到的新鎖。
- **Asymmetric**：first-comer 免費持 tree（不預測未來）；later-comer 偵測 lock 自己隔離。沒有 session 會 retroactively 搬 tree。
- **idle ≠ done 被繞過**：later session **不等** holder 結束——它立刻隔離。Lock 只回答「此 tree 還有別的 live session 嗎」，由 liveness 回收，從不由「做完了嗎」回收（這次 ai_martech incident 的 watcher 證明 process-quiet ≠ session-done）。
- **Release**：`idd-close` Step 6.8 釋放（holder-scoped + idempotent）；session 異常結束留下的 stale lock 由下一個 `acquire` 自動 reclaim。

**與 #184 的關係**：escalated session 會 branch+merge，放大了 orphan-commit 風險（branch 沒完整 merge 回 main）。所以 tree-lock 與 **#184 merge-completeness gate** 是配套——lock 防 FM-1（並行碰撞），#184 gate 防 FM-2（orphan）。fail-open 之所以安全，正因 #184 是正確性兜底。

**fixtures**：`scripts/tests/idd-tree-lock/test.sh`（acquire-race-one-winner / dead-PID-reclaim / live-PID-held / fail-open / holder-scoped-release）。

## See Also

- [`cross-repo-cwd.md`](cross-repo-cwd.md) — `--cwd` flag convention；worktree 路徑就是餵給 `--cwd` 的值，本 doc 是它的一個 application
- [`pr-flow.md`](pr-flow.md) — PR vs direct-commit path resolution；每個平行 worktree 各自獨立解析 PR path
- [`chain-flow.md`](chain-flow.md) — sequential `/idd-all-chain` 的 cluster-PR 機制；本 doc 的 fan-out convergence 的相反側
