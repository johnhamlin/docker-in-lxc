# Research: CLI UX Improvements

**Feature**: 003-cli-ux | **Date**: 2026-02-12

This is a retroactive spec — all features are already implemented and merged. Research documents the decisions that were made.

## R-001: Symlink Resolution for SCRIPT_DIR

**Decision**: Use `readlink -f "$0"` wrapped in `cd "$(dirname ...)" && pwd` to resolve the real filesystem path of `dilxc.sh`, following symlinks.

**Rationale**: `readlink -f` is the standard GNU coreutils way to canonicalize a path, resolving all symlinks. It's always available on Ubuntu 24.04. The `cd && pwd` wrapper ensures an absolute directory path even in edge cases.

**Alternatives considered**:
- `realpath` — equivalent on Linux, but `readlink -f` is more universally available across GNU systems.
- `$BASH_SOURCE` with manual symlink resolution — overly complex for the target platform where `readlink -f` is guaranteed.
- No symlink support — would prevent the `~/.local/bin/dilxc` install pattern, forcing users to type the full repo path.

## R-002: Container Selection Cascade Design

**Decision**: Four-level priority cascade: `@name` prefix → `DILXC_CONTAINER` env var → `.dilxc` file (walk up from `$PWD`) → default `docker-lxc`.

**Rationale**: Each level serves a different use case:
- `@name` — ad-hoc one-off targeting ("run this command on that container")
- `DILXC_CONTAINER` — session-level override (export in shell profile)
- `.dilxc` file — project-level binding (committed to repo or local convention)
- Default — zero-config for single-container users

The cascade runs once at script startup before subcommand dispatch. This means cascade-independent commands like `init` and `update` still resolve a container name (which they ignore), but the overhead is negligible and the code stays simple.

**Alternatives considered**:
- Subcommand-level container selection (per-command `--container` flag) — would require argument parsing in every command function, violating Constitution III (readability).
- Only env var + default — insufficient for multi-project workflows where each project maps to a different container.
- Config file in `~/.config/dilxc/` — overengineered for the current scope; `.dilxc` per-project is simpler and more portable.

## R-003: .dilxc File Walk Algorithm

**Decision**: Walk up from `$PWD` directory by directory using a `while` loop with `dirname`, stopping at filesystem root (`/`). Read the first line of the first `.dilxc` file found.

**Rationale**: Mirrors the convention used by `.nvmrc`, `.ruby-version`, `.node-version`, and similar tools. Users working in subdirectories of a project automatically get the right container.

**Alternatives considered**:
- Only check `$PWD` (no walk) — breaks when working in subdirectories.
- Walk up and check root (`/`) — current implementation skips `/` since a `.dilxc` at filesystem root would be a misconfiguration.
- Trim whitespace from `.dilxc` content — not implemented; whitespace becomes part of the container name. Documented as an edge case.

## R-004: Init Subcommand Architecture

**Decision**: `cmd_init()` uses `exec "$SCRIPT_DIR/setup-host.sh" "$@"` to replace the current process entirely, passing all arguments through to `setup-host.sh`.

**Rationale**: `exec` is the cleanest delegation pattern — no subprocess, no exit code forwarding needed, no cleanup. `setup-host.sh` handles its own argument validation (including `--help`). Using `$SCRIPT_DIR` to locate the sibling script ensures it works regardless of symlinks or current directory.

**Alternatives considered**:
- Subprocess (`"$SCRIPT_DIR/setup-host.sh" "$@"`) — works but creates an unnecessary process layer and requires explicit exit code handling.
- Inlining setup logic into `dilxc.sh` — violates Constitution II (three scripts, three execution contexts).

## R-005: Update Subcommand Design

**Decision**: `cmd_update()` runs `git -C "$SCRIPT_DIR" pull` after verifying `$SCRIPT_DIR/.git` exists and displaying the current short commit hash.

**Rationale**: The tool is installed via `git clone`, so `git pull` is the natural update mechanism. Showing the current hash before pulling gives the user a reference point for what changed. The `-C` flag ensures git operates in the right directory regardless of where the user invoked `dilxc`.

**Alternatives considered**:
- Auto-update on every invocation — violates Constitution VIII (detect and report, don't auto-fix).
- Download-based update (curl a tarball) — overengineered; git clone is the only supported install method.
- Check for updates without pulling — useful but deferred; `update` should actually update.

## R-006: Containers Listing

**Decision**: `cmd_containers()` lists all LXD containers (not just dilxc-managed ones) using `lxc list -f csv -c ns`, marking the cascade-resolved active container with `(active)`.

**Rationale**: There's no metadata to distinguish dilxc-created containers from other LXD containers. Showing all containers provides full situational awareness. The `(active)` marker connects the listing to the cascade resolution.

**Alternatives considered**:
- Only show dilxc-managed containers — impossible without adding metadata (labels, config keys), which would be overengineering.
- JSON output — unnecessary for a human-readable listing. Users needing machine output can use `lxc list -f json` directly.

## R-007: .gitattributes for Distribution

**Decision**: Add `.gitattributes` at repo root with `export-ignore` for `specs/`, `.specify/`, `.claude/`, `constitution-input.md`, `spec-input.md`, and `HANDOFF.md`.

**Rationale**: `git archive` is the standard mechanism for creating distribution tarballs. Development artifacts (specs, AI configuration, design inputs) should not ship to end users. The `.gitattributes` mechanism is built into git and requires no external tooling.

**Alternatives considered**:
- `.npmignore` / `.dockerignore` — not applicable; this is a bash-only project, not an npm package or Docker image.
- Manual exclusion at archive time — error-prone; `.gitattributes` makes it automatic and declarative.
