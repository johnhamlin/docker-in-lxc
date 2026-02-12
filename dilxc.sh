#!/bin/bash
# =============================================================================
# Docker-in-LXC - Management Helper
# Common operations for your container
# =============================================================================

# --- Container name resolution (first match wins) ---------------------------
# 1. @name prefix:    ./dilxc.sh @project-b shell
# 2. DILXC_CONTAINER: env var override
# 3. .dilxc file:     walk up from $PWD looking for .dilxc
# 4. Default:         docker-lxc
if [[ "${1:-}" == @* ]]; then
  CONTAINER_NAME="${1#@}"
  shift
elif [[ -n "${DILXC_CONTAINER:-}" ]]; then
  CONTAINER_NAME="$DILXC_CONTAINER"
else
  _dir="$PWD"
  CONTAINER_NAME=""
  while [[ "$_dir" != "/" ]]; do
    if [[ -f "$_dir/.dilxc" ]]; then
      CONTAINER_NAME=$(head -1 "$_dir/.dilxc")
      break
    fi
    _dir=$(dirname "$_dir")
  done
  unset _dir
  CONTAINER_NAME="${CONTAINER_NAME:-docker-lxc}"
fi

SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

usage() {
  cat << EOF
Usage: dilxc <command> [options]

Commands:
  init [options]         Create a new sandbox (runs setup-host.sh)
  update                 Update Docker-in-LXC to the latest version

  shell                  Open a shell in the container as ubuntu user
  root                   Open a root shell in the container
  start                  Start the container
  stop                   Stop the container
  restart                Restart the container
  status                 Show container status and resource usage

  login                  Authenticate Claude Code via browser OAuth (one-time)
  claude                 Run Claude Code interactively (autonomous mode)
  claude-run "prompt"    Run Claude Code with a one-shot prompt
  claude-resume          Resume the most recent Claude Code session

  sync                   Sync project from read-only mount to working dir
  exec <command>         Run a command in the container's project dir
  pull <path> [dest]     Pull file/dir from container to host
  push <path> [dest]     Push file/dir from host to container

  snapshot [name]        Create a named snapshot (default: timestamp)
  restore <name>         Restore to a snapshot (auto-restarts container)
  snapshots              List all snapshots

  logs                   Show Docker container logs inside sandbox
  docker <args>          Run docker commands inside the sandbox
  proxy <action>         Manage port proxies (add, list, rm)

  containers             List available containers and their status
  health-check           Verify container, network, Docker, and Claude Code
  git-auth               Check SSH agent and GitHub CLI auth status
  destroy                Delete the container entirely (asks for confirmation)

Container Selection (first match wins):
  @<name> prefix         dilxc @myproject shell
  DILXC_CONTAINER        Environment variable override
  .dilxc file            Auto-detected from current/ancestor directory
  (default)              docker-lxc

Examples:
  dilxc init -p /path/to/project                    # create a sandbox
  dilxc init -p /path/to/project -n mybox --fish    # with options
  dilxc login                                       # first-time auth
  dilxc shell
  dilxc claude
  dilxc claude-run "fix the failing tests in src/api/"
  dilxc claude-resume                               # pick up where you left off
  dilxc exec npm test                               # run a command in project dir
  dilxc snapshot before-big-refactor
  dilxc restore before-big-refactor
  dilxc pull /home/ubuntu/project/dist/ ./dist/
  dilxc docker compose logs -f
  dilxc health-check
  dilxc update                                      # pull latest version
EOF
}

# --- Helpers -----------------------------------------------------------------

require_container() {
  if ! lxc info "$CONTAINER_NAME" &>/dev/null; then
    echo "Error: container '$CONTAINER_NAME' not found"
    echo "  Create it with: ./setup-host.sh -n $CONTAINER_NAME -p /path/to/project"
    exit 1
  fi
}

