# liuqin 天马面板：全量问题清单与打勾排除法

> 目的：把"黑屏有背光"拆成**可以逐条判真伪的问题**，一条一次打勾，不跳层。
> 依据：`xiaomipad-6pro-mainline/out/vendor-display/`（原厂 V14 快照，root）、
> `display-drivers-archive/` 两份驱动、`docs/display-driver-plan.md`、
> 以及本次复核（2026-10-28）的结论。
> 新事实：**liuqin-6.17 的 boot.img 在本机同样黑屏 + 背光**，所以"6.17 能亮"
> 这条前提作废，唯一可信的"能亮"配置只剩原厂 ABL + MIUI 内核。

---

## 0. 怎么用这份清单

**证据来源分级（2026-10-28 用户更正）**：

| 等级 | 来源 | 可当什么 |
|---|---|---|
| A 真值 | 本机原厂运行态（`out/vendor-display`、本次实采寄存器/`dump_info`）、原厂 DTBO、本机 dmesg | 可直接下结论 |
| B 参考 | `caf-display/`（**社区实现，不是本机厂商驱动**）、主线代码、上游 6.17 | 只能提出假设，必须由 A 级证据或实测确认 |
| C 叙述 | 文档里转述、找不到原始文件的值 | 引用前必须重采 |

**当前计数（2026-10-29 收尾）**：140 条 —— **⛔ 117 / ⚠️ 11 / ⬜ 4 / 📌 7 / ❌ 1**。
**最后两个有据假设（E19 非连续时钟、I20 PPS 顺序）均已实测排除，软件侧走完。**

**已关闭的关键项（按轮次累计）**：F11 广播缺陷；J01/J02 60 Hz 真值；A04/M05
desc 与命令行；I01/I02 init 与分页；F06/O01 命令通路；I06/R4 `0x9e` 判据作废；
F01/F02/F03/F09/G03/E01/F10 DSI 控制器层逐值一致；I14/K04 DPU 出帧与绑定；H01/H04
PPS 字节规范；H02 PPS A/B 无差别；E07 PHY 比对；I15/行为三图无变化。
**当前唯一未知**：I16（面板是否检测到有效信号，DCS `0x0e`）与 I17（多发的 `0x9b`）。

**已知错误改动与误判**：见 `known-wrong-changes.md`。每次动代码/实验设计前，
先过一遍那份文档 §4 的 8 条自检。

**状态词**（只认这四种，别写"应该没问题"）：

| 记号 | 含义 | 要求 |
|---|---|---|
| ⛔ | 已排除 | 必须有一句可复现的观测（寄存器值/日志/现象） |
| ⚠️ | 可疑或证据不足 | 有间接证据但不能定案，或静态对但运行时未验 |
| ⬜ | 未测 | 没做过，或做过但方法无效 |
| ❓ | 本机无法测 | 缺硬件/缺手段，需要换思路 |
| 📌 | 事实 / 背景记录 | 不是待办，只是"已确认的事实"或"技术债"，留档用 |

**纪律**（不遵守的话清单会退化成玄学）：

1. 一条 = 一个变量 = 一次上机；不达预期立刻回退。
2. "静态一致"（DT/字节比对）只记 ⚠️，不记 ⛔；⛔ 必须是运行时观测。
3. 每排除一条，写清"用哪个观测排除的"，写在本文表格的"现状"列里。
4. 同一层没打完勾，不进下一层；但允许先打"信息量最大"的那几条（见 §3）。

---

## 0.5 当前进度（每确定一项就在这里落一行）

| 步 | 目标条目 | 手段 | 状态 | 证据位置 |
|---|---|---|---|---|
| 0 | F11（CMD_DMA 广播位） | 原厂两条链路对照 → 改默认值 | ✅ 已修并实测 | §8 第一/五轮 |
| 1 | J01 / J02（60 Hz 真值） | 原厂边滑动边抓 | ✅ `TOTAL=186301bf` 命中 | §8 第三/四轮 |
| 1.5 | 基线与 HEAD 源码差异 | `git diff 308065ef..HEAD` | ✅ 5 文件，DPU 预取已回退 | `docs/diff-308065ef-vs-head.md` |
| 2 | A04 / M05 / I01 / I02 / F06 / O01 | 进 shell 后看日志 + poke | ✅ 全部关闭 | §8 第五/六轮 |
| 3 | I06 / R4（`0x9e` 判据） | 切页后发真 DCS `0x38` | ✅ 判据作废 | §8 第六轮 |
| 4 | DSI 控制器层（F01/F02/F03/F09/G03/E01/F10/J02） | 60 Hz 下与原厂逐值比 | ✅ 逐值一致 | §8 第七轮 |
| 5 | I14 / K04（DPU 出帧与绑定） | `intf_2` 帧计数 + PP/DSC mux | ✅ 60 fps、绑定自洽 | §8 第八/十三轮 |
| 6 | H01 / H04 / H02（PPS 字节） | `PPS-pre:` 打印 + 离线解码 + A/B | ✅ 规范 DSC 1.1；A/B 无差别 | §8 第十一/十七轮 |
| 7 | E07（PHY） | `/dev/mem` 读 0xae94400 与原厂比 | ✅ 20/23 相同，差异为实例相关 | §8 第十五/十六轮 |
| 8 | I15 / I17（面板侧命令） | 三张行为图（DSC/900/无 DSC） | ✅ 全部无变化；`13/53/55/51` poke 亦无效 | §8 第十七轮 |
| 9 | I16 / I17（`0x0e` 信号模式、`no_9b`） | 构建 `eec78a8c` → 两张图 | ✅ 已测：`signal=0x80`、`status=0x00`；`no_dsc` 亦然 | §8 第十八/十九轮 |
| 10 | I18（是否在 HS 发数据） | 连续采样 `LANE_STATUS` | ✅ 在发：`1f00`(HS) ↔ `1f1f`(LP) | §8 第二十轮前 |
| 11 | B04（面板偏压） | `regulator_summary` | ✅ 已排除：VSP/VSN 5.5V enabled | §8 第二十轮 |
| 12 | 状态机命令（`0x13`/`0x11`/`0x29`） | poke 后读 `0x0a` | ✅ 无效，`power` 恒 `0x9e` | §8 第二十轮 |
| 13 | 停止线 | 见 §0.7 | ⏸ 2026-10-28 触发 | — |
| 14 | skill 六条成因逐项核对 | `experience/display.md` 黑屏条目 | ✅ 五条排除，只剩"非连续时钟" | §8 第十三轮 |
| 15 | **I20** PPS 顺序（对齐上游同型号驱动） | `pps_in_init=1 no_9b=1` | ✅ 生效但**无变化** | §8 收尾 |
| 16 | **E19** 非连续时钟 | `cont_clock=1`（`mode_flags=0x403`） | ✅ 生效但**无变化** | §8 收尾 |
| 17 | 软件侧收尾 | 全部有据假设已测 | ⛔ **走完**：只剩抓线 / 第二台设备 | 见下 |

### 现状与结论（软件侧已走完，2026-10-29 收尾）

> **2026-10-29 晚：天马面板已在 6.17 上点亮（§8 第二十七轮）。**
> 下面这一节的"走完"只对 **7.0 移植**成立；同一张 DTB、同一块面板，在
> `liuqin-6.17-tianma` 上 DRM 起来后画面正常。⇒ 面板/DDIC/时序/init 全部无罪，
> **问题在 7.0 这条移植线的显示代码里**。注意：7.0 在 DRM 起来时的
> `DSI0 CTRL` 也是 `0x1f3`（§7 第 309/622 行），与 6.17 相同；
> 之前记的 `0x1f7` 是 **Z 实验（msm 被黑名单、DSI 停在 ABL 残留状态）** 的读数，
> 不能当作 7.0 的差异。7.0 与 6.17 的差异仍待逐值 diff。

**能证明"对"的层**（都有运行时观测，不是静态比对）：

| 层 | 观测 |
|---|---|
| DSI 控制器（0x00–0x3fc） | 60 Hz 下与原厂逐值一致（`TOTAL=186301bf` 命中） |
| DSI PHY lane timing | 14 个值与原厂完全一致；PHY 23 个字里 20 个相同，余 3 为实例相关 |
| DPU 出帧与路由 | `intf_2` 帧计数 121 帧/2 s；INTF↔PP↔DSC 的 mux 两侧一致 |
| DSC 编码器 | 与 PPS 逐值吻合；两个 DSC 配置相同 |
| PPS 128 字节 | 规范 DSC 1.1；pic/slice/chunk/RC 全表正确 |
| 面板 init 216 包 | 与 DTBO 字节相同；无失败日志 |
| 面板供电/背光 | VSP/VSN 5.5 V enabled、DVDD enabled、背光已亮 |
| 命令通路 | 读写均有效（`0x10`→`0x0e`、`0x11`→`0x9e`） |
| HS 链路 | `LANE_STATUS` 在 `1f00`(HS)/`1f1f`(LP) 间切换，确实在发 |

**未解的核心事实**：面板始终报 `power=0x9e`（厂商 DT 声明正常应为 `0x9d`）、
`signal=0x80`、`display=0x00`，状态机命令（`0x13`/`0x11`/`0x29`/`0x38`）均无效，
画面全黑但背光亮。**注意：黑屏发生在"我们接管"的那一刻，不是交接时**——
开机时屏幕能正常显示内核日志，见 §8 第二十五轮。

**最后两个有据假设也已排除**（2026-10-29）：
- **I20** 把 PPS 移到 init 内、`display_on` 之前（与上游 `panel-novatek-nt36532.c` 完全一致的顺序），
  参数生效（`PPS-pre` 计数 0）但画面无变化；
- **E19** 连续时钟（`cont_clock=1`，`mode_flags=0x403`，`CLOCK_NON_CONTINUOUS` 位已清），同样无变化。

⇒ **软件侧所有"有据可依"的假设均已测完并排除**。只剩两条，且都需要外部手段：
1. 面板 DDIC 内部状态机/解码（寄存器读不到更深原因）；
2. HS 电气层（眼图/终端匹配，寄存器反映不了）。

## 0.7 恢复实验的前提（硬性）

在下列**任一**条件满足之前，不再做任何内核侧参数/寄存器实验，也不再为显示问题构建：

1. ~~拿到原厂系统健康态的 `0x0a`/`0x0e` 读数~~ —— **已尝试并关闭**：
   原厂 `dri/0/DSI-1/rx_cmd` 写入不报错但**不产生任何输出**（开了
   `file *dsi_display* +p` 也没有），`cat` 该节点始终 `EINVAL`
   （video 模式面板上这条读路径不可用）。间接替代：原厂 DT 的
   `panel-status-value = <0x9d>` 被 MIUI 的 ESD 检查（`mi_dsi_panel_esd_irq_ctrl_locked`
   在亮/灭屏时都会被启用）用作判据，若面板常态不是 `0x9d`，原厂应持续报 ESD
   异常并做恢复；原厂工作正常 ⇒ **`0x9d` 就是健康态**，我们的 `0x9e` 确实异常。
   实测佐证（2026-10-28 原厂侧）：`mi_esd_err_irq_handle` / `_sde_connector_report_panel_dead`
   只在**亮屏恢复的瞬间**报过一次 `esd check failed`（随后 `ESD recovery already pending`，
   属于恢复过程中的瞬态），稳态显示期间没有任何 ESD 报错 ⇒ 健康态确为 `0x9d`。
   该替代只验证了 `0x0a`，**`0x0e` 的位语义仍未验证**；
2. 有**逻辑分析仪/示波器**能抓 DSI HS 线，确认我们发出的视频包在物理层是否有效；
3. 出现**新的、独立的证据**（例如另一台同型号设备上同样镜像的表现、或厂商侧新的可读数据源）。

> 2026-10-29 补充：由 skill 经验库和上游同型号驱动引出的两条假设（I20 PPS 顺序、
> E19 非连续时钟）**已经测过并排除**，不要把它们当作恢复实验的理由重复尝试。
> 恢复实验的**唯一**正当理由是上面三条之一。
>
> 2026-10-29 追加（离线，见 §8 第二十三轮）：已从 `uefi.elf` 解出引导程序自己的
> 面板 XML，本机面板 `M81 36 02 0a` 的 init 序列与 DTBO 的 216 包 **99.3% 相同**，
> 只差 `D1 20/28` 与一条 `0F 20`。这份 XML 同时给出了 skew=-2、PHY DCDC、
> `PicWidthSlice=2` 等"工作配置"。它够格当条件 3 的**证据源**，但只支持
> "针对这两条差异做一次定向 A/B"，不支持重开参数试错。

## 0.8 手段 2 / 3 的具体做法

### 手段 2：抓 DSI HS 线（仪器）

**抓哪里**：SoC 到面板的 DSI 差分对——CLKP/N、D0P/N…D3P/N。实际落点通常是主板上显示
BTB 连接器的焊盘/测试点，或 FPC 上的测试点。**只需要抓一条数据 lane + 时钟 lane** 就够判读。

**用什么**：带宽 ≥1 GHz 的示波器 + 差分探头（有源差分最佳）；若要做协议解码，需要带
DSI 解码的示波器或专用分析仪。**最低配**：只要能看到时钟 lane 的方波与一条数据 lane 的
HS 突发即可。

**看什么**（按信息量排序）：

1. 时钟 lane 有没有 1.007 Gbit/s 的差分方波（周期 ~0.99 ns）→ PHY 是否真的在按对的速率发；
2. 数据 lane 在 active 区有没有 HS 突发、幅度是否正常（差分 ~200 mV）、有没有 SoT/EoT；
3. 突发里的包头（data type + WC）：**WC 应该约 900**（我们 DSI 配的就是 1 包/行、900 字节）；
4. 若能看到包头但内容错乱 → 载荷/编码问题；若根本没有突发 → DSI 视频通路没启动。

**代价/风险**：需要拆机或在 FPC 上飞线，细间距、易损；**先确认有测试点再动手**。

### 手段 3：新的独立证据（不需要仪器）

按"成本从低到高"排列：

| 证据 | 怎么做 | 能回答什么 |
|---|---|---|
| **A. 原厂 `reg_dump` / `evtlog_dump`** | 原厂系统**亮屏状态**下 `cat /sys/kernel/debug/dri/0/reg_dump`（必要时配 `reg_dump_blk_mask`），以及 `evtlog_dump` | 我们唯一没拿到的对照：原厂 DPU 的 **CTL/INTF** 值（K02/K04 一直是"原厂拿不到"）。`evtlog_dump` 里 CAF 的 `SDE_EVT32` 可能带 DSC/编码器参数 |
| **B. 面板/DDIC 身份** | 我们内核里读 DCS `0x04`（display id）、`0xDA`/`0xA1`（厂商/版本）——需要给 `dcs` 节点再加两行（小构建） | 排除"这块面板其实是另一个 DDIC 变体"（P01/P03）：若 ID 与 `m81_36_02_0a` 不符，init/PPS 的前提就错了 |
| **C. 面板自检图案** | 用 poke 试 Novatek 厂商页里的 test pattern / BIST 寄存器（从 DTBO init 里找可用的寄存器对） | 面板能否在不依赖我们码流的情况下显示内容——若能，说明 DSI 接收通路有问题；若不能，说明面板侧状态机没打开 |
| **D. 第二台同型号设备** | 同一张镜像 boot 上去 | 区分"驱动问题"与"这台设备/这块面板的个体差异"（P04）；这是最有说服力也最贵的一条 |
| **E. ABL/LK 的显示路径** | bootloader 能在本机点亮面板（splash），它的初始化序列/porch 是**独立可工作的实现**；若能取到 ABL 的显示日志或其 LK 源码 | 提供一份"在这块硬件上确实能亮"的参照，和我们对比 |

推荐顺序：**A → B → C**（都不需要拆机），再考虑 D/E。

### 0.8.1 第二台同型号设备：怎么用

**目的**：把"我们的驱动/码流有问题"与"这台机器的面板/排线/批次不同"分开。

**前置（必须先确认，否则对照无效）**：第二台机器的**面板型号必须相同**——
在原厂系统上看 `/proc/cmdline` 里的
`msm_drm.dsi_display0=qcom,mdss_dsi_<面板名>`（本机是 `m81_36_02_0a`，天马；
若是 `m81_42_02_0b` 就是 CSOT，两组不能混着比）。

**步骤**：同一张镜像（`sha256` 必须一致）`fastboot boot` 上去，只记四样：

1. 启动文字→灰→黑的时点是否与第一台一致；
2. `cat /sys/kernel/debug/nt36532/dcs | head -2`（`power` / `signal`）；
3. `dmesg | grep 'panel desc'`（确认也是 `tianma`）；
4. 屏幕有没有任何画面。

**判读**：

| 第二台 | 结论 | 意义 |
|---|---|---|
| 也全黑，`0x9e`/`0x80` | **软件问题** | 与个体无关，必须继续在驱动/码流里找（或上仪器） |
| **能亮** | **这台机器的个体差异**（面板批次、DDIC 固件、排线/连接器） | 软件路径其实是通的；转查两台的面板 ID（DCS `0x04`/`0xDA`）、`dtbo_idx`、硬件版本 |
| 能进 shell 但 `power` 值不同 | 面板状态机行为不同 | 同上，先比面板身份再比行为 |

**成本**：只需借到一台同型号机器，不需要仪器，也不需要构建。

### 0.8.2 逻辑分析仪抓 4 条 lane：怎么用

**目的**：确认线上到底有没有"结构正确、长度正确、内容非零"的 MIPI DSI 视频包。

**抓哪里**：CLKP/N、D0P/N、D1P/N、D2P/N（D3 可选）。落点是主板显示 BTB 连接器的焊盘、
FPC 上的测试点，或飞线到耦合电容靠 SoC 一侧。

**需要什么**：

| 目标 | 最低配置 |
|---|---|
| 只看时钟频率 + 包头 WC | 2 通道差分，**≥1.5 GHz** 带宽（bit clock 1.007 Gbit/s，UI≈0.99 ns） |
| 完整解码一行视频包 | 带 DSI 解码的示波器/协议分析仪（或 ≥4 GHz 采样 + 软件解码） |
| 普通 24 MHz USB 逻辑分析仪 | **完全不够**，不要买 |

**看四件事（按信息量排序）**：

1. **时钟频率**：CLK 差分方波周期应为 ≈0.99 ns（1.007 Gbit/s）。不是这个值 ⇒ PHY 分频错；
2. **HS 突发是否存在**：每行一次 LP-11 → HS-0 → SoT(0xB8) → 数据 → EoT；
3. **包头 WC**：视频模式包的 `WC` 应该是 **900**（`0x0384`，对应 1 包/行、900 字节）；
4. **载荷内容**：900 字节是否像 DSC 数据（有结构、非全零）。

**判读**：

