**GitHub-side tracker**: #499

## Problem

#499 的 verify 第 1 輪判定 PASS，表裡有五項要在這張修的問題：

1. idd-plan Step 2 新加的查詢區塊不檢查 NUMBER。那一次 Bash 呼叫裡沒設、或不是數字時，名稱過濾比對不到任何東西，區塊印 new，開著的 change 被讀成沒有；值是點加星號這類字串時會比對到別張 issue 的 change。
2. idd-implement Step 2 決定 tasks 寫到哪裡時看最新那則 plan 的標題，並寫明不看留言是誰貼的；「已經有 Spec tasks 留言就不再貼」也沒有限定作者。讀取 plan 行的指令只讀有寫入權的帳號貼的 plan，兩邊選到的可能不是同一則。契約第 3 步的說明有同樣的缺口。
3. spec-wrapper-contract 檢查「核准之後才 propose」的句子有沒有帶限定時，豁免字樣「有核准」也比對到「沒有核准」。
4. 同一個 suite 檢查「idd-plan 沒有任何一行說 Step 2 被跳過」時，否定句的排除以整行為單位，同一行另有一句真的說跳過時會漏掉。
5. 第 3 項那個檢查只看帶有 tier 名稱的句子；契約講 plan 行的那一段改寫後沒有那個詞，拿掉它的限定，檢查仍然通過。

## Root Cause

第 1 項：區塊照契約第 3 步的查詢逐行抄寫，契約的查詢本來就不檢查 NUMBER；新區塊的目的是讀不到時停下，卻沒有檢查它自己需要的輸入。第 2 項：寫 Step 2 的規則時只想到兩個 skill 用同一個帳號貼文、不能用「是不是自己貼的」來分，把它寫成「不看留言是誰貼的」，連有沒有寫入權也一起不看了。第 3 到 5 項：檢查是照當時的句子寫的，沒有用應該被抓到的資料測過檢查本身。

## Proposed Solution

- 第 1 項：區塊在查詢之前檢查 NUMBER，沒設、空字串、以 0 開頭或不是十進位數字時印 stop 加原因，不執行任何列出 change 的指令。查詢的三行不動，仍與契約第 3 步逐行相同。規格那一句加上這個情況，Example 加六列。
- 第 2 項：Step 2 與契約寫明，最新那則 plan 就是讀取 plan 行的指令選的那一則（有寫入權的帳號貼的），Spec tasks 留言也只有有寫入權的帳號貼過才算已經貼過。規格加一句；讀取端的行為沒有改，既有的 Example 已經有「沒有寫入權的帳號貼的 plan 不算」那一列。
- 第 3 到 5 項：三個檢查改嚴，並各加自測：把應該被抓到的句子餵給檢查，確認它抓得到。

## Non-Goals

- 契約第 3 步的查詢（idd-implement 執行的那一份）加同樣的 NUMBER 檢查：那一份在 #480 就是這樣，與清單形狀不對時讀成沒有 change 是同一類，記在 #496。這次只讓新區塊擋住自己的輸入。
- 兩份查詢合成單一實作（#500 第 10 項）。
- 用程式檢查 Step 2 實際選到哪一則留言：選留言與貼留言由照 SKILL.md 執行的模型做，規格把它列在 No executable check，這次不改。
- ASSUMPTION: 不升版號，CHANGELOG 補在既有的 Unreleased 條目。

## Success Criteria

- spec-wrapper-contract 新增的檢查在改動前失敗、改動後通過：NUMBER 沒設、空字串、abc、帶井號的 7、點加星號、07 六種情況各印一行以 stop 開頭的結果，而且不執行任何列出 change 的指令；三個自測各抓到它該抓的句子；每一行說「就不再貼」的都寫明有寫入權的帳號。
- 查詢原有的十列、逐行比對與 stop 原因相同這些檢查照舊通過。
- run-all-tests 的 73 個 suite 與 spectra-archive-post-ic 全部通過。
- 連結檢查對改過的 requirement 回 ok。

## Impact

- Affected specs: spec-on-every-issue（MODIFIED requirement「Spec changes go through Spectra behind IDD wrappers」）
- Affected code:
  - Modified: plugins/issue-driven-dev/skills/idd-plan/SKILL.md
  - Modified: plugins/issue-driven-dev/skills/idd-implement/SKILL.md
  - Modified: plugins/issue-driven-dev/references/spec-wrapper.md
  - Modified: plugins/issue-driven-dev/scripts/tests/spec-wrapper-contract/test.sh
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
