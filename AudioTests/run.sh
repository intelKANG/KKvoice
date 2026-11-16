#!/bin/sh
set -eu
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TEST_BINARY=$(mktemp "${TMPDIR:-/tmp}/kkvoice-audio-test.XXXXXX")
trap 'rm -f "$TEST_BINARY"' EXIT
swiftc "$ROOT_DIR/Audio/CoreAudioOutput.swift" "$ROOT_DIR/Audio/RemotePCMBuffer.swift" "$ROOT_DIR/Audio/RemoteAudioBridge.swift" "$ROOT_DIR/AudioTests/main.swift" -o "$TEST_BINARY"
"$TEST_BINARY"
