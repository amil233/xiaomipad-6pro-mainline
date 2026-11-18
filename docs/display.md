# 显示：已确立的结论与判读陷阱

**这是显示侧唯一现行文档。** 它取代了原先散落的 6 份材料
（`display-panel-checklist.md`、`display-blackout-plan.md`、
`display-driver-plan.md`、`display-driver-repair-plan.md`、
`display-617-tianma-lit.md`、`diff-308065ef-vs-head.md`）——
那些文件已冻结到 `docs/archive/`，只作为取证过程留档，其中的
"未解决问题""下一步""候选补丁"**全部不再是任务**。

事实基线：设备 Xiaomi Pad 6 Pro（liuqin，128G），面板天马
`m81_36_02_0a`，DPU 8.0（`0x80050000`），DSI 6G v2.6，双 DSI bonded，
1800×2880 @ 120 Hz，DSC v1.1。

## 1. 结论：显示已经点亮，且不是靠"更多寄存器对齐"

点亮发生在 6.17 阶段，并在 7.0 阶段复现。关键判断是：

- **DPU 在出帧、DSC 在编码、DSI 在传**——这些都用测量证明过
  （`INTF_FRAME_COUNT` 每秒 +121、`SSPP UBWC_ERROR_STATUS=0`、
  `SRC_ADDR_SW_STATUS=0`、无 SMMU fault、PPS 128 字节逐字段正确）。
- **寄存器层面我们与厂商"逐值相同"的范围是有限的**：只有
  `CTRL=0x1f3`、`VID_CFG0=0x02009230`、`ACTIVE_H/V/HSYNC`、
  `DSC_CTRL=0x03840b01`、`CLK_STATUS=0x008047c3`、INTF `CONFIG2` 与
  `+064` 这几项被双方向对照过。**不要把"我猜厂商也这样"写成"相同"。**
- 7.0 阶段曾出现"6.17 + 天马其中一版能亮、7.0 全黑且寄存器逐值相同"，
  最终定位在**寄存器之外**：init 序列时机、DSC/PPS 发送点、面板
  desc 里的 mode 与面板实际被 init 成的模式是否一致。
- 因此**不要**再从"多对齐一个厂商寄存器值"入手解决问题。同类改动
  已经全部失败并被登记（见 §4）。

## 2. 黄金值（能亮状态，逐值）

| 项 | 值 |
|---|---|
| `/sys/class/drm/` | `card0`、`card0-DSI-1`、`renderD128` |
| 控制台 | `printk: console [drm_log0] enabled` |
| `dsc:` 打印 | `pic 1800x2880 slice 450x20 count 2 chunk 450 bpp 128 bpc 8`（`ae96000.dsi.0`） |
| DSI0 `CTRL` | `0x000001F3` |
| DSI0 `VID_CFG0` | `0x02009230` |
| DSI0 `TOTAL` | `0x0C3101BF`（120 Hz） |
| DSI0 `0x0a8` | `0x1F00` |
| DSI0 `CLK_STATUS` | `0x008047C3` |
| DSI0 `DSC_CTRL` | `0x03840B01` |

寄存器级快照在 `repack/golden-617/`（`dsi0.txt`、`dsi1.txt`、
`phy0-70.txt`、`ctl-lm-pp-70.txt`），全部取自**能亮状态**。

## 3. 面板 desc 与模式（当前产品形态）

| 字段 | 值 |
|---|---|
| `dsi_info` | type `pipa`，channel 0 |
| `format` | `MIPI_DSI_FMT_RGB888` |
| `mode_flags` | `VIDEO \| CLOCK_NON_CONTINUOUS`（**非 burst**） |
| `dsc` | v1.1，slice **450×20**，`slice_count=2`，`bpc=8`，`bpp=8<<4`，`block_pred_enable=true` |
| `init_sequence` | `m81_36_02_0a_init_sequence`，**216 包**，与原厂 `V14.0.9.0` DTBO `entry.15` 逐字节相同 |
| `reset_sequence` | `pipa_tm_reset`：10 / 3 / 3 / 15 ms |
| 供电 | `vddio` / `dvddbuck` / `dvddldo` 三路 regulator + `reset-gpios`（tlmm 0） |
| 双链路 | of graph port 1 取 `dsi1`，bonded（`qcom,dsi-ctrl-num <0 1>`） |

`pipa_mode_120`（点亮用的就是这一版）：

