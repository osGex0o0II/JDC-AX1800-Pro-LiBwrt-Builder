# Development

此项目维护一套 **core-only** 的 JDC AX1800 Pro / LiBwrt 构建配置。主要工作是固定设备行为、限制不需要的软件包，并记录上游源码与编译产物。

返回 [README](../README.md) · [Build](build.md) · [Firmware](firmware.md)

## Repository layout

```text
.github/workflows/build.yml          GitHub Actions 编译与发布
configs/core.config                  目标设备与软件包配置
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
| 增删固件软件包 | `configs/core.config` |
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
bash -n scripts/diy.sh scripts/update-feeds.sh scripts/verify-ipq6018-nss-region.sh
sh -n files/usr/sbin/jdc-healthcheck

bash tests/test-verify-ipq6018-nss-region.sh
python3 tests/test-remove-default-luci.py
```

这些只验证脚本的语法与部分回归条件，**不能证明** OpenWrt 依赖解析、完整编译或硬件行为正确。Pull Request 会触发 [Build workflow](../.github/workflows/build.yml) 进行实际构建；合并前应检查其最终 `Download packages` 和 `Compile firmware` 阶段。

## Dependency policy

- LiBwrt 默认使用 `25.12-nss`，可通过工作流 `repo_commit` 输入固定上游 40 位 SHA。
- 普通软件包和 Go 工具链取自上游 `feeds.conf.default` 所声明的 feeds。
- NSS firmware 由当前 NSS feed 的可选配置决定。
- sing-box 与 Aurora 优先严格稳定 semver 标签；HomeProxy 若未发布稳定标签，则跟随默认分支。
- HomeProxy/sing-box 的适配由 `diy.sh` 补丁及 CI 静态断言保护；实际设备的运行兼容性须单独测试。
- 不是所有可移动引用都能通过一个 `repo_commit` 锁定。需要精确复现时应保存完整依赖快照。

关于实际构建、来源追溯与 Artifact，请阅读 [Build guide](build.md)。

## Pull requests and releases

1. 在独立分支修改。
2. 对相关脚本和文档做本地验证。
3. 开启面向 `main` 的 Pull Request，等待完整构建。
4. 查看日志、版本清单和生成的 sysupgrade 文件，确认没有包选择回退或设备校验失败。
5. 合并后如需正式发布，仍需在 `main` 上**手动**触发 workflow；PR 构建不会发布固件。

仅更改说明文档时，不应声称新的固件功能、实机兼容或性能已经验证。若用户报告无法升级，应优先收集硬件版本、board id、分区布局、当前固件和 `sysupgrade -T` 结果，**不要提供未经验证的强刷指令**。

## Related upstreams

- [LiBwrt / LibWrt](https://github.com/LiBwrt/LibWrt)
- [Qualcomm NSS packages](https://github.com/qosmio/nss-packages)
- [ImmortalWrt packages](https://github.com/immortalwrt/packages)
- [HomeProxy](https://github.com/immortalwrt/homeproxy)
- [sing-box](https://github.com/SagerNet/sing-box)
- [Aurora](https://github.com/eamonxg/luci-theme-aurora)
