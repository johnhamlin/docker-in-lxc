# Implementation Plan: Shell Test Suite

**Branch**: `007-shell-test-suite` | **Date**: 2026-02-13 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/007-shell-test-suite/spec.md`

## Summary

Add a comprehensive bats-core test suite that verifies all three shell scripts behave according to their specs. The test framework and helpers are distributed as git submodules so tests are runnable immediately after cloning. Tests mock all external commands (`lxc`, `docker`, `rsync`, etc.) for fast, infrastructure-free execution. A single `run-tests.sh` at the repo root auto-initializes submodules and runs all tests. The project constitution is amended to require TDD for all future features.

## Technical Context

**Language/Version**: Bash (GNU Bash, Ubuntu 24.04 default)
**Primary Dependencies**: bats-core, bats-support, bats-assert (git submodules — no system packages)
**Storage**: N/A (shell scripts and test files only)
**Testing**: bats-core with TAP-compliant output
**Target Platform**: Linux (Ubuntu)
**Project Type**: single
**Performance Goals**: Full test suite completes in under 30 seconds
**Constraints**: No additional system packages beyond bash and git; no external mock libraries
**Scale/Scope**: 3 scripts under test (~30 subcommands in dilxc.sh alone), 6 prior specs defining testable behavior

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

### Pre-Design Check

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Shell Scripts Only | PASS | bats tests are bash scripts; submodules are bash-native |
| II. Three Scripts, Three Execution Contexts | JUSTIFIED VIOLATION | `run-tests.sh` is a new script. See Complexity Tracking below. |
| III. Readability Wins Over Cleverness | PASS | Tests use explicit names, no chained pipelines |
| IV. The Container Is the Sandbox | N/A | Tests run on developer machine, not in containers |
| V. Don't Touch the Host | N/A | Tests don't interact with LXD or host services |
| VI. LXD Today, Incus Eventually | PASS | Tests mock `lxc` commands; mocks are trivially changeable |
| VII. Idempotent Provisioning | N/A | Tests don't provision anything |
| VIII. Detect and Report, Don't Auto-Fix | JUSTIFIED TENSION | `run-tests.sh` auto-initializes submodules. See Complexity Tracking below. |
| IX. Shell Parity: Bash Always, Fish Opt-In | PASS | Tests verify bash/fish config equivalence (FR-008) |
| X. Error Handling | PASS | `run-tests.sh` uses `set -euo pipefail`; `dilxc.sh` does not (per principle) |
| XI. Rsync Excludes Stay Synchronized | PASS | FR-008 adds an explicit test verifying sync across all three locations |
| XII. Keep Arguments Safe | PASS | Tests verify `printf %q` escaping in claude-run and docker passthrough |

### Post-Design Check

All gates pass. No new violations introduced during design. The two justified items (Principle II, VIII) are documented in Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/007-shell-test-suite/
├── plan.md              # This file
├── research.md          # Phase 0: framework selection, mock strategy, testability
├── data-model.md        # Phase 1: test entities and relationships
├── quickstart.md        # Phase 1: how to run and write tests
└── tasks.md             # Phase 2 output (/speckit.tasks command)
```

### Source Code (repository root)

```text
run-tests.sh                              # Test runner — auto-inits submodules, runs all tests
test/
├── bats/                                 # [submodule] bats-core test runner
├── test_helper/
│   ├── bats-support/                     # [submodule] assertion support library
│   ├── bats-assert/                      # [submodule] assertion functions
│   └── common-setup.bash                 # Shared: load libs, PROJECT_ROOT, mock helpers
├── dilxc.bats                            # Tests for dilxc.sh (~30 subcommands)
├── setup-host.bats                       # Tests for setup-host.sh
└── provision-container.bats              # Tests for provision-container.sh
```

**Structure Decision**: Flat `test/` directory at repo root. One `.bats` file per script under test. No subdirectories for test categories — all tests are unit/functional (integration tests requiring real LXD are out of scope). Submodules under `test/` keep test dependencies self-contained.

