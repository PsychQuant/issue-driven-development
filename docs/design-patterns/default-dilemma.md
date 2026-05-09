# 預設兩難 (Default Dilemma)

> When choosing a flag's default value forces you into a trilemma where every option is wrong, the dichotomy itself is the bug — not the default.

## TL;DR

如果你正在設計「加 flag 還是另開 skill」,且發現自己卡在「flag 預設值該是什麼」,**flag 路線本身就是錯的訊號**。三種預設值各自帶一個失敗模式:

| Default | 失敗模式 |
|---------|---------|
| `off` | 多數 user 不知道有此功能,等於沒做 |
| `auto` | 既有 user 跑舊 command 突然行為變了,surprise factor |
| `ask` | 每次都問,變 prompt friction |

當三個都 plausible 但都有問題,真正的 design choice 是 **separate skill**,不是「找最不爛的預設」。

## 起源

2026-05-08,設計 `/idd-all` chain-solve mode 時:

- 提案 1:`/idd-all #N --chain` flag + `chain_policy` config
- 卡點:`chain_policy` 預設值沒有合理選擇
- User 一句「預設這樣的話要不要 chain 就會是兩難」直指核心
- 修正:`/idd-all-chain` separate skill,**不存在預設這個問題**

完整 session 在 [`PsychQuant/issue-driven-development#44`](https://github.com/PsychQuant/issue-driven-development/issues/44) diagnose + spectra-discuss。

## 診斷流程

問自己 3 個問題:

### Q1. 三個 default 都有 plausible 失敗?

對 `chain_policy`:

- `off` → 使用者跑 `/idd-all #28` 看到 verify spawn `#29 #34 #41`,不知道可以「順便解掉」 — 功能 dead 在 config 裡
- `auto` → 既有 `/loop` automation caller 預期 `/idd-all #N` 跑單 issue,突然 commit 5 個 issue 進 PR,review 工被打亂
- `ask` → 每次 `/idd-all` 都跳 「要 chain 嗎?」 prompt,2 prompts 比 1 個 explicit invocation 累

3 個都 plausible 失敗 → trilemma 成立 → 路線錯。

### Q2. User 心中是 binary 還是 spectrum?

- **Binary** (「我這次要 / 不要 chain」):每次都明確,沒灰色地帶 → separate skill
- **Spectrum** (「大多數時候要 / 少數時候不要,且依 issue 大小調整」):config 預設有意義 → flag

Chain solve 是 binary — user 心中清楚「這次 root issue 簡單,不要 chain」 vs 「這次 root issue 會 ripple,要 chain」。沒中間值。

### Q3. 兩條路 90% 共用 implementation 嗎?

- **是** + binary → separate skill,共用透過 reference doc / shared helper
- **是** + spectrum → flag with config default
- **否** → separate skill 必然(沒得選)

## Resolution

當 Q1 = yes、Q2 = binary、Q3 = yes,**separate skill + reference doc 抽共用邏輯** 是正解:

```
existing skill          ←  baseline behavior, default everyone gets
new skill               ←  new mode, explicit opt-in via invocation
references/shared.md    ←  90% common pipeline, both skills cite
```

**「預設這個概念消失」是 healthier outcome**:User 沒打 `/new-skill` 就是 baseline,沒 surprise、沒 friction、沒 dead config。

## 反例:flag 才對的情境

不是所有 design tension 都是 default dilemma。Flag-with-default 仍是對的,當:

### Case A. Per-invocation 自然 explicit

**範例**: `idd-issue --bundle-mode ordered` / `idd-issue --parent N`

每次 `/idd-issue` invocation user 都明確選 (single / bundle / child of N),flag 是 invocation 的 modifier,不是 session-level mode。沒「預設兩難」因為:
- 不帶 flag = single issue (自然 default)
- 帶 flag = 該 invocation 的 explicit choice

### Case B. Default 有 dominant 多數

**範例**: `idd-implement --no-pr` / `idd-all --no-pr` 的 `pr_policy` config

90% 場景使用者要 PR mode (collaboration / review trail),`pr_policy` default 「PR」是 dominant pick。極少數 solo project 才設 `never` — minority 願意 explicit override。**沒兩難因為一邊壓倒性 dominant**。

### Case C. 三個 default 中有一個明顯對

如果 `off / auto / ask` 中,**有一個是 obviously correct** (e.g. 安全考量強迫 `off`),trilemma 不成立,選那個 default 就好。不需另開 skill。

## 驗證 checklist

提案「加 flag with config default」前,跑這個 mental check:

- [ ] 我能說出 default = `off` 的具體失敗模式嗎?
- [ ] 我能說出 default = `auto` 的具體失敗模式嗎?
- [ ] 三個失敗模式都不是「marginal edge case」,而是「會在多數場景發生」嗎?
- [ ] User 心中是 binary (要 / 不要),不是 spectrum (要多少)?

**3 個以上 yes → 預設兩難。考慮 separate skill。**

## IDD 內既有的 close call

Bundle 設計 (`idd-issue --bundle-mode`) 一度也考慮過另開 `/idd-bundle` skill:

```
> 考慮過另開新 skill 但選擇加 flag 到 idd-issue:
> 1. 70% 重疊:bundle 仍要 target resolution、attachment upload、mention validation
> 2. 漸進式採用:--parent / --blocked-by / --bundle-mode 三 flag 各有獨立用途
> 3. Skill 數量已多:IDD 已 14+ skills
```
— `idd-issue/SKILL.md` § 「設計理由」

Bundle 過了 default-dilemma checklist:
- 沒 default 兩難(不帶 flag = single issue,自然 default,壓倒性 dominant)
- Per-invocation explicit pick (Case A)
- 重疊率 70% 不到 90%

→ Flag 是對的。Chain mode 過不了 checklist → separate skill 是對的。

## Why does this matter

「先決定該加 flag 還是新 skill」這個 question 在 plugin 設計過程一直出現。沒 framework 時,我們會 default 到「重疊高 → 加 flag」,但這只 cover 90% 重疊的 implementation cost,**忽略 default 設計成本**。

預設兩難 framework 把「default 設計成本」變 explicit。當 framework 顯示 trilemma,proceed with flag 等於把這個 cost 推給未來 user (every invocation 都付 surprise / friction / dead-config tax)。

Separate skill 的「skill count cognitive cost」是 N×log(N) 級(autocomplete + mental indexing),flag 的 default tax 是 N(每個 user × 每個 invocation)。**N 大時後者贏 — separate skill 反而 cheaper**。

## Provenance

- **Surfaced**: 2026-05-08, `/spectra-discuss` for #44 chain-solve mode
- **Triggering insight**: User: 「預設這樣的話要不要 chain 就會是兩難」
- **Resolution applied to**: `/idd-all` vs `/idd-all-chain` decision

## Related

- `idd-issue` SKILL.md § 「設計理由:為什麼不另開 `/idd-bundle` skill」 — counter-example (passes the checklist)
- `idd-plan` skill — separate from `idd-implement` because Plan tier has independent semantics, not because of default dilemma
