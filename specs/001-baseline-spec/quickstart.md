# Quickstart: Docker-in-LXC

## Prerequisites

- Ubuntu server with LXD installed (`sudo snap install lxd && sudo lxd init`)
- btrfs storage pool configured in LXD
- User in the `lxd` group (`sudo usermod -aG lxd $USER`, then re-login)
- Internet connectivity for downloading packages during provisioning

## 1. Create a Sandbox

```bash
# Basic setup — mount your project read-only
./setup-host.sh -n docker-lxc -p /home/john/dev/myproject/

# With fish shell as default
./setup-host.sh -n docker-lxc -p /home/john/dev/myproject/ --fish

# With deploy mount for pushing output back to host
./setup-host.sh -n docker-lxc -p /home/john/dev/myproject/ -d /srv/www
```

Setup creates the container, installs all tooling (Docker, Node.js, Claude Code, uv, Spec Kit), and takes a `clean-baseline` snapshot.

## 2. Authenticate

```bash
# Browser OAuth (Claude Max subscribers)
./dilxc.sh login
# Complete the flow in your browser, then exit with /exit

# OR: API key (set before running setup-host.sh)
ANTHROPIC_API_KEY=sk-... ./setup-host.sh -p /path/to/project
```

## 3. Sync Your Project

```bash
# Copy project files from read-only mount to writable working directory
./dilxc.sh sync
```

## 4. Run Claude Code

```bash
# Interactive session (autonomous mode)
./dilxc.sh claude

# One-shot prompt
./dilxc.sh claude-run "refactor the auth module and run tests"

# Resume last session
./dilxc.sh claude-resume
```

## 5. Snapshot Before Risky Operations

```bash
# Take a named snapshot
./dilxc.sh snapshot before-big-refactor

# If something goes wrong, instant rollback
./dilxc.sh restore before-big-refactor

# List all snapshots
./dilxc.sh snapshots
```

## 6. Get Files Out

```bash
# Pull files from container to host
./dilxc.sh pull /home/ubuntu/project/dist/ ./dist/

# Or push from host to container
./dilxc.sh push local-file.txt /home/ubuntu/project/
```

## Common Operations

```bash
./dilxc.sh shell              # Interactive shell
./dilxc.sh exec npm test      # Run a command in the project dir
./dilxc.sh docker ps          # Docker commands inside sandbox
./dilxc.sh health-check       # Verify everything works
./dilxc.sh status             # Container info + snapshots
```

## Multiple Sandboxes

```bash
# Create a second sandbox for a different project
./setup-host.sh -n project-b -p /home/john/dev/other-project/

# Operate on it
DILXC_CONTAINER=project-b ./dilxc.sh claude
```

## Important Notes

- **Sync is destructive**: `dilxc.sh sync` uses `rsync --delete` — files only in the working copy are removed. Commit and push to GitHub before syncing.
- **The container IS the sandbox**: Claude runs with `--dangerously-skip-permissions`. If something goes wrong, restore a snapshot.
- **Setup failures**: Delete the container (`./dilxc.sh destroy`) and re-run `setup-host.sh`.
