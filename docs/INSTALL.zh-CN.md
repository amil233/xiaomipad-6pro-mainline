# 安装 / 更新 / 恢复 —— 全新安装 Ubuntu 26.04 arm64（128G，A 槽单系统）

适用设备：Xiaomi Pad 6 Pro（liuqin，SM8475，**128G**，天马 `m81_36_02_0a`），
运行本工作区自建、附加了树外驱动的 Linux 7.3 内核（`liuqin-7.3`），
**从 A 槽直接启动**，设备上**没有 Android**，也没有任何旧内核。

> **2026-11 起的新流程（取代旧安装器流程）**
>
> 本仓库**不再实现**参考项目式的"设备端安装器"
> （installer.img / install.py / bundle.json / 分区计划 / 设备侧脚本）。
> 实际设备上的安装只有一条主线：
>
> 1. **内核开发 → CI 编译 → ci/ 下载 → 本机装配完整 boot 镜像 → fastboot 刷入**
> 2. **内核就绪 → 组装 rootfs → 刷入完整用户空间**
>    （全新安装）或 **构建新内核 deb → 在现有系统上覆盖安装**
>
> **产品 / 开发不再区分**：只有一套镜像、一套 ramdisk、一套固件集；CI
> artifact 与内核锁定 commit 一致才装配。

## 1. 全新安装

### 1.1 装配 boot 镜像并刷入内核

```sh
A=ci/liuqin-kernel-<sha>/kernel
KERNEL_OUT="$PWD/$A" OUT_DIR="$PWD/repack/<sha>-boot" \
DTC=/usr/bin/dtc FDTOVERLAY=/usr/bin/fdtoverlay \
  sh xiaomipad-6pro-mainline/tools/lib/build-bootimg.sh
fastboot flash boot_a repack/<sha>-boot/boot-liuqin-firstboot.img
```

- 刷入后冷启动验证：显示、触控、音频、Wi-Fi、GNOME 输入、指纹……，
  见 `docs/STATUS.zh-CN.md`。
- 装配参数与内置 round-trip 校验：见 `docs/BUILD.zh-CN.md` §3。

### 1.2 组装 rootfs 并刷入完整用户空间

- 全新安装：从已下载的 CI artifact / 本机输入组装 rootfs（Ubuntu Base
  squashfs + 设备层），刷入完整 Ubuntu 26.04 arm64 用户空间（全新用户态）。
- 更新：构建新的内核 deb（`tools/build-liuqin-debs.sh`），
  在**现有系统**上覆盖安装更新（`dpkg -i` 或等价操作）。

### 1.3 恢复原厂

- 原厂恢复：V14 线刷包（`V14.0.9.0.TMYCNXM`）`flash_all.sh`，
  见 `docs/STATUS.zh-CN.md` §7。

## 2. 更新

- **新内核**：push 内核仓 `liuqin-7.3` → CI 出 artifact → ci/ 下载 →
  本机装配 boot 镜像 → `fastboot flash boot_a` → 冷启动验证。
- **新用户空间**：同上组装 rootfs；或新 deb 覆盖安装。

## 3. 故障排查

- initramfs 内 USB 网络救援：telnet 2323（见 STATUS §2）。
- 刷机前先看 `repack/<sha>-boot/boot-liuqin-firstboot.info`（cmdline、ramdisk、
  ABL 元数据）。
- 已知问题与待办：`docs/STATUS.zh-CN.md` §6。
