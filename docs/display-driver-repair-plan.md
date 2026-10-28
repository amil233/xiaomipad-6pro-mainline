# liuqin 天马面板：驱动问题复核与修复计划

> 输入：工作区 `AGENTS.md`（§6–§8 交接点）、`xiaomipad-6pro-mainline/AGENTS.md`、
> `docs/display-driver-plan.md`、`docs/display-blackout-plan.md`、
> `display-drivers-archive/` 两份互斥驱动（`old-nt36532-210577a`、
> `new-nt36523-3b7bf64`）。
> 基线：内核 `liuqin-7.0` @ `3b7bf64894c2`（工作树干净，CI 产物已核对）。
> 本文只写能落到文件/行号/字节的事实；推断单独标注。

---

## 0. 结论摘要

1. **desc 选型既不可见、也从未被运行时验证过。** 两份驱动都只在
   `saved_command_line` 含 `mdss_dsi_m81_36_02_0a` 时才选天马 desc
   （旧 `:1177-1179`，新 `:1837-1839`），而**两者都不打印实际选中的 desc**。
   现有证据两边都有，互相矛盾：
   - `repack/` 下 24 个已装配镜像的 `/chosen/bootargs` 与 boot header cmdline
     **都不含**该串（逐个解出，见 §1.1）；
   - 但 bootloader 自己的命令行**含**该串——`repack/2105-boot/README.md:120-121`
     有实采的 `Kernel command line: … msm_drm.dsi_display0=qcom,mdss_dsi_m81_36_02_0a…`；
     而正常启动时我们的串与 ABL 串同时出现（同文件 `:102-103`）。
   ⇒ **任何一次黑屏实验到底跑的是天马还是 CSOT 的 194 包 init 序列，无法从现有产物判定。**
   因此文档里所有"天马 desc 同样黑 / 不是 desc 的问题"一类的结论，都要降级为
   "desc 未验证"，而不是判错。
   - 唯一例外：`3b7bf64` 的 oneshot 带 `CONFIG_CMDLINE_FORCE` + 含模块名的强制串
     （`ci/…/.config:590`），内核命令行被强制替换，**必然是**天马 desc；它黑屏 +
     有背光 + 约 10 s 复位，但面板状态、扫描行、PPS 一概没采到。

2. 因此下列结论**需要加"desc 未验证"标注**（不是判错，是不能当证据用）：
   - 「6.17 + 天马 desc 同样黑 ⇒ 不是 7.0 回归」（`xiaomipad-6pro-mainline/AGENTS.md` §3.1）；
   - 「init 序列/复位已排除」（同 §4）——那是**静态比对**，与运行时是否送这套序列无关；
   - 「`no_dsc` 非压缩路径关闭」（工作区 `AGENTS.md` §7.1/§7.2）——当轮用的 desc 未知，
     且若跑的是 CSOT desc，它不带 `VIDEO_BURST`，与天马节点本就不同；
   - 「根因在 DSI/DPU 接管」（同 §7.5）——支撑它的 `skip_panel_init`、`no_dsc`
     同样没有 desc 证据。

3. 两份驱动之间**真正影响显示**的差异只剩三条，其余都已闭合（§2.5）：
   desc 选型不透明、天马模式（旧驱动 144 Hz vs 新驱动 120 Hz）、
   以及新驱动独有的 ~10 s 复位。前两条在旧驱动上就能测，第三条暂时绕开
   （不阻断旧驱动平台），但产品化前必须修。

4. 还有一条**可当场判伪**的 DSC 级不一致：主线把 PPS 的 `pic_width` 写成
   整条模式的 1800，而每条 bonded 链路只送 2 个 450 宽 slice，
   PPS 却让解码端算出 4 个（§2.3）。`pps:` 日志的第 8、9 字节就能定案。

5. **执行顺序改为"先修旧驱动，再移植"（用户决策）**：新驱动在能进 shell 之前
   就复位，没有用户态就没有任何可观测性；旧驱动能一直 boot，debugfs、poke、
   `no_dsc`、扫描行、照片比对全都能用。所以旧驱动做**诊断平台**（P0–P2），
   根因定下来之后一次性移植到新驱动，并在同一阶段修它的 ~10 s 复位（P3）。
   新驱动阶段没有用户态窗口，取数靠 `ramoops/pstore`（附录 A）。