```
.clock     = (1800+200+4+92) * (2880+26+2+214) * 120 / 1000   // 785245 kHz
.hdisplay  = 1800    .hsync_start = 2000   .hsync_end = 2004   .htotal = 2096
.vdisplay  = 2880    .vsync_start = 2906   .vsync_end = 2908   .vtotal = 3122
.width_mm  = 148     .height_mm = 237
```

`force_fps=0`（默认）用 desc 自带模式；`force_fps=60` 切 `pipa_mode_60_dsc`
（VFP 26→3148，pclk/byteclk 不变）。

**desc 选择的硬规则**：`desc_sel=auto` 时，若 of 匹配到 `pipa_desc`(CSOT)
且命令行含 `mdss_dsi_m81_36_02_0a`，切到 `pipa_tm_desc`。点亮日志必须有
`panel desc: tianma (desc_sel=auto cmdline_match=1)`——没有这一行就是选错 desc。

**默认模式必须是 init 序列里编进去的那个**：厂商 init 编的是 120 Hz 的
porch 组（`b3 40 b2 91`），144 Hz 需要运行时再发命令。曾把 144 当默认，
结果"面板被 init 成 120、主机送 144"，全部黑屏。

## 4. 判读陷阱（踩过的，别重复）

| 陷阱 | 真相 |
|---|---|
| 把 `0xa4` 当 LANE_STATUS | 能亮时它也读 0（偏移错）。判链路用 `0xa8` 和 `0x120 CLK_STATUS` |
| `signal=0x80`/`display=0x00` 当成"面板没收到码流" | 能亮时也这样出现，不是证据 |
| 两边都没有 fbdev，往 `/dev/tty0` 写 | 不会显示 |
| "DSC 从未被配置" | 探针打在 `dpu_hw_dsc.c`，而 DPU 8.0 走 `dpu_hw_dsc_1_2.c` |
| "DSC 里是 bootloader 残留值" | 读的是 `0x80100`（ENC 子块），`DSC_COMMON_MODE` 在块基址 `0x80000` |
| "厂商 CLKOUT 是 `0x19`" | 看错行 |
| "fbdev 也是纯黑" | 那次背光根本没亮，测试无效 |
| "全部与厂商一致" | 过度概括；真正逐值相同的只有 §2 那几项 |
| 把 `caf-display/` 当厂商驱动 | 它是社区实现，与设备实际 `msm_drm.ko` 未必同源；只能提出假设（B 级证据） |

### 已证伪的改动（全部已回退或未进树）

| 改动 | 错在哪 |
|---|---|
| `CMD_DMA_CTRL` 把厂商 master 值写每条链路 | 原厂是 "master 踢一次 + 硬件广播"，主线是 "两条各写一份 + 同时 trigger"，互斥；两路都置 master 会让 DCS 重复/交错 |
| `INTF_CONFIG` bit31 单独置位 | 它与 `PROG_FETCH_START` 成对；本机 `vbp+vsw=216 ≥ 24`，起点恒 0 ⇒ 预取落在第 0 行，属 undefined |
| `CLKOUT_TIMING_CTRL` 硬编码 `0x13e0391f` 按 `mode->clock` 匹配 | 魔法数开关，且该值未在任何原始快照里出现；当前保留但未验证，60/120 路径不生效 |
| 写 `DSI DSC` 的 `0x2a4..0x33c`（39 个影子寄存器） | 只有 `0x2a0` 是编程寄存器，其余是 shadow，会覆盖硬件自算值 |
| 天马 desc 默认 144 Hz | 见 §3 |
| 删旧驱动换上"能 probe 但看不见"的新驱动 | 所有 debugfs/poke 手段随之失效，实验只能盲做 |
| `CONFIG_CMDLINE_FORCE` 强行接管命令行 | 强制串是 DTB 串的子集，丢掉 `initcall_debug`/`rootwait`/`panic=` 等；两张开了它的镜像都在 shell 前复位 |

## 5. 当前没有在跑的显示排查

原 §5 登记的那条键盘问题已于 2026-11-18 **撤销**：成因是 GNOME 无障碍屏幕
键盘未启用，与显示、触控、面板 follower 均无关，见
`STATUS.zh-CN.md` §6 的撤销记录。**不要再按"面板 follower 抢 TDDI 固件"
这条假设去改 nt36523。**

除此之外，显示侧**没有在跑的排查计划**。"再多对齐一个厂商值"这条路线
已经关闭——上面七条失败记录就是它的全部产出。
