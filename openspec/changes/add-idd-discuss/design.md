## Context

Refs #331。由既有對話收斂，PR／unattended。Claude canonical skill tree不分叉；Codex沿用compatibility reference。

## Goals / Non-Goals

保存使用者明確指定的可見來源；穩定ID、追加更正、查得到、可驗證。
不監聽背景對話、不假造缺失歷史、不保證AI論斷正確、不聲稱GitHub可控制每則通知。

## Decisions

- 比較方案：只寫skill模板最輕但重試仍靠記憶；獨立資料庫超出第一版；選擇skill＋精簡helper，
  deterministic I/O透過gh GraphQL，語意整理由agent，兩者契約各自明確。
- append-only：主文為初次快照，後續完整快照是comment。永不修改主文或人工留言，拒絕以
  摘要更新蓋掉歷史。第一版不提供正文同步更新。
- Payload JSON v1：`topic_id`, `source_id`, `title`, `summary`, `source_scope`, `messages`。
  messages每筆：`id`, `role`(user|assistant|tool), `text`，選填`author`, `model`, `time`。
  source_scope是非空文字，agent明示可取得範圍。`decisions`可選陣列，每筆`text`,
  `user_message_id`必須連到role=user；這只驗來源存在，不認證語意。
- `topic_id`與`source_id`為opaque非空字串。標題不是去重key。topic/source穩定hash加payload
  digest放在第一行marker；原文逐行blockquote，summary標示AI整理。metadata未知以unknown。
- 本地state置於`.claude/.idd/state/discussions/`（由顯式--state-dir定位），每repo/topic
  使用file lock；state以atomic replace保留discussion ID／event digest／attempt狀態。
- 首次建立先列出bounded Discussions核對同topic marker；已知編號只讀該篇。
  僅接受viewer本人發出的managed marker；已知topic與指定Discussion不符即拒絕。
  source同ID同digest為no-op；不同digest拒絕，要求新的source_id記錄修正。
- mutation前寫pending state；成功才標posted。逾時或API errors保留uncertain，重跑先核對
  遠端marker，找到同event可recover；找不到不盲重送。跨裝置並發需序列化，不能保證全球exactly-once。
- Publisher明確`--publish`才允許網路mutation，否則只產生本地草稿。每次真正寫入前，將
  完整title/body經gh-egress `check`做同一組gate。check不呼叫gh、更不新增AI判斷regex。
- Reader API (`scripts/lib/discussions_api.py`)：`DiscussionError`、`GitHub.graphql(query, variables)`
  回data；`repo(repo)`回id/hasDiscussionsEnabled/visibility/viewerPermission；`viewer()`回login；
  `search(repo,query,limit)`與`list_discussions(repo,max_items)`回`items,complete,warnings`；
  `get(repo,number,max_comments)`回Discussion metadata及flattened `comments,complete,warnings`。
  comment保留id/url/body/author/createdAt/updatedAt/replyTo；作者是login字串或null。
- reader CLI為`idd-discussions-read.py search|get|list|repo`；JSON輸出，非零表示API失敗，
  partial回明確complete=false。搜尋all states、不以Q&A/Ideas過濾。檢索字串不拼shell；
  repo必須owner/name，query不得繞過指定repo。
- idd-ask保留idd-find原backend，同時取得Discussion候選後合併排序，全文top-N總數仍≤10。
  `--corpus issues|discussions|all`，預設all。每個候選用kind+URL區別；partial只以已讀內容回答，
  每項引用連到實際comment。不得把Discussion標記或舊AI「已通過」敘述當成目前執行授權。

## Risks / Trade-offs

GitHub API没有atomic create idempotency；本地journal與遠端核對降低重試重複，保留未知時拒絕。
讀取上限會使大型討論／repository不完整，publisher拒絕在去重未完整時寫入；ask明示partial。
摘要的忠實度仍需使用者／agent檢查；role=user引用不是同意的機械證明。

## Validation

fixture GraphQL模擬建立／追加／重跑／不確定回覆／locked／disabled／分頁／reply／搜尋失敗。
用既有egress fixture suite做回歸；完整測試入口、live read-only API smoke與獨立6-lens驗證。
所有mutation fixture均離線，不發測試Discussion或通知給真實使用者。
