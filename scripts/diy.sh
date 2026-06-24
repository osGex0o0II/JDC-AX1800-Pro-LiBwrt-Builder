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
    const root = document.documentElement;
    if (root && root.getAttribute("data-darkmode") === "true") return "dark";
    return "light";
}
~;
    }
    s/\Rreturn view\.extend\(\{\R/\n$helper\nreturn view.extend({\n/ or die "quickfile-go theme helper anchor not found\n";
    s/    theme: \x27dark\x27,/    theme: defaultQuickFileTheme(),/ or die "quickfile-go theme property anchor not found\n";
    s/this\.theme = this\.theme === \x27dark\x27 \? \x27light\x27 : \x27dark\x27; this\.refresh\(this\.currentPath\);/this.theme = this.theme === "dark" ? "light" : "dark"; this.refresh(this.currentPath);/ or die "quickfile-go theme toggle anchor not found\n";
  ' "$view"

  perl -0pi -e '
    BEGIN {
      $aurora = q~
        /* Aurora theme bridge: keep QuickFile-Go visually inside LuCI instead of
           carrying its upstream Element-style hard-coded palette. */
        .qf-app {
            background: transparent !important;
            color: var(--text, #141822) !important;
            font-family: var(--font-sans, "Lato", ui-sans-serif, system-ui, sans-serif) !important;
        }
        .qf-header, .qf-card, .qf-toolbar,
        .qf-dialog, .qf-settings-panel, .qf-confirm-dialog,
        .qf-settings-dialog, .qf-install-dialog, .qf-editor-dialog,
        .qf-terminal-dialog, .qf-task-row {
            background: var(--surface, #fff) !important;
            color: var(--text, #141822) !important;
            border-color: var(--hairline, rgba(20,24,34,.08)) !important;
            box-shadow: none !important;
        }
        .qf-header, .qf-card {
            border: 1px solid var(--hairline, rgba(20,24,34,.08)) !important;
            border-radius: 8px !important;
        }
        .qf-toolbar {
            border-bottom: 1px solid var(--hairline, rgba(20,24,34,.08)) !important;
        }
        .qf-logo, .qf-item-name, .qf-grid.qf-list-view .qf-item-name,
        .qf-task-title, .qf-confirm-message, .qf-install-status {
            color: var(--text, #141822) !important;
        }
        .qf-header-right, .qf-breadcrumb, .qf-item-meta,
        .qf-grid.qf-list-view .qf-item-meta,
        .qf-grid.qf-list-view .qf-col-time,
        .qf-grid.qf-list-view .qf-col-mode,
        .qf-empty, .qf-settings-note, .qf-task-meta,
        .qf-form-help, .qf-download-path, .qf-install-actions-left {
            color: var(--text-muted, #5f636b) !important;
        }
        .qf-header-right span:hover, .qf-breadcrumb span.qf-bc-link:hover,
        .qf-list-header span[data-sort]:hover, .qf-menu-item:hover {
            color: var(--brand, #46a3d1) !important;
        }
        .qf-btn, .qf-confirm-cancel, .qf-terminal-action {
            background: var(--surface, #fff) !important;
            border-color: var(--hairline, rgba(20,24,34,.08)) !important;
            color: var(--text, #141822) !important;
            border-radius: 8px !important;
            box-shadow: none !important;
        }
        .qf-btn:hover, .qf-confirm-cancel:hover, .qf-terminal-action:hover {
            background: var(--surface-sunken, #f0f1f3) !important;
            border-color: var(--hairline, rgba(20,24,34,.08)) !important;
            color: var(--brand, #46a3d1) !important;
        }
        .qf-btn-primary, .qf-confirm-ok, .qf-install-dot {
            background: var(--brand, #46a3d1) !important;
            border-color: var(--brand, #46a3d1) !important;
            color: var(--on-brand, #fff) !important;
        }
        .qf-btn-danger-text, .qf-form-error, .qf-install-status.fail,
        .qf-menu-item[style*="f56c6c"] {
            color: var(--danger, #6c1517) !important;
        }
        .qf-btn:disabled, .qf-btn.disabled {
            background: var(--surface-sunken, #f0f1f3) !important;
            border-color: var(--hairline, rgba(20,24,34,.08)) !important;
            color: var(--text-subtle, #7e8188) !important;
        }
        .qf-btn-icon {
            display: none !important;
        }
        .qf-search-box, .qf-settings-field input, .qf-settings-field select,
        .qf-form-input, .qf-download-path, .qf-confirm-target,
        .qf-install-meta, .qf-install-log, .qf-editor-host,
        .qf-editor, .qf-terminal-status {
            background: var(--surface-sunken, #f0f1f3) !important;
            border-color: var(--hairline, rgba(20,24,34,.08)) !important;
            color: var(--text, #141822) !important;
        }
        .qf-search-box input {
            color: var(--text, #141822) !important;
        }
        .qf-settings-field input:focus, .qf-settings-field select:focus,
        .qf-form-input:focus {
            border-color: var(--brand, #46a3d1) !important;
            box-shadow: 0 0 0 2px var(--focus-ring, rgba(70,163,209,.35)) !important;
        }
        .qf-list-header {
            background: var(--surface, #fff) !important;
            border-color: var(--hairline, rgba(20,24,34,.08)) !important;
            color: var(--text-muted, #5f636b) !important;
        }
        .qf-grid.qf-list-view .qf-item {
            border-color: var(--hairline, rgba(20,24,34,.08)) !important;
        }
        .qf-item:hover, .qf-menu-item:hover {
            background: var(--surface-sunken, #f0f1f3) !important;
        }
        .qf-item.selected, .qf-item.context-target,
        .qf-app.drag-over {
            background: var(--brand-subtle, #e0eaf2) !important;
            border-color: var(--brand, #46a3d1) !important;
        }
        .qf-context-menu {
            background: var(--surface-overlay, var(--surface, #fff)) !important;
            color: var(--text, #141822) !important;
            border-color: var(--hairline, rgba(20,24,34,.08)) !important;
            box-shadow: var(--app-shadow-md, 0 4px 16px rgba(0,0,0,.08)) !important;
            border-radius: 8px !important;
        }
        .qf-menu-separator, .qf-settings-actions,
        .qf-dialog-header, .qf-dialog-footer,
        .qf-confirm-dialog .qf-dialog-footer,
        .qf-install-dialog .qf-dialog-footer,
        .qf-editor-dialog .qf-dialog-footer {
            border-color: var(--hairline, rgba(20,24,34,.08)) !important;
        }
        .qf-overlay {
            background: var(--scrim, rgba(0,0,0,.6)) !important;
        }
        .qf-thumb {
            background: var(--surface-sunken, #f0f1f3) !important;
            border-color: var(--hairline, rgba(20,24,34,.08)) !important;
        }
~;
    }
    s/(\n\s*`;\R\s*document\.head\.appendChild\(E\(\x27style\x27, \{ id: \x27qf-custom-css\x27 \}, css\)\);\R)/\n$aurora$1/ or die "quickfile-go Aurora style anchor not found\n";
    s/this\.theme === \x27light\x27 \? \x27.*?深色模式\x27 : \x27.*?浅色模式\x27/this.theme === \x27light\x27 ? \x27深色模式\x27 : \x27浅色模式\x27/ or die "quickfile-go theme label anchor not found\n";
    s/const logoIcon = this\.makeIcon\(`(<svg viewBox="0 0 1024 1024" width="22" height="22"><path[^`]+fill=")#409eff("[^`]+)`\);/const logoIcon = this.makeIcon(`$1currentColor$2`);/ or die "quickfile-go logo icon anchor not found\n";
  ' "$view"

  perl -0pi -e 's/"title": "QuickFile-Go"/"title": "\\u6587\\u4ef6\\u7ba1\\u7406"/ or die "quickfile-go menu title anchor not found\n";' "$menu"

  grep -Fq 'listen_addr="${listen_addr%%/*}"' "$initd" || {
    echo "ERROR: quickfile-go init script does not strip CIDR from listen_addr" >&2
    exit 1
  }
  if grep -Fq "quickfileGoTheme" "$view"; then
    echo "ERROR: quickfile-go theme state must not persist after leaving the page" >&2
    exit 1
  fi
  grep -Fq "data-darkmode" "$view" || {
    echo "ERROR: quickfile-go theme patch no longer follows LuCI dark mode" >&2
    exit 1
  }
  grep -Fq "Aurora theme bridge" "$view" || {
    echo "ERROR: quickfile-go Aurora theme bridge is missing" >&2
    exit 1
  }
  grep -Fq 'fill="currentColor"' "$view" || {
    echo "ERROR: quickfile-go logo icon no longer follows text color" >&2
    exit 1
  }
  if grep -Fq '🌙 深色模式' "$view" || grep -Fq '☀ 浅色模式' "$view"; then
    echo "ERROR: quickfile-go theme toggle still uses standalone emoji labels" >&2
    exit 1
  fi
  grep -Fq '"title": "\u6587\u4ef6\u7ba1\u7406"' "$menu" || {
    echo "ERROR: quickfile-go menu title patch is missing" >&2
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
