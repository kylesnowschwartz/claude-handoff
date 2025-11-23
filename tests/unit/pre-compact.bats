# pre-compact.bats - Unit tests for PreCompact hook
#
# Purpose: Test the pre-compact.sh hook behavior
# Tests: State file creation, handoff: prefix detection, whitespace handling

# bats file_tags=unit,hooks,pre-compact

# Load Bats libraries
load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'
load '../test_helper/bats-file/load'

# Load custom helpers
load '../test_helper/git-test-helpers'
load '../test_helper/json-assertions'

# Hook path
PRECOMPACT_HOOK="$BATS_TEST_DIRNAME/../../handoff-plugin/hooks/entrypoints/pre-compact.sh"

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

# Test 1: PreCompact with handoff: prefix creates state file
# bats test_tags=state-file,creation
@test "should create state file with handoff: prefix" {
  # Prepare input JSON
  local input=$(jq -n \
    --arg session "test-session-123" \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: $session,
      trigger: "manual",
      cwd: $cwd,
      manual_instructions: "handoff:implement feature X"
    }')

  # Run hook
  run bash "$PRECOMPACT_HOOK" <<<"$input"
  assert_success

  # Verify output is valid JSON
  assert_valid_json "$output"

  # Verify continue:true and suppressOutput:true
  assert_json_field_equals "$output" ".continue" "true"
  assert_json_field_equals "$output" ".suppressOutput" "true"

  # Verify state file was created
  assert_file_exist "$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Verify state file contents
  local state_file="$TEST_REPO/.git/handoff-pending/handoff-context.json"
  assert_json_field_equals "$state_file" ".previous_session" "test-session-123"
  assert_json_field_equals "$state_file" ".trigger" "manual"
  assert_json_field_equals "$state_file" ".cwd" "$TEST_REPO"
  assert_json_field_equals "$state_file" ".user_instructions" "implement feature X"
  assert_json_field_equals "$state_file" ".type" "compact"
}

# Test 2: PreCompact without handoff: prefix does NOT create state file
# bats test_tags=state-file,skip
@test "should NOT create state file without handoff: prefix" {
  # Prepare input JSON
  local input=$(jq -n \
    --arg session "test-session-456" \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: $session,
      trigger: "manual",
      cwd: $cwd,
      manual_instructions: "some other instructions"
    }')

  # Run hook
  run bash "$PRECOMPACT_HOOK" <<<"$input"
  assert_success

  # Verify output is valid JSON
  assert_valid_json "$output"

  # Verify continue:true and suppressOutput:true
  assert_json_field_equals "$output" ".continue" "true"
  assert_json_field_equals "$output" ".suppressOutput" "true"

  # Verify state file was NOT created
  assert_file_not_exist "$TEST_REPO/.git/handoff-pending/handoff-context.json"
}

# Test 3: PreCompact with empty manual_instructions does NOT create state file
# bats test_tags=state-file,empty
@test "should NOT create state file with empty manual_instructions" {
  # Prepare input JSON
  local input=$(jq -n \
    --arg session "test-session-789" \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: $session,
      trigger: "manual",
      cwd: $cwd,
      manual_instructions: ""
    }')

  # Run hook
  run bash "$PRECOMPACT_HOOK" <<<"$input"
  assert_success

  # Verify output is valid JSON
  assert_valid_json "$output"

  # Verify state file was NOT created
  assert_file_not_exist "$TEST_REPO/.git/handoff-pending/handoff-context.json"
}

# Test 4: PreCompact with "handoff: " (space) trims whitespace correctly
# bats test_tags=whitespace,trimming
@test "should trim leading whitespace after handoff: prefix" {
  # Prepare input JSON with space after colon
  local input=$(jq -n \
    --arg session "test-session-whitespace" \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: $session,
      trigger: "manual",
      cwd: $cwd,
      manual_instructions: "handoff:   execute phase one"
    }')

  # Run hook
  run bash "$PRECOMPACT_HOOK" <<<"$input"
  assert_success

  # Verify state file was created
  assert_file_exist "$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Verify whitespace was trimmed
  local state_file="$TEST_REPO/.git/handoff-pending/handoff-context.json"
  assert_json_field_equals "$state_file" ".user_instructions" "execute phase one"
}

# Test 5: PreCompact with missing manual_instructions field
# bats test_tags=edge-case,missing-field
@test "should handle missing manual_instructions field gracefully" {
  # Prepare input JSON without manual_instructions
  local input=$(jq -n \
    --arg session "test-session-missing" \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: $session,
      trigger: "manual",
      cwd: $cwd
    }')

  # Run hook
  run bash "$PRECOMPACT_HOOK" <<<"$input"
  assert_success

  # Verify output is valid JSON
  assert_valid_json "$output"

  # Verify state file was NOT created
  assert_file_not_exist "$TEST_REPO/.git/handoff-pending/handoff-context.json"
}

# Test 6: PreCompact with "handoff:" at start but more text
# bats test_tags=pattern-matching
@test "should extract instructions after handoff: with complex text" {
  # Prepare input JSON
  local input=$(jq -n \
    --arg session "test-session-complex" \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: $session,
      trigger: "manual",
      cwd: $cwd,
      manual_instructions: "handoff: now implement this for teams as well, not just individual users"
    }')

  # Run hook
  run bash "$PRECOMPACT_HOOK" <<<"$input"
  assert_success

  # Verify state file was created
  assert_file_exist "$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Verify full instructions extracted
  local state_file="$TEST_REPO/.git/handoff-pending/handoff-context.json"
  assert_json_field_equals "$state_file" ".user_instructions" \
    "now implement this for teams as well, not just individual users"
}

# Test 7: PreCompact always returns continue:true (fail-open)
# bats test_tags=fail-open,reliability
@test "should always return continue:true even with invalid input" {
  # Prepare malformed input (invalid JSON)
  local input="not valid json"

  # Run hook - it should still succeed and return valid JSON
  run bash "$PRECOMPACT_HOOK" <<<"$input"

  # Hook should exit successfully (fail-open)
  assert_success

  # Output should be valid JSON
  assert_valid_json "$output"

  # Should contain continue:true
  assert_json_field_equals "$output" ".continue" "true"
}

# Test 8: PreCompact creates directory if it doesn't exist
# bats test_tags=directory-creation
@test "should create .git/handoff-pending directory if not exists" {
  # Verify directory doesn't exist initially
  assert_dir_not_exist "$TEST_REPO/.git/handoff-pending"

  # Prepare input JSON
  local input=$(jq -n \
    --arg session "test-session-dir" \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: $session,
      trigger: "manual",
      cwd: $cwd,
      manual_instructions: "handoff:test goal"
    }')

  # Run hook
  run bash "$PRECOMPACT_HOOK" <<<"$input"
  assert_success

  # Verify directory was created
  assert_dir_exist "$TEST_REPO/.git/handoff-pending"
}

# Test 9: PreCompact with just "handoff:" (no instructions after)
# bats test_tags=edge-case,empty-instructions
@test "should handle handoff: with no instructions after colon" {
  # Prepare input JSON
  local input=$(jq -n \
    --arg session "test-session-empty-after" \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: $session,
      trigger: "manual",
      cwd: $cwd,
      manual_instructions: "handoff:"
    }')

  # Run hook
  run bash "$PRECOMPACT_HOOK" <<<"$input"
  assert_success

  # State file should be created (handoff: prefix matches)
  assert_file_exist "$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # User instructions should be empty string
  local state_file="$TEST_REPO/.git/handoff-pending/handoff-context.json"
  assert_json_field_equals "$state_file" ".user_instructions" ""
}
