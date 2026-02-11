<!--
  Sync Impact Report
  ==================
  Version change: N/A → 1.0.0 (initial ratification)

  Added principles:
    I.    Shell Scripts Only
    II.   Three Scripts, Three Execution Contexts
    III.  Readability Wins Over Cleverness
    IV.   The Container Is the Sandbox
    V.    Don't Touch the Host
    VI.   LXD Today, Incus Eventually
    VII.  Idempotent Provisioning
    VIII. Detect and Report, Don't Auto-Fix
    IX.   Shell Parity: Bash Always, Fish Opt-In
    X.    Error Handling
    XI.   Rsync Excludes Stay Synchronized
    XII.  Keep Arguments Safe

  Added sections:
    - Architecture & Execution Contexts
    - Development Workflow
    - Governance

  Removed sections: None (initial creation)

  Templates requiring updates:
    - .specify/templates/plan-template.md ✅ No updates needed
    - .specify/templates/spec-template.md ✅ No updates needed
    - .specify/templates/tasks-template.md ✅ No updates needed
    - .specify/templates/agent-file-template.md ✅ No updates needed

  Follow-up TODOs: None
-->
# Claude LXC Sandbox Constitution

## Core Principles

### I. Shell Scripts Only

The entire project is three bash scripts. No frameworks, no compiled
languages, no package managers for the project itself. Dependencies exist
only inside the container (Node.js, Docker, uv, etc.) — the host-side
tooling is plain bash.

### II. Three Scripts, Three Execution Contexts

Each script runs in exactly one place:

- `setup-host.sh` — runs on the host, creates and provisions the container
- `provision-container.sh` — runs inside the container, installs tools and
  configures the user environment
- `sandbox.sh` — runs on the host, wraps `lxc` commands for day-to-day use

When adding functionality, it MUST go into the appropriate existing script.
New scripts MUST NOT be created unless there is a genuinely new execution
context that does not fit any of the three above.

### III. Readability Wins Over Cleverness

When readable and concise conflict, choose readable. Spell things out. Use
explicit variable names. Avoid chained pipelines that require mental
unpacking. The scripts MUST be understandable by someone reading them for
the first time.

### IV. The Container Is the Sandbox

LXD is the security boundary. Sandboxing layers inside the container
(firejail, AppArmor profiles, restricted users) MUST NOT be added. Claude
Code runs with `--dangerously-skip-permissions` because the container
itself is disposable. If something goes wrong, restore a snapshot.

### V. Don't Touch the Host

The host is a shared machine running other services — Docker stacks, other
LXD containers, production workloads. Every `lxc` command MUST be scoped
to `$CLAUDE_SANDBOX`. Scripts MUST NOT operate on other containers, modify
host-level config, or assume the sandbox is the only thing running. Each
container is independent: one project mount, its own snapshots, no
cross-container state.

### VI. LXD Today, Incus Eventually

The project currently targets LXD (`lxc` CLI). Incus (the community fork)
is a planned future target. LXD-specific assumptions MUST be avoided where
possible — the `lxc` and `incus` CLIs are nearly identical. Container
management commands MUST be kept clean and isolable so migrating to Incus
is a find-and-replace, not a rewrite.

### VII. Idempotent Provisioning

Re-running `provision-container.sh` on an existing container MUST be safe.
Use `--yes` flags on key operations (like `gpg --dearmor --yes`), avoid
appending duplicate config blocks, and do not fail on "already exists"
conditions. The user's escape hatch is deleting the container and running
`setup-host.sh` again, but re-provisioning SHOULD work when possible.

### VIII. Detect and Report, Don't Auto-Fix

When something is wrong (container not running, network down, Docker
broken), tell the user what failed and what command to run. Scripts MUST
NOT silently retry, auto-start containers, or guess at fixes. The
`health-check` command is the model: check each thing, report pass/fail,
let the user decide.