---

## 1. 证据复核

### 1.1 desc 选型取证（本次新增，可复现，结论是"无法判定"）

两份驱动都在 probe 里做同一个判断：

```c
if (pinfo->desc == &pipa_desc && saved_command_line &&
    strstr(saved_command_line, "mdss_dsi_m81_36_02_0a"))
        pinfo->desc = &pipa_tm_desc;
```

`pipa_desc` 是 CSOT（194 包 init），`pipa_tm_desc` 是天马（216 包 init）。
所以"这次到底初始化了哪块屏"完全取决于内核命令行的来源。

把 24 个已装配镜像的 boot header cmdline（偏移 `0x40`）与 DTB
`/chosen/bootargs` 都解出来：**两处都不含该串**，只有
`initcall_blacklist`/`console`/`no_dsc` 这类诊断参数。

| 镜像 | header cmdline | `/chosen/bootargs` | 含模块串 |
|---|---|---|---|
| `oneshot-boot/boot-oneshot-3b7bf64.img` | 诊断串 | 诊断串 | 否（但内核内置强制串含，见下） |
| `base-308065ef/…`、`nodsc-boot/*`、`2105-boot/*`、`4ab4-boot/A–E`、`87a3`、`703`、`ff5f`、`fef0`、`c434`、`a8b6`、`1473`、`nomsm`、`notouch` | 诊断串（个别为空） | 诊断串 | 否 |

复现（只读）：

```sh
python3 - <<'EOF'
import struct,glob
for f in sorted(glob.glob('repack/*-boot/*.img')):
    d=open(f,'rb').read()
    print(f, repr(d[64:64+512].split(b'\0')[0][:60]))
EOF
fdtget -t s <解出的 dtb> /chosen bootargs
```

但 bootloader 自己传的串**是含**该串的。`repack/2105-boot/README.md` 记了两次实采：

- `:102-103` 正常启动（装好的产品镜像）：`/proc/cmdline` = 我们的 271 字符串
  **出现两次**（header + DT）+ `androidboot.verifiedbootstate=orange …`；
- `:117-122` 一次 `fastboot boot` 失败退出到诊断 shell：内核只拿到 ABL 的 stock 串，
  ```
  [0.000000] Kernel command line: androidboot.bootdevice=1d84000.ufshc ...
              msm_drm.dsi_display0=qcom,mdss_dsi_m81_36_02_0a_dualdsi_dsc_lcd_video: ...
  ```
  同一次 `diag[` 一条都没有、DCS 全 `0xff`（面板根本没 prepare）。

⇒ 于是有两种自洽的解释，产物本身分不出来：(a) 黑屏那几次用的是我们的
header/DT 串（不含模块串）→ CSOT desc；(b) ABL 串被合并进来（含模块串）→
天马 desc。**必须用一行 `dev_info` 或 `/proc/cmdline` 才能定案**，这就是 P1-1
和 P0 采集里第一件事。

唯一可以确定的是 oneshot：`3b7bf64` 带 `CONFIG_CMDLINE_FORCE=y` 与
`CONFIG_CMDLINE="... msm_drm.dsi_display0=qcom,mdss_dsi_m81_36_02_0a_dualdsi_dsc_lcd_video:"`
（`ci/liuqin-kernel-3b7bf64…/kernel/.config:590`），强制串**替换**掉 DT/ABL 的全部
内容，因此那一次必然是 `pipa_tm_desc`。它黑屏 + 有背光 + 复位——但面板状态、
扫描行、PPS 一概没采到：复位实际来得比 10 s 更早，远程 shell 根本进不去。

### 1.2 厂商 DTBO 与两个 desc 的对照（已闭合）

以 `repack/e15.dts:11087-11221`（天马节点，`panel-name = "xiaomi m81 36 02 0a
dualdsi dsc lcd video panel"`）为准：

