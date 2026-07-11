# Discussions Intake Bridge（#221）

GitHub **Discussions** 是真實 intake channel（bug report / feature request 常以 Q&A 形式抵達），
但 Discussions **沒有 REST API** — `gh issue list` 天然看不到。本檔是 `idd-list --discussions` 與
`idd-issue --from-discussion` 共用的 **normative contract + GraphQL 樣板**（single source；兩個
skill 引用本檔，不得各自內嵌分歧的 query 副本）。

動機案例：2026-07-04 `/idd-list` 對 `PsychQuant/che-ical-mcp` 回報 0 open issues（乾淨 backlog），
但一條真實權限 bug 的完整生命週期（回報 → 診斷 → 「已修好」確認）都發生在 Discussion 105 —
IDD 對整條 intake channel 全盲。

## Normative constraints（三條，缺一不可）

### 1. no-auto-file — 絕不自動建 issue

Bridge **只 surface，人來判斷**。動機案例的 Discussion 被發現時**已解決**（回報者最後一則留言
是「everything is fixed, thank you」）— 機械式對每個「問題貌」Discussion 建 issue 會製造
開了就要關的 noise issue。`--from-discussion` 是**顯式人為呼叫**，不是自動化觸發點。

### 2. dedup — 已被 issue 引用者不重複標記

任何**既有 issue（open 或 closed）** body 內含該 Discussion URL → 該 Discussion 不列入
actionable。搜尋方式：`gh issue list --repo <owner/repo> --state all --search "<discussion-url>" --json number`
非空即視為已橋接。

### 3. resolution-detection — `answerChosenAt` 是機械邊界

`answerChosenAt != null`（已選答案）→ 不 actionable。**留言情緒判讀（「已修好，謝謝」）明文
out of scope** — 那是人的判斷，不是機械信號（#221 diagnosis Residue）。category 過濾：只有
**Q&A 與 Ideas** 算 intake；Announcements / Show-and-tell / Polls 不算。

## Outward-write 邊界（idd-issue 端）

建案後的 Discussion 回文（back-reference reply）**一律 draft-and-confirm**：
- **attended**：draft 呈現 → `AskUserQuestion` 確認 → 才執行 `addDiscussionComment` mutation
- **unattended**（orchestrator UNATTENDED MODE）：**draft-only 絕不 post** — 回文草稿印在
  Step 5 report 標記「suggested reply (not posted)」

## GraphQL 樣板

> **Schema 假設（2026-07-11 驗於 GitHub GraphQL v4）**：`Repository.hasDiscussionsEnabled`、
> `Repository.discussions(first, states)`、`Discussion.{number,title,url,body,createdAt,updatedAt,answerChosenAt}`、
> `Discussion.category.name`、`Discussion.author.login`、mutation `addDiscussionComment(discussionId, body)`。
> Discussions API 比 REST 年輕 — query 失敗時**降級為一行 skip note，絕不 hard-abort 呼叫端 skill**。

### Probe — hasDiscussionsEnabled

```bash
gh api graphql -f query='query($owner:String!,$repo:String!){
  repository(owner:$owner,name:$repo){ hasDiscussionsEnabled }
}' -f owner="$OWNER" -f repo="$REPO_NAME" --jq '.data.repository.hasDiscussionsEnabled'
```

### List — open discussions（first 50）

```bash
gh api graphql -f query='query($owner:String!,$repo:String!){
  repository(owner:$owner,name:$repo){
    discussions(first:50, states:OPEN, orderBy:{field:UPDATED_AT, direction:DESC}){
      nodes{ number title url updatedAt answerChosenAt
             category{ name } author{ login } }
    }
  }
}' -f owner="$OWNER" -f repo="$REPO_NAME" \
  --jq '.data.repository.discussions.nodes[]'
```

Actionable filter（呼叫端套用，順序固定 — 便宜的先）：
`category.name ∈ {"Q&A","Ideas"}` → `answerChosenAt == null` → dedup search（constraint 2）。

### Fetch one — for `--from-discussion` seeding

```bash
gh api graphql -f query='query($owner:String!,$repo:String!,$num:Int!){
  repository(owner:$owner,name:$repo){
    discussion(number:$num){ id number title url body createdAt answerChosenAt
                             category{ name } author{ login } }
  }
}' -f owner="$OWNER" -f repo="$REPO_NAME" -F num="$DISCUSSION_NUM" \
  --jq '.data.repository.discussion'
```

（`id` 是 node ID — 之後 `addDiscussionComment` 的 `discussionId` 用它。）

### Reply — back-reference（attended confirm 後才執行）

```bash
gh api graphql -f query='mutation($id:ID!,$body:String!){
  addDiscussionComment(input:{discussionId:$id, body:$body}){ comment { url } }
}' -f id="$DISCUSSION_NODE_ID" -f body="$REPLY_BODY"
```

## Provenance 格式（idd-issue seeding）

```markdown
## Provenance

> Source: <discussion-url>（Discussion #<num>，author @<login>，category <name>）

原文（opening post，verbatim blockquote）：

> <discussion body，逐行 blockquote>
```

原文一律 blockquote（plugin 原文引用紀律）；issue body 其餘段落照 idd-issue 正常 pipeline
（type / priority / privacy gate / gh-egress）。

Refs #221。
