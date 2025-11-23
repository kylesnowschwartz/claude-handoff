# git-test-helpers.bash - Git repository testing utilities for Bats
#
# Purpose: Provide temporary git repositories for testing hooks
# Used by: Unit and integration tests requiring git repositories

# Global variables (set by helpers, used by tests)
TEST_REPO=""

# setup_test_repo() - Create temporary git repository
#
# Creates a fresh git repo in $BATS_TEST_TMPDIR with:
# - Configured user.name and user.email
# - Initial empty commit
# - .git directory for state file testing
#
# Sets global variables:
#   TEST_REPO - Path to created repository
#
# Usage:
#   setup() {
#     setup_test_repo
#   }
setup_test_repo() {
  TEST_REPO="$BATS_TEST_TMPDIR/test-repo"
  mkdir -p "$TEST_REPO"
  cd "$TEST_REPO"

  git init -q
  git config user.email "test@example.com"
  git config user.name "Test User"

  # Create initial empty commit
  git commit --allow-empty -m "initial" -q
}

# cleanup_test_repo() - Remove test repository
#
# Cleans up test repository created by setup_test_repo().
# Safe to call multiple times or if repo doesn't exist.
#
# Usage:
#   teardown() {
#     cleanup_test_repo
#   }
cleanup_test_repo() {
  if [[ -n "$TEST_REPO" ]] && [[ -d "$TEST_REPO" ]]; then
    cd /
    rm -rf "$TEST_REPO"
  fi
  TEST_REPO=""
}

# create_state_file() - Create handoff state file with given parameters
#
# Args:
#   $1 - previous_session ID
#   $2 - trigger (manual, auto, etc.)
#   $3 - user_instructions
#
# Usage:
#   create_state_file "test-session-123" "manual" "implement feature X"
create_state_file() {
  local session="$1"
  local trigger="$2"
  local instructions="$3"

  mkdir -p "$TEST_REPO/.git/handoff-pending"

  jq -n \
    --arg session "$session" \
    --arg trigger "$trigger" \
    --arg cwd "$TEST_REPO" \
    --arg instructions "$instructions" \
    '{
      previous_session: $session,
      trigger: $trigger,
      cwd: $cwd,
      user_instructions: $instructions,
      type: "compact"
    }' \
    >"$TEST_REPO/.git/handoff-pending/handoff-context.json"
}

# state_file_exists() - Check if state file exists
#
# Returns: 0 if file exists, 1 otherwise
state_file_exists() {
  [[ -f "$TEST_REPO/.git/handoff-pending/handoff-context.json" ]]
}

# get_state_field() - Extract field from state file
#
# Args:
#   $1 - field selector (jq format, e.g., ".user_instructions")
#
# Usage:
#   local instructions=$(get_state_field ".user_instructions")
get_state_field() {
  local field="$1"
  jq -r "$field" "$TEST_REPO/.git/handoff-pending/handoff-context.json"
}
