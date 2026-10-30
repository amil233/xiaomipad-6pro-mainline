# AGENTS.md —— liuqin 天马面板主线点亮：现状与交接

最后更新：2026-10-27，对应内核分支 `liuqin-7.0`，commit `4ab4102c17f6`。

本文只写**有证据的结论**。每条都标注证据来源和可信度，并单独列出
**已被推翻的结论**，避免下一个人重复走过的弯路。

---

## 1. 目标与状态

**目标**：在 Xiaomi Pad 6 Pro（liuqin，128G，天马面板 `m81_36_02_0a`）上，
用主线 7.0.14 内核点亮屏幕。单一目标，不含触控/音频/桌面。

**状态**：**未达成**。内核启动、面板 enable、DPU 出帧全部正常，屏幕无画面。

**关键前提**：这台设备的天马面板**从未在任何主线内核上点亮过**。
上游作者 `liuqin-6.17` 分支的成功是在他自己的 **CSOT（256G）** 设备上取得的，
不能当作本机的已知正确基线。

---

## 2. 环境

| 项 | 值 |
|---|---|
| 设备 | Xiaomi Pad 6 Pro（liuqin），128G，Tianma `m81_36_02_0a` |
| SoC | **SM8475（骁龙 8+ Gen 1）**；`sm8450` 只是父 dtsi / 驱动命名（`dpu_8_1_sm8450`、`camcc-sm8450`），不是这颗 SoC |
| DPU | **8.0**（`dpu hardware revision: 0x80050000`） |
| DSI | 6G v2.6（`0x20060000`），bonded dual-DSI，4 lane，video mode |
| DSC | 3:1，slice 450×20，slice_count 2，slice_per_pkt 2，1800×2880@120 |
| 原厂（设备在装） | **V14.0.9.0.TMYCNXM（Android 13）**，内核 `5.10.136-android12-9-00021-g821df8f5bd36-ab9585204`；证据：`out/vendor-display/dmesg.txt` 的 `swinfo.fingerprint=liuqin:13/V14.0.9.0.TMYCNXM:user` |
| 手头另有 | OS2.0.6.0.VMYCNXM（Android 15）线刷包，**未装在设备上**；2026-10-28 之前的本文把两者混用 |
| 主线 | 7.0.14，分支 `liuqin-7.0` |
| 上游参考 | `liuqin-6.17`（作者 CSOT 设备已点亮） |
| CAF 参考源码 | `caf-display/`，`display-kernel.lnx.5.10.r11-rel`，tag `DISPLAY.LA.2.0.r5-00100-NEOLA.0` |

**重要限制**：`caf-display/` 是从 CodeLinaro 取的通用分支，**未验证**与设备实际
运行的驱动是同一版本（`msm_drm.ko` 已 strip，`uname -r` 只给出 ACK 基线）。
凡只依据它的结论都在下面单独标注。

---

## 3. 已证实的可信事实

### 3.1 设备直接观测（最高可信）

| 事实 | 含义 |
|---|---|
| bootloader 画面在这块面板上正常显示 | 面板、供电、背光、DSI 链路、DSC 通路在厂商配置下全部可用 |
| 主线启动后黑屏，背光亮 | 面板处于 enable 状态但无有效画面 |
| 面板响应 DCS 读写，切页成功 | 数字接口通，命令可达 DDIC |
| `Console: switching to colour frame buffer device 112x90` | fbcon 成功绑定，`/proc/fb`=`msmdrmfb`，`/dev/fb0` 存在 |
| 向 `/dev/kmsg`、`/dev/tty0` 写内容无显示 | 内容到不了面板 |
| 6.17 分支 + 天马 desc 同样黑（`liuqin-6.17-tianma`，`87a3f76ddd64`） | **不是 7.0 的回归** |

### 3.2 双方向寄存器逐值相同（可信）

厂商值来自 `out/vendor-display/`（在设备在装的 **V14.0.9.0（Android 13）** 上
抓的快照）与在原厂系统上现抓的 `sde_off`/`sde_reg` 段落。

