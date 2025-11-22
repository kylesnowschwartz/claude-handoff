#!/usr/bin/env bash
set -euo pipefail

# SessionStart hook: Generate and inject handoff context after /clear

# Read hook input
input=$(cat)
cwd=$(echo "$input" | jq -r '.cwd // "."')

# Change to project directory
cd "$cwd" || exit 0

# Check for pending handoff state
state_file=".git/handoff-pending/handoff-context.json"

if [[ ! -f "$state_file" ]]; then
  # No handoff pending, exit silently
  exit 0
fi

# Read handoff context
previous_session=$(cat "$state_file" | jq -r '.previous_session // ""')

if [[ -z "$previous_session" ]]; then
  rm -f "$state_file"
  exit 0
fi

# Generate handoff by asking Claude to analyze the previous session
handoff=$(claude --resume "$previous_session" --print --model haiku \
  "Analyze this conversation and create a focused handoff prompt for the next session.

Include:
1. **What we were working on** - Current task/goal
2. **Key decisions made** - Important choices or approaches agreed upon
3. **Relevant files** - Paths to files read/modified (paths only, no content)
4. **Next steps** - What should happen next
5. **Blockers** - Any errors, issues, or open questions

Format as concise markdown. Be specific and actionable. Omit meta-discussion about creating this handoff." 2>&1)

# Clean up state file
rm -f "$state_file"
rmdir .git/handoff-pending 2>/dev/null || true

# If handoff generation failed or is empty, exit silently
if [[ -z "$handoff" ]] || [[ "$handoff" == *"No conversation found"* ]]; then
  exit 0
fi

# Return JSON with additionalContext
jq -n --arg draft "$handoff" '{
  hookSpecificOutput: {
    hookEventName: "SessionStart",
    additionalContext: $draft
  }
}'

exit 0
