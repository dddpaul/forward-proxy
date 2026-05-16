#!/bin/bash
# naming-guard.sh — Block non-ASCII characters in task titles and branch names
# Trigger: Bash(backlog task create *), Bash(git checkout -b *)
# Action: deny JSON (PreToolUse)
# Input: tool_input JSON on stdin

cmd=$(jq -r '.tool_input.command')

target=""

# Try extracting task title (double-quoted, then single-quoted)
title=$(echo "$cmd" | sed -n 's/^backlog task create[[:space:]]*"\([^"]*\)".*/\1/p')
if [ -z "$title" ]; then
  title=$(echo "$cmd" | sed -n "s/^backlog task create[[:space:]]*'\([^']*\)'.*/\1/p")
fi

if [ -n "$title" ]; then
  target="$title"
else
  # Try extracting branch name
  target=$(echo "$cmd" | sed -n 's/^git checkout -b[[:space:]]*\([^[:space:]]*\).*/\1/p')
fi

if [ -n "$target" ] && printf '%s' "$target" | LC_ALL=C grep -q '[^[:print:][:space:]]'; then
  echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: title/branch must be ASCII English (filenames are derived from titles). Put translations in -d or --ac."}}'
fi
