# Research: Slim Default Provision

**Branch**: `006-slim-default-provision` | **Date**: 2026-02-12

## R1: Complete inventory of uv/Spec Kit/postgresql-client references

**Decision**: Six files require modification (beyond the spec itself).

**Findings**:

| File | Lines | Reference | Action |
|------|-------|-----------|--------|
| `provision-container.sh` | 56-60 | uv + Spec Kit install section | Remove entire section |
| `provision-container.sh` | 72 | `postgresql-client` in apt-get | Remove from package list |
| `provision-container.sh` | 101 | `# Add uv / Spec Kit to PATH` comment (bash) | Update comment |
| `provision-container.sh` | 145 | `# Add uv / Spec Kit to PATH` comment (fish) | Update comment |
| `provision-container.sh` | 210-211 | uv + Spec Kit in final verification output | Remove both lines |
| `CLAUDE.md` | 7 | "pre-installed with uv and Spec Kit" | Remove mention |
| `CLAUDE.md` | 22 | "uv, Spec Kit (`specify-cli`)" in provision description | Remove mention |
| `CLAUDE.md` | 44 | "uv, Spec Kit (`specify-cli`)" in installed tools list | Remove mention, remove postgresql-client |
| `CLAUDE.md` | 52 | "`pip`/`uv`" in available package managers | Remove `/uv` |
| `README.md` | 3 | "and Spec Kit for spec-driven development" | Remove mention |
| `README.md` | 20 | uv + Spec Kit in "What Gets Installed" | Remove line, add custom provisioning note |
| `README.md` | 179-194 | "Spec Kit Integration" section | Replace with custom provisioning / recipes section |
| `README.md` | 209 | "uv, Spec Kit" in How It Works description | Remove mention |
| `dilxc.sh` | 671 | "uv, Spec Kit" in customize template comment | Remove mention |
| `.specify/memory/constitution.md` | 43 | "uv" as example in Principle I | Update example list |

**Out of scope** (not project files):
- `.specify/scripts/`, `.specify/templates/`, `.claude/commands/` — these are Spec Kit tooling files
- `specs/001-*`, `specs/003-*`, `specs/005-*` — historical specs, not modified

## R2: PATH entry behavior without uv

**Decision**: Keep `~/.local/bin` on PATH in both bash and fish configs.

**Rationale**: `~/.local/bin` is a standard user bin directory used by pip, pipx, cargo, and many other tools. Removing it would break any custom-provisioned tool that installs there. The comment referencing uv/Spec Kit should be updated to something generic like "User-installed tools".

**Alternatives considered**:
- Remove PATH entry entirely → rejected, breaks custom tool installations
- Conditionally add PATH only if `~/.local/bin` exists → unnecessary complexity, the directory may be created later by custom provisioning

## R3: Constitution impact

**Decision**: Minor update to Principle I example list. Not a constitutional amendment — just updating an illustrative example.

**Rationale**: Principle I says "Dependencies exist only inside the container (Node.js, Docker, uv, etc.)". The principle itself is unchanged — dependencies still exist only inside the container. uv is just no longer a default example. Replace with a more generic list or remove uv from the example.

**Alternatives considered**:
- Full constitution amendment → overkill for changing an example in parentheses
- Leave as-is → misleading since uv is no longer installed by default

## R4: RECIPES.md structure

**Decision**: Include at minimum two recipes: (1) uv + Spec Kit, (2) PostgreSQL client. Start with a brief explanation of the three-tier tool installation model, then list recipes as copy-paste-ready code blocks.

**Rationale**: These are the two tools being removed from defaults. Additional recipes can be added over time. Each recipe must be self-contained (install its own dependencies) and follow the `custom-provision.sh` conventions documented in CLAUDE.md.

**Alternatives considered**:
- Single combined recipe for all removed tools → rejected, users should pick what they need
- Separate files per recipe → overkill, a single RECIPES.md is sufficient
