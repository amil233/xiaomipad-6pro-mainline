# 当前整体状态（2026-11-07）

本文是项目状态的快照：**已经在跑什么、还坏着什么、怎么构建/刷机、下一步做什么**。
历史细节见 `kernel-version-upgrade.md`（逐级升级记录）、
`kernel-v73-divergence.md`（相对上游 v7.3 的偏离清单）、
`AUDIO.zh-CN.md`（外放 TDM 链路）、`display-panel-checklist.md`（显示取证）。
`AGENTS.md` 是 7.0 显示点亮阶段的历史交接，**以本文为准**。

## 1. 设备与环境

| 项 | 值 |
|---|---|
| 设备 | Xiaomi Pad 6 Pro（liuqin，128G，天马 `m81_36_02_0a`），SM8475 |
| 系统 | Ubuntu 26.04 arm64 桌面（GNOME），分区布局 linux-only（root `LIUQIN_ROOT` + home `LIUQIN_HOME`） |
| 内核 | `liuqin-7.3`，tip `52866ba809f1`（7.3.0-g52866ba809f1），已推送并由 CI 构建 |
| 点亮基线 | `db08160915e3`（v7.3 点亮内核；其后为音频修复） |
| 刷机主机 | 树莓派（只跑 fastboot + 保存备份/镜像） |
| 构建主机 | 云端开发机（2 核/11G，**只做源码、装配、打包，不编译内核**） |

## 2. 已工作

- **显示**：2 LM / 2 DSC 拓扑、双 DSI bonded、120 Hz，面板天马 desc；点亮内核
  `db08160915e3`（`repack/730fix-boot/` 留档）。
- **触控**：Novatek NVT（`nt36523` 厂商驱动 + 天马固件自动更新）。
- **音频（外放）**：48 kHz / 4 声道 / 24-bit / 4×32-bit slot 的 TDM 链路，
  四颗 CS35L41 各占一个 slot；`speaker-test -c 4` 与桌面播放均出声。
  改动与复测见 `AUDIO.zh-CN.md`。
- **桌面**：GNOME 可用；USB 网络救援（initramfs telnet 2323）、持久化 root/home。
- **恢复手段**：安装时 `--backup` 的原厂 boot_a/boot_b/persist/GPT 备份；
  设备 boot_a 里的产品版 initramfs 已提取到 `out/initramfs-liuqin/`。

## 3. 已知问题 / 待办

| # | 问题 | 现状 / 下一步 |
|---|---|---|
| 1 | 关机后插电自动开机 | ABL `off-mode-charge:1`。先取证 `/proc/cmdline` 是否有 `androidboot.mode=charger`；可试 `fastboot oem off-mode-charge 0`，不支持则只能接受 |
| 2 | 长时间熄屏后屏幕键盘唤不出 | 需区分"触控失效"还是"GNOME OSK 状态"；见 `triage-2026-10.md` 后续补记 |
| 3 | 亮度重启后重置 | `ktz8866-backlight` 是模块，查 `systemd-backlight@` 是否在设备注册前跑；必要时加恢复服务 |
| 4 | 相机 | 需要 camcc GDSC 修复（`66f4fbf82d26`，已在 7.3 树上）+ 去掉 `/etc/modprobe.d/liuqin-camcc.conf`；未验证，暂不优先 |
| 5 | 音频边角 | 当前守卫只接受 48k/4ch/24-bit；桌面已能协商出可用元组，强制 2ch/S16 的应用仍会被拒。槽位与物理喇叭对应可按听感微调 |
| 6 | 升级 v7.4 | 见 §5 的"必须保留的下游偏离" |
| 7 | 内核 deb 升级与 native-root 合同 | 已修：合同曾钉住 `kernel.release`/`kernel-modules.manifest`，装新内核 deb 后启动被 fail-closed 拒绝（2026-11-07 实测）。`build-root-contract.py` 的 native 列表已不再钉这两个文件，现有设备用重新生成的合同重建了 initramfs |


