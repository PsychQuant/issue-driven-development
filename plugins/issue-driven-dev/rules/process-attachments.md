# Rule: Process Attachments

> Issue body / comments 含 attachment(docx / pdf / image / 其他 binary)時,**忽略附件 = 忽略來源**。所有 idd-* skills 在讀 issue 時都必須處理附件 — 上游負責下載,下游負責檢查。

## Why this rule exists

`gh issue view --json body` 抓到的只是 markdown 字面 — link target 的內容**不在** JSON 回應裡。如果 skill 沒主動 fetch + parse,等於只看了 issue 標題式的概述,完整 source-of-truth(摘要 / 老師 feedback / 受試者資料 / 圖表)被忽略。

歷史案例: kiki830621/collaboration_liu-thesis-analysis#21 — `idd-diagnose` 跑時沒讀附件 docx,後續 spectra-propose 重建出來的 design.md / spec.md 漏了「mismatch / SP 作為機制 / construct mapping」三個從附件結尾段落才能讀出的關鍵 narrative bridge。修補成本 = 一輪 design/spec/tasks edit + version bump。

## Single source of truth: helper script

**機械工作(detection / download / manifest write / diff check / disk verify)由 `scripts/process-attachments.sh` 處理**,SKILL.md 直接 call 不再 inline curl/jq。理由:文檔 link Claude 不一定 follow,shell call 一定執行。

```bash
# 上游下載(idd-issue / idd-diagnose)
bash $CLAUDE_PLUGIN_ROOT/scripts/process-attachments.sh download <NUMBER>

# 下游檢查(idd-implement / idd-verify / idd-report)
bash $CLAUDE_PLUGIN_ROOT/scripts/process-attachments.sh check <NUMBER>

# 結案 disk 驗證(idd-close)
bash $CLAUDE_PLUGIN_ROOT/scripts/process-attachments.sh verify <NUMBER>
```

Repo 自動從 walk-up config 解析(支援 `.claude/.idd/local.json` / `.claude/issue-driven-dev.local.json` / `.claude/issue-driven-dev.local.md`);可用 `--repo owner/repo` 顯式 override。`IDD_CALLER` 環境變數記錄到 manifest `fetched_by` 欄位。

完整 script 內容見 [`scripts/process-attachments.sh`](../scripts/process-attachments.sh)。

## Scope(誰在哪一階段做什麼)

| Skill | Action | 用 script 哪個 command |
|-------|--------|-----------------------|
| `idd-issue` | 來源附帶素材 → 同時上傳 release + 下載到 attachment dir | `download`(配合既有上傳邏輯) |
| `idd-diagnose` | Step 1.5 fetch issue 全部 attachment | `download` |
| `idd-implement` | Step 1.2 確認 manifest;偵測 diagnose 後新增 | `check` |
| `idd-verify` | 把 attachment 路徑塞進 reviewer agent prompt | `check` + 用 `attachments/issue-NNN/` 路徑 |
| `idd-close` | 確認 closing comment 引用的檔案還在 disk | `verify` |
| `idd-report` | 報告引用 attachment 用相對 path | `check` |
| `idd-comment` / `idd-update` / `idd-edit` | 引用 attachment 時用相對 path,不主動 fetch | (不 call script) |
| `idd-list` / `idd-config` | 不分析 issue 內容 | (不適用) |

下游若發現 manifest 缺漏(`check` 回 exit 1) → **不 auto-fetch**,而是輸出警告引導使用者重跑 `idd-diagnose`。理由:下游補抓會 mask 上游 skill 的 bug,讓「忘了處理 attachment」這類錯誤晚被發現。

## Storage location

```
.claude/.idd/attachments/issue-{NNN}/
  ├── 檔名.docx
  ├── 圖片.png
  └── _manifest.json
```

每個 issue 一個子目錄。檔名保留原始 filename(URL 解碼後)。

**Manifest schema**(由 helper script 寫入):

