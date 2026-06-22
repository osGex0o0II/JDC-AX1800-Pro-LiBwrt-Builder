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

inject_quickfile() {
  echo "Injecting luci-app-quickfile (pinned commit)"

  rm -rf package/quickfile

  local quickfile_commit="e6621cf4cb4e46c022bcf13089ddd82454c35e1b"
  local quickfile_makefile_sha256="808f64def69cd1ddce5185d78e1072e9c07eb03fec9b84f89b3f86f195b1b387"
  local luci_app_quickfile_makefile_sha256="1aef0d690b577157f8eac21745b2518b149393e4ce8606c0f30258ff853f7376"
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "QUICKFILE_COMMIT=${quickfile_commit}" >> "$GITHUB_ENV"
  fi

  git clone https://github.com/sbwml/luci-app-quickfile package/quickfile
  cd package/quickfile
  git -c advice.detachedHead=false checkout "$quickfile_commit"

  local quickfile_computed_sha256
  quickfile_computed_sha256="$(sha256sum quickfile/Makefile 2>/dev/null | awk '{print $1}')"
  if [ "$quickfile_computed_sha256" != "$quickfile_makefile_sha256" ]; then
    echo "ERROR: quickfile Makefile SHA256 mismatch!" >&2
    echo "  Expected: ${quickfile_makefile_sha256}" >&2
    echo "  Got:      ${quickfile_computed_sha256:-<file not found>}" >&2
    exit 1
  fi

  local luci_app_quickfile_computed_sha256
  luci_app_quickfile_computed_sha256="$(sha256sum luci-app-quickfile/Makefile 2>/dev/null | awk '{print $1}')"
  if [ "$luci_app_quickfile_computed_sha256" != "$luci_app_quickfile_makefile_sha256" ]; then
    echo "ERROR: luci-app-quickfile Makefile SHA256 mismatch!" >&2
    echo "  Expected: ${luci_app_quickfile_makefile_sha256}" >&2
    echo "  Got:      ${luci_app_quickfile_computed_sha256:-<file not found>}" >&2
    exit 1
  fi
  grep -q '^LUCI_DEPENDS:=+luci-nginx +quickfile$' luci-app-quickfile/Makefile || {
    echo "ERROR: unexpected luci-app-quickfile dependencies" >&2
    exit 1
  }
  grep -q '^PKG_VERSION:=1.0.24$' quickfile/Makefile || {
    echo "ERROR: unexpected quickfile package version" >&2
    exit 1
  }
  echo "quickfile Makefiles integrity verified (SHA256 match)"
  cd "$OLDPWD" || exit 1
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

inject_quickfile

if [ "$VARIANT" = "core-daed" ]; then
  echo "Injecting dae (pinned commit, with LuCI status/log UI)"

  rm -rf \
    package/dae \
    package/daed \
    package/luci-app-daed \
    package/luci-app-dae \
    package/feeds/packages/dae \
    package/feeds/packages/daed \
    package/feeds/luci/luci-app-daed \
    package/feeds/luci/luci-app-dae

  DAE_COMMIT="27213747d9fe82645dd3c16f07c0da53b4b34b97"
  DAE_MAKEFILE_SHA256="4dab7b9fce7da10970b8ae4ee2794fc98401e169a8f1847f4768168f1cf77c31"
  DAE_INIT_SHA256="218af1544f31c79fc802bd473b1f507d98c50732edcde0888c7b8973b1d0c56c"
  DAE_CONFIG_SHA256="87641bee9900c787fd23e96d08feb400f14b8a8ac13e57296738f2d823fe606a"
  LUCI_APP_DAE_MAKEFILE_SHA256="24d430d45ea42c49487651dcf6fc8d098d80154b4bdc75e20c3fd3ec705a3e5d"
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "DAE_COMMIT=${DAE_COMMIT}" >> "$GITHUB_ENV"
  fi

  mkdir -p package/dae
  git -C package/dae init
  git -C package/dae remote add origin https://github.com/sbwml/luci-app-dae.git
  git -C package/dae fetch --depth=1 origin "$DAE_COMMIT"
  git -C package/dae -c advice.detachedHead=false checkout FETCH_HEAD
  cd package/dae

  DAE_COMPUTED_SHA256="$(sha256sum dae/Makefile 2>/dev/null | awk '{print $1}')"
  if [ "$DAE_COMPUTED_SHA256" != "$DAE_MAKEFILE_SHA256" ]; then
    echo "ERROR: dae Makefile SHA256 mismatch!" >&2
    echo "  Expected: ${DAE_MAKEFILE_SHA256}" >&2
    echo "  Got:      ${DAE_COMPUTED_SHA256:-<file not found>}" >&2
    exit 1
  fi

  DAE_INIT_COMPUTED_SHA256="$(sha256sum dae/files/dae.init 2>/dev/null | awk '{print $1}')"
  if [ "$DAE_INIT_COMPUTED_SHA256" != "$DAE_INIT_SHA256" ]; then
    echo "ERROR: dae init SHA256 mismatch!" >&2
    echo "  Expected: ${DAE_INIT_SHA256}" >&2
    echo "  Got:      ${DAE_INIT_COMPUTED_SHA256:-<file not found>}" >&2
    exit 1
  fi

  DAE_CONFIG_COMPUTED_SHA256="$(sha256sum dae/files/dae.config 2>/dev/null | awk '{print $1}')"
  if [ "$DAE_CONFIG_COMPUTED_SHA256" != "$DAE_CONFIG_SHA256" ]; then
    echo "ERROR: dae UCI config SHA256 mismatch!" >&2
    echo "  Expected: ${DAE_CONFIG_SHA256}" >&2
    echo "  Got:      ${DAE_CONFIG_COMPUTED_SHA256:-<file not found>}" >&2
    exit 1
  fi

  LUCI_APP_DAE_COMPUTED_SHA256="$(sha256sum luci-app-dae/Makefile 2>/dev/null | awk '{print $1}')"
  if [ "$LUCI_APP_DAE_COMPUTED_SHA256" != "$LUCI_APP_DAE_MAKEFILE_SHA256" ]; then
    echo "ERROR: luci-app-dae Makefile SHA256 mismatch!" >&2
    echo "  Expected: ${LUCI_APP_DAE_MAKEFILE_SHA256}" >&2
    echo "  Got:      ${LUCI_APP_DAE_COMPUTED_SHA256:-<file not found>}" >&2
    exit 1
  fi

  grep -q '^PKG_NAME:=dae$' dae/Makefile || {
    echo "ERROR: unexpected dae package name" >&2
    exit 1
  }
  grep -q '^PKG_VERSION:=0.4.0rc1$' dae/Makefile || {
    echo "ERROR: unexpected dae package version" >&2
    exit 1
  }
  grep -q '^define Package/dae-geoip$' dae/Makefile || {
    echo "ERROR: dae-geoip package is missing" >&2
    exit 1
  }
  grep -q '^define Package/dae-geosite$' dae/Makefile || {
    echo "ERROR: dae-geosite package is missing" >&2
    exit 1
  }
  grep -q '^LUCI_DEPENDS:=+dae +dae-geoip +dae-geosite$' luci-app-dae/Makefile || {
    echo "ERROR: unexpected luci-app-dae dependencies" >&2
    exit 1
  }

  cat > luci-app-dae/luasrc/controller/dae.lua <<'EOF'
local sys  = require "luci.sys"
local http = require "luci.http"

module("luci.controller.dae", package.seeall)

function index()
	if not nixio.fs.access("/etc/config/dae") then
		return
	end

	local page = entry({"admin", "services", "dae"}, cbi("dae"), _("DAE"), -1)
	page.dependent = true
	page.acl_depends = { "luci-app-dae" }

	entry({"admin", "services", "dae", "status"}, call("act_status")).leaf = true
end

function act_status()
	local e = {}
	e.running = sys.call("pidof dae >/dev/null") == 0
	e.log = sys.exec("logread 2>/dev/null | grep -i '[d]ae' | tail -n 120")
	http.prepare_content("application/json")
	http.write_json(e)
end
EOF

  cat > luci-app-dae/luasrc/model/cbi/dae.lua <<'EOF'
local sys = require "luci.sys"
local m, s

m = Map("dae", translate("DAE"))
m.description = translate("A Linux high-performance transparent proxy solution based on eBPF.") ..
	"<br />" .. translate("Configuration file") .. ": <code>/etc/dae/config.dae</code>" ..
	"<br />" .. translate("Runtime UCI file") .. ": <code>/etc/config/dae</code>"

m:section(SimpleSection).template = "dae/dae_status"

s = m:section(TypedSection, "dae")
s.addremove = false
s.anonymous = true

o = s:option(Button, "_reload", translate("Reload Service"), translate("Reload the service effective configuration file."))
o.write = function()
	sys.exec("/etc/init.d/dae reload")
end

return m
EOF

  cat > luci-app-dae/luasrc/view/dae/dae_status.htm <<'EOF'
<script type="text/javascript">//<![CDATA[
	XHR.poll(5, '<%=url("admin/services/dae/status")%>', null,
		function(x, data)
		{
			var status = document.getElementById('dae_status');
			var log = document.getElementById('dae_log');

			if (data && status)
			{
				if (data.running)
					status.innerHTML = '<em style="color:green"><b><%:DAE%> <%:RUNNING%></b></em>';
				else
					status.innerHTML = '<em style="color:red"><b><%:DAE%> <%:NOT RUNNING%></b></em>';
			}

			if (data && log)
				log.textContent = data.log || '<%:No dae logs yet.%>';
		}
	);
//]]></script>

<fieldset class="cbi-section">
	<p id="dae_status">
		<em><b><%:Collecting data...%></b></em>
	</p>
	<p><%:Configuration file%>: <code>/etc/dae/config.dae</code></p>
	<p><%:Runtime UCI file%>: <code>/etc/config/dae</code></p>
</fieldset>

<fieldset class="cbi-section">
	<legend><%:Runtime log%></legend>
	<pre id="dae_log" style="white-space:pre-wrap; max-height:24em; overflow:auto;"><%:Collecting data...%></pre>
</fieldset>
EOF

  cat >> luci-app-dae/po/zh_Hans/dae.po <<'EOF'

msgid "Configuration file"
msgstr "配置文件"

msgid "Runtime UCI file"
msgstr "运行时 UCI 文件"

msgid "Runtime log"
msgstr "运行日志"

msgid "No dae logs yet."
msgstr "暂无 dae 日志。"
EOF

  grep -q '/etc/dae/config.dae' luci-app-dae/luasrc/view/dae/dae_status.htm || {
    echo "ERROR: luci-app-dae config path display patch failed" >&2
    exit 1
  }
  grep -q 'pidof dae' luci-app-dae/luasrc/controller/dae.lua || {
    echo "ERROR: luci-app-dae status check patch failed" >&2
    exit 1
  }
  grep -q 'logread' luci-app-dae/luasrc/controller/dae.lua || {
    echo "ERROR: luci-app-dae log display patch failed" >&2
    exit 1
  }
  ! grep -q 'fs.writefile("/etc/dae/config.dae"' luci-app-dae/luasrc/model/cbi/dae.lua || {
    echo "ERROR: luci-app-dae config editor is still writable" >&2
    exit 1
  }
  echo "dae package integrity verified (SHA256 match, LuCI status/log UI retained)"

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