| 线上看到 | 结论 | 下一步 |
|---|---|---|
| 完全没有 HS 突发 | 视频通路没启动（与我们 `LANE_STATUS` 的观测矛盾，需复核抓点） | 查 DSI video engine / INTF 使能 |
| 有突发但 `WC` ≠ 900 | 打包配置错 | 查 `DSC_MODE_CTRL` 与包化 |
| 结构对、载荷全零 | DPU 没在喂数据 | 查 PP/DSC 取数（内容路径） |
| 结构对、载荷非零 | 我们发的东西是对的 | 问题在**面板/DDIC 接受度**或电气（眼图/终端） |

**成本/风险**：需要拆机或飞线，1 GHz 差分探测对连接器有损伤风险，探头负载也可能影响链路；
**建议先确认有测试点，再动手**。


恢复后要做的第一件事：把上面三条里的新数据填进 §8，再按它与现状的差异决定下一步，
**不要重新开始"猜参数"**。所有历史结论见 §8 各轮记录与 `known-wrong-changes.md`。

## 1. 结构性前提（这几条不解决，后面所有"排除"都会被打回）

| 编号 | 问题 | 为什么致命 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| A01 | 没有可信的"能亮"基线 | 6.17 boot.img 在本机也黑 ⇒ 所有"移植自 6.17/上游"的配置都只是假设 | 无：事实 | 📌 事实 |
| A02 | 唯一可信的"能亮"是原厂 ABL + MIUI | splash 与系统画面都正常 | 开机看 splash | ⛔ 已知 |
| A03 | 对照基准 | 模式不同则寄存器不可比 | **已定为 60 Hz**（用户选择）：原厂 60 Hz 真值已抓，我们的目标 mode 也按 60 写，两侧同模式可直接逐字节比 | ⛔（基准已定） |
| A04 | 实际跑的是哪个 desc | 选错就会用另一块屏的 init | **已确认**：`panel desc: tianma … cmdline_match=1`（镜像 A，`702b079d`） | ⛔ |
| A05 | 新驱动没有用户态窗口（进 shell 前复位） | 面板状态类判据全部拿不到 | 改用旧驱动做实验台，或内核自打印→pstore | 📌 事实（属 N06） |
| A06 | `0x0a` 的 bit0/bit1 语义 | 曾被当成"booster 没开" | **判据作废**：切页后真 DCS `0x38` 也清不掉 bit1，仅 bit4 随睡眠变化；不再用作判据 | ⛔（判据作废） |
| A07 | "init 序列逐字节一致"≠"运行时真的送达并被接受" | 静态比对通过却从未验证运行时 | 内核日志 + poke 有效性测试 | ⚠️ 无法判定（DDIC 内部） |
| A08 | 上游作者 CSOT 成功不可复现、也无日志 | 任何"上游能亮所以代码对"的推理失效 | 无 | 📌 事实 |

---

## 2. 分类问题清单

### B. 供电与上电时序（8）

| 编号 | 可能的问题 | 与黑屏的因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| B01 | vddio 1.8 V 未上/偏低 | DDIC 数字域不工作，命令会失败 | 读 `regulator_summary`；面板能回 DCS 即已工作 | ⛔（DCS 有响应） |
| B02 | dvddbuck/dvddldo 1.3 V 未上 | 同上 | 同上 | ⛔ |
| B03 | 三路供电的**顺序与间隔**不符合 DDIC 要求 | 上电顺序错会导致内部状态机锁死（黑屏但能应答） | 对照原厂 DT 的 `panel-supply-entries` 顺序与延时；在 prepare 里逐路上电并打印时间 | ⛔ 功能可用（裕量未量化） |
| B04 | VSP/VSN（±5.5 V 面板偏压）的归属与使能 | 没有偏压 → 面板既不显示也不报"有信号" | **已排除**：`backlight_gpio_vsp`/`vsn` 均 `enabled`、5500mV；`display_panel_dvdd_buck`/`ldo` 也 enabled。ktz8866 已使能 `enable-lcd-bias`（写 `0x09=0x9F`） | ⛔（电源层无问题） |
| B05 | bulk enable 的先后顺序 | 同 B03 | 读两份驱动的 `pipa_supply_names[]` 顺序，与 DT 顺序比 | ⛔ 功能可用 |
| B06 | 供电电流不足/load switch 压降 | 面板上电瞬间掉压 | 万用表/示波器（需要拆机条件） | ⚠️ 需仪器 |
| B07 | 从未逐条记录实际电压 | 无法证明供电正常 | 原厂实测：pm8350c_l2=1800 mV、dvdd_buck=1300、dvdd_ldo=1300、vsp=5500、vsn=5500，全部 use=1 | ⛔ |
| B08 | 上电到复位、复位到首包的等待不够 | DDIC 还没准备好就发命令 | 与原厂 prepare 的 sleep 序列逐项比；加长验证 | ⛔ 功能可用 |

### C. 复位与 GPIO（6）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| C01 | reset GPIO 极性反了（nRESET 被一直拉住） | init 全部"成功"但面板不工作 | 抓 GPIO 电平（`gpio` debugfs 或万用表）；对比 <0 10 1 3 0 3 1 15> 的末态 | ⛔ 已排除（命令可达） |
| C02 | 复位脉宽/间隔不对 | 复位不彻底 | 逐项对比 DTBO 与 `pipa_reset()` | ⛔ 已排除（厂商值+可达） |
| C03 | 复位释放到第一条 DCS 的间隔 | DDIC 未就绪 | 加日志时间戳 | ⛔ 功能可用 |
| C04 | 复位期间链路不在 LP-11 | DDIC 采不到唤醒 | 读 `LANE_STATUS`（原厂 00001f1f） | ⚠️ 需抓线 |
| C05 | reset-gpios 与 `sde_dsi_active` pinctrl 冲突 | GPIO 被别的功能占用 | 查 pinctrl 定义与 gpio 0 的复用 | ⛔ 已排除 |
| C06 | 双链路只需一个复位（原厂如此） | — | 已一致 | ⛔ |

### D. 背光（4）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| D01 | 把"背光亮"当成"面板在工作" | 背光是独立 IC（ktz8866），与面板是否解码无关 | 已区分 | ⛔ |
| D02 | 背光电压/电流异常 | 只是亮度问题，不会全黑 | 读 ktz8866 寄存器（0x09=0x9f） | ⛔ |
| D03 | 背光早于/晚于面板使能 | 短暂闪白/闪黑，不是常黑 | 抓 enable 时间线 | ⛔ 已排除（背光已亮） |
| D04 | 亮度寄存器为 0（0x51） | 背光 IC 亮但面板内部调光为 0 | 读 init 里的 `0x51 0x0f 0xff` 与当前值 | ⛔ 已排除（0x51=0FFF 且重发无效） |

### E. DSI 物理层（10）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| E01 | lane 数/占用不对 | 数据缺失 | `ACTIVE_H/V`、`LANE_CTRL=01000000` 与原厂一致 | ⛔（同模式实测） |
| E02 | lane 极性/顺序（p/n 反、lane swap） | 链路起不来或误码 | 逐 lane 交换实验；读 error 计数 | ⛔ 已排除（LP 命令可达） |
| E03 | PLL/bit clock 频率 | 若不同会改变 LP/HS 裕量 | **实测一致**：原厂 `clk_summary` 里 `disp_cc_mdss_pclk0_clk=167838720`、`byte0_clk=125879040` → bitclk=1,007,032,320；与我方 120 fps 模式按 `dsi_get_pclk_rate()` 算出的三项逐位相同。另 `dsi1_phy_pll_out_*` 的 enable count=0，双链路确实共用 dsi0 的 PLL | ⛔（运行时实测） |
| E04 | PHY 14 项 timing 与原厂差 5 项 | 同上 | `msm.vendor_phy_timing=1` 已试，无变化 | ⛔（试过，不改变现象） |
| E05 | clock lane 连续/LP 策略 | 原厂不 force HS | 已试 `CLOCK_NON_CONTINUOUS`，无变化 | ⛔ |
| E06 | EOT 包（`rx-eot-ignore`/`tx-eot-append`） | 原厂置了这两个；不影响解码但影响错误检测 | 对照 `CTRL`/`VID_CFG0` 的 EOT 位 | ⛔ 已排除（status=0 无协议错误） |
| E19 | DSC 视频模式面板用了非连续时钟导致失锁（skill 经验库点名） | 时钟在 BLLP 停振 → 面板 PLL 失锁 → 全黑但寄存器全对 | **已 A/B，无效果**：`cont_clock=1` 生效（`diag: cont_clock=1 (mode_flags=0x403)`，NON_CONTINUOUS 位已清），面板仍 `power=0x9e`、`signal=0x80`、屏幕全黑 ⇒ 时钟策略不是原因（与上游同样使用非连续时钟吻合） | ⛔（已排除） |
| E07 | 驱动强度/预加重/PHY 配置 | HS 数据电平/时序不对 → 面板锁不上而命令仍可通 | **已比对并定性**：dsi0 PHY 23 个寄存器 20 个与原厂一致；差异只在 0x10/0x14/0x20。但**我们自己的 dsi0 与 dsi1 也不同**（0x61/0x30 vs 0xF1/0x34），说明这三处属"实例/PLL 相关"状态，不能拿原厂 dsi0 的值当正确答案。**寄存器层面到此穷尽** | ⛔（已穷尽，非可行方向） |
| E08 | PHY 0.9 V 供电 | 完全无链路 | 能通信即排除 | ⛔ |
| E09 | ULPS 误入 | 链路休眠 | 原厂 ULPS=N；主线未启用 | ⛔ |
| E10 | dsi1 的 PLL 父时钟 | 双链路不同步 | **与原厂一致**：原厂 `dsi1_phy_pll_out_*` enable=0（共用 dsi0 PLL），我们同样配置，且 dsi1 上命令可达 | ⛔ |

### F. DSI 协议/控制器（10）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| F01 | video/cmd mode 选错 | 全黑 | **同模式逐值一致**：60 Hz 下 `CTRL=000001f3`、`VID_CFG0=02009230`，与原厂完全相同 | ⛔（同模式实测） |
| F02 | burst vs 非 burst | 打包方式不同 | `VID_CFG0=02009230` 与原厂一致 | ⛔（同模式实测） |
| F03 | BLLP power/EOF 模式 | 低功耗间隙行为不同 | 已含在 `VID_CFG0`，与原厂一致 | ⛔（同模式实测） |
| F04 | bonded 双链路同步（master/slave/sync/broadcast） | 两半不同步 → 无画面 | 原厂还有 `cmd-sync-wait-broadcast`；主线靠 `msm_dsi_manager_cmd_xfer` 双 commit | ⛔ 已排除（双链路均在发） |
| F05 | 另一条链路的 DDIC 是否也收到命令 | 只有一路被初始化 → 黑/半屏 | 写经 dsi[1] 生效 ⇒ 至少一条链路正常；另一路是否也需要由 C 图（`msm.dsi_cmd_broadcast=1`）对照。原厂两条链路只有 `CMD_DMA_CTRL` 差 master 位 | ⚠️ 无法区分（需广播对照） |
| F06 | 命令固定走 dsi[1] | 若主链路才是 DDIC，命令发不出去 | **已排除**：poke `0x10`/`0x11` 改变了面板 power 状态，说明经 dsi[1] 的写入确实到达 DDIC | ⛔ |
| F07 | 视频流期间命令的 BLLP 窗口不足 | 长命令被丢弃 | **已排除**：多次 poke（含 1 字节参数的 `0xff`）全部成功 | ⛔ |
| F08 | virtual channel/stream 不一致 | 收不到 | DT 与原厂都是 0/0 | ⛔ |
| F09 | ACTIVE_H（压缩后） | 有效区错 | `015c0030` 与原厂一致 | ⛔（同模式实测） |
| F10 | DSI 错误状态被忽略 | 误码/超时无感 | `STATUS0` 只差 bit13（主线 XML 未定义，疑厂商位）；`FIFO`/`LANE_STATUS` 的差异是采样时刻的 FIFO 空/停态位 | ⛔（可解释） |
| F11 | **`CMD_DMA_CTRL` 在两条链路上都写了 vendor 的 master 值** | 两条都置 broadcast+master，与主线"双 DMA 双 trigger"互斥 → 命令重复/交错 | **已修**（`cec2a7b5`，默认回上游 `0x14000000`）；镜像实测 `CMD_DMA_CTRL=14000000`。对画面是否有效仍未判定（不是这个缺陷的判断范围） | ⛔（缺陷关闭，值已验证） |

### G. DPU 侧 DSC 编码（8）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| G01 | DSC 使能/配置顺序（PPS→compression→EN） | 编码器与面板不同步 | 抓 DPU/DSI 侧寄存器写入顺序 | ⛔ 已排除（顺序同 DTBO） |
| G02 | slice_count/width/height 与 DPU 不匹配 | 编码 slice 错 | **已核对**：`dsc_0_enc` 的 SLICE=450×20、chunk=450，与 DSI 的 `DSC_CTRL=03840b01` 一致 | ⛔ |
| G03 | chunk / pkt_per_line | 打包错 | `DSC_CTRL=03840b01` 与原厂一致（WC=900、1 包/行） | ⛔（同模式实测） |
| G04 | bpp/bpc/block-pred | 解码错 | DT 与原厂一致 | ⛔ |
| G05 | DSC 版本/SCR | 解码器拒绝 | 1.1/0，原厂同 | ⛔ |
| G06 | 每 encoder 的 DSC 实例数（2 LM/2 DSC） | 拓扑错 | 逐块读 CTL/PP 绑定 | ⛔ 已排除（两 DSC 均配置） |
| G07 | DPU 的 pic_width 是整幅还是每链路 | 编码端错 | **DPU 侧自洽**：`dsc_0_top=00000101`（EN+SPLIT_PANEL）、`dsc_0_enc` PICTURE=1800×2880；`dpu_encoder_prep_dsc()` 就是按整幅 1800 写、由 SPLIT_PANEL 分半。面板侧的问题归 H02 | ⛔（DPU 侧） |
| G08 | DSC 输出与 DSI packetizer 的 slice 排布 | 数据错位 | 需要 PPS/寄存器双侧证据 | ⚠️ 需抓线 |

### H. PPS 与面板侧解码（10）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| H01 | 我们发出的 128 字节 PPS 与厂商是否一致 | 面板按错参数解码 → 黑 | PPS 已加十六进制打印（`bf394ce5` 的 `PPS-pre:`）。**注意：厂商 PPS 从未采到，而且基本拿不到**——原厂开 `file *dsi_panel* +p` 等动态调试后，`dsi_panel_tx_cmd_set` 的 packet-count 与 PPS 都没有打印（2026-10-28 实采）；`caf-display` 只能给出"参考实现会发什么"（B 级），不能当厂商真值 | ⛔ 降级关闭（厂商 PPS 不可得，A/B 无差别） |
| H02 | `pic_width` 写成 1800（每链路只送 2×450） | 解码端算出 4 slice/行 | **已结案（上游实证）**：正在上游化的 `panel-novatek-nt36532.c`（OnePlus Pad 2，同为 NT36532 双 DSC）用 `slice_count=2`、`slice_width=750`、`pic_width` 不填、由 msm 用 `mode->hdisplay` 填**整幅**（3000）——与我们的 1800/450/2 完全同构。整幅就是对的，A/B 也无差别 | ⛔ |
| H03 | `slice_chunk_size` 为 0 或不是 450 | 包长错 | 内核打印 `chunk`；寄存器 WC=900 已证 | ⛔ |
| H04 | RC 字段（initial_dec_delay/scale/bpg/offsets）与原厂不同 | 解码率控错，画面乱或黑 | 只能用 `caf-display` 做**参考**复算（B 级），得不到厂商真值；最终判据只能是"面板是否出画面" | ⚠️ 不可验证 |
| H05 | PPS 发送时机（init 之后、视频流之前） | 面板未准备好 | 与原厂 ON→PPS 顺序对照 | ⛔（顺序同） |
| H06 | PPS 只发一条链路 | 另一路 DDIC 无参数 | 见 F05 | ⚠️ 同 F05 |
| H07 | 多发了一条 DCS `0x9b`（compression enable），原厂无 | 可能被当成厂商分页命令 | 做成参数 A/B | ⬜ 暂停（见 §0.7） |
| H08 | `pps_id`/PPS1 字节 | 多 PPS 场景用错 | CAF 也写 0 | ⛔ |
| H09 | 分页状态下 `0x9b` 的语义 | 同上 | 先 page 0x10 再发 | ⬜ 暂停 |
| H10 | PPS 应在 display-on 之前/之后 | 时序 | 原厂：ON 内含 0x29，之后 PPS；我们相同 | ⛔ |

### I. 面板 init / DDIC 状态机（12）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| I01 | 216 包 init 是否真的发出 | 没发 = 面板停在 bootloader 状态 | **已确认发出且成功**：`prepare()` 无失败日志，且随后的 poke 写能改变面板状态 | ⛔ |
| I02 | 分页状态与后续 DCS 冲突 | 命令被当成厂商命令 | **已排除**：`0xff 0x10` 切回 DCS 页后，`0x10`/`0x11` 立即改变 power 状态 ⇒ 切页与标准 DCS 都有效 | ⛔ |
| I03 | init 尾部 0x11/0x29 的等待 | 太短 | 原厂 120/20 ms，我们 120/40 ms | ⛔ |
| I04 | 模式/porch 编程（`0x90/0x91`、`0xb3/0xb2`、`0x3b`） | 面板按错误 porch 解码 | 字节一致；需验证被接受 | ⛔ 已排除（字节同 DTBO） |
| I05 | DSC 相关厂商命令（`0x90/0x91` 组） | 面板 DSC 未使能 | 字节一致 | ⛔ 已排除（同上） |
| I06 | `0x9e` 的 bit0/bit1 | 曾被当成"booster 没开" | **判据作废**：切页后发真正的 DCS `0x38`，bit1 仍恒为 1；`0x10`/`0x11` 只改变 bit4。该位不可由标准 DCS 清除，更像"未锁到有效码流"的上报 | ⛔（不再用作判据） |
| I07 | ESD/status 检查 | 不影响点亮 | 原厂运行时 "ESD feature not enabled" | ⛔ |
| I08 | TE（video mode 不需要） | — | 原厂也是 video | ⛔ |
| I09 | 亮度寄存器 `0x51` | 内部调光 0 | init 里写了 `0f ff` | ⛔ |
| I10 | 复位后 PPS 是否要重发 | 重连后参数丢失 | 我们每次 prepare 都发 | ⛔ |
| I11 | sleep in/out 的 120 ms | 面板没醒 | **已排除**：poke `0x10`→`0x0e`、`0x11`→`0x9e` 立即生效 | ⛔ |
| I12 | CSOT/TM desc 混用 | 用错 init | **已排除**：`panel desc: tianma … cmdline_match=1` | ⛔ |
| I13 | 面板是否在扫我们的帧（DCS `0x45`） | 黑屏与"锁流"的分水岭 | 8 次采样只得 9 和 11，**判为弱证据**（多数 DDIC 的扫描计数自由运行）。改用 DCS `0x0e`（GET_SIGNAL_MODE）定性——见 I16 | ⛔ 判据作废（改用 I16） |
| I14 | DPU 是否真的在出帧（本镜像） | 面板收不到有效流 | **已重测并确认**：`intf_2`（0x36000）`+000=00000001`（TIMING_ENGINE_EN=1）、`+0ac` 14813→14933（**+120 帧 / 2 s = 60 fps**）、`+0b0` 行计数在帧内回绕。DPU→INTF2 确实在出帧 | ⛔ |
| I15 | 厂商在 enable 时额外下发一批 MIUI 命令 | 可能是"面板不显示"的开关 | **已测，无效果**：在默认图（刚 init 过）上按厂商顺序完整发送 `ff10 → 51 0fff → 53 24 → 55 00 → ff27 → d1 28 → ff10 → 53 2c → 13 00`，9 条全部 `write_ret` 正常，`power` 仍 `0x9e`、`signal` 仍 `0x80`、屏幕无变化 | ⛔（关闭） |

