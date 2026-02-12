# Tasks: Slim Default Provision

**Input**: Design documents from `/specs/006-slim-default-provision/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, quickstart.md

**Tests**: Not requested in the feature specification. No test tasks generated.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Phase 1: Setup

**Purpose**: N/A — this feature modifies existing files and creates two new files at the repo root. No project initialization needed.

---

## Phase 2: Foundational

**Purpose**: N/A — no blocking prerequisites. All user stories operate on independent files.

---

## Phase 3: User Story 1 - Leaner Default Container (Priority: P1) MVP

**Goal**: Remove uv, Spec Kit, and postgresql-client from default provisioning so new containers only include essential tools (Docker, Node.js, Claude Code, git, dev tools).

**Independent Test**: Run `setup-host.sh` to provision a fresh container. Verify `uv`, `specify`, and `psql` are NOT found. Verify `docker`, `node`, `claude`, `git`, `gh` still work.

### Implementation for User Story 1

- [X] T001 [US1] Remove the entire `# --- uv and Spec Kit ---` install section (curl + uv tool install + success echo, ~lines 56-60) from provision-container.sh
- [X] T002 [US1] Remove `postgresql-client` from the `apt-get install -y` package list in the dev tools section (~line 72) in provision-container.sh
- [X] T003 [US1] Update `# Add uv / Spec Kit to PATH` comment to `# User-installed tools` in both the bash config block (~line 101) and the fish config block (~line 145) in provision-container.sh
- [X] T004 [US1] Remove the `uv:` and `Spec Kit:` echo lines from the final verification output (~lines 210-211) in provision-container.sh
- [X] T005 [P] [US1] Update the customize template comment in dilxc.sh (~line 671) to remove "uv, Spec Kit (`specify-cli`)" from the list of already-installed tools

**Checkpoint**: At this point, `provision-container.sh` and `dilxc.sh` no longer reference uv, Spec Kit, or postgresql-client. A freshly provisioned container would not include these tools.

---

## Phase 4: User Story 2 - Recipes for Persistent Custom Tools (Priority: P2)

**Goal**: Create a RECIPES.md reference file explaining the three-tier tool installation model and providing copy-paste snippets for tools removed from the default install.

**Independent Test**: Copy a recipe from RECIPES.md into a `custom-provision.sh`, run provisioning, and verify the tool installs correctly.

### Implementation for User Story 2

- [X] T006 [US2] Create RECIPES.md in the repo root with: (1) a brief explanation of the three-tier tool installation model (default provisioning, custom provisioning via `custom-provision.sh`, manual install), (2) a recipe for uv + Spec Kit (installs uv first, then uses `uv tool install specify-cli`), and (3) a recipe for PostgreSQL client. Each recipe must follow `custom-provision.sh` conventions: idempotent, non-interactive, with `echo "--- Installing X ---"` section headers and `echo "  X installed"` result messages.

**Checkpoint**: RECIPES.md exists with working, self-contained recipes that follow documented conventions.

---

## Phase 5: User Story 3 - Updated Documentation (Priority: P3)

**Goal**: Update all project documentation so no file claims uv, Spec Kit, or postgresql-client are installed by default. Add references to RECIPES.md and custom provisioning where appropriate.

**Independent Test**: Search all documentation files for "uv", "Spec Kit", "specify", "postgresql-client" and verify none appear in a "default" or "pre-installed" context.

### Implementation for User Story 3

- [X] T007 [P] [US3] Update README.md: (a) remove "and Spec Kit for spec-driven development" from opening description (~line 3), (b) update "What Gets Installed" section to remove uv/Spec Kit line, fix fish description (fish is opt-in via `--fish`, not default — move aliases/helpers to the dev tools bullet since they exist in bash too), and add a note about custom provisioning with link to RECIPES.md (~lines 19-21), (c) replace "Spec Kit Integration" section (~lines 179-194) with a "Customizing Your Container" section that explains custom provisioning and links to RECIPES.md, (d) remove "uv, Spec Kit" from provision-container.sh description in How It Works (~line 209)
- [X] T008 [P] [US3] Update CLAUDE.md: (a) remove "pre-installed with uv and Spec Kit (`specify-cli`)" from project overview (~line 7), (b) remove "uv, Spec Kit (`specify-cli`)," from provision-container.sh description (~line 22), (c) remove "uv, Spec Kit (`specify-cli`)," and "postgresql-client" from the installed tools list in custom provision writing section (~line 44), (d) change "`pip`/`uv`" to "`pip`" in available package managers (~line 52)
- [X] T009 [P] [US3] Update .specify/memory/constitution.md: change Principle I example list from "(Node.js, Docker, uv, etc.)" to "(Node.js, Docker, etc.)" or similar (~line 43)

**Checkpoint**: All documentation accurately reflects the new default toolset. No file claims uv, Spec Kit, or postgresql-client are pre-installed.

---

## Phase 6: User Story 4 - Personal Custom Provision with Spec Kit (Priority: P4)

