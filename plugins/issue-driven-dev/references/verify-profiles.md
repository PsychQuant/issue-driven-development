# Verification Profiles（#258, v2.97.0+）

本檔是 `idd-verify --profile` 的 **single source of truth**：每個 profile 是一個四元組 **(lens set, DA focus, 輸入源預設, freshness 機制)**。`idd-verify` SKILL.md 與兩個 ensemble backend（pai canonical `customLenses` / manual fan-out prompts）都從本檔取 lens 文本 — **引用、不內嵌複本**（反 typo-drift，同 reason-pattern registry 紀律）。drift-guard：`scripts/tests/verify-profiles/test.sh`。

## 為什麼存在

engine 層的 composability primitive 早已存在（pai-ensemble 接受 `profile: 'custom'` + `customLenses` + `daFocus` + `diffFile`），但 skill 層把 code lens 與 git 輸入源寫死。非 code deliverable 的驗證需求（學術 / 臨床 prose、信件、報告）只能臨場手動重映射 — 不可複現、不可稽核（#258）。本檔把那組已被實戰驗證的映射升格為 first-class 契約。

## 總表

| Profile | Lenses | 輸入源預設 | Freshness |
|---------|--------|-----------|-----------|
| `code`（預設） | requirements / logic / security / regression | git auto-detect（diff / `--pr` / `--commits` / `--branch`） | #228 FROZEN_SHA vs HEAD |
| `prose` | factual-accuracy-vs-source / requirements-format-compliance / pii-phi-leak / citation-support | `--file` / `--dir`（必填其一） | file SHA-256 snapshot |
| `academic` | 同 prose 四軸 | 同 prose | 同 prose |

DA（devil's advocate）在所有 profile 都存在 — 變的是 focus 文本，不是機制。

## Profile: code

**今日行為，逐 byte 不變**（backward-compat 鎖，spec scenario「default invocation is unchanged」）。lens 文本維持 idd-verify SKILL.md Step 2 / pai customLenses 既有四則（requirements / logic / security / regression），DA focus 維持既有 adversarial-refute 文本，輸入源走既有 Step 0.5 auto-detect 鏈，freshness 走 #228 git gate。本檔對 `code` **不**另立文本 — 避免雙 source。

## Profile: prose

輸入源：`--file <path>` 或 `--dir <path>`（必填其一；無 → abort，不 fallback git）。

| Lens key | Focus 文本（填入 `customLenses[].focus` / manual Agent prompt） |
|----------|------------------------------------------------------------|
| `factual-accuracy-vs-source` | whether every factual claim in the deliverable is supported by the cited or attached sources; hunt for fabricated facts, numbers, dates, names, or events not present in any source (hallucination), and for source statements that are misrepresented or overstated. |
| `requirements-format-compliance` | whether the deliverable satisfies the requirements of the ref'd issue(s) and the stated template / format / length / language conventions; flag missing required sections, violated formatting rules, and unaddressed requirements. |
| `pii-phi-leak` | personally identifiable information or protected health information that should not leave the document's trust boundary — names, identifiers, dates of birth, medical record details, contact information; flag any leak with its exact location. |
| `citation-support` | whether each citation / reference actually supports the claim it is attached to; hunt for citations that do not contain the claimed content, circular support, and claims that need a citation but have none. |

**DA focus**：adversarially refute the other reviewers' judgments: hunt for factual or compliance defects where they passed, false positives in their findings, and claims of source support that the document does not actually satisfy.

## Profile: academic

lens 四軸與 prose 相同（表同上）。差異在 **DA focus 改學術審稿人姿態**：

**DA focus**：act as a hostile peer reviewer defending the field's standards: attack the argument structure, methodology claims, and citation practices; refute the other reviewers' passes by finding weaknesses a journal reviewer would reject on — overclaiming, unsupported generalization, missing limitations, and citation padding.

## File-based freshness gate（#228 等價物）

git 模式的 gate 語意是「verdict 必須對應 verify 當下的 snapshot」（FROZEN_SHA vs HEAD）。file 模式等價物：

1. **Snapshot**：ensemble 啟動前對每個輸入檔算 SHA-256，記入 `FROZEN_HASHES`（含檔案清單；`--dir` 遞迴）
2. **Re-check**：aggregate / post master comment 前重算比對
3. **Mismatch（含檔案增刪）→ refuse**：不 post verdict，印 stale-snapshot 訊息 + 重跑指令

MUST gate，與 git 模式同級 — **不因輸入不在 git 而靜默豁免**（#258 Risks）。

## 自訂 profile（config `verify_profiles`）

schema 與 collision 規則的 canonical 定義在 [`config-protocol.md`](config-protocol.md)（`### verify_profiles field`）。摘要：

- 自訂名與內建碰撞 → **內建勝 + warning**（`code` 的 backward-compat 保證不可被 config 靜默改寫）
- schema 不合（缺 `lenses` / `da_focus` / `input` 非法）→ 該 entry 忽略 + warning（absent-safe）
- 未知 `--profile` 名（內建與 config 都查無）→ **abort + 可用 profile 清單**（fail-loud：`--profile` 是顯式意圖，typo 靜默跑錯 profile 比失敗更糟 — 同 `IDD_AGENT_MODEL` 判準）

## 輸入 bundle 格式（`diffFile` 載體重用）

file 模式下 ensemble 的 `diffFile` 參數裝**檔案內容 bundle**：單檔直接放；`--dir` 遞迴串接、以 `=== FILE: <relpath> ===` 行分隔。agents 用 file-read tool 讀取，與 diff 路徑同管道 — findings contract / master report 結構不變。