| I16 | **面板有没有检测到有效视频信号**（DCS `0x0e`） | 唯一能区分"流没到"与"收到但不显示"的读数 | **已读**：`signal=0x80`（bit0=0 → 信号模式关）、`status=0x00`（无 DSI 错误）。结合原厂 DT 声明的期望值 `0x0a=0x9d` 而我们是 `0x9e`，两条独立指标一致：**面板没有收到有效视频流** | ⛔（读数到手，方向确定） |
| I18 | **DSI 到底有没有在 HS 上发数据** | 若数据 lane 一直停在 LP-11，则"没信号"= 我们压根没发 | **已测：在发**。dsi0 连续 10 次采样出现 `1f00`（四条数据 lane 均非 stopstate = HS）与 `1f1f`（LP，BLLP 间隙）；dsi1 同样混合 `1f00/1f0f/1f1f` ⇒ 两条链路都在 HS 上发视频，**不是"没发"** | ⛔（在发） |
| I17 | 我们多发的那条 DCS `0x9b`（compression mode） | `0x9b` 可能让 DDIC 切到"按压缩方式接收命令" | **优先级降为最低**：`0x9b` 只影响"收到流之后怎么解"，而面板报告根本没收到有效流 ⇒ `no_9b` 图暂不跑 | ⬜ 暂停（见 §0.7） |
### J. 时序与时钟（8）
| I20 | **PPS 的发送顺序**：我们在 `display_on(0x29)` 之后才发 PPS | 面板在拿到解码参数前开始扫压缩流 | **已 A/B，无效果**：`pps_in_init=1 no_9b=1` 生效（`/proc/cmdline` 含两参数、`PPS-pre` 计数=0），面板仍 `power=0x9e`、`signal=0x80`、屏幕全黑 ⇒ PPS 顺序不是原因 | ⛔（已排除） |

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| J01 | 面板是否接受各刷新率的 porch 变化 | 若只认 init 里那一组，改帧率就会黑 | 原厂 kernel 的 mode 表就是 120/144/90/60/50/48/30 七档（`dumpsys display`），且当前跑到 60 fps 正常显示 ⇒ 同一套 init 支持 porch 变化 | ⛔ |
| J02 | htotal/vtotal 与运行模式 | 模式相关寄存器天然不同 | **同模式命中**：镜像 B（`force_fps=0`）实测 `TOTAL=186301bf`，与原厂 60 Hz 逐字节相同 | ⛔ |
| J03 | bit clock 不同 | PHY 裕量 | **一致**：785,245 kHz 是 DRM 的 mode clock（未压缩整幅），msm 经 `dsi_adjust_pclk_for_compression()` 折半+压缩后得到 167,838,720/125,879,040/1,007,032,320，与原厂一致 | ⛔ |
| J04 | `dsi_adjust_pclk_for_compression` 的算法 | 时钟算错 | **已验证**：按该算法算出的 pclk/byteclk 与原厂 `state_info` 逐位相同（167838720/125879040） | ⛔ |
| J05 | mdp clk 375 MHz | 带宽 | 与原厂一致 | ⛔ |
| J06 | 双链路 PLL 共享 | 不同步 | 见 E10，原厂也是共享 dsi0 PLL | ⛔ |
| J07 | 时钟 gating（`clk_ignore_unused` 是掩盖） | 时钟被关 | 去掉参数复测；读 clk_summary | 📌 技术债 |
| J08 | dispcc GDSC/PD | 上电不完整 | 读 GDSC 状态 | ⛔ 已排除（显示子系统已上电） |

### K. DPU / CTL / INTF / 取数（10）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| K01 | DPU 是否在出帧 | 黑屏 | **已实测**：`bundle` 的 `intf_1` 帧计数 121 帧 / 2 s = 60.5 fps | ⛔ |
| K02 | CTL_TOP/CTL 配置与原厂不同 | 路由/混合错 | 同模式对照 `CTL_TOP=28000300`、`+0x20=00033000`、`+0x24=1` | ⚠️ 原厂 CTL 不可得 |
| K03 | INTF 可编程预取（bit31） | 取数时机 | 已置位 | ⛔ |
| K04 | 2LM/2DSC/2INTF 拓扑与 PP 绑定 | 数据通路接错 → INTF 读到空 PP | **已澄清，绑定自洽**：`intf_1 +25c` 低 4 位=0（→PP0）、`dsc_0_ctl +000`=0（PP0）；`intf_2 +25c` 低 4 位=1（→PP1）、`dsc_1_ctl +000`=1（PP1）。两个 DSC 的 picture/slice/RC 寄存器与 PPS 逐值相同（`0x10120258/0b400708/001401c2/01e10200/20/000601bc/…/2000`） | ⛔ |
| K05 | SSPP 取数/格式/UBWC | 无数据 | UBWC 错误 0、无 underrun | ⛔ |
| K06 | UBWC HBB 编码（7.0 改了） | 花屏 | 线性 fb 不走该分支 | ⛔ |
| K07 | CSC/色彩空间 | 黑或偏色 | 读 CSC 配置 | ⬜ 暂停 |
| K08 | underrun/超时中断 | 花屏/黑 | dmesg 无 underrun | ⛔ |
| K09 | CTL flush/commit 时序 | 不出帧 | 已出帧 | ⛔ |
| K10 | DSC 与 PP 的绑定 | 编码器没接上 | 读绑定 | ⛔ 已排除（mux 一致） |

### L. 内存 / IOMMU / 交接（6）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| L01 | SMMU fault | 黑屏/复位 | dmesg 无 fault | ⛔ |
| L02 | framebuffer 地址/大小 | 画面错位/黑 | **已核对**：`state` 里 plane-0 挂 1800×2880 AR24 fb，帧计数推进 | ⛔ |
| L03 | UBWC/线性不一致 | 花屏 | 线性 fb | ⛔ |
| L04 | cache/coherency | 陈旧数据 | 帧在推进、无取数错误 | ⛔ |
| L05 | simplefb 与 msm 抢同一个 framebuffer | 双 console 互相覆盖 | **已排除**：cmdline 含 `initcall_blacklist=simplefb_driver_init`，dmesg 有 `blacklisting initcall simplefb_driver_init`×2 与 `initcall simplefb_driver_init blacklisted` | ⛔ |
| L06 | 带宽/AB 投票不足 | underrun | 无 underrun | ⛔ |

### M. DT / 引导链（10）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| M01 | panel `compatible` | probe 不上 | `xiaomi,pipa-nt36532` 命中 | ⛔ |
| M02 | supplies 名称/句柄 | 取不到电 | 三路都取到 | ⛔ |
| M03 | reset-gpios 极性 | 见 C01 | 静态一致 | ⛔ 已排除（同 C01） |
| M04 | 双链路 endpoint/remote | 只有一路 | 两个 port 都在 | ⛔ |
| M05 | cmdline/desc 选择 | 见 A04 | **已确认**：`/proc/cmdline` 里我们的 271 字符串出现两次（header+DT）+ `force_fps=120`，ABL 串追加在后；`simplefb_driver_init` 被 blacklist、`force_fps` 生效 | ⛔ |
| M06 | DTBO/panel-id 选择 | 用错 overlay | **已确认**：cmdline 里 `androidboot.dtbo_idx=15` 且 desc 命中 `m81_36_02_0a`，选择正确 | ⛔ |
| M07 | bootloader splash 与内核接管的交接 | 接管瞬间黑 | 观察"灰闪一下"的时刻；`fbcon` 绑定 | 📌 现象记录 |
| M08 | regulators always-on 与内核管理的差异 | 掉电时序 | 对照原厂 DT 的 always-on/管理方式 | ⛔ 已排除（VSP/VSN/DVDD 均 enabled） |
| M09 | backlight 绑定 | 背光不亮 | 已亮 | ⛔ |
| M10 | dsi1 时钟父 | 见 E10 | 已核对，与原厂一致 | ⛔ |

### N. 驱动 / 框架（8）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| N01 | probe 依赖顺序（backlight 先于 panel） | panel 不上 | 看 probe 日志顺序 | ⛔ 已排除（背光已 probe） |
| N02 | panel bridge prepare/enable 顺序 | 命令发在链路未上电时 | 已核对 `drm_bridge.c`/`dsi_manager.c` 顺序 | ⛔ |
| N03 | `prepare_prev_first` | 同上 | 与上游一致 | ⛔ |
| N04 | 没有 `.enable` 回调 | 二次 enable 不亮 | `drm_panel_enable` 有判空，背光照开 | ⛔ |
| N05 | 双链路 attach | 第二路没挂上 | attach 成功日志 | ⛔ |
| N06 | **~10 s 复位**（新驱动独有） | 无法测量 | 新驱动在进 shell 前复位；旧驱动无此问题。取证走 pstore（附录 A），与当前面板诊断并行推进 | ❌ 未解（独立问题） |
| N07 | DRM client 是否提交 modeset | 面板根本没 enable | fbcon 绑定 + 帧计数 | ⛔ |
| N08 | 背光 enable 与 panel enable 的先后 | 闪白 | 时间线 | ⛔ 已排除（同 D03） |

### O. 测量方法本身的陷阱（8）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| O01 | video mode 下 DCS 读的失败语义 | 误判"面板没醒" | **已排除**：`0x0a` 读稳定返回（`0x9e`/`0x0e`），且与写入引起的状态变化一致 | ⛔ |
| O02 | 寄存器窗口太短（原厂只到 0x5c） | 看不到 DSC/lane 块 | 6d240ec 已做全窗口 dump | ⛔ |
| O03 | 照片判读（黑/灰闪/条纹） | 结论方向错 | 每次录像 | 📌 记录 |
| O04 | `0x9e` 位解释 | 误读 | 同 A06：不再用 `0x9e` 判定面板状态 | ⛔（判据作废） |
| O05 | pstore 只保留一轮 | 读数丢失 | 见附录 A | 📌 记录（属 N06） |
| O06 | 模式不可比 | 见 A03 | 同模式 | ⛔ 已排除（已同模式） |
| O07 | 一次改多个变量 | 结论污染 | 纪律 | ⛔ |
| O08 | 把"能 boot"当"驱动正确" | 掩盖真因 | 已区分 | ⛔ |

### P. 硬件（5）

| 编号 | 可能的问题 | 因果 | 怎么打勾 | 现状 |
|---|---|---|---|---|
| P01 | 面板型号/批次 | init/DSC 不通用 | **已确认**：cmdline + DTBO 一致指向 `m81_36_02_0a`（天马） | ⛔ |
| P02 | 排线/连接器接触 | 部分 lane 失效 | 重插、看 error 计数 | ⚠️ 需硬件检查 |
| P03 | DDIC 固件差异（同型号不同批次） | 某些命令不认 | 与另一块同型号面板对比 | ⚠️ 需另一台设备 |
| P04 | 另一台同型号设备对照 | 排除个例 | 需要设备 | ⚠️ 需另一台设备 |
| P05 | 面板本身坏了 | 全黑 | splash 正常 | ⛔ |

---

## 3. 建议的打勾顺序（先打信息量最大、成本最低的）

| 步 | 打哪几条 | 为什么先打 | 不通过时 |
|---|---|---|---|
| 0 | **F11** | 一行代码、已由原厂寄存器证明我们写错；改完一次上机就能看出 init 是否变完整 | 若仍黑，说明还有别的层 |
| 1 | A04 / M05 | 一条 `cat /proc/cmdline` 把"到底跑哪个 desc"钉死（证据已倾向天马，但要证实） | 用 `desc=` 参数强制 |
| 2 | A03 / J01 / J02 | 原厂快照是 50 fps，和我们 120 fps 不可比；不同模式下去比寄存器是白费 | 抓 120 fps 快照，或把 mode 改成 50 那组 porch |
| 3 | I02 / I01 / F06 | 先证明"命令写得到 DDIC 且真的生效"（page 0x10 → sleep in/out），这是最底层、最没人验的一环 | 若写无效，问题在链路/DDIC 接收，不在 DSC |
| 4 | H01 / H02 | PPS 是唯一无法从寄存器验证的环节；字节 8/9 直接判 1800 vs 900 | 改 `pic_width` 做 A/B |
| 5 | E10 / F04 | 双链路时钟源与同步（bitclk 已证一致，只剩链路级差异） | 对照 `Clock master = dsi-ctrl-0` |
| 6 | F04 / F05 | 双链路是否两路都收到命令（原厂用 broadcast） | 改 broadcast/双路发送 |
| 7 | G02 / G07 | DPU 侧 DSC 的 pic_width/slice 与 DSI 是否一致 | 统一成 per-link |
| 8 | B03 / B04 / B08 | 供电顺序与 VSP/VSN 时序（"背光亮、屏不亮"的经典成因） | 按原厂顺序重排并加延时 |
| 9 | E07 / E06 | 驱动强度、EOT、lane 极性 | 按原厂值写 |
| 10 | L05 / M07 | simplefb 与内核接管 | 黑名单 simplefb，复测 |
| 11 | K02 / K04 | CTL/INTF 拓扑逐寄存器 | 同模式对照 |
| 12 | N06 | 新驱动的复位（只在移植阶段） | pstore 判读 |

---

## 4. 原厂侧还能补的采集（root，性价比最高）

原厂系统里有 `dynamic_debug`，这是目前唯一能拿到**厂商实际下发的命令/PPS/时序**
的途径，能一次性关掉 H01/H04/H05/I01/F07 五六条：

1. 开日志（在 root 的原厂系统上）：
   ```sh
   mount -t debugfs none /sys/kernel/debug 2>/dev/null
   echo 'file *dsi_panel* +p'   > /sys/kernel/debug/dynamic_debug/control
   echo 'file *dsi_display* +p' > /sys/kernel/debug/dynamic_debug/control
   echo 'file *dsi_ctrl* +p'    > /sys/kernel/debug/dynamic_debug/control
   echo 'file *sde_dsc* +p'     > /sys/kernel/debug/dynamic_debug/control
   ```
2. 熄屏/亮屏一次（`input keyevent 26` 或亮度拉到 0 再拉回），抓 `dmesg`。
   里面会有：`dsi_panel_prepare/enable`、`DSI_CMD_SET_ON`、PPS 命令、
   `bit_clk`/`pclk`/`byte_clk`、DSC 参数。
3. **同模式快照**：让屏幕跑 120 fps（滑动/视频/游戏），同时抓
   `dri/0/debug/qcom,mdss_dsi_m81_36_02_0a_dualdsi_dsc_lcd_video/*`
   （`dump_info`、`state_info`、`sde_reg`、`clk_summary`、`regulator_summary`）。
   这样 A03/J02/J03/K02 全部变成可比。
4. 熄屏→亮屏瞬间的 `sde_reg`/`dsi-ctrl-0_reg` 差分，能看出厂商在 "接管" 时
   改了哪些我们没改的寄存器（M07）。

---

## 5. 记录模板（每打一条勾，追加一行）

```
编号：
假设：
改动/观测命令：
预期：
实测（原始输出/照片）：
结论：⛔排除 / ⚠️降级 / ⬜未测
下一步：
```

---

## 8. 实测记录（原厂 root，逐步追加）

### 2026-10-28 第一轮（设置 60 Hz，静态界面）

| 观测 | 值 | 对应条目 |
|---|---|---|
| `clk_summary` | `disp_cc_mdss_pclk0_clk=167838720`、`byte0_clk=125879040`、`mdp_clk=375000000`；`dsi1_phy_pll_out_*` enable=0 | E03/J03 ⛔ |
| `dsi0_ctrl_reg` / `dsi1_ctrl_reg` | 除 `0x3c` 外逐字相同；dsi0=`0xd4000000`、dsi1=`0x94000000`（bit30 只在 master） | F05 ⚠️（原厂用广播） |
| `regulator_summary` | l2=1800 mV、dvdd_buck=1300、dvdd_ldo=1300、vsp=5500、vsn=5500，全部 use=1；vsp/vsn 挂在 panel 名下 | B07 ⛔；B04 ⚠️（vsp/vsn 归属与主线不同） |
| `dri/0/state` | crtc-0 上两块 `900x2880` 平面（x=0 与 x=900），另有 `60x2880@1740` 等小平面 | 双链路 2×900 分半（K04 背景） |
| `/proc/cmdline` | `msm_drm.dsi_display0=qcom,mdss_dsi_m81_36_02_0a_dualdsi_dsc_lcd_video:` | A04：bootloader 自带该串（倾向天马） |
| `dump_info` | **没抓到**：面板 debugfs 目录在 `/sys/kernel/debug/` 顶层，不在 `dri/0/debug/` | 下一轮修正 |

**注意**：本轮虽然设置成 60 Hz，但 DSI 侧仍是 50 fps 的时序（`TOTAL=0x15f30254`，与 10-27 的 50 fps 快照逐字相同）——
说明 MIUI 在静态界面上会走 dfps 的省电档 50 Hz（不在设置的 60/90/120 三档里）。
要抓 60/90/120，必须让画面动起来（滑动/播放视频），或把 `min_refresh_rate` 钉住。

### 2026-10-28 第二轮：原厂两条链路的 CTRL 对照（关键）

`dsi0_ctrl_reg` 与 `dsi1_ctrl_reg` 除 **`0x3c`（CAF 命名的 CMD_DMA_CTRL，主线偏移 0x38）** 外逐字相同：

```
dsi0: 0x3c = d4000000   bit31 BROADCAST_EN=1, bit30 is_master=1, bit28 embedded=1, bit26 LPM=1
dsi1: 0x3c = 94000000   bit31 BROADCAST_EN=1, bit30 is_master=0, bit28 embedded=1, bit26 LPM=1
```