## Script Testability Strategy

### dilxc.sh — Main Guard Refactoring (REQUIRED)

**Current state**: Container name resolution (the `@name`/env/`.dilxc`/default cascade near the top), `SCRIPT_DIR` initialization, and case dispatch (the `case "${1:-help}" in` block at the bottom) all execute at top level. The script cannot be sourced without triggering side effects.

**Change**: Wrap all imperative code in a main guard. Function definitions remain outside.

```bash
#!/bin/bash

# --- All function definitions (usage, helpers, cmd_* functions) ---
# These are defined but not called when sourced.

# --- Main guard ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  # Container name resolution cascade
  if [[ "${1:-}" == @* ]]; then
    CONTAINER_NAME="${1#@}"
    shift
  elif [[ -n "${DILXC_CONTAINER:-}" ]]; then
    CONTAINER_NAME="$DILXC_CONTAINER"
  else
    _dir="$PWD"
    while [[ "$_dir" != "/" ]]; do
      if [[ -f "$_dir/.dilxc" ]]; then
        CONTAINER_NAME=$(head -1 "$_dir/.dilxc")
        break
      fi
      _dir=$(dirname "$_dir")
    done
    unset _dir
    CONTAINER_NAME="${CONTAINER_NAME:-docker-lxc}"
  fi

  SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

  # Dispatch
  case "${1:-help}" in
    # ... existing dispatch ...
  esac
fi
```

**Impact**: Zero behavior change when script is executed directly. When sourced (by tests), only function definitions are loaded. Tests set `CONTAINER_NAME` and `SCRIPT_DIR` explicitly.

### setup-host.sh — No Refactoring

**Testing approach**: Black-box via `run` with PATH-based mocking. The script uses `set -euo pipefail` and is entirely imperative — sourcing it would fail. Tests create mock executables for `lxc`, `snap`, `lxc` etc. in a temp directory prepended to PATH.

### provision-container.sh — No Refactoring

**Testing approach**: Same as setup-host.sh. Mock `apt-get`, `npm`, `curl`, `su`, `systemctl`, `chsh`, `usermod`. Use temp directories for config file output assertions.

## Mock Framework Design

### Core Pattern

Every test gets an isolated mock environment via `common-setup.bash`:

```bash
_common_setup() {
    load 'test_helper/bats-support/load'
    load 'test_helper/bats-assert/load'
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." >/dev/null 2>&1 && pwd)"
    PATH="$PROJECT_ROOT:$PATH"
    MOCK_BIN="$BATS_TEST_TMPDIR/mock-bin"
    mkdir -p "$MOCK_BIN"
    PATH="$MOCK_BIN:$PATH"
}
```

### Mock Creation Helpers

```bash
create_mock()               # cmd [exit_code] — records calls, returns exit code
create_mock_with_output()   # cmd output [exit_code] — records calls, prints output
```

Mocks write `"$@"` to `$BATS_TEST_TMPDIR/<cmd>.calls`, one line per invocation.

### Assertion Helpers

```bash
assert_mock_called <cmd>           # At least one invocation recorded
assert_mock_not_called <cmd>       # No invocations recorded
assert_mock_called_with <cmd> <args>  # Specific invocation line exists in call log
```

### Conditional Mocks

For commands needing different responses per subcommand (e.g., `lxc info` vs `lxc exec`), tests write custom mock scripts with `case` dispatch:

```bash
cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/bin/bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info)  echo "Status: RUNNING" ;;
    list)  echo "NAME,STATUS\ntest-container,RUNNING" ;;
esac
MOCK
chmod +x "$MOCK_BIN/lxc"
```

## Test Coverage Map

### dilxc.sh Tests (P1) — Source and Call Functions (except container name resolution)

> **Note**: Most dilxc.sh tests source the script and call `cmd_*` functions directly. The exception is container name resolution (T006), which must run dilxc.sh as a command (black-box) because the resolution cascade is inside the main guard.

