## Why

人與AI的討論仍散落在聊天視窗，現有IDD無法保存主題的決策演變，idd-ask也無法讀回Discussion。
Issue #331要求將這段歷史接回開發流程，並明確限制「記錄完整」與「AI正確性」的差異。

## What Changes

- 新增idd-discuss、可重試的append-only publisher與來源格式。
- 新增共用GraphQL reader／search helper，納入留言、回覆、分頁與不完整狀態。
- idd-ask預設整合Discussion候選，新增corpus選擇並保留既有issue檢索。
- gh-egress新增check-only能力供publisher沿用同一組隱私／mention檢查。
- 更新公開技能清單、routing、版本及行為測試。

## Capabilities

### New Capabilities

- `idd-discuss`: 授權保存、來源溯源、追加更正、去重及失敗處置。
- `idd-ask-discussions`: Discussion知識查詢與既有issue語料共同引用。

### Modified Capabilities

無移除既有接口；egress新增無dispatch的檢查操作。

## Impact

影響plugins/issue-driven-dev內的新skill與helpers、idd-ask、gh-egress及公開文件。
沿用Python標準函式庫、gh CLI及既有隱私gate，沒有新增平台或安裝依賴。
