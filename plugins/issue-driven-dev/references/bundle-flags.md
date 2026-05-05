# Bundle Flags Reference

`idd-issue` 對 ordered/unordered issue bundle 的 first-class 支援(v2.52.0+)。本文件是 `--parent` / `--blocked-by` / `--bundle-mode` 三個 flag 的 canonical reference。

> **TL;DR**:GitHub 提供三個原生 primitive:**parent body task list**(自動渲染 sub-issues + 進度條)、**Blocked-by dependency**(GraphQL `addBlockedByDependency`)、**milestone**(分組無依賴)。本機制把前兩個包進 `idd-issue` 的 flag 介面,讓常見的 ordered/unordered bundle 一個指令完成,並保證 idempotent + graceful degradation。

## Overview — 三個正交軸

`idd-issue` 在 v2.52.0 之前已支援兩個軸:

| 軸 | 機制 | 表達 |
|----|------|------|
| **分組(時間/範圍)** | Step 4.5 milestone | 「這 N 個 issue 屬於同一個 release / 文件 / 階段」 |
| **跨 repo cross-link** | `groups` 機制 | 「這個邏輯 issue 在多個 repo 都要追蹤」 |
| **同 repo parent-child + 順序**(NEW v2.52.0) | bundle flags | 「這 N 個 issue 有 epic + dependency」 |

三軸正交:同一個 bundle 可以同時隸屬於 milestone,parent epic 也可以是 group 的 primary。

## Flag Spec

### `--parent <N>`

把當下建立的 child issue 加進 parent #N body 的 task list 段落。

