#!/bin/bash
# Ralph Wiggum - Long-running AI agent loop
# Usage: ./ralph.sh [--tool claude|opencode] [--model model_id] [--effort low|medium|high|xhigh|max]
#                    [--timeout minutes] [--on-error stop|continue|retry] [--retry-count N]
#                    [--log-file path] [--prompt-file path] [--tasks ids]
#                    [--devcontainer] [--help] [--version] [max_iterations]

set -uo pipefail

RALPH_VERSION="0.5.0"

# Print usage information and available options
show_help() {
  cat <<'HELPEOF'
Usage: ralph.sh [OPTIONS] [max_iterations]

Options:
  --tool <claude|opencode>     AI tool to use (default: claude)
  --model <model_id>           Model ID for claude tool (default: claude-opus-4-7)
  --effort <low|medium|high|xhigh|max>  Effort level for claude tool (default: max)
  --timeout <minutes>          Per-iteration timeout in minutes (default: 15)
  --on-error <stop|continue|retry>  Error handling strategy (default: stop)
  --retry-count <N>            Number of retries for --on-error=retry (default: 2)
  --log-file <path>            Log file for errors
  --prompt-file <path>         File to load prompt template from
  --tasks <ids>                Comma-separated numeric task IDs to run (e.g. 62,64,65)
                               Mutually exclusive with --prompt-file
  --devcontainer               Run inside a devcontainer
  --help                       Show this help message and exit
  --version                    Show version and exit
HELPEOF
}

# Parse arguments
TOOL="claude"
MODEL="claude-opus-4-7"  # Default model for claude tool
EFFORT="max"  # Default effort level for claude tool (low|medium|high|xhigh|max)
TIMEOUT=15  # Per-iteration timeout in minutes
MAX_ITERATIONS=10
USE_DEVCONTAINER=false
ON_ERROR="stop"  # stop | continue | retry
RETRY_COUNT=2  # Number of retries for --on-error=retry
LOG_FILE=""  # Optional log file for errors
PROMPT_FILE=""  # Optional file to load prompt template from
TASKS_RAW=""  # Optional comma-separated task IDs whitelist

# Parse command-line arguments into global configuration variables
parse_args() {
  while [[ $# -gt 0 ]]; do
    case $1 in
      --tool)
        TOOL="$2"
        shift 2
        ;;
      --tool=*)
        TOOL="${1#*=}"
        shift
        ;;
      --model)
        MODEL="$2"
        shift 2
        ;;
      --model=*)
        MODEL="${1#*=}"
        shift
        ;;
      --effort)
        EFFORT="$2"
        shift 2
        ;;
      --effort=*)
        EFFORT="${1#*=}"
        shift
        ;;
      --timeout)
        TIMEOUT="$2"
        shift 2
        ;;
      --timeout=*)
        TIMEOUT="${1#*=}"
        shift
        ;;
      --devcontainer)
        USE_DEVCONTAINER=true
        shift
        ;;
      --on-error)
        ON_ERROR="$2"
        shift 2
        ;;
      --on-error=*)
        ON_ERROR="${1#*=}"
        shift
        ;;
      --retry-count)
        RETRY_COUNT="$2"
        shift 2
        ;;
      --retry-count=*)
        RETRY_COUNT="${1#*=}"
        shift
        ;;
      --log-file)
        LOG_FILE="$2"
        shift 2
        ;;
      --log-file=*)
        LOG_FILE="${1#*=}"
        shift
        ;;
      --prompt-file)
        PROMPT_FILE="$2"
        shift 2
        ;;
      --prompt-file=*)
        PROMPT_FILE="${1#*=}"
        shift
        ;;
      --tasks)
        TASKS_RAW="$2"
        shift 2
        ;;
      --tasks=*)
        TASKS_RAW="${1#*=}"
        shift
        ;;
      --help)
        show_help
        exit 0
        ;;
      --version)
        echo "ralph.sh $RALPH_VERSION"
        exit 0
        ;;
      --*)
        echo "Error: Unknown flag '$1'. Use --help for usage."
        exit 1
        ;;
      *)
        if [[ "$1" =~ ^[0-9]+$ ]]; then
          MAX_ITERATIONS="$1"
        else
          echo "Error: Unexpected argument '$1'. Use --help for usage."
          exit 1
        fi
        shift
        ;;
    esac
  done
}

