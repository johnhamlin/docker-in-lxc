#!/usr/bin/env bats

setup() {
    load 'test_helper/common-setup'
    _common_setup
    source "$PROJECT_ROOT/dilxc.sh"
    CONTAINER_NAME="test-container"
    SCRIPT_DIR="$PROJECT_ROOT"
}

# =============================================================================
# Smoke tests (US1)
# =============================================================================

@test "help output shows usage information" {
    run usage
    assert_success
    assert_output --partial "Usage: dilxc <command>"
    assert_output --partial "Commands:"
}

@test "unknown subcommand shows usage when run as command" {
    run "$PROJECT_ROOT/dilxc.sh" nonsense-command
    assert_success
    assert_output --partial "Usage: dilxc <command>"
}

# =============================================================================
# Container name resolution (US2 — T006)
# These tests run dilxc.sh as a command (black-box) because the resolution
# cascade is inside the main guard.
# =============================================================================

@test "@name prefix sets container name" {
    create_mock_with_output lxc "Name: myproject
Status: RUNNING"
    run "$PROJECT_ROOT/dilxc.sh" @myproject status
    assert_success
    assert_mock_called_with lxc "info myproject"
}

@test "DILXC_CONTAINER env var sets container name" {
    create_mock_with_output lxc "Name: env-container
Status: RUNNING"
    DILXC_CONTAINER=env-container run "$PROJECT_ROOT/dilxc.sh" status
    assert_success
    assert_mock_called_with lxc "info env-container"
}

@test ".dilxc file walk-up from subdirectory sets container name" {
    # Create a directory tree with a .dilxc file
    local testdir="$BATS_TEST_TMPDIR/project/sub/deep"
    mkdir -p "$testdir"
    echo "file-container" > "$BATS_TEST_TMPDIR/project/.dilxc"

    create_mock_with_output lxc "Name: file-container
Status: RUNNING"

    # Run from the deep subdirectory — the walk-up should find .dilxc
    cd "$testdir"
    run "$PROJECT_ROOT/dilxc.sh" status
    assert_success
    assert_mock_called_with lxc "info file-container"
}

@test "default container name is docker-lxc" {
    # Run from a temp dir with no .dilxc file and no env var
    create_mock_with_output lxc "Name: docker-lxc
Status: RUNNING"
    cd "$BATS_TEST_TMPDIR"
    unset DILXC_CONTAINER 2>/dev/null || true
    run "$PROJECT_ROOT/dilxc.sh" status
    assert_success
    assert_mock_called_with lxc "info docker-lxc"
}

@test "@name takes precedence over DILXC_CONTAINER env var" {
    create_mock_with_output lxc "Name: atname
Status: RUNNING"
    DILXC_CONTAINER=env-name run "$PROJECT_ROOT/dilxc.sh" @atname status
    assert_success
    assert_mock_called_with lxc "info atname"
}

# =============================================================================
# Helper functions and lifecycle commands (US2 — T007)
# =============================================================================

@test "require_container exits with error when container doesn't exist" {
    create_mock lxc 1
    run require_container
    assert_failure
    assert_output --partial "container 'test-container' not found"
}

@test "require_running exits with error when container is stopped" {
    # lxc info succeeds (container exists) but reports STOPPED
    create_mock_with_output lxc "Status: STOPPED"
    run require_running
    assert_failure
    assert_output --partial "not running"
}

@test "require_running succeeds when container is running" {
    create_mock_with_output lxc "Status: RUNNING"
    run require_running
    assert_success
}

@test "cmd_start calls lxc start with container name" {
    create_mock lxc
    run cmd_start
    assert_success
    assert_mock_called_with lxc "start test-container"
    assert_output --partial "Container started"
}

@test "cmd_stop calls lxc stop with container name" {
    # Need lxc to handle both require_running check and the stop command
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info) echo "Status: RUNNING" ;;
    stop) exit 0 ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    run cmd_stop
    assert_success
    assert_mock_called_with lxc "stop test-container"
    assert_output --partial "Container stopped"
}

@test "cmd_restart calls lxc restart with container name" {
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info) echo "Status: RUNNING" ;;
    restart) exit 0 ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    run cmd_restart
    assert_success
    assert_mock_called_with lxc "restart test-container"
    assert_output --partial "Container restarted"
}

@test "cmd_status shows container info" {
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info) echo "Name: test-container"; echo "Status: RUNNING"; echo "Snapshots:" ;;
    list) echo "eth0: 10.0.0.1" ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    run cmd_status
    assert_success
    assert_output --partial "Container Status"
}

