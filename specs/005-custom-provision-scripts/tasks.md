# Tasks: Custom Provision Scripts

**Input**: Design documents from `/specs/005-custom-provision-scripts/`
**Prerequisites**: plan.md (required), spec.md (required), research.md, data-model.md, quickstart.md

**Tests**: No test framework — manual acceptance testing only.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Setup

**Purpose**: Prevent accidental commits of user-specific files during development

- [x] T001 Add `custom-provision.sh` to `.gitignore`

**Details**: Append `custom-provision.sh` to the existing `.gitignore` file (currently contains only `.claude/settings.local.json`). This satisfies FR-013.

**Checkpoint**: `git status` no longer tracks `custom-provision.sh` if one exists in repo root.

---

## Phase 2: User Story 1 - Add Custom Tools via Provision Script (Priority: P1) 🎯 MVP

**Goal**: Enable an optional `custom-provision.sh` file to be automatically detected, pushed into the container, and executed after standard provisioning completes.

**Independent Test**: Create a `custom-provision.sh` that installs `jq`. Run `setup-host.sh`. Verify `jq` is available inside the container. Then delete `custom-provision.sh` and run `setup-host.sh` again — verify no errors.

### Implementation for User Story 1

- [x] T002 [P] [US1] Add custom script invocation block to `provision-container.sh`

**Details**: Insert a new section after line 190 (`echo "  User configured ✓"`) and before line 192 (`# --- Final verification`). The block checks for `/tmp/custom-provision.sh`, makes it executable, and runs it. Because `set -euo pipefail` is active, a non-zero exit halts provisioning automatically — no extra error handling needed. Reference `plan.md` Change 1 for exact code.

```bash
# --- Custom provisioning (optional) -----------------------------------------
if [[ -f /tmp/custom-provision.sh ]]; then
  echo "--- Running custom provisioning ---"
  chmod +x /tmp/custom-provision.sh
  /tmp/custom-provision.sh
  echo "  Custom provisioning complete ✓"
fi
```

- [x] T003 [P] [US1] Add custom script push logic to `setup-host.sh`

**Details**: Insert after the existing `provision-container.sh` push (line 179) and before `chmod +x` / execution (line 180). Uses `$(dirname "$0")` for path resolution (matches existing pattern). Deletes before pushing to work around the known `lxc file push` overwrite issue. Must come BEFORE the `lxc exec ... /tmp/provision-container.sh` call so the custom script is in place when `provision-container.sh` looks for it. Reference `plan.md` Change 2 for exact code.

```bash
# Push custom provisioning script if present
CUSTOM_PROVISION="$(dirname "$0")/custom-provision.sh"
if [[ -f "$CUSTOM_PROVISION" ]]; then
  lxc exec "$CONTAINER_NAME" -- rm -f /tmp/custom-provision.sh
  lxc file push "$CUSTOM_PROVISION" "$CONTAINER_NAME/tmp/custom-provision.sh"
  echo "  Custom provision script detected — will run after standard provisioning"
fi
```

**Checkpoint**: US1 complete. The core mechanism works: custom scripts are pushed and executed during provisioning, skipped silently when absent, and failures halt setup before snapshot.

---

## Phase 3: User Story 2 - Edit Custom Provision File via CLI Command (Priority: P2)

**Goal**: Provide a discoverable `dilxc.sh customize` subcommand that creates a starter template (if absent) and opens `custom-provision.sh` in the user's editor.

**Independent Test**: Run `dilxc.sh customize` with no existing file — verify a template is created and the editor opens. Run it again — verify the existing file opens without overwriting. Verify `EDITOR` env var is respected.

### Implementation for User Story 2

- [x] T004 [US2] Add `cmd_customize()` function, dispatch entry, and usage text to `dilxc.sh`

**Details**: Three changes in `dilxc.sh`:

