# 构建与 CI（只允许 CI 编译内核）

**铁律：内核、镜像不在本机编译。** 本机 2 核/11 GB、无 ccache；唯一构建
通道是 GitHub Actions。本机只做 `dtc`/`fdtoverlay`/`mkbootimg` 装配与
`dpkg-deb` 打包。详见根 `AGENTS.md` §0.1。

## 1. 上游与分支

- 唯一上游：工作区 `linux/`（Linux 主线）。7.3 基座从 `v7.3` tag 合并，
  7.4 也从它来；`sm8450-mainline/linux` 只是内核仓的历史来源，不是上游。
- 内核仓 `linux-sm8450-liuqin` 的设备分支：**`liuqin-7.3`**，
  当前 tip `c03e1015c71d`（`7.3.0-gc03e1015c71d`）。
- 集成仓 `xiaomipad-6pro-mainline` 的本机工作分支：**`liuqin-7.3`**；
  `main` 只保留参考项目 v0.6.0 的历史骨架，不再更新。

## 2. 内核 CI 与 artifact 契约

推内核仓 `liuqin-7.3` 触发 `linux-sm8450-liuqin/.github/workflows/liuqin.yml`
（`runs-on: ubuntu-24.04-arm`，原生 arm64）。它 checkout 集成仓
`liuqin-7.3` 的 `.github/actions/kernel` 共享 action，不需要跨仓写 token。

产物由用户放进工作区根的 `ci/`，**agent 不下载**：

```
ci/liuqin-kernel-<40 位 SHA>/
├── kernel/          Image、sm8475-xiaomi-liuqin.dtb、.config、vmlinux、
│                    System.map、SHA256SUMS、build-info.json
└── kernel-modules/  modules.tar、modules.manifest、kernel.release、
                     kernel.commit、SHA256SUMS
```

使用前必须：

1. `build-info.json.commit` 与目录名一致；
2. `sha256sum -c SHA256SUMS` 两目录都过。

`build-info.json` 里的 `product_kernel_commit` 是**构建当时的
`kernel/source.json` 锁值**，用于区分 development 与 product-input 构建；
它不是当前运行内核的提交，不要拿它当 tip。

## 3. 本机装配 boot 镜像

```sh
A=ci/liuqin-kernel-<sha>/kernel
KERNEL_OUT="$PWD/$A" OUT_DIR="$PWD/repack/<sha>-boot" \
DTC=/usr/bin/dtc FDTOVERLAY=/usr/bin/fdtoverlay \
  sh xiaomipad-6pro-mainline/tools/lib/build-bootimg.sh
```

- **必须显式传 `DTC`/`FDTOVERLAY`**：脚本默认到 artifact 里找 `scripts/dtc/`，
  CI 产物不含构建工具。
- CMDLINE 与 ramdisk 决定行为；换内核时若两者不变，差异只在 Image/DTB，便于对照。
- 脚本内置 round-trip 校验（`cmp` Image/dtb/ramdisk、header cmdline、v2 layout），
  失败即装配有问题。
- 刷入：`fastboot flash boot_a`（A 槽直启）；试跑：`fastboot boot`。
- 两个 ramdisk 不要混：`out/ramdisk`（产品版，40,326,354 B，`a04d2b25…`）
  与 `xiaomipad-6pro-mainline/out/initramfs-liuqin/liuqin-firstboot.cpio.gz`
  （重建版，30,930,155 B，`1690e9ec…`）。

## 4. 系统镜像与安装包（可选，需专用主机）

`tools/build-liuqin-image.py` 是本地/CI 装配入口，消费已完成的 product
kernel 构建与准备好的输入，不重编第三方依赖；`--stage` 可续跑。它需要
root、GNU tar、ACL/xattr、squashfs-tools、cpio、ARM64 binfmt；整包 CI
使用自托管 x86-64 runner（`liuqin-images`），默认手动触发。

**Android/双系统打包已移除**：不再生成 `liuqin_boot_ubuntu-*.zip` 或
`dualboot-tools.zip`，bundle 里不再带 KernelSU/切换工具。`--layout dual`
在安装器中直接报错。

输入来源必须是本机 **V14.0.9.0.TMYCNXM**：

- 原版 Ubuntu 桌面 base：脚本下载固定 ISO、校验后提取；
- 设备固件：`tools/build-liuqin-firmware-prep.sh`（输入池、
  `V14.../extracted`、音频拓扑、WLAN tuple）；
- ABL overlay/DTB：`V14.../analysis`（38 DTBO + 11 base DTB）；
- 音频拓扑：`tools/build-liuqin-audio-topology.sh`；
- 传感器：`tools/build-liuqin-sensors-stack.sh`（V14 提取物）。

> **已知缺口**：`device/firmware/` 里跟踪的 blob 仍是 2026-10-20 从
> `OS2.0.6.0` 导入的旧集（见 `STATUS.zh-CN.md` §7）。重提取 V14 前，
> 镜像里的固件不是 V14；不要声称已统一。

## 5. 内核 deb 与模块

```sh
sh xiaomipad-6pro-mainline/tools/build-liuqin-debs.sh kernel
# → out/liuqin-debs/liuqin-kernel_0.1_arm64.deb
```

纯文件包（无维护脚本、无 `Depends`）：756 `.ko` + `/boot/{vmlinuz,initrd,dtb}`。
装到平板后 `depmod`/`update-initramfs` 由用户态处理；不要与不同内核的
Image/DTB 混用。

## 6. 发布

**本项目目前没有公开发布包。** 不要使用 `yzddmr6` 的 Releases 或
`OS2.0.6.0` 的物料；参考项目的 v0.6.0 只是用户态起点，已经归档。
只有在本机完整安装、冷启动、功能复核后，才能把 bundle 标为 `DEVICE_TESTED`。