因果（CAF `dsi_ctrl_hw_cmn.c:861-876`：`en_broadcast`→BIT(31)、`is_master`→BIT(30)）：
原厂是**从 master 踢一次、硬件广播到两条链路**，slave 自己的 DMA 从不启动。

我们的 `dsi_host.c:871` 把 master 的那个值无条件下发到**每一个 host**：

```c
/* Vendor liuqin value; the upstream pair leaves bits 31/30 clear. */
dsi_write(msm_host, REG_DSI_CMD_DMA_CTRL, 0xd4000000);
```

而主线的命令通路是"两条链路各写一份 DMA、由 `msm_dsi_manager_cmd_xfer()` 同时 trigger"
（`dsi_manager.c:507-548`），与 broadcast 是**互斥的两种机制**。两边都置 broadcast，
等于每条链路都广播一次，同一串 216 包 init 可能在两路之间重复并交错 —— 分页写被打乱，
DDIC 就可能停在"能应答、不显示"的状态。

修法（一行，下一版验证）：恢复上游语义
`DSI_CMD_DMA_CTRL_FROM_FRAME_BUFFER | DSI_CMD_DMA_CTRL_LOW_POWER`（= `0x14000000`，bit31/30 清零），
让每条链路只发自己那一份；若将来要做真广播，则必须同时改成"只在 master 上 kickoff"，
不能两者混用。

### 2026-10-28 第三轮：60 Hz 真值（关键）

原厂 `dump_info`（设置 60 Hz，动态时）：

```
Resolution = 900(46|100|2|0)x2880(214|3148|2|0)@60fps 1007032320 Hz
```

| 刷新率 | hfp | vfp | 每链路 htotal × vtotal | 备注 |
|---|---|---|---|---|
| 120（DTBO timing@0） | 100 | 26 | 1048 × 3122 | 我们当前代码用的 |
| **60（本轮实测）** | 100 | **3148** | 1048 × **6244** | = 120 Hz 的 vfp 翻倍 |
| 50（10-27 快照） | 249 | 2524 | 1197 × 5620 | 静态省电档，不在设置三档里 |

bit clock 三档都不变（`1007032320 Hz`）。因此 60 Hz 的 DSI 侧唯一变化是 vtotal：
`DSI htotal = 300(压缩后有效) + 148(消隐) = 448`，`vtotal = 6244`，
⇒ `TOTAL` 期望 `0x186301bf`，`ACTIVE_H/ACTIVE_V/VID_CFG0/DSC_MODE_CTRL` 全部不变。

另外 `dumpsys display` 显示原厂 kernel 的 mode 表：120/144/90/60/50/48/30 共 7 档，
`defaultModeId=120`，当前 `mActiveSfDisplayMode=60`。**144 确实存在**（只是设置界面不提供）。

### 2026-10-28 第四轮：60 Hz 预测验证（模型闭环）

预测 `TOTAL=0x186301bf`，实测：

```
dsi0: 0x2c = 186301bf   0x3c = d4000000 (master+broadcast)
dsi1: 0x2c = 186301bf   0x3c = 94000000 (broadcast, 非 master)
其余 ACTIVE_H/ACTIVE_V/VID_CFG0/DSC_MODE_CTRL 全部不变
pclk0=167838720  byte0=125879040  （与 120 Hz 一模一样）
```

⇒ **"固定 1.007 G bit clock、只改 porch" 得到证实**；60 Hz = 120 Hz 的 vfp 翻倍。
我方 60 Hz 目标 mode 的 DSI 寄存器可以被逐字节预测，第一次有了真正的同模式对照。

附带观察（待复核，不作结论）：本轮 `dsi1` 的 `FIFO_STATUS = 0x11111010`，
而 `dsi0` 是 `0x00001010`（50 fps 快照时两条都是 `0x00001010`）。
按寄存器定义 bit16-19 是 DLN0 的 HS FIFO empty/full/overflow/underflow 四位，
同时置位不合常理，更可能是"四条 lane 的 HS FIFO empty"或采样时刻差异。
下一轮请连读 3 次（间隔 1 s）确认是否稳定；若只在从链路上出现，值得单独查。

### 2026-10-28 第五轮：第一次带着修复进 shell（关键）

镜像 `repack/60hz-boot/boot-702b079d-A.img`（内核 `702b079d`，旧驱动、DPU 预取已回退、
broadcast 默认关闭）。**能进 shell** —— 闸门通过。

`nt36532/dcs`：`power=0x9e display=0x00 addr=0x00 pixfmt=0x07`（仍黑）。

`dsi0/regs`（主线偏移，CTRL 在 0x00）：

| 寄存器 | 我们 | 原厂 60 Hz | 判定 |
|---|---|---|---|
| `CTRL` | `000001f3` | `000001f3` | 同 |
| `STATUS0` | `00000008` | `00002008` | **差**（原厂 bit13 置位） |
| `FIFO_STATUS` | `00001210` | `00001010` | **差**（bit9） |
| `VID_CFG0` | `02009230` | `02009230` | 同 |
| `ACTIVE_H/V` | `015c0030`/`0c1800d8` | 同 | 同 |
| `TOTAL` | `0c3101bf` | `186301bf` | **我们跑的是 120 Hz，不是 60** |
| `CMD_DMA_CTRL` | `14000000` | `d4000000`(master) | 与基线/上游一致（W1 的修法） |
| `DSC_MODE_CTRL` | `03840b01` | `03840b01` | 同 |
| `LANE_STATUS` | `00001f00` | `00001f1f` | **差**（低 5 位） |
| `LANE_CTRL` | `01000000` | `01000000` | 同 |
| `CLK_STATUS` | `008047c3` | `008047c3` | 同 |

**更正（同轮）**：第一次贴的 dmesg 行被 printk 截断，误判成"命令行被 ABL 覆盖"。
完整 `/proc/cmdline` 显示我们的 271 字符串**出现两次**（header + DT）+
`panel_novatek_nt36532.force_fps=120`，再接 ABL 的 `androidboot.*`。
所以 bootargs 是生效的，`force_fps=120` 也确实进了内核（`TOTAL=0c3101bf` 与之一致：
天马 desc + 强制 120 Hz）。同时 dmesg 里有两行
`blacklisting initcall simplefb_driver_init`，说明黑名单也生效。
⇒ 运行时开关**可以**继续用 bootargs；此前"必须改走 DT 属性"的结论作废。

**poke 结果（关键）**：依次写入 `0xff 0x10`、`0x10`、`0x11`、`0x29` 后，
每次都在 dmesg 产生 `dsi_err_worker: status=5`：

- `status=5` = `DSI_ERR_STATE_TIMEOUT(0x1) | DSI_ERR_STATE_FIFO(0x4)`；
- FIFO 位是已知误报（原厂正常态 FIFO_STATUS 也非零，见 R3）；
- **TIMEOUT 是真实的**：命令 DMA 在 200 ms 内没有完成 ⇒ DCS 写没有发出去/没被确认；
- 四次写入后 `power` 仍是 `0x9e`，面板状态完全没变。

推论（待验证）：若写通路一直超时，则 216 包 init 序列**很可能从未成功下发**，
`prepare()` 应当返回 `-110` 并打印 `failed to initialize panel`。下一轮先确认这行。

### 2026-10-28 第六轮：desc 定案、写通路确认、real exit-idle 无效

镜像 A（`702b079d`，`force_fps=120`，进 shell 正常）。

| 观测 | 结果 | 条目 |
|---|---|---|
| `panel desc: tianma, htotal=2096 vtotal=6244 clock=785245 kHz, force_fps=120, cmdline_match=1` | **天马 desc 确认**，bootargs 生效 | A04 / M05 ⛔ |
| 无 `failed to initialize panel` | 216 包 init + PPS + compression mode **全部发送成功** | I01 ⛔（此前 ⚠️） |
| `poke 0x10` → `power=0x0e`；`0x11` → `0x9e` | **DCS 写到达 DDIC 并改变状态**；写通路正常 | I02 / F06 ⛔（写入有效） |
| `poke 0x38`（已先 `0xff 0x10` 切页）→ `power` 仍 `0x9e` | 真正的 DCS EXIT_IDLE **不能**清掉 bit1 | 记入 R4 |
| `dsi_err_worker: status=5` 每 33 ms 刷一次 | 假警报：FIFO 位是已知误报（R3），TIMEOUT 是锁存残位；写入本身成功 | 不再追 |

推论：`power` 的 bit1（"idle"）在 `0x9e`/`0x0e` 两种状态下恒为 1，DCS 清不掉 ⇒
它更可能是 **DDIC 对"未锁到有效码流"的状态上报**，而不是可由 0x38 清除的 idle 模式。
下一轮重点转为"同模式逐字节对照 + 面板是否在扫我们的帧"。

### 2026-10-28 第七轮：60 Hz 同模式对照成立（DSI 控制器层结案）

镜像 B（`force_fps=0`）实测：`panel desc: tianma … force_fps=0`、**`TOTAL=186301bf`**。

与原厂 60 Hz dump 逐值比：

| 寄存器 | 我们 | 原厂 | 结论 |
|---|---|---|---|
| `CTRL` / `VID_CFG0` / `ACTIVE_H` / `ACTIVE_V` / `ACTIVE_HSYNC` | 一致 | 一致 | ⛔ |
| `TOTAL` | `186301bf` | `186301bf` | ⛔ **同模式命中** |
| `DSC_CTRL` | `03840b01` | `03840b01` | ⛔ |
| `CMD_DMA_CTRL` | `14000000` | `d4000000`(master) | 我们的修法（双 DMA 双 trigger 下不能开广播） |
| `LANE_CTRL` | `01000000` | `01000000` | ⛔ |
| `STATUS0` | `00000008` | `00002008` | 差 bit13，主线 XML 未定义该位 |
| `FIFO_STATUS` | `11111210` | `00001010` | 多出的 bit16/20/24/28 是四条 lane 的 HS FIFO empty，属采样时刻状态 |
| `LANE_STATUS` | `00001f0f` | `00001f1f` | 差 CLKLN 停态位，同样与采样时刻/连续时钟策略有关 |

⇒ **DSI 控制器这一层在 60 Hz 下已经逐值对齐**，不再是嫌疑。
剩余待取：DPU 是否在出帧（`INTF_FRAME_COUNT`，`bundle` 的 `intf_0` 窗口 +0x0ac/+0x0b0），
以及面板侧是否锁流（`0x45`，需一次构建）。

**窗口名更正**：`dpu_diag_wins[]`（`dpu_kms.c:305-325`）里的名字是
`sspp_vig0 / ctl_0 / ctl_1 / intf_1 / intf_2 / lm_0 / dspp_0 / pp_0..3 /
dsc_0_top / dsc_0_enc / dsc_1_enc / dsc_0_ctl / dsc_1_ctl / dsc_2_top / dsc_2_enc`。
没有 `intf_0`。而且 **DPU 的 DSC 窗口这次是可读的**（`dsc_0_*`），
之前"DPU DSC 编码器抓不到"的结论只对 vendor 的 `sde_off` 成立，对我们自己的
`bundle` 不成立——这是补 PPS/编码器对照的新入口。

### 2026-10-28 第八轮：DPU 确实在出帧（I14 关闭）

`bundle` 的 `intf_1`（0x35000）窗口：

| 采样 | `+0a0`（第 4 字 = FRAME_COUNT） | `+0b0`（第 1 字 = LINE_COUNT） |
|---|---|---|
| pass1 | `00000a7a` = 2682 | `000017ba` = 6074 |
| pass2（+2 s） | `00000af3` = 2803 | `0000089b` = 2203 |

增量 **121 帧 / 2 s = 60.5 fps**，与 60 Hz 模式一致 ⇒ DPU 在真实出帧，
INTF 在过帧，DSI 在送。**整条"内存→DPU→INTF→DSI"链路已在 60 Hz 下被测量证明在工作。**

DPU 侧 DSC 编码器（`dsc_0_enc` 0x80100，第一次拿到）decode：

| 寄存器 | 值 | 含义 |
|---|---|---|
| `+0x34` DSC_PICTURE_SIZE | `0b400708` | height 0x0b40=2880, width 0x0708=1800 |
| `+0x38` DSC_SLICE_SIZE | `001401c2` | slice 450×20 |
| `+0x3c` | `000001c2` | chunk = 450 |
| `dsc_0_top +000` | `00000101` | common mode：EN + SPLIT_PANEL（bit8） |
| `dsc_0_ctl +004` | `00001801` | 控制块 |

`dpu_encoder_prep_dsc()`（`dpu_encoder.c:2021-2062`）以**整幅** 1800 作为
`dsc->pic_width`，用 `DSC_MODE_SPLIT_PANEL` 让两个 DSC 各分 900；
所以 DPU 侧 `pic_width=1800` 是主线设计如此，寄存器与代码自洽。
⇒ **H02（PPS 的 pic_width 是 1800 还是 900）不能靠 DPU 寄存器判定**，
只能靠 PPS 字节与"面板是否接受"来判。

**剩余两个未知，且只剩两个**：

1. **面板有没有在扫我们的帧**（DCS `0x45`）——旧驱动读不了，需要一次构建（I13）；
2. **我们发出的 128 字节 PPS 与厂商实际发送的是否一致**（H01/H04）——需要把
   PPS 打出来，并用 CAF 的 `sde_dsc_helper.c` 离线复算对照。

### 2026-10-28 第九轮：为"锁流"和"PPS 字节"做准备（代码已提交）

`bf394ce59719` 加了三样诊断（都默认惰性）：

1. `dcs` 节点读 8 次 DCS `0x45`，输出 `first/last/advancing`——
   这是"面板有没有锁我们的流"的唯一直接判据（I13）；
2. `prepare()` 打印 `dsc-pre:` 字段与 128 字节 `PPS-pre:`（H01）；
3. `panel_novatek_nt36532.pps_per_link_pic_width=1` 时，PPS 用 pic_width/2 打包
   （1800→900），**不动 DPU 的 SPLIT_PANEL 编码配置**（H02 的 A/B）。

已知可用的运行时开关（bootargs 已证明生效）：
`force_fps=60|120|144`、`pps_per_link_pic_width=0|1`、`no_dsc=1`、
`skip_panel_init=1`、`msm.dsi_cmd_broadcast=0|1`。

### 2026-10-28 第十轮：原厂动态调试实采（A 级，重要）

打开 `dsi_panel/dsi_display/dsi_ctrl/sde_dsc/sde_encoder` 的 dynamic debug，熄屏→亮屏一次：

```
dsi_display_set_mode: mdp_transfer_time=0, hactive=1800, vactive=2880, fps=60, clk_rate=1007032320
dsi_ctrl_isr_configure: dsi-ctrl-0/1: IRQ registered
set 51 backlight 65295
dsi_panel_enable: primary panel: DSI_CMD_SET_ON
dsi_display_set_power: Display (primary), Power mode (On)
mi_dsi_panel_set_disp_param: feature: flat_mode, value: 1 → flat mode on
dsi_display_post_enable
mi_dsi_panel_match_fps_pen_setting: refresh_rate[60]
mi_dsi_panel_set_disp_param: feature: cabc, value: 0 → cabc off !!
mi_dsi_panel_set_disp_param: feature: dimming, value: 1
mi_dsi_panel_update_last_bl_level: disable insert black
（随后 dfps: fps 60 → 50，再次 set_mode，clk_rate 仍是 1007032320）
```

由此得到两条结论：

1. **原厂在 60 fps 下的模式就是 `1800×2880 @ clk_rate=1007032320`**，与我们完全一致；
   且 CAF 的 `pic_width = h_active` 用的是 1800 ⇒ H02"应该发 900"基本可以放掉，
   `pps_per_link_pic_width` 只留作兜底 A/B。
2. **厂商在 enable 时还额外发了一串 MIUI 特性命令**（`0x51` 亮度、flat_mode、cabc off、
   dimming on、insert-black、按 fps 的 pen 命令），我们的驱动一条都没发（I15）。
   这些是原厂"点亮"路径的一部分，但优先级要等 `advancing` 结果再定。

### 2026-10-28 第十一轮：PPS 字节到手，`advancing` 存疑

`bf394ce5` 镜像实测（默认 60 Hz）：

```
dsc-pre: pic 1800x2880 slice 450x20 count 2 chunk 450 bpp 128 bpc 8 per_link=0
PPS-pre: 11 00 00 89 30 80 0b 40 07 08 00 14 01 c2 01 c2
         02 00 01 e1 00 20 01 bc 00 06 00 0c 05 0e 06 1a
         ...
dcs: power=0x9e display=0x00 addr=0x00 pixfmt=0x07
     scanline samples=8 first=9 last=11 advancing=yes
```

PPS 逐字段解码（全部落在 DSC 1.1 的规范值上，没有异常）：

| 字节 | 值 | 含义 |
|---|---|---|
| 0 | `11` | DSC 1.1 |
| 3 | `89` | line_buf_depth 9、8 bpc |
| 4–5 | `30 80` | block_pred=1、convert_rgb=1、bpp=128（8.0） |
| 6–9 | `0b40 0708` | 2880 × 1800 |
| 10–15 | `0014 01c2 01c2` | slice 20×450、chunk 450 |
| 16–17 | `0200` | initial_xmit_delay 512 |
| 18–19 | `01e1` | initial_dec_delay 481 |
| 21–25 | `20 01bc 0006` | initial_scale 32、scale_inc 444、scale_dec 6 |
| 27–35 | `0c 050e 061a 1800 10f0` | first_line_bpg 12、nfl 1294、slice_bpg 1562、initial_offset 6144、final 4336 |
| 36–43 | `03 0c 2000 06 0b 0b 33` | flatness 3/12、rc_model 8192、edge 6、qincr 11/11、tgt offset 3/3 |
| 44–57 | `0e 1c 2a 38 46 54 62 69 70 77 79 7b 7d 7e` | 标准 buf_thresh 表 |

⇒ **PPS 内容本身没有可疑项**（H01/H04 从"内容错误"降级）；`advancing=yes` 因为只差 2
且采样与 vsync 同步，只能算弱证据（I13 降级）。
下一步用"往 `/dev/fb0` 写随机数据、看屏幕是否出噪点"直接判定"内容有没有到面板"；
同时准备 `no_dsc` 镜像（`boot-bf394ce-60-nodsc.img`）作为对照。

### 2026-10-28 第十二轮：`/dev/fb0` 不存在的原因，以及"量错了 INTF"

- `/dev/fb0` 与 `/proc/fb` 都不存在是**正常的**：本配置 `CONFIG_DRM_CLIENT_LOG=y`、
  `CONFIG_DRM_CLIENT_SELECTION=y`，控制台客户端是 `drm_log`（`drivers/gpu/drm/clients/`），
  它独占 DRM 客户端，fbdev 模拟就不会再建 fb。drm_log 自己会
  `drm_client_buffer_flush` + `drm_client_modeset_commit`，所以"往 fb 写随机数据"这条路
  **用户态走不通**；内容只能由控制台客户端自己提交。
