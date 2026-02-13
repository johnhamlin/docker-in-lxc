#!/usr/bin/env bats

# =============================================================================
# Tests for setup-host.sh (T014-T017)
#
# setup-host.sh uses set -euo pipefail and cannot be sourced.
# All tests run the script black-box via `run` with comprehensive mocks.
# =============================================================================

setup() {
    load 'test_helper/common-setup'
    _common_setup

    # Create temp directories for test isolation
    TEST_PROJECT_DIR="$BATS_TEST_TMPDIR/project"
    mkdir -p "$TEST_PROJECT_DIR"

    TEST_HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$TEST_HOME"

    TEST_DEPLOY_DIR="$BATS_TEST_TMPDIR/deploy"
    mkdir -p "$TEST_DEPLOY_DIR"

    # Copy setup-host.sh to a temp directory so tests that create
    # custom-provision.sh (resolved via dirname "$0") don't pollute
    # the working tree
    SETUP_SCRIPT_DIR="$BATS_TEST_TMPDIR/script-dir"
    mkdir -p "$SETUP_SCRIPT_DIR"
    cp "$PROJECT_ROOT/setup-host.sh" "$SETUP_SCRIPT_DIR/setup-host.sh"

    # Create comprehensive lxc mock that handles all subcommands
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info)
        # Return success so script takes the "already exists" path
        echo "Name: test-container"
        echo "Status: RUNNING"
        ;;
    launch)  exit 0 ;;
    config)  exit 0 ;;
    exec)    exit 0 ;;
    file)    exit 0 ;;
    storage) echo "default,btrfs" ;;
    network) echo "lxdbr0,bridge" ;;
    snapshot) exit 0 ;;
    list)    echo "test-container,RUNNING" ;;
    delete)  exit 0 ;;
    *)       exit 0 ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    # Mock snap (script checks for it when lxc is not found)
    create_mock snap

    # Mock sleep (used in network wait loop)
    create_mock sleep

    # Ensure SSH_AUTH_SOCK is set to something for deterministic behavior
    export SSH_AUTH_SOCK="/tmp/test-ssh-agent.sock"
}

# Helper: run setup-host.sh with the lxc mock and isolated HOME
_run_setup() {
    HOME="$TEST_HOME" run "$SETUP_SCRIPT_DIR/setup-host.sh" "$@"
}

# =============================================================================
# T014 -- Argument parsing tests
# =============================================================================

@test "T014: no arguments exits with 'project path is required' error" {
    _run_setup
    assert_failure
    assert_output --partial "project path is required"
}

@test "T014: unknown flag exits with error" {
    _run_setup --bogus-flag
    assert_failure
    assert_output --partial "Unknown option: --bogus-flag"
}

@test "T014: -h shows usage information" {
    _run_setup -h
    assert_success
    assert_output --partial "Usage: ./setup-host.sh"
    assert_output --partial "--project"
    assert_output --partial "--name"
    assert_output --partial "--deploy"
    assert_output --partial "--fish"
}

@test "T014: --help shows usage information" {
    _run_setup --help
    assert_success
    assert_output --partial "Usage: ./setup-host.sh"
}

@test "T014: -p without value exits with error" {
    _run_setup -p
    assert_failure
}

# =============================================================================
# T015 -- Flag handling and LXD command tests
# =============================================================================

@test "T015: --name sets container name" {
    _run_setup -p "$TEST_PROJECT_DIR" -n my-custom-name
    assert_success
    assert_output --partial "Container: my-custom-name"
    # Verify lxc commands used the custom container name
    assert_mock_called_with lxc "info my-custom-name"
}

@test "T015: default container name is docker-lxc" {
    # Unset DILXC_CONTAINER to get the default
    unset DILXC_CONTAINER
    _run_setup -p "$TEST_PROJECT_DIR"
    assert_success
    assert_output --partial "Container: docker-lxc"
}

@test "T015: DILXC_CONTAINER env var sets default container name" {
    DILXC_CONTAINER="env-container" _run_setup -p "$TEST_PROJECT_DIR"
    assert_success
    assert_output --partial "Container: env-container"
}

@test "T015: --fish flag is passed through to provisioning script" {
    _run_setup -p "$TEST_PROJECT_DIR" --fish
    assert_success
    # The script calls: lxc exec CONTAINER -- /tmp/provision-container.sh --fish
    assert_mock_called_with lxc "exec docker-lxc -- /tmp/provision-container.sh --fish"
}

@test "T015: without --fish, provisioning script is called without --fish" {
    _run_setup -p "$TEST_PROJECT_DIR"
    assert_success
    # The script calls: lxc exec CONTAINER -- /tmp/provision-container.sh (no --fish)
    assert_mock_called_with lxc "exec docker-lxc -- /tmp/provision-container.sh"
}

