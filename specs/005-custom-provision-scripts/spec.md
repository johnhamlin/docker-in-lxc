# Feature Specification: Custom Provision Scripts

**Feature Branch**: `005-custom-provision-scripts`
**Created**: 2026-02-12
**Status**: Draft
**Input**: User description: "If the user wants to add any other tools that are automatically setup in all of his repos, he should be able to add a file with those in it. The repo should ship with a CLAUDE.md smart enough to write those for him. For instance, I want spec Kit in all of my containers. I'm thinking the setup script could look for an optional file that contains any additional shell commands that the user wants to add to the provision script that gets copied in the new lxc container. Ideally, the repo should ship with instructions for coding agents that make it easy to use a tool like claude code to generate these custom shell scripts for the user so that he just has to describe the tools / customizations he wants to his environment and the coding agent will produce the custom shell commands correctly formatted"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Add Custom Tools via Provision Script (Priority: P1)

A server admin wants every new LXC container to come pre-installed with specific tools beyond the defaults (e.g., Spec Kit, a particular linter, a custom CLI). They create an optional custom provisioning file in the repo. When `setup-host.sh` runs, it detects this file and executes its contents inside the container after the standard provisioning completes. The custom tools are available immediately when the admin enters the container.

**Why this priority**: This is the core capability — without the mechanism to detect and execute custom provisioning scripts, nothing else works. It delivers immediate value by eliminating manual post-setup tool installation.

**Independent Test**: Can be fully tested by creating a custom provision file that installs a specific tool (e.g., `jq`), running `setup-host.sh`, and verifying the tool is available inside the container.

**Acceptance Scenarios**:

1. **Given** a custom provision file exists in the repo, **When** `setup-host.sh` runs, **Then** the custom commands execute inside the container after standard provisioning completes and before the baseline snapshot is taken.
2. **Given** no custom provision file exists in the repo, **When** `setup-host.sh` runs, **Then** standard provisioning completes normally with no errors or warnings about the missing file.
3. **Given** a custom provision file exists, **When** `setup-host.sh` runs and the custom script fails (non-zero exit), **Then** the setup process reports the failure clearly and does not take a baseline snapshot with a broken state.
4. **Given** a custom provision file exists, **When** a new container is created, **Then** the custom tools are available to the `ubuntu` user (not just root) after setup completes.

---

### User Story 2 - Edit Custom Provision File via CLI Command (Priority: P2)

A server admin wants to create or edit their custom provision file but doesn't want to remember the repo's location or the exact filename. They run `dilxc.sh customize`, which opens `custom-provision.sh` in their default editor. If the file doesn't exist yet, the command creates it with a starter template (shebang, comment header explaining usage) before opening. This gives the user a single, discoverable entry point for managing their customizations.

**Why this priority**: Discoverability and ease of use — without this, users must know the repo path and filename. This is a small addition but significantly improves the experience, and it pairs naturally with the P1 mechanism.

**Independent Test**: Can be tested by running the CLI command and verifying it opens the correct file in the user's editor, creating a valid starter file if none existed.

**Acceptance Scenarios**:

1. **Given** no custom provision file exists, **When** the user runs the edit command, **Then** a new file is created with a starter template and opened in the user's default editor.
2. **Given** a custom provision file already exists, **When** the user runs the edit command, **Then** the existing file is opened in the user's default editor without modification.
3. **Given** the user has the `EDITOR` environment variable set, **When** the edit command runs, **Then** the file opens in that editor.
4. **Given** no `EDITOR` environment variable is set, **When** the edit command runs, **Then** the system falls back to a common default editor (e.g., `nano` or `vi`).

---

### User Story 3 - Coding Agent Generates Custom Provision Scripts (Priority: P3)

> *Priority unchanged — remains P3 despite new P2 insertion above.*

