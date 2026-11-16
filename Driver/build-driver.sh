#!/bin/zsh
# LOCAL DEVELOPMENT ONLY — DO NOT USE FOR RELEASES.
# This legacy script binary-patches a locally installed vRemoteDriver.driver.
# For redistributable builds and releases, use Driver/build-blackhole-driver.sh instead.
set -euo pipefail
root="${0:A:h:h}"
source="/Library/Audio/Plug-Ins/HAL/vRemoteDriver.driver"
output="$root/.build/KKvoiceMic.driver"
[[ -d "$source" ]] || { print -u2 "Missing vRemote driver: $source"; exit 1; }
mkdir -p "$root/.build"
[[ ! -e "$output" ]] || /bin/rm -rf "$output"
ditto "$source" "$output"
python3 - "$output/Contents/MacOS/BlackHole" <<'PY'
import sys
p=sys.argv[1]
b=open(p,'rb').read()
replacements={
 b'vRemoteDr%ich_2_UID':b'KKvoiceMi%ich_2_UID',
 b'vRemoteDr%ich_ModelUID':b'KKvoiceMi%ich_ModelUID',
 b'vRemoteDr%ich_UID':b'KKvoiceMi%ich_UID',
 b'vRemoteDr %ich 2':b'KKvoice Mic 2   ',
 b'vRemoteDr %ich':b'KKvoice Mic   ',
 b'vRemoteDr Box':b'KKvoice Box  ',
 b'audio.local.vRemoteDriver2chXX':b'audio.local.KKvoiceMicDriverXX',
}
for old,new in replacements.items():
 expected = 8 if old.startswith(b'audio.local.') else 2
 assert len(new)==len(old) and b.count(old+b'\0')==expected, (old,b.count(old+b'\0'))
 b=b.replace(old+b'\0',new+b'\0')
open(p,'wb').write(b)
PY
plist="$output/Contents/Info.plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier audio.local.KKvoiceMicDriverXX' "$plist"
/usr/libexec/PlistBuddy -c 'Set :CFBundleName KKvoice Mic' "$plist"
/usr/libexec/PlistBuddy -c 'Delete :CFPlugInFactories:B7C4C615-9E72-4C83-A329-71C4E50E4A91' "$plist"
/usr/libexec/PlistBuddy -c 'Add :CFPlugInFactories:813EAA21-8D32-4A84-86D7-5C8C68D8F078 string BlackHole_Create' "$plist"
/usr/libexec/PlistBuddy -c 'Set :CFPlugInTypes:443ABAB8-E7B3-491A-B985-BEB9187030DB:0 813EAA21-8D32-4A84-86D7-5C8C68D8F078' "$plist"
codesign --force --deep --sign - --timestamp=none "$output"
codesign --verify --deep --strict "$output"
print "Built $output"
