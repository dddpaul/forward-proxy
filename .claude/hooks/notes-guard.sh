#!/bin/bash
# notes-guard.sh — Block --notes (destructive overwrite) on backlog task edit
# Trigger: Bash(backlog task edit *)
# Action: deny JSON (PreToolUse)
# Input: tool_input JSON on stdin

cmd=$(jq -r '.tool_input.command')

if echo "$cmd" | grep -qE ' --notes([= ]|$)' &&
   ! echo "$cmd" | grep -qE ' --append-notes'; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: --notes overwrites the Notes section and destroys commit hashes. Use --append-notes instead."}}'
fi