```json
{
  "issue": 21,
  "fetched_at": "2026-04-30T03:13:02Z",
  "fetched_by": "idd-diagnose",
  "files": [
    {
      "filename": "1.docx",
      "url": "https://github.com/user-attachments/files/27209809/1.docx",
      "sha256": "2ae0236747...",
      "size_bytes": 16363
    }
  ]
}
```

下載失敗的條目改為:

```json
{ "filename": "...", "url": "...", "error": "download_failed" }
```

`fetched_by` 來自 `IDD_CALLER` 環境變數,skill 應設這個變數作為 audit 標記:

```bash
IDD_CALLER=idd-diagnose bash $CLAUDE_PLUGIN_ROOT/scripts/process-attachments.sh download 21
```

## Parsing(by Claude, not by script)

Script 只下載 + 寫 manifest,**parse 不是 script 的工作**。Skill 在 download 完後用適當工具讀內容:

| 副檔名 | 工具(MCP-first) |
|--------|-----------------|
| `.docx` | `che-word-mcp` MCP tool;fallback `pandoc -f docx -t markdown` |
| `.pdf` | `che-pdf-mcp` MCP tool;fallback `pdftotext` |
| `.png` / `.jpg` / `.jpeg` / `.gif` / `.webp` | `Read` tool(Claude 多模態直讀) |
| `.xlsx` / `.csv` | `excel-to-json` skill / `che-duckdb-mcp` |
| `.txt` / `.md` | `Read` tool |

**MCP / cli 都沒有** → 警告「無 parser,attachment 已下載但未 parse,請手動處理」,但 skill 仍繼續執行(parse 失敗不該 abort 整個 diagnose flow)。

## Reference convention(idd-* comments)

當 idd-* skill 在 GitHub comment 引用 attachment 內容,**必須**用 repo 內相對 path,不要重複 paste 全文:

```markdown
依摘要(`.claude/.idd/attachments/issue-21/1.docx`)結論段「機器人所展現的肢體語言因未完全符合人類的真實感而造成負荷」...
```

**禁止**:
- 直接貼 attachment URL 作來源(URL 可能 expire / private 看不到)
- 只憑記憶引用內容不標 attachment path
- 把 attachment 內容大段 paste 進 comment(comment 應 link 不應重述)

## .gitignore guidance

`.claude/.idd/attachments/` 含 binary,**預設 commit 進 repo**(因為 attachment 是 issue 審計軌跡的一部分)。

若 attachment 含敏感資料(受試者個資 / 未發表資料 / 私人文件),使用者可在 `.gitignore` 加:

```
# 不上傳 attachment 內容到遠端,但保留 manifest
.claude/.idd/attachments/**
!.claude/.idd/attachments/**/_manifest.json
```

只 ignore 二進位內容,保留 manifest(讓協作者知道有 attachment、URL 是什麼,需要時自行 fetch)。

## Iron rules

- **下載 = mandatory for upstream**: idd-diagnose / idd-issue 偵測到 attachment URL 必須 call `download`,不可「我覺得不重要就跳過」
- **Reference by path, never by URL**: comment / report 引用 attachment 用 repo 相對 path
- **Failure must be visible**: script `download` 失敗會把 `error` 條目寫進 manifest;skill 必須把警告 surface 給使用者,禁止靜默
- **Downstream never auto-repairs upstream**: 下游 `check` 回 exit 1 → 警告 + 引導回上游,不 silent fallback 到自己 download
- **Storage location is fixed**: `.claude/.idd/attachments/issue-{NNN}/`,skill 不允許各自選位置
- **Script is source of truth**: 機械工作(curl / jq / sha256)由 helper script 處理,SKILL.md 不得 inline 重新實作

## Related rules

- `references/config-protocol.md` — config walk-up search(`.claude/.idd/local.json` 是新主路徑)
- `rules/spectra-bridge.md` — bridge bookmark 在 `.claude/.idd/state/bridge.json`
- `rules/tagging-collaborators.md` — @mention 驗證(與 attachment processing 並行)
