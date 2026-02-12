# Tasks: LXC Port Proxy

**Input**: Design documents from `/specs/002-port-proxy/`
**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/proxy.md

**Tests**: Not requested — acceptance scenarios from spec.md are validated in the Polish phase.

**Organization**: Tasks are grouped by user story. All tasks modify a single file (`dilxc.sh`), so no parallel markers are used.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: Which user story this task belongs to (e.g., US1, US2, US3)
- Include exact file paths in descriptions

---

## Phase 1: Foundational (Shared Infrastructure)

**Purpose**: Add shared helpers and scaffolding that ALL proxy sub-actions depend on. Must be complete before any user story work.

**Why no Setup phase**: This feature modifies a single existing file (`dilxc.sh`). No new files, directories, or dependencies are needed.

- [x] T001 Add `validate_port()` helper function to `dilxc.sh`
- [x] T002 Add `proxy_usage()` help text function, `cmd_proxy()` dispatcher, main dispatch entry, and usage line to `dilxc.sh`

### Task Details

**T001 — `validate_port()` helper** (`dilxc.sh`, in the Helpers section after `require_running`):

Add a function that validates a port number argument. Used by both `proxy add` and `proxy rm`.

```
validate_port(value, label) → exits 1 on failure, returns silently on success
```

Behavior per contracts/proxy.md:
- Takes two args: the value to validate and a label for error messages (e.g., "container port", "host port")
- Check value is non-empty and consists of digits only (`[[ "$value" =~ ^[0-9]+$ ]]`)
- Check value is in range 1-65535
- On failure: print `Error: invalid port '<value>' — must be a number between 1 and 65535` and exit 1
- On success: return silently (caller uses the value directly)

Place this function in the `# --- Helpers ---` section, after `require_running()`.

**T002 — Scaffolding: `proxy_usage()`, `cmd_proxy()`, dispatch entry, usage line** (`dilxc.sh`):

Add four things:

1. **`proxy_usage()` function** — Place after `cmd_destroy()`, before the main dispatch block. Print exact help text from contracts/proxy.md:
   ```
   Usage: ./dilxc.sh proxy <action> [options]

   Actions:
     add <container-port> [host-port]   Forward a host port to a container port
     list                               List active port proxies
     rm <host-port>                     Remove a proxy by host port
     rm all                             Remove all proxies

   Examples:
     ./dilxc.sh proxy add 3000          # host:3000 → container:3000
     ./dilxc.sh proxy add 8080 9090     # host:9090 → container:8080
     ./dilxc.sh proxy list
     ./dilxc.sh proxy rm 3000
     ./dilxc.sh proxy rm all
   ```

2. **`cmd_proxy()` dispatcher function** — Place after `proxy_usage()`. Pattern from contracts/proxy.md:
   ```bash
   cmd_proxy() {
     local action="${1:-help}"
     shift 2>/dev/null || true
     case "$action" in
       add)           require_running; cmd_proxy_add "$@" ;;
       list|ls)       require_container; cmd_proxy_list ;;
       rm|remove)     require_running; cmd_proxy_rm "$@" ;;
       help|--help|*) proxy_usage ;;
     esac
   }
   ```
   Note: `cmd_proxy_add`, `cmd_proxy_list`, and `cmd_proxy_rm` don't exist yet — they'll be added in Phases 2-4. For now, placeholder stubs are NOT needed; the dispatcher is syntactically valid because these will be added before the script is used.

3. **Main dispatch entry** — Add to the case block (before the `help|*` line):
   ```bash
   proxy)         shift; cmd_proxy "$@" ;;
   ```

4. **Usage line** — Add to the `usage()` function, in the Commands section (after the `docker` line, before the `health-check` line):
   ```
     proxy <action>         Manage port proxies (add, list, rm)
   ```

**Checkpoint**: After T001-T002, `./dilxc.sh proxy --help` should display the proxy usage text. The `add`, `list`, and `rm` sub-actions will fail because their functions don't exist yet — that's expected.

---

## Phase 2: User Story 1 — Forward a Container Port to the Host (Priority: P1) — MVP

**Goal**: Users can expose a container service to the LAN by running `./dilxc.sh proxy add <port>`.

**Independent Test**: Start a service inside the container on a port (e.g., `python3 -m http.server 8000`), run `proxy add 8000`, then curl `<host-ip>:8000` from the host or another LAN machine.

### Implementation for User Story 1

- [x] T003 [US1] Implement `cmd_proxy_add()` function in `dilxc.sh`

### Task Details

**T003 — `cmd_proxy_add()`** (`dilxc.sh`, place between `cmd_destroy()` and `proxy_usage()`):

Implement the proxy add command per contracts/proxy.md and data-model.md.

**Arguments**: `<container-port> [host-port]`
- `container-port` (required): Port the service listens on inside the container
- `host-port` (optional): Port to listen on the host; defaults to `container-port`