| 项 | 厂商 | 旧驱动 | 新驱动 | 判定 |
|---|---|---|---|---|
| 模式 | 单一 `timing@0`，120 Hz，`clockrate=0x3c061800`（1.007 GHz） | 天马 `pipa_mode_144`（2394×5620，1.9376 GHz，来自 vendor 运行态） | `pipa_mode_120`（2096×3122，785 MHz） | **旧驱动与厂商 init 冲突**：on-command 写的是 120 Hz porch 组（`b3 0x40 b2 0x91`、`3b 03 d8 1a 0a 0a 00`），144 需另发 `b3 00 b2 00` |
| 行时序 | 每链路 900+100+2+46=1048 | 2096/2=1048 | 2096/2=1048 | 一致，不是问题 |
| 复位 | `<0 10 1 3 0 3 1 15>` | 天马同值；CSOT 用 12/12/12/12 | `pipa_reset` 同值 | 天马一致；CSOT 的值才是旧驱动的瑕疵，但"CSOT 已在 6.17 点亮"只是上游说法，本机未复现，不动 |
| 链路标志 | `burst_mode` + `bllp-power-mode` + `bllp-eof-power-mode` | 天马 = VIDEO\|BURST\|NON_CONT | 天马 = 同 + LPM | 已由 `VID_CFG0=02009230` 实测闭合 |
| DSC | 1.1、450×20、2 slice/pkt、8bpc/8bpp、block-pred；**无** slice-count/chunk/RC 字段 | 同 | 同 | 一致 |
| `slice_per_pkt` | `qcom,mdss-dsc-slice-per-pkt = <2>` | 2 | 2 | `DSC_MODE_CTRL=0x03840b01`（WC=0x384=900）实测闭合 |
| init 序列 | 216 包 | 216 包（逐包相同） | 216 包（逐包相同） | 内容一致；**但见 §1.1：历史运行几乎没跑过它** |
| 结尾 | `0x11` 等 120 ms、`0x29` 等 20 ms | — | 等 40 ms | 无害 |
| PHY 14 字节 | `00 22 08 09 19 23 09 09 09 02 04 00 1c 0e` | 计算值，5/14 不同 | 同 | `vendor_phy_timing=1` 实测无变化，已排除 |

DSC/PPS 参数本身**不需要再查**：8bpc/8bpp 下 CAF 与主线的 RC 推导输入逐值相同
（`caf-display/msm/sde_dsc_helper.c:121` vs `resolute/…/drm_dsc_helper.c:374-376`），
`slice_chunk_size = 450` 两边相同，`pps_delay_ms` 两边都是 0。
唯一需要确认的是**打包时机**：PPS 在 `prepare()` 里打包（新驱动 `:1582`），
必须晚于 msm 的 `dsi_populate_dsc_params()`（`dsi_host.c:1853-1896`，
由 `power_on → dsi_timing_setup` 触发）。`3b7bf64` 已经把
`dsc: … chunk %u` 打进 dmesg，**这一行就是自检**：chunk=450 才算时序正确。

---

## 2. 两份驱动的问题清单

### 2.1 新驱动 `panel-novatek-nt36523.c`（产品目标，暂缓上机）

| # | 问题 | 位置 | 影响 | 判据/证据 |
|---|---|---|---|---|
| N1 | desc 由 cmdline 子串决定，且**不打印选中的 desc** | `:1837-1839` | 选型不可观测；历史实验无法判定（§1.1）；`fastboot boot` 丢命令行时会静默退回 CSOT | 无日志即不可观测 |
| N2 | 约 10 s 复位，根因未查清 | 整驱动 | 阻断一切采集 | 旧驱动同机不复位；`PANIC_TIMEOUT=0` 且无看门狗节点 |
| N3 | probe 在 `drm_panel_add()` 之后可失败返回，未 `drm_panel_remove()` | `:1899-1914` | panel 留在全局链表、devm 释放后 UAF；attach 半成功 | 代码路径 |
| N4 | `num_supplies` 未与 `supplies[3]` 校验 | `:1841-1844` | 后续 desc 越界写 | 代码路径 |
| N5 | `disable()` 循环按 `DSI_NUM_MIN + is_dual_dsi` 解引用 `dsi[1]`，无 NULL 检查 | `:1617,1623` | 今天靠 probe 保证，未来必炸 | 代码路径 |
| N6 | 诊断只经 debugfs `state`，19 次 DCS 读、视频模式下每次 70 ms + 200 ms 等待 | `:1761-1808` | 本机没有可用的用户态窗口（复位早于 shell），这个节点在故障场景下等于不存在 | `dsi_host.c:1257,1510` |
| N7 | `MIPI_DSI_MODE_LPM` 常驻 `mode_flags`（desc），而旧驱动在 `prepare` 加、`unprepare` 清 | `:1526-1527` | 语义差异，未见危害 | 旧驱动 `:1001-1003,1110-1112` |

