#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
mkdir -p "$root/.build"
cc -std=c11 -Wall -Wextra -Werror "$root/KeyboardTests/modifier_edges.c" -o "$root/.build/kkvoice-modifier-edges-test"
"$root/.build/kkvoice-modifier-edges-test"
