#!/usr/bin/env bash
set -euo pipefail

# Detect /clear and generate handoff context for SessionStart

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Read hook input from stdin
input=$(cat)
prompt=$(echo "$input" | jq -r '.prompt // ""')
session_id=$(echo "$input" | jq -r '.session_id')
transcript_path=$(echo "$input" | jq -r '.transcript_path // ""')

# Detect /claude-handoff:handoff command
if [[ "$prompt" == *"/claude-handoff:handoff"* ]]; then
  # Extract goal after ":handoff "
  goal="${prompt#*:handoff }"
  goal=$(echo "$goal" | xargs) # trim whitespace

  # If goal is empty, use default
  if [[ -z "$goal" ]]; then
    goal="Continue previous work"
  fi

  # Generate handoff draft (POC version - will be replaced with transcript analysis)
  draft="## 🔄 Handoff Context

**Goal:** $goal

**Previous Session:** $session_id
**Transcript:** $transcript_path

This is a proof-of-concept. In the full implementation, this will contain:
- Key decisions from previous thread
- Relevant files modified
- User requirements and context
- Recommended next steps

---

**Your Task:** $goal

(Handoff analysis will be implemented in Phase 2)"

  # Store handoff state for SessionStart hook
  state_dir=".git/handoff-pending"
  mkdir -p "$state_dir"

  jq -n \
    --arg draft "$draft" \
    --arg goal "$goal" \
    --arg prev_session "$session_id" \
    '{
      draft: $draft,
      goal: $goal,
      previous_session: $prev_session,
      created_at: (now | todate)
    }' >"$state_dir/handoff-context.json"

  # Inform user that handoff is prepared
  jq -n --arg msg "✓ Handoff context prepared for: $goal

Now run \`/clear\` to start a fresh session with this context automatically injected." '{
    hookSpecificOutput: {
      hookEventName: "UserPromptSubmit",
      additionalContext: $msg
    }
  }'
fi

# Always exit 0 (fail-open)
exit 0
