# CLI Contract: provision-container.sh

**Script**: `provision-container.sh`
**Execution context**: Inside the LXD container (pushed and invoked by `setup-host.sh`)
**Error handling**: `set -euo pipefail` — exits on any failure
**Recovery**: Delete container and re-run `setup-host.sh` from scratch

## Synopsis

```
/tmp/provision-container.sh [--fish]
```

## Options

| Flag | Argument | Default | Description |
|------|----------|---------|-------------|
| `--fish` | *(none)* | `false` | Install fish shell, write fish config, set as default shell |

## Environment Variables

| Variable | Effect |
|----------|--------|
| `DEBIAN_FRONTEND` | Set to `noninteractive` internally to suppress apt prompts |

## Installation Sequence

| Order | Component | Method | Verification |
|-------|-----------|--------|-------------|
| 1 | System packages | `apt-get update && upgrade` | — |
| 2 | Docker CE + compose | Docker apt repo + `gpg --dearmor --yes` | `docker --version` printed |
| 3 | Node.js 22 LTS | NodeSource setup script | `node --version` + `npm --version` printed |
| 4 | Claude Code | `npm install -g @anthropic-ai/claude-code` | Installed message |
| 5 | uv + Spec Kit | uv install script + `uv tool install specify-cli` | Installed message |
| 6 | Dev tools | apt install: git, build-essential, jq, ripgrep, fd-find, htop, tmux, postgresql-client | Installed message |
| 7 | Git defaults | `git config --global` (main branch, sandbox identity) | — |
| 8 | User config | Bash aliases, functions, PATH in `.bashrc` | — |
| 9 | Fish (optional) | Install fish, write config, `chsh` | Only if `--fish` passed |

## User Configuration Written

### Bash (always)

Appended to `/home/ubuntu/.bashrc`:

| Item | Type | Value |
|------|------|-------|
| PATH | export | `$HOME/.local/bin:$PATH` |
| `cc` | alias | `claude --dangerously-skip-permissions` |
| `cc-resume` | alias | `claude --dangerously-skip-permissions --resume` |
| `cc-prompt` | alias | `claude --dangerously-skip-permissions -p` |
| `sync-project` | function | rsync with `--delete` and 4 excludes |
| `deploy` | function | rsync to `/mnt/deploy` if mounted |

### Fish (only with `--fish`)

Written to `/home/ubuntu/.config/fish/config.fish`:

| Item | Type | Value |
|------|------|-------|
| PATH | `fish_add_path` | `~/.local/bin` |
| `cc` | abbreviation | `claude --dangerously-skip-permissions` |
| `cc-resume` | abbreviation | `claude --dangerously-skip-permissions --resume` |
| `cc-prompt` | abbreviation | `claude --dangerously-skip-permissions -p` |
| `sync-project` | function | rsync with `--delete` and 4 excludes |
| `deploy` | function | rsync to `/mnt/deploy` if mounted |

### Git defaults

| Config | Value |
|--------|-------|
| `init.defaultBranch` | `main` |
| `user.name` | `Claude Code (docker-lxc)` |
| `user.email` | `docker-lxc@localhost` |

## Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success |
| 1 | Any failure (apt, npm, curl, etc. — via `set -e`) |

## Output

Verbose progress to stdout with section headers (`--- Installing Docker ---`). Final summary prints versions of all installed components.

## Idempotency

Designed for re-run safety (Constitution Principle VII):
- `gpg --dearmor --yes` overwrites existing GPG key
- `apt-get install -y` is naturally idempotent
- `npm install -g` upgrades if already installed
- **Caveat**: Bash config is appended via `cat >>`, so re-provisioning duplicates the aliases block. This is an accepted limitation — the primary recovery path is delete-and-recreate.
