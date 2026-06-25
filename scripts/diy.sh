#!/usr/bin/env bash
set -euo pipefail

# diy.sh - Apply custom configurations before build
# Usage: bash diy.sh <variant>
#   variant: core | core-daede | ultimate

VARIANT="${1:-core}"
OPENWRT_DIR="${OPENWRT_PATH:-openwrt}"
cd "$OPENWRT_DIR"

refresh_package_metadata() {
  rm -f tmp/.packageinfo tmp/.packagedeps tmp/.packageauxvars tmp/.packageusergroup tmp/.config-package.in tmp/.config-feeds.in
  rm -f tmp/info/.files-packageinfo.* tmp/info/.packageinfo-*
}

require_file_sha256() {
  local path="$1"
  local expected="$2"
  local label="$3"
  local computed

  computed="$(sha256sum "$path" 2>/dev/null | awk '{print $1}')"
  if [ "$computed" != "$expected" ]; then
    echo "ERROR: ${label} SHA256 mismatch!" >&2
    echo "  Expected: ${expected}" >&2
    echo "  Got:      ${computed:-<file not found>}" >&2
    exit 1
  fi
}

normalize_overlay_modes() {
  [ -d files/etc/uci-defaults ] && find files/etc/uci-defaults -type f -exec chmod 755 {} +
  [ -d files/etc/init.d ] && find files/etc/init.d -type f -exec chmod 755 {} +
  [ -d files/etc/hotplug.d ] && find files/etc/hotplug.d -type f -exec chmod 755 {} +
  [ -d files/usr/sbin ] && find files/usr/sbin -type f -exec chmod 755 {} +
}

latest_stable_git_tag() {
  local repo="$1"
  git ls-remote --tags --refs "$repo" |
    awk '{print $2}' |
    sed 's#refs/tags/##' |
    tr -d '\r' |
    grep -E '^v[0-9]+\.[0-9]+\.[0-9]+$' |
    sort -V |
    tail -n 1
}

version_ge() {
  [ "$1" = "$2" ] || [ "$(printf '%s\n%s\n' "$2" "$1" | sort -V | head -n 1)" = "$2" ]
}

