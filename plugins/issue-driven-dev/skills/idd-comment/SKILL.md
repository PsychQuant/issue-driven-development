---
name: idd-comment
description: |
  加 template-guided comment 到 GitHub issue。
  支援 decision/note/question/correction/link/errata 6 個 types，強制 blockquote 原文、加 timestamp 與 metadata marker。
  用於記錄使用者決定、外部 context、開放問題，不走完整 diagnose/implement phase 時。
  支援 batch mode（v2.34.0+）：多個 #N 同步加同一段 comment（如 `#34 #36 --type note --body 'blocked by upstream'`）。
  防止的失敗：非流程性 decision 散落在 chat，未來無法追溯。
argument-hint: "#issue [#issue ...] --type=<type> [options] e.g. '#42 --type note --body ...' or '#34 #36 --type note --body ...' (batch)"
allowed-tools:
  - Bash(gh:*)
  - Read
  - Write
---

# /idd-comment — Template-guided issue comment

快速記錄決策、外部 context、未決問題到 issue，不用走完整 diagnose/implement phase。

## 核心原則

> 使用者的決定、外部 context、未決問題，都應該**留在 issue 裡**，不是 chat history。Comment 是 audit trail。

## Batch mode（v2.34.0+）

`idd-comment #34 #36 --type note --body 'blocked by upstream X'` 把同樣的 comment 套到多個 issue。每個 issue 仍各自 post 獨立 comment（不是合併、不是 cross-link），保留 per-issue audit trail。完整契約見 [batch-and-cluster.md](../../references/batch-and-cluster.md)。

實用情境：upstream 有變動波及多個 in-progress issue、同一個 advisor feedback 適用多個提案、宣告統一 deferral 原因。`--type=question` 也適合 batch（同一個未決問題影響多個 issue）。

## When to use `idd-issue` multi-finding mode instead（v2.55.0+）

