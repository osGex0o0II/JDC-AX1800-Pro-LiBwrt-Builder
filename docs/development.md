# Development

此项目维护 `core` 和 `core-honk` 两个 JDC AX1800 Pro / LiBwrt 变体，共用设备和基础插件配置。

返回 [README](../README.md) · [Build](build.md) · [Firmware](firmware.md)

## Repository layout

```text
.github/workflows/build.yml          GitHub Actions 编译与发布
configs/core.config                  目标设备与软件包配置
configs/core-honk.config             Honk 变体的代理与内核覆盖
deps/                               固定的源码、feeds 与校验值
package/honk/                       Honk 和 LuCI 入口的打包配方
files/                               通用系统 overlay
files-homeproxy/                     HomeProxy 默认项与巡检定时任务
scripts/diy.sh                       上游设备、内核和软件包兼容调整
scripts/remove-default-luci.py       从上游默认包清单移除 LuCI 元包
scripts/update-feeds.sh              feeds 更新安装
scripts/verify-ipq6018-nss-region.sh NSS 保留内存校验
scripts/version.sh                   编译版本信息
tests/                               核心脚本回归测试
docs/                                项目使用和技术文档
```

`docs/` 是面向读者的稳定文档入口；`README.md` 只提供定位、下载、入门和导航。详细技术背景或流程改动应在对应专题文档更新，不要持续向首页堆砌历史记录。

## Where to make changes

| 想修改的内容 | 推荐位置 |
| --- | --- |
| 增删固件软件包 | `configs/core.config` 与 `configs/core-honk.config` |
| 设备分区/镜像 recipe、NSS 与内核调整 | `scripts/diy.sh` 与相关校验脚本 |
| 开机服务、LuCI 默认项 | `files/etc/uci-defaults/` |
| HomeProxy 首启配置 | `files-homeproxy/` |
| 编译流程、Artifact 和 Release 发布条件 | `.github/workflows/build.yml` |
| 版本与源码选择说明 | `docs/build.md` |
| 刷机注意事项 | `docs/upgrade.md` |

`diy.sh` 会在构建前修改外部源码；对其做任何更改都应同步更新对应检测条件，避免构建“成功”却遗漏必须的配置。不要直接关闭有价值的校验以掩盖依赖冲突。

## Validate changes

在拥有 Python 3 和 Bash 的开发环境中，可先运行无需完整 OpenWrt 编译的检查：

```sh
for script in scripts/*.sh tests/*.sh; do bash -n "$script" || exit; done
sh -n files/usr/sbin/jdc-healthcheck

bash tests/test-verify-ipq6018-nss-region.sh
python3 tests/test-remove-default-luci.py
bash tests/test-build-contracts.sh
```

这些只验证脚本的语法与部分回归条件，**不能证明** OpenWrt 依赖解析、完整编译或硬件行为正确。Pull Request 会触发 [Build workflow](../.github/workflows/build.yml) 进行实际构建；合并前应检查其最终 `Download packages` 和 `Compile firmware` 阶段。

## Dependency policy

- LiBwrt 和 feeds 通过 `deps/` 固定；更新源码时要同时检查 NSS feed 和设备 recipe。
- HomeProxy 与 sing-box 按 ZN-M2 的 feed 配套刷新；确认生成器要求的最低版本与 sing-box 匹配。
- 定向更新放在 `scripts/apply-package-updates.sh`。安全更新被 25.12 feed 吸收后，可删除相应覆盖。
- Honk 版本应与官方 ARM64 完整包的摘要和内嵌 Doona 版本一起更新。CI 校验 BTF、必需的包、变体互斥和 12 MiB HLOS 镜像上限；LAN DNS、NSS 和代理功能必须单独实测。

关于实际构建、来源追溯与 Artifact，请阅读 [Build guide](build.md)。

## Pull requests and releases

1. 在独立分支修改。
2. 对相关脚本和文档做本地验证。
3. 开启面向 `main` 的 Pull Request，等待完整构建。
4. 查看日志、版本清单和生成的 sysupgrade 文件，确认没有包选择回退或设备校验失败。
5. 合并后如需发布，在 `main` 手动触发并勾选 `publish`。`core-honk` 作为独立预发布，不替代 `core`。

仅更改说明文档时，不应声称新的固件功能、实机兼容或性能已经验证。若用户报告无法升级，应优先收集硬件版本、board id、分区布局、当前固件和 `sysupgrade -T` 结果，**不要提供未经验证的强刷指令**。

## Related upstreams

- [LiBwrt / LibWrt](https://github.com/LiBwrt/LibWrt)
- [Qualcomm NSS packages](https://github.com/qosmio/nss-packages)
- [ImmortalWrt packages](https://github.com/immortalwrt/packages)
- [HomeProxy](https://github.com/immortalwrt/homeproxy)
- [sing-box](https://github.com/SagerNet/sing-box)
- [Aurora](https://github.com/eamonxg/luci-theme-aurora)
