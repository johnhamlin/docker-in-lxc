# Feature Specification: LXD Sandbox for Autonomous Claude Code

**Feature Branch**: `001-baseline-spec`
**Created**: 2026-02-11
**Status**: Draft
**Input**: Baseline specification documenting the complete, already-built LXD sandbox tool. Three bash scripts for running Claude Code autonomously inside a disposable LXD system container on an Ubuntu homelab server.

## Clarifications

### Session 2026-02-11

- Q: Does sync (`sandbox.sh sync` / `sync-project`) use `--delete`, removing container-only files, or preserve them? → A: Destructive sync with `--delete` — full reset to source. Use GitHub to get changes out of the container.
- Q: Is re-provisioning a supported workflow (sandbox.sh subcommand + user story) or an escape hatch? → A: Escape hatch only — documented in CLAUDE.md, no formal subcommand or user story. Primary recovery is snapshot restore or delete-and-recreate.
- Q: What output do scripts produce during execution — silent, verbose, or mixed? → A: Verbose by default with step-by-step progress output to stdout, errors to stderr. No `--quiet` flag. Visibility builds trust for a homelab tool.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Create a New Sandbox (Priority: P1)

A developer on an Ubuntu homelab server wants to create an isolated sandbox for running Claude Code against one of their projects. They run a single setup command on the host, specifying their project directory. The tool creates an LXD container with all required tooling pre-installed, mounts the project read-only, creates a writable working copy, and takes a baseline snapshot for rollback safety.

**Why this priority**: This is the foundational operation — nothing else works without a functioning sandbox. First-time experience determines adoption.

**Independent Test**: Can be fully tested by running the setup script with a project directory and verifying the container exists with correct mounts, tooling, and a baseline snapshot.

**Acceptance Scenarios**:

1. **Given** an Ubuntu host with LXD and btrfs storage configured, **When** the user runs `setup-host.sh -n my-sandbox -p /path/to/project`, **Then** an Ubuntu 24.04 container is created with nesting enabled, the project directory is mounted read-only at `/home/ubuntu/project-src`, a writable copy exists at `/home/ubuntu/project`, and a `clean-baseline` snapshot is taken.
2. **Given** the user specifies the `--fish` flag during setup, **When** provisioning completes, **Then** fish shell is installed, configured with equivalent aliases and functions, and set as the default shell for the `ubuntu` user.
3. **Given** the user provides a deploy directory via `--deploy`, **When** setup completes, **Then** the deploy directory is mounted read-write at `/mnt/deploy` inside the container.
4. **Given** network connectivity fails during setup, **When** the 30-second timeout elapses, **Then** setup reports the failure and exits with a nonzero status.
5. **Given** setup fails partway through, **When** the user wants to retry, **Then** they delete the container and run setup again from scratch (no partial recovery).

---

### User Story 2 - Run Claude Code Autonomously (Priority: P1)

A developer wants Claude Code to work on their project inside the sandbox, operating autonomously with full permissions within the container. They start an interactive session or fire a one-shot prompt, and Claude works in the writable project directory with `--dangerously-skip-permissions` (safe because the container IS the sandbox).

**Why this priority**: This is the core value proposition — running Claude Code with full autonomy in a safe, disposable environment.

**Independent Test**: Can be tested by starting an interactive Claude session and a one-shot prompt, verifying both operate in the correct directory with skip-permissions enabled.

**Acceptance Scenarios**:

1. **Given** a running sandbox with Claude Code authenticated, **When** the user runs `sandbox.sh claude`, **Then** an interactive Claude Code session starts in `/home/ubuntu/project` with `--dangerously-skip-permissions` and a TTY allocated.
2. **Given** a running sandbox, **When** the user runs `sandbox.sh claude-run "refactor the auth module"`, **Then** Claude Code executes the prompt non-interactively in the project directory, with the prompt safely shell-escaped.
3. **Given** a previous Claude session exists, **When** the user runs `sandbox.sh claude-resume`, **Then** the most recent session resumes with its full context.

---

### User Story 3 - Authenticate Claude Code (Priority: P1)

After creating a sandbox, the developer needs to authenticate Claude Code before first use. They either complete a browser OAuth flow or pre-configure an API key.

**Why this priority**: Authentication is a prerequisite for running Claude Code — must work reliably on first attempt.

**Independent Test**: Can be tested by running the login command and verifying Claude Code can start a session afterward.

**Acceptance Scenarios**:

