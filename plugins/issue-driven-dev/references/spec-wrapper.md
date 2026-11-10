# Spec wrapper：每一張實作的 issue 都留下規格（#480）

`idd-implement`（Simple tier）與 `idd-plan`（Plan tier）照這份契約，把 issue 的實作包進一個 Spectra change；Spectra tier 由 `idd-all` 照同一份契約收尾。規格依據是 capability `spec-on-every-issue`。機械判定都在 `scripts/spec-change.py`，這裡只寫誰在什麼時候呼叫它、看到什麼結果要做什麼。

其他 skill 不直接依賴 Spectra 的 skill 介面；要改 IDD 用 Spectra 的方式，只改這份契約與兩個 wrapper。

下面寫的 `openspec/` 指 Spectra 的規格目錄：`.spectra.yaml` 的 `spec_dir`，沒有這一欄就是 `openspec`（Spectra 3 新初始化的 repo 是 `docs/spectra`）。`spec-change.py` 照同一條規則解析。

## 1. Preflight（建立任何東西之前）

```bash
CAN_WRITE=no
case "$(gh repo view "$GITHUB_REPO" --json viewerPermission -q .viewerPermission 2>/dev/null)" in
  WRITE|MAINTAIN|ADMIN) CAN_WRITE=yes ;;
esac
PF=$(python3 "${CLAUDE_PLUGIN_ROOT}/scripts/spec-change.py" preflight --cwd "$CWD" --can-write "$CAN_WRITE"); PF_RC=$?
printf '%s\n' "$PF" | jq -r '"→ spec preflight: \(.status) \(.message)"'
```

| `status` | 做什麼 |
|---|---|
| `ready` | 往下走第 2 步 |
| `third-party` | 照沒有這份契約時的方式實作，不建立 `openspec/`；Implementation Complete 寫 `**Spec**: third-party clone` |
| `linked-worktree` | 停下，不建立任何 artifact、不 commit。Spectra 在 linked worktree 裡會寫進主工作樹。改在主工作樹或獨立 clone 裡跑 |
| `install-spectra` | 停下，把 `message` 原樣轉給使用者 |
| `init-openspec` | 停下，把 `message` 原樣轉給使用者 |
| `error`、或 exit 64 | 停下，回報 |

`--can-write` 讀不到權限時是 `no`：寧可少寫一次規格，不在別人的 repo 建 `openspec/`。

## 2. 決定這張 issue 留下什麼

先問一句：這張 issue 的改動，會不會讓 repo 裡任何 skill、script、hook、rule 的行為不同（印出或貼出的文字、結束碼、寫入或刪除的檔案、對外的呼叫、問的問題、跑的步驟）？

- 會 → 寫規格（第 3 步起）。
- 不會 → 宣告 `**Spec**: no behaviour change`，跳到第 6 步。只有這四種，不得依性質相似類推第五種：
  - (a) 只改沒有東西會執行的文件或敘述。skill、rule、會被 skill 執行的 reference 不算文件。
  - (b) 一次性的分析：沒有呼叫者的 script 與它的報告。
  - (c) 只改測試或 CI 設定。
  - (d) 重構之後，上面列的每一種行為都沒有變。

宣告會被 `idd-verify` 的 Regression lens 審：範圍內有任何行為改動就是 HIGH。拿不準就寫規格。

## 3. Propose

change 名稱是 `idd-<N>-<slug>`（slug 取 issue 標題，小寫英數與連字號）。先看這個 change 是不是已經存在（`idd-plan` 會先建好）：

```bash
spectra list --json | jq -r '.changes[]?.name' ; spectra list --parked --json | jq -r '.parked[]?.name'
```

已經有 `idd-<N>-` 開頭的 change → 不再 propose，直接第 4 步。

沒有 → 呼叫 `Skill(skill="spectra-propose", args="<change 名稱>：<需求，取自 Diagnosis 的 Strategy>。輕量形式：不做 discuss、不寫 design。")`，並在 args 寫明：

- 輕量形式（Simple tier 與 unattended 的 Plan tier）：不做 discuss、不寫 design，只寫短的 proposal、spec delta 與 tasks。
- 每一條新增或改到的 requirement 至少一個 `##### Example:`，標題在該 capability 裡唯一；寫不出檢查的，寫一行 `No executable check:` 加理由。
- tasks 裡每個 Example 對應一個測試 task，測試檔要帶標記 `spec-example: <capability> / <Example title>`。

