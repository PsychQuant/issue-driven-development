---
name: idd-comment
description: |
  加 template-guided comment 到 GitHub issue。
  支援 decision/note/question/correction/link/errata 6 個 types，強制 blockquote 原文、加 timestamp 與 metadata marker。
  用於記錄使用者決定、外部 context、開放問題，不走完整 diagnose/implement phase 時。
  防止的失敗：非流程性 decision 散落在 chat，未來無法追溯。
argument-hint: "#issue --type=<type> [options]"
allowed-tools:
  - Bash(gh:*)
  - Read
  - Write
---

# /idd-comment — Template-guided issue comment

快速記錄決策、外部 context、未決問題到 issue，不用走完整 diagnose/implement phase。

## 核心原則

> 使用者的決定、外部 context、未決問題，都應該**留在 issue 裡**，不是 chat history。Comment 是 audit trail。

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

讀取 `.claude/issue-driven-dev.local.md` frontmatter 取得 `github_repo`。

## Execution

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
# 自動執行：
/idd-edit comment:{target-comment} --prepend-note --reason="See errata at <new comment URL>"
```

這讓 target comment 讀者看到「⚠️ 本 comment 已有 errata（下方）」的警示。

### Step 4: Post comment

```bash
# 用 --body-file 避免 backtick / 多行 escape 問題
echo "$COMMENT_BODY" > /tmp/idd-comment-$$.md
gh issue comment $NUMBER --repo $GITHUB_REPO --body-file /tmp/idd-comment-$$.md
rm /tmp/idd-comment-$$.md
```

### Step 5: Report + Auto-update

```
✓ Comment posted to #NNN (type: {type})
  URL: {comment URL}
```

如果 type = errata → 額外報告 idd-edit 的結果。

最後呼叫 `idd-update #NNN`（同步 body Current Status）。

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

## 鐵律

- **第一段必 prose**：`decision` / `note` / `correction` 三個長 body 的 types，body 必須以**至少一段完整論述段落（3+ 句）**開頭，解釋 context 與推論鏈條。之後才能接 tables / bullets 作 supporting evidence。**避免通篇 bullet-only**——bullets 容易把邏輯 gap 隱藏在排版底下，三個月後回讀無法重建脈絡。
- **原文必 blockquote**：`decision` type 的 `--quote` 必用 `>` 包住
- **Timestamp 必加**：所有 types 的 metadata marker 含 date
- **errata 必 auto-call idd-edit**：確保 target comment 本體也被警示
- **不走 phase detection**：idd-comment 是 ad-hoc，不觸發 phase 推斷（那是 idd-update 的事）
- **Comment body 要自我解釋**：三個月後回來看，光看 comment 就知道 context。這是「第一段 prose」的動機。

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
