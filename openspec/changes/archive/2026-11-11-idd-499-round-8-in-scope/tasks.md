## 1. 測試先行

- [x] 1.1 idd-plan 的查詢區塊有可執行的檢查：依 requirement「Spec changes go through Spectra behind IDD wrappers」的 Example「idd-plan looks up the open change of the issue」，spec-wrapper-contract 新增一組檢查，測試檔帶標記 spec-example: spec-on-every-issue / idd-plan looks up the open change of the issue。檢查從 idd-plan 的 SKILL.md 抽出印「→ idd-plan change lookup:」的 bash 區塊，放進只有假的 spectra 與假的 gh 的環境執行，Example 的十列各一個檢查；另外檢查每次只印一行、只執行兩個列出 change 的指令、沒有呼叫 gh，以及區塊裡查詢的幾行與契約第 3 步逐字相同。驗證：跑 spec-wrapper-contract，這一組在 SKILL.md 改動前失敗（抽不到區塊）。
- [x] 1.2 較新的 Spec tasks 留言不會被讀成 plan：依 Example「reading the Spec plan line」新增的一列，spec-change 的測試加一個 plan_case（維護者的 plan 點名 idd-7-x，之後有一則較新的 Spec tasks 留言，讀出 change、idd-7-x、exit 0）。驗證：跑 spec-change 的測試，這一列通過。它釘住讀取端既有的行為，改動前就通過；之後有人放寬 plan 標題的比對時它會失敗。
- [x] 1.3 四項文字各有性質檢查，不比對單一字串（spec-wrapper-contract）：(a) idd-plan、idd-implement 與契約沒有任何一句說 idd-implement 看到 proposed 就不 propose 或不 apply 而不帶「開著的 change」這個條件，Aborted 列提到開著的 change 與契約第 3 步；(b) 契約與兩個 skill 裡說「核准之後才 propose」的句子都帶有「經 idd-plan」的限定（規格的那一句由這個 change 的 delta 改，主規格要到封存才更新，所以不由這條檢查讀）；(c) idd-implement Step 2 點名 Plan tier 的 plan 標題與 Spec tasks 的標題、寫明不帶 checkbox 與已經有就不再貼，而且沒有再加一行 Spec plan 的指示；(d) idd-plan 沒有任何一行說某個 Step 2 被跳過，取代原本比對 Step 2: SKIP 的檢查；(e) idd-plan Step 6 寫明 tasks 另貼成 Spec tasks 留言。驗證：跑 spec-wrapper-contract，(a) 到 (e) 在改動前各自失敗。

## 2. skills 與契約

- [x] 2.1 idd-plan 用固定 bash 找開著的 change，中止之後的說明與實際一致：Step 2 加查詢的 bash 區塊，原本描述查詢的那句散文改成指向區塊並說明三種結果各自怎麼用；Step 5 的 Aborted 列改成兩句（有開著的 change 時照契約第 3 步停下，沒有時那一行不擋任何 run）；Step 0 的 chain_to_idd_implement task 與「與 idd-implement 的關係」最後一段改成與 Step 6 一致；Step 6 與流程圖寫明 tasks 另貼成 Spec tasks 留言。驗證：1.1 與 1.3 的 (a)(d)(e) 通過；spec-wrapper-contract 原有的檢查仍通過，其中檢查散文那一行含 parked 清單指令的那一條改成檢查抽出的區塊。
- [x] 2.2 idd-implement 不改核准過的 plan：Step 2 的說明改成封閉列舉，誰貼 plan、要不要 propose 三種；tasks 寫到哪裡兩種，看最新那則 plan 的標題。驗證：1.3 的 (c) 通過；spec-wrapper-contract 對 Step 2 原有的檢查仍通過。
- [x] 2.3 契約第 3 步的說法與規格一致：references/spec-wrapper.md 講 plan 行的那一段與輕量形式那一項限縮到經 idd-plan 的 run，並寫明核准過的 plan 不改、tasks 另貼。驗證：1.3 的 (b) 通過；既有檢查鎖住的「核准之後才由 idd-implement propose」仍在。

## 3. 收尾

- [x] 3.1 CHANGELOG 記下這四項：plugins/issue-driven-dev/CHANGELOG.md 加 Unreleased 的 Fixed 條目，註明 #499。驗證：條目在 4.0.0 之前，已發布版本的條目沒有改動（git diff 只有新增行）。
- [x] 3.2 讀到這些檔案的 suite 全部通過：spec-wrapper-contract、spec-change、plan-routing-consistency、actionability-gate、meeting-issue-type、complexity-hard-gate、superpowers-staging、issue-write-back、skill-plugin-root、verify-scratch-paths、check-existing-work、gh-egress-rollout、pr-body-autoclose-guard、dashboard-comment、closing-summary-prose-drift、blocked-by-mutation，最後跑 run-all-tests.sh。驗證：每個 suite 的結束碼是 0，結果記在 Implementation Complete。