**Behavior**:
1. If no arguments provided: print usage message for proxy add and exit 1. Use a short inline message (not the full `proxy_usage`):
   ```
   Usage: ./dilxc.sh proxy add <container-port> [host-port]
   ```
2. Set `container_port="$1"` and `host_port="${2:-$1}"`
3. Validate `container_port` using `validate_port "$container_port" "container port"`
4. Validate `host_port` using `validate_port "$host_port" "host port"`
5. Set `device_name="proxy-tcp-${host_port}"` (per data-model.md naming convention)
6. Check for duplicate: run `lxc config device show "$CONTAINER_NAME"` and grep for `^${device_name}:`. If found, print `Error: host port ${host_port} is already proxied (device: ${device_name})` and exit 1
7. Create the proxy device:
   ```bash
   lxc config device add "$CONTAINER_NAME" "$device_name" proxy \
     listen="tcp:0.0.0.0:${host_port}" \
     connect="tcp:127.0.0.1:${container_port}"
   ```
8. If the `lxc` command fails: print `Error: failed to add proxy device — is the port already in use?` and exit 1
9. On success: print `Proxy added: 0.0.0.0:${host_port} → container:${container_port} (${device_name})`

**Key details from research.md**:
- Listen on `0.0.0.0` (all interfaces) for LAN accessibility (Decision 2)
- Connect to `127.0.0.1` inside container for stability (Decision 5)
- Duplicate detection via device name lookup, not port scanning (Decision 4)

**Acceptance scenarios** (spec.md US1):
1. `proxy add 3000` → creates `proxy-tcp-3000` with `listen=tcp:0.0.0.0:3000`, `connect=tcp:127.0.0.1:3000`
2. `proxy add 8080 9090` → creates `proxy-tcp-9090` with `listen=tcp:0.0.0.0:9090`, `connect=tcp:127.0.0.1:8080`
3. Duplicate host port → error message with device name

**Checkpoint**: After T003, `./dilxc.sh proxy add 3000` should create a working proxy device. Verify with `lxc config device show docker-lxc`.

---

## Phase 3: User Story 2 — List Active Port Proxies (Priority: P2)

**Goal**: Users can see all active proxy devices and their mappings at a glance.

**Independent Test**: Add one or more proxies, run `proxy list`, verify the output shows correct host→container port mappings in a readable table.

### Implementation for User Story 2

- [x] T004 [US2] Implement `cmd_proxy_list()` function in `dilxc.sh`

### Task Details

**T004 — `cmd_proxy_list()`** (`dilxc.sh`, place after `cmd_proxy_add()`):

Implement the proxy list command per contracts/proxy.md and research.md Decision 7.

**Arguments**: None

**Pre-condition**: Uses `require_container` (not `require_running`) — works on stopped containers per spec clarification.

**Behavior**:
1. Capture output of `lxc config device show "$CONTAINER_NAME"`
2. Parse the YAML output to find devices matching `proxy-tcp-*`
3. For each matching device, extract the `listen` and `connect` field values
4. If no proxy devices found: print `No proxy devices configured` and exit 0
5. If proxies found: display in tabular format per contracts/proxy.md:
   ```
   HOST               CONTAINER
   0.0.0.0:3000    →  127.0.0.1:3000
   0.0.0.0:9090    →  127.0.0.1:8080
   ```

**YAML parsing approach** (research.md Decision 7):
The output of `lxc config device show` looks like:
```yaml
proxy-tcp-3000:
  connect: tcp:127.0.0.1:3000
  listen: tcp:0.0.0.0:3000
  type: proxy
```

Use awk to parse this: track current device name, when it matches `proxy-tcp-*`, capture the `connect` and `listen` values. Strip the `tcp:` prefix for display. Print as formatted table with header and arrow separator.

**Acceptance scenarios** (spec.md US2):
1. With proxies: shows table with HOST and CONTAINER columns
2. Without proxies: prints `No proxy devices configured`

**Checkpoint**: After T004, `./dilxc.sh proxy list` should display a formatted table of all proxy devices.

---

## Phase 4: User Story 3 — Remove a Port Proxy (Priority: P2)

**Goal**: Users can clean up individual proxies by host port or remove all proxies at once.

**Independent Test**: Add a proxy, remove it by port, verify it's gone from `lxc config device show`. Add multiple proxies, remove all, verify all are gone.

### Implementation for User Story 3

- [x] T005 [US3] Implement `cmd_proxy_rm()` function in `dilxc.sh`

### Task Details

**T005 — `cmd_proxy_rm()`** (`dilxc.sh`, place after `cmd_proxy_list()`):

Implement the proxy rm command per contracts/proxy.md.

**Arguments**: `<host-port>` or `all`

**Behavior (single port removal)**:
1. If no arguments: print usage message and exit 1:
   ```
   Usage: ./dilxc.sh proxy rm <host-port>
          ./dilxc.sh proxy rm all
   ```
