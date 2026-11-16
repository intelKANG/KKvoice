#!/bin/zsh
set -euo pipefail
root="${0:A:h:h}"
helper="$root/.build/KKvoiceRemoteHelper.app"
contents="$helper/Contents"
mkdir -p "$contents/MacOS"
cp "$root/Native/Helper/Info.plist" "$contents/Info.plist"
clang -O2 -fobjc-arc -arch arm64 -arch x86_64 -mmacosx-version-min=12.0 \
  -framework Foundation -framework AppKit -framework CoreBluetooth \
  -framework CoreGraphics -framework IOKit -framework Carbon \
  "$root/Native/Helper/ChromecastVoiceRemoteHelper.m" \
  -o "$contents/MacOS/KKvoiceRemoteHelper"
codesign --force --sign - --timestamp=none --requirements '=designated => identifier "local.kkvoice.remote-helper"' "$helper"
codesign --verify --strict "$helper"
print "Built helper: $helper"