**不算缺陷**（不要再改）：没有 `.enable` 回调（`drm_panel_enable()` 有判空，
背光仍会开）；PPS 在 `prepare` 里发（vendor 也是 ON→PPS，且时序自检见 §1.2）；
40 ms vs 20 ms 收尾延时。

### 2.2 旧驱动 `panel-novatek-nt36532.c`（诊断平台，先修这块）

| # | 问题 | 位置 | 影响 |
|---|---|---|---|
| O1 | CSOT desc 用 12/12/12/12 复位、无 burst，与 DTBO 不一致 | `:758-781` | "CSOT 已在 6.17 点亮"是上游说法、本机未复现；暂不动，回归时再查 |
| O2 | 天马 desc 用 144 Hz 运行态时序 | `:722-741` | 与厂商 init 的 120 Hz porch 组矛盾；P1 先改成 120 并留 `mode=` 开关 |
| O3 | 诊断节点只有 `dcs` poke，没有扫描行读（0x45） | `:945-971` | 无法回答"面板是否在扫我们的帧"；P1 补上 |
| O4 | `no_dsc` 的 `enable()` 分支已修（`:1073`） | — | 但那一轮跑的是 CSOT desc，结论仍作废 |

### 2.3 唯一还站得住的 DSC 级不一致：PPS 的 `pic_width`

把 DSC 从面板驱动追到硬件（`resolute` 与 liuqin 两棵树一致）：

- 面板只提供 `struct drm_dsc_config`（`:1036-1046`），PPS 由 `prepare()` 打包
  （`:1582`）后当**普通 DCS 命令**发出（`:1592`），不写任何 DSI 寄存器
  （主线没有 `dsi_dsc_pkt`、没有 `0x9a`）。
- `dsi_populate_dsc_params()`（`dsi_host.c:1853-1896`）补全 RC 参数、
  `slice_chunk_size=450`、`line_buf_depth=9`，但**从不改 `slice_count`、
  也不改 `pic_width`**；`pic_width` 在 `dsi_timing_setup()` 里被写成
  **整条模式的宽度** `mode->hdisplay` = 1800（`dsi_host.c:1037`），
  而同函数已经把 DSI 时序按 bonded 折半（`:1012-1022`）。
- DSC 解码端只能从 PPS 推 slices/line：`pic_width/slice_width`。
  于是 PPS 说每行 4 个 slice（1800/450），而每条链路实际只送 2 个
  （`DSC_MODE_CTRL=0x03840b01`：WC=900=450×2、1 包/行）。
- 厂商侧是每链路 900：DTBO `panel-width=0x384`、`slice-width=0x1c2`，
  CAF `intf_width = mode->timing.h_active`、`pic_width = h_active`、
  `slice_count = ceil(intf_width/slice_width) = 2`（`dsi_panel.c:2754,2762,2836`），
  与本机实测的 `PKT_PER_LINE=0`（=1 包/行，即 slice_count/slice_per_pkt=1）自洽。
- 主线**没有任何 dual-DSI + DSC 面板先例**可参照：`resolute` 里带
  `dual_dsi` 的三个面板（himax-hx8279、novatek-nt35950、novatek-nt36523）
  都不设 `slice_count`，也就没有暴露过这条算术。

可判伪的检查：`3b7bf64` 已在 prepare 里打印 128 字节 PPS
（`pps: %*ph`）。**PPS 第 8、9 字节**（0 基）应是 `07 08`（1800）还是
`03 84`（900）——一条 dmesg 即可定案，不需要额外的实验。
**反向证据**：上游作者的 6.17 树里 `pic_width` 同样是 `mode->hdisplay`
（`liuqin-6.17:dsi_host.c:1013`），若"CSOT 设备已点亮"属实，
1800 就不是 CSOT 的致命项——但天马模块是否同样容忍，未知。
所以这条按"高置信推断、待硬件判据"处理，不作为既定根因。

