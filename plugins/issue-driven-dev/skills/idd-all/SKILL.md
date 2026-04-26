---
name: idd-all
description: |
  自動串連 IDD 完整 workflow（issue → diagnose → implement → verify），在 feature branch 開 PR，停在 verified 等 user merge + close。
  Use when: 想一次跑完整條 IDD pipeline、信任 6-AI verify 會抓錯、希望 fire-and-forget。
  防止的失敗：手動跑 5 個 idd-* skill 太繁瑣、忘記中間某一步、orchestration 一致性。
argument-hint: "[#NNN | 'issue description'] (empty = interactive)"
allowed-tools:
  - Bash(gh:*)
  - Bash(git:*)
  - Bash(grep:*)
  - Bash(find:*)
  - Read
  - Glob
  - Grep
  - AskUserQuestion
  - Skill
---

# /idd-all — 自動 IDD Pipeline

把 idd-issue → idd-diagnose → idd-implement → idd-verify 串成一條自動跑的鏈，所有 commit 在 feature branch，最後開 PR。停在 verified 讓 user 親自 merge + /idd-close。

## 核心原則

> Orchestrator skill 的 contract:**自動化便利不能犧牲安全**。
>
> - **Unattended assumption**: idd-all 假設整條 pipeline 跑完都沒有 user 在旁邊。所有 sub-skill 呼叫都必須在 args 裡傳 unattended hint,**override sub-skill 的 attended-by-default AskUserQuestion checkpoint**。包含 SDD path:`spectra-discuss` 不停下對話、`spectra-propose` 不問 Park/Apply、`spectra-apply` 不問 continue。Sub-skill 預設 attended 是它們在 solo 用法的合理選擇 — orchestrator 用 args 覆蓋是 idd-all 的責任,不該去改 sub-skill plugin。
> - **Always PR path**: idd-all 強制走 PR path(等同 `idd-implement --pr`),覆蓋 `pr_policy` config。理由:orchestrator 一鍵跑完整條 pipeline,沒有 user 在每個 commit 攔下來檢查;PR review 是 batch 的人類 checkpoint。完整 path contract 見 [pr-flow.md](../../references/pr-flow.md)。
> - **Branch isolation**:所有 commits 在 feature branch,`main` 永遠乾淨。
> - **PR as checkpoint**:user 透過 review PR 一次看完所有 diff + verify report。
> - **Stop before close**:idd-all 永遠停在 verified,close 動作必須 user 主動觸發(保留 closing summary 的人類驗收)。
> - **Fail-safe escalation**:遇到 ambiguity 寧可 abort,絕不亂猜 — 但 SDD path 預設是「文件化 assumption 後繼續」(見 Phase 3b),不是 abort。Abort 是最後手段。

## 與其他 idd-* skills 的關係

| Skill | 模式 | 用途 |
|-------|------|------|
| `idd-issue/diagnose/implement/verify/close` | Atomic — 手動逐步 | 細緻控制、需要中途插手 |
| **`idd-all`** | **Orchestrator — 一鍵跑完** | 信任 pipeline、想 fire-and-forget |

idd-all 不取代 atomic skills,而是包它們。每個 phase 仍透過 `Skill(skill=...)` 呼叫對應的 atomic skill,所有 sub-skill 的 stage TaskList、auto-update、IDD 紀律都繼承下來。

## Configuration

從 `.claude/issue-driven-dev.local.md` frontmatter 讀 `github_repo`。如不存在,呼叫 `idd-issue` 流程會自動處理。

## Execution

### Step 0: Bootstrap Stage Task List(強制)

**動任何事之前**先用 `TaskCreate` 建 stage-level todo list:

```
TaskCreate(name="preflight", description="Phase 0: 檢查 git clean / gh auth / 解析 args / 建 feature branch")
TaskCreate(name="ensure_issue", description="Phase 1: 若 from-scratch 則跑 idd-issue; from-issue 則 verify issue 存在")
TaskCreate(name="diagnose", description="Phase 2: 跑 idd-diagnose,讀回 complexity 判定")
TaskCreate(name="implement_or_sdd", description="Phase 3: Simple → idd-implement --pr; SDD → spectra-discuss → spectra-propose → spectra-apply (chained, unattended)")
TaskCreate(name="verify_loop", description="Phase 4: idd-verify; blocking findings 自動修復(最多 2 round); follow-ups → 開新 issue")
TaskCreate(name="open_pr", description="Phase 5: git push + gh pr create(body 含 Refs #N, 不含 Closes)")
TaskCreate(name="report_and_stop", description="Phase 6: 顯示 PR URL + 提示 user 可 merge 後跑 /idd-close")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。

`idd-all` 內部呼叫的 atomic skill 會各自建自己的 stage TaskList(那是它們的責任),idd-all 的 task list 只追 phase-level 進度。

---

### Phase 0: Pre-flight Checks

#### Step 0.1: Argument Parsing

| 輸入 | Mode | 行為 |
|------|------|------|
| `/idd-all` | interactive | AskUserQuestion: 建新 issue 還是用既有 issue? |
| `/idd-all #19` | from-issue | 直接從 #19 進 diagnose |
| `/idd-all "bug: foo doesn't work"` | from-scratch | 用該字串當 issue title 進 idd-issue |
| `/idd-all path/to/spec.md` | from-scratch | 把檔案當 issue 描述進 idd-issue |

#### Step 0.2: Hard pre-flight gates

任何一項失敗就 abort,顯示具體訊息讓 user 修。

```bash
# 1. 必須在 git repo
git rev-parse --git-dir > /dev/null 2>&1 || abort "Not in a git repository."

# 2. 必須 gh auth
gh auth status > /dev/null 2>&1 || abort "gh CLI not authenticated. Run: gh auth login"

# 3. Working tree 必須乾淨(由設計決策 #1 決定:Abort,不 stash)
if [ -n "$(git status --porcelain)" ]; then
    echo "Uncommitted changes detected. idd-all needs a clean working tree."
    git status --short
    abort "Run 'git stash' or 'git commit' first, then re-run /idd-all."
fi

# 4. 必須在 main / master / 預設 branch(避免從另一個 feature branch 起跳)
CURRENT=$(git branch --show-current)
DEFAULT=$(gh repo view --json defaultBranchRef -q .defaultBranchRef.name)
if [ "$CURRENT" != "$DEFAULT" ]; then
    abort "Currently on '$CURRENT'. idd-all must start from '$DEFAULT'. Run: git checkout $DEFAULT"
fi
```

#### Step 0.3: Resolve Issue Number

- **from-issue mode**(`/idd-all #19`): 確認 issue #19 存在且 OPEN(`gh issue view 19 --json state -q .state`); 若 state=CLOSED → abort
- **from-scratch mode**: skip 到 Phase 1 跑 idd-issue
- **interactive mode**: AskUserQuestion 兩選一

#### Step 0.4: Create Feature Branch

決策 #2 已選定命名規則:`idd/{N}-{slug}`

```bash
N="19"  # 從 args 或 idd-issue 結果取得
TITLE=$(gh issue view "$N" --json title -q .title)
SLUG=$(echo "$TITLE" | tr '[:upper:]' '[:lower:]' \
    | sed 's/[^a-z0-9]/-/g' | sed 's/--*/-/g' | sed 's/^-\|-$//g' \
    | cut -c1-40)
BRANCH="idd/${N}-${SLUG}"

# 若 branch 已存在 → AskUserQuestion(continue 還是建 -2 suffix)
if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
    # 詢問:該 branch 已存在,要 checkout 繼續 or 用 idd/19-...-2?
    # 預設 default 不 auto-pick,因為這是 user state edge case
fi

git checkout -b "$BRANCH"
```

