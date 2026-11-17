# 当前整体状态（2026-11-17）

**电量已恢复正常**，设备在跑 Ubuntu 26.04 + 本工作区自建 7.3 内核，无安卓系统。

本文是状态快照：**在跑什么、坏着什么、怎么构建/刷机、下一步做什么**。
历史细节见 `kernel-version-upgrade.md`（逐级升级、三方对比、以及两次已作废的
参考树移植记录）、`kernel-v73-divergence.md`（相对主线 v7.3 的偏离）、
`AUDIO.zh-CN.md`（外放 TDM）、`display-panel-checklist.md`（显示取证）。

> **上游只有 Linux 主线**（工作区 `linux/`）。`liuqin-6.17test` 是作者在 6.17
> 上的参考分支，**不是上游**——详见工作区 `AGENTS.md` §1。

## 1. 设备与环境

| 项 | 值 |
|---|---|
| 设备 | Xiaomi Pad 6 Pro（liuqin，128G，天马 `m81_36_02_0a`），SM8475 |
| 系统 | Ubuntu 26.04 arm64 桌面（GNOME），分区布局 linux-only（root `LIUQIN_ROOT` + home `LIUQIN_HOME`） |
| 内核 | `liuqin-7.3`，tip `c03e1015c71d`（已推送、CI 已构建） |
| 当前镜像 | `repack/c03e10-boot/`（`c03e1015c71d`，**已上机点亮、电量正常**）= `17abc027f75f` + 三个与充电无关的修复 |
| 点亮基线 | `17abc027f75f`（`repack/17abc-boot/`，同样点亮、电量正常，最佳对照） |
| 刷机主机 | 树莓派（只跑 fastboot + 保存备份/镜像） |
| 构建主机 | 云端开发机（2 核/11G，**只做源码、装配、打包，不编译内核**） |

## 2. 已工作

- **显示**：2 LM / 2 DSC 拓扑、双 DSI bonded、120 Hz，面板天马 desc；
  点亮内核 `db08160915e3`（`repack/730fix-boot/` 留档）。
- **触控**：Novatek NVT（`nt36523` 厂商驱动 + 天马固件自动更新）。
- **音频（外放）**：48 kHz / 4 声道 / 24-bit / 4×32-bit slot 的 TDM 链路，
  四颗 CS35L41 各占一个 slot；`speaker-test -c 4` 与桌面播放均出声。
  改动与复测见 `AUDIO.zh-CN.md`。
- **桌面**：GNOME 可用；USB 网络救援（initramfs telnet 2323）、持久化 root/home。
- **恢复手段**：安装时 `--backup` 的原厂 boot_a/boot_b/persist/GPT 备份；
  设备 boot_a 镜像已归档到 `out/boot_a.img`，产品 ramdisk 在 `out/ramdisk`。
- **2026-11-14 内核更新**（`52866ba809f1` → `17abc027f75f`，共 32 个提交）：
  - 上游作者 v0.6.1 / v0.6.2 的 **24 个内核补丁**（充电热敏与 cooling-level、
    CPU capacity + CPU/LLCC BWMON、GPU CX 投票、DPU resume OPP、a6xx HFI、
    lpass 时钟顺序、q6apm 采集、wcd938x RX 中断、qmp-combo/ucsi/hci_qca/
    geni-serial/rpmsg-glink、nt36523 调试属性等）；
  - **6 个 mainline v7.4-rc2 bug fix**（a6xx secondary rail/dep votes、
    Lucid Ole PLL、dispcc mdp_clk_src、DPU slave encoder、DSI tx VM 泄漏）；
  - **TDM 策略改为 v7.4 的 per-DAI 形式**（`17abc027f75f`）；
  - 清理 kernel 仓里误提交的 `repack/diff-70-710/*`。
- **镜像**：`repack/c03e10-boot/`（`c03e1015c71d`，50,065,408 B，
  sha256 `8977f56a…dc288`）**已上机点亮、电量正常**，为当前镜像；
  基线对照 `repack/17abc-boot/`（`17abc027f75f`，同样点亮、电量正常），
  产品 ramdisk 对照 `repack/17abc-boot-prodrd/`。
- **模块 deb**：`out/liuqin-debs/liuqin-kernel_0.1_arm64.deb`
  （sha256 `1ac2bfe6…f6859159`，756 个模块，release `7.3.0-g17abc027f75f`）
  已安装；`iptables` 等此前"缺少对应版本模块"的报错消失。
