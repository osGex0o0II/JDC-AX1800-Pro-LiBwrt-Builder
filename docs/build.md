# Build guide

构建目标：`qualcommax/ipq60xx` · `jdcloud_re-ss-01` · `core` / `core-honk`。

返回 [README](../README.md) · [Firmware](firmware.md) · [Upgrade](upgrade.md)

## Build with GitHub Actions

这是项目使用的标准构建路径。

1. Fork 仓库并在 **Actions** 中启用工作流。
2. 打开 [Build JDC AX1800 Pro LiBwrt](https://github.com/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder/actions/workflows/build.yml)；在自己的 Fork 中执行。
3. 选择 `main` → **Run workflow**。
4. 选择 `core`、`core-honk` 或 `all`。`repo_commit` 留空使用已核验的 LiBwrt 提交；若覆盖，须填写 **40 位十六进制 SHA**。
5. 成功后在运行页面下载 `firmware-core` 或 `firmware-core-honk`。

面向 `main` 的 Pull Request 和合并后的构建只生成 Actions 产物。发布时在 `main` 上手动运行，并勾选 `publish`。两个变体使用独立 Release；`core-honk` 标为预发布。Release 只附该变体的 sysupgrade 镜像，SHA256 写在中文发布说明中。

> [!NOTE]
> GitHub Actions 属于持续构建服务。构建环境容量、上游源码、feeds 或网络连接变化都可能导致新的失败；某次绿色状态不能替代实机验证。

## Build locally

建议使用具备 OpenWrt 编译依赖的 **Linux** 环境，并准备足够的内存、磁盘空间和网络连接。项目的工作流会额外安装 LLVM/Clang、`dos2unix` 等工具；本地环境也需满足相同编译依赖。

以下命令从空目录开始；`builder` 与 `openwrt` 是同级目录：

```bash
git clone https://github.com/osGex0o0II/JDC-AX1800-Pro-LiBwrt-Builder.git builder
. builder/deps/firmware.env
git init openwrt
git -C openwrt remote add origin https://github.com/LiBwrt/LibWrt.git
git -C openwrt fetch --depth 1 origin "$OPENWRT_COMMIT"
git -C openwrt checkout --detach FETCH_HEAD

cd openwrt
export OPENWRT_PATH="$PWD"
variant=core  # 或 core-honk
bash ../builder/scripts/update-feeds.sh

mkdir -p files
cp -a ../builder/files/. files/
if [ "$variant" = core ]; then cp -a ../builder/files-homeproxy/. files/; fi
bash ../builder/scripts/configure-variant.sh "$variant" > .config

bash ../builder/scripts/diy.sh "$variant"

make defconfig
bash ../builder/scripts/verify-variant.sh "$variant" config .config
make download -j"$(nproc)"
make -j"$(nproc)"
```

重要说明：

- `diy.sh` 会修改当前工作目录下的上游源码、设备 recipe、内核配置和部分 feeds 文件；应在独立、可丢弃的源码副本中运行。
- `core.config` 与 `core-honk.config` 是配置请求。实际启用的组件应以 `make defconfig` 结果和镜像包清单为准。
- `core-honk` 构建需要支持 BTF 的宿主工具；先安装 `dwarves`（提供 `pahole`）及 Linux 编译依赖。
- 本地构建不等于通过 GitHub Actions 的全套断言；如需一致验证，应参照 [Development](development.md) 中的测试及工作流检查。

## Build outputs

GitHub Actions 为每个变体上传镜像、校验和、构建清单和包清单，保留 7 天。以 `core` 为例：

| 文件 | 用途 |
| --- | --- |
| `JDC-AX1800-Pro-LiBwrt-YYYY.MM.DD-core-sysupgrade.bin` | 用于受支持升级路径的镜像；**不是 factory 镜像** |
| `sha256sums-core` | 固件校验和 |
| `BUILD-MANIFEST-core.txt` | 构建器版本、上游提交、组件版本与镜像 SHA256 |
| `build-info-YYYY.MM.DD-core.tar.gz` | 配置、feeds 信息、profile 和包清单等构建资料 |

注意：源码树可能额外生成 factory 或 initramfs 文件，但本项目工作流**只上传 / 发布 sysupgrade 镜像**，不对其他镜像提供刷机支持。

## Versions and reproducibility

源码入口为 [`LiBwrt/LibWrt`](https://github.com/LiBwrt/LibWrt) 的 `25.12-nss`。默认使用 [`deps/firmware.env`](../deps/firmware.env) 和 [`deps/feeds.conf`](../deps/feeds.conf) 中固定的提交。NSS firmware 选用该 NSS feed 的最高可用版本。初始化脚本和 Honk 官方 ARM64 压缩包均校验 SHA256。

`core` 使用 ZN-M2 同一 VIKINGYFY feed 快照的 HomeProxy `20261026-r3` 与 sing-box `1.15.0-alpha.13`（配套预发布版本）；两个变体共用 Aurora `1.4.0`、集客 AC `2.2.20251015` 与配套 LuCI。定向更新了 Samba `4.22.11`、Go `1.26.11`、Dropbear `2026.94`、OpenSSH SFTP `10.6p2`、miniupnpd `2.3.11`、nftables `1.1.7`。实际安装版本见该次 Actions Artifact 中的：

- `BUILD-MANIFEST-core.txt`：LiBwrt、HomeProxy、Aurora、sing-box 等完整版本和提交。
- `build-info-*.tar.gz`：构建时的 `config.buildinfo`、`feeds.buildinfo`、`profiles.json` 和包清单（文件以实际存在为准）。
- `sha256sums-core`：sysupgrade 镜像的校验和。

`repo_commit` 只覆盖 LiBwrt 核心源码；其余锁保持不变，较老或不同底座可能和锁定 feeds、配方不兼容。需要复现时还应保存宿主环境信息和源码归档。

## Troubleshooting

- **配置校验失败**：检查 `make defconfig` 解析后的 `.config` 与工作流 `Download packages` 步骤日志，而不是直接删除校验。
- **下载错误 / 哈希不匹配**：检查 upstream 状态、网络和源码哈希；不要跳过完整性校验。
- **存储不足 / 编译被终止**：检查可用磁盘、内存、并行作业数，必要时降低 `make -j` 并发。
- **构建通过但设备不接受镜像**：这是升级兼容性问题，不是 CI 构建错误。参见 [Upgrade & recovery](upgrade.md)；不要强制刷入。
