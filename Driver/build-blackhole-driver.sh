#!/bin/zsh
set -euo pipefail

root="${0:A:h:h}"
BLACKHOLE_TAG="${BLACKHOLE_TAG:-v0.6.1}"
BLACKHOLE_VERSION="${BLACKHOLE_TAG#v}"
BLACKHOLE_REPO="https://github.com/ExistentialAudio/BlackHole.git"
BUNDLE_ID="local.kkvoice.mic.driver"
PLUGIN_FACTORY_UUID="813EAA21-8D32-4A84-86D7-5C8C68D8F078"

src_dir="$root/.build/BlackHole"
build_dir="$root/.build/blackhole-build"
output="$root/.build/KKvoiceMic.driver"

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

if ! command -v xcodebuild >/dev/null 2>&1 || ! xcodebuild -version >/dev/null 2>&1; then
  print -u2 "Error: full Xcode (xcodebuild) is required to build KKvoiceMic.driver from BlackHole source."
  print -u2 "Command Line Tools alone cannot build Xcode bundle targets. Select Xcode with: sudo xcode-select -s /Applications/Xcode.app"
  exit 1
fi

mkdir -p "$root/.build"

fetch_blackhole_source() {
  local target_dir="$1"
  /bin/rm -rf "$target_dir"

  local proxy_env=()
  if [[ -z "${HTTPS_PROXY:-}" && -z "${https_proxy:-}" ]]; then
    local sc_info
    sc_info="$(scutil --proxy 2>/dev/null || true)"
    if [[ "$sc_info" == *"HTTPEnable : 1"* ]]; then
      local host port
      host="$(print -r -- "$sc_info" | awk '/HTTPProxy :/ {print $3; exit}')"
      port="$(print -r -- "$sc_info" | awk '/HTTPPort :/ {print $3; exit}')"
      if [[ -n "$host" && -n "$port" ]]; then
        proxy_env=("HTTP_PROXY=http://${host}:${port}" "HTTPS_PROXY=http://${host}:${port}")
      fi
    fi
  fi

  if env "${proxy_env[@]}" git clone --depth 1 --branch "$BLACKHOLE_TAG" "$BLACKHOLE_REPO" "$target_dir" >/dev/null 2>&1; then
    return 0
  fi

  print "git clone did not complete directly; fetching $BLACKHOLE_TAG release archive..."
  /bin/rm -rf "$target_dir"
  mkdir -p "$target_dir"
  local archive="$root/.build/BlackHole-${BLACKHOLE_TAG}.tar.gz"
  if command -v gh >/dev/null 2>&1 && gh api "repos/ExistentialAudio/BlackHole/tarball/${BLACKHOLE_TAG}" > "$archive" 2>/dev/null; then
    tar -xzf "$archive" -C "$target_dir" --strip-components=1
    /bin/rm -f "$archive"
    return 0
  fi

  env "${proxy_env[@]}" curl -fsSL "https://github.com/ExistentialAudio/BlackHole/archive/refs/tags/${BLACKHOLE_TAG}.tar.gz" -o "$archive"
  tar -xzf "$archive" -C "$target_dir" --strip-components=1
  /bin/rm -f "$archive"
}

if [[ ! -d "$src_dir/BlackHole.xcodeproj" ]] || [[ "$(tr -d '[:space:]' < "$src_dir/VERSION" 2>/dev/null || true)" != "$BLACKHOLE_VERSION" ]]; then
  print "Fetching BlackHole $BLACKHOLE_TAG into $src_dir..."
  fetch_blackhole_source "$src_dir"
fi

# Patch TransportType from kAudioDeviceTransportTypeVirtual ('virt') to kAudioDeviceTransportTypeUSB ('usb ')
# so AVCaptureDevice-based speech apps (e.g. Doubao Input Method) discover KKvoice Mic as a selectable microphone.
blackhole_c="$src_dir/BlackHole/BlackHole.c"
if grep -q "kAudioDeviceTransportTypeVirtual" "$blackhole_c"; then
  /usr/bin/sed -i '' 's/kAudioDeviceTransportTypeVirtual/kAudioDeviceTransportTypeUSB/g' "$blackhole_c"
fi
grep -q "kAudioDeviceTransportTypeUSB" "$blackhole_c" || {
  print -u2 "Error: failed to patch kAudioDeviceTransportTypeUSB in $blackhole_c"
  exit 1
}

/bin/rm -rf "$build_dir" "$output"

print "Building KKvoiceMic.driver from BlackHole $BLACKHOLE_TAG..."
xcodebuild \
  -project "$src_dir/BlackHole.xcodeproj" \
  -target BlackHole \
  -configuration Release \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  MACOSX_DEPLOYMENT_TARGET=12.0 \
  CONFIGURATION_BUILD_DIR="$build_dir" \
  PRODUCT_BUNDLE_IDENTIFIER="$BUNDLE_ID" \
  CODE_SIGNING_ALLOWED=NO \
  GCC_PREPROCESSOR_DEFINITIONS='$(inherited) DEBUG=0 kNumber_Of_Channels=2 kSampleRates=48000 kPlugIn_BundleID=\"local.kkvoice.mic.driver\" kDriver_Name=\"KKvoiceMi\" kDevice_Name=\"KKvoice\ Mic\" kDevice2_Name=\"KKvoice\ Mic\ 2\"' \
  >/dev/null

ditto "$build_dir/BlackHole.driver" "$output"
/bin/rm -rf "$build_dir"

plist="$output/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $BUNDLE_ID" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleName KKvoice Mic" "$plist"
/usr/libexec/PlistBuddy -c "Delete :CFPlugInFactories:e395c745-4eea-4d94-bb92-46224221047c" "$plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Delete :CFPlugInFactories:$PLUGIN_FACTORY_UUID" "$plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :CFPlugInFactories:$PLUGIN_FACTORY_UUID string BlackHole_Create" "$plist"
/usr/libexec/PlistBuddy -c "Set :CFPlugInTypes:443ABAB8-E7B3-491A-B985-BEB9187030DB:0 $PLUGIN_FACTORY_UUID" "$plist"
/usr/libexec/PlistBuddy -c "Delete :KKvoiceBuildSource" "$plist" 2>/dev/null || true
/usr/libexec/PlistBuddy -c "Add :KKvoiceBuildSource string ExistentialAudio/BlackHole@${BLACKHOLE_TAG}" "$plist"

if [[ -f "$root/Driver/LICENSES/BlackHole-GPL-3.0.txt" ]]; then
  cp "$root/Driver/LICENSES/BlackHole-GPL-3.0.txt" "$output/Contents/Resources/LICENSE"
fi

sign_identity="$(resolve_codesign_identity)"
if [[ "$sign_identity" == "-" ]]; then
  codesign --force --deep --sign - --timestamp=none "$output"
else
  codesign --force --deep --options runtime --timestamp=none --sign "$sign_identity" "$output"
fi
codesign --verify --deep --strict "$output"

print "Built $output (from BlackHole $BLACKHOLE_TAG, signed with $sign_identity)"
