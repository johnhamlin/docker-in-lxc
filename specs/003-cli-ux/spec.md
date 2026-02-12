# Feature Specification: CLI UX Improvements

**Feature Branch**: `003-cli-ux`
**Created**: 2026-02-12
**Status**: Draft
**Input**: Retroactive specification documenting CLI UX improvements to dilxc.sh — symlink-based installation, init/update commands, multi-container selection, containers listing, and .gitattributes for clean distribution.

## Clarifications

### Session 2026-02-12

- Q: How does `init` interact with the container selection cascade? → A: `init` and `update` are cascade-independent commands. The cascade runs but the result is unused — `setup-host.sh`'s `-n` flag controls the container name for `init`, and `update` operates on `SCRIPT_DIR`. This is by design.
- Q: Does `containers` intentionally list all LXD containers, not just dilxc-managed ones? → A: Yes, intentional. There's no metadata to distinguish dilxc-created containers, and showing all LXD containers gives full situational awareness on the host.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Install and Invoke dilxc from Anywhere (Priority: P1)

A developer clones the Docker-in-LXC repository and wants to use `dilxc` as a system-wide command without typing the full path to the script. They create a symlink from `dilxc.sh` to `~/.local/bin/dilxc`, and the script resolves its real location via `readlink -f` to find sibling scripts (like `setup-host.sh`) regardless of where the symlink lives.

**Why this priority**: Installation is the first thing any new user does. If the tool can't be invoked conveniently, adoption suffers. The `SCRIPT_DIR` resolution also underpins `init` and `update` commands.

**Independent Test**: Can be fully tested by creating a symlink to `dilxc.sh` in `~/.local/bin/`, invoking `dilxc help` from a different directory, and verifying the script resolves its real location correctly.

**Acceptance Scenarios**:

