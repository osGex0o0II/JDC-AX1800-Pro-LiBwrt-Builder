# JDC AX1800 Pro · LiBwrt

为**京东云无线宝亚瑟**提供的纯有线路由固件，基于 [LiBwrt](https://github.com/LiBwrt/LibWrt) `25.12-nss`，**不包含 Wi-Fi**。

[**下载固件**](https://github.com/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder/releases) · [构建状态](https://github.com/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder/actions/workflows/build.yml) · [升级指南](docs/upgrade.md)

> [!WARNING]
> **只提供 sysupgrade 镜像，不支持原厂固件首次刷机。** 升级前请核对硬件与分区、完成备份并准备恢复手段。兼容性检查失败时不要强刷。

## 主要功能

- **网络加速**：Qualcomm NSS / ECM、BBR + fq。
- **`core`**：HomeProxy + sing-box，代理软件包与 [ZN-M2 LiBwrt 构建](https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder) 一致。
- **`core-honk`**：Honk + 内嵌 Doona 的实验版，Honk 默认停用；LuCI 提供服务入口。
- **管理界面**：Aurora 主题、简体中文 LuCI。
- **共同插件**：集客 AC（默认停用）、ZeroTier、UPnP、网络唤醒、定时重启、ttyd、Samba、USB 存储、DiskMan。

## 下载与使用

- **下载固件**：从 [Releases](https://github.com/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder/releases) 选择 `core` 或实验版 `core-honk`，按发布说明校验 SHA256。
- **升级固件**：阅读 [升级与恢复指南](docs/upgrade.md)。构建成功不代表每台设备都能安全刷入。
- **自行编译**：Fork 本仓库，在 **Actions → Build JDC AX1800 Pro LiBwrt → Run workflow** 中选择变体。编译记录见 `firmware-core` 或 `firmware-core-honk`。

## 文档

[编译说明](docs/build.md) · [功能与默认设置](docs/firmware.md) · [升级与恢复](docs/upgrade.md) · [开发维护](docs/development.md)

---

基于 [LiBwrt](https://github.com/LiBwrt/LibWrt)、[NSS packages](https://github.com/laipeng668/nss-packages)、[VIKINGYFY packages](https://github.com/VIKINGYFY/packages)、[Honk / Doona](https://github.com/daeuniverse/honk/releases/tag/v0.1.0-beta.6) 和 [Aurora](https://github.com/eamonxg/luci-theme-aurora)。构建器许可证：[GPL-2.0-only](LICENSE)；各组件沿用自己的许可证。