> **為什麼從 default branch 起跳**:idd-all 假設 issue 是針對 main 的工作。如果 user 已經在 feature branch 上要做 idd-all,代表他們在做 nested feature work,這不是 idd-all 的設計使用情境 — 應該 abort 讓 user 想清楚。

---

### Phase 1: Ensure Issue Exists

```
if [ from-scratch mode ]:
    Skill(skill="issue-driven-dev:idd-issue", args="<arg from /idd-all>")
    # idd-issue 會 post issue 並 print 出 number → capture 它
    N = parse from idd-issue output
elif [ from-issue mode ]:
    # already validated in Phase 0.3
    pass
```

---

### Phase 2: Diagnose

```
Skill(skill="issue-driven-dev:idd-diagnose", args="#$N")
```

**讀回 complexity**:idd-diagnose 結束後 fetch issue comments,grep 最新 `## Diagnosis` 區塊的 `### Complexity` 欄位:

```bash
COMPLEXITY=$(gh issue view "$N" --json comments \
    | python3 -c "
import json, sys, re
d = json.load(sys.stdin)
diagnosis_comments = [c for c in d['comments'] if '## Diagnosis' in c['body']]
if not diagnosis_comments:
    print('UNKNOWN'); exit(0)
latest = diagnosis_comments[-1]['body']
m = re.search(r'### Complexity\n(.+?)\n', latest)
print(m.group(1).strip() if m else 'UNKNOWN')
")
```

| Complexity 值 | 下一步 |
|--------------|--------|
| `Simple` | Phase 3a: idd-implement |
| `SDD-warranted` | Phase 3b: spectra-discuss → spectra-propose → spectra-apply (unattended chain) |
| `UNKNOWN` | **abort** — diagnose 沒判定 complexity,user 需手動釐清 |

> **SDD path 是 unattended 的**(v2.28.0+):idd-all 的 contract 是 fire-and-forget,所以 SDD path 也必須跑完整條 — 不停在 discuss 等對齊、不停在 propose 等 Park/Apply 抉擇。每個 spectra-* 呼叫都帶 explicit unattended hint(見 Phase 3b),sub-skill 看到 hint 就知道抑制 AskUserQuestion。如果 user 想要 attended SDD discussion,**不該**用 `idd-all` — 該用 `idd-diagnose` 後手動 `/spectra-discuss` + `/spectra-propose` + `/spectra-apply`。

---

### Phase 3a: Simple Path — idd-implement

```
Skill(skill="issue-driven-dev:idd-implement", args="#$N --pr")
```

**`--pr` flag is mandatory** — orchestrator path always = PR path (覆蓋 user 的 `pr_policy` config)。不傳 `--pr` 會讓 idd-implement 走 config / fork detection,結果可能不一致。

idd-implement 會在 feature branch(由 Phase 0.4 建好的)上做所有 commit,因為已經 checkout 在 feature branch 上,Step 0.5 fork detection 會看到非 default branch + `--pr` flag,直接 reuse 當前 branch 不再 checkout。已自帶 strategy-level TaskList + scope guard,idd-all 不重複。

**Phase 5.5 PR creation idempotency**: idd-implement 的 Step 5.5(PR creation)用 `gh pr list --head $BRANCH` 先查當前 branch 有沒有 open PR,有就 skip。idd-all 不需要傳特殊 flag — 兩個流程自然相容:

- **idd-all 流程**: Phase 5(後面)會在 verify PASS 後 `gh pr create` 開 PR(含 verify result)。idd-implement 結束時 branch 還沒 PR,所以 Step 5.5 會嘗試開 — 但若 idd-all 設計成「先 verify 再開 PR」,可在 Phase 0.5 預先 `git push -u`(無 PR),這樣 idd-implement Step 5.5 看到 push 過但無 PR → 自己開了基礎 PR(body 簡版),Phase 5 再 `gh pr edit` 補 verify result。
- **手動 standalone**: idd-implement 開 basic PR,user 自己跑 `idd-verify` + 手動 update PR body。

