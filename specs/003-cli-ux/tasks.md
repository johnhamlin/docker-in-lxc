# Tasks: CLI UX Improvements

**Input**: Design documents from `/specs/003-cli-ux/`
**Prerequisites**: plan.md (required), spec.md (required for user stories), research.md, data-model.md

**Tests**: Not requested — no test tasks included.

**Organization**: Tasks are grouped by user story to enable independent implementation and testing of each story. Since all changes target a single file (`dilxc.sh`) plus one new file (`.gitattributes`), tasks are structured by logical code sections within the script.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

## Path Conventions

All changes are in the repository root:
- `dilxc.sh` — CLI wrapper script (all US1–US5 changes)
- `.gitattributes` — distribution exclusions (US6)

---

## Phase 1: Setup

**Purpose**: No project initialization needed — this feature modifies an existing script in an established repository.

(No tasks — existing project structure is sufficient)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: No shared infrastructure to build. `dilxc.sh` already exists with its dispatch pattern, helper functions, and subcommand structure from previous features.

(No tasks — existing script infrastructure is sufficient)

**Checkpoint**: Existing `dilxc.sh` with case-based dispatch, `require_container`/`require_running` helpers, and `CONTAINER_NAME` variable is the foundation.

---

## Phase 3: User Story 1 — Install and Invoke dilxc from Anywhere (Priority: P1) MVP

**Goal**: Enable symlink-based installation so `dilxc` can be invoked from any directory via `~/.local/bin/dilxc`, with the script resolving its real location to find sibling scripts.

**Independent Test**: Create a symlink `~/.local/bin/dilxc -> /path/to/dilxc.sh`, run `dilxc help` from a different directory, verify usage text appears and `SCRIPT_DIR` points to the real directory.

### Implementation for User Story 1

- [X] T001 [US1] Replace hardcoded `SCRIPT_DIR` assignment with symlink-aware resolution using `readlink -f "$0"` wrapped in `cd "$(dirname ...)" && pwd` in `dilxc.sh` (line 31)
- [X] T002 [US1] Verify `SCRIPT_DIR` is used (not relative paths) in all sibling script references throughout `dilxc.sh`

**Checkpoint**: `dilxc help` works correctly when invoked via a symlink from any directory. `SCRIPT_DIR` resolves to the real directory containing `dilxc.sh`.

---

## Phase 4: User Story 3 — Target a Specific Container (Priority: P1)

**Goal**: Implement a four-level priority cascade for container name resolution: `@name` prefix → `DILXC_CONTAINER` env var → `.dilxc` file walk → default `docker-lxc`.

**Independent Test**: Create a `.dilxc` file containing a container name, run `dilxc status` from that directory, verify it targets the named container. Also test `dilxc @other-name status` to verify prefix override.

### Implementation for User Story 3

- [X] T003 [US3] Implement `@name` prefix parsing at the top of `dilxc.sh` — detect `$1` matching `@*`, extract container name via `${1#@}`, and `shift` the argument before dispatch
- [X] T004 [US3] Implement `DILXC_CONTAINER` env var check as the second cascade level in `dilxc.sh`
- [X] T005 [US3] Implement `.dilxc` file walk — loop from `$PWD` upward via `dirname`, check for `.dilxc` file at each level, read first line with `head -1`, stop at filesystem root (`/`) in `dilxc.sh`
- [X] T006 [US3] Set default fallback `CONTAINER_NAME="${CONTAINER_NAME:-docker-lxc}"` after cascade in `dilxc.sh`
- [X] T007 [US3] Replace the old static `CONTAINER_NAME` assignment with the cascade block at the top of `dilxc.sh` (lines 12-29)

**Checkpoint**: `dilxc @name status`, `DILXC_CONTAINER=name dilxc status`, `.dilxc` file-based resolution, and default fallback all work correctly. Priority order is respected when multiple sources are present.

---

## Phase 5: User Story 2 — Create a Sandbox via dilxc init (Priority: P1)

**Goal**: Add `dilxc init` as a convenience wrapper that delegates to `setup-host.sh` with full argument passthrough.

**Independent Test**: Run `dilxc init --help` and verify it shows `setup-host.sh`'s help output.

**Depends on**: US1 (uses `$SCRIPT_DIR` to locate `setup-host.sh`)

### Implementation for User Story 2

- [X] T008 [US2] Add `cmd_init()` function that uses `exec "$SCRIPT_DIR/setup-host.sh" "$@"` to delegate with full argument passthrough in `dilxc.sh`
- [X] T009 [US2] Add `init)` case entry in the main dispatch block with `shift` before calling `cmd_init "$@"` in `dilxc.sh`
- [X] T010 [US2] Add `init [options]` line to the `usage()` function with description in `dilxc.sh`

**Checkpoint**: `dilxc init -p /path/to/project -n mybox --fish` invokes `setup-host.sh` with all flags passed through. Exit code propagates directly.

---

## Phase 6: User Story 4 — Update to the Latest Version (Priority: P2)

**Goal**: Add `dilxc update` to self-update the tool via `git pull` in the script's repository directory.

**Independent Test**: Run `dilxc update` in a git-cloned installation and verify the repo is updated with version feedback.

**Depends on**: US1 (uses `$SCRIPT_DIR` to locate `.git` and run `git pull`)

### Implementation for User Story 4

