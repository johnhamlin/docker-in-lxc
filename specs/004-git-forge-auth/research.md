# Research: Git & Forge Authentication Forwarding

**Branch**: `004-git-forge-auth` | **Date**: 2026-02-12

## Decision 1: SSH Agent Socket — Container-Side Path

**Decision**: `/tmp/ssh-agent.sock`

**Rationale**: Needs to be a fixed, well-known path so shell config can set `SSH_AUTH_SOCK` statically. `/tmp` is always writable and requires no directory creation. The socket is created by the LXD proxy device, not the filesystem, so `/tmp` cleanup on reboot is irrelevant — LXD recreates the socket when the container starts.

**Alternatives considered**:
- `/home/ubuntu/.ssh/agent.sock` — requires ensuring `~/.ssh` exists; adds provisioning complexity for no benefit.
- `/run/user/1000/ssh-agent.sock` — `/run/user/1000` may not exist in the container without systemd user sessions enabled.

## Decision 2: LXD Proxy Device for SSH Agent

**Decision**: Use a `proxy` device with `bind=container` to forward the host's SSH agent socket into the container.

```bash
lxc config device add "$CONTAINER_NAME" ssh-agent proxy \
  connect="unix:$SSH_AUTH_SOCK" \
  listen=unix:/tmp/ssh-agent.sock \
  bind=container \
  uid=1000 \
  gid=1000 \
  mode=0600
```

**Rationale**:
- `bind=container` creates the socket on the container side; connections are proxied to the host socket.
- `uid=1000 gid=1000 mode=0600` restricts access to the `ubuntu` user (uid 1000).
- LXD proxy devices are hot-pluggable (no restart needed) and persist across restarts and snapshot restores (stored in LXD's Dqlite database, not the container filesystem).

**Key property**: The `connect` path can be updated at any time with `lxc config device set`, allowing `dilxc.sh` to track the host's changing `$SSH_AUTH_SOCK` path.

## Decision 3: gh Config Mount — Host Directory Handling

**Decision**: Do NOT create `~/.config/gh` on the host. Instead, add the disk device dynamically in `dilxc.sh`'s `ensure_auth_forwarding` helper only when the directory exists.

**Rationale**: Constitution Principle V ("Don't Touch the Host") prohibits creating host-side directories. FR-008 says "MUST NOT modify any host-side files." Instead:
1. `setup-host.sh` adds the disk device only if `~/.config/gh` exists at setup time.
2. `dilxc.sh`'s `ensure_auth_forwarding` checks on each interaction: if the directory exists but the device doesn't, it adds the device (hot-plug, no restart needed).
3. This satisfies the spec's requirement that "auth forwarding begins working on the next dilxc.sh interaction" after the user runs `gh auth login` on the host.

**Alternatives considered**:
- `mkdir -p ~/.config/gh` in setup-host.sh — violates Principle V.
- `required=false` on the disk device — device would be created but mount inactive; would need container restart when dir appears later. Poor UX.

## Decision 4: gh CLI Installation Method

**Decision**: Add GitHub CLI apt repository via GPG key, matching the existing Docker CE pattern in provision-container.sh.

```bash
curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
  -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
chmod a+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
echo "deb [arch=$(dpkg --print-architecture) signed-by=...] https://cli.github.com/packages stable main" | \
  tee /etc/apt/sources.list.d/github-cli.list > /dev/null
apt-get update
apt-get install -y gh
```

**Rationale**: The GitHub CLI GPG key at `https://cli.github.com/packages/githubcli-archive-keyring.gpg` is already in binary (dearmored) format, so `gpg --dearmor` is NOT needed (unlike Docker's key). Direct download with `curl -o` and overwrite is idempotent. Follows Principle VII (Idempotent Provisioning).

**Alternatives considered**:
- `snap install gh` — adds snap dependency; inconsistent with apt-based pattern.
- `npm install -g gh` — wrong package manager for a system tool.

## Decision 5: SSH_AUTH_SOCK Update Mechanism

**Decision**: A single helper function `ensure_auth_forwarding` in `dilxc.sh`, called before interactive commands, performs two operations:

1. **SSH agent**: If the `ssh-agent` proxy device exists and `$SSH_AUTH_SOCK` is set on the host, update the device's `connect` path: `lxc config device set $CONTAINER_NAME ssh-agent connect=unix:$SSH_AUTH_SOCK`
2. **gh config**: If `~/.config/gh` exists on the host but the `gh-config` disk device doesn't exist on the container, add it.

**Rationale**: Keeps the pre-command overhead minimal (one `lxc config device set` call, ~100ms). No restart needed — both operations are hot-plug compatible.

**Called before**: `shell`, `claude`, `claude-run`, `claude-resume`, `exec`, `login`, `git-auth`

## Decision 6: Device Naming Convention

**Decision**:
- `ssh-agent` — SSH agent socket proxy device
- `gh-config` — GitHub CLI configuration disk device

**Rationale**: Matches existing short-name convention (`project`, `deploy`). Clear and descriptive.

## Decision 7: Setup with Missing Prerequisites

**Decision**: `setup-host.sh` handles missing prerequisites gracefully:
- **SSH agent not running** (`$SSH_AUTH_SOCK` unset): Create proxy device with `connect=unix:/dev/null` as placeholder. Non-functional until `dilxc.sh` updates it on first use with a valid `$SSH_AUTH_SOCK`.
- **gh config not present** (`~/.config/gh` doesn't exist): Skip disk device creation. `dilxc.sh` will add it later when the directory appears.

**Rationale**: Follows spec FR-011 (setup completes without errors). No broken container state. Auth starts working on next `dilxc.sh` interaction after prerequisites are met.

## Decision 8: git-auth Diagnostic Output Format

**Decision**: Follow `health-check` pattern — aligned status lines with pass/fail indicators and actionable remediation messages.

```
=== Git & Forge Auth: docker-lxc ===
  SSH agent:    ok (2 identities available)
  GitHub CLI:   ok (authenticated as username)
```

Or on failure:
```
=== Git & Forge Auth: docker-lxc ===
  SSH agent:    NOT CONFIGURED
    → Start your SSH agent: eval "$(ssh-agent -s)" && ssh-add
  GitHub CLI:   NOT AUTHENTICATED
    → Authenticate on the host: gh auth login
```

**Rationale**: Follows Principle VIII (Detect and Report, Don't Auto-Fix). Matches existing `health-check` output style.
