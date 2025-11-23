# pre-compact.bats - Unit tests for PreCompact hook (fork-session architecture)
#
# Purpose: Test pre-compact.sh with --fork-session immediate handoff generation
# NOTE: Mock claude binary required to test fork-session handoff generation
# Tests: handoff: prefix detection, fork-session call, handoff_content state

# bats file_tags=unit,hooks,pre-compact,fork-session-architecture

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

# Setup: Create git test repo and mock claude binary
setup() {
  setup_test_repo

  # Create mock claude binary for fork-session testing
  MOCK_CLAUDE_DIR="$BATS_TEST_TMPDIR/mock-bin"
  mkdir -p "$MOCK_CLAUDE_DIR"

  cat >"$MOCK_CLAUDE_DIR/claude" <<'EOF'
#!/usr/bin/env bash
# Mock claude binary that returns fake handoff content

# Parse flags
RESUME_SESSION=""
FORK_SESSION=false
MODEL=""
PROMPT=""

while [[ $# -gt 0 ]]; do
  case $1 in
    --resume)
      RESUME_SESSION="$2"
      shift 2
      ;;
    --fork-session)
      FORK_SESSION=true
      shift
      ;;
    --model)
      MODEL="$2"
      shift 2
      ;;
    --print)
      PROMPT="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

# Return fake handoff content
cat <<'HANDOFF'
## Goal
Implement authentication feature

## Relevant Context
- Need OAuth integration
- Using passport.js

## Key Details
- src/auth.ts - main module
- tests/auth.test.ts - test suite

## Important Notes
- Keep backward compatible
HANDOFF

exit 0
EOF

  chmod +x "$MOCK_CLAUDE_DIR/claude"
  export PATH="$MOCK_CLAUDE_DIR:$PATH"
}

# Teardown: Clean up
teardown() {
  cleanup_test_repo
  rm -rf "$MOCK_CLAUDE_DIR"
}

# Test 1: PreCompact with handoff: prefix generates handoff content
# bats test_tags=critical,fork-session,handoff-generation
@test "should generate handoff content with fork-session when handoff: prefix present" {
  # Prepare input JSON
  local input=$(jq -n \
    --arg session "test-session-123" \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: $session,
      trigger: "manual",
      cwd: $cwd,
      custom_instructions: "handoff:implement feature X"
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
  assert_file_exists "$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Verify state file contains handoff_content (not previous_session)
  local state_file="$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Check for new fields
  local has_handoff_content
  has_handoff_content=$(cat "$state_file" | jq 'has("handoff_content")')
  assert_equal "$has_handoff_content" "true"

  # Check handoff_content is not empty
  local content
  content=$(cat "$state_file" | jq -r '.handoff_content')
  refute [ -z "$content" ]

  # Verify goal field
  assert_json_field_equals "$state_file" ".goal" "implement feature X"

  # Verify trigger field
  assert_json_field_equals "$state_file" ".trigger" "manual"
}

# Test 2: PreCompact without handoff: prefix does NOT generate handoff
# bats test_tags=critical,skip-handoff
@test "should NOT generate handoff without handoff: prefix" {
  # Prepare input JSON
  local input=$(jq -n \
    --arg session "test-session-456" \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: $session,
      trigger: "manual",
      cwd: $cwd,
      custom_instructions: "some other instructions"
    }')

  # Run hook
  run bash "$PRECOMPACT_HOOK" <<<"$input"
  assert_success

  # Verify output is valid JSON
  assert_valid_json "$output"

  # Verify state file was NOT created
  assert_file_not_exists "$TEST_REPO/.git/handoff-pending/handoff-context.json"
}

# Test 3: PreCompact handles empty handoff content gracefully
# bats test_tags=error-handling,empty-content
@test "should handle empty handoff content from claude gracefully" {
  # Override mock claude to return empty output
  cat >"$MOCK_CLAUDE_DIR/claude" <<'EOF'
#!/usr/bin/env bash
# Return empty content
echo ""
exit 0
EOF
  chmod +x "$MOCK_CLAUDE_DIR/claude"

  # Prepare input JSON
  local input=$(jq -n \
    --arg session "test-session-empty" \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: $session,
      trigger: "manual",
      cwd: $cwd,
      custom_instructions: "handoff:test goal"
    }')

  # Run hook
  run bash "$PRECOMPACT_HOOK" <<<"$input"
  assert_success

  # Should still return continue:true (fail-open)
  assert_json_field_equals "$output" ".continue" "true"

  # State file should NOT be created (empty content)
  assert_file_not_exists "$TEST_REPO/.git/handoff-pending/handoff-context.json"
}

# Test 4: PreCompact handles claude failure gracefully
# bats test_tags=error-handling,claude-failure
@test "should handle claude --fork-session failure gracefully" {
  # Override mock claude to fail
  cat >"$MOCK_CLAUDE_DIR/claude" <<'EOF'
#!/usr/bin/env bash
echo "Error: Something went wrong"
exit 1
EOF
  chmod +x "$MOCK_CLAUDE_DIR/claude"

  # Prepare input JSON
  local input=$(jq -n \
    --arg session "test-session-failure" \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: $session,
      trigger: "manual",
      cwd: $cwd,
      custom_instructions: "handoff:test goal"
    }')

  # Run hook
  run bash "$PRECOMPACT_HOOK" <<<"$input"
  assert_success

  # Should still return continue:true (fail-open)
  assert_json_field_equals "$output" ".continue" "true"

  # State file should NOT be created (claude failed)
  assert_file_not_exists "$TEST_REPO/.git/handoff-pending/handoff-context.json"
}

# Test 5: PreCompact trims whitespace after handoff: prefix
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
      custom_instructions: "handoff:   execute phase one"
    }')

  # Run hook
  run bash "$PRECOMPACT_HOOK" <<<"$input"
  assert_success

  # Verify state file was created
  assert_file_exists "$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Verify whitespace was trimmed
  local state_file="$TEST_REPO/.git/handoff-pending/handoff-context.json"
  assert_json_field_equals "$state_file" ".goal" "execute phase one"
}

