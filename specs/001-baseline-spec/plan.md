# Implementation Plan: Docker-in-LXC

**Branch**: `001-baseline-spec` | **Date**: 2026-02-11 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/001-baseline-spec/spec.md`

**Note**: This is a baseline spec — the system is already built. This plan documents the architecture, validates it against the constitution, and produces design artifacts for future development.

## Summary

Three bash scripts provide an LXD-based sandbox for running Claude Code autonomously on an Ubuntu homelab server. `setup-host.sh` creates and provisions a container, `provision-container.sh` installs tooling inside it, and `dilxc.sh` wraps day-to-day operations. The container IS the sandbox — btrfs snapshots provide rollback safety, the project is mounted read-only with a writable working copy, and Claude Code runs with `--dangerously-skip-permissions` because the container is disposable.

## Technical Context

**Language/Version**: Bash (GNU Bash, no minimum version requirement beyond Ubuntu 24.04 default)
**Primary Dependencies**: LXD (`lxc` CLI), rsync, btrfs (via LXD storage pool)
**Container Tooling**: Docker CE + compose, Node.js 22 LTS, Claude Code (npm), uv, Spec Kit (`specify-cli`), git, ripgrep, fd-find, jq, tmux, htop, postgresql-client
**Storage**: btrfs snapshots via `lxc snapshot` / `lxc restore`
**Testing**: Manual acceptance testing against user story scenarios (no test framework — plain bash scripts)
**Target Platform**: Ubuntu homelab server with LXD installed and btrfs storage pool
**Project Type**: Single — three bash scripts at repository root
**Performance Goals**: N/A — interactive CLI tool, no throughput targets
**Constraints**: Must coexist with Docker and other LXD containers on shared host; UFW firewall rules must account for Docker iptables interference
**Scale/Scope**: Single-user homelab; multiple containers via `DILXC_CONTAINER` env var

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| # | Principle | Status | Evidence |
|---|-----------|--------|----------|
| I | Shell Scripts Only | PASS | Three bash scripts, no frameworks or compiled languages on the host side |
| II | Three Scripts, Three Execution Contexts | PASS | `setup-host.sh` (host, creates container), `provision-container.sh` (inside container), `dilxc.sh` (host, day-to-day) |
| III | Readability Wins Over Cleverness | PASS | Explicit variable names, no chained pipelines, step-by-step progress output |
| IV | The Container Is the Sandbox | PASS | No inner sandboxing layers; `--dangerously-skip-permissions` used because container is disposable |
| V | Don't Touch the Host | PASS | All `lxc` commands scoped to `$DILXC_CONTAINER`; no host config modifications |
| VI | LXD Today, Incus Eventually | PASS | Uses `lxc` CLI only; no LXD-specific API calls; Incus noted as future target in spec |
| VII | Idempotent Provisioning | PASS | `gpg --dearmor --yes`, device removal before re-add, `DEBIAN_FRONTEND=noninteractive` |
| VIII | Detect and Report, Don't Auto-Fix | PASS | `health-check` reports pass/fail; `require_container`/`require_running` report and exit, don't auto-start |
| IX | Shell Parity: Bash Always, Fish Opt-In | PASS | Bash config always written; fish only with `--fish`; both have same aliases, functions, PATH |
| X | Error Handling | PASS | `set -euo pipefail` in setup/provision; `dilxc.sh` handles failures per-command |
| XI | Rsync Excludes Stay Synchronized | PASS | Same 4 excludes (`node_modules`, `.git`, `dist`, `build`) in bash function, fish function, and `dilxc.sh sync` |
| XII | Keep Arguments Safe | PASS | `printf '%q'` used in `cmd_claude_run`, `cmd_exec`, and `cmd_docker` |

**Gate Result**: ALL PASS — no violations, no complexity tracking needed.

## Project Structure

### Documentation (this feature)

```text
specs/001-baseline-spec/
├── plan.md              # This file
├── research.md          # Phase 0: architectural decisions documented
├── data-model.md        # Phase 1: entities, states, relationships
├── quickstart.md        # Phase 1: getting started guide
├── contracts/           # Phase 1: CLI interface contracts
│   ├── setup-host.md    #   setup-host.sh flags and behavior
│   ├── provision.md     #   provision-container.sh flags and behavior
│   └── sandbox.md       #   dilxc.sh subcommands and behavior
└── tasks.md             # Phase 2 output (/speckit.tasks - NOT created by /speckit.plan)
```

### Source Code (repository root)

```text
./
├── setup-host.sh          # Host setup script (201 lines)
├── provision-container.sh # Container provisioning script (188 lines)
├── dilxc.sh             # Day-to-day management wrapper (376 lines)
├── CLAUDE.md              # Agent instructions
├── README.md              # User-facing documentation
├── constitution-input.md  # Constitution source material
├── spec-input.md          # Spec source material
└── .gitignore             # Local settings exclusion
```

**Structure Decision**: Flat root layout — three executable scripts with supporting documentation. No `src/` or `tests/` directories. This is appropriate for a pure-bash project with no build step, no dependencies, and no test framework. The scripts ARE the product.

## Complexity Tracking

> No violations — table not needed.
