# CLI Contract: sandbox.sh

**Script**: `sandbox.sh`
**Execution context**: Host (Ubuntu homelab server)
**Error handling**: No `set -e` — handles failures per-command
**Container selection**: `$CLAUDE_SANDBOX` env var (default: `claude-sandbox`)

## Synopsis

```
./sandbox.sh <command> [options]
```

## Subcommands

### Session Commands

| Command | Requires | TTY | Description |
|---------|----------|-----|-------------|
| `shell` | running | yes | Open bash shell as `ubuntu` user via `su - ubuntu` |
| `root` | running | yes | Open root bash shell |
| `login` | running | yes | Open Claude Code for browser OAuth; user completes flow and exits |

### Claude Code Commands

| Command | Requires | TTY | Description |
|---------|----------|-----|-------------|
| `claude` | running | yes | Interactive Claude Code in `/home/ubuntu/project` with `--dangerously-skip-permissions` |
| `claude-run "<prompt>"` | running | no | One-shot Claude Code with prompt; `printf %q` escaping |
| `claude-resume` | running | yes | Resume most recent Claude Code session |

### Lifecycle Commands

| Command | Requires | TTY | Description |
|---------|----------|-----|-------------|
| `start` | exists | no | Start stopped container |
| `stop` | running | no | Stop container |
| `restart` | running | no | Restart container |
| `status` | exists | no | Show container info, IP address, snapshots |
| `destroy` | exists | no | Delete container after name confirmation prompt |

### File Commands

| Command | Requires | TTY | Description |
|---------|----------|-----|-------------|
| `sync` | running | no | rsync `project-src/` to `project/` with `--delete` and 4 excludes |
| `exec <cmd> [args]` | running | no | Run command in `/home/ubuntu/project`; args escaped via `printf %q` |
| `pull <path> [dest]` | running | no | `lxc file pull -r` from container to host (default dest: `.`) |
| `push <path> [dest]` | running | no | `lxc file push` from host to container (default dest: `/home/ubuntu/project/`) |

### Snapshot Commands

| Command | Requires | TTY | Description |
|---------|----------|-----|-------------|
| `snapshot [name]` | exists | no | Create btrfs snapshot; auto-name: `snap-YYYYMMDD-HHMMSS` |
| `restore <name>` | exists | no | Restore snapshot + auto-restart; lists snapshots if name missing |
| `snapshots` | exists | no | List all snapshots |

### Docker Commands

| Command | Requires | TTY | Description |
|---------|----------|-----|-------------|
| `docker <args>` | running | no | Run docker command inside container; args escaped via `printf %q` |
| `logs` | running | no | Show Docker container logs (compose or standalone) |

### Diagnostic Commands

| Command | Requires | TTY | Description |
|---------|----------|-----|-------------|
| `health-check` | running | no | Check network, Docker, Claude Code, project dir, source mount |
| `help` | — | no | Show usage (also default if no command given) |

## Precondition Helpers

| Helper | Checks | Error output |
|--------|--------|-------------|
| `require_container` | Container exists (`lxc info`) | "container not found" + create instructions |
| `require_running` | Container exists AND status is `RUNNING` | "container is STOPPED" + start instructions |

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CLAUDE_SANDBOX` | `claude-sandbox` | Target container name for all operations |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Command failure, missing container, container not running, or health check failure |

## Output

Each command produces minimal output (success/failure messages). `status` and `health-check` produce structured multi-line output. `health-check` reports each component as `ok` or `FAILED`.

## Argument Escaping

Three commands use `printf '%q'` for safe shell escaping:

| Command | What's escaped | Why |
|---------|---------------|-----|
| `claude-run` | The prompt string | Prompts may contain quotes, spaces, shell metacharacters |
| `exec` | Each positional argument | Commands like `npm test -- --grep "my test"` must pass through |
| `docker` | Each positional argument | Docker args like `-e "MY_VAR=hello world"` must pass through |

## Examples

```bash
# Authentication
./sandbox.sh login

# Interactive Claude
./sandbox.sh claude

# One-shot with special characters
./sandbox.sh claude-run "fix the tests in src/api/ and run 'npm test'"

# Resume last session
./sandbox.sh claude-resume

# Sync project files
./sandbox.sh sync

# Run a command
./sandbox.sh exec npm test

# Snapshot workflow
./sandbox.sh snapshot before-refactor
./sandbox.sh restore before-refactor

# File transfer
./sandbox.sh pull /home/ubuntu/project/dist/ ./dist/
./sandbox.sh push local-file.txt /home/ubuntu/project/

# Docker passthrough
./sandbox.sh docker compose up -d
./sandbox.sh docker ps

# Health check
./sandbox.sh health-check

# Multiple sandboxes
CLAUDE_SANDBOX=project-b ./sandbox.sh claude
```