### Phase 3b: SDD Path — discuss → propose → apply (unattended chain)

idd-all 走 SDD path 時,**必須**串完三步:`spectra-discuss` → `spectra-propose` → `spectra-apply`。每步都用 args 傳 **unattended mode hint**,明確抑制 sub-skill 內建的 `AskUserQuestion` confirmation 點。

> **為什麼三步都要明文 unattended hint**:
> - `spectra-discuss` 預設「one question at a time」對話節奏 — 在 idd-all 裡會卡住
> - `spectra-propose` Step 10 預設用 AskUserQuestion 問「Park or Apply」並 default 選 Park — idd-all 不該被 park 起來
> - `spectra-propose` 還有禁令 `NEVER invoke /spectra-apply`(L267) — 所以**idd-all 必須自己**接著呼叫 `spectra-apply`,不能依賴 propose 自串
> - `spectra-apply` Step 4 有 continue-confirmation — 也要抑制
>
> idd-all 不修改 spectra 任何檔案 — 全程用 args 傳指示 override sub-skill 的 attended 預設。

#### Step 3b.1: Capture issue context for prompt

```bash
ISSUE_TITLE=$(gh issue view "$N" --repo "$GITHUB_REPO" --json title -q .title)
ISSUE_BODY=$(gh issue view "$N" --repo "$GITHUB_REPO" --json body -q .body | head -50)
DIAGNOSIS=$(gh issue view "$N" --repo "$GITHUB_REPO" --json comments \
    | python3 -c "import json,sys; cs=json.load(sys.stdin)['comments']; \
        ds=[c for c in cs if '## Diagnosis' in c['body']]; \
        print(ds[-1]['body'] if ds else '')")
```

#### Step 3b.2: Discuss (converge in one round)

```
Skill(
  skill="spectra-discuss",
  args="""Topic: ${ISSUE_TITLE} (#${N})

Context (from issue body + diagnosis):
${ISSUE_BODY}
${DIAGNOSIS}

UNATTENDED MODE — called by /idd-all orchestrator.

Discipline overrides for this invocation:
- Converge in ONE round. Do NOT use AskUserQuestion to pace the discussion across multiple turns.
- If you have a strong recommendation among 2-3 options, pick it and state your reasoning.
- If multiple viable approaches exist, choose the one with the smallest blast radius and document the trade-off.
- End your output with a single line: 'Conclusion: <chosen approach in one sentence>' so the orchestrator can pass it to spectra-propose.
- Do NOT pause to ask the user — there is no user available.
"""
)
```

Capture the conclusion line for the next step.

#### Step 3b.3: Propose (suppress Park/Apply confirmation)

```
Skill(
  skill="spectra-propose",
  args="""<conclusion line from Step 3b.2>

Original issue: #${N} ${ISSUE_TITLE}

UNATTENDED MODE — called by /idd-all orchestrator.

Discipline overrides for this invocation:
- Skip ALL AskUserQuestion checkpoints. Make reasonable decisions and document them inline in the proposal/design artifacts.
- Step 10 'Park or Apply' question: SUPPRESS. Do NOT call spectra park. Do NOT call /spectra-apply (your guardrail at L267 still applies). Just end the workflow after artifact validation succeeds.
- If a 'plan file' check (Step 1.x) finds an existing plan, use it without asking.
- If context is insufficient, prefer making a documented assumption over asking — write the assumption explicitly in proposal.md so it can be challenged later.
- Output the final change-name on its own line as 'Change: <name>' so the orchestrator can pass it to spectra-apply.
"""
)
```

Capture the change-name line.

#### Step 3b.4: Apply (suppress continue-confirmation)

