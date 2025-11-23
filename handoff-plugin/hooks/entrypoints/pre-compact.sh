#!/usr/bin/env bash
# pre-compact.sh - PreCompact hook for claude-handoff plugin
#
# PURPOSE:
#   Saves session state when user runs `/compact handoff:<instructions>`
#   so that SessionStart can generate goal-focused handoff context.
#
# HOOK EVENT: PreCompact
#   - Fires BEFORE compact operations (manual /compact)
#   - Only activates when manual_instructions match "handoff:..." format
#   - Receives: session_id, transcript_path, trigger, manual_instructions
#
# TESTING:
#   1. Enable debug logging in hooks/lib/logging.sh (set LOGGING_ENABLED=true)
#   2. Start a conversation, add substantial context (multiple tool uses)
#   3. Run: /compact handoff:now implement feature X
#   4. Check logs:
#        tail -f /tmp/handoff-precompact.log
#   5. Verify state file created:
#        cat .git/handoff-pending/handoff-context.json
#   6. Expected state file structure:
#        {
#          "previous_session": "abc123...",
#          "trigger": "manual",
#          "cwd": "/path/to/project",
#          "user_instructions": "now implement feature X",
#          "type": "compact"
#        }
#
# NEGATIVE TEST (should not trigger):
#   /compact  # No state file created
#   /compact some other instructions  # No state file created
#
# MANUAL TESTING WITH FAKE INPUT:
#   echo '{"session_id":"test-123","trigger":"manual","cwd":"'$(pwd)'","manual_instructions":"handoff:test goal"}' | bash pre-compact.sh
#   cat .git/handoff-pending/handoff-context.json
#   rm -rf .git/handoff-pending  # cleanup
#
# EXIT BEHAVIOR:
#   - Always exits 0 (never blocks compact)
#   - Returns JSON: {"continue": true, "suppressOutput": true}
#
set -euo pipefail

# Load logging module
source "${BASH_SOURCE%/*}/../lib/logging.sh"
init_logging "precompact"

# Fail-open: always succeed, never block compact
trap 'jq -n "{continue:true,suppressOutput:true}" && exit 0' ERR

# Parse hook input from stdin
input=$(cat)
session_id=$(echo "$input" | jq -r '.session_id')
trigger=$(echo "$input" | jq -r '.trigger // "auto"')
cwd=$(echo "$input" | jq -r '.cwd // "."')
manual_instructions=$(echo "$input" | jq -r '.manual_instructions // ""')

log "Received input: session_id=$session_id trigger=$trigger cwd=$cwd manual_instructions=$manual_instructions"

# Only proceed if manual instructions match "handoff:..." format
if [[ ! "$manual_instructions" =~ ^handoff: ]]; then
  log "Manual instructions don't match 'handoff:' pattern, skipping handoff"
  jq -n '{continue: true, suppressOutput: true}'
  exit 0
fi

# Extract user instructions after "handoff:" prefix
user_instructions="${manual_instructions#handoff:}"
# Trim leading whitespace
user_instructions="${user_instructions#"${user_instructions%%[![:space:]]*}"}"

log "Handoff triggered with user instructions: $user_instructions"

# Change to project directory
cd "$cwd" || exit 0

# Create state directory and save session metadata for SessionStart
mkdir -p .git/handoff-pending

# Write state file that SessionStart will read
jq -n \
  --arg session "$session_id" \
  --arg trigger "$trigger" \
  --arg cwd "$cwd" \
  --arg instructions "$user_instructions" \
  '{
    previous_session: $session,
    trigger: $trigger,
    cwd: $cwd,
    user_instructions: $instructions,
    type: "compact"
  }' \
  >.git/handoff-pending/handoff-context.json

log "State saved to .git/handoff-pending/handoff-context.json"

# Success - allow compact to proceed
jq -n '{continue: true, suppressOutput: true}'
exit 0
