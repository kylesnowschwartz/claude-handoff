# session-start.bats - Unit tests for SessionStart hook (fork-session architecture)
#
# Purpose: Test session-start.sh injecting pre-generated handoff content
# NOTE: Tests simplified - no more claude --resume calls, just content injection
# Tests: Source filtering, handoff_content injection, cleanup

# bats file_tags=unit,hooks,session-start,fork-session-architecture

# Load Bats libraries
load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'
load '../test_helper/bats-file/load'

# Load custom helpers
load '../test_helper/git-test-helpers'
load '../test_helper/json-assertions'

# Hook path
SESSIONSTART_HOOK="$BATS_TEST_DIRNAME/../../handoff-plugin/hooks/entrypoints/session-start.sh"

# Disable logging for tests
export LOGGING_ENABLED=false

# Setup: Create git test repo before each test
setup() {
  setup_test_repo
}

# Teardown: Clean up git repo after each test
teardown() {
  cleanup_test_repo
}

# Test 1: SessionStart with no state file exits silently
# bats test_tags=critical,state-file,missing
@test "should exit silently with no state file" {
  # Prepare input JSON
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "new-session-123",
      cwd: $cwd,
      source: "compact"
    }')

  # Run hook
  run bash "$SESSIONSTART_HOOK" <<<"$input"

  # Should exit successfully
  assert_success

  # Should have no output (silent exit)
  assert_output ""
}

# Test 2: SessionStart with source != "compact" exits silently
# bats test_tags=critical,source-filtering
@test "should exit silently when source is not compact" {
  # Create state file with handoff_content
  mkdir -p "$TEST_REPO/.git/handoff-pending"
  jq -n \
    --arg content "test handoff content" \
    --arg goal "test goal" \
    '{
      handoff_content: $content,
      goal: $goal,
      trigger: "manual",
      type: "compact"
    }' \
    >"$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Prepare input JSON with source="other"
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "new-session-456",
      cwd: $cwd,
      source: "other"
    }')

  # Run hook
  run bash "$SESSIONSTART_HOOK" <<<"$input"

  # Should exit successfully
  assert_success

  # Should have no output (silent exit)
  assert_output ""

  # State file should still exist (not cleaned up)
  assert_file_exists "$TEST_REPO/.git/handoff-pending/handoff-context.json"
}

# Test 3: SessionStart injects handoff_content successfully
# bats test_tags=critical,injection,success-path
@test "should inject handoff_content as systemMessage" {
  # Create state file with handoff_content
  mkdir -p "$TEST_REPO/.git/handoff-pending"
  local handoff_text="## Goal
Implement OAuth integration

## Relevant Context
- Basic login implemented
- Need OAuth provider support

## Key Details
- src/auth.ts - main module
- tests/auth.test.ts - test suite"

  jq -n \
    --arg content "$handoff_text" \
    --arg goal "implement OAuth integration" \
    '{
      handoff_content: $content,
      goal: $goal,
      trigger: "manual",
      type: "compact"
    }' \
    >"$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Prepare input JSON
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "new-session-inject",
      cwd: $cwd,
      source: "compact"
    }')

  # Run hook
  run bash "$SESSIONSTART_HOOK" <<<"$input"

  # Should exit successfully
  assert_success

  # Output should be valid JSON
  assert_valid_json "$output"

  # Output should contain systemMessage field
  local has_system_message
  has_system_message=$(echo "$output" | jq 'has("systemMessage")')
  assert_equal "$has_system_message" "true"

  # systemMessage should contain the handoff content
  local message_content
  message_content=$(echo "$output" | jq -r '.systemMessage')
  assert_regex "$message_content" "OAuth integration"
  assert_regex "$message_content" "src/auth.ts"
}

# Test 4: SessionStart cleans up state file after injection
# bats test_tags=critical,cleanup
@test "should clean up state file after successful injection" {
  # Create state file with handoff_content
  mkdir -p "$TEST_REPO/.git/handoff-pending"
  jq -n \
    --arg content "test handoff content" \
    --arg goal "test goal" \
    '{
      handoff_content: $content,
      goal: $goal,
      trigger: "manual",
      type: "compact"
    }' \
    >"$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Verify state file exists
  assert_file_exists "$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Prepare input JSON
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "new-session-cleanup",
      cwd: $cwd,
      source: "compact"
    }')

  # Run hook
  run bash "$SESSIONSTART_HOOK" <<<"$input"
  assert_success

  # State file should be deleted
  assert_file_not_exists "$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Directory should be deleted (since we only had one file)
  assert_dir_not_exists "$TEST_REPO/.git/handoff-pending"
}