| 屬性 | 值 |
|------|------|
| 取值 | 正整數 issue number(parent 的 #N) |
| 多值 | 不支援(一次只能掛一個 parent) |
| 副作用 | 1. 建 child(`gh issue create`)<br>2. PATCH parent body(append `- [ ] #child` 到 task list) |
| Idempotent | ✅ 重複呼叫同 flag 不產生重複 entry |
| Cross-repo | ❌ refuse + 指引 `groups` 機制 |

```bash
# 範例:加新 child 到既存 parent #100
idd-issue --parent 100 "Step 4: 加 email 通知"
```

### `--blocked-by <M>[,<M2>...]`

在當下建立的 child body 加 Blocked-by 標註,並嘗試 GitHub 原生 dependency。

| 屬性 | 值 |
|------|------|
| 取值 | 逗號分隔的正整數 issue number list |
| 多值 | ✅ `--blocked-by 50,51,52` |
| 副作用 | 1. Body prepend `> Blocked by #M` blockquote(每個 M 一行)<br>2. 嘗試 GraphQL `addBlockedByDependency` mutation<br>3. 若 `--parent` 同時 used:在 parent task list entry 加 `(blocked by #M)` 註解 |
| Graceful degradation | ✅ GraphQL 失敗 → warning + 繼續,不 abort |
| Cross-repo blocked-by | ❌ 同 repo only(跨 repo 用 cross-reference link 即可) |

```bash
# 範例:單一 dependency
idd-issue --blocked-by 50 "Step 2: 加 /signup API"

# 範例:多重 dependency
idd-issue --blocked-by 50,51 "Step 3: 加登入 UI"

# 範例:組合 --parent + --blocked-by
idd-issue --parent 100 --blocked-by 50 "Step 2: 加 /signup API"
# parent #100 的 task list 會記為 `- [ ] #child (blocked by #50)`
```

### `--bundle-mode <ordered|unordered>`

單次 invocation 建多個 issue 時,自動 orchestrate parent + N children + (ordered 時)Blocked-by 鏈。

| 屬性 | 值 |
|------|------|
| 取值 | `ordered` 或 `unordered`(enum 形式,可擴充) |
| 觸發條件 | 同次 invocation 必須 ≥2 個 item;單一 item 直接 refuse |
| 副作用 | 1. 建 1 個 epic parent<br>2. 建 N 個 children,每個 auto-applied `--parent <epic>`<br>3. `ordered` 模式:每個 child(從第二個起)auto-applied `--blocked-by <prev-child>`<br>4. `unordered` 模式:純 task list,不加 Blocked-by |
| Group mode 互斥 | ❌ `--bundle-mode` 和 group mode(`--target group:<label>`)互斥;同時 set → refuse |

```bash
# 範例:ordered bundle
idd-issue --bundle-mode ordered "做會員系統:建 schema; 加 API; 加 UI; 接 email"
# → 建 epic + 4 children,child2 blocked by child1, child3 blocked by child2, child4 blocked by child3

# 範例:unordered bundle
idd-issue --bundle-mode unordered "首頁優化:換 hero 圖; footer 對齊; 加暗色模式"
# → 建 epic + 3 children,純 task list,無 Blocked-by
```

## Edit Algorithm — Parent Body Task List

PATCH parent body 加 child entry 時,演算法保證 idempotency:

```
1. 找 task list 段落:
   - 掃 parent body,找第一個含 `- [ ]` 或 `- [x]` 的連續區段(連續 = 中間沒有非 task list 行 / 段落分隔)
   - 若找不到 → 在 body 末尾新增 `## Children` 段落作為 anchor(空段落,接著 append child)

2. 檢查重複:
   - Scan 該段落每個 entry 的 `#N` reference(規則化:取 `#\d+` 第一個 match)
   - 若 `#child` 已存在 → no-op(idempotent skip)

3. Append:
   - 若不存在 → 在段落末尾加 `- [ ] #child` 一行
   - 若 `--blocked-by <M>` 同時 used → entry 改為 `- [ ] #child (blocked by #M)`(多重 blocked-by 用逗號分隔)

4. 保留現有結構:
   - 不重排現有 entry
   - 不修改 task list 段落以外的 body 內容
   - 不 normalize 其他人手寫的 entry(如 `- [ ] #50 — description`)
```

### 為什麼掃 `#N` 而非 line-level diff

使用者可能會手動編輯 entry(改 description / 加註解 / 重排),line-level 比對會誤判為「不同」進而 append 重複。`#N` 是 stable identifier。

### 為什麼 anchor 用 `## Children`

採用 GitHub 原生 sub-issue 渲染慣例,不破壞既有 body 內容。若使用者偏好其他 anchor 名稱(如 `## Tasks`),可手動在 parent body 預先建立空的 task list,演算法步驟 1 會偵測到該段落並使用,不會重新建 `## Children`。

### Edit 結果矩陣

| Parent body before | Invocation | Parent body after |
|---|---|---|
| `## Children\n- [ ] #101\n- [ ] #102\n` | `--parent <P> #103` | `## Children\n- [ ] #101\n- [ ] #102\n- [ ] #103\n` |
| `## Children\n- [ ] #101\n- [ ] #102\n- [ ] #103\n` | `--parent <P> #103`(retry) | `## Children\n- [ ] #101\n- [ ] #102\n- [ ] #103\n`(no-op) |
| `Plain prose body, no checkboxes` | `--parent <P> #103` | `Plain prose body, no checkboxes\n\n## Children\n- [ ] #103\n` |
| `## Repro\n- [ ] open app\n- [ ] click X` | `--parent <P> #103` | `## Repro\n- [ ] open app\n- [ ] click X\n\n## Children\n- [ ] #103\n`(新建獨立 anchor,不污染 Repro) |
| `## Children\n- [ ] #101\n` | `--parent <P> --blocked-by 50 #103` | `## Children\n- [ ] #101\n- [ ] #103 (blocked by #50)\n` |

## Fallback Chain — Blocked-By Three-Layer

當 `--blocked-by <M>` 觸發時,**三層全部執行**(不是「失敗才下一層」),保證至少有一層讓 dependency 可見:

### Layer 1 — GitHub GraphQL native dependency(嘗試)

呼叫 `addBlockedByDependency` GraphQL mutation,把 child issue 跟 #M 綁成原生 Blocked-by 關係。

```bash
gh api graphql -f query='
mutation($issueId:ID!, $blockedById:ID!) {
  addBlockedByDependency(input: {
    issueId: $issueId,
    blockedByIssueId: $blockedById
  }) {
    issue { id }
  }
}' -F issueId="$CHILD_NODE_ID" -F blockedById="$M_NODE_ID"
```

成功效果:
- GitHub UI 顯示 「Blocked by #M」 紅色 warning
- Issue side panel 顯示原生 dependency
- task list 自動連動(parent 看 #M close 才解 child block)

失敗情境:
- Repo / org 未 enable native dependency feature
- API rate limit
- 權限不足
- Issue 跨 repo(GraphQL mutation 限同 repo)

**失敗處理**:emit warning 名指 `M` 和 failure reason,**不 abort** child issue 建立。

### Layer 2 — Body blockquote 標註(無條件)

無論 Layer 1 成功或失敗,**一律**在 child body 開頭加 blockquote:

```markdown
> Blocked by #50

(其餘原本的 body...)
```

多個 blocked-by 各自一行:

```markdown
> Blocked by #50
> Blocked by #51

(其餘 body...)
```

**為什麼一律執行**:Layer 1 native dep 在 `gh issue view --web` 才看得到,但 body blockquote 在 CLI / API / 任何 markdown viewer 都看得到。雙重保險的代價只是 1 行 body 內容,benefit 是「永遠有可讀的 dependency 標註」。

### Layer 3 — Parent task list annotation(僅 `--parent` co-used 時)

當 `--parent <N>` 同時 used,parent task list entry 加 `(blocked by #M)` 註解:

```markdown
## Children
- [ ] #101
- [ ] #102 (blocked by #101)
- [ ] #103 (blocked by #102)
```

效果:從 parent epic 視角直接看到 dependency 鏈,不需要點進 child 才看到。

## Partial Failure Handling

Bundle 或 multi-target 操作的失敗情境分類處理:

| 失敗情境 | 行為 |
|---------|------|
| `--bundle-mode` 中第一個 child 建立失敗 | abort 整個 invocation,清理已建的 epic(如果已建)。錯誤訊息名指失敗 child 的 title |
| `--bundle-mode` 中第 N 個 child 建立失敗(N>1) | 不 abort 已建的 children;**continue** 後續 children;最後報告 partial success(N-1 成功 / total)。使用者可以重跑 invocation 並用 `--parent <epic>` 補建 |
| `--blocked-by 50,51,52` 中某個 mutation 失敗 | 該 target 的 Layer 1 失敗 → warning + 繼續嘗試下個 target;Layer 2 body blockquote 一律加(包括失敗的 target);Layer 3 parent annotation 一律加 |
| Parent body PATCH 失敗(權限 / API error) | child 仍建立成功;parent body 未更新 → warning + 退出非零 code,使用者可 `gh issue edit` 手動補 |
| GraphQL `addBlockedByDependency` 對全部 target 都失敗 | child 仍建立成功;child body 仍含 `> Blocked by #M` blockquote;每個 target 各自一條 warning |

## Idempotency Contract

| 操作 | Idempotent? | 機制 |
|------|------------|------|
| `--parent <N>` 重複呼叫(同一 child) | ✅ | Edit algorithm Step 2 掃 `#N` reference;already-exists → no-op skip |
| `--blocked-by <M>` 重複呼叫(同一 child) | ✅(body)/ ⚠(GraphQL) | Body blockquote 重複 prepend 會產生重複行 → 演算法掃 `> Blocked by #M` 字串先 dedup;GraphQL mutation 重複呼叫由 GitHub 端 dedup(no-op for already-blocking pair) |
| `--bundle-mode` 重複呼叫(同樣 input) | ❌ | bundle 必然建新 epic + 新 children;使用者責任避免重複呼叫 |

**為什麼 `--bundle-mode` 不 idempotent**:bundle 把 N 個 child 視為一次性 transaction,沒有 stable identifier 可掃。idempotency 只在「個別 child 的 parent / blocked-by 標註」層級保證。

## Cross-Repo Refuse

當 `--parent <N>` 偵測到 #N 不在當前解析的 target repo(透過 `idd-issue` Step 0.5 / Step 2.5 機制決定的 `$GITHUB_REPO`):

```
RESOLVED_TARGET=$(... Step 0.5/2.5 logic ...)
PARENT_REPO=$(gh issue view "$N" --json repository --jq '.repository.nameWithOwner' 2>/dev/null)

if [ "$PARENT_REPO" != "$RESOLVED_TARGET" ]; then
  echo "✗ refuse: parent #$N is in '$PARENT_REPO' but target repo is '$RESOLVED_TARGET'"
  echo "  Bundle mechanism is same-repo only."
  echo "  For cross-repo coordinated issues, use the 'groups' mechanism."
  echo "  See plugins/issue-driven-dev/CLAUDE.md § Configuration § groups."
  exit 1
fi
```

### 為什麼不降級到 group 機制

跨 repo parent-child 是不同的 mental model:

| 機制 | 目的 | 結構 |
|------|------|------|
| Bundle(同 repo) | 表達 epic + dependency | parent body task list + GraphQL native dep + body blockquote |
| Group(跨 repo) | 表達多 repo 同步追蹤 | primary issue body 完整 + tracking issues body 含 `Tracking primary: X#N` + cross-link comment |

Mixing them silently 會讓 task list 渲染失效(GitHub task list 跨 repo 不連動進度條)。明確 refuse + 指引到 groups 比 silent 降級安全。

### Group mode 與 `--bundle-mode` 互斥

`--target group:<label>` 解析到 group(`tentative_default` 是 group),然後 user 又下 `--bundle-mode ordered` → refuse:

```
✗ refuse: --bundle-mode 和 group mode 互斥
  group mode 已 implicitly 表達多 issue + cross-link;
  bundle 是同 repo parent-child + dependency,語意不同。
  請選一個。
```

## Orthogonality with Existing Mechanisms

Bundle flags **不修改**既有 `idd-issue` 機制:

### Step 4.5 Auto-milestone

當來源是文件且建了 ≥2 個 issue 時:

- 不論 `--bundle-mode` 是否 used,Step 4.5 仍建 milestone
- bundle children 全部 assign 到該 milestone
- bundle 的 epic parent 也 assign 到該 milestone

```
文件來源 + --bundle-mode ordered → 1 milestone + 1 epic + N children(全部都在 milestone)
```

### Step 4.7 Sister Sweep

- 對 bundle 的 epic parent 仍跑 sister sweep(掃 epic body draft + linked attachments + recent conversation)
- Sister sweep 提出的 sibling issues 不會被加進 epic 的 task list(它們是正交的旁支,非 bundle 子 issue)

### Group Mode

- Group mode(`groups[]` config 或 `--target group:<label>`)和 `--bundle-mode` **互斥**(同時 set → refuse,見上)
- 但 group mode 的 primary issue **可以**之後用 `--parent <primary>` 加 child(即把 primary 當 epic)— 這是漸進式組合
- Group mode 的 tracking issues 不參與 bundle(不能對 tracking issue 用 `--parent`,refuse)

### Step 0.5 / Step 2.5 Target Resolution

- Bundle flag 處理在 target resolution 之後;target 解析失敗 → bundle 操作不會嘗試
- Cross-repo refuse 用解析後的 `$GITHUB_REPO` 作為 source of truth

## Why no separate `/idd-bundle` skill

考慮過另開一個 `/idd-bundle` skill 但選擇加 flag 到 `idd-issue`,理由:

1. **70% 重疊**:bundle 仍要 target resolution(Step 0.5)、attachment upload(Step 4)、mention validation(Step 2.6)、sister sweep(Step 4.7),這些邏輯不該複製
2. **漸進式採用**:`--parent <N>` 可以單獨用(對既存 parent 加 child);`--blocked-by` 可以獨立用(不一定要有 parent);`--bundle-mode` 是高階組合。三 flag 各有獨立用途,不需要 mega skill
3. **Skill 數量已多**:IDD 已有 14+ skills,新增 skill 的 cognitive cost 不值得 ~30% 獨特功能

詳細抉擇見 design.md `### Decision: Flag 介面拆三層而非單一 mega flag`。

## See Also

- `plugins/issue-driven-dev/skills/idd-issue/SKILL.md § Ordered Bundle Pattern` — 使用者導向的 pattern 介紹
- `plugins/issue-driven-dev/CLAUDE.md § Configuration § Groups` — cross-repo 場景的正確機制
- GitHub Docs: [Issue dependencies](https://docs.github.com/en/issues/managing-your-work-with-issues/managing-dependencies-and-blockers) — `addBlockedByDependency` 原生功能
- GitHub Docs: [Issue task lists / sub-issues](https://docs.github.com/en/issues/managing-your-work-with-issues/about-sub-issues) — parent task list 渲染慣例