require_running() {
  require_container
  local state
  state=$(lxc info "$CONTAINER_NAME" | grep -oP 'Status: \K\w+')
  if [[ "$state" != "RUNNING" ]]; then
    echo "Error: container '$CONTAINER_NAME' is $state (not running)"
    echo "  Start it with: ./dilxc.sh start"
    exit 1
  fi
}

validate_port() {
  local value="$1"
  local label="$2"
  if [[ -z "$value" || ! "$value" =~ ^[0-9]+$ || "$value" -lt 1 || "$value" -gt 65535 ]]; then
    echo "Error: invalid $label '$value' — must be a number between 1 and 65535"
    exit 1
  fi
}

ensure_auth_forwarding() {
  local devices
  devices=$(lxc config device show "$CONTAINER_NAME" 2>/dev/null) || return 0
  # Update SSH agent proxy device connect path to current host socket
  if echo "$devices" | grep -q "^ssh-agent:"; then
    if [[ -n "${SSH_AUTH_SOCK:-}" ]]; then
      lxc config device set "$CONTAINER_NAME" ssh-agent connect="unix:$SSH_AUTH_SOCK" 2>/dev/null || true
    fi
  fi
  # Add gh config mount if host config exists but device is missing
  if ! echo "$devices" | grep -q "^gh-config:"; then
    if [[ -d "$HOME/.config/gh" ]]; then
      lxc config device add "$CONTAINER_NAME" gh-config disk \
        source="$HOME/.config/gh" \
        path=/home/ubuntu/.config/gh \
        readonly=true \
        shift=true 2>/dev/null || true
    fi
  fi
}

# --- Commands ----------------------------------------------------------------

cmd_shell() {
  require_running
  ensure_auth_forwarding
  lxc exec "$CONTAINER_NAME" -t -- su - ubuntu
}

cmd_root() {
  require_running
  lxc exec "$CONTAINER_NAME" -t -- bash
}

cmd_start() {
  require_container
  if lxc start "$CONTAINER_NAME"; then
    echo "Container started"
  else
    echo "Failed to start container"
    exit 1
  fi
}

cmd_stop() {
  require_running
  if lxc stop "$CONTAINER_NAME"; then
    echo "Container stopped"
  else
    echo "Failed to stop container"
    exit 1
  fi
}

cmd_restart() {
  require_running
  if lxc restart "$CONTAINER_NAME"; then
    echo "Container restarted"
  else
    echo "Failed to restart container"
    exit 1
  fi
}

cmd_status() {
  require_container
  echo "=== Container Status ==="
  lxc info "$CONTAINER_NAME" | grep -E "^(Name|Status|Type|Architecture|PID|Processes|Memory|Disk|Network)"
  echo ""
  echo "=== IP Address ==="
  lxc list "$CONTAINER_NAME" -f csv -c 4 | tr -d '"' | grep eth0
  echo ""
  echo "=== Snapshots ==="
  lxc info "$CONTAINER_NAME" | grep -A 100 "^Snapshots:" || echo "  None"
}

cmd_login() {
  require_running
  ensure_auth_forwarding
  echo "Opening Claude Code for browser authentication..."
  echo "Complete the OAuth flow in your browser, then exit with /exit."
  lxc exec "$CONTAINER_NAME" -t -- su - ubuntu -c "claude"
}

cmd_claude() {
  require_running
  ensure_auth_forwarding
  lxc exec "$CONTAINER_NAME" -t -- su - ubuntu -c \
    "cd /home/ubuntu/project && claude --dangerously-skip-permissions"
}

cmd_claude_resume() {
  require_running
  ensure_auth_forwarding
  lxc exec "$CONTAINER_NAME" -t -- su - ubuntu -c \
    "cd /home/ubuntu/project && claude --dangerously-skip-permissions --resume"
}

cmd_claude_run() {
  require_running
  ensure_auth_forwarding
  local prompt="$1"
  if [[ -z "$prompt" ]]; then
    echo "Error: provide a prompt string"
    echo "  ./dilxc.sh claude-run \"fix the tests\""
    exit 1
  fi
  local escaped
  escaped=$(printf '%q' "$prompt")
  lxc exec "$CONTAINER_NAME" -- su - ubuntu -c \
    "cd /home/ubuntu/project && claude --dangerously-skip-permissions -p $escaped"
}