@test "cmd_destroy confirmation prompt references correct container name" {
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info) exit 0 ;;
    delete) exit 0 ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    CONTAINER_NAME="jellyfish"
    # Provide wrong name via stdin to abort — test that prompt mentions "jellyfish"
    run bash -c "source '$PROJECT_ROOT/dilxc.sh' && CONTAINER_NAME=jellyfish && PATH='$PATH' && BATS_TEST_TMPDIR='$BATS_TEST_TMPDIR' && echo 'wrong-name' | cmd_destroy"
    assert_output --partial "jellyfish"
    assert_output --partial "Aborted"
}

@test "cmd_destroy with explicit name argument targets that container" {
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info) exit 0 ;;
    delete) exit 0 ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    # Provide the correct name to confirm deletion
    run bash -c "source '$PROJECT_ROOT/dilxc.sh' && CONTAINER_NAME=test-container && PATH='$PATH' && BATS_TEST_TMPDIR='$BATS_TEST_TMPDIR' && echo 'other-box' | cmd_destroy other-box"
    assert_output --partial "other-box"
}

# =============================================================================
# Interactive command tests (US2 — T008)
# =============================================================================

@test "cmd_shell passes -t flag for TTY and runs as ubuntu user" {
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info) echo "Status: RUNNING" ;;
    config) exit 0 ;;
    exec) exit 0 ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    run cmd_shell
    assert_success
    assert_mock_called_with lxc "exec test-container -t -- su - ubuntu"
}

@test "cmd_root passes -t flag and runs bash" {
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info) echo "Status: RUNNING" ;;
    exec) exit 0 ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    run cmd_root
    assert_success
    assert_mock_called_with lxc "exec test-container -t -- bash"
}

@test "cmd_login allocates TTY" {
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info) echo "Status: RUNNING" ;;
    config) exit 0 ;;
    exec) exit 0 ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    run cmd_login
    assert_success
    assert_mock_called_with lxc "exec test-container -t -- su - ubuntu -c claude"
}

@test "cmd_claude passes --dangerously-skip-permissions" {
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info) echo "Status: RUNNING" ;;
    config) exit 0 ;;
    exec) exit 0 ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    run cmd_claude
    assert_success
    assert_mock_called_with lxc "exec test-container -t -- su - ubuntu -c cd /home/ubuntu/project && claude --dangerously-skip-permissions"
}

@test "cmd_claude_resume passes --resume flag" {
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info) echo "Status: RUNNING" ;;
    config) exit 0 ;;
    exec) exit 0 ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    run cmd_claude_resume
    assert_success
    assert_mock_called_with lxc "--dangerously-skip-permissions --resume"
}

@test "cmd_claude_run escapes prompt via printf %q" {
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info) echo "Status: RUNNING" ;;
    config) exit 0 ;;
    exec) exit 0 ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    run cmd_claude_run "fix the tests"
    assert_success
    # printf %q escapes spaces — verify the escaped prompt appears in the call
    assert_mock_called_with lxc "fix\ the\ tests"
}

@test "cmd_claude_run errors when no prompt is provided" {
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info) echo "Status: RUNNING" ;;
    config) exit 0 ;;
    exec) exit 0 ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    run cmd_claude_run ""
    assert_failure
    assert_output --partial "provide a prompt"
}

# =============================================================================
# File operation tests (US2 — T009)
# =============================================================================

# Helper: create a standard lxc mock that handles require_running + commands
_mock_lxc_running() {
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info) echo "Status: RUNNING" ;;
    config) exit 0 ;;
    exec) exit 0 ;;
    file) exit 0 ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"
}

@test "cmd_sync calls rsync with correct excludes and paths" {
    _mock_lxc_running
    run cmd_sync
    assert_success
    # Verify rsync call has the correct excludes (the script uses multi-line formatting)
    assert_mock_called_with lxc "--exclude=node_modules"
    assert_mock_called_with lxc "--exclude=.git"
    assert_mock_called_with lxc "--exclude=dist"
    assert_mock_called_with lxc "--exclude=build"
    assert_mock_called_with lxc "/home/ubuntu/project-src/ /home/ubuntu/project/"
    assert_output --partial "Project synced"
}

@test "cmd_exec passes through arbitrary commands" {
    _mock_lxc_running
    run cmd_exec npm test
    assert_success
    assert_mock_called_with lxc "exec test-container -- su - ubuntu -c"
    assert_mock_called_with lxc "npm"
}

