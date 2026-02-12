# Data Model: LXC Port Proxy

**Branch**: `002-port-proxy` | **Date**: 2026-02-11

## Entities

### Proxy Device

An LXD proxy device that forwards TCP traffic from a host port to a container port. Managed via `lxc config device add/show/remove`.

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| device_name | string | derived | Format: `proxy-tcp-<host_port>` (e.g., `proxy-tcp-3000`) |
| container | ContainerRef | `$DILXC_CONTAINER` | Parent container that owns this device |
| type | string | hardcoded | Always `proxy` |
| listen | string | computed | Format: `tcp:0.0.0.0:<host_port>` |
| connect | string | computed | Format: `tcp:127.0.0.1:<container_port>` |
| protocol | string | hardcoded | Always `tcp` (UDP out of scope) |
| host_port | integer | user input | Port on the host; range 1-65535 |
| container_port | integer | user input | Port in the container; range 1-65535; defaults to host_port if omitted |

**Validation rules**:
- Port numbers must be integers in range 1-65535
- Device name must be unique within the container (enforced by naming convention — one proxy per host port)
- Container must be running before add/remove operations (`require_running`)

**State transitions**:

```
[Not Created] --proxy add--> [Active]
                                |
                                +--proxy rm--> [Removed]
                                |
                                +--proxy rm all--> [Removed]
                                |
                                +--container restart--> [Active] (persists)
                                |
                                +--container destroy--> [Gone]
```

**Persistence**: Proxy devices persist across container restarts. They are stored in the container's LXD configuration, not in memory. Removing a proxy device deletes it from the configuration permanently.

## Relationships

```
Container 1 ──── 0..* ProxyDevice
Container 1 ──── 0..1 ProjectMount (read-only disk device)
Container 1 ──── 0..1 DeployMount (read-write disk device)

ProxyDevice names: proxy-tcp-<host_port>
ProjectMount name: project
DeployMount name:  deploy
```

Proxy devices coexist with disk devices in the container's device list. The naming convention (`proxy-tcp-*` vs `project`/`deploy`) ensures no collisions.

## Command-to-LXC Mapping

| dilxc.sh command | LXC command | Notes |
|------------------|-------------|-------|
| `proxy add <cport> [hport]` | `lxc config device add $CONTAINER proxy-tcp-<hport> proxy listen=tcp:0.0.0.0:<hport> connect=tcp:127.0.0.1:<cport>` | Creates device; hport defaults to cport |
| `proxy list` | `lxc config device show $CONTAINER` | Filter output for `proxy-tcp-*` devices |
| `proxy rm <port>` | `lxc config device remove $CONTAINER proxy-tcp-<port>` | Removes single device |
| `proxy rm all` | `lxc config device remove $CONTAINER <name>` (repeated) | Removes all `proxy-tcp-*` devices |
