#!/usr/bin/env bash
# session-start.sh - SessionStart hook for claude-handoff plugin
#
# PURPOSE:
#   Generates goal-focused handoff context after `/compact handoff:<goal>`
#   by using claude --resume to extract relevant context from previous session.
#
# HOOK EVENT: SessionStart (matcher: "compact")
#   - Fires when sessions start after compact operations
#   - Receives: session_id, transcript_path, cwd, source ("compact")
#
# BEHAVIOR:
#   - Checks for pending handoff state saved by pre-compact.sh
#   - Uses user's goal to focus context extraction from previous session
#   - Uses claude --resume to generate goal-focused handoff prompt
#   - Injects generated handoff as systemMessage for new session
#   - Cleans up state file after successful generation
#
# TESTING:
#   1. Enable debug logging in hooks/lib/logging.sh (set LOGGING_ENABLED=true)
#   2. Run: /compact handoff:implement feature X
#   3. New session starts automatically
#   4. Check logs:
#        tail -f /tmp/handoff-sessionstart.log
#   5. Verify goal-focused handoff appears as system message in new session
#   6. Check state file cleaned up on success:
#        ls -la .git/handoff-pending/  # should not exist after successful handoff
#   7. Verify handoff focused on user's goal, not full session summary
#
# MANUAL TESTING WITH FAKE STATE:
#   # Create fake state
#   mkdir -p .git/handoff-pending
#   echo '{"previous_session":"SESSION_ID","trigger":"manual","cwd":"'$(pwd)'","user_instructions":"implement auth feature"}' > .git/handoff-pending/handoff-context.json
#
#   # Run hook (replace SESSION_ID with a real session from ~/.claude/projects/*/transcript.jsonl)
#   echo '{"cwd":"'$(pwd)'","source":"compact"}' | bash session-start.sh
#
#   # Check output should contain systemMessage with goal-focused handoff
#   # Cleanup
#   rm -rf .git/handoff-pending
#
# EXIT BEHAVIOR:
#   - Returns JSON with additionalContext if handoff generated
#   - Exits silently (exit 0, no output) if no handoff or generation fails
#
set -euo pipefail

# Load logging module
source "${BASH_SOURCE%/*}/../lib/logging.sh"
init_logging "sessionstart"

# Prevent recursion: if we're already generating a handoff, exit immediately
if [[ "${HANDOFF_IN_PROGRESS:-}" == "1" ]]; then
  log "Already in handoff generation, skipping to prevent recursion"
  exit 0
fi

# Read hook input
input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd // "."')
source=$(echo "$input" | jq -r '.source // "unknown"')

log "Received input: cwd=$cwd source=$source"

# Only proceed if this is a compact-triggered session start
if [[ "$source" != "compact" ]]; then
  log "Source is '$source', not 'compact'. Exiting."
  exit 0
fi

# Change to project directory
cd "$cwd" || exit 0

# Check for pending handoff state
state_file=".git/handoff-pending/handoff-context.json"

if [[ ! -f "$state_file" ]]; then
  log "No state file found, exiting"
  exit 0
fi

log "Found state file: $state_file"

# Read handoff context
previous_session=$(cat "$state_file" | jq -r '.previous_session // ""')
trigger=$(cat "$state_file" | jq -r '.trigger // ""')
user_instructions=$(cat "$state_file" | jq -r '.user_instructions // ""')

log "State: session=$previous_session trigger=$trigger user_instructions=$user_instructions"

if [[ -z "$previous_session" ]]; then
  log "No previous_session, cleaning up"
  rm -f "$state_file"
  exit 0
fi

# Generate handoff using claude --resume
log "Invoking claude --resume $previous_session"

# Build handoff generation prompt with user instructions
handoff_prompt="The previous session was compacted (trigger: $trigger).

USER'S GOAL FOR THE NEW SESSION:
$user_instructions

Your task: Analyze the previous conversation and extract ONLY the context relevant to achieving the user's goal above.

Create a focused handoff prompt that includes:

1. **Context from previous session** - What we were working on that's relevant to the new goal
2. **Key decisions/patterns** - Approaches, conventions, or constraints already established
3. **Relevant files** - Paths to files that matter for the new goal (paths only)
4. **Current state** - Where things were left that affects the new work
5. **Blockers/dependencies** - Any issues or prerequisites the new session should know about

Be ruthlessly selective. Omit anything not relevant to: $user_instructions

Format as concise markdown. Start directly with \"## Handoff Context\" - no preamble about this being a handoff or mentioning the plugin."

# Capture exit code and add timeout, redirect stderr to log
# Set env var to prevent recursive hook invocation
handoff_exit_code=0
handoff=$(HANDOFF_IN_PROGRESS=1 claude --resume "$previous_session" --model haiku --print \
  "$handoff_prompt") || handoff_exit_code=$?

log "Claude exit code: $handoff_exit_code"
log "Handoff length: ${#handoff} chars"

# If handoff generation failed or is empty, exit silently WITHOUT cleanup
# This keeps the state file for retry on next session start
if [[ $handoff_exit_code -ne 0 ]] || [[ -z "$handoff" ]] || [[ "$handoff" == *"No conversation found"* ]]; then
  log "Handoff generation failed (exit: $handoff_exit_code), keeping state for retry"
  exit 0
fi

# Only cleanup state file on SUCCESS
rm -f "$state_file"
rmdir .git/handoff-pending 2>/dev/null || true

log "Handoff generated successfully, returning systemMessage"

# Return JSON with systemMessage to show in transcript
jq -n --arg context "$handoff" '{
  systemMessage: $context
}'

exit 0