@test "cmd_exec requires at least one argument" {
    _mock_lxc_running
    run cmd_exec
    assert_failure
    assert_output --partial "provide a command"
}

@test "cmd_pull transfers from container to host" {
    _mock_lxc_running
    run cmd_pull /home/ubuntu/project/dist/ ./dist/
    assert_success
    assert_mock_called_with lxc "file pull -r test-container/home/ubuntu/project/dist/ ./dist/"
    assert_output --partial "Pulled"
}

@test "cmd_push transfers from host to container" {
    _mock_lxc_running
    # Create a test file to push
    local testfile="$BATS_TEST_TMPDIR/testfile.txt"
    echo "test" > "$testfile"
    run cmd_push "$testfile" /home/ubuntu/project/
    assert_success
    assert_mock_called_with lxc "file push $testfile test-container/home/ubuntu/project/"
    assert_output --partial "Pushed"
}

# =============================================================================
# Snapshot tests (US2 — T010)
# =============================================================================

@test "cmd_snapshot with explicit name calls lxc snapshot with that name" {
    create_mock lxc
    run cmd_snapshot my-snap
    assert_success
    assert_mock_called_with lxc "snapshot test-container my-snap"
    assert_output --partial "Snapshot 'my-snap' created"
}

@test "cmd_snapshot without name generates timestamp-based name" {
    create_mock lxc
    run cmd_snapshot
    assert_success
    assert_mock_called_with lxc "snapshot test-container snap-"
    assert_output --partial "Snapshot 'snap-"
}

@test "cmd_restore calls lxc restore then restarts container" {
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info) exit 0 ;;
    restore) exit 0 ;;
    start) exit 0 ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    run cmd_restore my-snap
    assert_success
    assert_mock_called_with lxc "restore test-container my-snap"
    assert_mock_called_with lxc "start test-container"
    assert_output --partial "Restored and restarted"
}

@test "cmd_restore without name shows error and lists snapshots" {
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info) echo "Snapshots:"; echo "  clean-baseline" ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    run cmd_restore ""
    assert_failure
    assert_output --partial "specify snapshot name"
}

@test "cmd_snapshots calls lxc info to list snapshots" {
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
echo "Snapshots:"
echo "  clean-baseline (2026/02/13 10:00 UTC)"
MOCK
    chmod +x "$MOCK_BIN/lxc"

    run cmd_snapshots
    assert_success
    assert_mock_called_with lxc "info test-container"
    assert_output --partial "Snapshots:"
}

# =============================================================================
# Docker and proxy tests (US2 — T011)
# =============================================================================

@test "cmd_docker escapes arguments via printf %q" {
    _mock_lxc_running
    run cmd_docker compose up -d
    assert_success
    assert_mock_called_with lxc "exec test-container -- su - ubuntu -c docker compose up -d"
}

@test "cmd_proxy_add validates port range - rejects 0" {
    _mock_lxc_running
    run cmd_proxy_add 0
    assert_failure
    assert_output --partial "invalid"
}

@test "cmd_proxy_add validates port range - rejects 99999" {
    _mock_lxc_running
    run cmd_proxy_add 99999
    assert_failure
    assert_output --partial "invalid"
}

@test "cmd_proxy_add validates port range - rejects non-numeric" {
    _mock_lxc_running
    run cmd_proxy_add abc
    assert_failure
    assert_output --partial "invalid"
}

@test "cmd_proxy_add creates lxc proxy device with single port" {
    _mock_lxc_running
    run cmd_proxy_add 3000
    assert_success
    assert_mock_called_with lxc "config device add test-container proxy-tcp-3000 proxy"
    assert_mock_called_with lxc "listen=tcp:0.0.0.0:3000"
    assert_mock_called_with lxc "connect=tcp:127.0.0.1:3000"
}

@test "cmd_proxy_add with two args maps container port to different host port" {
    _mock_lxc_running
    run cmd_proxy_add 8080 9090
    assert_success
    assert_mock_called_with lxc "config device add test-container proxy-tcp-9090 proxy"
    assert_mock_called_with lxc "listen=tcp:0.0.0.0:9090"
    assert_mock_called_with lxc "connect=tcp:127.0.0.1:8080"
}

@test "cmd_proxy_list formats output" {
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info) exit 0 ;;
    config)
        cat << 'EOF'
