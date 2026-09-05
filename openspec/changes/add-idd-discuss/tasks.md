## 1. Specification and issue framing
- [x] 1.1 建立issue331、發布Diagnosis、記錄模式與資料來源界線。
- [x] 1.2 凍結append-only、stable source IDs、uncertain journal與combined retrieval契約。

## 2. Implement and test
- [x] 2.1 實作shared GraphQL reader與CLI，測試搜尋／留言／回覆／分頁／錯誤。
- [x] 2.2 gh-egress新增check-only，既有所有網路dispatch行為不變。
- [x] 2.3 實作publish helper、來源格式、去重、鎖與uncertain recovery，行為測試通過。
- [x] 2.4 新增idd-discuss skill，整合idd-ask、公開routing與技能清單。
- [x] 2.5 更新版本與changelog、完成spec validation、baseline對照與live read-only smoke。

## 3. Verify and deliver
- [ ] 3.1 執行獨立requirements／logic／security／regression／DA與Codex驗證，修正blocking findings。
- [ ] 3.2 提交、更新issue Current Status與驗證紀錄、push及建立PR，停止於verified。
