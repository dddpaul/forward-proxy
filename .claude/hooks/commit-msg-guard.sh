#!/bin/bash
# commit-msg-guard.sh — Block forbidden trailers and headings in commits and PRs
# Trigger: Bash(git commit *), Bash(gh pr create *)
# Action: deny JSON (PreToolUse)
# Input: tool_input JSON on stdin

cmd=$(jq -r '.tool_input.command')

if echo "$cmd" | grep -qiE 'Co-Authored-By|Generated with Claude Code' ||
   echo "$cmd" | grep -qE '##[[:space:]]*Test [Pp]lan'; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: forbidden trailer/heading. Remove Co-Authored-By, Generated-with, and Test plan sections."}}'
fi
