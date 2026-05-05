## Why

IDD 已支援文件來源批次建 issue + 自動 milestone(`idd-issue` Step 4.5),但沒有「順序執行的 bundle」原語。當 N 個 issue 之間存在 dependency(schema 在 API 之前、phase 1 在 phase 2 之前),目前要手動兩步:先建 children,再建 parent epic 並編 task list,還要逐 child 加 Blocked-by 標註。這個流程容易漏掉 task list 連結、忘了 Blocked-by、或 cross-link comment 沒同步,結果 bundle 變成散落的 N 個 issue,失去依賴語意。

milestone 解的是「分組」(時間軸/範圍),不解「依賴」(順序);group 機制解的是「跨 repo cross-link」,不解「同 repo parent-child」。三者正交,bundle 是缺的第三軸。

## What Changes

- **新增 `--parent <N>` flag** to `idd-issue`:子 issue 建完後 PATCH parent #N body,把 `- [ ] #child` 加進 parent 的 task list 區段。Idempotent — 重複呼叫不會重複 entry。
- **新增 `--blocked-by <M>[,<M2>...]` flag** to `idd-issue`:在 child body 加 `> Blocked by #M` blockquote 標註;同時嘗試 GitHub GraphQL `addBlockedByDependency` mutation;若 mutation 失敗(repo 沒 enable native dep / API rate limit / 權限不足)→ 自動 fallback 純文字標註,不 abort。
- **新增 `--bundle-mode <ordered|unordered>` flag** to `idd-issue`:當單次 invocation 建多個 issue 時,自動建立 1 個 parent epic issue + N 個 children + 把 children 全部加進 epic body 的 task list;`ordered` 模式額外逐個串 Blocked-by 鏈(child[i] blocked by child[i-1]);`unordered` 模式只建 task list,不加 dependency。
- **新增 SKILL.md `## Ordered Bundle Pattern` 段落**:三種 GitHub-native bundle 模式對照表(parent + task list / native dependency / milestone)、新 flag 用法、為什麼不另開 `/idd-bundle` skill 的設計理由、retrofit 既存散落 issue 為 bundle 的步驟。
- **新增 canonical reference doc** `plugins/issue-driven-dev/references/bundle-flags.md`:flag 完整 spec、parent body 編輯演算法(找 task list 段落 → append → 不重複)、Blocked-by 三層 fallback chain、idempotency 保證、各種 partial failure 模式的處理。
- **更新 plugin metadata**:`plugin.json` version v2.51.0 → v2.52.0,description 加新 changelog entry;`CHANGELOG.md` 新增 v2.52.0 段落;`CLAUDE.md` skills 表 `idd-issue` 行的「用途」欄補一句 bundle 支援。

## Non-Goals

- **Layer 3 runtime hint(Step 4.6 / IC_R011 application)留給後續 proposal**:本 proposal 只做 primitive(flags)+ documentation。理由:hint 的啟發式評分(順序 keyword / title 編號 / 主題一致性)需要 dogfooding 經驗才能調準,先把 flag 做好讓使用者可立即使用,再依實際使用 pattern 設計 hint。
- **不取代 milestone 機制**:milestone 表達「分組」(時間軸 / 範圍),bundle 表達「依賴」(順序)。一個 bundle 可以同時隸屬於一個 milestone — Step 4.5 自動 milestone 行為對 bundle 完全不變。
- **不另開 `/idd-bundle` skill**:`idd-issue` 的 target resolution(Step 0.5)、attachment upload(Step 4)、mention validation(Step 2.6)、sister sweep(Step 4.7)邏輯不應該複製。flag 加在 idd-issue 是最低成本整合,且 ~70% 程式碼重疊的 cost 不值得。
- **不強制使用 GraphQL native dependency**:GitHub `addBlockedByDependency` 還在 GA 階段,部分 repo / org 未 enable。always degrade to body 文字 是不變式 — 三層 fallback chain 永遠至少有 body 文字標註可用。
- **不處理 cross-repo bundle**:bundle 假設 parent 和 children 在同一個 repo。跨 repo 場景仍走既有的 `groups` 機制(primary + tracking + cross-link comment)。flag 偵測到 `--parent` 跨 repo → refuse + 報錯。
- **不自動 close parent 當所有 children close**:依賴 GitHub native task list 進度條 + `idd-close` 手動 trigger。理由:parent epic 可能還有 epic 自身的 closing summary 要寫,不該被 mechanical auto-close。

## Capabilities

### New Capabilities

- `idd-issue-bundle`: `idd-issue` 對 ordered/unordered issue bundle 的 first-class 支援。涵蓋三個 flag(`--parent` / `--blocked-by` / `--bundle-mode`)的語法與行為、parent body task list 編輯演算法的 idempotency 契約、Blocked-by 三層 fallback chain(GraphQL native → body blockquote → 純 task list)、cross-repo refuse 規則、與既有 milestone / group / sister sweep 機制的正交性。

### Modified Capabilities

(none)

## Impact

- Affected specs: 1 new — `idd-issue-bundle`
- Affected code:
  - Modified:
    - `plugins/issue-driven-dev/skills/idd-issue/SKILL.md` — 新 flag handling 區塊、Step 0 Bootstrap Task List 加 bundle 相關 sub-tasks、新增 `## Ordered Bundle Pattern` 段落
    - `plugins/issue-driven-dev/CLAUDE.md` — skills 表 `idd-issue` 行補 bundle 支援描述
    - `plugins/issue-driven-dev/.claude-plugin/plugin.json` — version v2.51.0 → v2.52.0,description 加 changelog entry
    - `plugins/issue-driven-dev/CHANGELOG.md` — 新增 v2.52.0 段落
  - New:
    - `plugins/issue-driven-dev/references/bundle-flags.md` — canonical reference for bundle flag 完整 spec、edit algorithm、fallback chain、partial failure handling
    - `openspec/specs/idd-issue-bundle/spec.md`(透過本 change archive 後生成)
  - Removed: (none)