- [X] T011 [US4] Add `cmd_update()` function in `dilxc.sh` that: (1) checks for `$SCRIPT_DIR/.git` directory and exits with error if missing, (2) displays current short commit hash via `git rev-parse --short HEAD`, (3) runs `git -C "$SCRIPT_DIR" pull`
- [X] T012 [US4] Add `update)` case entry in the main dispatch block in `dilxc.sh`
- [X] T013 [US4] Add `update` line to the `usage()` function with description in `dilxc.sh`

**Checkpoint**: `dilxc update` shows "Updating Docker-in-LXC from abc1234..." and runs `git pull`. Non-git installs get a clear error message.

---

## Phase 7: User Story 5 — List Available Containers (Priority: P2)

**Goal**: Add `dilxc containers` to list all LXD containers with status, marking the active one (as resolved by the selection cascade).

**Independent Test**: Run `dilxc containers` and verify all LXD containers appear with name, status, and `(active)` marker on the cascade-resolved container.

**Depends on**: US3 (uses `$CONTAINER_NAME` from cascade for the active marker)

### Implementation for User Story 5

- [X] T014 [US5] Add `cmd_containers()` function in `dilxc.sh` that: (1) prints a `CONTAINER STATUS` header, (2) parses `lxc list -f csv -c ns` output, (3) marks the cascade-resolved `$CONTAINER_NAME` with `(active)` using `printf` alignment
- [X] T015 [US5] Add `containers)` case entry in the main dispatch block in `dilxc.sh`
- [X] T016 [US5] Add `containers` line to the `usage()` function with description in `dilxc.sh`

**Checkpoint**: `dilxc containers` lists all LXD containers in a formatted table with the active container marked.

---

## Phase 8: User Story 6 — Clean Distribution via .gitattributes (Priority: P3)

**Goal**: Exclude development artifacts from `git archive` output so distribution tarballs contain only essential scripts and docs.

**Independent Test**: Run `git archive HEAD | tar -t` and verify `specs/`, `.specify/`, `.claude/`, `constitution-input.md`, `spec-input.md`, and `HANDOFF.md` are absent.

**Independent of all other user stories**

### Implementation for User Story 6

- [X] T017 [P] [US6] Create `.gitattributes` at repository root with `export-ignore` rules for: `specs/`, `.specify/`, `.claude/`, `constitution-input.md`, `spec-input.md`, `HANDOFF.md`

**Checkpoint**: `git archive HEAD | tar -t | grep -E '(specs/|\.specify/|\.claude/)'` returns no matches.

---

## Phase 9: Polish & Cross-Cutting Concerns

**Purpose**: Final updates that span multiple user stories.

- [X] T018 Update `usage()` function in `dilxc.sh` to include Container Selection documentation section showing the cascade priority order with examples
- [X] T019 Verify all dispatch entries in the `case` block at the bottom of `dilxc.sh` are present and correctly route to their `cmd_*` functions

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: N/A — existing project
- **Foundational (Phase 2)**: N/A — existing infrastructure
- **US1 (Phase 3)**: No dependencies — can start immediately
- **US3 (Phase 4)**: No dependencies — can start immediately, parallelizable with US1
- **US2 (Phase 5)**: Depends on US1 (needs `SCRIPT_DIR` for locating `setup-host.sh`)
- **US4 (Phase 6)**: Depends on US1 (needs `SCRIPT_DIR` for locating `.git`)
- **US5 (Phase 7)**: Depends on US3 (needs `CONTAINER_NAME` from cascade for active marker)
- **US6 (Phase 8)**: No dependencies — fully independent, parallelizable with any phase
- **Polish (Phase 9)**: Depends on all user stories being complete

### User Story Dependencies

```text
US1 (SCRIPT_DIR) ──→ US2 (init)
                 └──→ US4 (update)

US3 (cascade)   ──→ US5 (containers)

US6 (.gitattributes) — independent
```

### Parallel Opportunities

- **US1 and US3** can be implemented in parallel (different code sections of `dilxc.sh`)
- **US6** can be implemented in parallel with any other story (different file)
- **US2 and US4** can be implemented in parallel after US1 completes (different functions)
- **US5** can be implemented in parallel with US2/US4 after US3 completes

---

## Parallel Example: Initial Sprint

```text
# Sprint 1 — can all run in parallel:
Agent A: US1 (SCRIPT_DIR resolution) — dilxc.sh line 31
Agent B: US3 (cascade) — dilxc.sh lines 12-29
Agent C: US6 (.gitattributes) — new file

# Sprint 2 — after Sprint 1 completes:
Agent A: US2 (init) — dilxc.sh cmd_init()
Agent B: US4 (update) — dilxc.sh cmd_update()
Agent C: US5 (containers) — dilxc.sh cmd_containers()

# Sprint 3:
All: Polish — usage(), dispatch verification
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete US1: SCRIPT_DIR resolution
2. **STOP and VALIDATE**: Symlink install works, `dilxc help` from anywhere
3. This alone enables convenient installation

### Incremental Delivery

1. US1 (SCRIPT_DIR) → symlink install works → MVP
2. US3 (cascade) → multi-container targeting works
3. US2 (init) → streamlined sandbox creation
4. US4 (update) → self-update capability
5. US5 (containers) → situational awareness
6. US6 (.gitattributes) → clean distribution
7. Each story adds value without breaking previous stories

---

## Notes

- All US1–US5 tasks modify `dilxc.sh` — coordinate to avoid merge conflicts if working in parallel
- US6 is the only task touching a different file (`.gitattributes`), making it fully safe to parallelize
- Since this is a retroactive spec, all tasks describe already-implemented code
- No test framework — validation is manual per acceptance scenarios in spec.md
