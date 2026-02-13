#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ ! -x "$SCRIPT_DIR/test/bats/bin/bats" ]]; then
    git -C "$SCRIPT_DIR" submodule update --init --recursive
fi

if [[ $# -gt 0 ]]; then
    "$SCRIPT_DIR/test/bats/bin/bats" "$@"
else
    "$SCRIPT_DIR/test/bats/bin/bats" "$SCRIPT_DIR/test/"
fi
