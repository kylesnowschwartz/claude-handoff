# Claude-Handoff Test Suite

Comprehensive test suite for the claude-handoff plugin using [Bats (Bash Automated Testing System)](https://github.com/bats-core/bats-core).

## Directory Structure

```
tests/
├── unit/                  # Unit tests for individual hooks
│   ├── pre-compact.bats  # Tests for PreCompact hook
│   └── session-start.bats # Tests for SessionStart hook
├── integration/          # Integration tests (future)
├── fixtures/             # Test fixtures and mock data
└── test_helper/          # Test helper modules
    ├── bats-support/     # Bats support library (submodule)
    ├── bats-assert/      # Bats assertion library (submodule)
    ├── bats-file/        # Bats file assertion library (submodule)
    ├── git-test-helpers.bash    # Git repo helpers
    └── json-assertions.bash     # JSON validation helpers
```

## Prerequisites

- **Bats**: Install via Homebrew: `brew install bats-core`
- **jq**: Install via Homebrew: `brew install jq`
- **Git submodules**: Initialize with `git submodule update --init --recursive`

## Running Tests

```bash
# Run all tests
bats tests/unit/

# Run specific test file
bats tests/unit/pre-compact.bats
bats tests/unit/session-start.bats

# Run with verbose output
bats --verbose-run tests/unit/

# Run tests with TAP output
bats --tap tests/unit/

# Filter by tags
bats --filter-tags state-file tests/unit/
```

## Test Coverage

### PreCompact Hook (`tests/unit/pre-compact.bats`)

Tests the `pre-compact.sh` hook behavior:

- ✅ State file creation with `handoff:` prefix
- ✅ Skipping state file creation without `handoff:` prefix
- ✅ Empty manual_instructions handling
- ✅ Whitespace trimming after `handoff:` prefix
- ✅ Missing field handling
- ✅ Complex instruction text extraction
- ✅ Fail-open behavior (always returns `continue:true`)
- ✅ Directory creation
- ✅ Edge cases (empty instructions after colon)

**9 tests total**

### SessionStart Hook (`tests/unit/session-start.bats`)

Tests the `session-start.sh` hook behavior:

- ✅ Silent exit with no state file
- ✅ Source filtering (compact vs. other sources)
- ✅ State file cleanup on empty/missing previous_session
- ✅ Correct state file field reading
- ✅ Recursion prevention (HANDOFF_IN_PROGRESS)
- ✅ Malformed JSON handling (fail-fast)
- ✅ Missing field defaults
- ✅ Null value handling

**10 tests total**

## Test Helpers

### Git Test Helpers (`test_helper/git-test-helpers.bash`)

Utilities for creating temporary git repositories:

- `setup_test_repo()` - Create temporary git repo with initial commit
- `cleanup_test_repo()` - Clean up test repository
- `create_state_file()` - Create handoff state file with parameters
- `state_file_exists()` - Check if state file exists
- `get_state_field()` - Extract field from state file

### JSON Assertions (`test_helper/json-assertions.bash`)

Utilities for JSON validation:

- `assert_json_field_exists()` - Assert field exists
- `assert_json_field_equals()` - Assert field equals value
- `assert_json_field_matches()` - Assert field matches regex
- `assert_json_field_type()` - Assert field type
- `assert_json_fields_exist()` - Assert multiple fields exist
- `assert_valid_json()` - Assert valid JSON structure

## Writing New Tests

### Basic Test Template

```bash
# Load libraries
load '../test_helper/bats-support/load'
load '../test_helper/bats-assert/load'
load '../test_helper/bats-file/load'

# Load custom helpers
load '../test_helper/git-test-helpers'
load '../test_helper/json-assertions'

# Setup/teardown
setup() {
  setup_test_repo
}

teardown() {
  cleanup_test_repo
}

# Test case
@test "should do something useful" {
  # Arrange
  local input=$(jq -n '{"field": "value"}')

  # Act
  run bash "$HOOK_SCRIPT" <<<"$input"

  # Assert
  assert_success
  assert_output "expected output"
}
```

### Test Tags

Use Bats tags for filtering and organization:

```bash
# bats file_tags=unit,hooks,pre-compact
# bats test_tags=state-file,creation
@test "test name" {
  # ...
}
```

## CI/CD Integration

Tests are designed to run in CI environments:

- Use temporary directories (no side effects)
- Disable logging (`LOGGING_ENABLED=false`)
- Fast execution (no external dependencies)
- Clear, actionable failure messages

### Example GitHub Actions

```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
        with:
          submodules: recursive
      - name: Install Bats
        run: npm install -g bats
      - name: Run tests
        run: bats tests/unit/
```

## Debugging Tests

### Enable Logging

Edit `handoff-plugin/hooks/lib/logging.sh`:

```bash
LOGGING_ENABLED=true  # Enable logging
```

Then check logs:

```bash
tail -f /tmp/handoff-precompact.log
tail -f /tmp/handoff-sessionstart.log
```

### Verbose Output

```bash
bats --verbose-run tests/unit/pre-compact.bats
```

### Print Test Variables

```bash
@test "debug test" {
  local value="test"
  echo "Debug: value=$value" >&3  # Print to terminal
  run some_command
}
```

## Best Practices

1. **Test Isolation**: Each test creates a fresh temporary git repository
2. **No Side Effects**: Tests don't modify project files or global state
3. **Clear Assertions**: Use descriptive assertion messages
4. **Edge Cases**: Test boundary conditions and error cases
5. **Documentation**: Use comments and test names to explain what's tested
6. **Fast Tests**: Keep tests fast (no long sleeps or network calls)

## Troubleshooting

### Submodules Not Found

```bash
git submodule update --init --recursive
```

### jq Not Found

```bash
brew install jq
```

### Tests Fail with "command not found: bats"

```bash
brew install bats-core
```

### Permission Denied on Hook Scripts

```bash
chmod +x handoff-plugin/hooks/entrypoints/*.sh
```

## Resources

- [Bats Documentation](https://bats-core.readthedocs.io/)
- [bats-assert Library](https://github.com/bats-core/bats-assert)
- [bats-file Library](https://github.com/bats-core/bats-file)
- [bats-support Library](https://github.com/bats-core/bats-support)
