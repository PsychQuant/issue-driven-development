## Context

`idd-issue` v2.51.0 已支援:單 issue 建立、文件來源批次建 issue + 自動 milestone(Step 4.5)、跨 repo `groups` 機制(primary + tracking + cross-link)、sister sweep(Step 4.7)。但**同 repo 內的 parent-child + ordering** 沒有 first-class 支援。使用者目前只能手動兩步:先建 children → 再建 parent + 編 task list + 逐個加 Blocked-by 標註。這個流程的失敗模式有三:

1. **漏連結**:children 建好後忘了把 `- [ ] #N` 寫進 parent 的 task list,parent 變成空殼
2. **漏 dependency**:ordered bundle 的 `Blocked by #N-1` 標註要逐個手動加,容易漏中間某個
3. **使用者放棄 epic**:覺得「太麻煩就不建 parent」,結果 N 個原本應該被串起來的 issue 變成孤兒

GitHub 提供的原生 primitive 有三個:**parent body task list**(自動渲染 sub-issues + 進度條)、**Blocked by/Blocks dependency**(GraphQL `addBlockedByDependency`,UI 紅色 warning)、**milestone**(分組無依賴)。本 change 的目的是把前兩個包進 `idd-issue` 的 flag 介面,讓常見的 ordered/unordered bundle 形成一個指令完成。

正交性:milestone(分組)、group(跨 repo cross-link)、bundle(同 repo parent-child + dependency)是三個 orthogonal 軸,可以共存。一個 bundle 可以同時隸屬於 milestone,parent epic 也可以是 group 的 primary。

## Goals / Non-Goals

**Goals:**

- `idd-issue` 支援單一 invocation 完成 ordered/unordered bundle(parent + N children + task list + 可選 Blocked-by 鏈)
- 漸進式採用:`--parent <N>` / `--blocked-by <M>` 可獨立使用,使用者可以一次只加一個 child 到既存 parent;`--bundle-mode` 是高階組合
- Idempotency 契約:重複呼叫同 flag 不會產生重複的 task list entry / Blocked-by 標註;適合 retry / partial failure 復原
- Graceful degradation:`addBlockedByDependency` GraphQL mutation 失敗不 abort,自動 fallback 到 body blockquote 標註;最終一定有純文字的可讀標註
- 跟既有 mechanism(milestone Step 4.5、group、sister sweep Step 4.7、attachment Step 4)正交不互相干擾

**Non-Goals:**

- Layer 3 runtime hint(自動偵測「這看起來像 bundle」並 prompt 使用者)— 留給後續 proposal,理由見 proposal Non-Goals
- 取代 milestone(milestone 仍然解「分組」,bundle 解「依賴」)
- 跨 repo bundle(parent 和 children 在同一 repo;跨 repo 走既有 group 機制)
- 自動 close parent 當所有 children close(epic 可能還有 epic-level closing summary 要寫)
- 提供 retroactive 工具把既存 N 個散落 issue 重組成 bundle(可手動 `gh issue edit`,不在本 change 範圍)

## Decisions

### Decision: Flag 介面拆三層而非單一 mega flag

採三 flag 設計:

| Flag | 用途 | 使用情境 |
|------|------|----------|
| `--parent <N>` | child 建完後加進 parent #N 的 task list | 漸進式擴張 bundle(已有 parent,陸續加 child) |
| `--blocked-by <M>[,<M2>...]` | child 加 Blocked-by 標註 + 嘗試 GraphQL native dep | 表達單一 dependency,可獨立於 parent |
| `--bundle-mode <ordered\|unordered>` | 單次 invocation 建 N 個 issue 時,自動建 parent + 全部 children + task list + (ordered 時)Blocked-by 鏈 | 一次成形整個 bundle |

**為什麼不單一 `--bundle <spec>` mega flag**:使用者實際 workflow 不總是一次建完整個 bundle。常見的是「建好 #100 epic,過幾天加第 4 個 child 進去」,這時只需要 `--parent 100`,不需要其他 flag。三層 flag 各有獨立用途,組合時自然形成完整 bundle 行為。