- **设备本地包**：`liuqin-firmware`、`liuqin-device-support`、`liuqin-sensors`
  仍是 0.1 并被 `apt-mark hold`。上游 v0.6.1/v0.6.2 的**用户态**改动
  （充电策略服务、传感器 RPC/退出修复、GNOME 键盘 guard 等）**没有合并**，
  这三个包暂不需要更新；以后合并时必须成套 bump 版本并一起安装
  （`liuqin-device` 元包依赖 `= 0.1`）。

## 3. 已知问题 / 待办

| # | 问题 | 现状 / 下一步 |
|---|---|---|
| 1 | 关机后插电自动开机 | ABL `off-mode-charge:1`。先取证 `/proc/cmdline` 是否有 `androidboot.mode=charger`；可试 `fastboot oem off-mode-charge 0`，不支持则只能接受 |
| 2 | 长时间熄屏后屏幕键盘唤不出 | 需区分"触控失效"还是"GNOME OSK 状态"；见 `triage-2026-10.md` 后续补记。已补 DPU 恢复投票与 slave encoder 顺序。**2026-11-15 另发现真实缺陷方向**：7.3 树的 nt36523 follower 仍挂在 `panel_prepared`，会在面板 prepare 窗口抢 TDDI 下载固件；`liuqin-7.3-v070` 已改到 `panel_enabled` 并加 vblank 等待，待上机验证 |
| 3 | 亮度重启后重置 | `ktz8866-backlight` 是模块，查 `systemd-backlight@` 是否在设备注册前跑；必要时加恢复服务 |
| 4 | 相机 | 需要 camcc GDSC 修复（`66f4fbf82d26`，已在 7.3 树上）+ 去掉 `/etc/modprobe.d/liuqin-camcc.conf`；未验证，暂不优先 |
| 5 | 音频边角 | 当前守卫只接受 48k/4ch/24-bit；桌面已能协商出可用元组，强制 2ch/S16 的应用仍会被拒。槽位与物理喇叭对应可按听感微调 |
| 6 | 升级 v7.4 | 等 7.4 正式版；已做 `merge-tree` 预演：**13 个文件真冲突**，清单见 `kernel-version-upgrade.md` 三方审计一节 |
| 7 | 内核 deb 升级与 native-root 合同 | 已修：合同不再钉 `kernel.release`/`kernel-modules.manifest`（2026-11-07） |
| 8 | 接电脑 USB 口时掉电 | 已定位到**内核侧的一半**：`input_current_limit` 在 SDP 上是 100000（100 mA），原厂靠 USB 栈枚举后 `usb_psy_set_icl()` 抬到 500 mA，而我们没跑 USB gadget ⇒ 永不发生。`9acfdc025415` 从内核补 500 mA 并可写。**待上机复验**是否从掉电转为缓慢充电 |
| 9 | 电池电量/充电计数值不可用或差 1000 倍 | SM8475 从不发 `BAT_INFO` ⇒ `unit` 恒为 `mWh` ⇒ `CHARGE_*` 全 `-ENODATA`、`CHARGE_COUNTER` 按 mAh 当 uAh 报。`1fdb432ed06b` 已修，待上机看量级 |
| 10 | GPU 终止失败策略 | v0.6.1 的 `018982b5e1ac` + `fdf3c8b8b912` 未移植（依赖 6.17 recovery 布局），如果遇到 GPU 恢复失败卡死再单独立项 |
| 11 | 连接器温度上报 | 7.3 树（以及 v0.6.2）**完全没有**这条链路，是 v0.7.0 新增的。`liuqin-7.3-v070` 已移植整链（pmic_glink 端口源状态 + battmgr 在 worker 里取 ADC + 接受 `IIO_VAL_INT`）。注意上游在 v0.7.0 开发中途先引入过 `if (ret)` 的错判（把每个有效样本当失败跳过、固件收不到温度），`3fe3a2068602` 已修，我们移植的是修好的最终形态。待上机读 `raw_xm_connector_temp` 验证 |

## 4. 构建 / 刷机工作流（2026-11-14 现状）

