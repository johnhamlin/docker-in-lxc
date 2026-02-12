# Data Model: Custom Provision Scripts

**Feature**: 005-custom-provision-scripts | **Date**: 2026-02-12

## Entities

### Custom Provision File

A user-authored bash script containing additional provisioning commands.

| Property | Type | Description |
|----------|------|-------------|
| Location (host) | File path | `<repo-root>/custom-provision.sh` |
| Location (container) | File path | `/tmp/custom-provision.sh` |
| Format | Bash script | `#!/bin/bash` shebang, standard bash syntax |
| Permissions | `+x` (executable) | Set by `chmod +x` in both `cmd_customize` and `provision-container.sh` |
| Ownership | Root | Pushed by `lxc file push` (root-owned in container) |
| Lifecycle | Optional, persistent on host | Created by user or `customize` command; pushed per-provision; cleaned from `/tmp/` on container reboot |

**Validation rules**:
- Must be a valid bash script (syntax errors cause non-zero exit → provisioning halts)
- Must be idempotent (re-provisioning runs it again)
- Must use non-interactive flags (no stdin prompts)

### Starter Template

The default content created by `cmd_customize` when no `custom-provision.sh` exists.

| Property | Type | Description |
|----------|------|-------------|
| Contents | Bash script | Shebang + comment header (execution context, requirements, example) + empty body |
| Created by | `cmd_customize()` in `dilxc.sh` | Only created if file doesn't exist |
| Overwrite behavior | Never | Existing files are opened without modification |

## Flow: Initial Setup with Custom Script

```
User creates custom-provision.sh (via `dilxc.sh customize` or manually)
  │
  ▼
setup-host.sh runs
  │
  ├─ [Step 6] Push provision-container.sh to /tmp/
  ├─ [Step 6] Check: does custom-provision.sh exist in repo root?
  │   ├─ YES → rm -f /tmp/custom-provision.sh; push to /tmp/
  │   └─ NO  → skip silently
  │
  ├─ [Step 6] Execute provision-container.sh inside container
  │   │
  │   ├─ Standard provisioning (Docker, Node.js, Claude Code, etc.)
  │   ├─ User configuration (bashrc, fish, aliases)
  │   ├─ Check: does /tmp/custom-provision.sh exist?
  │   │   ├─ YES → chmod +x; execute; echo success
  │   │   │   └─ On failure → set -euo pipefail halts; error propagates
  │   │   └─ NO  → skip silently
  │   └─ Final verification output
  │
  ├─ [Step 7] Authentication
  └─ [Step 8] Baseline snapshot (only reached if everything succeeded)
```

## Flow: Re-provisioning with Custom Script

```
User updates custom-provision.sh
  │
  ▼
Manual re-provision commands (documented in CLAUDE.md):
  │
  ├─ rm -f /tmp/provision-container.sh /tmp/custom-provision.sh
  ├─ push provision-container.sh to /tmp/
  ├─ push custom-provision.sh to /tmp/ (if it exists)
  ├─ chmod +x /tmp/provision-container.sh
  └─ execute /tmp/provision-container.sh
      │
      └─ Same flow as initial setup (standard → custom → verification)
```

## Flow: `dilxc.sh customize`

```
User runs: dilxc.sh customize
  │
  ├─ Check: does $SCRIPT_DIR/custom-provision.sh exist?
  │   ├─ NO  → Create file with starter template; chmod +x; echo "Created"
  │   └─ YES → Skip creation
  │
  └─ Open file in ${EDITOR:-nano}
```
