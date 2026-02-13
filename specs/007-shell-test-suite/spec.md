# Feature Specification: Shell Test Suite

**Feature Branch**: `007-shell-test-suite`
**Created**: 2026-02-12
**Status**: Draft
**Input**: User description: "I just did some manual testing and found a lot of little bugs. We are long overdue for a comprehensive testing suite. Look into best practices for testing shell scripts, and bear in mind that we're telling users to clone this whole repo. In writing tests, write them to test to verify that the functionality matches the specs-- dont just lock in the current functionality. Going forward, ammend the constitution to require TDD"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Run Tests After Cloning the Repo (Priority: P1)

A contributor or user clones the repo and wants to run the test suite to verify everything works. They run a single command from the repo root and see clear pass/fail output for every test. The test framework and all helpers are included in the repo via git submodules, so no system-wide installation is needed beyond bash and git.

**Why this priority**: If users can't run tests easily after cloning, the entire testing suite is inaccessible. This is the foundation everything else depends on.

**Independent Test**: Can be fully tested by cloning the repo with `--recurse-submodules`, running the test command from the repo root, and verifying TAP-formatted output appears with pass/fail results.

**Acceptance Scenarios**:

1. **Given** a fresh clone with `git clone --recurse-submodules`, **When** the user runs `./run-tests.sh` from the repo root, **Then** all tests execute and produce clear pass/fail output.
2. **Given** a clone without `--recurse-submodules` (submodules not initialized), **When** the user runs `./run-tests.sh`, **Then** the test runner silently initializes submodules via `git submodule update --init` before running tests.
3. **Given** the repo is cloned on any Linux system with bash 4+ and git installed, **When** the user runs `./run-tests.sh`, **Then** tests execute without requiring any additional system packages or tools.

---

### User Story 2 - Verify CLI Commands Match Spec Behavior (Priority: P1)

A developer wants confidence that `dilxc.sh` subcommands behave according to their specifications. The test suite covers every subcommand's documented behavior — argument parsing, output messages, error handling, and exit codes — by mocking external dependencies (LXD, Docker, rsync) so tests run fast and without real infrastructure.

**Why this priority**: `dilxc.sh` is the primary user-facing script with the most commands and the highest surface area for bugs. Testing it against spec behavior (not just current behavior) catches regressions and spec violations.

**Independent Test**: Can be tested by running the dilxc test file(s) and verifying each subcommand's acceptance scenarios pass with mocked external commands.

**Acceptance Scenarios**:

1. **Given** tests for a dilxc.sh subcommand, **When** the tests run, **Then** they verify behavior described in the corresponding spec's acceptance scenarios, not just the current implementation.
2. **Given** a mocked `lxc` command, **When** `dilxc.sh destroy jellifish` runs, **Then** the confirmation prompt references "jellifish" (not the default container name).
3. **Given** a mocked `lxc` command that reports a container as stopped, **When** `dilxc.sh shell` runs, **Then** it exits with a non-zero status and an error message.
4. **Given** the container selection cascade (`@name`, `DILXC_CONTAINER`, `.dilxc` file, default), **When** each selection method is used, **Then** the correct container name is resolved per the spec.

---

### User Story 3 - Verify Setup Script Logic (Priority: P2)

A developer wants to verify that `setup-host.sh` correctly validates inputs, constructs LXD commands, and handles error conditions. Since setup creates real containers, these tests mock the `lxc` command to verify the script's logic — argument parsing, flag handling (`--fish`, `--deploy`), device configuration, and error paths — without touching real infrastructure.

**Why this priority**: `setup-host.sh` is run less frequently than `dilxc.sh` but its failures are more costly (requires delete-and-recreate). Testing its logic prevents misconfigurations.

**Independent Test**: Can be tested by sourcing setup-host.sh functions with mocked `lxc` commands and verifying correct argument handling and command construction.

**Acceptance Scenarios**:

1. **Given** `setup-host.sh` is invoked without required flags, **When** it parses arguments, **Then** it exits with a usage message and non-zero status.
2. **Given** the `--fish` flag is passed, **When** setup runs, **Then** it passes the `--fish` flag through to the provisioning script.
3. **Given** a `custom-provision.sh` exists in the repo root, **When** setup runs, **Then** it pushes the custom script to the container alongside the standard provisioning script.
4. **Given** a `custom-provision.sh` does not exist, **When** setup runs, **Then** it completes without error or warning about the missing file.

