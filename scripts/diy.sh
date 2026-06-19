#!/usr/bin/env bash
set -euo pipefail

# diy.sh - Apply custom configurations before build
# Usage: bash diy.sh <variant>
#   variant: core | home | ultimate

VARIANT="${1:-core}"
OPENWRT_DIR="${OPENWRT_PATH:-openwrt}"
cd "$OPENWRT_DIR"

# ── Dynamic kernel version detection ──
KERNEL_VER="$(grep -E '^KERNEL_PATCHVER:=' target/linux/qualcommax/Makefile 2>/dev/null | sed 's/.*:=//;s/^[[:space:]]*//')"
KERNEL_VER="${KERNEL_VER:-6.12}"
KERNEL_CFG="target/linux/qualcommax/config-${KERNEL_VER}"
echo "Detected kernel ${KERNEL_VER} (config: ${KERNEL_CFG})"

# ── Kernel config fixes ──

# ALLOC_SKB_PAGE_FRAG_DISABLE not covered by upstream config
if ! grep -q "^CONFIG_ALLOC_SKB_PAGE_FRAG_DISABLE=" "${KERNEL_CFG}" 2>/dev/null; then
  echo "CONFIG_ALLOC_SKB_PAGE_FRAG_DISABLE=n" >> "${KERNEL_CFG}"
  echo "Added CONFIG_ALLOC_SKB_PAGE_FRAG_DISABLE=n"
fi

# sch_fq built-in for BBR
if ! grep -q '^CONFIG_NET_SCH_FQ=' "${KERNEL_CFG}" 2>/dev/null; then
  echo "CONFIG_NET_SCH_FQ=y" >> "${KERNEL_CFG}"
  echo "Set CONFIG_NET_SCH_FQ=y"
fi

# /proc/config.gz for runtime debugging
for symbol in CONFIG_IKCONFIG CONFIG_IKCONFIG_PROC; do
  if ! grep -q "^${symbol}=" "${KERNEL_CFG}" 2>/dev/null; then
    echo "${symbol}=y" >> "${KERNEL_CFG}"
    echo "Set ${symbol}=y in ${KERNEL_CFG}"
  fi
done

# ── Write build info ──
mkdir -p files/etc
cat > files/etc/excalibur_release << EOF
ExcaliburOS $VARIANT
Version: ${GITHUB_RUN_NUMBER:-0}
Date: $(date +%Y.%m.%d)
Source: ${REPO_URL:-unknown}
Branch: ${REPO_BRANCH:-unknown}
Commit: ${SOURCE_COMMIT:-unknown}
Kernel: ${KERNEL_VER}
EOF

# ── Inject Aurora theme (pinned commit) ──
rm -rf package/luci-theme-aurora
AURORA_COMMIT="4f5ef09d1523773db1314c918d48744a5c518b28"
if [ -n "${GITHUB_ENV:-}" ]; then
  echo "AURORA_COMMIT=${AURORA_COMMIT}" >> "$GITHUB_ENV"
fi
if ! git clone https://github.com/eamonxg/luci-theme-aurora package/luci-theme-aurora; then
  rm -rf package/luci-theme-aurora
  echo "ERROR: Failed to clone luci-theme-aurora" >&2
  exit 1
fi
cd package/luci-theme-aurora
git -c advice.detachedHead=false checkout "$AURORA_COMMIT"
cd "$OLDPWD" || exit 1

# ── Inject HomeProxy (home / ultimate only) ──
if [ "$VARIANT" != "core" ]; then
  echo "Injecting HomeProxy (pinned commit)"

  rm -rf \
    feeds/luci/applications/luci-app-homeproxy \
    package/feeds/luci/luci-app-homeproxy \
    package/luci-app-homeproxy

  HOMEPROXY_COMMIT="29f61caf303cd3a7051e26055dc97fdf4890e2b0"
  HOMEPROXY_MAKEFILE_SHA256="6700e5b519ca151657f3c8b67d2f067d4f45bb91337a43ca583e6386cb8d0792"
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "HOMEPROXY_COMMIT=${HOMEPROXY_COMMIT}" >> "$GITHUB_ENV"
  fi

  git clone https://github.com/immortalwrt/homeproxy package/luci-app-homeproxy
  cd package/luci-app-homeproxy
  git -c advice.detachedHead=false checkout "$HOMEPROXY_COMMIT"

  COMPUTED_SHA256="$(sha256sum Makefile 2>/dev/null | awk '{print $1}')"
  if [ "$COMPUTED_SHA256" != "$HOMEPROXY_MAKEFILE_SHA256" ]; then
    echo "ERROR: HomeProxy Makefile SHA256 mismatch!" >&2
    echo "  Expected: ${HOMEPROXY_MAKEFILE_SHA256}" >&2
    echo "  Got:      ${COMPUTED_SHA256:-<file not found>}" >&2
    exit 1
  fi
  echo "HomeProxy Makefile integrity verified (SHA256 match)"
  cd "$OLDPWD" || exit 1
fi

exit 0