patch_sing_box_latest_stable() {
  local makefile="feeds/packages/net/sing-box/Makefile"
  local latest_tag version tarball_url tarball hash original_version
  local tar_listing tar_root sing_box_go_version golang_values openwrt_go_version

  [ -f "$makefile" ] || {
    echo "ERROR: sing-box Makefile not found at ${makefile}" >&2
    exit 1
  }

  latest_tag="$(latest_stable_git_tag https://github.com/SagerNet/sing-box.git)"
  [ -n "$latest_tag" ] || {
    echo "ERROR: failed to resolve latest stable sing-box tag" >&2
    exit 1
  }
  version="${latest_tag#v}"
  original_version="$(awk -F':=' '/^PKG_VERSION:=/ {print $2; exit}' "$makefile")"

  tarball_url="https://codeload.github.com/SagerNet/sing-box/tar.gz/${latest_tag}"
  tarball="$(mktemp)"
  if ! curl --retry 5 --retry-delay 2 --retry-all-errors -fsSL "$tarball_url" -o "$tarball"; then
    if command -v wget >/dev/null 2>&1; then
      wget -q -O "$tarball" "$tarball_url" || {
        rm -f "$tarball"
        echo "ERROR: failed to download sing-box ${latest_tag} source tarball" >&2
        exit 1
      }
    else
      rm -f "$tarball"
      echo "ERROR: failed to download sing-box ${latest_tag} source tarball" >&2
      exit 1
    fi
  fi
  if [ ! -s "$tarball" ]; then
    rm -f "$tarball"
    echo "ERROR: downloaded sing-box ${latest_tag} source tarball is empty" >&2
    exit 1
  fi
  if ! tar -tzf "$tarball" >/dev/null 2>&1; then
    rm -f "$tarball"
    echo "ERROR: downloaded sing-box ${latest_tag} source tarball is invalid" >&2
    exit 1
  fi
  tar_listing="$(tar -tzf "$tarball")"
  tar_root="${tar_listing%%/*}"
  sing_box_go_version="$(tar -xOzf "$tarball" "${tar_root}/go.mod" 2>/dev/null | awk '/^go / {print $2; exit}')"
  [ -n "$sing_box_go_version" ] || {
    rm -f "$tarball"
    echo "ERROR: failed to read sing-box ${latest_tag} go.mod Go version" >&2
    exit 1
  }
  golang_values="feeds/packages/lang/golang/golang-values.mk"
  [ -f "$golang_values" ] || {
    rm -f "$tarball"
    echo "ERROR: OpenWrt golang values file not found at ${golang_values}" >&2
    exit 1
  }
  openwrt_go_version="$(awk -F':=' '/^GO_DEFAULT_VERSION:=/ {gsub(/[[:space:]]/, "", $2); print $2; exit}' "$golang_values")"
  [ -n "$openwrt_go_version" ] || {
    rm -f "$tarball"
    echo "ERROR: failed to read OpenWrt GO_DEFAULT_VERSION" >&2
    exit 1
  }
  if ! version_ge "$openwrt_go_version" "$sing_box_go_version"; then
    rm -f "$tarball"
    echo "ERROR: sing-box ${latest_tag} requires Go ${sing_box_go_version}, but OpenWrt feed provides Go ${openwrt_go_version}" >&2
    exit 1
  fi
  hash="$(sha256sum "$tarball" | awk '{print $1}')"
  mkdir -p dl
  cp "$tarball" "dl/sing-box-${version}.tar.gz"
  rm -f "$tarball"

  sed -i \
    -e "s/^PKG_VERSION:=.*/PKG_VERSION:=${version}/" \
    -e "s/^PKG_HASH:=.*/PKG_HASH:=${hash}/" \
    "$makefile"

  grep -q "^PKG_VERSION:=${version}$" "$makefile" || {
    echo "ERROR: failed to patch sing-box PKG_VERSION" >&2
    exit 1
  }
  grep -q "^PKG_HASH:=${hash}$" "$makefile" || {
    echo "ERROR: failed to patch sing-box PKG_HASH" >&2
    exit 1
  }

  if [ -n "${GITHUB_ENV:-}" ]; then
    {
      echo "SING_BOX_VERSION=${version}"
      echo "SING_BOX_TAG=${latest_tag}"
      echo "SING_BOX_SOURCE_SHA256=${hash}"
      echo "SING_BOX_SOURCE_FILE=sing-box-${version}.tar.gz"
      echo "SING_BOX_GO_VERSION=${sing_box_go_version}"
      echo "OPENWRT_GO_VERSION=${openwrt_go_version}"
      echo "SING_BOX_FEED_VERSION=${original_version:-unknown}"
    } >> "$GITHUB_ENV"
  fi

  echo "sing-box updated from feed ${original_version:-unknown} to latest stable ${version} (${hash}); Go ${openwrt_go_version} >= ${sing_box_go_version}"
}

verify_theme_darkmode_hooks() {
  local aurora_header="package/luci-theme-aurora/ucode/template/themes/aurora/header.ut"
  local daede_config="package/luci-app-daede/htdocs/luci-static/resources/view/daede/config.js"
  local daede_styles="package/luci-app-daede/htdocs/luci-static/resources/view/daede/styles.js"

  grep -Fq "localStorage.getItem('aurora.theme')" "$aurora_header" || {
    echo "ERROR: luci-theme-aurora theme storage hook is missing" >&2
    exit 1
  }
  grep -Fq "document.documentElement.setAttribute('data-darkmode'" "$aurora_header" || {
    echo "ERROR: luci-theme-aurora data-darkmode hook is missing" >&2
    exit 1
  }
  grep -Fq "document.documentElement.setAttribute('data-daede-darkmode', 'true')" "$daede_config" || {
    echo "ERROR: luci-app-daede page-scoped dark-mode detector is missing" >&2
    exit 1
  }
  grep -Fq "document.documentElement.getAttribute('data-darkmode') === 'true'" "$daede_config" || {
    echo "ERROR: luci-app-daede no longer follows LuCI theme state" >&2
    exit 1
  }
  if grep -Fq '0.299 * m[0]' "$daede_config"; then
    echo "ERROR: luci-app-daede still uses brittle RGB brightness detection" >&2
    exit 1
  fi
  if grep -Fq "document.documentElement.setAttribute('data-darkmode', 'true')" "$daede_config"; then
    echo "ERROR: luci-app-daede must not force global LuCI data-darkmode" >&2
    exit 1
  fi
  grep -Fq 'html[data-daede-darkmode="true"] .dd-card' "$daede_styles" || {
    echo "ERROR: luci-app-daede dark-mode styles are missing" >&2
    exit 1
  }
  grep -Fq 'No prefers-color-scheme dark block' "$daede_styles" || {
    echo "ERROR: luci-app-daede may force OS dark mode instead of LuCI theme state" >&2
    exit 1
  }
}