---

### User Story 4 - Verify Provisioning Script Logic (Priority: P2)

A developer wants to verify that `provision-container.sh` correctly handles its flags, writes the expected shell configurations, and invokes custom provisioning when present. Tests mock package installation commands and verify the script's structural logic — bash config generation, fish config generation (when `--fish` is passed), and custom script invocation.

**Why this priority**: Provisioning bugs cause containers to be misconfigured, requiring recreation. Testing config generation and flag handling prevents these issues.

**Independent Test**: Can be tested by running provisioning functions with mocked `apt-get`, `npm`, and system commands, verifying correct config file content and execution flow.

**Acceptance Scenarios**:

1. **Given** `provision-container.sh` runs without `--fish`, **When** it generates shell configuration, **Then** bash aliases and functions are written but no fish configuration is created.
2. **Given** `provision-container.sh` runs with `--fish`, **When** it generates shell configuration, **Then** both bash and fish configurations are written with equivalent aliases and functions.
3. **Given** `/tmp/custom-provision.sh` exists, **When** provisioning completes, **Then** the custom script is executed after standard provisioning.
4. **Given** `/tmp/custom-provision.sh` does not exist, **When** provisioning completes, **Then** no error is raised about the missing custom script.

---

### User Story 5 - Amend Constitution to Require TDD (Priority: P3)

The project constitution is updated to include a new principle requiring test-driven development for all future features. New specs must include testable acceptance scenarios, and implementation must include corresponding tests that verify behavior against the spec. This ensures the testing discipline established by this feature persists for all future work.

**Why this priority**: The constitution amendment is a governance change that supports the testing infrastructure. It depends on the testing framework being in place first (P1) so the TDD requirement is actionable.

**Independent Test**: Can be verified by reading the constitution and confirming it contains a TDD principle with clear expectations for when and how tests must be written.

**Acceptance Scenarios**:

1. **Given** the current constitution, **When** the amendment is applied, **Then** a new numbered principle requires tests for all new features.
2. **Given** the TDD principle, **When** a developer reads it, **Then** they understand that tests must verify spec behavior (acceptance scenarios), not just lock in current implementation.
3. **Given** the TDD principle, **When** a developer reads it, **Then** they understand which testing framework and patterns to use (as established by this feature).

---

### Edge Cases

- What happens when git submodules are not initialized? The test runner silently runs `git submodule update --init` before executing tests.
- What happens when a test file has a syntax error? The test framework reports the error with file and line number, and continues running other test files.
- What happens when a mock function is not cleaned up between tests? Each test runs in a subshell (bats-core default), so mock functions defined in one test do not leak into others.
- What happens when tests are run on macOS (different coreutils)? Tests that rely on GNU-specific flags should be documented. The primary target is Linux (Ubuntu), matching the project's host environment.
- What happens when a spec changes but the tests are not updated? The test should fail because it verifies spec behavior — any spec-implementation mismatch surfaces as a test failure, prompting an update.
- What happens when `dilxc.sh` is sourced for testing but it tries to resolve `CONTAINER_NAME` at the top level? Tests must handle the top-level container resolution by either mocking the resolution commands or sourcing only the function definitions.
- What happens when rsync exclude lists in bash config, fish config, and dilxc.sh fall out of sync? A dedicated test verifies that all three exclude lists contain the same entries.

## Clarifications

### Session 2026-02-13

- Q: What should the test runner script be named and how should it be invoked? → A: `./run-tests.sh` — standalone script at repo root, consistent with project's `*.sh` naming convention.
- Q: Should `run-tests.sh` auto-initialize missing submodules or error with instructions? → A: Auto-initialize silently — run `git submodule update --init` if submodules are missing, no message needed.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The repo MUST include a test framework (bats-core) and its assertion helpers (bats-support, bats-assert) as git submodules, so tests are runnable immediately after cloning with `--recurse-submodules`.
- **FR-002**: The repo MUST provide `run-tests.sh` at the repo root that initializes submodules if needed and executes all test files.
- **FR-003**: Tests MUST mock external commands (`lxc`, `docker`, `rsync`, `apt-get`, `npm`) so they run without real infrastructure and complete in seconds.
- **FR-004**: Tests for `dilxc.sh` MUST cover every subcommand's documented behavior including argument parsing, output messages, error conditions, and exit codes.
- **FR-005**: Tests for `setup-host.sh` MUST cover argument validation, flag handling, LXD command construction, and error paths.
- **FR-006**: Tests for `provision-container.sh` MUST cover flag handling (`--fish`), shell config generation, and custom provision script invocation.
- **FR-007**: Tests MUST verify behavior against spec acceptance scenarios, not merely assert current implementation behavior.
- **FR-008**: A test MUST verify that rsync exclude lists are consistent across bash config, fish config, and `dilxc.sh`.
- **FR-009**: Tests MUST produce TAP-compliant output for CI compatibility.
- **FR-010**: The project constitution MUST be amended to add a TDD principle requiring tests for all future features, with tests that verify spec-defined behavior.
- **FR-011**: The test directory structure MUST include shared helpers for common setup (loading assertion libraries, setting PROJECT_ROOT, defining reusable mock functions).
- **FR-012**: The test suite MUST be runnable by any user who clones the repo on a Linux system with bash and git, with no additional package installation required.