如果你要做的是「**從一個 source 文件抽多個 findings,部分 comment 既存 issue、部分建新 issue**」(典型場景:transcript 有 10 個觀察點,5 個對應 #14/#17/#23 的補充、5 個是新主題),**不要**手動跑 `idd-comment` 多次,改用 `idd-issue` multi-finding mode:

```bash
idd-issue source.docx       # auto-trigger when source contains ≥2 findings
```

差別:

| 情境 | 用 idd-comment | 用 idd-issue multi-finding mode |
|------|---------------|-------------------------------|
| 已知對哪個 #N 加同一 comment(批次) | ✅ batch mode | overkill |
| 從 source 文件分流多 finding 到多個 destination | 5 次 invoke + 失 audit trail | ✅ 一次 invoke + jsonl run log + per-action footer |
| Mixed routing(new + comment + edit) | 不支援 | ✅ Stage 2 picker 對每筆選 routing |

完整 multi-finding mode 契約見 `idd-issue` SKILL.md `## Multi-finding source mode` 段落。

## 6 個 Types

| Type | 用途 | 必填 | 產出格式 emoji |
|------|------|------|--------|
| `decision` | 使用者/老師做的決定 | `--quote`, `--body` | 🎯 |
| `note` | 外部 context（meeting、paper、advisor feedback） | `--source`, `--body` | 📝 |
| `question` | 開放性待決問題 | `--body` | ❓ |
| `correction` | 修正外部 data / interpretation | `--body` | 🔧 |
| `link` | 交叉引用其他 issue | `--target`, `--body` | 🔗 |
| `errata` | 標記既有 comment 內容錯了（配 idd-edit 用） | `--target-comment`, `--body` | ⚠️ |

## Configuration

按 [config-protocol](../../references/config-protocol.md) 解析 target repo:

- `--repo owner/repo` flag → per-invocation override(注意:`--target` 在 idd-comment 是「link 目標 issue」,不是 repo override)
- Walk-up `.claude/issue-driven-dev.local.json`(從 cwd 往上找)
- Path / git predicates 自動匹配

**Group/predicate 行為**:`idd-comment` 只用 path/git 類 predicate(因為操作對象是已存在的 issue,沒有 title/labels 可評估)。Group config 會 fall through 到 primary repo。

## Execution

### Step 0: Bootstrap Stage Task List（強制)

**在動任何事之前**先用 `TaskCreate` 為這個 stage 建 todo list,確保每個 sub-step 都被追蹤:

```
TaskCreate(name="parse_args", description="Parse #NNN + --type + --body / --quote / --source / --target / --target-comment / --deadline / --mention / --resume-spectra 等 options")
TaskCreate(name="detect_spectra_context", description="Step 0.7: 偵測是否從 spectra-discuss 中斷進來（--resume-spectra flag / --source 含 spectra / spectra list 有 in-flight / .claude/state/idd-bridge.json）— 詳見 rules/spectra-bridge.md")
TaskCreate(name="validate_type_requirements", description="依 type 檢查必填欄位（decision 要 quote、note 要 source、link 要 target、errata 要 target-comment）")
TaskCreate(name="resolve_mentions", description="Step 1.5: 若有 --mention 或 body 含 @xxx，強制走 rules/tagging-collaborators.md 協定（gh api 取 collaborators → fuzzy match → AskUserQuestion fallback → 用 @login 不用 display name）")
TaskCreate(name="build_comment_body", description="按 type 對應 template 組 markdown（emoji header + blockquote + body + metadata marker），插入已驗證的 @login mentions")
TaskCreate(name="verify_mentions", description="post 前 grep body 的 @\\w+ 全部 cross-check 已驗證的 collaborator set；未驗證 token 直接 abort")
TaskCreate(name="post_comment", description="gh issue comment #NNN 用 --body-file 避免 escape 問題；errata type 額外 auto-call idd-edit")
TaskCreate(name="report_result", description="輸出 ✓ Comment posted + URL；errata type 加報 idd-edit 結果")
TaskCreate(name="auto_update_body", description="跑 /idd-update #NNN 同步 issue body Current Status（強制，常被漏；同 idd-close Step 6 模式）")
TaskCreate(name="spectra_bridge_resume", description="Step 7: 若 SPECTRA_BRIDGE_ACTIVE，寫 .claude/state/idd-bridge.json bookmark + 輸出 ↩ Resume spectra-discuss 區塊（rules/spectra-bridge.md）")
```

完成每一步立即 `TaskUpdate → completed`。**靜默完成 = 違規**。**TaskCreate 清單 = 真實的步驟清單；任何寫在 skill 裡但沒列進 TaskCreate 的步驟，都視為 skill 的 bug，必須補進 Task 清單。**

特別提醒：**`auto_update_body` 不可省略**——`idd-comment` 的 comment 本身（例如 decision / correction）會改變 issue 的當前狀態，body Current Status 區塊必須同步。歷史上 idd-close 2.18.0 同樣的「Report + Auto-update 合在一個 Step」設計造成大量漏跑，於 2.18.1 修正。

**v2.32.0 新增**：`detect_spectra_context` / `resolve_mentions` / `verify_mentions` / `spectra_bridge_resume` 四個 task 對應兩個新規則 [`rules/tagging-collaborators.md`](../../rules/tagging-collaborators.md) 與 [`rules/spectra-bridge.md`](../../rules/spectra-bridge.md)。違反這兩個規則 = skill bug。

---

### Step 0.7: Detect Spectra Context（v2.32.0+）

在 parse_args 完成後、validate 之前，依 [`rules/spectra-bridge.md`](../../rules/spectra-bridge.md) 偵測是否從 spectra-discuss 中斷進來：

```bash
SPECTRA_BRIDGE_ACTIVE=0
SPECTRA_TOPIC=""

# Signal 1: 顯式 flag
if [ -n "$RESUME_SPECTRA" ]; then
  SPECTRA_BRIDGE_ACTIVE=1
  SPECTRA_TOPIC="$RESUME_SPECTRA"
fi

# Signal 2: --source 含 spectra-discuss
if echo "$SOURCE" | grep -qi "spectra-discuss"; then
  SPECTRA_BRIDGE_ACTIVE=1
fi

# Signal 3: spectra list 有 in-flight
if command -v spectra >/dev/null 2>&1; then
  IN_FLIGHT=$(spectra list --json 2>/dev/null | jq '.changes | length')
  if [ "${IN_FLIGHT:-0}" -gt 0 ]; then
    SPECTRA_BRIDGE_ACTIVE=1
  fi
fi

# Signal 4: bookmark 已存在
if [ -f ".claude/state/idd-bridge.json" ]; then
  ACTIVE=$(jq -r '.active_spectra_session // false' .claude/state/idd-bridge.json 2>/dev/null)
  [ "$ACTIVE" = "true" ] && SPECTRA_BRIDGE_ACTIVE=1
fi
```

若 `SPECTRA_BRIDGE_ACTIVE=1`，告訴使用者：「Detected spectra context. Will emit resume prompt at the end.」這樣使用者知道末尾要找 resume block。

### Step 1: Parse arguments

```
/idd-comment #NNN --type=<type> [options]
```

Options (視 type 而定)：
- `--body="..."` — 主要內容
- `--quote="..."` — 原文引用（decision type 必填）
- `--source="..."` — 外部來源（note type 必填）
- `--target=#XX` — 目標 issue（link type 必填）
- `--target-comment=<id>` — 目標 comment ID（errata type 必填）
- `--deadline=YYYY-MM-DD` — 未決問題的期限（question type 可選）
- `--mention <login>[,<login>...]` — tag 人到 comment（**v2.32.0+**，強制走 [`rules/tagging-collaborators.md`](../../rules/tagging-collaborators.md)）
- `--mention-prompt` — 強制走 AskUserQuestion 從 collaborator menu 選（不嘗試 auto-resolve）
- `--resume-spectra="<topic>"` — 顯式宣告從 spectra-discuss 中斷進來（**v2.32.0+**，觸發 Step 7 resume prompt）

### Step 2: Validate type-specific requirements

| Type | 必填檢查 |
|------|---------|
| decision | `--quote` + `--body` 必存在 |
| note | `--source` + `--body` 必存在 |
| question | `--body` 必存在 |
| correction | `--body` 必存在 |
| link | `--target` + `--body` 必存在 |
| errata | `--target-comment` + `--body` 必存在 |

缺必填 → 用 AskUserQuestion 詢問。

### Step 2.5: Resolve Mentions（v2.32.0+）

若使用 `--mention` flag 或 body / quote / source 含 `@xxx`，**必須**遵循 [`rules/tagging-collaborators.md`](../../rules/tagging-collaborators.md) 的 5 步協定：

1. **Detect intent** — flag 或自然語言（"tag X" / "ping X" / "通知 X"）
2. **Fetch real list** — `gh api repos/$OWNER/$REPO/collaborators` + （若 org repo）`gh api orgs/$OWNER/members`
3. **Resolve** — fuzzy match against login + name field；唯一匹配直接用，否則 AskUserQuestion
4. **AskUserQuestion fallback** — 0 或 2+ 匹配時必選；options 用實際 collaborator list
5. **Verify** — post 前 grep `@\w+` token 全部 cross-check 已驗證 set；未驗證 token = abort

```bash
# Step 2 — 抓清單
OWNER=$(echo "$GITHUB_REPO" | cut -d/ -f1)
REPO=$(echo "$GITHUB_REPO" | cut -d/ -f2)
gh api repos/$OWNER/$REPO/collaborators --jq '.[] | {login, name}' \
  > /tmp/idd-collaborators-$$.json
```

**禁止**：從訓練記憶、聊天歷史、git log 推測 @handle。API 失敗 = 取消 tagging（post comment 但不含 mention，並告訴使用者）。

### Step 3: Build comment body

#### Template: `decision`

```markdown
## 🎯 Decision

> **Original** (YYYY-MM-DD)：
> 「{quote}」

### 決定
{body_prose — 1-2 句陳述做了什麼決定}

### Rationale
{body_prose — 至少 1 段完整論述，解釋為何選這個方向 + 排除其他選項的理由}

### Related
{auto-detect: scan body for #XX references}

<!-- idd:comment type=decision date=YYYY-MM-DD -->
```

#### Template: `note`

```markdown
## 📝 Note

**Source**: {source}
**Date**: YYYY-MM-DD

### 論述
{body_prose — 至少 1 段 prose 解釋 note 的 context 與含義}

### Details (optional)
{bullets / tables 補充細節}

<!-- idd:comment type=note date=YYYY-MM-DD source="{source}" -->
```

#### Template: `question`

```markdown
## ❓ Open Question

{body}

**Deadline**: {deadline or "TBD"}

<!-- idd:comment type=question date=YYYY-MM-DD status=open -->
```

#### Template: `correction`

```markdown
## 🔧 Correction

### 論述
{body_prose — 至少 1 段完整論述，解釋 (1) 先前的錯誤 claim、(2) 為何錯了、
(3) 正確的理解是什麼、(4) 對後續決策的含義。避免通篇 bullets。}

### Supporting evidence (optional)
{tables / bullets / links — 支撐上面論述的具體數字、引用、圖表}

### Related (optional)
{cross-reference issues / commits / comments}

<!-- idd:comment type=correction date=YYYY-MM-DD -->
```

#### Template: `link`

```markdown
## 🔗 Cross-reference: {target}

{body}

See also: {target}

<!-- idd:comment type=link date=YYYY-MM-DD target={target} -->
```

#### Template: `errata` (SPECIAL BEHAVIOUR)

```markdown
## ⚠️ Errata

This notice concerns [comment {target-comment}](https://github.com/{repo}/issues/{issue}#issuecomment-{target-comment}).

### 錯在哪
{body}

### 正確內容
請見本 errata 以下的新 comment（如有），或下方標示。

<!-- idd:comment type=errata date=YYYY-MM-DD target-comment={target-comment} -->
```

**Errata 的 auto-call idd-edit**：

建立 errata comment 後，**自動呼叫 idd-edit** 在 target comment 頂部加警示（prepend-note mode）：

```bash
# 自動執行（OWNER comment 或 bot comment）：
IDD_CALLER=idd-comment-errata \
  /idd-edit comment:{target-comment} --prepend-note --reason="See errata at <new comment URL>"
```

這讓 target comment 讀者看到「⚠️ 本 comment 已有 errata（下方）」的警示。

**v2.81.0+ (#154) R5 行為**：當 target comment 是 user-authored（非 OWNER 非 bot）時，`/idd-edit` 會 refuse with exit code 4 + 印 helpful message（per [#154](https://github.com/PsychQuant/issue-driven-development/issues/154) D2 decision — 不 auto-override per IC_R007 user-authored-intent spirit）。 處理:

```bash
# Auto-call 偵測 exit code 4 → idd-comment 顯示 hint:
if [ $EDIT_EXIT -eq 4 ]; then
  cat <<EOF >&2

Errata target comment $TARGET_COMMENT is user-authored.
Per IDD R5 discipline (rules/append-vs-modify.md), modifying user content requires explicit consent.

Manually run:
  /idd-edit comment:$TARGET_COMMENT --prepend-note \\
    --override-user-content \\
    --reason='errata clarification per IDD discipline — see new errata at $NEW_ERRATA_URL'
EOF
  # errata comment 本身已成功 post — 只 prepend-note marker 需 user 顯式 consent
fi
```

完整 R4/R5 規範 + override pathway 見 [`/idd-edit` SKILL.md](../idd-edit/SKILL.md) `## Runtime gates (#154, v2.81.0+)`。

### Step 3.5: Verify mentions (v2.32.0+)

Post 前最後一道防線：

```bash
# 抓 body 中所有 @xxx token
MENTIONS=$(grep -oE '@[A-Za-z0-9-]+' /tmp/idd-comment-body-$$.md | sort -u)

for handle in $MENTIONS; do
  login=${handle#@}
  if ! jq -e ".[] | select(.login == \"$login\")" /tmp/idd-collaborators-$$.json > /dev/null 2>&1; then
    echo "ERROR: $handle not in collaborator list. Aborting post."
    echo "若這真是 collaborator 但 API 沒列到（outside collaborator / 私人 repo），用 --mention-prompt 強制選單。"
    rm -f /tmp/idd-comment-body-$$.md /tmp/idd-collaborators-$$.json
    exit 1
  fi
done
```

通過驗證才進 Step 4。

### Step 4: Post comment

```bash
# 用 --body-file 避免 backtick / 多行 escape 問題
echo "$COMMENT_BODY" > /tmp/idd-comment-$$.md
gh issue comment $NUMBER --repo $GITHUB_REPO --body-file /tmp/idd-comment-$$.md
rm /tmp/idd-comment-$$.md
```

### Step 5: Report

```
✓ Comment posted to #NNN (type: {type})
  URL: {comment URL}
```

如果 type = errata → 額外報告 idd-edit 的結果。

### Step 6: Auto-Update Issue Body（強制，不可省略）

```
Skill(skill="issue-driven-dev:idd-update", args="#NNN")
```

或等價手動執行 `/idd-update #NNN`。

**為何強制**：`idd-comment` post 的 decision / correction / question 會改變 issue 的 Current Status；不同步 body 會導致 `gh issue view` 與 `idd-list` 看到舊 phase。歷史上 idd-close 2.18.0 同樣把 Report + Auto-update 合在一個 Step，造成大量漏跑（見 idd-close 2.18.1 fix）。

### Step 7: Spectra Bridge Resume Prompt（v2.32.0+，僅當 SPECTRA_BRIDGE_ACTIVE=1）

依 [`rules/spectra-bridge.md`](../../rules/spectra-bridge.md) 執行兩件事：

#### 7.1 寫 bookmark 檔

```bash
mkdir -p .claude/state
cat > .claude/state/idd-bridge.json <<EOF
{
  "version": 1,
  "created_at": "$(date -u +%Y-%m-%dT%H:%M:%S%z)",
  "spectra_topic": "$SPECTRA_TOPIC",
  "issue_number": $NUMBER,
  "issue_url": "https://github.com/$GITHUB_REPO/issues/$NUMBER",
  "idd_action": "idd-comment",
  "idd_action_url": "$COMMENT_URL",
  "open_questions": $OPEN_QUESTIONS_JSON,
  "next_step_hint": "/spectra-discuss 接續 #$NUMBER 的討論..."
}
EOF
```

若已存在，merge 而非覆寫（保留更早的 `open_questions`，更新 `idd_action` 為最新）。

#### 7.2 輸出 Resume Prompt 區塊

```
↩ Resume spectra-discuss
═══════════════════════════════════════════════════════════
Paste the following prompt back into the spectra-discuss session
to continue with full context preserved:

  /spectra-discuss 接續 ${SPECTRA_TOPIC} 的討論。
  上輪結論已 comment 到 issue #${NUMBER}（${COMMENT_URL}）。
  ${MENTIONS_LINE}
  待解問題:
  ${OPEN_QUESTIONS_BULLETS}

State saved to: .claude/state/idd-bridge.json
═══════════════════════════════════════════════════════════
```

**鐵律**：
- **Never auto-invoke `/spectra-discuss`** — 使用者控 pacing
- Bookmark 寫失敗 → 印 warning 但 resume prompt 還是要輸出（prompt 才是真正的 recovery）
- Topic 必須 verbatim，不要 paraphrase

## Metadata Marker 格式

HTML comment 在 GitHub 不渲染，但可 parse：

```html
<!-- idd:comment type=<type> date=<date> [extra=<value>]* -->
```

未來可用 `gh api ... --jq` grep marker 做 comment type filtering（例如 "列出這個 issue 所有 decisions"）。

## 使用範例

### Decision

```
/idd-comment #16 --type=decision \
  --quote="A + D 組合（原始順序 + Intro transparency paragraph）" \
  --body="採方向 A+D，Primary + Boundary thesis 替代 Dual Mechanism。

方向 B 有 HARKing 風險；方向 A 尊重真實研究歷程。"
```

### Note (advisor feedback)

```
/idd-comment #15 --type=note \
  --source="Advisor meeting 2026-04-15" \
  --body="老師同意採用 Primary + Boundary framing，但希望保留 Dual Mechanism 名稱作為 abstract 層級的簡稱。"
```

### Errata (自動 prepend 警示)

```
/idd-comment #17 --type=errata \
  --target-comment=4241327867 \
  --body="原 comment 聲稱 'Holm 校正後 p=.049 顯著'，實際 Holm 未正確校正。真正校正後 p=.146 n.s."
```

→ 自動在 comment 4241327867 頂部加「⚠️ See errata below」警示。

### Note with mention (v2.32.0+)

```
/idd-comment #96 --type=note \
  --source="spectra-discuss session 2026-04-28" \
  --mention=Hardy1Yang \
  --body="..."
```

→ 觸發 [`rules/tagging-collaborators.md`](../../rules/tagging-collaborators.md)：抓 `gh api repos/PsychQuant/contact-book/collaborators` → 找到 `@Hardy1Yang` → 插入 body → verify pass → post。

### Spectra-bridge resume (v2.32.0+)

```
/idd-comment #96 --type=note \
  --source="spectra-discuss session 2026-04-28" \
  --resume-spectra="ContactBook 雲端資料層 — CloudKit vs Supabase" \
  --mention=Hardy1Yang \
  --body="..."
```

→ Step 0.7 detect 命中 → Step 7 寫 `.claude/state/idd-bridge.json` + 印 `↩ Resume spectra-discuss` 區塊讓使用者貼回 spectra session。

## 鐵律

- **第一段必 prose**：`decision` / `note` / `correction` 三個長 body 的 types，body 必須以**至少一段完整論述段落（3+ 句）**開頭，解釋 context 與推論鏈條。之後才能接 tables / bullets 作 supporting evidence。**避免通篇 bullet-only**——bullets 容易把邏輯 gap 隱藏在排版底下，三個月後回讀無法重建脈絡。
- **原文必 blockquote**：`decision` type 的 `--quote` 必用 `>` 包住
- **Timestamp 必加**：所有 types 的 metadata marker 含 date
- **errata 必 auto-call idd-edit**：確保 target comment 本體也被警示
- **不走 phase detection**：idd-comment 是 ad-hoc，不觸發 phase 推斷（那是 idd-update 的事）
- **Comment body 要自我解釋**：三個月後回來看，光看 comment 就知道 context。這是「第一段 prose」的動機。
- **任何 @xxx 必走 collaborator API**（v2.32.0+）：禁止從訓練記憶 / 聊天歷史 / git log 推測 handle。違反 = 通知錯人，不可逆。詳見 [`rules/tagging-collaborators.md`](../../rules/tagging-collaborators.md)。
- **Spectra context 不可靜默忽略**（v2.32.0+）：偵測到從 spectra-discuss 進來必須印 resume prompt。使用者要不要回去 spectra 是他的事，但 skill 不能讓 context 默默掉地。

## 與其他 idd-* skill 的關係

| Skill | comment 類型 | 何時用 |
|-------|------|------|
| `idd-issue` | Problem / Type / Expected | 建立 issue |
| `idd-diagnose` | Diagnosis report | 分析 root cause |
| `idd-implement` | Implementation Plan / Complete | 實作前/後 |
| `idd-verify` | Verify findings | 驗證結果 |
| `idd-close` | Closing Summary | 結案 |
| **`idd-comment`** | **Ad-hoc 決定 / 外部 context / 未決問題** | **流程外的重要記錄** |
| `idd-update` | Body Current Status | 其他 skill 結尾自動呼叫 |
| `idd-edit` | 編輯既有 comment | 修 typo / 補說明 / 標記過時 |

## Next Step

一般情境：comment 後繼續當前 phase（diagnose / implement / verify）。

Errata 情境：comment 後若要同時改 target comment 內容，手動執行：
```
/idd-edit comment:<target-id> --replace --body-file=...
```