1. **Given** a newly created sandbox without authentication, **When** the user runs `sandbox.sh login`, **Then** an interactive session opens with TTY allocated, allowing the user to complete browser OAuth and exit.
2. **Given** the `ANTHROPIC_API_KEY` environment variable is set before running `setup-host.sh`, **When** provisioning completes, **Then** the API key is written into the container's shell configuration and Claude Code can authenticate without browser OAuth.

---

### User Story 4 - Snapshot and Rollback (Priority: P2)

A developer wants to create save points before risky operations and instantly roll back if Claude makes unwanted changes. They take named snapshots and restore to any previous state.

**Why this priority**: Rollback safety is a key differentiator of the sandbox approach — it gives developers confidence to let Claude operate autonomously.

**Independent Test**: Can be tested by taking a snapshot, making changes in the container, restoring the snapshot, and verifying changes are reverted.

**Acceptance Scenarios**:

1. **Given** a running sandbox, **When** the user runs `sandbox.sh snapshot before-refactor`, **Then** a btrfs snapshot named `before-refactor` is created.
2. **Given** a running sandbox, **When** the user runs `sandbox.sh snapshot` without a name, **Then** a snapshot with an auto-generated timestamp name is created.
3. **Given** a snapshot named `before-refactor` exists, **When** the user runs `sandbox.sh restore before-refactor`, **Then** the container is restored to that snapshot state and automatically restarted.
4. **Given** multiple snapshots exist, **When** the user runs `sandbox.sh snapshots`, **Then** all snapshots are listed.

---

### User Story 5 - Sync and File Transfer (Priority: P2)

A developer needs to refresh the writable working copy from the host project (after pulling changes on the host) or transfer files between host and container.

**Why this priority**: File synchronization is essential for iterative workflows where the host project evolves between sandbox sessions.

**Independent Test**: Can be tested by modifying the host project, running sync, and verifying the writable copy is updated with correct exclusions.

**Acceptance Scenarios**:

1. **Given** the host project has new changes, **When** the user runs `sandbox.sh sync`, **Then** the writable working copy at `/home/ubuntu/project` is replaced via rsync with `--delete` from `/home/ubuntu/project-src`, excluding `node_modules`, `.git`, `dist`, and `build`. Files existing only in the working copy are removed.
2. **Given** a file exists in the container, **When** the user runs `sandbox.sh pull /home/ubuntu/project/output.txt ./`, **Then** the file is copied from the container to the host.
3. **Given** a file exists on the host, **When** the user runs `sandbox.sh push local-file.txt /home/ubuntu/project/`, **Then** the file is copied into the container.
4. **Given** the `sync-project` bash function is called inside the container, **When** it completes, **Then** it performs the same rsync with the same exclusion list as `sandbox.sh sync`.
5. **Given** a deploy mount is configured at `/mnt/deploy`, **When** the user calls the `deploy` function inside the container, **Then** output files are rsynced to the deploy mount.

---

### User Story 6 - Container Lifecycle Management (Priority: P2)

A developer manages the sandbox container's lifecycle — starting, stopping, restarting, checking status, opening shells, and destroying when done.

**Why this priority**: Basic lifecycle operations are needed for daily use, but the container usually stays running.

**Independent Test**: Can be tested by cycling through start/stop/restart/status/destroy commands and verifying each produces the expected state.

**Acceptance Scenarios**:

1. **Given** a stopped sandbox, **When** the user runs `sandbox.sh start`, **Then** the container starts.
2. **Given** a running sandbox, **When** the user runs `sandbox.sh stop`, **Then** the container stops.
3. **Given** a running sandbox, **When** the user runs `sandbox.sh restart`, **Then** the container stops and starts again.
4. **Given** a running sandbox, **When** the user runs `sandbox.sh status`, **Then** the output shows container info, IP address, and available snapshots.
5. **Given** a running sandbox, **When** the user runs `sandbox.sh shell`, **Then** an interactive bash shell opens as the `ubuntu` user with a TTY allocated.
6. **Given** a running sandbox, **When** the user runs `sandbox.sh root`, **Then** an interactive root shell opens with a TTY allocated.
7. **Given** a sandbox exists, **When** the user runs `sandbox.sh destroy`, **Then** a confirmation prompt appears, and upon confirmation, the container is deleted.

---

### User Story 7 - Docker Inside the Sandbox (Priority: P3)

A developer needs to run Docker containers inside the sandbox — for example, to spin up databases, run integration tests, or build container images as part of the project.

**Why this priority**: Docker support is important for realistic project environments but not every project requires it.

**Independent Test**: Can be tested by running `sandbox.sh docker run hello-world` and verifying Docker operates correctly inside the nested container.

**Acceptance Scenarios**:

