#!/usr/bin/env bats

# =============================================================================
# Tests for provision-container.sh (T018-T020)
#
# provision-container.sh uses set -euo pipefail and cannot be sourced.
# All tests run a patched copy of the script black-box via `run` with
# comprehensive mocks. The patched copy replaces hardcoded /home/ubuntu
# and /tmp/custom-provision.sh paths with temp directories so tests can
# run as a regular user without root privileges.
#
# CRITICAL: cat and bash are NOT mocked — bats-core uses them internally.
# The script's heredoc writes (cat >> .bashrc, cat > config.fish) use the
# real cat command, which writes to our temp directories after patching.
# =============================================================================

setup() {
    load 'test_helper/common-setup'
    _common_setup

    # Create a fake ubuntu home directory for config file assertions
    FAKE_HOME="$BATS_TEST_TMPDIR/home/ubuntu"
    mkdir -p "$FAKE_HOME"
    mkdir -p "$FAKE_HOME/.config"

    # Path where custom-provision.sh will be checked (redirected from /tmp/)
    CUSTOM_PROVISION_PATH="$BATS_TEST_TMPDIR/custom-provision.sh"

    # Create a patched copy of provision-container.sh with temp paths
    PATCHED_SCRIPT="$BATS_TEST_TMPDIR/provision-container.sh"
    sed -e "s|/home/ubuntu|$FAKE_HOME|g" \
        -e "s|/tmp/custom-provision.sh|$CUSTOM_PROVISION_PATH|g" \
        "$PROJECT_ROOT/provision-container.sh" > "$PATCHED_SCRIPT"
    chmod +x "$PATCHED_SCRIPT"

    # Mock all external commands the script calls (except cat and bash)
    create_mock apt-get
    create_mock curl
    create_mock su
    create_mock systemctl
    create_mock usermod
    create_mock chsh
    create_mock gpg
    # Custom tee mock that drains stdin to avoid SIGPIPE in pipes like
    # echo "..." | tee /path/to/file > /dev/null
    # (set -o pipefail causes SIGPIPE to abort the script if tee exits
    # without reading its stdin)
    cat > "$MOCK_BIN/tee" << 'MOCK'
#!/usr/bin/env bash
echo "$@" >> "$BATS_TEST_TMPDIR/tee.calls"
cat > /dev/null
exit 0
MOCK
    chmod +x "$MOCK_BIN/tee"
    create_mock install
    create_mock chmod
    create_mock chown

    # Mock commands that produce version output (used in echo statements)
    create_mock_with_output docker "Docker version 24.0.0"
    create_mock_with_output dpkg "amd64"
    create_mock_with_output node "v22.0.0"
    create_mock_with_output git "git version 2.43.0"
    create_mock_with_output claude "1.0.0"
    create_mock_with_output gh "gh version 2.40.0"

    # npm is used both for version output (npm --version) and install commands
    create_mock_with_output npm "10.0.0"

    # IMPORTANT: Do NOT mock 'cat' or 'bash' — bats-core needs them
}

# Helper: run the patched provision-container.sh
_run_provision() {
    run "$PATCHED_SCRIPT" "$@"
}

# =============================================================================
# T018 -- Flag handling tests
# =============================================================================

@test "T018: without --fish, script completes successfully" {
    _run_provision
    assert_success
    assert_output --partial "Container Provisioning Complete"
}

@test "T018: without --fish, chsh is not called" {
    _run_provision
    assert_success
    assert_mock_not_called chsh
}

@test "T018: without --fish, fish config file is not created" {
    _run_provision
    assert_success
    [[ ! -f "$FAKE_HOME/.config/fish/config.fish" ]]
}

@test "T018: without --fish, apt-get is not called with fish" {
    _run_provision
    assert_success
    # Verify no apt-get call includes 'fish' as a standalone install target
    # (apt-get is called many times, but none should be for fish)
    if grep -q "^install -y fish$" "$BATS_TEST_TMPDIR/apt-get.calls" 2>/dev/null; then
        fail "apt-get should not be called to install fish without --fish flag"
    fi
}

@test "T018: with --fish, script completes successfully" {
    _run_provision --fish
    assert_success
    assert_output --partial "Container Provisioning Complete"
}

@test "T018: with --fish, both bash and fish configs are written" {
    _run_provision --fish
    assert_success
    # Bash config is always written
    [[ -f "$FAKE_HOME/.bashrc" ]]
    # Fish config is written only with --fish
    [[ -f "$FAKE_HOME/.config/fish/config.fish" ]]
}

@test "T018: with --fish, chsh is called to set fish as default shell" {
    _run_provision --fish
    assert_success
    assert_mock_called chsh
    assert_mock_called_with chsh "-s /usr/bin/fish ubuntu"
}

@test "T018: with --fish, fish shell installed message is shown" {
    _run_provision --fish
    assert_success
    assert_output --partial "Fish shell installed and set as default"
}

# =============================================================================
# T019 -- Bash config content tests
# =============================================================================

@test "T019: bashrc contains cc alias" {
    _run_provision
    assert_success
    local bashrc="$FAKE_HOME/.bashrc"
    [[ -f "$bashrc" ]]
    grep -q "alias cc='claude --dangerously-skip-permissions'" "$bashrc"
}

@test "T019: bashrc contains cc-resume alias" {
    _run_provision
    assert_success
    grep -q "alias cc-resume='claude --dangerously-skip-permissions --resume'" "$FAKE_HOME/.bashrc"
}

