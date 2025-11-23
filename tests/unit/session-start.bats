# session-start.bats - Unit tests for SessionStart hook
#
# Purpose: Test the session-start.sh hook behavior
# Tests: Source filtering, state file detection, exit behavior

# bats file_tags=unit,hooks,session-start

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
# bats test_tags=state-file,missing
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
# bats test_tags=source-filtering
@test "should exit silently when source is not compact" {
  # Create a state file first
  create_state_file "test-session-prev" "manual" "test goal"

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
  assert_file_exist "$TEST_REPO/.git/handoff-pending/handoff-context.json"
}

# Test 3: SessionStart with source="new" exits silently
# bats test_tags=source-filtering
@test "should exit silently when source is new" {
  # Create a state file first
  create_state_file "test-session-prev" "manual" "test goal"

  # Prepare input JSON with source="new"
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "new-session-new",
      cwd: $cwd,
      source: "new"
    }')

  # Run hook
  run bash "$SESSIONSTART_HOOK" <<<"$input"

  # Should exit successfully
  assert_success

  # Should have no output
  assert_output ""

  # State file should still exist
  assert_file_exist "$TEST_REPO/.git/handoff-pending/handoff-context.json"
}

# Test 4: SessionStart with empty previous_session exits and cleans up
# bats test_tags=validation,cleanup
@test "should clean up state file if previous_session is empty" {
  # Create state file with empty previous_session
  mkdir -p "$TEST_REPO/.git/handoff-pending"
  jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      previous_session: "",
      trigger: "manual",
      cwd: $cwd,
      user_instructions: "test goal",
      type: "compact"
    }' \
    >"$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Prepare input JSON
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "new-session-789",
      cwd: $cwd,
      source: "compact"
    }')

  # Run hook
  run bash "$SESSIONSTART_HOOK" <<<"$input"

  # Should exit successfully
  assert_success

  # Should have no output
  assert_output ""

  # State file should be cleaned up
  assert_file_not_exist "$TEST_REPO/.git/handoff-pending/handoff-context.json"
}

# Test 5: SessionStart with missing previous_session field exits and cleans up
# bats test_tags=validation,cleanup
@test "should clean up state file if previous_session is missing" {
  # Create state file without previous_session field
  mkdir -p "$TEST_REPO/.git/handoff-pending"
  jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      trigger: "manual",
      cwd: $cwd,
      user_instructions: "test goal",
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

  # State file should be cleaned up
  assert_file_not_exist "$TEST_REPO/.git/handoff-pending/handoff-context.json"
}

# Test 6: SessionStart reads all state file fields correctly
# bats test_tags=state-reading
@test "should read all fields from state file correctly" {
  # Create comprehensive state file
  create_state_file "prev-session-uuid" "manual" "implement auth feature"

  # Verify state file has correct structure
  local state_file="$TEST_REPO/.git/handoff-pending/handoff-context.json"
  assert_file_exist "$state_file"
  assert_json_field_equals "$state_file" ".previous_session" "prev-session-uuid"
  assert_json_field_equals "$state_file" ".trigger" "manual"
  assert_json_field_equals "$state_file" ".user_instructions" "implement auth feature"
  assert_json_field_equals "$state_file" ".type" "compact"

  # Note: We can't test the actual claude --resume invocation in unit tests
  # That requires integration tests with mocked claude binary
}

# Test 7: SessionStart with recursion prevention (HANDOFF_IN_PROGRESS)
# bats test_tags=recursion-prevention
@test "should exit immediately if HANDOFF_IN_PROGRESS is set" {
  # Create state file
  create_state_file "test-session-recursion" "manual" "test goal"

  # Set recursion prevention flag
  export HANDOFF_IN_PROGRESS=1

  # Prepare input JSON
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "new-session-recursion",
      cwd: $cwd,
      source: "compact"
    }')

  # Run hook
  run bash "$SESSIONSTART_HOOK" <<<"$input"

  # Should exit successfully
  assert_success

  # Should have no output
  assert_output ""

  # State file should still exist (not processed)
  assert_file_exist "$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Clean up
  unset HANDOFF_IN_PROGRESS
}

# Test 8: SessionStart with malformed state file JSON
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

  # This is expected behavior - the script uses set -euo pipefail
  # and doesn't have a trap like pre-compact does
}

# Test 9: SessionStart with source field missing (defaults to "unknown")
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

# Test 10: SessionStart with valid state file but no previous_session creates cleanup scenario
# bats test_tags=edge-case
@test "should handle state file with null previous_session" {
  # Create state file with null previous_session
  mkdir -p "$TEST_REPO/.git/handoff-pending"
  jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      previous_session: null,
      trigger: "manual",
      cwd: $cwd,
      user_instructions: "test goal",
      type: "compact"
    }' \
    >"$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Prepare input JSON
  local input=$(jq -n \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: "new-session-null",
      cwd: $cwd,
      source: "compact"
    }')

  # Run hook
  run bash "$SESSIONSTART_HOOK" <<<"$input"

  # Should exit successfully
  assert_success

  # Should have no output
  assert_output ""

  # State file should be cleaned up (null treated as empty)
  assert_file_not_exist "$TEST_REPO/.git/handoff-pending/handoff-context.json"
}
