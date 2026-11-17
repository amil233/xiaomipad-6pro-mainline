# 当前整体状态（2026-11-17）

**这是唯一的状态源。** 其它文档里出现的提交号、镜像哈希、分区槽、ROM 版本
若与本文冲突，以本文为准；历史取值见 `docs/archive/`（已冻结）。

## 0. 这台设备到底是什么

两条独立的线，不要混：

| | 我们的设备现状 | 参考项目 `liuqin-6.17test` |
|---|---|---|
| 内核基座 | **主线 Linux v7.3**（工作区 `linux/`） | 6.17 |
| 内核分支 | `liuqin-7.3` @ `c03e1015c71d` | `liuqin-6.17` / `release/v0.6.x` |
| 启动槽 | **A 槽直接启动** | 它的安装器把 Ubuntu 写 B 槽 |
| ROM | `V14.0.9.0.TMYCNXM`（Android 13，设备在装） | `OS2.0.6.0`（HyperOS 2） |
| 我们的关系 | 全部自建 | 只贡献了**用户态骨架**（集成仓 v0.6.0 时代） |

**唯一上游是 Linux 主线。** `liuqin-6.17test` 是另一个项目：目的类似、基座
不同、ROM 不同、槽位方案不同。它的补丁与数值**只能当线索**，不能当上游，
也不能当我们的设计依据（代价案例见工作区 `AGENTS.md` §1）。

## 1. 设备与环境

