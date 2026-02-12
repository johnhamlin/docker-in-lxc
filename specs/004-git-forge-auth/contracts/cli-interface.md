# CLI Interface Contract: Git & Forge Authentication

**Branch**: `004-git-forge-auth` | **Date**: 2026-02-12

## New Subcommand: `dilxc.sh git-auth`

### Synopsis

```
./dilxc.sh git-auth
```

### Description

Reports the status of SSH agent forwarding and GitHub CLI authentication for the target container. Follows the `health-check` diagnostic pattern.

### Prerequisites

- Container must exist (`require_container`)
- Container must be running (`require_running`)
- `ensure_auth_forwarding` called before checks (updates device state)

### Output Format

**All OK**:
```
=== Git & Forge Auth: <container-name> ===
  SSH agent:    ok (<N> identities available)
  GitHub CLI:   ok (authenticated as <username>)
```

**Partial failure**:
```
=== Git & Forge Auth: <container-name> ===
  SSH agent:    NOT CONFIGURED
    → Start your SSH agent: eval "$(ssh-agent -s)" && ssh-add
  GitHub CLI:   ok (authenticated as <username>)
```

**All failing**:
```
=== Git & Forge Auth: <container-name> ===
  SSH agent:    NOT CONFIGURED
    → Start your SSH agent: eval "$(ssh-agent -s)" && ssh-add
  GitHub CLI:   NOT CONFIGURED
    → Authenticate on the host: gh auth login
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | All configured auth mechanisms are working |
| 1 | One or more auth mechanisms are not working |

### Check Details

**SSH Agent Check**:
1. Verify `ssh-agent` proxy device exists on container
2. Run `ssh-add -l` inside container (as ubuntu user)
3. Success: report number of identities
4. Failure modes:
   - Device missing → "NOT CONFIGURED" + guidance to start SSH agent and run `dilxc.sh update`
   - Agent not running on host → "NOT AVAILABLE" + guidance to start agent
   - No identities loaded → "NO KEYS" + guidance to run `ssh-add`

**GitHub CLI Check**:
1. Verify `gh-config` disk device exists on container
2. Run `gh auth status` inside container (as ubuntu user)
3. Success: extract and report username
4. Failure modes:
   - Device missing → "NOT CONFIGURED" + guidance to run `gh auth login` on host
   - Not authenticated → "NOT AUTHENTICATED" + guidance to run `gh auth login` on host

---

## Helper Function: `ensure_auth_forwarding`

### Synopsis

```bash
ensure_auth_forwarding
```

### Description

Called internally before interactive `dilxc.sh` commands. Performs two operations:

1. **Update SSH agent proxy**: If the `ssh-agent` device exists and `$SSH_AUTH_SOCK` is set, updates the device's `connect` path to match the current host socket.
2. **Add gh config mount**: If `~/.config/gh` exists on the host but the `gh-config` device doesn't exist on the container, adds the disk device.

### Behavior

```
IF ssh-agent device exists on container:
  IF $SSH_AUTH_SOCK is set and non-empty:
    lxc config device set $CONTAINER_NAME ssh-agent connect=unix:$SSH_AUTH_SOCK

IF gh-config device does NOT exist on container:
  IF ~/.config/gh directory exists on host:
    lxc config device add $CONTAINER_NAME gh-config disk \
      source=$HOME/.config/gh \
      path=/home/ubuntu/.config/gh \
      readonly=true
```

### Error Handling

- Failures are silent (suppress stderr). This is a best-effort pre-command hook.
- If `lxc config device set` fails, the command proceeds with stale config. The `git-auth` diagnostic catches the issue.

### Callers

`cmd_shell`, `cmd_claude`, `cmd_claude_run`, `cmd_claude_resume`, `cmd_exec`, `cmd_login`, `cmd_git_auth`

---

## Modified Commands

### `setup-host.sh` — New Device Creation

After existing device creation (project mount, optional deploy mount):

```bash
# SSH agent forwarding
lxc config device add "$CONTAINER_NAME" ssh-agent proxy \
  connect="unix:${SSH_AUTH_SOCK:-/dev/null}" \
  listen=unix:/tmp/ssh-agent.sock \
  bind=container \
  uid=1000 \
  gid=1000 \
  mode=0600

# gh config sharing (only if host config exists)
if [[ -d "$HOME/.config/gh" ]]; then
  lxc config device add "$CONTAINER_NAME" gh-config disk \
    source="$HOME/.config/gh" \
    path=/home/ubuntu/.config/gh \
    readonly=true
fi
```

### `dilxc.sh update` — Add Missing Devices

After `git pull`, check for and add missing auth devices:

```bash
# Add SSH agent proxy device if missing
if ! lxc config device show "$CONTAINER_NAME" 2>/dev/null | grep -q "^ssh-agent:"; then
  lxc config device add "$CONTAINER_NAME" ssh-agent proxy \
    connect="unix:${SSH_AUTH_SOCK:-/dev/null}" \
    listen=unix:/tmp/ssh-agent.sock \
    bind=container \
    uid=1000 gid=1000 mode=0600
  echo "  Added SSH agent forwarding device"
fi

# Add gh config device if missing and host config exists
if ! lxc config device show "$CONTAINER_NAME" 2>/dev/null | grep -q "^gh-config:"; then
  if [[ -d "$HOME/.config/gh" ]]; then
    lxc config device add "$CONTAINER_NAME" gh-config disk \
      source="$HOME/.config/gh" \
      path=/home/ubuntu/.config/gh \
      readonly=true
    echo "  Added GitHub CLI config mount"
  fi
fi
```

### `provision-container.sh` — gh CLI Installation

Added after existing dev tools installation:

```bash
echo "--- Installing GitHub CLI ---"
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
chmod a+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | \
  tee /etc/apt/sources.list.d/github-cli.list > /dev/null
apt-get update
apt-get install -y gh
```

### `provision-container.sh` — Shell Environment

**Bash** (added to `.bashrc` block):
```bash
export SSH_AUTH_SOCK=/tmp/ssh-agent.sock
```

**Fish** (added to `config.fish` block, if `--fish`):
```fish
set -gx SSH_AUTH_SOCK /tmp/ssh-agent.sock
```