1. **Given** the repository is cloned to `/opt/claude-lxc-sandbox`, **When** the user creates a symlink `~/.local/bin/dilxc -> /opt/claude-lxc-sandbox/dilxc.sh`, **Then** running `dilxc help` from any directory displays the usage text.
2. **Given** `dilxc.sh` is invoked via a symlink, **When** the script computes `SCRIPT_DIR`, **Then** `SCRIPT_DIR` points to the real directory containing `dilxc.sh` (not the symlink's directory), and sibling scripts like `setup-host.sh` are found there.
3. **Given** `dilxc.sh` is invoked directly (not via symlink), **When** the script computes `SCRIPT_DIR`, **Then** `SCRIPT_DIR` still resolves correctly to the script's containing directory.

---

### User Story 2 - Create a Sandbox via dilxc init (Priority: P1)

A developer wants to create a new sandbox without remembering the path to `setup-host.sh`. They run `dilxc init` with the same options they would pass to `setup-host.sh`, and the command passes all arguments through.

**Why this priority**: Streamlines the first-use experience. Without `init`, users must know the repo path and invoke `./setup-host.sh` directly.

**Independent Test**: Can be tested by running `dilxc init --help` and verifying it shows setup-host.sh's help output, confirming argument passthrough works.

**Acceptance Scenarios**:

1. **Given** `dilxc` is installed via symlink, **When** the user runs `dilxc init -p /home/john/dev/myproject`, **Then** `setup-host.sh` is invoked with `-p /home/john/dev/myproject` and creates the sandbox.
2. **Given** the user runs `dilxc init -p /path/to/project -n mybox --fish`, **When** `init` executes, **Then** all flags (`-p`, `-n`, `--fish`) are passed through to `setup-host.sh` without modification.
3. **Given** `init` uses `exec` to replace the current process, **When** `setup-host.sh` finishes (success or failure), **Then** the exit code propagates directly to the caller with no intermediate cleanup step.

---

### User Story 3 - Target a Specific Container (Priority: P1)

A developer works with multiple sandboxes on the same host and needs to direct commands to a specific container. The system resolves the target container using a priority-based cascade: `@name` prefix, `DILXC_CONTAINER` env var, `.dilxc` file from the current or ancestor directory, or the default `docker-lxc`.

**Why this priority**: Multi-container support is essential once a developer has more than one project. Without it, every command requires manually setting an environment variable.

**Independent Test**: Can be tested by creating a `.dilxc` file containing a container name, running `dilxc status` from that directory, and verifying it targets the correct container.

**Acceptance Scenarios**:

1. **Given** the user runs `dilxc @project-b shell`, **When** the command is parsed, **Then** the `@project-b` prefix is consumed, `CONTAINER_NAME` is set to `project-b`, and `shell` is the subcommand.
2. **Given** `DILXC_CONTAINER=staging` is set and no `@name` prefix is used, **When** the user runs `dilxc status`, **Then** the command targets the `staging` container.
3. **Given** a file `/home/john/dev/myproject/.dilxc` contains `myproject-sandbox`, **When** the user runs `dilxc shell` from `/home/john/dev/myproject/src/`, **Then** the script walks up from `src/` to `myproject/`, finds `.dilxc`, and targets `myproject-sandbox`.
4. **Given** no `@name` prefix, no `DILXC_CONTAINER` env var, and no `.dilxc` file in any ancestor directory, **When** the user runs any command, **Then** the default container name `docker-lxc` is used.
5. **Given** both `@name` prefix and `DILXC_CONTAINER` are present, **When** the command is parsed, **Then** `@name` wins (first match in the priority cascade).

---

### User Story 4 - Update to the Latest Version (Priority: P2)

A developer wants to pull the latest version of Docker-in-LXC. They run `dilxc update`, which performs a `git pull` in the script's repository directory.

**Why this priority**: Self-update is convenient but less critical than core installation and multi-container support.

**Independent Test**: Can be tested by running `dilxc update` in a git-cloned installation and verifying the repo is updated.

**Acceptance Scenarios**:

1. **Given** `dilxc` was installed from a git clone, **When** the user runs `dilxc update`, **Then** `git pull` runs in the script's repository directory and shows the update output.
2. **Given** the script directory is not a git checkout, **When** the user runs `dilxc update`, **Then** an error message is displayed: "Error: not a git checkout — update by re-downloading from GitHub" and the command exits with a nonzero status.
3. **Given** `dilxc update` runs, **When** it displays progress, **Then** it shows the current short commit hash before pulling (e.g., "Updating Docker-in-LXC from abc1234...").

---

### User Story 5 - List Available Containers (Priority: P2)

A developer wants to see all LXD containers on the host and which one is currently active (targeted by the container selection cascade).

**Why this priority**: Provides situational awareness for multi-container users, but is supplementary to the core selection mechanism.

**Independent Test**: Can be tested by running `dilxc containers` and verifying the output lists all LXD containers with status and marks the active one.

**Acceptance Scenarios**:

1. **Given** multiple LXD containers exist on the host, **When** the user runs `dilxc containers`, **Then** all containers are listed with their name and status in a formatted table.
2. **Given** the active container (resolved by the selection cascade) is `docker-lxc`, **When** the output is displayed, **Then** `docker-lxc` is marked with `(active)` in the listing.

---

### User Story 6 - Clean Distribution via .gitattributes (Priority: P3)

When the repository is packaged for distribution via `git archive`, spec artifacts, Specify configuration, Claude configuration, and other development files are excluded from the archive.

**Why this priority**: Distribution cleanliness is a nice-to-have that doesn't affect daily usage.

**Independent Test**: Can be tested by running `git archive` on the repository and verifying that `specs/`, `.specify/`, `.claude/`, and other excluded paths are absent from the archive.

**Acceptance Scenarios**:

1. **Given** the repository has a `.gitattributes` file, **When** `git archive` produces a tarball, **Then** the `specs/`, `.specify/`, `.claude/` directories and files like `constitution-input.md`, `spec-input.md`, and `HANDOFF.md` are excluded.

---

### Edge Cases

- What happens when `.dilxc` contains whitespace or an empty line? The script reads the first line via `head -1`, so leading/trailing whitespace becomes part of the container name. Empty file results in an empty container name, falling through to the default.
- What happens when multiple `.dilxc` files exist in the ancestor chain? The first one found (closest to `$PWD`) wins — the walk stops at the first match.
- What happens when `dilxc update` encounters a merge conflict? Git handles it normally — the conflict is reported to the user and requires manual resolution.
- What happens when the user runs `dilxc init` without any arguments? `setup-host.sh` handles its own argument validation and shows its help text.
- What happens when `SCRIPT_DIR` resolution fails because `readlink -f` is not available? On Ubuntu 24.04, GNU coreutils `readlink` is always available. This is not a concern for the target platform.
- What happens when a user runs `dilxc @mybox init -p /path`? The `@mybox` prefix is consumed by the cascade but the resolved `CONTAINER_NAME` is unused — `init` delegates to `setup-host.sh`, which has its own `-n` flag. Similarly, `update` ignores the cascade result. This is by design; these commands are cascade-independent.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The script MUST resolve its real filesystem location via `readlink -f` to compute `SCRIPT_DIR`, following symlinks to find sibling scripts regardless of invocation path.
- **FR-002**: The `init` subcommand MUST pass all arguments through to `setup-host.sh` using `exec`, replacing the current process entirely.
- **FR-003**: The `init` subcommand MUST locate `setup-host.sh` via `SCRIPT_DIR`, not relative to the current working directory.
- **FR-004**: The `update` subcommand MUST run `git pull` in `SCRIPT_DIR` to update the tool.
- **FR-005**: The `update` subcommand MUST verify that `SCRIPT_DIR` contains a `.git` directory and exit with an error if not.
- **FR-006**: The `update` subcommand MUST display the current short commit hash before pulling, so the user can see what version they're updating from.
- **FR-007**: Container name resolution MUST follow this priority cascade (first match wins): `@name` prefix argument, `DILXC_CONTAINER` environment variable, `.dilxc` file found by walking up from `$PWD`, default value `docker-lxc`.
- **FR-008**: The `@name` prefix MUST be consumed (shifted) before subcommand dispatch, so the subcommand does not see it as an argument.
- **FR-009**: The `.dilxc` file search MUST walk up from the current working directory, checking each directory for a `.dilxc` file, stopping at the filesystem root.
- **FR-010**: The `.dilxc` file MUST contain the container name on its first line.
- **FR-011**: The `containers` subcommand MUST list all LXD containers on the host (not just dilxc-managed ones) with their name and status, providing full visibility into the host's container landscape.
- **FR-012**: The `containers` subcommand MUST mark the currently active container (as resolved by the selection cascade) with an `(active)` indicator.
- **FR-013**: The `.gitattributes` file MUST exclude `specs/`, `.specify/`, `.claude/`, `constitution-input.md`, `spec-input.md`, and `HANDOFF.md` from `git archive` output.

### Key Entities

- **Container Selection Cascade**: The priority-ordered mechanism for resolving which container a command targets. Sources: `@name` prefix, `DILXC_CONTAINER` env var, `.dilxc` file, default `docker-lxc`.
- **`.dilxc` File**: A single-line file containing a container name, placed in a project directory to automatically associate that directory tree with a specific container.
- **`SCRIPT_DIR`**: The resolved real filesystem directory containing `dilxc.sh`, used to locate sibling scripts. Computed via `readlink -f` to follow symlinks.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Users can invoke `dilxc` from any directory on the system after creating a single symlink, without needing to know or type the repository path.
- **SC-002**: Creating a new sandbox requires only `dilxc init -p /path/to/project` — no need to locate or directly invoke `setup-host.sh`.
- **SC-003**: Users can target any container using a single `@name` prefix without modifying environment variables or configuration files.
- **SC-004**: A `.dilxc` file in a project directory eliminates the need for any per-command container specification — the correct container is selected automatically when working within that directory tree.
- **SC-005**: Running `dilxc update` brings the tool to the latest version in a single command, with clear feedback on the current version before updating.
- **SC-006**: `dilxc containers` provides a complete overview of available containers and which one is currently targeted, enabling informed multi-container workflows.
- **SC-007**: Distribution archives produced by `git archive` contain only the essential scripts and documentation, excluding development artifacts.

## Assumptions

- The host runs Ubuntu with GNU coreutils (specifically `readlink -f` support).
- `~/.local/bin` is on the user's `PATH` (standard on Ubuntu 24.04).
- The tool is installed via `git clone`, making `git pull` a valid update mechanism. Non-git installations (e.g., downloaded tarballs) are not supported for self-update.
- The `.dilxc` file convention is project-local — users create it manually or via documentation guidance. There is no `dilxc` command to generate it.
- All features in this spec are already implemented and merged to main. This is a retroactive specification.
