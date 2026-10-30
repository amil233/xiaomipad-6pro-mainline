# 6.17 + 天马面板：点亮配置的权威记录（2026-10-30）

本文是"liuqin 天马面板在 6.17 上点亮"这一事实的**唯一权威参数记录**。
核对方法：按 §6 的复现命令重跑装配，得到的 boot 镜像 sha256 必须等于
`c76820fe69b44212732c04065d177c51a0479e0542af3a4ee29eeae7321e1923`。
**该复现已于 2026-10-30 验证通过**（产物在 `repack/617fix-rebuild/`，
与 `repack/617fix-boot/` 的镜像逐位相同）。

点亮时间线：

| 时间 | 事件 |
|---|---|
| 2026-10-29 晚 | `boot-617-nodp.img`（`3b694685881d` + 运行期 `fdtput` 关 DP）点亮 |
| 2026-10-29 夜 | `0c71219b` 把 DP disable 写进 DTS，但写成了第二个 `&mdss_dp0` 块，被原有 `status = "okay"` 覆盖 ⇒ **空操作提交**（`known-wrong-changes.md` W8） |
| 2026-10-29 深夜 | 修复提交 `c7e51cdf3290`：`status = "disabled"` 挪进真正生效的节点 |
| 2026-10-30 | `c7e51cdf3290` 的 CI 产物装配成 `repack/617fix-boot/boot-liuqin-firstboot.img`，**上机确认点亮**（用户确认） |

根因（一句话）：msm DRM master 把 DP 控制器当作 component，而 DP 一直
`-EPROBE_DEFER`（等 USB-C altmode 的 `drm_bridge`），master 永不 bind ⇒
没有 `card0` ⇒ 没有首帧提交 ⇒ 面板 `prepare()` 一次都不执行。把
`displayport-controller@ae90000` 的 `status` 改成 `disabled` 即可解开。
**这与面板、init 序列、DSC 全部无关**。

---

## 1. 镜像身份

| 项 | 值 |
|---|---|
| 路径 | `repack/617fix-boot/boot-liuqin-firstboot.img`（仓库外本机数据） |
| **sha256** | `c76820fe69b44212732c04065d177c51a0479e0542af3a4ee29eeae7321e1923` |
| 大小 | 58,687,488 字节（上限 201,326,592，即 192 MiB boot 分区） |
| 内核 | `6.17.0-rc1-gc7e51cdf3290` |
| 分支 | `linux-sm8450-liuqin` 的 `liuqin-6.17-tianma` @ `c7e51cdf3290047f33f66f9b0a9408b2c60251bf` |
| 上机方式 | `fastboot boot`（内存启动；仅当回读不到 cmdline 时才写 boot 分区） |

前一张实测点亮的镜像（历史参照）：`repack/617-boot/boot-617-nodp.img`，
sha256 `99fcc9b224104cac7840a74655b31464f893bbf1fef98713f7aafd3d564935a8`，
内核 `6.17.0-rc1-g3b694685881d`，与 617fix 的**唯一差别**是 DP 由运行期
`fdtput` 关闭而不是源码关闭。

## 2. 装配输入（四件套 + 哈希）

| 输入 | 来源 | sha256 |
|---|---|---|
| kernel Image | `ci/liuqin-kernel-c7e51cdf…/kernel/arch/arm64/boot/Image` | `8f5225ad791fd1c00ae067d45dd9dc24780dba2073829a4dd089119d5a7258b0` |
| 板级 DTB | 同一 artifact 的 `arch/arm64/boot/dts/qcom/sm8475-xiaomi-liuqin.dtb` | `293c8accc14a48ae3fe6c2464a368908d1f91b0730cca74cb1af8d8054de11de` |
| ABL overlay | `device/liuqin-abl-boot-overlay.dts`（编译后 `liuqin-abl-boot-overlay.dtbo`，260 字节） | `6e66e2f7a36b0f53fd48b9ee5dfc0ebf2130c402710b29d4f32501f323d2baf0` |
| ramdisk | `repack/unpacked/ramdisk`（installer.img 解包根，40,326,354 字节） | `a04d2b258a5571ae54ba56303bba5060f1f7e47572f6a703a0bb32d6f60d7682` |

装配中间产物（合并后的 boot DTB）：`sm8475-xiaomi-liuqin-abl.dtb`，
222,625 字节，sha256 `80b93fa2bff8d2ebdee3ec6594b536d613ce4aa7a572f59009167243a0463d44`。
镜像内 kernel 段是 `gzip -n -9` 的 Image.gz：18,126,376 字节，
sha256 `94563469b129f79a8a84e73b613032a79722810bde89ca77e6e530ea45f32406`。

