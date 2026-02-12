# Data Model: CLI UX Improvements

**Feature**: 003-cli-ux | **Date**: 2026-02-12

This feature has no persistent data model — it's a bash CLI with no database, no state files, and no serialization beyond reading `.dilxc` files. This document captures the key entities and their relationships as they exist at runtime.

## Entities

### Container Selection Cascade

The priority-ordered mechanism for resolving which LXD container a command targets.

| Source | Priority | Scope | Persistence |
|--------|----------|-------|-------------|
| `@name` prefix | 1 (highest) | Single invocation | None (argument) |
| `DILXC_CONTAINER` env var | 2 | Shell session | Shell environment |
| `.dilxc` file | 3 | Directory tree | Filesystem |
| Default `docker-lxc` | 4 (lowest) | Global fallback | Hardcoded |

**Resolution**: First match wins. Cascade runs once at script startup (lines 12-29 of `dilxc.sh`), before subcommand dispatch.

**Output**: `CONTAINER_NAME` shell variable, used by all `cmd_*` functions.

### SCRIPT_DIR

The resolved real filesystem directory containing `dilxc.sh`.

| Field | Value |
|-------|-------|
| Computed by | `readlink -f "$0"` → `dirname` → `cd && pwd` |
| Used by | `cmd_init()` (locates `setup-host.sh`), `cmd_update()` (locates `.git`) |
| Follows symlinks | Yes — `readlink -f` resolves the entire chain |

### .dilxc File

A single-line convention file placed in project directories.

| Field | Description |
|-------|-------------|
| Location | Any directory in the path from `$PWD` to `/` |
| Format | Plain text, first line = container name |
| Discovery | Walk up from `$PWD`, stop at first match |
| Edge cases | Empty file → empty name → falls through to default. Whitespace is not trimmed. |

### .gitattributes Exclusions

Declarative list of paths excluded from `git archive` output.

| Path | Reason |
|------|--------|
| `specs/` | Development specifications |
| `.specify/` | Spec Kit configuration |
| `.claude/` | Claude Code configuration |
| `constitution-input.md` | Constitution source input |
| `spec-input.md` | Spec source input |
| `HANDOFF.md` | Development handoff notes |

## Relationships

```text
User invocation
  → @name prefix? ──yes──→ CONTAINER_NAME
  → DILXC_CONTAINER? ──yes──→ CONTAINER_NAME
  → .dilxc file walk? ──yes──→ CONTAINER_NAME
  → default ──────────────→ CONTAINER_NAME = "docker-lxc"

SCRIPT_DIR (from readlink -f)
  → cmd_init() → exec $SCRIPT_DIR/setup-host.sh
  → cmd_update() → git -C $SCRIPT_DIR pull
```

## State Transitions

No stateful entities. The container selection cascade is pure — same inputs always produce the same output.

## Contracts

Not applicable. This is a bash CLI with no API endpoints, no RPC interfaces, and no serialization formats. The "contract" is the `dilxc.sh` CLI interface itself, documented in the `usage()` function and the spec's acceptance scenarios.
