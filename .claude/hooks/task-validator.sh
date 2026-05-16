#!/bin/bash
# task-validator.sh — Validate backlog task structure after edit/create
# Trigger: Bash(backlog task edit *), Bash(backlog task create *)
# Action: PostToolUse JSON feedback via hookSpecificOutput.additionalContext
# Input: tool_input JSON on stdin

set -uo pipefail

# Read tool input from stdin (JSON)
INPUT=$(cat)

# Extract the command that was run
CMD=$(echo "$INPUT" | jq -r '.tool_input.command // empty')
# Extract task ID from command
TASK_ID=$(echo "$CMD" | grep -oE '\btask (edit|create)[[:space:]]+([0-9]+)' | grep -oE '[0-9]+$')
if [[ -z "$TASK_ID" ]]; then
  exit 0
fi

# Find the task file
TASK_FILE=$(find backlog/tasks -maxdepth 1 -name "task-${TASK_ID} -*" -o -name "task-${TASK_ID}-*" 2>/dev/null | head -1)
if [[ -z "$TASK_FILE" ]] || [[ ! -f "$TASK_FILE" ]]; then
  exit 0
fi

# === Deterministic Checks ===
DET_ISSUES=()

# Read task file content
TASK_CONTENT=$(<"$TASK_FILE")

# 1. Description body is non-empty after stripping frontmatter and title heading
DESC_SECTION=$(echo "$TASK_CONTENT" | sed -n '/<!-- SECTION:description -->/,/<!-- SECTION:/p' | sed '1d;$d')
if [[ -z "$DESC_SECTION" ]]; then
  DESC_SECTION=$(echo "$TASK_CONTENT" | sed -n '/^## Description/,/^## /p' | sed '1d;$d' | sed '/^$/d')
fi
if [[ -z "$(echo "$DESC_SECTION" | sed '/^[[:space:]]*$/d')" ]]; then
  DET_ISSUES+=("Description body is empty")
fi

# 2. At least one acceptance criterion present
AC_LINES=$(echo "$TASK_CONTENT" | grep -E '^\s*- \[(x| )\]' || true)
AC_COUNT=$(echo "$AC_LINES" | grep -c '.' 2>/dev/null || echo "0")
if [[ "$AC_COUNT" -eq 0 ]]; then
  DET_ISSUES+=("No acceptance criteria defined")
fi

# 3. No empty AC line ('- [ ]' or '- [x]' with no content after checkbox)
if echo "$AC_LINES" | grep -qE '^\s*- \[(x| )\]\s*$'; then
  DET_ISSUES+=("Empty acceptance criterion line (checkbox with no text)")
fi

