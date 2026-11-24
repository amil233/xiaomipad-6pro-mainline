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

**唯一上游是主线 Linux，由内核仓 `linux-sm8450-liuqin` 的 `linux` remote
（torvalds/linux）直接同步。** 7.3 基座从 `v7.3` tag 合并；工作区不再单独
保留 `linux/` checkout。`sm8450-mainline/linux` 只是内核仓的**历史来源**，不是上游。

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
- 恢复：原厂 V14 快刷（`flash_all.sh`）；`out/boot_a.img` 留档。
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
| 11 | 安装器槽位 | 安装器流程已按新政策作废（不区分产品/开发，全新安装走"装配 → fastboot flash boot_a"新流程）。**下一次全新安装走 `repack/<sha>-boot` → `fastboot flash boot_a`**，无需再复核 installer。 |
| 12 | 固件集已对齐 V14（无需刷机） | 2026-11-18 从 V14 `super.img`/`NON-HLOS.bin`/`BTFM.bin` 重提取；设备已装 rootfs 的 `native.contract` 与其中 5 个固件逐字节相同，说明实机本来就在用这组文件，见 §7 |
| 13 | 安装器不再用 256GB 样例做预览 | 确认页现按设备 `userdata` 实际大小计算 `linux_root`/`linux_home`；`STOCK_TABLE` 只剩合成测试用，`--check` 不再打印虚构分区表 |
| 14 | 用户态 P0 已装机，contract 已更新 | 2026-11-18 的 `liuqin-device-support` 重编了 wlan-mac/power-keyd，旧 initramfs contract 拒绝挂载；已更新 `native.contract` 并重打 `repack/9a81b1a-contract-boot/`。新 boot 与新 device-support 成对使用；待冷启动验证 Wi‑Fi、登录音频、GNOME 输入、指纹 |

**已撤销的登记（编号留空，避免其它文档的 `§5 #N` 引用错位）**

- **#2「长时间熄屏后屏幕键盘唤不出」——2026-11-18 撤销，不是缺陷。**
  实际是 GNOME 无障碍屏幕键盘未启用；与触控、面板 follower 都无关。
- 2026-11-18 复核：`FLASHING` 的 "33554432 扇区 = 16 GiB" 按 512 B 扇区计
  是正确的，不是换算错误。

## 7. 固件与 ROM 输入（V14 已对齐，无需再刷机）

- **唯一受支持的 ROM 输入是 `V14.0.9.0.TMYCNXM`**（MIUI 14 / Android 13）。
  `OS2.0.6.0.VMYCNXM`（HyperOS 2 / Android 15）也是小米官方 liuqin 包，两者
  都能刷进这台设备；区别是 Android 基线、厂商 blob 版本（WLAN/BT/DSP/触摸/
  GPU/VPU）和传感器配置。参考项目用 OS2 是因为它的机器在 OS2；我们的 persist、
  校准和已装 rootfs 都是 V14，所以统一用 V14，不混用。
- **对 Linux 来说，Android 版本本身不参与启动**：两套都是官方 liuqin 包，
  整套 blob 与板级数据匹配时，V14/OS2 通常都能跑（参考项目在 OS2 上跑过 Linux，
  我们在 V14 上跑）。但两套不是逐字节等价，整套互换要重验 Wi-Fi/BT/触控/
  音频/GPU/传感器；**不要跨套逐文件混用**，也不要为了“更新”而换 OS2。
- 2026-11-18 已从 V14 线刷包重提取并替换 `device/firmware/`：
  1. `images/super.img`（Android sparse）→ `simg2img` → `lpunpack.py -p vendor_a`；
  2. `vendor_a.img` 是 EROFS → `fsck.erofs --extract` 取 `/firmware`
     （触摸、GPU、VPU、WLAN 板号文件）；
  3. `NON-HLOS.bin`（FAT）→ `mcopy` 取 DSP 68 件；`BTFM.bin` → `mcopy`
     取蓝牙 89 件；
  4. `tools/build-liuqin-firmware-prep.sh` 重新生成树（音频拓扑来自仓库、
     WLAN tuple 来自 `out/wlan`、VPU 来自 V14 `/firmware`）。
- 新树 **173 文件 + 4 符号链接**；触摸 `709726ba…`/`267f5eb0…`、VPU
  `cc27f8e3…`、A730 SQE `8df3e5ab…` 与 V14 提取物一致，蓝牙 89 件与
  V14 `BTFM.bin` 逐一相同。
- **实机本来就在用这组固件**：`native.contract` 是设备已装 rootfs 的哈希快照，
  其中 5 个 `/usr/lib/firmware` 条目与本次提取逐字节相同（旧 OS2 集是不匹配的）。
  所以 `device/firmware/` 只是**构建期的副本**，供以后整包装配使用；
  当前设备不需要因此重刷镜像，也不需要再做一次"固件验收"。
- 与旧 OS2 集相比，V14 少 22 个蓝牙 patch 变体、且不带 `regulatory.db`
  （内核已内建签名 regdb，属可选）。这些是有意删除，不是漏拷。
- 说明：`firmware.manifest` 是固件树的内容校验；脚本里的 `*_sha256` 只是
  **漂移提示**（不一致时打印 note），不是发布/产品锁。没有新增任何产品 SHA
  门禁，也不会因为换 ROM 而阻塞构建。
- 原 Android 双系统用的 `liuqin-rom-images.json`（OS2 校验表）已随 dual 路径
  删除，安装器改用设备常量 `PINNED_BOOT_BYTES = 192 MiB`。

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
| 11 | 上游 = 内核仓 `linux` remote（torvalds/linux）；`sm8450-mainline` 只是历史来源；不再保留 `linux/` checkout |
| 12 | 集成仓新工作放在 `liuqin-7.3` 分支；`main` 保留 v0.6.0 历史 |
| 13 | **2026-11 起新策略**：不区分产品/开发，删 `installer.img` / `17abc-boot-prodrd/` / `out/ramdisk`；全新安装走"装配 boot img → fastboot flash boot_a"；更新走"新内核装配 → flash，或新 deb 覆盖安装" |

## 9. 文档索引

| 文档 | 内容 |
|---|---|
| `STATUS.zh-CN.md` | **本文**，唯一状态源 |
| `INSTALL.zh-CN.md` | 本机安装/更新/恢复：128G、A 槽单系统、装配 boot img → fastboot flash boot_a；rootfs 刷入或内核 deb 覆盖更新 |
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
- **initramfs 单一来源，别混**：
  - `xiaomipad-6pro-mainline/out/initramfs-liuqin/liuqin-firstboot.cpio.gz`：
    post-contract（30,945,812 B，sha256 `935226d6…`）；旧 pre-contract
    （`liuqin-firstboot.cpio.gz.before-contract`，30,930,155 B，`1690e9ec…`）
    仅供历史对照（`17abc-boot` / `c03e10-boot`）。旧产品版 `out/ramdisk`
    （40,326,354 B，`a04d2b25…`）已按新政策删除。
- `ci/` 只保留最新两套 artifact；`repack/` 只保留当前、对照、回滚镜像。
