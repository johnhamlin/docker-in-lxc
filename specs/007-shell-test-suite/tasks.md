# Tasks: Shell Test Suite

**Input**: Design documents from `/specs/007-shell-test-suite/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, contracts/testing-conventions.md, quickstart.md

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story. The entire feature IS about writing tests, so tests are the primary deliverable — there is no separate "test vs implementation" distinction.

**Prior spec references**: Tasks reference prior feature specs by number (e.g., "spec 003", "spec 001-US5"). These are located at `specs/<NNN>-*/spec.md` in the repository.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Initialize test framework, directory structure, and shared helpers

- [X] T001 Add bats-core, bats-support, and bats-assert as git submodules at test/bats/, test/test_helper/bats-support/, and test/test_helper/bats-assert/
- [X] T002 Create test/test_helper/common-setup.bash with `_common_setup()` (load bats libs, set PROJECT_ROOT, create MOCK_BIN on PATH), `create_mock()`, `create_mock_with_output()`, `assert_mock_called()`, `assert_mock_not_called()`, and `assert_mock_called_with()` per contracts/testing-conventions.md
- [X] T003 Create run-tests.sh at repo root — set -euo pipefail, auto-initialize submodules if test/bats/bin/bats is missing. When args are provided, pass them directly to bats (supports running individual files: `./run-tests.sh test/dilxc.bats`). When no args, invoke bats on test/ directory (all tests).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Make dilxc.sh sourceable for testing — MUST complete before any dilxc.sh tests can source functions

**CRITICAL**: No dilxc.sh test work can begin until this phase is complete

- [X] T004 Add main guard to dilxc.sh — wrap container name resolution (lines 12-29), SCRIPT_DIR initialization (line 31), and case dispatch (lines 695-725) inside `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then ... fi`, keeping all function definitions outside the guard. Verify script behavior is unchanged when executed directly.

**Checkpoint**: Framework installed, helpers ready, dilxc.sh sourceable — test authoring can begin

---

## Phase 3: User Story 1 - Run Tests After Cloning the Repo (Priority: P1) MVP

**Goal**: A user clones the repo and runs `./run-tests.sh` from the root — tests execute with clear pass/fail TAP output, no extra packages needed.

**Independent Test**: Clone the repo with `--recurse-submodules`, run `./run-tests.sh`, verify TAP-formatted pass/fail output appears.

- [X] T005 [US1] Create test/dilxc.bats with setup() that loads common-setup, sources dilxc.sh, and sets CONTAINER_NAME="test-container" and SCRIPT_DIR="$PROJECT_ROOT". Add initial smoke tests: help/usage output works, unknown subcommand shows usage. Verify `./run-tests.sh` produces TAP output and exits 0.

**Checkpoint**: `./run-tests.sh` runs end-to-end on a fresh clone. US1 acceptance scenarios verified. MVP deliverable.

---

## Phase 4: User Story 2 - Verify CLI Commands Match Spec Behavior (Priority: P1)

**Goal**: Every dilxc.sh subcommand has tests verifying its documented spec behavior — argument parsing, output, error handling, exit codes — with mocked external commands.

**Independent Test**: Run `./run-tests.sh test/dilxc.bats` and verify all subcommand tests pass with mocked lxc/docker/rsync.

- [X] T006 [US2] Add container name resolution tests to test/dilxc.bats — run dilxc.sh as a command (not sourced) to test the main guard's resolution cascade: @name prefix sets CONTAINER_NAME, DILXC_CONTAINER env var is used, .dilxc file walk-up from subdirectory works, default "docker-lxc" fallback, and @name takes precedence over env var (spec 003 acceptance scenarios)
- [X] T007 [US2] Add helper function and lifecycle tests to test/dilxc.bats — require_container exits with error when container doesn't exist, require_running exits with error when container is stopped (spec 001-US6-AS3), cmd_start/cmd_stop/cmd_restart call correct lxc commands, cmd_status shows container info, cmd_destroy confirmation prompt references correct container name (spec 007-US2-AS2 "jellifish" test)
- [X] T008 [US2] Add interactive command tests to test/dilxc.bats — cmd_shell/cmd_root pass -t flag for TTY and correct user, cmd_login allocates TTY, cmd_claude passes --dangerously-skip-permissions, cmd_claude_resume passes --resume flag, cmd_claude_run escapes prompt via printf %q (spec 001-US2 acceptance scenarios)
- [X] T009 [US2] Add file operation tests to test/dilxc.bats — cmd_sync calls rsync with --exclude=node_modules --exclude=.git --exclude=dist --exclude=build and correct source/dest paths, cmd_exec passes through arbitrary commands with require_running check, cmd_pull transfers from container to host, cmd_push transfers from host to container (spec 001-US5 acceptance scenarios)
- [X] T010 [US2] Add snapshot tests to test/dilxc.bats — cmd_snapshot with explicit name calls lxc snapshot with that name, cmd_snapshot without name generates timestamp, cmd_restore calls lxc restore then restarts container, cmd_snapshots calls lxc info to list snapshots (spec 001-US4 acceptance scenarios)
- [X] T011 [US2] Add docker and proxy tests to test/dilxc.bats — cmd_docker escapes arguments via printf %q (spec 001-US7-AS2), cmd_proxy_add validates port range 1-65535 and creates lxc proxy device, cmd_proxy_add with two args maps container:arg1 to host:arg2, cmd_proxy_list formats output, cmd_proxy_rm removes single proxy, cmd_proxy_rm "all" removes all proxies (spec 002 acceptance scenarios)
- [X] T012 [US2] Add utility command tests to test/dilxc.bats — cmd_containers lists containers with active marker for current CONTAINER_NAME (spec 003-US5), cmd_update runs git pull and calls ensure_auth_forwarding (spec 003-US4), cmd_init delegates to setup-host.sh via exec (spec 003-US2), cmd_customize creates custom-provision.sh template when absent and opens editor (spec 005-US2), cmd_health checks network/docker/claude/dirs and reports pass/fail (spec 001-US9)
- [X] T013 [US2] Add git-auth and ensure_auth_forwarding tests to test/dilxc.bats — cmd_git_auth reports SSH agent status and gh auth status with remediation messages on failure (spec 004-US3), ensure_auth_forwarding updates ssh-agent device connect path and adds gh-config device when ~/.config/gh exists (spec 004-US4)

**Checkpoint**: Every dilxc.sh subcommand has at least one spec-driven test (SC-003). Container selection cascade verified (SC-004).

---

## Phase 5: User Story 3 - Verify Setup Script Logic (Priority: P2)

**Goal**: Tests verify setup-host.sh argument validation, flag handling, LXD command construction, and error paths using mocked commands.

**Independent Test**: Run `./run-tests.sh test/setup-host.bats` and verify all tests pass.

- [X] T014 [P] [US3] Create test/setup-host.bats with setup() that loads common-setup and creates comprehensive mocks (lxc, snap, ping, sleep, readlink, dirname, git, lxc) plus a temp directory for PROJECT_PATH. Add argument parsing tests: no args exits with "project path is required" error, unknown flag exits with error, -h shows usage (spec 007-US3-AS1)
- [X] T015 [US3] Add flag handling and LXD command tests to test/setup-host.bats — --fish flag passed through to provisioning script execution (spec 007-US3-AS2), --deploy flag creates deploy disk device, --name sets container name, lxc launch called with ubuntu:24.04 image and security.nesting=true (spec 001-US1)
- [X] T016 [US3] Add device mount and provisioning tests to test/setup-host.bats — project device has readonly=true and shift=true, deploy device optional (only with --deploy), ssh-agent proxy device created, gh-config disk device created when ~/.config/gh exists, custom-provision.sh pushed when present (spec 007-US3-AS3), silently skipped when absent (spec 007-US3-AS4)
- [X] T017 [US3] Add completion tests to test/setup-host.bats — lxc snapshot "clean-baseline" called, .dilxc file written to PROJECT_PATH with container name

**Checkpoint**: setup-host.sh logic verified without real infrastructure.

---

## Phase 6: User Story 4 - Verify Provisioning Script Logic (Priority: P2)

**Goal**: Tests verify provision-container.sh flag handling, shell config generation, and custom script invocation using mocked system commands.

**Independent Test**: Run `./run-tests.sh test/provision-container.bats` and verify all tests pass.

- [X] T018 [P] [US4] Create test/provision-container.bats with setup() that loads common-setup and creates comprehensive mocks (apt-get, npm, curl, su, systemctl, usermod, chsh, mkdir, chown, gpg, tee). Do NOT mock cat or bash — these are used internally by bats-core and mocking them will break the test runner. Set up temp HOME and filesystem for config file assertions. Add flag handling tests: without --fish no fish config written (spec 007-US4-AS1), with --fish both configs written (spec 007-US4-AS2)
- [X] T019 [US4] Add bash config content tests to test/provision-container.bats — verify .bashrc contains aliases (cc, cc-resume, cc-prompt), sync-project function with rsync excludes (node_modules, .git, dist, build), deploy function, PATH includes ~/.local/bin, SSH_AUTH_SOCK set to /tmp/ssh-agent.sock
- [X] T020 [US4] Add fish config and custom provision tests to test/provision-container.bats — fish config has equivalent abbreviations and functions when --fish passed, custom-provision.sh executed when /tmp/custom-provision.sh exists (spec 007-US4-AS3), no error when absent (spec 007-US4-AS4)

**Checkpoint**: provision-container.sh logic verified without real system modifications.

---

## Phase 7: User Story 5 - Amend Constitution to Require TDD (Priority: P3)

**Goal**: Constitution updated with a TDD principle that is clear enough for a new contributor to follow.

**Independent Test**: Read the constitution and confirm Principle XIII exists with clear framework, pattern, and expectation guidance.

- [X] T021 [P] [US5] Add Principle XIII (Test-Driven Development) to .specify/memory/constitution.md — all new features MUST include bats-core tests verifying spec-defined acceptance scenarios, tests MUST verify behavior not lock in implementation, bug fixes SHOULD include regression tests. Bump version 1.0.0 → 1.1.0. Update Sync Impact Report header.
- [X] T022 [P] [US5] Update CLAUDE.md: add a "Testing" section (after Editing Notes) documenting how to run tests (`./run-tests.sh`), that the framework is bats-core with submodules, and that all future features must include tests verifying spec-defined acceptance scenarios per Constitution Principle XIII

**Checkpoint**: Constitution Principle XIII is actionable for new contributors (SC-005).

---

## Phase 8: Polish & Cross-Cutting Concerns

**Purpose**: Cross-cutting tests and final validation

- [X] T023 Add rsync exclude sync test (FR-008) to test/dilxc.bats — extract exclude lists from dilxc.sh cmd_sync, provision-container.sh bash sync-project, and provision-container.sh fish sync-project, assert all three contain identical entries (node_modules, .git, dist, build)
- [X] T024 Run full test suite via ./run-tests.sh and verify all tests pass, output is TAP-compliant, and suite completes under 30 seconds (SC-001, SC-002, SC-006)
- [X] T025 Update .gitattributes to exclude test/bats/, test/test_helper/bats-support/, test/test_helper/bats-assert/ from git archive exports if applicable

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 (T001-T003) — BLOCKS all dilxc.sh tests
- **US1 (Phase 3)**: Depends on Phase 2 (T004) — creates first test file
- **US2 (Phase 4)**: Depends on Phase 3 (T005) — adds tests to existing dilxc.bats
- **US3 (Phase 5)**: Depends on Phase 1 only (T001-T003) — creates separate test file, does NOT need T004
- **US4 (Phase 6)**: Depends on Phase 1 only (T001-T003) — creates separate test file, does NOT need T004
- **US5 (Phase 7)**: No code dependencies — can start after Phase 1 if desired, but logically follows test suite completion
- **Polish (Phase 8)**: Depends on all user stories being complete

### User Story Dependencies

- **US1 (P1)**: Depends on Setup + Foundational — enables all other stories
- **US2 (P1)**: Depends on US1 (test file exists) — sequential within dilxc.bats
- **US3 (P2)**: Independent of US2 — different test file, can start after Phase 1
- **US4 (P2)**: Independent of US2 and US3 — different test file, can start after Phase 1
- **US5 (P3)**: Independent of all test stories — constitution/docs only

### Within Each User Story

- US2: Tasks T006-T013 are sequential (same file: test/dilxc.bats)
- US3: Tasks T014-T017 are sequential (same file: test/setup-host.bats)
- US4: Tasks T018-T020 are sequential (same file: test/provision-container.bats)
- US5: Tasks T021-T022 can run in parallel (different files)

### Parallel Opportunities

- After Phase 1 completes: US3 (T014) and US4 (T018) can start in parallel with Phase 2
- After Phase 2 completes: US1/US2 work begins, US3/US4 may already be in progress
- US5 tasks T021 and T022 are parallelizable (different files)
- US3 and US4 are fully independent and can run in parallel throughout

---

## Parallel Example: After Phase 1

```
Agent A (sequential):           Agent B (parallel):          Agent C (parallel):
  Phase 2: T004 (main guard)     US3: T014 → T015 → T016     US4: T018 → T019 → T020
  Phase 3: T005 (US1 MVP)                    → T017
  Phase 4: T006 → T007 → ...