### 2.4 其他次要不确定项

- `mipi_dsi_compression_mode()` 会额外发一条 DCS `0x9b`（enable）
  命令；厂商侧没有等价命令（CAF 只发 PPS，`dsi_panel.c:4414-4431`）。
  可能无害，也可能扰动 DDIC；建议做成模块参数，便于 A/B。
- 旧驱动天马 desc 的 144 Hz 与厂商 init 内置的 120 Hz porch 组矛盾（§1.2），
  不能用来证明"天马 desc 也黑"。

### 2.5 已闭合、不要重复的项

- DSC **参数**与 PPS **字段值**（两边推导逐值相同；§2.3 的 `pic_width` 是
  框架层写值，不是 desc 参数）、`slice_per_pkt`（`0x384=900` 实测）、
  行场时序（1048/3122 实测一致）、复位波形、init 序列字节一致性、
  PHY 时序（5/14 差异，`vendor_phy_timing=1` 无变化）、链路 flags、`no_dsc`、
  `skip_panel_init`、link flags、clock lane LP、写 `0x2a4..0x33c`（见
  `display-driver-plan.md` §9 negative list）。

---

## 3. 修复计划

### 3.0 决策：诊断平台用旧驱动，产品目标仍是新驱动

用户实测新驱动在能进 shell 之前就复位，**没有用户态就没有可观测性**：debugfs、
poke、`no_dsc`、扫描行、照片对比全都用不上。旧驱动能一直 boot，这些手段都在。
所以把两件事分开：

| | 旧驱动 `nt36532` | 新驱动 `nt36523` |
|---|---|---|
| 角色 | **诊断平台**：所有实验、所有交互式取证 | **产品目标**：上游化、最终入库 |
| 上机 | 现在就开始 | 暂缓，等旧驱动上把根因定下来再移植 |
| 代价 | 已从树上删除（`5fa8a9a`），需要诊断分支 revert 回来 | ~10 s 复位这条缺陷仍要单独修 |

这样做不违背项目方向：新驱动是最终目标，但**先在一个能看见东西的平台上把
"面板为什么不亮"变成可复现的观测**，再一次性移植，比在新驱动上盲改便宜得多。
所有在旧驱动上验证过的差异（模式、复位、PPS、init 分页）都是机械可移植的。

### P0（零构建，今天就能做）：旧驱动 + 天马 desc，先确认命令通路

0. **先花一分钟给 §1.1 定案**：在现在正常启动的产品镜像上直接
   ```sh
   cat /proc/cmdline | tr ' ' '\n' | grep -n 'dsi_display0\|m81_36'
   ```
   能看到 `msm_drm.dsi_display0=qcom,mdss_dsi_m81_36_02_0a…`，说明 ABL 串会被
   合并进 `saved_command_line`，那么历史实验一直是天马 desc，下一步的
   `fdtput` 也就天然可信；看不到，说明只有我们的串生效，天马 desc 从未被选中。
   这一步不改任何东西，却把整份计划里最贵的一个歧义消掉。
1. 从 `repack/base-308065ef/boot-base-308065ef.img`（旧驱动、能稳定 boot）出发：
   取出内嵌 DTB，`fdtget /chosen bootargs` 拿到现串，`fdtput` 在末尾追加
   `msm_drm.dsi_display0=qcom,mdss_dsi_m81_36_02_0a_dualdsi_dsc_lcd_video:`，
   用 `tools/lib/build-bootimg.sh` 重新装配，`fdtget` 回读校验。
   **上机第一件事 `cat /proc/cmdline`**：串不在就说明这条路对 RAM 启动不可靠
   （§1.1 的 ABL 覆盖问题），直接跳到 P1 用 `CONFIG_CMDLINE_FORCE`。
