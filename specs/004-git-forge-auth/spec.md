# Feature Specification: Git & Forge Authentication Forwarding

**Feature Branch**: `004-git-forge-auth`
**Created**: 2026-02-12
**Status**: Draft
**Input**: User description: "Enable git push/pull and GitHub API operations from inside the LXC container without requiring interactive authentication inside the container. Two complementary mechanisms: SSH agent forwarding for forge-agnostic git transport, and GitHub CLI config forwarding for GitHub API operations."

## User Scenarios & Testing

### User Story 1 - Push and pull code over SSH from inside the container (Priority: P1)

A user (or Claude Code) has developed code inside the container's writable working copy and wants to push it to a remote forge (GitHub, GitLab, Bitbucket, etc.) using SSH. After initial setup, `git push` and `git pull` over SSH work transparently inside the container without any authentication prompts or key management. The host user's SSH agent handles all authentication — private keys never enter the container.

**Why this priority**: This is the core workflow that unblocks the entire develop-in-sandbox-push-to-forge cycle. Without it, code written in the container cannot be shipped.

**Independent Test**: Can be fully tested by running `ssh -T git@github.com` inside the container and verifying it authenticates successfully, then pushing a commit to a test repository.

**Acceptance Scenarios**:

1. **Given** the host user has an SSH agent running with keys loaded and the container was set up with auth forwarding, **When** the container user runs `git push origin main` for a repository with an SSH remote, **Then** the push succeeds without any password or key prompts.
2. **Given** the host user has an SSH agent running with keys loaded, **When** the container user runs `ssh -T git@github.com` (or another forge), **Then** the connection authenticates successfully using the forwarded agent.
3. **Given** a container that has been restored from a snapshot, **When** the container user runs `git push`, **Then** SSH agent forwarding still works (the forwarding configuration survives snapshot restores).

---

### User Story 2 - Use GitHub CLI for API operations from inside the container (Priority: P1)

A user (or Claude Code) wants to create pull requests, list issues, check CI status, and perform other GitHub API operations from inside the container using the `gh` CLI. The host user's existing GitHub authentication is shared read-only with the container, so `gh` commands work without a separate login step.

**Why this priority**: Claude Code uses `gh pr create`, `gh issue list`, and `gh pr checks` extensively during autonomous development. Without this, Claude Code can write code but cannot interact with the forge workflow.

**Independent Test**: Can be fully tested by running `gh auth status` inside the container and verifying it shows authenticated, then running `gh repo view` against a known repository.

**Acceptance Scenarios**:

1. **Given** the host user has authenticated `gh` on the host and the container was set up with auth forwarding, **When** the container user runs `gh auth status`, **Then** it shows the user is authenticated.
2. **Given** the host user has authenticated `gh`, **When** the container user runs `gh pr create --title "test" --body "test"` in a repository, **Then** the PR is created successfully on GitHub.
3. **Given** a container that has been restored from a snapshot, **When** the container user runs `gh auth status`, **Then** GitHub CLI authentication still works.
4. **Given** the `gh` CLI is installed in the container, **When** the container user runs `gh auth setup-git`, **Then** git is configured to use `gh` as the credential helper for HTTPS remotes, enabling `git push` over HTTPS as well.

---

### User Story 3 - Check authentication status from the host (Priority: P2)

A user wants to verify that git and forge authentication are properly configured and working before starting a development session. They run a single diagnostic command from the host that reports the status of both SSH agent forwarding and GitHub CLI authentication.

**Why this priority**: Troubleshooting auth issues is frustrating without visibility. A status command helps users diagnose and resolve problems quickly, following the project's "detect and report" philosophy.

**Independent Test**: Can be fully tested by running the diagnostic command and verifying it reports the correct status for each auth mechanism.

**Acceptance Scenarios**:

1. **Given** SSH agent forwarding and `gh` config are both properly configured, **When** the user runs `./dilxc.sh git-auth`, **Then** the output shows both mechanisms as working with key details (e.g., which SSH identities are available, which GitHub user is authenticated).
2. **Given** the host's SSH agent is not running, **When** the user runs `./dilxc.sh git-auth`, **Then** the output clearly indicates SSH agent forwarding is not working and tells the user how to start their SSH agent and load keys.
3. **Given** the host user has not authenticated `gh`, **When** the user runs `./dilxc.sh git-auth`, **Then** the output clearly indicates GitHub CLI is not authenticated and tells the user to run `gh auth login` on the host.

---

### User Story 4 - Graceful setup when auth prerequisites are missing (Priority: P3)

