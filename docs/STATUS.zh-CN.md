# 当前整体状态（2026-11-18）

**这是唯一的状态源。** 其它文档里出现的提交号、镜像哈希、分区槽、ROM 版本、
固件来源若与本文冲突，以本文为准。历史取值与旧文档见 `docs/archive/`
（已冻结，不再维护），参考项目的文档见 `docs/archive/reference-v0.6.0/`。

## 0. 这台设备

| 项 | 值 |
|---|---|
| 设备 | Xiaomi Pad 6 Pro（liuqin，**128G**，天马 `m81_36_02_0a`），SM8475 |
| 系统 | Ubuntu 26.04 arm64 桌面（GNOME），**单系统，无 Android** |
| 启动 | **A 槽直接启动**（`fastboot flash boot_a`）；`boot_b` 保存安装时写入的 Ubuntu 副本，但**不从 B 启动** |
| 分区 | `linux_root`(#36, `LIUQIN_ROOT`) + `linux_home`(#37, `LIUQIN_HOME`)，从 userdata 尾部划出 |
| ROM | 原厂 `V14.0.9.0.TMYCNXM`（Android 13）——**唯一 ROM 输入** |
| 内核 | `liuqin-7.3` @ `c03e1015c71d`（`7.3.0-gc03e1015c71d`），已推送、CI 已构建 |
| 当前镜像 | `repack/c03e10-boot/`（50,065,408 B，sha256 `8977f56a…`），已上机点亮、电量正常 |
| 对照/回滚 | `repack/17abc-boot/`（`17abc027f75f`）、`repack/730fix-boot/`（`db08160915e3`） |
| 内核包 | `out/liuqin-debs/liuqin-kernel_0.1_arm64.deb`（release `7.3.0-gc03e1015c71d`，756 `.ko`） |
| 集成仓分支 | **`liuqin-7.3`**（本分支；`main` 只保留参考项目 v0.6.0 的历史骨架，不再更新） |
| 工作机 | 本机 2 核/11 GB：只做源码、装配、打包，**不编译内核** |
| 刷机主机 | 树莓派（只跑 fastboot 与保存备份/镜像） |

## 1. 与参考项目的关系（防止再混淆）

**唯一上游是主线 Linux，即工作区 `linux/`。** 内核 7.3 基座从它的 `v7.3`
tag 合并；`sm8450-mainline/linux` 只是内核仓的**历史来源**，不是上游。

`liuqin-6.17test`（yzddmr6）是**另一个项目**：6.17 内核、`OS2.0.6.0`
（HyperOS 2）ROM、安装器把 Ubuntu 写 B 槽。我们只在 2026 年基于它的集成仓
v0.6.0 搭了用户态骨架，此后设备事实（ROM、槽位、内核、构建）全部自建。

**2026-11-18 决策：它的文档不再作为任何依据。** 其双语 README、安装手册、
构建指南已整体移入 `docs/archive/reference-v0.6.0/`，只作历史取证；其中
"256 GB 开发机""B 槽安装""Android 双系统""OS2.0.6.0""6.17 内核"都不是本机事实。

## 2. 安装与槽位现状（已核实）

- 本机确实用这套安装器的 `--layout linux-only` 安装过，分区表、`linux_root`、
  `linux_home`、`boot_b` 都来自它；安装器当时写入 `boot_b` 并 `--set-active=b`。
- 之后做了**手动修正**：`fastboot flash boot_a`（零填充到 192 MiB 分区）+
  `fastboot --set-active=a`，所以现在从 A 槽启动；`boot_b` 里仍是那次安装写入的
  Ubuntu 副本，只作为残留备份，**不参与启动**。
- 本分支已把安装器 `linux-only` 的目标槽改为 **A**（`LINUX_ONLY_UBUNTU_SLOT='a'`），
  新安装不再需要手动改槽；`boot_b` 不再写入。
- **Android/双系统路径已移除**：Android 资产、KernelSU 回切模块、`liuqin-switch`
  及其桌面入口/polkit 动作、打包脚本都已删除；安装器对 `--layout dual` 直接报错。
  安装手册里"双系统切换""重启到 Android"整章作废。

## 3. 用户态：停在参考项目 v0.6.0

设备上的 `liuqin-firmware` / `liuqin-device-support` / `liuqin-sensors` 仍是
**v0.6.0 形态**，全部 `0.1` 版本并被 `apt-mark hold`；`device/` 相对
`release/v0.6.0` 只改过 2 个配置文件（`configs/liuqin-firstboot.config`、
`native-bootargs.txt`）。

参考项目 v0.6.1–v0.8.0 的用户态改动（充电策略、传感器 RPC、GNOME 键盘
guard、devmode、release notifier 等）**一条都没进设备**；其 `device/` 相对
v0.6.0 共 111 个文件、+6573/−532。是否补、补哪些仍是决策项，逐项取舍见
[`userspace-port.md`](userspace-port.md)。

**不要**把参考项目的功能表当成本机能力表：本机指纹、相机都按本文 §5 的状态。

## 4. 内核侧的版本关系（已核实到提交级）

| 批次 | 结论 |
|---|---|
| 参考项目 v0.6.1 / v0.6.2 的 24 个内核补丁 | 已移植在树（充电热敏与 cooling-level、CPU capacity + BWMON、GPU CX 投票、DPU resume OPP、a6xx HFI、lpass 时钟顺序、q6apm 采集、wcd938x RX 中断、qmp-combo/ucsi/hci_qca/geni-serial/rpmsg-glink、nt36523 调试属性等） |
| 参考项目 v0.7.0 的积压 | 只在已丢弃分支 `liuqin-7.3-v070`，**不在 `liuqin-7.3`** |
| 参考项目 v0.8.0 整批 | **2026-11-17 全部回退**（其前提是作者的 `OS2.0.6.0` 行为，本机 V14 不成立） |

`c03e1015c71d` = `17abc027f75f` + 3 个与充电无关的独立修复：
`0be8362d2405`（q6apm hw_ptr，与主线 `0337b8129cf6` 逐字节相同）、
`b30b611dcd58`（q6dsp-lpass-clocks NULL 解引用，上游化候选）、
`c03e1015c71d`（liuqin DTS 关闭未使用的 QCE）。

## 5. 已工作 / 未验证

**已工作**

- 显示：2 LM / 2 DSC、双 DSI bonded、120 Hz、天马面板 desc；点亮记录
  `db08160915e3`，当前 c03e10 继续点亮。
- 触控：Novatek `nt36523` 厂商驱动（SPI）+ 天马固件自动更新。
- 音频：48 kHz / 4 声道 / 24-bit / 4×32-bit slot 的 TDM，四颗 CS35L41 各占
  一个 slot；`speaker-test -c 4` 与桌面播放均出声（见 `AUDIO.zh-CN.md`）。
- 桌面：GNOME 可用；USB 网络救援（initramfs telnet 2323）、持久 root/home。
- 恢复：安装时 `--backup` 的原厂 boot_a/boot_b/persist/GPT 备份；
  `out/boot_a.img` 留档，产品 ramdisk 在 `out/ramdisk`。
- 内核 deb：756 `.ko` + `/boot/{vmlinuz,initrd,dtb}`，纯文件包。

**未验证（不要写成可用）**

| 功能 | 状态 | 依据 |
|---|---|---|
| 指纹 | 🧪 未验证 | v0.6.0 时代在参考项目上验证过；本机 7.3 内核**未重测**，引导日志与模板都未复核 |
| 相机 | 🧪 未验证 | 只在 `fastboot boot` 的相机内核上验证过；本项目完整镜像未带相机启动，且需去掉 `/etc/modprobe.d/liuqin-camcc.conf` 后再验 |
| 自动亮度 | ❌ 不支持 | 参考项目 v0.6.1+ 才有，未合并 |
| 连接器温度 | ❌ 树里没有 | v0.7.0 新增，随已丢弃分支 |

## 6. 已知问题 / 待办

| # | 问题 | 现状 / 下一步 |
|---|---|---|
| 1 | 关机后插电自动开机 | ABL `off-mode-charge:1`；先取证 `/proc/cmdline`，可试 `fastboot oem off-mode-charge 0` |
| 3 | 亮度重启后重置 | `ktz8866-backlight` 是模块，查 `systemd-backlight@` 时序 |
| 4 | 相机 | camcc GDSC 修复已在树（`66f4fbf82d26`）；去掉 `liuqin-camcc.conf` 后用完整镜像冷启动验证，未做前保持 🧪 |
| 5 | 音频边角 | 守卫只接受 48k/4ch/24-bit；强制 2ch/S16 的应用会被拒 |
| 6 | 升级 v7.4 | 等正式版；`merge-tree` 预演 13 个文件真冲突，见 `kernel-v73-divergence.md` |
| 7 | 连接器温度 | 树里没有；需要时单独立项 |
| 8 | 接电脑 USB 掉电 | SDP 上 `input_current_limit` 100 mA，原厂靠 gadget 枚举抬到 500 mA；树里没有该补丁 |
| 9 | 电压/电流计数值 | c03e10 上机已正常；v0.8.0 相关改动已回退，不要重引入 |
| 10 | 用户态版本落差 | 见 §3；合并与否待决策 |
| 11 | 安装器槽位 | 本分支已把 linux-only 目标改为 A；双系统路径已禁用。**下一次全新安装要复核 `--set-active=a` 与 `boot_a` 回读** |
| 12 | 固件集仍是 OS2 旧集 | 见 §7；在重提取前不要声称"固件已是 V14" |

**已撤销的登记（编号留空，避免其它文档的 `§5 #N` 引用错位）**

- **#2「长时间熄屏后屏幕键盘唤不出」——2026-11-18 撤销，不是缺陷。**
  实际是 GNOME 无障碍屏幕键盘未启用；与触控、面板 follower 都无关。
- 2026-11-18 复核：`FLASHING` 的 "33554432 扇区 = 16 GiB" 按 512 B 扇区计
  是正确的，不是换算错误。

## 7. 固件与 ROM 输入（V14 唯一，但树内 blob 仍待重提取）

- **唯一受支持的 ROM 输入是 `V14.0.9.0.TMYCNXM`。** 装配 boot 所需的
  ABL overlay/DTB 分析数据在
  `tools/local/roms/liuqin/V14.0.9.0.TMYCNXM/analysis`（38 DTBO + 11 base DTB）。
- 工具默认路径已全部指向 V14：`prepare-image-inputs.py`、`build-liuqin-firmware-prep.sh`、
  `build-liuqin-sensors-stack.sh`、`build-liuqin-wlan.py` 的输入/注释。
- **但 `device/firmware/` 里跟踪的 197 个 blob 是 2026-10-20 从 `OS2.0.6.0`
  导入的旧集**（提交 `dea2482` 的提交信息明写 OS2）。与本机 V14 提取池
  `tools/local/firmware-liuqin/` 对比：201 个跟踪文件中 135 个哈希不同、
  36 个在池里没有同名件（含 VPU、拓扑等）。触摸固件就是最直接的例子：
  树内 `novatek_nt36532_m81_fw_tm.bin` 是 `3d9737da…`，V14 池里是 `267f5eb0…`。
- **本机无法离线重提取 V14**：`V14.../extracted` 已被清理（只剩 `analysis`），
  且本机没有 `simg2img`/`lpunpack`/`debugfs`，`super.img` 是稀疏镜像，
  磁盘只剩 11 GB。因此"把树内固件换成 V14"必须在一台有 Android 解包工具、
  且能访问 V14 `super.img` 的机器上做，步骤：
  1. 解包 V14 `super.img` → `vendor_a`；
  2. 按 `tools/build-liuqin-firmware-prep.sh` 的输入布局重摆 pool（触摸、BT、
     WLAN、DSP、GPU、VPU、拓扑）；
  3. 运行固件准备脚本生成新树，替换 `device/firmware/usr/lib/firmware/`，
     重写 `firmware.manifest` 与 README；
  4. 冷启动验证 Wi-Fi/蓝牙/触控/音频/GPU 后，再在 STATUS 把 #12 划掉。
- **在 #12 完成前**：所有文档只写"目标/唯一输入是 V14"，不得写"固件池已
  全部来自 V14"。原 Android 双系统用的 `liuqin-rom-images.json`（OS2 校验表）
  已随 dual 路径一起删除，安装器改用设备常量 `PINNED_BOOT_BYTES = 192 MiB`。

## 8. 2026-11-18 决策记录

| 编号 | 决策 |
|---|---|
| 1 | 设备容量 **128G**；所有 256GB 表述作废 |
| 2 | **A 槽是唯一事实**；安装器 linux-only 目标槽改为 A |
| 3 | 本机确实用该安装器安装，之后手动刷 A 槽；文档按"安装器 + 手动修正"写 |
| 4 | 删除"A 槽启动组合尚未测试"的旧结论 |
| 5 | **移除/停止打包 Android 与双系统资产**；安装器 dual 路径禁用 |
| 6 | 双语 README 整体归档；项目不再维护英文文档 |
| 7 | **V14.0.9.0 是唯一 ROM 输入**；OS2 是参考项目的输入 |
| 8 | 指纹降为 🧪 未验证；相机标未验证 |
| 9 | `boot_b` 本机有安装时写入的副本，但**不从 B 启动** |
| 10 | 触控统一写"Novatek `nt36523`（SPI）"；面板驱动文件是 `panel-novatek-nt36532.c` |
| 11 | 上游 = 主线 `linux/`；`sm8450-mainline` 只是历史来源 |
| 12 | 集成仓新工作放在 `liuqin-7.3` 分支；`main` 保留 v0.6.0 历史 |

## 9. 文档索引

| 文档 | 内容 |
|---|---|
| `STATUS.zh-CN.md` | **本文**，唯一状态源 |
| `INSTALL.zh-CN.md` | 本机安装/重装/恢复：128G、A 槽单系统、安装器 + 手动修正 |
| `BUILD.zh-CN.md` | CI-only 内核构建、artifact 契约、本机装配与打包 |
| `FEATURES.zh-CN.md` | 指纹/相机/快充/Waydroid 的设备特定细节（状态以本文为准） |
| `display.md` | 显示点亮：结论、黄金值、判读陷阱 |
| `AUDIO.zh-CN.md` | 外放 TDM：数据通路、内核改动、诊断、复测 |
| `kernel-v73-divergence.md` | 相对主线 v7.3 的偏离清单 + 7.4 冲突与决策 |
| `userspace-port.md` | 用户态 v0.6.0→v0.8.0 的取舍清单（提案） |
| `archive/` | 冻结的历史取证；`archive/reference-v0.6.0/` 是参考项目旧文档 |

## 10. 构建 / 刷机工作流

```
内核源码改动 → 推 GitHub liuqin-7.3 → CI 出 artifact → ci/liuqin-kernel-<sha>/
  → 本机装配 boot 镜像：CI Image + dtb + initramfs + ABL overlay
    （repack/<sha>-boot/，放在工作区根目录）
  → 传到树莓派 → fastboot boot（试跑） / fastboot flash boot_a
模块：CI 的 modules.tar + Image + dtb → liuqin-kernel deb → 平板上 dpkg -i
```

- **内核只在 CI 编译**；本机只做 `dtc`/`fdtoverlay`/`mkbootimg` 装配和
  `dpkg-deb` 打包。详见 `BUILD.zh-CN.md`。
- **initramfs 两个来源，别混**：
  - `out/ramdisk`：产品版（从设备 boot_a 取出，40,326,354 B，sha256 `a04d2b25…`）；
  - `xiaomipad-6pro-mainline/out/initramfs-liuqin/liuqin-firstboot.cpio.gz`：
    2026-11-07 重建版（30,930,155 B，sha256 `1690e9ec…`），`17abc-boot` 与
    `c03e10-boot` 用的都是它。
- `ci/` 只保留最新两套 artifact；`repack/` 只保留当前、对照、回滚镜像。
