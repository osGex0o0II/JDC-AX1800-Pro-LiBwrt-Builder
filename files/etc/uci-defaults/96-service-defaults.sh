#!/bin/sh

# Keep NSS as the primary acceleration path. Software flow offloading can
# compete with NSS packet handling on ipq60xx builds.
uci -q set firewall.@defaults[0].flow_offloading='0'
uci -q set firewall.@defaults[0].flow_offloading_hw='0'
uci commit firewall

uci -q set network.globals.packet_steering='0'
uci commit network

# TTYD is useful for recovery, but should not listen until explicitly enabled.
[ -x /etc/init.d/ttyd ] && /etc/init.d/ttyd disable 2>/dev/null || true
[ -x /etc/init.d/ttyd ] && /etc/init.d/ttyd stop 2>/dev/null || true

# QuickFile-Go remains available on LAN, while its built-in terminal is off by
# default because it is the highest-risk file manager capability.
if uci -q show quickfile-go >/dev/null 2>&1; then
  uci -q set quickfile-go.main.enabled='1'
  uci -q set quickfile-go.main.listen_addr='auto'
  uci -q set quickfile-go.main.enable_terminal='0'
  uci -q commit quickfile-go
fi

[ -x /etc/init.d/uhttpd ] && /etc/init.d/uhttpd enable 2>/dev/null || true
[ -x /etc/init.d/uhttpd ] && /etc/init.d/uhttpd restart 2>/dev/null || true
[ -x /etc/init.d/quickfile-go ] && /etc/init.d/quickfile-go enable 2>/dev/null || true
[ -x /etc/init.d/quickfile-go ] && /etc/init.d/quickfile-go restart 2>/dev/null || true

exit 0
