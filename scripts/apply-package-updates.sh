#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/deps/firmware.env"

tmp=$(mktemp -d)
trap 'rm -rf -- "$tmp"' EXIT

checkout_recipes() {
  local checkout=$1 url=$2 commit=$3
  shift 3
  git init -q "$checkout"
  git -C "$checkout" remote add origin "$url"
  git -C "$checkout" sparse-checkout set --cone "$@"
  git -C "$checkout" fetch --quiet --depth=1 --filter=blob:none origin "$commit"
  git -C "$checkout" checkout --quiet --detach FETCH_HEAD
  [[ $(git -C "$checkout" rev-parse HEAD) == "$commit" ]]
}

replace_recipe() {
  local source=$1 destination=$2 expected=$3
  grep -Fxq "PKG_VERSION:=$expected" "$source/Makefile"
  test -f "$destination/Makefile"
  mv -- "$destination" "$tmp/original-$(basename "$destination")"
  cp -a -- "$source" "$destination"
}

checkout_recipes "$tmp/packages" https://github.com/immortalwrt/packages.git \
  "$PACKAGE_UPDATES_COMMIT" net/openssh net/miniupnpd
checkout_recipes "$tmp/system" https://github.com/immortalwrt/immortalwrt.git \
  "$SYSTEM_UPDATES_COMMIT" package/network/services/dropbear package/network/utils/nftables

replace_recipe "$tmp/packages/net/openssh" feeds/packages/net/openssh 10.6_p2
replace_recipe "$tmp/packages/net/miniupnpd" feeds/packages/net/miniupnpd 2.3.11
replace_recipe "$tmp/system/package/network/services/dropbear" package/network/services/dropbear 2026.94
replace_recipe "$tmp/system/package/network/utils/nftables" package/network/utils/nftables 1.1.7

# Same-series updates retain the 25.12 feed's build and packaging patches.
samba=feeds/packages/net/samba4/Makefile
go=feeds/packages/lang/golang/golang1.26/Makefile
grep -Fxq 'PKG_VERSION:=4.22.7' "$samba"
grep -Fxq 'PKG_HASH:=12195811d4542f661536e9055b44d58c53020412beafaae205e227bf72f6a497' "$samba"
sed -i -e "s/^PKG_VERSION:=.*/PKG_VERSION:=$SAMBA_VERSION/" \
  -e 's/^PKG_RELEASE:=.*/PKG_RELEASE:=1/' \
  -e "s/^PKG_HASH:=.*/PKG_HASH:=$SAMBA_SHA256/" "$samba"
grep -Fxq 'GO_VERSION_PATCH:=10' "$go"
grep -Fxq 'PKG_HASH:=fd63e883ba2f2bfca93c1646b31ebef63e2b1e4d2b317c9789d976a68d81f36f' "$go"
sed -i -e "s/^GO_VERSION_PATCH:=.*/GO_VERSION_PATCH:=${GO_VERSION##*.}/" \
  -e "s/^PKG_HASH:=.*/PKG_HASH:=$GO_SHA256/" "$go"