```
Skill(
  skill="spectra-apply",
  args="""<change-name from Step 3b.3>

Issue ref: #${N}

UNATTENDED MODE — called by /idd-all orchestrator.

Discipline overrides for this invocation:
- Skip Step 4 continue-confirmation. Proceed directly through implementation tasks.
- If validation reveals ambiguity that would normally trigger AskUserQuestion: document the assumption in tasks.md (mark with 'ASSUMPTION:'), proceed with the most conservative interpretation, and surface it in the verify phase.
- Every commit MUST reference (#${N}) — same convention as idd-implement.
- All commits land on the feature branch from Phase 0.4 ('${BRANCH}').
"""
)
```

#### Failure handling

| Situation | Action |
|---|---|
| `spectra-discuss` doesn't emit a `Conclusion:` line | Re-prompt once with explicit format requirement; if still missing, abort with branch preserved |
| `spectra-propose` doesn't emit a `Change:` line | Same as above |
| `spectra-propose` hits a hard stop (e.g. spec validation fail it can't auto-fix) | Abort, preserve artifacts, instruct user to run `/spectra-propose` manually |
| `spectra-apply` reports tasks remaining unfinished | Continue to Phase 4 (verify) — verify will surface incompleteness |

> **Why idd-all overrides spectra defaults via args, not by modifying spectra**: spectra is a separate plugin with its own attended-by-default contract that's correct for solo use. idd-all is the one promising "unattended", so it's idd-all's responsibility to configure each sub-skill invocation to honor that promise. Args-based override keeps the boundary clean.

---

### Phase 4: Verify Loop(最多 2 round)

```python
for round in 1..2:
    Skill(skill="issue-driven-dev:idd-verify", args="#$N")

    findings = parse_verify_report(latest verify comment)

    if findings.blocking_count == 0:
        break  # PASS

    if round == 2:
        abort_with_message("verify still failing after 2 rounds; manual intervention needed")

    # round 1 → auto-fix attempt(設計決策 #3)
    attempt_auto_fix(findings.blocking)
```

**Auto-fix 策略**(設計決策 #3:best-effort):

對每個 blocking finding,讀其描述 + suggested action,套用 Edit/Write 修正:

- 文法/拼字/字串 typo → 安全可修
- 邏輯錯誤(null check, edge case) → 嘗試但 risky
- 安全漏洞 → **不 auto-fix**,直接 abort 讓 user 處理

每個 auto-fix commit:`fix: address verify finding — {finding summary} (#$N)`

**Follow-up findings**(設計決策 #4:auto-create issues):

每個 P3/follow-up finding → 呼叫 `Skill(skill="issue-driven-dev:idd-issue")` 建新 issue,body 引用本次 verify report 原文。新 issue target main(不是當前 branch)。

---

### Phase 5: Open PR

```bash
git push -u origin "$BRANCH"

# 組 PR body
PR_BODY=$(cat <<EOF
Refs #${N}

## Summary
{從 issue title + diagnosis 的 Strategy 摘要}

## Verification
6-AI cross-model verification PASS(Agent Team + Codex xhigh)。詳見 issue #${N} 的 Verify comment。

## Checklist
- [x] Diagnose ✓
- [x] Implement(${COMMIT_COUNT} commits)
- [x] Verify ✓
- [ ] **Pending: human review of this PR + /idd-close after merge**

## Related
{若有 follow-up issues,列出 #N #M ...}

---
🤖 Generated by /idd-all. **Do NOT add 'Closes #${N}'** — IDD discipline requires manual /idd-close after merge to enforce checklist gate + closing summary.
EOF
)

gh pr create --title "$PR_TITLE" --body "$PR_BODY" --base "$DEFAULT" --head "$BRANCH"
```

> **絕對不能在 PR body 用 Closes/Fixes/Resolves trailer**(設計決策 #3:不包含)。理由見 idd-implement skill 裡的 trailer 禁令說明 — auto-close 會繞過 idd-close 的 checklist gate 和 closing summary。

---

### Phase 6: Report and Stop

```
✓ idd-all complete

  Issue:        #${N} — ${TITLE}
  Branch:       ${BRANCH}
  Commits:      ${COMMIT_COUNT} (implementation + ${FIX_ROUND_COUNT} verify-fix rounds)
  PR:           ${PR_URL}
  Verify:       PASS (6-AI cross-model)
  Follow-ups:   ${FOLLOWUP_ISSUE_LIST or "(none)"}

Next steps (manual):
  1. Review PR ${PR_URL}
  2. Merge if approved
  3. Run /issue-driven-dev:idd-close #${N} to post closing summary and close issue
```

**STOP**。不 auto-merge,不 auto-close。user 可能想看 PR diff、跑 CI、找其他人 review。

---

## Failure Modes(每個都該明確 abort,不該 swallow)

| 情況 | 行為 |
|------|------|
| Working tree dirty | Phase 0 abort,顯示 git status |
| Not on default branch | Phase 0 abort,提示 git checkout |
| gh auth 沒設定 | Phase 0 abort,提示 gh auth login |
| Issue #N 不存在 / CLOSED | Phase 0 abort |
| Branch 已存在 | Phase 0 AskUserQuestion(checkout / -2 suffix / abort) |
| Diagnose 判定 UNKNOWN complexity | Phase 2 abort,提示手動跑 idd-diagnose |
| spectra-discuss 沒 emit `Conclusion:` line(unattended hint 失敗)| Re-prompt 一次;再失敗 abort,branch 保留 |
| spectra-propose 沒 emit `Change:` line | 同上 |
| spectra-propose 遇到 unrecoverable validation error | Phase 3b abort,artifacts 保留,提示手動 `/spectra-propose` |
| spectra-apply 留下 unfinished tasks | 不 abort — Phase 4 verify 會抓出來 |
| Verify 2 round 後仍 blocking | Phase 4 abort,留 branch 給 user 手動修 |
| `gh pr create` fail | Phase 5 abort,branch 已 push,提示手動開 PR |

abort 時:
- TaskList 標記當前 phase 為 in_progress(不要 mark completed)
- 顯示「自己手動接手」的具體命令(例:`/idd-verify #19` 或 `gh pr create ...`)
- branch 不刪除(保留進度,user 可繼續)

---

## 鐵律

- **永遠在 feature branch**。idd-all 的存在意義就是 main isolation。
- **永遠停在 verified**。close 是人類 checkpoint(closing summary 含 root cause + solution + verification trail,該由人寫不該由機器猜)。
- **永遠不 auto-merge PR**。即使 verify PASS,PR review 是另一層保險(CI、其他 reviewer、user 自己再看一次)。
- **abort 比硬撐好**。任何 ambiguity → 停下、留 branch、告訴 user 怎麼接手。

## Examples

### 用既有 issue 跑全自動

```
/idd-all #42
```

從 main 開 `idd/42-fix-auth-bug` branch → diagnose → implement → verify(若 1 round 不過自動再 1 round) → push → 開 PR → 顯示 PR URL → STOP。

### 從零開始 — 文字描述

```
/idd-all "bug: login button stops responding after 3 failed attempts"
```

跑 idd-issue 建 issue #N → 從 main 開 `idd/N-login-button-stops-responding` branch → diagnose → implement → verify → PR → STOP。

### 從零開始 — 用 spec 檔

```
/idd-all docs/specs/new-feature.md
```

把 spec 內容當 issue body 跑 idd-issue → 後續同上。

---

## Auto-Update

每個 sub-skill(idd-issue / idd-diagnose / idd-implement / idd-verify)在自己的 Step N Auto-Update 都會跑 idd-update,所以 issue body 的 Current Status 會在每個 phase 後自動 sync。idd-all 不需要額外 update。

## Next Step

idd-all 結束後,user 接手:

```bash
# 1. Review PR
gh pr view <PR_URL>

# 2. Merge(approve 後)
gh pr merge <N> --squash  # or --merge / --rebase

# 3. Close issue with summary
/issue-driven-dev:idd-close #${N}
```
