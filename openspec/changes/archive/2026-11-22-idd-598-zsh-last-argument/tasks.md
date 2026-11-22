## 1. 測試先寫

- [x] 1.1 新增 `plugins/issue-driven-dev/scripts/tests/skill-arg-parsing/test.sh`，涵蓋三條 requirement「idd-all reads every argument in bash and zsh」「idd-all-chain reads every argument in bash and zsh」「idd-clarify reads every argument in bash and zsh」：從三份 SKILL.md 取出 `# >>> arg-parse` 與 `# <<< arg-parse` 之間的區塊（標記缺少或重複時套件失敗），用每個 Example 的參數在 bash 與 zsh 各跑一次，比對兩邊都得到 Example 的值。帶標記 `spec-example: idd-pr-hitl-modes / idd-all reads the last argument in both shells`、`spec-example: idd-all-chain / idd-all-chain reads the last argument in both shells`、`spec-example: idd-clarify / idd-clarify reads the last argument in both shells`。驗證：在原本的迴圈上加了標記之後，bash 通過、zsh 對最後一個參數的情境失敗。

## 2. Skills

- [x] 2.1 [after: 1.1] requirement「idd-all reads every argument in bash and zsh」：`skills/idd-all/SKILL.md` Step 0.2 改成標記之間的 shift 迴圈，每個旗標照原樣移植（衝突檢查、`--stop` 的取值規則）。驗證：套件裡 idd-all 的情境在 bash 與 zsh 都通過。
- [x] 2.2 [after: 1.1] requirement「idd-all-chain reads every argument in bash and zsh」：`skills/idd-all-chain/SKILL.md` Step 0.1 改成 shift 迴圈；最小的 root 不用從 0 起算的索引。驗證：idd-all-chain 的情境在兩個 shell 都通過。
- [x] 2.3 [after: 1.1] requirement「idd-clarify reads every argument in bash and zsh」：`skills/idd-clarify/SKILL.md` Step 1 改成 shift 迴圈。驗證：idd-clarify 的情境在兩個 shell 都通過。

## 3. 回歸

- [ ] 3.1 [after: 2.1, 2.2, 2.3] `run-all-tests.sh` 全過。