```

---

## Implementation Strategy

### MVP First (US1 Only)

1. Complete Phase 1: Setup (T001-T003)
2. Complete Phase 2: Foundational (T004)
3. Complete Phase 3: US1 (T005)
4. **STOP and VALIDATE**: Run `./run-tests.sh` — should produce TAP output with passing smoke tests
5. Commit and verify on fresh clone

### Incremental Delivery

1. Setup + Foundational → Framework ready
2. US1 → Smoke tests pass → **MVP commit**
3. US2 → Full dilxc.sh coverage → **Major milestone commit**
4. US3 + US4 (parallel) → All three scripts covered → **Feature-complete commit**
5. US5 → Constitution amended → **Governance commit**
6. Polish → Cross-cutting tests, final validation → **Release-ready**

### Suggested Commit Points

- After T005: "feat: add bats-core test framework with smoke tests"
- After T013: "feat: comprehensive dilxc.sh spec-driven tests"
- After T017: "feat: setup-host.sh spec-driven tests"
- After T020: "feat: provision-container.sh spec-driven tests"
- After T022: "feat: amend constitution with TDD principle (XIII)"
- After T025: "feat: cross-cutting tests and polish"

---

## Notes

- [P] tasks = different files, no dependencies on incomplete tasks
- [Story] label maps task to specific user story for traceability
- Each user story is independently testable via `./run-tests.sh test/<file>.bats`
- All dilxc.sh tests (US2) are in one file and must be sequential
- US3 and US4 are fully parallelizable with each other and with US2
- Commit after each checkpoint to maintain rollback safety
