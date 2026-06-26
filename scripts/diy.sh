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

normalize_overlay_modes() {
  [ -d files/etc/uci-defaults ] && find files/etc/uci-defaults -type f -exec chmod 755 {} +
  [ -d files/etc/init.d ] && find files/etc/init.d -type f -exec chmod 755 {} +
  [ -d files/etc/hotplug.d ] && find files/etc/hotplug.d -type f -exec chmod 755 {} +
  [ -d files/usr/sbin ] && find files/usr/sbin -type f -exec chmod 755 {} +
  return 0
}

git_tag_names() {
  local repo="$1"
  git ls-remote --tags --refs "$repo" |
    awk '{print $2}' |
    sed 's#refs/tags/##' |
    tr -d '\r'
}

latest_semver_git_tag() {
  local repo="$1"
  git_tag_names "$repo" |
    sed -nE 's/^v([0-9]+)\.([0-9]+)\.([0-9]+)$/\1 \2 \3 &/p' |
    sort -n -k1,1 -k2,2 -k3,3 |
    awk 'END { print $4 }'
}

latest_date_git_tag() {
  local repo="$1"
  git_tag_names "$repo" |
    sed -nE \
      -e 's/^v([0-9]{4})\.([0-9]{2})\.([0-9]{2})$/\1 \2 \3 0 &/p' \
      -e 's/^v([0-9]{4})\.([0-9]{2})\.([0-9]{2})\.([0-9]+)$/\1 \2 \3 \4 &/p' |
    sort -n -k1,1 -k2,2 -k3,3 -k4,4 |
    awk 'END { print $5 }'
}

makefile_value() {
  local path="$1"
  local key="$2"
  awk -F':=' -v key="$key" '$1 == key { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print $2; exit }' "$path"
}

append_github_env() {
  [ -n "${GITHUB_ENV:-}" ] || return 0
  printf '%s\n' "$@" >> "$GITHUB_ENV"
}