# 4. No identical AC strings after normalization
if [[ "$AC_COUNT" -gt 1 ]]; then
  # -E enables ERE so (x| ) is alternation, not literal
  NORMALIZED_ACS=$(echo "$AC_LINES" | sed -E 's/^[[:space:]]*- \[(x| )\][[:space:]]*//' | sed 's/^#[0-9]* //' | tr '[:upper:]' '[:lower:]' | sed 's/[[:space:]]\+/ /g' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
  UNIQUE_COUNT=$(echo "$NORMALIZED_ACS" | sort -u | grep -c '.' 2>/dev/null || echo "0")
  TOTAL_COUNT=$(echo "$NORMALIZED_ACS" | grep -c '.' 2>/dev/null || echo "0")
  if [[ "$UNIQUE_COUNT" -lt "$TOTAL_COUNT" ]]; then
    DET_ISSUES+=("Duplicate acceptance criteria detected")
  fi
fi

# 5. Status Done consistent with all AC checked (and vice versa)
STATUS=$(echo "$TASK_CONTENT" | grep -E '^status:' | head -1 | sed 's/^status:[[:space:]]*//')
if [[ -z "$STATUS" ]]; then
  STATUS=$(echo "$TASK_CONTENT" | grep -E '^Status:' | head -1 | sed 's/^Status:[[:space:]]*//' | sed 's/^[^[:alpha:]]*//')
fi
ALL_CHECKED=true
ANY_AC=false
while IFS= read -r line; do
  [[ -z "$line" ]] && continue
  ANY_AC=true
  if echo "$line" | grep -qE '^\s*- \[ \]'; then
    ALL_CHECKED=false
    break
  fi
done <<< "$AC_LINES"

if [[ "$ANY_AC" == true ]]; then
  if [[ "$STATUS" == *"Done"* ]] && [[ "$ALL_CHECKED" == false ]]; then
    DET_ISSUES+=("Status is Done but not all AC are checked")
  fi
  if [[ "$ALL_CHECKED" == true ]] && [[ "$STATUS" != *"Done"* ]] && [[ "$AC_COUNT" -gt 0 ]]; then
    DET_ISSUES+=("All AC are checked but status is not Done")
  fi
fi

# 6. Dependencies resolve to existing task IDs
DEPS=$(echo "$TASK_CONTENT" | grep -E '^dependencies:' | sed 's/^dependencies:[[:space:]]*//' | tr ',' '\n' | grep -oE '[0-9]+' || true)
for dep_id in $DEPS; do
  DEP_FILE=$(find backlog/tasks -maxdepth 1 -name "task-${dep_id} -*" -o -name "task-${dep_id}-*" 2>/dev/null | head -1)
  if [[ -z "$DEP_FILE" ]] || [[ ! -f "$DEP_FILE" ]]; then
    DET_ISSUES+=("Dependency TASK-${dep_id} not found in backlog/tasks/")
  fi
done

# 7. File-path references in backtick spans or markdown links exist
IN_FENCE=false
while IFS= read -r line; do
  if echo "$line" | grep -qE '^```'; then
    if [[ "$IN_FENCE" == true ]]; then
      IN_FENCE=false
    else
      IN_FENCE=true
    fi
    continue
  fi
  [[ "$IN_FENCE" == true ]] && continue

  # Extract backtick-quoted paths
  BACKTICK_PATHS=$(echo "$line" | grep -oE '`[^`]+`' | sed 's/^`//;s/`$//' || true)
  # Extract markdown link paths
  LINK_PATHS=$(echo "$line" | grep -oE '\]\([^)]+\)' | sed 's/^\](//' | sed 's/)$//' || true)

  PATHS_TO_CHECK=$(printf '%s\n%s\n' "$BACKTICK_PATHS" "$LINK_PATHS" | sed '/^[[:space:]]*$/d')
  while IFS= read -r path; do
    [[ -z "$path" ]] && continue
    # Skip URLs
    echo "$path" | grep -qE '^https?://|^www\.' && continue
    # Skip wildcards/globs
    echo "$path" | grep -qE '[*?]|\.\.\.' && continue
    # Skip non-path-like strings (must contain / or end with known extension)
    if ! echo "$path" | grep -qE '/|\.sh$|\.js$|\.ts$|\.py$|\.md$|\.json$|\.yaml$|\.yml$|\.toml$'; then
      continue
    fi
    # Check existence
    if [[ ! -e "$path" ]]; then
      DET_ISSUES+=("Referenced path '$path' does not exist")
    fi
  done <<< "$PATHS_TO_CHECK"
done <<< "$TASK_CONTENT"

# === Build deterministic check message (defer output for single JSON emission) ===
DET_TEXT=""
if [[ ${#DET_ISSUES[@]} -gt 0 ]]; then
  DET_TEXT="Task validator [det] issues for TASK-${TASK_ID}:"
  for issue in "${DET_ISSUES[@]}"; do
    DET_TEXT="${DET_TEXT}"$'\n'"  - ${issue}"
  done
fi

emit_context() {
  if [[ -n "$1" ]]; then
    jq -n --arg ctx "$1" '{"hookSpecificOutput":{"hookEventName":"PostToolUse","additionalContext":$ctx}}'
  fi
}

# === LLM Nudge ===
# Short-circuit if autonomous mode (zero output)
if [[ "${RALPH_AUTONOMOUS:-}" == "1" ]]; then
  exit 0
fi

# Substantive-edit predicate: check if description body or AC text changed
DIFF_OUTPUT=$(git diff HEAD -- "backlog/tasks/task-${TASK_ID}"* 2>/dev/null || true)
if [[ -z "$DIFF_OUTPUT" ]]; then
  if ! echo "$CMD" | grep -qE '^backlog task create\b'; then
    emit_context "$DET_TEXT"
    exit 0
  fi
fi

# Check if changes are substantive (affect description or AC lines)
SUBSTANTIVE=false
if echo "$CMD" | grep -qE '^backlog task create\b'; then
  SUBSTANTIVE=true
else
  # Find line range for description+AC sections in the task file
  DESC_START=$(grep -nE '<!-- SECTION:description -->|^## Description' "$TASK_FILE" | head -1 | cut -d: -f1)
  AC_END_LINE=$(grep -nE '<!-- AC:END -->|<!-- SECTION:dod -->|^## Definition of Done' "$TASK_FILE" | head -1 | cut -d: -f1)
  DESC_START=${DESC_START:-0}
  AC_END_LINE=${AC_END_LINE:-0}

  # Parse diff hunks to extract changed lines within desc/AC range
  SUBST_ADDED=""
  SUBST_REMOVED=""
  CUR_OLD=0
  CUR_NEW=0
  while IFS= read -r line; do
    if [[ "$line" =~ ^@@\ -([0-9]+)(,[0-9]+)?\ \+([0-9]+)(,[0-9]+)?\ @@ ]]; then
      CUR_OLD=${BASH_REMATCH[1]}
      CUR_NEW=${BASH_REMATCH[3]}
      continue
    fi
    [[ "$line" =~ ^(---|\+\+\+|diff) ]] && continue
    if [[ "$line" == +* ]]; then
      if [[ "$CUR_NEW" -ge "$DESC_START" ]] && [[ "$AC_END_LINE" -eq 0 || "$CUR_NEW" -le "$AC_END_LINE" ]]; then
        SUBST_ADDED="${SUBST_ADDED}${line}"$'\n'
      fi
      CUR_NEW=$((CUR_NEW + 1))
    elif [[ "$line" == -* ]]; then
      if [[ "$CUR_OLD" -ge "$DESC_START" ]] && [[ "$AC_END_LINE" -eq 0 || "$CUR_OLD" -le "$AC_END_LINE" ]]; then
        SUBST_REMOVED="${SUBST_REMOVED}${line}"$'\n'
      fi
      CUR_OLD=$((CUR_OLD + 1))
    else
      CUR_OLD=$((CUR_OLD + 1))
      CUR_NEW=$((CUR_NEW + 1))
    fi
  done <<< "$DIFF_OUTPUT"

  # Further filter markers and blanks from substantive candidates
  SUBST_ADDED=$(echo "$SUBST_ADDED" | grep -vE '^\+(<!-- |## |[[:space:]]*$)' || true)
  SUBST_REMOVED=$(echo "$SUBST_REMOVED" | grep -vE '^\-(<!-- |## |[[:space:]]*$)' || true)

  # Detect checkbox-only flips: if all remaining AC diffs have identical text
  CHECKBOX_ONLY=false
  if [[ -n "$SUBST_ADDED" ]] || [[ -n "$SUBST_REMOVED" ]]; then
    NON_AC_ADDED=$(echo "$SUBST_ADDED" | grep -vE '^\+- \[(x| )\] #[0-9]+' || true)
    NON_AC_REMOVED=$(echo "$SUBST_REMOVED" | grep -vE '^\-- \[(x| )\] #[0-9]+' || true)
    AC_ADDED=$(echo "$SUBST_ADDED" | grep -E '^\+- \[(x| )\] #[0-9]+' || true)
    AC_REMOVED=$(echo "$SUBST_REMOVED" | grep -E '^\-- \[(x| )\] #[0-9]+' || true)

    if [[ -z "$NON_AC_ADDED" ]] && [[ -z "$NON_AC_REMOVED" ]] && [[ -n "$AC_ADDED" ]] && [[ -n "$AC_REMOVED" ]]; then
      ADDED_TEXTS=$(echo "$AC_ADDED" | sed -E 's/^\+- \[(x| )\] //' | sort)
      REMOVED_TEXTS=$(echo "$AC_REMOVED" | sed -E 's/^-- \[(x| )\] //' | sort)
      if [[ "$ADDED_TEXTS" == "$REMOVED_TEXTS" ]]; then
        CHECKBOX_ONLY=true
      fi
    fi
  fi

  if [[ "$CHECKBOX_ONLY" == false ]] && { [[ -n "$SUBST_ADDED" ]] || [[ -n "$SUBST_REMOVED" ]]; }; then
    SUBSTANTIVE=true
  fi
fi

if [[ "$SUBSTANTIVE" == false ]]; then
  emit_context "$DET_TEXT"
  exit 0
fi

# Check if task body contains URLs (for reachability rubric item)
HAS_URLS=false
if echo "$TASK_CONTENT" | grep -qE 'https?://|www\.'; then
  HAS_URLS=true
fi

# Build rubric items
RUBRIC=""
ITEM_NUM=1

RUBRIC="${RUBRIC}${ITEM_NUM}. Logical contradictions between description and AC, or between AC items.\n"
ITEM_NUM=$((ITEM_NUM + 1))

RUBRIC="${RUBRIC}${ITEM_NUM}. Semantic AC duplication (same requirement stated differently).\n"
ITEM_NUM=$((ITEM_NUM + 1))

RUBRIC="${RUBRIC}${ITEM_NUM}. AC implementability (each AC is concrete, testable, and scoped to one thing).\n"
ITEM_NUM=$((ITEM_NUM + 1))

if [[ "$HAS_URLS" == true ]]; then
  RUBRIC="${RUBRIC}${ITEM_NUM}. Reference reachability — verify URLs are accessible. Check allowed hosts in .devcontainer/init-firewall.sh.\n"
  ITEM_NUM=$((ITEM_NUM + 1))
fi

RUBRIC="${RUBRIC}${ITEM_NUM}. Self-containment (task can be completed without unstated context).\n"

# Build rubric text and combine with det issues for single JSON emission
RUBRIC_TEXT=$(printf 'Task validator triggered for TASK-%s.\nFile: %s\n\nRead the task file and evaluate against this rubric:\n%b\nOutput format: "Validator [llm]: task-%s OK" if no issues, or "Validator [llm]: task-%s" followed by terse one-line issues. No remediation suggestions, no rewrites.' "$TASK_ID" "$TASK_FILE" "$RUBRIC" "$TASK_ID" "$TASK_ID")

# === Emit combined JSON output ===
COMBINED=""
if [[ -n "$DET_TEXT" ]] && [[ -n "$RUBRIC_TEXT" ]]; then
  COMBINED="${DET_TEXT}"$'\n\n'"${RUBRIC_TEXT}"
elif [[ -n "$DET_TEXT" ]]; then
  COMBINED="$DET_TEXT"
elif [[ -n "$RUBRIC_TEXT" ]]; then
  COMBINED="$RUBRIC_TEXT"
fi

emit_context "$COMBINED"