# Validate parsed arguments and exit on invalid values
validate_args() {
  if [[ "$TOOL" != "claude" && "$TOOL" != "opencode" ]]; then
    echo "Error: Invalid tool '$TOOL'. Must be 'claude' or 'opencode'."
    exit 1
  fi

  if ! [[ "$TIMEOUT" =~ ^[0-9]*\.?[0-9]+$ ]] || [[ -z "${TIMEOUT//[0.]}" ]]; then
    echo "Error: Timeout must be a positive number of minutes."
    exit 1
  fi

  if [[ "$EFFORT" != "low" && "$EFFORT" != "medium" && "$EFFORT" != "high" && "$EFFORT" != "xhigh" && "$EFFORT" != "max" ]]; then
    echo "Error: Invalid effort level '$EFFORT'. Must be 'low', 'medium', 'high', 'xhigh', or 'max'."
    exit 1
  fi

  if [[ "$ON_ERROR" != "stop" && "$ON_ERROR" != "continue" && "$ON_ERROR" != "retry" ]]; then
    echo "Error: Invalid on-error strategy '$ON_ERROR'. Must be 'stop', 'continue', or 'retry'."
    exit 1
  fi

  if [[ ! "$RETRY_COUNT" =~ ^[0-9]+$ ]] || [[ "$RETRY_COUNT" -lt 0 ]]; then
    echo "Error: Retry count must be a non-negative integer."
    exit 1
  fi

  if [[ -n "$PROMPT_FILE" ]] && [[ ! -r "$PROMPT_FILE" ]]; then
    echo "Error: Prompt file '$PROMPT_FILE' does not exist or is not readable."
    exit 1
  fi

  if [[ -n "$TASKS_RAW" ]]; then
    if ! [[ "$TASKS_RAW" =~ ^[0-9]+(,[0-9]+)*$ ]]; then
      echo "Error: --tasks must be comma-separated numeric IDs (e.g. 62,64,65). Got: '$TASKS_RAW'"
      exit 1
    fi
    if [[ -n "$PROMPT_FILE" ]]; then
      echo "Error: --tasks and --prompt-file are mutually exclusive"
      exit 1
    fi
  fi
}

TASK_WHITELIST=()

if [[ "${RALPH_SOURCE_ONLY:-}" != "1" ]]; then
  parse_args "$@"
  validate_args
fi

# Build whitelist array from TASKS_RAW
if [[ -n "$TASKS_RAW" ]]; then
  IFS=',' read -ra TASK_WHITELIST <<< "$TASKS_RAW"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

# --- Inlined from lib/status.sh ---

# Escape special characters in a string for safe JSON embedding
_status_json_escape() {
  local s="$1"
  s="${s//\\/\\\\}"
  s="${s//\"/\\\"}"
  s="${s//$'\n'/\\n}"
  s="${s//$'\r'/\\r}"
  s="${s//$'\t'/\\t}"
  printf '%s' "$s"
}

# Convert a newline-delimited string into a JSON array of strings
_status_json_array() {
  local items="$1"
  if [[ -z "$items" ]]; then
    printf '[]'
    return
  fi
  local first=true
  printf '['
  while IFS= read -r item; do
    [[ -z "$item" ]] && continue
    if [[ "$first" == true ]]; then
      first=false
    else
      printf ','
    fi
    printf '"%s"' "$(_status_json_escape "$item")"
  done <<< "$items"
  printf ']'
}