version_ge() {
  awk -v have="$1" -v need="$2" '
    function splitver(v, a) {
      split(v, a, /[.+_-]/)
    }
    BEGIN {
      splitver(have, h)
      splitver(need, n)
      for (i = 1; i <= 4; i++) {
        hv = (h[i] == "" ? 0 : h[i] + 0)
        nv = (n[i] == "" ? 0 : n[i] + 0)
        if (hv > nv) exit 0
        if (hv < nv) exit 1
      }
      exit 0
    }
  '
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

patch_sing_box_latest_stable() {
  local makefile="feeds/packages/net/sing-box/Makefile"
  local latest_tag version tarball_url tarball hash original_version
  local tar_listing tar_root sing_box_go_version golang_values openwrt_go_version

  [ -f "$makefile" ] || {
    echo "ERROR: sing-box Makefile not found at ${makefile}" >&2
    exit 1
  }

  latest_tag="$(latest_semver_git_tag https://github.com/SagerNet/sing-box.git)"
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
    append_github_env \
      "SING_BOX_VERSION=${version}" \
      "SING_BOX_TAG=${latest_tag}" \
      "SING_BOX_SOURCE_SHA256=${hash}" \
      "SING_BOX_SOURCE_FILE=sing-box-${version}.tar.gz" \
      "SING_BOX_GO_VERSION=${sing_box_go_version}" \
      "OPENWRT_GO_VERSION=${openwrt_go_version}" \
      "SING_BOX_FEED_VERSION=${original_version:-unknown}"
  fi

  echo "sing-box updated from feed ${original_version:-unknown} to latest stable ${version} (${hash}); Go ${openwrt_go_version} >= ${sing_box_go_version}"
}

patch_homeproxy_sing_box_compat() {
  local generator="feeds/luci/applications/luci-app-homeproxy/root/etc/homeproxy/scripts/generate_client.uc"
  local updater="feeds/luci/applications/luci-app-homeproxy/root/etc/homeproxy/scripts/update_subscriptions.uc"
  local legacy_sniff_count legacy_override_count detour_count direct_detour_count

  [ -f "$generator" ] || {
    echo "ERROR: HomeProxy client generator not found at ${generator}" >&2
    exit 1
  }
  [ -f "$updater" ] || {
    echo "ERROR: HomeProxy subscription updater not found at ${updater}" >&2
    exit 1
  }
  sed -i 's/\r$//' "$generator"
  sed -i 's/\r$//' "$updater"

  legacy_sniff_count="$(awk 'index($0, "sniff: true") { count++ } END { print count + 0 }' "$generator")"
  legacy_override_count="$(awk 'index($0, "sniff_override_destination: strToBool(sniff_override)") { count++ } END { print count + 0 }' "$generator")"
  if [ "$legacy_sniff_count" -gt 0 ] || [ "$legacy_override_count" -gt 0 ]; then
    [ "$legacy_sniff_count" -eq 4 ] && [ "$legacy_override_count" -eq 4 ] || {
      echo "ERROR: unexpected HomeProxy legacy inbound sniff field counts: sniff=${legacy_sniff_count}, override=${legacy_override_count}" >&2
      exit 1
    }
    perl -ni -e '
      next if /^\t+sniff: true,?$/;
      next if /^\t+sniff_override_destination: strToBool\(sniff_override\),?$/;
      print;
    ' "$generator"
    perl -0pi -e 's/,(\n\t+\}\);)/$1/g' "$generator"
  fi

  if ! grep -Fq "inbound: ['mixed-in', 'redirect-in', 'tproxy-in', 'tun-in']" "$generator"; then
    perl -0pi -e '
      s~\n\t\t/\*\n\t\t \* leave for sing-box 1\.13\.0\n\t\t \* \{\n\t\t \* \taction: '"'"'sniff'"'"'\n\t\t \* \}\n\t\t \*/~~;
      $n = s~(\t\t\{\n\t\t\tinbound: '"'"'dns-in'"'"',\n\t\t\taction: '"'"'hijack-dns'"'"'\n\t\t\})~$1,\n\t\t{\n\t\t\tinbound: ['"'"'mixed-in'"'"', '"'"'redirect-in'"'"', '"'"'tproxy-in'"'"', '"'"'tun-in'"'"'],\n\t\t\taction: '"'"'sniff'"'"'\n\t\t}~;
      END { die "ERROR: failed to add HomeProxy route sniff action\n" unless $n == 1; }
    ' "$generator"
  fi

  if ! grep -Fq "const main_urltest_nodes = filter(uci.get(uciconfig, ucimain, 'main_urltest_nodes')" "$generator"; then
    perl -0pi -e "s~const main_urltest_nodes = uci\\.get\\(uciconfig, ucimain, 'main_urltest_nodes'\\) \\|\\| \\[\\];~const main_urltest_nodes = filter(uci.get(uciconfig, ucimain, 'main_urltest_nodes') || [], (k) => !isEmpty(uci.get_all(uciconfig, k)?.type));~" "$generator"
  fi
  if ! grep -Fq "const main_udp_urltest_nodes = filter(uci.get(uciconfig, ucimain, 'main_udp_urltest_nodes')" "$generator"; then
    perl -0pi -e "s~const main_udp_urltest_nodes = uci\\.get\\(uciconfig, ucimain, 'main_udp_urltest_nodes'\\) \\|\\| \\[\\];~const main_udp_urltest_nodes = filter(uci.get(uciconfig, ucimain, 'main_udp_urltest_nodes') || [], (k) => !isEmpty(uci.get_all(uciconfig, k)?.type));~" "$generator"
  fi
  if ! grep -Fq "const cfg_urltest_nodes = filter(cfg.urltest_nodes || []" "$generator"; then
    perl -0pi -e "s~(\\t\\tif \\(cfg\\.node === 'urltest'\\) \\{\\n)~\$1\\t\\t\\tconst cfg_urltest_nodes = filter(cfg.urltest_nodes || [], (k) => !isEmpty(uci.get_all(uciconfig, k)?.type));\\n~" "$generator"
    sed -i 's/outbounds: map(cfg.urltest_nodes/outbounds: map(cfg_urltest_nodes/; s/filter(cfg.urltest_nodes, (l) =>/filter(cfg_urltest_nodes, (l) =>/' "$generator"
  fi
  if ! grep -Fq "if (isEmpty(urltest_node.type))" "$generator"; then
    perl -0pi -e "s~(const urltest_node = uci\\.get_all\\(uciconfig, i\\) \\|\\| \\{\\};\\n)~\$1\\t\\tif (isEmpty(urltest_node.type))\\n\\t\\t\\tcontinue;\\n~g" "$generator"
  fi

  detour_count="$(awk 'index($0, "download_detour: '\''main-out'\''") { count++ } END { print count + 0 }' "$generator")"
  if [ "$detour_count" -gt 0 ]; then
    [ "$detour_count" -eq 3 ] || {
      echo "ERROR: unexpected HomeProxy main-out rule-set detour count: ${detour_count}" >&2
      exit 1
    }
    sed -i "s/download_detour: 'main-out'/download_detour: 'direct-out'/g" "$generator"
  fi

  if grep -Fq "sniff_override_destination: strToBool(sniff_override)" "$generator" ||
     grep -Fq "sniff: true" "$generator"; then
    echo "ERROR: HomeProxy still contains legacy sing-box inbound sniff fields" >&2
    exit 1
  fi
  grep -Fq "inbound: ['mixed-in', 'redirect-in', 'tproxy-in', 'tun-in']" "$generator" || {
    echo "ERROR: HomeProxy sing-box 1.13 route sniff action is missing" >&2
    exit 1
  }
  grep -Fq "const main_urltest_nodes = filter(uci.get(uciconfig, ucimain, 'main_urltest_nodes')" "$generator" || {
    echo "ERROR: HomeProxy main urltest nodes are not filtered for stale UCI sections" >&2
    exit 1
  }
  grep -Fq "const main_udp_urltest_nodes = filter(uci.get(uciconfig, ucimain, 'main_udp_urltest_nodes')" "$generator" || {
    echo "ERROR: HomeProxy UDP urltest nodes are not filtered for stale UCI sections" >&2
    exit 1
  }
  grep -Fq "const cfg_urltest_nodes = filter(cfg.urltest_nodes || []" "$generator" || {
    echo "ERROR: HomeProxy custom urltest nodes are not filtered for stale UCI sections" >&2
    exit 1
  }
  grep -Fq "if (isEmpty(urltest_node.type))" "$generator" || {
    echo "ERROR: HomeProxy standalone urltest outbound generation does not skip stale UCI sections" >&2
    exit 1
  }
  direct_detour_count="$(awk 'index($0, "download_detour: '\''direct-out'\''") { count++ } END { print count + 0 }' "$generator")"
  [ "$direct_detour_count" -ge 3 ] || {
    echo "ERROR: HomeProxy remote rule-set downloads are not forced to direct-out" >&2
    exit 1
  }

  if ! grep -Fq "function is_placeholder_subscription_node(config)" "$updater"; then
    local tmp_updater
    tmp_updater="$(mktemp)"
    awk '
      /^\/\* String helper end \*\/$/ && !inserted {
        print "function is_placeholder_subscription_node(config) {"
        print "\tconst label = config.label || \"\";"
        print "\tconst address = config.address || \"\";"
        print ""
        print "\tif (address === \"localhost\" || address === \"0.0.0.0\" || address === \"::\" || address === \"::1\" || match(address, /^127\\./))"
        print "\t\treturn true;"
        print ""
        print "\tif (match(label, /v2rayN|old client|client too old|update client/))"
        print "\t\treturn true;"
        print ""
        print "\treturn false;"
        print "}"
        print ""
        inserted = 1
      }
      { print }
      END { if (!inserted) exit 1 }
    ' "$updater" > "$tmp_updater" || {
      rm -f "$tmp_updater"
      echo "ERROR: failed to add HomeProxy placeholder subscription node helper" >&2
      exit 1
    }
    cat "$tmp_updater" > "$updater"
    rm -f "$tmp_updater"
  fi

  if ! grep -Fq "is_placeholder_subscription_node(config)" "$updater" ||
     ! grep -Fq "Skipping placeholder subscription node" "$updater"; then
    local tmp_updater
    tmp_updater="$(mktemp)"
    awk '
      index($0, "config.address) + " q ":" q " + config.port;") && !inserted {
        print
        print ""
        print "\t\tif (is_placeholder_subscription_node(config)) {"
        print "\t\t\tlog(sprintf(\"Skipping placeholder subscription node: %s.\", config.label || config.address || \"NULL\"));"
        print "\t\t\treturn null;"
        print "\t\t}"
        inserted = 1
        next
      }
      { print }
      END { if (!inserted) exit 1 }
    ' q="'" "$updater" > "$tmp_updater" || {
      rm -f "$tmp_updater"
      echo "ERROR: failed to add HomeProxy placeholder subscription node check" >&2
      exit 1
    }
    cat "$tmp_updater" > "$updater"
    rm -f "$tmp_updater"
  fi

  if ! grep -Fq "No main node is selected, switching to the first node." "$updater"; then
    local tmp_updater
    tmp_updater="$(mktemp)"
    awk '
      index($0, "\tlet need_restart = (via_proxy !== " q "1" q ");") && !inserted {
        print
        print "\tconst first_server = uci.get_first(uciconfig, ucinode);"
        print "\tif (routing_mode !== " q "custom" q " && isEmpty(main_node) && first_server) {"
        print "\t\tuci.set(uciconfig, ucimain, " q "main_node" q ", first_server);"
        print "\t\tuci.set(uciconfig, ucimain, " q "main_udp_node" q ", " q "same" q ");"
        print "\t\tuci.commit(uciconfig);"
        print "\t\tmain_node = first_server;"
        print "\t\tmain_udp_node = " q "same" q ";"
        print "\t\tneed_restart = true;"
        print ""
        print "\t\tlog(" q "No main node is selected, switching to the first node." q ");"
        print "\t}"
        inserted = 1
        next
      }
      { print }
      END { if (!inserted) exit 1 }
    ' q="'" "$updater" > "$tmp_updater" || {
      rm -f "$tmp_updater"
      echo "ERROR: failed to add HomeProxy first subscription node fallback" >&2
      exit 1
    }
    cat "$tmp_updater" > "$updater"
    rm -f "$tmp_updater"

    perl -0pi -e "s/\n\t\tconst first_server = uci\.get_first\(uciconfig, ucinode\);//" "$updater"
  fi

  grep -Fq "function is_placeholder_subscription_node(config)" "$updater" || {
    echo "ERROR: HomeProxy placeholder subscription node helper is missing" >&2
    exit 1
  }
  grep -Fq "Skipping placeholder subscription node" "$updater" || {
    echo "ERROR: HomeProxy placeholder subscription node check is missing" >&2
    exit 1
  }
  grep -Fq "No main node is selected, switching to the first node." "$updater" || {
    echo "ERROR: HomeProxy first subscription node fallback is missing" >&2
    exit 1
  }

  echo "Patched HomeProxy scripts for sing-box 1.13+, direct rule-set bootstrap downloads, placeholder subscription filtering, and first node fallback"
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
  local daede_tag daede_commit dae_version daed_version luci_app_daede_version

  echo "Injecting openwrt-daede (latest stable tag)"

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

  daede_tag="$(latest_date_git_tag https://github.com/kenzok8/openwrt-daede.git)"
  [ -n "$daede_tag" ] || {
    echo "ERROR: failed to resolve latest stable openwrt-daede tag" >&2
    exit 1
  }

  git -c advice.detachedHead=false clone --depth 1 --branch "$daede_tag" https://github.com/kenzok8/openwrt-daede package/openwrt-daede
  daede_commit="$(git -C package/openwrt-daede rev-parse HEAD)"
  mv package/openwrt-daede/dae package/dae
  mv package/openwrt-daede/daed package/daed
  mv package/openwrt-daede/luci-app-daede package/luci-app-daede
  rm -rf package/openwrt-daede

  patch_daede_theme

  grep -q '^PKG_NAME:=dae$' package/dae/Makefile || {
    echo "ERROR: unexpected dae package name" >&2
    exit 1
  }
  dae_version="$(makefile_value package/dae/Makefile PKG_VERSION)"
  [ -n "$dae_version" ] || {
    echo "ERROR: dae package version is missing" >&2
    exit 1
  }
  [ -n "$(makefile_value package/dae/Makefile PKG_HASH)" ] || {
    echo "ERROR: dae source hash is missing" >&2
    exit 1
  }
  grep -q '^PKG_NAME:=daed$' package/daed/Makefile || {
    echo "ERROR: unexpected daed package name" >&2
    exit 1
  }
  daed_version="$(makefile_value package/daed/Makefile PKG_VERSION)"
  [ -n "$daed_version" ] || {
    echo "ERROR: daed package version is missing" >&2
    exit 1
  }
  [ -n "$(makefile_value package/daed/Makefile PKG_HASH)" ] || {
    echo "ERROR: daed source hash is missing" >&2
    exit 1
  }
  grep -q '^PKG_NAME:=luci-app-daede$' package/luci-app-daede/Makefile || {
    echo "ERROR: unexpected luci-app-daede package name" >&2
    exit 1
  }
  luci_app_daede_version="$(makefile_value package/luci-app-daede/Makefile PKG_VERSION)"
  [ -n "$luci_app_daede_version" ] || {
    echo "ERROR: luci-app-daede package version is missing" >&2
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

  append_github_env \
    "DAEDE_TAG=${daede_tag}" \
    "DAEDE_COMMIT=${daede_commit}" \
    "DAE_VERSION=${dae_version}" \
    "DAED_VERSION=${daed_version}" \
    "LUCI_APP_DAEDE_VERSION=${luci_app_daede_version}"

  echo "openwrt-daede source verified (${daede_tag} commit ${daede_commit}; dae ${dae_version}, daed ${daed_version}, luci-app-daede ${luci_app_daede_version})"
}

