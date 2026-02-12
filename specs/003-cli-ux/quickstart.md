# Quickstart: CLI UX Improvements

**Feature**: 003-cli-ux | **Date**: 2026-02-12

## What Changed

Five additions to the Docker-in-LXC tooling:

1. **Symlink-aware installation** — `dilxc.sh` resolves its real location via `readlink -f`, so it works correctly when invoked through a `~/.local/bin/dilxc` symlink.

2. **`dilxc init`** — Creates a new sandbox by delegating to `setup-host.sh` with full argument passthrough via `exec`.

3. **`dilxc update`** — Self-updates via `git pull` in the script's repo directory.

4. **Container selection cascade** — Automatic container targeting with four priority levels: `@name` prefix, `DILXC_CONTAINER` env var, `.dilxc` file, default.

5. **`dilxc containers`** — Lists all LXD containers with status, marking the active one.

6. **`.gitattributes`** — Excludes development artifacts from `git archive` output.

## How to Use

### Install via symlink

```bash
ln -s /path/to/claude-lxc-sandbox/dilxc.sh ~/.local/bin/dilxc
dilxc help   # works from anywhere
```

### Create a sandbox

```bash
dilxc init -p /home/john/dev/myproject
dilxc init -p /home/john/dev/myproject -n mybox --fish
```

### Target a specific container

```bash
# One-off (highest priority)
dilxc @project-b shell

# Session-level
export DILXC_CONTAINER=staging
dilxc shell

# Project-level (create a .dilxc file)
echo "myproject-sandbox" > /home/john/dev/myproject/.dilxc
cd /home/john/dev/myproject/src/
dilxc shell   # targets myproject-sandbox
```

### Update the tool

```bash
dilxc update
```

### List containers

```bash
dilxc containers
```

## Files Modified

| File | Change |
|------|--------|
| `dilxc.sh` | Added container cascade (lines 1-29), `SCRIPT_DIR` resolution (line 31), `cmd_init()`, `cmd_update()`, `cmd_containers()`, updated `usage()` and dispatch |
| `.gitattributes` | New file — `export-ignore` rules for dev artifacts |

## Verification

All acceptance scenarios from the spec can be verified manually:

```bash
# Symlink resolution
ln -s "$(pwd)/dilxc.sh" /tmp/dilxc-test
/tmp/dilxc-test help        # should show usage
rm /tmp/dilxc-test

# Container cascade
dilxc @nonexistent status   # should target 'nonexistent'
DILXC_CONTAINER=test dilxc status  # should target 'test'

# Init passthrough
dilxc init --help           # should show setup-host.sh help

# Update
dilxc update                # should show git pull output

# Containers listing
dilxc containers            # should list all LXD containers

# Git archive exclusions
git archive HEAD | tar -t | grep -E '(specs/|\.specify/|\.claude/)' && echo "FAIL" || echo "PASS"
```
