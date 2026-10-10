# JDC AX1800 Pro LiBwrt Builder

为 **JDC AX1800 Pro / 京东云无线宝亚瑟** 编译的 LiBwrt NSS 固件，基于 [LiBwrt/LibWrt](https://github.com/LiBwrt/LibWrt) `25.12-nss` 分支。

[![Build](https://github.com/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder/actions/workflows/build.yml/badge.svg)](https://github.com/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder/actions/workflows/build.yml)
[![License](https://img.shields.io/github/license/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder)](LICENSE)

> 本项目面向有经验的 OpenWrt/LiBwrt 用户。刷机、改分区和 U-Boot 操作均有变砖风险，执行前请确认设备型号、备份原厂分区，并准备好救砖手段。

## 特性

- 目标设备：上游 `jdcloud_re-ss-01`，实机兼容 ID `jdcloud,ax1800-pro`
- Qualcomm IPQ60xx NSS 硬件加速
- 有线主路由取向，移除设备 Wi-Fi 数据、ath11k/mac80211/hostapd 和 NSS Wi-Fi mesh 包，并释放 WCSS/Q6 保留内存
- BBR + fq，内建 `sch_fq`，避免启动早期 sysctl 失败
- Aurora LuCI 主题，构建时自动选择上游最新稳定 tag
- 默认包含 HomeProxy/sing-box；sing-box 1.14 与 HomeProxy 的启动兼容性仍需实测；HomeProxy 构建时优先选择上游最新稳定 tag，暂无稳定 tag 时跟随仓库默认分支；sing-box 自动选择官方最新稳定版
- NSS firmware 构建时从上游 nss-packages feed 自动选择当前可用最高版本
- 默认包含 cpufreq、Samba、ZeroTier、ECM、DiskMan 和挂载支持
- GitHub Actions 自动编译、上传 artifact，并按日期合并发布 Release
- Release 附带精简下载表、manifest、固件 SHA256、上游源码信息和最终配置摘要
- 默认关闭 `ttyd`、SSH 密码认证、packet steering 和 flow offloading，避免暴露不必要入口或与 NSS 路径冲突

## 固件配置

| 变体 | 定位 | 主要内容 |
|:---|:---|:---|
| `core` | 日用主路由 | NSS/ECM、cpufreq、HomeProxy、sing-box、ZeroTier、IPv6、UPnP、Samba、DiskMan、挂载、USB 存储、CoreMark |



上游 LiBwrt `25.12-nss` 中该设备定义为 `JDCloud RE-SS-01`，配置符号为 `CONFIG_TARGET_qualcommax_ipq60xx_DEVICE_jdcloud_re-ss-01`，对应本项目的 JDC AX1800 Pro / 亚瑟。实机 QWRT/iStoreOS 分区布局使用 eMMC GPT，board id 为 `jdcloud,ax1800-pro`，HLOS/HLOS_1 为 12 MiB；构建脚本会在编译阶段把上游 recipe 的 kernel slot 从 6 MiB 调整到 12 MiB，并加入该兼容 ID。

有线构建同时禁用 Wi-Fi、WCSS remoteproc 和 Q6 相关 reserved-memory 节点。Linux 基线中的 `q6_region` 长度为 `0x05500000`，但该设备使用的 512 MiB DTS 将其覆盖为 `0x03700000`，实际 carveout 是 55 MiB；另有 1 MiB 的 Q6 ETR 与 1 MiB 的 M3 dump 区域。这 57 MiB 不再因已移除的无线功能占用；NSS 自身独立的 16 MiB `nss_region` 继续保留。


出于攻击面和日常需求权衡，`core` 基底不再内置 QuickFile-Go 或其它 LuCI 文件管理器；需要文件操作时建议通过 SSH/SFTP 完成。

## 版本策略与核验快照（历史记录）

构建不会绕过 LiBwrt feed 强行替换其中每个软件包。OpenWrt 内核、工具链和普通软件包由所选 LiBwrt 源码的 `feeds.conf.default` 统一解析，以保持 ABI 和补丁兼容；`make download` 仍会校验各 recipe 的源码哈希。以下组件由本项目额外解析或固定。

| 组件 | 选择策略 | 2026-07-12 历史核验结果 |
|:---|:---|:---|
| LiBwrt | 项目基线为滚动的 `25.12-nss`；正式触发时使用完整 SHA 锁定 | `fff6bde9652cd23133b5dfe0db2a4e6ca3eeb49f`（历史快照；2026-10-10 上游 HEAD `3a3d0b08595530070ad9cd8a20c0ae4ea3e77f70`） |
| LiBwrt feed 软件包 | 更新并安装锁定源码所声明的全部 feeds；版本以最终 `.config`、manifest 和 buildinfo 为准 | 当前 `25.12-nss` feed 快照 |
| NSS firmware | 从 `nss_packages` feed 选择数值最高的可用版本 | `12.5`（Release 210；构建时再次解析并写入 manifest） |
| sing-box | 只接受严格 `vMAJOR.MINOR.PATCH`，排除 alpha/beta/rc | `v1.13.14` (`25a600db...`) |
| Aurora | 只接受严格稳定 semver tag | `v1.1.0` (`7cb99b5f...`) |
| HomeProxy | 优先稳定 semver tag；上游当前没有任何 tag 或 Release，因此跟随默认分支并记录完整 commit | `master` (`7826c263...`) |
| 构建环境脚本 | 下载后先核对固定 SHA256，再以 root 执行 | `85f4b2c2...6185dd8` |
| GitHub Actions | 使用各项目最新稳定 Release 对应的完整 commit SHA | checkout `v7.0.0`、cache `v6.1.0`、upload `v7.0.1`、download `v8.0.1`、maximize-build-space `v10`、release-action `v1.21.0` |

“最新稳定版”只适用于上游实际发布稳定 tag/Release 的组件。`25.12-nss` 和 HomeProxy 默认分支都是可移动引用，不能描述为稳定发布；每次 Release 的 `BUILD-MANIFEST-*.txt` 和 `build-info-*.tar.gz` 会记录本次解析到的完整 commit、版本和哈希，供复现与审计。

## 使用 GitHub Actions 编译

1. Fork 本仓库。
2. 进入 **Actions**，启用 workflow。
3. 打开 **Build JDC AX1800 Pro LiBwrt**。
4. 在 `main` 分支手动点击 **Run workflow**；测试 PR 自动编译但不发布 Release。
5. 可选：在 `repo_commit` 填入 LiBwrt 上游完整的 40 位 commit SHA，用于固定源码版本。
6. 编译完成后从 workflow artifact 或 Releases 下载固件。

Actions 会在编译前校验目标设备和关键软件包，避免配置叠加失败或上游 defconfig 变化导致包被静默移除。

## 本地编译

需要将本项目与上游源码克隆到同一目录下，再从 `openwrt` 目录执行。

```bash
git clone https://github.com/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder.git builder
git clone --depth 1 -b 25.12-nss https://github.com/LiBwrt/LibWrt.git openwrt
cd openwrt

cp ../builder/configs/core.config .config

./scripts/feeds update -a
./scripts/feeds install -a

mkdir -p files
cp -a ../builder/files/. files/

cp -a ../builder/files-homeproxy/. files/

OPENWRT_PATH="$PWD" bash ../builder/scripts/diy.sh core
make defconfig
make download -j"$(nproc)"
make -j"$(nproc)"
```


## 默认配置

| 项目 | 值 |
|:---|:---|
| 管理地址 | `192.168.1.1` |
| 用户名 | `root` |
| 初始登录 | LuCI 首次访问使用 `root` 和空密码，登录后立即设置强密码 |
| SSH | 默认禁用密码登录；需要 SSH 时先在 LuCI 中配置公钥 |
| LuCI 语言 | 简体中文 |
| 默认主题 | Aurora |
| 主机名 | `JDC-AX1800-Pro` |
| TTYD | 已安装，默认关闭 |
| flow offloading / packet steering | 默认关闭 |

## 刷机与升级

本项目**不发布 factory 镜像**，也没有经过验证、可用于 U-Boot Web 或 TTL/TFTP 的恢复镜像。Release 只包含 `*-sysupgrade.bin`，仅用于当前固件能够识别本机型并通过 OpenWrt/LiBwrt sysupgrade 校验的升级路径。不要把 sysupgrade 镜像写入单个 eMMC 分区，也不要在 U-Boot Web 中尝试刷入。

### 生成的固件文件

| 文件 | 用途 | 刷入方式 |
|:---|:---|:---|
| `*-sysupgrade.bin` | 已运行兼容 OpenWrt/LiBwrt 时升级 | LuCI 备份/升级页面或 `sysupgrade` 命令 |

### 方式一：LuCI Web 界面升级（推荐）

只适用于当前系统的固件校验能够接受该 sysupgrade 镜像的设备。

1. 登录 LuCI → **系统 → 备份/升级**（System → Backup/Flash Firmware）。
2. 在「刷写新固件」区域点击「选择文件」，选择 `*-sysupgrade.bin`。
3. **取消勾选**「保留配置」（Keep settings），避免跨版本配置冲突。
4. 点击「刷写固件」，确认后等待设备自动重启。
5. 系统启动后访问 `192.168.1.1`，使用 `root` 和空密码首次进入 LuCI，并立即设置强密码。

### 方式二：SSH 命令行升级

```bash
# 上传 sysupgrade.bin 到设备 /tmp 目录（可用 SCP、HTTP 下载等方式）
scp JDC-AX1800-Pro-LiBwrt-*-sysupgrade.bin root@192.168.1.1:/tmp/

# 先校验镜像；只有返回成功时才继续
ssh root@192.168.1.1 "sysupgrade -T /tmp/JDC-AX1800-Pro-LiBwrt-*-sysupgrade.bin"

# 刷入且不保留配置；不要使用 -F 绕过设备校验
ssh root@192.168.1.1 "sysupgrade -n /tmp/JDC-AX1800-Pro-LiBwrt-*-sysupgrade.bin"
```

### 跨版本 / 跨固件升级注意事项

- 跨大版本或跨第三方固件升级时不要保留旧配置（使用 `-n`）。
- `sysupgrade -T` 或 LuCI 固件校验拒绝镜像时立即停止；不要使用 `-F` 绕过检查。
- 当前系统若使用不同的分区布局、board id 或升级机制，本项目镜像不适用。

## 恢复边界

本项目没有已验证的 U-Boot Web、TTL/TFTP 或 9008 恢复包，也不提供首次从原厂系统刷入的 factory 镜像。设备无法正常启动或当前系统不接受 sysupgrade 时，应使用与设备硬件版本和现有分区布局严格匹配的完整恢复包；在确认来源、哈希和写入布局前不要执行分区写入命令。

### 备份建议

刷机前建议在电脑端直接接收 eMMC 前 1111 MiB，避免先把大文件写入路由器的 `/tmp`。以下命令在电脑上运行，并要求提前配置 SSH 公钥：

```bash
ssh root@192.168.1.1 "dd if=/dev/mmcblk0 bs=1M count=1111" > ax1800-backup.img
```

备份完成后在电脑上记录文件大小和 SHA256，并验证镜像可读，再开始升级。

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
- 可用内存


## 项目结构

```text
.
├── .github/workflows/
│   └── build.yml          # 仅编译 core；main 分支手动发布
├── configs/
│   └── core.config        # 唯一固件配置
├── files/                 # 通用系统配置 overlay
├── files-homeproxy/       # HomeProxy/sing-box 默认项
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
- 更新第三方 GitHub Actions 时，建议继续固定到具体 commit SHA。

## 致谢

- [LiBwrt/LibWrt](https://github.com/LiBwrt/LibWrt)
- [osGex0o0II/ZN-M2-LiBwrt-Builder](https://github.com/osGex0o0II/ZN-M2-LiBwrt-Builder)
- [immortalwrt/homeproxy](https://github.com/immortalwrt/homeproxy)
- [eamonxg/luci-theme-aurora](https://github.com/eamonxg/luci-theme-aurora)

## 许可证

[GPL-2.0-only](LICENSE)
