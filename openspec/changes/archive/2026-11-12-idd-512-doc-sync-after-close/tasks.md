## 1. 測試先行

- [x] 1.1 doc-sync 檢查的位置有可執行的檢查：依 requirement「The doc-sync sweep runs after the issue is closed」的 Example「where the doc-sync sweep sits in idd-close」，doc-sync-sweep 加一個讀 idd-close SKILL.md 的檢查程式與 Example 八列各自的檢查，測試檔帶標記 spec-example: idd-close-doc-sync / where the doc-sync sweep sits in idd-close。現行的檔案要通過；七份改壞的副本（「位置」那一句說在關閉之前、那一句沒說 issue 已經關閉、沒有「位置」那一句、Step 6.3 移到 Step 4 之前、Step 6.3 移到 Step 6.5 之後、清單裡 doc_sync_sweep 排在 publish_and_close 之前、清單裡 doc_sync_sweep 排在 distribution_sync_chain_detection 之後）各自被抓到，而且抓到的原因是那一份改壞的地方。驗證：改 SKILL.md 之前，現行的檔案不通過，說在關閉之前的那份副本做不出來（與現行檔案相同），四份改順序的副本除了順序還帶著那一句的問題。

## 2. skill 文字

- [x] 2.1 改 idd-close Step 6.3 的「位置」那一句：寫成 issue 已關閉、closing summary 已貼出之後，在 Step 6 body sync 之後、Step 6.5 distribution sync 之前。步驟的順序與 Step 0.5 的清單不動。驗證：1.1 全部通過；doc-sync-sweep 原有的七個檢查照舊通過。

## 3. 收尾

- [x] 3.1 CHANGELOG 的 Unreleased 加 Fixed 條目（#512）。驗證：git diff 只有新增行，已發布版本的條目沒有改動。
- [x] 3.2 跑 doc-sync-sweep 與整套測試（run-all-tests.sh 與 spectra-archive-post-ic）。驗證：結束碼都是 0。
