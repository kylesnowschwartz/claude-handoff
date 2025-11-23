#!/usr/bin/env bash
# session-start.sh - SessionStart hook for claude-handoff plugin
#
# PURPOSE:
#   Generates and injects intelligent handoff context after /compact
#   by using claude --resume to analyze the previous session.
#
# HOOK EVENT: SessionStart (matcher: "compact")
#   - Fires when sessions start after compact operations
#   - Receives: session_id, transcript_path, cwd, source ("compact")
#
# BEHAVIOR:
#   - Checks for pending handoff state saved by pre-compact.sh
#   - Uses claude --resume to generate handoff prompt from previous session
#   - Injects generated handoff as additionalContext for new session
#   - Cleans up state file after successful generation
#
# TESTING:
#   1. Debug logging is enabled (see LOG_FILE below)
#   2. Run /compact after some work
#   3. Check logs:
#        tail -f /tmp/handoff-sessionstart.log
#   4. Verify handoff appears in new session
#   5. Check state file cleaned up on success:
#        ls -la .git/handoff-pending/  # should not exist after successful handoff
#   6. Check exit codes logged (should be 0 on success)
#   7. Verify timeout works: handoff should not hang >30s
#
# MANUAL TESTING WITH FAKE STATE:
#   # Create fake state
#   mkdir -p .git/handoff-pending
#   echo '{"previous_session":"SESSION_ID","trigger":"manual","cwd":"'$(pwd)'"}' > .git/handoff-pending/handoff-context.json
#
#   # Run hook (replace SESSION_ID with a real session from ~/.claude/projects/*/transcript.jsonl)
#   echo '{"cwd":"'$(pwd)'","source":"compact"}' | bash session-start.sh
#
#   # Check output should contain additionalContext with handoff
#   # Cleanup
#   rm -rf .git/handoff-pending
#
# EXIT BEHAVIOR:
#   - Returns JSON with additionalContext if handoff generated
#   - Exits silently (exit 0, no output) if no handoff or generation fails
#
set -euo pipefail

# Debug logging - fresh log each run
LOG_FILE="/tmp/handoff-sessionstart.log"
exec 2>"$LOG_FILE"
set -x
echo "[$(date -Iseconds)] SessionStart hook triggered" >>"$LOG_FILE"

# Read hook input
input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd // "."')
source=$(echo "$input" | jq -r '.source // "unknown"')

echo "[$(date -Iseconds)] Received input: cwd=$cwd source=$source" >>"$LOG_FILE"

# Change to project directory
cd "$cwd" || exit 0

# Check for pending handoff state
state_file=".git/handoff-pending/handoff-context.json"

if [[ ! -f "$state_file" ]]; then
  echo "[$(date -Iseconds)] No state file found, exiting" >>"$LOG_FILE"
  exit 0
fi

echo "[$(date -Iseconds)] Found state file: $state_file" >>"$LOG_FILE"

# Read handoff context
previous_session=$(cat "$state_file" | jq -r '.previous_session // ""')
trigger=$(cat "$state_file" | jq -r '.trigger // ""')

echo "[$(date -Iseconds)] State: session=$previous_session trigger=$trigger" >>"$LOG_FILE"

if [[ -z "$previous_session" ]]; then
  echo "[$(date -Iseconds)] No previous_session, cleaning up" >>"$LOG_FILE"
  rm -f "$state_file"
  exit 0
fi

# Generate handoff using claude --resume
echo "[$(date -Iseconds)] Invoking claude --resume $previous_session" >>"$LOG_FILE"

# Capture exit code and add timeout, redirect stderr to log
handoff_exit_code=0
handoff=$(timeout 90s claude --resume "$previous_session" --print --model haiku \
  "The previous session was compacted (trigger: $trigger).
Pay special attention to context that may have been lost in compaction.

Analyze this conversation and create a focused handoff prompt for the next session.

Include:
1. **What we were working on** - Current task/goal
2. **Key decisions made** - Important choices or approaches agreed upon
3. **Relevant files** - Paths to files read/modified (paths only, no content)
4. **Next steps** - What should happen next
5. **Blockers** - Any errors, issues, or open questions

Format as concise markdown. Be specific and actionable. Omit meta-discussion about creating this handoff.

Ensure the user knows this was a result of the Claude-Handoff plugin system.
" 2>>"$LOG_FILE") || handoff_exit_code=$?

echo "[$(date -Iseconds)] Claude exit code: $handoff_exit_code" >>"$LOG_FILE"
echo "[$(date -Iseconds)] Handoff length: ${#handoff} chars" >>"$LOG_FILE"

# If handoff generation failed or is empty, exit silently WITHOUT cleanup
# This keeps the state file for retry on next session start
if [[ $handoff_exit_code -ne 0 ]] || [[ -z "$handoff" ]] || [[ "$handoff" == *"No conversation found"* ]]; then
  echo "[$(date -Iseconds)] Handoff generation failed (exit: $handoff_exit_code), keeping state for retry" >>"$LOG_FILE"
  exit 0
fi

# Only cleanup state file on SUCCESS
rm -f "$state_file"
rmdir .git/handoff-pending 2>/dev/null || true

echo "[$(date -Iseconds)] Handoff generated successfully, returning additionalContext" >>"$LOG_FILE"

# Return JSON with additionalContext
jq -n --arg context "$handoff" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $context
  }
}'

exit 0
