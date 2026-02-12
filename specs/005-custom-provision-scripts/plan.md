# Implementation Plan: Custom Provision Scripts

**Branch**: `005-custom-provision-scripts` | **Date**: 2026-02-12 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/005-custom-provision-scripts/spec.md`

## Summary

Add an optional `custom-provision.sh` file mechanism that lets users define additional tools and configurations to be automatically installed in every new LXC container. The file is pushed into the container by `setup-host.sh` and invoked at the end of `provision-container.sh`. A `customize` CLI subcommand provides a discoverable entry point for creating/editing the file. CLAUDE.md gets agent instructions for generating these scripts from natural language.

## Technical Context

**Language/Version**: Bash (GNU Bash, Ubuntu 24.04 default)
**Primary Dependencies**: LXD (`lxc` CLI), GNU coreutils (`readlink -f`, `dirname`), git
**Storage**: N/A (single optional file in repo root, `/tmp/` inside container)
**Testing**: Manual acceptance testing (no test framework — bash scripts)
**Target Platform**: Ubuntu homelab server (host) + Ubuntu 24.04 LXD container
**Project Type**: Single (three existing bash scripts + CLAUDE.md)
**Performance Goals**: N/A
**Constraints**: N/A
**Scale/Scope**: 3 scripts modified, 1 new file convention, 1 `.gitignore` entry, 1 CLAUDE.md section

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Shell Scripts Only | PASS | All changes are to existing bash scripts + CLAUDE.md. `custom-provision.sh` is user-authored, not a project-maintained script. |
| II. Three Scripts, Three Execution Contexts | PASS | No new maintained scripts. The custom file is invoked BY `provision-container.sh` — an extension of the existing container execution context. |
| III. Readability Wins Over Cleverness | PASS | Simple if-exists-then-execute pattern. |
| IV. The Container Is the Sandbox | PASS | Custom scripts run inside the container only. |
| V. Don't Touch the Host | PASS | No host modifications. |
| VI. LXD Today, Incus Eventually | PASS | Uses standard `lxc file push` / `lxc exec` patterns. |
| VII. Idempotent Provisioning | PASS | Spec requires custom scripts to be idempotent (FR-008). Documented in CLAUDE.md. |
| VIII. Detect and Report, Don't Auto-Fix | PASS | Failed custom scripts report error and halt — no auto-retry. |
| IX. Shell Parity: Bash Always, Fish Opt-In | N/A | Custom provisioning runs as root, not user shell config. |
| X. Error Handling | PASS | `provision-container.sh` uses `set -euo pipefail` — non-zero exit propagates. `setup-host.sh` already catches provisioning failure. |
| XI. Rsync Excludes Stay Synchronized | N/A | No rsync changes. |
| XII. Keep Arguments Safe | PASS | No user arguments passed to the custom script. |

**Result**: All gates pass. No violations.

## Project Structure

### Documentation (this feature)

```text
specs/005-custom-provision-scripts/
├── plan.md              # This file
├── research.md          # Phase 0 output (minimal — no external unknowns)
├── data-model.md        # Phase 1 output (entities and flow)
├── quickstart.md        # Phase 1 output (developer guide)
└── tasks.md             # Phase 2 output (created by /speckit.tasks)
```

### Source Code (repository root)

```text
.
├── setup-host.sh              # MODIFY: push custom-provision.sh if it exists
├── provision-container.sh     # MODIFY: invoke /tmp/custom-provision.sh at end
├── dilxc.sh                   # MODIFY: add cmd_customize + dispatch entry
├── CLAUDE.md                  # MODIFY: add custom provision script instructions
├── .gitignore                 # MODIFY: add custom-provision.sh
└── custom-provision.sh        # NEW (user-created, gitignored, optional)
```

**Structure Decision**: No new directories or source structure. All changes modify existing files in the repo root, plus adding one `.gitignore` entry.

## Implementation Design

### Change 1: `provision-container.sh` — Invoke custom script at end

**Location**: After "User configured" message (line ~190), before "Final verification" section.

```bash
# --- Custom provisioning (optional) -----------------------------------------
if [[ -f /tmp/custom-provision.sh ]]; then
  echo "--- Running custom provisioning ---"
  chmod +x /tmp/custom-provision.sh
  /tmp/custom-provision.sh
  echo "  Custom provisioning complete ✓"
