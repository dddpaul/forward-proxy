#!/bin/bash
# commit-prefix-guard.sh — Enforce task-<id> prefix on commit messages
# Trigger: Bash(git commit *)
# Action: deny JSON (PreToolUse)
# Input: tool_input JSON on stdin

cmd=$(jq -r '.tool_input.command')

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)
case "$branch" in task-*) ;; *) exit 0;; esac

task_id=$(echo "$branch" | grep -oE '^task-[0-9]+' | sed 's/task-//')

msg=$(echo "$cmd" | sed -n 's/.*-m[[:space:]]*"\(.*\)".*/\1/p')
if [ -z "$msg" ]; then
  msg=$(echo "$cmd" | sed -n "s/.*-m[[:space:]]*'\(.*\)'.*/\1/p")
fi
if [ -z "$msg" ]; then
  msg=$(echo "$cmd" | sed -n '/cat <</{n;s/^[[:space:]]*//;p;q;}')
fi

if echo "$msg" | grep -qiE '^Merge branch'; then exit 0; fi

if ! echo "$msg" | grep -qE "^task-${task_id}: "; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: commit message on task-%s branch must start with `task-%s: `."}}' "$task_id" "$task_id"
fi