**為什麼 `--bundle-mode` 而非 `--ordered` 旗標**:`ordered`/`unordered` 是 enum 不是 binary 開關,日後可能新增 `--bundle-mode parallel` 或 `--bundle-mode pipeline` 等。enum 形式可擴充。

### Decision: Blocked-by 三層 fallback chain

當 `--blocked-by <M>` 觸發時,依序嘗試:

1. **Layer 1 — GitHub GraphQL native dependency**:`addBlockedByDependency` mutation 加原生 Blocks/Blocked-by 關係(GitHub UI 顯示紅色 warning,task list 自動連動)
2. **Layer 2 — Body blockquote 標註**:無論 Layer 1 成功與否,**一律**在 child body 開頭加 `> Blocked by #M`(可讀 audit trail,跨工具可見)
3. **Layer 3 — 純 task list reference**:作為 Layer 1 失敗時的 visibility fallback,parent body 的 task list entry 加註解 `- [ ] #child (blocked by #M)` 讓 parent 視角也看得到依賴

**為什麼一律執行 Layer 2 而非只在 Layer 1 失敗時**:GraphQL native dep 在 `gh issue view --web` 才看得到,但 body blockquote 在 CLI / API / 任何 markdown viewer 都看得到。雙重保險的代價只是 1 行 body 內容,benefit 是「永遠有可讀的 dependency 標註」。

**為什麼 Layer 1 用嘗試而非檢測**:檢測 repo 是否 enable native dep 需要額外 API call(尚無公開 endpoint),嘗試 mutation 並 catch error 是最直接的能力探測方式。失敗 cost = 1 個失敗 mutation,可接受。

### Decision: Parent body task list 編輯演算法 idempotent

PATCH parent body 加 child entry 時用以下演算法,保證重複呼叫同 flag 不產生重複 entry:

1. **找 task list 段落**:掃 parent body,找第一個含 `- [ ]` 或 `- [x]` 的連續區段;若找不到,在 body 末尾新增 `## Children` 段落作為 anchor
2. **檢查重複**:scan 該段落每個 entry 的 `#N` reference,若 `#child` 已存在 → no-op(idempotent skip)
3. **append**:若不存在,在段落末尾加 `- [ ] #child` 一行
4. **保留現有結構**:不重排現有 entry、不修改其他 body 內容

**為什麼掃 `#N` 而非 line-level diff**:使用者可能會手動編輯 entry(如改 description / 加註解 / 重排),line-level 比對會誤判為「不同」進而 append 重複。`#N` 是 stable identifier。

**Anchor 段落命名 `## Children`**:採用 GitHub 原生 sub-issue 渲染慣例;不破壞既有 body 內容。若使用者想用其他 anchor(如 `## Tasks`),可手動在 parent body 預先建立空的 task list,演算法會偵測到並使用該段落。

### Decision: Cross-repo bundle 直接 refuse 而非降級

當 `idd-issue --parent <N>` 偵測到 parent #N 不在當前解析的 target repo(透過 Step 0.5 / Step 2.5 機制決定的 `$GITHUB_REPO`):**refuse + 錯誤訊息**指出走既有 `groups` 機制,不嘗試自動切換 repo。

**為什麼不降級**:跨 repo parent-child 是不同的 mental model(group 機制有 cross-link comment、tracking_body_mode、bidirectional reference);bundle 機制假設「同 repo 同一個 issue tracker 視窗」。混用會讓 task list 渲染失效(GitHub task list 跨 repo 不連動進度條)。明確 refuse + 指引到 groups 比 silent 降級安全。

### Decision: SKILL.md 段落放在 Step 5 之後而非散落各 Step

新增 `## Ordered Bundle Pattern` 作為**獨立 reference 段落**(類似既有的 `## 來源文件規則`),放在 Step 5 之後 / `## 來源文件規則` 之前。flag 行為的具體細節仍在 Step 3(建立 Issue)/ Step 4(附件)區塊就近說明。

