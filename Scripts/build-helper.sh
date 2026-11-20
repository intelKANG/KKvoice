#!/bin/zsh
set -euo pipefail
root="${0:A:h:h}"
helper="$root/.build/KKvoiceRemoteHelper.app"
contents="$helper/Contents"

resolve_codesign_identity() {
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    print -r -- "$CODESIGN_IDENTITY"
    return
  fi
  local identities id
  identities="$(security find-identity -v -p codesigning 2>/dev/null || true)"
  id="$(print -r -- "$identities" | awk '/"Developer ID Application:/ {print $2; exit}')"
  if [[ -z "$id" ]]; then
    id="$(print -r -- "$identities" | awk '/"Apple Development:/ {print $2; exit}')"
  fi
  if [[ -n "$id" ]]; then
    print -r -- "$id"
  else
    print -r -- "-"
  fi
}

mkdir -p "$contents/MacOS"
cp "$root/Native/Helper/Info.plist" "$contents/Info.plist"
clang -O2 -fobjc-arc -arch arm64 -arch x86_64 -mmacosx-version-min=12.0 \
  -framework Foundation -framework AppKit -framework CoreBluetooth \
  -framework CoreGraphics -framework IOKit -framework Carbon \
  "$root/Native/Helper/ChromecastVoiceRemoteHelper.m" \
  -o "$contents/MacOS/KKvoiceRemoteHelper"

sign_identity="$(resolve_codesign_identity)"
helper_entitlements="$root/Native/Helper/KKvoiceRemoteHelper.entitlements"
if [[ "$sign_identity" == "-" ]]; then
  codesign --force --sign - --timestamp=none --entitlements "$helper_entitlements" --requirements '=designated => identifier "local.kkvoice.remote-helper"' "$helper"
else
  codesign --force --options runtime --timestamp=none --entitlements "$helper_entitlements" --sign "$sign_identity" "$helper"
fi
codesign --verify --strict "$helper"
print "Built helper: $helper (signed with $sign_identity)"