A user runs the container setup before configuring SSH keys or `gh` authentication on the host. The setup completes successfully, and the auth mechanisms degrade gracefully — they simply don't work until the host-side prerequisites are met. No errors during setup, no broken container state.

**Why this priority**: Users should be able to set up the container first and configure auth later. The setup should never fail due to missing optional auth prerequisites.

**Independent Test**: Can be fully tested by running setup with no SSH agent and no `gh` config, verifying setup completes, then configuring auth on the host and verifying it starts working inside the container.

**Acceptance Scenarios**:

1. **Given** the host user has no SSH agent running (`$SSH_AUTH_SOCK` unset), **When** they run `setup-host.sh`, **Then** setup completes successfully — the LXD proxy device is created with a placeholder path (non-functional). The next `dilxc.sh` command after the user starts their agent will update the device to the real socket path.
2. **Given** the host user has not authenticated `gh` (no `~/.config/gh/` directory), **When** they run `setup-host.sh`, **Then** setup completes successfully — the `gh` config disk device is not created. It will be added automatically by `dilxc.sh` on the next interaction after the user runs `gh auth login` on the host.
3. **Given** setup completed without auth prerequisites, **When** the user later starts their SSH agent and runs `gh auth login` on the host, **Then** auth forwarding begins working inside the container on the next `dilxc.sh` interaction (no manual reconfiguration needed).

---

### Edge Cases

- **SSH agent socket path varies**: Different Ubuntu configurations place the SSH agent socket at different paths (`$SSH_AUTH_SOCK` is not a fixed path). `setup-host.sh` creates the LXD proxy device with whatever path is current (or a placeholder). `dilxc.sh` updates the proxy device's `connect` path to match the current `$SSH_AUTH_SOCK` before each container interaction via a small helper function, so the forwarding stays correct across reboots and session changes.
- **SSH agent not running at container start**: If the host's SSH agent starts after the container, the forwarding should still work — the next `dilxc.sh` command will update the proxy device to the current socket path.
- **Host `gh` config directory doesn't exist**: If `~/.config/gh/` doesn't exist on the host, the mount configuration should be created but will be empty. The `gh` CLI inside the container will report "not authenticated" rather than crashing.
- **`gh` config mounted read-only**: The `gh` CLI cannot write state or cache files to the mounted config directory. This is accepted — `gh` reads auth tokens from `hosts.yml` and works for the operations Claude Code needs (`pr create`, `issue list`, `auth status`). State write failures are silent or produce ignorable warnings.
- **Multiple SSH identities**: The forwarded agent may have multiple keys loaded. The user manages which keys are in their agent — the container simply uses whatever the agent provides.
- **Re-provisioning**: Running `provision-container.sh` again on an existing container must not break existing auth forwarding. The `gh` CLI installation must be idempotent.
- **Existing containers without auth devices**: Running `dilxc.sh update` on a container created before this feature adds the SSH agent proxy device and `gh` config disk device without affecting other container configuration.
- **Container stopped/restarted**: Auth forwarding configuration must survive container restarts without manual re-setup.

## Requirements

### Functional Requirements

