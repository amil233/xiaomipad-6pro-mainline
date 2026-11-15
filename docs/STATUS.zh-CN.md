# 当前整体状态（2026-11-15）

本文是项目状态的快照：**已经在跑什么、还坏着什么、怎么构建/刷机、下一步做什么**。
历史细节见 `kernel-version-upgrade.md`（逐级升级记录 + 上游 v0.6.1/v0.6.2
移植 + 三方对比审计 + **上游 v0.7.0 移植**）、`kernel-v73-divergence.md`（相对上游 v7.3 的偏离清单）、
`AUDIO.zh-CN.md`（外放 TDM 链路）、`display-panel-checklist.md`（显示取证）。
`AGENTS.md` 是 7.0 显示点亮阶段的历史交接，**以本文为准**。

## 1. 设备与环境

| 项 | 值 |
|---|---|
| 设备 | Xiaomi Pad 6 Pro（liuqin，128G，天马 `m81_36_02_0a`），SM8475 |
| 系统 | Ubuntu 26.04 arm64 桌面（GNOME），分区布局 linux-only（root `LIUQIN_ROOT` + home `LIUQIN_HOME`） |
| 内核 | `liuqin-7.3`，tip `17abc027f75f`（`7.3.0-g17abc027f75f`），已推送、CI 已构建、**已上机点亮**（2026-11-14） |
| 待验证候选 | `liuqin-7.3-v070`（`9773628af36f`，**本地未推送、未编译、未上机**）：上游 v0.7.0 的 5 个移植提交，见 §7 |
| 点亮基线 | `db08160915e3`（v7.3 点亮内核）；`17abc027f75f` 在其上叠加 32 个提交 |
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
- **镜像**：`repack/17abc-boot/boot-liuqin-firstboot.img`
  （50,061,312 B，sha256 `9a715024…6fed67`）**已上机点亮**；对照镜像
  `repack/17abc-boot-prodrd/`（同内核 + 产品 ramdisk）。
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
| 9 | 连接器温度上报 | 7.3 树（以及 v0.6.2）**完全没有**这条链路，是 v0.7.0 新增的。`liuqin-7.3-v070` 已移植整链（pmic_glink 端口源状态 + battmgr 在 worker 里取 ADC + 接受 `IIO_VAL_INT`）。注意上游在 v0.7.0 开发中途先引入过 `if (ret)` 的错判（把每个有效样本当失败跳过、固件收不到温度），`3fe3a2068602` 已修，我们移植的是修好的最终形态。待上机读 `raw_xm_connector_temp` 验证 |
| 8 | GPU 终止失败策略 | v0.6.1 的 `018982b5e1ac` + `fdf3c8b8b912` 未移植（依赖 6.17 recovery 布局），如果遇到 GPU 恢复失败卡死再单独立项 |

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

## 7. 待验证候选：`liuqin-7.3-v070`（2026-11-15）

上游作者 v0.7.0（2026-11-14）的内核提交已做三方对比，取其中 5 项进新分支
**`liuqin-7.3-v070`**（本地，基线 `17abc027f75f`，tip `9773628af36f`）。
完整理由、逐条对比和上机判据见 `kernel-version-upgrade.md`
"上游 v0.7.0 移植"一节。

| 提交 | 一句话 |
|---|---|
| `553e9f02bac6` | `q6dsp-lpass-clocks` 在注册 clock 前设 drvdata —— 修上游报告的真实 NULL 解引用，我们树里是同一潜在崩溃 |
| `44bc4522df22` | 充电口热敏整链（pmic_glink 端口源状态 + battmgr 采样 + 接受整数 ADC + DTS/yaml）；**旧代码从未把温度送到固件** |
| `fa7a5cf0e111` | nt36523 follower 改到 `panel_enabled`/`panel_disabling` + 等 vblank 再下固件 + `WQ_FREEZABLE` |
| `4650887b7766` | fastrpc 用 `TASK_FREEZABLE` 保住跨 suspend 的 DSP 调用（liuqin-only 候选，主线未收） |
| `9773628af36f` | `msm_gem_submit` 大 submit 回退 `kvzalloc`（主线未收，健壮性） |

**未合入**：a6xx GMU 超时与 panel follower 回调（本树已有）、
QCE DTS 关闭（`CONFIG_CRYPTO_DEV_QCE` 因 `depends on BROKEN` 在我们配置里
根本不存在，节点无驱动绑定）。

**状态**：未推送、未跑 CI、未上机。本机按纪律不编译，验证走
CI（需先把 `liuqin-7.3-v070` 加进 `.github/workflows/liuqin.yml` 的
`branches:`）。

**上机第一优先**：面板 follower 时序改动直接影响触摸 ——
冷启动、熄屏再亮、长时间熄屏后唤醒三项都要过。