- 之前 `state` 里 `fb=92 allocated by = drm_log` 也印证了这一点。
- **更正**：我先前用 `intf_1` 的帧计数宣布"DPU 在出帧"，但 boot 日志写的是
  `DIAG vid_enable: intf2 state=1 -> ENABLING`，用的 INTF 是 **intf_2**。
  所以"DPU 出帧"这条要重测，且必须看 `intf_2` 的 `+000`/`+0ac`/`+25c`。

### 2026-10-28 第十三轮：`intf_2` 确认在出帧，但发现 PP 绑定疑点

`intf_2 (0x36000)`：

| 偏移 | 值 | 含义 |
|---|---|---|
| `+000` | `00000001` | TIMING_ENGINE_EN = 1 |
| `+004` | `00800000` | INTF_CONFIG（bit31 未置，符合我们回退预取后的状态） |
| `+0a0` 第 4 字 | 14813 → 14933（2 s） | **+120 帧 = 60 fps** |
| `+0b0` 第 1 字 | 3040 → 5375 | 行计数在 6244 内推进 |
| `+25c` | `000f0001` | INTF_MUX 低 4 位 = 1（PP1）；高 4 位 = 0xf |

而 `dsc_0_ctl (0x80f00) +000` = 0（DSC 的 PP 选择 = PP0），`dsc_0_top +000` = 0x101（EN+SPLIT_PANEL），
`dsc_0_enc` 的 picture/slice/chunk 都对。

同时 `intf_1` 的帧计数也在以 60 fps 跑（2682→2803）——说明**两条 INTF 都在运行**。
于是出现一个必须澄清的问题：**哪条 INTF 由哪个 DSC/PP 喂**。
若 INTF2 读 PP1、而我们的 DSC0 写在 PP0，INTF2 读到的就是没被填充的 ping-pong，
画面当然全黑——这与"DSI/PPS/时序全对、帧计数正常"完全自洽。

### 2026-10-28 第十四轮：绑定澄清 + "insert black" 成为头号嫌疑

- 路由自洽：`intf_1`↔PP0↔`dsc_0`，`intf_2`↔PP1↔`dsc_1`；两个 DSC 的编码器寄存器
  与 PPS 逐值相同（picture 1800×2880、slice 450×20、chunk 450、RC 全表）。
  ⇒ **DPU 侧从平面到 DSC 编码器全部自洽**，K04 结案。
- 由此只剩最后一个未被检验的维度：**面板侧的显示开关**。
  DTBO 里有一组 MIUI 命令（A 级明文），厂商在 enable 之后都会发：
  `ff 10 13 00`（disable insert black）、`ff 10 55 00`（cabc off）、
  `ff 27 d1 28 ff 10 53 2c`（dimming on）、`ff 10 51 0f ff`（亮度满）、
  `ff 10 22 00`（insert black，背光变化时用）。
  我们一条都没发。
- 头号假设：**bootloader/上电把面板留在 "insert black" 状态**，
  于是码流、PPS、时序全对，面板照样显示纯黑。`13 00` 能否点亮，一次 poke 即知。

### 2026-10-28 第十五轮：PHY 逐值比对（最后一块未比对区域）

`/dev/mem` + `busybox devmem 0xae94400` 直接读 dsi0 PHY，与原厂
`out/vendor-display/dri_0_debug_dsi0_phy_reg.txt` 对齐：

| 偏移 | 原厂 | 我们 | |
|---|---|---|---|
| 0x00/0x04/0x08/0x0c | 25/0/2/0 | 25/0/2/0 | 同 |
| **0x10** | `00000031` | **`00000061`** | **不同** |
| **0x14** | `00000021` | **`00000030`** | **不同** |
| 0x18/0x1c | 0/1 | 0/1 | 同 |
| **0x20** | `00000044` | **`00000053`** | **不同** |
| 0x24–0x58（21 个） | 7f/0/40/04/21/84/01/b8/0/7f/7f/0/ff/ff | 完全相同 | 同 |

⇒ PHY 的 lane timing 段（`vendor_phy_timing` 覆盖的那 14 个值）**完全一致**；
差异只在 CMN/PLL 控制段的三处（0x10、0x14、0x20）。
注意：原厂快照取于亮屏态、我们取于黑屏态，部分位可能是状态相关，
不能直接判为错误——需要 dsi1 PHY 与第二次采样来区分。

### 2026-10-28 第十六轮：PHY 差异定性 —— 寄存器层面穷尽

| 偏移 | 原厂 dsi0 | 我们 dsi0（两次一致） | 我们 dsi1 |
|---|---|---|---|
| 0x10 | `31` | `61` | `F1` |
| 0x14 | `21` | `30` | `34` |
| 0x20 | `44` | `53` | `53` |
| 0x3c | `01` | `01` | `00` |

**我们自己的两条链路就不一样**（0x10：`61` vs `F1`），说明这三处不是"固定配置"，
而是实例/PLL 相关（含状态位）。拿原厂 dsi0 的值当目标是错的（R5 的同类陷阱）。

⇒ **可读寄存器的比对到此全部穷尽**，结论是：控制器、lane timing、DPU、DSC、
PPS、INTF、平面/帧缓冲路由**都与原厂一致**；PHY 的 CMN/PLL 三处无法定性且不可作为判据。

剩下的判别只能靠行为实验，不能再靠读寄存器：
1. `no_dsc` 对照（未压缩时面板是否出任何东西）；
2. `pps_per_link_pic_width=1` 对照；
3. 若无结论 → 需要抓 DSI 线（逻辑分析仪）或原厂 PPS 字节，二者本机都拿不到。

### 2026-10-28 第十七轮：三张行为图全部无变化（重要分界）

| 图 | 变化 |
|---|---|
| `boot-bf394ce-60.img`（60 Hz，DSC，PPS 1800） | 无（黑 + 背光） |
| `boot-bf394ce-60-perlinkpps.img`（PPS pic_width 900） | 无 |
| `boot-bf394ce-60-nodsc.img`（不走 DSC） | 无 |

⇒ **面板在任何码流配置下都不显示**，且三种配置之间肉眼无差别。
结合前面已逐值确认的控制器/PHY lane timing/DPU 路由/DSC 寄存器/PPS 字节/init 字节，
可以下结论：**差异不在"配置值"，而在"驱动时序/状态机"或电气层**。

由此收敛出两个尚未验证的具体差异：

1. **我们比原厂多发了一条 DCS `0x9b`（compression mode）**——DTBO 的 on-command 里没有它
   （H07）。`0x9b` 在部分 DDIC 上会让面板进入"按压缩方式接收命令模式"，
   与 video 模式冲突时可能表现为不出画面。需要在 prepare 里**不发**它来验证。
2. **面板的"信号模式"从未读过**：DCS `0x0e`（GET_SIGNAL_MODE）直接回答
   "DDIC 有没有检测到有效视频信号"，是区分"没收到流"与"收到但不显示"的唯一直接判据。

这两条合成一次构建即可（`no_9b` 参数 + `0x0e`/`0x09` 读数）。

### 2026-10-28 第十八轮：`signal=0x80` —— 面板没收到有效视频流

```
power=0x9e display=0x00 addr=0x00 pixfmt=0x07
signal=0x80 status=0x00
scanline samples=8 first=4 last=5 advancing=yes
```

- `signal=0x80`：bit0=0 ⇒ **信号模式关闭**（DDIC 没有检测到有效视频输入）；
- `status=0x00`：没有 DSI 协议错误（说明命令与包层面没报错）；
- 与 `0x0a=0x9e` 对照原厂 DT 的期望值 `0x0d`…（`panel-status-value = <0x9d>`）：
  只差 bit0（booster）与 bit1（idle）⇒ **面板从未离开"无信号待机"态**。

结论（两条独立指标一致）：

1. **PPS 不是问题**——PPS 错只会导致花屏/错色，不会导致"信号模式关闭"（H01/H04 彻底关闭）；
2. **`no_9b` 暂不必跑**——它只影响"收到流之后怎么解"；
3. 现在的唯一问题是：**我们的视频流没有以面板能识别的形式出现在 HS 链路上**，
   要么我们根本没在发（I18），要么发出去的电平/时序面板认不出。

⇒ 下一动作（零构建）：连续采样 `LANE_STATUS`，确认数据 lane 是否真的在发。

**I18 结果与推论**：`LANE_STATUS` 在 `1f00`（HS）与 `1f1f`（LP，BLLP）之间来回，
说明视频数据确实在 HS 链路上跑，面板也处在能"看见"数据的状态，但它仍报
`signal=0x80`（信号模式关）。

⇒ 只剩两种解释：
1. **发出去的载荷面板不认**（DSC 码流无效 → 有些 DDIC 把"解不出有效图像"报成无信号）；
2. **电气层**（电平/预加重，面板收得到但解不出）。

用同一内核再跑一张 `no_dsc=1`（未压缩载荷）即可区分：
若 `signal` 变成"有效"，说明 DCS/DSC 载荷是元凶；若仍是 `0x80`，则指向电气层。

### 2026-10-28 第十九轮：`no_dsc` 仍是 `signal=0x80` —— 转向面板偏压

`no_dsc` 图读数与默认完全一样（`power=0x9e`、`signal=0x80`、`status=0x00`）。
注意：这张图**并不能**干净地区分"载荷"与"电气"——面板 init 里已按 DSC 配置，
未压缩数据本来就不该被接受，所以阴性结果不具判别力（这条是我的设计失误）。

由此剩下的、且**从没验证过**的硬件层是 **VSP/VSN 面板偏压（±5.5 V）**：

- 厂商：`soc:qcom,dsi-display-primary-vsp/vsn` 由显示驱动使能；
- 主线：由 ktz8866 负责（`vddpos-supply`/`vddneg-supply` + `kinetic,enable-lcd-bias`，
  驱动里写 `LCD_BIAS_CFG1(0x09) = 0x9F`）。

若这两路偏压没起来，源极驱动无电 → **面板在任何码流配置下都不会显示、也不会报"有信号"**，
而 DCS 命令（1.8 V 逻辑）与背光（LED 升压）都照常工作——这与我们观测到的**全部**现象吻合。

### 2026-10-28 第二十轮：偏压正常，状态机命令无效 → 停止参数实验

- 面板偏压 **正常**：`backlight_gpio_vsp/vsn` enabled @5500mV，DVDD enabled（B04 关闭）。
- `0x13`（normal）、`0x11`（sleep out）、`0x29`（display on）连续下发后：
  `power` 仍 `0x9e`、`signal` 仍 `0x80`、`display=0x00`，**毫无变化**。
- 原厂 DT 声明的正常值 `0x9d` 达不到。

⇒ 按第十八轮定下的**硬性停止条件**：**不再做任何参数/寄存器实验**。

至此能证明"正确"的层：DSI 控制器与 lane timing、DSI PHY（20/23）、DPU 路由与出帧
（60 fps）、DSC 编码器与 PPS、init 字节、面板供电与背光、命令通路（读写均有效）、
HS 链路确实在传数据（`LANE_STATUS` 在 `1f00`/`1f1f` 间切换）。

**唯一还没排除的两条**：
1. **面板自己的状态机/解码**（DDIC 内部，寄存器读不到深层原因）；
2. **电气层**（HS 眼图/终端匹配，寄存器无法反映）。

两条都需要外部手段：逻辑分析仪抓 DSI 线，或在原厂系统上取一份**健康态的 `0x0a`/`0x0e`
读数**用来验证我们对位含义的解释（目前 `0x9d` 只是 DT 里的声明值）。

### 2026-10-28 第二十一轮：Z（无 DRM）也灰→黑 —— 交接本身就结束了画面（结论已修正，见第二十五轮）

> **2026-10-29 修正**：本轮第 1 条结论**不成立**。用户上机明确观察到：开机后屏幕正常显示
> 大段 `initcall ... calling ...` 日志，随后才在**我们接管的那一刻**灰化、然后黑屏。
> 画面死在接管时，不死在交接时。详见 §8 第二十五轮。

关键实验：`initcall_blacklist=simplefb_driver_init,msm_drm_init`（**整个 DRM 不初始化**），
现象与默认图**完全相同**：启动文字 → 全灰一瞬 → 纯黑。

由此得到两条硬结论：

1. **画面变黑不是我们驱动造成的**：DRM 完全不介入时也一样黑；
   bootloader 交接之后（ABL 停止驱动 / 显示相关时钟与电源在 late init 被收走），
   面板本来就进入无信号态。**"黑屏"是交接后的默认状态，不是故障点。**
2. 我们驱动的任务因此是**冷启动**（reset + init + PPS + 视频流），
   而厂商内核走的是**连续 splash 继承**（`cont_splash`）——它从不做冷启动。
   ⇒ **这台设备上不存在可参照的"厂商冷启动"日志**，只有"厂商亮屏（suspend→resume）"
   那一次是可比的，而那次比我们多发了 MIUI 的后置命令（0x51/0x53/0x55/0x13/dimming）。

另外纠正一个设计失误：`no_dsc=1` 会改变 bit clock（1.007 G→约 2.3 G），
面板 PLL 必然失锁，所以 Y 图（`skip_panel_init+no_dsc`）的"灰黑"**不具判别力**。

**原厂 DPU 寄存器不可得（已确认，2026-10-28 末）**：

| 入口 | 结果 |
|---|---|
| `debug/sde_off` | `cat` 显示 `0x00000000 5c`，写入 `"0x15000"`、`"86016 256"` 均被忽略，窗口无法改 |
| `debug/reg_dump` | 输出仅 2 行（空） |
| `debug/evtlog_dump` | 空 |
| `debug/sde_reg` | 永远返回基址 0x0 起的 `0x5c` 字节（`80050000 …`），与 `sde_off` 无关 |

⇒ **原厂 DPU（CTL/INTF/DSC/PP）侧永远拿不到对照数据**。DSI 控制器与 PHY 的窗口
（`dsi0_ctrl_reg`/`dsi0_phy_reg` 等）是固定的，能读，但 DPU 不行。

**新的下一步（零构建）**：在**刚启动、面板刚被我们 init 过**的状态下，
按厂商顺序完整发一遍后置命令（此前是零散 poke，顺序和时机都不对）：

```
ff 10 → 51 0f ff → 53 24 → 55 00 → ff 27 → d1 28 → ff 10 → 53 2c → 13 00
```

若仍无变化，则 I15 也关闭，回到 §0.7 的仪器路线。

### 2026-10-28 第二十二轮：厂商后置命令全部无效 —— 软件侧穷尽

在默认图（面板刚被我们 reset+init 过）上，按厂商顺序完整发送 9 条后置命令，
全部 `write_ret` 正常，**`power` 仍 `0x9e`、`signal` 仍 `0x80`、屏幕无任何变化**。

**读数陷阱（新）**：在厂商页 `0xff 0x27` 之后读 `0x0a` 得到 `0xe4`——
那不是电源模式寄存器，而是页 0x27 的厂商寄存器；切回 `0xff 0x10` 后又回到 `0x9e`。
以后**任何 DCS 读数都必须确认当前页码**（已记入 `known-wrong-changes.md` R10）。

至此，软件侧能做的实验全部完成。逐项关闭清单：

| 曾怀疑 | 结论 |
|---|---|
| 广播位 / DPU 预取 / 强制命令行 | 已修/已回退 |
| DSI 控制器、PHY lane timing、DPU 路由、DSC 编码器、PPS、init 字节 | 与原厂逐值一致 |
| 供电、背光、命令通路、HS 是否在发 | 正常 / 在发 |
| 面板 init 是凶手 | 否（`skip_panel_init` 同样黑） |
| 接管是凶手 | 否（无 DRM 时同样黑） |
| 面板后置命令 | 否（本轮） |
| 状态机命令（0x13/0x11/0x29/0x38） | 无效 |

**唯一剩下的解释**：我们发出去的 DSC 码流在物理层/内容上不被该 DDIC 接受，
或该 DDIC 需要某种本机无法复现的初始化条件。⇒ 只剩 §0.7 的仪器路线（或第二台设备）。

### 2026-10-29：按 skill 经验库做的最后一次 A/B

skill `experience/display.md` 的「软件状态全部正常，屏幕却是黑的」一节列出了六条成因，
本移植逐条核对后**五条已排除**（背光使能、TE/vblank、DSC 参数、有效宽度取整、供电步进），
**只剩一条没试**：

> DSC 视频模式面板用了**非连续时钟**导致失锁。

我们的天马 desc 确实带 `MIPI_DSI_CLOCK_NON_CONTINUOUS`。已加
`panel_novatek_nt36532.cont_clock=1`（commit `57cf6a65`）：attach 时清掉该标志，
并打印 `diag: cont_clock=%d (mode_flags=0x…)`。

同一份 skill 还确认了两件事，记录备查：

1. **"接管时屏幕会黑一下"属于正常现象**（上游没有无缝接管，驱动移除 simpledrm 后复位硬件）
   ⇒ 我们 Z 实验（无 DRM 也灰黑）的结论与之一致，不必再查；
2. **"借用固件画面"路线**要求 bootloader 的扫描一直存活；本机 Z 实测交接后扫描停止
   ⇒ 该路线在本机 `fastboot boot` 下不可用。

预期的诚实判断：命中概率不高（厂商 DT 带 `bllp-power-mode`，暗示原厂也是非连续时钟），
但这是**有据可依的最后一个实验**。

### 2026-10-29 第十三轮：skill 经验 + 上游同型号驱动，得到两个可测假设

**① skill 经验库**（`experience/display.md`「软件状态全部正常，屏幕却是黑的」）列了六条成因，
逐条核对后五条已排除，只剩**非连续时钟** ⇒ `cont_clock`（`57cf6a65`）。
同文件另两条也印证了我们的判断："接管时屏幕会黑一下"**属正常现象**（与 Z 实验一致）；
"借用固件画面"要求 bootloader 持续扫描，本机做不到（Z 实验已证明）。

**② 上游正在化的 `panel-novatek-nt36532.c`**（OnePlus Pad 2 / CSOT PPC100HB1-1；
同为 NT36532 + 双 DSI + 双 DSC + `slice_per_pkt=2` + 4 lane）——**同型号 DDIC 的、别人已跑通的实现**：

| 项 | 上游 | 我们 | 判定 |
|---|---|---|---|
| `slice_count`/`slice_width`/`pic_width` | 2 / 750 / 由 msm 填整幅 3000 | 2 / 450 / 整幅 1800 | ✅ 同构，H02 结案 |
| `mode_flags` | VIDEO \| **CLOCK_NON_CONTINUOUS** \| LPM | 同 | ✅ E19 命中率低 |
| `dsc_version` | 1.2 | 1.1（DTBO 写死） | 面板不同，不构成差异 |
| **PPS 位置** | init 内、`0x90 0x03` 之后、`exit_sleep`/`display_on` 之前 | **`display_on` 之后** | ❗**唯一实质顺序差异** |
| **`0x9b`** | **从不发** | 会发 | 已知，可用 `no_9b=1` |

