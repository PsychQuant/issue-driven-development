**GitHub-side tracker**: #525

## Problem

#525 的 verify 第 1 輪（2026-11-13，審查 `6ed8dec..6cdae05`）有三項 MEDIUM 與四項 LOW 要在這條 branch 上修：

- 判斷「這一句有沒有把開著的 change 列成訊號」的函式與規格的描述對不上。規格寫在分號切子句，函式只在「分號加空白」切；規格用 do not count 描述允許的說明，函式不認得這個說法。
- 同一個子句裡另有一句講別件事的「不算」，就把列入蓋掉；中文只認三種說法，而且後面要接英文的 change；規格卻寫「不論用什麼語言」。
- `idd-comment` 自己的文字沒有跟上：鐵律「偵測到從 spectra-discuss 進來必須印 resume prompt」沒有綁在 Step 0.7 的三個訊號上，Step 0.7 的說明也沒有寫對話脈絡不算。
- 「規則那一行在表的下方」沒有檢查位置；偵測表不提對話脈絡只比對英文；Step 7 的檢查只確認標題裡有一個字串。

## Root Cause

第一個 change 把判斷規則寫成一句話加七個例子，函式照例子寫，兩邊在例子沒有涵蓋的地方各說各話。改規則時只改了規則檔，沒有回頭讀執行的模型實際照著做的 skill 文字。

## Proposed Solution

- 規格把判斷規則寫成四個步驟（在哪裡切子句、哪些字算提到、哪些字算「不算」的說明而且要寫在提到之後、怎樣算列入），並寫明規則以外的說法不會被認出來。Example 的表擴成 29 列，每一個切點、每一個字、每一個步驟至少有一列會因為它而改變答案。
- suite 直接從主規格讀這張表，逐列執行規則。表與檢查不會對不上。
- `skills/idd-comment/SKILL.md`：Step 0.7 區塊下方加一行（對話脈絡不是訊號，要帶 `--resume-spectra`）；鐵律改成以 Step 0.7 的判定為準，並寫明不從對話推斷。偵測的區塊不改。
- requirement「Conversation context does not turn the spectra bridge on」加上這兩處，Example 改名為「what the rule and the skill say about conversation context」並加兩列；規則那一行的檢查改成只看表的下方，偵測表的檢查也比對「對話脈絡」。
- Step 7 的檢查改成比對「僅當 `SPECTRA_BRIDGE_ACTIVE=1`」。

## Non-Goals

- Step 7.1 把主題直接寫進 bridge 檔的 JSON、沒有跳脫（第 1 輪第 8 列）：既有的行為，補記在 #524。
- 用規則以外的說法（例如別的語言、別的同義詞）把那個訊號寫回去：規則認不出來，規格已寫明這個限制。
- ASSUMPTION: 不升版號，CHANGELOG 改寫既有的 Unreleased 條目。

## Success Criteria

- 第 1 輪的函式配上新的表，有列會失敗；新的函式 29 列全過。
- 每一個切點、每一個字、每一個步驟各改壞一次，至少有一列失敗。
- `idd-comment` 的兩個檢查在改 skill 之前失敗；把規則那一行搬到表的上方時，檢查失敗。
- `spectra-bridge-detect` 在 bash 5 與 macOS 內建的 bash 3.2 都通過，`LC_ALL=C` 之下也通過；run-all-tests 的全部 suite 與 spectra-archive-post-ic 通過；連結檢查回 ok。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `spectra-bridge-detection`: 判斷規則寫成明確的步驟；對話脈絡不是訊號這件事也寫進 `idd-comment`。

## Impact

- Affected specs: spectra-bridge-detection（MODIFIED requirement「Open Spectra changes do not turn the spectra bridge on」與「Conversation context does not turn the spectra bridge on」）
- Affected code:
  - Modified: plugins/issue-driven-dev/skills/idd-comment/SKILL.md
  - Modified: plugins/issue-driven-dev/scripts/tests/spectra-bridge-detect/test.sh
  - Modified: plugins/issue-driven-dev/CHANGELOG.md