1. **Function**: Add `cmd_customize()` before the `# --- Main dispatch` section (line 656). The function checks for `$SCRIPT_DIR/custom-provision.sh`, creates a starter template with shebang + comment header if absent, then opens it in `${EDITOR:-nano}`. No container interaction needed. Reference `plan.md` Change 3 for the full function.

2. **Dispatch entry**: Add `customize)  cmd_customize ;;` to the case block (between `git-auth` and `destroy`, around line 682).

3. **Usage text**: Add `customize              Create/edit custom provisioning script` to the usage output. Place it in the management section after `git-auth` (around line 68).

**Checkpoint**: US2 complete. Users can create and edit custom provision files with a single command.

---

## Phase 4: User Story 3 - Coding Agent Generates Custom Provision Scripts (Priority: P3)

**Goal**: Add CLAUDE.md instructions that enable coding agents to generate correctly formatted `custom-provision.sh` files from natural language descriptions.

**Independent Test**: Ask a coding agent with access to the repo's CLAUDE.md to "add Spec Kit to my container" and verify it produces a valid, idempotent custom provision file.

### Implementation for User Story 3

- [x] T005 [US3] Add "Custom Provision Scripts" agent instructions section to `CLAUDE.md`

**Details**: Add a new `## Custom Provision Scripts` section to `CLAUDE.md`. Place it after the "File Strategy Inside the Container" section (the custom provision file is part of the container's file strategy context). Reference `plan.md` Change 5.

The section must include:
- File location: `custom-provision.sh` in repo root, pushed to `/tmp/custom-provision.sh` in container
- Execution context: root user, inside Ubuntu 24.04 container, with network access
- What's already installed after standard provisioning: Docker, Node.js 22, npm, git, Claude Code, uv, Spec Kit, gh CLI
- Error handling: MUST include `set -euo pipefail` after the shebang so that any failing command halts the script and propagates the error to the parent provisioning process
- Idempotency requirements: must be safe to run multiple times (use `apt-get install -y`, check-before-install patterns)
- Non-interactive requirements: no stdin prompts (`DEBIAN_FRONTEND=noninteractive`, `-y` flags)
- Section structure conventions: echo headers (`echo "--- Installing X ---"`), echo results (`echo "  X installed ✓"`)
- That the file is gitignored (user-specific, not committed to shared repo)
- Available package managers: `apt-get`, `npm`, `pip`/`uv`, `cargo`

**Checkpoint**: US3 complete. Coding agents can generate valid custom provision files from the CLAUDE.md instructions.

---

## Phase 5: User Story 4 - Re-provision with Custom Scripts (Priority: P4)

**Goal**: Document how to re-provision an existing container so updated custom provisioning changes are applied without container recreation.

**Independent Test**: Modify `custom-provision.sh` to add a new tool, re-provision the container using the documented workflow, and verify the new tool is available.

### Implementation for User Story 4

- [x] T006 [US4] Update re-provisioning workflow and Key Commands in `CLAUDE.md`

**Details**: Two edits to `CLAUDE.md`. Reference `plan.md` Change 6.

1. **Re-provisioning commands** (in "Key Commands" section): Update the existing re-provisioning code block to also delete and push `custom-provision.sh`. The current block (around line 20-25 in Key Commands) only handles `provision-container.sh`.

```bash
# Re-provision an existing container without recreating it
lxc exec docker-lxc -- rm -f /tmp/provision-container.sh /tmp/custom-provision.sh
lxc file push provision-container.sh docker-lxc/tmp/provision-container.sh
[[ -f custom-provision.sh ]] && lxc file push custom-provision.sh docker-lxc/tmp/custom-provision.sh
lxc exec docker-lxc -- chmod +x /tmp/provision-container.sh
lxc exec docker-lxc -- /tmp/provision-container.sh
```

2. **Key Commands list**: Add `./dilxc.sh customize` to the day-to-day commands section.

**Checkpoint**: US4 complete. Users can iterate on custom provisioning without recreating containers.

---

## Phase 6: Polish & Cross-Cutting Concerns

**Purpose**: Documentation consistency and final validation

- [x] T007 Update Editing Notes in `CLAUDE.md` with custom provisioning guidance

**Details**: Add a bullet to the "Editing Notes" section noting that `custom-provision.sh` is invoked at the end of `provision-container.sh` and pushed by `setup-host.sh` — both files must stay in sync regarding the `/tmp/custom-provision.sh` path convention.

- [x] T008 Manual acceptance validation per `quickstart.md` checklist

**Details**: Walk through the acceptance test checklist from `quickstart.md`:
1. With `custom-provision.sh` present: `setup-host.sh` pushes it, tools are installed
2. Without `custom-provision.sh`: `setup-host.sh` completes normally, no errors
3. With failing custom script: provisioning halts, no snapshot taken
4. `dilxc.sh customize`: creates template if absent, opens in editor
5. `dilxc.sh customize` again: opens existing file without overwriting
6. Re-provisioning with custom script: updated tools are applied
7. `custom-provision.sh` is in `.gitignore`

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: No dependencies — start immediately
- **US1 (Phase 2)**: Depends on Setup — this is the core mechanism
- **US2 (Phase 3)**: Depends on Setup only (file name convention) — can run in parallel with US1
- **US3 (Phase 4)**: Depends on US1 completion (documents the mechanism) — needs to reference correct behavior
- **US4 (Phase 5)**: Depends on US3 (both edit CLAUDE.md — avoids merge conflicts)
- **Polish (Phase 6)**: Depends on all user stories being complete

### User Story Dependencies

- **US1 (P1)**: Can start after Setup — no dependencies on other stories
- **US2 (P2)**: Can start after Setup — independent of US1 (different file: `dilxc.sh`)
- **US3 (P3)**: Should start after US1 — documents the mechanism US1 creates
- **US4 (P4)**: Should start after US3 — both edit `CLAUDE.md`, sequential avoids conflicts

### Within Each User Story

- US1: T002 and T003 are independent (different files) — can run in parallel
- US2: Single task (T004) — all changes in one file (`dilxc.sh`)
- US3: Single task (T005) — adds new section to `CLAUDE.md`
- US4: Single task (T006) — edits existing sections in `CLAUDE.md`

### Parallel Opportunities

- T002 and T003 can run in parallel (different files: `provision-container.sh` and `setup-host.sh`)
- US1 and US2 can run in parallel (different files, no code dependencies)
- T007 can run in parallel with T008 (editing vs. manual testing)

---

## Parallel Example: User Story 1

```bash
# Launch both US1 tasks together (different files):
Task: "Add custom script invocation block to provision-container.sh"
Task: "Add custom script push logic to setup-host.sh"
```

## Parallel Example: US1 + US2

```bash
# These user stories touch different files and can run concurrently:
# Agent A: US1 (provision-container.sh + setup-host.sh)
# Agent B: US2 (dilxc.sh)
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Setup (`.gitignore`)
2. Complete Phase 2: User Story 1 (`provision-container.sh` + `setup-host.sh`)
3. **STOP and VALIDATE**: Create a test `custom-provision.sh`, run setup, verify tools are installed
4. Core mechanism works — user can manually create and use custom provision files

### Incremental Delivery

1. Setup → `.gitignore` entry in place
2. US1 → Core mechanism works (MVP!)
3. US2 → CLI discoverability (`dilxc.sh customize`)
4. US3 → Agent-assisted script generation (CLAUDE.md instructions)
5. US4 → Re-provisioning workflow documented
6. Polish → Documentation consistency + acceptance validation

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Each user story is independently testable after completion
- Commit after each task or logical group
- Stop at any checkpoint to validate story independently
- No test framework — all validation is manual acceptance testing
- Total: 8 tasks across 6 phases
