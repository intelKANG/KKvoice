#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
binary=$(mktemp "${TMPDIR:-/tmp}/kkvoice-capture-gate.XXXXXXXX")
trap 'rm -f "$binary"' EXIT
clang -std=c11 -Wall -Wextra -Werror -I "$root/Native/Helper" "$root/NativeTests/capture-gate.c" -o "$binary"
"$binary"
