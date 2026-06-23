#!/bin/sh

# QuickFile uses nginx to proxy a Unix socket under LuCI. Use nginx as the
# web entrypoint, but keep the QuickFile backend disabled until a LuCI page
# opens a short-lived session.
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
  uci -q commit nginx
fi

QUICKFILE_LOCATIONS="/etc/nginx/conf.d/quickfile.locations"
if [ -f "$QUICKFILE_LOCATIONS" ]; then
  if grep -q ' /mnt/mmcblk0p24 ' /proc/mounts 2>/dev/null; then
    QUICKFILE_TMP="/mnt/mmcblk0p24/quickfile_tmp"
  else
    QUICKFILE_TMP="/tmp/quickfile_tmp"
  fi

  mkdir -p "$QUICKFILE_TMP"
  chmod 1777 "$QUICKFILE_TMP" 2>/dev/null || true

  sed -i \
    "s|^[#[:space:]]*client_body_temp_path .*|client_body_temp_path ${QUICKFILE_TMP};|" \
    "$QUICKFILE_LOCATIONS"
fi

[ -x /etc/init.d/uhttpd ] && /etc/init.d/uhttpd disable 2>/dev/null || true
[ -x /etc/init.d/uhttpd ] && /etc/init.d/uhttpd stop 2>/dev/null || true
[ -x /etc/init.d/quickfile ] && /etc/init.d/quickfile disable 2>/dev/null || true
[ -x /etc/init.d/quickfile ] && /etc/init.d/quickfile stop 2>/dev/null || true
[ -x /etc/init.d/nginx ] && /etc/init.d/nginx enable 2>/dev/null || true
[ -x /etc/init.d/nginx ] && /etc/init.d/nginx restart 2>/dev/null || true

exit 0