# Test 6: PreCompact always returns continue:true (fail-open)
# bats test_tags=fail-open,reliability
@test "should always return continue:true even with invalid input" {
  # Prepare malformed input
  local input="not valid json"

  # Run hook
  run bash "$PRECOMPACT_HOOK" <<<"$input"

  # Should exit successfully (fail-open)
  assert_success

  # Output should be valid JSON
  assert_valid_json "$output"

  # Should contain continue:true
  assert_json_field_equals "$output" ".continue" "true"
}

# Test 7: PreCompact with "handoff:" at start but more text
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
      custom_instructions: "handoff: now implement this for teams as well, not just individual users"
    }')

  # Run hook
  run bash "$PRECOMPACT_HOOK" <<<"$input"
  assert_success

  # Verify state file was created
  assert_file_exists "$TEST_REPO/.git/handoff-pending/handoff-context.json"

  # Verify full instructions extracted
  local state_file="$TEST_REPO/.git/handoff-pending/handoff-context.json"
  assert_json_field_equals "$state_file" ".goal" \
    "now implement this for teams as well, not just individual users"
}

# Test 8: PreCompact with "handoff:" in MIDDLE of string should NOT trigger
# bats test_tags=edge-case,pattern-matching,negative
@test "should NOT trigger when handoff: appears in middle of string" {
  # Prepare input JSON with "handoff:" NOT at start
  local input=$(jq -n \
    --arg session "test-session-middle" \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: $session,
      trigger: "manual",
      cwd: $cwd,
      custom_instructions: "do something handoff:foo"
    }')

  # Run hook
  run bash "$PRECOMPACT_HOOK" <<<"$input"
  assert_success

  # Verify state file was NOT created
  assert_file_not_exists "$TEST_REPO/.git/handoff-pending/handoff-context.json"
}

# Test 9: PreCompact creates directory if it doesn't exist
# bats test_tags=directory-creation
@test "should create .git/handoff-pending directory if not exists" {
  # Verify directory doesn't exist initially
  assert_dir_not_exists "$TEST_REPO/.git/handoff-pending"

  # Prepare input JSON
  local input=$(jq -n \
    --arg session "test-session-dir" \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: $session,
      trigger: "manual",
      cwd: $cwd,
      custom_instructions: "handoff:test goal"
    }')

  # Run hook
  run bash "$PRECOMPACT_HOOK" <<<"$input"
  assert_success

  # Verify directory was created
  assert_dir_exists "$TEST_REPO/.git/handoff-pending"
}

# Test 10: PreCompact verifies state file contains correct structure
# bats test_tags=state-structure
@test "should create state file with correct structure for new architecture" {
  # Prepare input JSON
  local input=$(jq -n \
    --arg session "test-session-structure" \
    --arg cwd "$TEST_REPO" \
    '{
      session_id: $session,
      trigger: "manual",
      cwd: $cwd,
      custom_instructions: "handoff:verify state structure"
    }')

  # Run hook
  run bash "$PRECOMPACT_HOOK" <<<"$input"
  assert_success

  # Verify state file exists
  local state_file="$TEST_REPO/.git/handoff-pending/handoff-context.json"
  assert_file_exists "$state_file"

  # Verify NEW architecture fields exist
  local has_handoff_content
  has_handoff_content=$(cat "$state_file" | jq 'has("handoff_content")')
  assert_equal "$has_handoff_content" "true"

  local has_goal
  has_goal=$(cat "$state_file" | jq 'has("goal")')
  assert_equal "$has_goal" "true"

  local has_trigger
  has_trigger=$(cat "$state_file" | jq 'has("trigger")')
  assert_equal "$has_trigger" "true"

  local has_type
  has_type=$(cat "$state_file" | jq 'has("type")')
  assert_equal "$has_type" "true"

  # Verify OLD architecture fields do NOT exist
  local has_previous_session
  has_previous_session=$(cat "$state_file" | jq 'has("previous_session")')
  assert_equal "$has_previous_session" "false"

  local has_user_instructions
  has_user_instructions=$(cat "$state_file" | jq 'has("user_instructions")')
  assert_equal "$has_user_instructions" "false"
}
