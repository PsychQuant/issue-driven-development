---
name: implement
description: |
  按照 diagnosis 的策略實作，嚴格控制 scope。
  只改 issue 要求的東西，每個 commit 引用 #NNN。
  Use when: diagnosis 確認後、開始寫 code 時。
  防止的失敗：scope creep — 改 #42 順手重構了三個不相關的檔案。
argument-hint: "#issue e.g. '#42'"
allowed-tools:
  - Bash(gh:*)
  - Bash(git:*)
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - AskUserQuestion
---

# /implement — 紀律實作

按 diagnosis 的策略寫 code，不多做也不少做。

## 核心原則

> 每一行改動都必須能追溯到 #NNN。追溯不到的改動 → 開新 issue。

## Execution

### Step 1: 讀取 Issue + Diagnosis

```bash
gh issue view $NUMBER --repo $GITHUB_REPO --json title,body,labels
```

回顧對話中的 diagnosis report，確認 strategy。

### Step 2: 列出變更清單

根據 diagnosis 的 strategy，列出具體要改的檔案：

```markdown
## 變更清單 for #NNN

- [ ] 修改 src/foo.ts — {改什麼}
- [ ] 修改 src/bar.ts — {改什麼}
- [ ] 新增 tests/foo.test.ts — {測什麼}
```

**Scope check**: 清單裡的每一項都能對應到 issue 的某個要求？
- 對應不上 → 移除，或開新 issue
- Issue 的要求沒被覆蓋 → 補上

### Step 3: TDD 執行

每個變更項依序執行：

1. **寫測試**（RED）
   - 測試描述用 issue 的語言
   - 測 behavior，不測 implementation

2. **跑測試確認失敗**
   - 失敗原因必須是「功能還沒實作」，不是「測試寫錯」

3. **寫最小實作**（GREEN）
   - 只寫讓測試通過的 code
   - 不「順便」優化、重構、加功能

4. **跑測試確認通過**
   - 全部測試，不只新的

5. **Commit**
   ```bash
   git add {changed files}
   git commit -m "fix: {description} (#NNN)"
   ```

### Step 4: Scope 守衛

實作過程中發現的問題：

| 發現 | 處理 |
|------|------|
| 不相關的 bug | 開新 issue，繼續 #NNN |
| 不相關的 code smell | 開新 issue，繼續 #NNN |
| #NNN 的前置依賴 | 確認是否 blocker。是 → 先處理依賴；不是 → 記錄在 issue comment |
| 比預期更大的改動 | 停下來，回到 diagnosis 重新評估 |

**鐵律**：不在 #NNN 的 branch 上修不相關的東西。

### Step 5: 完成確認

所有變更清單項目完成後：

```bash
git status --short
git diff --stat HEAD~{N}
```

回顧：
- 每個 commit 都引用了 #NNN？
- 變更範圍跟 diagnosis 的 strategy 一致？
- 沒有超出 scope 的改動？

提示下一步：`/issue-driven-dev:verify #NNN`

## Commit 規範

```
<type>: <description> (#NNN)
```

- type: fix / feat / refactor / docs / test
- description: 用 issue 的語言描述改了什麼
- **必須**包含 `(#NNN)` 或 `#NNN`

## Next Step

實作完成後，進入 `verify`：

```
/issue-driven-dev:verify #NNN
```
