#!/usr/bin/env bash
set -euo pipefail

# Debug SessionEnd hook

DEBUG_LOG="/tmp/handoff-sessionend-debug.log"
echo "=== $(date) SessionEnd hook triggered ===" >>"$DEBUG_LOG"

input=$(cat)
echo "INPUT: $input" >>"$DEBUG_LOG"

reason=$(echo "$input" | jq -r '.reason // ""')
echo "REASON: $reason" >>"$DEBUG_LOG"

transcript_path=$(echo "$input" | jq -r '.transcript_path // ""')
echo "TRANSCRIPT: $transcript_path" >>"$DEBUG_LOG"

# Output success
jq -n '{
  continue: true,
  suppressOutput: false,
  stopReason: ""
}'

echo "=== Hook completed ===" >>"$DEBUG_LOG"
exit 0