# -- Dynamic kernel version detection --
KERNEL_VER="$(grep -E '^KERNEL_PATCHVER:=' target/linux/qualcommax/Makefile 2>/dev/null | sed 's/.*:=//;s/^[[:space:]]*//')"
KERNEL_VER="${KERNEL_VER:-6.12}"
KERNEL_CFG="target/linux/qualcommax/config-${KERNEL_VER}"
echo "Detected kernel ${KERNEL_VER} (config: ${KERNEL_CFG})"
normalize_overlay_modes
select_latest_nss_firmware

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

# -- Inject Aurora theme --
rm -rf package/luci-theme-aurora
AURORA_TAG="$(latest_semver_git_tag https://github.com/eamonxg/luci-theme-aurora.git)"
[ -n "$AURORA_TAG" ] || {
  echo "ERROR: failed to resolve latest stable luci-theme-aurora tag" >&2
  exit 1
}
if ! git -c advice.detachedHead=false clone --depth 1 --branch "$AURORA_TAG" https://github.com/eamonxg/luci-theme-aurora package/luci-theme-aurora; then
  rm -rf package/luci-theme-aurora
  echo "ERROR: Failed to clone luci-theme-aurora" >&2
  exit 1
fi
AURORA_COMMIT="$(git -C package/luci-theme-aurora rev-parse HEAD)"
append_github_env \
  "AURORA_TAG=${AURORA_TAG}" \
  "AURORA_COMMIT=${AURORA_COMMIT}"