A server admin wants to add tools to their container environment but doesn't want to manually write shell scripts. They describe what they want in natural language to a coding agent (e.g., Claude Code). The agent, guided by instructions in CLAUDE.md, produces a correctly formatted custom provision file that follows the project's conventions and will execute successfully during container setup.

**Why this priority**: This makes the custom provisioning feature accessible to users who aren't comfortable writing provisioning shell scripts. It depends on the P1 mechanism existing first.

**Independent Test**: Can be tested by asking a coding agent to "add Spec Kit to my container" and verifying the agent produces a valid custom provision file that follows the documented format and conventions.

**Acceptance Scenarios**:

1. **Given** a coding agent has access to the repo's CLAUDE.md, **When** a user describes a tool they want installed (e.g., "I want Spec Kit in all my containers"), **Then** the agent generates a correctly formatted custom provision file.
2. **Given** the generated custom provision file, **When** it is executed during container setup, **Then** the described tool is installed and configured correctly.
3. **Given** a user describes multiple tools or customizations, **When** the coding agent generates the script, **Then** each tool's installation is organized as a clearly labeled section within the file.

---

### User Story 4 - Re-provision with Custom Scripts (Priority: P4)

A server admin updates their custom provision file (adding a new tool or changing a configuration). They re-provision their existing container. The updated customizations are applied without needing to destroy and recreate the container.

**Why this priority**: Supports iterative workflow — users shouldn't need to tear down containers to add new tools. Lower priority because container recreation is an acceptable workaround.

**Independent Test**: Can be tested by modifying the custom provision file to add a new tool, re-running provisioning, and verifying the new tool is available.

**Acceptance Scenarios**:

1. **Given** an existing running container and an updated custom provision file, **When** the user re-provisions the container (via the existing re-provision workflow), **Then** the updated custom commands execute successfully.
2. **Given** a custom provision file with idempotent commands, **When** re-provisioning runs the custom script again, **Then** already-installed tools remain functional and no duplicate installations occur.

---

### Edge Cases

- What happens when the custom provision file has a syntax error (e.g., invalid bash)? The setup process fails with a clear error identifying the custom script as the source, and no baseline snapshot is taken.
- What happens when the custom provision file tries to install a package that doesn't exist or a URL that is unreachable? The script fails with a non-zero exit code, and the setup process reports the failure.
- What happens when the custom provision file requires interactive input (e.g., a prompt)? The script hangs or fails. CLAUDE.md instructions must document that custom scripts should use non-interactive flags (e.g., `apt-get install -y`, `DEBIAN_FRONTEND=noninteractive`).
- What happens when the custom provision file modifies system files that conflict with standard provisioning (e.g., overwriting `.bashrc`)? The custom script runs after standard provisioning, so its changes take precedence. CLAUDE.md instructions should warn against overwriting files managed by the standard provisioning script.
- What happens when the custom provision file is present but empty? The setup process completes normally — an empty script is a valid bash script that exits 0.
- What happens when the user runs the edit command but no editor is available (no `EDITOR` set and no common editors installed)? The command reports a clear error message suggesting the user set the `EDITOR` variable.
- What happens when the user runs the edit command and the starter template already exists but hasn't been modified? The existing file is opened — the command does not overwrite or regenerate the template.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: The system MUST look for an optional custom provision file at `custom-provision.sh` in the repo root.
- **FR-002**: `provision-container.sh` MUST check for `/tmp/custom-provision.sh` at the end of its execution and invoke it if present, so that custom provisioning runs as part of the same provisioning process.
- **FR-003**: The custom provision file MUST execute with the same environment and permissions as the standard provisioning script (root, inside the container, with network access).
- **FR-004**: The system MUST skip custom provisioning silently (no error, no warning) when the custom provision file does not exist.
- **FR-005**: The system MUST report a clear error message and halt setup (before taking the baseline snapshot) if the custom provision script exits with a non-zero status.
- **FR-006**: The custom provision file MUST be a standard bash script that users can write or that coding agents can generate.
- **FR-007**: The repo's CLAUDE.md MUST contain a dedicated section with instructions that guide coding agents in generating correctly formatted custom provision files, including: the file location, execution context (root inside Ubuntu 24.04 container), available package managers and tools after standard provisioning, idempotency requirements, non-interactive execution requirements, and conventions to follow.
- **FR-008**: The CLAUDE.md instructions MUST document that custom provision scripts should be idempotent so they work correctly during both initial setup and re-provisioning.
- **FR-009**: The re-provisioning workflow (documented in CLAUDE.md) MUST push `custom-provision.sh` to `/tmp/custom-provision.sh` alongside the standard provision script. Since `provision-container.sh` invokes the custom script at its end (FR-002), re-provisioning inherits custom script execution automatically.
- **FR-010**: `setup-host.sh` MUST push `custom-provision.sh` (if it exists) to `/tmp/custom-provision.sh` inside the container before executing `provision-container.sh`, following the existing `lxc file push` pattern.
- **FR-011**: The management CLI MUST provide a `customize` subcommand (`dilxc.sh customize`) that opens `custom-provision.sh` in the user's default editor, creating the file with a starter template if it does not yet exist.
- **FR-012**: The starter template created by the edit command MUST include a shebang line, a comment header explaining the file's purpose and execution context, and an example section structure — giving the user a valid starting point.
- **FR-013**: The custom provision file MUST be listed in the repo's `.gitignore` so that user-specific customizations are not accidentally committed to the shared repository.
- **FR-014**: The edit command MUST use the `EDITOR` environment variable when set, falling back to a common default editor when it is not.