```
内核源码改动 → 推 GitHub liuqin-7.3 → CI 出 artifact → ci/liuqin-kernel-<sha>/
   → 云端装配 boot 镜像：CI Image + dtb + initramfs + ABL overlay
     （repack/<sha>-boot/，放在工作区根目录）
   → 传到树莓派 → fastboot boot（试跑） / fastboot flash boot_a
模块：CI 的 modules.tar + Image + dtb → liuqin-kernel deb → 平板上 dpkg -i
```

要点：

- **内核只在 CI 编译**；本机只做 `dtc`/`fdtoverlay`/`mkbootimg` 装配和
  `dpkg-deb` 打包。
- **initramfs 两个来源，别混**：
  - `out/ramdisk`：产品版（从设备 boot_a 取出，40,326,354 B，
    sha256 `a04d2b25…`）——619/700/710/720/730fix 一路点亮用的；
  - `xiaomipad-6pro-mainline/out/initramfs-liuqin/liuqin-firstboot.cpio.gz`：
    2026-11-07 18:14 重建版（30,930,155 B，sha256 `1690e9ec…`），
    17abc-boot 用它点亮。
- 装配 boot 必需的 ROM 分析目录：
  `tools/local/roms/liuqin/V14.0.9.0.TMYCNXM/analysis`（38 DTBO + 11 base DTB）。
- `ci/` 只保留最新一套 artifact；`repack/` 只保留当前镜像、对照镜像和回滚镜像
  （见 `repack/README.md`）。
- 树莓派只需要：fastboot、安装时 `--backup` 的备份目录、传过去的 boot 镜像。

## 5. 升级到 v7.4 时必须保留 / 关注的下游偏离

来自 `kernel-v73-divergence.md` 与三方对比审计：

- 显示：quad-pipe 常量、mixer 粒度拆分、2LM/2DSC、`dsc_slice_per_pkt`、
  bonded-DSI PLL 修复（`db08160915e3`，上游仍是 revert 态；7.4 merge 会
  自动保留，但要人工复查）。
- 机器表别名：`ubwc_config.c` 的 `qcom,cape`（7.3 丢过一次）。
- 音频：**TDM 已改成 v7.4 的 per-DAI 板级配置**（`17abc027f75f`，对齐
  `ea6e98472c65`）；保留 `cs35l41.c` 的 `.set_tdm_slot`。7.4 merge 时
  上游 per-DAI 结构会与我们的扩展字段相邻，注意不要丢 `codec_dai_fmt`/
  `codec_tdm_slot_each`/`codec_component_sysclk`。
- pinctrl-sm8475 的 `MSM_GPIO_PIN_FUNCTION`、sm8450 ICC `link_nodes` 修复、
  camcc GDSC 重新挂父域（`66f4fbf82d26`）。
- 面板驱动撞名：v7.4 新增同名 `panel-novatek-nt36532.c`（CSOT PPC100HB1）
  + 同 Kconfig 符号，merge 是 add/add 冲突；计划以主线文件为底重加
  pipa/Tianma desc，详见 `kernel-version-upgrade.md` 面板差距一节。
- 上游新进入的 revert：`git log v7.(N-1)..v7.N --grep '^Revert ' -- drivers/gpu/drm/msm/`。

## 6. 文档索引

| 文档 | 内容 |
|---|---|
| `AUDIO.zh-CN.md` | 外放 TDM 链路：数据通路、四个内核改动、诊断要点、复测 |
| `kernel-version-upgrade.md` | 6.17→7.3 逐级升级、上游 v0.6.1/v0.6.2 移植、三方对比审计与 7.4 预演 |
| `kernel-v73-divergence.md` | 相对上游 v7.3 的 173 文件偏离清单 |
| `display-panel-checklist.md` | 显示点亮的取证、寄存器黄金值、判读陷阱 |
| `known-wrong-changes.md` | 已证伪的改动与判读陷阱，改显示前先读 |
| `triage-2026-10.md` | 早期外设/启动问题分诊 |
| `FLASHING.zh-CN.md` / `BUILD.zh-CN.md` | 刷机 / 构建说明（编写时的流程） |

## 7. 历史：v0.7.0 / v0.8.0 两批移植（均已作废）

2026-11-15 与 11-17 曾两次从 `liuqin-6.17test`（作者在 **6.17** 内核上的
参考分支，**不是我们的上游**）移植补丁，**共 16 个提交，全部已回退**。

