# Feature Specification: Slim Default Provision

**Feature Branch**: `006-slim-default-provision`
**Created**: 2026-02-12
**Status**: Draft
**Input**: User description: "Remove opinionated tools from default provisioning, create RECIPES.md for reinstallation examples, link from README, add Spec Kit to personal custom-provision.sh"

## Clarifications

### Session 2026-02-12

- Q: How persistent is container storage — can users just shell in and install tools manually? → A: Fully persistent. LXC system containers keep all changes across reboots/stops. Manual installs only reset on snapshot restore or container deletion.
- Q: Does this change the purpose of RECIPES.md? → A: Yes. RECIPES.md is for tools users want in **every** container (via `custom-provision.sh`), not for one-off installs. One-off tools can be installed manually in each container's shell.
- Q: Should we recommend snapshots after manual tool installs? → A: No. Users familiar with the snapshot workflow can figure this out. Keep it light — at most a brief mention, not a formal recommendation.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Leaner Default Container (Priority: P1)

A new user runs `setup-host.sh` to create a sandbox container. The container provisions with only the essential tools needed for Claude Code and Docker workflows. Opinionated tools like uv, Spec Kit, and postgresql-client are not installed by default, resulting in a faster provisioning process and a container that doesn't include tools the user may never use. Users who need additional tools for a specific project can install them manually inside that container's shell — the changes persist for the life of the container (or until a snapshot restore).

**Why this priority**: This is the core change — removing opinionated tools from the default install reduces setup time, container size, and avoids imposing tool preferences on new users.

**Independent Test**: Can be fully tested by running `setup-host.sh` and verifying that uv, Spec Kit, and postgresql-client are not present in the resulting container, while Docker, Node.js, Claude Code, and other essential tools still work.

**Acceptance Scenarios**:

1. **Given** a fresh host with LXD installed, **When** the user runs `setup-host.sh -p /path/to/project`, **Then** the container is provisioned without uv, Spec Kit, or postgresql-client
2. **Given** a newly provisioned container, **When** the user runs `claude --version`, `docker --version`, and `node --version` inside it, **Then** all three tools are available and functional
3. **Given** a newly provisioned container, **When** the user checks for `uv`, `specify`, or `psql`, **Then** none of these commands are found

---

### User Story 2 - Recipes for Persistent Custom Tools (Priority: P2)

A user who wants certain tools available in **every** container they create (not just one-off installs) can find ready-to-use snippets in a RECIPES.md file. Each recipe is designed to be pasted into `custom-provision.sh` so it runs automatically during provisioning and survives snapshot restores. RECIPES.md explains the three-tier tool installation model:

1. **Default provisioning** — tools every developer needs (Docker, Node.js, Claude Code, git, etc.)
2. **Custom provisioning** (`custom-provision.sh`) — tools you personally want in every container, re-applied on each provision and snapshot restore
3. **Manual install** — one-off tools for a specific project, installed ad hoc via `dilxc shell`

**Why this priority**: Users need to understand *where* each tool belongs. Recipes bridge the gap between a lean default and personal customization, and the three-tier model helps users choose the right approach.

**Independent Test**: Can be tested by copying a recipe into `custom-provision.sh`, running provisioning, and verifying the tool installs correctly.

**Acceptance Scenarios**:

1. **Given** a RECIPES.md file exists in the repository root, **When** a user reads it, **Then** they find the three-tier tool installation model explained clearly
2. **Given** RECIPES.md, **When** a user reads a recipe (e.g., Spec Kit), **Then** it follows `custom-provision.sh` conventions (idempotent, non-interactive, section headers) and can be pasted directly into their custom script
3. **Given** a recipe from RECIPES.md, **When** a user copies it into their `custom-provision.sh` and provisions a container, **Then** the tool installs successfully
4. **Given** RECIPES.md, **When** a user reads the README, **Then** they find a link directing them to RECIPES.md

---

### User Story 3 - Updated Documentation (Priority: P3)

The README, CLAUDE.md, and other project documentation accurately reflect the new default toolset and the three-tier installation model. References to uv and Spec Kit as default-installed tools are removed or updated to indicate they are optional via custom provisioning or manual install.

**Why this priority**: Documentation must match reality. Users reading the README should not expect tools that are no longer installed by default.

**Independent Test**: Can be tested by reading all documentation files and verifying no claims are made about tools that are no longer installed by default.

**Acceptance Scenarios**:

1. **Given** the updated README, **When** a user reads the "What Gets Installed" section, **Then** uv and Spec Kit are not listed as default tools
2. **Given** the updated README, **When** a user looks for optional tool installation, **Then** they are directed to RECIPES.md and the custom provisioning mechanism
3. **Given** the updated CLAUDE.md, **When** Claude Code reads it for project context, **Then** the description accurately reflects which tools are installed by default