@test "T015: --deploy flag creates deploy disk device" {
    _run_setup -p "$TEST_PROJECT_DIR" -d "$TEST_DEPLOY_DIR"
    assert_success
    assert_mock_called_with lxc "config device add docker-lxc deploy disk"
    assert_output --partial "Mounting deploy directory"
}

@test "T015: without --deploy, deploy step is skipped" {
    _run_setup -p "$TEST_PROJECT_DIR"
    assert_success
    assert_output --partial "No deploy path specified, skipping"
    # Should NOT have a device add for deploy (but device remove for deploy may be absent)
    # Verify the deploy mount message is not shown
    refute_output --partial "Mounted $TEST_DEPLOY_DIR"
}

@test "T015: lxc info is called to check if container exists" {
    _run_setup -p "$TEST_PROJECT_DIR"
    assert_success
    assert_mock_called_with lxc "info docker-lxc"
}

@test "T015: when container exists, creation is skipped" {
    _run_setup -p "$TEST_PROJECT_DIR"
    assert_success
    assert_output --partial "already exists. Skipping creation"
}

@test "T015: when container does not exist, lxc launch is called with correct args" {
    # Override lxc mock so info returns failure (container doesn't exist)
    cat > "$MOCK_BIN/lxc" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/lxc.calls"
case "$1" in
    info)
        # First call: container doesn't exist
        if [[ ! -f "$BATS_TEST_TMPDIR/lxc_info_called" ]]; then
            touch "$BATS_TEST_TMPDIR/lxc_info_called"
            exit 1
        fi
        echo "Name: test-container"
        echo "Status: RUNNING"
        ;;
    launch)  exit 0 ;;
    config)  exit 0 ;;
    exec)    exit 0 ;;
    file)    exit 0 ;;
    storage) echo "default,btrfs" ;;
    network) echo "lxdbr0,bridge" ;;
    snapshot) exit 0 ;;
    list)    echo "test-container,RUNNING" ;;
    delete)  exit 0 ;;
    *)       exit 0 ;;
esac
MOCK
    chmod +x "$MOCK_BIN/lxc"

    _run_setup -p "$TEST_PROJECT_DIR"
    assert_success
    assert_mock_called_with lxc "launch ubuntu:24.04 docker-lxc -c security.nesting=true -c security.syscalls.intercept.mknod=true -c security.syscalls.intercept.setxattr=true"
}

# =============================================================================
# T016 -- Device mount and provisioning tests
# =============================================================================

@test "T016: project device has readonly=true and shift=true" {
    _run_setup -p "$TEST_PROJECT_DIR"
    assert_success
    # Check that the device add call includes readonly=true and shift=true
    local calls
    calls=$(cat "$BATS_TEST_TMPDIR/lxc.calls")
    # The call should look like:
    # config device add docker-lxc project disk source=... path=/home/ubuntu/project-src readonly=true shift=true
    local project_line
    project_line=$(grep "config device add docker-lxc project disk" "$BATS_TEST_TMPDIR/lxc.calls" || true)
    [[ -n "$project_line" ]]
    [[ "$project_line" == *"readonly=true"* ]]
    [[ "$project_line" == *"shift=true"* ]]
}

@test "T016: deploy device is only created with --deploy flag" {
    _run_setup -p "$TEST_PROJECT_DIR"
    assert_success
    # No deploy device add without the flag
    if grep -q "config device add docker-lxc deploy disk" "$BATS_TEST_TMPDIR/lxc.calls" 2>/dev/null; then
        fail "Deploy device should not be created without --deploy flag"
    fi
}

@test "T016: deploy device is created with --deploy flag" {
    _run_setup -p "$TEST_PROJECT_DIR" -d "$TEST_DEPLOY_DIR"
    assert_success
    local deploy_line
    deploy_line=$(grep "config device add docker-lxc deploy disk" "$BATS_TEST_TMPDIR/lxc.calls" || true)
    [[ -n "$deploy_line" ]]
    [[ "$deploy_line" == *"source=$TEST_DEPLOY_DIR"* ]]
    [[ "$deploy_line" == *"path=/mnt/deploy"* ]]
    [[ "$deploy_line" == *"shift=true"* ]]
}

@test "T016: ssh-agent proxy device is created" {
    _run_setup -p "$TEST_PROJECT_DIR"
    assert_success
    assert_mock_called_with lxc "config device add docker-lxc ssh-agent proxy"
}

@test "T016: ssh-agent proxy device uses SSH_AUTH_SOCK" {
    export SSH_AUTH_SOCK="/tmp/my-agent.sock"
    _run_setup -p "$TEST_PROJECT_DIR"
    assert_success
    local ssh_line
    ssh_line=$(grep "config device add docker-lxc ssh-agent proxy" "$BATS_TEST_TMPDIR/lxc.calls" || true)
    [[ -n "$ssh_line" ]]
    [[ "$ssh_line" == *"connect=unix:/tmp/my-agent.sock"* ]]
}

