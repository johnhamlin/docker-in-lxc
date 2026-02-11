# Tasks: LXD Sandbox for Autonomous Claude Code

**Input**: Design documents from `/specs/001-baseline-spec/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/

**Context**: This is a baseline spec — the system is already built. Tasks validate the existing implementation against the specification, contracts, and constitution principles. Each task audits code and/or runs an acceptance scenario.

**Tests**: Not requested. No test framework (Decision 7 in research.md).

**Organization**: Tasks are grouped by user story to enable independent validation of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup (Project Structure Validation)

**Purpose**: Verify project structure matches plan.md and all scripts exist

- [ ] T001 Validate project structure matches plan.md layout — verify `setup-host.sh`, `provision-container.sh`, `sandbox.sh`, `CLAUDE.md`, and `.gitignore` exist at repository root
- [ ] T002 [P] Verify `setup-host.sh` uses `set -euo pipefail` and `#!/bin/bash` per contracts/setup-host.md
- [ ] T003 [P] Verify `provision-container.sh` uses `set -euo pipefail` and `#!/bin/bash` per contracts/provision.md
- [ ] T004 [P] Verify `sandbox.sh` uses `#!/bin/bash` and per-command error handling (no `set -e`) per contracts/sandbox.md

---

## Phase 2: Foundational (Cross-Script Compliance)

**Purpose**: Validate constitution principles and cross-cutting concerns that apply to ALL user stories

**CRITICAL**: These checks underpin every user story — failures here indicate systemic issues

- [ ] T005 [P] Validate rsync exclude list parity (Constitution XI) — confirm `node_modules`, `.git`, `dist`, `build` are excluded identically in `sandbox.sh` `cmd_sync`, bash `sync-project` function, and fish `sync-project` function within `provision-container.sh`
- [ ] T006 [P] Validate argument escaping (Constitution XII) — verify `printf '%q'` usage in `sandbox.sh` for `cmd_claude_run`, `cmd_exec`, and `cmd_docker` subcommands
- [ ] T007 [P] Validate TTY allocation — verify `-t` flag on `lxc exec` for interactive commands (`shell`, `root`, `login`, `claude`, `claude-resume`) in `sandbox.sh`
- [ ] T008 [P] Validate precondition helpers — verify `require_container` and `require_running` functions exist in `sandbox.sh` and are called before relevant subcommands per contracts/sandbox.md
- [ ] T009 [P] Validate verbose output (FR-023) — confirm all three scripts produce step-by-step progress to stdout and errors to stderr
- [ ] T010 Validate shell parity (Constitution IX) — verify bash config block and fish config block in `provision-container.sh` define identical aliases/abbreviations, functions, and PATH entries per contracts/provision.md

**Checkpoint**: All cross-cutting concerns validated — user story validation can proceed

---

## Phase 3: User Story 1 — Create a New Sandbox (Priority: P1) MVP

**Goal**: Verify `setup-host.sh` and `provision-container.sh` create a fully functional sandbox from scratch

**Independent Test**: Run `setup-host.sh` with a test project directory, verify container exists with correct mounts, tooling, and baseline snapshot

### Validation for User Story 1

