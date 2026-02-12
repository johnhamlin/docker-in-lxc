#!/bin/bash
# =============================================================================
# Docker-in-LXC - Host Setup Script
# Run this on your Ubuntu homelab server
# =============================================================================

set -euo pipefail

usage() {
  cat << EOF
Usage: ./setup-host.sh [options]

Creates an LXD container with Claude Code, Docker, and dev tools.

Options:
  -n, --name <name>      Container name (default: \$DILXC_CONTAINER or docker-lxc)
  -p, --project <path>   Host project directory to mount read-only
  -d, --deploy <path>    Host directory to mount read-write for deploy output
  -f, --fish             Install fish shell and set as default (default: bash only)
  -h, --help             Show this help message

Examples:
  ./setup-host.sh -n docker-lxc -p /home/john/dev/myproject/
  ./setup-host.sh -p /home/john/dev/myproject/ --fish
  ./setup-host.sh -p /home/john/dev/myproject/ -d /srv/www
  ANTHROPIC_API_KEY=sk-... ./setup-host.sh -p /path/to/project
EOF
}

# --- Configuration -----------------------------------------------------------
CONTAINER_NAME="${DILXC_CONTAINER:-docker-lxc}"
UBUNTU_VERSION="24.04"
PROJECT_PATH=""
DEPLOY_PATH=""
INSTALL_FISH=false

while [[ $# -gt 0 ]]; do
  case $1 in
    -p|--project) PROJECT_PATH="$2"; shift 2 ;;
    -d|--deploy)  DEPLOY_PATH="$2"; shift 2 ;;
    -n|--name)    CONTAINER_NAME="$2"; shift 2 ;;
    -f|--fish)    INSTALL_FISH=true; shift ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "Unknown option: $1"; usage; exit 1 ;;
  esac
done

# --- Validate required arguments ----------------------------------------------
if [[ -z "$PROJECT_PATH" ]]; then
  echo "Error: project path is required."
  echo "  Usage: ./setup-host.sh -p /path/to/project"
  exit 1
fi

echo "============================================="
echo "  Docker-in-LXC Setup"
echo "  Container: $CONTAINER_NAME"
echo "============================================="
echo ""

# --- Step 1: Install LXD if needed ------------------------------------------
if ! command -v lxc &> /dev/null; then
  echo "[1/8] Installing LXD..."
  sudo snap install lxd
  sudo lxd init --auto
  # Add current user to lxd group
  sudo usermod -aG lxd "$USER"
  echo "  Warning: You were added to the 'lxd' group."
  echo "    Log out and back in, then re-run this script."
  exit 1
else
  echo "[1/8] LXD already installed"
fi

# Verify LXD/Incus is initialized (has storage + network)
if ! lxc storage list --format csv 2>/dev/null | grep -q .; then
  echo "Error: No storage pool configured."
  echo "  Run 'sudo lxd init' to set up LXD before using this script."
  exit 1
fi
if ! lxc network list --format csv 2>/dev/null | grep -q .; then
  echo "Error: No network configured."
  echo "  Run 'sudo lxd init' to set up LXD before using this script."
  exit 1
fi

# --- Step 2: Create the container --------------------------------------------
if lxc info "$CONTAINER_NAME" &> /dev/null 2>&1; then
  echo "[2/8] Container '$CONTAINER_NAME' already exists. Skipping creation."
else
  echo "[2/8] Creating Ubuntu $UBUNTU_VERSION container..."
  lxc launch "ubuntu:$UBUNTU_VERSION" "$CONTAINER_NAME" \
    -c security.nesting=true \
    -c security.syscalls.intercept.mknod=true \
    -c security.syscalls.intercept.setxattr=true

  # Wait for network
  echo "  Waiting for network..."
  network_ok=false
  for i in {1..30}; do
    if lxc exec "$CONTAINER_NAME" -- ping -c 1 -W 1 8.8.8.8 &> /dev/null; then
      network_ok=true
      break
    fi
    sleep 1
  done
  if $network_ok; then
    echo "  Container is up"
  else
    echo "  Container has no network after 30s."
    echo "    Check: sudo ufw status, lxdbr0 rules, Docker iptables."
    exit 1
  fi
fi

# --- Step 3: Mount project directory (read-only) ----------------------------
echo "[3/8] Mounting project directory (read-only)..."
# Remove existing device if present
lxc config device remove "$CONTAINER_NAME" project 2>/dev/null || true
lxc config device add "$CONTAINER_NAME" project disk \
  source="$PROJECT_PATH" \
  path=/home/ubuntu/project-src \
  readonly=true
echo "  Mounted $PROJECT_PATH -> /home/ubuntu/project-src (read-only)"

# --- Step 4: Mount deploy directory (read-write, optional) -------------------
if [[ -n "$DEPLOY_PATH" ]]; then
  echo "[4/8] Mounting deploy directory..."
  lxc config device remove "$CONTAINER_NAME" deploy 2>/dev/null || true
  lxc config device add "$CONTAINER_NAME" deploy disk \
    source="$DEPLOY_PATH" \
    path=/mnt/deploy
  echo "  Mounted $DEPLOY_PATH -> /mnt/deploy (read-write)"
  echo "  Warning: Claude Code CAN write to this path on the host!"