**引用纪律（2026-10-28 复核）**：`out/vendor-display/dri_0_debug_dsi0_ctrl_reg.txt`
的窗口只有 `0x00–0x5c`，其中真实存在的厂商值只有 `HW=0x20060000`、`CTRL=0x1f3`、
`STATUS0=0x2008`、`FIFO=0x1010`、`VID_CFG0=0x02009230`、`ACTIVE_H/V`、
`TOTAL=0x15f30254`、`ACTIVE_HSYNC`、`CMD_DMA_CTRL=0xd4000000`。
文档里出现过的 `CLKOUT=0x13e0391f`、`CTL=0x28000300/0x33000`、
`CLK_STATUS=0x008047c3`、`LANE_CTRL/LANE_STATUS`、厂商侧 `DSC_MODE_CTRL`
在任何原始文件里都不存在，**引用前必须用足够大的窗口重采**，不能当既成事实。

| 寄存器 | 值 |
|---|---|
| DSI `CTRL` | `000001f3` |
| DSI `VID_CFG0` | `02009230`（burst） |
| DSI `ACTIVE_H` / `ACTIVE_V` / `ACTIVE_HSYNC` | `015c0030` / `0c1800d8` / `00020000` |
| DSI `DSC_CTRL` | `03840b01`（EN=1，WC=900，datatype=0x0b，1 pkt/line） |
| DSI `CLK_STATUS` | `008047c3`（含 PLL 锁定位） |
| INTF `CONFIG2` / `+064` / 活动宽度 | `00001011` / `00c50030` / `015b0030` |
| SSPP `+030`–`+050`（格式/unpack/op mode/fetch config） | 逐字节相同 |

### 3.3 我们自己内核的测量（可信，反映"发生了什么"）

| 测量 | 结果 | 意义 |
|---|---|---|
| **`INTF_FRAME_COUNT`** | 0x1175→0x11EE（1 秒 +121） | **DPU 在按 120fps 稳定出帧** |
| `INTF_LINE_COUNT` | 帧内正常回绕 | 扫描在推进 |
| `SSPP UBWC_ERROR_STATUS` | 0 | 取数无错误 |
| `SSPP SRC_ADDR_SW_STATUS` | 0 | 无挂起地址更新 |
| dmesg | 无 SMMU fault / underrun / timeout | 无总线级错误 |
| `DIAG dsc` | mode=5, init_lines=3, bpp=128, bpc=8, slice=450x20 x2, chunk=450, first_bpg=12 | DSC 编码器参数符合预期 |
| PPS 128 字节 | 逐字段解码正确（pic 1800×2880、slice、chunk、version 1.1） | 下发给面板的 PPS 格式正确 |
| 面板 init 序列 | 216 条与厂商 DTBO **逐字节相同** | 初始化内容一致 |

### 3.4 单变量实验结果

| 实验 | 结果 | 结论 |
|---|---|---|
| `msm.vendor_phy_timing=1`（厂商 14 字节 PHY 时序） | 与基线完全一致 | **PHY 时序中 5/14 的差异与黑屏无关** |
| `panel_novatek_nt36532.skip_panel_init=1` | 与基线一致 | 复位/init 序列不是直接原因 |
| `drm_client_lib.active=fbdev` | 背光熄灭、仍无画面 | 渲染路径排除（且该次因背光熄灭而判读受限） |
| mode_flags 三种组合（作者非 burst、厂商 burst、burst+LPM+非连续） | 均黑 | 链路 flags 不是原因 |

---

## 4. 已排除的假设

| 假设 | 排除依据 |
|---|---|
| 面板硬件损坏 | bootloader 能显示 |
| 背光未开 / 总使能未写 | `ktz8866-backlight` 存在，`0x09=0x9f`，背光随面板 enable 亮灭 |
| 供电轨异常 | vsp/vsn 5500mV、dvdd 1300mV，`use=2` 全部使能 |
| 复位引脚错误 | `sde_dsi_active` 把 gpio0 配成 GPIO；`reset-gpios` 与厂商 `<&tlmm 0 0>` 一致 |
| init 序列错误 | 216 条与厂商 DTBO 逐字节相同 |
| DSC 参数错误 | 与厂商 DT 的 `scr-version`/`block-prediction`/bpp/bpc/slice 全部一致 |
| PPS 内容错误 | 128 字节逐字段正确 |
| DSI 控制器配置错误 | 与厂商逐值相同 |
| SSPP 取数失败 | `UBWC_ERROR_STATUS=0`、`SRC_ADDR_SW_STATUS=0`、格式匹配 |
| **DPU 没有出帧** | **`INTF_FRAME_COUNT` 1 秒 +121** |
| PHY 时序错误 | `vendor_phy_timing` 实验无变化 |
| 内核版本回归 | 6.17 + 天马同样黑 |
| 渲染路径未绘制 | fbcon 绑定成功，写 console 仍无画面 |
| SMMU 映射失败 | 无 fault |

