#!/usr/bin/env bash
set -euo pipefail

# diy.sh - Apply custom configurations before build
# Usage: bash diy.sh [core|core-honk]

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VARIANT="${1:-core}"
case "$VARIANT" in
  core|core-honk) ;;
  *)
    echo "ERROR: unsupported variant: ${VARIANT}" >&2
    exit 64
    ;;
esac
OPENWRT_DIR="${OPENWRT_PATH:-openwrt}"
cd "$OPENWRT_DIR"

refresh_package_metadata() {
  rm -f tmp/.packageinfo tmp/.packagedeps tmp/.packageauxvars tmp/.packageusergroup tmp/.config-package.in tmp/.config-feeds.in
  rm -f tmp/info/.files-packageinfo.* tmp/info/.packageinfo-*
}

normalize_overlay_modes() {
  [ -d files/etc/uci-defaults ] && find files/etc/uci-defaults -type f -exec chmod 755 {} +
  [ -d files/etc/init.d ] && find files/etc/init.d -type f -exec chmod 755 {} +
  [ -d files/etc/hotplug.d ] && find files/etc/hotplug.d -type f -exec chmod 755 {} +
  [ -d files/usr/sbin ] && find files/usr/sbin -type f -exec chmod 755 {} +
  return 0
}

append_github_env() {
  [ -n "${GITHUB_ENV:-}" ] || return 0
  printf '%s\n' "$@" >> "$GITHUB_ENV"
}

latest_nss_firmware_symbol() {
  local makefile="feeds/nss_packages/firmware/nss-firmware/Makefile"
  [ -f "$makefile" ] || return 1
  awk '/config NSS_FIRMWARE_VERSION_[0-9_]+/ { print $2 }' "$makefile" |
    sed -E 's/^NSS_FIRMWARE_VERSION_([0-9]+)_([0-9]+)$/\1 \2 &/' |
    sort -n -k1,1 -k2,2 |
    awk 'END { print $3 }'
}

select_latest_nss_firmware() {
  local symbol full_symbol

  symbol="$(latest_nss_firmware_symbol || true)"
  [ -n "$symbol" ] || {
    echo "ERROR: failed to resolve latest NSS firmware version from nss-packages feed" >&2
    exit 1
  }
  full_symbol="CONFIG_${symbol}"

  if grep -q '^CONFIG_NSS_FIRMWARE_VERSION_[0-9_]*=y$' .config 2>/dev/null; then
    sed -i -E 's/^CONFIG_(NSS_FIRMWARE_VERSION_[0-9_]*)=y$/# CONFIG_\1 is not set/' .config
  fi
  if grep -q "^# ${full_symbol} is not set$" .config 2>/dev/null; then
    sed -i "s/^# ${full_symbol} is not set$/${full_symbol}=y/" .config
  elif grep -q "^${full_symbol}=y$" .config 2>/dev/null; then
    :
  else
    printf '%s=y\n' "$full_symbol" >> .config
  fi
  append_github_env "NSS_FIRMWARE_VERSION=${symbol#NSS_FIRMWARE_VERSION_}"
  echo "Selected latest NSS firmware ${symbol#NSS_FIRMWARE_VERSION_}"
}

dts_node_is_disabled() {
  local dts="$1"
  local node="$2"

  awk -v node="&${node}" '
    $0 == node " {" { in_node = 1; next }
    in_node && /status = "disabled";/ { found = 1 }
    in_node && /^};$/ { in_node = 0 }
    END { exit !found }
  ' "$dts"
}

