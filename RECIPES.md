# Recipes

Copy-paste snippets for `custom-provision.sh`. Each recipe is self-contained, idempotent, and follows the [custom provisioning conventions](CLAUDE.md#writing-a-custom-provision-script).

## How Tool Installation Works

Tools get into your container through three tiers:

1. **Default provisioning** (`provision-container.sh`) — Docker, Node.js, Claude Code, git, GitHub CLI, and common dev tools. Always installed.
2. **Custom provisioning** (`custom-provision.sh`) — Your personal additions, run automatically on every new container. See [Customizing Your Container](#customizing-your-container) below.
3. **Manual install** — One-off tools installed via `dilxc shell` or `dilxc root`. Lost on snapshot restore.

For anything you want in every container, put it in `custom-provision.sh`.

## Customizing Your Container

```bash
dilxc customize    # creates the file and opens your editor
```

Or create `custom-provision.sh` manually in the repo root. It runs as root inside the container after standard provisioning. The file is gitignored — it won't affect other users.

## uv + Spec Kit

Installs [uv](https://github.com/astral-sh/uv) (Python package manager) and [Spec Kit](https://github.com/github/spec-kit) (`specify-cli`) for spec-driven development workflows.

```bash
echo "--- Installing uv ---"
if ! su - ubuntu -c 'command -v uv' &>/dev/null; then
  curl -LsSf https://astral.sh/uv/install.sh | su - ubuntu -c "bash"
fi
echo "  uv installed $(su - ubuntu -c 'uv --version' 2>/dev/null)"

echo "--- Installing Spec Kit ---"
su - ubuntu -c 'uv tool install specify-cli --force --from "git+https://github.com/github/spec-kit.git"'
echo "  Spec Kit installed ✓"
```

## PostgreSQL Client

Installs `psql` for connecting to PostgreSQL databases.

```bash
echo "--- Installing PostgreSQL client ---"
apt-get install -y postgresql-client
echo "  PostgreSQL client installed $(psql --version)"
```