⇒ 新假设 I20：**我们在 `0x29` 之后才发 PPS**，面板在拿到解码参数前已开始扫压缩流。
已加 `pps_in_init=1`（`ca4e87fd`）。

**构建产物说明**：`ca4e87fd` 是 `57cf6a65` 的后代，**两个参数都在最新那一个产物里**；
只需把最新产物放进 `ci/`，旧的 57cf6a65 不必下载（除非新构建失败）。

**I20 结论（2026-10-29）**：把 PPS 移到 init 内、`0x90 0x03` 之后、`0x9d` 之前，并停发 `0x9b`
（与上游工作驱动完全一致的顺序），参数确实生效（`/proc/cmdline` 两个参数都在、
`dmesg | grep -c 'PPS-pre'` = 0），但面板状态与画面**毫无变化**。
⇒ **PPS 发送顺序不是原因**。

至此，由 skill 经验库与上游同型号驱动引出的两个新假设，一个已排除（I20），
另一个（E19 连续时钟）待测。

### 2026-10-29 收尾：两个最后的假设都被排除，软件侧正式走完

| 假设 | 来源 | 实测 | 结论 |
|---|---|---|---|
| **I20** PPS 顺序（应在 display-on 之前） | 上游 `panel-novatek-nt36532.c`（OnePlus Pad 2，同 DDIC 双 DSC） | `pps_in_init=1 no_9b=1`，参数生效（`/proc/cmdline` 有、`PPS-pre` 计数 0） | ❌ 无变化 |
| **E19** 非连续时钟致失锁 | skill `experience/display.md` 六条成因的最后一条 | `cont_clock=1`，生效（`mode_flags=0x403`，位已清） | ❌ 无变化 |

**至此，所有"有据可依"的软件假设都已排除**：

配置侧（DSI 控制器、PHY lane timing、DPU 路由、DSC 编码器、PPS 字节、init 字节、
时钟策略、PPS 顺序）与原厂一致或已 A/B；
资源侧（VSP/VSN、DVDD、背光）正常；
命令侧（读写、分页、后置命令、状态机命令）全部可用或已试；
链路侧（HS 确实在发）。

**唯一未解且不可再测的**：面板 DDIC 为何不认这路码流。
可行的继续手段只剩 §0.7 的②（抓 DSI 线）与③（第二台设备）；
①（原厂健康读数）已确认不可得（`rx_cmd` 不可用、DPU 寄存器窗口不可读）。

### 2026-10-29 第二十三轮（纯离线）：从 `uefi.elf` 解出引导程序的面板配置

**入口**：`liuqin_images_V14.0.9.0.TMYCNXM_13.0/images/uefi.elf`
（2.76 MB，ELF64 单 LOAD 段，一个 FV）。FV 里两个 `FV_IMAGE` 文件的 GUIDed
section（GUID `1d301fe9-be79-4353-91c2-d23bc959ae0c`，`DataOffset=0x18`）
实际是 **gzip** 流；解压得到两个 DXE FV（3.86 MB / 3.08 MB）。
`abl.elf`（204 KB，32 位）与 `xbl_s.melf` 里没有任何 panel/dsi 串，**不是**显示路径。

**内容**：FV1 里是整套面板 XML 库（47 个 `<DSIInitSequence>`），其中有
`M81 36 02 0a Dual DSI DPHY Vid Mode LCD Panel (1800x2880 24bpp)`——
与本机面板同名、同分辨率、同 DSC（450×20、scr 0）、同 bit clock
（`1007032320`，与 DTBO 的 `0x3c061800` 逐位相同）。

**与我们的 init 比对**（DTBO `repack/e15.dts:11203`，216 包，去重后逐命令对齐）：

| # | 我们发的（DTBO） | 引导程序发的（UEFI） |
|---|---|---|
| 1 | `D1 20`（page 0x27） | `D1 28` |
| 2 | 无 | page 0x25 中多一条 `0F 20`（紧跟 `05 00` 之后） |

217 条里 215 条逐字节相同（相似度 99.3%）。**init 内容本身基本不是差异点。**

**同一份 XML 还给出的"工作配置"**：

| 项 | 值 | 我们 |
|---|---|---|
| `DSISlaveControllerSkewLines` | `-2` | 主线 DSI 驱动**没有** skew 概念 |
| `DSIPhyDCDCMode` | `True` | `dsi_phy_7nm.c` 里**没有** DCDC |
| `DSIDSCPicWidthSlice` | `2` | 我们 PPS 用整幅 1800（=4 slice），`pps_per_link_pic_width=1` 试过无变化 |
| `DSITiming*` 14 值 | 与 `vendor_phy_timing` 的 14 字节相同 | 已试，无变化 |
| `DSILowPowerModeInBLLP/BLLPEOF` | `True` | 与我们一致（非连续时钟） |
| `DisplayResetInfo` | `0 10 1000 10000 0` | DT 是 `10/3/3/15`（ms） |

**判读边界（重要）**：

1. UEFI 在每次冷启动时点亮面板，用的就是这套序列 ⇒ **序列内容本身不是黑屏原因**
   （这是目前唯一"在这块板上确实点亮过"的独立实现）。
2. 但**不能**因此断定 `D1`/`0F` 两处差异是关键：MIUI 内核的 prepare/enable 走的是
   同一份 DTBO on-command，若 resume 时不跳过 init，这套序列也在亮屏路径上用过；
   这一点**未取证**（原厂无从观察）。
3. 所以这两条只值**一次**定向 A/B（改 desc 两条命令），不构成重开参数试错的理由。
4. 顺带纠正一个比读陷阱（已记 `known-wrong-changes.md` R11）：`repack/e15.dts` 是
   dtbo entry 15 的整棵树，含 **58 个** `on-command` 数组；天马是倒数第二个
   （`:11203`，216 包），CSOT 是最后一个（`:11346`，194 包）。抓第一个数组
   （Sharp qhd，80 包）会得出"UEFI 与 DTBO 完全不同"的错误结论。

**数据来源复核（2026-10-29，按用户要求用一手文件）**：本轮的 DTBO 侧数据
**不是**取自 `repack/e15.dts`，而是直接从
`liuqin_images_V14.0.9.0.TMYCNXM_13.0/images/dtbo.img`（sha256 `f73eedd1…`）
重新解析：38 个条目里有 3 个含 `m81_36_02_0a`（idx 2 / 3 / 15），三者的天马
`on-command` 完全相同（2047 字节 / 216 包，sha256 `6b14c9e0…`，
与 UEFI XML 的差异仍是上面那两条）；`repack/v14-dtbo/entry.15` 与本次解出的
entry 15 **逐字节相同**（dtb sha256 `90845c32…`），`repack/e15.dts` 只是同一
dtb 的另一种 dts 渲染。**结论：repack 没有污染这份数据。**

解析注意：这个 `dtbo.img` 的头与条目表是**大端**（文件头 `d7 b7 ab 1e`），
按小端读会得到 `count=637534208` 之类的垃圾值。可复现：

```sh
python3 - <<'PY'
import struct
d=open('liuqin_images_V14.0.9.0.TMYCNXM_13.0/images/dtbo.img','rb').read()
_,_,_,esz,cnt,off,_,_=struct.unpack_from('>8I',d,0)   # 大端
for i in range(cnt):
    size,doff=struct.unpack_from('>2I',d,off+i*esz)
    if b'm81_36_02_0a' in d[doff:doff+size]: print(i,size,hex(doff))
PY
# 取到条目偏移后：dtc -I dtb -O dts 解出
```

**已提交（2026-10-29，未推送）**：`195c4fbc3228`
（`drm/panel: match the bootloader's M81 36 02 0a init sequence`），只改
`m81_36_02_0a_init_sequence()` 两处：`d1 20→28`、`05 00` 后插 `0f 20`。
推送：`git -C linux-sm8450-liuqin push GitHub liuqin-7.0`（CI 自动触发）。
上机判据：**出画面** ⇒ 这两条命令即根因，转产品化；**仍黑** ⇒ 只剩条件类差异
（skew −2 / PHY DCDC / 复位时序）或仪器路线，不要回到参数试错。

**CI 已回、镜像已装配（2026-10-29）**：`ci/liuqin-kernel-195c4fbc3228…/`
核对通过（`sha256sum -c` 全过、`kernel.commit` 与目录名一致、
`NT36532=y`、`CONFIG_CMDLINE=""` 无 FORCE）。二进制级确认：旧产物与新产物的
`.rodata` 同偏移处 `d1 20`→`d1 28`，且 `05 00` 与 `14 80` 之间多了 `0f 20`。
镜像 `repack/195c4-boot/boot-195c4.img`，58,572,800 B，
sha256 `f68a4448…`，round-trip 全过（`repack/chk-195c4/`）；上机单见
`repack/195c4-boot/README.md`。

### 2026-10-29 第二十四轮（上机）：`D1 28` + `0F 20` 无效，init 内容线关闭

镜像 `repack/195c4-boot/boot-195c4.img`（`195c4fbc3228`）实测：

```
panel desc: tianma, htotal=2096 vtotal=6244 clock=785245 kHz, force_fps=0, cmdline_match=1
power=0x9e display=0x00 addr=0x00 pixfmt=0x07
signal=0x80 status=0x00
scanline samples=8 first=7 last=8 advancing=yes
CTRL 000001f3  STATUS0 00000008  FIFO_STATUS 00001210  VID_CFG0 02009230
ACTIVE_H 015c0030  ACTIVE_V 0c1800d8  TOTAL 186301bf  ACTIVE_HSYNC 00020000
CMD_DMA_CTRL 14000000  DSC_CTRL 03840b01  LANE_STATUS 00001f00  CLKOUT 0000191f
CLK_STATUS 008047c3
```

与打补丁前**逐字节相同**（`power`/`signal`/`display`/扫描行全一样），只有两个
只读状态位与原厂不同：`STATUS0` 少了 bit13（我们 `0x08`，原厂 `0x2008`）、
`FIFO_STATUS` 多了 bit9（我们 `0x1210`，原厂 `0x1010`）。这两条不作为判据
（同 R3 的教训，单看一个只读位说明不了因果）。

⇒ **结论**：引导程序与我们 DTBO 的两条 init 差异不是原因。**init 内容这条线
到此关闭**——两份实现（UEFI XML、厂商 DTBO）发的序列都实际发过，都无效。
补丁已回退：`213601cf2ea1`（Revert）。

⇒ **下一步**：软件侧已无可试项。`skip_panel_init`（含"天马 desc + 120 Hz"组合）
此前已测过、无变化（用户 2026-10-29 确认，记 E3）。**停止参数实验**；
要么等仪器/第二台设备，要么换目标，不再从已关闭的方向里找新说法。

### 2026-10-29 第二十五轮（观察修正）：画面不是交接时死的，是接管时死的

用户对"每次启动都相同的那段画面"的描述（多张镜像一致）：

1. 开机后屏幕点亮，**滚动出现大量 `initcall ... calling ...` 日志**；
2. 随后画面**快速但可见地变灰**，灰层底下仍能看到日志的残影；
3. 最后全灰 → 黑屏，只剩背光。

判读：

- 第 1 条证明 **bootloader 留下的整条显示链路在进入 Linux 之后仍然活着**：
  DPU 在扫、DSI 在送、面板在显示、背光与供电都在。那些字是 Linux 的
  `earlycon=simplefb` 写进显存的；能显示出来，就说明扫描一直在跑。
- 第 2 条是**视频流断掉后的液晶弛豫**（驱动电压消失 → 残影 → 均匀灰），
  不是"面板收到了一个灰画面"。
- 时间点与"我们接管"重合，候选动作只有两个（相隔约 100–200 ms，肉眼分不开）：
  面板 `prepare()` 拉复位脚；或 msm 重配 DSI、控制台切到 `drm_log`。

**因此修正两条旧结论**：

| 旧结论（第二十一轮） | 修正后 |
|---|---|
| bootloader 交接之后面板就进入无信号态，"黑屏"是交接后的默认状态 | **不成立**。画面一直显示到我们接管；黑屏发生在接管序列里 |
| Z 实验（无 DRM）也黑 ⇒ 不是我们驱动造成的 | Z 的黑要另找原因（没人 vote 住显示资源、late init 收走时钟/电源域等），**不能**据此推出"交接即无信号" |

**由此确定的边界**：

- 排除：面板坏、背光、供电、DSI 物理层"完全不工作"、面板"不接受任何码流"；
- 指向：接管序列（复位时机 / init / DSI 重配 / 控制台切换）里有一步让面板丢流且未恢复；
- 推论：6.17 若仍是"复位 + 重发 init"的接管方式，现象大概率相同，除非某一步与 7.0 不同。

**只读可做的判读**（不改代码）：把屏幕上最后一条可见的 `initcall` 对到 dmesg 同一行，
看它停在哪个阶段、与 `panel desc:` / msm probe 的先后关系——这能把"复位"和"DSI 重配"
这两个候选点分开。

### 2026-10-29 第二十六轮（上机）：稳压器是"黑"的凶手，流在更早的地方就断了

镜像 `repack/zreg-boot/boot-zreg-308065ef.img` = Z 镜像**只改一个命令行参数**
（`regulator_ignore_unused`；内核/ramdisk/DTB 逐字节相同，DT 反编译 diff 只有
`/chosen/bootargs` 一行）。

**现象**：屏幕不再转黑，而是**保持高亮灰色**。

**两条独立结论**：

1. 旧 Z 的"灰 → 黑"里的**黑**，是 `regulator_late_cleanup()`（late_initcall）
   关掉了没人 claim 的 VSP/VSN/DVDD 造成的：加上 `regulator_ignore_unused`
   后面板保持供电，不再掉黑。⇒ **凡是"背光只亮、屏纯黑"的旧图，都混进了这一个
   与显示驱动无关的变量**；判读"黑"时必须先确认这根轨没被收走。
2. **流仍然断了**：面板有电、背光在，画面却是均匀灰（液晶弛豫）——
   说明 ABL 的视频流在**完全没有任何驱动碰 DSI/DPU** 时（`msm_drm_register` 进黑名单）
   也会停。`clk_ignore_unused` 与 `pd_ignore_unused` 都是本树里真实存在的参数
   （`drivers/clk/clk.c`、`drivers/pmdomain/core.c`），所以"时钟/电源域被 late init
   收走"也不是原因。

**下一步（只读，不改代码）**：先看显示时钟与 ICC 带宽投票还在不在，再读 DSI
`LANE_STATUS`/`TOTAL` 与 DPU `INTF_FRAME_COUNT`，把"发送端停了"和"还在发但面板不认"
分开：

| 读数 | 含义 |
|---|---|
| `INTF_FRAME_COUNT` 不再增长 | DPU 停了（取数/带宽/时钟） |
| 帧计数在涨、`LANE_STATUS` 为 HS | 一直在发，面板不认 |
| 帧计数在涨、`LANE_STATUS` 为 LP | DSI 停了而 DPU 还在空转 |

**当轮追加读数（同一镜像，上机）**：

| 读数 | 值 | 含义 |
|---|---|---|
| `regulator_summary` | VSP/VSN 5500 mV、DVDD 1300 mV 全在 | 面板供电正常 |
| `regulator: Not disabling unused regulators`（33.87 s） | 打印出现 | `regulator_ignore_unused` 确实生效 |
| `clk_summary`：`mdp_clk` / `byte0/1` / `pclk0/1` / `mdss_ahb_clk` | `hardware enabled=Y` | 显示时钟支路全开（`rate=0` 只是 CCF 不知道 ABL 的分频） |
| `pm_genpd_summary`：`mmcx`、`mdss_gdsc` | **on** | **显示核心没有掉电**——"域被收走"这条假设当场作废 |
| `pm_genpd_summary`：`mdss_int2_gdsc` | off-0 | 第二个 GDSC 从没被开过（可能是 INTF2/DSI1 那一路） |
| `interconnect_summary` 显示相关节点 | 全 `0 0` | bootloader 的带宽投票没被继承 |
| `devmem 0xae36000`（INTF_1）起始的循环 | **系统重启** | MDP 窗口访问触发总线异常 ⇒ 该窗口在 Z 状态下不可读 |
| `devmem 0xae94000`（DSI0 `HW_VERSION`） | `0x20060000` | DSI0 块活着、可读 |
| `devmem 0xae94004`（DSI0 `CTRL`） | `0x000001f7` | 控制器仍处于使能态（原厂运行态是 `0x1f3`） |
| `devmem 0xae940a4`（`LANE_STATUS`）×5 | 全部 `0x00000000` | **PHY 各 lane 处于 off/idle**，既不是 HS(`1f00`) 也不是 LP(`1f1f`) |

**结论**：到用户态时 ABL 那路码流已经在 **DSI/PHY 层停掉**（控制器使能但 lane 不动），
面板只是有电、无信号。所以仍然拿不到"ABL 工作态"——必须在它死掉之前抓，或者先找出
是谁让它死的。

⚠️ `devmem` 读 MDP 窗口会 panic（panic=15 重启），**不要再整段扫**。

### 2026-10-29 第二十七轮（关键）：天马面板在 6.17 上点亮

镜像 `repack/617-boot/boot-617-nodp.img`（6.17 artifact `3b694685881d` + 天马 desc，
**唯一改动是把 DP 控制器的 `status` 改成 `disabled`**）。

**先踩的坑**：不加这一步时 6.17 **根本没走到点屏**——

```
probe of ae00000.display-subsystem returned -517   (-EPROBE_DEFER)
platform ae90000.displayport-controller: deferred probe pending
```

msm 的 DRM master 把 DP 控制器当作 component（MDP out-port 的远端节点），DP 一直在等
USB-C altmode 的 `drm_bridge`，于是 master 永不 bind ⇒ 没有 `card0` ⇒ 没有首帧提交
⇒ 面板 `prepare()` 一次都没跑（`dcs` 全 `0xff`、`devmem 0xae94000`=0）。
**这与面板无关，纯粹是 component 依赖。** 7.0 能跑到 `prepare()` 只是因为它没把 DP
拉进这条链。

**点亮后的观测**：

| 项 | 值 |
|---|---|
| `/sys/class/drm/` | `card0`、`card0-DSI-1`、`renderD128` |
| `panel desc` | `tianma (desc_sel=auto cmdline_match=1)` |
| `dsc:` | `pic 1800x2880 slice 450x20 count 2 chunk 450 bpp 128 bpc 8`（从 `ae96000.dsi.0` 打印） |
| 控制台 | `printk: console [drm_log0] enabled` |
| DSI0 `CTRL` | **`0x000001F3`**（与原厂、也与 7.0 的 DRM 运行态一致） |
| DSI0 `LANE_STATUS` | 采样值为 0（显示正常，说明该采样点落在 blanking/读法不可靠，别再当判据） |
| DPU | `dpu hardware revision:0x80050000`，`Initialized msm 1.13.0` |

