# JDC AX1800 Pro LiBwrt

为 **京东云无线宝亚瑟（JDC AX1800 Pro）** 构建纯有线 LiBwrt 固件。

基于 [LiBwrt](https://github.com/LiBwrt/LibWrt) `25.12-nss`，集成 Qualcomm NSS 硬件加速、HomeProxy 和 sing-box。仅维护 **core** 一种固件配置。

[![Build](https://github.com/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder/actions/workflows/build.yml/badge.svg)](https://github.com/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder/actions/workflows/build.yml)
[![License](https://img.shields.io/github/license/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder)](LICENSE)

## Download

- [Releases](https://github.com/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder/releases) — 已发布的固件、校验和与构建记录。
- [GitHub Actions](https://github.com/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder/actions/workflows/build.yml) — 查看构建状态和下载测试构建的 Artifacts。

本项目仅发布 `*-core-sysupgrade.bin`，**不提供原厂首次刷机的 factory 镜像或已验证的救砖镜像**。

> [!WARNING]
> **编译成功不等于刷机安全。** 目前没有本项目镜像在所有 AX1800 Pro 硬件及分区布局上的实机兼容性保证。刷入前必须核实设备、现有固件的升级机制和恢复方案；如果 `sysupgrade -T` 校验失败，请停止，勿使用 `-F` 强制刷入。

详见 [升级与恢复](docs/upgrade.md)。

## Get started

使用 GitHub Actions 构建，无需自行搭建完整的 OpenWrt 编译环境。

1. [Fork 本仓库](https://github.com/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder/fork)。
2. 在 Fork 的 **Actions** 中启用并打开 **Build JDC AX1800 Pro LiBwrt**。
3. 选择 `main` 分支，点击 **Run workflow**；可选填写 `repo_commit` 以锁定上游完整提交 SHA。
4. 编译成功后从当前运行的 **Artifacts** 下载 `firmware-core`。在 `main` 手动触发且构建成功时，工作流还会尝试发布 Release。

在 Pull Request 上触发的构建**只上传测试 Artifact，不发布 Release**。

详细步骤及本地编译说明：[Build guide](docs/build.md)。

## Features

- **NSS acceleration** — IPQ60xx NSS/ECM，针对 512 MiB 设备使用相应内存配置。
- **Wired-only** — 不编译 Wi-Fi 驱动、无线服务与 NSS Wi-Fi mesh 组件。
- **Proxy** — HomeProxy + sing-box，集成规则与订阅相关兼容补丁。
- **LuCI** — Aurora 主题、简体中文界面以及系统、网络和状态管理模块。
- **Everyday tools** — IPv6、ZeroTier、UPnP、Samba、USB 存储、DiskMan、cpufreq、BBR + fq 和网络诊断。

软件包依赖于编译时的上游源码与 feeds；最终版本请以对应构建的 `BUILD-MANIFEST-core.txt` 为准。

## Documentation

- [Build guide](docs/build.md) — GitHub Actions、本地编译、产物与版本追溯。
- [Firmware](docs/firmware.md) — 设备目标、功能、默认行为与运行限制。
- [Upgrade & recovery](docs/upgrade.md) — 升级前检查、镜像校验、备份与恢复边界。
- [Development](docs/development.md) — 项目结构、测试、定制与维护约定。

## Development

固件配置位于 [`configs/core.config`](configs/core.config)，构建自定义逻辑位于 [`scripts/diy.sh`](scripts/diy.sh)。欢迎通过 [Issues](https://github.com/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder/issues) 反馈问题或提交 Pull Request。

## Credits

基于 [LiBwrt](https://github.com/LiBwrt/LibWrt)、[ImmortalWrt](https://github.com/immortalwrt)、[NSS packages](https://github.com/qosmio/nss-packages)、[HomeProxy](https://github.com/immortalwrt/homeproxy) 和 [Aurora](https://github.com/eamonxg/luci-theme-aurora) 等开源项目。

## License

[GPL-2.0-only](LICENSE)
