#!/usr/bin/env bash
set -euo pipefail

# Fail-open: always succeed, never block /clear
trap 'jq -n "{continue:true,suppressOutput:false,stopReason:\"\"}" && exit 0' ERR

# Parse input
input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id')
cwd=$(echo "$input" | jq -r '.cwd // "."')

# Change to project directory
cd "$cwd" || exit 0

# Create state directory and store session metadata for SessionStart
mkdir -p .git/handoff-pending

jq -n \
  --arg session "$session_id" \
  --arg cwd "$cwd" \
  '{previous_session: $session, cwd: $cwd}' \
  >.git/handoff-pending/handoff-context.json

# Success
jq -n '{continue: true, suppressOutput: false, stopReason: ""}'
exit 0
