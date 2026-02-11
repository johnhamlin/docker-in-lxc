#!/bin/bash
# =============================================================================
# Claude Code LXD Sandbox - Host Setup Script
# Run this on your Ubuntu homelab server
# =============================================================================

set -euo pipefail

usage() {
  cat << EOF
Usage: ./setup-host.sh [options]

Creates an LXD container with Claude Code, Docker, and dev tools.

Options:
  -n, --name <name>      Container name (default: \$CLAUDE_SANDBOX or claude-sandbox)
  -p, --project <path>   Host project directory to mount read-only
  -d, --deploy <path>    Host directory to mount read-write for deploy output
  -f, --fish             Install fish shell and set as default (default: bash only)
  -h, --help             Show this help message

Examples:
  ./setup-host.sh -n claude-sandbox -p /home/john/dev/myproject/
  ./setup-host.sh -p /home/john/dev/myproject/ --fish
  ./setup-host.sh -p /home/john/dev/myproject/ -d /srv/www
  ANTHROPIC_API_KEY=sk-... ./setup-host.sh -p /path/to/project
EOF
}

# --- Configuration -----------------------------------------------------------
CONTAINER_NAME="${CLAUDE_SANDBOX:-claude-sandbox}"
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

echo "============================================="
echo "  Claude Code LXD Sandbox Setup"
echo "  Container: $CONTAINER_NAME"
echo "============================================="
echo ""

# --- Step 1: Install LXD if needed ------------------------------------------
if ! command -v lxc &> /dev/null; then
  echo "[1/6] Installing LXD..."
  sudo snap install lxd
  sudo lxd init --auto
  # Add current user to lxd group
  sudo usermod -aG lxd "$USER"
  echo "  Warning: You were added to the 'lxd' group."
  echo "    Log out and back in, then re-run this script."
  exit 1
else
  echo "[1/6] LXD already installed"
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
  echo "[2/6] Container '$CONTAINER_NAME' already exists. Skipping creation."
else
  echo "[2/6] Creating Ubuntu $UBUNTU_VERSION container..."
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
if [[ -n "$PROJECT_PATH" ]]; then
  echo "[3/6] Mounting project directory (read-only)..."
  # Remove existing device if present
  lxc config device remove "$CONTAINER_NAME" project 2>/dev/null || true
  lxc config device add "$CONTAINER_NAME" project disk \
    source="$PROJECT_PATH" \
    path=/home/ubuntu/project-src \
    readonly=true
  echo "  Mounted $PROJECT_PATH -> /home/ubuntu/project-src (read-only)"
else
  echo "[3/6] No project path specified, skipping mount."
  echo "  Use -p /path/to/project to mount your source code."
fi

# --- Step 4: Mount deploy directory (read-write, optional) -------------------
if [[ -n "$DEPLOY_PATH" ]]; then
  echo "[4/6] Mounting deploy directory..."
  lxc config device remove "$CONTAINER_NAME" deploy 2>/dev/null || true
  lxc config device add "$CONTAINER_NAME" deploy disk \
    source="$DEPLOY_PATH" \
    path=/mnt/deploy
  echo "  Mounted $DEPLOY_PATH -> /mnt/deploy (read-write)"
  echo "  Warning: Claude Code CAN write to this path on the host!"
else
  echo "[4/6] No deploy path specified, skipping."
  echo "  Use -d /srv/www to mount a deploy target."
fi

# --- Step 5: Run container provisioning script -------------------------------
echo "[5/6] Provisioning container (this takes a few minutes)..."
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

# --- Step 6: Authentication --------------------------------------------------
echo ""
echo "[6/6] Authentication Setup"

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
  echo "    ./sandbox.sh login"
  echo ""
  echo "  This opens an interactive Claude session where you can complete"
  echo "  the OAuth flow in your browser. You only need to do this once."
  echo ""
  echo "  Alternatively, set ANTHROPIC_API_KEY before running this script"
  echo "  to inject an API key instead."
fi

# --- Take a clean snapshot ---------------------------------------------------
echo ""
echo "Taking clean baseline snapshot..."
lxc snapshot "$CONTAINER_NAME" clean-baseline
echo "  Snapshot 'clean-baseline' created"

# --- Done! -------------------------------------------------------------------
echo ""
echo "============================================="
echo "  Setup Complete!"
echo "============================================="
echo ""
echo "  Quick reference:"
echo ""
echo "  ./sandbox.sh shell                # shell into the container"
echo "  ./sandbox.sh sync                 # copy project source to working dir"
echo "  ./sandbox.sh claude               # start Claude Code (autonomous)"
echo "  ./sandbox.sh claude-run \"prompt\"   # one-shot Claude Code"
echo "  ./sandbox.sh claude-resume        # resume last session"
echo "  ./sandbox.sh snapshot <name>      # btrfs snapshot"
echo "  ./sandbox.sh restore <name>       # instant rollback"
echo "  ./sandbox.sh pull <path> [dest]   # pull files to host"
echo "  ./sandbox.sh health-check         # verify everything works"
echo ""
