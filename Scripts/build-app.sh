#!/bin/zsh
set -euo pipefail
root="${0:A:h:h}"
cd "$root"

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

is_blackhole_built_driver() {
  local drv="$1"
  local plist="$drv/Contents/Info.plist"
  [[ -d "$drv" && -f "$plist" ]] || return 1
  local bundle_id provenance
  bundle_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$plist" 2>/dev/null || true)"
  provenance="$(/usr/libexec/PlistBuddy -c 'Print :KKvoiceBuildSource' "$plist" 2>/dev/null || true)"
  [[ "$bundle_id" == "local.kkvoice.mic.driver" && "$provenance" == ExistentialAudio/BlackHole@* ]]
}

driver_build="$root/.build/KKvoiceMic.driver"
if ! is_blackhole_built_driver "$driver_build"; then
  if command -v xcodebuild >/dev/null 2>&1 && xcodebuild -version >/dev/null 2>&1; then
    "$root/Driver/build-blackhole-driver.sh"
  fi
fi

"$root/Scripts/build-helper.sh"
swift build -c release

app="$root/dist/KKvoice.app"
contents="$app/Contents"
/bin/rm -rf "$app"
mkdir -p "$contents/MacOS" "$contents/Resources"
cp "$root/.build/release/KKvoice" "$contents/MacOS/KKvoice"
cp "$root/Native/Info.plist" "$contents/Info.plist"
cp "$root/Native/Assets/KKvoice.icns" "$contents/Resources/KKvoice.icns"
cp "$root/Native/Assets/KKvoice-logo.png" "$contents/Resources/KKvoice-logo.png"
if [[ -f "$root/Driver/LICENSES/BlackHole-GPL-3.0.txt" ]]; then
  cp "$root/Driver/LICENSES/BlackHole-GPL-3.0.txt" "$contents/Resources/BlackHole-GPL-3.0.txt"
fi
ditto "$root/.build/KKvoiceRemoteHelper.app" "$contents/Resources/KKvoiceRemoteHelper.app"

sign_identity="$(resolve_codesign_identity)"

# Sign inside-out: 1) KKvoiceMic.driver -> 2) KKvoiceRemoteHelper.app -> 3) KKvoice.app
if is_blackhole_built_driver "$driver_build"; then
  ditto "$driver_build" "$contents/Resources/KKvoiceMic.driver"
  if [[ "$sign_identity" == "-" ]]; then
    codesign --force --deep --sign - --timestamp=none "$contents/Resources/KKvoiceMic.driver"
  else
    codesign --force --deep --options runtime --timestamp=none --sign "$sign_identity" "$contents/Resources/KKvoiceMic.driver"
  fi
  codesign --verify --deep --strict "$contents/Resources/KKvoiceMic.driver"
else
  print -u2 "Warning: skipping KKvoiceMic.driver bundling (not built from BlackHole source)."
fi

if [[ "$sign_identity" == "-" ]]; then
  codesign --force --sign - --timestamp=none --requirements '=designated => identifier "local.kkvoice.remote-helper"' "$contents/Resources/KKvoiceRemoteHelper.app"
  codesign --force --sign - --timestamp=none --requirements '=designated => identifier "local.kkvoice.app"' "$app"
else
  codesign --force --options runtime --timestamp=none --sign "$sign_identity" "$contents/Resources/KKvoiceRemoteHelper.app"
  codesign --force --options runtime --timestamp=none --sign "$sign_identity" "$app"
fi

codesign --verify --deep --strict "$app"
print "Built: $app (signed with $sign_identity)"