- **FR-001**: The system MUST forward the host user's SSH agent into the container so that SSH-based git operations (`git push`, `git pull`, `git clone`) work transparently inside the container.
- **FR-002**: The system MUST ensure that private SSH keys never enter the container — only the agent socket is exposed.
- **FR-003**: The system MUST install the GitHub CLI (`gh`) inside the container during provisioning.
- **FR-004**: The system MUST share the host user's `gh` configuration with the container in read-only mode so that `gh` commands work without a separate authentication step.
- **FR-005**: The system MUST set the `SSH_AUTH_SOCK` environment variable in both bash and fish shell configurations inside the container, pointing to the forwarded agent socket.
- **FR-006**: The SSH agent forwarding and `gh` config sharing configurations MUST survive container snapshot restores (i.e., the configuration must live in the container's host-side metadata, not inside the container filesystem).
- **FR-007**: The system MUST provide a `git-auth` subcommand in `dilxc.sh` that reports the status of both SSH agent forwarding and GitHub CLI authentication, including actionable guidance when something is not configured.
- **FR-008**: The system MUST NOT modify any host-side files (SSH keys, `gh` config, git config) — host credentials are accessed read-only.
- **FR-009**: The `gh` CLI installation in `provision-container.sh` MUST be idempotent — re-running provisioning must not fail or produce duplicate configurations.
- **FR-010**: `dilxc.sh` MUST update the SSH agent proxy device's host-side connect path to match the current `$SSH_AUTH_SOCK` before each container interaction (`shell`, `claude`, `claude-run`, `claude-resume`, `exec`, `login`), via a short helper function (`ensure_auth_forwarding`). The `git-auth` diagnostic also calls this helper internally. This ensures forwarding survives reboots and session changes without re-running setup.
- **FR-011**: Container setup (`setup-host.sh`) MUST complete successfully even when auth prerequisites (SSH agent, `gh` authentication) are not yet configured on the host.
- **FR-012**: The `git-auth` subcommand MUST detect and report problems clearly, with specific remediation instructions, rather than attempting to auto-fix issues.
- **FR-013**: `dilxc.sh init` and `dilxc.sh update` MUST add the SSH agent proxy device and `gh` config disk device to the container if they are missing, enabling auth forwarding to be added to existing containers without recreating them.

### Key Entities

- **SSH Agent Socket**: A Unix socket on the host that provides access to the user's loaded SSH keys. Forwarded into the container at a well-known path. The container's shell environment is configured to use this socket.
- **GitHub CLI Configuration**: The host user's `gh` authentication state (tokens, user info). Mounted read-only into the container so the `gh` CLI can authenticate without a separate login.
- **Auth Forwarding Configuration**: Host-side container metadata (LXD device configs) that defines the SSH socket forwarding and `gh` config mount. Persists across container restarts and snapshot restores.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Users can push code from inside the container to a remote forge in a single `git push` command, with no authentication setup inside the container.
- **SC-002**: Users (and Claude Code) can create pull requests, list issues, and check CI status from inside the container using `gh` CLI commands, with no authentication setup inside the container.
- **SC-003**: Auth forwarding continues working after container snapshot restores without any reconfiguration by the user.
- **SC-004**: A new container setup with auth forwarding adds no more than 30 seconds to the existing setup time.
- **SC-005**: When auth prerequisites are missing, the `git-auth` diagnostic command clearly identifies the issue and provides actionable remediation steps within a single command invocation.

## Assumptions

- The host user is responsible for managing their own SSH keys and SSH agent. The system does not generate, install, or manage SSH keys.
- The host user is responsible for authenticating `gh` on the host. The system only forwards existing authentication.
- SSH agent forwarding works for any forge that supports SSH-based git transport (GitHub, GitLab, Bitbucket, Codeberg, Gitea, Forgejo, bare git servers).
- Only GitHub API operations are supported via `gh` CLI forwarding. Other forge CLIs (e.g., `glab` for GitLab) are out of scope but could be added later.
- `gh auth setup-git` (which configures git's HTTPS credential helper) is available to users inside the container but is not run automatically — users opt in to HTTPS credential forwarding by running it themselves.
- The host's SSH agent socket path is detected via the `$SSH_AUTH_SOCK` environment variable. `setup-host.sh` creates the LXD proxy device with the current path (or a placeholder if unset). `dilxc.sh` updates the device's connect path before each interaction, so the path does not need to be stable across reboots.

## Scope

### In Scope

- SSH agent socket forwarding from host into the container
- `gh` CLI installation inside the container during provisioning
- `gh` configuration directory mounting (read-only) from host into the container
- Shell environment configuration (`SSH_AUTH_SOCK`) in both bash and fish
- `git-auth` diagnostic subcommand in `dilxc.sh`
- Graceful degradation when auth prerequisites are missing
- Idempotent provisioning of `gh` CLI

### Out of Scope

- SSH key generation or management
- Non-GitHub forge CLIs (e.g., `glab` for GitLab)
- Automatic git remote URL rewriting
- GPG or SSH commit signing forwarding
- Automatic HTTPS credential helper setup (user can run `gh auth setup-git` manually)
- Host-side firewall changes for auth forwarding (forwarding uses local Unix sockets and file mounts, not network ports)

## Clarifications

### Session 2026-02-12

- Q: How should the system handle SSH agent socket path instability across reboots/sessions? → A: `dilxc.sh` updates the LXD proxy device's host-side connect path to match the current `$SSH_AUTH_SOCK` before each container interaction, via a short helper function. No symlinks or external state.
- Q: What happens when `$SSH_AUTH_SOCK` is unset at setup time? → A: `setup-host.sh` creates the proxy device with a placeholder path (non-functional). `dilxc.sh` updates it to the real path on first use once the agent is running.
- Q: Should the `gh` config mount be read-only given `gh` writes state/cache? → A: Yes, mount read-only. `gh` reads auth tokens and works for needed operations. State write failures are silent or ignorable. Keeps host credentials safe.
- Q: How do existing containers get auth forwarding? → A: `dilxc.sh init/update` adds the auth LXD devices if missing. No need to recreate the container or add a new subcommand.
