## Why

`/idd-all` 跑完 verify 就停下，merge 與 `/idd-close` 一律留給人（#392）。使用者要它跑到底：verify 乾淨通過就自己 merge 並 close，最後回報做了什麼。理由是這兩個動作都能復原（Foresay 的 traceable 分支：意圖清楚且可逆的操作不設事前確認，但必須事後回報）。這也是 #400「在雲端完整跑完一張 IDD」的前提：沒有自動 close，雲端 run 只能停在 PR。

## What Changes

- **BREAKING**（對 `/loop` 等自動化 caller）：`/idd-all` 的終點從 verified 改成 closed。最新一輪 verify 沒有 Blocking、也沒有 In-scope fix 時，PR mode 會 merge PR 再跑 `/idd-close`；direct-commit mode 在預設 branch 上會先 push 再 close。
- 自動收尾只用在意圖確認過、而且 run 開始之後沒有別人插手的 run（verify round 3、4 之後的範圍決定，#392 comment 6566557673、6567272352）：issue 與 comment 都出自有寫入權限的人、沒有未解的 Clarity 問題、unattended run 的 tier 是 Simple、最新 Diagnosis 沒有略過確認的紀錄；不符合就停在 verified、PR 照開。
- 無人在場（unattended）時，In-scope fix 與 Blocking 一起在同一個 PR 修，修完重跑 verify，最多 2 輪；仍不乾淨就停在 verified。有人在場（attended）時照舊不自動修。
- merge 前必須通過 guardrail（verify round 1–3 之後擴充，完整清單見 design 與 `skills/idd-all/SKILL.md` Phase 5c；最初的四道是）：verify 乾淨、CI checks 全綠、Step 0.8 auto-close trap 掃描乾淨、idd-all 自己組的 squash commit message 不含 close 類關鍵字緊鄰 issue 編號。任一不過就停在 verified 並寫明原因。
- `/idd-close` 新增「由 idd-all 呼叫」的指示：residue 記為殘留、follow-up 照 IC_R011 預設開 issue、Step 1.6 與 Step 1.55 的警告一律停下不 close、distribution sync 在有人在場時照問、無人在場時略過並寫進回報。
- 新增一支 helper，把 verify 報告的分類表解析成計數；表格讀不出來時一律判定「不乾淨」，不會因解析失敗而 merge。
- Phase 6 回報改成 Foresay 的 operation 格式：做了什麼、作用在哪、實際改動範圍、開了哪些 follow-up、記下的 residue、略過的 distribution sync，以及復原方式（`gh issue reopen`、`git revert`）。
- MANIFESTO 的 auto-merge 段改成兩個理由並列（verify 保證改得對；可逆讓它免事前確認、但必須事後回報），指向已結案 #37 的那段改指 #392。
- 吸收 #387：`parallel-orchestration` 的 batch 情境與 idd-all 的 description 一併寫明 meeting 例外。
- 不變：`--in-chain`（chain 的 cluster PR 由 `/idd-all-chain` 處理，見 #393）、`type=meeting` 的停點、`--review`（帶這個旗標時照舊停在 verified）。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `idd-pr-hitl-modes`: 終點從「verify 後停下」改成「verify 乾淨就 merge 並 close」；PR path 與 direct-commit path 的既有條款配合修改；新增修正迴圈、merge guardrail、idd-close 指示、回報格式、解析失敗即不乾淨等條款。
- `parallel-orchestration`: batch mode 每張各自 merge 並 close，meeting issue 停在 diagnosed 或 planning（吸收 #387）。
- `idd-ic-r011-checkpoint`: `/idd-close` Step 3.5 保留 3 選項詢問，但 `ORCHESTRATED BY /idd-all` 呼叫時不問、取 IC_R011 預設（verify round 1 加）。

## Impact

- Affected specs: `idd-pr-hitl-modes`、`parallel-orchestration`、`idd-ic-r011-checkpoint`、`idd-existing-work-lookup`
- Affected code:
  - New: plugins/issue-driven-dev/scripts/verify-gate.py
  - New: plugins/issue-driven-dev/scripts/close-stage.py（verify round 1 加：close stage 的單一 process；round 2 加 confirm-close）
  - New: plugins/issue-driven-dev/scripts/tests/close-stage/test.sh、fake-gh.py
  - Modified: plugins/issue-driven-dev/references/ic-r011-checkpoint.md、plugins/issue-driven-dev/skills/idd-all-chain/SKILL.md、docs/workflows.md（verify round 1 加）；plugins/issue-driven-dev/references/config-protocol.md（verify round 2 加）
  - New: plugins/issue-driven-dev/scripts/tests/verify-gate/test.sh
  - New: plugins/issue-driven-dev/scripts/tests/merge-and-close-contract/test.sh
  - Modified: plugins/issue-driven-dev/skills/idd-all/SKILL.md
  - Modified: plugins/issue-driven-dev/skills/idd-close/SKILL.md
  - Modified: plugins/issue-driven-dev/skills/idd-verify/SKILL.md（Step 5a 的報告格式規則，apply 時加，見 tasks.md 2.2 的 ASSUMPTION）
  - Modified: plugins/issue-driven-dev/MANIFESTO.md
  - Modified: plugins/issue-driven-dev/CLAUDE.md
  - Modified: plugins/issue-driven-dev/README.md
  - Modified: plugins/issue-driven-dev/references/usecase-routing.md
  - Modified: plugins/issue-driven-dev/references/pr-flow.md
  - Modified: plugins/issue-driven-dev/references/parallel-orchestration.md
  - Modified: docs/commands.md
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
  - Modified: plugins/issue-driven-dev/.claude-plugin/plugin.json
  - Modified: .claude-plugin/marketplace.json
- 開工順序：#383 的 branch 正在改 `plugins/issue-driven-dev/skills/idd-all/SKILL.md`，實作要等 #383 merge 後才開始。
- 相關 issue：#392（本張）、#387（併入）、#393（idd-all-chain 是否跟進，另案）、#400（雲端 run 的終點依賴本張）。