2. If argument is not `all`: validate with `validate_port "$1" "host port"`
3. Set `device_name="proxy-tcp-${1}"`
4. Check device exists: run `lxc config device show "$CONTAINER_NAME"` and grep for `^${device_name}:`. If not found: print `Error: no proxy found for host port ${1}` and exit 1
5. Remove the device: `lxc config device remove "$CONTAINER_NAME" "$device_name"`
6. If `lxc` command fails: print `Error: failed to remove proxy device` and exit 1
7. On success: print `Proxy removed: ${device_name}`

**Behavior (`all` removal)**:
1. Get list of all `proxy-tcp-*` device names from `lxc config device show "$CONTAINER_NAME"` output (grep for lines matching `^proxy-tcp-.*:` and strip the colon)
2. If no proxy devices found: print `No proxy devices to remove` and exit 0
3. Loop over each device name and run `lxc config device remove "$CONTAINER_NAME" "$device_name"`
4. Count removals. Print `Removed <count> proxy device(s)`

**Acceptance scenarios** (spec.md US3):
1. `proxy rm 3000` with existing proxy → removes `proxy-tcp-3000`, prints confirmation
2. `proxy rm all` with multiple proxies → removes all, prints count
3. `proxy rm 3000` with no proxy on that port → error message

**Checkpoint**: After T005, `./dilxc.sh proxy rm <port>` and `./dilxc.sh proxy rm all` should work correctly.

---

## Phase 5: Polish & Cross-Cutting Concerns

**Purpose**: Validate the complete feature against acceptance scenarios and verify end-to-end workflows.

- [x] T006 Validate all proxy commands against acceptance scenarios from spec.md on a live container
- [x] T007 Run quickstart.md common workflow end-to-end on a live container

## Completion Summary

All 7 tasks completed on 2026-02-11. Implementation validated against live `claude-sandbox` container.

### Task Details

**T006 — Acceptance validation** (live container):

Run through every acceptance scenario from spec.md against the live `docker-lxc` container:

1. **US1 scenarios**: `proxy add 3000` (same port), `proxy add 8080 9090` (different ports), duplicate add (should error)
2. **US2 scenarios**: `proxy list` (with proxies), clean up all, `proxy list` (no proxies)
3. **US3 scenarios**: `proxy rm 9090` (single), `proxy rm all` (all), `proxy rm 9999` (nonexistent → error)
4. **Edge cases**: Invalid port (0, 99999, abc, -1), no args to `proxy add`, no args to `proxy rm`, `proxy --help`, stopped container behavior for `proxy list`
5. **Verify output format**: Matches contracts/proxy.md exactly (success messages, error messages, table format)

**T007 — Quickstart workflow** (live container):

Run the complete workflow from quickstart.md:
1. Start a service inside the container (`python3 -m http.server 8000` or similar)
2. Run `./dilxc.sh proxy add 8000`
3. Verify the service is reachable at `<host-ip>:8000`
4. Run `./dilxc.sh proxy list` and verify the output
5. Run `./dilxc.sh proxy rm 8000`
6. Verify the service is no longer reachable on the host port

---

## Dependencies & Execution Order

### Phase Dependencies

- **Foundational (Phase 1)**: No dependencies — start immediately. BLOCKS all user stories.
- **US1 (Phase 2)**: Depends on Phase 1 completion (needs `validate_port` and dispatch scaffolding)
- **US2 (Phase 3)**: Depends on Phase 1 completion. Independent of US1 (no code dependency).
- **US3 (Phase 4)**: Depends on Phase 1 completion. Independent of US1 and US2 (no code dependency).
- **Polish (Phase 5)**: Depends on Phases 2, 3, and 4 all being complete.

### User Story Independence

- **US1, US2, US3** are independent at the code level — each is a separate function in `dilxc.sh` with no cross-references.
- However, all three modify the same file, so true parallel execution by separate agents is impractical.
- Recommended execution order: US1 → US2 → US3 (priority order), since US1 is needed to create proxies for manual testing of US2 and US3.

### Within Each User Story

Each user story is a single task (one function), so no within-story ordering is needed.

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Complete Phase 1: Foundational (T001-T002)
2. Complete Phase 2: User Story 1 (T003)
3. **STOP and VALIDATE**: Run `proxy add 3000`, verify with `lxc config device show`
4. MVP delivers the core value — exposing container services to the LAN

### Incremental Delivery

1. Phase 1 (T001-T002) → Scaffolding in place, `proxy --help` works
2. Phase 2 (T003) → `proxy add` works → MVP!
3. Phase 3 (T004) → `proxy list` works → visibility
4. Phase 4 (T005) → `proxy rm` works → full lifecycle
5. Phase 5 (T006-T007) → Validated against all acceptance scenarios

---

## Notes

- All 7 tasks modify a single file (`dilxc.sh`) — no parallel execution opportunities
- No test tasks generated (not requested in spec)
- Each user story is one function; the simplicity reflects the ~150-line scope of this feature
- The existing `require_container` and `require_running` helpers are reused, not reimplemented
- Commit after each phase for clean git history
