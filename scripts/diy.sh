#!/usr/bin/env bash
set -euo pipefail

# diy.sh - Apply custom configurations before build
# Usage: bash diy.sh <variant>
#   variant: core | core-daed | ultimate

VARIANT="${1:-core}"
OPENWRT_DIR="${OPENWRT_PATH:-openwrt}"
cd "$OPENWRT_DIR"

refresh_package_metadata() {
  rm -f tmp/.packageinfo tmp/.packagedeps tmp/.packageauxvars tmp/.packageusergroup tmp/.config-package.in tmp/.config-feeds.in
  rm -f tmp/info/.files-packageinfo.* tmp/info/.packageinfo-*
}

# ── Dynamic kernel version detection ──
KERNEL_VER="$(grep -E '^KERNEL_PATCHVER:=' target/linux/qualcommax/Makefile 2>/dev/null | sed 's/.*:=//;s/^[[:space:]]*//')"
KERNEL_VER="${KERNEL_VER:-6.12}"
KERNEL_CFG="target/linux/qualcommax/config-${KERNEL_VER}"
echo "Detected kernel ${KERNEL_VER} (config: ${KERNEL_CFG})"

# The retail AX1800 Pro layout seen on QWRT/iStoreOS uses 12 MiB HLOS slots
# and reports board id jdcloud,ax1800-pro. LiBwrt's RE-SS-01 recipe is the
# closest DTS match, but its default 6 MiB kernel slot is too small for 6.12 NSS.
JDC_IMAGE_MK="target/linux/qualcommax/image/ipq60xx.mk"
if [ -f "$JDC_IMAGE_MK" ]; then
  tmp_image_mk="$(mktemp)"
  awk '
    /^define Device\/jdcloud_re-ss-01$/ { in_device = 1 }
    in_device && /^[[:space:]]*KERNEL_SIZE :=/ {
      print "\tKERNEL_SIZE := 12288k"
      kernel_size_seen = 1
      next
    }
    in_device && /^[[:space:]]*DEVICE_PACKAGES :=/ && !compat_seen {
      print "\tSUPPORTED_DEVICES += jdcloud,ax1800-pro"
      compat_seen = 1
    }
    /^endef$/ && in_device { in_device = 0 }
    { print }
    END {
      if (!kernel_size_seen || !compat_seen) {
        exit 1
      }
    }
  ' "$JDC_IMAGE_MK" > "$tmp_image_mk" || {
    rm -f "$tmp_image_mk"
    echo "ERROR: failed to patch JDCloud RE-SS-01 image recipe" >&2
    exit 1
  }
  cat "$tmp_image_mk" > "$JDC_IMAGE_MK"
  rm -f "$tmp_image_mk"

  awk '
    /^define Device\/jdcloud_re-ss-01$/ { in_device = 1 }
    in_device && /KERNEL_SIZE := 12288k/ { kernel_ok = 1 }
    in_device && /SUPPORTED_DEVICES \+= jdcloud,ax1800-pro/ { compat_ok = 1 }
    /^endef$/ && in_device { in_device = 0 }
    END { exit !(kernel_ok && compat_ok) }
  ' "$JDC_IMAGE_MK" || {
    echo "ERROR: JDCloud AX1800 Pro image recipe verification failed" >&2
    exit 1
  }
  echo "Patched JDCloud RE-SS-01 image recipe for AX1800 Pro 12MiB HLOS layout"
fi

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
cat > files/etc/firmware_build << EOF
JDC AX1800 Pro LiBwrt $VARIANT
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

if [ "$VARIANT" = "core-daed" ]; then
  echo "Injecting luci-app-daed (pinned commit)"

  rm -rf \
    package/dae \
    package/daed \
    package/luci-app-daed \
    package/feeds/packages/dae \
    package/feeds/packages/daed \
    package/feeds/luci/luci-app-daed

  DAED_COMMIT="b2ee25e12ecadea724fa6f5b02e6c8ddd88e9119"
  DAED_MAKEFILE_SHA256="6d63d892828d9477b6a1bb5f9770149ce176625432e5b987fdb1639ce4634e14"
  LUCI_APP_DAED_MAKEFILE_SHA256="1ce969ca124fe040aa3b80b03f17b44444c9d7cda85e9a4cd7d08e794031e2f9"
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "DAED_COMMIT=${DAED_COMMIT}" >> "$GITHUB_ENV"
  fi

  mkdir -p package/dae
  git -C package/dae init
  git -C package/dae remote add origin https://github.com/QiuSimons/luci-app-daed.git
  git -C package/dae fetch --depth=1 origin "$DAED_COMMIT"
  git -C package/dae -c advice.detachedHead=false checkout FETCH_HEAD
  cd package/dae

  DAED_COMPUTED_SHA256="$(sha256sum daed/Makefile 2>/dev/null | awk '{print $1}')"
  if [ "$DAED_COMPUTED_SHA256" != "$DAED_MAKEFILE_SHA256" ]; then
    echo "ERROR: daed Makefile SHA256 mismatch!" >&2
    echo "  Expected: ${DAED_MAKEFILE_SHA256}" >&2
    echo "  Got:      ${DAED_COMPUTED_SHA256:-<file not found>}" >&2
    exit 1
  fi

  LUCI_APP_DAED_COMPUTED_SHA256="$(sha256sum luci-app-daed/Makefile 2>/dev/null | awk '{print $1}')"
  if [ "$LUCI_APP_DAED_COMPUTED_SHA256" != "$LUCI_APP_DAED_MAKEFILE_SHA256" ]; then
    echo "ERROR: luci-app-daed Makefile SHA256 mismatch!" >&2
    echo "  Expected: ${LUCI_APP_DAED_MAKEFILE_SHA256}" >&2
    echo "  Got:      ${LUCI_APP_DAED_COMPUTED_SHA256:-<file not found>}" >&2
    exit 1
  fi
  echo "daed Makefiles integrity verified (SHA256 match)"
  cd "$OLDPWD" || exit 1

  refresh_package_metadata
  exit 0
fi

# ── Inject HomeProxy ──
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

git clone https://github.com/immortalwrt/homeproxy feeds/luci/applications/luci-app-homeproxy
mkdir -p package/feeds/luci
ln -s ../../../feeds/luci/applications/luci-app-homeproxy package/feeds/luci/luci-app-homeproxy
cd feeds/luci/applications/luci-app-homeproxy
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

refresh_package_metadata
exit 0
