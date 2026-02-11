# Data Model: Docker-in-LXC

**Branch**: `001-baseline-spec` | **Date**: 2026-02-11

## Entities

### Container

The primary entity. An LXD system container bound to a single host project.

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| name | string | `$DILXC_CONTAINER` or `-n` flag | Default: `docker-lxc` |
| image | string | hardcoded | `ubuntu:24.04` |
| status | enum | `lxc info` | `RUNNING`, `STOPPED`, `FROZEN` |
| nesting | bool | config | Always `true` (Docker support) |
| project_mount | DeviceRef | `lxc config device` | Read-only disk at `/home/ubuntu/project-src` |
| deploy_mount | DeviceRef? | `lxc config device` | Optional read-write disk at `/mnt/deploy` |
| snapshots | Snapshot[] | `lxc info` | Zero or more btrfs snapshots |
| ip_address | string | `lxc list` | Assigned by lxdbr0 DHCP |

**Validation rules**:
- Name must be a valid LXD container name (alphanumeric + hyphens)
- Project mount source path must exist on host before setup
- Container must exist before any `dilxc.sh` operation (`require_container`)
- Container must be RUNNING for most operations (`require_running`)

**State transitions**:

```
[Not Created] --setup-host.sh--> RUNNING --stop--> STOPPED
                                    |                  |
                                    |<----start--------|
                                    |
                                    |--restart--> STOPPED --> RUNNING
                                    |
                                    |--restore--> STOPPED --> RUNNING (auto-start)
                                    |
                                    |--destroy--> [Deleted]

[Not Created] = no container exists
[Deleted]     = container and all snapshots removed
```

### Snapshot

A btrfs point-in-time capture of a container's full state.

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| name | string | user-provided or auto-generated | Auto format: `snap-YYYYMMDD-HHMMSS` |
| container | ContainerRef | parent container | One container has many snapshots |
| created_at | timestamp | LXD metadata | Set by `lxc snapshot` |

**Validation rules**:
- Snapshot name must be unique within a container
- `clean-baseline` is created automatically at end of setup
- Restore requires an existing snapshot name; lists available if name missing

**State transitions**:

```
[None] --snapshot--> [Exists] --restore--> [Container reset to this state]
                         |
                         +--destroy--> [Deleted with container]
```

### Project Mount (Device)

An LXD disk device binding a host directory into the container.

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| device_name | string | hardcoded | `project` or `deploy` |
| source | path | `-p` or `-d` flag | Host directory path |
| path | path | hardcoded | `/home/ubuntu/project-src` or `/mnt/deploy` |
| readonly | bool | config | `true` for project, `false` for deploy |

**Validation rules**:
- Existing device is removed before re-add (idempotent)
- Source path should exist on host (LXD handles this)

### Working Copy

Not an LXD entity — a filesystem directory managed by rsync.

| Field | Type | Source | Notes |
|-------|------|--------|-------|
| path | path | hardcoded | `/home/ubuntu/project` |
| source | path | hardcoded | `/home/ubuntu/project-src` |
| excludes | string[] | hardcoded | `node_modules`, `.git`, `dist`, `build` |
| sync_mode | enum | hardcoded | Destructive (`--delete`) |

**Validation rules**:
- Directory created during provisioning (`mkdir -p`)
- Content populated post-setup by user running `dilxc.sh sync` (not during provisioning)
- Exclude lists must match across bash config, fish config, and `dilxc.sh sync`

## Relationships

```
Container 1 ──── 0..* Snapshot
Container 1 ──── 0..1 ProjectMount (read-only)
Container 1 ──── 0..1 DeployMount (read-write)
Container 1 ──── 1    WorkingCopy

ProjectMount ──syncs-to──> WorkingCopy (via rsync --delete)
WorkingCopy  ──deploys-to──> DeployMount (via rsync --delete)
```

## Authentication Model

Not a persistent entity — transient configuration.

| Method | Mechanism | Persistence |
|--------|-----------|-------------|
| Browser OAuth | `claude` interactive login | Stored by Claude Code in user home |
| API Key | `ANTHROPIC_API_KEY` env var | Written to `.bashrc` (and `.config/fish/config.fish` if fish) |

OAuth is the primary method (Claude Max subscribers). API key is the alternative, injected during setup if the env var is set.

## Shell Configuration

Written by `provision-container.sh`, consumed by the `ubuntu` user inside the container.

| Item | Bash | Fish | Notes |
|------|------|------|-------|
| `cc` alias | `alias cc='claude --dangerously-skip-permissions'` | `abbr -a cc ...` | Interactive Claude |
| `cc-resume` alias | `alias cc-resume='...'` | `abbr -a cc-resume ...` | Resume session |
| `cc-prompt` alias | `alias cc-prompt='...'` | `abbr -a cc-prompt ...` | One-shot prompt |
| `sync-project` function | bash function | fish function | Same rsync command |
| `deploy` function | bash function | fish function | Same rsync to `/mnt/deploy` |
| PATH | `export PATH="$HOME/.local/bin:$PATH"` | `fish_add_path ~/.local/bin` | uv/Spec Kit binaries |

Parity between bash and fish is required by Constitution Principle IX.
