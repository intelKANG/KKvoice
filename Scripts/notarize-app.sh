#!/bin/zsh
set -euo pipefail
root="${0:A:h:h}"
cd "$root"

# Verify Developer ID Application identity is installed in Keychain
dev_id="$(security find-identity -v -p codesigning 2>/dev/null | awk '/"Developer ID Application:/ {print $2; exit}')"
if [[ -z "$dev_id" ]]; then
  print -u2 "Error: 未在钥匙串中找到 Developer ID Application 证书。"
  print -u2 "请在 Xcode -> Settings -> Accounts -> Manage Certificates 中点击 + 创建 Developer ID Application 证书后重试。"
  exit 1
fi

profile="${NOTARY_PROFILE:-AppleNotary}"
if ! xcrun notarytool history --keychain-profile "$profile" >/dev/null 2>&1; then
  if xcrun notarytool history --keychain-profile "KKvoiceNotary" >/dev/null 2>&1; then
    profile="KKvoiceNotary"
  else
    print -u2 "Error: 未找到 notarytool 凭据配置 '$profile'。"
    print -u2 "请先执行一次："
    print -u2 "  xcrun notarytool store-credentials \"AppleNotary\" --apple-id \"你的AppleID\" --team-id \"AR7E4MUM8B\" --password \"App专用密码\""
    exit 1
  fi
fi

CODESIGN_IDENTITY="$dev_id" CODESIGN_TIMESTAMP=1 "$root/Scripts/build-app.sh"

app="$root/dist/KKvoice.app"
zip_path="$root/dist/KKvoice.app.zip"
/bin/rm -f "$zip_path"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip_path"

print "Submitting $zip_path to Apple Notarization..."
xcrun notarytool submit "$zip_path" --keychain-profile "$profile" --wait

print "Stapling notarization ticket to $app..."
xcrun stapler staple "$app"
xcrun stapler validate "$app"

/bin/rm -f "$zip_path"
ditto -c -k --sequesterRsrc --keepParent "$app" "$zip_path"
spctl -a -vvv -t exec "$app"
print "Notarized & ready: $zip_path"
