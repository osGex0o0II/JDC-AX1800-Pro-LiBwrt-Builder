# JDC AX1800 Pro LiBwrt Builder

为 **JDC AX1800 Pro / 京东云无线宝亚瑟** 编译的 LiBwrt NSS 固件，基于 [LiBwrt/openwrt-6.x](https://github.com/LiBwrt/openwrt-6.x) `main-nss` 分支。

[![Build](https://github.com/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder/actions/workflows/build.yml/badge.svg)](https://github.com/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder/actions/workflows/build.yml)
[![License](https://img.shields.io/github/license/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder)](LICENSE)

> 本项目面向有经验的 OpenWrt/LiBwrt 用户。刷机、改分区和 U-Boot 操作均有变砖风险，执行前请确认设备型号、备份原厂分区，并准备好救砖手段。
>
> **⚠️ factory 镜像不能通过 pepe2k U-Boot Web UI 刷入！** 详见下方[刷机与升级](#刷机与升级)章节。

## 特性

- 目标设备：上游 `jdcloud_re-ss-01`，实机兼容 ID `jdcloud,ax1800-pro`
- Qualcomm IPQ60xx NSS 硬件加速
- 有线主路由取向，默认移除 ath11k Wi-Fi 相关包
- BBR + fq，内建 `sch_fq`，避免启动早期 sysctl 失败
- Aurora LuCI 主题，固定上游 commit
- 默认包含 HomeProxy/sing-box；HomeProxy 构建时跟随上游 master，sing-box 构建时自动选择官方最新稳定版
- 默认包含 cpufreq、Samba、ZeroTier、ECM、DiskMan 和挂载支持
- 提供 `core-daede` 实验变体，用于评估 dae/daed eBPF 透明代理，包源固定为 `kenzok8/openwrt-daede`
- GitHub Actions 自动编译、上传 artifact，并按日期合并发布 Release
- Release 附带精简下载表、manifest、固件 SHA256、上游源码信息和最终配置摘要
- 默认关闭 `ttyd`、packet steering 和 flow offloading，避免与 NSS 路径冲突

## 固件变体

| 变体 | 定位 | 主要内容 |
|:---|:---|:---|
| `core` | 日用主路由 | NSS/ECM、cpufreq、HomeProxy、sing-box、ZeroTier、IPv6、UPnP、Samba、DiskMan、挂载、USB 存储、CoreMark |
| `core-daede` | eBPF 代理实验版 | 在 `core` 基础上替换为固定 commit 的 `kenzok8/openwrt-daede`，包含 `dae`、`daed` 和 `luci-app-daede`；默认选择 `daed` backend |
| `ultimate` | 存储下载增强版 | 在 `core` 基础上增加 Aria2、NTFS3/Btrfs/FUSE 和更多 USB 工具，不包含 Docker |

`core-daede.config` 是在 `core.config` 上叠加的实验配置；`luci-app-daede` 默认选择 `daed` backend，同时显式安装 `dae`，因为上游 daede 页面仍会调用 `/usr/bin/dae` 做 DSL 校验和版本检测；不再保留旧 `luci-app-dae` / `luci-app-daed` 入口和本项目自写的 DAE 控制、编辑、日志补丁。上游 daede 的 LuCI 辅助脚本会直接调用 `curl`、`uclient-fetch` 和 `ucode`，本项目在该变体中显式保留并体检这些工具，同时核对 BusyBox 默认提供 `flock`。构建脚本会把 daede 深色样式限定在页面内，避免进入 daede 后改写全局 LuCI 深浅色状态，并让关键按钮、圆角和焦点色跟随 Aurora 主题变量。`ultimate.config` 是在 `core.config` 上叠加的存储下载增强配置。`ultimate` 不叠加 `core-daede.config`，避免同时包含两套代理方案。

上游 LiBwrt `main-nss` 中该设备定义为 `JDCloud RE-SS-01`，配置符号为 `CONFIG_TARGET_qualcommax_ipq60xx_DEVICE_jdcloud_re-ss-01`，对应本项目的 JDC AX1800 Pro / 亚瑟。实机 QWRT/iStoreOS 分区布局使用 eMMC GPT，board id 为 `jdcloud,ax1800-pro`，HLOS/HLOS_1 为 12 MiB；构建脚本会在编译阶段把上游 recipe 的 kernel slot 从 6 MiB 调整到 12 MiB，并加入该兼容 ID。

出于攻击面和日常需求权衡，`core` 基底不再内置 QuickFile-Go 或其它 LuCI 文件管理器；需要文件操作时建议通过 SSH/SFTP 完成。

## 使用 GitHub Actions 编译

1. Fork 本仓库。
2. 进入 **Actions**，启用 workflow。
3. 打开 **Build JDC AX1800 Pro LiBwrt**。
4. 点击 **Run workflow**，默认选择 `all` 一次构建 `core`、`core-daede` 和 `ultimate`，并发布到同一个日期 Release。
5. 可选：在 `repo_commit` 填入 LiBwrt 上游 commit hash，用于固定源码版本。
6. 编译完成后从 workflow artifact 或 Releases 下载固件。

也可以只选择 `core`、`core-daede` 或 `ultimate` 单独构建；任意选择只要构建成功都会更新当天 Release。同名固件资产会由最新构建自动覆盖，Release 中只保留当前同名固件。

Actions 会在编译前校验目标设备和关键软件包，避免配置叠加失败或上游 defconfig 变化导致包被静默移除。

## 本地编译

```bash
git clone --depth 1 -b main-nss https://github.com/LiBwrt/openwrt-6.x.git openwrt
cd openwrt

# core
cp ../configs/core.config .config

# core-daede
# cat ../configs/core.config ../configs/core-daede.config > .config

# ultimate
# cat ../configs/core.config ../configs/ultimate.config > .config

./scripts/feeds update -a
./scripts/feeds install -a

mkdir -p files
cp -a ../files/. files/

# core/ultimate 复制 HomeProxy 默认项
cp -a ../files-homeproxy/. files/

# core-daede 需要额外复制 daede 默认项
# cp -a ../files-daede/. files/

# ultimate 需要额外复制存储下载增强默认项
# cp -a ../files-ultimate/. files/

OPENWRT_PATH="$PWD" bash ../scripts/diy.sh core
make defconfig
make download -j"$(nproc)"
make -j"$(nproc)"
```

本地编译 `core-daede` 或 `ultimate` 时，请把配置叠加、overlay 复制和 `diy.sh` 的最后一个参数改成对应变体。

## 默认配置

| 项目 | 值 |
|:---|:---|
| 管理地址 | `192.168.1.1` |
| 用户名 | `root` |
| 密码 | `password`，首次登录后请立即修改 |
| LuCI 语言 | 简体中文 |
| 默认主题 | Aurora |
| 主机名 | `JDC-AX1800-Pro` |
| TTYD | 已安装，默认关闭 |
| flow offloading / packet steering | 默认关闭 |

## 刷机与升级

> **⚠️ 重要：factory 镜像不能通过 pepe2k U-Boot Web UI 刷入！**
>
> JDC AX1800 Pro 的 pepe2k U-Boot Web UI 会将 factory 镜像写入 `0:HLOS` 分区（仅 12 MB），
> 而本固件 factory 镜像约 57 MB，**超出分区大小会导致数据溢出、分区表损坏、设备变砖**。
> 请严格按下方说明选择刷机方式。

### 生成的固件文件

| 文件 | 用途 | 刷入方式 |
|:---|:---|:---|
| `*-factory.bin` | 首次刷入 / 全新 U-Boot 恢复 | 仅限 **TTL 串口 + TFTP**（见救砖章节） |
| `*-sysupgrade.bin` | 已运行 OpenWrt/LiBwrt 时升级 | LuCI Web 界面 或 `sysupgrade` 命令 |

### 方式一：LuCI Web 界面升级（推荐）

适用于已运行 QWRT / iStoreOS / OpenWrt / LiBwrt 的设备。

1. 登录 LuCI → **系统 → 备份/升级**（System → Backup/Flash Firmware）。
2. 在「刷写新固件」区域点击「选择文件」，选择 `*-sysupgrade.bin`。
3. **取消勾选**「保留配置」（Keep settings），避免跨版本配置冲突。
4. 点击「刷写固件」，确认后等待设备自动重启。
5. 指示灯变绿后访问 `192.168.1.1`，默认密码为 `password`。

### 方式二：SSH 命令行升级

```bash
# 上传 sysupgrade.bin 到设备 /tmp 目录（可用 SCP、HTTP 下载等方式）
scp JDC-AX1800-Pro-LiBwrt-*-sysupgrade.bin root@192.168.1.1:/tmp/

# 刷入（不保留配置）
ssh root@192.168.1.1 "sysupgrade -F -n /tmp/JDC-AX1800-Pro-LiBwrt-*-sysupgrade.bin"
```

### 跨版本 / 跨固件升级注意事项

- 跨大版本、跨分区布局、跨第三方固件升级时，**不要保留旧配置**（使用 `-n`）。
- 从 QWRT/iStoreOS 升级到 LiBwrt 属于跨固件，建议先在 Web 界面取消「保留配置」。
- 首次从第三方固件刷入时，建议使用 `sysupgrade.bin` 而非 `factory.bin`。

## 救砖指南

### 分区布局说明

JDC AX1800 Pro 使用 eMMC GPT 分区，关键分区如下：

| 分区 | 标签 | 默认大小 | 说明 |
|:---|:---|:---|:---|
| mmcblk0p13 | 0:APPSBL | 640 KB | pepe2k U-Boot |
| mmcblk0p14 | 0:APPSBL_1 | 640 KB | U-Boot 备份 |
| mmcblk0p16 | 0:HLOS | **12 MB** | 内核（FIT 镜像） |
| mmcblk0p17 | 0:HLOS_1 | **12 MB** | 内核备份 |
| mmcblk0p18 | rootfs | 2 GB | 根文件系统（squashfs） |
| mmcblk0p20 | rootfs_1 | 60 MB | 根文件系统备份 |
| mmcblk0p22 | rootfs_data | 200 MB | 数据分区 |

> **factory 镜像约 57 MB，超出 HLOS 分区 12 MB 限制。**
> 通过 U-Boot Web UI 刷 factory 镜像会写入 HLOS 分区，溢出数据会破坏相邻分区导致变砖。
> **只能通过 TTL 串口 + TFTP 刷入 factory 镜像。**

### 变砖判断

| 现象 | 可能原因 | 恢复方式 |
|:---|:---|:---|
| 红灯常亮，无法访问 Web | 分区数据损坏，U-Boot 存活 | 重新进入 U-Boot 刷固件 |
| 红灯闪烁后蓝灯，Web 不通 | U-Boot 损坏或网卡不兼容 | TTL 刷 U-Boot + TFTP 刷固件 |
| 完全无灯，TTL 无输出 | 硬件损坏或 eMMC 损坏 | 9008 EDL 模式刷机（需拆机） |

### 恢复方式一：U-Boot Web UI 重新刷入（仅 U-Boot 存活时）

1. 断电，按住路由器背面 **Reset** 按钮不放。
2. 插电，持续按住约 10-15 秒，观察指示灯从红灯变为蓝灯后松开。
3. 电脑设置静态 IP：`192.168.1.2`，子网掩码 `255.255.255.0`。
4. 浏览器访问 `http://192.168.1.1` 进入 U-Boot Web UI。
5. **选择 `*-sysupgrade.bin` 文件刷入**（不要选择 factory 镜像）。
6. 等待指示灯变绿，系统启动完成。

### 恢复方式二：TTL 串口 + TFTP 刷入 factory 镜像

需要准备：
- CH340G USB 转 TTL 适配器
- 三根公对母杜邦线
- 拆机工具
- Tftpd64 软件

**步骤：**

1. **拆机**，找到主板上的 TTL 串口（TX/RX/GND）。
2. **连接 TTL**，使用 MobaXterm 或 PuTTY 打开串口终端（波特率 115200）。
3. **通电**，在终端中快速按 `Enter` 中断启动，进入 `IPQ6018#` 命令行。
4. **设置电脑 IP** 为 `192.168.10.1`，启动 Tftpd64。
5. **通过 TFTP 刷入 U-Boot 和固件**：

```bash
# 刷入 U-Boot（替换为实际文件名）
tftpboot uboot.bin && flash 0:APPSBL && flash 0:APPSBL_1

# 刷入 factory 镜像到 HLOS 分区
tftpboot factory.bin && flash 0:HLOS
```

6. 重启设备，进入新系统。

### 恢复方式三：9008 EDL 模式（硬砖终极方案）

当 U-Boot 也损坏时，需要拆机短接进入高通 9008 EDL 模式。

1. 拆机，找到主板背面的**启动电阻焊盘**（靠近 TTL 接口）。
2. 用镊子短接焊盘，同时插入电源，等 2 秒后松开。
3. 电脑连接路由器 USB 口，设备管理器应显示 `Qualcomm HS-USB QDLoader 9008`。
4. 安装高通 9008 驱动，使用专用线刷工具重写固件。

详细教程参考：
- [保姆级救砖指南](https://blog.csdn.net/garlic/article/details/154469720)
- [USB 救砖教程](https://www.scribd.com/document/854251949/)

### 备份建议

刷机前务必备份 eMMC 前 1111 MB（包含分区表和原厂分区）：

```bash
dd if=/dev/mmcblk0 bs=1M count=1111 of=/tmp/ax1800-backup.img
```

通过 SCP 或挂载的 SMB 共享将备份文件保存到电脑。

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
- dnsmasq 进程状态
- 系统解析路径
- HomeProxy/sing-box 状态
- daed/dae 状态
- 可用内存

`core`、`core-daede` 和 `ultimate` 变体会通过 cron 定期运行健康检查。脚本只做服务级恢复和日志记录，不会自动重启整机；DNS 查询失败只记录日志，不会因为上游解析瞬断而直接重启 dnsmasq。

## 项目结构

```text
.
├── .github/workflows/
│   ├── build.yml          # 编译与发布
│   └── cleanup.yml        # 清理旧 workflow runs 和 releases
├── configs/
│   ├── core.config        # 基础配置
│   ├── core-daede.config  # dae/daed eBPF 实验配置
│   └── ultimate.config    # ultimate 存储下载增强配置
├── files/                 # 所有变体共用 overlay
├── files-homeproxy/       # HomeProxy/sing-box 默认项
├── files-daede/           # daede 默认项
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
- 增加运行时文件时优先放到对应 overlay：通用放 `files/`，HomeProxy 放 `files-homeproxy/`，daede 放 `files-daede/`，ultimate 存储下载增强相关放 `files-ultimate/`。
- HomeProxy 和 sing-box 版本由 `scripts/diy.sh` 在构建时联网解析；构建摘要会记录实际 HomeProxy commit、sing-box 稳定 tag 和源码 SHA256。
- 更新 `core-daede` 时，同步核对 `DAEDE_COMMIT`、`dae` / `daed` / `luci-app-daede` 的 Makefile SHA256、`PKG_VERSION` / `PKG_HASH` / backend 依赖，以及 `luci-app-daede` 辅助脚本使用的 `curl` / `uclient-fetch` / `ucode` / BusyBox applet，并优先在 `core-daede` 变体验证。
- 更新第三方 GitHub Actions 时，建议继续固定到具体 commit SHA。

## 致谢

- [LiBwrt/openwrt-6.x](https://github.com/LiBwrt/openwrt-6.x)
- [osGex0o0II/ZN-M2-LiBwrt-Builder](https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder)
- [immortalwrt/homeproxy](https://github.com/immortalwrt/homeproxy)
- [eamonxg/luci-theme-aurora](https://github.com/eamonxg/luci-theme-aurora)
- [kenzok8/openwrt-daede](https://github.com/kenzok8/openwrt-daede)

## 许可证

[GPL-2.0-only](LICENSE)
