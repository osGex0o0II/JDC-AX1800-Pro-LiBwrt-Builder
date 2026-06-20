#!/bin/sh
# Set default language and theme

uci set luci.main.lang=zh_cn
uci set luci.main.mediaurlbase=/luci-static/aurora
uci commit luci

exit 0