patch_wired_only_dts() {
  local dts="target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/ipq6000-re-ss-01.dts"
  local target_mk="target/linux/qualcommax/Makefile"

  [ -f "$dts" ] || {
    echo "ERROR: JDCloud RE-SS-01 DTS not found" >&2
    exit 1
  }
  [ -f "$target_mk" ] || {
    echo "ERROR: qualcommax target Makefile not found" >&2
    exit 1
  }

  # Avoid the LuCI collection pulling luci-app-package-manager back in via
  # DEFAULT_PACKAGES; core.config explicitly includes the needed LuCI parts.
  python3 "$SCRIPT_DIR/remove-default-luci.py" "$target_mk" "include/target.mk"

  # The Chinese defaults depend transitively on the full luci collection.
  # Narrow default-settings to luci-base while keeping default-settings-chn.
  local default_settings_mk="package/emortal/default-settings/Makefile"
  if [ ! -f "$default_settings_mk" ]; then
    echo "ERROR: expected default-settings recipe is missing" >&2
    exit 1
  fi
  if ! grep -Fxq '  DEPENDS:=+luci' "$default_settings_mk"; then
    echo "ERROR: upstream default-settings LuCI dependency changed; review before building" >&2
    exit 1
  fi
  sed -i 's/DEPENDS:=+luci/DEPENDS:=+luci-base/' "$default_settings_mk"
  grep -Fxq '  DEPENDS:=+luci-base' "$default_settings_mk" || {
    echo "ERROR: unable to retain minimal default-settings LuCI dependency" >&2
    exit 1
  }
  echo "Retained default-settings-chn without pulling the luci collection"

  sed -i '/^[[:space:]]*kmod-qca-nss-drv-vxlanmgr \\/s/[[:space:]]*\\$/ /' "$target_mk"
  sed -i '/^[[:space:]]*kmod-qca-nss-drv-wifi-meshmgr[[:space:]]*$/d' "$target_mk"

  for node in wifi q6v5_wcss q6_region q6_etr_region m3_dump_region; do
    if ! dts_node_is_disabled "$dts" "$node"; then
      cat >> "$dts" <<EOF

&${node} {
	status = "disabled";
};
EOF
    fi
    dts_node_is_disabled "$dts" "$node" || {
      echo "ERROR: failed to disable ${node} in JDCloud DTS" >&2
      exit 1
    }
  done

  ! grep -Fq 'kmod-qca-nss-drv-wifi-meshmgr' "$target_mk" || {
    echo "ERROR: NSS Wi-Fi mesh manager remains in target defaults" >&2
    exit 1
  }
  grep -Fq '#include "ipq6018-nss.dtsi"' "$dts" || {
    echo "ERROR: JDCloud DTS no longer includes the NSS device tree" >&2
    exit 1
  }
  "$SCRIPT_DIR/verify-ipq6018-nss-region.sh" "target/linux/qualcommax/patches-${KERNEL_VER}"
}

# -- Dynamic kernel version detection --
KERNEL_VER="$(grep -E '^KERNEL_PATCHVER:=' target/linux/qualcommax/Makefile 2>/dev/null | sed 's/.*:=//;s/^[[:space:]]*//')"
KERNEL_VER="${KERNEL_VER:-6.12}"
KERNEL_CFG="target/linux/qualcommax/config-${KERNEL_VER}"
echo "Detected kernel ${KERNEL_VER} (config: ${KERNEL_CFG})"
normalize_overlay_modes
patch_wired_only_dts
select_latest_nss_firmware

# The retail AX1800 Pro layout seen on QWRT/iStoreOS uses 12 MiB HLOS slots
# and reports board id jdcloud,ax1800-pro. LiBwrt's RE-SS-01 recipe is the
# closest DTS match, but its default 6 MiB kernel slot is too small for 6.12 NSS.
JDC_IMAGE_MK="target/linux/qualcommax/image/ipq60xx.mk"
if [ -f "$JDC_IMAGE_MK" ]; then
  compat_present="$(awk '
    /^define Device\/jdcloud_re-ss-01$/ { in_device = 1 }
    in_device && /SUPPORTED_DEVICES \+= jdcloud,ax1800-pro/ { found = 1 }
    /^endef$/ && in_device { in_device = 0 }
    END { print found + 0 }
  ' "$JDC_IMAGE_MK")"
  tmp_image_mk="$(mktemp)"
  awk -v compat_seen="$compat_present" '
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
    in_device { gsub(/ipq-wifi-jdcloud_re-ss-01/, ""); sub(/[[:space:]]+$/, "") }
    in_device && /^[[:space:]]*DEVICE_PACKAGES :=/ {
      if ($0 !~ /(^|[[:space:]])-luci([[:space:]]|$)/) {
        $0 = $0 " -luci"
      }
    }
    in_device && /^[[:space:]]*IMAGE\/factory\.bin :=/ {
      next
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
    in_device && /ipq-wifi-jdcloud_re-ss-01/ { wifi_package_present = 1 }
    in_device && /(^|[[:space:]])-luci([[:space:]]|$)/ { luci_collection_excluded = 1 }
    in_device && /IMAGE\/factory\.bin :=/ { factory_present = 1 }
    /^endef$/ && in_device { in_device = 0 }
    END { exit !(kernel_ok && compat_ok && luci_collection_excluded && !wifi_package_present && !factory_present) }
  ' "$JDC_IMAGE_MK" || {
    echo "ERROR: JDCloud AX1800 Pro image recipe verification failed" >&2
    exit 1
  }
  echo "Patched JDCloud RE-SS-01 image recipe for AX1800 Pro 12MiB HLOS layout"
fi

# -- Kernel config fixes --

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

sed -i \
  -e '/^CONFIG_QCOM_Q6V5_WCSS=/d' \
  -e '/^# CONFIG_QCOM_Q6V5_WCSS is not set$/d' \
  "${KERNEL_CFG}"
echo "# CONFIG_QCOM_Q6V5_WCSS is not set" >> "${KERNEL_CFG}"

# -- Write build info --
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

bash "$SCRIPT_DIR/apply-package-updates.sh"
bash "$SCRIPT_DIR/install-variant-packages.sh" "$VARIANT"
refresh_package_metadata
