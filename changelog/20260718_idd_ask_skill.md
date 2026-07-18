# 2026-07-18 — /idd-ask 落地：surfacing family 第 4 員（v2.99.0）

## 已 merge 至 main（PR #266）

- **#72 /idd-ask**（Spectra `idd-ask-skill`，opt-out → propose）：issue 知識庫 grounded 問答，鏡像 /spectra-ask。question → decide-to-search gate（bug 貌問題**不觸發 diagnose**）→ retrieval **delegate idd-find backend**（family「不重造唯讀查詢」鐵律首次用於 primitive 之間）→ top-N 全文（5／上限 10）→ grounded 合成：blockquote 原問題、claim 必附引用、source priority（closed-with-PR > open > orphaned comment）、分歧 surface、`### Referenced Issues`、**查無誠實說查無**（訓練記憶不是語料）。read-only allowed-tools 鎖定。

## 過程紀錄

- **#140 增員程序首戰**：三題判準的 Q3（delegate 消費者）弱命中 — 以 spectra-ask 同構先例（ask 類消費者本來就是人）judgment 開員，先例寫回 `surfacing-primitives.md` 供未來弱 Q3 候選參考。

#72 已依 close ritual 結案（summary + body sync + dashboard）；`idd-ask-skill` 已 archive（idd-ask capability spec +2 requirements）。新 suite `idd-ask` 17/17；全 sweep **37 suites 0 fail**。**v2.99.0** 同日發版（今日第二版 — 上午 v2.98.0 codex 依賴化）、marketplace 已同步。

CLAUDE.md：plugin CLAUDE.md 已於 PR 內加 idd-ask 列；專案 CLAUDE.md 無需更新。