else
  echo "[4/8] No deploy path specified, skipping."
  echo "  Use -d /srv/www to mount a deploy target."
fi

# --- Step 5: Git & forge auth devices ----------------------------------------
echo "[5/8] Setting up git & forge auth forwarding..."

# SSH agent proxy: forwards host SSH agent socket into container
lxc config device remove "$CONTAINER_NAME" ssh-agent 2>/dev/null || true
lxc config device add "$CONTAINER_NAME" ssh-agent proxy \
  connect="unix:${SSH_AUTH_SOCK:-/dev/null}" \
  listen=unix:/tmp/ssh-agent.sock \
  bind=container \
  uid=1000 \
  gid=1000 \
  mode=0600
if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
  echo "  SSH agent forwarding: configured"
else
  echo "  SSH agent forwarding: placeholder (no agent running)"
  echo "    Start your agent and run ./dilxc.sh shell to activate"
fi

# gh config mount: share host GitHub CLI config read-only
lxc config device remove "$CONTAINER_NAME" gh-config 2>/dev/null || true
if [[ -d "$HOME/.config/gh" ]]; then
  lxc config device add "$CONTAINER_NAME" gh-config disk \
    source="$HOME/.config/gh" \
    path=/home/ubuntu/.config/gh \
    readonly=true \
    shift=true
  echo "  GitHub CLI config: mounted"
else
  echo "  GitHub CLI config: skipped (no ~/.config/gh on host)"
  echo "    Run 'gh auth login' on host, then ./dilxc.sh update"
fi

# --- Step 6: Run container provisioning script -------------------------------
echo "[6/8] Provisioning container (this takes a few minutes)..."
lxc exec "$CONTAINER_NAME" -- rm -f /tmp/provision-container.sh
lxc file push "$(dirname "$0")/provision-container.sh" \
  "$CONTAINER_NAME/tmp/provision-container.sh"
lxc exec "$CONTAINER_NAME" -- chmod +x /tmp/provision-container.sh
PROVISION_ARGS=()
$INSTALL_FISH && PROVISION_ARGS+=(--fish)
lxc exec "$CONTAINER_NAME" -- /tmp/provision-container.sh "${PROVISION_ARGS[@]+"${PROVISION_ARGS[@]}"}" || {
  echo "Error: provisioning failed. Delete the container and start fresh."
  exit 1
}

# --- Step 7: Authentication --------------------------------------------------
echo ""
echo "[7/8] Authentication Setup"

if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
  escaped=$(printf '%q' "$ANTHROPIC_API_KEY")
  lxc exec "$CONTAINER_NAME" -- bash -c \
    "printf 'export ANTHROPIC_API_KEY=%s\n' $escaped >> /home/ubuntu/.bashrc"
  if $INSTALL_FISH; then
    lxc exec "$CONTAINER_NAME" -- bash -c \
      "printf 'set -gx ANTHROPIC_API_KEY %s\n' $escaped >> /home/ubuntu/.config/fish/config.fish"
  fi
  echo "  API key injected into shell config"
else
  echo "  Claude Pro/Max subscribers: authenticate via browser login."
  echo "  After setup completes, run:"
  echo ""
  echo "    ./dilxc.sh login"
  echo ""
  echo "  This opens an interactive Claude session where you can complete"
  echo "  the OAuth flow in your browser. You only need to do this once."
  echo ""
  echo "  Alternatively, set ANTHROPIC_API_KEY before running this script"
  echo "  to inject an API key instead."
fi

# --- Step 8: Take a clean snapshot -------------------------------------------
echo ""
echo "[8/8] Taking clean baseline snapshot..."
lxc snapshot "$CONTAINER_NAME" clean-baseline
echo "  Snapshot 'clean-baseline' created"

# Create .dilxc in project directory for automatic container detection
echo "$CONTAINER_NAME" > "$PROJECT_PATH/.dilxc"
echo "  Created $PROJECT_PATH/.dilxc"

# --- Done! -------------------------------------------------------------------
echo ""
echo "============================================="
echo "  Setup Complete!"
echo "============================================="
echo ""
echo "  Quick reference:"
echo ""
echo "  ./dilxc.sh shell                # shell into the container"
echo "  ./dilxc.sh sync                 # copy project source to working dir"
echo "  ./dilxc.sh claude               # start Claude Code (autonomous)"
echo "  ./dilxc.sh claude-run \"prompt\"   # one-shot Claude Code"
echo "  ./dilxc.sh claude-resume        # resume last session"
echo "  ./dilxc.sh snapshot <name>      # btrfs snapshot"
echo "  ./dilxc.sh restore <name>       # instant rollback"
echo "  ./dilxc.sh pull <path> [dest]   # pull files to host"
echo "  ./dilxc.sh health-check         # verify everything works"
echo ""
