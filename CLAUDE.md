# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Bash scripts for running Claude Code autonomously inside an LXD system container on an Ubuntu homelab server. The LXD container IS the sandbox — Claude Code runs with `--dangerously-skip-permissions` inside it, and btrfs snapshots provide rollback safety. Docker runs natively inside the container (via `security.nesting=true`), avoiding Docker-in-Docker complications.

## Host Environment

- **Server**: Ubuntu (hostname: gram-server, user: john)
- **LXD bridge**: `lxdbr0` at 10.200.12.1/24
- **Storage**: btrfs pool on dedicated LVM volume at `/var/lib/lxd-storage`
- Docker also runs on the host with many stacks — Docker's iptables rules can block LXD bridge traffic (see Known Issues below)

## Architecture

Three scripts, each with a distinct execution context:

1. **`setup-host.sh`** — Runs on the host. One-time setup: creates an Ubuntu 24.04 LXD container, mounts project directory read-only, pushes and executes the provisioning script, takes a baseline snapshot. Uses `set -euo pipefail`; if it fails partway through, delete the container and start fresh rather than resuming. Presents browser OAuth login as the primary auth method; API key injection via `ANTHROPIC_API_KEY` env var is the alternative.

2. **`provision-container.sh`** — Runs inside the container (pushed by setup-host.sh). Installs Docker CE, Node.js 22 (NodeSource), Claude Code (npm global), and dev tools. Configures the `ubuntu` user with aliases (`cc`, `cc-resume`, `cc-prompt`), helper functions (`sync-project`, `deploy`), and `~/.local/bin` on PATH in bash. Fish shell is opt-in via `--fish` flag (installs fish, writes fish config, sets fish as default shell).

3. **`dilxc.sh`** — Runs on the host. Day-to-day management wrapper around `lxc` commands. Container name comes from `DILXC_CONTAINER` env var (default: `docker-lxc`).

## File Strategy Inside the Container

- `/home/ubuntu/project-src` — Host project mounted read-only
- `/home/ubuntu/project` — Writable working copy (Claude works here)
- `/mnt/deploy` — Optional read-write mount for deploying output to host

## Custom Provision Scripts

Users can create an optional `custom-provision.sh` in the repo root to install additional tools in every new container. This file is gitignored (user-specific, not committed to the shared repo).

### How it works

- `setup-host.sh` detects `custom-provision.sh` in the repo root and pushes it to `/tmp/custom-provision.sh` inside the container
- `provision-container.sh` checks for `/tmp/custom-provision.sh` at the end of standard provisioning and executes it if present
- If the file is absent, both scripts skip silently — no errors

### Writing a custom provision script

The script runs as **root** inside an **Ubuntu 24.04** container with network access. The following are already installed by standard provisioning: Docker CE, Node.js 22, npm, git, Claude Code, gh CLI, and common dev tools (jq, ripgrep, fd-find, htop, tmux).

**Required conventions:**
- Start with `#!/bin/bash` and `set -euo pipefail` (so failing commands halt the script and propagate the error to the parent provisioning process)
- Must be **idempotent** — safe to run multiple times (use `apt-get install -y`, check-before-install patterns like `command -v tool || install_tool`)
- Must be **non-interactive** — no stdin prompts (`DEBIAN_FRONTEND=noninteractive`, `-y` flags)
- Use section structure: `echo "--- Installing X ---"` headers, `echo "  X installed ✓"` results

**Available package managers:** `apt-get`, `npm`, `pip`

### Creating the file

Run `./dilxc.sh customize` to create a starter template and open it in your editor, or create `custom-provision.sh` manually in the repo root.

## Key Commands

```bash
# Setup help
./setup-host.sh --help

# Initial setup (run on host)
./setup-host.sh -n docker-lxc -p /home/john/dev/jellyfish/
./setup-host.sh -n docker-lxc -p /home/john/dev/jellyfish/ --fish

# Authenticate (one-time, after setup)
./dilxc.sh login

# Re-provision an existing container without recreating it
lxc exec docker-lxc -- rm -f /tmp/provision-container.sh /tmp/custom-provision.sh
lxc file push provision-container.sh docker-lxc/tmp/provision-container.sh
[[ -f custom-provision.sh ]] && lxc file push custom-provision.sh docker-lxc/tmp/custom-provision.sh
lxc exec docker-lxc -- chmod +x /tmp/provision-container.sh
lxc exec docker-lxc -- /tmp/provision-container.sh

# Day-to-day (run on host)
./dilxc.sh shell                # interactive shell as ubuntu
./dilxc.sh claude               # interactive Claude Code (autonomous)
./dilxc.sh claude-run "prompt"  # one-shot Claude Code
./dilxc.sh claude-resume        # resume last session
./dilxc.sh exec npm test        # run a command in the project dir
./dilxc.sh snapshot <name>      # btrfs snapshot
./dilxc.sh restore <name>       # instant rollback (auto-restarts)
./dilxc.sh sync                 # rsync project-src -> project
./dilxc.sh docker <args>        # run docker commands inside sandbox
./dilxc.sh health-check         # verify container, network, Docker, Claude
./dilxc.sh git-auth             # check SSH agent and GitHub CLI auth status
./dilxc.sh customize            # create/edit custom provisioning script

# Multiple containers
DILXC_CONTAINER=other-name ./dilxc.sh shell
```

## Known Issues

### Docker iptables vs LXD bridge (RESOLVED)

Docker's iptables rules on the host block LXD bridge traffic at two levels, causing containers to get IPv6 but no IPv4:

