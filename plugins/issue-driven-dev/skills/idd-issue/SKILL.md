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
TaskCreate(name="detect_target_repo", description="Step 0.5: 解析 target — --target flag → walked-up config → predicate pre-resolve → fork detection")
TaskCreate(name="read_source", description="讀取來源(docx → mcp__che-word-mcp 讀文字 + 列圖片)")
TaskCreate(name="gather_info", description="Step 2: 蒐集 title / type / priority / description")
TaskCreate(name="reresolve_target", description="Step 2.5: 用 title/labels 重評 content predicates,若新匹配 != tentative_default 則問使用者要不要切")
TaskCreate(name="create_issue", description="Step 3: gh issue create — Single mode 或 Group mode(primary + tracking + cross-link comment)")
TaskCreate(name="attach_images", description="上傳圖片到 attachments release 並編輯 issue body 嵌入(若有)")
TaskCreate(name="create_milestone", description="來源為文件時自動建立 milestone 並指派(見 Step 4.5)")
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

# 2. 查 origin 是不是 fork,以及 upstream 是誰
REPO_JSON=$(gh repo view "$ORIGIN" --json isFork,parent 2>/dev/null)
IS_FORK=$(echo "$REPO_JSON" | jq -r '.isFork')
UPSTREAM=$(echo "$REPO_JSON" | jq -r '.parent.nameWithOwner // empty')
```

接下來按既有邏輯:

**E1. `IS_FORK=false`（不是 fork）**

直接用 origin,**寫入 config 到 `$PWD/.claude/issue-driven-dev.local.json`**,繼續。不需要詢問。

**E2. `IS_FORK=true` 且 `UPSTREAM` 存在** → **強制使用 `AskUserQuestion` 呈現三選項**：

| 選項 | target | 適合情境 |
|------|--------|---------|
| **Upstream** (`$UPSTREAM`) | upstream | Bug report、feature 提議、跟原作者討論架構、PR 先行討論 |
| **Own fork** (`$ORIGIN`) | origin | 個人 TODO、客製化筆記、只給自己看的追蹤、路線分岔後的獨立專案 |
| **Both (cross-linked)** | upstream 主 + origin 追蹤 | 想貢獻上游但同時要在自己 fork 記錄進度 |

「Both」模式：等同於建立一個 ad-hoc group(primary=upstream, tracking=origin)。Step 3 會走 group flow。

#### F. 寫回 config(僅在 Step 0.5.E 觸發時)

無論 E1/E2 選了什麼，都把結果寫入 `$PWD/.claude/issue-driven-dev.local.json`：

```json
{
  "github_repo": "chosen/repo",
  "github_owner": "chosen",
  "attachments_release": "attachments",
  "tracking_upstream": "upstream/repo"
}
```

`tracking_upstream` 只在 Both 模式或 fork 情境下寫入（讓後續 skill 知道 upstream 是誰）。

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

依來源類型挑對應的讀取 + 抽附件 tool；**Step 4 上傳時不分類型，一視同仁全部 push 到 release**。

| Source type | 讀文字 | 抽附件 |
|-------------|--------|--------|
| `.docx` / `.doc` | `mcp__che-word-mcp__get_document_text(source_path)` | `mcp__che-word-mcp__list_images` → `mcp__che-word-mcp__export_image(image_id, output_path)` 逐張存檔 |
| `.pdf` | `pdftotext` 或 `mcp__che-word-mcp` 開啟（若可） | `pdfimages -all input.pdf prefix` 抽全部嵌入圖 |
| Telegram chat range | `mcp__plugin_che-telegram-mcp_telegram-all__get_chat_history(chat_id, limit)` 或 `dump_chat_to_markdown` | 列舉 chat 中所有 `[photo]` / `[document]` / `[video]` placeholder → 嘗試 MCP `download_file`（若存在）→ 否則**明列檔名 + 必要請求**讓使用者用 Telegram client 手動存檔到指定路徑後 skill 接手 upload |
| Apple Mail / 郵件 | `mcp__plugin_che-apple-mail-mcp_mail__get_email(message_id)` | `list_attachments` → `save_attachment(filename, output_path)` |
| Apple Notes | `mcp__plugin_che-apple-notes-mcp_notes__get_note` | 同上 export 全部 inline 圖 |
| 直接貼文字（無附件） | argument 直接帶文字 | n/a |
| 混合（文字 + 圖片貼上） | argument 帶文字 + 使用者另外提供 path 清單 | 把使用者給的 path 全部納入 Step 4 上傳清單 |

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

根據 Step 0.5 / Step 2.5 解析結果,分兩種情境:

- **Single repo 模式**(常見) → 直接 `gh issue create` 到 `$GITHUB_REPO`,如下方範例
- **Group 模式**(`tentative_default` 或 user 選擇是 group,或 fork-aware 選了 Both) → 走 Step 3.G(下一節)

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

### Step 5: 回報並停止

輸出：issue number、URL、labels、type。
如果有 milestone：輸出 milestone name、URL、issue count。

提示下一步：`/issue-driven-dev:idd-diagnose #NNN`

> **CRITICAL: 建立 issue 後必須停止。不要自動開始 diagnose 或 implement。**
> Issue 建立是人的決定點 — 人決定優先級、分配、時機。
> AI 不應該擅自開始解決問題。等使用者明確說「開始做」或呼叫 `idd-diagnose` 才繼續。

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
