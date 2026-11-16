#!/bin/zsh
set -euo pipefail
root="${0:A:h:h}"
cd "$root"
"$root/Scripts/build-helper.sh"
swift build -c release
app="$root/dist/KKvoice.app"
contents="$app/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources"
cp "$root/.build/release/KKvoice" "$contents/MacOS/KKvoice"
cp "$root/Native/Info.plist" "$contents/Info.plist"
cp "$root/Native/Assets/KKvoice.icns" "$contents/Resources/KKvoice.icns"
cp "$root/Native/Assets/KKvoice-logo.png" "$contents/Resources/KKvoice-logo.png"
ditto "$root/.build/KKvoiceRemoteHelper.app" "$contents/Resources/KKvoiceRemoteHelper.app"
codesign --force --sign - --timestamp=none --requirements '=designated => identifier "local.kkvoice.app"' "$app"
codesign --verify --deep --strict "$app"
print "Built: $app"