2. 启动后（`telnet 192.168.7.2 2323`，可长时间停留）按顺序做三组观察：
   - **A 读状态**：`cat /sys/kernel/debug/nt36532/dcs` → `power/display/addr/pixfmt`；
     拍照记录屏幕（黑/灰闪/条纹）。
   - **B 验证 DCS 写是否真的生效**（这是目前最底层、也最没人验证过的一环）：
     ```sh
     echo "0xff 0x10" > /sys/kernel/debug/nt36532/dcs   # 切回 DCS 页
     echo "0x10"      > /sys/kernel/debug/nt36532/dcs   # sleep in
     ```
     立刻 `cat` 同节点看 power mode 是否变化；再 `echo "0x11"`（sleep out）、
     `echo "0x29"`（display on）各读一次。
   - **C 对照**：同一镜像不加模块串（= CSOT desc）再跑一遍 A/B。
3. 判据：

| 观察 | 结论 | 下一步 |
|---|---|---|
| sleep in / out 能改变 power mode | 命令通路有效，问题在码流/模式/init 内容 | P1（模式 + 扫描行 + PPS） |
| 无论发什么都停在 `0x9e` | 命令写没到 DDIC（分页、链路、或写被丢弃） | P1 先做"分页探测 + 双链路 poke"，这比 DSC 更底层 |
| 加/不加模块串读数不同 | desc（=init 序列/模式）确实影响面板状态 | P1 以天马 desc 为主线 |
| 加/不加完全相同 | desc 不是决定项，重点转向码流与时序 | P1 重心放 PPS/模式 |

这一步只改 cmdline，不动内核、不动驱动，可反复重跑来验证读数的稳定性。

### P1（CI 构建 #1，旧驱动诊断版）：把旧驱动变成完整的实验台

在 `liuqin-7.0` 上开一个**只用于诊断**的分支：`git revert 5fa8a9a`（恢复
`panel-novatek-nt36532.c` + Kconfig），保留 msm 侧 7.0 的全部修复与 `dsi_host`
诊断。不推送产品分支。然后一次构建带上下面的开关（每项一个提交）：

1. **desc 可见、可强制**：probe 打 `dev_info("desc=%s cmdline_match=%d")`，
   加 `desc=tm|csot|auto` module param（`auto` 不匹配时 warning 而不是静默）。
2. **天马时序改 120 Hz**（与厂商 on-command 内置的 120 Hz porch 组一致），
   并加 `mode=120|144` 参数，一个镜像里做 A/B。144 从此只作候选，不再当默认。
3. **扫描行读**：`dcs` 节点加一条读 `0x45` 的分支（或独立 `scanline` 节点），
   16 次采样给出 `first/last/advancing`——这是"面板到底有没有在扫我们的帧"的
   唯一直接判据，旧驱动现在缺这一项。
4. **PPS/DSC 日志**：prepare/enable 打印 `slice/slice_count/bpp/bpc/chunk` 与
   128 字节 PPS（旧驱动已有 `print_hex_dump`，只需补字段）。
5. **`pic_width` per-link 探针**：把 §2.3 的修复做成
   `msm.dsc_pic_width_per_link=1`（`dsi_host.c` 一行分支），同一镜像可 A/B。
6. **分页/双链路 poke**：`dcs` 节点支持带链路选择（现在固定 `dsi[1]`），
   便于验证"命令是否只到了从链路"。
7. 保留 `no_dsc`、`skip_panel_init`（已有，且 `enable()` 里的 PPS 已正确受
   `no_dsc` 约束）。

预期：一次上机能拿到 `desc=…`、`chunk=450`、`power=0x..`、
`scanline advancing=…`、`pps:` 字节，并且**不再有时间压力**。

### P2（旧驱动上迭代修复）：一次一个变量

按 P0/P1 的读数选一条路，每次都只在旧驱动上改、只上机一次：

- **PPS `pic_width`**：打开 P1-5 的参数 → 面板锁流/点亮？
- **模式**：`mode=120` vs `mode=144`；
- **init 内容**：现在能 poke 了，按 `0x9e` 是否变化，逐条定位到某个分页/命令
  （例如 `0xff 0x10` 之后的 `0x90/0x91/0xb3/0xb2/0x3b` 这组模式/porch 写）；
- **复位/供电**：CSOT 的 12/12/12/12 与厂商值不一致，可单独 A/B（本机是天马，
  只记录，不作结论）。

判据始终是 `0x45` 推进 + `0x0a` 变 `0x9d` + 有画面；不达预期立即回退该提交。

### P3（移植到新驱动 + 修 ~10 s 复位）：产品路径