- [ ] T011 [US1] Validate `setup-host.sh` argument parsing — verify `-n`, `-p`, `-d`, `--fish`, `-h` flags match contracts/setup-host.md options table
- [ ] T012 [P] [US1] Validate container creation in `setup-host.sh` — verify `lxc launch ubuntu:24.04` with `security.nesting=true` (FR-001)
- [ ] T013 [P] [US1] Validate network wait in `setup-host.sh` — verify 30-second timeout with nonzero exit on failure (FR-019, Acceptance 1.4)
- [ ] T014 [US1] Validate project mount in `setup-host.sh` — verify read-only disk device at `/home/ubuntu/project-src` with source path validation (FR-002, Acceptance 1.1)
- [ ] T015 [P] [US1] Validate deploy mount in `setup-host.sh` — verify optional read-write disk device at `/mnt/deploy` (FR-018, Acceptance 1.3)
- [ ] T016 [US1] Validate provisioning push in `setup-host.sh` — verify `provision-container.sh` is pushed and executed inside container (step 5/6 per contract)
- [ ] T017 [US1] Validate `provision-container.sh` installation sequence — verify Docker CE, Node.js 22, Claude Code, uv, Spec Kit, dev tools installed in order per contracts/provision.md
- [ ] T018 [P] [US1] Validate git defaults in `provision-container.sh` — verify `init.defaultBranch=main`, sandbox user identity per contracts/provision.md (FR-017)
- [ ] T019 [US1] Validate bash config in `provision-container.sh` — verify aliases (`cc`, `cc-resume`, `cc-prompt`), functions (`sync-project`, `deploy`), and PATH per contracts/provision.md (FR-005)
- [ ] T020 [US1] Validate fish config in `provision-container.sh` — verify `--fish` flag triggers fish install, abbreviations, functions, PATH, and `chsh` per contracts/provision.md (FR-016, Acceptance 1.2)
- [ ] T021 [US1] Validate baseline snapshot in `setup-host.sh` — verify `clean-baseline` snapshot is taken after successful provisioning (FR-007)
- [ ] T022 [P] [US1] Validate idempotent GPG key in `provision-container.sh` — verify `gpg --dearmor --yes` for Docker repo key (FR-022)
- [ ] T023 [US1] Acceptance test: Run `setup-host.sh -n test-sandbox -p <test-dir>` end-to-end and verify container exists, mounts correct, tooling installed, `clean-baseline` snapshot present (Acceptance 1.1)

**Checkpoint**: User Story 1 validated — sandbox creation works as specified

---

## Phase 4: User Story 2 — Run Claude Code Autonomously (Priority: P1)

**Goal**: Verify `sandbox.sh` Claude commands launch Claude Code with correct flags in the correct directory

**Independent Test**: Start an interactive Claude session and a one-shot prompt, verify both operate in `/home/ubuntu/project` with `--dangerously-skip-permissions`

### Validation for User Story 2

- [ ] T024 [US2] Validate `cmd_claude` in `sandbox.sh` — verify interactive Claude Code starts in `/home/ubuntu/project` with `--dangerously-skip-permissions` and TTY (FR-005, FR-010, Acceptance 2.1)
- [ ] T025 [US2] Validate `cmd_claude_run` in `sandbox.sh` — verify one-shot prompt execution with `printf %q` escaping in project directory (FR-011, Acceptance 2.2)
- [ ] T026 [US2] Validate `cmd_claude_resume` in `sandbox.sh` — verify session resume with `--resume` flag and TTY (Acceptance 2.3)
- [ ] T027 [US2] Acceptance test: Run `sandbox.sh claude-run "fix the tests in src/api/ and run 'npm test' -- --grep \"auth module\""` and verify it executes non-interactively with correct working directory and the prompt passes through with quotes and spaces intact (Acceptance 2.2, SC-007)

**Checkpoint**: User Story 2 validated — Claude Code runs autonomously as specified

---

## Phase 5: User Story 3 — Authenticate Claude Code (Priority: P1)

**Goal**: Verify authentication pathways (browser OAuth and API key injection)

**Independent Test**: Run `sandbox.sh login` and verify Claude Code can start a session afterward

### Validation for User Story 3

- [ ] T028 [US3] Validate `cmd_login` in `sandbox.sh` — verify interactive Claude Code session with TTY for browser OAuth flow (FR-012, Acceptance 3.1)
- [ ] T029 [US3] Validate API key injection in `setup-host.sh` — verify `ANTHROPIC_API_KEY` env var is written into container shell config when set (FR-012, Acceptance 3.2)
- [ ] T030 [P] [US3] Validate API key written to bash config in `provision-container.sh` — verify export statement appended to `.bashrc` when API key is passed
- [ ] T031 [P] [US3] Validate API key written to fish config in `provision-container.sh` — verify `set -gx` in fish config when API key is passed and `--fish` is used

**Checkpoint**: User Story 3 validated — both auth methods work as specified

---

## Phase 6: User Story 4 — Snapshot and Rollback (Priority: P2)

