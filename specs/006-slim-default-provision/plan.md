# Implementation Plan: Slim Default Provision

**Branch**: `006-slim-default-provision` | **Date**: 2026-02-12 | **Spec**: [spec.md](spec.md)
**Input**: Feature specification from `/specs/006-slim-default-provision/spec.md`

## Summary

Remove opinionated tools (uv, Spec Kit, postgresql-client) from default container provisioning. Create RECIPES.md with copy-paste snippets for users who want these tools in every container via `custom-provision.sh`. Update all documentation to reflect the leaner defaults and the three-tier tool installation model. Create the maintainer's personal `custom-provision.sh` with Spec Kit.

## Technical Context

**Language/Version**: Bash (GNU Bash, Ubuntu 24.04 default)
**Primary Dependencies**: LXD (`lxc` CLI)
**Storage**: N/A (shell scripts and markdown files)
**Testing**: Manual verification (run provisioning, check tool absence/presence)
**Target Platform**: Ubuntu host with LXD
**Project Type**: Single (three bash scripts + documentation)
**Performance Goals**: N/A
**Constraints**: Must follow constitution principles (idempotent provisioning, shell parity, readability)
**Scale/Scope**: 5 files modified, 2 new files created

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Principle | Status | Notes |
|-----------|--------|-------|
| I. Shell Scripts Only | PASS | Editing existing bash scripts + markdown |
| II. Three Scripts, Three Contexts | PASS | Changes to `provision-container.sh` (container context) and `dilxc.sh` (host context) — no new scripts |
| III. Readability Over Cleverness | PASS | Changes are straightforward removals |
| IV. Container Is the Sandbox | N/A | |
| V. Don't Touch the Host | N/A | |
| VI. LXD Today, Incus Eventually | N/A | |
| VII. Idempotent Provisioning | PASS | Removing sections doesn't affect idempotency. Custom provision recipes must be idempotent (required by FR-007) |
| VIII. Detect and Report | N/A | |
| IX. Shell Parity | PASS | PATH comment update applies to both bash and fish config blocks. Both must be updated together |
| X. Error Handling | N/A | |
| XI. Rsync Excludes Synchronized | N/A | |
| XII. Keep Arguments Safe | N/A | |

No violations. No complexity tracking needed.

**Post-Phase 1 re-check**: PASS. No design decisions introduced new violations. Constitution Principle I example list gets a minor wording update (not an amendment — just an illustrative example change).

## Project Structure

### Documentation (this feature)

```text
specs/006-slim-default-provision/
├── spec.md              # Feature specification
├── plan.md              # This file
├── research.md          # Reference inventory and decisions
├── quickstart.md        # Implementation checklist
├── checklists/
│   └── requirements.md  # Spec quality checklist
└── tasks.md             # Task breakdown (created by /speckit.tasks)
```

### Source Code (repository root)

```text
(repo root)
├── provision-container.sh  # Modified: remove uv/Spec Kit section, remove postgresql-client, update comments, update verification output
├── dilxc.sh                # Modified: update customize template comment
├── RECIPES.md              # New: three-tier model explanation + copy-paste recipes
├── README.md               # Modified: update tool descriptions, replace Spec Kit Integration section
├── CLAUDE.md               # Modified: update tool references throughout
├── custom-provision.sh     # New: maintainer's personal custom provisioning (gitignored)
└── .specify/
    └── memory/
        └── constitution.md # Modified: update Principle I example list
```

**Structure Decision**: No new directories. All changes are to existing files at the repo root, plus two new files (`RECIPES.md` committed, `custom-provision.sh` gitignored).

## Implementation Details

### Phase A: Script Changes (P1 — Leaner Default Container)

**File: `provision-container.sh`**

1. **Remove uv + Spec Kit install section** (lines 56-60): Delete the entire `# --- uv and Spec Kit ---` block including the curl/uv-tool-install commands and success echo
2. **Remove postgresql-client** (line 72): Remove `postgresql-client` from the `apt-get install -y` list in the dev tools section
3. **Update bash config comment** (line 101): Change `# Add uv / Spec Kit to PATH` to `# User-installed tools`
4. **Update fish config comment** (line 145): Change `# Add uv / Spec Kit to PATH` to `# User-installed tools`
5. **Remove final verification lines** (lines 210-211): Delete the `uv:` and `Spec Kit:` echo lines from the verification output

**File: `dilxc.sh`**

6. **Update customize template** (line 671): Change "Docker, Node.js 22, npm, git, Claude Code, uv, Spec Kit, gh CLI are already installed" to remove uv and Spec Kit

### Phase B: New Files (P2 — Recipes + P4 — Personal Custom Provision)

7. **Create `RECIPES.md`**: Three-tier model explanation followed by recipes:
   - Recipe: uv + Spec Kit (installs uv first, then uses it to install specify-cli)
   - Recipe: PostgreSQL client

8. **Create `custom-provision.sh`**: Maintainer's personal script with uv + Spec Kit recipe (copied from RECIPES.md)

### Phase C: Documentation Updates (P3 — Updated Documentation)

**File: `README.md`**

9. **Line 3**: Remove "and Spec Kit for spec-driven development" from the opening description
10. **Lines 19-21**: Update "What Gets Installed" — remove uv/Spec Kit line, fix fish description (fish is opt-in via `--fish`, not default — move aliases/helpers to the dev tools bullet since they exist in bash), add note about custom provisioning and link to RECIPES.md
11. **Lines 179-194**: Replace "Spec Kit Integration" section with "Customizing Your Container" section that explains custom provisioning and links to RECIPES.md
12. **Line 209**: Remove "uv, Spec Kit" from provision-container.sh description in How It Works

**File: `CLAUDE.md`**

13. **Line 7**: Remove "pre-installed with uv and Spec Kit" from project overview
14. **Line 22**: Remove "uv, Spec Kit (`specify-cli`)" from provision-container.sh description
15. **Line 44**: Remove "uv, Spec Kit (`specify-cli`)" and "postgresql-client" from installed tools list
16. **Line 52**: Change "`pip`/`uv`" to "`pip`" in available package managers

**File: `.specify/memory/constitution.md`**

17. **Line 43**: Update Principle I example from "(Node.js, Docker, uv, etc.)" to "(Node.js, Docker, etc.)" or similar
