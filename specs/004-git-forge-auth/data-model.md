# Data Model: Git & Forge Authentication Forwarding

**Branch**: `004-git-forge-auth` | **Date**: 2026-02-12

## Entities

### 1. SSH Agent Proxy Device

An LXD proxy device that forwards the host's SSH agent Unix socket into the container.

| Field | Value | Notes |
|-------|-------|-------|
| Device name | `ssh-agent` | On container `$CONTAINER_NAME` |
| Device type | `proxy` | LXD proxy device |
| `connect` | `unix:$SSH_AUTH_SOCK` | Host-side socket; updated dynamically by `dilxc.sh` |
| `listen` | `unix:/tmp/ssh-agent.sock` | Fixed path inside container |
| `bind` | `container` | Socket created on container side |
| `uid` | `1000` | ubuntu user |
| `gid` | `1000` | ubuntu group |
| `mode` | `0600` | Owner-only access |

**Lifecycle**:
- Created by `setup-host.sh` during initial container setup (or by `dilxc.sh update`)
- `connect` path updated by `dilxc.sh` before each interactive command
- Persists across container restarts and snapshot restores (stored in LXD metadata)

**States**:
| State | Condition | Behavior |
|-------|-----------|----------|
| Active | `connect` points to valid host socket | SSH operations work transparently |
| Placeholder | `connect=unix:/dev/null` | Device exists but non-functional; set when `$SSH_AUTH_SOCK` was unset at setup |
| Stale | `connect` points to old/invalid socket | Fails silently; updated on next `dilxc.sh` interaction |
| Missing | Device not configured | No SSH forwarding; `git-auth` reports it |

### 2. GitHub CLI Config Disk Device

An LXD disk device that bind-mounts the host's `~/.config/gh` directory into the container read-only.

| Field | Value | Notes |
|-------|-------|-------|
| Device name | `gh-config` | On container `$CONTAINER_NAME` |
| Device type | `disk` | LXD disk device |
| `source` | `$HOME/.config/gh` | Host-side path (resolved at creation time) |
| `path` | `/home/ubuntu/.config/gh` | Container-side mount point |
| `readonly` | `true` | Prevents writes to host config |

**Lifecycle**:
- Created by `setup-host.sh` if `~/.config/gh` exists at setup time
- Created by `dilxc.sh ensure_auth_forwarding` if directory appears later
- Persists across container restarts and snapshot restores

**States**:
| State | Condition | Behavior |
|-------|-----------|----------|
| Active | Device exists, source dir exists with auth tokens | `gh` commands work transparently |
| Empty | Device exists, source dir exists but empty | `gh auth status` reports "not authenticated" |
| Missing | Device not configured (source dir doesn't exist on host) | No gh forwarding; `git-auth` reports it |

### 3. Shell Environment (SSH_AUTH_SOCK)

Environment variable set in the container's shell configuration files.

| Shell | Config File | Syntax |
|-------|------------|--------|
| Bash | `/home/ubuntu/.bashrc` | `export SSH_AUTH_SOCK=/tmp/ssh-agent.sock` |
| Fish | `/home/ubuntu/.config/fish/config.fish` | `set -gx SSH_AUTH_SOCK /tmp/ssh-agent.sock` |

**Lifecycle**: Written by `provision-container.sh` during container provisioning. Static value — the path never changes.

## Relationships

```
Host SSH Agent ($SSH_AUTH_SOCK)
  └──[proxied via]──→ SSH Agent Proxy Device
                        └──[socket at]──→ /tmp/ssh-agent.sock (container)
                                           └──[referenced by]──→ SSH_AUTH_SOCK env var
                                                                   └──[used by]──→ git, ssh

Host gh Config (~/.config/gh/)
  └──[mounted via]──→ GH Config Disk Device
                        └──[visible at]──→ /home/ubuntu/.config/gh (container)
                                            └──[read by]──→ gh CLI
```

## Validation Rules

1. SSH Agent Proxy Device `connect` path MUST start with `unix:` prefix
2. SSH Agent Proxy Device `listen` path MUST be `/tmp/ssh-agent.sock` (fixed)
3. GH Config Disk Device `readonly` MUST be `true`
4. GH Config Disk Device `source` MUST be an absolute path
5. Device names MUST be `ssh-agent` and `gh-config` (used for lookup in helper functions)
