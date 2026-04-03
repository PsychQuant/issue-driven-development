---
name: idd-report
description: |
  產出進度報告到 GitHub Discussions。
  可指定 issue 清單、來源檔案、或 milestone，彙整所有相關 issue 的處理狀態。
  Use when: milestone 完成、Sprint review、向客戶/主管匯報進度。
argument-hint: "#157 #158 ... 或 source:檔案名 或 milestone:名稱 [@tag1 @tag2]"
allowed-tools:
  - Bash(gh:*)
  - Read
  - Grep
  - Glob
  - WebFetch
---

# /idd-report — 進度報告

從 GitHub Issues 彙整進度，發布到 GitHub Discussions。

## 核心原則

> 報告是給人看的，不是給工程師看的。引用原文，白話解釋，量化成果。

## 參數格式

```
/idd-report #157 #158 #159                    → 指定 issues
/idd-report source:網站調整內容.docx           → 所有來自該檔案的 issues
/idd-report milestone:UX Redesign             → milestone 下所有 issues
/idd-report #157 #158 @Hardy1Yang @che        → 指定 issues + tag 人
/idd-report milestone:UX Redesign @hardy      → milestone + tag
```

## Configuration

讀取 `.claude/issue-driven-dev.local.md` frontmatter：

```yaml
---
github_repo: "owner/repo"
github_owner: "owner"
attachments_release: "attachments"
---
```

## Execution

### Step 1: Parse Arguments

從 `$ARGUMENTS` 解析：

1. **Issues**：所有 `#NNN` → issue number 清單
2. **Source file**：`source:檔案名` → 搜尋 issue body 含該檔案名的 issues
3. **Milestone**：`milestone:名稱` → 該 milestone 下所有 issues
4. **Tags**：所有 `@username` → 報告末尾 mention

如果沒有任何指定，提示使用者。

### Step 2: 收集 Issue 資料

```bash
# 方式 A: 指定 issues
for n in $ISSUE_NUMBERS; do
  gh issue view $n --repo $GITHUB_REPO \
    --json number,title,state,body,labels,comments,closedAt,createdAt
done

# 方式 B: 來源檔案
gh issue list --repo $GITHUB_REPO --state all --limit 100 \
  --json number,title,state,body,labels,closedAt \
  | jq '[.[] | select(.body | contains("'$SOURCE_FILE'"))]'

# 方式 C: Milestone
gh issue list --repo $GITHUB_REPO --state all --milestone "$MILESTONE_NAME" \
  --json number,title,state,body,labels,closedAt
```

### Step 3: 驗證完整性

對每個 issue 檢查：

```bash
# 找對應 commits
git log --all --oneline --grep="#$NUMBER" | head -5

# 找對應 PR
gh pr list --repo $GITHUB_REPO --state merged --search "#$NUMBER" \
  --json number,title,mergedAt,additions,deletions
```

產出驗證表：

```markdown
| # | Issue | 狀態 | PR | 變更量 | 驗證 |
|---|-------|------|----|--------|------|
| 1 | #157 首頁架構 | CLOSED | #165 | +314/-496 | ✅ |
| 2 | #158 Hero F型 | CLOSED | #167 | +82/-65 | ✅ |
| 3 | #260 某功能 | OPEN | — | — | 🔴 尚未完成 |
```

### Step 4: 讀取每個 Issue 的細節

對每個 CLOSED issue：

1. **讀 issue body** — 擷取 `Problem` 段落中的原文引用（blockquote）
2. **讀 closing comment**（如果有）— 擷取 Solution 和 Verification
3. **讀 PR diff stats** — 量化改動規模

### Step 5: 產出報告

#### 報告模板

```markdown
# {Project} 進度報告

> **報告日期**：{YYYY-MM-DD}
> **來源**：{source_file / milestone_name / 手動指定}
> **處理狀態**：{closed_count} / {total_count} 個問題已解決

---

## 總覽

{來源描述}共包含 {total_count} 個工作項目。
目前 {closed_count} 個已完成，{open_count} 個處理中。

### 變更統計

| 指標 | 數值 |
|------|------|
| Issues 總數 | {total_count} |
| 已關閉 | {closed_count} |
| PRs 合併 | {pr_count} |
| 新增行數 | +{additions} |
| 刪除行數 | -{deletions} |
| 測試數量 | {test_count} |

---

## 已完成的工作

### {N}. {plain_language_title}

**需求**：
> {引用 issue body 的原文，blockquote 格式}
> — 來源：{source}

**做了什麼**：{白話描述解決方式，不用技術術語}

**驗證方式**：{怎麼確認做對了}

**狀態**：✅ 已完成（[#{number}]({issue_url}) → [PR #{pr}]({pr_url})）

---

（重複每個 issue...）

## 處理中的工作

（列出 OPEN issues，說明目前進度和阻礙）

---

## 下一步

{建議的後續行動}

---

{@tag1 @tag2 請查閱}
```

### Step 6: 檢查既有報告（CREATE vs UPDATE）

```bash
# 搜尋 Discussions 中是否已有同主題報告
gh api graphql -f query='
query($query: String!) {
  search(query: $query, type: DISCUSSION, first: 5) {
    nodes {
      ... on Discussion {
        id
        number
        title
        url
        updatedAt
      }
    }
  }
}' -f query="repo:$GITHUB_REPO {report_title}"
```

- **找到** → 問使用者要更新還是新建
- **沒找到** → 新建

### Step 7: 確認 Discussion Category

```bash
# 列出可用的 Discussion categories
gh api graphql -f query='
query($owner: String!, $name: String!) {
  repository(owner: $owner, name: $name) {
    discussionCategories(first: 20) {
      nodes {
        id
        name
      }
    }
  }
}' -f owner="$GITHUB_OWNER" -f name="$REPO_NAME"
```

優先使用 `Reports` category。不存在則讓使用者選擇。

### Step 8: 發布到 Discussions

先顯示報告預覽給使用者確認，確認後發布：

```bash
# CREATE
gh api graphql -f query='
mutation($repoId: ID!, $catId: ID!, $title: String!, $body: String!) {
  createDiscussion(input: {
    repositoryId: $repoId,
    categoryId: $catId,
    title: $title,
    body: $body
  }) {
    discussion { url }
  }
}'

# UPDATE
gh api graphql -f query='
mutation($id: ID!, $body: String!) {
  updateDiscussion(input: {
    discussionId: $id,
    body: $body
  }) {
    discussion { url }
  }
}'
```

### Step 9: 回報

```
✓ 報告已發布：{discussion_url}
  涵蓋 {total_count} 個 issues（{closed_count} 已完成）
  Tagged: @user1, @user2
```

## 寫作原則

1. **讀者是非技術人員** — 不要出現程式碼、檔案路徑、函數名稱
2. **引用原文** — 每個問題的「需求」用 blockquote 引用 issue 原文
3. **三段式** — 需求 → 做了什麼 → 驗證方式
4. **量化成果** — 「修復了 7 個問題」「新增 1200 行程式碼」「111 個測試全部通過」
5. **Issue 超連結** — 每個 issue 編號都要有 GitHub 連結
6. **PR 超連結** — 每個 PR 編號都要有 GitHub 連結
7. **Tag 放最後** — `@username 請查閱` 放在報告最末

## 與其他 IDD skills 的關係

```
idd-issue → idd-diagnose → idd-implement → idd-verify → idd-close
                                                              ↓
                                                         idd-report
                                                    （多個 close 後彙整）
```

`idd-report` 是在多個 issues 完成後，把成果打包成一份可讀的報告。
