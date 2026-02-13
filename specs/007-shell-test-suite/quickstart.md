# Quickstart: Shell Test Suite

**Feature Branch**: `007-shell-test-suite`
**Date**: 2026-02-13

## Running Tests

```bash
# From repo root — runs all tests
./run-tests.sh

# Run a specific test file
./run-tests.sh test/dilxc.bats

# TAP output (for CI)
./run-tests.sh --tap

# Verbose output (show test names as they run)
./run-tests.sh --verbose-run
```

If submodules aren't initialized, `run-tests.sh` handles it automatically.

## Writing a New Test

### 1. Choose the right file

| Script under test | Test file |
|---|---|
| `dilxc.sh` | `test/dilxc.bats` |
| `setup-host.sh` | `test/setup-host.bats` |
| `provision-container.sh` | `test/provision-container.bats` |

### 2. Add a `@test` block

Every test follows this structure:

```bash
@test "describe the spec behavior being verified" {
    # Arrange: create mocks
    create_mock lxc

    # Act: run the command
    run dilxc.sh snapshot my-snap

    # Assert: verify behavior
    assert_success
    assert_mock_called_with lxc "snapshot test-container my-snap"
}
```

### 3. Use shared helpers

All test files start with:

```bash
setup() {
    load 'test_helper/common-setup'
    _common_setup
}
```

This gives you:
- `$PROJECT_ROOT` — absolute path to repo root
- `$MOCK_BIN` — temp directory for mock executables (on `PATH`)
- bats-assert functions (`assert_success`, `assert_failure`, `assert_output`, `assert_line`, `refute_output`)
- Mock helpers (`create_mock`, `create_mock_with_output`, `assert_mock_called`, `assert_mock_called_with`, `assert_mock_not_called`)

## Mock Patterns

### Basic mock (records calls, exits 0)

```bash
create_mock lxc
```

### Mock with specific exit code

```bash
create_mock lxc 1   # mock lxc that fails
```

### Mock with output

```bash
create_mock_with_output lxc "test-container RUNNING" 0
```

### Assert mock was called

```bash
assert_mock_called lxc
assert_mock_called_with lxc "info test-container"
assert_mock_not_called docker
```

### Conditional mock behavior

For mocks that need different responses based on arguments:

```bash
cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/bin/bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info)  echo "Status: RUNNING" ;;
    exec)  echo "command output" ;;
    *)     echo "unknown" ;;
esac
MOCK
chmod +x "$MOCK_BIN/lxc"
```

## Testing dilxc.sh (Sourceable)

`dilxc.sh` has a main guard, so tests can source it to access functions directly:

```bash
setup() {
    load 'test_helper/common-setup'
    _common_setup
    source "$PROJECT_ROOT/dilxc.sh"
    CONTAINER_NAME="test-container"
}

@test "require_running exits when container is stopped" {
    create_mock_with_output lxc "STOPPED" 0
    run require_running
    assert_failure
}
```

## Testing setup-host.sh / provision-container.sh (Black-Box)

These scripts can't be sourced. Test them as external commands:

```bash
@test "setup-host.sh requires -p flag" {
    create_mock lxc
    run "$PROJECT_ROOT/setup-host.sh"
    assert_failure
    assert_output --partial "project path is required"
}
```

## Key Conventions

- **Test names describe spec behavior**, not implementation: "destroy prompts with container name" not "cmd_destroy calls read"
- **One assertion focus per test** — multiple asserts are fine if they verify the same behavior
- **Mocks record, tests assert** — never put assertions inside mock scripts
- **Tests verify spec, not implementation** — if the spec says "exits with error", test for `assert_failure` and error message, don't assert internal function call order
