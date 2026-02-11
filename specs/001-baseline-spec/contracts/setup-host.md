# CLI Contract: setup-host.sh

**Script**: `setup-host.sh`
**Execution context**: Host (Ubuntu homelab server)
**Error handling**: `set -euo pipefail` — exits on any failure
**Recovery**: Delete container and re-run from scratch

## Synopsis

```
./setup-host.sh [options]
```

## Options

| Flag | Long | Argument | Default | Description |
|------|------|----------|---------|-------------|
| `-n` | `--name` | `<name>` | `$DILXC_CONTAINER` or `docker-lxc` | Container name |
| `-p` | `--project` | `<path>` | *(required)* | Host project directory to mount read-only |
| `-d` | `--deploy` | `<path>` | *(none)* | Host directory to mount read-write for deploy output |
| `-f` | `--fish` | *(none)* | `false` | Install fish shell and set as default |
| `-h` | `--help` | *(none)* | — | Show help and exit |

## Environment Variables

| Variable | Effect |
|----------|--------|
| `DILXC_CONTAINER` | Default container name if `-n` not specified |
| `ANTHROPIC_API_KEY` | If set, injected into container's shell config for API key auth |

## Execution Steps

| Step | Label | Action | Failure behavior |
|------|-------|--------|------------------|
| 1/6 | Install LXD | Install LXD via snap if missing; verify storage + network | Exits with instructions if LXD not initialized |
| 2/6 | Create container | `lxc launch ubuntu:24.04` with nesting; wait 30s for network | Exits if container has no network after 30s |
| 3/6 | Mount project | Add read-only disk device at `/home/ubuntu/project-src` | Exits with error if `-p` not specified |
| 4/6 | Mount deploy | Add read-write disk device at `/mnt/deploy` | Skips with message if `-d` not specified |
| 5/6 | Provision | Push and execute `provision-container.sh` inside container | Exits with "delete and start fresh" message |
| 6/6 | Authentication | Inject API key or print OAuth instructions | Informational only |
| — | Snapshot | Take `clean-baseline` snapshot | Part of normal flow |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Any failure (LXD not initialized, network timeout, provisioning error, unknown flag) |

## Output

Verbose step-by-step progress to stdout. Errors to stderr (via `set -e` propagation). Final output includes a quick reference card of common commands.

## Idempotency

Partially idempotent:
- If container already exists, step 2 is skipped
- Device mounts are removed before re-add
- Provisioning is re-runnable (Constitution Principle VII)
- Snapshot will fail if `clean-baseline` already exists

## Examples

```bash
# Basic setup
./setup-host.sh -n docker-lxc -p /home/john/dev/myproject/

# With fish shell
./setup-host.sh -p /home/john/dev/myproject/ --fish

# With deploy mount
./setup-host.sh -p /home/john/dev/myproject/ -d /srv/www

# With API key auth
ANTHROPIC_API_KEY=sk-... ./setup-host.sh -p /path/to/project
```
