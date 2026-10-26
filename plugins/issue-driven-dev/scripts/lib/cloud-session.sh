#!/usr/bin/env bash
# cloud-session.sh — is this a Claude Code cloud session, and is a human attending it? (#416)
#
# Source it; it defines two functions and prints nothing:
#   idd_is_cloud_session     exit 0 iff CLAUDE_CODE_REMOTE is exactly "true"
#   idd_cloud_interaction    print "attended" iff CLAUDE_CODE_SESSION_ATTENDED is exactly "1", else "unattended"
#
# Exact literals, no normalisation: an unknown value means "not cloud" (the run then meets
# GitHub's own explanatory 403s) or "unattended" (fewer questions, the work still ships as a PR).
# Unattended is the safe side because attended sub-skill questions have no timeout
# (spec idd-pr-hitl-modes, "No silent timeout") — a cloud session nobody watches would wait forever.
# Never infer cloud execution from a GitHub API error. Contract: references/claude-code-remote-tools.md.

idd_is_cloud_session() {
  [ "${CLAUDE_CODE_REMOTE:-}" = "true" ]
}

idd_cloud_interaction() {
  if [ "${CLAUDE_CODE_SESSION_ATTENDED:-}" = "1" ]; then
    printf 'attended\n'
  else
    printf 'unattended\n'
  fi
}
