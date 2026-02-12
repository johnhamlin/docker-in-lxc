# Tasks: Git & Forge Authentication Forwarding

**Input**: Design documents from `/specs/004-git-forge-auth/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/cli-interface.md, quickstart.md

**Tests**: No test framework; manual acceptance testing only (per plan.md). Test tasks are not included.

**Organization**: Tasks are grouped by user story. US1 and US2 are both P1 but organized as separate phases since they target different auth mechanisms. US4 (graceful degradation) is embedded in US1/US2 implementations and verified in the Polish phase.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

No source tree — this is a three-script bash project. All changes modify existing files at the repository root:

```text
setup-host.sh              # Container creation and device setup
provision-container.sh     # Package installation and shell config
dilxc.sh                   # Runtime management CLI
```

## Phase 1: Setup

**Purpose**: Understand existing script structure and identify insertion points

- [x] T001 Read setup-host.sh, provision-container.sh, and dilxc.sh to identify exact insertion points for all modifications (device creation blocks, shell config blocks, helper function area, dispatch block)

---

## Phase 2: Foundational (Provisioning)

**Purpose**: Install gh CLI and configure shell environment inside the container — MUST complete before any user story work

**CRITICAL**: No user story work can begin until this phase is complete

- [x] T002 Add GitHub CLI installation via apt repository (GPG key + apt source + apt-get install) after existing dev tools section in provision-container.sh — use binary keyring at /etc/apt/keyrings/githubcli-archive-keyring.gpg (no gpg --dearmor needed, per research.md Decision 4)
- [x] T003 [P] Add `export SSH_AUTH_SOCK=/tmp/ssh-agent.sock` to the bash config block (.bashrc heredoc) in provision-container.sh
- [x] T004 [P] Add `set -gx SSH_AUTH_SOCK /tmp/ssh-agent.sock` to the fish config block (config.fish heredoc, inside `--fish` conditional) in provision-container.sh

**Checkpoint**: Container provisioning now installs gh CLI and sets SSH_AUTH_SOCK in both shells

---

## Phase 3: User Story 1 — Push and Pull Code Over SSH (Priority: P1) MVP

**Goal**: SSH-based git operations (push, pull, clone) work transparently inside the container using the host's SSH agent. Private keys never enter the container.

**Independent Test**: Run `ssh -T git@github.com` inside the container — should authenticate successfully using forwarded agent. Then push a commit to a test repository.

### Implementation for User Story 1

- [x] T005 [P] [US1] Add SSH agent proxy device creation after existing device creation (project mount) in setup-host.sh — use `connect="unix:${SSH_AUTH_SOCK:-/dev/null}"` for graceful fallback when agent is not running, `listen=unix:/tmp/ssh-agent.sock`, `bind=container`, `uid=1000`, `gid=1000`, `mode=0600` (per contracts/cli-interface.md and data-model.md)
- [x] T006 [P] [US1] Add `ensure_auth_forwarding` helper function in dilxc.sh (place near other helper functions like require_container/require_running) — SSH agent logic: check if ssh-agent device exists via `lxc config device show` grep for `^ssh-agent:`, and if exists AND $SSH_AUTH_SOCK is set, run `lxc config device set $CONTAINER_NAME ssh-agent connect=unix:$SSH_AUTH_SOCK`; failures are silent (suppress stderr, per contracts/cli-interface.md)
- [x] T007 [US1] Wire `ensure_auth_forwarding` call into cmd_shell, cmd_claude, cmd_claude_run, cmd_claude_resume, cmd_exec, and cmd_login functions in dilxc.sh — add call after require_running but before the main lxc exec command in each function
- [x] T008 [US1] Add SSH agent proxy device creation to cmd_update function in dilxc.sh — check if ssh-agent device exists (grep `lxc config device show` output for `^ssh-agent:`), if missing add with same parameters as setup-host.sh, print "Added SSH agent forwarding device"

**Checkpoint**: SSH agent forwarding works end-to-end. `ssh -T git@github.com` authenticates inside the container. Auth survives snapshot restores and reboots (device metadata in LXD, not container filesystem).

---

## Phase 4: User Story 2 — GitHub CLI for API Operations (Priority: P1)

**Goal**: `gh` commands (pr create, issue list, auth status) work transparently inside the container using the host's gh authentication. Host config is mounted read-only.

**Independent Test**: Run `gh auth status` inside the container — should show authenticated. Then run `gh repo view` against a known repository.

### Implementation for User Story 2

- [x] T009 [P] [US2] Add gh-config disk device creation in setup-host.sh — only if `~/.config/gh` directory exists on host (per research.md Decision 3: don't create host dirs). Use `source="$HOME/.config/gh"`, `path=/home/ubuntu/.config/gh`, `readonly=true`. Place after SSH agent device block.
- [x] T010 [P] [US2] Extend `ensure_auth_forwarding` function in dilxc.sh with gh config logic — if gh-config device does NOT exist on container AND `~/.config/gh` directory exists on host, add disk device dynamically (hot-plug, no restart). Check device existence via `lxc config device show` grep for `^gh-config:`. Failures are silent.
- [x] T011 [US2] Add gh-config disk device creation to cmd_update function in dilxc.sh — check if gh-config device exists, if missing AND `~/.config/gh` exists on host, add device with same parameters as setup-host.sh, print "Added GitHub CLI config mount"

**Checkpoint**: GitHub CLI operations work from inside the container. `gh auth status` shows authenticated. Auth survives snapshot restores. Both US1 and US2 are independently functional.

---

## Phase 5: User Story 3 — Authentication Diagnostics (Priority: P2)

**Goal**: Users can verify auth status from the host with a single command that reports SSH agent and GitHub CLI status with actionable remediation guidance.

**Independent Test**: Run `./dilxc.sh git-auth` — should show status for both mechanisms. Test with agent running/stopped and gh authenticated/not.

### Implementation for User Story 3

- [x] T012 [US3] Add `cmd_git_auth` diagnostic function in dilxc.sh — follows health-check pattern. Call `require_container`, `require_running`, `ensure_auth_forwarding` first. Print header `=== Git & Forge Auth: $CONTAINER_NAME ===`. SSH check: verify ssh-agent device exists, run `ssh-add -l` inside container (as ubuntu), report identity count or failure with remediation. GH check: verify gh-config device exists, run `gh auth status` inside container (as ubuntu), extract username or report failure with remediation. Exit 0 if all working, exit 1 if any mechanism failing. (See contracts/cli-interface.md for exact output format and failure modes.)
- [x] T013 [US3] Add `git-auth` case to the dispatch block (case statement) at the bottom of dilxc.sh — route to `cmd_git_auth`, following existing pattern for health-check

**Checkpoint**: `./dilxc.sh git-auth` reports accurate status for both auth mechanisms with clear remediation guidance when something is misconfigured.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Help text updates, graceful degradation verification (US4), and end-to-end validation

- [x] T014 Update dilxc.sh help/usage text to include `git-auth` subcommand in the usage message and any help output
- [x] T015 Verify graceful degradation (US4 acceptance scenarios) — confirm setup-host.sh completes when $SSH_AUTH_SOCK is unset (placeholder device created) and when ~/.config/gh doesn't exist (device skipped); confirm auth starts working on next dilxc.sh interaction after host-side prerequisites are met
- [x] T016 Run quickstart.md validation scenarios end-to-end per specs/004-git-forge-auth/quickstart.md

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — can start immediately
- **Foundational (Phase 2)**: Depends on Phase 1 — BLOCKS all user stories
- **US1 (Phase 3)**: Depends on Phase 2 completion
- **US2 (Phase 4)**: Depends on Phase 2 completion — can run in parallel with US1
- **US3 (Phase 5)**: Depends on Phase 3 AND Phase 4 (diagnostic checks both mechanisms)
- **Polish (Phase 6)**: Depends on Phases 3, 4, and 5

### User Story Dependencies

- **US1 (P1)**: Can start after Foundational (Phase 2) — no dependencies on other stories
- **US2 (P1)**: Can start after Foundational (Phase 2) — no dependencies on other stories; can run in parallel with US1
- **US3 (P2)**: Depends on US1 AND US2 — diagnostic function checks both SSH and gh status
- **US4 (P3)**: No separate implementation — graceful degradation is embedded in US1 (T005: `/dev/null` fallback) and US2 (T009: conditional device creation, T010: dynamic hot-plug). Verified in Polish phase (T015).

### Note on `cmd_init` (FR-013)

`cmd_init` delegates to `setup-host.sh` via `exec "$SCRIPT_DIR/setup-host.sh" "$@"`. Therefore, T005 and T009 (which add device creation to setup-host.sh) fully cover the `init` path. No separate tasks are needed for `cmd_init`.

### Within Each User Story

- setup-host.sh changes and dilxc.sh helper function can be done in parallel [P]
- Helper function must exist before wiring it into commands
- cmd_update changes depend on knowing the device creation pattern
- Dispatch block entry depends on the function it routes to

### Parallel Opportunities

- Phase 2: T003 and T004 can run in parallel (different shell config blocks)
- Phase 3: T005 and T006 can run in parallel (different files: setup-host.sh vs dilxc.sh)
- Phase 4: T009 and T010 can run in parallel (different files: setup-host.sh vs dilxc.sh)
- Phase 3 and Phase 4 can run in parallel (independent user stories)

---

## Parallel Example: User Story 1

```bash
# Launch setup-host.sh and dilxc.sh changes in parallel:
Task: "T005 [US1] Add SSH agent proxy device creation in setup-host.sh"
Task: "T006 [US1] Add ensure_auth_forwarding helper function in dilxc.sh"