| Spec Area | Key Tests |
|-----------|-----------|
| Container name resolution (003) | `@name` prefix, `DILXC_CONTAINER` env, `.dilxc` file walk-up, default fallback, precedence |
| Lifecycle: start/stop/restart (001) | Calls `lxc start/stop/restart`, require_running checks, output messages |
| shell/root (001) | TTY flag, user context, require_running |
| claude/claude-resume/claude-run (001) | TTY flags, `--dangerously-skip-permissions`, prompt escaping via `printf %q` |
| sync (001) | rsync exclude list, source→dest paths |
| exec (001) | Command passthrough, require_running |
| pull/push (001) | File transfer direction, path handling |
| snapshot/restore/snapshots (001) | Snapshot naming, auto-timestamp, restore + restart |
| destroy (001) | Confirmation prompt with correct container name, deletion |
| status (001) | Container info display |
| health-check (001) | Multi-check pass/fail reporting |
| docker (001) | Argument escaping via `printf %q` |
| login (001) | TTY allocation |
| proxy add/list/rm (002) | Port validation, device creation, listing, removal, `rm all` |
| containers (003) | List formatting, active marker |
| update (003) | Git pull, auth device setup |
| init (003) | Delegation to setup-host.sh |
| customize (005) | File creation, editor invocation |
| git-auth (004) | SSH agent check, gh auth check, remediation messages |
| ensure_auth_forwarding (004) | SSH agent device update, gh config mount |
| Rsync exclude sync (cross-cutting) | FR-008: verify bash, fish, and dilxc.sh exclude lists match |

### setup-host.sh Tests (P2) — Black-Box with Mocks

| Spec Area | Key Tests |
|-----------|-----------|
| Argument parsing | Missing `-p` → error, unknown flag → error, `-h` → usage |
| Flag handling | `--fish` passed through to provisioning, `--deploy` creates mount |
| Container creation | `lxc launch` with correct image, security flags |
| Device mounts | project (read-only, shift=true), deploy (optional), ssh-agent, gh-config |
| Custom provision | Detected and pushed when present, silently skipped when absent |
| Provisioning execution | Script pushed, chmod'd, executed with flags |
| Snapshot | `clean-baseline` snapshot created |
| .dilxc file | Written to project path with container name |

### provision-container.sh Tests (P2) — Black-Box with Mocks

| Spec Area | Key Tests |
|-----------|-----------|
| Flag handling | Without `--fish`: bash only; with `--fish`: bash + fish |
| Bash config | Aliases (cc, cc-resume, cc-prompt), sync-project function, deploy function, PATH, SSH_AUTH_SOCK |
| Fish config | Equivalent abbreviations, functions, PATH, SSH_AUTH_SOCK (only when `--fish`) |
| Custom provision | `/tmp/custom-provision.sh` executed when present, skipped when absent |
| Package installation | Correct apt-get/npm calls (verified via mock recordings) |

## Constitution Amendment (P3)

Add **Principle XIII: Test-Driven Development** to the constitution:

- All new features MUST include tests that verify spec-defined acceptance scenarios
- Tests MUST use the bats-core framework established by this feature
- Tests MUST verify behavior against specs, not merely lock in current implementation
- Bug fixes SHOULD include a regression test demonstrating the fix

This is a MINOR version bump (1.0.0 → 1.1.0) per the constitution's governance rules.

## Complexity Tracking

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| `run-tests.sh` — new script (Principle II) | Test runner is a genuinely new execution context: development tooling that runs on a developer's machine. It doesn't manage containers, provision software, or wrap LXD — it runs tests. | Users could invoke `test/bats/bin/bats test/` directly, but this fails to auto-initialize submodules (violating FR-002) and is not discoverable. |
| `run-tests.sh` auto-inits submodules (Principle VIII) | Spec explicitly requires silent auto-initialization (US1, AS2). The principle governs container management scripts where auto-fixing can cause data loss — auto-initializing git submodules is safe, reversible, and expected developer tooling behavior. | Could error with "run `git submodule update --init`" instructions, but spec explicitly rejects this approach. |