無人值守的 run（照 [`unattended-contract.md`](unattended-contract.md) 判定）不能停在 Spectra 的問題上。先判定一次：

```bash
. "${CLAUDE_PLUGIN_ROOT}/scripts/lib/unattended-state.sh"
is_unattended "$CWD" && echo "→ spec wrapper: unattended" || echo "→ spec wrapper: attended"
```

印 `unattended` 時，`spectra-propose` 與第 4 步 `spectra-apply` 的 args 末尾都附上這一段（attended 時不附，Spectra 的問題照常問人）：

> UNATTENDED MODE — called by an IDD spec wrapper (references/spec-wrapper.md).
> - Skip every AskUserQuestion checkpoint. Where you would ask, make the most conservative choice and write it into the artifact as a line starting with `ASSUMPTION:`.
> - Do not ask whether to park or apply. Do not ask whether to continue a parked change.
> - Every commit references the issue as `(#<N>)` at the end of the subject.

`spectra-propose` 結束時可能會 park 這個 change；第 4 步由 wrapper 自己 unpark，不交給 `spectra-apply` 去問。

## 4. Apply

```bash
CHANGE="<change 名稱>"
if spectra list --parked --json | jq -e --arg n "$CHANGE" 'any(.parked[]?; .name == $n)' >/dev/null; then
  spectra unpark "$CHANGE" && echo "→ unparked $CHANGE"
fi
```

然後 `Skill(skill="spectra-apply", args="<change 名稱>")`（無人值守時附上第 3 步那一段）。每個 Example 的測試先寫、先看到它失敗，再寫程式。進度記在 change 的 `tasks.md`，不另外建 TaskList。

## 5. Close-out（verify 之前，順序固定）

1. `Skill(skill="spectra-verify", args="<change 名稱>")`。回報 critical 就修；修不了就停下回報，不封存。
2. `spectra archive <change 名稱> -y`。
3. 確認封存落在要 commit 的這個工作樹：`openspec/changes/<change 名稱>/` 不見了，`openspec/changes/archive/` 底下多了 `<日期>-<change 名稱>`。沒有就停下。
4. commit：`chore: archive <change 名稱> (#N)`。
5. 連結檢查：

```bash
DEFAULT_BRANCH=$(gh repo view "$GITHUB_REPO" --json defaultBranchRef -q .defaultBranchRef.name)
git -C "$CWD" fetch -q origin "$DEFAULT_BRANCH"
SPEC_BASE=$(git -C "$CWD" merge-base HEAD "origin/$DEFAULT_BRANCH")
python3 "${CLAUDE_PLUGIN_ROOT}/scripts/spec-change.py" links --base "$SPEC_BASE" --cwd "$CWD"
```

`git merge-base HEAD "origin/$DEFAULT_BRANCH"` 在 PR path 是分岔點；在 direct-commit path 是 run 還沒推的 commit 之前那一個。`missing` 就補測試或標記再跑一次；`error` 停下回報。

6. 確認宣告與 HEAD 一致：把第 6 步要貼的 `**Spec**:` 行寫進一個暫存檔，跑 `python3 "${CLAUDE_PLUGIN_ROOT}/scripts/spec-change.py" archived --file <暫存檔> --cwd "$CWD" --ref HEAD`，要 `pass`。

## 6. Implementation Complete 的宣告

留言第一行是標記，之後有剛好一行 `**Spec**:`：

```markdown
<!-- idd:comment type=implementation-complete -->
## Implementation Complete

**Spec**: change idd-42-fix-timeout
```

三種寫法：`**Spec**: change <名稱>[, <名稱>…]`（這張 issue 所有封存了的 change，依時間順序）、`**Spec**: no behaviour change`、`**Spec**: third-party clone`。這一行不放在 code block 裡。

## 7. verify 之後的修正

修正新增或修改了 requirement → 再建一個 change `idd-<N>-fix<k>`（k 是 verify 的輪數），走第 3 步的輕量形式，在下一輪 verify 之前照第 5 步封存，新的 Implementation Complete 列出這張 issue 的所有 change。requirement 與 Example 已經有、只是測試沒寫對 → 只補測試。Blocking 的修正要留下一條寫出該性質的 requirement、Example，以及一個在修正前的 commit 上會失敗的測試。