### IX. Shell Parity: Bash Always, Fish Opt-In

Bash configuration is always written. Fish is only configured when the
`--fish` flag is passed. When both exist, they MUST stay in sync — same
aliases and abbreviations, same helper functions, same PATH entries. Any
change to the bash config section MUST be checked against the fish
equivalent and updated if one exists.

### X. Error Handling

`setup-host.sh` and `provision-container.sh` use `set -euo pipefail`. If
setup fails partway, the recovery path is deleting the container and
starting over, not trying to resume. `sandbox.sh` does NOT use `set -e`
because it needs to handle failures gracefully in individual commands.

### XI. Rsync Excludes Stay Synchronized

The rsync exclude list (`node_modules`, `.git`, `dist`, `build`) appears
in three places: the bash `sync-project` function, the fish `sync-project`
function, and the `sandbox.sh sync` command. These three lists MUST always
match. Any change to one MUST be propagated to the other two.

### XII. Keep Arguments Safe

`printf '%q'` MUST be used for shell-escaping user-provided arguments
before passing them through `lxc exec`. This applies to `claude-run`
prompts and `docker` passthrough where arguments may contain spaces and
special characters.

## Architecture & Execution Contexts

The project follows a strict three-script architecture with clear
boundaries:

- **Host scripts** (`setup-host.sh`, `sandbox.sh`): Interact with LXD via
  the `lxc` CLI. MUST NOT assume anything about the container's internal
  state beyond what `lxc` reports.
- **Container script** (`provision-container.sh`): Runs inside the
  container only. MUST NOT interact with the host or other containers.
- **File strategy inside the container**:
  - `/home/ubuntu/project-src` — Host project mounted read-only
  - `/home/ubuntu/project` — Writable working copy (Claude works here)
  - `/mnt/deploy` — Optional read-write mount for deploying output to host
- **Container name**: Comes from `CLAUDE_SANDBOX` env var (default:
  `claude-sandbox`). Multiple containers are supported by changing this
  variable.
- **Snapshots**: btrfs snapshots via `lxc snapshot` provide instant
  rollback. A `clean-baseline` snapshot is taken at the end of initial
  setup.

## Development Workflow

When editing the scripts, follow these conventions:

- All three scripts use `#!/bin/bash`. Error handling differs by script
  (see Principle X).
- `provision-container.sh` always writes bash config. Fish config is only
  written when `--fish` is passed. When changing aliases or helper
  functions, update both shell configs within that script (see
  Principle IX).
- `sandbox.sh` uses a case-based dispatch pattern for subcommand routing.
  The `require_container` and `require_running` helpers validate container
  state before each command.
- `sandbox.sh` uses `-t` flag on `lxc exec` for interactive commands
  (`shell`, `root`, `login`, `claude`, `claude-resume`) to allocate a TTY.
- When adding new subcommands to `sandbox.sh`, follow the existing pattern:
  add a `cmd_<name>` function and a case entry in the dispatch block.

## Governance

This constitution defines the non-negotiable principles for the Claude LXC
Sandbox project. All contributions — whether from humans or AI agents —
MUST comply with these principles.

- **Supremacy**: This constitution supersedes all other guidance when
  conflicts arise. If a feature request contradicts a principle, the
  principle wins unless the constitution is formally amended first.
- **Amendment procedure**: Amendments require updating this file with a
  version bump, a clear rationale for the change, and propagation to
  dependent artifacts (CLAUDE.md, templates, etc.).
- **Versioning**: Follows semantic versioning. MAJOR for principle removals
  or redefinitions, MINOR for new principles or materially expanded
  guidance, PATCH for clarifications and wording fixes.
- **Compliance review**: Any PR or code review SHOULD verify that changes
  comply with the applicable principles. The `CLAUDE.md` file contains
  operational guidance derived from this constitution.

**Version**: 1.0.0 | **Ratified**: 2026-02-11 | **Last Amended**: 2026-02-11
