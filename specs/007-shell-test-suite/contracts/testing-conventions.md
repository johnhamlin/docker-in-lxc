# Testing Conventions Contract

**Feature**: 007-shell-test-suite
**Date**: 2026-02-13

This document defines the conventions and interfaces that all test files must follow.

## Test File Structure

Every `.bats` file follows this template:

```bash
#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    # File-specific setup (e.g., source dilxc.sh, set CONTAINER_NAME)
}

@test "descriptive name matching spec behavior" {
    # Arrange
    # Act
    # Assert
}
```

## Common Setup Contract

`test/test_helper/common-setup.bash` exports:

| Symbol | Type | Description |
|--------|------|-------------|
| `_common_setup` | Function | Must be called in every `setup()`. Loads bats libs, sets PROJECT_ROOT, creates MOCK_BIN. |
| `PROJECT_ROOT` | Variable | Absolute path to repository root |
| `MOCK_BIN` | Variable | Per-test temp directory prepended to PATH; place mock executables here |
| `create_mock` | Function | `create_mock <cmd> [exit_code]` — creates mock that records calls |
| `create_mock_with_output` | Function | `create_mock_with_output <cmd> <output> [exit_code]` — mock with stdout |
| `assert_mock_called` | Function | `assert_mock_called <cmd>` — fails if mock was never called |
| `assert_mock_not_called` | Function | `assert_mock_not_called <cmd>` — fails if mock was called |
| `assert_mock_called_with` | Function | `assert_mock_called_with <cmd> <expected_args>` — fails if no invocation matches |

## Mock Call Recording Format

Mock executables append one line per invocation to `$BATS_TEST_TMPDIR/<cmd>.calls`:

```
arg1 arg2 arg3
```

Each line is the mock's `$@` (all positional parameters, space-separated). The file does not exist if the mock was never called.

## Test Naming Convention

Test names describe the **spec behavior** being verified, not the implementation detail:

```bash
# Good — describes spec behavior
@test "destroy prompts with the specified container name"
@test "shell exits with error when container is stopped"
@test "sync excludes node_modules .git dist and build"

# Bad — describes implementation
@test "cmd_destroy calls read builtin"
@test "cmd_shell checks lxc list output"
@test "cmd_sync passes four exclude flags to rsync"
```

## Testing Approaches by Script

### dilxc.sh — Source and Test Functions

```bash
setup() {
    load 'test_helper/common-setup'
    _common_setup
    source "$PROJECT_ROOT/dilxc.sh"
    CONTAINER_NAME="test-container"
    SCRIPT_DIR="$PROJECT_ROOT"
}
```

Tests call `cmd_*` functions directly or run `dilxc.sh` as a command.

### setup-host.sh — Black-Box

```bash
@test "setup-host.sh requires project path" {
    create_mock lxc
    run "$PROJECT_ROOT/setup-host.sh"
    assert_failure
    assert_output --partial "project path is required"
}
```

Must mock all external commands the script calls.

### provision-container.sh — Black-Box

```bash
@test "provision-container.sh writes bash aliases" {
    # Mock all system commands
    create_mock apt-get
    create_mock npm
    create_mock curl
    create_mock su
    create_mock systemctl
    create_mock usermod
    create_mock chsh
    # ... run and assert
}
```

Must mock all system commands and use temp directories for file output.

## Exit Code Conventions

| Exit Code | Meaning | Test Assertion |
|-----------|---------|----------------|
| 0 | Success | `assert_success` |
| 1 | User error (bad args, missing prereqs) | `assert_failure` |
| Non-zero | Command failure propagation | `assert_failure` with specific message check |
