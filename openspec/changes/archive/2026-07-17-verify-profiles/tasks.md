## 1. Tests first (RED)

- [x] 1.1 (Req: Composable verification profiles selectable at the skill layer; Req: Non-git input sources join input-source resolution; Req: File-input freshness gate equivalent to the diff-freshness gate) New drift-guard suite plugins/issue-driven-dev/scripts/tests/verify-profiles/test.sh: reference file exists with three built-in profile sections + prose lens keys; SKILL documents `--profile` / `--file` / `--dir` + mutual exclusion + fail-loud unknown profile + code-default-unchanged sentence + file SHA-256 freshness gate; config-protocol documents `verify_profiles` + built-in-wins collision rule. Run: RED.

## 2. Prose (GREEN)

- [x] 2.1 (Design D1 — profile 是四元組，reference 檔是 single source; D3 — file-based freshness gate) New references/verify-profiles.md: profile 四元組表、prose/academic lens 文本（以 #258 Provenance 即興映射為底稿）、DA focus、file SHA-256 freshness 契約、custom-profile schema。
- [x] 2.2 (Design D2 — 輸入源抽象掛在既有 Step 0.5 resolution algorithm; D5 — 兩個 backend 同時支援) skills/idd-verify/SKILL.md: 參數表加 `--profile` / `--file` / `--dir`；Step 0.5 input resolution 加 file 分支 + 互斥 abort；freshness gate mirror；backend dispatch 段記 profile → customLenses / manual prompt 的組裝點。
- [x] 2.3 (Design D4 — repo-local 自訂 profile：內建名不可 shadow) references/config-protocol.md: 新 `### verify_profiles field`（schema、collision 內建勝 + warning、invalid entry 忽略 + warning、unknown --profile fail-loud 對照）。
- [x] 2.4 Verify: suite GREEN; full plugin sweep 0 fail; spectra validate clean.