| 项 | 值 |
|---|---|
| 设备 | Xiaomi Pad 6 Pro（liuqin，128G，天马 `m81_36_02_0a`），SM8475 |
| 系统 | Ubuntu 26.04 arm64 桌面（GNOME），**单系统，无 Android** |
| 启动 | **A 槽直接启动**（`fastboot flash boot_a`）；B 槽不参与 |
| 分区 | `linux_root`(#36, `LIUQIN_ROOT`) + `linux_home`(#37, `LIUQIN_HOME`)，从 userdata 尾部划出 |
| 内核 | `liuqin-7.3`，tip `c03e1015c71d`（`7.3.0-gc03e1015c71d`），已推送、CI 已构建 |
| 当前镜像 | `repack/c03e10-boot/`（50,065,408 B，sha256 `8977f56a…`）**已上机点亮、电量正常** |
| 对照/回滚 | `repack/17abc-boot/`（`17abc027f75f`，点亮基线）、`repack/730fix-boot/`（`db08160915e3`） |
| 内核包 | `out/liuqin-debs/liuqin-kernel_0.1_arm64.deb`（sha256 `a0354248…`，756 `.ko`，release `7.3.0-gc03e1015c71d`） |
| 构建主机 | 云端 2 核/11G，**只做源码、装配、打包，不编译内核** |
| 刷机主机 | 树莓派（只跑 fastboot + 保存备份/镜像） |

## 2. 用户态的现实：停在参考项目 v0.6.0

**这是当前最大的版本落差，也是唯一待决策项。**

集成仓 `device/` 相对参考项目 `release/v0.6.0` 只改过 **2 个文件**
（`configs/liuqin-firstboot.config`、`native-bootargs.txt`）。也就是说，
设备上跑的 `liuqin-firmware` / `liuqin-device-support` / `liuqin-sensors`
仍是 **v0.6.0 形态**，全部 `0.1` 版本并被 `apt-mark hold`。

参考项目 v0.6.1 / v0.6.2 / v0.7.0 的用户态改动（充电策略服务、传感器
RPC 与退出修复、GNOME 键盘 guard、devmode、release notifier、一批
sensor-proxy 补丁，合计数千行）**一条都没进设备**。

要不要补、补哪些，是决策而不是顺手更新：必须成套 bump 版本、重装并
冷启动验证（`liuqin-device` 元包依赖 `= 0.1`）。

## 3. 内核侧的版本关系（已核实到提交级）

| 批次 | 结论 |
|---|---|
| 参考项目 v0.6.1 / v0.6.2 的 24 个内核补丁 | **已移植**在树（充电热敏与 cooling-level、CPU capacity + LLCPU/LLCC BWMON、GPU CX 投票、DPU resume OPP、a6xx HFI、lpass 时钟顺序、q6apm 采集、wcd938x RX 中断、qmp-combo/ucsi/hci_qca/geni-serial/rpmsg-glink、nt36523 调试属性等） |
| 参考项目 v0.7.0 的积压（面板 follower 改 `enabled` 阶段、连接器温度整链、fastrpc freezeable 等） | 只在分支 `liuqin-7.3-v070`，**已丢弃、不在 `liuqin-7.3` 里**，不是待合并项 |
| 参考项目 v0.8.0 整批（电池属性表重写等） | **2026-11-17 全部回退**，前提是作者的 `OS2.0.6.0` 行为，本机 `V14.0.9.0` 不成立 |

`c03e1015c71d` = `17abc027f75f` + **3 个与充电无关的独立修复**：

| 提交 | 文件 | 用途 |
|---|---|---|
| `0be8362d2405` | `q6apm.c` | xrun 恢复后上报旧播放位置；**主线 `0337b8129cf6` 逐字节相同** |
| `b30b611dcd58` | `q6dsp-lpass-clocks.c` | 修 `cc->desc` NULL 解引用；主线 v7.4-rc3/master 同错 ⇒ **上游化候选** |
| `c03e1015c71d` | liuqin DTS | `&crypto { status = "disabled" }`；本树无 `CONFIG_CRYPTO_DEV_QCE`，属显式意图 |

`qcom_battmgr.c` 在 `c03e1015c71d` 上**没有任何 v0.7.0/v0.8.0 改动**——
那两批提交从未进过这条分支。树里的 148 处 XM 引用与 v7.3 的 978 行增量
是**先前多个版本累积下来的既有实现**，不是这批移植的产物。

## 4. 已工作

- **显示**：2 LM / 2 DSC 拓扑、双 DSI bonded、120 Hz，天马面板 desc；
  点亮内核 `db08160915e3`（`repack/730fix-boot/` 留档）。
- **触控**：Novatek NVT（`nt36523` 厂商驱动 + 天马固件自动更新）。
- **音频（外放）**：48 kHz / 4 声道 / 24-bit / 4×32-bit slot 的 TDM 链路，
  四颗 CS35L41 各占一个 slot；`speaker-test -c 4` 与桌面播放均出声。
  详见 `AUDIO.zh-CN.md`。
- **桌面**：GNOME 可用；USB 网络救援（initramfs telnet 2323）、持久 root/home。
- **恢复手段**：安装时 `--backup` 的原厂 boot_a/boot_b/persist/GPT 备份；
  设备 boot_a 镜像归档在 `out/boot_a.img`，产品 ramdisk 在 `out/ramdisk`。
- **内核 deb**：756 `.ko` + `/boot/{vmlinuz,initrd,dtb}`，纯文件包（无维护
  脚本、无 `Depends`），已核对与 CI artifact 逐字节一致。

## 5. 已知问题 / 待办

| # | 问题 | 现状 / 下一步 |
|---|---|---|
| 1 | 关机后插电自动开机 | ABL `off-mode-charge:1`。先取证 `/proc/cmdline` 是否有 `androidboot.mode=charger`；可试 `fastboot oem off-mode-charge 0`，不支持则只能接受 |
| 2 | 长时间熄屏后屏幕键盘唤不出 | 需区分"触控失效"还是"GNOME OSK 状态"。7.3 树的 nt36523 follower 仍挂在 `panel_prepared`，理论上会在面板 prepare 窗口抢 TDDI 下载固件；把它改到 `panel_enabled` + vblank 等待的那版**只在已丢弃的 `liuqin-7.3-v070` 上，未进树** |
| 3 | 亮度重启后重置 | `ktz8866-backlight` 是模块，查 `systemd-backlight@` 是否在设备注册前跑；必要时加恢复服务 |
| 4 | 相机 | 需要 camcc GDSC 修复（`66f4fbf82d26`，已在 7.3 树上）+ 去掉 `/etc/modprobe.d/liuqin-camcc.conf`；未验证，暂不优先 |
| 5 | 音频边角 | 当前守卫只接受 48k/4ch/24-bit；桌面已能协商出可用元组，强制 2ch/S16 的应用仍会被拒 |
| 6 | 升级 v7.4 | 等正式版。`merge-tree` 预演**13 个文件真冲突**，清单与决策见 `kernel-v73-divergence.md` |
| 7 | 连接器温度上报 | 树里**没有**这条链路（v0.7.0 新增，随已丢弃分支）；需要时单独立项 |
| 8 | 接电脑 USB 口时掉电 | 内核侧一半已定位：SDP 上 `input_current_limit` 是 100 mA，原厂靠 USB gadget 枚举后才抬到 500 mA，我们不跑 gadget ⇒ 永不发生。**树里没有 SDP 500 mA 补丁**（它随已回退批次），需要时重做 |
| 9 | 电压/电流计数值 | 已恢复正常（`c03e10-boot` 上机确认）；相关 v0.8.0 改动已全部回退，不要重引入 |
| 10 | 用户态版本落差 | 见 §2。要不要合并 v0.6.1–v0.7.0 的用户态改动，需用户决策 |
| 11 | 安装器槽位与实机不符 | `tools/install-liuqin.py:36` `LINUX_ONLY_UBUNTU_SLOT = 'b'`，实机是 **A 槽直启**；`INSTALL-TESTING`/`STAGE2`/`liuqin_layout.py` 的槽位描述同样过时，尚未改代码 |

## 6. 构建 / 刷机工作流

```
内核源码改动 → 推 GitHub liuqin-7.3 → CI 出 artifact → ci/liuqin-kernel-<sha>/
   → 本机装配 boot 镜像：CI Image + dtb + initramfs + ABL overlay
     （repack/<sha>-boot/，放在工作区根目录）
   → 传到树莓派 → fastboot boot（试跑） / fastboot flash boot_a
模块：CI 的 modules.tar + Image + dtb → liuqin-kernel deb → 平板上 dpkg -i
```

要点：

- **内核只在 CI 编译**；本机只做 `dtc`/`fdtoverlay`/`mkbootimg` 装配和
  `dpkg-deb` 打包。
- **initramfs 两个来源，别混**：
  - `out/ramdisk`：产品版（从设备 boot_a 取出，40,326,354 B，
    sha256 `a04d2b25…`）；
  - `xiaomipad-6pro-mainline/out/initramfs-liuqin/liuqin-firstboot.cpio.gz`：
    2026-11-07 重建版（30,930,155 B，sha256 `1690e9ec…`），
    `17abc-boot` 与 `c03e10-boot` 用的都是它。
- 装配 boot 必需的 ROM 分析目录：
  `tools/local/roms/liuqin/V14.0.9.0.TMYCNXM/analysis`（38 DTBO + 11 base DTB）。
- `ci/` 只保留最新两套 artifact；`repack/` 只保留当前、对照、回滚镜像
  （见 `repack/README.md`）。

## 7. 升级到 v7.4 时必须保留 / 关注的下游偏离

完整清单见 `kernel-v73-divergence.md`（174 文件、63 新增、0 删除）。
最容易丢的几条：

- 显示：quad-pipe 常量、mixer 粒度拆分、2LM/2DSC、`dsc_slice_per_pkt`、
  bonded-DSI PLL 修复（上游仍是 revert 态）。
- 机器表别名：`ubwc_config.c` 的 `qcom,cape`（7.3 丢过一次）。
- 音频：**TDM 已改成 v7.4 的 per-DAI 板级配置**（`17abc027f75f`）；合并时
  注意不要丢 `codec_dai_fmt`/`codec_tdm_slot_each`/`codec_component_sysclk`。
- pinctrl-sm8475 的 `MSM_GPIO_PIN_FUNCTION`、sm8450 ICC `link_nodes` 修复、
  camcc GDSC 重新挂父域（`66f4fbf82d26`）。
- **面板驱动撞名**：v7.4 新增同名 `panel-novatek-nt36532.c` + 同 Kconfig 符号，
  merge 是 add/add 冲突；以主线文件为底重加 pipa/Tianma desc。
- 上游新进入的 revert：`git log v7.(N-1)..v7.N --grep '^Revert ' -- drivers/gpu/drm/msm/`。

## 8. 文档索引

| 文档 | 内容 |
|---|---|
| `STATUS.zh-CN.md` | **本文**，唯一状态源 |
| `kernel-v73-divergence.md` | 相对主线 v7.3 的偏离清单 + 7.4 冲突与决策 |
| `AUDIO.zh-CN.md` | 外放 TDM 链路：数据通路、内核改动、诊断、复测 |
| `display.md` | 显示点亮：已确立结论、寄存器黄金值、判读陷阱（由 6 份历史文档压缩） |
| `BUILD.zh-CN.md` / `CI.md` | 构建与流水线 |
| `FLASHING.zh-CN.md` / `INSTALL-TESTING.zh-CN.md` / `STAGE2-PERSISTENT.zh-CN.md` | 安装与持久化（槽位一节已注明与实机不符） |
| `CAMERA.zh-CN.md` / `FINGERPRINT.zh-CN.md` / `FASTCHARGE.zh-CN.md` / `WAYDROID.zh-CN.md` | 单功能说明 |
| `archive/` | 冻结的历史取证（显示黑屏、逐级升级、迁移、分诊），**不再维护** |