cmd_sync() {
  require_running
  if lxc exec "$CONTAINER_NAME" -- su - ubuntu -c \
    "rsync -av --delete \
      --exclude=node_modules \
      --exclude=.git \
      --exclude=dist \
      --exclude=build \
      /home/ubuntu/project-src/ /home/ubuntu/project/"; then
    echo "Project synced"
  else
    echo "Sync failed"
    exit 1
  fi
}

cmd_exec() {
  require_running
  ensure_auth_forwarding
  if [[ $# -eq 0 ]]; then
    echo "Error: provide a command to run"
    echo "  ./dilxc.sh exec npm test"
    exit 1
  fi
  local cmd=""
  local arg
  for arg in "$@"; do
    cmd+=" $(printf '%q' "$arg")"
  done
  lxc exec "$CONTAINER_NAME" -- su - ubuntu -c "cd /home/ubuntu/project &&$cmd"
}

cmd_pull() {
  require_running
  local src="$1"
  local dest="${2:-.}"
  if [[ -z "$src" ]]; then
    echo "Error: specify path to pull"
    echo "  ./dilxc.sh pull /home/ubuntu/project/dist/ ./dist/"
    exit 1
  fi
  if lxc file pull -r "$CONTAINER_NAME$src" "$dest"; then
    echo "Pulled $src -> $dest"
  else
    echo "Pull failed"
    exit 1
  fi
}

cmd_push() {
  require_running
  local src="$1"
  local dest="${2:-/home/ubuntu/project/}"
  if [[ -z "$src" ]]; then
    echo "Error: specify file to push"
    exit 1
  fi
  if [[ -d "$src" ]]; then
    if lxc file push -r "$src" "$CONTAINER_NAME$dest"; then
      echo "Pushed $src -> $dest"
    else
      echo "Push failed"
      exit 1
    fi
  else
    if lxc file push "$src" "$CONTAINER_NAME$dest"; then
      echo "Pushed $src -> $dest"
    else
      echo "Push failed"
      exit 1
    fi
  fi
}

cmd_snapshot() {
  require_container
  local name="${1:-snap-$(date +%Y%m%d-%H%M%S)}"
  if lxc snapshot "$CONTAINER_NAME" "$name"; then
    echo "Snapshot '$name' created"
  else
    echo "Snapshot failed"
    exit 1
  fi
}

cmd_restore() {
  require_container
  local name="$1"
  if [[ -z "$name" ]]; then
    echo "Error: specify snapshot name"
    echo "Available snapshots:"
    lxc info "$CONTAINER_NAME" | grep -A 100 "^Snapshots:" || echo "  None"
    exit 1
  fi
  echo "Restoring to snapshot '$name'..."
  if lxc restore "$CONTAINER_NAME" "$name"; then
    lxc start "$CONTAINER_NAME" 2>/dev/null || true
    echo "Restored and restarted"
  else
    echo "Restore failed"
    exit 1
  fi
}

cmd_snapshots() {
  require_container
  lxc info "$CONTAINER_NAME" | grep -A 100 "^Snapshots:" || echo "No snapshots"
}

cmd_logs() {
  require_running
  lxc exec "$CONTAINER_NAME" -- su - ubuntu -c "docker compose logs -f" 2>/dev/null || \
  lxc exec "$CONTAINER_NAME" -- su - ubuntu -c "docker logs --tail 100 -f \$(docker ps -q)" 2>/dev/null || \
  echo "No running Docker containers found"
}

cmd_docker() {
  require_running
  local cmd="docker"
  local arg
  for arg in "$@"; do
    cmd+=" $(printf '%q' "$arg")"
  done
  lxc exec "$CONTAINER_NAME" -- su - ubuntu -c "$cmd"
}

cmd_health() {
  require_running
  echo "=== Health Check: $CONTAINER_NAME ==="
  local ok=true

  # Network
  if lxc exec "$CONTAINER_NAME" -- ping -c 1 -W 2 8.8.8.8 &>/dev/null; then
    echo "  Network:      ok"
  else
    echo "  Network:      FAILED"
    ok=false
  fi

  # Docker
  if lxc exec "$CONTAINER_NAME" -- su - ubuntu -c "docker info" &>/dev/null; then
    echo "  Docker:       ok"
  else
    echo "  Docker:       FAILED"
    ok=false
  fi

  # Claude Code
  if lxc exec "$CONTAINER_NAME" -- su - ubuntu -c "claude --version" &>/dev/null; then
    echo "  Claude Code:  ok"
  else
    echo "  Claude Code:  FAILED"
    ok=false
  fi

  # Project directory
  if lxc exec "$CONTAINER_NAME" -- test -d /home/ubuntu/project; then
    echo "  Project dir:  ok"
  else
    echo "  Project dir:  FAILED"
    ok=false
  fi

  # Source mount
  if lxc exec "$CONTAINER_NAME" -- test -d /home/ubuntu/project-src; then
    echo "  Source mount: ok"
  else
    echo "  Source mount: FAILED"
    ok=false
  fi

  $ok || { echo ""; echo "Some checks failed."; exit 1; }
}

cmd_git_auth() {
  require_running
  ensure_auth_forwarding
  echo "=== Git & Forge Auth: $CONTAINER_NAME ==="
  local ok=true

  # SSH agent check
  if lxc config device show "$CONTAINER_NAME" 2>/dev/null | grep -q "^ssh-agent:"; then
    local ssh_output
    if ssh_output=$(lxc exec "$CONTAINER_NAME" -- su - ubuntu -c "ssh-add -l" 2>&1); then
      local count word
      count=$(echo "$ssh_output" | grep -c '^[0-9]')
      word="identities"; [[ "$count" -eq 1 ]] && word="identity"
      echo "  SSH agent:    ok ($count $word available)"
    else
      if echo "$ssh_output" | grep -q "Could not open a connection"; then
        echo "  SSH agent:    NOT AVAILABLE"
        echo "    → Start your SSH agent: eval \"\$(ssh-agent -s)\" && ssh-add"
        ok=false
      else
        echo "  SSH agent:    NO KEYS"
        echo "    → Add a key: ssh-add ~/.ssh/id_ed25519"
        ok=false
      fi
    fi
  else
    echo "  SSH agent:    NOT CONFIGURED"
    echo "    → Start your SSH agent: eval \"\$(ssh-agent -s)\" && ssh-add"
    echo "    → Then run: ./dilxc.sh update"
    ok=false
  fi

  # GitHub CLI check
  if lxc config device show "$CONTAINER_NAME" 2>/dev/null | grep -q "^gh-config:"; then
    local gh_output
    if gh_output=$(lxc exec "$CONTAINER_NAME" -- su - ubuntu -c "gh auth status" 2>&1); then
      local username
      username=$(echo "$gh_output" | grep -oP 'Logged in to github.com account \K\S+' | head -1)
      if [[ -n "$username" ]]; then
        echo "  GitHub CLI:   ok (authenticated as $username)"
      else
        echo "  GitHub CLI:   ok"
      fi
    else
      echo "  GitHub CLI:   NOT AUTHENTICATED"
      echo "    → Authenticate on the host: gh auth login"
      ok=false
    fi
  else
    echo "  GitHub CLI:   NOT CONFIGURED"
    echo "    → Authenticate on the host: gh auth login"
    echo "    → Then run: ./dilxc.sh update"
    ok=false
  fi

  $ok || { echo ""; echo "Some checks failed."; exit 1; }
}

cmd_destroy() {
  require_container
  echo "Warning: This will permanently delete container '$CONTAINER_NAME' and all snapshots."
  read -rp "Type the container name to confirm: " confirm
  if [[ "$confirm" == "$CONTAINER_NAME" ]]; then
    lxc delete "$CONTAINER_NAME" --force
    echo "Container destroyed"
  else
    echo "Aborted."
  fi
}

cmd_containers() {
  local active="$CONTAINER_NAME"
  echo "CONTAINER                        STATUS"
  lxc list -f csv -c ns | while IFS=, read -r name status; do
    if [[ "$name" == "$active" ]]; then
      printf "%-32s %s  (active)\n" "$name" "$status"
    else
      printf "%-32s %s\n" "$name" "$status"
    fi
  done
}

# --- Proxy commands ----------------------------------------------------------

cmd_proxy_add() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: ./dilxc.sh proxy add <container-port> [host-port]"
    exit 1
  fi
  local container_port="$1"
  local host_port="${2:-$1}"
  validate_port "$container_port" "container port"
  validate_port "$host_port" "host port"
  local device_name="proxy-tcp-${host_port}"
  if lxc config device show "$CONTAINER_NAME" 2>/dev/null | grep -q "^${device_name}:"; then
    echo "Error: host port ${host_port} is already proxied (device: ${device_name})"
    exit 1
  fi
  if ! lxc config device add "$CONTAINER_NAME" "$device_name" proxy \
    listen="tcp:0.0.0.0:${host_port}" \
    connect="tcp:127.0.0.1:${container_port}"; then
    echo "Error: failed to add proxy device — is the port already in use?"
    exit 1
  fi
  echo "Proxy added: 0.0.0.0:${host_port} → container:${container_port} (${device_name})"
}

cmd_proxy_list() {
  local output
  if ! output=$(lxc config device show "$CONTAINER_NAME" 2>&1); then
    echo "Error: failed to list devices for container '$CONTAINER_NAME'" >&2
    echo "$output" >&2
    return 1
  fi
  local table
  table=$(echo "$output" | awk '
    function flush() {
      if (listen != "" && connect != "") {
        rows[++n] = listen "|" connect
      }
      listen = ""; connect = ""
    }
    /^proxy-tcp-.*:/ { flush(); in_proxy=1; next }
    /^[^ ]/ { flush(); in_proxy=0; next }
    in_proxy && /listen:/ { listen=$2; sub(/^tcp:/, "", listen) }
    in_proxy && /connect:/ { connect=$2; sub(/^tcp:/, "", connect) }
  END {
    flush()
    if (n > 0) {
      printf "%-18s  %s\n", "HOST", "CONTAINER"
      for (i = 1; i <= n; i++) {
        split(rows[i], parts, "|")
        printf "%-18s  →  %s\n", parts[1], parts[2]
      }
    }
  }')
  if [[ -z "$table" ]]; then
    echo "No proxy devices configured"
  else
    echo "$table"
  fi
}

cmd_proxy_rm() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: ./dilxc.sh proxy rm <host-port>"
    echo "       ./dilxc.sh proxy rm all"
    exit 1
  fi
  if [[ "$1" == "all" ]]; then
    local devices
    devices=$(lxc config device show "$CONTAINER_NAME" 2>/dev/null | grep -oP '^proxy-tcp-[^:]+' || true)
    if [[ -z "$devices" ]]; then
      echo "No proxy devices to remove"
      return 0
    fi
    local count=0
    local dev
    while IFS= read -r dev; do
      lxc config device remove "$CONTAINER_NAME" "$dev" && ((count++))
    done <<< "$devices"
    echo "Removed ${count} proxy device(s)"
  else
    validate_port "$1" "host port"
    local device_name="proxy-tcp-${1}"
    if ! lxc config device show "$CONTAINER_NAME" 2>/dev/null | grep -q "^${device_name}:"; then
      echo "Error: no proxy found for host port ${1}"
      exit 1
    fi
    if ! lxc config device remove "$CONTAINER_NAME" "$device_name"; then
      echo "Error: failed to remove proxy device"
      exit 1
    fi
    echo "Proxy removed: ${device_name}"
  fi
}

proxy_usage() {
  cat << 'EOF'
Usage: ./dilxc.sh proxy <action> [options]

Actions:
  add <container-port> [host-port]   Forward a host port to a container port
  list                               List active port proxies
  rm <host-port>                     Remove a proxy by host port
  rm all                             Remove all proxies

Examples:
  ./dilxc.sh proxy add 3000          # host:3000 → container:3000
  ./dilxc.sh proxy add 8080 9090     # host:9090 → container:8080
  ./dilxc.sh proxy list
  ./dilxc.sh proxy rm 3000
  ./dilxc.sh proxy rm all
EOF
}

cmd_proxy() {
  local action="${1:-help}"
  shift 2>/dev/null || true
  case "$action" in
    add)           require_running; cmd_proxy_add "$@" ;;
    list|ls)       require_container; cmd_proxy_list ;;
    rm|remove)     require_running; cmd_proxy_rm "$@" ;;
    help|--help|*) proxy_usage ;;
  esac
}