@test "T019: bashrc contains cc-prompt alias" {
    _run_provision
    assert_success
    grep -q "alias cc-prompt='claude --dangerously-skip-permissions -p'" "$FAKE_HOME/.bashrc"
}

@test "T019: bashrc contains sync-project function" {
    _run_provision
    assert_success
    grep -q "sync-project()" "$FAKE_HOME/.bashrc"
}

@test "T019: bashrc sync-project excludes node_modules" {
    _run_provision
    assert_success
    grep -q "\-\-exclude=node_modules" "$FAKE_HOME/.bashrc"
}

@test "T019: bashrc sync-project excludes .git" {
    _run_provision
    assert_success
    grep -q "\-\-exclude=\.git" "$FAKE_HOME/.bashrc"
}

@test "T019: bashrc sync-project excludes dist" {
    _run_provision
    assert_success
    grep -q "\-\-exclude=dist" "$FAKE_HOME/.bashrc"
}

@test "T019: bashrc sync-project excludes build" {
    _run_provision
    assert_success
    grep -q "\-\-exclude=build" "$FAKE_HOME/.bashrc"
}

@test "T019: bashrc contains deploy function" {
    _run_provision
    assert_success
    grep -q "deploy()" "$FAKE_HOME/.bashrc"
}

@test "T019: bashrc PATH includes ~/.local/bin" {
    _run_provision
    assert_success
    grep -q 'export PATH="$HOME/.local/bin:$PATH"' "$FAKE_HOME/.bashrc"
}

@test "T019: bashrc sets SSH_AUTH_SOCK to /tmp/ssh-agent.sock" {
    _run_provision
    assert_success
    grep -q 'export SSH_AUTH_SOCK=/tmp/ssh-agent.sock' "$FAKE_HOME/.bashrc"
}

# =============================================================================
# T020 -- Fish config and custom provision tests
# =============================================================================

# --- Fish config content ---

@test "T020: fish config has cc abbreviation" {
    _run_provision --fish
    assert_success
    local fishrc="$FAKE_HOME/.config/fish/config.fish"
    [[ -f "$fishrc" ]]
    grep -q "abbr -a cc 'claude --dangerously-skip-permissions'" "$fishrc"
}

@test "T020: fish config has cc-resume abbreviation" {
    _run_provision --fish
    assert_success
    grep -q "abbr -a cc-resume 'claude --dangerously-skip-permissions --resume'" "$FAKE_HOME/.config/fish/config.fish"
}

@test "T020: fish config has cc-prompt abbreviation" {
    _run_provision --fish
    assert_success
    grep -q "abbr -a cc-prompt 'claude --dangerously-skip-permissions -p'" "$FAKE_HOME/.config/fish/config.fish"
}

@test "T020: fish config has sync-project function" {
    _run_provision --fish
    assert_success
    grep -q "function sync-project" "$FAKE_HOME/.config/fish/config.fish"
}

@test "T020: fish config sync-project excludes node_modules .git dist and build" {
    _run_provision --fish
    assert_success
    local fishrc="$FAKE_HOME/.config/fish/config.fish"
    grep -q "\-\-exclude=node_modules" "$fishrc"
    grep -q "\-\-exclude=\.git" "$fishrc"
    grep -q "\-\-exclude=dist" "$fishrc"
    grep -q "\-\-exclude=build" "$fishrc"
}

@test "T020: fish config has deploy function" {
    _run_provision --fish
    assert_success
    grep -q "function deploy" "$FAKE_HOME/.config/fish/config.fish"
}

@test "T020: fish config adds ~/.local/bin to PATH" {
    _run_provision --fish
    assert_success
    grep -q "fish_add_path ~/.local/bin" "$FAKE_HOME/.config/fish/config.fish"
}

@test "T020: fish config sets SSH_AUTH_SOCK" {
    _run_provision --fish
    assert_success
    grep -q "set -gx SSH_AUTH_SOCK /tmp/ssh-agent.sock" "$FAKE_HOME/.config/fish/config.fish"
}

# --- Custom provision script ---

@test "T020: custom-provision.sh is executed when present" {
    # Create a custom-provision.sh that writes a marker file
    cat > "$CUSTOM_PROVISION_PATH" << 'EOF'
#!/bin/bash
echo "custom-ran" > "$BATS_TEST_TMPDIR/custom-marker"
EOF
    chmod +x "$CUSTOM_PROVISION_PATH"

    # Export BATS_TEST_TMPDIR so the custom script can use it
    export BATS_TEST_TMPDIR
    _run_provision
    assert_success
    assert_output --partial "Running custom provisioning"
    assert_output --partial "Custom provisioning complete"
    [[ -f "$BATS_TEST_TMPDIR/custom-marker" ]]
}

@test "T020: no error when custom-provision.sh is absent" {
    # Ensure no custom-provision.sh exists
    rm -f "$CUSTOM_PROVISION_PATH"
    _run_provision
    assert_success
    refute_output --partial "Running custom provisioning"
    refute_output --partial "Custom provisioning complete"
}

@test "T020: script completes successfully regardless of custom-provision.sh presence" {
    rm -f "$CUSTOM_PROVISION_PATH"
    _run_provision
    assert_success
    assert_output --partial "Container Provisioning Complete"
}
