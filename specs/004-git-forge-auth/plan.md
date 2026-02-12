# Implementation Plan: Git & Forge Authentication Forwarding

**Branch**: `004-git-forge-auth` | **Date**: 2026-02-12 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/004-git-forge-auth/spec.md`

## Summary

Enable git push/pull and GitHub API operations from inside the LXC container without interactive authentication. Two complementary mechanisms:

1. **SSH agent forwarding** — An LXD proxy device forwards the host's SSH agent socket (`$SSH_AUTH_SOCK`) into the container at a fixed path (`/tmp/ssh-agent.sock`). `dilxc.sh` updates the host-side socket path before each interaction to handle reboots and session changes.

2. **GitHub CLI config sharing** — An LXD disk device mounts the host's `~/.config/gh` directory read-only into the container, making `gh` commands work transparently. The `gh` CLI is installed during provisioning.

Both mechanisms store configuration in LXD device metadata (not the container filesystem), so they survive snapshot restores. A new `git-auth` diagnostic subcommand reports the status of both mechanisms.

## Technical Context

**Language/Version**: Bash (GNU Bash, Ubuntu 24.04 default)
**Primary Dependencies**: LXD (`lxc` CLI), GitHub CLI (`gh`), OpenSSH (`ssh-agent`, `ssh-add`)
**Storage**: N/A (LXD device metadata in Dqlite database)
**Testing**: Manual acceptance testing (no test framework; bash scripts)
**Target Platform**: Ubuntu homelab server with LXD
**Project Type**: Single (three bash scripts, no source tree)
**Performance Goals**: Auth forwarding adds <1s overhead per `dilxc.sh` command; setup adds <30s
**Constraints**: Host-side scripts are plain bash; no host-side package managers; no host-side file modifications
**Scale/Scope**: Single user, single container at a time

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| # | Principle | Status | Notes |
|---|-----------|--------|-------|
| I | Shell Scripts Only | PASS | All changes are to existing bash scripts |
| II | Three Scripts, Three Execution Contexts | PASS | Each change goes into the correct script: setup-host.sh (device creation), provision-container.sh (gh install + shell env), dilxc.sh (runtime management + diagnostic) |
| III | Readability Wins Over Cleverness | PASS | Helper function is explicit; no chained pipelines |
| IV | The Container Is the Sandbox | PASS | No extra security layers; socket permissions are minimal LXD device config |
| V | Don't Touch the Host | PASS | No host-side directories or files created. SSH agent socket is read (not written). gh config is mounted read-only. Disk device for gh config is only added when the host directory already exists. |
| VI | LXD Today, Incus Eventually | PASS | All `lxc config device` commands have direct `incus` equivalents |
| VII | Idempotent Provisioning | PASS | gh CLI installation uses `curl -o` (overwrites) and `apt-get install -y`; re-provisioning is safe |
| VIII | Detect and Report, Don't Auto-Fix | PASS | `git-auth` subcommand reports status with remediation guidance; does not auto-start agents or auto-login |
| IX | Shell Parity: Bash Always, Fish Opt-In | PASS | `SSH_AUTH_SOCK` added to both bash (always) and fish (when `--fish`) configs |
| X | Error Handling | PASS | setup-host.sh inherits `set -euo pipefail`; dilxc.sh handles failures gracefully in `ensure_auth_forwarding` |
| XI | Rsync Excludes Stay Synchronized | N/A | No rsync changes |
| XII | Keep Arguments Safe | N/A | No user-provided arguments in new commands |

**Post-design re-check**: All gates still PASS. No violations to track.

## Project Structure

### Documentation (this feature)

```text
specs/004-git-forge-auth/
├── plan.md                       # This file
├── research.md                   # Phase 0: design decisions and rationale
├── data-model.md                 # Phase 1: LXD device entities and relationships
├── quickstart.md                 # Phase 1: verification guide
├── contracts/
│   └── cli-interface.md          # Phase 1: subcommand and helper function contracts
└── tasks.md                      # Phase 2 output (NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
# No new files. Modifications to existing scripts only:
setup-host.sh              # Add SSH agent proxy device + gh config disk device
provision-container.sh     # Install gh CLI + add SSH_AUTH_SOCK to shell configs
dilxc.sh                   # Add ensure_auth_forwarding helper, git-auth subcommand,
                           #   update cmd_update, call helper before interactive commands
```

**Structure Decision**: No source tree — this is a three-script bash project. All changes modify existing files. No new scripts are created (Constitution Principle II).

## Implementation Approach

### Phase A: Provisioning (provision-container.sh)

1. **Install GitHub CLI** via apt repository (GPG key + apt source), matching the Docker CE installation pattern. Key is already binary — no `gpg --dearmor` needed.
2. **Add `SSH_AUTH_SOCK` export** to bash config block (always written).
3. **Add `SSH_AUTH_SOCK` set** to fish config block (written when `--fish`).

### Phase B: Container Setup (setup-host.sh)

1. **Add SSH agent proxy device** after existing device creation (project mount). Uses `$SSH_AUTH_SOCK` if set, falls back to `/dev/null` placeholder.
2. **Add gh config disk device** if `~/.config/gh` exists on host. Mounted read-only with `shift=true` for kernel idmapped UID remapping (host UID → container UID).

Note: Since `setup-host.sh` creates a fresh container, devices won't pre-exist and simple `lxc config device add` is sufficient (no remove-then-add needed).

### Phase C: Runtime Management (dilxc.sh)

1. **Add `ensure_auth_forwarding` helper** — updates SSH agent connect path and dynamically adds gh config device. Called before interactive commands.
2. **Add `cmd_git_auth` function** — diagnostic subcommand following `health-check` pattern.
3. **Update `cmd_update`** — after `git pull`, check for and add missing auth devices.
4. **Wire `ensure_auth_forwarding`** into `cmd_shell`, `cmd_claude`, `cmd_claude_run`, `cmd_claude_resume`, `cmd_exec`, `cmd_login`.
5. **Add `git-auth` case** to dispatch block.

### Phase D: Verification

1. Test all acceptance scenarios from the spec.
2. Run `dilxc.sh git-auth` to verify diagnostics.
3. Test graceful degradation (missing prerequisites).
4. Test `dilxc.sh update` on existing container.

## Complexity Tracking

No violations. No entries needed.
