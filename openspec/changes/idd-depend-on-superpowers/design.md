## Context

#209（使用者裁決：hard dependency、pai-parallel 為先例、rule 放專案層）+ 同 issue decision comment（D1–D5 逐字在案）。現狀：IDD 在 idd-implement 內建 TDD loop 敘述、在 idd-diagnose 內建 bug RCA 五步驟、在完成前檢查散落各 skill — 與 superpowers 的 test-driven-development / systematic-debugging / verification-before-completion 同構。既有整合先例：openspec/changes/idd-verify-depend-on-pai-engine（canonical 引擎 + 版本閘門 + frozen-fork degrade）。superpowers 安裝來源為 claude-plugins-official（Anthropic 官方 marketplace，Claude Code 首次互動啟動自動註冊）。

## Goals / Non-Goals

**Goals:**

- superpowers 成為 IDD 的 install-time hard dependency（自動安裝 + 缺席 fail-fast）
- 三個 delegation 點以 superpowers canonical skills 取代 IDD 內建等價敘述
- 「深度整合 >> hard-coded」判準文件化為 dev-only 專案 rule

**Non-Goals:**

- 不動 idd-verify ensemble（pai canonical 路徑，另有 spec）、worktree isolation（#167）、planning 紀律（Spectra + idd-plan 覆蓋）— D3 keep 列
- 不 vendor superpowers 任何內容（frozen-fork degrade 不適用，見 D2）
- 不對 superpowers 上游提任何改動；不 pin 版本（無 tag convention 可依）
- #210（既有綁定 audit sweep）另案處理，blocked by 本 change 的 rule 落地

## Decisions

### D1 — 依賴宣告走 native dependencies，target = claude-plugins-official

plugin.json dependencies 條目指向 superpowers@claude-plugins-official，unversioned。替代方案「SessionStart hook 自動 claude plugin install」被排除：native 機制有遞移 enable、prune、doctor 整合，hook 重造這些等於 hard-code 一份 dependency resolver — 正是 rule 反對的形狀。unversioned 理由：官方 marketplace 以 commit-SHA pin 發佈、無 name--vX.Y.Z git tag，宣告 semver range 會落 no-matching-tag 而把 IDD 整個 disable。

### D2 — hard 語意 = 缺席即 fail-fast，無 vendored fallback（與 pai 刻意分岔）

pai 的 frozen-fork degrade 存在理由是時序解耦且 fork 本來就在手上、品質等價；superpowers 是 process-discipline prompt 內容，vendor 即複製 — rule 反對的形狀。替代方案「soft fallback 回內建敘述」被使用者裁決排除（「要hard，保證品質」）。fail-fast 訊息必含一步安裝指令（claude plugin install superpowers@claude-plugins-official）。

### D3 — delegation 三點、keep 三類

delegate：TDD loop（idd-implement）、完成前檢查（idd-implement）、bug RCA 執行框架（idd-diagnose）。keep：verify ensemble（IDD 差異化價值 + pai canonical 已綁）、worktree isolation（orchestration 層目的不同）、planning — 明文含 `brainstorming` 與 `writing-plans`（IDD 對應物是 spectra-discuss / idd-plan / Layer V clarify，已覆蓋；double-delegate 會兩套 planning 紀律打架 — R1 verify #1 補明文，issue Expected 點名 brainstorming 須有判定）。delegation 形狀：SKILL.md 對應段落改為「invoke Skill superpowers:<name>」+ 保留 IDD 專屬 wrapper 紀律（commit refs #N、scope 控制、report 格式）— delegate 的是 process 執行框架，不是 IDD 的 issue-anchored 外殼。

### D4 — R1 rule 內容以 pai 案例為 exemplar

判準鏈：需要的能力生態系有 canonical 套件？→ 上游接口穩定（STABLE contract 或官方 marketplace）？→ 深度整合（依賴宣告 + 存在/版本閘門 + fail-fast 或 frozen-fork degrade）。具名例外：上游無穩定契約、隱私/安全邊界、時序解耦需要（各須記錄理由）。放 .claude/rules/（dev-only，per Clarity row 3），不放 plugins/issue-driven-dev/rules/。

### D5 — pre-flight 雙重驗證，接口 = skill 名稱

superpowers 無 EXTERNAL-CONSUMER CONTRACT，skill 名稱即事實接口。pre-flight 檢查兩層：(1) plugin 目錄存在於 plugin cache（比照 pai 的 cache-path 掃描）；(2) 目標 skill 目錄/SKILL.md 存在。名稱清單集中一處常數宣告（單點維護），上游改組 skills 時錯誤訊息指名缺哪個 skill。

## Implementation Contract

- plugin.json 含 dependencies 條目（superpowers + marketplace 欄位）；marketplace.json 含 allowCrossMarketplaceDependenciesOn 陣列 — grep 可驗
- idd-implement / idd-diagnose SKILL.md 的 delegation 段落含：pre-flight 檢查 bash 區塊、invoke 指示、fail-fast 訊息模板（含一步安裝指令）；原內建等價敘述移除或改為 wrapper 說明
- check-plugin-presence.sh 延伸支援 skill-level 檢查（新增參數或 sibling helper），exit code 與既有慣例一致；缺席訊息含安裝指令
- .claude/rules/deep-integration-over-hardcode.md 存在且含判準鏈 + 三個具名例外 + pai exemplar 引用
- 行為驗證：模擬 superpowers 缺席（暫時 rename cache 目錄）→ idd-implement / idd-diagnose(bug) 路徑 abort 且訊息含安裝指令；恢復後正常
- spectra validate 綠；CHANGELOG + 版本 2.90.0 同步 plugin.json 與 marketplace.json

## Risks / Trade-offs

- superpowers 上游改組 skill 名稱 → delegation 斷裂：pre-flight 指名缺失 skill，錯誤即診斷；名稱常數單點維護降低修復成本
- unversioned 依賴 → 上游行為漂移：接受（官方 marketplace 有 review pipeline），漂移發現時再議 pin
- BREAKING：升級後未裝 superpowers 的使用者 abort — 錯誤訊息一步可修，CHANGELOG 標 BREAKING