# --- Init / Update -----------------------------------------------------------

cmd_init() {
  exec "$SCRIPT_DIR/setup-host.sh" "$@"
}

cmd_update() {
  if [[ ! -d "$SCRIPT_DIR/.git" ]]; then
    echo "Error: not a git checkout — update by re-downloading from GitHub"
    exit 1
  fi
  echo "Updating Docker-in-LXC from $(git -C "$SCRIPT_DIR" rev-parse --short HEAD)..."
  git -C "$SCRIPT_DIR" pull

  # Add missing auth devices to existing containers
  if lxc info "$CONTAINER_NAME" &>/dev/null; then
    if ! lxc config device show "$CONTAINER_NAME" 2>/dev/null | grep -q "^ssh-agent:"; then
      lxc config device add "$CONTAINER_NAME" ssh-agent proxy \
        connect="unix:${SSH_AUTH_SOCK:-/dev/null}" \
        listen=unix:/tmp/ssh-agent.sock \
        bind=container \
        uid=1000 gid=1000 mode=0600
      echo "  Added SSH agent forwarding device"
    fi
    if ! lxc config device show "$CONTAINER_NAME" 2>/dev/null | grep -q "^gh-config:"; then
      if [[ -d "$HOME/.config/gh" ]]; then
        lxc config device add "$CONTAINER_NAME" gh-config disk \
          source="$HOME/.config/gh" \
          path=/home/ubuntu/.config/gh \
          readonly=true \
          shift=true
        echo "  Added GitHub CLI config mount"
      fi
    fi
  fi
}

