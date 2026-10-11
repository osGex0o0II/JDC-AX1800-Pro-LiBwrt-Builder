# JDC AX1800 Pro · LiBwrt

为**京东云无线宝亚瑟**提供的纯有线路由固件，基于 [LiBwrt](https://github.com/LiBwrt/LibWrt) `25.12-nss`。仅维护 **core** 版本，**不包含 Wi-Fi**。

[**下载固件**](https://github.com/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder/releases) · [构建状态](https://github.com/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder/actions/workflows/build.yml) · [升级指南](docs/upgrade.md)

> [!WARNING]
> **只提供 sysupgrade 镜像，不支持原厂固件首次刷机。** 升级前请核对硬件与分区、完成备份并准备恢复手段。兼容性检查失败时不要强刷。

## 主要功能

- **网络加速**：Qualcomm NSS / ECM、BBR + fq。
- **代理服务**：HomeProxy、sing-box。
- **管理界面**：Aurora 主题、简体中文 LuCI。
- **常用工具**：IPv6、ZeroTier、UPnP、Samba、USB 存储、DiskMan。

## 下载与使用

- **下载固件**：从 [Releases](https://github.com/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder/releases) 获取 `*-core-sysupgrade.bin`，并校验 SHA256。
- **升级固件**：阅读 [升级与恢复指南](docs/upgrade.md)。构建成功不代表每台设备都能安全刷入。
- **自行编译**：Fork 本仓库，在 **Actions → Build JDC AX1800 Pro LiBwrt → Run workflow** 中运行。构建产物为 `firmware-core`。

## 文档

[编译说明](docs/build.md) · [功能与默认设置](docs/firmware.md) · [升级与恢复](docs/upgrade.md) · [开发维护](docs/development.md)

---

基于 [LiBwrt](https://github.com/LiBwrt/LibWrt)、[NSS packages](https://github.com/qosmio/nss-packages)、[HomeProxy](https://github.com/immortalwrt/homeproxy)、[Aurora](https://github.com/eamonxg/luci-theme-aurora) 等开源项目。许可证：[GPL-2.0-only](LICENSE)。
