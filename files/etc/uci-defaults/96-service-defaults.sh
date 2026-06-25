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

[ -x /etc/init.d/uhttpd ] && /etc/init.d/uhttpd enable 2>/dev/null || true
[ -x /etc/init.d/uhttpd ] && /etc/init.d/uhttpd restart 2>/dev/null || true
[ -x /etc/init.d/jdc-unmount-backup-rootfs ] && /etc/init.d/jdc-unmount-backup-rootfs enable 2>/dev/null || true
[ -x /usr/sbin/jdc-unmount-backup-rootfs ] && /usr/sbin/jdc-unmount-backup-rootfs 2>/dev/null || true

exit 0
