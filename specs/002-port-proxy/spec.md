# Feature Specification: LXC Port Proxy

**Feature Branch**: `002-port-proxy`
**Created**: 2026-02-11
**Status**: Draft
**Input**: User description: "We need to add a convenience script to the main shell script to allow users to lxc proxy ports from their lxc container for the project to a port on the host machine. that way, for instance, if a server or docker container is running in lxc and the host machine is a server, the user can access the server from another machine running on the same LAN. Remember to keep it simple yet convenient and keep the scripting human readable"

## User Scenarios & Testing

### User Story 1 - Forward a container port to the host (Priority: P1)

A user is running a web server (or Docker container exposing a port) inside their LXC container. They want to make that service reachable from the host machine and from other machines on the LAN. They run a single command from the host to create an LXC proxy device that maps a container port to a host port.

**Why this priority**: This is the core use case — without the ability to create a proxy, nothing else matters. It delivers immediate value by exposing container services to the network.

**Independent Test**: Can be fully tested by starting a service inside the container on a port, running the proxy command, and then curling the host port from the host or another LAN machine.

**Acceptance Scenarios**:

1. **Given** a running container with a service listening on port 3000, **When** the user runs `./dilxc.sh proxy add 3000`, **Then** an LXC proxy device is created mapping host port 3000 to container port 3000, and the service is reachable at `<host-ip>:3000` from the LAN.
2. **Given** a running container with a service listening on port 8080, **When** the user runs `./dilxc.sh proxy add 8080 9090`, **Then** an LXC proxy device is created mapping host port 9090 to container port 8080.
3. **Given** a proxy is being added for a host port that already has a proxy on this container, **When** the user runs the command, **Then** the user sees a clear error message indicating the conflict.

---

### User Story 2 - List active port proxies (Priority: P2)

A user wants to see which port proxies are currently active for their container so they can manage them or debug connectivity issues.

**Why this priority**: Without visibility into what's proxied, users cannot manage their proxies effectively.

**Independent Test**: Can be fully tested by adding one or more proxies, then running the list command and verifying the output shows the correct mappings.

**Acceptance Scenarios**:

1. **Given** one or more proxy devices exist on the container, **When** the user runs `./dilxc.sh proxy list`, **Then** the output shows each proxy with its host port, container port, and protocol in a human-readable format.
2. **Given** no proxy devices exist on the container, **When** the user runs `./dilxc.sh proxy list`, **Then** the output clearly indicates no proxies are configured.

---

### User Story 3 - Remove a port proxy (Priority: P2)

A user wants to remove a port proxy that is no longer needed, either by specifying the port number or removing all proxies at once.

**Why this priority**: Equal to listing — users need full lifecycle management (add, list, remove) for proxies to be useful.

**Independent Test**: Can be fully tested by adding a proxy, removing it, and verifying the service is no longer reachable on the host port.

**Acceptance Scenarios**:

1. **Given** an active proxy on host port 3000, **When** the user runs `./dilxc.sh proxy rm 3000`, **Then** the proxy device is removed and the port is no longer forwarded.
2. **Given** multiple active proxies, **When** the user runs `./dilxc.sh proxy rm all`, **Then** all proxy devices are removed.
3. **Given** no proxy exists for the specified port, **When** the user tries to remove it, **Then** the user sees a clear error message.

---

### Edge Cases

- **Host port already in use on host**: The tool does not pre-check host port availability. If LXD's proxy bind fails, the error is relayed to the user with a hint: "is it already in use?"
- **Container stopped**: `proxy add` and `proxy rm` require a running container (error with clear message). `proxy list` works on stopped containers.
- **Invalid port numbers** (negative, zero, >65535, non-numeric): Rejected with a clear validation error (FR-007).
- **`proxy add` with no arguments**: Shows usage message with examples (FR-009).

## Clarifications

### Session 2026-02-11

- Q: What should happen when the user specifies a host port already in use by another process on the host? → A: No pre-check; relay LXD's bind failure with a hint suggesting "is it already in use?"
- Q: Should `proxy list` require a running container, or work even when stopped? → A: Allow `proxy list` on stopped containers; require running only for `add` and `rm`.

## Requirements

### Functional Requirements

- **FR-001**: The system MUST provide a `proxy` subcommand in `dilxc.sh` with sub-actions: `add`, `list` (or `ls`), and `rm` (or `remove`).
- **FR-002**: The `proxy add` action MUST accept a container port as the first argument and an optional host port as the second argument, defaulting the host port to the same value as the container port when omitted.
- **FR-003**: The `proxy add` action MUST create an LXC proxy device that listens on all host interfaces (`0.0.0.0`) so the service is reachable from the LAN, not just localhost.
- **FR-004**: The `proxy add` action MUST support TCP protocol by default.
- **FR-005**: The `proxy list` action MUST display all active proxy devices for the container in a readable format showing host port, container port, and protocol.
- **FR-006**: The `proxy rm` action MUST accept a port number to remove a specific proxy, or `all` to remove all proxies.
- **FR-007**: The system MUST validate port numbers are integers in the range 1-65535.
- **FR-008**: The system MUST use clear, descriptive proxy device names (e.g., `proxy-tcp-3000`) so they are easily identifiable in LXC device listings.
- **FR-009**: The system MUST show a usage message with examples when `proxy` is called with no sub-action or with `--help`.
- **FR-010**: The system MUST prevent adding a duplicate proxy for a host port that is already proxied on the container.

## Success Criteria

### Measurable Outcomes

- **SC-001**: Users can expose a container service to the LAN in a single command (under 5 seconds).
- **SC-002**: Users can view all active proxies and understand the mappings at a glance.
- **SC-003**: Users can clean up proxies individually or all at once in a single command.
- **SC-004**: Invalid inputs (bad ports, missing arguments) produce clear, actionable error messages rather than cryptic failures.

## Assumptions

- LXC proxy devices are the correct mechanism for port forwarding (using `lxc config device add` with `type=proxy`). This is a built-in, well-supported LXD feature.
- Only TCP proxying is needed for the initial implementation. UDP support could be added later but is not required.
- The host listen address should be `0.0.0.0` (all interfaces) since the stated goal is LAN accessibility. Users who need localhost-only binding can use `lxc config device` directly.
- The proxy device name convention `proxy-tcp-<host-port>` is sufficient for avoiding conflicts with other LXC devices.
- The container must be running to add or remove proxies (consistent with how other `dilxc.sh` commands work). `proxy list` works on stopped containers since device configs are stored in LXD's database.

## Scope

### In Scope

- Adding, listing, and removing TCP port proxy devices via `dilxc.sh`
- Input validation for port numbers
- Human-readable output and error messages
- Help text and usage examples

### Out of Scope

- UDP port proxying (can be added later)
- Port range forwarding (e.g., 3000-3010)
- Automatic proxy persistence across container restarts (LXC proxy devices persist by default, so this is handled by LXD itself)
- Firewall rule management on the host (UFW rules are managed separately)
- Health checking whether the proxied service is actually responding