@test "T016: gh-config disk device is created when ~/.config/gh exists" {
    # Create the gh config directory in our test HOME
    mkdir -p "$TEST_HOME/.config/gh"
    _run_setup -p "$TEST_PROJECT_DIR"
    assert_success
    assert_mock_called_with lxc "config device add docker-lxc gh-config disk"
    assert_output --partial "GitHub CLI config: mounted"
}

@test "T016: gh-config disk device has readonly=true and shift=true" {
    mkdir -p "$TEST_HOME/.config/gh"
    _run_setup -p "$TEST_PROJECT_DIR"
    assert_success
    local gh_line
    gh_line=$(grep "config device add docker-lxc gh-config disk" "$BATS_TEST_TMPDIR/lxc.calls" || true)
    [[ -n "$gh_line" ]]
    [[ "$gh_line" == *"readonly=true"* ]]
    [[ "$gh_line" == *"shift=true"* ]]
}

@test "T016: gh-config device is skipped when ~/.config/gh does not exist" {
    # Do NOT create gh config directory
    _run_setup -p "$TEST_PROJECT_DIR"
    assert_success
    assert_output --partial "GitHub CLI config: skipped"
    # Should not have a device add for gh-config
    if grep -q "config device add docker-lxc gh-config disk" "$BATS_TEST_TMPDIR/lxc.calls" 2>/dev/null; then
        fail "gh-config device should not be created when ~/.config/gh does not exist"
    fi
}

@test "T016: provision-container.sh is pushed to container" {
    _run_setup -p "$TEST_PROJECT_DIR"
    assert_success
    assert_mock_called_with lxc "file push"
    # Check that the provision script path is correct
    local push_line
    push_line=$(grep "file push" "$BATS_TEST_TMPDIR/lxc.calls" | head -n 1)
    [[ "$push_line" == *"provision-container.sh"* ]]
    [[ "$push_line" == *"docker-lxc/tmp/provision-container.sh"* ]]
}

@test "T016: custom-provision.sh is pushed when present" {
    # Create a custom-provision.sh next to the setup script copy
    cat > "$SETUP_SCRIPT_DIR/custom-provision.sh" << 'EOF'
#!/bin/bash
set -euo pipefail
echo "custom provisioning"
EOF
    _run_setup -p "$TEST_PROJECT_DIR"
    assert_success
    assert_output --partial "Custom provision script detected"
    # Check that lxc file push was called for custom-provision.sh
    local custom_push
    custom_push=$(grep "file push.*custom-provision.sh" "$BATS_TEST_TMPDIR/lxc.calls" || true)
    [[ -n "$custom_push" ]]
}

@test "T016: custom-provision.sh is skipped when absent" {
    # Ensure no custom-provision.sh exists next to the setup script
    rm -f "$SETUP_SCRIPT_DIR/custom-provision.sh"
    _run_setup -p "$TEST_PROJECT_DIR"
    assert_success
    refute_output --partial "Custom provision script detected"
    # Check that lxc file push was NOT called for custom-provision.sh
    if grep -q "file push.*custom-provision.sh" "$BATS_TEST_TMPDIR/lxc.calls" 2>/dev/null; then
        fail "custom-provision.sh should not be pushed when it does not exist"
    fi
}

@test "T016: chmod +x is called on provision script" {
    _run_setup -p "$TEST_PROJECT_DIR"
    assert_success
    assert_mock_called_with lxc "exec docker-lxc -- chmod +x /tmp/provision-container.sh"
}

# =============================================================================
# T017 -- Completion tests
# =============================================================================

@test "T017: lxc snapshot clean-baseline is called" {
    _run_setup -p "$TEST_PROJECT_DIR"
    assert_success
    assert_mock_called_with lxc "snapshot docker-lxc clean-baseline"
    assert_output --partial "Snapshot 'clean-baseline' created"
}

@test "T017: .dilxc file is written to PROJECT_PATH with container name" {
    _run_setup -p "$TEST_PROJECT_DIR"
    assert_success
    [[ -f "$TEST_PROJECT_DIR/.dilxc" ]]
    local contents
    contents=$(cat "$TEST_PROJECT_DIR/.dilxc")
    [[ "$contents" == "docker-lxc" ]]
}

@test "T017: .dilxc file contains custom container name when --name is used" {
    _run_setup -p "$TEST_PROJECT_DIR" -n my-special-container
    assert_success
    [[ -f "$TEST_PROJECT_DIR/.dilxc" ]]
    local contents
    contents=$(cat "$TEST_PROJECT_DIR/.dilxc")
    [[ "$contents" == "my-special-container" ]]
}

@test "T017: setup complete message is shown" {
    _run_setup -p "$TEST_PROJECT_DIR"
    assert_success
    assert_output --partial "Setup Complete!"
}

@test "T017: snapshot uses custom container name" {
    _run_setup -p "$TEST_PROJECT_DIR" -n custom-box
    assert_success
    assert_mock_called_with lxc "snapshot custom-box clean-baseline"
}
