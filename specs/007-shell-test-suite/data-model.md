# Data Model: Shell Test Suite

**Feature Branch**: `007-shell-test-suite`
**Date**: 2026-02-13

This feature has no persistent data model (no databases, no APIs, no state files). The "entities" below describe the file-level structure and conventions that tests operate on.

## Entities

### Test File (`*.bats`)

One per script under test. Contains `@test` blocks that verify spec-defined behavior.

| Field | Type | Description |
|-------|------|-------------|
| Script under test | Reference | The bash script this file tests (e.g., `dilxc.sh`) |
| setup() | Function | Per-test initialization: loads helpers, creates mocks |
| @test blocks | Functions | Individual test cases, each runs in isolated subshell |
| teardown() | Function | Optional per-test cleanup (rarely needed due to subshell isolation) |

**Files**:
- `test/dilxc.bats` — tests for `dilxc.sh` (P1, most tests)
- `test/setup-host.bats` — tests for `setup-host.sh` (P2)
- `test/provision-container.bats` — tests for `provision-container.sh` (P2)

### Mock Executable

Temporary bash scripts placed in `$MOCK_BIN` (which is on `PATH`) that shadow real commands during tests.

| Field | Type | Description |
|-------|------|-------------|
| Command name | String | The command being mocked (e.g., `lxc`, `docker`) |
| Exit code | Integer | What the mock returns (default: 0) |
| Stdout output | String | What the mock prints (optional) |
| Call recording | File | `$BATS_TEST_TMPDIR/<cmd>.calls` — one line per invocation with args |

**Lifecycle**: Created in `setup()` or individual `@test`, destroyed automatically when `$BATS_TEST_TMPDIR` is cleaned up.

### Common Setup Helper

Shared initialization loaded by every test file.

| Field | Type | Description |
|-------|------|-------------|
| PROJECT_ROOT | Variable | Absolute path to repo root |
| MOCK_BIN | Variable | Per-test temp directory for mock executables |
| PATH | Variable | `$MOCK_BIN:$PROJECT_ROOT:$PATH` |
| create_mock() | Function | Creates a mock executable that records calls |
| assert_mock_* | Functions | Assertion helpers for mock invocations |

**File**: `test/test_helper/common-setup.bash`

### Git Submodules

External dependencies bundled in the repo.

| Submodule | Path | Purpose |
|-----------|------|---------|
| bats-core | `test/bats/` | Test runner executable |
| bats-support | `test/test_helper/bats-support/` | Base assertion support |
| bats-assert | `test/test_helper/bats-assert/` | Assertion functions (`assert_success`, `assert_output`, etc.) |

## Relationships

```
run-tests.sh
  └── invokes test/bats/bin/bats
        └── runs test/*.bats files
              └── each @test:
                    ├── loads test/test_helper/common-setup.bash
                    │     ├── loads test/test_helper/bats-support/
                    │     └── loads test/test_helper/bats-assert/
                    ├── creates mocks in $MOCK_BIN
                    └── runs script under test (or sources dilxc.sh)
```

## State Transitions

Tests are stateless. Each `@test` starts clean (unique `$BATS_TEST_TMPDIR`) and leaves no persistent artifacts. The only state that persists across tests within a file is anything exported in `setup_file()`, which this project does not use.
