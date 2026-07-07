---
name: idd-diagnose
description: |
  對照 GitHub Issue 找 root cause（bug）或分析需求（feature/refactor）。
  輸出 diagnosis report：原因、影響範圍、修復/實作策略。
  支援 batch mode（v2.34.0+）：多個 #N 依序跑（如 `#34 #36 #38`），各自 post diagnosis comment。
  Use when: issue 建立後、開始寫 code 之前。
  防止的失敗：修了表象，沒修根本原因。
argument-hint: "#issue [#issue ...] [--cwd /path/to/clone] e.g. '#42' or '#34 #36 #38' (batch)"
allowed-tools:
  - Bash(gh:*)
  - Bash(git:*)
  - Bash(grep:*)
  - Bash(find:*)
  - Read
  - Glob
  - Grep
  - AskUserQuestion
---

# /diagnose — 理解問題

在寫任何一行 code 之前，先確認你真的理解問題。

## Batch mode（v2.34.0+）

`idd-diagnose #34 #36 #38` 對 3 個 issue **依序**跑完整 diagnose 流程（每個 issue 各自 post diagnosis comment + auto-update phase）。語意同單一 issue，只是包了一層 loop。完整契約見 [batch-and-cluster.md](../../references/batch-and-cluster.md)。

Aggregate report 在最後輸出（每個 issue 的 complexity 判定 + comment URL）。Per-issue abort 不停 batch — 失敗的 issue 標 `aborted` 在 report 裡，使用者個別處理。

## 核心原則

> 不理解問題就動手 = 修表象。修表象 = 問題會回來。

## Cross-repo invocation（v2.40.0+）

支援 `--cwd /path/to/local/clone` flag,讓 diagnose 在指定 local clone 上跑(不依賴 Claude Code session cwd)。Step 0 解析 `--cwd` 後,後續所有 `git`/`gh` 命令依 [`references/cross-repo-cwd.md`](../../references/cross-repo-cwd.md) 的 substitution rule 改寫:

- `git X` → `git -C "$CWD" X`
- `gh issue/pr/repo X` → `gh ... X -R "$GITHUB_REPO"`

完整 algorithm + 失敗模式見 reference 文件。**本 skill 內所有 bash 範例為 cwd-only 寫法以保持可讀性,執行時請套用 substitution rule。**

## Configuration

按 [config-protocol](../../references/config-protocol.md) 解析 target repo:

- `--repo owner/repo` flag → per-invocation override
- Walk-up `.claude/issue-driven-dev.local.json`(從 cwd 往上找)
- Path / git predicates 自動匹配

**Group/predicate 行為**:`idd-diagnose` 操作既存 issue,只用 path/git 類 predicate。Group config 會 fall through 到 primary repo。

## Execution

### Step 0: Bootstrap Stage Task List（強制)

**在動任何事之前**先用 `TaskCreate` 為這個 stage 建 todo list:

```
TaskCreate(name="read_issue", description="gh issue view #NNN 讀 title/body/labels/comments")
TaskCreate(name="clarity_gate_check", description="Step 0.5 (v2.71.0+, #135): grep issue body for ### Clarity Surface unresolved rows; refuse if any per IC clarity axis hard-refuse rule (类比 PR Gate Check / idd-all-chain #119); backward compat: silent proceed if block absent (legacy pre-v2.71.0 issue)")
TaskCreate(name="download_attachments", description="偵測 issue body/comments 的 attachment URL 全部下載到 .claude/.idd/attachments/issue-NNN/,寫 _manifest.json,parse(MCP-first: che-word-mcp / che-pdf-mcp / Read for images)。依 rules/process-attachments.md。忽略附件 = 忽略來源,違反鐵律。")
TaskCreate(name="diagnose_by_type", description="依 issue type 做診斷: bug→RCA / feature→需求分析 / refactor→現狀分析 / docs→敘述性審查 / meeting→Phase A/B/C 審議 Strategy（見 Step 3 meeting-adapted Diagnosis）")
TaskCreate(name="post_diagnosis_report", description="產出 Diagnosis Report 並 comment 到 issue(非只在對話中顯示)")
TaskCreate(name="vagueness_precheck", description="Step 3.4 (v2.50+): Layer V Vagueness Pre-check — 用 .claude/rules/attribute-assessment.md 的 6-point Likert anchors 評 V1 + V4,trigger ≥ 4 跳 Hybrid 3-option (clarify/proceed/escalate),audit trail PATCH 到 Diagnosis comment。Unattended mode 自動 proceed + audit trail。#57: type=meeting 直接短路跳過整個 Layer V,不評 V1/V4")
TaskCreate(name="complexity_assessment", description="Step 3.5: meeting-first 7-step routing 判定 Simple / Plan / Spectra(或 meeting 分支)並寫入 report 的 Complexity 欄位。序列: (1) type=meeting → (2) Layer 1 → (3) Layer V → (4) Spectra → (5) #129 硬閘 → (6) Layer P → (7) Simple 預設(v2.36+ Spectra rename;v2.50+ Layer V;#129 硬閘 + #57 meeting 分支)")
TaskCreate(name="sister_concern_surfacing", description="Step 3.6: re-read posted Diagnosis content + scout session log for sister-concern markers (也有 / sister / 同樣的 / 另外 / etc); per IC_R011 file-by-default (v2.72.0+, see references/ic-r011-checkpoint.md §1.1); PATCH Diagnosis comment with `### Sister Concerns Filed` audit trail (per IC_R011 #528)")
TaskCreate(name="confirm_and_route", description="與使用者確認診斷正確,依 complexity 顯示下一步命令")
TaskCreate(name="auto_update_body", description="Step 5: 跑 /idd-update #NNN 同步 issue body Current Status phase → diagnosed（強制，常被漏；同 idd-close 2.18.1 模式）")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。**TaskCreate 清單 = 真實的步驟清單；任何寫在 skill 裡但沒列進 TaskCreate 的步驟，都視為 skill 的 bug，必須補進 Task 清單。**

特別提醒:**`post_diagnosis_report` 必須 comment 到 GitHub**,不是只在對話中回答。歷史上多次看到「診斷完但忘了 comment」→ 下次回來看不到脈絡。**`auto_update_body` 同樣常被漏跑** — 跟 idd-close 2.18.0 同樣的坑（narrative Auto-Update section 沒被升成強制 step），於 2.18.1 修正 idd-close、本次（2.19.0）一併修 idd-diagnose。

**v2.32.0+ tagging 規則**：若 diagnosis comment 中要 @-tag 任何人（例如要通知 owner 看 root cause），**必須**遵循 [`rules/tagging-collaborators.md`](../../rules/tagging-collaborators.md) 5 步協定（gh api → fuzzy match → AskUserQuestion fallback → @login 不用 display name → post 前 verify）。違反 = 通知錯人，不可逆。

---

### Step 0.5: Clarity Surface PR Gate (v2.71.0+, PsychQuant/issue-driven-development#135)

