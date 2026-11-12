#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

tmp=$(mktemp -d)
trap 'rm -r "$tmp"' EXIT

bash scripts/configure-variant.sh core > "$tmp/core"
bash scripts/configure-variant.sh core-honk > "$tmp/honk"
for variant in core honk; do
  grep -Fxq 'CONFIG_PACKAGE_luci-app-gecoosac=y' "$tmp/$variant"
  grep -Fxq 'CONFIG_PACKAGE_mtr-nojson=y' "$tmp/$variant"
  grep -Fxq 'CONFIG_IPQ_MEM_PROFILE_512=y' "$tmp/$variant"
done
grep -Fxq 'CONFIG_PACKAGE_luci-app-homeproxy=y' "$tmp/core"
! grep -Fxq 'CONFIG_PACKAGE_honk=y' "$tmp/core" || exit 1
grep -Fxq 'CONFIG_PACKAGE_honk=y' "$tmp/honk"
grep -Fxq 'CONFIG_KERNEL_DEBUG_INFO_BTF=y' "$tmp/honk"
! grep -Eq '^CONFIG_PACKAGE_(luci-app-homeproxy|sing-box)=y$' "$tmp/honk" || exit 1
! bash scripts/configure-variant.sh wrong || exit 1

cat > "$tmp/shared-manifest" <<'EOF'
luci-theme-aurora - 1.4.0-r20260920
gecoosac - 2.2.20251015-r1
luci-app-gecoosac - 20261016-r1
luci-i18n-gecoosac-zh-cn - 20261016-r1
luci-app-wol - test
etherwake - test
luci-app-autoreboot - test
mtr-nojson - 0.95-r3
luci-app-zerotier - test
luci-app-ttyd - test
luci-app-upnp - test
luci-app-samba4 - test
samba4-server - 4.22.11-r1
luci-app-diskman - test
dropbear - 2026.94-r3
openssh-sftp-server - 10.6_p2-r1
miniupnpd-nftables - 2.3.11-r1
libnftnl11 - 1.3.2-r1
nftables-json - 1.1.7-r1
EOF
cp "$tmp/shared-manifest" "$tmp/core-manifest"
cat >> "$tmp/core-manifest" <<'EOF'
luci-app-homeproxy - 20261026-r3
luci-i18n-homeproxy-zh-cn - test
sing-box - 1.15.0_alpha13-r1
kmod-nft-socket - test
kmod-nft-tproxy - test
EOF
bash scripts/verify-variant.sh core manifest "$tmp/core-manifest"
sed 's/4\.22\.11-r1/4.22.7-r3/' "$tmp/core-manifest" > "$tmp/old-samba"
! bash scripts/verify-variant.sh core manifest "$tmp/old-samba" || exit 1

cp "$tmp/shared-manifest" "$tmp/honk-manifest"
cat >> "$tmp/honk-manifest" <<'EOF'
honk - 0.1.0_beta6-r1
kmod-veth - test
kmod-sched-core - test
kmod-sched-bpf - test
kmod-nft-queue - test
kmod-nfnetlink-queue - test
kmod-nf-conntrack - test
v2ray-geoip - test
v2ray-geosite - test
EOF
bash scripts/verify-variant.sh core-honk manifest "$tmp/honk-manifest"
printf '%s\n' 'sing-box - 1.15.0_alpha13-r1' >> "$tmp/honk-manifest"
! bash scripts/verify-variant.sh core-honk manifest "$tmp/honk-manifest" || exit 1

mkdir -p "$tmp/tree/scripts"
cat > "$tmp/tree/scripts/feeds" <<'EOF'
#!/bin/sh
printf '%s\n' "$1" >> "$LOG"
[ "$1" != "$FAIL_STEP" ]
EOF
chmod +x "$tmp/tree/scripts/feeds"
export LOG="$tmp/log" OPENWRT_PATH="$tmp/tree"
export FAIL_STEP=update
! bash scripts/update-feeds.sh || exit 1
[[ $(cat "$LOG") == update ]]
export FAIL_STEP=install
: > "$LOG"
mkdir -p "$tmp/bin"
cat > "$tmp/bin/git" <<'EOF'
#!/bin/sh
name=${2##*/}
awk -v name="$name" '$2 == name { sub(/^.*\^/, "", $3); print $3 }' feeds.conf
EOF
chmod +x "$tmp/bin/git"
export PATH="$tmp/bin:$PATH"
! bash scripts/update-feeds.sh || exit 1
[[ $(cat "$LOG") == $'update\ninstall' ]]

mkdir -p "$tmp/image/sysupgrade-jdcloud_re-ss-01"
cd "$tmp/image"
printf 'board=jdcloud_re-ss-01\n' > sysupgrade-jdcloud_re-ss-01/CONTROL
printf 'fake kernel\n' > sysupgrade-jdcloud_re-ss-01/kernel
printf 'fake squashfs\n' > sysupgrade-jdcloud_re-ss-01/root
tar -cf "$tmp/sysupgrade.bin" sysupgrade-jdcloud_re-ss-01
cd - >/dev/null
bash scripts/verify-image.sh "$tmp/sysupgrade.bin"
dd if=/dev/zero of="$tmp/image/sysupgrade-jdcloud_re-ss-01/kernel" bs=1048576 count=13 status=none
tar -cf "$tmp/oversize.bin" -C "$tmp/image" sysupgrade-jdcloud_re-ss-01
! bash scripts/verify-image.sh "$tmp/oversize.bin" || exit 1

printf '%s\n' 'build contracts: passed'
