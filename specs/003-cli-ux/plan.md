# Implementation Plan: CLI UX Improvements

**Branch**: `003-cli-ux` | **Date**: 2026-02-12 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/003-cli-ux/spec.md`

**Note**: This is a retroactive plan documenting already-implemented CLI UX improvements to `dilxc.sh`.

## Summary

Add symlink-aware `SCRIPT_DIR` resolution, `init`/`update` subcommands, a priority-based container selection cascade (`@name` → env var → `.dilxc` file → default), a `containers` listing command, and `.gitattributes` for clean `git archive` distribution. All changes are in `dilxc.sh` (host-side wrapper) and `.gitattributes` (repo root), consistent with the three-script architecture.

## Technical Context

**Language/Version**: Bash (GNU Bash, Ubuntu 24.04 default)
**Primary Dependencies**: LXD (`lxc` CLI), GNU coreutils (`readlink -f`, `dirname`), git (for `update`)
**Storage**: N/A (no persistent data beyond `.dilxc` convention files)
**Testing**: Manual acceptance testing via shell invocation (no test framework)
**Target Platform**: Ubuntu 24.04 host (gram-server)
**Project Type**: Single — three bash scripts
**Performance Goals**: N/A (CLI tool, latency is negligible)
**Constraints**: No new scripts (Constitution II), no compiled languages (Constitution I)
**Scale/Scope**: Single host, handful of LXD containers

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Shell Scripts Only | PASS | All changes are bash and `.gitattributes` — no new languages |
| II. Three Scripts, Three Execution Contexts | PASS | All CLI changes are in `dilxc.sh` (host script). No new scripts created |
| III. Readability Wins Over Cleverness | PASS | Container cascade uses explicit if/elif/else. `.dilxc` walk uses a simple while loop |
| IV. The Container Is the Sandbox | PASS | No changes to sandbox security model |
| V. Don't Touch the Host | PASS | `lxc` commands scoped to `$CONTAINER_NAME`. `update` only touches `$SCRIPT_DIR` (the tool's own repo) |
| VI. LXD Today, Incus Eventually | PASS | Uses `lxc` CLI generically; `containers` uses `lxc list` which has an Incus equivalent |
| VII. Idempotent Provisioning | N/A | No provisioning changes |
| VIII. Detect and Report, Don't Auto-Fix | PASS | `update` reports error if not a git checkout; doesn't try to self-install |
| IX. Shell Parity: Bash Always, Fish Opt-In | N/A | No shell config changes in `provision-container.sh` |
| X. Error Handling | PASS | `dilxc.sh` does NOT use `set -e`, handles errors per-command |
| XI. Rsync Excludes Stay Synchronized | N/A | No rsync changes |
| XII. Keep Arguments Safe | PASS | `init` uses `exec` (no shell reinterpretation); existing `printf '%q'` pattern unchanged |

**Gate result: PASS** — No violations.

## Project Structure

### Documentation (this feature)

```text
specs/003-cli-ux/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
└── tasks.md             # Phase 2 output (via /speckit.tasks)
```

### Source Code (repository root)

```text
dilxc.sh                 # All CLI changes (container cascade, init, update, containers)
.gitattributes           # Distribution exclusions for git archive
```

**Structure Decision**: No new files or directories beyond `dilxc.sh` modifications and `.gitattributes` at the repo root. This is a pure bash script enhancement — no source tree restructuring needed.

## Complexity Tracking

No constitution violations — this section is intentionally empty.