1. **Given** a running sandbox with Docker installed, **When** the user runs `sandbox.sh docker ps`, **Then** the Docker command executes inside the container and returns results.
2. **Given** Docker arguments with spaces or special characters, **When** the user runs `sandbox.sh docker run -e "MY_VAR=hello world" nginx`, **Then** arguments are safely escaped via `printf %q` and passed correctly.
3. **Given** Docker containers are running inside the sandbox, **When** the user runs `sandbox.sh logs`, **Then** Docker container logs are displayed.

---

### User Story 8 - Multiple Sandboxes (Priority: P3)

A developer works on multiple projects and wants a separate sandbox for each, with full isolation between them.

**Why this priority**: Multi-project support enables realistic use but most developers start with a single sandbox.

**Independent Test**: Can be tested by creating two sandboxes with different project directories and verifying each operates independently.

**Acceptance Scenarios**:

1. **Given** the user sets `CLAUDE_SANDBOX=project-b`, **When** they run any `sandbox.sh` command, **Then** the command operates on the `project-b` container instead of the default.
2. **Given** two sandboxes exist for different projects, **When** the user takes a snapshot on one, **Then** the other sandbox is unaffected — no shared state.

---

### User Story 9 - Health Check (Priority: P3)

A developer wants to verify their sandbox is working correctly — network, Docker, Claude Code, project directory, and source mount are all functional.

**Why this priority**: Diagnostic capability helps troubleshoot issues but is not needed for normal operation.

**Independent Test**: Can be tested by running `sandbox.sh health-check` on a healthy container and verifying all checks pass, then breaking one component and verifying the check detects it.

**Acceptance Scenarios**:

1. **Given** a fully functional sandbox, **When** the user runs `sandbox.sh health-check`, **Then** each check (network, Docker, Claude Code, project directory, source mount) reports "ok".
2. **Given** a sandbox with a broken component, **When** the user runs `sandbox.sh health-check`, **Then** the failed check reports "FAILED" and the command exits with a nonzero status.

---

### Edge Cases

- What happens when the host project directory does not exist at setup time? Setup must fail with a clear error before creating the container.
- What happens when `lxc file push` is used to overwrite an existing file? It silently fails — the file must be deleted first, then pushed.
- What happens when Docker's iptables rules on the host block LXD bridge traffic? Containers get IPv6 but no IPv4. Requires UFW rules for DHCP/DNS on lxdbr0 and a DOCKER-USER chain entry for the LXD subnet.
- What happens when the user runs `sandbox.sh` commands against a non-existent container? The `require_container` helper validates the container exists before executing.
- What happens when the user runs commands requiring a running container on a stopped one? The `require_running` helper validates the container is running.
- What happens when rsync exclude lists in `sandbox.sh`, bash config, and fish config diverge? Sync behavior becomes inconsistent — all three must be kept in sync manually.
- What happens when a user runs sync after Claude has created new files in the working copy? The `--delete` flag removes container-only files. Users must commit and push to GitHub before syncing to preserve work.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST create Ubuntu 24.04 LXD containers with `security.nesting=true` to allow Docker to run natively inside.
- **FR-002**: System MUST mount the user's project directory as read-only at `/home/ubuntu/project-src` inside the container.
- **FR-003**: System MUST create a writable working copy directory at `/home/ubuntu/project` during provisioning. The directory is populated by the user running `sandbox.sh sync` after setup completes.
- **FR-004**: System MUST install Docker CE with compose plugin, Node.js 22 LTS, Claude Code (npm global), uv, Spec Kit, and standard dev tools during provisioning.
- **FR-005**: System MUST configure shell aliases (`cc`, `cc-resume`, `cc-prompt`) that invoke Claude Code with `--dangerously-skip-permissions`.
- **FR-006**: System MUST provide a `sync-project` function and `sandbox.sh sync` command that rsync with `--delete` from the read-only mount to the writable copy, excluding `node_modules`, `.git`, `dist`, and `build`. Sync is destructive — files existing only in the working copy are removed. The expected workflow for preserving changes is to commit and push to GitHub before syncing.
- **FR-007**: System MUST take a `clean-baseline` btrfs snapshot after successful provisioning.
- **FR-008**: System MUST support snapshot creation with user-provided or auto-generated timestamp names.
- **FR-009**: System MUST support snapshot restoration with automatic container restart.
- **FR-010**: System MUST allocate a TTY for interactive commands (`shell`, `root`, `login`, `claude`, `claude-resume`).
- **FR-011**: System MUST safely shell-escape arguments using `printf %q` for `claude-run`, `exec`, and `docker` passthrough commands.
- **FR-012**: System MUST support browser OAuth as the primary authentication method and API key injection as the alternative.
- **FR-013**: System MUST validate container existence (`require_container`) and running state (`require_running`) before executing subcommands.
- **FR-014**: System MUST provide a health check that verifies network connectivity, Docker, Claude Code, project directory, and source mount, reporting each as ok/FAILED.
- **FR-015**: System MUST support operating on different containers via the `CLAUDE_SANDBOX` environment variable.
- **FR-016**: System MUST optionally install and configure fish shell when the `--fish` flag is passed, writing equivalent aliases, functions, and PATH configuration.
- **FR-017**: System MUST configure git defaults (main branch, sandbox identity) for the `ubuntu` user inside the container.
- **FR-018**: System MUST support an optional read-write deploy mount at `/mnt/deploy` with a corresponding `deploy` function.
- **FR-019**: System MUST wait for network connectivity with a 30-second timeout during setup before proceeding with provisioning.
- **FR-020**: System MUST prompt for confirmation before destroying a container.
- **FR-021**: System MUST support `pull` and `push` subcommands for transferring files between host and container via `lxc file pull/push`.
- **FR-022**: System MUST use `gpg --dearmor --yes` for Docker GPG key installation to ensure idempotent re-provisioning.
- **FR-022a**: Known limitation: bash config is appended via `cat >>`, so re-provisioning duplicates the aliases block. This is functionally safe but not clean. The primary recovery path is delete-and-recreate, not re-provision.
- **FR-023**: All scripts MUST produce step-by-step progress output to stdout during execution. Errors MUST go to stderr. There is no quiet mode — verbose output is the only mode.

