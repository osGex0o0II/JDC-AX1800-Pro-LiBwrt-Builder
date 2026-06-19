# JDC AX1800 Pro LiBwrt Builder

为 **JDC AX1800 Pro / 京东云无线宝亚瑟** 编译的 LiBwrt NSS 固件，基于 [LiBwrt/openwrt-6.x](https://github.com/LiBwrt/openwrt-6.x) `main-nss` 分支。

[![Build](https://github.com/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder/actions/workflows/build.yml/badge.svg)](https://github.com/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder/actions/workflows/build.yml)
[![License](https://img.shields.io/github/license/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder)](LICENSE)

> 本项目面向有经验的 OpenWrt/LiBwrt 用户。刷机、改分区和 U-Boot 操作均有变砖风险，执行前请确认设备型号、备份原厂分区，并准备好救砖手段。

## 特性

- 目标设备：`jdcloud_re-ss-01`
- Qualcomm IPQ60xx NSS 硬件加速
- 有线主路由取向，默认移除 ath11k Wi-Fi 相关包
- BBR + fq，内建 `sch_fq`，避免启动早期 sysctl 失败
- Aurora LuCI 主题，固定上游 commit
- 默认包含 HomeProxy/sing-box，固定 HomeProxy commit 并校验 Makefile SHA256
- 提供 `core-daed` 实验变体，用于评估 daed/eBPF 透明代理
- GitHub Actions 自动编译、上传 artifact、发布 Release
- Release 附带 manifest、固件 SHA256、上游源码信息和最终配置摘要
- 默认关闭 `ttyd`、packet steering 和 flow offloading，避免与 NSS 路径冲突

## 固件变体

| 变体 | 定位 | 主要内容 |
|:---|:---|:---|
| `core` | 日用主路由 | NSS、HomeProxy、sing-box、ZeroTier、IPv6、UPnP、Samba、统计、USB 存储、CoreMark |
| `core-daed` | eBPF 代理实验版 | 在 `core` 基础上替换为 daed/luci-app-daed，并启用 BPF/BTF/XDP 相关配置 |
| `ultimate` | 全功能版 | 在 `core` 基础上增加 Docker、Dockerman、Aria2、DiskMan、更多文件系统支持 |

`core-daed.config` 是在 `core.config` 上叠加的实验配置，`ultimate.config` 是在 `core.config` 上叠加的全功能配置。`ultimate` 不叠加 `core-daed.config`，避免同时包含两套代理方案。

上游 LiBwrt `main-nss` 中该设备定义为 `JDCloud RE-SS-01`，配置符号为 `CONFIG_TARGET_qualcommax_ipq60xx_DEVICE_jdcloud_re-ss-01`，对应本项目的 JDC AX1800 Pro / 亚瑟。

## 使用 GitHub Actions 编译

1. Fork 本仓库。
2. 进入 **Actions**，启用 workflow。
3. 打开 **Build JDC AX1800 Pro LiBwrt**。
4. 点击 **Run workflow**，选择 `core`、`core-daed` 或 `ultimate`。
5. 可选：在 `repo_commit` 填入 LiBwrt 上游 commit hash，用于固定源码版本。
6. 编译完成后从 workflow artifact 或 Releases 下载固件。

Actions 会在编译前校验目标设备和关键软件包，避免配置叠加失败或上游 defconfig 变化导致包被静默移除。

## 本地编译

```bash
git clone --depth 1 -b main-nss https://github.com/LiBwrt/openwrt-6.x.git openwrt
cd openwrt

# core
cp ../configs/core.config .config

# core-daed
# cat ../configs/core.config ../configs/core-daed.config > .config

# ultimate
# cat ../configs/core.config ../configs/ultimate.config > .config

./scripts/feeds update -a
./scripts/feeds install -a

mkdir -p files
cp -a ../files/. files/

# core/ultimate 复制 HomeProxy 默认项
cp -a ../files-homeproxy/. files/

# core-daed 需要额外复制 daed 默认项
# cp -a ../files-daed/. files/

# ultimate 需要额外复制 Docker/存储默认项
# cp -a ../files-ultimate/. files/

OPENWRT_PATH="$PWD" bash ../scripts/diy.sh core
make defconfig
make download -j"$(nproc)"
make -j"$(nproc)"
```

本地编译 `core-daed` 或 `ultimate` 时，请把配置叠加、overlay 复制和 `diy.sh` 的最后一个参数改成对应变体。

## 默认配置

| 项目 | 值 |
|:---|:---|
| 管理地址 | `192.168.1.1` |
| 用户名 | `root` |
| 密码 | OpenWrt 默认空密码，首次登录后请立即设置 |
| LuCI 语言 | 简体中文 |
| 默认主题 | Aurora |
| TTYD | 已安装，默认关闭 |
| flow offloading / packet steering | 默认关闭 |

## 刷机与升级

生成的固件通常包含：

- `*-factory.ubi`：用于从 U-Boot 或特定过渡环境首次刷入。
- `*-sysupgrade.bin`：用于已运行 OpenWrt/LiBwrt 时升级。

已运行 OpenWrt/LiBwrt 的设备可通过 LuCI「系统 - 备份/升级」上传 `sysupgrade.bin`，或通过 SSH 执行：

```bash
sysupgrade -n /tmp/JDC-AX1800-Pro-LiBwrt-*-sysupgrade.bin
```

跨大版本、跨分区布局、跨第三方固件升级时，建议不要保留旧配置。首次刷机和 U-Boot 相关操作请以你当前设备分区布局和救砖资料为准。

## 性能与稳定性说明

### NSS 与 flow offloading

本固件默认使用 NSS 作为主要加速路径，并在首次启动时关闭软件 flow offloading、硬件 flow offloading 和 packet steering。NSS 与 OpenWrt 的 flow offloading/packet steering 可能竞争数据包处理路径，混用可能导致吞吐下降或连接异常。

### BBR + fq

固件默认配置：

```text
net.core.default_qdisc=fq
net.ipv4.tcp_congestion_control=bbr
```

`scripts/diy.sh` 会把 `CONFIG_NET_SCH_FQ=y` 写入目标内核配置，确保系统启动早期就能设置 `fq`。

### 健康检查

固件内置 `/usr/sbin/jdc-healthcheck`，会检查：

- 默认路由
- 本地 dnsmasq 解析
- HomeProxy/sing-box 状态
- daed 状态
- Docker 状态
- 可用内存

`core`、`core-daed` 和 `ultimate` 变体会通过 cron 定期运行健康检查。脚本只做服务级恢复和日志记录，不会自动重启整机。

## 项目结构

```text
.
├── .github/workflows/
│   ├── build.yml          # 编译与发布
│   └── cleanup.yml        # 清理旧 workflow runs 和 releases
├── configs/
│   ├── core.config        # 基础配置
│   ├── core-daed.config   # daed/eBPF 实验配置
│   └── ultimate.config    # ultimate 增量配置
├── files/                 # 所有变体共用 overlay
├── files-homeproxy/       # HomeProxy/sing-box 默认项
├── files-daed/            # daed 默认项
├── files-ultimate/        # ultimate 专属 overlay
├── scripts/
│   ├── diy.sh             # 编译前自定义
│   ├── update-feeds.sh    # feeds 更新
│   └── version.sh         # 版本信息
├── patches/
├── docs/
├── README.md
└── LICENSE
```

## 自定义建议

- 修改包选择时优先编辑 `configs/*.config`，不要直接改 Actions 里的包列表。
- 增加运行时文件时优先放到对应 overlay：通用放 `files/`，HomeProxy 放 `files-homeproxy/`，daed 放 `files-daed/`，Docker/存储相关放 `files-ultimate/`。
- 更新 HomeProxy commit 时，同步更新 `HOMEPROXY_MAKEFILE_SHA256`。
- 更新 daed 时，同步更新 `DAED_COMMIT`，并优先在 `core-daed` 变体验证。
- 更新第三方 GitHub Actions 时，建议继续固定到具体 commit SHA。

## 致谢

- [LiBwrt/openwrt-6.x](https://github.com/LiBwrt/openwrt-6.x)
- [osGex0o0II/ZN-M2-LiBwrt-Builder](https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder)
- [immortalwrt/homeproxy](https://github.com/immortalwrt/homeproxy)
- [eamonxg/luci-theme-aurora](https://github.com/eamonxg/luci-theme-aurora)

## 许可证

[GPL-2.0-only](LICENSE)
