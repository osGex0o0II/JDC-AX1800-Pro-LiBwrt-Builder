#!/usr/bin/env bash
set -euo pipefail

# diy.sh - Apply custom configurations before build
# Usage: bash diy.sh <variant>
#   variant: core | core-dae | ultimate

VARIANT="${1:-core}"
OPENWRT_DIR="${OPENWRT_PATH:-openwrt}"
cd "$OPENWRT_DIR"

refresh_package_metadata() {
  rm -f tmp/.packageinfo tmp/.packagedeps tmp/.packageauxvars tmp/.packageusergroup tmp/.config-package.in tmp/.config-feeds.in
  rm -f tmp/info/.files-packageinfo.* tmp/info/.packageinfo-*
}

normalize_overlay_modes() {
  [ -d files/etc/uci-defaults ] && find files/etc/uci-defaults -type f -exec chmod 755 {} +
  [ -d files/usr/sbin ] && find files/usr/sbin -type f -exec chmod 755 {} +
  [ -x files/usr/sbin/quickfile-session ] || {
    echo "ERROR: quickfile session helper is missing or not executable" >&2
    exit 1
  }
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

  mkdir -p luci-app-quickfile/root/usr/share/rpcd/acl.d
  cat > luci-app-quickfile/root/usr/share/luci/menu.d/luci-app-quickfile.json <<'EOF'
{
	"admin/system/quickfile": {
		"title": "Quick File Manager",
		"order": 80,
		"action": {
			"type": "view",
			"path": "system/quickfile"
		},
		"depends": {
			"acl": [ "luci-app-quickfile" ]
		}
	}
}
EOF

  cat > luci-app-quickfile/root/usr/share/rpcd/acl.d/luci-app-quickfile.json <<'EOF'
{
	"luci-app-quickfile": {
		"description": "Grant access to the temporary QuickFile session gate",
		"read": {
			"file": {
				"/usr/sbin/quickfile-session status": [ "exec" ]
			},
			"ubus": {
				"file": [ "exec" ]
			}
		},
		"write": {
			"file": {
				"/usr/sbin/quickfile-session enable": [ "exec" ],
				"/usr/sbin/quickfile-session heartbeat": [ "exec" ],
				"/usr/sbin/quickfile-session disable": [ "exec" ]
			},
			"ubus": {
				"file": [ "exec" ]
			}
		}
	}
}
EOF

  cat > luci-app-quickfile/htdocs/luci-static/resources/view/system/quickfile.js <<'EOF'
'use strict';
'require fs';
'require ui';
'require view';

function session(action) {
	return fs.exec('/usr/sbin/quickfile-session', [ action ]);
}

return view.extend({
	render: function () {
		let interval = null;
		let active = false;

		const status = E('span', { 'class': 'spinning' }, _('Checking status...'));
		const button = E('button', {
			'class': 'btn cbi-button cbi-button-apply',
			'click': enableSession
		}, _('Enable QuickFile'));
		const iframe = E('iframe', {
			'src': 'about:blank',
			'style': 'display:none;width:100%;height:calc(100vh - 220px);min-height:760px;border:0;border-radius:8px;'
		});

		const container = E('div', { 'class': 'cbi-map' }, [
			E('h2', {}, _('Quick File Manager')),
			E('div', { 'class': 'cbi-section' }, [
				E('p', {}, status),
				E('div', { 'class': 'right' }, [ button ])
			]),
			iframe
		]);

		function setInactive(text) {
			active = false;
			status.className = '';
			status.textContent = text || _('QuickFile is disabled.');
			button.disabled = false;
			button.style.display = '';
			iframe.style.display = 'none';
			iframe.src = 'about:blank';
		}

		function setActive() {
			active = true;
			status.className = '';
			status.textContent = _('QuickFile is enabled for this page.');
			button.disabled = true;
			button.style.display = 'none';
			iframe.style.display = '';
			iframe.src = L.url('admin/system/quickfile').replace(/\/admin\/system\/quickfile$/, '/quickfile');
		}

		function stopHeartbeat() {
			if (interval != null) {
				window.clearInterval(interval);
				interval = null;
			}
		}

		function disableSession() {
			stopHeartbeat();
			if (active)
				session('disable').catch(function () {});
			setInactive(_('QuickFile is disabled.'));
		}

		function heartbeat() {
			if (!container.isConnected) {
				disableSession();
				return;
			}

			session('heartbeat').catch(function () {
				disableSession();
			});
		}

		function enableSession() {
			button.disabled = true;
			status.className = 'spinning';
			status.textContent = _('Enabling QuickFile...');

			session('enable').then(function () {
				setActive();
				heartbeat();
				stopHeartbeat();
				interval = window.setInterval(heartbeat, 8000);
			}).catch(function (e) {
				button.disabled = false;
				ui.addNotification(null, E('p', {}, _('Failed to enable QuickFile: %s').format(e.message || e)), 'danger');
				setInactive(_('QuickFile is disabled.'));
			});
		}

		function checkStatus() {
			session('status').then(function (res) {
				if ((res.stdout || '').trim() == 'enabled') {
					setActive();
					heartbeat();
					stopHeartbeat();
					interval = window.setInterval(heartbeat, 8000);
				}
				else {
					setInactive(_('QuickFile is disabled.'));
				}
			}).catch(function () {
				setInactive(_('QuickFile is disabled.'));
			});
		}

		window.addEventListener('pagehide', disableSession, { once: true });
		window.addEventListener('beforeunload', disableSession, { once: true });
		document.addEventListener('visibilitychange', function () {
			if (document.hidden)
				disableSession();
		});

		checkStatus();
		return container;
	},

	handleSave: null,
	handleSaveApply: null,
	handleReset: null
});
EOF

  cat >> luci-app-quickfile/po/zh_Hans/quickfile.po <<'EOF'

msgid "Checking status..."
msgstr "正在检查状态..."

msgid "Enable QuickFile"
msgstr "启用 QuickFile"

msgid "QuickFile is disabled."
msgstr "QuickFile 已关闭。"

msgid "QuickFile is enabled for this page."
msgstr "QuickFile 已为当前页面临时启用。"

msgid "Enabling QuickFile..."
msgstr "正在启用 QuickFile..."

msgid "Failed to enable QuickFile: %s"
msgstr "启用 QuickFile 失败：%s"
EOF

  grep -q '"acl": \[ "luci-app-quickfile" \]' luci-app-quickfile/root/usr/share/luci/menu.d/luci-app-quickfile.json || {
    echo "ERROR: luci-app-quickfile menu ACL gate is missing" >&2
    exit 1
  }
  grep -q '/usr/sbin/quickfile-session enable' luci-app-quickfile/root/usr/share/rpcd/acl.d/luci-app-quickfile.json || {
    echo "ERROR: luci-app-quickfile session ACL is missing" >&2
    exit 1
  }
  grep -q "session('heartbeat')" luci-app-quickfile/htdocs/luci-static/resources/view/system/quickfile.js || {
    echo "ERROR: luci-app-quickfile heartbeat gate is missing" >&2
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

if [ "$VARIANT" = "core-dae" ]; then
  echo "Using feeds dae and injecting luci-app-dae (pinned commit, controls/editor/log UI)"

  rm -rf \
    package/dae \
    package/daed \
    package/luci-app-daed \
    package/luci-app-dae \
    package/feeds/packages/daed \
    package/feeds/luci/luci-app-daed \
    package/feeds/luci/luci-app-dae

  LUCI_APP_DAE_COMMIT="27213747d9fe82645dd3c16f07c0da53b4b34b97"
  LUCI_APP_DAE_MAKEFILE_SHA256="24d430d45ea42c49487651dcf6fc8d098d80154b4bdc75e20c3fd3ec705a3e5d"
  if [ -n "${GITHUB_ENV:-}" ]; then
    echo "LUCI_APP_DAE_COMMIT=${LUCI_APP_DAE_COMMIT}" >> "$GITHUB_ENV"
  fi

  test -f package/feeds/packages/dae/Makefile || {
    echo "ERROR: feeds dae package is missing" >&2
    exit 1
  }

  grep -q '^PKG_NAME:=dae$' package/feeds/packages/dae/Makefile || {
    echo "ERROR: unexpected feeds dae package name" >&2
    exit 1
  }
  grep -q '^PKG_VERSION:=1.0.0$' package/feeds/packages/dae/Makefile || {
    echo "ERROR: unexpected feeds dae package version" >&2
    exit 1
  }
  grep -q '^PKG_HASH:=d933b93fc30cb4e9941cbb1be23557bd6caa2a33af212883505fec435d06fc13$' package/feeds/packages/dae/Makefile || {
    echo "ERROR: unexpected feeds dae source hash" >&2
    exit 1
  }
  grep -q '^define Package/dae-geoip$' package/feeds/packages/dae/Makefile || {
    echo "ERROR: dae-geoip package is missing" >&2
    exit 1
  }
  grep -q '^define Package/dae-geosite$' package/feeds/packages/dae/Makefile || {
    echo "ERROR: dae-geosite package is missing" >&2
    exit 1
  }
  grep -q '+kmod-veth' package/feeds/packages/dae/Makefile || {
    echo "ERROR: feeds dae is missing kmod-veth dependency" >&2
    exit 1
  }

  if ! grep -q '$(1)/etc/dae/config.dae' package/feeds/packages/dae/Makefile; then
    sed -i '/$(INSTALL_CONF).*$(PKG_BUILD_DIR)\/example.dae.*$(1)\/etc\/dae\/$/a\
	$(INSTALL_CONF) $(PKG_BUILD_DIR)/example.dae $(1)/etc/dae/config.dae' \
      package/feeds/packages/dae/Makefile
  fi
  grep -q '$(1)/etc/dae/config.dae' package/feeds/packages/dae/Makefile || {
    echo "ERROR: failed to patch feeds dae default config install" >&2
    exit 1
  }

  if [ -f package/feeds/packages/dae/files/dae.init ] && \
    ! grep -q 'mkdir -p "$LOG_DIR"' package/feeds/packages/dae/files/dae.init; then
    sed -i '/local enabled/i\  mkdir -p "$LOG_DIR"' package/feeds/packages/dae/files/dae.init
  fi
  grep -q 'mkdir -p "$LOG_DIR"' package/feeds/packages/dae/files/dae.init || {
    echo "ERROR: failed to patch dae init log directory setup" >&2
    exit 1
  }

  mkdir -p package/dae
  git -C package/dae init
  git -C package/dae remote add origin https://github.com/sbwml/luci-app-dae.git
  git -C package/dae fetch --depth=1 origin "$LUCI_APP_DAE_COMMIT"
  git -C package/dae -c advice.detachedHead=false checkout FETCH_HEAD
  cd package/dae
  rm -rf dae

  LUCI_APP_DAE_COMPUTED_SHA256="$(sha256sum luci-app-dae/Makefile 2>/dev/null | awk '{print $1}')"
  if [ "$LUCI_APP_DAE_COMPUTED_SHA256" != "$LUCI_APP_DAE_MAKEFILE_SHA256" ]; then
    echo "ERROR: luci-app-dae Makefile SHA256 mismatch!" >&2
    echo "  Expected: ${LUCI_APP_DAE_MAKEFILE_SHA256}" >&2
    echo "  Got:      ${LUCI_APP_DAE_COMPUTED_SHA256:-<file not found>}" >&2
    exit 1
  fi

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
	e.log = sys.exec("tail -n 120 /var/log/dae/dae.log 2>/dev/null")
	if not e.log or #e.log == 0 then
		e.log = sys.exec("logread 2>/dev/null | grep -i '[d]ae' | tail -n 120")
	end
	e.action = sys.exec("tail -n 80 /tmp/luci-dae-action.log 2>/dev/null")
	http.prepare_content("application/json")
	http.write_json(e)
end
EOF

  cat > luci-app-dae/luasrc/model/cbi/dae.lua <<'EOF'
local fs = require "nixio.fs"
local sys = require "luci.sys"
local m, s, o

local CONFIG_FILE = "/etc/dae/config.dae"
local ACTION_LOG = "/tmp/luci-dae-action.log"

local function shellquote(value)
	return "'" .. tostring(value):gsub("'", "'\"'\"'") .. "'"
end

local function write_action_log(text)
	fs.writefile(ACTION_LOG, os.date("%Y-%m-%d %H:%M:%S") .. "\n" .. tostring(text or "") .. "\n")
end

local function validate_config_file(path)
	local log = "/tmp/luci-dae-validate.log"
	local cmd = "dae validate -c " .. shellquote(path) .. " > " .. shellquote(log) .. " 2>&1"
	local ok = sys.call(cmd) == 0
	local output = fs.readfile(log) or ""
	fs.remove(log)
	return ok, output
end

local function validate_config_text(value)
	value = (value or ""):gsub("\r\n?", "\n")
	if value:gsub("%s+", "") == "" then
		return nil, translate("Configuration cannot be empty.")
	end

	local tmp = "/tmp/luci-dae-config-" .. tostring(os.time()) .. "-" .. tostring(math.random(100000, 999999)) .. ".dae"
	fs.writefile(tmp, value)
	local ok, output = validate_config_file(tmp)
	fs.remove(tmp)

	if not ok then
		return nil, translate("DAE configuration validation failed:") .. "\n" .. output
	end

	return value
end

local function service_action(action)
	if action ~= "stop" then
		local ok, output = validate_config_file(CONFIG_FILE)
		if not ok then
			write_action_log(translate("DAE configuration validation failed:") .. "\n" .. output)
			return
		end
	end

	if action == "start" then
		sys.call("uci -q set dae.config.enabled='1' && uci -q commit dae >/dev/null 2>&1")
		sys.call("/etc/init.d/dae enable >/dev/null 2>&1")
	elseif action == "stop" then
		sys.call("uci -q set dae.config.enabled='0' && uci -q commit dae >/dev/null 2>&1")
		sys.call("/etc/init.d/dae disable >/dev/null 2>&1")
	end

	local log = "/tmp/luci-dae-service.log"
	local rc = sys.call("/etc/init.d/dae " .. action .. " > " .. shellquote(log) .. " 2>&1")
	local output = fs.readfile(log) or ""
	fs.remove(log)
	write_action_log("dae " .. action .. " rc=" .. tostring(rc) .. "\n" .. output)
end

m = Map("dae", translate("DAE"))
m.description = translate("A Linux high-performance transparent proxy solution based on eBPF.") ..
	"<br />" .. translate("Configuration file") .. ": <code>" .. CONFIG_FILE .. "</code>" ..
	"<br />" .. translate("Runtime UCI file") .. ": <code>/etc/config/dae</code>"

m:section(SimpleSection).template = "dae/dae_status"

s = m:section(TypedSection, "dae")
s.addremove = false
s.anonymous = true

o = s:option(Flag, "enabled", translate("Enabled"))
o.rmempty = false
function o.write(self, section, value)
	Flag.write(self, section, value)
	if value == "1" then
		sys.call("/etc/init.d/dae enable >/dev/null 2>&1")
	else
		sys.call("/etc/init.d/dae disable >/dev/null 2>&1")
		sys.call("/etc/init.d/dae stop >/dev/null 2>&1")
	end
end

o = s:option(Button, "_start", translate("Start Service"))
o.inputstyle = "apply"
o.write = function()
	service_action("start")
end

o = s:option(Button, "_stop", translate("Stop Service"))
o.inputstyle = "reset"
o.write = function()
	service_action("stop")
end

o = s:option(Button, "_restart", translate("Restart Service"))
o.inputstyle = "reload"
o.write = function()
	service_action("restart")
end

o = s:option(Button, "_reload", translate("Reload Service"), translate("Reload the service effective configuration file."))
o.inputstyle = "reload"
o.write = function()
	service_action("reload")
end

o = s:option(TextValue, "daeconf", translate("Configuration Editor"))
o.rows = 28
o.rmempty = false
o.wrap = "off"

function o.cfgvalue(self, section)
	return fs.readfile(CONFIG_FILE) or ""
end

function o.validate(self, value, section)
	return validate_config_text(value)
end

function o.write(self, section, value)
	value = validate_config_text(value)
	if value then
		fs.writefile(CONFIG_FILE, value)
		write_action_log(translate("DAE configuration saved and validated."))
	end
end

o = s:option(DummyValue, "")
o.template = "dae/dae_editor"

return m
EOF

  cat > luci-app-dae/luasrc/view/dae/dae_status.htm <<'EOF'
<script type="text/javascript">//<![CDATA[
	XHR.poll(5, '<%=url("admin/services/dae/status")%>', null,
		function(x, data)
		{
			var status = document.getElementById('dae_status');
			var log = document.getElementById('dae_log');
			var action = document.getElementById('dae_action');

			if (data && status)
			{
				if (data.running)
					status.innerHTML = '<em style="color:green"><b><%:DAE%> <%:RUNNING%></b></em>';
				else
					status.innerHTML = '<em style="color:red"><b><%:DAE%> <%:NOT RUNNING%></b></em>';
			}

			if (data && log)
				log.textContent = data.log || '<%:No dae logs yet.%>';

			if (data && action)
				action.textContent = data.action || '<%:No recent action output.%>';
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

<fieldset class="cbi-section">
	<legend><%:Action output%></legend>
	<pre id="dae_action" style="white-space:pre-wrap; max-height:12em; overflow:auto;"><%:Collecting data...%></pre>
</fieldset>
EOF

  cat >> luci-app-dae/po/zh_Hans/dae.po <<'EOF'

msgid "Configuration file"
msgstr "配置文件"

msgid "Runtime UCI file"
msgstr "运行时 UCI 文件"

msgid "Runtime log"
msgstr "运行日志"

msgid "Action output"
msgstr "操作输出"

msgid "No dae logs yet."
msgstr "暂无 dae 日志。"

msgid "No recent action output."
msgstr "暂无操作输出。"

msgid "Start Service"
msgstr "启动服务"

msgid "Stop Service"
msgstr "停止服务"

msgid "Restart Service"
msgstr "重启服务"

msgid "Configuration cannot be empty."
msgstr "配置不能为空。"

msgid "DAE configuration validation failed:"
msgstr "DAE 配置校验失败："

msgid "DAE configuration saved and validated."
msgstr "DAE 配置已保存并通过校验。"
EOF

  grep -q '/etc/dae/config.dae' luci-app-dae/luasrc/view/dae/dae_status.htm || {
    echo "ERROR: luci-app-dae config path display patch failed" >&2
    exit 1
  }
  grep -q 's:option(Flag, "enabled"' luci-app-dae/luasrc/model/cbi/dae.lua || {
    echo "ERROR: luci-app-dae enabled switch patch failed" >&2
    exit 1
  }
  grep -q 's:option(TextValue, "daeconf"' luci-app-dae/luasrc/model/cbi/dae.lua || {
    echo "ERROR: luci-app-dae config editor patch failed" >&2
    exit 1
  }
  grep -q 'validate_config_text' luci-app-dae/luasrc/model/cbi/dae.lua || {
    echo "ERROR: luci-app-dae config validation patch failed" >&2
    exit 1
  }
  grep -q 'fs.writefile(CONFIG_FILE' luci-app-dae/luasrc/model/cbi/dae.lua || {
    echo "ERROR: luci-app-dae config writer patch failed" >&2
    exit 1
  }
  grep -q 'pidof dae' luci-app-dae/luasrc/controller/dae.lua || {
    echo "ERROR: luci-app-dae status check patch failed" >&2
    exit 1
  }
  grep -q '/var/log/dae/dae.log' luci-app-dae/luasrc/controller/dae.lua || {
    echo "ERROR: luci-app-dae file log display patch failed" >&2
    exit 1
  }
  grep -q 'logread' luci-app-dae/luasrc/controller/dae.lua || {
    echo "ERROR: luci-app-dae log display patch failed" >&2
    exit 1
  }
  echo "dae package source verified (feeds dae 1.0.0, LuCI controls/editor/log UI retained)"

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