- 把 P2 验证过的每一条差异**逐条**搬到 `panel-novatek-nt36523.c`（通常就是
  desc 里的一个值、prepare 里一个顺序），一条一个提交；
- 同时修新驱动自身的缺陷：probe 生命周期（N3/N4/N5）、desc 选型（N1）、
  以及 ~10 s 复位（N2，见 §4）；
- 这个阶段没有用户态窗口，取数靠 ramoops/pstore（附录 A）；
- 最后再考虑撤掉旧驱动、恢复 `CONFIG_DRM_PANEL_NOVATEK_NT36523`。

### P4（产品化）：清理

撤 `CONFIG_CMDLINE_FORCE`、删诊断节点与参数、CSOT 回归、刷新率切换、
suspend/resume、文档与配置入库（沿用 `display-driver-plan.md` P3/P4）。

## 4. 新驱动 ~10 s 复位（P3 阶段处理）

配置事实（`ci/…-3b7bf64/kernel/.config`）：`PANIC_TIMEOUT=0`、
`PANIC_ON_OOPS` 未开、`SOFTLOCKUP`/`HUNG_TASK` 未编译、DT 里没有 watchdog 节点
（`qcom-wdt`/`pm8916_wdt` 都是 `=m` 且无节点）。所以**内核不会自己重启**：
要么 panic 后外部看门狗动作，要么 hard hang，要么新供电/复位时序造成的
延迟硬件故障。三者在 pstore 日志里的指纹不同：

| 日志形态 | 判读 | 下一步 |
|---|---|---|
| 以 panic/oops 横幅结束 | 内核 panic（SMMU context fault、空指针、`BUG()`） | 按栈定位；先看 `nt36523_prepare/enable` 之后的第一处 |
| 在某一处**直接截断**，无任何横幅 | hard hang（关中断、等 DSI/时钟/硬件） | 读最后 3–5 行，对到源码位置 |
| 日志完整走到 init/udev，之后才复位 | 与显示路径无关（供电/看门狗时序） | 用 `skip_panel_init=1` 隔离面板路径 |
| 完全没有 ours 的输出 | 连 probe 都没到 | 先确认 pstore 是否真的在工作 |

排序假设（不预设结论）：① panic；② 关中断死等；③ 供电/复位时序；
④ 外部看门狗（只有 ①/② 成立时才谈得上）。

注意：`printk` 的每条都实时进 ramoops，所以"截断"是真实截断，不是没来得及刷盘。
取证步骤见附录 A；这条路只在 P3（新驱动）阶段用，因为旧驱动有用户态、不需要它。

---

## 5. 上机纪律（不变）

- 只用 `fastboot boot`，不写分区；电量 ≥50%；一条命令一个 serial。
- 每个实验记录：假设、改动、预期、实测、结论；失败记录不删。
- 一次 CI 构建带全部单元；一次上机改一个变量。
- 结论落盘到 `xiaomipad-6pro-mainline/docs/`，恢复/安装按已验证流程。

---

## 6. 文档修订清单（本次证据要求）

| 文件 | 需要改的内容 |
|---|---|
| 工作区 `AGENTS.md` §7.1/§7.2/§7.5 | 标注"当轮用的是天马还是 CSOT desc 无运行时证据（§1.1）"，结论降级为"desc 未验证" |
| `xiaomipad-6pro-mainline/AGENTS.md` §3.1/§4/§6 | 同上；"init 序列已排除"改为"静态一致，运行时 desc 与序列都未验证" |
| `docs/display-driver-plan.md` §3 事实表 | `0x9e` 一行加注"CSOT desc 下测得" |
| `docs/display-blackout-plan.md` §6.9/§11.4.1 | 补一条：desc 选型依赖 cmdline，而 RAM 启动可能拿到 ABL 串或我们的串；每次上机必须 `cat /proc/cmdline` 留证 |
| `display-drivers-archive/*/README.md` | 新驱动 README 的"暂停使用"原因改为"10 s 复位未查清 + desc 自检缺失"；旧驱动 README 标注"临时作为诊断平台" |
| 工作区 `AGENTS.md` §6 | 记一条决策：**诊断用旧驱动（revert 5fa8a9a 的诊断分支），产品仍用新驱动**；旧驱动不推送、不发布 |