artifact 交付契约核对（`ci/` 契约）：`sha256sum -c kernel/SHA256SUMS` 全过、
`build-info.json.commit` = 目录名、`kernel-modules/kernel.release` =
`6.17.0-rc1-gc7e51cdf3290`。

## 3. boot header 参数（mkbootimg v2）

`tools/lib/build-bootimg.sh` 的 liuqin v2 契约：

| 字段 | 值 |
|---|---|
| header version | 2 |
| pagesize | 4096 |
| base | 0 |
| kernel offset | `0x00008000` |
| ramdisk offset | `0x01000000` |
| tags offset | `0x00000100` |
| dtb offset | `0x01f00000` |
| header cmdline | **= DTB `/chosen/bootargs` 逐字一致**（脚本 drift 即失败） |
| os version / patch level | None |

装配后脚本自动做 round-trip 校验：`unpack_bootimg.py` 拆包后对
kernel（gzip 解压回 Image）、dtb、ramdisk 逐字节 `cmp`，并断言 header v2、
cmdline、各段大小与 dtb 地址。**这次复现全部通过。**

## 4. 内核命令行（= 6.17 板级 DTS `/chosen/bootargs`）

```
earlycon=simplefb keep_bootcon console=drm_log console=tty0
initcall_blacklist=simplefb_driver_init initcall_debug ignore_loglevel
clk_ignore_unused pd_ignore_unused rootwait
mtdoops.dump_oops=1 hung_task_panic=1 softlockup_panic=1 panic=0
qcom_q6v5_pas.slpi_auto_boot=0
```

要点：

- **未改动**，直接用 6.17 板级 DTS 自带串；与 7.0 基线唯一差别是 `panic=0`
  （7.0 是 `panic=15`）。
- **没有** `regulator_ignore_unused`（保持与 7.0 基线可比；面板驱动自己
  claim VSP/VSN/DVDD）。
- `earlycon=simplefb` + `keep_bootcon` + `console=drm_log` + 黑名单
  `simplefb_driver_init` 四件套是承载性的：早于所有 initcall 在 bootloader
  framebuffer 上出字，晚注册的 drm_log 接管（其首次写提交初始 atomic
  modeset）。两边都**没有 fbdev**（`/proc/fb` 空、无 `/dev/fb0`），
  控制台走 `drm_log`。
- **面板 desc 不靠命令行参数选**：ABL 启动时往 `/chosen/bootargs` 追加
  `msm_drm.dsi_display0=qcom,mdss_dsi_m81_36_02_0a_dualdsi_dsc_lcd_video`，
  驱动里 `strstr(saved_command_line, "m81_36_02_0a")` 命中天马 desc
  （见 §5）。`fastboot boot` 会连 DTB 一起送进内存，所以 bootargs 生效。

## 5. 显示侧配置（`pipa_tm_desc`）

源码：`linux-sm8450-liuqin` 分支 `liuqin-6.17-tianma` 的
`drivers/gpu/drm/panel/panel-novatek-nt36532.c`。

**desc 选择**：`desc_sel` 模块参数为 `auto` 时，若 of 匹配到的是
`pipa_desc`（csot）且命令行含 `mdss_dsi_m81_36_02_0a`，则切到
`pipa_tm_desc`。点亮日志应为
`panel desc: tianma (desc_sel=auto cmdline_match=1)`。

| 字段 | 值 |
|---|---|
| `dsi_info` | type `pipa`，channel 0 |
| `format` | `MIPI_DSI_FMT_RGB888` |
| `mode_flags` | `MIPI_DSI_MODE_VIDEO \| MIPI_DSI_MODE_CLOCK_NON_CONTINUOUS`（**非 burst**） |
| `drm_mode` | `pipa_mode_120`（见下） |
| `dsc` | v1.1，slice **450×20**，`slice_count = 2`，`bits_per_component = 8`，`bits_per_pixel = 8<<4`（8 bpp），`block_pred_enable = true` |
| `init_sequence` | `m81_36_02_0a_init_sequence`，**216 包**，与原厂 V14.0.9.0 DTBO entry.15 逐字节相同 |
| `reset_sequence` | `pipa_tm_reset`：10 / 3 / 3 / 15 ms（厂商 DTBO `<0 10 1 3 0 3 1 15>`） |
| 供电 | `vddio` / `dvddbuck` / `dvddldo` 三路 regulator + `reset-gpios`（tlmm 0） |
| 双链路 | of graph port 1 取 `dsi1`，bonded dual-DSI（`qcom,dsi-ctrl-num <0 1>`） |

