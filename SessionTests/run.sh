#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_BIN=$(mktemp "${TMPDIR:-/tmp}/kkvoice-session.XXXXXXXX")
trap 'rm -f "$TEST_BIN"' EXIT
swiftc "$ROOT_DIR/Session/VoiceSession.swift" "$ROOT_DIR/Session/ShortcutRelay.swift" "$ROOT_DIR/Session/SystemShortcut.swift" "$ROOT_DIR/Session/ShortcutDefinition.swift" "$ROOT_DIR/SessionTests/main.swift" -o "$TEST_BIN"
"$TEST_BIN"