**Compliance**: this step implements the **third IDD quality axis**(terminology / semantic accuracy)gate per `/idd-clarify` composable primitive design。Per design D2, gate strength is **hard refuse**(類比 PR Gate Check in `idd-close` Step 1.5 + fail-fast in `idd-all-chain` #119)。

**Why this gate exists**:`idd-diagnose` 預設 issue 已 framed correctly,只做 routing + complexity。若 source 用詞有誤 / 隱含 missing-context,diagnose chain 繼承錯誤越走越歪。Step 0.5 gate 強制 user 在 diagnose 之前先處理 `### Clarity Surface` annotation block 內的 surfaced rows(per `/idd-clarify` skill output schema)。

**Rule (SHALL, hard refuse + reason-pattern accept)**:

`(category: state-field-update, scope: gate condition relaxation per #150 Path C pattern + #137 reason-pattern accept)` per [`rules/append-vs-modify.md`](../../rules/append-vs-modify.md)。 Reason literal cited from [Reason pattern registry](../../rules/append-vs-modify.md#reason-pattern-registry) — strict literal `unattended-auto-Step-4.6-deferred`(dot-escaped regex `^unattended-auto-Step-4\.6-deferred$`,case-sensitive)。

```bash
# Read issue body
BODY=$(gh issue view $NUMBER --repo $GITHUB_REPO --json body --jq '.body')

# Strip ``` fenced code blocks BEFORE scanning (#181). A `### Clarity Surface` that only
# appears INSIDE a code fence — an issue that documents / illustrates the annotation format
# (like #181 itself, or #178) — is NOT a real annotation block and must not trip the gate.
# Mirrors idd-list Step 3.5 strip_fenced_code() (#14): the awk toggles `infence` on any line
# whose first non-space chars are ``` and prints only out-of-fence lines; inline `code` is
# left alone (rarer false positive). NOTE the ``` in the awk regex stays MID-line on purpose
# (the line starts with BODY_SCAN=) so it does not close THIS markdown ```bash fence.
BODY_SCAN=$(printf '%s\n' "$BODY" | awk '/^[[:space:]]*```/{infence=!infence; next} !infence{print}')

# Look for ### Clarity Surface block (scan the fence-stripped body)
if echo "$BODY_SCAN" | grep -q '^### Clarity Surface'; then
  # Extract block + count surfaced rows
  # NOTE (v2.74.1+, #137 verify R1 fix): naive `awk '/^### Clarity Surface/,/^### /'`
  # collapses on line 1 because start regex matches end regex (both `^### `),
  # losing all rows. Use flag-based pattern instead — also removes GNU-only
  # `head -n -1` dependency (errors on BSD/macOS).
  BLOCK=$(echo "$BODY_SCAN" | awk '/^### Clarity Surface/{flag=1; print; next} flag && /^### /{flag=0} flag')
  SURFACED_COUNT=$(echo "$BLOCK" | grep -cE '\| surfaced \|')

  # v2.74.0+ #137 — per-row reason-pattern scan for deferred rows:
  # Reason literal cite registered in rules/append-vs-modify.md § Reason pattern registry
  # Strict regex (dot-escaped) — `unattended-auto-Step-4.6-deferred` is the registered literal
  DEFERRED_TOTAL=$(echo "$BLOCK" | grep -cE '\| deferred \|')
  DEFERRED_AUTO=$(echo "$BLOCK" | grep -cE '\| deferred \| unattended-auto-Step-4\.6-deferred \|')
  DEFERRED_LEGACY=$((DEFERRED_TOTAL - DEFERRED_AUTO))

  # Legacy deferred (no reason match, or non-registry-cited reason) → block as before
  TOTAL_UNRESOLVED=$((SURFACED_COUNT + DEFERRED_LEGACY))

  if [ "$TOTAL_UNRESOLVED" -gt 0 ]; then
    cat <<EOF >&2
✗ Step 0.5: Clarity Surface gate refuse — Issue #$NUMBER has $TOTAL_UNRESOLVED unresolved rows.

Surfaced rows: $SURFACED_COUNT
Deferred rows (legacy / non-registry reason): $DEFERRED_LEGACY (REFUSE; need manual /idd-clarify)
Deferred rows (unattended-auto, registry-cited): $DEFERRED_AUTO (PROCEED-with-warn)

Resolve via:
  - /idd-clarify #$NUMBER --status resolved=<idx>,<reason>
  - /idd-clarify #$NUMBER --status dismissed=<idx>,<reason>
  - LINE/email domain expert and update issue body manually

Then re-run /idd-diagnose #$NUMBER.
EOF
    exit 1
  fi

  # Auto-deferred rows: PROCEED with warn audit (per #137)
  if [ "$DEFERRED_AUTO" -gt 0 ]; then
    echo "[Step 0.5] $DEFERRED_AUTO row(s) auto-deferred under unattended mode (reason: unattended-auto-Step-4.6-deferred) — proceeding with warn (per #137 / spec idd-diagnose-clarity-gate). Manual /idd-clarify follow-up surfaced in /idd-all Phase 6 final report Action items section." >&2
  fi
fi

# Backward compat: legacy issues with no ### Clarity Surface block
# (filed before v2.71.0 plugin version — silently proceed). Uses BODY_SCAN so a body whose
# only `### Clarity Surface` is inside a code fence is correctly treated as "no block" (#181).
if ! echo "$BODY_SCAN" | grep -q '^### Clarity Surface'; then
  echo "[Step 0.5] no Clarity Surface block found (legacy issue — pre-v2.71.0). Proceeding to Step 1."
fi

# Passed marker rows (no surfaced/deferred) → proceed normally
```

**Behavior scenarios**(per spec `idd-diagnose-clarity-gate`):

| Body state | Step 0.5 action |
|---|---|
| Has block with ≥1 `surfaced` row | REFUSE + actionable message |
| Has block with ≥1 `deferred` row (no reason / legacy reason / non-registry-cited reason) | REFUSE + retry hint message (clarify-failed / manual defer cases) |
| Has block with ≥1 `deferred` row reason = `unattended-auto-Step-4.6-deferred` (v2.74.0+, #137) | PROCEED-with-warn (emit audit line to stderr; `/idd-all` Phase 6 Action items section surfaces for human review) |
| Has block, all rows `resolved` / `dismissed` / `passed` | PROCEED to Step 1 |
| No `### Clarity Surface` block(legacy pre-v2.71.0) | PROCEED with log line |

**Why hard refuse not warn-continue**:

- 同 `idd-close` Step 1.5 PR Gate Check precedent(unmerged PR exists → 拒 close 直到 user 處理 PR state)
- 同 `idd-all-chain` #119 reasoning:「fail-fast 強制 explicit choice,消除 silent partial-success」
- Warn-continue 會讓 `### Clarity Surface` annotation 被 silently ignored = 整個 `/idd-clarify` skill 沒用,違反 codify 初衷
- Dismiss 是 1-step 操作(`/idd-clarify #N --status dismissed=<idx>,<reason>`),refuse + easy-dismiss 等價於 explicit choice — 不擾人

**Unattended mode contract (v2.74.0+, #137)**:

`#137` 收斂為 Option D — reuse existing `deferred` enum + registry-cited reason literal `unattended-auto-Step-4.6-deferred`(see `rules/append-vs-modify.md` § Reason pattern registry)。

- `/idd-clarify` Step 4.8.A unattended detection → 寫 `deferred` rows with reason literal
- `/idd-diagnose` Step 0.5 gate(本 step)→ per-row reason scan,registry-cited → PROCEED-with-warn,non-registry → REFUSE(legacy backward-compat 保留)
- `/idd-all` Phase 6 final report → surface auto-deferred rows 到「Action items」section(per #137 Strategy)

完整 lifecycle 見 #137 closing summary;reason literal 集中 source 在 [Reason pattern registry](../../rules/append-vs-modify.md#reason-pattern-registry)。

完整 unattended decision space 待 #137 ship 後 codify(可能 options:auto-dismiss / hold-and-flag / hard-fail)。當前 implementation 走 hard-fail 預設,可由 #137 改進。

---

### Step 1: 讀取 Issue

```bash
gh issue view $NUMBER --repo $GITHUB_REPO --json title,body,labels,comments
```

識別 issue type：bug / feature / refactor / docs / meeting。（`meeting` = 使用者驅動的審議 / 決策 issue —— 在 Step 3.5 routing 最優先分流走 meeting Strategy，不進 code 複雜度評估）

**Type 解析順序（可機械判定；round-5 verify HIGH fix —— 支撐「type 是確定性欄位」的前提）**：`idd-issue` 建立時把 type 同時寫進 GitHub label（`--label <type>`）與 body 的 `## Type` heading。讀取優先序：(1) **GitHub label** 中的 type 值為主（`gh issue view --json labels`）；(2) label 無 type 時讀 body `## Type` heading；(3) 兩者衝突 → **label 勝**（label 是 idd-issue 的 canonical 寫入、且 filter/自動化以 label 為準）；(4) 兩者皆無 type 訊號 → 依內容推斷，**預設非 meeting**（meeting 需 explicit 標記，避免把一般 issue 誤判成 meeting 而跳過複雜度評估）。

### Step 1.5: 下載 Attachment(強制)

依 [`rules/process-attachments.md`](../../rules/process-attachments.md),helper script 處理機械工作:

```bash
IDD_CALLER=idd-diagnose bash $CLAUDE_PLUGIN_ROOT/scripts/process-attachments.sh download $NUMBER
```

Exit code:
- `0` — 下載完成(或 issue 無 attachment,empty manifest 已寫)
- `1` — 部分檔案下載失敗(error 條目已寫進 manifest,警告 surface 給使用者)
- `2` — usage / repo resolution 失敗

下載完成後 **必須** 用 MCP-first parser 讀檔案內容(由 Claude 而非 script 處理):

| 副檔名 | 工具 |
|--------|------|
| `.docx` | `che-word-mcp` MCP tool;fallback `pandoc -f docx -t markdown` |
| `.pdf` | `che-pdf-mcp` MCP tool;fallback `pdftotext` |
| `.png` / `.jpg` / 等圖片 | `Read` tool(多模態直讀) |

把 attachment 摘要納入 diagnosis 的 source-of-truth,在 Diagnosis Report 引用時用相對 path:`.claude/.idd/attachments/issue-NNN/檔名`。

**沒有 attachment** → script 寫空 manifest 後 exit 0,Diagnosis Report 標明「issue 無 attachment」。

**有 attachment 但 fetch 失敗** → script 把 error 條目寫進 manifest,Report 標明「attachment X 未能讀取,後續分析可能不完整」(禁止靜默)。

### Step 2: 依類型診斷

#### Bug → Root Cause Analysis（v2.90.0+ #209: superpowers delegation）

**Pre-flight（強制）** — per spec `superpowers-integration`「Dual pre-flight at delegation sites」：

```bash
"$CLAUDE_PLUGIN_ROOT/scripts/check-plugin-presence.sh" \
  claude-plugins-official superpowers systematic-debugging || exit 1
```

缺 plugin 或缺目標 skill → helper 印出含一步安裝指令（`claude plugin install superpowers@claude-plugins-official`）的錯誤，**立即 abort**。不做內建 fallback、不 silent degrade（#209 D2）。**注意（#209 F10 → #212 已解）**：pre-flight 現亦查 `claude plugin list --json` 的 enabled 狀態 — installed-but-disabled 會在 pre-flight 即 exit 3 並印一步 `claude plugin enable` 指令；claude CLI 缺席時 graceful degrade 回磁碟檢查（警告可見）。

**執行框架 = `superpowers:systematic-debugging`（canonical process source）**：invoke `Skill(skill="superpowers:systematic-debugging")`，依其紀律完成重現 → trace → 假設形成（一次一個假設、證據先於修法）。IDD 不再內嵌自己的 RCA 步驟敘述 — 除錯 process 以 superpowers 為 single source（#209 D3）。

**IDD wrapper 紀律（不 delegate）**：root cause 的產出仍寫入下方 Step 3 的 Diagnosis Report 模板並 comment 到 issue；證據引用 attachment 用 repo 相對 path；假設陳述格式「我認為 root cause 是 X，因為 Y」進 `### Root Cause / Analysis` 區段。

> **(Opt-in) 多子系統平行 fan-out（v2.83.0+, #182）**：當 root cause *橫跨 N 個獨立子系統 / 假設*（例如一個 code-gen contract + 一個 cache-invalidation footgun + 一個 sister-occurrence sweep），可選擇用 **Workflow tool** fan out — 每個子系統一個 read-only investigator 平行 trace，再用一個 synthesis agent 把 findings 併成單一 Diagnosis Report。**single-agent 仍是 default**（簡單 issue 不 fan out）。synthesis **必須引用 ≥2 個 investigator leg** 的 file 參照（fan-out 的價值正是 cross-leg 重新框定 —— 一個 leg 的 reads 會修正另一個的 framing）。high-stakes findings 可用 **adversarial-verify variant**：fan out N 個 skeptic 各自試圖 refute 一個假設、通過才進 report。opt-in only —— auto-detect「N 子系統」本身模糊、且 fan-out 乘上 token spend。**所有 fan-out agent（investigator / synthesis / skeptic）的 dispatch model 依 idd-verify 的解析規則顯式指定**（`IDD_AGENT_MODEL` else `opus`，非法值 fail-loud；#205——不指定會繼承 session main-loop model，高階 session 下重演 quota 撞牆）。契約見 [`references/parallel-orchestration.md`](../../references/parallel-orchestration.md)。

#### Feature → 需求分析

1. **拆解需求**
   - Issue 要求的每個功能點列出來
   - 模糊的地方標出來，詢問使用者

2. **影響範圍**
   - 需要改哪些檔案？
   - 有沒有既有的 pattern 可以參考？

3. **實作策略**
   - 有幾種做法？各自的 trade-off？
   - 推薦哪種？為什麼？

#### Refactor → 現狀分析

1. **為什麼要重構**
   - 現在的問題是什麼？（效能？可讀性？耦合？）

2. **風險評估**
   - 改動範圍多大？
   - 有沒有 test coverage 保護？
   - 有沒有隱藏的依賴？

3. **重構策略**
   - 一步到位還是漸進式？
   - 如何確保行為不變？

### Step 3: 輸出 Diagnosis Report

產生 diagnosis report 並 **comment 到 issue 底下**（預設行為）：

```markdown
## Diagnosis

### Type
{bug / feature / refactor / docs / meeting}

### Root Cause / Analysis
{bug: root cause + evidence}
{feature: requirements breakdown}
{refactor: current state + problems}

### Impact
- 影響的檔案：...
- 影響的使用者流程：...

### Strategy
{具體的修復 / 實作計畫}
- [ ] 改 A
- [ ] 改 B
- [ ] 加測試 C

### Conflict Class
{A_parallel_safe / B_resource_serialize / C_shared_module_coord / D_diagnose_first / E_verified_close}
{一行 justification；`B`/`C` 必須 named 出共享資源（DB / upload endpoint / submodule）}

### Complexity
{Simple / Plan / Spectra}
{如果 Plan，列出觸發的 Layer P 信號}
{如果 Spectra，列出 Layer 2 + Layer 3 觸發項}

### Risks
{可能出錯的地方}

### Residue
{NSQL §4.6 — issue 意圖中*無法 operationalize* 的部分（它的 purpose / horizon）。明確標記，不靜默丟棄。無殘留則寫 (none)}
```

```bash
gh issue comment $NUMBER --repo $GITHUB_REPO --body "$DIAGNOSIS_REPORT"
```

> **`type=meeting` 的 meeting-adapted Diagnosis（#57）**：當 issue type 是 `meeting` 時，`### Strategy` 段改用 **Phase A/B/C 審議模板**，**而非 code-centric 的 Files & Changes / Strategy checklist**（meeting 是使用者驅動的審議 / 決策工作，不是 TDD loop，emit code-centric 計畫沒有意義）。meeting Diagnosis 的 Strategy 段落格式：
>
> ```markdown
> ### Strategy (meeting deliberation)
> **Phase A（議程）** — 本次要談的議題清單
> - {議題 1} / {議題 2} …
> **Phase B（決策點）** — 需要拍板的決策 + 候選選項（可列舉時用 AskUserQuestion render）
> - {決策點 1：候選 A / B / C} …
> **Phase C（行動項）** — 每個決策對應的 follow-up action + owner
> - [ ] {action item 1} …
> ```
>
> meeting 分支在 Step 3.5 complexity scoring **之前分流**（**複雜度評估前分流**）—— meeting issue **不進 Layer 1 / Layer V / Spectra（Layer 2+3）/ 硬閘 / Layer P**，不產生 Simple / Plan / Spectra complexity verdict（見 Step 3.5「評估順序」的 meeting 分支）。closing 語意也不同（decision→action mapping，無 `/idd-verify` TDD pass；見 idd-close）。

> **數學公式格式**：GitHub 支援 `$...$`（inline）和 `$$...$$`（display）math mode。
> 含底線的程式變數名（如 `mse_info`）**不放進 math mode** — KaTeX 無法可靠渲染底線跳脫。
> 改用混合寫法：數學部分用 `$R_I = J \cdot$`，變數名用 backtick code `` `mse_info` ``。
> 純數學符號（$\theta$, $\hat{d}_J$ 等）放 math mode 沒問題。

> **為什麼 comment 到 issue？** Diagnosis 是 issue 的一部分 — 三個月後回來看，issue 裡就有完整的「問題 → 診斷 → 解法」脈絡，不用翻對話紀錄。

> **原文引用格式**：所有逐字引用的原文（使用者對話、老師回饋、文件段落）**必須**使用 blockquote（`>`）格式，與分析/解讀在視覺上明確區分。

> **`### Residue` 是什麼（v2.64.0+, #103）**：NSQL §4.6 的 residue —— issue 的意圖裡*無法被 operationalize* 的那部分（它的 purpose / horizon）。**跟 Layer V vagueness 不同**：Layer V = issue *不清楚*；residue = issue *清楚*，但它的部分意圖（為什麼要這個、要放進什麼脈絡看）本來就接不進 function/argument。標出來，不靜默丟掉 —— 誠實的縮減 ≠ 假裝完整。**無殘留時必填 `(none)`**；空著等於沒判斷,違反「明確標記」的本意。

> **`### Conflict Class` 是什麼（v2.83.0+, #182）**：給 `idd-all` 的 multi-issue batch mode 消費的「實作時碰到的物理資源」分類（conflict-class discipline），五選一 —— `A_parallel_safe`（獨立檔案編輯、無共享 mutable 資源）/ `B_resource_serialize`（單寫者資源：DB lock、serial upload、external queue）/ `C_shared_module_coord`（共享 submodule / vendored dep）/ `D_diagnose_first`（scope 未明，須先讀）/ `E_verified_close`（已完成、只需 verify+close）。**判斷的是「碰到什麼資源」不是「issue 多難」**。`B`/`C` 的 justification **必須 named 出共享資源**，否則無法 audit（見 `references/parallel-orchestration.md` 的 Scoundrel/Lazy/Confused lens）。**Consumer 契約**：消費端若讀到的 Diagnosis 缺 `### Conflict Class` 或無法 parse，SHALL 預設為 `D_diagnose_first` 並 **surface 這個 fallback**（印出來），不得靜默、不得預設成 parallel class。完整 taxonomy + lane scheduling 見 [`references/parallel-orchestration.md`](../../references/parallel-orchestration.md)。

同時在對話中顯示 report，讓使用者可以即時確認。

### Step 3.4: Vagueness Pre-check (Layer V, v2.50.0+)

Diagnosis 完成、Step 3.5 Complexity Assessment 之前,評估 issue 的「需求清晰度」。如果模糊到無法可靠 routing,先讓 user 表態:澄清 / 照做 / 升級 Plan。

> **`type=meeting` short-circuit（round-2 verify HIGH fix — MUST）**：若 issue `type=meeting`，**跳過整個 Layer V（Step 3.4）**，不評 V1/V4、不觸發 vagueness gate，直接進 Step 3.5 走 meeting 分支。理由：Step 3.4 在 Step 3.5 **之前**執行 —— 若不在此短路，meeting issue 會先撞上 Layer V 的 AskUserQuestion（或 unattended 下被設 `Plan via Layer V`），Step 3.5 的 meeting-first 排序就形同虛設。meeting 的模糊性由 Phase A/B/C 議程本身釐清（#57：type=meeting self-clarifying），故 Layer V 對它是 dead weight。

**為何在 Step 3.5 之前**:Layer V 是 routing 決策的一階信號,放在 Step 3.5 之後等於 routing 已經做完才檢查 — 太晚。Layer 1 disqualifier 仍最優先(narrative / ad-hoc 強制 Simple,vagueness 不該推翻),所以 Step 3.4 在 Layer 1 之後、Layer 2/3/P 之前（**但 `type=meeting` 更優先，見上方 short-circuit**）。

> **procedure vs verdict-precedence（round-4 verify HIGH 澄清）**：Step 3.4（Layer V）在 procedural 上先於 Step 3.5 執行（先 score、必要時 prompt），但 canonical 7-step 是 **verdict precedence** —— 其中 Layer 1（step 2）優先於 Layer V（step 3）。兩者不衝突：Layer V 在 3.4 只是**預先 score / 記 audit**，真正套用其結果是在 Step 3.5 step 3；而 Step 3.5 step 2 的 Layer 1 若命中 → `Simple` 並**停止**，覆蓋任何 Layer V escalation（narrative 勝 vagueness）。換言之 3.4 是 pre-check，最終裁決順序仍是 Layer 1 先於 Layer V。

#### A. 載入 attribute-assessment 規則(必要)

```bash
RULE_PATH=".claude/rules/attribute-assessment.md"
if [ -f "$RULE_PATH" ]; then
  ANCHOR_SOURCE="$RULE_PATH"
else
  echo "⚠ Layer V: This repo has no project rule for attribute-assessment;using plugin built-in anchors"
  ANCHOR_SOURCE="plugin built-in (see plugins/issue-driven-dev/rules/sdd-integration.md Layer V section)"
fi
```

Anchors 載入後,AI 對 issue body 評 V1 + V4 兩個 score(每個 1–6),依 anchor 給的 example 校準。

#### B. Likert scoring (per-axis)

對 issue body(若 Step 3.6 已澄清過,用更新後的 body)評估:

- **V1 (vague WHAT)** — 「要做什麼」的清晰度
- **V4 (vague ACCEPTANCE)** — 「完成定義」的清晰度

每軸獨立評分 1–6,**不**用 keyword matching(brittle 且 cross-language drift)。Score + 一句話 reasoning(引具體證據:行號 / 引用 / 結構觀察 — 不可寫「感覺像 X」)。

V2(vague HOW)已被 Layer P "decision-heavy" 覆蓋,本步驟**不**評。
V3(vague SCOPE)由 IC_R011 sister sweep(Step 3.6)處理,本步驟**不**評。

#### C. Trigger 判斷

```
trigger = (V1 >= 4) OR (V4 >= 4)
max_score = max(V1, V4)
```

`trigger == false` → 跳過 D,直接進 E(audit trail untriggered)再進 Step 3.5。

#### D. Hybrid 3-option AskUserQuestion(僅在 trigger 時)

依 `max_score` 決定 default option(AskUserQuestion 第一選項):

| max_score | Default option       |
|-----------|----------------------|
| 4         | `proceed anyway`     |
| 5         | `clarify now`        |
| 6         | `escalate to Plan`   |

```
AskUserQuestion(
  question = "Layer V triggered (V1=$V1, V4=$V4). 模糊度 $max_score/6 — 怎麼處理?",
  options = [
    # 順序依 max_score 重排,把 default 放第一個
    {label: "clarify now",      description: "Claude 對 1-3 個不清楚的點 render 候選詮釋讓你挑（NSQL P1 — Read-Only for Humans;無法列舉的點 fallback 才用 free-text 問）→ append 到 issue body 'Clarification (added during diagnose)' 區塊 → 重跑 Layer V + Step 3.5"},
    {label: "proceed anyway",   description: "跳過 clarify,routing 進 Layer 2/3/P。trigger 事實寫入 audit trail"},
    {label: "escalate to Plan", description: "verdict 直接設 Plan via Layer V,跳過 Step 3.5。Routing 進 /idd-plan EnterPlanMode 對齊"}
  ]
)
```

#### D.1 Choice handlers

**`clarify now`**:
1. AI 根據 V1 / V4 評分理由,挑出 1–3 個最不清楚的點。**對每個點套用 Choice-First Decision Rendering doctrine**（見 `MANIFESTO.md`「Choice-first decision rendering」/ spec capability `choice-first-decision-rendering`）—— 此處是該 doctrine 在 vagueness-clarification 情境的一個 instance,規則的 single source of truth 在 doctrine,本步不另立規則：
   - **可列舉** → 用 AskUserQuestion render 該點的候選詮釋（`1. X（推薦） 2. Y 3. Z`）。User *挑選*,不從白紙寫。
   - **無法列舉**（問題本質開放,AI 真的舉不出候選）→ fallback 才用 free-text 問,且須說明為何無法列舉（doctrine 的具名例外,不是預設）。
2. 把 user 的選擇 / 回答組合成 markdown 區塊:
   ```markdown
   ## Clarification (added during diagnose)

   **Q**: <question — 含 AI render 的候選清單,若有>
   **A**: <user 的選擇,或 free-text 回答>

   (repeat for each Q/A pair)
   ```
3. 用 `gh issue edit $NUMBER --repo $GITHUB_REPO --body "$NEW_BODY"` append 到 issue body(放在 `---` separator 上,Current Status 之前)
4. **重跑 Step 3.4**(Layer V 用更新後的 body 重新評分;若仍 trigger 再問,但循環不超過 2 次)+ Step 3.5

**`proceed anyway`**:
- 不澄清,不修 issue body
- Audit trail entry(見 E)記 `Layer V triggered (V1=N V4=M), user opted to proceed`
- 進 Step 3.5 Layer 2/3/P 評估

**`escalate to Plan`**:
- 直接設 verdict = `Plan via Layer V`(會被 Step 3.5 的 verdict format 採納)
- 跳過 Step 3.5 Layer 2/3/P 評估
- Routing 直接進 `/idd-plan` 走 EnterPlanMode approval gate

#### E. Audit trail PATCH(無論是否 trigger 都要寫)

把 Step 3.4 結果 append 到剛 post 的 Diagnosis comment:

```bash
COMMENT_ID=<剛 post 的 comment id>
CURRENT_BODY=$(gh api "/repos/$GITHUB_REPO/issues/comments/$COMMENT_ID" --jq '.body')

# Trigger case
if [ "$trigger" = "true" ]; then
  AUDIT_BLOCK="
### Vagueness Pre-check

- **V1**: $V1 — $V1_REASONING
- **V4**: $V4 — $V4_REASONING
- **Triggered**: yes (max=$max_score)
- **User choice**: $USER_CHOICE
- **Effect**: $EFFECT_DESCRIPTION
"
else
  AUDIT_BLOCK="
### Vagueness Pre-check

- **V1**: $V1 — $V1_REASONING
- **V4**: $V4 — $V4_REASONING
- **Triggered**: no — both axes ≤ 3
"
fi

NEW_BODY="${CURRENT_BODY}${AUDIT_BLOCK}"
gh api -X PATCH "/repos/$GITHUB_REPO/issues/comments/$COMMENT_ID" -f body="$NEW_BODY"
```

#### F. `idd-all` Unattended mode

當 idd-diagnose 在 `idd-all` UNATTENDED MODE directive 下執行(透過 args 偵測),Step 3.4 仍評分 + 寫 audit trail,但**不**跳 AskUserQuestion。自動 apply `proceed anyway`,audit trail 寫:

```
[Layer V: V1=$V1 V4=$V4, clarify-default skipped under unattended mode, defaulting to proceed]
```

跟 Plan tier 在 unattended mode 也跳過 EnterPlanMode 同樣設計(user 不在現場,沒法 review prompt)。User 後續 review final report 仍能看到 audit trail 上的 trigger 記錄,可以手動重 route。

### Step 3.5: Complexity Assessment (3-tier: Simple / Plan / Spectra)

Diagnosis 完成 + Step 3.4 Vagueness Pre-check 結束後（`type=meeting` 已在 Step 3.4 短路，直接落到本 step 的 meeting 分支），依 meeting-first 7-step routing 判定 Complexity。**Default = Simple。** 完整邏輯見 [`rules/sdd-integration.md`](../../rules/sdd-integration.md)。

> **v2.36.0+ rename**：原本是二元 `Simple` / `SDD-warranted`，現在是三層 `Simple` / `Plan` / `Spectra`。`SDD-warranted` 是 `Spectra` 的 backward-compat alias（既有 issue 不需重寫）。Plan 是新增的中間層，覆蓋「想先想清楚再動手，但沒到要寫 spec contract」的常見場景。
>
> **v2.50.0+ Layer V**：Step 3.4 Vagueness Pre-check 在 Layer 1 之後、Layer 2 之前評估「需求清晰度」。若 user 在 Step 3.4 選 `escalate to Plan`，verdict 直接設 `Plan via Layer V`,本 step 跳過 Layer 2/3/P 評估。

#### 評估順序（統一 routing，必須照此順序）

**canonical routing 序列（#129 × #57 耦合收斂；meeting-first，忠實 7 步）**：**(1) type=meeting → (2) Layer 1 → (3) Layer V → (4) Spectra（Layer 2+3）→ (5) #129 硬閘 → (6) Layer P → (7) Simple 預設**（此序列與下方 operational list 一一對應，不省略任何 gate —— round-2 verify HIGH-5 fix：舊「5-stage」摘要漏列 Spectra 造成歧義）。**`type=meeting` 最優先分流**：type 是 issue 的確定性欄位，先於任何內容啟發式判定 —— 否則 meeting 的 Phase A/B/C 審議內容會被 Layer 1 的 narrative disqualifier 誤判成 Simple 而攔截（#57 裁決；round-1 verify HIGH-2 fix）。硬閘只作用於**非 meeting 的 code-centric issue**，兩者不對同一 issue 同時給出衝突 verdict。

1. **`type=meeting`** → 走 meeting Strategy（Phase A/B/C 審議模板，複雜度評估前分流）→ **本 step 結束**，**不進 Layer 1 / Layer V / Spectra（Layer 2+3）/ 硬閘 / Layer P**，不產生 Simple / Plan / Spectra complexity verdict（見 Step 3「meeting-adapted Diagnosis」）。meeting **刻意跳過 Layer V** vagueness pre-check —— 審議 issue 的模糊性由 Phase A/B/C 議程本身釐清（#57 裁決：type=meeting self-clarifying）
2. **Layer 1 disqualifiers** 任一命中 → `Simple`，停止
3. **Layer V (Step 3.4)** Vagueness 已在 Step 3.4 處理:
   - User 選 `escalate to Plan` → verdict = `Plan via Layer V`,**本 step 結束**
   - User 選 `clarify now` → 已重跑 Layer V + 進到本 step
   - User 選 `proceed anyway` 或 V≤3 → 繼續以下評估
4. **Layer 2 + Layer 3** 都命中 → `Spectra`（published API contract；優先於硬閘 / Layer P）
5. **#129 硬閘（Hard Gate，MUST-trigger）** 命中 → `Plan`（疊加於 Layer P 之上，只升級不反轉）
6. **Layer P** 任一命中 → `Plan`
7. 否則 → `Simple`（default）

#### Layer 1: Simple-required disqualifiers（任一命中 → 強制 Simple）

- 主要 deliverable 是 narrative / prose（摘要改寫、論文段落、報告、closing summary、wording polish、translation）
- 主要 deliverable 是 ad-hoc analysis script（一次性 R/Python/Julia 分析,腳本本身不會被別 caller 呼叫;產出 tables/figures/reports 給人看）
- 主要 deliverable 是更新既有 prose 但不改 behavior（typo、wording cleanup、文件 restructure）
- Multi-file 但每個檔案 independent（parallel doc updates、parallel script tweaks;檔案數不是 routing 信號）

任一命中 → 直接判 Simple，**完全跳過** Layer 2 / Layer P。**Plan / Spectra 對 fluid narrative / one-shot analysis 是 dead weight。**

#### Spectra（Layer 2 + Layer 3，兩者皆需）

`Spectra` 保留給「**為 future callers 產出 frozen contract**」的改動。

**Layer 2: Necessary condition**

- 改動會對外暴露 published API / protocol / skill / tool surface 給 future callers（function、MCP tool、plugin skill、agent、public Swift API、REST endpoint、OOXML element handler 等），**且** abstraction 的 behavior contract 應該為這些 callers 寫成 documented spec

未命中 Layer 2 → **不走 Spectra**，掉到 Layer P（Plan）評估。

**Layer 3: Spectra confirmation signals（至少一個命中，加在 Layer 2 之上）**

- 修改既有 published spec 的 normative behavior（MUST/SHALL clause changes,影響 downstream maintainers）
- 影響 2+ 既有 specs 需要 consistency-checking（cross-spec impact,需要協調更新）
- Architectural decision with long-term maintenance implications（不是 method-level choice,是會被 future engineers 繼承的結構性決定）

**Plan-Spectra 分界**：「published API/protocol 給 future callers」就是 line。內部 refactor 5 個檔案 → Plan；加新 MCP tool / plugin skill / public API → Spectra。

#### Hard Gate（硬閘，MUST-trigger，疊加於 Layer P 之上）

在 Layer P 之上先評一層 **MUST-trigger 硬閘**。`/idd-diagnose` 在 implementation 之前跑、**沒有實際 diff** 可 grep，故硬閘觸發是 AI 對「本 issue 預期改動範圍」的**估計**（依 `attribute-assessment` 紀律揭露理由 + 具體錨點，audit line 見下方 Step 3.5 尾），不是 diff-time 機械比對。

判準（OR，任一命中 → 強制 `Plan`）：

1. **單一概念散佈 ≥ 5 檔** — 門檻 **N = 5**（保守以保護 Simple 預設；3 = 激進、5 = 保守；N 是本設計唯一可調旋鈕）。**判準是「同一 conceptual 改動散佈到 ≥ 5 檔」，不是純檔數**：genuinely 各自獨立、無共享概念的多檔（parallel doc updates / 各自獨立的 script tweaks）由 Layer 1「Multi-file but each file independent」保持 Simple、**不**觸發硬閘（round-1 verify HIGH-7 fix —— 消解硬閘 vs Layer 1 的矛盾）。取 5 而非 3：impl + test + doc 這類合法小改常觸及 3 檔，門檻設 3 會過度觸發；5 檔才是「單一概念散佈多處」的可靠訊號（對齊 #44/#47 failure class —— CR/PTSR/PCQ 三量表共用一個 scoring helper 即是「散佈的單一概念」，非獨立多檔）。
2. **動到 shared abstraction** — 被 **≥ 2 個其他檔案** 引用的 data structure / helper interface / constants set。以「issue 描述 + 對現有程式碼的引用查找」估計某待改符號的跨檔 caller 數；≥ 2 → 命中。**shared abstraction 命中時，產出的 Plan 必涵蓋 family-wide 影響** —— 列舉該抽象的所有已知 call site / family member 為 in-scope（填入 `/idd-plan` 的 `Family-wide scope` 小節），而非只覆蓋觸發當下那個檔案（#44 教訓：miss 不在沒開 Plan，而在 Plan 只覆蓋一個量表、漏了同 family 的 sibling）。

硬閘**只升級、不反轉** Simple 預設 —— 命中 → 強制 `Plan`；硬閘未命中 → **落回 Layer P** + Simple 預設（既有行為不變）。硬閘是「加法」不是「換底」：把大型多檔 / 共用抽象改動從 Simple 拉升到 Plan，但不把小改也拖進 plan-mode approval gate（**替代方案「反轉為 Default-Plan」已被使用者否決** —— over-trigger 成本高於 under-plan 殘餘風險）。硬閘只作用於**非 meeting 的 code-centric issue**（Layer 1 已把 narrative / 各自獨立的 multi-file 改動強制 Simple、不會進到這裡）。

**Audit line（揭露估計，與 Layer V 同等 audit trail）**：硬閘評估後於 Diagnosis comment 印**一行** `Hard-gate: <triggered|not triggered> — <reason with anchors>`，與 Step 3.4 的 Layer V audit line 並列。reason 必引**具體錨點**（估計的檔名 / 符號名），不是 style words。命中 → `Hard-gate: triggered — <列出估計觸及的模組 + shared helper>`；未命中 → `Hard-gate: not triggered — <reason>`。**訊號不足**（issue 描述太稀、無法估計檔數或 caller 數）→ 硬閘**不觸發**（fail-open 回 Layer P + Simple 預設），該行寫 `Hard-gate: not triggered — insufficient signal`。理由：硬閘是「加保護」，訊號不足時不應誤升級；漏升級由既有 Layer P 兜底。

#### Plan（Layer P，至少一個命中）

如果 Layer 1 沒命中、Layer 2 沒滿足 Spectra、硬閘也沒命中，評估 Plan signals：

- **2+ 檔案有順序依賴** — 檔案 A 的改動影響檔案 B 必須怎麼改，無法 parallel edit
- **Strategy 有 5+ ordered steps** — sequential 複雜度，受惠於 explicit checkpoint
- **Decision-heavy with 2+ valid approaches** — diagnosis 列出 2+ 實作策略，選哪個會影響 code shape（例如 regex splice vs DOM walker、optimistic-locking vs pessimistic、batch vs streaming）
- **觸及 risk-sensitive 邊界** — concurrency、migrations、backward-compat shims、security-critical paths、save-durability、ordering semantics、atomic operations、irreversible side effects
- **Cross-file refactor 但無 external contract change** — 抽 shared logic 成 helper、拆 god-function、rename internal API used by ≥3 callers

任一命中 → `Plan`。Plan path 在 diagnosis 和 TDD execution 之間插入 `EnterPlanMode` approval gate — user 在 plan-mode UI 看 Implementation Plan，approve 或修改後再進 implementation。

#### Simple（default，沒命中以上任何條件）

- Bug fix with clear root cause + self-contained fix
- 單檔案 change
- 跟既有 pattern 走（例如加上第 N 個已知 visitor instance）
- Cross-file research analysis（R/Python script + outputs + docs + abstract）
- Narrative revision
- Ad-hoc one-shot analysis where script is the deliverable
- Multi-step workflow with no shared abstraction

#### Verdict 寫入 Diagnosis Report

把判定結果寫進 Diagnosis Report 的 `### Complexity` 區段。格式：

```
### Complexity
{Simple / Plan / Spectra}

{對 Simple：列出哪個 Layer 1 命中、或 Layer 2/P 都沒命中的說明}
{對 Plan：列出觸發的 Layer P 信號}
{對 Spectra：列出 Layer 2 + Layer 3 觸發項}
```

#### 各 verdict 的 Next Step

| Verdict | Next Step | Flow |
|---------|-----------|------|
| `Simple` | `/idd-implement #NNN` | diagnose → implement → verify → close |
| `Plan` | `/idd-plan #NNN` | diagnose → plan (EnterPlanMode 審查 Implementation Plan → 使用者 approve via ExitPlanMode) → implement → verify → close |
| `Spectra` (default) | `/spectra-discuss` | diagnose → discuss → propose → apply → verify → close + archive |
| `Spectra` (opt-out) | `/spectra-propose` | diagnose → propose → apply → verify → close + archive（僅當 ALL opt-out conditions 成立） |
| `meeting`（**type 分流，非 complexity verdict** —— 在 Step 3.5 最優先分支、不經複雜度評分） | `/idd-plan #NNN`（meeting-adapted plan） | diagnose（Phase A/B/C Strategy）→ plan（meeting Plan body：議程 → 決策點 → 行動項；**不** chain to `/idd-implement`）→ close（decision→action mapping + meeting-specific gate，無 `/idd-verify` TDD pass） |

> **Pre-implementation staging hand-off（#111，非綁定）**：verdict 為 `Plan` 或 `Spectra`（design-heavy）時，diagnose 在 report 印一行非綁定 pointer —— `→ 建議 pre-implementation staging: superpowers:brainstorming`（先 brainstorm 對齊方向再進 plan / propose）。這是**非綁定建議**：IDD 自身**不** invoke `superpowers:brainstorming`，使用者自行決定是否跟進（見 README「IDD ↔ superpowers stage mapping」）。

> **為什麼 discuss 是 Spectra default?** AI 常常高估 diagnosis 的完整度。一份看起來詳盡的 diagnosis 可能仍留下關鍵的未決項:命名、範圍邊界、多個合理方案中該選哪個、新產物要放哪裡。直接跳到 `spectra-propose` 會產生建立在未確認假設之上的 proposal。`spectra-discuss` 是對齊的 safety net — 強制把假設列出、讓使用者修正。跳過它應該是例外,不是預設。
>
> **何時可 opt-out 跳過 discuss?** 當且僅當以下**全部**成立:使用者已在 issue body 或 diagnosis 對話中明確選定方向、無命名/範圍/trade-off 的 open questions、Strategy 沒有未決項、遵循既有 pattern 無新抽象。任一不成立,保留 discuss。
>
> **為什麼 Plan 用 EnterPlanMode?** Plan tier 的價值是「approval checkpoint before any tool that modifies state」。Claude Plan Mode 是這個約束的 first-class API — `EnterPlanMode` 鎖到 read-only tool set，user 必須對呈現的 plan 點 approve（透過 `ExitPlanMode`）才能繼續。比 AskUserQuestion 更強約束（後者只是 yes/no 確認，agent 仍可以「忘了」就動手）。

> **核心原則**：不是所有 issue 都需要 Plan / Spectra，但所有 Plan / Spectra 都值得有一個 issue。三層都是 IDD 的 special case — issue 始終是工作的入口和出口。
>
> **Anti-pattern: 三層 over-trigger**：
> - Spectra over-trigger：cross-file refactor 沒對外暴露 API → 應該 Plan，不是 Spectra
> - Plan over-trigger：clear root cause 單檔 fix → 應該 Simple，不是 Plan
> - Simple under-served：che-word-mcp#104 P1 sub-bug — diagnosis 漏了 rawXML-shadowing case，approval gate 會抓到 → 應該 Plan

### Step 3.6: Sister Concern Surfacing (v2.47.0+, kiki830621/ai_martech_global_scripts#528;v2.72.0+ default-flip #148)

**Per IC_R011 follow-up filing checkpoint** (per IC_R011 — see [`references/ic-r011-checkpoint.md`](../../references/ic-r011-checkpoint.md))。

**Trigger condition**: 在 Step 4 (確認 + Routing) 前，re-read the just-posted Diagnosis comment + session log from Step 1 (Read Issue) for sister-concern markers (deliberation-moment surfacing per canonical §6 — Diagnosis Strategy section often surfaces tangential concerns)。Empty list 是合法結果，但 step 本身不可省略。

**Per-step deviation**:

- **Diagnosis-specific heuristic** (in addition to canonical §2 trigger categories): scan the just-posted Diagnosis content for sister-pattern markers — 「也有」 / 「same pattern」 / 「related」 / 「另外」 / 「sister」 / 「likewise affects」 — referencing files / functions / scenarios beyond the current issue scope. Also surface "this won't solve X" disclaimers in Strategy section + adjacent code quality issues (TODOs / FIXMEs / drift) encountered during root-cause analysis.
- **Source footer literal** (per canonical §7.2): `**Source**: surfaced during /idd-diagnose #N sister concern surfacing (Step 3.6)`
- **Issue title suffix**: `(sister concern from #$NNN)` — distinguishes diagnose-surfaced from other sites' suffixes (e.g. plan: "mid-plan tangential", verify: "follow-up finding")
- **Chain manifest write** (per [`references/spawn-manifest.md`](../../references/spawn-manifest.md), v2.55+ #44 / v2.60+ #46 schema v2): when filing a candidate, classify `spawn_kind` (`sister-concern` for same-root-cause-different-file vs `upstream-tracking` for cross-cutting), pass `same_file` / `same_skill` flags, and call `manifest-append.sh` with `ROOT_ID_FOR_MANIFEST="${IDD_CHAIN_CURRENT_ROOT_ID:-${NNN:-}}"` (silent skip when chain context inactive — additive behavior, baseline unchanged).

**Audit trail target**: `### Sister Concerns Filed (mid-diagnose, v2.47.0+ #528)` section appended to the Diagnosis comment (Step 3 已 post) via `gh api PATCH /repos/$GITHUB_REPO/issues/comments/$COMMENT_ID`. Audit line formats per canonical §4.2. **`(category: audit-block-append, scope: "### Sister Concerns Filed")` per [`rules/append-vs-modify.md`](../../rules/append-vs-modify.md)** — adds new audit block to named section without modifying existing Diagnosis prose.

**Default behavior (v2.72.0+)**: File by default per canonical §1.1. Skip path requires per-candidate 3-category taxonomy per §1.4 ((a) unactionable / (b) infeasible / (c) blocked-on-external). Legacy 3-option ask preserved only under `AI_LOW_BAR_ISSUE_FILING=false` env var or `# Disable IC_R011` repo CLAUDE.md flag (per §5 escape hatches);unattended mode falls back to implicit (a) skip per §5.4.

> **Why is this SHALL not SHOULD?** Diagnosis is a **deliberation moment** (per canonical eligibility criteria §6) — Strategy authoring is when sister concerns naturally surface. Closing tier (`#527` Step 3.5) is SHOULD because it's an after-the-fact text scan;diagnosis is a creative + analytical authoring moment where the mention is fresh + actionable.

### Step 3.7: Agent Routing Recommendation (v2.38.0+, optional)

If `idd-route` is installed (`command -v idd-route`), call it for an agent recommendation based on observed track record + the static heuristic fallback. The recommendation is informational — user accepts or overrides during Step 4 routing. **Skip silently if binary missing.**

```bash
if command -v idd-route &>/dev/null; then
  REPO_PATH=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
  STATS="$REPO_PATH/.claude/.idd/routing-stats.jsonl"
  GLOBAL="$HOME/.cache/idd-route/stats.jsonl"

  # Detect signals from issue body + diagnosis (controlled vocabulary in
  # idd-route plugin's references/signal-vocabulary.md). Common signals:
  # explicit_acceptance, single_handler, sibling_sweep_needed, design_negotiation,
  # cross_repo, breaking_change, requires_changelog, public_api, hot_context, etc.
  SIGNALS="..."  # comma-separated, derived from your diagnosis

  # Estimate scope LOC from diagnosis Strategy (rough — counting bullets,
  # mentioned files, etc.)
  SCOPE_LOC="..."

  RECOMMENDATION=$(idd-route recommend \
    --stats-file "$STATS" \
    --global-stats-file "$GLOBAL" \
    --complexity "$COMPLEXITY" \
    --scope-loc-estimate "$SCOPE_LOC" \
    --signals "$SIGNALS" \
    --candidates codex-gpt-5.5-xhigh,claude-opus-4.7,claude-sonnet-4.6,claude-haiku-4.5 \
    2>&1)
  EXIT=$?  # 0=warm data-driven, 3=cold static heuristic, other=error
fi
```

If recommendation succeeded, append a section to the diagnosis comment:

```markdown
### Recommended Agent: <recommended>
**Confidence**: <confidence>  (0.0-1.0; lower = less data, take with grain of salt)
**Data source**: <data_source>  (per_repo / global / static_heuristic)
**Expected**: <round_trips> avg round trips, <blocking> avg blocking, <merge_rate>% merge rate
**Reasoning**: <reasoning>

**Compare**:
| Agent | N | Avg RT | Avg blocking | Merge% | Score |
|-------|---|--------|-------------|--------|-------|
| codex-gpt-5.5-xhigh | 8 | 1.0 | 0.2 | 87% | 4.35 |
| claude-opus-4.7 | 4 | 2.5 | 1.5 | 100% | 0.40 |
| claude-sonnet-4.6 | 0 | — | — | — | insufficient_data |
| claude-haiku-4.5 | 0 | — | — | — | insufficient_data |
```

Full integration contract: [`references/agent-routing.md`](../../references/agent-routing.md).

### Step 4: 確認 + Routing

Diagnosis comment 到 #NNN 後，進行兩階段確認:

#### Stage 1: 確認 diagnosis 正確性

詢問使用者：「Diagnosis 已 comment 到 #NNN。正確嗎？要調整策略嗎？」

- 如果要調整 → 修改後用 `gh issue comment` 追加修正,然後回到這個 Stage 1 重新確認

> **Choice-first decision surfacing**（套用 `MANIFESTO.md`「Choice-first decision rendering」doctrine / spec `choice-first-decision-rendering`）：當 diagnosis 的 Strategy / Conflict / Risks 浮出**需 stakeholder 拍板且可列舉**的決策（多個 valid approach、方向衝突、命名 / 範圍取捨等），Stage 1 **SHALL** 用 `AskUserQuestion` render 成候選選項（含推薦項）讓 user 挑,而非只用散文列出請 user 自行 articulate。選項空間真的開放（AI 舉不出候選）時才 fallback free-text,且須具名說明為何無法列舉。batch / aggregate diagnose 收尾列多個待拍板決策時同理。Unattended 下不 block,套用既有 unattended 慣例（取安全 non-blocking 預設、寫 audit trail；如 Layer V 的 `proceed anyway`,未必是推薦項）。

#### Stage 2: Routing（根據 Complexity 選下一步）

**如果 Complexity = `Simple`**:
- 直接顯示下一步命令:
  ```
  /issue-driven-dev:idd-implement #NNN
  ```

**如果 Complexity = `Plan`**:
- 直接顯示下一步命令:
  ```
  /issue-driven-dev:idd-plan #NNN
  ```
- `idd-plan` 內部會呼叫 `EnterPlanMode`、呈現完整 Implementation Plan 給使用者審查、等 user 透過 `ExitPlanMode` approve 後才 chain 到 `idd-implement`。
- 不要自動 invoke — 使用者應主導 pacing（同 Spectra 路徑慣例）。

**如果 Complexity = `Spectra`**（含 backward-compat alias `SDD-warranted`）:
- **必須**使用 **AskUserQuestion 工具**強制使用者在 `spectra-discuss` 和 `spectra-propose` 之間明確選擇,不可預設任一方向自動繼續
- AskUserQuestion 的 question 和 options 範例:
  ```
  question: "Spectra。預設走 spectra-discuss 對齊方向，要 opt-out 嗎？"
  options:
    - label: "spectra-discuss (default)"
      description: "先列 assumptions 讓你 correct，對齊後才寫 proposal。適用於還有 naming / 範圍 / trade-off 的不確定。"
    - label: "spectra-propose (opt-out)"
      description: "方向已在 issue 或 diagnosis 中明確選定，直接進 formal proposal。僅當零 open questions 時選這個。"
  ```
- 根據使用者選擇**顯示**對應命令讓使用者**自行執行**（不要自動 invoke,使用者應主導 pacing）:
  - 選 `spectra-discuss` → 顯示:`/spectra-discuss` 並附上 topic 建議(例如 issue 標題或核心議題)
  - 選 `spectra-propose` → 顯示:`/spectra-propose`

> **為什麼 Spectra 強制選擇而非給 default?** diagnose 階段 AI 常常高估 strategy 的確定性。若只給「建議」使用者容易忽略並直接跳 propose。AskUserQuestion 把這個決定明確化,避免「忘記走 discuss」。
>
> **為什麼 Simple / Plan 不需要 AskUserQuestion?** 兩條路徑都只有一個合理 next command（idd-implement / idd-plan），沒有 opt-out 分支需要決定。
>
> **為什麼只顯示命令而不自動 invoke?** 使用者應該主導流程節奏。自動 invoke 下游 skills 會讓使用者失去對何時進入下一階段的 visibility 和控制。idd-diagnose 的職責到「告訴使用者下一步是什麼」為止,實際執行由使用者主導。

> **Backward compat (v2.36.0+)**：若 diagnosis comment 寫了 `SDD-warranted`（pre-v2.36 格式），routing 視同 `Spectra` 處理。新 diagnosis comment **必須**寫 `Spectra`。

### Step 5: Auto-Update Issue Body（強制，不可省略）

Step 4 確認 / routing 完成後**立刻**執行，更新 issue body 的 `Current Status` 區塊（phase → `diagnosed`）：

```
Skill(skill="issue-driven-dev:idd-update", args="#NNN")
```

或等價手動執行 `/idd-update #NNN`。

**為何強制**：diagnosis comment 已 post 到 issue，但 body 的 Current Status phase 還停留在 `created`。沒做 Step 5 會導致：

- `gh issue view` / `idd-list` 仍顯示 `created`，掃不到「這個 issue 已 diagnosed」
- 下一次回來不知道是 `diagnosed` 還是 `(no phase)`
- 與 idd-close 2.18.0 同樣的「narrative Auto-Update 沒升 Step」漏跑模式（見 idd-close 2.18.1 fix `4762e64`）

## 鐵律

- **不跳過 diagnosis**。就算「很明顯」也要做。簡單的問題做 diagnosis 只要 2 分鐘，但省下的是 2 小時的重工。
- **發現多個問題 → 開新 issue**。一個 issue 修一個問題。
- **不確定就問**。問使用者比猜測好。
- **Step 5 Auto-Update 是工作流真實終點**，不是可選 nice-to-have。Step 4 confirm-and-route 完成後馬上跑 `/idd-update`。

## Next Step

Diagnosis 確認後,依 Complexity 分流（v2.36.0+ 三路）:

**Complexity = `Simple`**:
```
/issue-driven-dev:idd-implement #NNN
```

**Complexity = `Plan`**:
```
/issue-driven-dev:idd-plan #NNN
```
`idd-plan` 內部會用 EnterPlanMode 把 Implementation Plan 呈現給使用者審查，approve 後才執行 TDD loop。

**Complexity = `Spectra` (default — discuss first)**:
```
/spectra-discuss
```
對齊方向後再執行 `/spectra-propose`。

**Complexity = `Spectra` (opt-out — 方向已明確)**:
```
/spectra-propose
```

> Step 4 會透過 AskUserQuestion 強制使用者在 discuss / propose 之間選擇,避免漏走 discuss。
>
> **Backward compat**: 若舊 issue 的 Complexity 寫 `SDD-warranted`，視同 `Spectra` 處理。新 diagnosis 必須寫 `Spectra`。