### Key Entities

- **Test Suite**: Collection of bats test files (`*.bats`) organized by script under test, located in a `test/` directory at the repo root.
- **Test Framework**: bats-core and its helper libraries (bats-support, bats-assert), included as git submodules under `test/`.
- **Mock Functions**: Bash functions that shadow external commands (lxc, docker, rsync) during tests, providing canned responses and recording invocations for assertion.
- **Test Runner**: `run-tests.sh` at the repo root — initializes submodules if needed and executes all test files.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: The full test suite runs and passes on a fresh clone (with submodules) on an Ubuntu system with no additional installation steps.
- **SC-002**: The test suite completes in under 30 seconds (all tests use mocked commands, no real infrastructure).
- **SC-003**: Every `dilxc.sh` subcommand has at least one test verifying its primary documented behavior.
- **SC-004**: Tests for the container selection cascade verify all four resolution methods (`@name`, `DILXC_CONTAINER`, `.dilxc` file, default).
- **SC-005**: The constitution contains a TDD principle that is clear enough for a new contributor to follow without additional guidance.
- **SC-006**: When a spec acceptance scenario is violated by a code change, at least one test fails — demonstrating spec-driven testing rather than implementation-locking.

## Assumptions

- bats-core is the testing framework. It is the most widely adopted bash testing framework with the largest community, lowest learning curve, and best CI integration. It is bash-native (matching the project's shell-scripts-only principle) and distributes cleanly via git submodules.
- Tests focus on unit and functional testing of script logic. Integration tests requiring real LXD containers are out of scope for this feature (they would require a dedicated CI environment with LXD).
- The scripts may need minor refactoring to be testable (e.g., guarding top-level execution behind a main guard so functions can be sourced independently). Such refactoring must preserve existing behavior.
- The `test/` directory and its contents are committed to the repo (not gitignored). Users who clone the repo get the tests.
- The constitution amendment adds a new principle; it does not modify existing principles.
- macOS compatibility for the test suite is not a requirement. The project targets Ubuntu homelab servers.

## Research

### Testing Framework Selection

Evaluated three frameworks for bash script testing:

| Criterion      | bats-core                       | ShellSpec                  | shunit2                  |
| -------------- | ------------------------------- | -------------------------- | ------------------------ |
| Community      | ~5,800 stars, largest ecosystem | ~1,300 stars               | ~1,600 stars, declining  |
| Maintenance    | Active (v1.13.0, Nov 2025)     | Active, single maintainer  | Minimal updates          |
| Built-in mocking | No (function overrides suffice) | Yes                      | No                       |
| Repo-friendly  | Git submodules (~600KB total)   | Git clone                  | Single file source       |
| CI integration | Official GitHub Action          | Good                       | Fair                     |

**Decision**: bats-core. Its bash-native syntax aligns with the project's shell-scripts-only principle, the git submodule distribution adds minimal weight, and the large community ensures contributors can find help easily.

### Mocking Strategy

For a project that wraps `lxc`, `docker`, and `rsync`, function overrides are the recommended approach:
- Define bash functions that shadow external commands in test `setup()`
- Functions record calls for assertion and return canned responses
- bats-core runs each `@test` in a subshell, providing natural mock isolation

### Testability Considerations

The scripts currently execute top-level code when sourced (e.g., `dilxc.sh` resolves `CONTAINER_NAME` at parse time). To make functions testable in isolation, the scripts may need a guard pattern so tests can source function definitions without triggering side effects.