### Key Entities

- **Custom Provision File**: A user-authored bash script in the repo root containing additional provisioning commands. Executed after standard provisioning inside the container. Must be idempotent.
- **CLAUDE.md Agent Instructions**: A dedicated section in CLAUDE.md that describes the custom provision file format, execution context, and conventions, enabling coding agents to generate valid custom provision scripts from natural language descriptions.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A user can add a custom provision file and have its tools available in a newly created container without any manual post-setup steps.
- **SC-002**: Omitting the custom provision file causes no change in behavior — existing setups continue to work identically.
- **SC-003**: A coding agent (given the repo's CLAUDE.md) can produce a working custom provision file from a natural language description on the first attempt for common tool installations.
- **SC-004**: Re-provisioning an existing container applies custom provisioning changes without requiring container recreation.
- **SC-005**: A failed custom provision script produces an error message that identifies the failure source (custom provisioning, not standard provisioning) so the user knows where to look.
- **SC-006**: A user can create and start editing their custom provision file with a single CLI command, without needing to know the repo path or filename.
- **SC-007**: The custom provision file is excluded from version control by default, preventing accidental commits of user-specific customizations.

## Assumptions

- The custom provision file is a single file (not a directory of scripts). A single file keeps the mechanism simple and predictable.
- The file uses bash syntax consistent with Ubuntu 24.04's default bash version.
- The custom provision file runs as root inside the container, same as `provision-container.sh`.
- Package installation via `apt-get` is the primary method for system packages; `npm`, `pip`/`uv`, and `cargo` are also available after standard provisioning.
- Users are responsible for ensuring their custom commands are idempotent (the CLAUDE.md instructions will document this requirement and provide guidance).
- The custom provision file is not parameterized — it runs the same way for every container created from this repo.

## Clarifications

### Session 2026-02-12

- Q: What should the custom provision file be named? → A: `custom-provision.sh` (mirrors `provision-container.sh` naming convention)
- Q: How should the custom provision script be integrated into the execution flow? → A: Built-in — `provision-container.sh` checks for `/tmp/custom-provision.sh` at its end and invokes it if present. `setup-host.sh` pushes both files before running `provision-container.sh`.
- Q: What should the CLI edit subcommand be named? → A: `customize` (verb-style, matches original user description)
