#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/deps/firmware.env"

variant=${1:?firmware variant required}
case $variant in core|core-honk) ;; *) exit 64 ;; esac

packages=(gecoosac luci-app-gecoosac)
if [[ $variant == core ]]; then
  rm -f package/feeds/luci/luci-app-homeproxy package/feeds/packages/sing-box \
    package/feeds/packages/sing-box-tiny
  packages+=(luci-app-homeproxy sing-box)
fi
./scripts/feeds install -f -p vikingfy "${packages[@]}"
for pkg in "${packages[@]}"; do
  [[ $(readlink -f "package/feeds/vikingfy/$pkg") == "$(pwd)/feeds/vikingfy/$pkg" ]]
done
grep -Fxq "PKG_VERSION:=$GECOOSAC_VERSION" feeds/vikingfy/gecoosac/Makefile
grep -Fxq "PKG_VERSION:=$GECOOSAC_LUCI_VERSION" feeds/vikingfy/luci-app-gecoosac/Makefile
grep -Eq "^[[:space:]]*option enabled '0'$" feeds/vikingfy/luci-app-gecoosac/root/etc/config/gecoosac

git -c advice.detachedHead=false clone --depth 1 --branch "$AURORA_TAG" \
  https://github.com/eamonxg/luci-theme-aurora.git package/luci-theme-aurora
[[ $(git -C package/luci-theme-aurora rev-parse HEAD) == "$AURORA_COMMIT" ]]

if [[ $variant == core ]]; then
  grep -Fxq "PKG_UPSTREAM_VERSION:=$SING_BOX_VERSION" feeds/vikingfy/sing-box/Makefile
  grep -Fxq "PKG_VERSION:=${HOMEPROXY_VERSION%-r*}" feeds/vikingfy/luci-app-homeproxy/Makefile
  grep -Fxq "PKG_RELEASE:=${HOMEPROXY_VERSION##*-r}" feeds/vikingfy/luci-app-homeproxy/Makefile
  grep -q '^LUCI_EXTRA_DEPENDS:=sing-box (>=' feeds/vikingfy/luci-app-homeproxy/Makefile
else
  test -f target/linux/qualcommax/ipq60xx/target.mk
  cp -a "$root/package/honk" package/honk
fi
