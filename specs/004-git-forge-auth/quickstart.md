# Quickstart: Git & Forge Authentication Forwarding

**Branch**: `004-git-forge-auth` | **Date**: 2026-02-12

## Prerequisites (Host)

1. SSH agent running with at least one key loaded:
   ```bash
   eval "$(ssh-agent -s)"
   ssh-add ~/.ssh/id_ed25519   # or your key
   ssh-add -l                  # verify: should list identities
   ```

2. GitHub CLI authenticated:
   ```bash
   gh auth login               # follow prompts
   gh auth status              # verify: should show authenticated
   ```

## Setup (New Container)

```bash
./setup-host.sh -n docker-lxc -p /path/to/project
```

Auth devices are created automatically during setup.

## Setup (Existing Container)

```bash
./dilxc.sh update
```

Adds missing auth devices to the container without recreating it.

## Verify

```bash
./dilxc.sh git-auth
```

Expected output (all working):
```
=== Git & Forge Auth: docker-lxc ===
  SSH agent:    ok (1 identity available)
  GitHub CLI:   ok (authenticated as youruser)
```

## Test SSH (Inside Container)

```bash
./dilxc.sh shell
# Inside container:
ssh -T git@github.com
# Expected: "Hi youruser! You've successfully authenticated..."

git clone git@github.com:youruser/yourrepo.git
cd yourrepo
echo test >> README.md
git add . && git commit -m "test from container"
git push
```

## Test GitHub CLI (Inside Container)

```bash
./dilxc.sh shell
# Inside container:
gh auth status
# Expected: "Logged in to github.com account youruser"

gh repo view youruser/yourrepo
gh pr list
```

## Troubleshooting

If `git-auth` reports issues, follow the remediation instructions it provides. Common fixes:

| Problem | Fix (run on host) |
|---------|-------------------|
| SSH agent not running | `eval "$(ssh-agent -s)" && ssh-add` |
| gh not authenticated | `gh auth login` |
| Devices missing | `./dilxc.sh update` |
