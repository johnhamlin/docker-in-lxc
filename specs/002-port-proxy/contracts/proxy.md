# CLI Contract: dilxc.sh proxy

**Script**: `dilxc.sh`
**Subcommand**: `proxy`
**Execution context**: Host (Ubuntu homelab server)
**Error handling**: No `set -e` — handles failures per-command
**Container selection**: `$DILXC_CONTAINER` env var (default: `docker-lxc`)

## Synopsis

```
./dilxc.sh proxy <action> [options]
```

## Actions

### proxy add

Create an LXC proxy device to forward a host port to a container port.

```
./dilxc.sh proxy add <container-port> [host-port]
```

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| `container-port` | yes | — | Port the service listens on inside the container (1-65535) |
| `host-port` | no | same as container-port | Port to listen on the host (1-65535) |

**Requires**: Container running
**Device name**: `proxy-tcp-<host-port>`
**Listen address**: `tcp:0.0.0.0:<host-port>` (all host interfaces)
**Connect address**: `tcp:127.0.0.1:<container-port>`

**Behavior**:
1. Validate both ports are integers in range 1-65535
2. Check if `proxy-tcp-<host-port>` device already exists on the container
3. If exists: print error and exit 1
4. Create the proxy device via `lxc config device add`
5. Print confirmation with the mapping

**Success output**:
```
Proxy added: 0.0.0.0:3000 → container:3000 (proxy-tcp-3000)
```

**Error cases**:

| Condition | Message | Exit |
|-----------|---------|------|
| No arguments | Usage message with examples | 1 |
| Non-numeric port | `Error: invalid port '<value>' — must be a number between 1 and 65535` | 1 |
| Port out of range | `Error: invalid port '<value>' — must be a number between 1 and 65535` | 1 |
| Host port already proxied | `Error: host port <port> is already proxied (device: proxy-tcp-<port>)` | 1 |
| `lxc config device add` fails | `Error: failed to add proxy device — is the port already in use?` | 1 |

### proxy list / proxy ls

Display all active proxy devices for the container.

```
./dilxc.sh proxy list
./dilxc.sh proxy ls
```

**Requires**: Container exists (works on stopped containers per spec clarification)
**Parameters**: None

**Behavior**:
1. Run `lxc config device show $CONTAINER_NAME`
2. Filter for devices matching `proxy-tcp-*`
3. Parse `listen` and `connect` fields
4. Display in tabular format

**Output (with proxies)**:
```
HOST               CONTAINER
0.0.0.0:3000    →  127.0.0.1:3000
0.0.0.0:9090    →  127.0.0.1:8080
```

**Output (no proxies)**:
```
No proxy devices configured
```

### proxy rm / proxy remove

Remove a proxy device by host port, or remove all proxy devices.

```
./dilxc.sh proxy rm <host-port>
./dilxc.sh proxy rm all
./dilxc.sh proxy remove <host-port>
./dilxc.sh proxy remove all
```

| Parameter | Required | Description |
|-----------|----------|-------------|
| `host-port` | yes (or `all`) | Host port of the proxy to remove (1-65535) |
| `all` | yes (or port) | Remove all proxy devices |

**Requires**: Container running

**Behavior (single port)**:
1. Validate port is integer in range 1-65535
2. Check if `proxy-tcp-<port>` device exists
3. If not: print error and exit 1
4. Remove the device via `lxc config device remove`
5. Print confirmation

**Behavior (all)**:
1. Find all devices matching `proxy-tcp-*`
2. If none: print "No proxy devices to remove" and exit 0
3. Remove each device
4. Print confirmation with count

**Success output (single)**:
```
Proxy removed: proxy-tcp-3000
```

**Success output (all)**:
```
Removed 2 proxy device(s)
```

**Error cases**:

| Condition | Message | Exit |
|-----------|---------|------|
| No arguments | Usage message with examples | 1 |
| Non-numeric port (and not `all`) | `Error: invalid port '<value>' — must be a number between 1 and 65535` | 1 |
| Port out of range | `Error: invalid port '<value>' — must be a number between 1 and 65535` | 1 |
| No proxy for that port | `Error: no proxy found for host port <port>` | 1 |
| `lxc config device remove` fails | `Error: failed to remove proxy device` | 1 |

### proxy (no action / --help)

Display usage and examples.

```
./dilxc.sh proxy
./dilxc.sh proxy --help
```

**Output**:
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

## Port Validation Function

A shared helper validates port numbers for both `add` and `rm`:

```
validate_port(value, label) → void or exit 1
```

- Checks value is a non-empty string
- Checks value is a positive integer (digits only)
- Checks value is in range 1-65535
- On success: returns silently
- On failure: prints `Error: invalid <label> '<value>' — must be a number between 1 and 65535` and exits 1

## Integration with Existing Commands

### Main Dispatch Addition

```bash
# In the case block at the bottom of dilxc.sh:
proxy)  shift; cmd_proxy "$@" ;;
```

### Usage Message Addition

```
  proxy <action>         Manage port proxies (add, list, rm)
```

### Function Pattern

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

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success (or `rm all` with nothing to remove) |
| 1 | Invalid input, missing device, or LXC command failure |

## Examples

```bash
# Forward port 3000 (same on both sides)
./dilxc.sh proxy add 3000

# Forward container:8080 to host:9090
./dilxc.sh proxy add 8080 9090

# See what's proxied
./dilxc.sh proxy list

# Remove one
./dilxc.sh proxy rm 9090

# Remove everything
./dilxc.sh proxy rm all

# Help
./dilxc.sh proxy --help

# Multiple containers
DILXC_CONTAINER=project-b ./dilxc.sh proxy add 3000
```
