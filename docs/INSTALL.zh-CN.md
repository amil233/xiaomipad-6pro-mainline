# 安装 / 更新 / 恢复 —— 全新安装 Ubuntu 26.04 arm64（128G，A 槽单系统）

适用设备：Xiaomi Pad 6 Pro（liuqin，SM8475，**128G**，天马 `m81_36_02_0a`），
运行本工作区自建、附加了树外驱动的 Linux 7.3 内核（`liuqin-7.3`），
**从 A 槽直接启动**，设备上**没有 Android**，也没有任何旧内核。

> **新流程（2026-11 决策，取代旧安装器流程）**
>
> 本仓库**不再实现**参考项目式的"设备端安装器"
> （`installer.img` / `install.py` / `bundle.json` / 分区方案 / 设备侧
> `install-layout.sh` / `install-root.sh`）。实际设备内核工作流程只有一条：
>
> 1. **内核开发 → CI 编译 → ci/ 下载 → 本机装配完整 boot 镜像 → fastboot 刷入**
>    push 内核仓 `liuqin-7.3` → CI 出 artifact → 在本机 `ci/` 取
>    `ci/liuqin-kernel-<sha>/kernel` → `tools/lib/build-bootimg.sh` 装配完整
>    img（`repack/<sha>-boot/boot-liuqin-firstboot.img`）→ `fastboot flash boot_a`
>    （试跑 `fastboot boot`）。
> 2. **内核就绪 → 组装 rootfs → 刷入完整用户空间 / 或构建新内核 deb → 覆盖更新**
>    全新安装：装配出 rootfs（Ubuntu Base squashfs + 设备层），刷入完整
>    用户空间 Ubuntu 26.04 arm64（全新安装）；或构建新的内核 deb
>    （`tools/build-liuqin-debs.sh`）→ 在**现有系统**上覆盖安装更新
>    （`dpkg -i` / 等价更新），不再完全参照参考项目的安装脚本实现。
>
> **产品 / 开发不再区分**：我们不采纳参考项目里的"硬编码 sha 产品锁"，
> 只做一致性校验（CI artifact 与 `kernel/source.json` / `build-info` 锁定
> commit 一致才装配）。没有"产品版"与"开发版"两套 ramdisk / 镜像；唯一
> ramdisk 是 post-contract 版
> （`xiaomipad-6pro-mainline/out/initramfs-liuqin/liuqin-firstboot.cpio.gz`）。

## 1. 全新安装（新流程）

### 1.1 装配完整 boot 镜像并刷入

```sh
A=ci/liuqin-kernel-<sha>/kernel
KERNEL_OUT="$PWD/$A" OUT_DIR="$PWD/repack/<sha>-boot" \
DTC=/usr/bin/dtc FDTOVERLAY=/usr/bin/fdtoverlay \
  sh xiaomipad-6pro-mainline/tools/lib/build-bootimg.sh
fastboot flash boot_a repack/<sha>-boot/boot-liuqin-firstboot.img
```

- 装配参数（`DTC` / `FDTOVERLAY` / `HEADER_CMDLINE` / `partition_size` /
  `gzip -n -9` / ABL 校验 / round-trip）见 `docs/BUILD.zh-CN.md` §3；
  脚本内置 round-trip 校验，失败即中止装配。
- 刷入后冷启动验证（显示、触控、音频、Wi-Fi、GNOME 输入、指纹…），
  见 `docs/STATUS.zh-CN.md`。

### 1.2 组装 rootfs 并刷入完整用户空间

- 全新安装：从已装配的 CI artifact / 本机输入组装 rootfs，
  刷入完整 Ubuntu 26.04 arm64 用户空间（全新用户态）。
- 更新：构建新的内核 deb → 在现有系统上覆盖安装更新。

### 1.3 恢复原厂

- 原厂恢复路径：V14 线刷包（`V14.0.9.0.TMYCNXM`）`flash_all.sh`，
  见 `docs/STATUS.zh-CN.md` §7。

## 2. 更新（内核 ready → 装配 → flash，或 deb → 覆盖安装）

- **新内核**：push → CI → ci/ → 装配 → `fastboot flash boot_a` → 冷启动验证。
- **新用户空间**：同上组装 rootfs；或新 deb 覆盖安装。

## 3. 故障排查

- initramfs 内 USB 网络救援：telnet 2323（见 STATUS §2）。
- 刷机前先看 `repack/<sha>-boot/boot-liuqin-firstboot.info`（cmdline、ramdisk、
  ABL 元数据）。
- 已知问题与待办：`docs/STATUS.zh-CN.md` §6。
