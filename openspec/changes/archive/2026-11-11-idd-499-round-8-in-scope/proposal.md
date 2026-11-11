**GitHub-side tracker**: #499

## Problem

#480 第 8 輪 verify 判定 PASS，但留下四項 In-scope fix（#499），都在 capability spec-on-every-issue 與它的兩個 wrapper：

1. idd-plan 的 Aborted 列說，plan 行留在 proposed 時，idd-implement 看到它不會 propose 也不會 apply。這只在這張 issue 有開著的 change 時成立；沒有時契約第 3 步不讀 plan 行，直接往下 propose。規格與契約裡「Plan tier 的 change 只在核准之後才 propose」那一句同樣比實際寬。
2. 規格把「idd-plan 找開著的 change」列為寫不出檢查，但那是兩次列出 change 加名稱過濾，契約第 3 步同一件事已經是固定 bash 並有測試。idd-plan 只有一句散文，讀不到清單就停的行為退化時不會被發現。
3. idd-implement Step 2 在 propose 之後把 Implementation Plan 的清單換成 change 的 tasks，從 idd-plan 來的路徑也適用。那則留言是維護者核准的紀錄，核准過的清單會被沒有人核准過的 tasks 取代。同一段的「並加一行 Spec plan」還可以讀成再加一行，plan 有兩行 Spec plan 時讀取結果是 invalid。
4. idd-plan 有兩處仍說 idd-implement 跳過它的 Step 2，與同一份文件的 Step 6 及流程圖矛盾。擋這句話的檢查比對的字串已經不在文件裡，所以一定通過。

## Root Cause

#480 的修正輪每一輪改一處，說明文字沒有跟著全部改完；第 6 輪起維護者決定 MEDIUM 與 LOW 改到 follow-up。四項的共同點是文件說的比實際做的寬，而既有的檢查比對的是特定字串，不是性質。

## Proposed Solution

- 第 1 項：Aborted 列改成兩句，分開寫有開著的 change（照契約第 3 步停下，要人重跑 idd-plan）與沒有（那一行不擋任何 run，之後照 idd-implement 的 Step 0.6 重新決定）。規格與契約的那一句限縮到經 idd-plan 的 run。這一列不列舉呼叫者與互動模式：那是 idd-all 的 dispatch table 的內容。
- 第 2 項：idd-plan Step 2 的查詢寫成固定 bash 區塊，印一行以「→ idd-plan change lookup:」開頭的結果（change 名稱、new，或 stop 加原因）。查詢的幾行與契約第 3 步逐字相同，由測試比對。規格把這一項從 No executable check 移到固定 bash 那一句，並加一個 Example。
- 第 3 項：idd-implement Step 2 改成封閉列舉。tasks 寫到哪裡，看最新那則 plan 的標題：標題帶 (Plan tier) 的是 idd-plan 貼、人核准過的，不改它，tasks 另貼一則標題為 Spec tasks 的留言（不帶 checkbox、已經有就不再貼）；本 skill 自己貼的 plan 照舊改清單，Spec plan 行只有一行。規格加一句，Example「reading the Spec plan line」加一列。
- 第 4 項：idd-plan 的兩處改成與 Step 6 一致；檢查改成「idd-plan 沒有任何一行說某個 Step 2 被跳過」。

## Non-Goals

- 未核准的 plan 不得被 implement 的 guard（#496）。
- 在 plan mode 核准 proposal 本身，以及核准紀錄的一般做法（#497）。
- 查詢對形狀不對的 JSON 不會停、同時有兩個以上 change 時取第一個（#496 第 1、3 項）。idd-plan 的新區塊與契約逐字相同，所以帶著同樣的限制；兩處要一起改。
- idd-implement 本身沒有偵測既有 plan 的文字、它的 argument-hint 沒有 spec-change 旗標，以及中止或契約第 3 步停下之後 idd-all 沒有對應的文字：另開 follow-up。
- 把契約第 3 步與 idd-plan 的查詢合成單一實作：拆開契約那一段會讓兩段 bash 靠跨呼叫的 shell 變數相連，風險比重複四行大；另開 follow-up。
- ASSUMPTION: 不升版號。CHANGELOG 加 Unreleased 條目，版號由維護者在合併或發版時決定。

## Success Criteria

- spec-wrapper-contract 新增的檢查在改動前失敗、改動後通過：Aborted 列沒有「看到 proposed 就不 propose」的無條件句；說「核准之後才 propose」的句子都帶有限定；idd-plan 的查詢區塊在十種情況（active、parked、沒有、兩者都有、兩個前綴編號、兩個清單各自失敗、兩個清單各自不是 JSON）印出規格 Example 的結果；區塊與契約的查詢逐字相同；idd-implement Step 2 點名 Plan tier 的標題與 Spec tasks 的標題，沒有再加一行 Spec plan 的指示；idd-plan 沒有任何一行說 Step 2 被跳過。
- spec-change 的測試多一列：較新的 Spec tasks 留言不會被讀成 plan。
- 讀到這些檔案的 suite 全部通過，包含 plan-routing-consistency 與 actionability-gate。
- 連結檢查對改過的 requirement 回 ok。

## Impact

- Affected specs: spec-on-every-issue（MODIFIED requirement「Spec changes go through Spectra behind IDD wrappers」）
- Affected code:
  - Modified: plugins/issue-driven-dev/skills/idd-plan/SKILL.md
  - Modified: plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - Modified: plugins/issue-driven-dev/references/spec-wrapper.md
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-wrapper-contract/test.sh
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-change/test.sh
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