**Goal**: Verify snapshot creation, listing, and restoration with auto-restart

**Independent Test**: Take a snapshot, make changes, restore, verify changes reverted

### Validation for User Story 4

- [ ] T032 [US4] Validate `cmd_snapshot` in `sandbox.sh` — verify named snapshot creation via `lxc snapshot` (FR-008, Acceptance 4.1)
- [ ] T033 [US4] Validate auto-generated snapshot name in `sandbox.sh` — verify `snap-YYYYMMDD-HHMMSS` format when no name provided (FR-008, Acceptance 4.2)
- [ ] T034 [US4] Validate `cmd_restore` in `sandbox.sh` — verify snapshot restoration with automatic container restart (FR-009, Acceptance 4.3)
- [ ] T035 [P] [US4] Validate `cmd_snapshots` in `sandbox.sh` — verify snapshot listing output (Acceptance 4.4)
- [ ] T036 [US4] Validate restore error handling — verify missing snapshot name shows available snapshots (per contracts/sandbox.md)
- [ ] T037 [US4] Acceptance test: Take snapshot, create a file in container, restore, verify file is gone and container is running (SC-003)

**Checkpoint**: User Story 4 validated — snapshot/rollback works as specified

---

## Phase 7: User Story 5 — Sync and File Transfer (Priority: P2)

**Goal**: Verify sync, pull, push, and deploy operations with correct exclusions

**Independent Test**: Modify host project, run sync, verify writable copy updated with correct exclusions

### Validation for User Story 5

- [ ] T038 [US5] Validate `cmd_sync` in `sandbox.sh` — verify rsync with `--delete` from `project-src/` to `project/` with 4 excludes (FR-006, Acceptance 5.1)
- [ ] T039 [P] [US5] Validate `cmd_pull` in `sandbox.sh` — verify `lxc file pull -r` from container to host with default dest `.` (FR-021, Acceptance 5.2)
- [ ] T040 [P] [US5] Validate `cmd_push` in `sandbox.sh` — verify `lxc file push` from host to container with default dest `/home/ubuntu/project/` (FR-021, Acceptance 5.3)
- [ ] T041 [US5] Validate bash `sync-project` function in `provision-container.sh` — verify same rsync command and excludes as `cmd_sync` (FR-006, Acceptance 5.4)
- [ ] T042 [US5] Validate bash `deploy` function in `provision-container.sh` — verify rsync to `/mnt/deploy` with mount check (FR-018, Acceptance 5.5)
- [ ] T043 [US5] Acceptance test: Add a file on host, run `sandbox.sh sync`, verify file appears in `/home/ubuntu/project` and `node_modules`/`.git` are excluded (SC-004)

**Checkpoint**: User Story 5 validated — sync and file transfer work as specified

---

## Phase 8: User Story 6 — Container Lifecycle Management (Priority: P2)

**Goal**: Verify start, stop, restart, status, shell, root, and destroy commands

**Independent Test**: Cycle through start/stop/restart/status/destroy and verify each produces expected state

### Validation for User Story 6

- [ ] T044 [P] [US6] Validate `cmd_start` in `sandbox.sh` — verify `lxc start` with `require_container` precondition (Acceptance 6.1)
- [ ] T045 [P] [US6] Validate `cmd_stop` in `sandbox.sh` — verify `lxc stop` with `require_running` precondition (Acceptance 6.2)
- [ ] T046 [P] [US6] Validate `cmd_restart` in `sandbox.sh` — verify `lxc restart` with `require_running` precondition (Acceptance 6.3)
- [ ] T047 [P] [US6] Validate `cmd_status` in `sandbox.sh` — verify container info, IP address, and snapshot listing (Acceptance 6.4)
- [ ] T048 [P] [US6] Validate `cmd_shell` in `sandbox.sh` — verify bash shell as `ubuntu` user with TTY via `su - ubuntu` (FR-010, Acceptance 6.5)
- [ ] T049 [P] [US6] Validate `cmd_root` in `sandbox.sh` — verify root shell with TTY (Acceptance 6.6)
- [ ] T050 [US6] Validate `cmd_destroy` in `sandbox.sh` — verify confirmation prompt before `lxc delete` (FR-020, Acceptance 6.7)
- [ ] T051 [US6] Validate `cmd_exec` in `sandbox.sh` — verify command execution in `/home/ubuntu/project` with `printf %q` escaping (FR-011)

