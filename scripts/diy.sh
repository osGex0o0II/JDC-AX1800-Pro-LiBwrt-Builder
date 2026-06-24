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
  [ -d files/usr/sbin ] && find files/usr/sbin -type f -exec chmod 755 {} +
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
  grep -Fq "document.documentElement.setAttribute('data-darkmode', 'true')" "$daede_config" || {
    echo "ERROR: luci-app-daede dark-mode detector is missing" >&2
    exit 1
  }
  grep -Fq 'html[data-darkmode="true"] .dd-card' "$daede_styles" || {
    echo "ERROR: luci-app-daede dark-mode styles are missing" >&2
    exit 1
  }
  grep -Fq 'No prefers-color-scheme dark block' "$daede_styles" || {
    echo "ERROR: luci-app-daede may force OS dark mode instead of LuCI theme state" >&2
    exit 1
  }
}

patch_quickfile_go() {
  local initd="package/luci-app-quickfile-go/root/etc/init.d/quickfile-go"
  local view="package/luci-app-quickfile-go/htdocs/luci-static/resources/view/quickfile-go.js"
  local menu="package/luci-app-quickfile-go/root/usr/share/luci/menu.d/luci-app-quickfile-go.json"

  perl -0pi -e '
    s~(\tif \[ -z "\$listen_addr" \] \|\| \[ "\$listen_addr" = "auto" \]; then\R\t\tlisten_addr="\$\(uci -q get network\.lan\.ipaddr 2>/dev/null\)"\R\t\t\[ -n "\$listen_addr" \] \|\| listen_addr="192\.168\.1\.1"\R\tfi\R)~$1\tlisten_addr="\${listen_addr%%/*}"\n\t[ -n "\$listen_addr" ] || listen_addr="192.168.1.1"\n~ or die "quickfile-go init script anchor not found\n";
  ' "$initd"

  perl -0pi -e '
    BEGIN {
      $helper = q~
function defaultQuickFileTheme() {
    const saved = localStorage.getItem("quickfileGoTheme");
    if (saved === "light" || saved === "dark") return saved;
    const root = document.documentElement;
    if (root && root.getAttribute("data-darkmode") === "false") return "light";
    if (root && root.getAttribute("data-darkmode") === "true") return "dark";
    return window.matchMedia && window.matchMedia("(prefers-color-scheme: light)").matches ? "light" : "dark";
}

function saveQuickFileTheme(theme) {
    if (theme === "light" || theme === "dark") localStorage.setItem("quickfileGoTheme", theme);
}
~;
    }
    s/\Rreturn view\.extend\(\{\R/\n$helper\nreturn view.extend({\n/ or die "quickfile-go theme helper anchor not found\n";
    s/    theme: \x27dark\x27,/    theme: defaultQuickFileTheme(),/ or die "quickfile-go theme property anchor not found\n";
    s/this\.theme = this\.theme === \x27dark\x27 \? \x27light\x27 : \x27dark\x27; this\.refresh\(this\.currentPath\);/this.theme = this.theme === "dark" ? "light" : "dark"; saveQuickFileTheme(this.theme); this.refresh(this.currentPath);/ or die "quickfile-go theme toggle anchor not found\n";
  ' "$view"

  perl -0pi -e 's/"title": "QuickFile-Go"/"title": "\\u6587\\u4ef6\\u7ba1\\u7406"/ or die "quickfile-go menu title anchor not found\n";' "$menu"

  grep -Fq 'listen_addr="${listen_addr%%/*}"' "$initd" || {
    echo "ERROR: quickfile-go init script does not strip CIDR from listen_addr" >&2
    exit 1
  }
  grep -Fq 'localStorage.getItem("quickfileGoTheme")' "$view" || {
    echo "ERROR: quickfile-go theme persistence patch is missing" >&2
    exit 1
  }
  grep -Fq "data-darkmode" "$view" || {
    echo "ERROR: quickfile-go theme patch no longer follows LuCI dark mode" >&2
    exit 1
  }
  grep -Fq '"title": "\u6587\u4ef6\u7ba1\u7406"' "$menu" || {
    echo "ERROR: quickfile-go menu title patch is missing" >&2
    exit 1
  }
}

inject_quickfile_go() {
  echo "Injecting luci-app-quickfile-go (pinned commit)"

  rm -rf \
    package/quickfile \
    package/quickfile-go \
    package/luci-app-quickfile \
    package/luci-app-quickfile-go \
    package/luci-app-quickfile-go-src \
    package/feeds/luci/luci-app-quickfile \
    package/feeds/luci/luci-app-quickfile-go

  local quickfile_go_commit="57b9f4636b778b75de4642b84071881e98c72b7c"
  local quickfile_go_makefile_sha256="1458f7a213158953744c8f73e0b0ff64020bdcd23dd16bc53ac3604dd17050e4"
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "QUICKFILE_GO_COMMIT=${quickfile_go_commit}" >> "$GITHUB_ENV"
  fi

  git clone https://github.com/home16668/luci-app-quickfile-go package/luci-app-quickfile-go-src
  git -C package/luci-app-quickfile-go-src -c advice.detachedHead=false checkout "$quickfile_go_commit"
  mv package/luci-app-quickfile-go-src/luci-app-quickfile-go package/luci-app-quickfile-go
  rm -rf package/luci-app-quickfile-go-src

  require_file_sha256 \
    package/luci-app-quickfile-go/Makefile \
    "$quickfile_go_makefile_sha256" \
    "luci-app-quickfile-go Makefile"
  patch_quickfile_go

  grep -q '^PKG_NAME:=luci-app-quickfile-go$' package/luci-app-quickfile-go/Makefile || {
    echo "ERROR: unexpected luci-app-quickfile-go package name" >&2
    exit 1
  }
  grep -q '^PKG_VERSION:=2.0.1$' package/luci-app-quickfile-go/Makefile || {
    echo "ERROR: unexpected luci-app-quickfile-go package version" >&2
    exit 1
  }
  grep -q '^PKG_RELEASE:=73$' package/luci-app-quickfile-go/Makefile || {
    echo "ERROR: unexpected luci-app-quickfile-go package release" >&2
    exit 1
  }
  grep -q 'DEPENDS:=+luci-base +rpcd' package/luci-app-quickfile-go/Makefile || {
    echo "ERROR: unexpected luci-app-quickfile-go dependencies" >&2
    exit 1
  }
  grep -q 'quickfile-go-api' package/luci-app-quickfile-go/Makefile || {
    echo "ERROR: quickfile-go backend install rule is missing" >&2
    exit 1
  }
  if grep -Rq 'luci-nginx' package/luci-app-quickfile-go; then
    echo "ERROR: luci-app-quickfile-go unexpectedly references luci-nginx" >&2
    exit 1
  fi

  echo "luci-app-quickfile-go source verified (commit ${quickfile_go_commit})"
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

inject_quickfile_go

if [ "$VARIANT" = "core-daede" ]; then
  inject_daede
  verify_theme_darkmode_hooks
  refresh_package_metadata
  exit 0
fi

# -- Inject HomeProxy --
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
git -C feeds/luci/applications/luci-app-homeproxy -c advice.detachedHead=false checkout "$HOMEPROXY_COMMIT"

require_file_sha256 \
  feeds/luci/applications/luci-app-homeproxy/Makefile \
  "$HOMEPROXY_MAKEFILE_SHA256" \
  "HomeProxy Makefile"
echo "HomeProxy Makefile integrity verified (SHA256 match)"

refresh_package_metadata
exit 0