**结论（推翻之前的框架）**：

1. 天马面板、DDIC、init 216 包、DSC 参数、reset 时序、双 DSI 绑定——**全部无罪**；
2. "7.0 上黑屏"是**这条移植线自己的问题**，不是面板不接受码流；
3. **CTRL 不是差异**：7.0 在 DRM 起来时同样是 `0x1f3`（§7 第 309/622 行）。
   早先记的 `0x1f7` 来自 Z 实验（msm 黑名单、DSI 停在 ABL 残留态），已更正。
   7.0 与 6.17 的真正差异需要**在两者都 DRM 起来的状态下逐值 diff**
   （黄金参照：`repack/golden-617/`）。
4. 这张 6.17 镜像现在是**唯一已知能点亮本面板的主线实现**，可作为寄存器级黄金参照
   （`repack/golden-617/`，DSI0/1 两条链路逐值）。

**判读陷阱（新）**：`0x0a4` 在**能亮的状态下也读 0**；能亮时 `0x0a8 = 0x1F00`。
之前用 `0x0a4` 当 `LANE_STATUS`、据此判"lane 全停 ⇒ 没在发流"的结论**作废**
（错偏移）。以后判链路是否在发，用黄金参照里的 `0x0a8` 和 `0x120 CLK_STATUS`。


---

## 9. 参考：上游作者复盘（CSOT 设备，B 级）

来源：yzddMr6《150亿token：我给小米平板6Pro移植了原生Linux》
（Coolapk feed `73754584`；转载全文
<https://zone.ci/secarticles/wx/574737.html>）。**他的设备是 CSOT 面板**，
不是本机的天马，结论只能当参考。

他遇到的显示故障是**花屏**（整屏彩色噪点 → 文字可读但两条竖直噪声带），
修完两点后正常（120 Hz）：

| 他的修复 | 内容 | 本机现状 |
|---|---|---|
| DPU 拓扑 | 社区实验路径是 4:4:2，厂商是 **2:2:2**（2 LM / 2 DSC / 2 INTF）；非 virtual plane 下后两个 mixer 拿不到有效像素，DSC 把无效内容压成"合法"码流 | `num_dsc=2`、双 INTF、`slice_count=2`、`DSC_MODE_CTRL=03840b01`（WC=900=2×450）⇒ 已是 **2:2:2**，与他修好后的状态一致 |
| DSC 分包 | 社区 `slice_per_pkt=1`，厂商要 **2** | `dsc_slice_per_pkt=2`，一致 |

**对本机的意义**：他的故障是"有码流、内容错"（花屏）；本机是"面板报无信号、
完全不显示"（黑屏 + 背光），故障模式不同；他修好的两点我们本来就是对的。
所以这篇**没有可搬的修复**，只能作为"同一套代码能点亮 1800×2880 双 DSI +
DSC 面板"的旁证（同 SoC、同分辨率、同 KTZ8866 背光）。

另有两条可复用经验：

1. **TDDI 共用复位**：NT36532 的触控与显示共享复位和部分内部状态。他那边
   面板驱动一复位，触控固件就卡在 A0 不进扫描；最后靠恢复厂商 SPI 命令的
   完整长度修好。本机以后做触控时要记住这条。
2. **"一次实验没改善画面"不等于改动无效**：他的 `slice_per_pkt` 修复曾被
   4:4:2 拓扑问题掩盖，记成"没有效果"。所以阴性结果只对**当前状态**成立，
   E7 的结论也按这个口径写（"在当前状态下不是原因"），不是"永远无关"。

---

## 10. 同 DDIC（NT36532）的社区实现（2026-10-29 检索）

结论：**NT36532 有社区驱动和上游驱动，但没有一块针对 `m81_36_02_0a`。**

| 项目 | 面板 / 设备 | 状态 | 与本机的关系 |
|---|---|---|---|
| postmarketOS `soc/qualcomm-sm8250/linux` **MR !15**（Luka Panio；2026-02-12 **已合并**）→ 已进 `6.17.0` 分支，驱动在 `panel-novatek-nt36532.c` | Xiaomi Pad 6（pipa，SM8250）：NT36532，Tianma + CSOT 两个 desc（作者称两家 init 相同），1800×2880@120，148×237 mm | 已合并 | 同 DDIC、同分辨率、物理尺寸也与本机 DTBO 一致（148.0×236.7 mm），但 **init 序列不同**：pipa 约 161 条、本机 216 条，起止外壳相同（`FF 27…`、`B3 40/B2 91/90 03/91/92`），页 0x22 / 0x24 / 0x25 / 0x26 / 0x27 / 0x2A 的内容不同 ⇒ **不是同一块面板**，不能直接套 |
| lore：`[PATCH v3 2/2] drm/panel: Add Novatek NT36532 panel driver`（Junjie Cao，2026-08，Neil Armstrong `Reviewed-by`） | OnePlus Pad 2 / CSOT PPC100HB1-1：3000×2120@120，dual-DSI DSC | 上游化中（v3） | 同 DDIC 的另一块面板；用 `MIPI_DSI_MODE_DSC_ALL_SLICES_IN_PKT` 表达 `slice_per_pkt=2`，与本机用的 `dsc_slice_per_pkt` 字段功能等价 |

pipa 驱动与本机 desc 的配置差异（这些在本机**都已试过**，不是新方向）：

- `mode_flags` 无 `VIDEO_BURST`（本机 burst）——E2 与"三组合"实验已覆盖；
- 复位 12/12/12/12（本机 10/3/3/15）——早期基线就是 12/12/12/12；
- 默认 120 Hz（本机默认 60）——`force_fps=120` 已试；
- LPM 在 `prepare`/`unprepare` 里开关、`unprepare` 把 reset 拉高。

**意义**：NT36532 在主线里能被正常驱动（pipa 已合并进 pmOS 6.17 分支；
OnePlus Pad 2 的驱动在 review），所以"这块 DDIC 在 mainline 上驱不动"不成立；
但**本机这块面板没有现成实现可抄**，init 仍只能用本机 DTBO 那份
（已实测发送成功）。另注意：pipa 的 Tianma desc 是作者按"两家 init 相同"
直接复用的，MR 描述原话是 "seems like"，**没有真机证据**，不能当已验证参考。

本地留档：`.scratch/pipa_nt36532.c`（pipa 6.15.11 分支驱动）、
`.scratch/pipa.dts`（pipa 板级 DTS）。

---

## 11. 关键测试镜像与生成时的源码状态（2026-10-30 更新）

这张表是"想复现某个现象时该 boot 哪张镜像"的唯一索引。**sha256 都已重算核对**。
所有镜像都用 `repack/unpacked/ramdisk`（installer.img，`a04d2b25…`）同一份 ramdisk。
**6.17 点亮的完整装配参数（输入哈希、header、命令行、复现命令、显示配置）**
见 [`docs/display-617-tianma-lit.md`](display-617-tianma-lit.md)（权威记录，
复现命令已逐位验证）。

| 镜像 | sha256 | 大小 | 内核 / 分支 | DTB 与命令行相对源码的改动 | 现象 |
|---|---|---:|---|---|---|
| `repack/base-308065ef/boot-base-308065ef.img` | `60125e8e…344d3e` | 58,568,704 | `7.0.14-g308065ef80be`，`liuqin-7.0` @ `308065ef` | 无（DTB 与 DTS 同源，命令行用板级 DTS 自带串，`panic=15`） | 7.0 基线：DRM 起来、面板 init 跑完、**黑屏**；`power=0x9e`、`signal=0x80` |
| `repack/617-boot/boot-liuqin-firstboot.img` | `11e58ab5…eb3059` | 58,687,488 | `6.17.0-rc1-g3b694685881d`，`liuqin-6.17-tianma` @ `3b694685881d`（**早于** `0c71219b`） | 无（命令行用 6.17 板级 DTS 自带串，与 7.0 只差 `panic=0`） | **DRM 根本没起来**：`display-subsystem` 一直 `-EPROBE_DEFER`（DP 控制器等 USB-C altmode），`/sys/class/drm` 只有 `version`、`dcs` 全 `0xff` |
| `repack/617fix-boot/boot-liuqin-firstboot.img` | `c76820fe…1e1923` | 58,687,488 | `6.17.0-rc1-gc7e51cdf3290`，`liuqin-6.17-tianma` @ `c7e51cdf3290`（DP disable **已落源码**） | 无（命令行用板级 DTS 自带串） | ✅ **正式版，2026-10-30 上机确认点亮**：不依赖手工 `fdtput`；与 nodp 的唯一差别是 DP 由源码关闭 |
| `repack/617s-boot/boot-liuqin-firstboot.img` | `d524db1c…fcdcd84` | 58,695,680 | `6.17.0-gfc2fb59ef397`，`liuqin-6.17-stable` @ `fc2fb59ef397`（v6.17 final merge，仅 2 处冲突） | 无（装配管线/输入与 617fix 完全相同，只换 Image/DTB） | ✅ **2026-10-30 上机确认点亮**：逐级升级第一级（6.17-rc1 → 6.17 final）成功，显示通路零回归 |
| `repack/618-boot/boot-liuqin-firstboot.img` | `2a2f8101…e3052` | 58,855,424 | `6.18.0-g47048e710209`，`liuqin-6.18` @ `47048e710209`（v6.18 merge + 4 个修复，首次 `ubuntu-24.04-arm` 原生构建） | 无（同上） | ❌ **黑屏**（2026-10-31）：显示通路回归分析见 `kernel-version-upgrade.md` §5，头号嫌疑为 6.18 新增的 `dpu_crtc_mode_valid` 核心时钟过滤 |
| `repack/618fix1-boot/boot-liuqin-firstboot.img` | `0e9b3b86…a3ba0` | 58,859,520 | `6.18.0-ga2f0e2d32661`，`liuqin-6.18-fix1` @ `a2f0e2d3266`（回退 `dpu_crtc_mode_valid` 模式过滤，三个文件与 6.17 逐字节一致） | 无（同上） | ❌ **仍黑屏**（2026-10-31）：证伪——`/sys/class/drm/` 只有 `version`，无任何 DRM 设备，失败层比模式过滤更早。真根因与证伪过程见 `kernel-version-upgrade.md` §6 |
| `repack/618fix2-boot/boot-liuqin-firstboot.img` | `f2a64964…d536e` | 58,855,424 | `6.18.0-g7c18dc40cbd9`，`liuqin-6.18-fix2` @ `7c18dc40cbd9`（回移 v6.19 的 a6xx `ifpc_reglist` NULL 保护） | 无（同上） | 待刷机：真根因修复实验（`repack/618fix2-boot/README.md`） |
| `repack/617-boot/boot-617-nodp.img` | `99fcc9b2…4935a8` | 58,687,488 | 同上 | **唯一改动**：`fdtput` 把 `/soc@0/display-subsystem@ae00000/displayport-controller@ae90000` 的 `status` 设为 `disabled` | **天马面板点亮**（首张）：`card0`、`card0-DSI-1`、`dsc:` 正常、屏幕出画面 |
| `repack/7fps-boot/boot-fps120.img` | `c69f1884…f9b05d` | 58,572,800 | `7.0.14-g…`，`liuqin-7.0` @ `c4ba514b1256`（desc 已是 `VIDEO_BURST`、默认 60 Hz） | 命令行加 `panel_novatek_nt36532.force_fps=120`（零构建） | ❌ **上机直接重启**：`c4ba514b` 是坏提交（内核自身起不来），不可用 |
| `repack/702fps-boot/boot-702-fps120.img` | `7c1b3642…c66b91` | 58,568,704 | `liuqin-7.0` @ `702b079d`（能正常启动的版本，desc 带 `VIDEO_BURST`、默认 60 Hz） | 命令行加 `panel_novatek_nt36532.force_fps=120`（零构建） | 7.0 的 **120 Hz + burst**：能启动、**屏幕仍黑** ⇒ 组合不是解药 |
| `repack/zreg-boot/boot-zreg-308065ef.img` | `303ea791…ef3658` | 58,568,704 | `7.0.14-g308065ef80be` | Z 基线 + `regulator_ignore_unused`（DTB bootargs） | Z + 保稳压器：屏幕**保持高亮灰**、不再转黑；ABL 流仍在 ~1.4 s 断 |
| `repack/zreg-dispcc-boot/boot-zdcc-308065ef.img` | `74ec9033…2a5bd4` | 58,568,704 | 同上 | Z + `regulator_ignore_unused` + `initcall_blacklist=…,disp_cc_sm8450_driver_init` | 死亡时间 1.44 s→2.5 s，仍是黑 ⇒ dispcc 只是让断电晚一点 |
| `repack/nomsm-boot/boot-nomsm-308065ef.img` | `b14d7fa2…01bfc5` | 58,568,704 | 同上 | Z：`initcall_blacklist=simplefb_driver_init,msm_drm_register` + `clk_ignore_unused pd_ignore_unused iomem=relaxed` | 无 DRM：日志滚到 1.44 s 后画面死；DSI 停在 ABL 残留态（`CTRL=0x1f7`） |

**黄金参照**：`repack/golden-617/{dsi0.txt,dsi1.txt}`——`boot-617-nodp` 点亮时
DSI0/1 的非零寄存器逐值，判读陷阱与关键值见该目录 `README.md`。

> **2026-10-30 磁盘清理**：下表中标"已删"的镜像目录已删除（结论保留在本表与
> `known-wrong-changes.md`；被删目录的 README 收在 `repack/archive-7.0-notes/`）。
> 仍保留在本机可 boot 的镜像只有：`617fix-boot/`（点亮，首选）、
> `617-boot/boot-617-nodp.img`（首张点亮）、`base-308065ef/`、`nodsc-boot/`。

### 源码状态（2026-10-29 夜）

| 分支 | HEAD | 状态 | 说明 |
|---|---|---|---|
| `liuqin-6.17-tianma` | `0c71219b301b` | **已推送** | 板级 DTS `&mdss_dp0 { status = "disabled" }`；CI 产物从此可直接点亮 |
| `liuqin-7.0` | `b96111112b78` | **本地，未推送** | `pipa_tm_desc` 改回 `pipa_mode_120` + `VIDEO_BURST`（唯一没测过的组合） |
| `liuqin-6.17` | `c64b7fc85a8b` | 上游作者分支，未改动 | 只 fetch，不 push |

### 复现某个现象时选哪张

| 想看的 | 用哪张 |
|---|---|
| 天马面板正常显示（寄存器黄金参照、DPU/DSC 工作态） | **`repack/617fix-boot/boot-liuqin-firstboot.img`**（正式版，首选）；`boot-617-nodp.img` 是首张点亮的历史参照 |
| 7.0 的黑屏基线 | `boot-base-308065ef.img` |
| 7.0 的 120 Hz + burst 组合是否点亮 | `boot-702-fps120.img`（`boot-fps120.img` 会重启，别用） |
| ABL 显示的死亡时刻与稳压器关系 | `boot-zreg-…` / `boot-nomsm-…` |

### 2026-10-29 夜补充：`c4ba514b` 这个内核上机直接重启

- `repack/7fps-boot/boot-liuqin-firstboot.img`（`c4ba514b` artifact，命令行与源码一致）
  上机后**直接重启**，进不到 shell；镜像本身拆包校验通过（kernel/dtb/ramdisk 逐字节正确，
  DTB 可正常反编译），所以是**内核问题，不是打包问题**。
- 同一组合换到 `702b079d` 内核（`repack/702fps-boot/boot-702-fps120.img`）可以正常启动。
  ⇒ **`c4ba514b` 是一个不能用的提交**（`liuqin-7.0` 当前 HEAD 的父提交），
  在它之上做的任何验证都不可信；`b96111112b78`（120 Hz + burst）也因此没有可靠的
  构建基础，需要先定位 c4ba514b 的启动崩溃。
- 待查：`c4ba514b` 相对 `702b079d` 的差异（`68c7cfa` 换回 nt36532、`cec2a7b5`
  DSI 广播、`c4ba514b` 60 Hz desc）；怀疑点在面板驱动 `prepare()` 或 DSI 初始化。

### 结论（2026-10-29 夜）：120 Hz + burst 也黑 ⇒ 7.0 显示线暂停

- `repack/702fps-boot/boot-702-fps120.img`（`702b079d` + `force_fps=120`，
  sha256 `7c1b3642…c66b91`）**能正常启动**，屏幕仍黑。
- 至此 7.0 上三种组合全黑：120 Hz 非 burst（`base-308065ef`）、60 Hz burst
  （`702b079d` / `704`/`c4ba514b`）、**120 Hz burst（本轮）**；
  而 6.17 用 120 Hz burst 能亮，且 DSI/DSC/INTF 寄存器逐值无差别
  ⇒ 差异在寄存器之外（初始化顺序、时序或 DPU 之外的路径），继续盲试性价比为零。
- **决定：7.0 显示线暂停，6.17 作为显示方案继续推进。**
- 附带：`liuqin-7.0` HEAD 的父提交 `c4ba514b` 上机直接重启（坏提交），
  在该提交之上构建的任何产物都不要上机；`b96111112b78`（120 Hz burst）虽然 CI 通过，
  但建立在坏提交之上、且组合已被证明无效，**不要采用**。

### 下一步与决策记录（2026-10-30 更新）

**CI 状态**（`gh run list --repo amil233/linux-sm8450-liuqin`，均 completed/success）：

| 分支 | commit | run | 用途 | 可用性 |
|---|---|---|---|---|
| `liuqin-6.17-tianma` | `c7e51cdf3290` | — | DP disabled 真正生效（修复 `0c71219b` 的空操作） | ✅ **artifact 已进 `ci/` 并上机点亮**（`repack/617fix-boot/`） |
| `liuqin-6.17-tianma` | `0c71219b301b` | 40872397662 | DP disabled 写成了第二个 `&mdss_dp0` 块，被原 `status="okay"` 覆盖 | ⚠️ **空操作提交**，产物 DTB 里 DP 仍是 `okay`，不能点亮（见 W8） |
| `liuqin-7.0` | `b96111112b78` | 40873566741 | 120 Hz + burst | ❌ **不要上机**：建立在坏提交 `c4ba514b` 之上，且组合已被证明无效 |

**待办（按顺序）**：

1. ✅ **已完成（2026-10-30）**：`c7e51cdf3290` 的 artifact 进 `ci/`，装配出
   **不需要手工 `fdtput`** 的 `repack/617fix-boot/boot-liuqin-firstboot.img`
   （`c76820fe…1e1923`），`fastboot boot` **上机确认点亮**;
   装配参数权威记录在 `docs/display-617-tianma-lit.md`，复现命令已逐位验证；
