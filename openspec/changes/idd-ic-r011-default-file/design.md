## Context

IC_R011 follow-up filing checkpoint(IDD plugin commercial low-bar filing rule)目前以 canonical reference 形式存在於 `plugins/issue-driven-dev/references/ic-r011-checkpoint.md`(301 行),被 7 個 skill SKILL.md inline 引用 + 大段 procedure body 複製。`AskUserQuestion` 預設 3-option(`file all` / `file selected` / `skip`),user 必須主動選 file 才會 trigger issue creation。

**現況痛點**:
1. **建議消失到 conversation log**:user 不主動選 → AI surface 的 sister concerns / tangentials / verify follow-ups 沒被 track,過陣子就遺忘。Issue #148 由 user 在 session 中累積 3/3 `file all`-variant 選擇後 file。
2. **skip path 無 audit reason**:現況 `Skipped per user choice` 是 generic 字串,事後無法區分「真不該 file」vs「該 file 但 user 漏點」。
3. **7 sites inline procedure drift**:本 issue 自身就是 sync 痛點 source — canonical ref + 6 skill 各自寫一份相同 procedure,任何 wording / structure 改動要 sync N+1 places。
4. **`idd-verify` Step 5b 沒用 canonical「Rule (SHALL/SHOULD)」framing**(#149),inline 補強會放大已有的 drift。

**Constraint**:
- IC_R011 是 cross-repo 規則(NSQL ai_martech ID 系統的一部分),不能 rename(會 break 既有 cross-repo cite)。
- 既有 escape hatch `AI_LOW_BAR_ISSUE_FILING=false` env var + `# Disable IC_R011` repo CLAUDE.md flag 是 8 個檔案引用的 stable contract,**只能 shift 語意,不能廢除**。
- IDD plugin 已 ship 多版(plugin.json marketplace presence),break 既有 user 設定的 escape hatch 會造成 CI / unattended 環境 regression。

## Goals / Non-Goals

**Goals:**

- 翻轉 IC_R011 default 從「ask 3-option」到「file by default + 3-category skip taxonomy」,**file rate 上升 + 建議不消失**
- Skip 不再無 reason — 強制選 (a) unactionable / (b) infeasible / (c) blocked-on-external 三類,(b)(c) auto-file 進 parking lot,只有 (a) 真 skip
- Procedure body centralize 到 canonical reference,6 skill SKILL.md 從 inline 改 cite — 之後 IC_R011 spec 改動只需動 canonical ref 1 places(改 6 個 cite 行不算改 procedure)
- 既有 escape hatch backward-compat 語意 shift:`=false` 從 silent skip 變 「revert to 3-option ask」,CI / unattended 無 TTY 環境 fallback 到 implicit skip + audit trail
- 順手 close #149(verify Step 5b framing gap)

**Non-Goals:**

- ❌ 不 rename IC_R011 到 NSQL-native ID(MP/P/R/D 系統)— cross-repo cite 穩定優先,naming consolidation 不在本 change scope(可未來另開 change)
- ❌ 不改 `idd-close` Step 3.5 default(保留 3-option ask + SHOULD-tier)— closing 是 wrap-up moment,翻 default 增加 friction 無 proportional value
- ❌ 不改 `idd-all-chain` IC_R011 reference(經 verify 應為 spawn-manifest pass-through,非 standalone AskUserQuestion checkpoint;若 propose 階段 verify 發現是 standalone 才補回 scope)
- ❌ 不引入新 escape hatch(`AI_LOW_BAR_ISSUE_FILING_TAXONOMY` etc.)— 既有兩個 escape hatch 已涵蓋,新增 surface 違反 lead-minimal
- ❌ 不規範 `blocker:infeasible` / `blocker:waiting` label 在 repo 必須存在(label 自動建立屬於 repo grooming;若 repo 無此 label,issue 仍 file 成功,label 變成 plain text mention in body)

## Decisions

### Decision 1: Pick Option B file-by-default

**Rationale**:Option A 移除 human review gate,會 file 大量 low-value 建議,backlog noise 高。Option C 在 issue tracker 產生 transient noise(file 後又 close),review 視覺紊亂。Option B 保留 ask gate 但翻 friction direction:default action(file)零點擊,skip 反而需要明示 category。**符合 user feedback「預設要開起 issue,除非無法解決」字面語意**。

**Alternatives considered**:
- Option A:silent auto-file with env var opt-out — rejected:失去 human gate,low-value noise 風險高
- Option C:auto-file + retroactive delete — rejected:tracker transient noise + grooming burden

### Decision 2: 3-category skip taxonomy

**Rationale**:User feedback「無法解決」字面有 3 種解讀(diagnose Finding 3):純觀察 vs 暫不可行 vs 等外部。若 skip UX 不細化,user 會把 (b)(c) 也 skip 掉,失去 parking-lot 功能(這正是 #148 想避免的「建議消失」)。3-category 強制 disambiguate:**(a) skip 真不 file;(b)(c) auto-file P3 + `blocker:` label**。

**Acceptance test**:`/idd-diagnose` surface 3 個候選 finding,user 選 skip → AskUserQuestion 第二層 3-option (a)/(b)/(c) per item,(b)(c) 仍 `gh issue create`,(a) audit trail entry 寫 `skipped: (a) unactionable observation`。

**Alternatives considered**:
- 1 free-text「why」field — rejected:user 會留空,語意丟失
- Per-candidate independent AskUserQuestion — rejected:N candidates × 2 questions UX 過重

### Decision 3: SHALL skills 翻 default;idd-close 保留 3-option ask

**Rationale**:Canonical ref §6 明示 close 是 SHOULD 因為「closing 是 mechanical text scan,非 deliberation moment」。Closing 階段 user 已在 wrap-up 心智狀態,若翻 default 變成「last-call 默默 file 3 個 follow-up」反而增加 friction without proportional value。**保留 SHALL/SHOULD 既有 asymmetry**,只翻 SHALL 層。

**Per-site treatment matrix**:

| Skill | Step | Current rule | New default behavior |
|-------|------|--------------|---------------------|
| `idd-diagnose` | 3.6 | SHALL | file by default + 3-category skip |
| `idd-plan` | 2.5 | SHALL | file by default + 3-category skip |
| `idd-implement` | 5.7 | SHALL | file by default + 3-category skip |
| `idd-issue` | 4.7 | SHALL | file by default + 3-category skip |
| `idd-verify` | 5b | (unframed → become SHALL via #149 fix) | file by default + 3-category skip |
| `idd-close` | 3.5 | SHOULD | **unchanged — keep 3-option ask** |

**Alternatives considered**:
- Uniform translation 所有 6 site 同步翻 default — rejected:close 階段 friction increase 無 value
- 5 SHALL site 翻 default,close 也升為 SHALL + 翻 default — rejected:close 升 SHALL 本身需另開 change 討論,不在本 scope

### Decision 4: Centralize procedure body 到 canonical reference

**Rationale**:7 sites 各自 inline 大段 procedure body 是 spec drift source(本 issue 就是這個痛點)。改為 canonical ref 持有 normative body + procedure detail,skill SKILL.md 只持 1-line invoke + 該 step 特定 deviation。**未來 IC_R011 spec 改動 → 改 canonical ref 1 places;skill cite line 自動 inherit**。

**Refactor pattern**(canonical ref 新增 「How to invoke from skill」 section,給 skill 模板):

```markdown
H3 heading: Step N.M: <descriptive name>

**Per IC_R011 follow-up filing checkpoint** (see [`references/ic-r011-checkpoint.md`](../../references/ic-r011-checkpoint.md))。

**Trigger condition**: <skill-specific trigger>

**Per-step deviation** (if any):
- <e.g. idd-verify 5b 額外 filter follow-up-classified findings>
```

**Alternatives considered**:
- 維持 inline procedure body,只翻 default — rejected:drift risk 持續,下一次 spec change 又要 sync 7 places
- 把 SKILL.md 改成只 cite zero procedure detail — rejected:skill-specific deviation(`idd-implement` reproduction trace vs `idd-issue` linked-context vs etc.)需要 in-context 描述,純 cite 失去可讀性

### Decision 5: Escape hatch semantic shift

**Rationale**:8 places(canonical ref + 6 skills + CHANGELOG + plugin.json)引用 `AI_LOW_BAR_ISSUE_FILING`。引入新 var(`AI_LOW_BAR_ISSUE_FILING_TAXONOMY` etc.)增加 surface area 違反 lead-minimal,且使用者已建立 mental model「`=false` 等於 opt-out」。**Shift 語意:`=false` 從「silent skip」改為「revert to 3-option ask」**,unattended 無 TTY 環境 fallback 到 implicit (a) skip + audit trail(per `/idd-issue` Stage 4.5 既有 unattended pattern)。

**Semantic shift table**:

| Setting | Pre-change behavior | Post-change behavior |
|---------|--------------------|--------------------|
| (default) | 3-option ask | **file by default + 3-category skip** |
| `AI_LOW_BAR_ISSUE_FILING=false` | silent skip + audit | **revert to 3-option ask** |
| `# Disable IC_R011` in repo CLAUDE.md | silent skip + audit | **revert to 3-option ask** |
| Unattended (no TTY) + `=false` | silent skip + audit | implicit (a) skip + audit trail(fallback) |
| Unattended (no TTY) + default | (didn't apply pre-change) | implicit (a) skip + audit trail |

**Audit trail format change**:`Skipped per user choice (...)` 字串 → `Skipped: (a) unactionable observation | (b) infeasible | (c) blocked-on-external` per category(若 telemetry / log 分析依賴舊字串,CHANGELOG 必須 prominent 警告 + 提供 grep migration hint)。

**Alternatives considered**:
- 引入 `AI_LOW_BAR_ISSUE_FILING=ask` 為新值,`=false` 保留舊「silent skip」 — rejected:`false` 語意被改 = backward incompat,但新增三值列舉(`true` / `false` / `ask`)增加 cognitive surface,且 user mental model 已建立 boolean
- 不 shift 既有 var,新增 `IDD_IC_R011_DEFAULT=file|ask|skip` — rejected:三 env var 同主題增加 conflict surface(`=false` vs `=ask` 互動?)

## Implementation Contract

### Observable behaviors

- `/idd-diagnose` / `/idd-plan` / `/idd-implement` / `/idd-issue` / `/idd-verify` 跑 IC_R011 checkpoint 時:
  - **Default path**:surface candidate list → 顯示 「Filing N candidates as P3 follow-ups...」 → loop `gh issue create` per candidate(無 AskUserQuestion 阻擋)→ audit trail PATCH 既有 comment 寫 `Filed: #NNN, #MMM, #PPP`
  - **Skip request path**(user 主動說「skip」/「等等」/ env var `=false`):AskUserQuestion 改 surface「為哪些 candidates 你想 skip?」+ per-skip-candidate 第二層 (a)/(b)/(c) picker;(a) 真 skip,(b)(c) 仍 `gh issue create` 加 `blocker:` label
- `/idd-close` Step 3.5:行為**不變** — 維持 3-option ask `[file all]` / `[file selected]` / `[skip]`
- Unattended mode(no TTY,detect via `[ ! -t 0 ]` 或 env var `IDD_ALL_UNATTENDED=1`):**所有 SHALL skills 自動走 default file path**(no AskUserQuestion possible);`=false` 設定下 fallback 到 implicit (a) skip + audit trail

### Interface / data shape

- **Audit trail entry format**(canonical ref 規範 + 6 sites cite):
  - File case:`Filed: #NNN[, #MMM, ...]`(無變)
  - Skip (a):`Skipped: (a) unactionable observation`
  - Skip (b):`Skipped: (b) infeasible — filed as #NNN with blocker:infeasible label`
  - Skip (c):`Skipped: (c) blocked-on-external — filed as #NNN with blocker:waiting label`
  - Empty surface:`(none surfaced)`(無變)
  - Env var bypass:`Skipped (AI_LOW_BAR_ISSUE_FILING=false — reverted to 3-option ask, user chose skip)`
  - Unattended bypass:`Skipped (unattended mode + AI_LOW_BAR_ISSUE_FILING=false → implicit (a) skip)`

- **`gh issue create` invocation**(per (b)/(c) auto-file):
  - Title:`[$type] $description (sister concern from #$source)`(無變)
  - Labels:`$type,confidence:confirmed,priority:P3,blocker:infeasible|blocker:waiting`(新增 `blocker:` label)
  - Body footer:`**Source**: surfaced during /$skill #$source ... (Step $N.M)`(無變)

- **`AI_LOW_BAR_ISSUE_FILING` semantic contract**(env var docstring update in 8 places):
  - Pre-change:「Skip the checkpoint silently (file nothing). For CI / unattended runs.」
  - Post-change:「Revert to pre-default-flip 3-option ask. Unattended mode (no TTY) falls back to implicit (a) skip + audit trail.」

### Failure modes

- `gh issue create` 失敗(rate limit / network):per-candidate audit trail entry 寫 `Filed: failed — retry_hint: <gh command>`;**continue** to next candidate(per existing warn-continue pattern from `/idd-issue` Stage 4)
- `blocker:` label 不存在於 target repo:issue 仍 file 成功(GitHub auto-create label 行為);若 repo 用 strict label policy,label 退化成 body mention(無 fail)
- User cancel mid-skip-picker(close terminal / Ctrl-C):already-filed candidates 不 rollback;audit trail 寫 `Partial skip — N filed, M cancelled`
- Canonical ref 與 skill SKILL.md cite 不一致(refactor drift):`spectra validate` 偵測不到此類 drift(non-spec text);Tasks 階段加 grep check `grep -L 'per IC_R011' plugins/issue-driven-dev/skills/idd-{diagnose,plan,implement,issue,verify,close}/SKILL.md` 確認 6 site 都引用

### Acceptance criteria

實作完成後,以下 manual + scriptable 檢查全 pass:

1. **Default behavior translation**:`grep -A 3 'AskUserQuestion' plugins/issue-driven-dev/skills/idd-{diagnose,plan,implement,issue,verify}/SKILL.md` 應顯示 「按既有 procedure 改採 file-by-default」 wording,**不是** `[file all] / [file selected] / [skip]` 3-option
2. **idd-close unchanged**:`grep -A 5 'Step 3.5' plugins/issue-driven-dev/skills/idd-close/SKILL.md` 仍含 `[file all] / [file selected] / [skip]` 3-option 結構(only normalize wording 跟其他 site 一致,default 不變)
3. **Canonical ref centralization**:`wc -l plugins/issue-driven-dev/references/ic-r011-checkpoint.md` ≥ 350(吸收 procedure body 後成長);6 skill SKILL.md 對應 step section 顯著縮短(從 ~50 行 inline 變 ~15 行 cite + deviation)
4. **Backward-compat semantic shift documented**:CHANGELOG entry 含 「BREAKING: IC_R011 default flipped」 + env var semantic shift table
5. **#149 順手 fix**:`grep '\*\*Rule (SHALL)\*\*' plugins/issue-driven-dev/skills/idd-verify/SKILL.md` 至少 1 hit(Step 5b 補 framing)
6. **#148 + #149 close**:both 透過 `/idd-close` 走 normal closing flow(無 auto-close trailer per IDD discipline)
7. **`spectra validate idd-ic-r011-default-file`** PASS
8. **本 change 自身 dogfood**:apply 階段跑 IC_R011 checkpoint 時,**新 default 還沒 land**,所以仍走舊 3-option;第一個用 new default 的 invocation 是 apply 完成後的下一次 `/idd-diagnose`

### Scope boundaries

**In scope**:
- 翻 5 SHALL/unframed site default
- 補 #149 verify Step 5b framing
- 3-category skip taxonomy
- canonical ref centralization + 6 skill cite refactor
- env var semantic shift 文件化
- CHANGELOG entry

**Out of scope**:
- IC_R011 rename 到 NSQL-native ID
- `idd-close` Step 3.5 default 翻
- `idd-all-chain` IC_R011 reference 改寫(verify 後若是 standalone checkpoint 再開 follow-up change)
- 新 escape hatch env var
- `blocker:infeasible` / `blocker:waiting` label 自動建立 / repo grooming
- 移除既有 `Skipped per user choice (...)` 字串對應的 log 分析工具(屬於 user-side migration,非 spec scope)

## Risks / Trade-offs

| Risk | Mitigation |
|------|------------|
| **R1 Bikeshedding on 3-category boundary** — (a)(b)(c) 分界 user 可能爭(「需要 100x budget」算 (b) 還是 (c)?)| Tasks 階段在 canonical ref 給每 category 2-3 個 example,降低 boundary ambiguity;邊界 case 預設選右(較寬的 file path)|
| **R2 SHALL/SHOULD asymmetry surprises** — user 用 `/idd-close` 看到 3-option ask 不一致會困惑 | canonical ref §6 + close Step 3.5 wording explicit 解釋「close 是 wrap-up moment 維持 ask」;CHANGELOG 標明 |
| **R3 audit trail format change breaks downstream tools** — telemetry / log 分析依賴舊 `Skipped per user choice` 字串會 break | CHANGELOG prominent 警告 + 提供 grep migration hint `grep -E 'Skipped(:| per user choice)'` |
| **R4 Backward-compat env var semantic flip 引爆 CI**:現有 CI / unattended 設了 `=false` expecting silent skip,翻成 ask + no TTY 會 hang | Unattended fallback chain:`[ ! -t 0 ]` + `=false` → implicit (a) skip(不 hang,有 audit trail);CHANGELOG 警告 + 文件 fallback 邏輯 |
| **R5 Centralization 失敗 case** — canonical ref + skill cite drift 無 auto-detect | Tasks 加 grep check(`grep -L 'per IC_R011' plugins/issue-driven-dev/skills/idd-*/SKILL.md`)+ verify 階段 6-AI 至少 1 site 覆蓋;`spectra validate` 不 cover non-spec drift,manual gate 必要 |
| **R6 Dogfood paradox** — apply 階段 IC_R011 checkpoint 仍跑舊 default,某 sister concern 可能被 skip 過去 | Apply 全程 manual 注意 sister concerns,不依賴舊 default 表現;apply 完成後立刻在新 default 下跑一次 `/idd-diagnose` 試 invocation 作為 acceptance verification |
| **R7 `idd-all-chain` scope verify 未明** — IC_R011 reference 若實際是 standalone checkpoint 而非 spawn-manifest pass-through,本 change 漏 1 site | Tasks 第一個 step 是 `grep -A 20 'IC_R011' plugins/issue-driven-dev/skills/idd-all-chain/SKILL.md` verify;若 standalone,新開 follow-up change,本 change 仍 ship 5 site 翻 default |
| **R8 (b)/(c) auto-file 後 user 後悔** — auto-file 不像 ask 可預覽,filed 後 close 一個 issue 是 noise | (b)/(c) auto-file 走標準 `gh issue create` flow + body footer 含 source link,user 可隨時 `/idd-close` 該 issue 用 「retroactive — auto-filed as (b)/(c)」 reason |

## Migration Plan

1. **No staged rollout**:本 change ship 即生效,所有 IDD plugin user 下次 invocation 自動採新 default。Plugin install user 透過 `/plugin update` 拿新版。
2. **CHANGELOG promotion**:新版本 plugin.json bump minor(non-patch),CHANGELOG entry 標 `BREAKING (behavioral)` prominent
3. **Rollback strategy**:individual user 設 `AI_LOW_BAR_ISSUE_FILING=false` 回到 3-option ask 行為(per Decision 5 semantic shift);若整個 default-flip 需 revert,git revert 本 change PR(canonical ref + 6 skill SKILL.md + CHANGELOG)
4. **Acceptance window**:apply 完成後 7 天觀察期 — collect file rate 改變 + user feedback;若有不可預期 regression open hotfix change

## Open Questions

1. **`idd-all-chain` IC_R011 reference 是 pass-through 還是 standalone checkpoint?** — Tasks 第一個 step verify;若 standalone,scope 擴張到 6 site;若 pass-through,維持 5 site
2. **`blocker:infeasible` / `blocker:waiting` label policy** — 是否要在本 change 自動為 IDD plugin user 的 repo 建這兩個 label?**暫定 NO**(out of scope per Non-Goals)— label 自動建立屬於 repo grooming,本 change 只規範 issue body mention 即可,實際 label 是否 attach 由 repo 自身決定
3. **Audit trail jsonl format**(per `/idd-issue` Stage 4 multi-finding mode)— 是否同步增加 `skip_category: a|b|c` 欄位?**暫定 YES,延後 tasks 階段 verify**;若衝突太大可作為 separate follow-up