---

## 7. 风险与开放问题

1. **旧驱动已从树上删除**：需要 `git revert 5fa8a9a` 的**诊断分支**，只在本地用，
   不推送、不发布；移植完成后再删掉。这是"先修旧驱动"这条路的唯一结构性代价。
2. **旧驱动的天马 desc 与厂商 init 不自洽（144 vs 120 Hz）**：P1 先把模式改成
   120 再下结论，否则会把"模式错"误判成"init 错"。
3. **诊断分支的 msm 侧是最新代码**（含 `f5e92f4` 之后的 CMD_DMA/CLKOUT/INTF
   改动）：它可能改变旧驱动的启动表现。P1 第一次上机先只验"能不能 boot +
   能不能读到 `dcs`"，不达标就先回退这些 msm 改动再做实验。
4. **只保留一轮**（pstore，P3 阶段）：`console-ramoops-0` 读的是上一轮的 `old_log`，
   本轮的 console 写在另一个环形缓冲里，所以读的时候不急；
   但产品系统**再重启一次**，`old_log` 就会被本轮内容覆盖。
   ⇒ 复位 → 正常启动 → 读，中间不要多启一次。
   若读到的是产品启动自己的日志，说明 oneshot 根本没写进 console zone
   （检查 `ramoops` 是否 probe、`PSTORE_CONSOLE` 是否真的注册）。
5. **冷/热复位**：ramoops 依赖 warm reset。若观察到复位后 DDR 内容丢失
   （pstore 完全没有上一轮记录），说明是 PMIC 级掉电复位，
   这条路要换成"内核自打印 + 屏幕不可见时改用 USB 早期 gadget"，成本高得多。
6. **压缩**：`PSTORE_COMPRESS=y`，从 `devmem` 直读 ramoops 得到的是 zlib 流；
   只把 `console-ramoops-0` 当主通道，直读只作兜底。
7. `mi,panel-id` 是否进入我们合并后的 DTB 未确认；不确定就用 `desc=` 参数，
   不阻塞主线。
8. CSOT 单元不在手边，所有改动对 CSOT 的影响只能靠代码审查 + 后续回归。

---

## 附录 A：ramoops/pstore 采集（P3 新驱动阶段用）

新驱动在能进 shell 之前就复位，所以这个阶段没有任何用户态窗口。唯一可行的
内核侧通道是 `ramoops`：`PSTORE_CONSOLE` 注册的是**实时 console**
（`fs/pstore/platform.c:394-424`，`CON_PRINTBUFFER|CON_ENABLED|CON_ANYTIME`），
每条 printk 同步写进 `ramoops@a7000000`（4 MiB，console zone 2 MiB）。
下一次启动时 `persistent_ram_post_init()` 把上一轮内容存进 `old_log`
（`ram_core.c:542-561`），`console-ramoops-0` 读到的就是**上一轮**的日志。
`sm8475-xiaomi-liuqin.dts:238-246` 的注释写明 zone 尺寸刻意与厂商固件一致，
这条通道本来就是为失败启动准备的。

步骤（零构建、零交互）：

1. `fastboot boot` 目标镜像；
2. **不要碰设备**，等它自己复位；
3. 让设备正常启动一个不死的系统（已装的 `308065ef` 产品镜像）；
4. 进 shell 后读，不要多启一轮（`old_log` 只保留一轮）：

```sh
ls -l /sys/fs/pstore/
cat /proc/cmdline > /tmp/product-cmdline.txt
cat /sys/fs/pstore/console-ramoops-0 > /tmp/crash.txt
for f in /sys/fs/pstore/dmesg-ramoops-*; do cat "$f" >> /tmp/crash.txt; done 2>/dev/null
grep -m1 'Kernel command line' /tmp/crash.txt
```

5. 在日志里依次找：`Kernel command line`（desc 定案）、`dsc: … chunk`、
`pps:` 字节、`desc=…`、最后一行（崩溃点）。判读表见 §4。

兜底：`console-ramoops-0` 为空时，先确认这次是 warm reset；仍无内容就
`devmem 0xa7000000` 直读 4 MiB 找 `Kernel command line`（压缩开启时是 zlib 流），
或回原厂 Android 读同一地址（zone 已对齐）。