proxy-tcp-3000:
  connect: tcp:127.0.0.1:3000
  listen: tcp:0.0.0.0:3000
  type: proxy
EOF
        ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    run cmd_proxy_list
    assert_success
    assert_output --partial "HOST"
    assert_output --partial "CONTAINER"
}

@test "cmd_proxy_rm removes single proxy" {
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info) echo "Status: RUNNING" ;;
    config)
        case "$2" in
            device)
                case "$3" in
                    show) echo "proxy-tcp-3000:"; echo "  type: proxy" ;;
                    remove) exit 0 ;;
                esac
                ;;
        esac
        ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    run cmd_proxy_rm 3000
    assert_success
    assert_mock_called_with lxc "config device remove test-container proxy-tcp-3000"
    assert_output --partial "Proxy removed"
}

@test "cmd_proxy_rm all removes all proxies" {
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info) echo "Status: RUNNING" ;;
    config)
        case "$2" in
            device)
                case "$3" in
                    show)
                        echo "proxy-tcp-3000:"
                        echo "  type: proxy"
                        echo "proxy-tcp-8080:"
                        echo "  type: proxy"
                        ;;
                    remove) exit 0 ;;
                esac
                ;;
        esac
        ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    run cmd_proxy_rm "all"
    assert_success
    assert_output --partial "Removed 2 proxy device(s)"
}

# =============================================================================
# Utility command tests (US2 — T012)
# =============================================================================

@test "cmd_containers lists containers with active marker for current name" {
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
echo "test-container,RUNNING"
echo "other-box,STOPPED"
MOCK
    chmod +x "$MOCK_BIN/lxc"

    run cmd_containers
    assert_success
    assert_output --partial "(active)"
    assert_output --partial "test-container"
    assert_output --partial "other-box"
}

@test "cmd_update runs git pull" {
    # SCRIPT_DIR must be a git checkout
    SCRIPT_DIR="$BATS_TEST_TMPDIR/fakegit"
    mkdir -p "$SCRIPT_DIR/.git"

    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info) exit 1 ;;  # container doesn't exist, skip device setup
    config) exit 0 ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    create_mock_with_output git "abc1234"

    run cmd_update
    assert_success
    assert_mock_called_with git "pull"
}

@test "cmd_init delegates to setup-host.sh via exec" {
    # Create a fake setup-host.sh that records it was called
    cat > "$MOCK_BIN/setup-host.sh" << MOCK
#!/usr/bin/env bash
echo "setup-host called with: \$@"
MOCK
    chmod +x "$MOCK_BIN/setup-host.sh"
    # Point SCRIPT_DIR to MOCK_BIN so exec finds our mock
    SCRIPT_DIR="$MOCK_BIN"

    # cmd_init uses exec, which replaces the process — use run
    run cmd_init -p /some/path --fish
    assert_success
    assert_output --partial "setup-host called with: -p /some/path --fish"
}

@test "cmd_customize creates template when absent and opens editor" {
    SCRIPT_DIR="$BATS_TEST_TMPDIR"
    # Set EDITOR to a no-op to avoid blocking
    EDITOR="true"

    run cmd_customize
    assert_success
    assert_output --partial "Created starter template"
    # Verify the file was actually created
    [[ -f "$BATS_TEST_TMPDIR/custom-provision.sh" ]]
}

@test "cmd_health checks network, docker, claude, and dirs" {
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info) echo "Status: RUNNING" ;;
    exec)
        # All health checks pass
        exit 0
        ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    run cmd_health
    assert_success
    assert_output --partial "Health Check: test-container"
    assert_output --partial "ok"
}

@test "cmd_health reports failures when checks fail" {
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info) echo "Status: RUNNING" ;;
    exec) exit 1 ;;  # all exec commands fail
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    run cmd_health
    assert_failure
    assert_output --partial "FAILED"
}

# =============================================================================
# git-auth and ensure_auth_forwarding tests (US2 — T013)
# =============================================================================

@test "cmd_git_auth reports SSH agent status when keys available" {
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info) echo "Status: RUNNING" ;;
    config)
        case "$3" in
            show)
                echo "ssh-agent:"
                echo "  type: proxy"
                echo "gh-config:"
                echo "  type: disk"
                ;;
            set) exit 0 ;;
        esac
        ;;
    exec)
        # Check what command is being run
        local args="$*"
        if [[ "$args" == *"ssh-add"* ]]; then
            echo "256 SHA256:abc123 user@host (ED25519)"
        elif [[ "$args" == *"gh auth"* ]]; then
            echo "Logged in to github.com account testuser"
        fi
        ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    run cmd_git_auth
    assert_success
    assert_output --partial "SSH agent:"
    assert_output --partial "ok"
    assert_output --partial "GitHub CLI:"
}

