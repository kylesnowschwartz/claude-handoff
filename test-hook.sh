#!/usr/bin/env bash
# Test the hook flow: UserPromptSubmit -> state file -> SessionStart

echo "=== Testing UserPromptSubmit hook (detects /handoff) ==="
cat <<'EOF' | handoff-plugin/hooks/entrypoints/user-prompt-submit.sh
{
  "session_id": "test-session-123",
  "prompt": "/claude-handoff:handoff implement this for teams",
  "transcript_path": "/tmp/test-transcript.jsonl",
  "hook_event_name": "UserPromptSubmit"
}
EOF

echo -e "\n=== Checking state file ==="
if [[ -f .git/handoff-pending/handoff-context.json ]]; then
  echo "✓ State file created:"
  cat .git/handoff-pending/handoff-context.json | jq
else
  echo "✗ State file not found"
  exit 1
fi

echo -e "\n=== Testing SessionStart hook (reads state) ==="
cat <<'EOF' | handoff-plugin/hooks/entrypoints/session-start.sh
{
  "session_id": "test-session-456",
  "source": "clear",
  "transcript_path": "/tmp/new-transcript.jsonl",
  "hook_event_name": "SessionStart"
}
EOF

echo -e "\n=== Verifying state cleanup ==="
if [[ ! -f .git/handoff-pending/handoff-context.json ]]; then
  echo "✓ State file cleaned up"
else
  echo "✗ State file still exists"
  exit 1
fi
