# Research: LXC Port Proxy

**Branch**: `002-port-proxy` | **Date**: 2026-02-11
**Context**: Adding port forwarding convenience commands to `dilxc.sh` using LXD proxy devices.

## Decision 1: LXD Proxy Devices for Port Forwarding

**Decision**: Use `lxc config device add` with `type=proxy` for port forwarding rather than iptables rules, SSH tunnels, or socat.

**Rationale**: LXD proxy devices are the native, built-in mechanism for port forwarding between host and container. They persist across restarts, are managed through the same `lxc` CLI used elsewhere in the project, and require no additional dependencies. The `forkproxy` process handles the actual forwarding.

**Alternatives considered**:
- **iptables/nftables rules**: Would work but requires root, is fragile with Docker's iptables interference (a known issue on this host), and doesn't integrate with LXD's device model.
- **SSH port forwarding**: Requires SSH server in the container and key management; adds complexity for no benefit.
- **socat**: Requires installation in the container; not persistent across restarts; not integrated with LXD.

## Decision 2: Listen on 0.0.0.0 (All Interfaces)

**Decision**: Proxy devices listen on `0.0.0.0` (all host interfaces) by default, making services reachable from the LAN.

**Rationale**: The spec explicitly requires LAN accessibility (FR-003). The stated use case is accessing container services from other machines on the LAN. Users who need localhost-only binding can use `lxc config device` directly.

**Alternatives considered**:
- **127.0.0.1 only**: Safer but defeats the stated use case (LAN access from other machines).
- **Configurable bind address**: Adds complexity; `0.0.0.0` is the right default for the stated use case. Advanced users can use the raw `lxc` command.

## Decision 3: Device Naming Convention `proxy-tcp-<host-port>`

**Decision**: Name proxy devices as `proxy-tcp-<host-port>` (e.g., `proxy-tcp-3000`, `proxy-tcp-9090`).

**Rationale**: The name must be unique per container, identifiable as a proxy (vs disk mounts), and parseable for the `list` and `rm` commands. Including the protocol allows future UDP support. Including the host port makes removal by port number a simple name lookup.

**Alternatives considered**:
- **`proxy-<port>`**: Doesn't indicate protocol; harder to extend for UDP.
- **`port-<port>`**: Ambiguous — doesn't indicate it's a proxy device type.
- **User-provided names**: Adds complexity; port-based names are sufficient for the use case.

## Decision 4: Duplicate Detection via Device Name Lookup

**Decision**: Check for existing proxy device with the same host port by checking if a device named `proxy-tcp-<host-port>` already exists, rather than relying on LXD to report bind errors.

**Rationale**: `lxc config device add` succeeds even if the host port is already in use by another process — the bind error only surfaces when the container restarts. Checking the device name catches duplicate proxies within the same container immediately. Port conflicts with non-LXD processes are outside our scope (consistent with the spec's out-of-scope items).

**Alternatives considered**:
- **Checking all device listen ports**: Would require parsing YAML output of `lxc config device show`; the naming convention makes this unnecessary.
- **Checking host port availability with `ss`/`netstat`**: Would catch conflicts with other processes but adds complexity; the spec only requires preventing duplicate proxies on the same container (FR-010).

## Decision 5: Connect to 127.0.0.1 Inside the Container

**Decision**: Proxy devices connect to `tcp:127.0.0.1:<container-port>` rather than the container's eth0 IP.

**Rationale**: `127.0.0.1` is stable regardless of container IP changes. Services inside the container typically listen on `0.0.0.0` or `127.0.0.1`. Using the loopback address avoids needing to look up the container's dynamic IP.

**Alternatives considered**:
- **Container eth0 IP**: Would require looking up the IP and would break if the IP changes (DHCP renewal, restart).
- **Container hostname**: Not supported by LXD proxy device `connect` parameter.

## Decision 6: Nested Case Dispatch for Sub-Actions

**Decision**: Implement `proxy` as a top-level subcommand in the main dispatch, with a nested `case` statement for `add`, `list`/`ls`, `rm`/`remove`, and `--help`.

**Rationale**: Follows the existing `dilxc.sh` pattern where each subcommand is a `cmd_<name>` function called from the main case block. A nested case inside `cmd_proxy` handles the sub-actions cleanly. This is the simplest approach that keeps the code readable.

**Alternatives considered**:
- **Flat dispatch (`proxy-add`, `proxy-list`, `proxy-rm`)**: Would work but makes the help text harder to organize and doesn't group related commands.
- **Separate script for proxy management**: Violates Constitution Principle II (three scripts, three contexts).

## Decision 7: Parsing `lxc config device show` Output

**Decision**: Parse the YAML output of `lxc config device show` using `grep` and `awk` to extract proxy device information for the `list` command.

**Rationale**: The output is simple, structured YAML. Each proxy device has a `connect` and `listen` field with the format `tcp:<addr>:<port>`. Parsing this with basic text tools is straightforward and avoids adding `yq` or `jq` as dependencies. The naming convention `proxy-tcp-*` makes filtering proxy devices from disk devices trivial.

**Alternatives considered**:
- **`yq` for YAML parsing**: More robust but adds a dependency; overkill for this simple structure.
- **`lxc config device list` + per-device `get`**: Would require multiple LXC commands; `show` gives everything in one call.
- **JSON output format (`--format=json`)**: LXD supports `--format=json` for some commands but not consistently for `config device show`.