@test "cmd_git_auth reports remediation when SSH agent not available" {
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
all_args="$*"
case "$1" in
    info) echo "Status: RUNNING" ;;
    config)
        case "$3" in
            show)
                echo "ssh-agent:"
                echo "  type: proxy"
                echo "gh-config:"
                echo "  type: disk"
                ;;
            set) exit 0 ;;
        esac
        ;;
    exec)
        if [[ "$all_args" == *"ssh-add"* ]]; then
            echo "Could not open a connection to your authentication agent." >&2
            exit 1
        elif [[ "$all_args" == *"gh auth"* ]]; then
            exit 1
        fi
        ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    run cmd_git_auth
    assert_failure
    assert_output --partial "NOT AVAILABLE"
    assert_output --partial "ssh-agent"
}

@test "cmd_git_auth reports when SSH device not configured" {
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info) echo "Status: RUNNING" ;;
    config)
        case "$3" in
            show) echo "" ;;  # no devices
            set) exit 0 ;;
        esac
        ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    run cmd_git_auth
    assert_failure
    assert_output --partial "NOT CONFIGURED"
}

@test "ensure_auth_forwarding updates ssh-agent device connect path" {
    SSH_AUTH_SOCK="/tmp/test-agent.sock"

    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    config)
        case "$2" in
            device)
                case "$3" in
                    show)
                        echo "ssh-agent:"
                        echo "  type: proxy"
                        echo "gh-config:"
                        echo "  type: disk"
                        ;;
                    set) exit 0 ;;
                    add) exit 0 ;;
                esac
                ;;
        esac
        ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    run ensure_auth_forwarding
    assert_success
    assert_mock_called_with lxc "config device set test-container ssh-agent connect=unix:/tmp/test-agent.sock"
}

@test "ensure_auth_forwarding adds gh-config device when missing and host config exists" {
    HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME/.config/gh"

    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    config)
        case "$2" in
            device)
                case "$3" in
                    show)
                        echo "ssh-agent:"
                        echo "  type: proxy"
                        ;;
                    set) exit 0 ;;
                    add) exit 0 ;;
                esac
                ;;
        esac
        ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    run ensure_auth_forwarding
    assert_success
    assert_mock_called_with lxc "config device add test-container gh-config disk"
    assert_mock_called_with lxc "shift=true"
}

# =============================================================================
# Cross-cutting: Rsync exclude sync test (FR-008 — T023)
# =============================================================================

@test "rsync excludes are identical across dilxc.sh, bash config, and fish config" {
    # Extract exclude lists from all three locations
    local dilxc_excludes bash_excludes fish_excludes

    # dilxc.sh cmd_sync excludes
    dilxc_excludes=$(grep -oP '(?<=--exclude=)\S+' "$PROJECT_ROOT/dilxc.sh" | sort)

    # provision-container.sh bash sync-project excludes (between 'sync-project()' and next function)
    bash_excludes=$(sed -n '/^sync-project()/,/^}/p' "$PROJECT_ROOT/provision-container.sh" | grep -oP '(?<=--exclude=)\S+' | sort)

    # provision-container.sh fish sync-project excludes (between 'function sync-project' and 'end')
    fish_excludes=$(sed -n '/^function sync-project/,/^end/p' "$PROJECT_ROOT/provision-container.sh" | grep -oP '(?<=--exclude=)\S+' | sort)

    # All three should be identical
    [[ "$dilxc_excludes" == "$bash_excludes" ]] || {
        echo "dilxc.sh excludes: $dilxc_excludes"
        echo "bash excludes: $bash_excludes"
        fail "dilxc.sh and bash sync-project excludes differ"
    }
    [[ "$bash_excludes" == "$fish_excludes" ]] || {
        echo "bash excludes: $bash_excludes"
        echo "fish excludes: $fish_excludes"
        fail "bash and fish sync-project excludes differ"
    }

    # Verify the expected set is present
    [[ "$dilxc_excludes" == *"node_modules"* ]]
    [[ "$dilxc_excludes" == *".git"* ]]
    [[ "$dilxc_excludes" == *"dist"* ]]
    [[ "$dilxc_excludes" == *"build"* ]]
}
