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

**当前计数（2026-10-28 第二十轮后，停止线已触发）**：138 条 —— ⛔ 114 / ⚠️ 11 / ⬜ 5 / 📌 7 / ❌ 1。

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
| 13 | **停止线** | 见 §0.7 | ⏸ 已触发：等待原厂健康读数或抓线 | — |

### 现状与结论（停止线已触发，2026-10-28）

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
画面全黑但背光亮。

**只剩两条，且都需要外部手段**：
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
| H02 | `pic_width` 写成 1800（每链路只送 2×450） | 解码端算出 4 slice/行 | **已 A/B，无差别**：`pps_per_link_pic_width=1`（PPS 用 900）画面与默认完全相同；且原厂 `dsi_display_set_mode` 自己打的就是 `hactive=1800`。判为**非问题** | ⛔（A/B 无差别） |
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

### 2026-10-28 第二十一轮：Z（无 DRM）也灰→黑 —— 交接本身就结束了画面

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