# Convert newline-delimited raw JSON values into a JSON array (no quoting)
_status_json_raw_array() {
  local items="$1"
  if [[ -z "$items" ]]; then
    printf '[]'
    return
  fi
  local first=true
  printf '['
  while IFS= read -r item; do
    [[ -z "$item" ]] && continue
    if [[ "$first" == true ]]; then
      first=false
    else
      printf ','
    fi
    printf '%s' "$item"
  done <<< "$items"
  printf ']'
}


# --- Inlined from lib/summary.sh ---

# Format seconds into a human-readable duration string (e.g. "1h 2m 3s")
format_duration() {
  local seconds="$1"
  local hours=$((seconds / 3600))
  local minutes=$(( (seconds % 3600) / 60 ))
  local secs=$((seconds % 60))

  if [[ $hours -gt 0 ]]; then
    printf "%dh %dm %ds" "$hours" "$minutes" "$secs"
  elif [[ $minutes -gt 0 ]]; then
    printf "%dm %ds" "$minutes" "$secs"
  else
    printf "%ds" "$secs"
  fi
}

# Print the end-of-run summary with stats and per-iteration durations
print_summary() {
  local tasks_completed="$1"
  local wall_time="$2"
  local iterations_used="$3"
  local max_iterations="$4"
  local exit_reason="$5"
  local tasks_remaining="$6"
  local failed_iterations="$7"
  shift 7
  local iter_durations=("$@")

  echo ""
  echo "==============================="
  echo "  Ralph Run Summary"
  echo "==============================="
  echo "Exit reason:        $exit_reason"
  echo "Tasks completed:    $tasks_completed"
  echo "Tasks remaining:    $tasks_remaining"
  echo "Iterations used:    $iterations_used of $max_iterations"
  echo "Failed iterations:  $failed_iterations"
  echo "Total wall time:    $(format_duration "$wall_time")"

  if [[ ${#iter_durations[@]} -gt 0 ]]; then
    echo ""
    echo "Per-iteration durations:"
    for idx in "${!iter_durations[@]}"; do
      echo "  Iteration $((idx + 1)): $(format_duration "${iter_durations[$idx]}")"
    done
  fi
  echo "==============================="
}

# Check if heartbeat file was modified within last 15 seconds
_is_heartbeat_fresh() {
  local hb_file="$1"
  [[ -f "$hb_file" ]] || return 1
  local _mtime _now
  _mtime=$(stat -f %m "$hb_file" 2>/dev/null || stat -c %Y "$hb_file" 2>/dev/null)
  _now=$(date +%s)
  [[ $((_now - _mtime)) -lt 15 ]]
}

# Count the number of backlog tasks still in "To Do" status
count_remaining_tasks() {
  if [[ ${#TASK_WHITELIST[@]} -gt 0 ]]; then
    local count=0
    for _id in "${TASK_WHITELIST[@]}"; do
      local _task_out
      _task_out=$(backlog task "$_id" --plain 2>/dev/null)
      if echo "$_task_out" | grep -q "Status:.*To Do"; then
        count=$((count + 1))
      fi
    done
    echo "$count"
  else
    local output
    output=$(backlog task list -s "To Do" --plain 2>/dev/null)
    if echo "$output" | grep -q "No tasks found"; then
      echo "0"
    else
      echo "$output" | grep -c "TASK-" || echo "0"
    fi
  fi
}

# Write current run state to the JSON status file
_update_status() {
  local state="$1"
  local completed_at="${2:-}"
  local exit_code="${3:-}"
  local elapsed=$(( $(date +%s) - RUN_START_TIME ))
  local remaining
  remaining=$(count_remaining_tasks)

  local tasks_done_json errors_json
  tasks_done_json=$(_status_json_array "$TASKS_DONE_IDS")
  errors_json=$(_status_json_raw_array "$STATUS_ERRORS")

  local current_task_json="null"
  [[ -n "$CURRENT_TASK" ]] && current_task_json="\"$(_status_json_escape "$CURRENT_TASK")\""

  local last_iter_json="null"
  [[ -n "$LAST_ITER_DURATION" ]] && last_iter_json="$LAST_ITER_DURATION"

  local completed_at_json="null"
  [[ -n "$completed_at" ]] && completed_at_json="\"$(_status_json_escape "$completed_at")\""

  local exit_code_json="null"
  [[ -n "$exit_code" ]] && exit_code_json="$exit_code"

  local iter_started_json="null"
  [[ -n "$ITERATION_STARTED_AT" ]] && iter_started_json="\"$(_status_json_escape "$ITERATION_STARTED_AT")\""

  cat > "$STATUS_FILE" <<STATUSEOF
{"pid":$$,"started_at":"$(_status_json_escape "$RUN_STARTED_AT")","state":"$(_status_json_escape "$state")","iteration":$CURRENT_ITERATION,"max_iterations":$MAX_ITERATIONS,"tool":"$(_status_json_escape "$TOOL")","tasks_done":$tasks_done_json,"tasks_remaining":${remaining:-0},"current_task":$current_task_json,"last_iteration_duration":$last_iter_json,"elapsed":$elapsed,"errors":$errors_json,"completed_at":$completed_at_json,"exit_code":$exit_code_json,"iteration_started_at":$iter_started_json,"timeout_sec":$TIMEOUT_SEC}
STATUSEOF
}

# Append a structured error entry to the STATUS_ERRORS accumulator
_append_status_error() {
  local message="$1"
  local error_at
  error_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local entry="{\"iteration\":$CURRENT_ITERATION,\"at\":\"$error_at\",\"message\":\"$(_status_json_escape "$message")\"}"
  if [[ -n "$STATUS_ERRORS" ]]; then
    STATUS_ERRORS="$STATUS_ERRORS"$'\n'"$entry"
  else
    STATUS_ERRORS="$entry"
  fi
}

# --- End inlined libraries ---

# Return early if sourced for testing
if [[ "${RALPH_SOURCE_ONLY:-}" == "1" ]]; then
  return 0 2>/dev/null || exit 0
fi

# Run tracking state
RUN_START_TIME=$(date +%s)
TASKS_COMPLETED=0
FAILED_ITERATIONS=0
ITER_DURATIONS=()
EXIT_REASON=""

# Status file tracking
STATUS_FILE="${RALPH_STATUS_FILE:-$SCRIPT_DIR/backlog/.ralph-status.json}"

# Double-run guard: refuse to start if another Ralph instance is alive
if [[ -f "$STATUS_FILE" ]]; then
  _existing_state=$(grep -o '"state":"[^"]*"' "$STATUS_FILE" | grep -o '"[^"]*"$' | tr -d '"')
  if [[ "$_existing_state" == "running" ]]; then
    _hb_file="${RALPH_HEARTBEAT_FILE:-$SCRIPT_DIR/backlog/.ralph-heartbeat}"
    if _is_heartbeat_fresh "$_hb_file"; then
      _existing_pid=$(grep -o '"pid":[0-9]*' "$STATUS_FILE" | grep -o '[0-9]*')
      echo "Error: Ralph is already running (PID ${_existing_pid:-unknown}). Use /ralph-status to check progress, or kill ${_existing_pid:-the process} to stop it."
      exit 1
    fi
    unset _hb_file
  fi
  unset _existing_state
fi

RUN_LOG="${RALPH_RUN_LOG:-$SCRIPT_DIR/backlog/.ralph-run.log}"
RUN_STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
TASKS_DONE_IDS=""
STATUS_ERRORS=""
CURRENT_TASK=""
LAST_ITER_DURATION=""
CURRENT_ITERATION=0
ITERATION_STARTED_AT=""

# List all task IDs currently in "Done" status, sorted
_get_done_task_ids() {
  backlog task list -s "Done" --plain 2>/dev/null | grep -o "TASK-[0-9]*" | sort || true
}

# Record a failed iteration, incrementing the failure counter and logging the reason
_record_iteration_failure() {
  local reason="$1"
  FAILED_ITERATIONS=$((FAILED_ITERATIONS + 1))
  _append_status_error "$reason"
  ITER_FAILED=true
}

# Display the run summary using current state
show_summary() {
  local reason="${1:-$EXIT_REASON}"
  local wall_time=$(( $(date +%s) - RUN_START_TIME ))
  local remaining
  remaining=$(count_remaining_tasks)
  print_summary "$TASKS_COMPLETED" "$wall_time" "${#ITER_DURATIONS[@]}" "$MAX_ITERATIONS" "$reason" "$remaining" "$FAILED_ITERATIONS" "${ITER_DURATIONS[@]}"
}

# Update status file, print summary, and exit with the given code
cleanup_and_exit() {
  local code="$1"
  local final_state="completed"
  [[ "$code" -ne 0 ]] && final_state="failed"
  _update_status "$final_state" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$code"
  show_summary
  exit "$code"
}

_ralph_cleanup_files=()
HEARTBEAT_FILE="${RALPH_HEARTBEAT_FILE:-$SCRIPT_DIR/backlog/.ralph-heartbeat}"
HB_PID=""
# Clean up heartbeat process and temporary files on exit
_ralph_cleanup() {
  if [[ -n "$HB_PID" ]]; then
    kill -- -"$HB_PID" 2>/dev/null || kill "$HB_PID" 2>/dev/null
  fi
  rm -f "$HEARTBEAT_FILE" "${_ralph_cleanup_files[@]}"
}
trap '_ralph_cleanup' EXIT
# Handle INT/TERM signals: kill children, update status, and exit
_ralph_interrupt() {
  EXIT_REASON="interrupted"
  _kill_children
  _update_status "failed" "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "130"
  show_summary "interrupted"
  exit 130
}

# Terminate all child processes except the log tee and heartbeat
_kill_children() {
  for pid in $(pgrep -P $$ 2>/dev/null); do
    [[ "$pid" == "${RUN_LOG_TEE_PID:-}" || "$pid" == "${HB_PID:-}" ]] && continue
    local pgid
    pgid=$(ps -o pgid= -p "$pid" 2>/dev/null | tr -d ' ')
    if [[ -n "$pgid" && "$pgid" != "$$" ]]; then
      kill -TERM -- -"$pgid" 2>/dev/null || true
    else
      kill -TERM "$pid" 2>/dev/null || true
    fi
  done
}
trap '_ralph_interrupt' INT TERM

# Verify backlog CLI is available
if ! command -v backlog &> /dev/null; then
  echo "Error: 'backlog' CLI not found. Install from https://github.com/MrLesk/Backlog.md"
  exit 1
fi

# Start devcontainer if requested
if [[ "$USE_DEVCONTAINER" == true ]]; then
  if ! command -v devcontainer &> /dev/null; then
    echo "Error: 'devcontainer' CLI not found. Install with: npm install -g @devcontainers/cli"
    exit 1
  fi
  echo "Starting devcontainer..."
  devcontainer up --workspace-folder "$SCRIPT_DIR"
  echo "Devcontainer is ready."
fi

# Log an error message to stderr and optionally to the log file
log_error() {
  local message="$1"
  local timestamp
  timestamp=$(date '+%Y-%m-%d %H:%M:%S')
  
  if [[ -n "$LOG_FILE" ]]; then
    echo "[$timestamp] ERROR: $message" >> "$LOG_FILE"
  fi
  echo "[$timestamp] ERROR: $message" >&2
}

# Handle a failed iteration based on the configured on-error strategy
handle_error() {
  local exit_code="$1"
  local iteration="$2"
  local retry_attempt="$3"

  log_error "Iteration $iteration failed with exit code $exit_code (tool: $TOOL, retry: $retry_attempt)"

  case "$ON_ERROR" in
    stop)
      echo "ERROR: AI tool failed with exit code $exit_code. Stopping."
      EXIT_REASON="error"
      _record_iteration_failure "Iteration $iteration failed with exit code $exit_code"
      LAST_ITER_DURATION=$(( $(date +%s) - ITER_START ))
      ITER_DURATIONS+=("$LAST_ITER_DURATION")
      cleanup_and_exit "$exit_code"
      ;;
    continue)
      echo "WARNING: AI tool failed with exit code $exit_code. Continuing to next iteration..."
      _record_iteration_failure "Iteration $iteration failed with exit code $exit_code"
      return 1
      ;;
    retry)
      if [[ $retry_attempt -lt $RETRY_COUNT ]]; then
        echo "WARNING: AI tool failed with exit code $exit_code. Retrying (attempt $((retry_attempt + 1)) of $RETRY_COUNT)..."
        return 2
      else
        echo "ERROR: AI tool failed after $RETRY_COUNT retries. Stopping."
        EXIT_REASON="error"
        _record_iteration_failure "Iteration $iteration failed with exit code $exit_code"
        LAST_ITER_DURATION=$(( $(date +%s) - ITER_START ))
        ITER_DURATIONS+=("$LAST_ITER_DURATION")
        cleanup_and_exit "$exit_code"
      fi
      ;;
  esac
}

# Validate --tasks whitelist: each task must exist and be in To Do status
if [[ ${#TASK_WHITELIST[@]} -gt 0 ]]; then
  for _wl_id in "${TASK_WHITELIST[@]}"; do
    _wl_out=$(backlog task "$_wl_id" --plain 2>/dev/null)
    if [[ -z "$_wl_out" ]] || echo "$_wl_out" | grep -q "not found"; then
      echo "ERROR: TASK-$_wl_id not found in backlog"
      exit 1
    fi
    _wl_status=$(echo "$_wl_out" | grep -o "Status:.*" | sed 's/Status:[[:space:]]*//' | sed 's/^[^[:alpha:]]*//')
    if [[ "$_wl_status" != *"To Do"* ]]; then
      echo "ERROR: TASK-$_wl_id is not To Do (status: $_wl_status)"
      exit 1
    fi
  done
  _wl_labels=$(printf ", TASK-%s" "${TASK_WHITELIST[@]}")
  echo "Restricted to: ${_wl_labels:2} (${#TASK_WHITELIST[@]} tasks)"
fi

MODEL_INFO=""
if [[ "$TOOL" == "claude" ]]; then
  MODEL_INFO=" ($MODEL, effort: $EFFORT)"
fi

CONFIG_INFO="on-error: $ON_ERROR"
[[ "$ON_ERROR" == "retry" ]] && CONFIG_INFO="$CONFIG_INFO (retries: $RETRY_COUNT)"
[[ -n "$LOG_FILE" ]] && CONFIG_INFO="$CONFIG_INFO, log: $LOG_FILE"

# Set up run logging
mkdir -p "$SCRIPT_DIR/backlog"
: > "$RUN_LOG"
exec > >(tee -a "$RUN_LOG") 2>&1
RUN_LOG_TEE_PID=$!

# Start heartbeat: touch file every 5s, exit when parent dies
_ralph_pid=$$
( trap 'exit 0' TERM; while kill -0 "$_ralph_pid" 2>/dev/null; do touch "$HEARTBEAT_FILE"; sleep 5 & wait $!; done ) </dev/null >/dev/null 2>&1 &
HB_PID=$!

# Compute timeout in seconds (used by _update_status and the iteration timeout command)
if [[ "$TIMEOUT" == *.* ]]; then
  _t_int="${TIMEOUT%%.*}"
  _t_frac="${TIMEOUT#*.}"
  _t_int_sec=$(( ${_t_int:-0} * 60 ))
  while [[ ${#_t_frac} -lt 3 ]]; do _t_frac="${_t_frac}0"; done
  _t_frac="${_t_frac:0:3}"
  TIMEOUT_SEC=$(( _t_int_sec + 10#$_t_frac * 60 / 1000 ))
else
  TIMEOUT_SEC=$(( TIMEOUT * 60 ))
fi

_update_status "running"

DEVCONTAINER_LABEL=""; [[ "$USE_DEVCONTAINER" == true ]] && DEVCONTAINER_LABEL=" (devcontainer)"
echo "Starting Ralph - Tool: $TOOL$MODEL_INFO - Max iterations: $MAX_ITERATIONS - Timeout: ${TIMEOUT}m${DEVCONTAINER_LABEL}"
echo "Config: $CONFIG_INFO"

for i in $(seq 1 "$MAX_ITERATIONS"); do
  # Determine next task: whitelist mode vs default mode
  WHITELIST_TASK_ID=""
  if [[ ${#TASK_WHITELIST[@]} -gt 0 ]]; then
    for _wl_id in "${TASK_WHITELIST[@]}"; do
      _wl_out=$(backlog task "$_wl_id" --plain 2>/dev/null)
      if echo "$_wl_out" | grep -q "Status:.*To Do"; then
        WHITELIST_TASK_ID="$_wl_id"
        break
      fi
    done
    if [[ -z "$WHITELIST_TASK_ID" ]]; then
      EXIT_REASON="all specified tasks done"
      cleanup_and_exit 0
    fi
    CURRENT_TASK="TASK-$WHITELIST_TASK_ID"
    REMAINING=$(count_remaining_tasks)
  else
    TODO_OUTPUT=$(backlog task list -s "To Do" --plain 2>/dev/null)
    if echo "$TODO_OUTPUT" | grep -q "No tasks found"; then
      EXIT_REASON="all tasks done"
      cleanup_and_exit 0
    fi
    CURRENT_TASK=$(echo "$TODO_OUTPUT" | grep -o "TASK-[0-9]*" | head -1)
    REMAINING=$(echo "$TODO_OUTPUT" | grep -c "TASK-" || echo "0")
  fi

  ITER_START=$(date +%s)
  CURRENT_ITERATION=$i
  ITERATION_STARTED_AT=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  DONE_BEFORE=$(_get_done_task_ids)
  _update_status "running"

  echo ""
  echo "==============================================================="
  echo "  Ralph Iteration $i of $MAX_ITERATIONS ($TOOL) - $REMAINING tasks remaining"
  echo "==============================================================="

  # Run the selected tool, saving output to temp file
  OUTFILE=$(mktemp)
  _ralph_cleanup_files+=("$OUTFILE")

  # Build prompt with autonomous mode prefix
  MODE_PREFIX="MODE: autonomous (Ralph loop iteration $i of $MAX_ITERATIONS)"

  # Build the exec prefix for devcontainer mode
  EXEC_PREFIX=()
  if [[ "$USE_DEVCONTAINER" == true ]]; then
    EXEC_PREFIX=(devcontainer exec --workspace-folder "$SCRIPT_DIR")
  fi

  # Build prompt: whitelist-targeted, file-loaded, or default
  if [[ -n "$WHITELIST_TASK_ID" ]]; then
    PROMPT_BODY="Execute TASK-$WHITELIST_TASK_ID using the full Task Lifecycle from CLAUDE.md. Do NOT pick any other task. If TASK-$WHITELIST_TASK_ID is already Done, reply with <promise>COMPLETE</promise>.
Your response MUST end with the ## Task Summary block. This is not optional."
  elif [[ -n "$PROMPT_FILE" ]]; then
    PROMPT_BODY=$(<"$PROMPT_FILE")
  else
    PROMPT_BODY="Pick the next To Do task and execute the full Task Lifecycle from CLAUDE.md.
Your response MUST end with the ## Task Summary block. This is not optional."
  fi
  PROMPT="$MODE_PREFIX

$PROMPT_BODY"

  # Retry loop for --on-error=retry
  retry_attempt=0
  while true; do
    export RALPH_AUTONOMOUS=1
    if [[ "$TOOL" == "opencode" ]]; then
      timeout "$TIMEOUT_SEC" ${EXEC_PREFIX[@]:+"${EXEC_PREFIX[@]}"} opencode run "$PROMPT" 2>&1 | tee "$OUTFILE"
      EXIT_CODE=${PIPESTATUS[0]}
    else
      timeout "$TIMEOUT_SEC" ${EXEC_PREFIX[@]:+"${EXEC_PREFIX[@]}"} claude --model "$MODEL" --effort "$EFFORT" --dangerously-skip-permissions --print <<< "$PROMPT" 2>&1 | tee "$OUTFILE"
      EXIT_CODE=${PIPESTATUS[0]}
    fi
    unset RALPH_AUTONOMOUS

    # Check if iteration timed out (exit code 124 = timeout)
    ITER_FAILED=false
    if [[ $EXIT_CODE -eq 124 ]]; then
      echo ""
      echo "WARNING: Iteration $i timed out after ${TIMEOUT}m ($(format_duration $(($(date +%s) - ITER_START)))). Continuing to next iteration..."
      _record_iteration_failure "Iteration $i timed out after ${TIMEOUT}m"
      sleep 2
      break
    fi

    # Check for errors (non-zero exit code)
    if [[ $EXIT_CODE -ne 0 ]]; then
      handle_error "$EXIT_CODE" "$i" "$retry_attempt"
      handler_result=$?

      if [[ $handler_result -eq 1 ]]; then
        break
      elif [[ $handler_result -eq 2 ]]; then
        # retry strategy - increment counter and retry
        retry_attempt=$((retry_attempt + 1))
        sleep 2
        continue
      fi
    fi

    # Success - break out of retry loop
    break
  done

  # Verify agent produced exactly one Task Summary block
  if ! grep -q '<promise>COMPLETE</promise>' "$OUTFILE"; then
    SUMMARY_COUNT=$(grep -c '^## Task Summary$' "$OUTFILE" || true)
    if [[ "$SUMMARY_COUNT" -ne 1 ]]; then
      echo "WARNING: Iteration $i produced $SUMMARY_COUNT '## Task Summary' blocks (expected 1). This may indicate the agent processed multiple tasks or none." >&2
    fi
  fi

  ITER_ELAPSED=$(( $(date +%s) - ITER_START ))
  ITER_DURATIONS+=("$ITER_ELAPSED")
  LAST_ITER_DURATION="$ITER_ELAPSED"
  CURRENT_TASK=$(backlog task list -s 'In Progress' --plain 2>/dev/null | grep -o 'TASK-[0-9]*' | head -1)

  # Track tasks that transitioned to Done during this iteration
  DONE_AFTER=$(_get_done_task_ids)
  if [[ -n "$DONE_AFTER" ]]; then
    NEW_DONE=""
    if [[ -n "$DONE_BEFORE" ]]; then
      NEW_DONE=$(comm -13 <(echo "$DONE_BEFORE") <(echo "$DONE_AFTER"))
    else
      NEW_DONE="$DONE_AFTER"
    fi
    if [[ -n "$NEW_DONE" ]]; then
      if [[ -n "$TASKS_DONE_IDS" ]]; then
        TASKS_DONE_IDS="$TASKS_DONE_IDS"$'\n'"$NEW_DONE"
      else
        TASKS_DONE_IDS="$NEW_DONE"
      fi
    fi
  fi

  if [[ "$ITER_FAILED" == true ]]; then
    _update_status "running"
    echo "Iteration $i failed ($(format_duration $ITER_ELAPSED)). Continuing..."
    sleep 2
    continue
  fi

  TASKS_COMPLETED=$((TASKS_COMPLETED + 1))
  _update_status "running"

  # Check for completion signal
  if grep -q "<promise>COMPLETE</promise>" "$OUTFILE"; then
    EXIT_REASON="all tasks done"
    cleanup_and_exit 0
  fi

  echo "Iteration $i complete ($(format_duration $ITER_ELAPSED)). Continuing..."
  sleep 2
done

if [[ "$TASKS_COMPLETED" -gt 0 && "$FAILED_ITERATIONS" -eq 0 ]]; then
  EXIT_REASON="max iterations reached ($TASKS_COMPLETED task(s) completed)"
  cleanup_and_exit 0
else
  EXIT_REASON="max iterations reached"
  cleanup_and_exit 1
fi
