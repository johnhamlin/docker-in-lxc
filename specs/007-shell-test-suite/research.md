# Research: Shell Test Suite

**Feature Branch**: `007-shell-test-suite`
**Date**: 2026-02-13

## Decision 1: Testing Framework

**Decision**: bats-core with bats-support and bats-assert, distributed as git submodules.

**Rationale**: bats-core is the most widely adopted bash testing framework (~5,800 GitHub stars), actively maintained (v1.13.0, Nov 2025), and bash-native — aligning with the project's Shell Scripts Only principle. Git submodules add ~600KB and require no system-wide installation. Each `@test` runs in its own process (subshell isolation), which provides natural mock cleanup between tests.

**Alternatives considered**:
- **ShellSpec** (~1,300 stars): Built-in mocking is appealing, but single-maintainer project and BDD-style syntax is less familiar to casual contributors.
- **shunit2** (~1,600 stars): Declining maintenance, no built-in test isolation, less CI integration.

## Decision 2: Submodule Layout

**Decision**: Standard bats-core layout under `test/`:

```
test/
├── bats/                     # bats-core (the runner)
├── test_helper/
│   ├── bats-support/         # assertion support library
│   ├── bats-assert/          # assertion functions (depends on bats-support)
│   └── common-setup.bash     # shared setup: load libs, PROJECT_ROOT, mock helpers
├── dilxc.bats
├── setup-host.bats
└── provision-container.bats
```

**Rationale**: This is the official bats-core tutorial layout. `bats-assert` requires `bats-support` to be a sibling directory — placing both under `test/test_helper/` satisfies this automatically. The `load` function resolves paths relative to the test file's directory.

**Submodule URLs**:
- `git submodule add https://github.com/bats-core/bats-core.git test/bats`
- `git submodule add https://github.com/bats-core/bats-support.git test/test_helper/bats-support`
- `git submodule add https://github.com/bats-core/bats-assert.git test/test_helper/bats-assert`

## Decision 3: Mocking Strategy

**Decision**: DIY mock recording via PATH manipulation and temp files — no external mock library.

**Rationale**: The project's scripts call external commands (`lxc`, `docker`, `rsync`, `apt-get`, etc.) that must be intercepted during tests. The PATH-based pattern is the standard bats-core approach:

1. `common-setup.bash` creates `MOCK_BIN="$BATS_TEST_TMPDIR/mock-bin"` and prepends it to `PATH`
2. Mock executables record invocations to `$BATS_TEST_TMPDIR/<cmd>.calls`
3. Helper functions (`create_mock`, `assert_mock_called_with`, etc.) encapsulate the pattern

Since `$BATS_TEST_TMPDIR` is unique per test, mock state is automatically isolated. No external mock library adds overhead or learning curve.

**Alternatives considered**:
- **jasonkarns/bats-mock**: Plan-file based stubs. Adds another submodule and concept. Overkill for this project's needs.
- **grayhemp/bats-mock**: More structured API but adds dependency. The DIY pattern is ~30 lines of helper code.
- **Function overrides (for sourceable scripts)**: When `dilxc.sh` is sourced, functions like `lxc() { ... }` can shadow the real command. This is viable for dilxc.sh tests but not for setup-host.sh/provision-container.sh which can't be sourced. Using PATH-based mocking consistently across all test files is simpler.

## Decision 4: dilxc.sh Testability — Main Guard

**Decision**: Add a main guard to `dilxc.sh` so it can be sourced for testing without triggering side effects.

**Pattern**:
```bash
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Container name resolution
  # SCRIPT_DIR initialization
  # Case dispatch
fi
```

**What moves inside the guard**:
- Container name resolution cascade (lines 12-29) — reads `$1`, calls `shift`, walks filesystem
- `SCRIPT_DIR` initialization (line 31) — uses `$0` which resolves to bats runner when sourced
- Case-based dispatch (lines 695-725)

**What stays outside the guard**:
- All function definitions (`usage`, `require_container`, `require_running`, `validate_port`, `ensure_auth_forwarding`, all `cmd_*` functions)

**Rationale**: This is the Google Shell Style Guide recommended pattern. The simple `BASH_SOURCE` comparison works for testing (no symlink concerns in test context). Container name resolution must be inside the guard because it has side effects (mutates `$@`, reads filesystem, sets globals) that would interfere with the test harness.

**Gotchas addressed**:
- `dilxc.sh` does NOT use `set -euo pipefail` (per Principle X), so sourcing it won't affect the bats runner
- `SCRIPT_DIR` uses `$0` which would resolve to the bats executable when sourced — moving it inside the guard avoids this
- The `shift` in `@name` handling would shift the test runner's args — moving it inside the guard avoids this

## Decision 5: setup-host.sh and provision-container.sh Testing Approach

**Decision**: Black-box testing via `run` with PATH-based mocking. No refactoring of these scripts.

**Rationale**: Both scripts are entirely imperative (no reusable functions) with `set -euo pipefail` at the top. Sourcing them would:
1. Execute `set -euo pipefail`, affecting the bats runner (known bats-core issue #36)
2. Immediately start running apt-get, lxc, etc.

Refactoring them to extract functions is possible but not justified — the scripts are run infrequently and their structure is linear and readable. PATH-based mocking provides full coverage:

```bash
@test "setup-host.sh fails without -p flag" {
    create_mock lxc
    run setup-host.sh
    assert_failure
    assert_output --partial "project path is required"
}
```

For `provision-container.sh`, tests need additional mocks for `apt-get`, `npm`, `curl`, `su`, `systemctl`, `chsh`, `usermod`, plus a writable temp filesystem for config file assertions.

## Decision 6: Test Runner Script

**Decision**: `run-tests.sh` at repo root, auto-initializes submodules silently.

**Pattern**:
```bash
#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [[ ! -x "$SCRIPT_DIR/test/bats/bin/bats" ]]; then
    git -C "$SCRIPT_DIR" submodule update --init --recursive
fi
if [[ $# -gt 0 ]]; then
    "$SCRIPT_DIR/test/bats/bin/bats" "$@"
else
    "$SCRIPT_DIR/test/bats/bin/bats" "$SCRIPT_DIR/test/"
fi
```

**Rationale**: Spec requires `./run-tests.sh` at repo root (FR-002, US1). Silent submodule initialization per US1-AS2. When arguments are provided (e.g., `./run-tests.sh test/dilxc.bats` or `./run-tests.sh --tap test/`), they replace the default `test/` directory so users can run individual test files. With no arguments, all tests run.

**Constitution tension**: Principle II (Three Scripts) says new scripts MUST NOT be created unless genuinely new execution context. A test runner IS a new context (development tooling, not container management). Principle VIII (Detect and Report) would prefer erroring with instructions, but the spec explicitly requires silent auto-init.

## Decision 7: Mock Helper Design

**Decision**: Shared helpers in `common-setup.bash` with these functions:

```bash
_common_setup()              # Load bats libs, set PROJECT_ROOT, create MOCK_BIN
create_mock <cmd> [exit]     # Create mock executable that records calls
create_mock_with_output <cmd> <output> [exit]  # Mock with stdout
assert_mock_called <cmd>     # Assert mock was called at least once
assert_mock_not_called <cmd> # Assert mock was never called
assert_mock_called_with <cmd> <args>  # Assert specific invocation exists
```

**Rationale**: Keeps test files focused on behavior assertions. The ~40 lines of helper code replace a third-party mock library dependency. Helpers use bats-assert's `fail` function for consistent error reporting.