# Test 5: SessionStart with missing handoff_content exits silently
# bats test_tags=critical,validation
@test "should exit silently when handoff_content is missing" {
  # Create state file WITHOUT handoff_content (old format)
  mkdir -p "$TEST_REPO/.git/handoff-pending"
  jq -n \
    --arg goal "test goal" \
    '{
      goal: $goal,
      trigger: "manual",
      type: "compact"
    }' \
    >"$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Prepare input JSON
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "new-session-missing",
      cwd: $cwd,
      source: "compact"
    }')

  # Run hook
  run bash "$SESSIONSTART_HOOK" <<<"$input"

  # Should exit successfully
  assert_success

  # Should have no output
  assert_output ""

  # State file should still exist (not cleaned up for safety)
  assert_file_exists "$TEST_REPO/.git/handoff-pending/handoff-context.json"
}

# Test 6: SessionStart with empty handoff_content exits silently
# bats test_tags=critical,validation
@test "should exit silently when handoff_content is empty" {
  # Create state file with empty handoff_content
  mkdir -p "$TEST_REPO/.git/handoff-pending"
  jq -n \
    --arg content "" \
    --arg goal "test goal" \
    '{
      handoff_content: $content,
      goal: $goal,
      trigger: "manual",
      type: "compact"
    }' \
    >"$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Prepare input JSON
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "new-session-empty",
      cwd: $cwd,
      source: "compact"
    }')

  # Run hook
  run bash "$SESSIONSTART_HOOK" <<<"$input"

  # Should exit successfully
  assert_success

  # Should have no output
  assert_output ""

  # State file should still exist (didn't clean up)
  assert_file_exists "$TEST_REPO/.git/handoff-pending/handoff-context.json"
}

# Test 7: SessionStart with source field missing defaults to "unknown"
# bats test_tags=defaults,missing-field
@test "should handle missing source field" {
  # Prepare input JSON without source field
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "new-session-no-source",
      cwd: $cwd
    }')

  # Run hook
  run bash "$SESSIONSTART_HOOK" <<<"$input"

  # Should exit successfully
  assert_success

  # Should have no output (source defaults to "unknown", not "compact")
  assert_output ""
}

# Test 8: SessionStart verifies correct JSON structure
# bats test_tags=schema-validation
@test "should return correct JSON structure with only systemMessage field" {
  # Create state file with handoff_content
  mkdir -p "$TEST_REPO/.git/handoff-pending"
  jq -n \
    --arg content "test handoff content for schema" \
    --arg goal "test goal" \
    '{
      handoff_content: $content,
      goal: $goal,
      trigger: "manual",
      type: "compact"
    }' \
    >"$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Prepare input JSON
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "new-session-schema",
      cwd: $cwd,
      source: "compact"
    }')

  # Run hook
  run bash "$SESSIONSTART_HOOK" <<<"$input"
  assert_success

  # Parse JSON and verify structure
  local output_json="$output"

  # Should have exactly one key: systemMessage
  local key_count
  key_count=$(echo "$output_json" | jq 'keys | length')
  assert_equal "$key_count" "1"

  # That key should be "systemMessage"
  local key_name
  key_name=$(echo "$output_json" | jq -r 'keys[0]')
  assert_equal "$key_name" "systemMessage"

  # systemMessage value should be a string
  local message_type
  message_type=$(echo "$output_json" | jq -r '.systemMessage | type')
  assert_equal "$message_type" "string"
}

# Test 9: SessionStart handles malformed state file JSON
# bats test_tags=error-handling,malformed-json
@test "should fail fast with malformed state file" {
  # Create malformed state file
  mkdir -p "$TEST_REPO/.git/handoff-pending"
  echo "not valid json" >"$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Prepare input JSON
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "new-session-malformed",
      cwd: $cwd,
      source: "compact"
    }')

  # Run hook - will fail due to jq parsing error (set -euo pipefail)
  run bash "$SESSIONSTART_HOOK" <<<"$input"

  # Should fail (jq returns non-zero for malformed JSON)
  assert_failure
}

# Test 10: SessionStart with OLD state format (previous_session) does NOT inject
# bats test_tags=backward-compatibility,old-format
@test "should NOT inject handoff when state file uses old previous_session format" {
  # Create state file with OLD architecture format
  mkdir -p "$TEST_REPO/.git/handoff-pending"
  jq -n \
    --arg session "old-session-uuid" \
    --arg cwd "$TEST_REPO" \
    '{
      previous_session: $session,
      trigger: "manual",
      cwd: $cwd,
      user_instructions: "old format instructions",
      type: "compact"
    }' \
    >"$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Prepare input JSON
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "new-session-old-format",
      cwd: $cwd,
      source: "compact"
    }')

  # Run hook
  run bash "$SESSIONSTART_HOOK" <<<"$input"

  # Should exit successfully
  assert_success

  # Should have no output (handoff_content is missing)
  assert_output ""

  # State file should still exist (not cleaned up)
  assert_file_exists "$TEST_REPO/.git/handoff-pending/handoff-context.json"
}
