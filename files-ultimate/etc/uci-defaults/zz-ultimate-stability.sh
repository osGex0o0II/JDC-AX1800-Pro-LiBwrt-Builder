#!/bin/sh

# Ultimate profile defaults: keep diagnostics useful while avoiding broad
# service exposure by default.
uci -q set dhcp.@dnsmasq[0].noresolv='1'
uci -q set dhcp.@dnsmasq[0].localservice='1'
uci -q set dhcp.@dnsmasq[0].ednspacket_max='1232'
uci -q set dhcp.@dnsmasq[0].dnsforwardmax='500'
uci -q set system.@system[0].log_size='256'

uci commit dhcp
uci commit system

[ -x /etc/init.d/ttyd ] && /etc/init.d/ttyd disable 2>/dev/null || true
[ -x /etc/init.d/ttyd ] && /etc/init.d/ttyd stop 2>/dev/null || true
[ -x /etc/init.d/aria2 ] && /etc/init.d/aria2 disable 2>/dev/null || true
[ -x /etc/init.d/aria2 ] && /etc/init.d/aria2 stop 2>/dev/null || true

CRON_FILE="/etc/crontabs/root"
CRON_LINE="*/5 * * * * MIN_MEM_KB=65536 /usr/sbin/excalibur-healthcheck >/dev/null 2>&1"
mkdir -p /etc/crontabs
touch "$CRON_FILE"
grep -Fxq "$CRON_LINE" "$CRON_FILE" 2>/dev/null || echo "$CRON_LINE" >> "$CRON_FILE"

[ -x /etc/init.d/cron ] && /etc/init.d/cron enable 2>/dev/null || true
[ -x /etc/init.d/cron ] && /etc/init.d/cron restart 2>/dev/null || true

exit 0
