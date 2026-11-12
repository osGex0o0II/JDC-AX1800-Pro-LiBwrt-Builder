#!/usr/bin/env bash
set -euo pipefail

variant=${1:?variant required}
mode=${2:?config or manifest required}
input=${3:?input file required}
required=(luci-theme-aurora gecoosac luci-app-gecoosac luci-i18n-gecoosac-zh-cn
  luci-app-wol etherwake luci-app-autoreboot mtr-nojson luci-app-zerotier
  luci-app-ttyd luci-app-upnp luci-app-samba4 samba4-server luci-app-diskman)
forbidden=(luci-app-package-manager luci-app-quickfile-go quickfile-go sing-box-tiny)
case $variant in
  core)
    required+=(luci-app-homeproxy luci-i18n-homeproxy-zh-cn sing-box kmod-nft-socket kmod-nft-tproxy)
    forbidden+=(honk luci-app-honk)
    ;;
  core-honk)
    required+=(honk kmod-veth kmod-sched-core kmod-sched-bpf kmod-nft-queue
      kmod-nfnetlink-queue kmod-nf-conntrack v2ray-geoip v2ray-geosite)
    forbidden+=(luci-app-homeproxy luci-i18n-homeproxy-zh-cn sing-box vmlinux-btf vmlinux-btf-builtin)
    ;;
  *) exit 64 ;;
esac

fail() { printf '%s %s: %s\n' "$variant" "$mode" "$*" >&2; exit 1; }
case $mode in
  config)
    enabled() { grep -Fxq "CONFIG_PACKAGE_$1=y" "$input" || grep -Fxq "CONFIG_PACKAGE_$1=m" "$input"; }
    included() { grep -Fxq "CONFIG_PACKAGE_$1=y" "$input"; }
    if [[ $variant == core-honk ]]; then
      for symbol in DEBUG_INFO DEBUG_INFO_BTF CGROUPS CGROUP_BPF; do
        grep -Fxq "CONFIG_KERNEL_$symbol=y" "$input" || fail "CONFIG_KERNEL_$symbol must be built in"
      done
      grep -Fxq '# CONFIG_KERNEL_DEBUG_INFO_REDUCED is not set' "$input" || fail 'debug info must not be reduced'
    fi
    ;;
  manifest)
    included() { awk -v pkg="$1" '$1 == pkg && $2 == "-" { found=1 } END { exit !found }' "$input"; }
    enabled() { included "$1"; }
    expect_version() {
      awk -v pkg="$1" -v ver="$2" '$1 == pkg && $2 == "-" && $3 == ver { ok=1 } END { exit !ok }' "$input" \
        || fail "expected $1 $2"
    }
    ;;
  *) exit 64 ;;
esac

for pkg in "${required[@]}"; do included "$pkg" || fail "missing $pkg"; done
for pkg in "${forbidden[@]}"; do
  if enabled "$pkg"; then fail "unexpected $pkg"; fi
done

if [[ $mode == manifest ]]; then
  expect_version samba4-server 4.22.11-r1
  expect_version dropbear 2026.94-r3
  expect_version openssh-sftp-server 10.6_p2-r1
  expect_version miniupnpd-nftables 2.3.11-r1
  expect_version libnftnl11 1.3.2-r1
  expect_version nftables-json 1.1.7-r1
  if [[ $variant == core ]]; then
    expect_version luci-app-homeproxy 20261026-r3
    expect_version sing-box 1.15.0_alpha13-r1
  else
    expect_version honk 0.1.0_beta6-r1
  fi
fi
