#!/usr/bin/env bash

_common_setup() {
    load 'test_helper/bats-support/load'
    load 'test_helper/bats-assert/load'
    PROJECT_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." >/dev/null 2>&1 && pwd)"
    PATH="$PROJECT_ROOT:$PATH"
    MOCK_BIN="$BATS_TEST_TMPDIR/mock-bin"
    mkdir -p "$MOCK_BIN"
    PATH="$MOCK_BIN:$PATH"
}

# create_mock <cmd> [exit_code]
# Creates a mock executable that records calls and returns the given exit code (default 0).
create_mock() {
    local cmd="$1"
    local exit_code="${2:-0}"
    cat > "$MOCK_BIN/$cmd" << MOCK
#!/usr/bin/env bash
echo "\$@" >> "\$BATS_TEST_TMPDIR/${cmd}.calls"
exit $exit_code
MOCK
    chmod +x "$MOCK_BIN/$cmd"
}

# create_mock_with_output <cmd> <output> [exit_code]
# Creates a mock that prints output, records calls, and returns the given exit code.
# Output is stored in a sidecar file to avoid shell quoting issues.
create_mock_with_output() {
    local cmd="$1"
    local output="$2"
    local exit_code="${3:-0}"
    printf '%s\n' "$output" > "$MOCK_BIN/${cmd}.output"
    cat > "$MOCK_BIN/$cmd" << MOCK
#!/usr/bin/env bash
echo "\$@" >> "\$BATS_TEST_TMPDIR/${cmd}.calls"
cat "$MOCK_BIN/${cmd}.output"
exit $exit_code
MOCK
    chmod +x "$MOCK_BIN/$cmd"
}

# assert_mock_called <cmd>
# Fails if the mock was never called.
assert_mock_called() {
    local cmd="$1"
    if [[ ! -f "$BATS_TEST_TMPDIR/${cmd}.calls" ]]; then
        fail "Expected '$cmd' to have been called, but it was not"
    fi
}

# assert_mock_not_called <cmd>
# Fails if the mock was called.
assert_mock_not_called() {
    local cmd="$1"
    if [[ -f "$BATS_TEST_TMPDIR/${cmd}.calls" ]]; then
        local calls
        calls=$(cat "$BATS_TEST_TMPDIR/${cmd}.calls")
        fail "Expected '$cmd' to not have been called, but it was called with:\n$calls"
    fi
}

# assert_mock_called_with <cmd> <expected_args>
# Fails if no invocation of the mock matches the expected args.
assert_mock_called_with() {
    local cmd="$1"
    local expected="$2"
    if [[ ! -f "$BATS_TEST_TMPDIR/${cmd}.calls" ]]; then
        fail "Expected '$cmd' to have been called with '$expected', but it was never called"
    fi
    if ! grep -qF -- "$expected" "$BATS_TEST_TMPDIR/${cmd}.calls"; then
        local actual
        actual=$(cat "$BATS_TEST_TMPDIR/${cmd}.calls")
        fail "Expected '$cmd' to have been called with '$expected', but actual calls were:\n$actual"
    fi
}