2. 把 `b96111112b78` revert 掉，保持 `liuqin-7.0` 历史干净（组合无效 + 底座是坏提交）；
3. 6.17 接进集成仓的镜像构建（Ubuntu 26.04 用户态 + 6.17 内核）；
4. 7.0 显示线**暂停**。以后若重启，需要的不是更多参数试错，而是能对照的**时序级证据**
   （初始化顺序 / 命令与视频流的先后），因为寄存器层面已经无法区分。

**上机前必查**（血泪教训，写在这里免得再犯）：

- `c4ba514b` 是坏提交，凡以它为底的产物一律不上机；
- `fastboot boot` 优先，只有回读不到命令行参数时才写 boot 分区；
- 判"黑"必须同时知道面板供电是否被 `regulator_late_cleanup` 收走（见 §8 第二十六轮）；
- `0x0a4` 不是 `LANE_STATUS` 的可靠读数（能亮时也读 0），别再用它判链路；
- `signal=0x80`、`display=0x00` **能亮时也出现**，不能当"面板没收到码流"的判据；
- 两边都**没有 fbdev**（`/proc/fb` 为空、无 `/dev/fb0`），往 `/dev/tty0` 写东西
  **不会显示**，别用它判断渲染是否正常。

### 2026-10-29 深夜更正：`0c71219b` 的 CI 产物**不能**点亮

- `ci/liuqin-kernel-0c71219b301b…/` 已核对（`sha256sum -c` 全过、commit 一致、
  `kernel.release=6.17.0-rc1-g0c71219b301b`），但 **DTB 里
  `displayport-controller@ae90000` 的 `status` 仍是 `okay`**：

  ```
  $ fdtget -t s .../sm8475-xiaomi-liuqin.dtb \
      /soc@0/display-subsystem@ae00000/displayport-controller@ae90000 status
  okay
  ```

- 原因：板级 DTS 里本来就有 `&mdss_dp0 { status = "okay"; }`（"DisplayPort out
  over USB-C"那段注释下），我在文件靠前的位置新增了第二个 `&mdss_dp0` 块，
  **DT 里后面的节点覆盖前面的** ⇒ 提交是空操作。详见
  `known-wrong-changes.md` W8。
- 修复提交：`c7e51cdf3290`（把 `status = "disabled"` 挪进真正生效的那个节点，
  并删掉重复块）。**需要推 `liuqin-6.17-tianma` 重新跑 CI**，产物才可用。
- 在此之前，**能点亮的仍然是 `repack/617-boot/boot-617-nodp.img`**
  （`3b694685881d` + 运行期 `fdtput` 关 DP），它和这一版内核的差别只有 DP 节点。

### 2026-10-29 深夜：DSI PHY 也逐值相同

在**同为 120 Hz** 的两个内核上各 dump 一次 DSI0 PHY（`0xae94400`–`0xae947fc`）：

- 7.0（`702b079d`+`force_fps=120`，黑屏）：`repack/golden-617/phy0-70.txt`
- 6.17（`boot-617-nodp`，能亮）：**与上面逐值完全相同**（含 `0x10 CLK_CFG0=0x61`、
  `0x14 CLK_CFG1=0x30`、`0x20 VREG_CTRL_0=0x53`）

⇒ 到这一刻，**DSI 控制器、DSI PHY、DSC 编码器、INTF 四层的运行时寄存器在能亮与不能亮
之间没有任何差异**。所以"7.0 为什么不亮"不可能由某个寄存器值解释，只剩两种可能：

1. **面板收到的命令/时序不同**（init 216 包、PPS 字节、`0x9b`、display_on 的**先后与时机**）；
2. **DPU 实际送出的内容不同**（7.0 可能老老实实在送黑帧，而"面板没锁上"的判断本身
   可能来自误读的 `0x9e/0x80`）。

下一步要抓的是**命令流本身**（`dmesg` 里的 `DSC:`/PPS 字节与时间戳），不是寄存器。

附：原厂 50 Hz 的 PHY 快照与这一组有 3 处不同（`0x10/0x14/0x20`），但那是**码率不同**
导致的正常差异，不能当判据。

### 2026-10-29 深夜（关键）：`signal=0x80` 是正常值，旧判据作废

在**能亮的 6.17** 上挂 debugfs 后读面板状态（`/sys/kernel/debug/nt36532/dcs`）：

| 字段 | 6.17（能亮） | 7.0（黑屏） |
|---|---|---|
| `power` | **`0x9c`** | `0x9e` |
| `display` | `0x00` | `0x00` |
| `signal` | **`0x80`** | `0x80` |
| `status` | `0x00` | `0x00` |
| `pixfmt` | `0x07` | `0x07` |

⇒ **`signal=0x80`、`display=0x00` 在正常显示时同样出现**，从第二十轮起
"`signal=0x80` ⇒ 面板没收到有效视频流"的判据**作废**（`known-wrong-changes.md`
应把它算进 R 系列）。`power` 的 `0x9c/0x9e` 只差 bit1，而原厂 DT 写的是 `0x9d`，
三个值互不相同 ⇒ 这个字节也不能单独当判据。

**DPU 取数也一致**（`sspp_0`，`0xae05000`）：

| 寄存器 | 6.17 | 7.0 |
|---|---|---|
| `SRC_SIZE` | `0x0B400384`（900×2880） | 同 |
| `SRC0_ADDR` | `0x00003000`（IOVA） | 同 |
| `SRC_FORMAT` | `0x000237FF` | 同 |
| `SRC_OP_MODE` | `0x80000000`（PE_OVERRIDE，**非纯色填充**） | 同 |
| `CONSTANT_COLOR` | 0 | 0 |

⇒ 两边都在"从同一类缓冲取同样的 900×2880 数据"。
剩下唯一没比的合成环节：**LM(layer mixer) / CTL(blend stage) / PP(pingpong)**。

---

## 12. "为什么 6.17 能亮而 7.0 不能"——目前能确定到什么程度（2026-10-29 夜）

### 已排除（逐项有实测）

| 层 | 证据 |
|---|---|
| 面板 / DDIC / 背光 / 供电 | 6.17 用同一块面板正常显示；VSP/VSN/DVDD 全程正常 |
| 面板 init 序列 | 两版驱动的 `m81_36_02_0a_init_sequence` **逐行相同**（唯一差异是 7.0 里一个默认关闭的 `pps_in_init` 诊断块） |
| 设备树 | display 子树结构相同（只差 phandle 编号） |
| DSI 控制器 | `CTRL/VID_CFG0/TOTAL/ACTIVE_*/DSC_CTRL/CLK_STATUS` 逐值相同 |
| DSI PHY | `0xae94400`–`0xae947fc` 全窗口逐值相同（含 `CLK_CFG0/CLK_CFG1/VREG_CTRL_0`） |
| DSC 编码器 | `0xae81100`–`0xae81198` 逐值相同（PPS 镜像区完全一致） |
| INTF | `0xae36000`–`0xae363fc` 逐值相同（含 `CONFIG/UNDERFLOW/活动宽度`） |
| SSPP（取数） | `SRC_SIZE/SRC0_ADDR/SRC_FORMAT/SRC_OP_MODE/CONSTANT_COLOR` 相同，**不是纯色填充** |
| LM / CTL / PP | 三块全窗口逐值相同（含 `LM_OP_MODE`、const alpha、blend stage） |
| 控制台路径 | 两边都**没有 fbdev**（`/proc/fb` 空、无 `/dev/fb0`），控制台都走 `drm_log`；7.0 的 `console [drm_log0] enabled` 在 3.715 s 出现，客户端是活的 |
| DPU 出帧 | 7.0 的 `INTF_FRAME_COUNT` 在涨，`vid_enable: intf1/intf2 ENABLING` 正常 |

### 唯一剩下的可观测差异

面板 `0x0a` 的 **bit1**：能亮的 6.17 是 `0x9c`，黑屏的 7.0 是 `0x9e`。
在 6.17 上静置 60 s 后仍是 `0x9c` ⇒ **不是"画面静止"自动触发的**，是真实状态差。

同时确认：`signal=0x80`、`display=0x00` 在**能亮时也一样**，这两个字节不能当判据
（旧判据作废）。

### 结论

**SoC 侧所有可读配置在"能亮"与"不能亮"之间没有任何差异**。因此差异只能落在
我们看不见的那一层：

1. **码流的时序/顺序**（例如 PPS、`0x9b`、display_on 与视频流启动的相对时刻）；
2. **码流内容本身**（DSC 比特流是否被这块 DDIC 的解码器接受）；
3. 面板对上述二者的反应（idle 位）。

### 要定案需要的手段（按性价比）

1. **文件级 bisect**：把 6.17 的 msm 显示文件逐个搬进 7.0（`dsi_host.c`、
   `dsi_phy_7nm.c`、`dpu_encoder_phys_vid.c`、`dpu_plane.c`、`dpu_hw_dsc*.c`…），
   每步一次 CI。可行性最高，因为两边版本接近、接口差异小。
2. **逻辑分析仪抓一条 DSI lane**：直接看码流是否合法（对照 §0.8 的方法）。
3. **内核侧打时间戳**：在关键写入点（PPS/0x9b/display_on/视频使能）加打印，
   比较两版的先后与间隔。

在这三条里，第 1 条最有可能给出"是哪一行代码"的答案；第 2 条能给出"码流到底对不对"。

### 文件级 bisect 批次 T1–T6（2026-10-29 夜，已建分支待推）

做法：每个分支 = **`702b079d`（最年轻的、确认能启动的 7.0 提交）** + 一个
"把 6.17 的某个显示文件原样搬过来"的提交 + 一处 workflow 触发改动
（`branches: [liuqin-7.0, "liuqin-7.0-t*"]`），一次推送即可并行起 6 个构建。

| 分支 | HEAD | 搬过来的 6.17 文件 | 想验证什么 |
|---|---|---|---|
| `liuqin-7.0-t1` | `cdbf982a5aeb` | `dsi/dsi_host.c` | DSI 命令/视频使能的时序与状态机 |
| `liuqin-7.0-t2` | `1bf2e84e6c99` | `dsi/phy/dsi_phy_7nm.c` | PHY/PLL（含 V7.0→V7.2 quirk、PLL bias 引用计数） |
| `liuqin-7.0-t3` | `3a933aae0551` | `disp/dpu1/dpu_plane.c` | 平面取数/格式路径 |
| `liuqin-7.0-t4` | `b481ef02cc3c` | `dpu_encoder_phys_vid.c`、`dpu_hw_intf.c`、`dpu_hw_dsc_1_2.c`、`dpu_crtc.c` | DPU 输出路径（也顺带去掉我们加在这些文件里的诊断补丁） |
| `liuqin-7.0-t5` | `cc2b9e6ad3c8` | `dsi_host.c` + `dsi_phy_7nm.c` | 整条 DSI 栈 |
| `liuqin-7.0-t6` | `127001a043e7` | 上面全部 7 个文件 | 整套显示栈 |

判读：哪个分支的产物**点亮**，差异就在它搬的那个文件里，然后在那个文件里继续二分。
全部仍然黑 ⇒ 说明差异不在这些文件，需要换思路（例如面板驱动之外的上层调用顺序）。

**顺带查到的一条线索**：`c4ba514b`（`702b079d` 的父提交）上机直接重启，而
`702b079d` 只做了一件事——revert 掉 `dpu_encoder_phys_vid.c` 里**一行**
"INTF programmable fetch (BIT31)"。也就是说 **那一行 BIT31 会让内核起不来**，
而它正是当初为对齐原厂 `INTF CONFIG=0x80800000` 加的。这条要么是我们的写法有问题，
要么该位在 DPU 8.0 上不能这么用——无论哪种，都别再直接照抄原厂那一位。

#### T1–T6 判读计划（一次推送并行 6 个构建）

统一做法：每个分支的 artifact 都装成**同一套** boot 镜像（同一 ramdisk、同一 DTB
流程、命令行统一加 `panel_novatek_nt36532.force_fps=120`），这样和已知黑屏的
`boot-702-fps120.img` 构成单变量对照。判据只有一个：**屏幕亮不亮**（辅以
`dmesg | grep -iE 'dsc:|panel desc|msm'` 确认 DRM 确实起来了）。

判读顺序（按信息量，命中即停）：

| 轮次 | boot 哪张 | 结果 → 下一步 |
|---|---|---|
| R1 | `t6`（7 个文件全搬） | **亮** → 进 R2；**黑** → 进 R3 |
| R2 | `t5`（DSI 两个文件）与 `t4`（DPU 四个文件） | 哪个亮，差异就在那一半；两只都亮 ⇒ 两半各自都能修，挑改动小的那半继续 |
| R3 | `t1`、`t2`、`t3`（单文件） | 哪只亮就锁定哪个文件；全黑 ⇒ 差异不在这些文件 |
| R4 | 锁定文件后：在该文件内部按函数二分（我按 `git diff` 的 hunk 生成子分支） | 直到缩到具体函数/语句 |

失败处理：

- **编译失败**的分支记下来（6.17→7.0 有 API 差异），改用"只搬函数"的方式重做该分支；
- 全部黑：把方向转到"上层调用顺序"（`drm_atomic` 提交顺序、`drm_panel` 的
  prepare/enable 与 encoder 使能的相对时刻），那需要的是时间戳打印，而不是再搬文件。

#### T1–T6 首轮结果：4 个编译失败（都是 API 漂移）

| 分支 | 结果 | 失败原因（CI 原文） |
|---|---|---|
| `t1`（dsi_host.c） | 仍在跑 | — |
| `t2`（dsi_phy_7nm.c） | ❌ | `undefined reference to 'dsi_phy_3nm_kaanapali_cfgs'`（7.0 的 `dsi_phy.c` 引用该符号，定义在被替换掉的 7.0 `dsi_phy_7nm.c` 里） |
| `t3`（dpu_plane.c） | ❌ | `implicit declaration of function 'dpu_crtc_get_num_lm'`（7.0 已移除该函数） |
| `t4`（DPU 四文件） | 仍在跑 | 大概率同样因 `CRTC_QUAD_MIXERS` 失败 |
| `t5`（DSI 两文件） | ❌ | 同 `t2` |
| `t6`（七文件） | ❌ | `'CRTC_QUAD_MIXERS' undeclared` + 静态断言 |

**结论**：整文件搬运跨一个内核版本不可行（枚举/函数被改名或删除）。整文件搬运本身
也不再是合适的工具——因为这些文件**产出的寄存器在两边已经逐值相同**
（§12 上面的证据），换代码最多只改变"写入的时刻"。

⇒ 计划改为**比时间线**：用两版 dmesg 的时间戳对齐
`面板 prepare → PPS → display_on → 视频使能 → 首帧` 的先后与间隔，
这正好是寄存器抓不到的那一层。若时间线仍无差异，再做"只搬函数"的定向移植。

### 触摸（TDDI）与显示共享芯片——2026-10-29 深夜

两版都启用 `CONFIG_TOUCHSCREEN_NT36523_SPI=y`，板级 DTS 里也都有触摸节点和
`novatek,swrst-n8-addr = <0x1fb43e>`。6.17 的启动日志显示触摸驱动在
`panel_prepared`（3.640 s）之后立刻重新下载固件（3.641–3.850 s，208 ms），
**而显示正常**——所以"触摸下载固件必然把 TDDI 打回 idle"这个推论不成立。

但 7.0 的下载过程完整日志还没采到，且它的请求时机（4.260 s）正好压在
`vid_enable` 上，所以用一个单变量实验直接排除：

| 项 | 值 |
|---|---|
| 镜像 | `repack/702fps-boot/boot-702-notouch.img` |
| 改动 | 在 `702fps-boot` 的命令行里加 `initcall_blacklist=…,nvt_spi_driver_init` |
| sha256 | `203e59925724fc1a862f1c8745402701cce4d0781a44095d6ab1c68c6ad7e2b9` |

判读：**亮** ⇒ 触摸固件下载就是凶手（与显示驱动无关，修法在触摸侧）；
**仍黑** ⇒ 触摸排除，回到"码流内容/时序"这条，需要逻辑分析仪或写回抓帧。

---

## 13. 前向移植（forward-port）：从 6.17 逐步升到 7.0

思路：**保持 liuqin 设备补丁不变，让上游代码前进**，用"内核版本"当单变量来二分
7.0 黑屏的根因。这比文件级 transplant 更干净，也不会被 API 漂移卡住。

仓库里可用的上游 tag：`v6.17`、`v6.19-rc6`、`v7.0`；`liuqin-6.17` 与三者的共同祖先
是 `90d970cade8e`，其上叠了 114 个 liuqin 提交。

### S1：merge v6.19-rc6（已完成，待推）

| 项 | 值 |
|---|---|
| 分支 | `liuqin-6.19` |
| merge commit | `692ff1ccce88` |
| CI 触发提交 | `445e465f8495`（workflow 的 branches 加入 `liuqin-6.19`） |
| 冲突 | 20 个文件 / 36 块 |

冲突处理原则（记录在 merge commit 里）：

| 文件 | 处理 |
|---|---|
| `tee/Kconfig`、`tee/Makefile`、`Documentation/tee/index.rst` | 两边都保留（liuqin qseecom + upstream qcomtee） |
| `include/uapi/linux/tee.h` | `TEE_IMPL_ID_QTEE=4` 与 `TEE_IMPL_ID_QSEECOM=5` 并存 |
| `qcom_scm.c` | 保留 liuqin 的 qseecom init |
| `ubwc_config.c` | upstream 表 + liuqin 的 `cape` 条目 |
| `audioreach.h`、`codecs/Makefile`、`snd_ar_tokens.h` | 两边都保留 |
| `sc8280xp.c` | 整份取 upstream（liuqin 不用这张卡） |
| `camss-csiphy`、`iris_platform_*` | 两边都保留 |
| `iris_hfi_gen2_command.c` | 取 upstream（drain 重构） |
| `qcom_battmgr.c` | 保留 liuqin 增补 |
| `dpu_encoder.c`（`MAX_CHANNELS_PER_ENC=4`）、`dpu_hw_mdss.h`（`STAGES_PER_PLANE=2`）、`dpu_plane.c` | **保留 liuqin 侧**（这是设备显示逻辑，不能丢）；`dpu_crtc.c` 里 `dpu_crtc_get_num_lm()` 的定义在自动合并中幸存，`dpu_plane` 依赖它 |

推送：`git -C linux-sm8450-liuqin push GitHub liuqin-6.19`

**判读**：编译通过后装镜像上机——**亮** ⇒ 6.17→6.19 无回归，继续 S2（merge `v7.0`）；
**黑** ⇒ 回归落在 6.17→6.19 之间，在 `v6.19-rc6` 之前的位置继续二分。

已知风险：iris/camss 的自定义平台数据可能与 6.19 的 `struct iris_platform_data`
字段变化冲突，首次 CI 可能失败，按报错修即可。
