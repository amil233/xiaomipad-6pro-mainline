# 状态（2026-11-24）

这里只写当前事实。内核版本、镜像哈希等会变的数字不抄进文档，用命令现场查：
`uname -r`、`git -C ../linux-sm8450-liuqin log -1`、`ls repack/`。

## 设备

| 项 | 值 |
|---|---|
| 设备 | Xiaomi Pad 6 Pro（liuqin，128G，天马 `m81_36_02_0a`，SM8475） |
| 系统 | Ubuntu 26.04 arm64 桌面（GNOME），单系统，没有 Android；新镜像基线改为 26.04.1 |
| 启动 | A 槽直接启动（`fastboot flash boot_a`）；`boot_b` 不参与启动 |
| 分区（现在） | 旧布局：`linux_root` + `linux_home`（2026 年由参考项目安装器划出） |
| 分区（目标） | 原厂分区表；`userdata` 是唯一数据分区（ext4，`LABEL=LIUQIN_ROOT`，根在 `native-root/` 下），没有单独的 `/home` 或 `/boot` 分区 |
| ROM | `V14.0.9.0.TMYCNXM` |
| 内核 | 内核仓 `liuqin-7.3`；平板实际跑哪个 commit，用 `uname -r` 对照 |
| 集成仓分支 | `liuqin-install` |
| 开发机 | Ubuntu 26.04.1 arm64，2 核 / 11 GB：做 boot.img、内核 deb、离线检查 |
| 构建机 | 另一台 arm64，磁盘要能同时放下 ISO、casper 层、解出的 root 和 tar；具体见 BUILD 第 4 节 |
| 刷机主机 | 通过 USB 连接平板：`fastboot`，把 `rootfs.tar.gz` 转成 ext4 镜像 |

## 安装与更新

构建机产出 `boot.img` + `rootfs.tar.gz`，刷机主机把 tar 转成 `rootfs.img`，
平板刷 `boot_a` 和 `userdata`。只换内核时，刷 `boot_a` 并在系统里装新的内核
deb；动了用户态时，boot.img 和 rootfs 一起换。步骤见
[`INSTALL.zh-CN.md`](INSTALL.zh-CN.md)，产物见 [`BUILD.zh-CN.md`](BUILD.zh-CN.md)。

## 已验证

- 显示：2 LM / 2 DSC、双 DSI、120 Hz、天马面板。
- 触控：Novatek `nt36523`（SPI）+ 天马固件自动更新。
- 音频：48 kHz / 4 声道 / 24-bit / 4×32-bit slot 的 TDM，四颗 CS35L41；
  `speaker-test -D hw:0,0 -c 4 -r 48000 -F S24_LE -t sine -l 1` 出声。
- 桌面：GNOME 可登录；USB 网络救援（initramfs `telnet 192.168.7.2 2323`）。
- 持久化：根分区和独立 `/home`（旧布局下）可读写。
- 恢复：原厂 V14 线刷包可以整机回退。

## 未验证或不支持

| 项 | 状态 | 说明 |
|---|---|---|
| 指纹 | 未验证 | v0.6.0 时代在参考项目上验证过，这台平板的 7.3 内核没有重测 |
| 相机 | 未验证 | 只在临时启动的相机内核上试过；完整镜像没有带相机启动 |
| 自动亮度 | 不支持 | 参考项目 v0.6.1 以后才有，没有合并 |
| 连接器温度 | 不支持 | 内核里没有对应代码 |
| 单数据分区安装 | 未验证 | 工具已就绪（构建机生成镜像），还没在平板上走过一遍 |
| 第一次启动的校准 | 未验证 | `provision-liuqin-from-persist.sh` 已在桌面环境支持，但新布局镜像没实测 |

## 已知问题

| 问题 | 现状 |
|---|---|
| 关机后插电自动开机 | 看 `/proc/cmdline` 里的 `off-mode-charge`；可试 `fastboot oem off-mode-charge 0` |
| 亮度重启后重置 | 背光驱动是模块，查 `systemd-backlight@` 启动顺序 |
| 接电脑 USB 掉电 | 电流上限停在 100 mA；原厂靠 USB 枚举抬到 500 mA，内核里没有这个处理 |
| 音频边角 | 只接受 48k/4ch/24-bit；强制 2ch/S16 的应用会被拒 |
| 分区迁移 | 当前平板还是旧布局；换成原厂表单数据分区要先刷 V14 整包，会清空整机 |
| 升级 7.4 | 等正式版；合并冲突先记在 `archive/kernel-v73-divergence.md` |

## 文档

| 文档 | 内容 |
|---|---|
| [`INSTALL.zh-CN.md`](INSTALL.zh-CN.md) | 刷机、更新、回滚 |
| [`BUILD.zh-CN.md`](BUILD.zh-CN.md) | 从源码到可刷产物 |
| [`archive/`](archive/) | 历史记录，不再维护 |