1. **INPUT chain** — UFW drops DHCP requests (udp/67) and DNS (udp+tcp/53) from lxdbr0. The default `before.rules` only allows DHCP *replies* (sport 67, dport 68), not *requests* from containers to dnsmasq on the bridge.

2. **FORWARD chain** — Docker's `DOCKER-USER` chain (defined in `/etc/ufw/after.rules`) allows specific subnets then DROPs all else. lxdbr0's 10.200.12.0/24 was not in the allow list.

**Fix applied** (persistent across reboots via UFW):

In `/etc/ufw/before.rules`, before the final `COMMIT`:
```
# LXD bridge: allow DHCP, DNS, and forwarding for lxdbr0
-A ufw-before-input -i lxdbr0 -p udp --dport 67 -j ACCEPT
-A ufw-before-input -i lxdbr0 -p udp --dport 53 -j ACCEPT
-A ufw-before-input -i lxdbr0 -p tcp --dport 53 -j ACCEPT
-A ufw-before-forward -i lxdbr0 -j ACCEPT
-A ufw-before-forward -o lxdbr0 -j ACCEPT
```

In `/etc/ufw/after.rules`, in the `DOCKER-USER` section before the DROP:
```
-A DOCKER-USER -s 10.200.12.0/24 -j RETURN
```

Reload with `sudo ufw reload`. No need for `netfilter-persistent` (it's in `rc` removed state on this host).

### Re-provisioning: `lxc file push` won't overwrite

When re-pushing `provision-container.sh` to an existing container, `lxc file push` silently fails to overwrite the file (reports "Forbidden" after showing 100% progress). Delete the target file first:
```bash
lxc exec docker-lxc -- rm -f /tmp/provision-container.sh
lxc file push provision-container.sh docker-lxc/tmp/provision-container.sh
```

## Editing Notes

- All three scripts use `#!/bin/bash`. `setup-host.sh` and `provision-container.sh` use `set -euo pipefail`.
- `provision-container.sh` always writes bash config. Fish config is only written when `--fish` is passed — if changing aliases or helper functions, update both shell configs within that script.
- `dilxc.sh` uses a case-based dispatch pattern at the bottom for subcommand routing. The `require_container` and `require_running` helpers validate container state before each command.
- The `sync-project` function (and `dilxc.sh sync`) excludes `node_modules`, `.git`, `dist`, and `build` from rsync — keep these lists in sync across bash config, fish config, and `dilxc.sh`.
- `dilxc.sh` uses `-t` flag on `lxc exec` for interactive commands (`shell`, `root`, `login`, `claude`, `claude-resume`) to allocate a proper TTY.
- `dilxc.sh` uses `printf %q` for safe shell escaping in `cmd_claude_run` and `cmd_docker` to handle arguments with spaces and special characters.
- `provision-container.sh` uses `gpg --dearmor --yes` so the Docker GPG key step is idempotent on re-provisioning.
- `custom-provision.sh` is invoked at the end of `provision-container.sh` and pushed by `setup-host.sh` — both files must stay in sync regarding the `/tmp/custom-provision.sh` path convention.
- All LXD disk devices (`project`, `deploy`, `gh-config`) MUST use `shift=true` for kernel idmapped mounts. Without it, host UID 1000 maps to `nobody` (65534) inside the unprivileged container. This breaks `0600` files (gh-config) and causes incorrect ownership on all mounted files. The `gh-config` device is created in three locations (`setup-host.sh`, `ensure_auth_forwarding` in `dilxc.sh`, `cmd_update` in `dilxc.sh`) — all must include `shift=true`.

## Active Technologies
- Bash (GNU Bash, no minimum version requirement beyond Ubuntu 24.04 default) + LXD (`lxc` CLI), rsync, btrfs (via LXD storage pool) (001-baseline-spec)
- btrfs snapshots via `lxc snapshot` / `lxc restore` (001-baseline-spec)
- LXD proxy devices via `lxc config device add/show/remove` for TCP port forwarding (002-port-proxy)
- Bash (GNU Bash, Ubuntu 24.04 default) + LXD (`lxc` CLI), GNU coreutils (`readlink -f`, `dirname`), git (for `update`) (003-cli-ux)
- N/A (no persistent data beyond `.dilxc` convention files) (003-cli-ux)
- Bash (GNU Bash, Ubuntu 24.04 default) + LXD (`lxc` CLI), GitHub CLI (`gh`), OpenSSH (`ssh-agent`, `ssh-add`) (004-git-forge-auth)
- N/A (LXD device metadata in Dqlite database) (004-git-forge-auth)
- N/A (single optional file in repo root, `/tmp/` inside container) (005-custom-provision-scripts)
- N/A (shell scripts and markdown files) (006-slim-default-provision)

## Recent Changes
- 006-slim-default-provision: Removed uv, Spec Kit, postgresql-client from default provisioning; added RECIPES.md with custom provisioning recipes
- 005-custom-provision-scripts: Added optional `custom-provision.sh` mechanism, `customize` CLI subcommand, agent instructions for generating custom provision scripts
- 004-git-forge-auth: Added SSH agent forwarding, GitHub CLI config sharing, `git-auth` diagnostic subcommand, `ensure_auth_forwarding` pre-command hook
- 001-baseline-spec: Added Bash (GNU Bash, no minimum version requirement beyond Ubuntu 24.04 default) + LXD (`lxc` CLI), rsync, btrfs (via LXD storage pool)