**為什麼分離**:bundle 是 cross-cutting concern(影響 Step 3 issue creation + Step 4 後處理 + Step 0 task list bootstrap)。把所有 bundle-related 解釋集中到一個段落比散落在多個 Step 容易維護;具體 flag 觸發行為仍 inline 在對應 Step 維持本地可讀性。

## Risks / Trade-offs

- **[Risk] GitHub `addBlockedByDependency` GraphQL mutation 在某些 org/repo 沒 enable** → Mitigation: Layer 2(body blockquote)永遠執行,確保標註至少在 markdown 可見;mutation 失敗 catch 後印 warning 但不 abort
- **[Risk] Parent body task list 演算法找錯段落**(例如 body 含 reproduction steps 的 checkbox)→ Mitigation: 搜尋第一個**連續** `- [ ]` 區段而非單一散落 checkbox;若 parent 是 `idd-issue` 建立的標準 epic 結構,task list 會在 `## Children` 或類似明確 anchor 段落,不會誤判
- **[Risk] Idempotency 檢查只看 `#N` reference,使用者改成手寫文字 reference(如「see issue 42」)會被當成新 entry** → Mitigation: 標準 task list entry 強制用 `#N` 格式;若使用者偏好其他寫法,文件明確說明 idempotency 只對 `#N` 格式生效
- **[Trade-off] Flag 拆成三個增加 cognitive surface vs. 單一 mega flag 較難漸進採用** → 選擇前者,理由見 Decision §1。文件需有清楚 flag 組合範例
- **[Trade-off] Bundle 不自動 close parent 增加使用者責任 vs. 自動 close 可能 mechanical 越權** → 選擇手動,理由:epic-level closing summary 是 IDD 重要 audit 紀錄(MANIFESTO 強調),不該 mechanical bypass
- **[Trade-off] 文件段落獨立放在 Step 5 之後 vs. 散落在 Step 3 / Step 4 各自說明** → 選擇分離 + 各 Step inline 注釋雙軌,理由見 Decision §5

## Migration Plan

無 breaking change。所有新 flag 都是 additive,既有 `idd-issue` invocation(無 flag)行為完全不變。

部署順序:

1. Implement flag handling + 編輯演算法 + GraphQL fallback chain(`SKILL.md`)
2. 寫 `references/bundle-flags.md` canonical reference
3. 更新 `CLAUDE.md` skills 表 `idd-issue` 行
4. Bump `plugin.json` v2.51.0 → v2.52.0,寫 `CHANGELOG.md` v2.52.0 entry
5. Dogfood 在本 repo(`issue-driven-development`)驗證:在實際 GitHub 上建一個 ordered bundle test case
6. 透過 marketplace 同步:`/plugin-tools:plugin-update issue-driven-dev`

Rollback:revert plugin commit + 退回 v2.51.0;新 flag 在 v2.51.0 不存在,使用者使用 flag 會直接報「unknown flag」,不會留下半完成 state(因 flag 失敗發生在 issue create 之前)。已建立的 bundle issue body 中的 `> Blocked by` blockquote 即使 plugin 退版仍是有效 markdown,不會壞。

## Open Questions

- **Q**: parent body task list anchor 段落 `## Children` 是否該 configurable(讓 repo CLAUDE.md 自定 anchor 名稱)?
  - 暫定:hardcode `## Children`,觀察是否有 repo 因 convention 衝突需要客製,若有再加 config field
- **Q**: `--bundle-mode ordered` 的 Blocked-by 是嚴格鏈式(child2 only blocked by child1)還是累積(child2 blocked by child1, child3 blocked by child1+child2)?
  - 暫定:嚴格鏈式(只 blocked by 前一個),理由是降低 dependency 圖複雜度;若使用者要更複雜的依賴可手動用 `--blocked-by <M1>,<M2>`
- **Q**: 是否提供 retroactive 工具把已存在的 N 個散落 issue 重組成 bundle?
  - 暫定:不在本 change 範圍。若使用者需要,可手動 `gh issue edit` parent + `gh issue comment` children;真有需求可以後續另開 proposal