# Then sequentially:
Task: "T007 [US1] Wire ensure_auth_forwarding into interactive commands in dilxc.sh"
Task: "T008 [US1] Add SSH agent device check to cmd_update in dilxc.sh"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (read existing scripts)
2. Complete Phase 2: Foundational (gh CLI install + SSH_AUTH_SOCK env)
3. Complete Phase 3: User Story 1 (SSH agent forwarding end-to-end)
4. **STOP and VALIDATE**: Test `ssh -T git@github.com` inside container
5. SSH-based git push/pull now works — core develop-in-sandbox-push-to-forge cycle is unblocked

### Incremental Delivery

1. Complete Setup + Foundational -> Foundation ready
2. Add User Story 1 -> Test SSH auth independently -> MVP!
3. Add User Story 2 -> Test gh CLI independently -> Full auth suite
4. Add User Story 3 -> Test diagnostics -> Complete feature
5. Polish phase -> Verify graceful degradation (US4) + end-to-end quickstart

### Parallel Strategy

With multiple workers:

1. Complete Setup + Foundational together
2. Once Foundational is done:
   - Worker A: User Story 1 (SSH agent forwarding)
   - Worker B: User Story 2 (GitHub CLI config sharing)
3. After both complete: User Story 3 (diagnostics)
4. Polish phase

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- All changes modify existing files — no new scripts created (Constitution Principle II)
- Device names are fixed: `ssh-agent` and `gh-config` (per research.md Decision 6)
- Container-side SSH socket path is fixed: `/tmp/ssh-agent.sock` (per research.md Decision 1)
- `ensure_auth_forwarding` failures are always silent — it's a best-effort pre-command hook
- Both auth mechanisms use LXD device metadata (survives snapshots) not container filesystem
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