**Checkpoint**: User Story 6 validated — lifecycle management works as specified

---

## Phase 9: User Story 7 — Docker Inside the Sandbox (Priority: P3)

**Goal**: Verify Docker passthrough and log commands

**Independent Test**: Run `sandbox.sh docker run hello-world` and verify Docker operates correctly

### Validation for User Story 7

- [ ] T052 [US7] Validate `cmd_docker` in `sandbox.sh` — verify Docker command passthrough with `printf %q` escaping (FR-011, Acceptance 7.1, 7.2)
- [ ] T053 [US7] Validate `cmd_logs` in `sandbox.sh` — verify Docker container log display (Acceptance 7.3)
- [ ] T054 [US7] Validate nesting configuration — verify `security.nesting=true` in `setup-host.sh` enables Docker inside container (FR-001)
- [ ] T055 [US7] Acceptance test: Run `sandbox.sh docker run hello-world` and verify successful output (SC-002 prerequisite)

**Checkpoint**: User Story 7 validated — Docker works inside the sandbox as specified

---

## Phase 10: User Story 8 — Multiple Sandboxes (Priority: P3)

**Goal**: Verify `CLAUDE_SANDBOX` env var enables independent container targeting

**Independent Test**: Create two sandboxes with different projects, verify each operates independently

### Validation for User Story 8

- [ ] T056 [US8] Validate `CLAUDE_SANDBOX` env var in `sandbox.sh` — verify container name defaults to `claude-sandbox` and is overridable (FR-015, Acceptance 8.1)
- [ ] T057 [US8] Validate `CLAUDE_SANDBOX` in `setup-host.sh` — verify `-n` flag and env var fallback per contracts/setup-host.md
- [ ] T058 [US8] Acceptance test: Set `CLAUDE_SANDBOX=test-b`, run `sandbox.sh status`, verify it targets `test-b` container (Acceptance 8.1, SC-006)

**Checkpoint**: User Story 8 validated — multiple sandboxes work independently

---

## Phase 11: User Story 9 — Health Check (Priority: P3)

**Goal**: Verify health-check reports pass/fail for all five components

**Independent Test**: Run `sandbox.sh health-check` on healthy container; all checks pass

### Validation for User Story 9

- [ ] T059 [US9] Validate `cmd_health_check` in `sandbox.sh` — verify checks for network, Docker, Claude Code, project directory, and source mount (FR-014, Acceptance 9.1)
- [ ] T060 [US9] Validate health-check exit code — verify nonzero exit on any component failure (Acceptance 9.2)
- [ ] T061 [US9] Validate health-check output format — verify each component reports `ok` or `FAILED` per contracts/sandbox.md
- [ ] T062 [US9] Acceptance test: Run `sandbox.sh health-check` on a working container and verify all five checks pass (SC-005)

**Checkpoint**: User Story 9 validated — health check works as specified

---

## Phase 12: Polish & Cross-Cutting Concerns

**Purpose**: Edge case validation and final compliance checks

- [ ] T063 [P] Validate edge case: missing project directory at setup time — verify `setup-host.sh` fails with clear error before creating container
- [ ] T064 [P] Validate edge case: commands on non-existent container — verify `require_container` produces "container not found" with create instructions
- [ ] T065 [P] Validate edge case: commands on stopped container — verify `require_running` produces "container is STOPPED" with start instructions
- [ ] T066 Validate `sandbox.sh` case-based dispatch — verify all subcommands from contracts/sandbox.md are routed and `help` is the default
- [ ] T067 Validate CLAUDE.md accuracy — verify Known Issues, Key Commands, and Editing Notes match the current implementation
- [ ] T068 Run quickstart.md validation — walk through quickstart.md end-to-end and verify each command works as documented

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: No dependencies — can run in parallel with Phase 1
- **User Stories (Phase 3–11)**: All depend on Phase 2 completion (cross-cutting checks inform story validation)
  - User stories can proceed in parallel (different scripts/concerns)
  - Or sequentially in priority order (P1 → P2 → P3)
