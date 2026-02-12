# Quickstart: Custom Provision Scripts

**Feature**: 005-custom-provision-scripts | **Date**: 2026-02-12

## What This Feature Does

Adds an optional `custom-provision.sh` file that runs inside the LXD container after standard provisioning. Users can add any tools or configurations they want in every new container.

## Files to Modify

1. **`provision-container.sh`** — Add custom script invocation block at end (before final verification)
2. **`setup-host.sh`** — Add custom script push logic in Step 6 (before executing provisioning)
3. **`dilxc.sh`** — Add `cmd_customize()` function and dispatch entry
4. **`CLAUDE.md`** — Add "Custom Provision Scripts" section with agent instructions
5. **`.gitignore`** — Add `custom-provision.sh`

## Implementation Order

1. `.gitignore` — Add the exclusion first (prevents accidental commits during development)
2. `provision-container.sh` — Add the invocation block (the core mechanism)
3. `setup-host.sh` — Add the push logic (connects the mechanism to initial setup)
4. `dilxc.sh` — Add the `customize` subcommand (user-facing entry point)
5. `CLAUDE.md` — Add agent instructions and update re-provisioning docs (documentation)

## Key Patterns to Follow

### Existing pattern: `lxc file push` with `rm -f` workaround

```bash
# Always delete before pushing (known LXD overwrite issue)
lxc exec "$CONTAINER_NAME" -- rm -f /tmp/custom-provision.sh
lxc file push "$CUSTOM_PROVISION" "$CONTAINER_NAME/tmp/custom-provision.sh"
```

### Existing pattern: `set -euo pipefail` error propagation

`provision-container.sh` uses strict error handling. The custom script invocation needs no try/catch — a non-zero exit automatically halts provisioning and propagates up to `setup-host.sh`.

### Existing pattern: `dilxc.sh` subcommand structure

```bash
# Function definition
cmd_customize() {
  # ... implementation
}

# Dispatch entry (in the case block at bottom)
customize)  cmd_customize ;;
```

### Existing pattern: `$(dirname "$0")` for script-relative paths

```bash
CUSTOM_PROVISION="$(dirname "$0")/custom-provision.sh"
```

## Acceptance Test Checklist

- [ ] With `custom-provision.sh` present: `setup-host.sh` pushes it, tools are installed
- [ ] Without `custom-provision.sh`: `setup-host.sh` completes normally, no errors
- [ ] With failing custom script: provisioning halts, no snapshot taken
- [ ] `dilxc.sh customize`: creates template if absent, opens in editor
- [ ] `dilxc.sh customize` again: opens existing file without overwriting
- [ ] Re-provisioning with custom script: updated tools are applied
- [ ] `custom-provision.sh` is in `.gitignore`
