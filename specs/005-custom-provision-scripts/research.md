# Research: Custom Provision Scripts

**Feature**: 005-custom-provision-scripts | **Date**: 2026-02-12

## Overview

This feature has no external technology unknowns. All implementation uses existing patterns already established in the codebase (`lxc file push`, `lxc exec`, bash conditionals, case dispatch). Research focused on validating design decisions against the existing codebase.

## Decision 1: Custom script invocation mechanism

**Decision**: `provision-container.sh` checks for `/tmp/custom-provision.sh` at its end and invokes it directly.

**Rationale**: The custom script runs in the same `set -euo pipefail` context as standard provisioning. A non-zero exit automatically halts the entire provisioning process. This leverages bash's existing error propagation — no try/catch or special error handling needed. The error surfaces through `setup-host.sh`'s existing provisioning failure handler (line 183-186), which prints an error and exits before taking the baseline snapshot.

**Alternatives considered**:
- **Source the file** (`source /tmp/custom-provision.sh`): Rejected — sourcing shares variable namespace and could interfere with `provision-container.sh` variables. Executing as a subprocess is cleaner isolation.
- **Separate `lxc exec` call from `setup-host.sh`**: Rejected — spec FR-002 requires `provision-container.sh` to invoke it, keeping the custom script as part of the provisioning process rather than a separate step. This also means re-provisioning (running `provision-container.sh` directly) automatically includes custom scripts.

## Decision 2: File push approach in `setup-host.sh`

**Decision**: Push `custom-provision.sh` to `/tmp/custom-provision.sh` before executing `provision-container.sh`, using the `rm -f` + `push` pattern to work around the known `lxc file push` overwrite issue.

**Rationale**: Matches the existing pattern for `provision-container.sh`. The `rm -f` workaround is already documented in CLAUDE.md as a known issue.

**Alternatives considered**:
- **Push only once without rm**: Rejected — the `lxc file push` overwrite issue (documented in Known Issues) would cause silent failures on re-runs.
- **Push to a different path** (e.g., `/opt/custom-provision.sh`): Rejected — `/tmp/` is the established convention for pushed provisioning scripts, and it's automatically cleaned on reboot.

## Decision 3: `customize` subcommand design

**Decision**: A host-side command that creates/opens `custom-provision.sh` in `$EDITOR` (falling back to `nano`). No container interaction needed.

**Rationale**: The file lives in the repo root on the host — it's pushed into the container only during provisioning. The `$SCRIPT_DIR` variable (already defined in `dilxc.sh`) gives the correct path regardless of where the user runs the command from.

**Alternatives considered**:
- **Fall back to `vi` instead of `nano`**: `nano` is more beginner-friendly and is installed by default on Ubuntu 24.04. Users who prefer `vi` will have `$EDITOR` set.
- **Open in a TUI menu**: Over-engineered for a single file. Direct editor opening is simpler and more standard.

## Decision 4: Error message attribution

**Decision**: Rely on `set -euo pipefail` error propagation. The "Running custom provisioning" echo before execution and the existing `setup-host.sh` error handler ("Error: provisioning failed") together identify the failure source.

**Rationale**: The user sees the "Running custom provisioning" message before execution. If the script fails, bash prints the failing command and line. Combined with the setup-host.sh error handler, this satisfies SC-005 (error identifies failure source) without adding a special error wrapper.

**Alternatives considered**:
- **Wrap in a subshell with custom error trap**: Over-engineered. The existing `set -euo pipefail` already provides the needed behavior.

## Decision 5: Gitignore strategy

**Decision**: Add `custom-provision.sh` to `.gitignore` at the repo root.

**Rationale**: FR-013 requires the custom provision file to be excluded from version control. The file contains user-specific customizations that shouldn't be committed to the shared repository. Users who want to version-control their customizations can use `git add -f`.
