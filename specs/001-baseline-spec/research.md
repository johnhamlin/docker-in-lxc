# Research: Docker-in-LXC

**Branch**: `001-baseline-spec` | **Date**: 2026-02-11
**Context**: Baseline spec — documenting decisions already made in the existing implementation.

## Decision 1: LXD System Containers as the Sandbox Boundary

**Decision**: Use LXD system containers (not Docker containers, VMs, or chroot) as the isolation boundary for Claude Code.

**Rationale**: LXD system containers provide full OS-level isolation with a shared kernel — Claude Code gets a complete Ubuntu environment with systemd, Docker support via nesting, btrfs snapshots for instant rollback, and near-native performance. Docker containers can't run Docker inside (without Docker-in-Docker hacks), VMs are too heavy for a homelab, and chroot provides no real isolation.

**Alternatives considered**:
- **Docker containers**: Can't nest Docker cleanly; no systemd; no btrfs snapshots of the whole environment; application containers aren't designed for interactive sessions.
- **VMs (QEMU/KVM)**: Full isolation but heavy — slow to create, no instant snapshot restore, more resource overhead than needed for a single-user homelab.
- **Firecracker/microVMs**: Good isolation-to-overhead ratio but complex setup; no native btrfs snapshot integration; overkill for this use case.
- **chroot/namespaces directly**: Insufficient isolation; no snapshot support; manual networking.

## Decision 2: Read-Only Mount + Writable Copy Architecture

**Decision**: Mount the host project read-only at `/home/ubuntu/project-src`, rsync to a writable copy at `/home/ubuntu/project`.

**Rationale**: The read-only mount prevents Claude from modifying the host filesystem. The writable copy gives Claude full access to work. Destructive sync (`--delete`) provides a clean reset path. Changes are preserved via git (push to GitHub from inside the container).

**Alternatives considered**:
- **Read-write mount**: Simpler but defeats the safety purpose — Claude could modify host files directly.
- **Copy-on-write overlay**: More efficient than rsync but adds complexity; overlayfs on top of btrfs adds a layer; harder to reason about what changed.
- **Git clone inside container**: Would work but requires the container to have git credentials for private repos; the mount approach works for any directory.

## Decision 3: Bash-Only Host Tooling

**Decision**: All host-side tooling is plain bash scripts. No Python, no Go, no package managers.

**Rationale**: Zero dependencies on the host beyond bash and LXD. The scripts are simple wrappers around `lxc` commands — adding a language runtime or package manager would be over-engineering. Constitution Principle I codifies this.

**Alternatives considered**:
- **Python CLI (Click/Typer)**: Better argument parsing and testing but adds a Python dependency on the host.
- **Go binary**: Single binary distribution but requires a build step; overkill for wrapping `lxc` commands.
- **Makefile**: Common for this type of tooling but less readable than a bash case statement for subcommand dispatch.

## Decision 4: `--dangerously-skip-permissions` Inside the Container

**Decision**: Claude Code runs with `--dangerously-skip-permissions` by default.

**Rationale**: The container IS the sandbox. Everything inside is disposable and restorable via snapshots. Adding permission prompts inside a sandboxed environment would defeat the purpose of the tool — autonomous operation in a safe, isolated environment.

**Alternatives considered**:
- **Normal permissions mode**: Would require human approval for every file operation, defeating the autonomous use case.
- **Custom allowlist**: Would require maintaining a permissions config; adds complexity for no safety benefit inside a disposable container.

## Decision 5: UFW for Firewall Coexistence with Docker

**Decision**: Use UFW rules (before.rules + after.rules) to ensure LXD bridge traffic is not blocked by Docker's iptables rules.

**Rationale**: Docker adds iptables rules that block traffic not destined for Docker networks. The LXD bridge (lxdbr0 at 10.200.12.0/24) gets caught in these rules. UFW's rule files persist across reboots and integrate cleanly with Docker's DOCKER-USER chain.

**Alternatives considered**:
- **netfilter-persistent**: Already in `rc` (removed) state on this host; would conflict with UFW management.
- **Manual iptables rules**: Don't persist across reboots without a persistence mechanism.
- **Disabling Docker's iptables integration**: Would break Docker networking for the host's Docker stacks.
- **Separate network namespace**: More complex; the UFW rules are a simpler, well-understood solution.

## Decision 6: Fish Shell as Opt-In

**Decision**: Bash is always configured; fish is only installed and configured when `--fish` is passed.

**Rationale**: Bash is the universal default. Fish is a better interactive shell but adds installation time and configuration surface area. Making it opt-in keeps the default setup fast and simple while supporting users who prefer fish.

**Alternatives considered**:
- **Fish by default**: Would surprise users who expect bash; adds ~30s to provisioning for everyone.
- **Zsh option**: Could be added similarly but wasn't requested; the pattern supports adding more shells later.
- **No fish support**: Simpler but the project author uses fish.

## Decision 7: No Test Framework

**Decision**: No automated test suite. Acceptance testing is manual, following the user story scenarios in the spec.

**Rationale**: The scripts are infrastructure automation that interacts with LXD, Docker, and network configuration. Meaningful tests would require a running LXD host with btrfs storage — essentially the target environment itself. Mock-based unit tests for bash scripts provide low value relative to their maintenance cost. Manual acceptance testing against the spec's scenarios is more practical.

**Alternatives considered**:
- **BATS (Bash Automated Testing System)**: Could test argument parsing and output formatting but can't test actual LXD operations without a real environment.
- **Integration test VM**: Could provision a VM with LXD and run end-to-end tests, but adds significant CI complexity for a three-script project.
- **ShellCheck + linting only**: ShellCheck is valuable and should be adopted, but it's linting, not testing.

## Decision 8: Destructive Sync (rsync --delete)

**Decision**: `sync-project` and `dilxc.sh sync` use `rsync --delete`, removing any files in the working copy that don't exist in the source mount.

**Rationale**: Sync is a full reset operation — the working copy should match the source exactly. This is the safest model: the user knows exactly what they'll get after a sync. The workflow for preserving container changes is to commit and push to GitHub before syncing.

**Alternatives considered**:
- **Non-destructive sync (no --delete)**: Leaves orphan files; creates confusion about what's in the working copy vs. what's on the host.
- **Interactive/dry-run mode**: Adds complexity; the use case is "give me a clean slate."
- **Git-based sync**: Would require git configuration in both places; the mount approach is simpler and works for any project type.
