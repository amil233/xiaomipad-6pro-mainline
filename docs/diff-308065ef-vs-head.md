# 基线镜像 `boot-base-308065ef` 与当前 HEAD 的源码差异

> 目的：在一次长构建之前，把"能进 shell 的基线镜像"和"我们现在的树"之间的
> 源码差异钉死，判断哪些差异**真的进了内核**、哪些可能改变早期启动行为。
> 基线镜像：`repack/base-308065ef/boot-base-308065ef.img`
> （内核提交 `308065ef80be`，CI 产物已不在 `ci/`，镜像仍在）。
> 当前 HEAD：`c4ba514b1256`（`liuqin-7.0`）；配置：`30771ea`（已去掉
> `CONFIG_CMDLINE_FORCE`）。
> 记录时间：2026-10-28。

---

## 1. 范围与方法

```sh
git -C linux-sm8450-liuqin log --oneline 308065ef80be..c4ba514b1256
git -C linux-sm8450-liuqin diff --stat 308065ef80be..c4ba514b1256
git -C linux-sm8450-liuqin diff 308065ef80be..c4ba514b1256 -- <file>
```

区间内 **10 个提交、5 个文件**（全树，非仅显示）：

| 文件 | 行数 | 来自 |
|---|---|---|
| `drivers/gpu/drm/msm/disp/dpu1/dpu_encoder_phys_vid.c` | 1 行 | `f5e92f4` |
| `drivers/gpu/drm/msm/dsi/dsi_host.c` | 57 | `f5e92f4`、`6d240ec`、`cec2a7b5`（本次） |
| `drivers/gpu/drm/panel/Kconfig` | 13 | `5fa8a9a`、`68c7cfa5`（本次） |
| `drivers/gpu/drm/panel/panel-novatek-nt36523.c` | 719 | `5fa8a9a`、`49f284c`、`3b7bf64` |
| `drivers/gpu/drm/panel/panel-novatek-nt36532.c` | 107 | `d2756356`、`68c7cfa5`、`c4ba514b`（本次） |

`drivers/gpu/drm/panel/Makefile`、DTS、DPU 其它文件、mm/clock/regulator 等**零差异**。
也就是说：基线镜像和现在之间，**除了显示子系统的这 5 个文件，源码完全一样**。

---

## 2. 每条差异是否进了我们的镜像

配置（`ci/liuqin-kernel-c4ba514b…/kernel/.config`）：`NT36532=y`、
`NT36523` 未选。据此：

| 差异 | 是否编译进镜像 | 对基线镜像的有效差异 |
|---|---|---|
| `dpu_encoder_phys_vid.c` 1 行 | ✅ 是 | **有，且无条件生效**（见 §3） |
| `dsi_host.c`：CLKOUT 硬编码 `0x13e0391f` | ✅ 是 | 只在 `mode->clock == 1937416` 时生效；我们 60/120 Hz 的 clock 都是 785245 → **不生效** |
| `dsi_host.c`：`CMD_DMA_CTRL` 参数化 | ✅ 是 | 默认值 = 基线的上游值 `0x14000000`，**等价** |
| `dsi_host.c`：DSI 全窗口 dump | ✅ 是 | 只在读 debugfs 时执行，正常路径**无影响** |
| `panel-novatek-nt36532.c` | ✅ 是 | 天马 desc 默认模式 144 Hz → **60 Hz**（新 porch）、`force_fps` 参数、probe 一行日志 |
| `panel-novatek-nt36523.c` 719 行 | ❌ 否 | 不进镜像 |
| `panel/Kconfig` 13 行 | — | 只是符号声明；NT36523 的条目未被选中 |

**因此我们的镜像相对基线，真正改变行为的只有三处**：DPU 预取那 1 行、
天马模式 144→60、以及新增的 probe 日志（无害）。

---

## 3. 唯一改变"显示使能路径"硬件编程的差异：DPU 可编程预取

`programmable_fetch_config()`（`dpu_encoder_phys_vid.c:222`）：

```c
-	if (vfp_fetch_lines) {
+	f.enable = 1;
+	if (vfp_fetch_lines) {
 		...
-		f.enable = 1;
 		f.fetch_start = vfp_fetch_start_vsync_counter;
 	}
```

代入本机参数（`dpu_8_1_sm8450.h:318`）：

| 量 | 值 |
|---|---|
| `prog_fetch_lines_worst_case` | **24** 行 |
| `start_of_frame_lines = vbp + vsw` | **216** = 214 + 2 |
| 判定 | `216 >= 24` → "prog fetch is not needed" |
| `vfp_fetch_lines` | **0** |
| `f.fetch_start` | 保持结构体初值 **0** |

于是：

| | 基线镜像 `308065ef` | 当前 HEAD |
|---|---|---|
| `f.enable` | 0（不进 if 就保持 0） | **1** |
| `INTF_CONFIG` bit31 | 清 0 | **置 1** |
| `INTF_PROG_FETCH_START` | 不写 | **写 0** |