**作废理由**（已核实，详见工作区 `AGENTS.md` §1）：

- 17abc 的 **XM（小米私有）协议本来就完整**（139 处引用，含鉴权与快充）；
- 主线的电池 ABI 与 17abc **逐字节相同** ⇒ 电池部分本就等于主线加 XM 增量；
- 那批改动的前提来自作者的 `OS2.0.6.0` ROM（属性号、换算系数、固件行为），
  本机是 `V14.0.9.0`，**不成立**；
- 代价：`1fdb432ed06b` 重写电池属性表后**电量显示报 unknown**，回退 v0.8.0
  后仍 unknown（还有 `CHARGE_COUNTER` ×1000 与 `devm_device_init_wakeup`
  两处残留）。

最终只保留三个与充电无关、各自独立的修复，见工作区 `AGENTS.md` §2。

原始移植记录保留在 `kernel-version-upgrade.md` 的"作废记录"一节，仅供追溯。

---

## 8. 工作区清理（2026-11-17）与当前状态

**电量已恢复正常**：`repack/c03e10-boot/`（`c03e1015c71d`）上机确认。
它是 `17abc027f75f` 的基线 + 三个与充电无关的修复（`q6apm` hw_ptr、
`q6dsp-lpass-clocks` drvdata 顺序、DTS 关 QCE）。

### 那 16 个提交全部作废

起因是把 `liuqin-6.17test`（作者在 **6.17** 内核上的参考分支，**不是我们的
上游**）的 `release/v0.8.0` 充电补丁整批移植。已核实两点：

- 17abc 的 **XM（小米私有）协议本来就完整**（139 处引用，含鉴权与快充属性）；
- 主线的电池 ABI 与 17abc **逐字节相同** ⇒ 17abc 的电池部分本就等于主线加
  XM 增量。

所以那批改动既非必要、前提又不成立（属性号/换算系数来自作者的
`OS2.0.6.0` ROM，本机是 `V14.0.9.0`）。教训已写入工作区 `AGENTS.md` §1。

### 清理明细（28G → 27G，释放约 1.7G）

删除了：

- `repack/9acfdc-boot/`、`repack/3c91c2-boot/`（两张电量 unknown 的镜像，
  源码已脱离分支，README 曾标 ⛔）；
- `ci/liuqin-kernel-9acfdc*`、`ci/liuqin-kernel-3c91c2*`（对应 artifact）；
- `repack/.scratch/`（`d710.dts`/`d720.dts` 历史遗留快照）；
- `vendor-liuqin-oss/`、`caf-display/`、`display-drivers-archive/`（三份
  历史参考树，当前代码与工具**零引用**；本页与 display 系列历史文档里仍有
  文字引用，属于取证记录，路径失效不影响结论）；
- 工作区根目录我留下的临时文件（`cur_battmgr.c`、`tgt.c`、`ml_battmgr.c`、
  `fix.patch`、`.dt/`、`.probe/` 等）。

**保留**：

| 项 | 原因 |
|---|---|
| `liuqin_images_V14.0.9.0...`（7.2G） | 用户决定保留。装配 boot 所需的 analysis 数据（47M）已独立在 `tools/local/roms/`，脚本从不读这个目录；另 `tools/lib/liuqin-rom-images.json` 是安装器校验 ROM 身份的清单 |
| `ci/liuqin-kernel-{17abc,c03e10}*` | 都对应仍在分支上的提交，各 302M |
| `repack/17abc-boot/`、`c03e10-boot/`、`730fix-boot/`、`17abc-boot-prodrd/` | 点亮 / 当前 / 回滚 / 对照 |
| `native.contract`、`native.hashes` | 已装根文件系统的校验快照，供 `tests/persistent-root.sh` 使用 |
| `repack/` 里的取证脚本 | `verify-*`、`compare-*`、`split-*` 等，部分文档仍在引用 |

### 待验证候选（未进树）

以下三个补丁**没有**合入，需要时再单独评估：

- 连接器热敏整链（v0.7.0 批次，含 `connector_worker`/`online_response`/
  DTS `channel@347`）：曾随作废的那批一起上机，无法与 v0.8.0 分离归因；
- `fastrpc` `TASK_FREEZABLE`、`msm_gem_submit` `kvzalloc`：主线未收，
  需真机验证收益。
