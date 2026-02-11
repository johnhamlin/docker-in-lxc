#!/bin/bash
# =============================================================================
# Docker-in-LXC - Container Provisioning
# This runs INSIDE the LXD container (called by setup-host.sh)
# =============================================================================

set -euo pipefail

INSTALL_FISH=false
[[ "${1:-}" == "--fish" ]] && INSTALL_FISH=true

export DEBIAN_FRONTEND=noninteractive

echo "--- Updating system packages ---"
apt-get update
apt-get upgrade -y

# --- Docker ------------------------------------------------------------------
echo "--- Installing Docker ---"
apt-get install -y ca-certificates curl gnupg

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | \
  gpg --dearmor --yes -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] \
  https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io \
  docker-buildx-plugin docker-compose-plugin

# Add ubuntu user to docker group
usermod -aG docker ubuntu

# Verify Docker works
systemctl enable docker
systemctl start docker
echo "  Docker $(docker --version) ✓"

# --- Node.js (via NodeSource) -----------------------------------------------
echo "--- Installing Node.js 22 LTS ---"
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs
echo "  Node $(node --version) ✓"
echo "  npm $(npm --version) ✓"

# --- Claude Code -------------------------------------------------------------
echo "--- Installing Claude Code ---"
npm install -g @anthropic-ai/claude-code
echo "  Claude Code installed ✓"

# --- uv and Spec Kit ---------------------------------------------------------
echo "--- Installing uv and Spec Kit ---"
curl -LsSf https://astral.sh/uv/install.sh | su - ubuntu -c "bash"
su - ubuntu -c '/home/ubuntu/.local/bin/uv tool install specify-cli --from "git+https://github.com/github/spec-kit.git"'
echo "  uv + Spec Kit installed ✓"

# --- Git and common dev tools ------------------------------------------------
echo "--- Installing dev tools ---"
apt-get install -y \
  git \
  build-essential \
  jq \
  ripgrep \
  fd-find \
  htop \
  tmux \
  postgresql-client

echo "  Dev tools installed ✓"

# --- Configure ubuntu user ---------------------------------------------------
echo "--- Configuring ubuntu user ---"

# Set up git defaults (user can override)
su - ubuntu -c 'git config --global init.defaultBranch main'
su - ubuntu -c 'git config --global user.name "Claude Code (docker-lxc)"'
su - ubuntu -c 'git config --global user.email "docker-lxc@localhost"'

# Create a working directory
su - ubuntu -c 'mkdir -p /home/ubuntu/project'

# Add helpful aliases to .bashrc (Claude Code uses bash internally)
cat >> /home/ubuntu/.bashrc << 'ALIASES'

# Add uv / Spec Kit to PATH
export PATH="$HOME/.local/bin:$PATH"

# Claude Code sandbox aliases
alias cc='claude --dangerously-skip-permissions'
alias cc-resume='claude --dangerously-skip-permissions --resume'
alias cc-prompt='claude --dangerously-skip-permissions -p'

# Quick project sync from read-only mount
sync-project() {
  if [ -d /home/ubuntu/project-src ]; then
    rsync -av --delete \
      --exclude=node_modules \
      --exclude=.git \
      --exclude=dist \
      --exclude=build \
      /home/ubuntu/project-src/ /home/ubuntu/project/
    echo "Project synced from source mount ✓"
  else
    echo "No project source mounted at /home/ubuntu/project-src"
  fi
}

# Deploy helper
deploy() {
  if [ -d /mnt/deploy ]; then
    local src="${1:-.}"
    rsync -av --delete "$src" /mnt/deploy/
    echo "Deployed to /mnt/deploy ✓"
  else
    echo "No deploy mount available. Use 'lxc file pull' from the host instead."
  fi
}
ALIASES

# Set up fish shell (opt-in)
if $INSTALL_FISH; then
  apt-get install -y fish

  su - ubuntu -c 'mkdir -p /home/ubuntu/.config/fish'
  cat > /home/ubuntu/.config/fish/config.fish << 'FISHCONFIG'
# Add uv / Spec Kit to PATH
fish_add_path ~/.local/bin

# Claude Code sandbox aliases
abbr -a cc 'claude --dangerously-skip-permissions'
abbr -a cc-resume 'claude --dangerously-skip-permissions --resume'
abbr -a cc-prompt 'claude --dangerously-skip-permissions -p'

# Quick project sync from read-only mount
function sync-project
  if test -d /home/ubuntu/project-src
    rsync -av --delete \
      --exclude=node_modules \
      --exclude=.git \
      --exclude=dist \
      --exclude=build \
      /home/ubuntu/project-src/ /home/ubuntu/project/
    echo "Project synced from source mount ✓"
  else
    echo "No project source mounted at /home/ubuntu/project-src"
  end
end

# Deploy helper
function deploy
  if test -d /mnt/deploy
    set src $argv[1]
    test -z "$src"; and set src "."
    rsync -av --delete "$src" /mnt/deploy/
    echo "Deployed to /mnt/deploy ✓"
  else
    echo "No deploy mount available. Use 'lxc file pull' from the host instead."
  end
end
FISHCONFIG
  chown ubuntu:ubuntu /home/ubuntu/.config/fish/config.fish

  # Set fish as default shell for ubuntu user
  chsh -s /usr/bin/fish ubuntu
  echo "  Fish shell installed and set as default ✓"
fi

echo "  User configured ✓"

# --- Final verification ------------------------------------------------------
echo ""
echo "=== Container Provisioning Complete ==="
echo ""
echo "  Docker:      $(docker --version)"
echo "  Docker Compose: $(docker compose version)"
echo "  Node.js:     $(node --version)"
echo "  npm:         $(npm --version)"
echo "  Git:         $(git --version)"
echo "  Claude Code: $(claude --version 2>/dev/null || echo 'installed')"
echo "  uv:          $(su - ubuntu -c '/home/ubuntu/.local/bin/uv --version' 2>/dev/null || echo 'installed')"
echo "  Spec Kit:    $(su - ubuntu -c '/home/ubuntu/.local/bin/specify --version' 2>/dev/null || echo 'installed')"
echo ""