**Goal**: Create the maintainer's personal `custom-provision.sh` so Spec Kit continues to be available in all new containers without relying on default provisioning.

**Independent Test**: Verify `custom-provision.sh` exists in repo root, contains uv + Spec Kit installation commands, follows documented conventions, and is gitignored.

### Implementation for User Story 4

- [X] T010 [US4] Create custom-provision.sh in the repo root with: `#!/bin/bash` and `set -euo pipefail`, then the uv + Spec Kit recipe (should match the recipe from RECIPES.md). Verify the file is already covered by .gitignore.

**Checkpoint**: Maintainer's personal custom provisioning script is ready. It will be picked up automatically by `setup-host.sh` on next container creation.

---

## Phase 7: Polish & Cross-Cutting Concerns

**Purpose**: Final verification across all modified files

- [X] T011 Run quickstart.md verification checklist against all modified files: confirm provision-container.sh has no uv/Spec Kit/postgresql-client references, dilxc.sh template is updated, README.md and CLAUDE.md have no stale default-tool claims, RECIPES.md exists with working recipes, custom-provision.sh exists and is gitignored, `~/.local/bin` PATH entry is preserved in both bash and fish configs, shell parity is maintained

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1 (Setup)**: N/A
- **Phase 2 (Foundational)**: N/A
- **US1 (Phase 3)**: No dependencies — can start immediately
- **US2 (Phase 4)**: No dependencies — can start in parallel with US1
- **US3 (Phase 5)**: Should follow US1 and US2 (needs to link to RECIPES.md and reflect script changes)
- **US4 (Phase 6)**: Should follow US2 (recipe content should be consistent with RECIPES.md)
- **Polish (Phase 7)**: Depends on all user stories being complete

### User Story Dependencies

```
US1 (Leaner Default) ──────┐
                            ├──→ US3 (Documentation) ──→ Polish
US2 (RECIPES.md) ──────────┤
                            └──→ US4 (Personal custom-provision.sh) ──→ Polish
```

- **US1 → US3**: Documentation needs to reflect what was removed
- **US2 → US3**: README links to RECIPES.md
- **US2 → US4**: custom-provision.sh recipe should match RECIPES.md content
- **US1 and US2**: Fully independent, can run in parallel

### Parallel Opportunities

- **T005** (dilxc.sh) can run in parallel with T001-T004 (provision-container.sh) — different files
- **T006** (RECIPES.md) can run in parallel with all US1 tasks — different files, no dependencies
- **T007, T008, T009** (README.md, CLAUDE.md, constitution.md) can all run in parallel — different files
- **T010** (custom-provision.sh) can run in parallel with T007-T009 if US2 is already complete

---

## Parallel Example: User Story 1 + User Story 2

```bash
# US1 and US2 can be worked on simultaneously since they touch different files:

# Agent A: US1 - provision-container.sh changes (T001-T004, sequential within file)
Task: "Remove uv + Spec Kit install section from provision-container.sh"
Task: "Remove postgresql-client from dev tools apt-get in provision-container.sh"
Task: "Update PATH comments in provision-container.sh"
Task: "Remove verification lines from provision-container.sh"

# Agent B: US1 + US2 parallel tasks
Task: "Update customize template in dilxc.sh"  # T005 [P]
Task: "Create RECIPES.md with three-tier model and recipes"  # T006
```

## Parallel Example: User Story 3

```bash
# All US3 tasks touch different files and can run simultaneously:
Task: "Update README.md - remove uv/Spec Kit references"  # T007 [P]
Task: "Update CLAUDE.md - remove default tool references"  # T008 [P]
Task: "Update constitution.md Principle I example"          # T009 [P]
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete US1 (T001-T005): Remove opinionated tools from provisioning scripts
2. **STOP and VALIDATE**: Provision a test container, verify tools are absent, essentials still work
3. Core value delivered — containers are leaner

### Incremental Delivery

1. US1 → Lean provisioning (MVP)
2. US2 → Recipes available for users who want removed tools back
3. US3 → Documentation matches reality
4. US4 → Maintainer's workflow preserved
5. Polish → Final verification pass

### Single-Developer Strategy (Recommended)

Since all changes are file edits with clear boundaries:

1. T001-T005 (US1) — all provision script changes, ~10 minutes
2. T006 (US2) — create RECIPES.md, ~10 minutes
3. T007-T009 (US3) — documentation updates, ~15 minutes (can parallelize across files)
4. T010 (US4) — create custom-provision.sh, ~5 minutes
5. T011 (Polish) — verification checklist, ~5 minutes

---

## Notes

- [P] tasks = different files, no dependencies
- [Story] label maps task to specific user story for traceability
- Line numbers are approximate — verify actual positions before editing
- Shell parity: bash and fish config changes in provision-container.sh must be kept in sync (T003 covers both)
- `custom-provision.sh` is gitignored — it won't affect other users
- The `~/.local/bin` PATH entry must be preserved even though uv is removed (FR-004)
- Commit after each user story phase for clean git history