`pipa_mode_120`（120 Hz，点亮用的就是这一版）：

```
.clock     = (1800+200+4+92) * (2880+26+2+214) * 120 / 1000   // 785245 kHz
.hdisplay  = 1800    .hsync_start = 2000   .hsync_end = 2004   .htotal = 2096
.vdisplay  = 2880    .vsync_start = 2906   .vsync_end = 2908   .vtotal = 3122
.width_mm  = 148     .height_mm = 237
```

`force_fps` 模块参数默认 0 ⇒ 用 desc 自带 mode（120 Hz）；`force_fps=60`
切换到 `pipa_mode_60_dsc`（VFP 翻倍 26→3148，pclk/byteclk 不变）。
**6.17 点亮用的是 120 Hz 非 burst**；7.0 那边三种组合（60/120 ×
burst/非 burst）全黑，且 DSI 控制器 / PHY / DSC / INTF 寄存器逐值相同，
差异在寄存器之外（初始化顺序、时序或命令流时机）。

## 6. 复现命令（已验证逐位复现）

```sh
cd /home/ubuntu/linux_kernel_git
ci=ci/liuqin-kernel-c7e51cdf3290047f33f66f9b0a9408b2c60251bf
export IMAGE="$ci/kernel/arch/arm64/boot/Image" \
       DTB="$ci/kernel/arch/arm64/boot/dts/qcom/sm8475-xiaomi-liuqin.dtb" \
       RAMDISK="repack/unpacked/ramdisk" \
       DTC=/usr/bin/dtc FDTOVERLAY=/usr/bin/fdtoverlay \
       CMDLINE="earlycon=simplefb keep_bootcon console=drm_log console=tty0 initcall_blacklist=simplefb_driver_init initcall_debug ignore_loglevel clk_ignore_unused pd_ignore_unused rootwait mtdoops.dump_oops=1 hung_task_panic=1 softlockup_panic=1 panic=0 qcom_q6v5_pas.slpi_auto_boot=0" \
       OUT_DIR="repack/617fix-rebuild"
sh xiaomipad-6pro-mainline/tools/lib/build-bootimg.sh
sha256sum repack/617fix-rebuild/boot-liuqin-firstboot.img
# 必须等于 c76820fe69b44212732c04065d177c51a0479e0542af3a4ee29eeae7321e1923
```

注意：

- `DTC`/`FDTOVERLAY` 必须用系统的 `/usr/bin/{dtc,fdtoverlay}`（DTC 1.7.2），
  CI artifact 不含 `scripts/dtc/`。
- `CMDLINE` 必须逐字等于 6.17 板级 DTS 的 bootargs；脚本在装配后断言
  DTB `/chosen/bootargs` 与请求串一致，drift 直接失败。
- 脚本内部只用 `dtc`/`fdtoverlay`/`mkbootimg.py`/`unpack_bootimg.py`，
  **不是内核编译**（AGENTS.md §0.1 允许的本地动作）。

## 7. DTB 加工链（`build-bootimg.sh` 内部）

1. `dtc -@` 把 `device/liuqin-abl-boot-overlay.dts` 编译成 overlay dtbo
   ——只放 ABL 选板用的私有元数据：
   `qcom,msm-id = <531 0x10000 540 0x10000 530 0x10000>`、
   `qcom,board-id = <0x10008 0>`、`xiaomi,miboard-id = <0x10 0>`
   （`miboard-id 0x10` = entry.15，本机 `hwid.project=16`）。
2. `fdtoverlay` 合并到板级 DTB。
3. `ABL_OVERLAY_SINK=1`（默认开）：`tools/lib/abl-symbols.py` 注入
   `__symbols__` + inert sink（`/liuqin-abl-overlay-sink`，phandle 0x16d）。
   符号 union 取自**设备在装的 V14.0.9.0.TMYCNXM**
   （`tools/local/roms/liuqin/V14.0.9.0.TMYCNXM/analysis`）：
   38 个 DTBO entry + 11 个 base DTB，共导出 1744 个符号。
   不加这步，ABL 应用原厂 overlay 时因缺 `__symbols__` 直接拒绝启动。