- **Polish (Phase 12)**: Depends on all user story phases being complete

### User Story Dependencies

- **US1 (P1)**: Independent — `setup-host.sh` + `provision-container.sh` audit
- **US2 (P1)**: Independent — `sandbox.sh` claude commands audit
- **US3 (P1)**: Partially depends on US1 (API key path involves `setup-host.sh`)
- **US4 (P2)**: Independent — `sandbox.sh` snapshot commands audit
- **US5 (P2)**: Independent — `sandbox.sh` sync/pull/push + `provision-container.sh` functions
- **US6 (P2)**: Independent — `sandbox.sh` lifecycle commands audit
- **US7 (P3)**: Depends on US1 (nesting config in `setup-host.sh`)
- **US8 (P3)**: Independent — env var handling across both host scripts
- **US9 (P3)**: Independent — `sandbox.sh` health-check audit

### Parallel Opportunities

- T002, T003, T004 (Phase 1) — different files
- T005–T010 (Phase 2) — independent cross-cutting checks
- T012, T013, T015 (US1) — independent setup-host.sh features
- T039, T040 (US5) — independent file transfer directions
- T044–T049 (US6) — independent lifecycle commands
- T063–T065 (Phase 12) — independent edge cases
- All user story phases can run in parallel (different scripts/concerns)

---

## Parallel Example: User Story 1

```bash
# Launch independent setup-host.sh validations together:
Task: "Validate container creation in setup-host.sh"       # T012
Task: "Validate network wait in setup-host.sh"              # T013
Task: "Validate deploy mount in setup-host.sh"              # T015

# Launch independent provision-container.sh validations together:
Task: "Validate git defaults in provision-container.sh"     # T018
Task: "Validate idempotent GPG key in provision-container.sh" # T022
```

---

## Parallel Example: User Story 6

```bash
# Launch all independent lifecycle validations together:
Task: "Validate cmd_start in sandbox.sh"    # T044
Task: "Validate cmd_stop in sandbox.sh"     # T045
Task: "Validate cmd_restart in sandbox.sh"  # T046
Task: "Validate cmd_status in sandbox.sh"   # T047
Task: "Validate cmd_shell in sandbox.sh"    # T048
Task: "Validate cmd_root in sandbox.sh"     # T049
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup validation
2. Complete Phase 2: Foundational cross-cutting checks
3. Complete Phase 3: User Story 1 (Create a New Sandbox)
4. **STOP and VALIDATE**: Confirm setup-host.sh and provision-container.sh match contracts
5. This validates the foundational script that all other stories depend on

### Incremental Delivery

1. Complete Setup + Foundational → Cross-cutting compliance confirmed
2. Validate US1 (Create Sandbox) → Foundation verified
3. Validate US2 + US3 (Run Claude + Auth) → Core value proposition verified
4. Validate US4 + US5 + US6 (Snapshot + Sync + Lifecycle) → Day-to-day operations verified
5. Validate US7 + US8 + US9 (Docker + Multi + Health) → Full feature set verified
6. Each story adds confidence without invalidating previous results

### Parallel Strategy

With multiple reviewers:

1. All complete Phase 1 + Phase 2 together
2. Once Foundational is done:
   - Reviewer A: US1 + US3 (setup-host.sh + provision-container.sh focus)
   - Reviewer B: US2 + US4 + US5 (sandbox.sh core commands)
   - Reviewer C: US6 + US7 + US8 + US9 (sandbox.sh remaining commands)
3. Phase 12: Polish done collaboratively

---

## Notes

- [P] tasks = different files or independent concerns, no dependencies
- [Story] label maps task to specific user story for traceability
- Baseline spec: tasks validate existing code, not build new code
- Acceptance test tasks (T023, T027, T037, T043, T055, T058, T062, T068) require a running LXD environment
- Code audit tasks can be completed by reading the source files
- Commit after each phase or logical group of validations
- Stop at any checkpoint to confirm story compliance independently
