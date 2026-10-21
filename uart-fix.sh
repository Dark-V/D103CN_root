#!/bin/sh
# Run in the STOCK root shell after the first successful FEL bootstrap.
set -eu
umask 077
conf=/data/config/miio/device.conf
old='sh<>/dev/ttyS0>&0&'
new='mkdir /tmp/d103-uart 2>/dev/null && setsid /sbin/getty -n -l /bin/sh -L 115200 ttyS0 &'
[ "$(id -u)" = 0 ] || { echo 'root required' >&2; exit 1; }
[ -f "$conf" ] && [ ! -L "$conf" ] || { echo 'unexpected config' >&2; exit 1; }
grep -qx 'model=xiaomi.vacuum.d103cn' "$conf" || { echo 'not D103CN' >&2; exit 1; }
if grep -Fqx "$new" "$conf"; then
    echo 'UART_FIX_ALREADY_PRESENT; no changes.'
    exit 0
fi
grep -Fqx "$old" "$conf" || { echo 'original UART hook missing; no changes' >&2; exit 1; }
command -v setsid >/dev/null
[ -x /sbin/getty ]
[ -e "$conf.uart-bak" ] || cp -p "$conf" "$conf.uart-bak"
tmp=$(mktemp /data/config/miio/.uart-fix.XXXXXX)
trap 'rm -f "$tmp"' EXIT HUP INT TERM
cp -p "$conf" "$tmp"
awk -v old="$old" -v new="$new" '$0==old {print new; found++; next} {print} END {if(found!=1)exit 1}' "$conf" >"$tmp"
grep -Fqx "$new" "$tmp"
mv -f "$tmp" "$conf"
sync
echo 'UART_FIX_OK. Reboot normally to remove old competing shells; then verify id.'
