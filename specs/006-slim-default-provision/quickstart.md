# Quickstart: Slim Default Provision

**Branch**: `006-slim-default-provision` | **Date**: 2026-02-12

## Implementation Checklist

### Phase A: Script Changes

- [ ] Remove uv + Spec Kit install section from `provision-container.sh` (lines 56-60)
- [ ] Remove `postgresql-client` from dev tools apt-get in `provision-container.sh` (line 72)
- [ ] Update `# Add uv / Spec Kit to PATH` comment to `# User-installed tools` in bash config block (line 101)
- [ ] Update `# Add uv / Spec Kit to PATH` comment to `# User-installed tools` in fish config block (line 145)
- [ ] Remove uv and Spec Kit lines from final verification output (lines 210-211)
- [ ] Update customize template comment in `dilxc.sh` (line 671) — remove uv, Spec Kit from installed tools list

### Phase B: New Files

- [ ] Create `RECIPES.md` with three-tier model explanation and recipes (uv + Spec Kit, PostgreSQL client)
- [ ] Create `custom-provision.sh` with uv + Spec Kit recipe for the maintainer

### Phase C: Documentation Updates

- [ ] Update `README.md` opening description (remove Spec Kit mention)
- [ ] Update `README.md` "What Gets Installed" section (remove uv/Spec Kit, fix fish as opt-in not default, add custom provisioning note)
- [ ] Replace `README.md` "Spec Kit Integration" section with "Customizing Your Container"
- [ ] Update `README.md` How It Works provision description (remove uv, Spec Kit)
- [ ] Update `CLAUDE.md` project overview (remove uv/Spec Kit pre-installed mention)
- [ ] Update `CLAUDE.md` provision-container.sh description (remove uv/Spec Kit)
- [ ] Update `CLAUDE.md` installed tools list (remove uv, Spec Kit, postgresql-client)
- [ ] Update `CLAUDE.md` available package managers (remove `/uv`)
- [ ] Update `.specify/memory/constitution.md` Principle I example list (remove uv)

## Verification

- [ ] `provision-container.sh` has no references to uv, Spec Kit, or postgresql-client
- [ ] `dilxc.sh` customize template has no references to uv or Spec Kit
- [ ] `README.md` has no references to uv or Spec Kit as default/pre-installed tools
- [ ] `CLAUDE.md` has no references to uv or Spec Kit as default/pre-installed tools
- [ ] `RECIPES.md` exists with working recipes
- [ ] `custom-provision.sh` exists and is gitignored
- [ ] `~/.local/bin` PATH entry preserved in both bash and fish configs
- [ ] Shell parity maintained (bash and fish config comments match)
