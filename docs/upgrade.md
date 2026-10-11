# Upgrade & recovery

此文档适用于**已运行兼容 OpenWrt/LiBwrt、并能使用 sysupgrade 的 JDC AX1800 Pro**。它不是从原厂系统首次刷机的教程。

返回 [README](../README.md) · [Download](../README.md#download) · [Firmware](firmware.md)

> [!CAUTION]
> **没有经过验证、可以覆盖全部硬件和分区布局的刷机方案。** 构建成功仅代表生成了镜像。无法确认设备身份、分区、升级兼容性或救砖途径时，不要刷入固件。

## Before you upgrade

请依次确认：

1. **设备身份**：核对机型、主板及硬件版本，不要仅根据外壳名称推断。
2. **现有固件与分区布局**：确认当前运行的固件提供兼容的 `sysupgrade`，并检查 board id、HLOS 分区与目标镜像是否匹配。
3. **恢复条件**：已经明确并准备好适用于自己设备的恢复方案，而不是依赖本仓库提供救砖包。
4. **备份已完成**：保存配置、网络信息、SSH 公钥和关键分区数据；确认备份可读取。
5. **操作可中断风险**：使用稳定供电和有线连接，安排允许设备离线的维护时间。

可在当前系统内收集基础信息（命令是否存在取决于现有固件）：

```sh
cat /tmp/sysinfo/board_name
cat /etc/openwrt_release
cat /proc/partitions
block info
```

如果 board id、分区结构或升级程序与你了解的目标不一致，应停止并先查证；**不要通过修改设备标识或强制参数绕过检查**。

## Download and verify

在 [Releases](https://github.com/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder/releases) 或 [Actions](https://github.com/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder/actions/workflows/build.yml) 下载相同构建的 `*-core-sysupgrade.bin` 及 `sha256sums` / `sha256sums-core`。

将校验和与镜像放在同一个目录，在电脑上执行：

```sh
sha256sum -c sha256sums-core
```

若使用 Release，其校验文件可能命名为 `sha256sums`，应按实际文件名执行。**校验和不匹配必须停止**。同时检查 `BUILD-MANIFEST-core.txt` 内的上游提交、设备目标和组件版本。

## Back up first

OpenWrt 提供的配置备份命令通常为：

```sh
sysupgrade -b /tmp/router-config-backup.tar.gz
```

执行后将备份文件传到电脑，并确认可读取。请注意：**配置备份不等于完整 eMMC/分区备份**，不能用于恢复 bootloader、分区表或所有固件分区。

如果需要完整存储设备备份，必须先核实**真实块设备、容量、分区表以及目标电脑的剩余空间**。不同固件可能使用不同设备节点；不要盲目复制网上的 `dd` 指令，也不要将整盘备份写入路由器内存盘 `/tmp`。

## Upgrade with LuCI

仅当当前系统支持且镜像通过兼容性检查时：

1. 登录当前 LuCI，打开 **系统 → 备份/升级**。
2. 选择对应构建的 `*-core-sysupgrade.bin`。
3. 查看设备兼容性检查结果；若提示不兼容，立即停止。
4. 跨固件或大版本升级时，**不要保留旧配置**，避免导入不兼容配置。
5. 确认具备恢复手段后再执行刷写，并等待设备完成启动。

## Upgrade with SSH

同样要求**当前系统能够正确接受目标镜像**。下例在电脑端执行，`router-ip`、镜像名和认证方式按实际情况替换：

```sh
scp ./JDC-AX1800-Pro-LiBwrt-YYYY.MM.DD-core-sysupgrade.bin \
  root@router-ip:/tmp/firmware.bin

ssh root@router-ip 'sysupgrade -T /tmp/firmware.bin'
```

第二条命令必须成功返回，才能继续评估刷机；但**校验通过也不能单独证明分区布局与硬件完全安全**。

确认设备、备份和恢复路径全部符合要求后，才可执行：

```sh
ssh root@router-ip 'sysupgrade -n /tmp/firmware.bin'
```

`-n` 表示不保留旧配置。刷机后 IP、凭据及 SSH 公钥可能恢复到新系统默认状态，提前准备有线控制路径。

**禁止使用 `sysupgrade -F` 或其它手段强制跳过兼容性验证。**

## Recovery boundary

本项目不提供：

- 原厂系统首次刷入的 `factory.bin` 安装流程；
- 已验证的 U-Boot Web、TTL/TFTP、9008 等恢复镜像；
- 通用分区擦写地址、`mtd write` / `dd` 写入命令或跨布局迁移承诺。

当设备无法启动或镜像被拒绝时，应优先使用**硬件版本和实际分区布局完全匹配**、来源和哈希均可验证的官方或可信恢复资料。不要将 `sysupgrade.bin` 当作单分区镜像写入。

## After boot

检查 LAN、LuCI 访问、NSS/ECM 模块、DNS、Samba、ZeroTier 和 HomeProxy 的实际状态；再恢复必要的配置。可参考 [Firmware](firmware.md) 的巡检与安全默认项。

GitHub Actions 的绿色构建状态**不是**上述设备运行检查的替代品。
