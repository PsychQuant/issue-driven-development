#!/usr/bin/env bash
# session-start-commit-rule.sh — SessionStart injection of the commit
# issue-reference iron rules (PsychQuant/issue-driven-development#214) and,
# since #424, the one-line living-issue write-back rule.
# HARD CEILING: output must stay ≤ 5 lines — every user pays this context tax
# each session. Content is STATIC; token alignment with the canonical rules
# file is enforced by scripts/tests/session-start-commit-rule/test.sh (D4).
# NO matcher on the SessionStart entry — DELIBERATE (#214 R1 finding 8):
# firing on startup/resume/clear/compact means the rule survives context
# compaction; the tax is ≤5 lines per SessionStart EVENT, not per session.
cat <<'RULES'
── IDD 紀律（完整版在 issue-driven-dev plugin 的 rules/commit-issue-reference.md 與 rules/issue-write-back.md）──
1. Issue ref 放 subject 尾端 (#N) 或 body 用 Refs #N
2. close / fix / resolve（含 fix: 前綴）絕不鄰接 #數字 — GitHub parser 會即刻 auto-close
3. 引用反例用 code fence + literal N；close 一律走 /idd-close
4. 討論 issue 時就地寫回、不先問：問題改正文段落、診斷改 Diagnosis（/idd-edit --correct），新資訊與決定新增 comment；只改自己的內容，別人的用 errata／correction
RULES