4. `ABL_DTB02_IDS=0`（默认）：断言 boot DTB 带本机身份
   `qcom,msm-id = <0x213 0x10000 0x21c 0x10000 0x212 0x10000>`、
   `qcom,board-id = <0x10008 0x00>`、`xiaomi,miboard-id = <0x10 0x00>`。
5. 断言 `/chosen/bootargs` = cmdline；断言 simple-framebuffer 节点还在
   （`reg = <0 0xb8000000 0 0x2b00000>`，1800×2880，stride 7200，
   `a8r8g8b8`）以及 `/chosen` 的 `#address-cells/#size-cells/ranges`
   （earlycon 地址翻译需要）。
6. `mkbootimg.py` 打包 → `unpack_bootimg.py` round-trip 逐字节校验。

**板级 DTS 里点亮的唯一源码改动**（`c7e51cdf3290`）：真正生效的那个
`&mdss_dp0` 节点 `status = "disabled"`（路径
`/soc@0/display-subsystem@ae00000/displayport-controller@ae90000`）。

## 8. 点亮后的观测（黄金参照）

| 项 | 值 |
|---|---|
| `/sys/class/drm/` | `card0`、`card0-DSI-1`、`renderD128` |
| DPU | `dpu hardware revision:0x80050000`、`Initialized msm 1.13.0` |
| 控制台 | `printk: console [drm_log0] enabled` |
| `dsc:` 打印 | `pic 1800x2880 slice 450x20 count 2 chunk 450 bpp 128 bpc 8`（`ae96000.dsi.0`） |
| DSI0 `CTRL` | `0x000001F3` |
| DSI0 `VID_CFG0` | `0x02009230` |
| DSI0 `TOTAL` | `0x0C3101BF`（120 Hz） |
| DSI0 `0x0a8` | `0x1F00` |
| DSI0 `CLK_STATUS` | `0x008047C3` |
| DSI0 `DSC_CTRL` | `0x03840B01` |

寄存器级黄金快照：`repack/golden-617/`（`dsi0.txt`、`dsi1.txt`、
`phy0-70.txt`、`ctl-lm-pp-70.txt`，均为能亮状态逐值）。

**判读陷阱（勿再踩）**：

- `0x0a4` 在**能亮时也读 0**（错偏移），不能当 `LANE_STATUS`；
  判链路用 `0x0a8` 和 `0x120 CLK_STATUS`。
- `signal=0x80`、`display=0x00` 在**能亮时也出现**，不是"面板没收到码流"的证据。
- 两边都没有 fbdev，往 `/dev/tty0` 写东西**不会显示**。

## 9. 相关配置文件索引

| 文件 | 作用 |
|---|---|
| `tools/lib/build-bootimg.sh` | 装配脚本（本文 §3/§6/§7 的契约来源） |
| `tools/lib/abl-symbols.py` | `__symbols__` union + sink 注入 |
| `tools/lib/abl-dtb-ids.py` | `ABL_DTB02_IDS=1` 时的身份镜像（本镜像未用） |
| `device/liuqin-abl-boot-overlay.dts` | ABL 选板元数据 overlay |
| `tools/local/roms/liuqin/V14.0.9.0.TMYCNXM/analysis` | 原厂 38 DTBO + 11 base DTB，符号 union 来源（gitignore） |
| 内核 `arch/arm64/boot/dts/qcom/sm8475-xiaomi-liuqin.dts` | 板级 DTS：bootargs、simple-framebuffer、`&mdss_dp0 status=disabled` |
| 内核 `drivers/gpu/drm/panel/panel-novatek-nt36532.c` | 天马 desc / init / DSC / reset（§5） |
| `ci/liuqin-kernel-c7e51cdf…/kernel/.config` | 本次构建配置（含 `CONFIG_CMDLINE` 相关） |
| `repack/unpacked/ramdisk` | installer.img ramdisk（gitignore） |
| `repack/golden-617/` | 能亮状态寄存器黄金快照（仓库外） |

## 10. 结论

1. 天马面板、DDIC、init 216 包、DSC 参数、reset 时序、双 DSI 绑定
   **全部无罪**；"7.0 黑屏"是 7.0 移植线自己的问题。
2. 6.17 方案的**决定性差异只有一个**：DP 控制器 `status = "disabled"`。
3. 7.0 显示线已暂停（`b96111112b78` 建议 revert：组合无效且底座
   `c4ba514b` 是坏提交）。7.0 若重启，需要的不是参数试错，而是
   **时序级证据**（初始化顺序 / 命令与视频流的先后），
   因为寄存器层面已无法区分能亮与不能亮。