`dpu_hw_intf.c:287-290` 自己的注释写着：

> Fetch should always be outside the active lines. If the fetching is
> programmed within active region, hardware behavior is unknown.

`fetch_start = 0` 正是**把预取起点放在帧的第 0 行**（有效区内）。
基线镜像不启用这个特性；我们启用了，而且起点是 0。**这是相对基线唯一
一处"无条件改变 INTF 硬件编程"的差异**，也是"显示一上电就挂/复位"最可疑的点。

背景：这一行来自 `f5e92f4`（"align the Tianma path with the vendor register
profile"），当时的目标是把 `INTF_CONFIG` 的 bit31 置成和厂商快照一致
（`0x80800000`）。但厂商的 `bit31` 是**带着它自己算出来的 fetch_start**
一起写的；我们这条路径 `vfp_fetch_lines` 恒为 0，只把 bit31 打开、起点写 0。

---

## 4. 其它差异的细节

### 4.1 `dsi_host.c` 的 `CLKOUT_TIMING_CTRL`

```c
if (msm_host->mode && msm_host->mode->clock == 1937416)
	data = 0x13e0391f;
else
	data = T_CLK_POST(...) | T_CLK_PRE(...);
```

按 `mode->clock` 精确匹配 144 Hz 模式；60 Hz（785245）与 120 Hz（785245）
都走 else 分支，与基线一致。**不构成差异。**

### 4.2 `CMD_DMA_CTRL`

基线：`FROM_FRAME_BUFFER | LOW_POWER`（`0x14000000`）。
当前：同一个值，只是包了一层 `dsi_cmd_broadcast` 参数（默认 0 → 同基线）。
`=1` 时才写厂商的 `0xd4000000`。**默认行为无差异。**

### 4.3 天马 desc 的模式

| | 基线 `308065ef` | 当前 |
|---|---|---|
| 天马 desc `drm_mode` | `pipa_mode_144`（2394×5620，1.9376 GHz） | `pipa_mode_60_dsc`（2096×6244，785245 kHz） |
| 天马复位 | `pipa_tm_reset` 10/3/3/15 | 同 |
| 新增参数 | — | `force_fps=60/120/144` |
| 新增日志 | — | `panel desc: …` |

60 Hz 的 porch 来自原厂实测（`900(46|100|2)x2880(214|3148|2)@60fps`），
换算后 DSI `TOTAL=0x186301bf`、clk 三件套与 120 Hz 完全相同——见
`docs/display-panel-checklist.md` §8。

### 4.4 诊断代码

- `6d240ec`（全窗口 DSI dump）：编译进来，但只在 `cat dsi0/regs` 这类读操作时执行；
- `49f284c`（`nt36523/state`）、`3b7bf64`（PPS 日志）：都在 NT36523 驱动里，
  **未编译**。

---

## 5. 结论与建议

1. 基线与现在的源码差异**只有 5 个文件**，其中真正影响运行时的只有
   **DPU 预取 1 行 + 天马模式 144→60**（日志无害）。
2. **已恢复**（`702b079dbeb3`，`liuqin-7.0`）：把 `f.enable = 1` 放回
   `if (vfp_fetch_lines)` 里，与基线写法一致。理由：
   - 它让 `INTF_CONFIG` bit31 与 `PROG_FETCH_START=0` 同时出现，而代码注释明确
     说这属于 undefined；
   - 基线镜像正是"不启用"的那一版，且能进 shell；
   - 恢复它等于回到已知可工作的硬件编程，代价一行。
   若以后仍想验证"和厂商 bit31 一致"，必须同时对照 `INTF_PROG_FETCH_START`，
   不能只看 bit31；需要时再用参数单独打开。

   > 注：`f5e92f4` 的原始动机写在它的提交信息里——"INTF programmable fetch
   > enable (BIT31) like the vendor"，即把 `INTF_CONFIG` 的 bit31 对齐厂商快照
   > 的 `0x80800000`。问题在于 bit31 只在**和 `PROG_FETCH_START` 配对**时才有
   > 意义，而那个寄存器由同一个结构体的 `fetch_start` 写入；本机
   > `vfp_fetch_lines` 恒为 0，于是只打开了开关、起点写成 0。只比一个 bit、
   > 不比配对的起点，是这条改动的根本问题。
3. 天马模式 144→60 是本次实验的目标，保留；用 `force_fps=144` 出对照图。
4. 复核命令与判据：

```sh
# 源码层面
git -C linux-sm8450-liuqin diff --stat 308065ef80be..HEAD          # 应只有 5 个文件
# 镜像层面（新产物）
grep -E 'CONFIG_DRM_PANEL_NOVATEK_NT365' ci/liuqin-kernel-<sha>/kernel/.config
# 运行时（进 shell 后）
grep -E 'INTF' /sys/kernel/debug/dri/0/debug/bundle | head
```
