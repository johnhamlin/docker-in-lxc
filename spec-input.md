# Feature Description for Baseline Spec

This describes the complete, already-built LXD sandbox tool. Everything below is implemented and working. This is a baseline spec — future features build on top of this.

## What it does

Three bash scripts that let you run Claude Code autonomously inside a disposable LXD system container on an Ubuntu homelab server.

## One-time setup (`setup-host.sh`)

The user runs `setup-host.sh` on their Ubuntu host to create a sandbox:

- Creates an Ubuntu 24.04 LXD container with nesting enabled (so Docker works inside it)
- Waits for network connectivity with a 30-second timeout
- Mounts the user's project directory into the container as read-only at `/home/ubuntu/project-src`
- Optionally mounts a deploy directory read-write at `/mnt/deploy`
- Pushes and executes the provisioning script inside the container
- Takes a `clean-baseline` btrfs snapshot when done

The container name defaults to `claude-sandbox` but is configurable via `-n` flag or `CLAUDE_SANDBOX` env var.

If setup fails partway through, the user deletes the container and starts fresh.

## Container provisioning (`provision-container.sh`)

Runs inside the container during setup. Installs:

- Docker CE with compose plugin
- Node.js 22 LTS via NodeSource
- Claude Code via npm (global install)
- uv and Spec Kit (`specify-cli`) for the ubuntu user
- Dev tools: git, build-essential, jq, ripgrep, fd-find, htop, tmux, postgresql-client

Configures the `ubuntu` user with:
- Shell aliases: `cc`, `cc-resume`, `cc-prompt` (all run Claude with `--dangerously-skip-permissions`)
- A `sync-project` function that rsyncs from the read-only mount to the writable working copy, excluding `node_modules`, `.git`, `dist`, and `build`
- A `deploy` function that rsyncs to the deploy mount
- `~/.local/bin` on PATH for uv/Spec Kit
- Git defaults (main branch, sandbox identity)

Fish shell is opt-in via `--fish` flag: installs fish, writes equivalent config with abbreviations and functions, sets fish as the default shell.

## Authentication

Two methods:

1. **Browser OAuth** (primary): After setup, the user runs `./sandbox.sh login`, which opens an interactive Claude session. They complete the OAuth flow in their browser and exit. One-time step.
2. **API key** (alternative): Set `ANTHROPIC_API_KEY` env var before running `setup-host.sh`. The key gets written into shell config inside the container.

## Daily workflow (`sandbox.sh`)

The management wrapper provides these operations:

### Running Claude Code
- `claude` — interactive autonomous session in the project directory
- `claude-run "prompt"` — one-shot execution with a prompt string, arguments safely escaped with `printf %q`
- `claude-resume` — resume the most recent Claude session

### Project management
- `sync` — rsync from read-only source mount to writable working copy (same exclude list as in-container function)
- `exec <command>` — run an arbitrary command in the project directory
- `pull <path> [dest]` — pull files from container to host via `lxc file pull`
- `push <path> [dest]` — push files from host into the container

### Snapshots and rollback
- `snapshot [name]` — create a btrfs snapshot (defaults to timestamped name)
- `restore <name>` — restore to a snapshot and auto-restart the container
- `snapshots` — list all snapshots

### Container lifecycle
- `shell` — interactive shell as ubuntu user (allocates TTY)
- `root` — root shell
- `start`, `stop`, `restart` — lifecycle management
- `status` — show container info, IP, and snapshots
- `destroy` — delete container with confirmation prompt

### Docker passthrough
- `docker <args>` — run docker commands inside the sandbox, arguments safely escaped
- `logs` — show Docker container logs

### Verification
- `health-check` — verifies network connectivity, Docker, Claude Code, project directory, and source mount. Reports each check as ok/FAILED and exits nonzero if anything fails.

## Multiple sandboxes

Set `CLAUDE_SANDBOX=other-name` env var before any `sandbox.sh` command to operate on a different container. Same variable is respected by `setup-host.sh` for the default container name.

Each container is bound to one project directory, set at creation via `--project`. Containers are fully isolated — separate project mounts, independent snapshots, no shared state. Spin up a new container per project, prefix commands with the env var, destroy when done.

## File layout inside the container

- `/home/ubuntu/project-src` — host project directory, mounted read-only
- `/home/ubuntu/project` — writable working copy where Claude operates
- `/mnt/deploy` — optional read-write mount for deploying output back to the host

## Incus support

The tool is meant to work on both LXD and Incus. Only LXD is implemented because that's the current host environment. The `lxc` and `incus` CLIs are nearly identical, so the migration path is straightforward. Incus development starts once an Incus test environment is available.