---

### User Story 4 - Personal Custom Provision with Spec Kit (Priority: P4)

The project maintainer (john) has a personal `custom-provision.sh` that includes Spec Kit installation, so his existing and future containers continue to have Spec Kit available without relying on the default provisioning.

**Why this priority**: This is a personal convenience item for the maintainer. It demonstrates the custom provisioning workflow and ensures no disruption to the maintainer's workflow.

**Independent Test**: Can be tested by verifying `custom-provision.sh` exists with Spec Kit installation commands and that it follows the documented conventions.

**Acceptance Scenarios**:

1. **Given** the repository root, **When** the maintainer checks for `custom-provision.sh`, **Then** it exists and contains commands to install uv and Spec Kit
2. **Given** the `custom-provision.sh` file, **When** it is executed inside a container, **Then** uv and Spec Kit are installed and available on the PATH

---

### Edge Cases

- What happens if a user has an existing container provisioned with the old defaults (uv/Spec Kit installed)? Re-provisioning should not break existing installations — the tools simply won't be reinstalled if removed, but leftover binaries remain.
- What happens if a user's `custom-provision.sh` depends on uv being pre-installed? This would fail. Recipes must be self-contained and install their own dependencies (e.g., a Spec Kit recipe must install uv first).
- What happens if the `~/.local/bin` PATH entry is removed from bash/fish config? Custom tools installed via `uv tool install` or `pip install --user` would not be found. The PATH entry should remain since it is useful beyond just uv/Spec Kit.
- What happens if a user manually installs a tool, then restores a snapshot? The manually installed tool is lost. This is expected behavior — users who want tools to survive restores should use `custom-provision.sh` instead.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Default provisioning MUST NOT install uv or Spec Kit
- **FR-002**: Default provisioning MUST NOT install postgresql-client
- **FR-003**: Default provisioning MUST continue to install Docker CE, Node.js 22, Claude Code, GitHub CLI, and common dev tools (git, build-essential, jq, ripgrep, fd-find, htop, tmux)
- **FR-004**: The `~/.local/bin` PATH entry in bash and fish configs MUST be preserved (useful for user-installed tools beyond uv)
- **FR-005**: A RECIPES.md file MUST exist in the repository root with ready-to-paste snippets for `custom-provision.sh`
- **FR-006**: RECIPES.md MUST explain the three-tier tool installation model (default provisioning, custom provisioning, manual install)
- **FR-007**: Each recipe MUST follow the `custom-provision.sh` conventions: idempotent, non-interactive, with section headers and result messages
- **FR-008**: The README MUST link to RECIPES.md from a relevant section
- **FR-009**: The README MUST be updated to remove uv and Spec Kit from the default tool descriptions
- **FR-010**: CLAUDE.md MUST be updated to reflect the changed default toolset
- **FR-011**: A `custom-provision.sh` file MUST be created in the repository root containing Spec Kit and uv installation
- **FR-012**: The final verification output in `provision-container.sh` MUST NOT reference uv or Spec Kit
- **FR-013**: The SSH agent socket export and Claude Code aliases in bash/fish configs MUST remain unchanged

## Assumptions

- LXC system containers have fully persistent storage — all changes survive reboots and stops/starts, only resetting on snapshot restore or container deletion.
- The `~/.local/bin` PATH addition remains useful for user-installed tools and should stay in the default config even without uv.
- Fish shell remains opt-in via `--fish` flag — this is not an opinionated tool since it's explicitly requested.
- GitHub CLI (`gh`) is essential for the git forge auth feature and should remain in the default install.
- `fd-find` is a common enough dev tool to remain in the default install alongside ripgrep.
- The existing `custom-provision.sh` is gitignored (per CLAUDE.md), so creating it does not affect other users.
- Users comfortable with LXD snapshots do not need formal guidance to snapshot after manual tool installs.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: A freshly provisioned container does not contain uv, Spec Kit, or postgresql-client
- **SC-002**: Provisioning no longer downloads or installs uv, Spec Kit, or postgresql-client
- **SC-003**: All recipes in RECIPES.md produce working installations when used in `custom-provision.sh`
- **SC-004**: Zero references to uv or Spec Kit as "default" or "pre-installed" exist in README.md or CLAUDE.md
- **SC-005**: The maintainer's `custom-provision.sh` successfully installs Spec Kit when executed
- **SC-006**: RECIPES.md clearly communicates the three-tier tool installation model
