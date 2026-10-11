# Build guide

构建目标：`qualcommax/ipq60xx` · `jdcloud_re-ss-01` · **core**。

返回 [README](../README.md) · [Firmware](firmware.md) · [Upgrade](upgrade.md)

## Build with GitHub Actions

这是项目使用的标准构建路径。

1. Fork 仓库并在 **Actions** 中启用工作流。
2. 打开 [Build JDC AX1800 Pro LiBwrt](https://github.com/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder/actions/workflows/build.yml)；在自己的 Fork 中执行。
3. 选择 `main` → **Run workflow**。
4. 根据需要填写 `repo_commit`，留空表示使用构建当时 `25.12-nss` 的最新提交。填写时必须是 **40 位十六进制 SHA**。
5. 检查所有构建步骤。成功后在运行页面下载名为 `firmware-core` 的 Artifact。

工作流也会在面向 `main` 的 Pull Request 中自动测试并构建，但**不会将 PR 构建发布为 Release**。只有在 `main` 上手动触发且构建成功时，`Publish firmware release` 任务才会执行。

> [!NOTE]
> GitHub Actions 属于持续构建服务。构建环境容量、上游源码、feeds 或网络连接变化都可能导致新的失败；某次绿色状态不能替代实机验证。

## Build locally

建议使用具备 OpenWrt 编译依赖的 **Linux** 环境，并准备足够的内存、磁盘空间和网络连接。项目的工作流会额外安装 LLVM/Clang、`dos2unix` 等工具；本地环境也需满足相同编译依赖。

以下命令从空目录开始；`builder` 与 `openwrt` 是同级目录：

```bash
git clone https://github.com/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder.git builder
git clone --depth 1 --branch 25.12-nss https://github.com/LiBwrt/LibWrt.git openwrt

cd openwrt
./scripts/feeds update -a
./scripts/feeds install -a

mkdir -p files
cp -a ../builder/files/. files/
cp -a ../builder/files-homeproxy/. files/
cp ../builder/configs/core.config .config

OPENWRT_PATH="$PWD" bash ../builder/scripts/diy.sh core

make defconfig
make download -j"$(nproc)"
make -j"$(nproc)"
```

重要说明：

- `diy.sh` 会修改当前工作目录下的上游源码、设备 recipe、内核配置和部分 feeds 文件；应在独立、可丢弃的源码副本中运行。
- `core.config` 是配置请求，不是最终结果。`make defconfig` 会解析上游依赖；实际配置应以生成的 `.config` 为准。
- 默认选用上游最新稳定 sing-box/Aurora 标签；HomeProxy 若无稳定标签，则选用仓库默认分支。离线构建或上游不可用时，可能失败。
- 本地构建不等于通过 GitHub Actions 的全套断言；如需一致验证，应参照 [Development](development.md) 中的测试及工作流检查。

## Build outputs

GitHub Actions 的 `firmware-core` Artifact 包含：

| 文件 | 用途 |
| --- | --- |
| `JDC-AX1800-Pro-LiBwrt-YYYY.MM.DD-core-sysupgrade.bin` | 用于受支持升级路径的镜像；**不是 factory 镜像** |
| `sha256sums-core` | 固件校验和 |
| `BUILD-MANIFEST-core.txt` | 构建器版本、上游提交、组件版本与镜像 SHA256 |
| `build-info-YYYY.MM.DD-core.tar.gz` | 配置、feeds 信息、profile 和包清单等构建资料 |

注意：源码树可能额外生成 factory 或 initramfs 文件，但本项目工作流**只上传 / 发布 sysupgrade 镜像**，不对其他镜像提供刷机支持。

## Versions and reproducibility

源码入口为 [`LiBwrt/LibWrt`](https://github.com/LiBwrt/LibWrt)，默认分支 `25.12-nss`。普通软件包和工具链由当前上游 `feeds.conf.default` 决定；NSS firmware 从当前 NSS feed 选择可用最高版本。sing-box 与 Aurora 的严格稳定版本标签由构建脚本动态解析；HomeProxy 优先稳定标签，否则使用默认分支。

因此，**不要把 README 中的版本描述当作某次构建的固定版本**。查询该次 Artifact/Release 中的：

- `BUILD-MANIFEST-core.txt`：LiBwrt、HomeProxy、Aurora、sing-box 等完整版本和提交。
- `build-info-*.tar.gz`：构建时的 `config.buildinfo`、`feeds.buildinfo`、`profiles.json` 和包清单（文件以实际存在为准）。
- `sha256sums-core`：sysupgrade 镜像的校验和。

填写 `repo_commit` 可以锁定 LiBwrt 核心源码，但**不能单独锁定所有可移动的 feeds 与第三方标签**。需要严格复现时，应保存构建清单、feeds 的提交状态、源码归档和全部依赖版本。

## Troubleshooting

- **配置校验失败**：检查 `make defconfig` 解析后的 `.config` 与工作流 `Download packages` 步骤日志，而不是直接删除校验。
- **下载错误 / 哈希不匹配**：检查 upstream 状态、网络和源码哈希；不要跳过完整性校验。
- **存储不足 / 编译被终止**：检查可用磁盘、内存、并行作业数，必要时降低 `make -j` 并发。
- **构建通过但设备不接受镜像**：这是升级兼容性问题，不是 CI 构建错误。参见 [Upgrade & recovery](upgrade.md)；不要强制刷入。