fi
```

**Rationale**: Because `set -euo pipefail` is active in the parent, a non-zero exit code from the custom script automatically halts provisioning. The error propagates up to `setup-host.sh`, which already handles provisioning failure (line 183-186) by printing an error and exiting before the snapshot step. The starter template and CLAUDE.md instructions require the custom script to also include `set -euo pipefail` so that intermediate command failures propagate correctly (without it, a failing `apt-get` mid-script would not halt the subprocess). This satisfies FR-002, FR-003, FR-005.

### Change 2: `setup-host.sh` — Push custom script if it exists

**Location**: Step 6, after pushing `provision-container.sh` and before executing it.

```bash
# Push custom provisioning script if present
CUSTOM_PROVISION="$(dirname "$0")/custom-provision.sh"
if [[ -f "$CUSTOM_PROVISION" ]]; then
  lxc exec "$CONTAINER_NAME" -- rm -f /tmp/custom-provision.sh
  lxc file push "$CUSTOM_PROVISION" "$CONTAINER_NAME/tmp/custom-provision.sh"
  echo "  Custom provision script detected — will run after standard provisioning"
fi
```

**Rationale**: Uses `$(dirname "$0")` for path resolution (same pattern as the existing `provision-container.sh` push). Deletes first to work around the `lxc file push` overwrite issue documented in CLAUDE.md. Satisfies FR-004 (silent skip when absent) and FR-010.

### Change 3: `dilxc.sh` — Add `customize` subcommand

**New function** `cmd_customize()`:

```bash
cmd_customize() {
  local custom_file="$SCRIPT_DIR/custom-provision.sh"
  if [[ ! -f "$custom_file" ]]; then
    cat > "$custom_file" << 'TEMPLATE'
#!/bin/bash
set -euo pipefail
# =============================================================================
# Custom Provisioning Script
# This file runs inside the LXD container after standard provisioning.
#
# Execution context:
#   - Runs as root inside an Ubuntu 24.04 container
#   - Uses set -euo pipefail (any failing command halts the script)
#   - Network access is available
#   - Docker, Node.js 22, npm, git, uv, gh CLI are already installed
#   - MUST be idempotent (safe to run multiple times)
#   - MUST use non-interactive flags (e.g., apt-get install -y)
#
# Example: install a tool
#   echo "--- Installing mytool ---"
#   apt-get install -y mytool
#   echo "  mytool installed ✓"
# =============================================================================

# Add your custom provisioning commands below:

TEMPLATE
    chmod +x "$custom_file"
    echo "Created starter template: $custom_file"
  fi
  "${EDITOR:-nano}" "$custom_file"
}
```

**Dispatch entry**: Add `customize)  cmd_customize ;;` to the case block.
**Usage text**: Add `customize` to the usage output.

**Rationale**: No container interaction needed — this edits a local file. Falls back to `nano` when `$EDITOR` is unset (matches FR-014). Template includes execution context documentation (FR-012).

### Change 4: `.gitignore` — Exclude custom-provision.sh

Add `custom-provision.sh` to `.gitignore`. Satisfies FR-013.

### Change 5: `CLAUDE.md` — Agent instructions for generating custom provision scripts

Add a new section "Custom Provision Scripts" with:
- File location and naming
- Execution context (root, Ubuntu 24.04, what's already installed)
- Idempotency requirements and patterns
- Non-interactive execution requirements
- Section structure conventions (echo headers, echo results)
- How to run after creating: `dilxc.sh customize` or manual placement

Also update the "Key Commands" section with:
- Re-provisioning workflow updated to include `custom-provision.sh`
- `dilxc.sh customize` command

### Change 6: CLAUDE.md — Update re-provisioning workflow

The existing re-provisioning commands in CLAUDE.md need updating to also push `custom-provision.sh`:

```bash
# Re-provision an existing container without recreating it
lxc exec docker-lxc -- rm -f /tmp/provision-container.sh /tmp/custom-provision.sh
lxc file push provision-container.sh docker-lxc/tmp/provision-container.sh
[[ -f custom-provision.sh ]] && lxc file push custom-provision.sh docker-lxc/tmp/custom-provision.sh
lxc exec docker-lxc -- chmod +x /tmp/provision-container.sh
lxc exec docker-lxc -- /tmp/provision-container.sh
```

## Complexity Tracking

No constitution violations to justify — all gates pass.
