#!/usr/bin/env bash
# session-start-commit-rule.sh — SessionStart injection of the commit
# issue-reference iron rules (PsychQuant/issue-driven-development#214).
# HARD CEILING: output must stay ≤ 5 lines — every user pays this context tax
# each session. Content is STATIC; token alignment with the canonical rules
# file is enforced by scripts/tests/session-start-commit-rule/test.sh (D4).
cat <<'RULES'
── IDD commit 紀律（完整版：rules/commit-issue-reference.md）──
1. Issue ref 放 subject 尾端 (#N) 或 body 用 Refs #N
2. close / fix / resolve（含 fix: 前綴）絕不鄰接 #數字 — GitHub parser 會即刻 auto-close
3. 引用反例用 code fence + literal N；close 一律走 /idd-close
RULES
