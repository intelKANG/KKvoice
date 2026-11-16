#!/bin/zsh
set -euo pipefail
root="${0:A:h:h}"
source="$root/.build/KKvoiceMic.driver"
destination="/Library/Audio/Plug-Ins/HAL/KKvoiceMic.driver"
[[ -d "$source" ]] || { print -u2 "Build the driver first: $source"; exit 1; }
stage=$(/usr/bin/mktemp -d /tmp/kkvoice-driver.XXXXXXXX)
trap '/bin/rm -rf "$stage"' EXIT
/bin/chmod 755 "$stage"
/usr/bin/ditto "$source" "$stage/KKvoiceMic.driver"
backup="${destination}.previous-$(/bin/date +%Y%m%d%H%M%S)"
if [[ -e "$destination" ]]; then
  command="/bin/mv '$destination' '$backup' && /usr/bin/ditto '$stage/KKvoiceMic.driver' '$destination' || { /bin/rm -rf '$destination'; /bin/mv '$backup' '$destination'; exit 1; }"
else
  command="/usr/bin/ditto '$stage/KKvoiceMic.driver' '$destination'"
fi
command+=" && /usr/sbin/chown -R root:wheel '$destination' && /usr/bin/find '$destination' -type d -exec /bin/chmod 755 {} \\; && /usr/bin/find '$destination' -type f -exec /bin/chmod 644 {} \\; && /bin/chmod 755 '$destination/Contents/MacOS/BlackHole' && /usr/bin/killall -9 coreaudiod"
escaped=${command//\\/\\\\}
escaped=${escaped//\"/\\\"}
osascript -e "do shell script \"$escaped\" with administrator privileges"
print "Installed: $destination"