---

## 5. 已被推翻的结论（重要，勿重复）

以下都是我早期基于**错误的探针或读地址**得出的结论，均已撤回：

| 错误结论 | 真实原因 |
|---|---|
| "DSC 从未被配置" | 探针打在 `dpu_hw_dsc.c`，而 DPU 8.0 走 `dpu_hw_dsc_1_2.c` |
| "DSC 里是 bootloader 残留值" | 读的是 `0x80100`（ENC 子块），`DSC_COMMON_MODE` 在块基址 `0x80000` |
| "pingpong 的 DSC 寄存器没写" | 读 `0x6a000` 实为 pp_1；窗口 0x40 够不到 `0xa0`；且两边都是 0 |
| "init 序列缺 exit-sleep/display-on" | 正则只匹配 `write_seq_multi`，漏了两个专用 API |
| "DSC/INTF 偏移差 0x1000" | mmio 基址不同，绝对地址其实相同 |
| "厂商 CLKOUT 是 0x19" | 看错行 |
| "fbdev 也是纯黑" | 那次背光根本未亮，测试无效 |
| "面板报 booster 关（0x9e）" | 按 MIPI 定义厂商的 `0x9d` 同样 bit0=0，该解读不可靠 |
| "全部与厂商一致" | 过度概括：真正逐值相同的只有 §3.2；其余是推断或未对照 |

---

## 6. 仍然存在的问题

### 6.1 未验证项

| # | 问题 | 为什么还没答案 |
|---|---|---|
| 1 | **DSC 码流内容是否有效** | 唯一无法从寄存器判断的环节；`no_dsc` 实验因代码缺陷无效（见 6.2） |
| 2 | 面板是否接受非压缩 RGB 输入 | `no_dsc` 那轮 DCS 读取失败（`ret=0`、`Invalid response cmd`），面板未响应 |
| 3 | 厂商的 PP / DSC 编码器 / LM 寄存器值 | 两次 `sde_off` 读取被子块范围拒绝，没拿到 |
| 4 | CAF 分支是否与设备驱动一致 | `.ko` 已 strip，无法确证 |
| 5 | 面板是否需要 DT 之外的初始化 | MIUI 显示 HAL 可能额外下发命令，未知 |

### 6.2 已知的代码缺陷（导致 B 实验无效）

`nt36532_enable()` 里仍有**无条件**的 PPS 发送（`panel-novatek-nt36532.c:1032/1037`），
`no_dsc` 只对 `prepare()` 生效。因此 `no_dsc=1` 时 **DSI 关闭了 DSC 但面板仍被
要求按 DSC 解码**，两端不一致，必然黑。

**修复方式**：把 `enable()` 里那段也包进 `if (!no_dsc)`，再重跑一次即可得到有效结论。

### 6.3 未能解释的差异

| 差异 | 我们 | 厂商 |
|---|---|---|
| INTF `CONFIG` bit31（可编程预取） | `00800000` | `80800000` |
| `CMD_DMA_CTRL` | `14000000` | `d4000000` |
| `CLKOUT_TIMING_CTRL` | `0000191f` | `00000000` |
| DSI `TOTAL`（h_total） | 448 | 596 |
| CTL 层配置 | `01000002` | `1db80000` |

其中 `TOTAL` 与 CTL 层配置**推测**与模式/pipe 数有关，但**未证明**。

---

## 7. 当前代码状态

### 7.1 分支

