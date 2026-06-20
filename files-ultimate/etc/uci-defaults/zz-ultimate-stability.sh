#!/bin/sh

# Ultimate profile defaults: keep diagnostics useful while avoiding broad
# service exposure by default.
uci -q set dhcp.@dnsmasq[0].noresolv='1'
uci -q set dhcp.@dnsmasq[0].localservice='1'
uci -q set dhcp.@dnsmasq[0].ednspacket_max='1232'
uci -q set dhcp.@dnsmasq[0].dnsforwardmax='500'
uci -q set system.@system[0].log_size='256'

if uci -q show nginx >/dev/null 2>&1; then
  uci -q set nginx.global.uci_enable='true'
  uci -q delete nginx._redirect2ssl
  uci -q delete nginx._lan
  uci -q set nginx._lan='server'
  uci -q set nginx._lan.server_name='_lan'
  uci -q add_list nginx._lan.listen='80 default_server'
  uci -q add_list nginx._lan.listen='[::]:80 default_server'
  uci -q add_list nginx._lan.include='conf.d/*.locations'
  uci -q set nginx._lan.access_log='off; # logd openwrt'
  uci commit nginx
fi

uci commit dhcp
uci commit system

[ -x /etc/init.d/ttyd ] && /etc/init.d/ttyd disable 2>/dev/null || true
[ -x /etc/init.d/ttyd ] && /etc/init.d/ttyd stop 2>/dev/null || true
[ -x /etc/init.d/aria2 ] && /etc/init.d/aria2 disable 2>/dev/null || true
[ -x /etc/init.d/aria2 ] && /etc/init.d/aria2 stop 2>/dev/null || true
[ -x /etc/init.d/uhttpd ] && /etc/init.d/uhttpd disable 2>/dev/null || true
[ -x /etc/init.d/uhttpd ] && /etc/init.d/uhttpd stop 2>/dev/null || true
[ -x /etc/init.d/quickfile ] && /etc/init.d/quickfile enable 2>/dev/null || true
[ -x /etc/init.d/quickfile ] && /etc/init.d/quickfile restart 2>/dev/null || true
[ -x /etc/init.d/nginx ] && /etc/init.d/nginx enable 2>/dev/null || true
[ -x /etc/init.d/nginx ] && /etc/init.d/nginx restart 2>/dev/null || true

exit 0