patch_daede_theme() {
  local config="package/luci-app-daede/htdocs/luci-static/resources/view/daede/config.js"
  local styles="package/luci-app-daede/htdocs/luci-static/resources/view/daede/styles.js"

  perl -0pi -e '
    BEGIN {
      $scoped = qq~\t\t/* Keep daede dark styles scoped to this page; Aurora exposes\n\t\t   the current LuCI theme state through html[data-darkmode]. */\n\t\ttry {\n\t\t\tif (document.documentElement.getAttribute(\x27data-darkmode\x27) === \x27true\x27)\n\t\t\t\tdocument.documentElement.setAttribute(\x27data-daede-darkmode\x27, \x27true\x27);\n\t\t} catch (e) {}\n~;
    }
    s~(document\.documentElement\.setAttribute\(\x27data-daede-theme\x27, /\\\/argon\\\//\.test\(themeHref\) \? \x27argon\x27 : \x27bootstrap\x27\);\R)~$1\t\tdocument.documentElement.removeAttribute(\x27data-daede-darkmode\x27);\n~ or die "daede theme anchor not found\n";
    s~\t\t/\* themes signal dark differently.*?\t\t\} catch \(e\) \{\}\R~$scoped~s or die "daede dark-mode block anchor not found\n";
  ' "$config"

  perl -0pi -e '
    s/html\[data-darkmode="true"\]/html[data-daede-darkmode="true"]/g;
    s/by data-darkmode \(config\.js reads the real page background\)/by data-daede-darkmode (config.js reads the real page background)/;
    s/border-radius:10px/border-radius:8px/g;
    s/background:linear-gradient\(#3886a1,#2f7288\);color:#fff/background:var(--brand,#46a3d1);color:var(--on-brand,#fff)/g;
    s/border-color:#4aa065 !important;color:#4aa065 !important/border-color:var(--brand,#46a3d1) !important;color:var(--brand,#46a3d1) !important/g;
    s/border-color:rgba\(56,134,161,\.7\);outline:0;box-shadow:0 0 0 2px rgba\(56,134,161,\.15\)/border-color:var(--brand,#46a3d1);outline:0;box-shadow:0 0 0 2px var(--focus-ring,rgba(70,163,209,.35))/g;
  ' "$styles"

  grep -Fq "document.documentElement.setAttribute('data-daede-darkmode', 'true')" "$config" || {
    echo "ERROR: luci-app-daede page-scoped dark-mode patch is missing" >&2
    exit 1
  }
  grep -Fq "document.documentElement.getAttribute('data-darkmode') === 'true'" "$config" || {
    echo "ERROR: luci-app-daede no longer follows LuCI theme state" >&2
    exit 1
  }
  if grep -Fq '0.299 * m[0]' "$config"; then
    echo "ERROR: luci-app-daede still uses brittle RGB brightness detection" >&2
    exit 1
  fi
  if grep -Fq "document.documentElement.setAttribute('data-darkmode', 'true')" "$config"; then
    echo "ERROR: luci-app-daede still forces global LuCI data-darkmode" >&2
    exit 1
  fi
  grep -Fq 'html[data-daede-darkmode="true"] .dd-card' "$styles" || {
    echo "ERROR: luci-app-daede page-scoped dark-mode styles are missing" >&2
    exit 1
  }
  grep -Fq 'border-radius:8px' "$styles" || {
    echo "ERROR: luci-app-daede card radius was not aligned with Aurora" >&2
    exit 1
  }
  if grep -Fq 'linear-gradient(#3886a1,#2f7288)' "$styles"; then
    echo "ERROR: luci-app-daede still uses a hard-coded active backend gradient" >&2
    exit 1
  fi
  grep -Fq 'background:var(--brand,#46a3d1)' "$styles" || {
    echo "ERROR: luci-app-daede active backend no longer follows Aurora brand color" >&2
    exit 1
  }
}

inject_daede() {
  echo "Injecting openwrt-daede (pinned commit)"

  rm -rf \
    package/dae \
    package/daed \
    package/luci-app-dae \
    package/luci-app-daed \
    package/luci-app-daede \
    package/openwrt-daede \
    package/feeds/packages/dae \
    package/feeds/packages/daed \
    package/feeds/luci/luci-app-dae \
    package/feeds/luci/luci-app-daed \
    package/feeds/luci/luci-app-daede

  local daede_commit="0aeb278ce033b3ab2d50c7ba4e6d9fc74008dad8"
  local dae_makefile_sha256="91a38f022c3abc6efed1fef1994e5a5785627541bcd25397ce46b0bb4ba2b40a"
  local daed_makefile_sha256="83fac799c40bda2c714ee63145c5bdd0bff7b20132e926b6118d358efb3a5354"
  local luci_app_daede_makefile_sha256="053045399c2f8c7b72ed436c530cef96bae5ce6f8749d6fa5326d05ceb29098e"
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "DAEDE_COMMIT=${daede_commit}" >> "$GITHUB_ENV"
  fi

  git clone https://github.com/kenzok8/openwrt-daede package/openwrt-daede
  git -C package/openwrt-daede -c advice.detachedHead=false checkout "$daede_commit"
  mv package/openwrt-daede/dae package/dae
  mv package/openwrt-daede/daed package/daed
  mv package/openwrt-daede/luci-app-daede package/luci-app-daede
  rm -rf package/openwrt-daede

  require_file_sha256 package/dae/Makefile "$dae_makefile_sha256" "dae Makefile"
  require_file_sha256 package/daed/Makefile "$daed_makefile_sha256" "daed Makefile"
  require_file_sha256 package/luci-app-daede/Makefile "$luci_app_daede_makefile_sha256" "luci-app-daede Makefile"
  patch_daede_theme

  grep -q '^PKG_NAME:=dae$' package/dae/Makefile || {
    echo "ERROR: unexpected dae package name" >&2
    exit 1
  }
  grep -q '^PKG_VERSION:=2026.06.14$' package/dae/Makefile || {
    echo "ERROR: unexpected dae package version" >&2
    exit 1
  }
  grep -q '^PKG_HASH:=5bbbd017bffdf04d0357a4e487c5d108b983c29b231fa752de17ddda00b2b462$' package/dae/Makefile || {
    echo "ERROR: unexpected dae source hash" >&2
    exit 1
  }
  grep -q '^PKG_NAME:=daed$' package/daed/Makefile || {
    echo "ERROR: unexpected daed package name" >&2
    exit 1
  }
  grep -q '^PKG_VERSION:=2026.06.14$' package/daed/Makefile || {
    echo "ERROR: unexpected daed package version" >&2
    exit 1
  }
  grep -q '^PKG_HASH:=eeba8db775d248ce06f34adda7a392548c78a1d9d11d9a162e0ab41d5cc216d6$' package/daed/Makefile || {
    echo "ERROR: unexpected daed source hash" >&2
    exit 1
  }
  grep -q '^PKG_NAME:=luci-app-daede$' package/luci-app-daede/Makefile || {
    echo "ERROR: unexpected luci-app-daede package name" >&2
    exit 1
  }
  grep -q '^PKG_VERSION:=1.14.7$' package/luci-app-daede/Makefile || {
    echo "ERROR: unexpected luci-app-daede package version" >&2
    exit 1
  }
  grep -Fq 'default PACKAGE_$(PKG_NAME)_daed' package/luci-app-daede/Makefile || {
    echo "ERROR: luci-app-daede default backend is not daed" >&2
    exit 1
  }
  grep -Fq '+PACKAGE_$(PKG_NAME)_dae:dae +PACKAGE_$(PKG_NAME)_daed:daed' package/luci-app-daede/Makefile || {
    echo "ERROR: luci-app-daede backend dependencies are unexpected" >&2
    exit 1
  }
  grep -q 'uclient-fetch' package/luci-app-daede/root/www/cgi-bin/daede-graphql || {
    echo "ERROR: luci-app-daede GraphQL relay no longer uses uclient-fetch" >&2
    exit 1
  }
  grep -q 'DAEDE_FETCH_BIN:-uclient-fetch' package/luci-app-daede/root/usr/share/luci-app-daede/fetch-clash-yaml.sh || {
    echo "ERROR: luci-app-daede subscription fetch helper dependency changed" >&2
    exit 1
  }
  grep -q 'ucode -e' package/luci-app-daede/root/usr/share/luci-app-daede/config-backup.sh || {
    echo "ERROR: luci-app-daede config backup helper dependency changed" >&2
    exit 1
  }
  grep -q 'curl -fsSL' package/luci-app-daede/root/usr/share/luci-app-daede/update-geo.sh || {
    echo "ERROR: luci-app-daede geo update helper dependency changed" >&2
    exit 1
  }
  grep -Fq "+@KERNEL_XDP_SOCKETS" package/dae/Makefile || {
    echo "ERROR: dae is missing KERNEL_XDP_SOCKETS dependency" >&2
    exit 1
  }
  grep -Fq "+@KERNEL_XDP_SOCKETS" package/daed/Makefile || {
    echo "ERROR: daed is missing KERNEL_XDP_SOCKETS dependency" >&2
    exit 1
  }

  echo "openwrt-daede source verified (commit ${daede_commit})"
}

# -- Dynamic kernel version detection --
KERNEL_VER="$(grep -E '^KERNEL_PATCHVER:=' target/linux/qualcommax/Makefile 2>/dev/null | sed 's/.*:=//;s/^[[:space:]]*//')"
KERNEL_VER="${KERNEL_VER:-6.12}"
KERNEL_CFG="target/linux/qualcommax/config-${KERNEL_VER}"
echo "Detected kernel ${KERNEL_VER} (config: ${KERNEL_CFG})"
normalize_overlay_modes

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

# -- Inject Aurora theme (pinned commit) --
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
git -C package/luci-theme-aurora -c advice.detachedHead=false checkout "$AURORA_COMMIT"

if [ "$VARIANT" = "core-daede" ]; then
  inject_daede
  verify_theme_darkmode_hooks
  refresh_package_metadata
  exit 0
fi

patch_sing_box_latest_stable

# -- Inject HomeProxy --
echo "Injecting HomeProxy (latest master)"

rm -rf \
  feeds/luci/applications/luci-app-homeproxy \
  package/feeds/luci/luci-app-homeproxy \
  package/luci-app-homeproxy

git clone --depth 1 https://github.com/immortalwrt/homeproxy feeds/luci/applications/luci-app-homeproxy
mkdir -p package/feeds/luci
ln -s ../../../feeds/luci/applications/luci-app-homeproxy package/feeds/luci/luci-app-homeproxy
HOMEPROXY_COMMIT="$(git -C feeds/luci/applications/luci-app-homeproxy rev-parse HEAD)"
HOMEPROXY_BRANCH="$(git -C feeds/luci/applications/luci-app-homeproxy rev-parse --abbrev-ref HEAD)"
if [ -n "${GITHUB_ENV:-}" ]; then
  {
    echo "HOMEPROXY_COMMIT=${HOMEPROXY_COMMIT}"
    echo "HOMEPROXY_BRANCH=${HOMEPROXY_BRANCH}"
  } >> "$GITHUB_ENV"
fi

grep -q '^LUCI_TITLE:=The modern ImmortalWrt proxy platform' feeds/luci/applications/luci-app-homeproxy/Makefile || {
  echo "ERROR: unexpected HomeProxy Makefile title after injection" >&2
  exit 1
}
grep -q '^LUCI_DEPENDS:=' feeds/luci/applications/luci-app-homeproxy/Makefile || {
  echo "ERROR: HomeProxy Makefile dependencies are missing" >&2
  exit 1
}
grep -q '+sing-box' feeds/luci/applications/luci-app-homeproxy/Makefile || {
  echo "ERROR: HomeProxy no longer depends on sing-box" >&2
  exit 1
}
echo "HomeProxy source verified (latest ${HOMEPROXY_BRANCH} commit ${HOMEPROXY_COMMIT})"

refresh_package_metadata
exit 0