| 分支 | 用途 | tip |
|---|---|---|
| `liuqin-7.0` | 产品分支 | `4ab4102c17f6` |
| `liuqin-6.17-tianma` | 交叉验证（6.17 + 天马 desc） | `87a3f76ddd64` |
| `liuqin-6.17` | 上游作者的 CSOT 版本 | 未改动 |

### 7.2 临时诊断代码（**全部需要在点亮后删除**）

| 文件 | 内容 |
|---|---|
| `dpu_kms.c` | `/sys/kernel/debug/dri/0/debug/bundle` 原始寄存器转储 |
| `dpu_encoder.c` / `dpu_crtc.c` / `dpu_hw_dsc*.c` / `dpu_hw_intf.c` / `dpu_hw_ctl.c` / `dpu_encoder_phys_vid.c` | `DIAG ...` 打印 |
| `dsi_host.c` | `/sys/kernel/debug/dsiN/regs` + `DIAG dsiN` |
| `panel-novatek-nt36532.c` | `diag_panel_state`、`/sys/kernel/debug/nt36532/dcs` poke、`skip_panel_init`、`no_dsc`（含 6.2 缺陷） |
| `ktz8866.c` | `/sys/kernel/debug/ktz8866/regs` 读写 |
| `dsi_phy_7nm.c` | `vendor_phy_timing` |

所有开关默认关闭，不影响正常启动路径。

### 7.3 诊断节点用法

```sh
mount -t debugfs none /sys/kernel/debug

# DPU 全量寄存器（含 INTF_FRAME_COUNT / LINE_COUNT / SSPP 错误位）
cat /sys/kernel/debug/dri/0/debug/bundle

# DSI 实时寄存器
cat /sys/kernel/debug/dsi0/regs

# 面板 DCS 读写
cat /sys/kernel/debug/nt36532/dcs
echo "0x29 0x00" > /sys/kernel/debug/nt36532/dcs

# ktz8866 偏压寄存器
cat /sys/kernel/debug/ktz8866/regs
```

### 7.4 测试镜像制作（注意）

用 `fastboot boot` 跑内存镜像。**不要用 `dtc` 反编译再编译改 bootargs**
（会产生大量告警且有风险），用 `fdtput`：

```sh
cp sm8475-xiaomi-liuqin-abl.dtb work.dtb
fdtput -t s work.dtb /chosen bootargs "<完整 cmdline>"
fdtget -t s work.dtb /chosen bootargs   # 回读校验
```

模块参数前缀：面板驱动是独立模块 `panel_novatek_nt36532.*`，
DSI PHY 属于 `msm` 模块（`msm.vendor_phy_timing=1`），
DRM 客户端是 `drm_client_lib.active`。

---

## 8. 下一步

### 8.1 唯一还能改变结论的软件实验

1. 修 §6.2 的缺陷（`enable()` 里的 PPS 加 `no_dsc` 判断）。
2. 构建一次，启动 `no_dsc=1`。
3. **判读**：
   - 点亮 → **DSC 码流是根因**，其余链路已证明正常，转去攻 DSC。
   - 仍黑且面板仍无响应 → 面板不接受非压缩输入，此路封闭。
   - 仍黑但面板有响应（DCS 读到值）→ DSC 排除，问题在面板解码侧。

### 8.2 需要用户提供的硬件侧证据（软件已到极限时）

- 万用表实测 VSP / VSN / VGH / VGL（面板排线测试点），与厂商状态对比。
- 或同型号另一台设备的对照结果。

### 8.3 仍值得补的对照数据（一次原厂重启，不必编译）

```sh
cd /sys/kernel/debug/dri/0/debug
echo "6c000 d0" > sde_off ; cat sde_reg     # 厂商活动 pingpong（pp_0 是空的）
echo "81100 60" > sde_off ; cat sde_reg     # 厂商 DSC 编码器 / RC 参数
```

---

## 9. 结论一句话

**从内存到 INTF 的整条链路已用测量证明在工作（帧计数 120fps、无取数错误、
寄存器与厂商一致），PHY 时序与内核版本均已排除；故障位于
`INTF 打包 → DSI 串行 → 面板解码` 这一段，其中唯一未验证的是 DSC 码流内容，
而检验它的实验因 `enable()` 里漏改 PPS 而失效，需修复后重跑一次。**
