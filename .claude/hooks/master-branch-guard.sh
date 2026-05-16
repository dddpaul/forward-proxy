#!/bin/bash
# master-branch-guard.sh — Block file edits on master branch (except .claude/, design/, .gitignore)
# Trigger: Edit|Write (all)
# Action: deny JSON (PreToolUse)
# Input: tool_input JSON on stdin

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)
if [ "$branch" != "master" ]; then exit 0; fi

path=$(jq -r '.tool_input.file_path // empty')
case "$path" in */.claude/*|.claude/*) exit 0;; esac
case "$path" in */design/*|design/*) exit 0;; esac
if [ "$(basename "$path")" = ".gitignore" ]; then exit 0; fi

echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"BLOCKED: no active task branch. Create a backlog task and `git checkout -b task-<id>-<desc> master` first."}}'
