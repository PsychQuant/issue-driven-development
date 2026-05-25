## Why

IDD discipline 內部已是 hybrid append + modify(不是純 append),但 hybrid 規則 implicit、case-by-case 演化、從未升上 plugin-level principle。本 session 親身觀察到 6 個 supersession workaround instances(#515 supersession bridge / #148 retroactive remediation / #149 retroactive closing summary / IC_R011 audit accumulation / canonical ref growth / 本 session 自身 issue body 被 bad sed 寫壞),數量持續增加,每個新 IDD feature 撞到「AI-authored stale state」就重新發明 workaround。痛點集中在「沒人問 root rule」— 缺乏 first-class principle 約束 modify-action 該怎麼存在。 Sister #137(unattended-mode Clarity Surface contract)與 #151(commit-body auto-close trap)的 remediation 設計直接受本 principle 決定影響,先 codify 本 principle 才能讓 sister design 一次到位不重做。

## What Changes

- **新 plugin-level rule 檔案** `plugins/issue-driven-dev/rules/append-vs-modify.md` — 含 7-category action taxonomy + decision tree + 與 IC_R007/IC_R010/IC_R011 邊界
- **Action 7-category 分類**:`state-field-update` / `bounded-section-replace` / `audit-block-append` / `inline-replace-before-publish` / `verbatim-preserve` / `append-only` / `free-rewrite`,每個 modify-action 屬其中一類
- **Default refuse**:任何 modify-action 未 declare scope category → SHALL REFUSE(by skill spec + by tooling gate)
- **No actor-based exemption**:AI invocation 與 user invocation 受同等 scope 約束,不分 actor identity
- **Path C gate generalization**:gate logic 採「only-look-at-latest」 統一 across `idd-close` Step 0 / `idd-verify` checklist scan / `idd-update` body sync / `idd-implement` Step 5 Checklist Sync。`#515` supersession bridge 已部分驗證,本 change 把 pattern generalize
- **BREAKING for `idd-edit`**:必須加 `--section` flag,refuse 在 `verbatim-preserve` zones(issue body above `---`)+ refuse 未 declared section name。 不再是 blanket user-modify entry
- **Retroactive scope classification** for 8+ 既有 actions:`/idd-update`(`bounded-section-replace`)/ `/idd-clarify`(`state-field-update`)/ `/idd-close` Step 3.5 inline replace(`inline-replace-before-publish`)/ IC_R011 audit PATCH 各 skill(`audit-block-append`)/ `spectra task done` checkbox(`state-field-update`)/ etc

## Non-Goals (optional)

設計 detail 列在 design.md Goals/Non-Goals 區段(本 proposal 不重複)。 本 change 不涵蓋:跨 plugin append/modify policy(限 IDD 自己)、GitHub-level UX 議題(comment 累積閱讀體驗、PR review UI 等屬 GitHub 產品 non-actionable)、`spectra archive` 既有 hybrid 行為(已 work,無痛點)、shell-scripting safety 的廣義防護(屬 plugin micro-discipline,本 rule 只透過 `(undeclared) → REFUSE` 間接 cover)。

## Capabilities

### New Capabilities

- `append-vs-modify-discipline`: Plugin-level normative principle 定義 7-category action taxonomy + scope declaration requirement + default REFUSE rule + actor-identity-independent enforcement + Path C gate-logic pattern(authoritative_source resolution)+ retroactive classification of existing actions + boundary with IC_R007/IC_R010/IC_R011 sister principles。

### Modified Capabilities

(none — 本 change 引入新 principle,既有 spec 不修改 normative behavior;但會在 implementation 階段 update 多個 SKILL.md 引用本 rule。SKILL.md update 屬實作細節非 spec normative change,所以 Modified Capabilities 為空。)

## Impact

- **Affected specs**:
  - 新 spec:`openspec/specs/append-vs-modify-discipline/spec.md`(本 change 建立)
  - 既有 spec **不修改 normative behavior**(但 implementation 階段會在 multiple SKILL.md citation 加 cross-ref to 本 rule)
- **Affected code**:
  - **New**:
    - `plugins/issue-driven-dev/rules/append-vs-modify.md`(principle 主文 + 7-category mapping table + decision tree)
    - `openspec/changes/add-action-scoped-modify-discipline/specs/append-vs-modify-discipline/spec.md`(delta spec)
  - **Modified**:
    - `plugins/issue-driven-dev/skills/idd-edit/SKILL.md`(加 `--section` flag + refuse 邏輯)
    - `plugins/issue-driven-dev/skills/idd-close/SKILL.md`(Step 0 supersession 改為 generalize 「only-look-at-latest」 pattern)
    - `plugins/issue-driven-dev/skills/idd-verify/SKILL.md`(gate logic align 「only-look-at-latest」)
    - `plugins/issue-driven-dev/skills/idd-update/SKILL.md`(gate logic align)
    - `plugins/issue-driven-dev/skills/idd-implement/SKILL.md`(Step 5 Checklist Sync align)
    - `plugins/issue-driven-dev/skills/idd-clarify/SKILL.md`(retroactive label as `state-field-update`)
    - `plugins/issue-driven-dev/skills/idd-issue/SKILL.md`(retroactive label IC_R011 audit PATCH as `audit-block-append`)
    - `plugins/issue-driven-dev/skills/idd-diagnose/SKILL.md`(same)
    - `plugins/issue-driven-dev/manifesto.md`(若存在,加 one-section overview pointing to 新 rule)
    - `plugins/issue-driven-dev/CHANGELOG.md`(BREAKING `idd-edit` `--section` 標記)
  - **Removed**:
    - 無 file removal;`#515` supersession bridge 邏輯保留作為 backward-compat fallback(legacy issues without `## Implementation Complete > ### Checklist` 仍走老 scan)
- **Affected systems**:
  - `idd-edit` BREAKING:未帶 `--section` flag 的舊 invocation pattern 會 refuse → migration period 需文件提示(CHANGELOG + skill SKILL.md prominent warning)
  - 4 個 gate sites(close / verify / update / implement)行為一致化 — 對 user 透明,但對 plugin maintainer 是 single mental model
  - Sister #137 / #151 unblock:design 階段必須 align 新 principle(每 action declare scope)
