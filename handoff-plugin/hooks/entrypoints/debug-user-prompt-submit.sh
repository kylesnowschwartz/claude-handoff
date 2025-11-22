#!/usr/bin/env bash
# Debug version with logging

set -euo pipefail

# Log to a debug file
DEBUG_LOG="/tmp/handoff-debug.log"
echo "=== $(date) UserPromptSubmit hook triggered ===" >>"$DEBUG_LOG"

# Read and log input
input=$(cat)
echo "INPUT: $input" >>"$DEBUG_LOG"

prompt=$(echo "$input" | jq -r '.prompt // ""')
echo "PROMPT: $prompt" >>"$DEBUG_LOG"

session_id=$(echo "$input" | jq -r '.session_id')
echo "SESSION: $session_id" >>"$DEBUG_LOG"

# Always output something to verify hook runs
jq -n '{
  hookSpecificOutput: {
    hookEventName: "UserPromptSubmit",
    additionalContext: "DEBUG: Hook executed successfully"
  }
}'

echo "=== Hook completed ===" >>"$DEBUG_LOG"
exit 0
