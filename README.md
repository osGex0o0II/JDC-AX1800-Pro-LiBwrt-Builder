# ExcaliburOS

The Sword of Arthur.

Custom LiBwrt Build for JDC AX1800 Pro (Arthur)

Based on [LiBwrt/openwrt-6.x](https://github.com/LiBwrt/openwrt-6.x) (`main-nss`, kernel 6.12)

[![Build](https://github.com/YOUR_USERNAME/ExcaliburOS/actions/workflows/build.yml/badge.svg)](https://github.com/YOUR_USERNAME/ExcaliburOS/actions/workflows/build.yml)
[![License](https://img.shields.io/github/license/YOUR_USERNAME/ExcaliburOS)](LICENSE)

## Features

- Optimized for IPQ6000 with **full NSS hardware acceleration**
- 512MB / 1G RAM Friendly
- eMMC Storage Support
- Docker Ready (Ultimate variant)
- GitHub Actions CI/CD
- BBR + fq congestion control
- CoreMark benchmark built-in

## Build Variants

| Variant | Use Case | Size |
|---------|----------|------|
| **Core** | Wired router / Enterprise | ~35MB |
| **Home** | Home network + Proxy | ~55MB |
| **Ultimate** | All-in-one + Docker | ~75MB |

See `configs/*.config` for complete package lists.

## Quick Start (GitHub Actions)

1. Fork this repository
2. Go to **Actions** → **Build ExcaliburOS**
3. Click **Run workflow**, select `core` / `home` / `ultimate`
4. Wait ~2-3 hours
5. Download firmware from Releases

### Optional: Lock upstream commit

Enter a commit hash in `repo_commit` to pin the upstream source for reproducible builds.

## Build Locally

```bash
git clone --depth 1 -b main-nss https://github.com/LiBwrt/openwrt-6.x.git libwrt
cp configs/core.config libwrt/.config
cd libwrt
./scripts/feeds update -a && ./scripts/feeds install -a
make defconfig
make download -j8
make -j$(nproc)
```

## Default Config

| Item | Value |
|------|-------|
| Management IP | 192.168.1.1 |
| Username | root |
| Password | password |
| LuCI Language | 简体中文 |

## Project Structure

```
ExcaliburOS/
├── .github/workflows/
│   ├── build.yml        # Build firmware (workflow_dispatch)
│   └── cleanup.yml      # Clean old runs and releases
├── configs/
│   ├── core.config      # Core variant config
│   ├── home.config      # Home variant config (additive)
│   └── ultimate.config  # Ultimate variant config (additive)
├── scripts/
│   ├── diy.sh           # Custom build script
│   ├── update-feeds.sh  # Feeds management
│   └── version.sh       # Auto versioning
├── files/               # Common files overlay
│   └── etc/
│       ├── sysctl.d/10-bbr.conf
│       └── uci-defaults/
├── patches/
├── docs/
├── README.md
└── LICENSE
```

## License

[GPL-2.0](LICENSE)
