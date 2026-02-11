# Claude Code LXD Sandbox

Run [Claude Code](https://docs.anthropic.com/en/docs/claude-code) autonomously inside an LXD system container with full Docker support, btrfs snapshot rollback, and [Spec Kit](https://github.com/github/spec-kit) for spec-driven development.

## Why LXD?

Claude Code's built-in sandbox can't run Docker. Running Claude Code inside a Docker container creates Docker-in-Docker problems. An LXD **system container** gives you a full Linux environment where Docker runs natively — Claude Code doesn't know it's in a container and everything just works.

- **Real Docker** — `docker compose up` works, Postgres runs, ports bind normally
- **Instant rollback** — btrfs snapshots before every session, restore in seconds
- **Source protection** — your project is mounted read-only; Claude works on a copy
- **Set it and forget it** — kick off autonomous sessions and walk away

## What Gets Installed

The container comes fully provisioned with:

- Ubuntu 24.04 with Docker CE running natively
- Node.js 22, Claude Code, and dev tools (git, ripgrep, jq, tmux, fish, etc.)
- [uv](https://github.com/astral-sh/uv) and [Spec Kit](https://github.com/github/spec-kit) (`specify-cli`) for spec-driven workflows
- Fish shell with aliases (`cc`, `cc-resume`, `cc-prompt`) and helpers (`sync-project`, `deploy`)
- A clean baseline snapshot for factory resets

## Prerequisites

- Ubuntu host (tested on 24.04, should work on 22.04+)
- LXD installed (`sudo snap install lxd && lxd init`)
- A btrfs or ZFS storage pool (for instant snapshots)
- A Claude Pro/Max subscription or Anthropic API key

If Docker also runs on your host, you'll need firewall rules to prevent Docker's iptables from blocking LXD bridge traffic. See [Host Firewall Setup](#host-firewall-setup).

## Quick Start

```bash
# 1. Clone and make scripts executable
git clone https://github.com/your-user/claude-lxc-sandbox.git
cd claude-lxc-sandbox
chmod +x setup-host.sh provision-container.sh sandbox.sh

# 2. Create the sandbox (takes ~5 minutes)
./setup-host.sh -n claude-sandbox -p /path/to/your/project

# 3. Authenticate Claude Code (one-time)
./sandbox.sh login
# Complete the browser OAuth flow, then type /exit

# 4. Start working
./sandbox.sh sync                              # copy project into sandbox
./sandbox.sh claude                            # interactive autonomous session
./sandbox.sh claude-run "fix the failing tests" # or fire-and-forget
```

**Using an API key instead?** Export it before setup:
```bash
export ANTHROPIC_API_KEY="sk-ant-..."
./setup-host.sh -n claude-sandbox -p /path/to/your/project
```

## Day-to-Day Usage

### sandbox.sh Commands

```
shell                  Open a shell in the container
root                   Open a root shell
start / stop / restart Container lifecycle
status                 Container info and snapshots

login                  Authenticate Claude Code via browser OAuth (one-time)
claude                 Interactive Claude Code (autonomous mode)
claude-run "prompt"    One-shot Claude Code with a prompt
claude-resume          Resume the most recent Claude Code session

sync                   Sync project from read-only mount to working copy
pull <path> [dest]     Pull files from container to host
push <path> [dest]     Push files from host to container

snapshot [name]        Create a snapshot (default: timestamp)
restore <name>         Restore to a snapshot
snapshots              List all snapshots

docker <args>          Run docker commands inside the sandbox
logs                   Tail Docker logs inside the sandbox
destroy                Delete the container (with confirmation)
```

### Typical Session

```bash
./sandbox.sh start                     # if stopped
./sandbox.sh snapshot before-session   # safety net
./sandbox.sh sync                      # pull in latest source
./sandbox.sh claude                    # let Claude loose
```

### One-Shot Prompts

```bash
./sandbox.sh claude-run "refactor the auth module to use JWT"
./sandbox.sh claude-run "write integration tests for the API endpoints"
./sandbox.sh claude-run "find and fix the memory leak in the worker process"
```

### Resuming Sessions

If a session gets interrupted or you want to continue where Claude left off:

```bash
./sandbox.sh claude-resume
```

### Snapshots

Take a snapshot before every session. They're instant and free (btrfs copy-on-write).

```bash
./sandbox.sh snapshot before-refactor   # save state
./sandbox.sh snapshots                  # list all

# If Claude goes off the rails:
./sandbox.sh restore before-refactor    # instant rollback

# Factory reset:
./sandbox.sh restore clean-baseline
```

### Getting Files Out

```bash
# Pull to host
./sandbox.sh pull /home/ubuntu/project/dist/ ./output/

# Git push from inside
./sandbox.sh shell
cd ~/project && git push origin feature-branch

# Deploy mount (if set up with -d flag)
# Inside the container:
deploy ./dist/
```

### Docker Inside the Sandbox

Docker runs natively. Use it normally:

```bash
# From inside the container
docker compose up -d
docker compose exec postgres psql -U myuser -d mydb

# From the host
./sandbox.sh docker compose ps
./sandbox.sh docker compose logs -f
```

### Multiple Sandboxes

```bash
./setup-host.sh -n project-alpha -p ~/projects/alpha
./setup-host.sh -n project-beta -p ~/projects/beta

CLAUDE_SANDBOX=project-alpha ./sandbox.sh claude
CLAUDE_SANDBOX=project-beta ./sandbox.sh claude-run "add pagination"
```

## Spec Kit Integration

The container comes with [Spec Kit](https://github.com/github/spec-kit) pre-installed for spec-driven development. If your project has a `.specify/` directory, sync it into the sandbox and use it in prompts:

```bash
./sandbox.sh sync
./sandbox.sh claude-run "implement the feature described in specs/auth-redesign.md"
```

Or use `specify` directly inside the container:

```bash
./sandbox.sh shell
cd ~/project
specify run
```

## How It Works

```
claude-lxc-sandbox/
├── setup-host.sh           # One-time setup (runs on host)
├── provision-container.sh  # Container provisioning (runs inside container)
├── sandbox.sh              # Day-to-day management (runs on host)
├── CLAUDE.md               # Machine-readable project docs for Claude Code
└── README.md
```

**setup-host.sh** creates the LXD container with `security.nesting=true` (required for Docker), mounts your project read-only, pushes the provisioning script inside, runs it, and takes a baseline snapshot.

**provision-container.sh** installs Docker CE, Node.js 22, Claude Code, uv, Spec Kit, and dev tools. It configures fish shell with aliases and helpers in both bash and fish configs.

**sandbox.sh** is your daily driver. It wraps `lxc` commands into a simple interface with proper TTY handling for interactive sessions and safe shell escaping for arguments.

### File Strategy

| Container Path | Access | Purpose |
|---|---|---|
| `/home/ubuntu/project-src` | Read-only | Your host project, mounted directly |
| `/home/ubuntu/project` | Read-write | Working copy where Claude edits |
| `/mnt/deploy` | Read-write | Optional output directory mapped to host |

Claude can't accidentally corrupt your host source. Sync changes in with `./sandbox.sh sync` and extract results with `git push`, `./sandbox.sh pull`, or the deploy mount.

## Host Firewall Setup

> **Only needed if Docker runs on the same host as LXD.**

Docker's iptables rules block LXD bridge traffic in two places. Without these fixes, containers get IPv6 but no IPv4 — they can't reach the internet.

### The Problem

1. **DHCP/DNS blocked** — UFW's default rules don't allow DHCP requests or DNS queries on the LXD bridge (`lxdbr0`). The container can't get an IP address.

2. **Forwarding blocked** — Docker's `DOCKER-USER` chain has a subnet allow-list followed by a blanket DROP. LXD's subnet isn't in it.

### The Fix

**1. Allow DHCP and DNS on the bridge**

Add to `/etc/ufw/before.rules`, before the final `COMMIT`:

```
# LXD bridge: allow DHCP, DNS, and forwarding
-A ufw-before-input -i lxdbr0 -p udp --dport 67 -j ACCEPT
-A ufw-before-input -i lxdbr0 -p udp --dport 53 -j ACCEPT
-A ufw-before-input -i lxdbr0 -p tcp --dport 53 -j ACCEPT
-A ufw-before-forward -i lxdbr0 -j ACCEPT
-A ufw-before-forward -o lxdbr0 -j ACCEPT
```

**2. Allow LXD subnet through Docker's filter**

Add to `/etc/ufw/after.rules`, in the `DOCKER-USER` section before the `-j DROP`:

```
-A DOCKER-USER -s 10.200.12.0/24 -j RETURN
```

Replace `10.200.12.0/24` with your `lxdbr0` subnet (`lxc network get lxdbr0 ipv4.address`).

**3. Apply**

```bash
sudo ufw reload
```

### Verify

```bash
sudo iptables -L ufw-before-input -v -n | grep lxdbr0
sudo iptables -L DOCKER-USER -v -n | grep 10.200
lxc exec claude-sandbox -- ping -c 1 8.8.8.8
```

## Troubleshooting

### Container has no IPv4 address

This is the firewall issue. Apply the [Host Firewall Setup](#host-firewall-setup) fix, then:
```bash
lxc exec claude-sandbox -- networkctl reconfigure eth0
```

### Docker won't start inside the container

```bash
lxc config get claude-sandbox security.nesting   # must be "true"
lxc exec claude-sandbox -- systemctl status docker
```

### Claude Code can't authenticate

**Pro/Max subscribers** — run `./sandbox.sh login` and complete the browser OAuth flow.

**API key users** — verify the key is set:
```bash
./sandbox.sh shell
echo $ANTHROPIC_API_KEY
```

### Provisioning failed partway

Don't try to resume. Delete and recreate:
```bash
lxc delete claude-sandbox --force
./setup-host.sh -n claude-sandbox -p /path/to/your/project
```

### Re-provisioning an existing container

```bash
lxc exec claude-sandbox -- rm -f /tmp/provision-container.sh
lxc file push provision-container.sh claude-sandbox/tmp/provision-container.sh
lxc exec claude-sandbox -- chmod +x /tmp/provision-container.sh
lxc exec claude-sandbox -- /tmp/provision-container.sh
```

Note: `lxc file push` won't overwrite an existing file — you must delete it first.

### Ran out of disk space

```bash
lxc exec claude-sandbox -- df -h /
lxc config device set claude-sandbox root size=50GB
```

## Security Notes

- **Container boundary is your safety net.** `--dangerously-skip-permissions` means Claude runs all commands without asking. The LXD container prevents host damage. Snapshots are your undo button.
- **`security.nesting=true`** allows Docker inside the container. Necessary but slightly widens the attack surface vs a flat container.
- **Deploy mount** (`-d`) gives Claude write access to a host directory. Only mount what you're comfortable with Claude modifying.
- **Read-only source mount** prevents Claude from modifying your host project. All edits happen on the working copy.
- **Resource limits** are available:
  ```bash
  lxc config set claude-sandbox limits.memory 8GB
  lxc config set claude-sandbox limits.cpu 4
  ```

## Alternatives

- **[code-on-incus](https://github.com/mensfeld/code-on-incus)** — A full-featured Incus-based sandbox with resource management, networking profiles, and multi-container orchestration. It does a lot more than this project. If you want something more mature with more features, start there. This project is three shell scripts you can grok 10 minutes.

## License

MIT