# --- Main dispatch -----------------------------------------------------------
case "${1:-help}" in
  init)          shift; cmd_init "$@" ;;
  update)        cmd_update ;;
  shell)         cmd_shell ;;
  root)          cmd_root ;;
  start)         cmd_start ;;
  stop)          cmd_stop ;;
  restart)       cmd_restart ;;
  status)        cmd_status ;;
  login)         cmd_login ;;
  claude)        cmd_claude ;;
  claude-run)    shift; cmd_claude_run "$@" ;;
  claude-resume) cmd_claude_resume ;;
  sync)          cmd_sync ;;
  exec)          shift; cmd_exec "$@" ;;
  pull)          shift; cmd_pull "$@" ;;
  push)          shift; cmd_push "$@" ;;
  snapshot)      shift; cmd_snapshot "$@" ;;
  restore)       shift; cmd_restore "$@" ;;
  snapshots)     cmd_snapshots ;;
  logs)          cmd_logs ;;
  docker)        shift; cmd_docker "$@" ;;
  proxy)         shift; cmd_proxy "$@" ;;
  containers)    cmd_containers ;;
  health|health-check) cmd_health ;;
  git-auth)      cmd_git_auth ;;
  destroy)       cmd_destroy ;;
  help|*)        usage ;;
esac
