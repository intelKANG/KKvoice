#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_BINARY=$(mktemp "${TMPDIR:-/tmp}/kkvoice-snapnote-test.XXXXXX")
trap 'rm -f "$TEST_BINARY"' EXIT
swiftc -parse-as-library "$ROOT_DIR"/SnapNote/*.swift "$ROOT_DIR/SnapNoteTests/main.swift" -o "$TEST_BINARY"
"$TEST_BINARY"
