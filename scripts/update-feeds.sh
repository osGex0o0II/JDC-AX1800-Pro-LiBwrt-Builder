#!/bin/bash
# update-feeds.sh - Update and install feeds for ExcaliburOS build

OPENWRT_DIR="${OPENWRT_PATH:-openwrt}"
cd "$OPENWRT_DIR" || exit 1

./scripts/feeds update -a
./scripts/feeds install -a

echo "Feeds updated"
exit 0
