# Project Description for Constitution

This project is a set of bash scripts for running Claude Code autonomously inside an LXD system container on an Ubuntu homelab server. The LXD container is the sandbox — there's no additional isolation layer inside it. Docker runs natively inside the container (via `security.nesting=true`), and btrfs snapshots provide instant rollback.

## Principles

### Shell scripts only

The entire project is three bash scripts. No frameworks, no compiled languages, no package managers for the project itself. Dependencies exist only inside the container (Node.js, Docker, uv, etc.) — the host-side tooling is plain bash.

### Three scripts, three execution contexts

Each script runs in exactly one place:

- `setup-host.sh` — runs on the host, creates and provisions the container
- `provision-container.sh` — runs inside the container, installs tools and configures the user environment
- `sandbox.sh` — runs on the host, wraps `lxc` commands for day-to-day use

When adding functionality, add it to the appropriate existing script. Do not create new scripts unless there's a genuinely new execution context.

### Readability wins over cleverness

When readable and concise conflict, choose readable. Spell things out. Use explicit variable names. Avoid chained pipelines that require mental unpacking. The scripts are meant to be understood by someone reading them for the first time.

### The container is the sandbox

LXD is the security boundary. Don't add sandboxing layers inside the container — no firejail, no AppArmor profiles, no restricted users. Claude Code runs with `--dangerously-skip-permissions` because the container itself is disposable. If something goes wrong, restore a snapshot.

### Don't touch the host

The host is a shared machine running other services — Docker stacks, other LXD containers, production workloads. Every `lxc` command is scoped to `$CLAUDE_SANDBOX`. Never operate on other containers, never modify host-level config, never assume the sandbox is the only thing running. Each container is independent: one project mount, its own snapshots, no cross-container state.

### LXD today, Incus eventually

The project currently targets LXD (`lxc` CLI). Incus (the community fork) is a planned future target. Don't hard-code LXD-specific assumptions where avoidable — the `lxc` and `incus` CLIs are nearly identical. Keep container management commands clean and isolable so migrating to Incus is a find-and-replace, not a rewrite.

### Idempotent provisioning

Re-running `provision-container.sh` on an existing container must be safe. Use `--yes` flags on key operations (like `gpg --dearmor --yes`), avoid appending duplicate config blocks, and don't fail on "already exists" conditions. The user's escape hatch is deleting the container and running `setup-host.sh` again, but re-provisioning should work when possible.

### Detect and report, don't auto-fix

When something is wrong (container not running, network down, Docker broken), tell the user what failed and what command to run. Don't silently retry, don't auto-start containers, don't guess at fixes. The `health-check` command is the model: check each thing, report pass/fail, let the user decide.

### Shell parity: bash always, fish opt-in

Bash configuration is always written. Fish is only configured when the `--fish` flag is passed. When both exist, they must stay in sync — same aliases/abbreviations, same helper functions, same PATH entries. If you change something in the bash config section, check whether a fish equivalent exists and update it too.

### Error handling

`setup-host.sh` and `provision-container.sh` use `set -euo pipefail`. If setup fails partway, the recovery path is deleting the container and starting over, not trying to resume. `sandbox.sh` does not use `set -e` because it needs to handle failures gracefully in individual commands.

### Rsync excludes stay synchronized

The rsync exclude list (`node_modules`, `.git`, `dist`, `build`) appears in three places: the bash `sync-project` function, the fish `sync-project` function, and the `sandbox.sh sync` command. These must always match.

### Keep arguments safe

Use `printf '%q'` for shell-escaping user-provided arguments before passing them through `lxc exec`. This matters for `claude-run` prompts and `docker` passthrough where arguments may contain spaces and special characters.