### Key Entities

- **Container**: An LXD system container running Ubuntu 24.04, bound to a single host project directory. Has a name (default: `claude-sandbox`), network configuration, and zero or more btrfs snapshots.
- **Snapshot**: A btrfs point-in-time capture of a container's state. Has a name (user-provided or timestamp-generated). Supports instant restore with automatic container restart.
- **Project Mount**: A read-only bind mount from host to `/home/ubuntu/project-src`. The source of truth for project files.
- **Working Copy**: A writable rsync copy at `/home/ubuntu/project` where Claude Code operates. Refreshed via sync commands.
- **Deploy Mount**: An optional read-write bind mount at `/mnt/deploy` for pushing output back to the host.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A new sandbox can be created and fully provisioned (container + all tooling + baseline snapshot) in a single command invocation.
- **SC-002**: Claude Code sessions start in the correct working directory with autonomous permissions within 5 seconds of the user issuing the command.
- **SC-003**: Snapshot restore returns the container to a previous state and restarts it, making the sandbox operational again without manual intervention.
- **SC-004**: File sync between the read-only mount and writable copy completes correctly, with all configured exclusions applied consistently across all sync mechanisms (host command, bash function, fish function).
- **SC-005**: Health check detects and reports failures in any of the five checked components (network, Docker, Claude Code, project directory, source mount) with a nonzero exit status.
- **SC-006**: Multiple sandboxes can operate simultaneously on the same host, each fully isolated with independent project mounts, snapshots, and no shared state.
- **SC-007**: One-shot Claude prompts with special characters (quotes, spaces, shell metacharacters) are passed correctly to Claude Code without corruption.
- **SC-008**: The system works correctly on an Ubuntu host with both Docker and LXD running, including when Docker's iptables rules would otherwise interfere with LXD bridge traffic (resolved via UFW configuration).

## Assumptions

- The host runs Ubuntu with LXD installed and a btrfs storage pool available.
- The user has sudo/root access on the host for LXD operations.
- The host has internet connectivity for downloading packages during provisioning.
- Docker is also running on the host (the UFW firewall rules account for Docker's iptables behavior).
- The `lxdbr0` bridge subnet is `10.200.12.0/24` (configurable in UFW rules if different).
- Fish shell is not needed by default — bash is sufficient for most users.
- Setup failures are handled by deleting and recreating the container, not by partial recovery.
- Re-provisioning an existing container is an advanced escape hatch (manual `lxc exec` steps documented in CLAUDE.md), not a supported sandbox.sh workflow. The primary recovery paths are snapshot restore or delete-and-recreate.
- The rsync exclusion list (`node_modules`, `.git`, `dist`, `build`) covers the common case for Node.js/web projects. Users with different needs would modify the scripts directly.

## Future Considerations

- **Incus Support**: The tool is designed to work with both LXD and Incus. Only LXD is implemented because that's the current host environment. The `lxc` and `incus` CLIs are nearly identical, so migration is straightforward. Incus development starts once an Incus test environment is available.
