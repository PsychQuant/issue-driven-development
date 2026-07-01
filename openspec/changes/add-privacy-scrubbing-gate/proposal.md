## Why

IDD 的每個 GitHub egress site（`gh issue create` / `gh issue comment` / `gh issue edit`）目前把 AI 起草的 body **直接 dispatch 出去，沒有任何 privacy gate**。當使用者在 third-party clone（reference / 教學 / 研究素材，見 #192）或任何公開 repo 上跑 idd-* skill 時，起草的 body 很容易夾帶 local / private identifiers：

- 本機 home path（`/Users/<name>/...`）
- `~/.claude.json` 裡的 project basename（洩漏本機資料夾結構）
- collaborator 的真實姓名（未公開 / 非當事人授權）
- 未發表的研究、內部 context

一旦 dispatch 到公開或第三方 tracker 就**不可逆**（GitHub 通知已送出、內容已公開存檔）。這與 CLAUDE.md 的「第三方逐字內容不進 remote」隱私邊界同源——只是這裡的洩漏路徑是 **AI 起草的 issue/comment body**，不是 raw 檔案。

現有唯一防線是 `sanitize_source_label`（#75，UTF-8-safe control-char strip + `@`-mention refuse）。它處理的是 **source label**（footer 的檔名 / 貼文 excerpt），不是整個 body 的**語意層** private identifier；而且它 trapped 在 `skills/idd-issue/SKILL.md:1815-1865` 內，其他 11 個 egress site 完全沒有覆蓋。缺的是一個 **repo-aware、跑在所有 egress 前**的 privacy-scrubbing gate。

**GitHub-side tracker**: #202

## What Changes

新增一個 **repo-aware privacy-scrubbing gate**，跑在任何 GitHub egress 之前。核心是「**LLM 語意偵測 + deterministic 執行 checkpoint**」的分離：

1. **Detection = LLM 語意自審，不是固定 regex / denylist。** Gate 在 egress time 指示 AI 對起草的 body 做語意檢查，找出 private identifiers（含**人名由語意判斷**——AI 從 context 理解誰是私人的，不用 NLP name-detector 或固定名單）。**不維護任何 pattern set。**（owner 明確否決固定偵測。）

2. **Enforcement = 一個 minimal deterministic checkpoint。** 關鍵區分：偵測是 LLM（語意、非固定），但**「gate 到底有沒有跑」必須被 deterministically 保證**——否則「規則說 AI 該自審」只是祈禱 AI 記得。引入單一 choke-point wrapper `scripts/gh-egress.sh`，**所有** egress site 改呼叫它、不再直接 `gh issue create/comment/edit`。wrapper **不做 pattern matching**（那正是 owner 否決的固定偵測），只：(a) enforce 自審步驟在 dispatch 前確實跑過；(b) 當作**極小的 last-resort safety net**，只攔 2-3 個 zero-tolerance **機械**項目——literal 絕對 home path（`/Users/<name>`）與 verbatim `~/.claude.json` 內容。語意廣度完全交給 LLM。

3. **Classification（gate 何時 fire + 多嚴）= 重用既有 third-party 偵測**（`references/config-protocol.md:238-268`，viewerPermission-based own vs third-party），**再加一支 repo visibility（`isPrivate`）query**——目前只 query `isFork` + `viewerPermission`。三個嚴格度：
   - **third-party**（viewerPermission ∉ {WRITE,MAINTAIN,ADMIN}）→ **ENFORCE**（block + 顯示 redaction diff + 要求 confirm）
   - **own-org + public** → **WARN**（flag，預設 proceed）
   - **private**（`isPrivate=true`）→ **LIGHT**（仍 honor CLAUDE.md raw-third-party 規則）
   這同時解掉 `add-third-party-clone-setup/design.md:145` 標記的 residue（push-permission 是 proxy，把 own+public 與 own+private 混為一談）。

4. **Redact vs Block = ENFORCE 時 block-with-diff**（偵測 → 顯示 redaction diff → 拒絕 dispatch 直到 confirm）。**絕不** silent auto-redact。這 mirror 既有 `sanitize_source_label` 的「refuse not strip」哲學（#75）。

5. **Shared home = 把 sanitization 契約抽出 skill-local。** 新增 `rules/privacy-scrubbing.md`（policy / behavioral rule，sibling to `rules/tagging-collaborators.md`）+ `scripts/gh-egress.sh`（choke point）+（若 convention warrant）references/-level 契約。既有 `sanitize_source_label` **原封不動**繼續做它的 control-char / mention 工作；privacy scrubbing 是疊在上面的新語意層。

6. **Egress retrofit = ~12 sites**（idd-issue, idd-comment, idd-edit, idd-diagnose, idd-implement, idd-plan, idd-update, idd-clarify, idd-close, idd-verify, idd-all-chain，加上 multi-finding Stage 4 dispatch）跑 `gh issue create/comment/edit`。邏輯只放**一處**（wrapper）；各 site 從 `gh issue comment ...` 改成 `bash scripts/gh-egress.sh comment ...`。**Phasing（APPROVED）：spec 覆蓋所有 site，但實作 idd-issue 先落地**（主要 authoring path、風險最高），其餘 site 列 follow-up。tasks.md 反映此 phasing。

## Non-Goals

- **不維護固定 pattern set / denylist / NLP name-detector** — 語意偵測是 LLM 的職責，wrapper 只留 2-3 機械 zero-tolerance 項當 safety net。
- **不 silent auto-redact** — ENFORCE 一律 block-with-diff 要 confirm，不偷偷改 body。
- **不改 `sanitize_source_label` 既有行為** — 它繼續管 control-char / `@`-mention refuse；privacy scrubbing 是新增層，不取代。
- **不在此 change 一次 retrofit 全部 site** — spec 覆蓋全部，實作 idd-issue 先，其餘 follow-up（見 tasks.md phasing）。
- **不解「什麼算 private」的邊界成固定規則** — 人名 / 未發表判斷永遠是 LLM 語意判斷，列為 acknowledged residue（見 design Open Questions），不靜默吞掉。

## Capabilities

### New Capabilities

- `privacy-scrubbing-gate`: 一個 repo-aware privacy-scrubbing gate，跑在所有 GitHub egress 之前。定義 (a) LLM 語意自審為唯一偵測機制（無固定 pattern）；(b) `scripts/gh-egress.sh` 單一 choke-point wrapper deterministically enforce 自審跑過 + 攔 2-3 機械 zero-tolerance 項；(c) 依 repo visibility（重用 viewerPermission + 新增 `isPrivate` query）三級嚴格度 third-party=ENFORCE / own-public=WARN / private=LIGHT；(d) ENFORCE 時 block-with-diff、不 silent redact；(e) 共用 `rules/privacy-scrubbing.md` policy rule + wrapper 為 shared home；(f) ~12 egress site retrofit 到 wrapper，實作 idd-issue 先、其餘 follow-up。

### Touched Capabilities (deltas)

- `idd-issue-multi-finding-source`（MODIFIED）: Stage 4 dispatch 從「直接呼叫 `gh issue create/comment/edit`」改為「透過 `scripts/gh-egress.sh` choke-point wrapper dispatch」，每個 create/comment/edit action 在 dispatch 前經過 privacy-scrubbing gate；warn-continue + JSONL audit trail 語意不變。
- `references/config-protocol.md`（cross-ref，非 openspec spec）: mechanism 5 的 repo classification 新增 `isPrivate` query，讓「own-public vs own-private」可分流（供 gate 的 WARN vs LIGHT 判斷）；沿用既有 viewerPermission-based own vs third-party 偵測。
