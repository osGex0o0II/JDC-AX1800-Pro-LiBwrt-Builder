# Firmware

**core** 是面向 JDC AX1800 Pro 的纯有线主路由配置。本页介绍编译目标和默认行为，不保证任意设备或已有系统均可直接升级。

返回 [README](../README.md) · [Build](build.md) · [Upgrade](upgrade.md)

## Hardware target

| 项目 | 配置 |
| --- | --- |
| 目标平台 | Qualcomm IPQ60xx（`qualcommax/ipq60xx`） |
| 编译设备 | `jdcloud_re-ss-01` |
| 预期设备 | 京东云无线宝亚瑟 / JDC AX1800 Pro |
| 设备兼容标识 | `jdcloud,ax1800-pro`（构建期间补入 recipe） |
| 内存配置 | 512 MiB，NSS medium profile |
| 源码基线 | LiBwrt `25.12-nss`，内核 6.12（以构建清单为准） |

项目会将上游 JDCloud RE-SS-01 的 kernel slot 配置调整到 **12 MiB**，以适配项目研究的 AX1800 Pro HLOS 分区方案。**同名设备或相似型号不保证分区表相同**；升级前仍须核查实际硬件与当前固件的 sysupgrade 兼容性。

## What's included

- **Acceleration**：Qualcomm NSS、ECM、NSS PPPoE / qdisc 等内核组件，BBR + fq。
- **Proxy**：HomeProxy、sing-box、TProxy 依赖以及项目的兼容性处理。
- **Web UI**：LuCI 完整管理模块、Aurora 主题与简体中文语言资源。
- **Networking**：IPv6、ZeroTier、UPnP、Samba4、`ip-full` 和网络诊断工具。
- **Storage and utilities**：USB 存储、DiskMan、挂载工具、cpufreq、CoreMark、SFTP 等。

具体包的最终安装状态以对应构建的 `.config` 和镜像包清单为准。默认的 LuCI 软件包管理器元包没有包含；需要额外软件时，应考虑自行维护配置和重新构建。

## Wired-only design

构建过程主动移除 Wi-Fi 驱动与服务，包括 ath11k、mac80211、hostapd 和 NSS Wi-Fi mesh manager；并禁用设备树中的 Wi-Fi / WCSS/Q6 相关节点。

项目还会校验 **NSS 独立的 16 MiB 保留内存**没有被错误关闭。上游设备树中，与 Q6/WCSS 有关的 `q6_region` 在 512 MiB 布局下配置为 `0x03700000`（55 MiB），另有 Q6 ETR、M3 dump 保留区域各 1 MiB。项目会禁用相关无线节点，并单独验证 NSS 内存，但**最终释放量应以实际设备树与启动日志为准**。禁用 carveout 不意味着全部内存都能直接交还 Linux，也不代表 NSS 性能已通过实机测试。

该镜像定位于**无无线功能的有线路由器**，不是官方全功能固件的替代品。

## Defaults

| 项目 | 项目配置 |
| --- | --- |
| 主机名 | `JDC-AX1800-Pro` |
| LuCI | Aurora 主题，简体中文 |
| Web 服务 | `uhttpd` 启用 |
| SSH | Dropbear 禁用密码认证（需要公钥时请提前规划） |
| Web 终端 | `ttyd` 已安装，但默认不启用、不运行 |
| 加速路径 | 关闭软件/硬件 flow offloading 与 packet steering，优先使用 NSS |
| 拥塞控制 | `bbr` + `fq` |
| HomeProxy 订阅 | 禁用不安全 TLS 证书验证选项 |
| 自动巡检 | 每 5 分钟调用 `/usr/sbin/jdc-healthcheck` |

**管理地址和初始凭据不应从编译配置推断。** 新系统通常可通过设备 LAN 地址访问 LuCI，但必须以实际网络设置和初始化状态为准。尽早设置安全的管理员凭据，验证 SSH 公钥与恢复通道。

## Health checks

`jdc-healthcheck` 会检查默认路由、dnsmasq、DNS 查询、已配置的 HomeProxy/sing-box 状态以及可用内存。必要时会尝试重启相关服务，并设置冷却间隔避免频繁重启。

这属于**轻量运行状态检查**，不是完整的网络可用性测试或 NSS 性能监控。查看日志可用：

```sh
logread | grep jdc-healthcheck
```

配置代理前，应自行检查规则、订阅和 DNS；**内置组件或配置补丁能成功编译，不等于代理服务在设备上一定能启动或正常转发流量**。

## Limitations

- **没有 Wi-Fi。** 如果设备承担无线 AP 职责，请勿使用本配置。
- **不是 factory / recovery 镜像。** 不支持从原厂系统直接安装，也不提供已验证的 U-Boot、TTL/TFTP 或 9008 恢复方案。
- **不能承诺所有 AX1800 Pro 分区布局兼容。** 不使用 `-F` 强行跳过镜像检查。
- **动态依赖会变化。** HomeProxy、sing-box、Aurora 和 NSS feed 的版本应以每次构建记录为准。
- **没有实机验收结论。** CI 成功说明构建和约束检查通过；刷机、NSS 加速表现、Web 管理界面及代理运行仍需目标设备验证。

刷机前务必阅读 [Upgrade & recovery](upgrade.md)。