echo "luci-theme-aurora source verified (${AURORA_TAG} commit ${AURORA_COMMIT})"

if [ "$VARIANT" = "core-daede" ]; then
  inject_daede
  verify_theme_darkmode_hooks
  refresh_package_metadata
  exit 0
fi

patch_sing_box_latest_stable

# -- Inject HomeProxy --
echo "Injecting HomeProxy (latest stable tag, or latest master when upstream has no stable tags)"

rm -rf \
  feeds/luci/applications/luci-app-homeproxy \
  package/feeds/luci/luci-app-homeproxy \
  package/luci-app-homeproxy

HOMEPROXY_TAG="$(latest_semver_git_tag https://github.com/immortalwrt/homeproxy.git)"
if [ -n "$HOMEPROXY_TAG" ]; then
  git -c advice.detachedHead=false clone --depth 1 --branch "$HOMEPROXY_TAG" https://github.com/immortalwrt/homeproxy feeds/luci/applications/luci-app-homeproxy
  HOMEPROXY_SOURCE="stable-tag"
else
  git clone --depth 1 https://github.com/immortalwrt/homeproxy feeds/luci/applications/luci-app-homeproxy
  HOMEPROXY_SOURCE="master"
fi
mkdir -p package/feeds/luci
ln -s ../../../feeds/luci/applications/luci-app-homeproxy package/feeds/luci/luci-app-homeproxy
HOMEPROXY_COMMIT="$(git -C feeds/luci/applications/luci-app-homeproxy rev-parse HEAD)"
HOMEPROXY_REF="$(git -C feeds/luci/applications/luci-app-homeproxy rev-parse --abbrev-ref HEAD)"
if [ -n "${GITHUB_ENV:-}" ]; then
  append_github_env \
    "HOMEPROXY_SOURCE=${HOMEPROXY_SOURCE}" \
    "HOMEPROXY_TAG=${HOMEPROXY_TAG:-not-available}" \
    "HOMEPROXY_COMMIT=${HOMEPROXY_COMMIT}" \
    "HOMEPROXY_REF=${HOMEPROXY_REF}"
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
patch_homeproxy_sing_box_compat
echo "HomeProxy source verified (${HOMEPROXY_SOURCE} ${HOMEPROXY_TAG:-${HOMEPROXY_REF}} commit ${HOMEPROXY_COMMIT})"

refresh_package_metadata
exit 0