## 4. 构建 / 刷机工作流（2026-11-07 起）

```
内核源码改动 → 推 GitHub liuqin-7.3 → CI 出 artifact → ci/liuqin-kernel-<sha>/
   → 云端装配 boot 镜像：CI Image + dtb + 产品版 initramfs + ABL overlay
     （repack/<sha>-boot/，放在工作区根目录）
   → 传到树莓派 → fastboot boot（试跑） / fastboot flash boot_a
模块：CI 的 modules.tar + Image + dtb → liuqin-kernel deb → 平板上 dpkg -i
```

要点：

- **内核只在 CI 编译**；本机只做 `dtc`/`fdtoverlay`/`mkbootimg` 装配和 `dpkg-deb` 打包。
- **产品版 initramfs** 来自设备 `boot_a`（`unpack_bootimg` 取出 ramdisk），
  路径 `xiaomipad-6pro-mainline/out/initramfs-liuqin/liuqin-firstboot.cpio.gz`
  （sha256 `226947667e…`）；只有改 `initramfs/` 内容时才需要重建。
- 重建 initramfs 需要的输入：`tools/local/busybox-arm64`、
  `tools/local/firmware-liuqin/*`（从 ramdisk 反抽或厂商 ROM 提取）、
  `out/audio-topology/Xiaomi-Pad-6-Pro-tplg.bin`（sha256 `9c9f8bfc…`）。
- 装配 boot 必需的 ROM 分析目录：
  `tools/local/roms/liuqin/V14.0.9.0.TMYCNXM/analysis`（38 DTBO + 11 base DTB）。
- `ci/` 只保留最新一套 artifact；`repack/` 只保留最新镜像 + 当前点亮的回滚镜像。
- 树莓派只需要：fastboot、安装时 `--backup` 的备份目录、传过去的 boot 镜像。

## 5. 升级到 v7.4 时必须保留的下游偏离

来自 `kernel-v73-divergence.md` 与各级升级复盘，合并后逐项 grep 校验：

- 显示：quad-pipe 常量、mixer 粒度拆分、2LM/2DSC、`dsc_slice_per_pkt`、
  bonded-DSI PLL 修复（`db08160915e3`，注意上游 revert 类回归）。
- 机器表别名：`ubwc_config.c` 的 `qcom,cape`（7.3 丢过一次）。
- 音频：`sc8280xp.c` 的 **TDM 后端跳过 BE fixup**、**codec PLL（component sysclk）**、
  DSP_A + 每颗功放一个 slot；`cs35l41.c` 的 `.set_tdm_slot`。
  上游 v7.4 仍把所有 BE 强制成 2ch/S16，这几处不能被覆盖。
- pinctrl-sm8475 的 `MSM_GPIO_PIN_FUNCTION`、sm8450 ICC `link_nodes` 修复、
  camcc GDSC 重新挂父域（`66f4fbf82d26`）。
- 上游新进入的 revert：`git log v7.(N-1)..v7.N --grep '^Revert ' -- drivers/gpu/drm/msm/`。

## 6. 文档索引

| 文档 | 内容 |
|---|---|
| `AUDIO.zh-CN.md` | 外放 TDM 链路：数据通路、四个内核改动、诊断要点、复测 |
| `kernel-version-upgrade.md` | 6.17→7.3 逐级升级与每级修复的完整记录 |
| `kernel-v73-divergence.md` | 相对上游 v7.3 的 159 文件偏离清单（含音频新增项） |
| `display-panel-checklist.md` | 显示点亮的取证、寄存器黄金值、判读陷阱 |
| `known-wrong-changes.md` | 已证伪的改动与判读陷阱，改显示前先读 |
| `triage-2026-10.md` | 早期外设/启动问题分诊 |
| `FLASHING.zh-CN.md` / `BUILD.zh-CN.md` | 刷机 / 构建说明（编写时的流程） |
