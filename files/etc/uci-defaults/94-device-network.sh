#!/bin/sh
# Device identity and LAN defaults. Keep LAN away from common ISP modem ranges.

uci -q set system.@system[0].hostname='JDC-AX1800-Pro'
uci -q commit system

uci -q set network.lan.ipaddr='192.168.10.1'
uci -q set network.lan.netmask='255.255.255.0'
uci -q commit network

exit 0
